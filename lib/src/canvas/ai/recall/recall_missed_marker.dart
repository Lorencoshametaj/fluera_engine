// ============================================================================
// ❓ RECALL MISSED MARKER — "Non ricordo" placeholder node
//
// Spec: P2-14, P2-15
//
// When the student double-taps on an empty area during Recall Mode,
// this marker is placed to indicate "I know something was here but
// I can't remember what."
//
// Visual: red (#FF3B30), dashed border, 60% opacity, "?" icon center.
// Freely positionable in the canvas.
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'recall_mode_controller.dart';

/// ❓ Widget for a "non ricordo" marker.
///
/// Renders as a dashed-border circle/rectangle with a "?" icon.
/// Can be dragged to reposition and tapped to remove.
class RecallMissedMarkerWidget extends StatefulWidget {
  /// The marker data.
  final RecallMissedMarker marker;

  /// Screen position (converted from canvas coordinates by parent).
  final Offset screenPosition;

  /// Scale factor from canvas controller.
  final double scale;

  /// Called when the marker is tapped (to remove it).
  final VoidCallback? onTap;

  /// Called when dragged to a new canvas position.
  final void Function(Offset newCanvasPosition)? onDragEnd;

  const RecallMissedMarkerWidget({
    super.key,
    required this.marker,
    required this.screenPosition,
    required this.scale,
    this.onTap,
    this.onDragEnd,
  });

  @override
  State<RecallMissedMarkerWidget> createState() =>
      _RecallMissedMarkerWidgetState();
}

class _RecallMissedMarkerWidgetState extends State<RecallMissedMarkerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = 60.0 * widget.scale.clamp(0.3, 2.0);

    return Positioned(
      left: widget.screenPosition.dx - size / 2,
      top: widget.screenPosition.dy - size / 2,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: GestureDetector(
          onTap: widget.onTap,
          child: CustomPaint(
            size: Size(size, size),
            painter: _MissedMarkerPainter(),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Text(
                  '?',
                  style: TextStyle(
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.8),
                    fontSize: size * 0.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the dashed border (P2-15).
class _MissedMarkerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF3B30).withValues(alpha: 0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Background fill.
    final fill = Paint()
      ..color = const Color(0xFFFF3B30).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final rect = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    canvas.drawRRect(rRect, fill);

    // Dashed border.
    final path = Path()..addRRect(rRect);
    final dashPath = _createDashPath(path, dashLength: 8.0, gapLength: 5.0);
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(_MissedMarkerPainter oldDelegate) => false;

  /// Create a dashed path from a source path.
  Path _createDashPath(
    Path source, {
    required double dashLength,
    required double gapLength,
  }) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final len = math.min(dashLength, metric.length - distance);
        dest.addPath(
          metric.extractPath(distance, distance + len),
          Offset.zero,
        );
        distance += dashLength + gapLength;
      }
    }
    return dest;
  }
}
