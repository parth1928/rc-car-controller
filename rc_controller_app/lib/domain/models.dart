class ControlPacket {
  final int seq;
  final int throttle;
  final int steering;
  final String mode;
  final int maxThrottle;
  final int deadzone;

  ControlPacket({
    required this.seq,
    required this.throttle,
    required this.steering,
    required this.mode,
    required this.maxThrottle,
    required this.deadzone,
  });

  int _modeToId(String value) {
    switch (value) {
      case 'sport':
        return 1;
      case 'drift':
        return 2;
      case 'crawl':
        return 3;
      default:
        return 0;
    }
  }

  String toUdpPayload() {
    final int modeId = _modeToId(mode);
    return 'C,$seq,$throttle,$steering,$modeId,$maxThrottle,$deadzone';
  }

  Map<String, dynamic> toJson() => {
    'type': 'control',
    'seq': seq,
    'throttle': throttle,
    'steering': steering,
    'mode': mode,
    'maxThrottle': maxThrottle,
    'deadzone': deadzone,
  };
}

class StatusPacket {
  final int throttle;
  final int steering;
  final String mode;
  final int rssi;

  StatusPacket({
    required this.throttle,
    required this.steering,
    required this.mode,
    required this.rssi,
  });

  factory StatusPacket.fromJson(Map<String, dynamic> json) {
    return StatusPacket(
      throttle: json['throttle'] ?? 0,
      steering: json['steering'] ?? 0,
      mode: json['mode'] ?? 'normal',
      rssi: json['rssi'] ?? 0,
    );
  }
}
