import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../editing/adjustment_layer.dart';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';

/// Scene graph node that wraps an [AdjustmentStack] for non-destructive
/// color adjustments.
///
/// Unlike most leaf nodes, an `AdjustmentLayerNode` does not render geometry
/// directly. Instead, it provides compositing metadata. When the
/// [SceneGraphRenderer] encounters this node, it can apply the
/// [adjustmentStack] as a post-processing step to the content below.
///
/// ```dart
/// final adjustment = AdjustmentLayerNode(
///   id: NodeId('brightness-boost'),
///   stack: AdjustmentStack(layers: [
///     AdjustmentLayer(type: AdjustmentType.brightness, value: 0.15),
///   ]),
/// );
/// layerNode.add(adjustment);
/// ```
class AdjustmentLayerNode extends CanvasNode {
  /// The composable stack of non-destructive adjustments.
  AdjustmentStack adjustmentStack;

  AdjustmentLayerNode({
    required NodeId id,
    required this.adjustmentStack,
    String name = '',
    double opacity = 1.0,
    ui.BlendMode blendMode = ui.BlendMode.srcOver,
    bool isVisible = true,
  }) : super(
         id: id,
         name: name,
         opacity: opacity,
         blendMode: blendMode,
         isVisible: isVisible,
       );

  // ---------------------------------------------------------------------------
  // Bounds — adjustment layers have no geometry, so zero-size bounds.
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds => Rect.zero;

  @override
  int get contentFingerprint => adjustmentStack.hashCode;

  // ---------------------------------------------------------------------------
  // Visitor
  // ---------------------------------------------------------------------------

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitAdjustmentLayer(this);

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'adjustmentLayer';
    json['adjustmentStack'] = adjustmentStack.toJson();
    return json;
  }

  /// Reconstruct from JSON.
  factory AdjustmentLayerNode.fromJson(Map<String, dynamic> json) {
    final node = AdjustmentLayerNode(
      id: NodeId(json['id'] as String),
      adjustmentStack: AdjustmentStack.fromJson(
        json['adjustmentStack'] as List<dynamic>,
      ),
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }
}
