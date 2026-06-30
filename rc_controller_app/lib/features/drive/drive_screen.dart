import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/udp_service.dart';
import 'drive_controller.dart';
import 'gamepad_joystick.dart';
import 'control_layouts.dart';
import '../../theme/app_theme.dart';

class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  late UdpControlService _udpService;
  late DriveController _driveController;

  String _currentMode = 'normal';
  int _maxThrottle = 95;
  int _deadzone = 3;
  int _steeringSens = 80;
  bool _cruiseEnabled = false;
  String _controlLayout = 'gamepad'; // 'joystick', 'dpad', 'gamepad'
  bool _isConnected = false;
  int _ping = 0;
  double _sendHz = 0;
  int _targetSendIntervalMs = 0;
  int _txOk = 0;
  int _txFail = 0;

  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<int>? _pingSubscription;
  StreamSubscription<RaceLinkStats>? _statsSubscription;

  double _currentThrottle = 0.0;
  double _currentSteering = 0.0;

  @override
  void initState() {
    super.initState();
    _udpService = UdpControlService();
    _driveController = DriveController(_udpService);

    _loadPreferences();

    _connectionSubscription = _udpService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() => _isConnected = connected);
      }
      if (connected) {
        Vibration.vibrate(duration: 50, amplitude: 128); // Haptic on connect
      }
    });

    _pingSubscription = _udpService.pingStream.listen((ping) {
      if (mounted) {
        setState(() => _ping = ping);
      }
    });

    _statsSubscription = _driveController.statsStream.listen((stats) {
      if (!mounted) return;
      setState(() {
        _sendHz = stats.sendHz;
        _targetSendIntervalMs = stats.targetIntervalMs;
        _txOk = stats.txOk;
        _txFail = stats.txFail;
      });
    });

    _udpService.connect();
    _driveController.start();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _maxThrottle = prefs.getInt('maxThrottle') ?? 95;
      _currentMode = prefs.getString('mode') ?? 'normal';
      _deadzone = prefs.getInt('deadzone') ?? 3;
      _steeringSens = prefs.getInt('steeringSens') ?? 80;
      _controlLayout = prefs.getString('controlLayout') ?? 'gamepad';
    });
    _driveController.setMaxThrottle(_maxThrottle);
    _driveController.setMode(_currentMode);
    _driveController.setDeadzone(_deadzone);
    _driveController.setSteeringSensitivity(_steeringSens);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('maxThrottle', _maxThrottle);
    await prefs.setString('mode', _currentMode);
    await prefs.setInt('deadzone', _deadzone);
    await prefs.setInt('steeringSens', _steeringSens);
    await prefs.setString('controlLayout', _controlLayout);
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _pingSubscription?.cancel();
    _statsSubscription?.cancel();
    _driveController.dispose();
    _udpService.dispose();
    super.dispose();
  }

  void _setMode(String mode) {
    if (_currentMode != mode) {
      Vibration.vibrate(duration: 30, amplitude: 64); // Haptic on mode change
      setState(() => _currentMode = mode);
      _driveController.setMode(mode);
      _saveSettings(); // Persist
    }
  }

  void _triggerEStop() {
    Vibration.vibrate(duration: 100, amplitude: 255); // Heavy haptic
    setState(() => _cruiseEnabled = false);
    _driveController.eStop();
  }

  void _updateDriveInputs() {
    _driveController.setJoystick(_currentSteering, _currentThrottle);
  }

  @override
  Widget build(BuildContext context) {
    final modeColor = AppTheme.getModeColor(_currentMode);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Status Bar
            _buildStatusBar(modeColor),

            Expanded(child: _buildControlLayout(modeColor)),

            // Bottom Action Row
            _buildBottomRow(modeColor),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(Color modeColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                _isConnected ? Icons.wifi : Icons.wifi_off,
                color: _isConnected ? modeColor : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                '$_ping ms  ${_sendHz.toStringAsFixed(0)}Hz  ${_targetSendIntervalMs}ms  tx:${_txOk}/${_txFail}',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: modeColor.withValues(alpha: 0.5)),
            ),
            child: Text(
              _currentMode.toUpperCase(),
              style: TextStyle(color: modeColor, fontWeight: FontWeight.bold),
            ),
          ),

          // Controller Layout Switcher
          DropdownButton<String>(
            value: _controlLayout,
            dropdownColor: AppTheme.surface,
            icon: Icon(Icons.gamepad, color: modeColor),
            underline: Container(),
            style: TextStyle(color: modeColor, fontWeight: FontWeight.bold),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _controlLayout = newValue;
                });
                _saveSettings();
              }
            },
            items: const [
              DropdownMenuItem(value: 'joystick', child: Text('Joysticks')),
              DropdownMenuItem(value: 'dpad', child: Text('Basic D-Pad')),
              DropdownMenuItem(value: 'gamepad', child: Text('Retro Gamepad')),
            ],
          ),

          const Icon(Icons.battery_0_bar, color: Colors.grey), // Placeholder
        ],
      ),
    );
  }

  Widget _buildControlLayout(Color modeColor) {
    if (_controlLayout == 'dpad') {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: VirtualDPad(
              color: modeColor,
              verticalOnly: true,
              onChanged: (x, y) {
                _currentThrottle = y;
                _updateDriveInputs();
              },
            ),
          ),
          _buildControlsPanel(modeColor),
          Expanded(
            child: VirtualDPad(
              color: modeColor,
              horizontalOnly: true,
              onChanged: (x, y) {
                _currentSteering = x;
                _updateDriveInputs();
              },
            ),
          ),
        ],
      );
    } else if (_controlLayout == 'gamepad') {
      return Row(
        children: [
          Expanded(
            child: GamepadController(
              color: modeColor,
              onDirectionChanged: (x, y) {
                _currentSteering = x;
                _currentThrottle = y;
                _updateDriveInputs();
              },
              onActionPressed: (action) {
                if (action == 'triangle') _setMode('sport');
                if (action == 'cross') _setMode('crawl');
                if (action == 'square') _setMode('drift');
                if (action == 'circle') _setMode('normal');
              },
            ),
          ),
        ],
      );
    } else {
      // Default: Floating Joysticks
      return Row(
        children: [
          Expanded(
            child: FloatingJoystick(
              color: modeColor,
              verticalOnly: true,
              onChanged: (x, y) {
                _currentThrottle = y;
                _updateDriveInputs();
              },
            ),
          ),
          _buildControlsPanel(modeColor),
          Expanded(
            child: FloatingJoystick(
              color: modeColor,
              horizontalOnly: true,
              onChanged: (x, y) {
                _currentSteering = x;
                _updateDriveInputs();
              },
            ),
          ),
        ],
      );
    }
  }

  Widget _buildControlsPanel(Color modeColor) {
    return SizedBox(
      width: 240,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Max Throttle Slider
          Column(
            children: [
              Text(
                'MAX',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              Text(
                '$_maxThrottle%',
                style: TextStyle(color: modeColor, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: _maxThrottle.toDouble(),
                    min: 10,
                    max: 100,
                    activeColor: modeColor,
                    inactiveColor: AppTheme.surfaceHighlight,
                    onChanged: (val) {
                      setState(() => _maxThrottle = val.toInt());
                      _driveController.setMaxThrottle(_maxThrottle);
                    },
                    onChangeEnd: (_) => _saveSettings(),
                  ),
                ),
              ),
            ],
          ),
          // Steering Sensitivity Slider
          Column(
            children: [
              Text(
                'STEERING',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              Text(
                '$_steeringSens%',
                style: TextStyle(color: modeColor, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: _steeringSens.toDouble(),
                    min: 20,
                    max: 100,
                    activeColor: modeColor,
                    inactiveColor: AppTheme.surfaceHighlight,
                    onChanged: (val) {
                      setState(() => _steeringSens = val.toInt());
                      _driveController.setSteeringSensitivity(_steeringSens);
                    },
                    onChangeEnd: (_) => _saveSettings(),
                  ),
                ),
              ),
            ],
          ),
          // Deadzone Slider
          Column(
            children: [
              Text(
                'DEADZONE',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              Text(
                '$_deadzone',
                style: TextStyle(color: modeColor, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: _deadzone.toDouble(),
                    min: 0,
                    max: 20,
                    activeColor: modeColor,
                    inactiveColor: AppTheme.surfaceHighlight,
                    onChanged: (val) {
                      setState(() => _deadzone = val.toInt());
                      _driveController.setDeadzone(_deadzone);
                    },
                    onChangeEnd: (_) => _saveSettings(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomRow(Color modeColor) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionBtn(
              'E-STOP',
              AppTheme.estop,
              _triggerEStop,
              isLarge: true,
            ),
            const SizedBox(width: 16),
            _buildModeBtn('NORMAL', 'normal'),
            const SizedBox(width: 8),
            _buildModeBtn('SPORT', 'sport'),
            const SizedBox(width: 8),
            _buildModeBtn('DRIFT', 'drift'),
            const SizedBox(width: 8),
            _buildModeBtn('CRAWL', 'crawl'),
            const SizedBox(width: 32),

            // Cruise Control Button
            GestureDetector(
              onTap: () {
                setState(() => _cruiseEnabled = !_cruiseEnabled);
                if (_cruiseEnabled) {
                  _driveController.enableCruiseControl();
                  Vibration.vibrate(
                    duration: 50,
                    amplitude: 128,
                  ); // Sharp click on
                } else {
                  _driveController.disableCruiseControl();
                  Vibration.vibrate(
                    duration: 50,
                    amplitude: 64,
                  ); // Soft click off
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _cruiseEnabled
                      ? Colors.green.withValues(alpha: 0.2)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _cruiseEnabled ? Colors.green : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Text(
                  'CRUISE',
                  style: TextStyle(
                    color: _cruiseEnabled ? Colors.green : AppTheme.textMuted,
                    fontWeight: _cruiseEnabled
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 360 Tank Spin Button (Hold)
            GestureDetector(
              onTapDown: (_) {
                _driveController.startSpin(1); // 1 = Spin Right
                Vibration.vibrate(duration: 50);
              },
              onTapUp: (_) => _driveController.stopSpin(),
              onTapCancel: () => _driveController.stopSpin(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple, width: 2),
                ),
                child: const Text(
                  'SPIN (HOLD)',
                  style: TextStyle(
                    color: Colors.purple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeBtn(String label, String mode) {
    final isSelected = _currentMode == mode;
    final color = AppTheme.getModeColor(mode);
    return GestureDetector(
      onTap: () => _setMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : AppTheme.textMuted,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildActionBtn(
    String label,
    Color color,
    VoidCallback onTap, {
    bool isLarge = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isLarge ? 24 : 16,
          vertical: isLarge ? 16 : 12,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: isLarge ? 18 : 14,
          ),
        ),
      ),
    );
  }
}
