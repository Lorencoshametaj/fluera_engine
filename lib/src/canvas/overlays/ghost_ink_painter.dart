import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// =============================================================================
// 🔮 GHOST INK PAINTER v2 — Paragraph-cached predicted text overlay
//
// v2 OPTIMIZATION:
//   🚀 Caches ui.Paragraph object — avoids paragraph layout on every paint()
//      when text + scale haven't changed. Only rebuilds on actual data change.
// =============================================================================

class GhostInkPainter extends CustomPainter {
  final String text;
  final Offset position;
  final double canvasScale;
  final double opacity;
  final Color color;
  final bool isRtl;

  GhostInkPainter({
    required this.text,
    required this.position,
    this.canvasScale = 1.0,
    this.opacity = 0.25,
    this.color = const Color(0xFFA78BFA),
    this.isRtl = false,
  });

  // ── Paragraph Cache ────────────────────────────────────────────────────
  // Static cache shared across repaints when text + scale don't change.
  static String _cachedText = '';
  static double _cachedScale = 0;
  static double _cachedOpacity = 0;
  static int _cachedColorValue = 0;
  static bool _cachedRtl = false;
  static ui.Paragraph? _cachedParagraph;

  ui.Paragraph _getOrBuildParagraph(double fontSize) {
    // Cache hit check
    if (_cachedParagraph != null &&
        _cachedText == text &&
        _cachedScale == canvasScale &&
        _cachedOpacity == opacity &&
        _cachedColorValue == color.toARGB32() &&
        _cachedRtl == isRtl) {
      return _cachedParagraph!;
    }

    // Cache miss — rebuild
    final textStyle = ui.TextStyle(
      color: color.withValues(alpha: opacity),
      fontSize: fontSize,
      fontStyle: ui.FontStyle.italic,
      letterSpacing: 0.5,
    );

    final paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        maxLines: 1,
      ),
    )
      ..pushStyle(textStyle)
      ..addText(text);

    final paragraph = paragraphBuilder.build();
    paragraph.layout(ui.ParagraphConstraints(width: 400.0 / canvasScale));

    // Store in cache
    _cachedText = text;
    _cachedScale = canvasScale;
    _cachedOpacity = opacity;
    _cachedColorValue = color.toARGB32();
    _cachedRtl = isRtl;
    _cachedParagraph = paragraph;

    return paragraph;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty) return;

    final fontSize = 20.0 / canvasScale.clamp(0.3, 3.0);
    final paragraph = _getOrBuildParagraph(fontSize);

    // Position the ghost text slightly offset from the stroke end
    final xOffset = isRtl
        ? -paragraph.maxIntrinsicWidth - 12.0 / canvasScale
        : 12.0 / canvasScale;
    final yOffset = -fontSize * 0.3;

    canvas.drawParagraph(
      paragraph,
      Offset(position.dx + xOffset, position.dy + yOffset),
    );

    // Subtle underline dot-dash pattern
    final dashPaint = Paint()
      ..color = color.withValues(alpha: opacity * 0.5)
      ..strokeWidth = 1.0 / canvasScale
      ..style = PaintingStyle.stroke;

    final underlineY = position.dy + yOffset + fontSize * 1.1;
    final underlineStart = position.dx + xOffset;
    final underlineEnd = underlineStart + paragraph.maxIntrinsicWidth;

    const dashLen = 4.0;
    const gapLen = 3.0;
    double x = underlineStart;
    while (x < underlineEnd) {
      final end = math.min(x + dashLen / canvasScale, underlineEnd);
      canvas.drawLine(
        Offset(x, underlineY),
        Offset(end, underlineY),
        dashPaint,
      );
      x = end + gapLen / canvasScale;
    }
  }

  @override
  bool shouldRepaint(covariant GhostInkPainter old) =>
      old.text != text ||
      old.position != position ||
      old.canvasScale != canvasScale ||
      old.opacity != opacity ||
      old.color != color;
}
