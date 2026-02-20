import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import '../effects/gradient_fill.dart';
import '../vector/vector_path.dart';

/// A single styled run of text within a [RichTextNode].
///
/// Multiple spans compose the full text content, each with its own
/// styling (font, size, weight, color, decorations, etc.).
class RichTextSpan {
  String text;
  String fontFamily;
  double fontSize;
  FontWeight fontWeight;
  FontStyle fontStyle;
  Color color;
  TextDecoration decoration;
  Color? decorationColor;
  double? letterSpacing;
  double? wordSpacing;
  Color? backgroundColor;

  RichTextSpan({
    required this.text,
    this.fontFamily = 'Roboto',
    this.fontSize = 24.0,
    this.fontWeight = FontWeight.normal,
    this.fontStyle = FontStyle.normal,
    this.color = const Color(0xFF000000),
    this.decoration = TextDecoration.none,
    this.decorationColor,
    this.letterSpacing,
    this.wordSpacing,
    this.backgroundColor,
  });

  /// Convert to Flutter [TextSpan] for TextPainter.
  TextSpan toTextSpan() {
    return TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        color: color,
        decoration: decoration,
        decorationColor: decorationColor,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
        backgroundColor: backgroundColor,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'text': text,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'fontWeight': fontWeight.index,
      'color': color.toARGB32(),
    };

    if (fontStyle != FontStyle.normal) json['fontStyle'] = fontStyle.name;
    if (decoration != TextDecoration.none) {
      json['decoration'] = _decorationToString(decoration);
    }
    if (decorationColor != null) {
      json['decorationColor'] = decorationColor!.toARGB32();
    }
    if (letterSpacing != null) json['letterSpacing'] = letterSpacing;
    if (wordSpacing != null) json['wordSpacing'] = wordSpacing;
    if (backgroundColor != null) {
      json['backgroundColor'] = backgroundColor!.toARGB32();
    }

    return json;
  }

  factory RichTextSpan.fromJson(Map<String, dynamic> json) {
    return RichTextSpan(
      text: json['text'] as String,
      fontFamily: json['fontFamily'] as String? ?? 'Roboto',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 24.0,
      fontWeight: FontWeight.values[json['fontWeight'] as int? ?? 3],
      fontStyle:
          json['fontStyle'] != null
              ? FontStyle.values.firstWhere(
                (s) => s.name == json['fontStyle'],
                orElse: () => FontStyle.normal,
              )
              : FontStyle.normal,
      color: Color((json['color'] as int?)?.toUnsigned(32) ?? 0xFF000000),
      decoration:
          json['decoration'] != null
              ? _decorationFromString(json['decoration'] as String)
              : TextDecoration.none,
      decorationColor:
          json['decorationColor'] != null
              ? Color((json['decorationColor'] as int).toUnsigned(32))
              : null,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble(),
      wordSpacing: (json['wordSpacing'] as num?)?.toDouble(),
      backgroundColor:
          json['backgroundColor'] != null
              ? Color((json['backgroundColor'] as int).toUnsigned(32))
              : null,
    );
  }

  static String _decorationToString(TextDecoration d) {
    if (d == TextDecoration.underline) return 'underline';
    if (d == TextDecoration.lineThrough) return 'lineThrough';
    if (d == TextDecoration.overline) return 'overline';
    return 'none';
  }

  static TextDecoration _decorationFromString(String s) {
    switch (s) {
      case 'underline':
        return TextDecoration.underline;
      case 'lineThrough':
        return TextDecoration.lineThrough;
      case 'overline':
        return TextDecoration.overline;
      default:
        return TextDecoration.none;
    }
  }
}

// ---------------------------------------------------------------------------
// RichTextNode
// ---------------------------------------------------------------------------

/// Scene graph node for multi-span rich text with paragraph formatting.
///
/// Unlike [TextNode] which wraps a simple single-style [DigitalTextElement],
/// `RichTextNode` supports:
/// - Multiple independently styled text runs ([spans])
/// - Paragraph-level formatting (alignment, line height, letter spacing)
/// - Auto-width or fixed-size text box with wrapping
/// - Text on path (optional, requires Phase 3 VectorPath)
///
/// ```
/// RichTextNode
///   spans: [
///     RichTextSpan("Hello ", bold, black),
///     RichTextSpan("World", italic, red),
///   ]
///   textAlign: TextAlign.center
///   lineHeight: 1.5
/// ```
class RichTextNode extends CanvasNode {
  /// Styled text runs composing the full content.
  List<RichTextSpan> spans;

