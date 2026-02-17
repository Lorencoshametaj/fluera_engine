import 'package:flutter/material.dart';
import '../../core/nodes/rich_text_node.dart';

/// Renders a [RichTextNode] to a [Canvas].
///
/// Handles multi-span text layout with paragraph formatting,
/// optional background fill, and auto/fixed sizing.
class RichTextRenderer {
  RichTextRenderer._();

  /// Layout and draw the rich text node.
  static void drawRichTextNode(Canvas canvas, RichTextNode node) {
    final textSpan = node.toTextSpan();

    final painter = TextPainter(
      text: textSpan,
      textAlign: node.textAlign,
      textDirection: TextDirection.ltr,
      textHeightBehavior: TextHeightBehavior(
        leadingDistribution: TextLeadingDistribution.even,
      ),
    );

    // Apply line height via strutStyle.
    if (node.lineHeight != 1.2) {
      painter.strutStyle = StrutStyle(
        forceStrutHeight: false,
        height: node.lineHeight,
        leading: 0,
      );
    }

    // Layout within constraints.
    if (node.autoWidth) {
      painter.layout();
    } else if (node.fixedSize != null) {
      painter.layout(maxWidth: node.fixedSize!.width);
    } else {
      painter.layout();
    }

    // Update cached size for bounds/hit testing.
    node.cachedSize = painter.size;

    // Draw background fill if present.
    final bounds = Rect.fromLTWH(0, 0, painter.width, painter.height);
    if (node.boxFillGradient != null) {
      final bgPaint = Paint()..shader = node.boxFillGradient!.toShader(bounds);
      canvas.drawRect(bounds, bgPaint);
    } else if (node.boxFillColor != null) {
      canvas.drawRect(bounds, Paint()..color = node.boxFillColor!);
    }

    // Paint the text.
    painter.paint(canvas, Offset.zero);
  }
}
