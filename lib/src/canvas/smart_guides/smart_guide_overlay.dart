import 'package:flutter/material.dart';
import '../infinite_canvas_controller.dart';
import './smart_guide_engine.dart';

/// 📐 Smart Guide Overlay Painter
///
/// Renders alignment guide lines on the canvas when dragging elements.
/// Lines are drawn in canvas space and transformed to screen space
/// via the canvas controller's transform.
///
/// DESIGN:
/// - Edge guides: solid cyan line (1px)
/// - Center guides: dashed magenta line (1px)
/// - Guide lines extend 10px beyond the aligned elements
class SmartGuidePainter extends CustomPainter {
  final List<SmartGuideLine> guides;
  final InfiniteCanvasController controller;

  SmartGuidePainter({required this.guides, required this.controller})
    : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    if (guides.isEmpty) return;

    final edgePaint =
        Paint()
          ..color = const Color(0xFF00BCD4) // Cyan
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

    final centerPaint =
        Paint()
          ..color = const Color(0xFFE040FB) // Magenta/purple
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

    for (final guide in guides) {
      final paint = guide.isCenter ? centerPaint : edgePaint;

      if (guide.axis == Axis.vertical) {
        // Vertical line at X = guide.position, from start to end (Y)
        final startScreen = controller.canvasToScreen(
          Offset(guide.position, guide.start),
        );
        final endScreen = controller.canvasToScreen(
          Offset(guide.position, guide.end),
        );

        if (guide.isCenter) {
          _drawDashedLine(canvas, startScreen, endScreen, paint);
        } else {
          canvas.drawLine(startScreen, endScreen, paint);
        }
      } else {
        // Horizontal line at Y = guide.position, from start to end (X)
        final startScreen = controller.canvasToScreen(
          Offset(guide.start, guide.position),
        );
        final endScreen = controller.canvasToScreen(
          Offset(guide.end, guide.position),
        );

        if (guide.isCenter) {
          _drawDashedLine(canvas, startScreen, endScreen, paint);
        } else {
          canvas.drawLine(startScreen, endScreen, paint);
        }
      }
    }
  }

  /// Draw a dashed line between two points.
  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final delta = end - start;
    final length = delta.distance;
    if (length < 1) return;

    final direction = delta / length;
    const dashLength = 6.0;
    const gapLength = 4.0;

    double drawn = 0;
    bool isDash = true;

    while (drawn < length) {
      final segLen = isDash ? dashLength : gapLength;
      final segEnd = (drawn + segLen).clamp(0.0, length);

      if (isDash) {
        canvas.drawLine(
          start + direction * drawn,
          start + direction * segEnd,
          paint,
        );
      }
      drawn = segEnd;
      isDash = !isDash;
    }
  }

  @override
  bool shouldRepaint(SmartGuidePainter oldDelegate) {
    return guides != oldDelegate.guides;
  }
}
