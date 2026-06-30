import 'dart:async';
import 'dart:math' as math;
import '../../services/udp_service.dart';
import '../../domain/models.dart';

class RaceLinkStats {
  final double sendHz;
  final int targetIntervalMs;
  final int txOk;
  final int txFail;

  const RaceLinkStats({
    required this.sendHz,
    required this.targetIntervalMs,
    required this.txOk,
    required this.txFail,
  });
}

class DriveController {
  final UdpControlService _udpService;

  // State
  int _targetThrottle = 0;
  int _targetSteering = 0;
  String _mode = 'normal';
  int _maxThrottle = 95;
  int _deadzone = 3;
  int _steeringSensitivity = 80;

  bool _isCruiseControl = false;
  bool _isSpinning = false;
  int _sequence = 0;

  Timer? _loopTimer;
  final int _tickMs = 10;
  final int _idleKeepAliveMs = 65;

  int? _lastSentThrottle;
  int? _lastSentSteering;
  String? _lastSentMode;
  int? _lastSentMaxThrottle;
  int? _lastSentDeadzone;
  DateTime? _lastSentAt;
  int _lastTargetIntervalMs = 65;

  int _txOk = 0;
  int _txFail = 0;
  int _windowPacketCount = 0;
  DateTime _windowStart = DateTime.now();
  DateTime _lastStatsPublishedAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _sendHz = 0;

  final StreamController<RaceLinkStats> _statsController =
      StreamController<RaceLinkStats>.broadcast();
  Stream<RaceLinkStats> get statsStream => _statsController.stream;

  DriveController(this._udpService);

  void start() {
    _loopTimer = Timer.periodic(Duration(milliseconds: _tickMs), (_) {
      _sendControlUpdate();
    });
  }

  void stop() {
    _loopTimer?.cancel();
  }

  void dispose() {
    stop();
    _statsController.close();
  }

  int _effectiveSteeringPercent() {
    final int effective = 20 + ((_steeringSensitivity * 4) ~/ 5);
    return effective.clamp(20, 100);
  }

  int _adaptiveSendIntervalMs(
    int throttle,
    int steering,
    bool stateChanged,
  ) {
    final int inputMag = math.max(throttle.abs(), steering.abs());

    if (_isSpinning) return 14;
    if (stateChanged && inputMag >= 60) return 16;
    if (inputMag >= 60) return 18;
    if (inputMag >= 35) return 24;
    if (inputMag >= 12) return 30;
    return 44;
  }

  void _recordTx(bool ok, DateTime now) {
    if (ok) {
      _txOk++;
    } else {
      _txFail++;
    }

    _windowPacketCount++;

    final int windowMs = now.difference(_windowStart).inMilliseconds;
    if (windowMs >= 1000) {
      _sendHz = (_windowPacketCount * 1000.0) / windowMs;
      _windowPacketCount = 0;
      _windowStart = now;
    }

    if (now.difference(_lastStatsPublishedAt).inMilliseconds >= 250) {
      _lastStatsPublishedAt = now;
      _statsController.add(
        RaceLinkStats(
          sendHz: _sendHz,
          targetIntervalMs: _lastTargetIntervalMs,
          txOk: _txOk,
          txFail: _txFail,
        ),
      );
    }
  }

  // Update inputs
  void setJoystick(double x, double y) {
    if (_isSpinning) return;

    final int steeringPercent = _effectiveSteeringPercent();
    final double clampedX = x.clamp(-1.0, 1.0);
    _targetSteering = (clampedX * steeringPercent).round();

    if (!_isCruiseControl) {
      _targetThrottle = (y * -100).round(); // Invert Y, linear response
    }
  }

  void setMode(String newMode) {
    _mode = newMode;
  }

  void setMaxThrottle(int value) {
    _maxThrottle = value.clamp(10, 100);
  }

  void setDeadzone(int value) {
    _deadzone = value.clamp(0, 20);
  }

  void setSteeringSensitivity(int value) {
    _steeringSensitivity = value.clamp(20, 100);
  }

  void setExpo(double value) {
    // Intentionally no-op. Expo is disabled for direct, linear control feel.
  }

  void enableCruiseControl() {
    _isCruiseControl = true;
  }

  void disableCruiseControl() {
    _isCruiseControl = false;
    _targetThrottle = 0;
  }

  void startSpin(int direction) {
    _isSpinning = true;
    _targetThrottle = 0;
    _targetSteering = direction > 0 ? 100 : -100;
  }

  void stopSpin() {
    _isSpinning = false;
    _targetThrottle = 0;
    _targetSteering = 0;
  }

  void eStop() {
    _isCruiseControl = false;
    _isSpinning = false;
    _targetThrottle = 0;
    _targetSteering = 0;
    _recordTx(_udpService.sendEStop(), DateTime.now());
  }

  void _sendControlUpdate() {
    int finalThrottle = _targetThrottle;
    int finalSteering = _targetSteering;

    final int clampedThrottle = finalThrottle.clamp(-100, 100);
    final int clampedSteering = finalSteering.clamp(-100, 100);
    final int clampedMaxThrottle = _maxThrottle.clamp(10, 100);
    final int clampedDeadzone = _deadzone.clamp(0, 20);

    final bool stateChanged =
        _lastSentThrottle != clampedThrottle ||
        _lastSentSteering != clampedSteering ||
        _lastSentMode != _mode ||
        _lastSentMaxThrottle != clampedMaxThrottle ||
        _lastSentDeadzone != clampedDeadzone;

    final DateTime now = DateTime.now();
    final int elapsedMs =
      _lastSentAt == null ? 1000000 : now.difference(_lastSentAt!).inMilliseconds;
    final int adaptiveIntervalMs = _adaptiveSendIntervalMs(
      clampedThrottle,
      clampedSteering,
      stateChanged,
    );
    final bool activeHold =
      math.max(clampedThrottle.abs(), clampedSteering.abs()) >= 12;
    final int holdIntervalMs = activeHold ? adaptiveIntervalMs : _idleKeepAliveMs;

    final bool shouldSend = stateChanged
      ? elapsedMs >= adaptiveIntervalMs
      : elapsedMs >= holdIntervalMs;

    if (!shouldSend) {
      return;
    }

    final packet = ControlPacket(
      seq: _sequence++,
      throttle: clampedThrottle,
      steering: clampedSteering,
      mode: _mode,
      maxThrottle: clampedMaxThrottle,
      deadzone: clampedDeadzone,
    );

    final bool ok = _udpService.sendPacket(packet);

    _lastSentThrottle = clampedThrottle;
    _lastSentSteering = clampedSteering;
    _lastSentMode = _mode;
    _lastSentMaxThrottle = clampedMaxThrottle;
    _lastSentDeadzone = clampedDeadzone;
    _lastSentAt = now;
    _lastTargetIntervalMs = stateChanged ? adaptiveIntervalMs : holdIntervalMs;

    _recordTx(ok, now);
  }
}
