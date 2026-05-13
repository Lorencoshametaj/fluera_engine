import 'package:flutter/material.dart';

import '../../canvas/infinite_canvas_controller.dart';

// ============================================================================
// 📐🌫️ PREVIEW OVERLAY PAINTERS — section + fog zone preview rectangles
//
// Originally lived as `_SectionPreviewPainter` / `_FogZonePreviewPainter`
// in `parts/ui/_ui_canvas_layer_painters.dart` (a `part of
// fluera_canvas_screen.dart` file). Extracted to this public file so
// [FlueraCanvasView] can render them outside the screen library.
//
// Both painters render a rectangle while the user drags to define a
// section / fog zone. Same shape (translucent fill + dashed border +
// corner accents + label), different color theme.
// ============================================================================

/// 📐 Paints a live preview rectangle while dragging to create a section.
/// Includes dashed border, corner marks, translucent fill, and dimension label.
class SectionPreviewPainter extends CustomPainter {
  final Offset startPoint;
  final Offset endPoint;
  final InfiniteCanvasController controller;

  SectionPreviewPainter({
    required this.startPoint,
    required this.endPoint,
    required this.controller,
  });

  static const _accentColor = Color(0xFF2196F3);
  static const _cornerLength = 14.0;
  static const _cornerStroke = 2.5;
  static const _dashLength = 6.0;
  static const _dashGap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(startPoint, endPoint);
    if (rect.width < 2 && rect.height < 2) return;

    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    // 1. Translucent fill
    final fillPaint = Paint()
      ..color = _accentColor.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);

    // 2. Dashed border
    final borderPaint = Paint()
      ..color = _accentColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / controller.scale;
    _drawDashedRect(canvas, rect, borderPaint);

    // 3. Corner marks (solid, thicker)
    final cornerPaint = Paint()
      ..color = _accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _cornerStroke / controller.scale
      ..strokeCap = StrokeCap.round;
    final cl = _cornerLength / controller.scale;
    _drawCornerMarks(canvas, rect, cornerPaint, cl);

    // 4. Dimension label
    final w = rect.width.round();
    final h = rect.height.round();
    if (w > 10 && h > 10) {
      final labelFontSize = 11.0 / controller.scale;
      final tp = TextPainter(
        text: TextSpan(
          text: '$w × $h',
          style: TextStyle(
            color: _accentColor,
            fontSize: labelFontSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelX = rect.center.dx - tp.width / 2;
      final labelY = rect.bottom + 6.0 / controller.scale;

      final labelPadH = 6.0 / controller.scale;
      final labelPadV = 3.0 / controller.scale;
      final labelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          labelX - labelPadH,
          labelY - labelPadV,
          tp.width + labelPadH * 2,
          tp.height + labelPadV * 2,
        ),
        Radius.circular(4.0 / controller.scale),
      );
      canvas.drawRRect(labelRect, Paint()..color = const Color(0xE0121212));

      tp.paint(canvas, Offset(labelX, labelY));
    }

    canvas.restore();
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    final invScale = 1.0 / controller.scale;
    final dash = _dashLength * invScale;
    final gap = _dashGap * invScale;
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint, dash, gap);
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint, dash, gap);
    _drawDashedLine(
      canvas,
      rect.bottomRight,
      rect.bottomLeft,
      paint,
      dash,
      gap,
    );
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint, dash, gap);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    double dashLen,
    double gapLen,
  ) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = Offset(dx, dy).distance;
    if (length < 1) return;
    final ux = dx / length;
    final uy = dy / length;

    double drawn = 0;
    bool drawing = true;
    while (drawn < length) {
      final segLen = drawing ? dashLen : gapLen;
      final remaining = length - drawn;
      final len = segLen < remaining ? segLen : remaining;

      if (drawing) {
        canvas.drawLine(
          Offset(start.dx + ux * drawn, start.dy + uy * drawn),
          Offset(start.dx + ux * (drawn + len), start.dy + uy * (drawn + len)),
          paint,
        );
      }
      drawn += len;
      drawing = !drawing;
    }
  }

  void _drawCornerMarks(Canvas canvas, Rect rect, Paint paint, double len) {
    canvas.drawLine(rect.topLeft, Offset(rect.left + len, rect.top), paint);
    canvas.drawLine(rect.topLeft, Offset(rect.left, rect.top + len), paint);
    canvas.drawLine(rect.topRight, Offset(rect.right - len, rect.top), paint);
    canvas.drawLine(rect.topRight, Offset(rect.right, rect.top + len), paint);
    canvas.drawLine(
      rect.bottomLeft,
      Offset(rect.left + len, rect.bottom),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      Offset(rect.left, rect.bottom - len),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      Offset(rect.right - len, rect.bottom),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      Offset(rect.right, rect.bottom - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant SectionPreviewPainter oldDelegate) =>
      startPoint != oldDelegate.startPoint || endPoint != oldDelegate.endPoint;
}

/// 🌫️ Paints a preview rectangle while dragging to select a fog-of-war
/// zone (PASSO 10 step). Uses a teal/fog accent to distinguish from
/// section creation.
class FogZonePreviewPainter extends CustomPainter {
  final Offset startPoint;
  final Offset endPoint;
  final InfiniteCanvasController controller;

  FogZonePreviewPainter({
    required this.startPoint,
    required this.endPoint,
    required this.controller,
  });

  static const _fogColor = Color(0xFF607D8B); // Blue-grey fog theme
  static const _dashLength = 8.0;
  static const _dashGap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(startPoint, endPoint);
    if (rect.width < 2 && rect.height < 2) return;

    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    final invScale = 1.0 / controller.scale;

    // 1. Translucent fill (fog-like)
    final fillPaint = Paint()
      ..color = _fogColor.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(8 * invScale)),
      fillPaint,
    );

    // 2. Dashed border
    final borderPaint = Paint()
      ..color = _fogColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * invScale;
    _drawDashedRect(canvas, rect, borderPaint, invScale);

    // 3. Corner dots
    final dotPaint = Paint()..color = _fogColor;
    final dotR = 3.0 * invScale;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(corner, dotR, dotPaint);
    }

    // 4. Label: "🌫️ Fog Zone"
    final labelFontSize = 12.0 * invScale;
    final tp = TextPainter(
      text: TextSpan(
        text: '🌫️ Fog Zone',
        style: TextStyle(
          color: Colors.white,
          fontSize: labelFontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelX = rect.center.dx - tp.width / 2;
    final labelY = rect.top - tp.height - 10.0 * invScale;

    final padH = 8.0 * invScale;
    final padV = 4.0 * invScale;
    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        labelX - padH,
        labelY - padV,
        tp.width + padH * 2,
        tp.height + padV * 2,
      ),
      Radius.circular(6.0 * invScale),
    );
    canvas.drawRRect(
      labelRect,
      Paint()..color = _fogColor.withValues(alpha: 0.85),
    );
    tp.paint(canvas, Offset(labelX, labelY));

    canvas.restore();
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint, double invScale) {
    final dash = _dashLength * invScale;
    final gap = _dashGap * invScale;

    void dashedLine(Offset a, Offset b) {
      final delta = b - a;
      final length = delta.distance;
      if (length < 1) return;
      final ux = delta.dx / length;
      final uy = delta.dy / length;
      double drawn = 0;
      bool on = true;
      while (drawn < length) {
        final seg = on ? dash : gap;
        final len = seg < (length - drawn) ? seg : (length - drawn);
        if (on) {
          canvas.drawLine(
            Offset(a.dx + ux * drawn, a.dy + uy * drawn),
            Offset(a.dx + ux * (drawn + len), a.dy + uy * (drawn + len)),
            paint,
          );
        }
        drawn += len;
        on = !on;
      }
    }

    dashedLine(rect.topLeft, rect.topRight);
    dashedLine(rect.topRight, rect.bottomRight);
    dashedLine(rect.bottomRight, rect.bottomLeft);
    dashedLine(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant FogZonePreviewPainter oldDelegate) =>
      startPoint != oldDelegate.startPoint || endPoint != oldDelegate.endPoint;
}
