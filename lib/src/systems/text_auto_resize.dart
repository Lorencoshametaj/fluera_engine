/// 📐 TEXT AUTO RESIZE — Auto-resize modes for text nodes.
///
/// Computes text node dimensions based on resize mode:
/// fixed, auto-width, auto-height, or auto-all.
///
/// ```dart
/// final size = TextAutoResizeEngine.computeSize(
///   text: 'Hello world',
///   style: TextStyle(fontSize: 16),
///   mode: TextResizeMode.autoHeight,
///   constraints: Size(200, double.infinity),
/// );
/// ```
library;

import 'package:flutter/painting.dart';

/// How a text node resizes to fit its content.
enum TextResizeMode {
  /// Fixed dimensions — text clips or overflows.
  fixed,

  /// Width adjusts to fit text, height is fixed.
  autoWidth,

  /// Height adjusts to fit text, width is fixed.
  autoHeight,

  /// Both width and height adjust to fit text.
  autoAll,
}

/// Computes text node dimensions based on resize mode.
class TextAutoResizeEngine {
  const TextAutoResizeEngine._();

  /// Compute the size a text node should have given its content and mode.
  ///
  /// [text] The text content.
  /// [style] The text style for rendering.
  /// [mode] How the text should resize.
  /// [constraints] Current size constraints (width for autoHeight,
  ///   height for autoWidth, both for fixed).
  /// [maxLines] Optional max lines limit.
  /// [textAlign] Text alignment.
  static Size computeSize({
    required String text,
    required TextStyle style,
    required TextResizeMode mode,
    required Size constraints,
    int? maxLines,
    TextAlign textAlign = TextAlign.left,
  }) {
    if (mode == TextResizeMode.fixed) return constraints;

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    );

    switch (mode) {
      case TextResizeMode.autoWidth:
        // Layout with infinite width, use natural width.
        painter.layout(minWidth: 0, maxWidth: double.infinity);
        return Size(
          painter.width,
          constraints.height.isFinite ? constraints.height : painter.height,
        );

      case TextResizeMode.autoHeight:
        // Layout with fixed width, use natural height.
        final maxWidth =
            constraints.width.isFinite ? constraints.width : double.infinity;
        painter.layout(minWidth: 0, maxWidth: maxWidth);
        return Size(constraints.width, painter.height);

      case TextResizeMode.autoAll:
        // Layout with infinite width for natural size.
        painter.layout(minWidth: 0, maxWidth: double.infinity);
        return Size(painter.width, painter.height);

      case TextResizeMode.fixed:
        return constraints;
    }
  }

  /// Compute the minimum size needed for text at a given width.
  static double computeMinHeight({
    required String text,
    required TextStyle style,
    required double width,
    int? maxLines,
    TextAlign textAlign = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    );
    painter.layout(minWidth: 0, maxWidth: width);
    return painter.height;
  }

  /// Compute the minimum width needed for text (single line).
  static double computeMinWidth({
    required String text,
    required TextStyle style,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    painter.layout(minWidth: 0, maxWidth: double.infinity);
    return painter.width;
  }

  /// Check if text overflows at given constraints.
  static bool isOverflowing({
    required String text,
    required TextStyle style,
    required Size constraints,
    int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    );
    painter.layout(minWidth: 0, maxWidth: constraints.width);
    return painter.didExceedMaxLines || painter.height > constraints.height;
  }
}
