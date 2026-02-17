import 'package:flutter/material.dart';
import '../../core/models/digital_text_element.dart';

/// 🎨 Painter per renderizzare testi digitali direttamente sul Canvas
/// Risolve problemi di sincronizzazione/floating rispetto ai widget
class DigitalTextPainter extends CustomPainter {
  final List<DigitalTextElement> texts;
  final Offset canvasOffset;
  final double canvasScale;
  final String? selectedElementId;

  DigitalTextPainter({
    required this.texts,
    required this.canvasOffset,
    required this.canvasScale,
    this.selectedElementId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (texts.isEmpty) return;

    canvas.save();
    // 🔗 Applica stessa trasformazione of strokes (Stroke)
    canvas.translate(canvasOffset.dx, canvasOffset.dy);
    canvas.scale(canvasScale);

    for (final element in texts) {
      // 🎨 Configure stile testo
      final textSpan = TextSpan(
        text: element.text,
        style: TextStyle(
          color: element.color,
          fontSize: element.fontSize * element.scale,
          fontFamily: element.fontFamily,
          fontWeight: element.fontWeight,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );

      // 📏 Layout del testo
      textPainter.layout();

      // 🖌️ Draw testo alla position corretta
      // The position is already in coordinate Canvas, e il canvas is trasformato
      textPainter.paint(canvas, element.position);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DigitalTextPainter oldDelegate) {
    // 🚀 Optimization: Ridisegna only if cambia qualcosa di visivo
    return oldDelegate.canvasOffset != canvasOffset ||
        oldDelegate.canvasScale != canvasScale ||
        oldDelegate.texts != texts ||
        oldDelegate.selectedElementId != selectedElementId;
  }
}
