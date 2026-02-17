import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/effects/node_effect.dart';
import '../core/effects/gradient_fill.dart';

// ---------------------------------------------------------------------------
// Design Tokens
// ---------------------------------------------------------------------------

/// A named color in the design system.
class ColorToken {
  final String name;
  final Color value;
  final String? description;

  const ColorToken({required this.name, required this.value, this.description});

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value.toARGB32(),
    if (description != null) 'description': description,
  };

  factory ColorToken.fromJson(Map<String, dynamic> json) => ColorToken(
    name: json['name'] as String,
    value: Color(json['value'] as int),
    description: json['description'] as String?,
  );
}

/// A named text style token.
class TypographyToken {
  final String name;
  final String fontFamily;
  final double fontSize;
  final FontWeight fontWeight;
  final double? lineHeight;
  final double? letterSpacing;

  const TypographyToken({
    required this.name,
    required this.fontFamily,
    required this.fontSize,
    this.fontWeight = FontWeight.w400,
    this.lineHeight,
    this.letterSpacing,
  });

  TextStyle toTextStyle() => TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: lineHeight,
    letterSpacing: letterSpacing,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'fontWeight': fontWeight.index,
    if (lineHeight != null) 'lineHeight': lineHeight,
    if (letterSpacing != null) 'letterSpacing': letterSpacing,
  };

  factory TypographyToken.fromJson(Map<String, dynamic> json) =>
      TypographyToken(
        name: json['name'] as String,
        fontFamily: json['fontFamily'] as String,
        fontSize: (json['fontSize'] as num).toDouble(),
        fontWeight: FontWeight.values[json['fontWeight'] as int? ?? 3],
        lineHeight: (json['lineHeight'] as num?)?.toDouble(),
        letterSpacing: (json['letterSpacing'] as num?)?.toDouble(),
      );
}

/// A named spacing/size token.
class SpacingToken {
  final String name;
  final double value;

  const SpacingToken({required this.name, required this.value});

  Map<String, dynamic> toJson() => {'name': name, 'value': value};

  factory SpacingToken.fromJson(Map<String, dynamic> json) => SpacingToken(
    name: json['name'] as String,
    value: (json['value'] as num).toDouble(),
  );
}

// ---------------------------------------------------------------------------
// Style Definition
// ---------------------------------------------------------------------------

/// A reusable style that can be applied to multiple nodes.
///
/// When a style is updated, all nodes linked to it update automatically.
/// Styles can define any combination of fill, stroke, effects, and text style.
///
/// ```dart
/// final style = StyleDefinition(
///   id: 'primary-button',
///   name: 'Primary Button',
///   fillColor: Colors.blue,
///   strokeColor: Colors.blue.shade800,
///   cornerRadius: 12,
/// );
/// registry.register(style);
/// registry.applyStyle('primary-button', buttonNode);
/// ```
class StyleDefinition {
  final String id;
  String name;

  // Fill
  Color? fillColor;
  GradientFill? fillGradient;

  // Stroke
  Color? strokeColor;
  double? strokeWidth;
  ui.StrokeCap? strokeCap;
  ui.StrokeJoin? strokeJoin;

  // Effects
  List<NodeEffect>? effects;

  // Text
  TypographyToken? typography;

  // Shape
  double? cornerRadius;

  // Opacity & blend
  double? opacity;
  ui.BlendMode? blendMode;

  StyleDefinition({
    required this.id,
    this.name = '',
    this.fillColor,
    this.fillGradient,
    this.strokeColor,
    this.strokeWidth,
    this.strokeCap,
    this.strokeJoin,
    this.effects,
    this.typography,
    this.cornerRadius,
    this.opacity,
    this.blendMode,
  });

