import 'package:flutter/material.dart';
import '../../core/nodes/latex_node.dart';
import '../../core/latex/latex_draw_command.dart';

/// 🧮 LatexRenderer — renders a [LatexNode] onto a Flutter [Canvas].
///
/// Consumes the pre-computed [LatexDrawCommand] list from the layout engine
/// and executes the corresponding Canvas operations:
/// - [GlyphDrawCommand] → `canvas.drawParagraph()` / `TextPainter.paint()`
/// - [LineDrawCommand]  → `canvas.drawLine()`
/// - [PathDrawCommand]  → `canvas.drawPath()`
///
/// When no cached layout is available, draws a placeholder.
class LatexRenderer {
  /// Draw the LaTeX node onto the canvas.
  static void drawLatexNode(Canvas canvas, LatexNode node) {
    final commands = node.cachedDrawCommands;
    if (commands == null || commands.isEmpty) {
      _drawPlaceholder(canvas, node);
      return;
    }

    for (final cmd in commands) {
      switch (cmd) {
        case GlyphDrawCommand():
          _drawGlyph(canvas, cmd);
        case LineDrawCommand():
          _drawLine(canvas, cmd);
        case PathDrawCommand():
          _drawPathCmd(canvas, cmd);
      }
    }
  }

  /// Draw a text glyph at its computed position.
  static void _drawGlyph(Canvas canvas, GlyphDrawCommand cmd) {
    final style = TextStyle(
      fontFamily: cmd.fontFamily.isNotEmpty ? cmd.fontFamily : null,
      fontSize: cmd.fontSize,
      color: cmd.color,
      fontStyle: cmd.italic ? FontStyle.italic : FontStyle.normal,
      fontWeight: cmd.bold ? FontWeight.bold : FontWeight.normal,
    );

    final painter = TextPainter(
      text: TextSpan(text: cmd.text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(canvas, Offset(cmd.x, cmd.y));
  }

  /// Draw a line segment (fraction bar, radical bar, etc.).
  static void _drawLine(Canvas canvas, LineDrawCommand cmd) {
    final paint =
        Paint()
          ..color = cmd.color
          ..strokeWidth = cmd.thickness
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.butt
          ..isAntiAlias = true;

    canvas.drawLine(Offset(cmd.x1, cmd.y1), Offset(cmd.x2, cmd.y2), paint);
  }

  /// Draw a path (integral sign, radical symbol, brackets, etc.).
  static void _drawPathCmd(Canvas canvas, PathDrawCommand cmd) {
    if (cmd.points.isEmpty) return;

    final path = Path();
    path.moveTo(cmd.points.first.dx, cmd.points.first.dy);
    for (int i = 1; i < cmd.points.length; i++) {
      path.lineTo(cmd.points[i].dx, cmd.points[i].dy);
    }
    if (cmd.closed) path.close();

    final paint =
        Paint()
          ..color = cmd.color
          ..isAntiAlias = true;

    if (cmd.filled) {
      paint.style = PaintingStyle.fill;
    } else {
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = cmd.strokeWidth;
      paint.strokeCap = StrokeCap.round;
      paint.strokeJoin = StrokeJoin.round;
    }

    canvas.drawPath(path, paint);
  }

  /// Draw a placeholder when the layout is not yet computed.
  ///
  /// Shows a light rectangle with "∑ ..." text to indicate that
  /// a LaTeX expression exists here but hasn't been laid out yet.
  static void _drawPlaceholder(Canvas canvas, LatexNode node) {
    final bounds = node.localBounds;

    // Background: semi-transparent gray rounded rect.
    final bgPaint =
        Paint()
          ..color = const Color(0x20808080)
          ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(6)),
      bgPaint,
    );

    // Border: dashed appearance via dotted stroke.
    final borderPaint =
        Paint()
          ..color = const Color(0x40808080)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(6)),
      borderPaint,
    );

    // "∑" icon + preview text.
    final preview =
        node.latexSource.length > 20
            ? '∑ ${node.latexSource.substring(0, 17)}...'
            : '∑ ${node.latexSource}';

    final tp = TextPainter(
      text: TextSpan(
        text: preview,
        style: TextStyle(
          color: const Color(0xFF888888),
          fontSize: node.fontSize * 0.7,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: bounds.width);

    tp.paint(
      canvas,
      Offset(
        bounds.left + (bounds.width - tp.width) / 2,
        bounds.top + (bounds.height - tp.height) / 2,
      ),
    );
  }
}
