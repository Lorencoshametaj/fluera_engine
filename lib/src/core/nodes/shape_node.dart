import 'dart:ui';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_visitor.dart';
import '../models/shape_type.dart';
import '../effects/mesh_gradient.dart';

/// Scene graph node that wraps a [GeometricShape].
///
/// The shape's geometry (startPoint/endPoint) is stored in local coordinates.
/// The [localTransform] positions/rotates/scales the shape in parent space.
class ShapeNode extends CanvasNode {
  /// The actual shape data.
  GeometricShape shape;

  /// Optional mesh gradient fill (rendered instead of solid fill).
  MeshGradient? meshGradient;

  ShapeNode({
    required super.id,
    required this.shape,
    this.meshGradient,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  });

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds {
    final left =
        shape.startPoint.dx < shape.endPoint.dx
            ? shape.startPoint.dx
            : shape.endPoint.dx;
    final top =
        shape.startPoint.dy < shape.endPoint.dy
            ? shape.startPoint.dy
            : shape.endPoint.dy;
    final right =
        shape.startPoint.dx > shape.endPoint.dx
            ? shape.startPoint.dx
            : shape.endPoint.dx;
    final bottom =
        shape.startPoint.dy > shape.endPoint.dy
            ? shape.startPoint.dy
            : shape.endPoint.dy;

    // Add padding for stroke width
    final padding = shape.strokeWidth;
    return Rect.fromLTRB(
      left - padding,
      top - padding,
      right + padding,
      bottom + padding,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'shape';
    json['shape'] = shape.toJson();
    if (meshGradient != null) {
      json['meshGradient'] = meshGradient!.toJson();
    }
    return json;
  }

  factory ShapeNode.fromJson(Map<String, dynamic> json) {
    final node = ShapeNode(
      id: json['id'] as String,
      shape: GeometricShape.fromJson(json['shape'] as Map<String, dynamic>),
      meshGradient:
          json['meshGradient'] != null
              ? MeshGradient.fromJson(
                json['meshGradient'] as Map<String, dynamic>,
              )
              : null,
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitShape(this);

  @override
  String toString() => 'ShapeNode(id: $id, type: ${shape.type})';
}
