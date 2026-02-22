/// 🔍 INSPECT ENGINE — Node inspection API for developer handoff.
///
/// Produces detailed inspection reports for any [CanvasNode], containing
/// all visual properties needed for design-to-code workflows.
library;

import 'dart:math' as math;
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart';

import '../../core/scene_graph/canvas_node.dart';
import '../../core/nodes/shape_node.dart';
import '../../core/nodes/path_node.dart';
import '../../core/nodes/text_node.dart';
import '../../core/nodes/rich_text_node.dart';
import '../../core/nodes/frame_node.dart';
import '../../core/effects/node_effect.dart';
import '../../core/effects/paint_stack.dart';
import '../../core/scene_graph/paint_stack_mixin.dart';
import '../style_system.dart';
import 'token_resolver.dart';

// =============================================================================
// INSPECT REPORT
// =============================================================================

/// Complete inspection report for a single node.
class InspectReport {
  final String nodeId;
  final String nodeName;
  final String nodeType;
  final Offset position;
  final Size size;
  final double rotation;
  final Rect worldBounds;
  final double opacity;
  final String blendMode;
  final List<InspectFill> fills;
  final InspectStroke? stroke;
  final double? cornerRadius;
  final List<InspectEffect> effects;
  final InspectTypography? typography;
  final InspectConstraint? constraint;
  final InspectFrameLayout? frameLayout;
  final String? linkedStyleName;
  final List<TokenReference> tokenReferences;

  const InspectReport({
    required this.nodeId,
    required this.nodeName,
    required this.nodeType,
    required this.position,
    required this.size,
    required this.rotation,
    required this.worldBounds,
    required this.opacity,
    required this.blendMode,
    required this.fills,
    this.stroke,
    this.cornerRadius,
    required this.effects,
    this.typography,
    this.constraint,
    this.frameLayout,
    this.linkedStyleName,
    required this.tokenReferences,
  });

  String get sizeLabel =>
      '${size.width.toStringAsFixed(0)} × ${size.height.toStringAsFixed(0)}';

  String get positionLabel =>
      '${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)}';

  Map<String, dynamic> toJson() => {
    'nodeId': nodeId,
    'nodeName': nodeName,
    'nodeType': nodeType,
    'position': {'x': position.dx, 'y': position.dy},
    'size': {'width': size.width, 'height': size.height},
    'rotation': rotation,
    'opacity': opacity,
    'blendMode': blendMode,
    'fills': fills.map((f) => f.toJson()).toList(),
    if (stroke != null) 'stroke': stroke!.toJson(),
    if (cornerRadius != null) 'cornerRadius': cornerRadius,
    'effects': effects.map((e) => e.toJson()).toList(),
    if (typography != null) 'typography': typography!.toJson(),
    if (constraint != null) 'constraint': constraint!.toJson(),
    if (frameLayout != null) 'frameLayout': frameLayout!.toJson(),
    if (linkedStyleName != null) 'linkedStyleName': linkedStyleName,
    'tokenReferences': tokenReferences.map((t) => t.toJson()).toList(),
  };
}

// =============================================================================
// INSPECT SUB-MODELS
// =============================================================================

class InspectFill {
  final Color? color;
  final String? gradientType;
  final List<Color>? gradientColors;

  const InspectFill({this.color, this.gradientType, this.gradientColors});
  String? get hexColor => color != null ? _colorToHex(color!) : null;

  Map<String, dynamic> toJson() => {
    if (color != null) 'color': _colorToHex(color!),
    if (gradientType != null) 'gradientType': gradientType,
    if (gradientColors != null)
      'gradientColors': gradientColors!.map(_colorToHex).toList(),
  };
}

class InspectStroke {
  final Color color;
  final double width;
  const InspectStroke({required this.color, required this.width});
  String get hexColor => _colorToHex(color);
  Map<String, dynamic> toJson() => {
    'color': _colorToHex(color),
    'width': width,
  };
}

class InspectEffect {
  final String type;
  final Map<String, dynamic> parameters;
  const InspectEffect({required this.type, required this.parameters});
  Map<String, dynamic> toJson() => {'type': type, ...parameters};
}

class InspectTypography {
  final String? fontFamily;
  final double? fontSize;
  final String? fontWeight;
  final double? lineHeight;
  final double? letterSpacing;
  final Color? color;

  const InspectTypography({
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.letterSpacing,
    this.color,
  });

  Map<String, dynamic> toJson() => {
    if (fontFamily != null) 'fontFamily': fontFamily,
    if (fontSize != null) 'fontSize': fontSize,
    if (fontWeight != null) 'fontWeight': fontWeight,
    if (lineHeight != null) 'lineHeight': lineHeight,
    if (letterSpacing != null) 'letterSpacing': letterSpacing,
    if (color != null) 'color': _colorToHex(color!),
  };
}

