import 'package:flutter/material.dart';

class FloatingJoystick extends StatefulWidget {
  final void Function(double x, double y) onChanged;
  final bool verticalOnly;
  final bool horizontalOnly;
  final Color color;

  const FloatingJoystick({
    super.key,
    required this.onChanged,
    this.verticalOnly = false,
    this.horizontalOnly = false,
    required this.color,
  });

  @override
  State<FloatingJoystick> createState() => _FloatingJoystickState();
}

class _FloatingJoystickState extends State<FloatingJoystick> {
  Offset? _basePosition;
  Offset _thumbOffset = Offset.zero;
  
  // Game-like tuning parameters
  final double _maxRadius = 80.0; // Generous travel distance for precision
  final double _baseSize = 140.0; // Visual big base ring
  final double _thumbSize = 56.0; // Easy-to-see glowing thumb nub

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _basePosition = details.localPosition;
      _thumbOffset = Offset.zero;
    });
    widget.onChanged(0.0, 0.0);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_basePosition == null) return;
    
    Offset delta = details.localPosition - _basePosition!;
    double dx = widget.verticalOnly ? 0 : delta.dx;
    double dy = widget.horizontalOnly ? 0 : delta.dy;

    Offset newOffset = Offset(dx, dy);
    if (newOffset.distance > _maxRadius) {
      newOffset = Offset.fromDirection(newOffset.direction, _maxRadius);
    }

    setState(() {
      _thumbOffset = newOffset;
    });

    widget.onChanged(
      newOffset.dx / _maxRadius,
      newOffset.dy / _maxRadius,
    );
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _basePosition = null;
      _thumbOffset = Offset.zero;
    });
    widget.onChanged(0.0, 0.0); // Immediately stop motor on release
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque, // Ensures the entire half of screen is tapable
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onPanCancel: () => _onPanEnd(DragEndDetails()),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.transparent, // Capture taps anywhere
        child: Stack(
          children: [
            if (_basePosition != null)
              Positioned(
                left: _basePosition!.dx - (_baseSize / 2),
                top: _basePosition!.dy - (_baseSize / 2),
                child: Container(
                  width: _baseSize,
                  height: _baseSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: widget.color.withValues(alpha: 0.4), width: 3),
                    color: widget.color.withValues(alpha: 0.1),
                  ),
                  child: Center(
                    child: Transform.translate(
                      offset: _thumbOffset,
                      child: Container(
                        width: _thumbSize,
                        height: _thumbSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.color,
                          boxShadow: [
                            BoxShadow(
                              color: widget.color.withValues(alpha: 0.8),
                              blurRadius: 15,
                              spreadRadius: 2,
                            )
                          ]
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.verticalOnly ? Icons.unfold_more_rounded : Icons.swap_horiz_rounded,
                      color: widget.color.withValues(alpha: 0.15),
                      size: 64,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.verticalOnly ? 'THROTTLE' : 'STEER',
                      style: TextStyle(
                        color: widget.color.withValues(alpha: 0.2),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    )
                  ],
                ),
              )
          ],
        ),
      ),
    );
  }
}
