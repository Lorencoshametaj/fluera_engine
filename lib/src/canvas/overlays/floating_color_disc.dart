import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// 🎨 FLOATING COLOR DISC — Compact draggable color picker (like Procreate)
//
// A small circle that shows the current color. Drag to reposition.
// Tap to expand into a mini HSB disc for quick color changes.
// Long-press to open the full ProColorPicker bottom sheet.
// =============================================================================

/// Floating color disc overlay — shows current color, expands to mini picker.
class FloatingColorDisc extends StatefulWidget {
  /// Current active color
  final Color color;

  /// Called when color is changed via the mini disc
  final ValueChanged<Color> onColorChanged;

  /// Called to open the full color picker
  final VoidCallback? onExpand;

  /// Initial position offset (from bottom-right)
  final Offset initialPosition;

  const FloatingColorDisc({
    super.key,
    required this.color,
    required this.onColorChanged,
    this.onExpand,
    this.initialPosition = const Offset(20, 140),
  });

  @override
  State<FloatingColorDisc> createState() => _FloatingColorDiscState();
}

class _FloatingColorDiscState extends State<FloatingColorDisc>
    with SingleTickerProviderStateMixin {
  late Offset _position;
  bool _isExpanded = false;
  bool _isDragging = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  // Mini disc state
  late HSVColor _hsv;

  static const double _collapsedSize = 44.0;
  static const double _expandedSize = 200.0;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _hsv = HSVColor.fromColor(widget.color);
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(FloatingColorDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color && !_isExpanded) {
      _hsv = HSVColor.fromColor(widget.color);
    }
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _hsv = HSVColor.fromColor(widget.color);
        _expandController.forward();
      } else {
        _expandController.reverse();
        // Apply the color when collapsing
        widget.onColorChanged(_hsv.toColor());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      right: _position.dx,
      bottom: _position.dy,
      child: GestureDetector(
        // Drag to reposition
        onPanStart: (_) => _isDragging = true,
        onPanUpdate: (d) {
          setState(() {
            _position = Offset(
              (_position.dx - d.delta.dx).clamp(0, screenSize.width - 60),
              (_position.dy - d.delta.dy).clamp(0, screenSize.height - 60),
            );
          });
        },
        onPanEnd: (_) => _isDragging = false,
        child: AnimatedBuilder(
          animation: _expandAnimation,
          builder: (context, child) {
            final t = _expandAnimation.value;
            final size = _collapsedSize + (_expandedSize - _collapsedSize) * t;

            return SizedBox(
              width: size,
              height: size,
              child: t < 0.1
                  ? _buildCollapsed(size)
                  : _buildExpanded(size, t),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCollapsed(double size) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: _toggle,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        widget.onExpand?.call();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          border: Border.all(
            color: isDark ? Colors.white : Colors.black26,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpanded(double size, double t) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark
            ? const Color(0xFF2A2A2A).withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        border: Border.all(
          color: isDark ? Colors.white24 : Colors.black12,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Mini hue ring
          Opacity(
            opacity: t,
            child: CustomPaint(
              size: Size(size - 16, size - 16),
              painter: _MiniHueRingPainter(
                hue: _hsv.hue,
                ringWidth: size * 0.10,
              ),
            ),
          ),

          // Hue ring gesture
          GestureDetector(
            onPanStart: (d) => _onMiniHuePan(d.localPosition, size),
            onPanUpdate: (d) => _onMiniHuePan(d.localPosition, size),
            child: SizedBox(width: size, height: size),
          ),

          // Center color preview + SV area
          Opacity(
            opacity: t,
            child: GestureDetector(
              onTap: _toggle,
              onLongPress: () {
                HapticFeedback.mediumImpact();
                widget.onExpand?.call();
              },
              child: Container(
                width: size * 0.52,
                height: size * 0.52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hsv.toColor(),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Brightness slider (vertical, right side)
          if (t > 0.5)
            Positioned(
              right: -2,
              top: size * 0.2,
              bottom: size * 0.2,
              child: Opacity(
                opacity: (t - 0.5) * 2,
                child: _MiniValueSlider(
                  value: _hsv.value,
                  hue: _hsv.hue,
                  saturation: _hsv.saturation,
                  onChanged: (v) => setState(() {
                    _hsv = _hsv.withValue(v);
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onMiniHuePan(Offset local, double size) {
    final center = Offset(size / 2, size / 2);
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);

    // Only accept touches on the ring area
    final outerR = size / 2 - 8;
    final innerR = outerR * 0.65;
    if (dist < innerR || dist > outerR + 10) return;

    final angle = math.atan2(dy, dx);
    final hue = ((angle * 180 / math.pi) + 360) % 360;
    setState(() => _hsv = _hsv.withHue(hue));
  }
}

// =============================================================================
// MINI PAINTERS
// =============================================================================

class _MiniHueRingPainter extends CustomPainter {
  final double hue;
  final double ringWidth;

  _MiniHueRingPainter({required this.hue, required this.ringWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = math.min(size.width, size.height) / 2;

    final gradient = SweepGradient(
      colors: List.generate(13, (i) =>
          HSVColor.fromAHSV(1, (i * 30.0) % 360, 1, 1).toColor()),
    );

    final rect = Rect.fromCircle(center: center, radius: outerRadius);
    canvas.drawCircle(center, outerRadius - ringWidth / 2,
        Paint()
          ..shader = gradient.createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth
          ..isAntiAlias = true);

    // Hue indicator dot
    final angle = hue * math.pi / 180 - math.pi / 2;
    final r = outerRadius - ringWidth / 2;
    final pos = Offset(
      center.dx + r * math.cos(angle),
      center.dy + r * math.sin(angle),
    );
    canvas.drawCircle(pos, ringWidth / 2 + 1,
        Paint()..color = Colors.white..isAntiAlias = true);
    canvas.drawCircle(pos, ringWidth / 2 - 1,
        Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor()..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_MiniHueRingPainter old) => old.hue != hue;
}

/// Mini vertical brightness/value slider on the right side of the floating disc.
class _MiniValueSlider extends StatelessWidget {
  final double value;
  final double hue;
  final double saturation;
  final ValueChanged<double> onChanged;

  const _MiniValueSlider({
    required this.value,
    required this.hue,
    required this.saturation,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(d.globalPosition);
        final v = 1.0 - (local.dy / box.size.height).clamp(0.0, 1.0);
        onChanged(v);
      },
      child: Container(
        width: 18,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              HSVColor.fromAHSV(1, hue, saturation, 1).toColor(),
              HSVColor.fromAHSV(1, hue, saturation, 0).toColor(),
            ],
          ),
          border: Border.all(color: Colors.white54, width: 1),
        ),
        child: Stack(
          children: [
            Positioned(
              top: (1 - value) * 80 - 4, // approximate
              left: 2,
              child: Container(
                width: 12,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