class InspectConstraint {
  final String primarySizing;
  final String crossSizing;
  final bool pinLeft, pinRight, pinTop, pinBottom;
  final double? minWidth, maxWidth, minHeight, maxHeight;

  const InspectConstraint({
    required this.primarySizing,
    required this.crossSizing,
    required this.pinLeft,
    required this.pinRight,
    required this.pinTop,
    required this.pinBottom,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
  });

  Map<String, dynamic> toJson() => {
    'primarySizing': primarySizing,
    'crossSizing': crossSizing,
    'pinLeft': pinLeft,
    'pinRight': pinRight,
    'pinTop': pinTop,
    'pinBottom': pinBottom,
    if (minWidth != null && minWidth! > 0) 'minWidth': minWidth,
    if (maxWidth != null && maxWidth != double.infinity) 'maxWidth': maxWidth,
    if (minHeight != null && minHeight! > 0) 'minHeight': minHeight,
    if (maxHeight != null && maxHeight != double.infinity)
      'maxHeight': maxHeight,
  };
}

class InspectFrameLayout {
  final String direction;
  final double spacing;
  final String mainAxisAlignment;
  final String crossAxisAlignment;
  final String padding;

  const InspectFrameLayout({
    required this.direction,
    required this.spacing,
    required this.mainAxisAlignment,
    required this.crossAxisAlignment,
    required this.padding,
  });

  Map<String, dynamic> toJson() => {
    'direction': direction,
    'spacing': spacing,
    'mainAxisAlignment': mainAxisAlignment,
    'crossAxisAlignment': crossAxisAlignment,
    'padding': padding,
  };
}

// =============================================================================
// SPACING MEASUREMENT
// =============================================================================

class SpacingMeasurement {
  final double horizontal;
  final double vertical;
  final Rect boundsA;
  final Rect boundsB;

  const SpacingMeasurement({
    required this.horizontal,
    required this.vertical,
    required this.boundsA,
    required this.boundsB,
  });

  bool get isOverlapping => horizontal == 0 && vertical == 0;

  Map<String, dynamic> toJson() => {
    'horizontal': horizontal,
    'vertical': vertical,
  };
}

// =============================================================================
// INSPECT ENGINE
// =============================================================================

class InspectEngine {
  final StyleRegistry? styleRegistry;
  final TokenResolver? tokenResolver;

  const InspectEngine({this.styleRegistry, this.tokenResolver});

  InspectReport inspect(CanvasNode node) {
    final bounds = node.localBounds;
    final worldBounds = node.worldBounds;
    final rotation = _extractRotation(node.localTransform);

    return InspectReport(
      nodeId: node.id.value,
      nodeName: node.name,
      nodeType: node.runtimeType.toString(),
      position: Offset(bounds.left, bounds.top),
      size: Size(bounds.width, bounds.height),
      rotation: rotation,
      worldBounds: worldBounds,
      opacity: node.opacity,
      blendMode: node.blendMode.name,
      fills: _extractFills(node),
      stroke: _extractStroke(node),
      cornerRadius: _extractCornerRadius(node),
      effects: _extractEffects(node),
      typography: _extractTypography(node),
      constraint: _extractConstraint(node),
      frameLayout: _extractFrameLayout(node),
      linkedStyleName: _resolveLinkedStyle(node),
      tokenReferences: _resolveTokens(node),
    );
  }