  /// Paragraph alignment.
  TextAlign textAlign;

  /// Line height multiplier (e.g. 1.5 = 150%).
  double lineHeight;

  /// Extra letter spacing applied globally.
  double letterSpacing;

  /// Extra spacing between paragraphs (newlines).
  double paragraphSpacing;

  /// If true, the text box grows horizontally to fit content.
  /// If false, text wraps within [fixedSize].
  bool autoWidth;

  /// Fixed dimensions for the text box (used when [autoWidth] is false).
  /// Text wraps within this width; height may overflow or be clipped.
  Size? fixedSize;

  /// Optional path for text-on-path layout (from Phase 3).
  VectorPath? textPath;

  /// Fill for the text background box (optional).
  Color? boxFillColor;
  GradientFill? boxFillGradient;

  /// Cached laid-out size (updated by renderer).
  Size _cachedSize = Size.zero;

  RichTextNode({
    required super.id,
    required this.spans,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    this.textAlign = TextAlign.left,
    this.lineHeight = 1.2,
    this.letterSpacing = 0.0,
    this.paragraphSpacing = 0.0,
    this.autoWidth = true,
    this.fixedSize,
    this.textPath,
    this.boxFillColor,
    this.boxFillGradient,
  });

  set cachedSize(Size size) => _cachedSize = size;
  Size get cachedSize => _cachedSize;

  /// The full plain text (all spans concatenated).
  String get plainText => spans.map((s) => s.text).join();

  /// Build a Flutter [TextSpan] tree from all spans.
  TextSpan toTextSpan() {
    return TextSpan(children: spans.map((s) => s.toTextSpan()).toList());
  }

  @override
  ui.Rect get localBounds {
    final w =
        fixedSize?.width ?? (_cachedSize.width > 0 ? _cachedSize.width : 200.0);
    final h =
        fixedSize?.height ??
        (_cachedSize.height > 0 ? _cachedSize.height : 40.0);
    return ui.Rect.fromLTWH(0, 0, w, h);
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'richText';
    json['spans'] = spans.map((s) => s.toJson()).toList();
    json['textAlign'] = textAlign.name;
    json['lineHeight'] = lineHeight;

    if (letterSpacing != 0.0) json['letterSpacing'] = letterSpacing;
    if (paragraphSpacing != 0.0) json['paragraphSpacing'] = paragraphSpacing;
    if (!autoWidth) json['autoWidth'] = false;
    if (fixedSize != null) {
      json['fixedWidth'] = fixedSize!.width;
      json['fixedHeight'] = fixedSize!.height;
    }
    if (textPath != null) json['textPath'] = textPath!.toJson();
    if (boxFillColor != null) json['boxFillColor'] = boxFillColor!.toARGB32();
    if (boxFillGradient != null) {
      json['boxFillGradient'] = boxFillGradient!.toJson();
    }

    return json;
  }

  factory RichTextNode.fromJson(Map<String, dynamic> json) {
    final spanList =
        (json['spans'] as List<dynamic>)
            .map((s) => RichTextSpan.fromJson(s as Map<String, dynamic>))
            .toList();

    final node = RichTextNode(
      id: NodeId(json['id'] as String),
      spans: spanList,
      textAlign: TextAlign.values.firstWhere(
        (a) => a.name == json['textAlign'],
        orElse: () => TextAlign.left,
      ),
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.2,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0.0,
      paragraphSpacing: (json['paragraphSpacing'] as num?)?.toDouble() ?? 0.0,
      autoWidth: json['autoWidth'] as bool? ?? true,
      fixedSize:
          json['fixedWidth'] != null
              ? Size(
                (json['fixedWidth'] as num).toDouble(),
                (json['fixedHeight'] as num).toDouble(),
              )
              : null,
      textPath:
          json['textPath'] != null
              ? VectorPath.fromJson(json['textPath'] as Map<String, dynamic>)
              : null,
      boxFillColor:
          json['boxFillColor'] != null
              ? Color((json['boxFillColor'] as int).toUnsigned(32))
              : null,
      boxFillGradient:
          json['boxFillGradient'] != null
              ? GradientFill.fromJson(
                json['boxFillGradient'] as Map<String, dynamic>,
              )
              : null,
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitRichText(this);
}
