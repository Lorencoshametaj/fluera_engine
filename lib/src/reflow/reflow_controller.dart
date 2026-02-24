import 'dart:ui';
import './content_cluster.dart';
import './reflow_physics_engine.dart';
import '../core/nodes/group_node.dart';
import '../core/nodes/stroke_node.dart';

/// 🌊 Reflow Controller — tool-agnostic orchestrator for content reflow.
///
/// Manages the lifecycle of reflow physics during any drag operation:
/// 1. **Attach**: Set the engine + cluster cache
/// 2. **During drag**: Call [computeGhostDisplacements] each frame
/// 3. **At drag end**: Call [solveAndBake] to finalize positions
/// 4. **Cleanup**: Call [clearGhosts]
///
/// Usage:
/// ```dart
/// final controller = ReflowController(engine: reflowEngine);
/// controller.updateClusters(clusters);
///
/// // During drag:
/// controller.computeGhostDisplacements(
///   disturbance: selectionBounds,
///   excludeIds: selectedClusterIds,
/// );
///
/// // At drag end:
/// controller.solveAndBake(
///   disturbance: selectionBounds,
///   excludeIds: selectedClusterIds,
///   layerNode: activeLayerNode,
/// );
/// ```
class ReflowController {
  final ReflowPhysicsEngine engine;

  /// Cached content clusters for the current canvas state.
  List<ContentCluster> clusterCache;

  /// Current ghost displacements for preview rendering during drag.
  /// Sparse map: only affected cluster IDs appear.
  Map<String, Offset> ghostDisplacements = {};

  /// Whether reflow is active and enabled.
  bool get isEnabled => engine.config.enabled;

  ReflowController({required this.engine, List<ContentCluster>? clusters})
    : clusterCache = clusters ?? [];

  // ===========================================================================
  // Cluster Management
  // ===========================================================================

  /// Update the cluster cache (call when layer content changes).
  void updateClusters(List<ContentCluster> clusters) {
    clusterCache = clusters;
  }

  // ===========================================================================
  // Phase A: Ghost Displacement (during drag, every frame)
  // ===========================================================================

  /// Compute ghost displacements for preview rendering.
  ///
  /// Call this every frame during drag. O(k) where k = nearby clusters.
  /// [disturbance] is the bounding rect of the dragged element(s).
  /// [excludeIds] are the cluster IDs that contain the dragged elements
  /// (they shouldn't push themselves).
  void computeGhostDisplacements({
    required Rect disturbance,
    required Set<String> excludeIds,
  }) {
    ghostDisplacements = engine.estimateDisplacements(
      clusters: clusterCache,
      disturbance: disturbance,
      excludeIds: excludeIds,
    );
  }

  // ===========================================================================
  // Phase B: Solve & Bake (at drag end, once)
  // ===========================================================================

  /// Solve final displacements and bake them into node positions.
  ///
  /// Call once at drag end. Resolves secondary collisions (Phase B)
  /// and translates affected nodes in the scene graph.
  ///
  /// [layerNode] is the active layer's node, used to look up and
  /// translate the affected elements.
  void solveAndBake({
    required Rect disturbance,
    required Set<String> excludeIds,
    required GroupNode layerNode,
  }) {
    if (ghostDisplacements.isEmpty) return;

    final finalDisplacements = engine.solve(
      clusters: clusterCache,
      disturbance: disturbance,
      excludeIds: excludeIds,
    );

    if (finalDisplacements.isEmpty) return;

    // Collect all element IDs that need to move
    final affectedElementIds = <String, Offset>{};
    for (final entry in finalDisplacements.entries) {
      final cluster = clusterCache.firstWhere(
        (c) => c.id == entry.key,
        orElse:
            () => ContentCluster(
              id: '',
              strokeIds: const [],
              bounds: Rect.zero,
              centroid: Offset.zero,
            ),
      );
      if (cluster.id.isEmpty) continue;
      for (final id in cluster.strokeIds) {
        affectedElementIds[id] = entry.value;
      }
      for (final id in cluster.shapeIds) {
        affectedElementIds[id] = entry.value;
      }
      for (final id in cluster.textIds) {
        affectedElementIds[id] = entry.value;
      }
      for (final id in cluster.imageIds) {
        affectedElementIds[id] = entry.value;
      }
    }

    if (affectedElementIds.isEmpty) return;

    // Apply displacements: translate actual data, not just node transform.
    // For StrokeNodes, modify ProStroke points so bounds stay correct.
    for (final entry in affectedElementIds.entries) {
      final node = layerNode.findChild(entry.key);
      if (node == null || node.isLocked) continue;
      final delta = entry.value;

      if (node is StrokeNode) {
        // 🔑 Translate actual stroke points — keeps ProStroke.bounds accurate
        final old = node.stroke;
        final translatedPoints =
            old.points.map((p) {
              return p.copyWith(position: p.position + delta);
            }).toList();
        node.stroke = old.copyWith(points: translatedPoints);
      } else {
        // For shapes, text, images: node transform is fine
        node.translate(delta.dx, delta.dy);
      }
    }

    // 🔑 Update cluster cache bounds so subsequent drags use fresh positions
    for (final entry in finalDisplacements.entries) {
      final displacement = entry.value;
      if (displacement == Offset.zero) continue;
      for (final cluster in clusterCache) {
        if (cluster.id == entry.key) {
          cluster.bounds = cluster.bounds.shift(displacement);
          cluster.centroid = cluster.centroid + displacement;
          cluster.resetDisplacement();
          break;
        }
      }
    }
  }

  // ===========================================================================
  // Utilities
  // ===========================================================================

  /// Clear ghost displacements (call after drag end or cancel).
  void clearGhosts() {
    ghostDisplacements = {};
  }

  /// Get cluster IDs that contain any of the given element IDs.
  ///
  /// Use this to build the [excludeIds] set for [computeGhostDisplacements]
  /// and [solveAndBake]. The dragged elements' clusters should be excluded
  /// so they don't push themselves.
  Set<String> getClusterIdsForElements(Set<String> elementIds) {
    final ids = <String>{};
    for (final cluster in clusterCache) {
      for (final elementId in elementIds) {
        if (cluster.containsElement(elementId)) {
          ids.add(cluster.id);
          break;
        }
      }
    }
    return ids;
  }
}