  SpacingMeasurement measureBetween(CanvasNode a, CanvasNode b) {
    final boundsA = a.worldBounds;
    final boundsB = b.worldBounds;
    return SpacingMeasurement(
      horizontal: _horizontalSpacing(boundsA, boundsB),
      vertical: _verticalSpacing(boundsA, boundsB),
      boundsA: boundsA,
      boundsB: boundsB,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  double _extractRotation(Matrix4 transform) {
    final storage = transform.storage;
    return math.atan2(storage[1], storage[0]) * 180 / math.pi;
  }

  List<InspectFill> _extractFills(CanvasNode node) {
    final fills = <InspectFill>[];

    // PaintStack fills (ShapeNode, PathNode, etc.).
    if (node is PaintStackMixin) {
      for (final fill in node.fills) {
        if (fill.gradient != null) {
          fills.add(
            InspectFill(
              gradientType: fill.gradient!.type.name,
              gradientColors: fill.gradient!.colors,
            ),
          );
        } else {
          fills.add(InspectFill(color: fill.color));
        }
      }
    }

    // FrameNode fill color (not through PaintStackMixin).
    if (node is FrameNode && node.fillColor != null) {
      fills.add(InspectFill(color: node.fillColor));
    }

    return fills;
  }

  InspectStroke? _extractStroke(CanvasNode node) {
    // PaintStack strokes.
    if (node is PaintStackMixin && node.strokes.isNotEmpty) {
      final first = node.strokes.first;
      return InspectStroke(
        color: first.color ?? const Color(0xFF000000),
        width: first.width,
      );
    }
    if (node is FrameNode && node.strokeColor != null) {
      return InspectStroke(color: node.strokeColor!, width: node.strokeWidth);
    }
    return null;
  }

  double? _extractCornerRadius(CanvasNode node) {
    if (node is FrameNode) return node.borderRadius;
    return null;
  }

  List<InspectEffect> _extractEffects(CanvasNode node) {
    return node.effects.map((e) {
      final params = <String, dynamic>{};
      if (e is BlurEffect) {
        params['sigmaX'] = e.sigmaX;
        params['sigmaY'] = e.sigmaY;
      } else if (e is DropShadowEffect) {
        params['color'] = _colorToHex(e.color);
        params['offset'] = {'dx': e.offset.dx, 'dy': e.offset.dy};
        params['blur'] = e.blurRadius;
        params['spread'] = e.spread;
      } else if (e is InnerShadowEffect) {
        params['color'] = _colorToHex(e.color);
        params['offset'] = {'dx': e.offset.dx, 'dy': e.offset.dy};
        params['blur'] = e.blurRadius;
      } else if (e is OuterGlowEffect) {
        params['color'] = _colorToHex(e.color);
        params['blurRadius'] = e.blurRadius;
      } else if (e is ColorOverlayEffect) {
        params['color'] = _colorToHex(e.color);
        params['blendMode'] = e.blendMode.name;
      }
      return InspectEffect(type: e.runtimeType.toString(), parameters: params);
    }).toList();
  }

  InspectTypography? _extractTypography(CanvasNode node) {
    if (node is TextNode) {
      final te = node.textElement;
      return InspectTypography(
        fontFamily: te.fontFamily,
        fontSize: te.fontSize,
        color: te.color,
      );
    }
    if (node is RichTextNode && node.spans.isNotEmpty) {
      final first = node.spans.first;
      return InspectTypography(
        fontFamily: first.fontFamily,
        fontSize: first.fontSize,
        fontWeight: first.fontWeight.toString(),
        letterSpacing: first.letterSpacing,
        color: first.color,
      );
    }
    return null;
  }

  InspectConstraint? _extractConstraint(CanvasNode node) {
    final parent = node.parent;
    if (parent is FrameNode) {
      final c = parent.constraintFor(node.id.value);
      return InspectConstraint(
        primarySizing: c.primarySizing.name,
        crossSizing: c.crossSizing.name,
        pinLeft: c.pinLeft,
        pinRight: c.pinRight,
        pinTop: c.pinTop,
        pinBottom: c.pinBottom,
        minWidth: c.minWidth,
        maxWidth: c.maxWidth,
        minHeight: c.minHeight,
        maxHeight: c.maxHeight,
      );
    }
    return null;
  }

  InspectFrameLayout? _extractFrameLayout(CanvasNode node) {
    if (node is FrameNode) {
      return InspectFrameLayout(
        direction: node.direction.name,
        spacing: node.spacing,
        mainAxisAlignment: node.mainAxisAlignment.name,
        crossAxisAlignment: node.crossAxisAlignment.name,
        padding:
            'T:${node.padding.top} R:${node.padding.right} '
            'B:${node.padding.bottom} L:${node.padding.left}',
      );
    }
    return null;
  }

  String? _resolveLinkedStyle(CanvasNode node) {
    if (styleRegistry == null) return null;
    final styleDef = styleRegistry!.styleForNode(node.id.value);
    return styleDef?.name;
  }

  List<TokenReference> _resolveTokens(CanvasNode node) {
    if (tokenResolver == null) return [];
    return tokenResolver!.resolveAll(node);
  }

  double _horizontalSpacing(Rect a, Rect b) {
    if (a.right <= b.left) return b.left - a.right;
    if (b.right <= a.left) return a.left - b.right;
    return 0;
  }

  double _verticalSpacing(Rect a, Rect b) {
    if (a.bottom <= b.top) return b.top - a.bottom;
    if (b.bottom <= a.top) return a.top - b.bottom;
    return 0;
  }
}

// =============================================================================
// HELPERS
// =============================================================================

String _colorToHex(Color color) {
  final r = (color.r * 255.0)
      .round()
      .clamp(0, 255)
      .toRadixString(16)
      .padLeft(2, '0');
  final g = (color.g * 255.0)
      .round()
      .clamp(0, 255)
      .toRadixString(16)
      .padLeft(2, '0');
  final b = (color.b * 255.0)
      .round()
      .clamp(0, 255)
      .toRadixString(16)
      .padLeft(2, '0');
  final a = (color.a * 255.0).round().clamp(0, 255);
  if (a == 255) return '#$r$g$b'.toUpperCase();
  final ah = a.toRadixString(16).padLeft(2, '0');
  return '#$r$g$b$ah'.toUpperCase();
}
