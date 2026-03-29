import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/digital_text_element.dart';
import '../../services/spellcheck_service.dart';

// =============================================================================
// 🔍 SPELLCHECK PAINTER — Animated wavy red underline for misspelled words
//
// Draws wavy underlines beneath misspelled words in DigitalTextElements.
// Supports fade-in animation for smooth appearance.
// =============================================================================

/// Cached spellcheck data for a single text element.
class SpellcheckOverlay {
  final String elementId;
  final List<SpellcheckError> errors;

  const SpellcheckOverlay({
    required this.elementId,
    required this.errors,
  });
}

class SpellcheckPainter extends CustomPainter {
  final List<DigitalTextElement> texts;
  final Offset canvasOffset;
  final double canvasScale;
  final Map<String, SpellcheckOverlay> overlays;
  final double opacity; // 🔥 Animated opacity for fade-in

  SpellcheckPainter({
    required this.texts,
    required this.canvasOffset,
    required this.canvasScale,
    required this.overlays,
    this.opacity = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (overlays.isEmpty || opacity <= 0.0) return;

    final wavyPaint = Paint()
      ..color = const Color(0xFFE53935).withValues(alpha: opacity)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.translate(canvasOffset.dx, canvasOffset.dy);
    canvas.scale(canvasScale);

    for (final text in texts) {
      final overlay = overlays[text.id];
      if (overlay == null || overlay.errors.isEmpty) continue;

      _drawWavyUnderlines(canvas, text, overlay.errors, wavyPaint);
    }

    canvas.restore();
  }

  void _drawWavyUnderlines(
    Canvas canvas,
    DigitalTextElement element,
    List<SpellcheckError> errors,
    Paint wavyPaint,
  ) {
    final painter = element.layoutPainter;
    final position = element.position;

    // Apply rotation if needed
    if (element.rotation != 0.0) {
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(element.rotation);
      canvas.translate(-position.dx, -position.dy);
    }

    for (final error in errors) {
      // Get the text position for the error's start and end
      final startOffset = painter.getOffsetForCaret(
        TextPosition(offset: error.startIndex),
        Rect.zero,
      );
      final endOffset = painter.getOffsetForCaret(
        TextPosition(offset: error.endIndex),
        Rect.zero,
      );

      // Calculate underline position
      final lineMetrics = painter.computeLineMetrics();
      if (lineMetrics.isEmpty) continue;

      // Find which line the error is on
      double baseline = lineMetrics.first.baseline;
      for (final metric in lineMetrics) {
        final lineTop = metric.baseline - metric.ascent;
        final lineBottom = metric.baseline + metric.descent;
        if (startOffset.dy >= lineTop && startOffset.dy <= lineBottom) {
          baseline = metric.baseline;
          break;
        }
      }

      final x1 = position.dx + startOffset.dx;
      final x2 = position.dx + endOffset.dx;
      final y = position.dy + baseline + 2.0; // 2px below baseline

      _drawWavyLine(canvas, x1, x2, y, wavyPaint);
    }

    if (element.rotation != 0.0) {
      canvas.restore();
    }
  }

  /// Draw a wavy (sinusoidal) line between x1 and x2 at height y.
  void _drawWavyLine(Canvas canvas, double x1, double x2, double y, Paint paint) {
    if (x2 <= x1) return;

    final path = Path();
    const waveLength = 4.0;
    const amplitude = 1.5;

    path.moveTo(x1, y);

    double x = x1;
    while (x < x2) {
      final nextX = math.min(x + waveLength / 2, x2);
      final cpY = y + (((x - x1) / (waveLength / 2)).floor().isEven
          ? -amplitude
          : amplitude);
      path.quadraticBezierTo(
        (x + nextX) / 2,
        cpY,
        nextX,
        y,
      );
      x = nextX;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SpellcheckPainter old) {
    if (old.canvasOffset != canvasOffset || old.canvasScale != canvasScale) {
      return true;
    }
    if (old.opacity != opacity) return true;
    if (old.overlays.length != overlays.length) return true;
    if (!identical(old.overlays, overlays)) return true;
    return false;
  }
}