  /// Apply this style's properties to a node.
  ///
  /// Only non-null properties are applied, preserving
  /// the node's existing values for unset properties.
  void applyTo(CanvasNode node) {
    if (opacity != null) node.opacity = opacity!;
    if (blendMode != null) node.blendMode = blendMode!;
    if (effects != null && effects!.isNotEmpty) {
      node.effects =
          effects!.map((e) => NodeEffect.fromJson(e.toJson())).toList();
    }
  }

  /// Create a deep copy of this style.
  StyleDefinition clone() => StyleDefinition(
    id: id,
    name: name,
    fillColor: fillColor,
    fillGradient: fillGradient,
    strokeColor: strokeColor,
    strokeWidth: strokeWidth,
    strokeCap: strokeCap,
    strokeJoin: strokeJoin,
    effects: effects?.map((e) => NodeEffect.fromJson(e.toJson())).toList(),
    typography: typography,
    cornerRadius: cornerRadius,
    opacity: opacity,
    blendMode: blendMode,
  );

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'id': id, 'name': name};
    if (fillColor != null) json['fillColor'] = fillColor!.toARGB32();
    if (fillGradient != null) json['fillGradient'] = fillGradient!.toJson();
    if (strokeColor != null) json['strokeColor'] = strokeColor!.toARGB32();
    if (strokeWidth != null) json['strokeWidth'] = strokeWidth;
    if (strokeCap != null) json['strokeCap'] = strokeCap!.name;
    if (strokeJoin != null) json['strokeJoin'] = strokeJoin!.name;
    if (effects != null) {
      json['effects'] = effects!.map((e) => e.toJson()).toList();
    }
    if (typography != null) json['typography'] = typography!.toJson();
    if (cornerRadius != null) json['cornerRadius'] = cornerRadius;
    if (opacity != null) json['opacity'] = opacity;
    if (blendMode != null) json['blendMode'] = blendMode!.name;
    return json;
  }

  factory StyleDefinition.fromJson(Map<String, dynamic> json) {
    return StyleDefinition(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      fillColor:
          json['fillColor'] != null ? Color(json['fillColor'] as int) : null,
      fillGradient:
          json['fillGradient'] != null
              ? GradientFill.fromJson(
                json['fillGradient'] as Map<String, dynamic>,
              )
              : null,
      strokeColor:
          json['strokeColor'] != null
              ? Color(json['strokeColor'] as int)
              : null,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble(),
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble(),
      opacity: (json['opacity'] as num?)?.toDouble(),
      effects:
          json['effects'] != null
              ? (json['effects'] as List<dynamic>)
                  .map((e) => NodeEffect.fromJson(e as Map<String, dynamic>))
                  .toList()
              : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Style Registry
// ---------------------------------------------------------------------------

/// Central registry for styles and design tokens.
///
/// Maintains the mapping between styles and the nodes they're applied to.
/// When a style is updated, all linked nodes update automatically.
class StyleRegistry {
  /// All registered styles, keyed by ID.
  final Map<String, StyleDefinition> _styles = {};

  /// Map from style ID → set of node IDs using that style.
  final Map<String, Set<String>> _styleToNodes = {};

  /// Map from node ID → style ID applied to that node.
  final Map<String, String> _nodeToStyle = {};

  /// Design tokens.
  final List<ColorToken> colorPalette = [];
  final List<TypographyToken> typographyScale = [];
  final List<SpacingToken> spacingScale = [];

  /// Callback when styles change.
  void Function(String styleId)? onStyleChanged;

  // ---- Style CRUD ----

  /// Register a new style.
  void register(StyleDefinition style) {
    _styles[style.id] = style;
    _styleToNodes.putIfAbsent(style.id, () => {});
  }

  /// Get a style by ID.
  StyleDefinition? getStyle(String styleId) => _styles[styleId];

  /// All registered styles.
  List<StyleDefinition> get allStyles => _styles.values.toList();

  /// Remove a style. Detaches all linked nodes first.
  void removeStyle(String styleId) {
    final linkedNodes = _styleToNodes[styleId];
    if (linkedNodes != null) {
      for (final nodeId in linkedNodes.toList()) {
        _nodeToStyle.remove(nodeId);
      }
    }
    _styleToNodes.remove(styleId);
    _styles.remove(styleId);
  }

  /// Update a style and re-apply to all linked nodes.
  void updateStyle(
    String styleId,
    void Function(StyleDefinition style) updater,
    CanvasNode? Function(String nodeId) nodeResolver,
  ) {
    final style = _styles[styleId];
    if (style == null) return;

    updater(style);

    // Re-apply to all linked nodes.
    final linkedNodes = _styleToNodes[styleId];
    if (linkedNodes != null) {
      for (final nodeId in linkedNodes) {
        final node = nodeResolver(nodeId);
        if (node != null) style.applyTo(node);
      }
    }

    onStyleChanged?.call(styleId);
  }

  // ---- Linking ----

  /// Apply a style to a node and create a link.
  void applyStyle(String styleId, CanvasNode node) {
    final style = _styles[styleId];
    if (style == null) return;

    // Remove existing link if any.
    detachNode(node.id);

    // Create new link.
    _nodeToStyle[node.id] = styleId;
    _styleToNodes.putIfAbsent(styleId, () => {}).add(node.id);

    // Apply the style.
    style.applyTo(node);
  }

  /// Get the style linked to a node, if any.
  StyleDefinition? styleForNode(String nodeId) {
    final styleId = _nodeToStyle[nodeId];
    return styleId != null ? _styles[styleId] : null;
  }

  /// Check if a node has a linked style.
  bool hasStyle(String nodeId) => _nodeToStyle.containsKey(nodeId);

  /// Detach a node from its style (keep current values).
  void detachNode(String nodeId) {
    final styleId = _nodeToStyle.remove(nodeId);
    if (styleId != null) {
      _styleToNodes[styleId]?.remove(nodeId);
    }
  }

  /// Number of nodes using a specific style.
  int usageCount(String styleId) => _styleToNodes[styleId]?.length ?? 0;

  // ---- Serialization ----

  Map<String, dynamic> toJson() => {
    'styles': _styles.values.map((s) => s.toJson()).toList(),
    'links': _nodeToStyle,
    'colorPalette': colorPalette.map((c) => c.toJson()).toList(),
    'typographyScale': typographyScale.map((t) => t.toJson()).toList(),
    'spacingScale': spacingScale.map((s) => s.toJson()).toList(),
  };

  void loadFromJson(Map<String, dynamic> json) {
    _styles.clear();
    _styleToNodes.clear();
    _nodeToStyle.clear();

    final stylesJson = json['styles'] as List<dynamic>? ?? [];
    for (final s in stylesJson) {
      final style = StyleDefinition.fromJson(s as Map<String, dynamic>);
      _styles[style.id] = style;
    }

    final linksJson = json['links'] as Map<String, dynamic>? ?? {};
    for (final entry in linksJson.entries) {
      final nodeId = entry.key;
      final styleId = entry.value as String;
      _nodeToStyle[nodeId] = styleId;
      _styleToNodes.putIfAbsent(styleId, () => {}).add(nodeId);
    }

    colorPalette.clear();
    final colorsJson = json['colorPalette'] as List<dynamic>? ?? [];
    for (final c in colorsJson) {
      colorPalette.add(ColorToken.fromJson(c as Map<String, dynamic>));
    }

    typographyScale.clear();
    final typJson = json['typographyScale'] as List<dynamic>? ?? [];
    for (final t in typJson) {
      typographyScale.add(TypographyToken.fromJson(t as Map<String, dynamic>));
    }

    spacingScale.clear();
    final spacJson = json['spacingScale'] as List<dynamic>? ?? [];
    for (final s in spacJson) {
      spacingScale.add(SpacingToken.fromJson(s as Map<String, dynamic>));
    }
  }
}
