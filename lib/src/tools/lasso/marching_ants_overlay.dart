import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated marching ants border around a selection rectangle.
///
/// Creates a Photoshop-style animated dashed border that continuously
/// moves around the selection bounds.
class MarchingAntsOverlay extends StatefulWidget {
  /// The bounding rectangle to draw marching ants around.
  final Rect bounds;

  /// Dash length in logical pixels.
  final double dashLength;

  /// Gap length between dashes.
  final double gapLength;

  /// Border width.
  final double strokeWidth;

  /// Primary dash color.
  final Color color;

  /// Background color (behind dashes, makes them visible on any surface).
  final Color backgroundColor;

  /// Animation speed — full cycle duration.
  final Duration animationDuration;

  const MarchingAntsOverlay({
    super.key,
    required this.bounds,
    this.dashLength = 6.0,
    this.gapLength = 4.0,
    this.strokeWidth = 1.5,
    this.color = Colors.white,
    this.backgroundColor = Colors.black54,
    this.animationDuration = const Duration(milliseconds: 800),
  });

  @override
  State<MarchingAntsOverlay> createState() => _MarchingAntsOverlayState();
}

class _MarchingAntsOverlayState extends State<MarchingAntsOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _MarchingAntsPainter(
            bounds: widget.bounds,
            dashLength: widget.dashLength,
            gapLength: widget.gapLength,
            strokeWidth: widget.strokeWidth,
            color: widget.color,
            backgroundColor: widget.backgroundColor,
            dashOffset:
                _controller.value * (widget.dashLength + widget.gapLength),
          ),
        );
      },
    );
  }
}

class _MarchingAntsPainter extends CustomPainter {
  final Rect bounds;
  final double dashLength;
  final double gapLength;
  final double strokeWidth;
  final Color color;
  final Color backgroundColor;
  final double dashOffset;

  _MarchingAntsPainter({
    required this.bounds,
    required this.dashLength,
    required this.gapLength,
    required this.strokeWidth,
    required this.color,
    required this.backgroundColor,
    required this.dashOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background stroke (solid, darker)
    final bgPaint =
        Paint()
          ..color = backgroundColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth;
    canvas.drawRect(bounds, bgPaint);

    // Foreground dashed stroke (animated)
    final fgPaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt;

    _drawDashedRect(canvas, bounds, fgPaint);
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    final path = Path()..addRect(rect);
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      double distance = dashOffset;
      while (distance < metric.length) {
        final start = distance;
        final end = math.min(distance + dashLength, metric.length);
        final extractPath = metric.extractPath(start, end);
        canvas.drawPath(extractPath, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_MarchingAntsPainter oldDelegate) =>
      oldDelegate.dashOffset != dashOffset || oldDelegate.bounds != bounds;
}
