import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/models.dart';

class UdpControlService {
  UdpControlService({
    this.controlPort = 4210,
    this.discoveryMessage = 'D',
  });

  final int controlPort;
  final String discoveryMessage;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  InternetAddress? _carAddress;
  int _carPort = 4210;

  bool _disposed = false;
  bool _lastPublishedConnection = false;

  DateTime? _lastPingSent;
  DateTime? _lastPongAt;
  int _currentPing = 0;
  int get currentPing => _currentPing;

  final _pingController = StreamController<int>.broadcast();
  Stream<int> get pingStream => _pingController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  Timer? _pingTimer;
  Timer? _discoveryTimer;
  Timer? _connectionWatchdogTimer;

  bool get isConnected {
    if (_socket == null || _carAddress == null || _lastPongAt == null) {
      return false;
    }

    final ageMs = DateTime.now().difference(_lastPongAt!).inMilliseconds;
    return ageMs < 3000;
  }

  void connect() {
    if (_disposed) return;

    _initSocketIfNeeded();
    _startTimers();
    _sendDiscovery();
    _publishConnectionState();
  }

  Future<InternetAddress?> _resolveBestLocalBindAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('192.168.43.') ||
              addr.address.startsWith('192.168.137.') ||
              addr.address.startsWith('172.20.10.')) {
            return addr;
          }
        }
      }

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            return addr;
          }
        }
      }
    } catch (_) {
      // Ignore and fall back to wildcard bind.
    }

    return null;
  }

  void _initSocketIfNeeded() {
    if (_socket != null || _disposed) return;

    unawaited(_initSocket());
  }

  Future<void> _initSocket() async {
    if (_socket != null || _disposed) return;

    try {
      final localBind = await _resolveBestLocalBindAddress();

      RawDatagramSocket socket;
      try {
        socket = await RawDatagramSocket.bind(
          localBind ?? InternetAddress.anyIPv4,
          controlPort,
        );
      } catch (_) {
        socket = await RawDatagramSocket.bind(
          localBind ?? InternetAddress.anyIPv4,
          0,
        );
      }

      socket.readEventsEnabled = true;
      socket.writeEventsEnabled = false;
      socket.broadcastEnabled = true;

      _socket = socket;
      _socketSubscription = socket.listen(
        _onSocketEvent,
        onDone: _resetSocket,
        onError: (_) => _resetSocket(),
      );

      _publishConnectionState();
    } catch (_) {
      _resetSocket();
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _socket == null) return;

    Datagram? datagram = _socket!.receive();
    while (datagram != null) {
      _handleDatagram(datagram);
      datagram = _socket!.receive();
    }
  }

  void _handleDatagram(Datagram datagram) {
    final String message;
    try {
      message = utf8.decode(datagram.data).trim();
    } catch (_) {
      return;
    }

    if (message.isEmpty) return;

    if (message.startsWith('H')) {
      _carAddress = datagram.address;
      _carPort = datagram.port;
      _lastPongAt = DateTime.now();
      _publishConnectionState();
      sendPing();
      return;
    }

    if (message.startsWith('P')) {
      _carAddress = datagram.address;
      _carPort = datagram.port;
      _lastPongAt = DateTime.now();

      if (_lastPingSent != null) {
        _currentPing = DateTime.now()
            .difference(_lastPingSent!)
            .inMilliseconds;
        _pingController.add(_currentPing);
      }

      _lastPingSent = null;
      _publishConnectionState();
      return;
    }

    if (message.startsWith('S,')) {
      _carAddress = datagram.address;
      _carPort = datagram.port;
      _lastPongAt = DateTime.now();
      _publishConnectionState();
    }
  }

  void _startTimers() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      sendPing();
    });

    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      final bool stale = _lastPongAt == null ||
          DateTime.now().difference(_lastPongAt!).inMilliseconds >= 3000;

      if (_carAddress == null || stale) {
        _sendDiscovery();
      }
    });

    _connectionWatchdogTimer?.cancel();
    _connectionWatchdogTimer =
        Timer.periodic(const Duration(milliseconds: 300), (_) {
      _publishConnectionState();
    });
  }

  void _publishConnectionState() {
    final bool current = isConnected;
    if (current != _lastPublishedConnection) {
      _lastPublishedConnection = current;
      _connectionController.add(current);
    }
  }

  void _sendDiscovery() {
    _initSocketIfNeeded();
    if (_socket == null) return;

    final payload = ascii.encode(discoveryMessage);
    final targets = <InternetAddress>[
      InternetAddress('255.255.255.255'),
      InternetAddress('192.168.43.255'),
      InternetAddress('192.168.137.255'),
      InternetAddress('192.168.4.255'),
    ];

    for (final target in targets) {
      try {
        _socket!.send(payload, target, controlPort);
      } catch (_) {
        // Ignore individual send failures; other interfaces may still work.
      }
    }
  }

  bool _sendPayload(String payload) {
    _initSocketIfNeeded();

    if (_socket == null || _carAddress == null) {
      return false;
    }

    try {
      final sent = _socket!.send(ascii.encode(payload), _carAddress!, _carPort);
      return sent > 0;
    } catch (_) {
      _resetSocket();
      return false;
    }
  }

  bool sendPacket(ControlPacket packet) {
    final bool ok = _sendPayload(packet.toUdpPayload());
    if (!ok) {
      _sendDiscovery();
    }
    return ok;
  }

  bool sendEStop() {
    final bool ok = _sendPayload('E');
    if (!ok) {
      _sendDiscovery();
    }
    return ok;
  }

  bool sendPing() {
    if (_lastPingSent != null) {
      final pendingMs = DateTime.now().difference(_lastPingSent!).inMilliseconds;
      if (pendingMs < 1500) {
        return false;
      }
      _lastPingSent = null;
    }

    _lastPingSent = DateTime.now();
    final bool ok = _sendPayload('P');
    if (!ok) {
      _lastPingSent = null;
      _sendDiscovery();
    }
    return ok;
  }

  void _resetSocket() {
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _socket?.close();
    _socket = null;
    _publishConnectionState();

    if (!_disposed) {
      _initSocketIfNeeded();
    }
  }

  void dispose() {
    _disposed = true;

    _pingTimer?.cancel();
    _discoveryTimer?.cancel();
    _connectionWatchdogTimer?.cancel();

    _socketSubscription?.cancel();
    _socket?.close();

    _pingController.close();
    _connectionController.close();
  }
}