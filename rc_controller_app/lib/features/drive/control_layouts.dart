import 'package:flutter/material.dart';

class VirtualDPad extends StatefulWidget {
  final void Function(double x, double y) onChanged;
  final Color color;
  final bool verticalOnly;
  final bool horizontalOnly;
  final double size;

  const VirtualDPad({
    super.key,
    required this.onChanged,
    required this.color,
    this.verticalOnly = false,
    this.horizontalOnly = false,
    this.size = 140,
  });

  @override
  State<VirtualDPad> createState() => _VirtualDPadState();
}

class _VirtualDPadState extends State<VirtualDPad> {
  double _dx = 0;
  double _dy = 0;

  void _handleUpdate(Offset localPosition) {
    double center = widget.size / 2;
    double dx = localPosition.dx - center;
    double dy = localPosition.dy - center;

    double outX = 0;
    double outY = 0;

    // Small interior deadzone
    if (dx.abs() > widget.size * 0.1 || dy.abs() > widget.size * 0.1) {
      if (!widget.verticalOnly && dx.abs() > dy.abs() * 0.3) {
        outX = dx > 0 ? 1.0 : -1.0;
      }
      if (!widget.horizontalOnly && dy.abs() > dx.abs() * 0.3) {
        outY = dy > 0 ? 1.0 : -1.0;
      }
    }

    if (outX != _dx || outY != _dy) {
      setState(() {
        _dx = outX;
        _dy = outY;
      });
      widget.onChanged(_dx, _dy);
    }
  }

  void _handleEnd() {
    setState(() {
      _dx = 0;
      _dy = 0;
    });
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => _handleUpdate(d.localPosition),
      onPanUpdate: (d) => _handleUpdate(d.localPosition),
      onPanEnd: (_) => _handleEnd(),
      onPanCancel: () => _handleEnd(),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(color: widget.color.withValues(alpha: 0.3), width: 2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (!widget.horizontalOnly) ...[
              Positioned(
                top: 10,
                child: Icon(Icons.arrow_drop_up,
                    color: _dy < 0 ? widget.color : widget.color.withValues(alpha: 0.2), size: 48),
              ),
              Positioned(
                bottom: 10,
                child: Icon(Icons.arrow_drop_down,
                    color: _dy > 0 ? widget.color : widget.color.withValues(alpha: 0.2), size: 48),
              ),
            ],
            if (!widget.verticalOnly) ...[
              Positioned(
                left: 10,
                child: Icon(Icons.arrow_left,
                    color: _dx < 0 ? widget.color : widget.color.withValues(alpha: 0.2), size: 48),
              ),
              Positioned(
                right: 10,
                child: Icon(Icons.arrow_right,
                    color: _dx > 0 ? widget.color : widget.color.withValues(alpha: 0.2), size: 48),
              ),
            ],
            // Center ring indicator
            Container(
              width: widget.size * 0.3,
              height: widget.size * 0.3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (_dx != 0 || _dy != 0) ? widget.color.withValues(alpha: 0.4) : Colors.transparent,
                border: Border.all(color: widget.color.withValues(alpha: 0.2), width: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GamepadController extends StatelessWidget {
  final void Function(double x, double y) onDirectionChanged;
  final void Function(String action) onActionPressed;
  final Color color;

  const GamepadController({
    super.key,
    required this.onDirectionChanged,
    required this.onActionPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2C529E),
        borderRadius: BorderRadius.circular(100),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Omni-directional Retro D-Pad
          VirtualDPad(
            color: const Color(0xFFF38137),
            onChanged: onDirectionChanged,
          ),
          
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildCenterBtn('START'),
              const SizedBox(height: 16),
              _buildCenterBtn('SELECT'),
            ],
          ),

          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(top: 0, child: _buildActionBtn(Icons.change_history, 'triangle')),
                Positioned(bottom: 0, child: _buildActionBtn(Icons.close, 'cross')),
                Positioned(left: 0, child: _buildActionBtn(Icons.crop_square, 'square')),
                Positioned(right: 0, child: _buildActionBtn(Icons.circle_outlined, 'circle')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn(IconData icon, String action) {
    return GestureDetector(
      onTap: () => onActionPressed(action),
      child: Container(
        width: 50,
        height: 50,
        decoration: const BoxDecoration(
          color: Color(0xFFF38137),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildCenterBtn(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF38137),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
