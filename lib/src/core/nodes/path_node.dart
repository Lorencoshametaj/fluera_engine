import 'dart:ui' as ui;
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_visitor.dart';
import '../vector/vector_path.dart';
import '../effects/gradient_fill.dart';

/// Scene graph node that wraps a [VectorPath] for rendering.
///
/// Supports independent fill and stroke with optional gradients.
/// This is the vector-editing equivalent of [ShapeNode], but with
/// full Bézier path control instead of fixed shape types.
///
/// ```
/// PathNode (star)
///   path: VectorPath (5-point star Bézier)
///   fillColor: Colors.gold
///   strokeColor: Colors.black
///   strokeWidth: 2.0
/// ```
class PathNode extends CanvasNode {
  VectorPath path;

  /// Fill properties (null = no fill).
  ui.Color? fillColor;
  GradientFill? fillGradient;

  /// Stroke properties (null strokeColor = no stroke).
  ui.Color? strokeColor;
  GradientFill? strokeGradient;
  double strokeWidth;

  /// Stroke cap and join styles.
  ui.StrokeCap strokeCap;
  ui.StrokeJoin strokeJoin;

  PathNode({
    required super.id,
    required this.path,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    this.fillColor,
    this.fillGradient,
    this.strokeColor,
    this.strokeGradient,
    this.strokeWidth = 2.0,
    this.strokeCap = ui.StrokeCap.round,
    this.strokeJoin = ui.StrokeJoin.round,
  });

  @override
  ui.Rect get localBounds {
    final pathBounds = path.computeBounds();
    if (pathBounds.isEmpty) return ui.Rect.zero;
    // Inflate by half stroke width so the stroke doesn't clip.
    return pathBounds.inflate(strokeWidth / 2);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'path';
    json['path'] = path.toJson();
    json['strokeWidth'] = strokeWidth;
    json['strokeCap'] = strokeCap.index;
    json['strokeJoin'] = strokeJoin.index;

    if (fillColor != null) json['fillColor'] = fillColor!.toARGB32();
    if (fillGradient != null) json['fillGradient'] = fillGradient!.toJson();
    if (strokeColor != null) json['strokeColor'] = strokeColor!.toARGB32();
    if (strokeGradient != null) {
      json['strokeGradient'] = strokeGradient!.toJson();
    }

    return json;
  }

  factory PathNode.fromJson(Map<String, dynamic> json) {
    final node = PathNode(
      id: json['id'] as String,
      path: VectorPath.fromJson(json['path'] as Map<String, dynamic>),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      strokeCap:
          json['strokeCap'] != null
              ? ui.StrokeCap.values[json['strokeCap'] as int]
              : ui.StrokeCap.round,
      strokeJoin:
          json['strokeJoin'] != null
              ? ui.StrokeJoin.values[json['strokeJoin'] as int]
              : ui.StrokeJoin.round,
      fillColor:
          json['fillColor'] != null
              ? ui.Color((json['fillColor'] as int).toUnsigned(32))
              : null,
      fillGradient:
          json['fillGradient'] != null
              ? GradientFill.fromJson(
                json['fillGradient'] as Map<String, dynamic>,
              )
              : null,
      strokeColor:
          json['strokeColor'] != null
              ? ui.Color((json['strokeColor'] as int).toUnsigned(32))
              : null,
      strokeGradient:
          json['strokeGradient'] != null
              ? GradientFill.fromJson(
                json['strokeGradient'] as Map<String, dynamic>,
              )
              : null,
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitPath(this);
}
