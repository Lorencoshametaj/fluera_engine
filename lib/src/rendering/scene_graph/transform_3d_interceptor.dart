/// 🎲 TRANSFORM 3D INTERCEPTOR — Applies 3D transforms in the render pipeline.
///
/// A [RenderInterceptor] that checks if a node has a [Transform3D] attached
/// and applies the 3D matrix before rendering.
///
/// Nodes opt-in by being registered in the interceptor's transform map.
///
/// ```dart
/// final interceptor = Transform3DInterceptor();
/// interceptor.setTransform(myNode.id, Transform3D(rotateY: 15, perspective: 800));
/// sceneGraphRenderer.addInterceptor(interceptor);
/// ```
library;

import 'package:flutter/material.dart';
import '../../core/scene_graph/canvas_node.dart';
import '../../core/scene_graph/node_id.dart';
import './render_interceptor.dart';
import '../../core/transforms/transform_3d.dart';

/// Render interceptor that applies [Transform3D] to registered nodes.
///
/// Uses a per-node transform map to avoid modifying CanvasNode itself.
class Transform3DInterceptor extends RenderInterceptor {
  /// Map of node ID → 3D transform.
  final Map<String, Transform3D> _transforms = {};

  /// Assign a 3D transform to a node by ID.
  void setTransform(NodeId nodeId, Transform3D transform) {
    if (transform.isIdentity) {
      _transforms.remove(nodeId.value);
    } else {
      _transforms[nodeId.value] = transform;
    }
  }

  /// Remove the 3D transform for a node.
  void removeTransform(NodeId nodeId) => _transforms.remove(nodeId.value);

  /// Clear all transforms.
  void clearAll() => _transforms.clear();

  /// Check if a node has a 3D transform.
  bool hasTransform(NodeId nodeId) => _transforms.containsKey(nodeId.value);

  /// Get the transform for a node (if any).
  Transform3D? getTransform(NodeId nodeId) => _transforms[nodeId.value];

  @override
  void intercept(
    Canvas canvas,
    CanvasNode node,
    Rect viewport,
    RenderNext next,
  ) {
    final t3d = _transforms[node.id.value];
    if (t3d == null || t3d.isIdentity) {
      next(canvas, node, viewport);
      return;
    }

    // Get node dimensions for origin calculation.
    final bounds = node.localBounds;
    final matrix = t3d.toMatrix4(
      nodeWidth: bounds.width,
      nodeHeight: bounds.height,
    );

    canvas.save();
    canvas.transform(matrix.storage);
    next(canvas, node, viewport);
    canvas.restore();
  }
}
