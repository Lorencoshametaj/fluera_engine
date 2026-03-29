import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/digital_text_element.dart';
import '../../services/grammar_check_service.dart';

// =============================================================================
// 📝 GRAMMAR PAINTER — Blue wavy underline for grammar errors
//
// Distinct from SpellcheckPainter (red). Draws blue wavy underlines
// beneath grammar errors in DigitalTextElements.
// =============================================================================

/// Internal data class used by _spellcheck.dart part file.
/// Re-exported here so both the painter and the part can reference it.
class _GrammarOverlayDataRef {
  final String elementId;
  final List<GrammarError> errors;
  const _GrammarOverlayDataRef({required this.elementId, required this.errors});
}

class GrammarPainter extends CustomPainter {
  final List<DigitalTextElement> texts;
  final Offset canvasOffset;
  final double canvasScale;
  final Map<String, dynamic> overlays; // Map<String, _GrammarOverlayData>

  GrammarPainter({
    required this.texts,
    required this.canvasOffset,
    required this.canvasScale,
    required this.overlays,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (overlays.isEmpty) return;

    final wavyPaint = Paint()
      ..color = const Color(0xFF42A5F5) // Blue
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.translate(canvasOffset.dx, canvasOffset.dy);
    canvas.scale(canvasScale);

    for (final text in texts) {
      final overlay = overlays[text.id];
      if (overlay == null) continue;

      // Access errors from the dynamic overlay object
      final List<GrammarError> errors;
      if (overlay is _GrammarOverlayDataRef) {
        errors = overlay.errors;
      } else {
        // Assume it has an 'errors' field (from _GrammarOverlayData in part file)
        try {
          errors = (overlay as dynamic).errors as List<GrammarError>;
        } catch (_) {
          continue;
        }
      }
      if (errors.isEmpty) continue;

      _drawUnderlines(canvas, text, errors, wavyPaint);
    }

    canvas.restore();
  }

  void _drawUnderlines(
    Canvas canvas,
    DigitalTextElement element,
    List<GrammarError> errors,
    Paint wavyPaint,
  ) {
    final painter = element.layoutPainter;
    final position = element.position;

    if (element.rotation != 0.0) {
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(element.rotation);
      canvas.translate(-position.dx, -position.dy);
    }

    for (final error in errors) {
      final startOffset = painter.getOffsetForCaret(
        TextPosition(offset: error.startIndex),
        Rect.zero,
      );
      final endOffset = painter.getOffsetForCaret(
        TextPosition(offset: error.endIndex),
        Rect.zero,
      );

      final lineMetrics = painter.computeLineMetrics();
      if (lineMetrics.isEmpty) continue;

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
      final y = position.dy + baseline + 2.0;

      _drawWavyLine(canvas, x1, x2, y, wavyPaint);
    }

    if (element.rotation != 0.0) {
      canvas.restore();
    }
  }

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
  bool shouldRepaint(covariant GrammarPainter old) {
    if (old.canvasOffset != canvasOffset || old.canvasScale != canvasScale) {
      return true;
    }
    if (old.overlays.length != overlays.length) return true;
    if (!identical(old.overlays, overlays)) return true;
    return false;
  }
}
