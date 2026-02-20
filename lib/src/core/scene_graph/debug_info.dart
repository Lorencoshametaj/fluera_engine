import 'package:flutter/foundation.dart';

import './canvas_node.dart';
import './scene_graph.dart';
import '../nodes/group_node.dart';

/// Diagnostic information about a [SceneGraph]'s structure.
///
/// Use this for debug overlays, performance profiling, and telemetry:
///
/// ```dart
/// final info = SceneGraphDebugInfo.collect(sceneGraph);
/// print(info); // SceneGraph: 142 nodes (max depth 5), 3 layers
/// debugPrint(info.toJson().toString());
/// ```
class SceneGraphDebugInfo {
  /// Total number of nodes (including root).
  final int totalNodes;

  /// Maximum nesting depth.
  final int maxDepth;

  /// Number of layers.
  final int layerCount;

  /// Node counts grouped by runtime type name.
  final Map<String, int> nodeCountByType;

  /// Number of nodes with at least one effect.
  final int nodesWithEffects;

  /// Total number of effects across all nodes.
  final int totalEffects;

  /// Number of currently dirty nodes.
  final int dirtyCount;

  SceneGraphDebugInfo._({
    required this.totalNodes,
    required this.maxDepth,
    required this.layerCount,
    required this.nodeCountByType,
    required this.nodesWithEffects,
    required this.totalEffects,
    required this.dirtyCount,
  });

  /// Collect debug info from a live scene graph.
  ///
  /// Returns `null` in release builds — the full tree-walk is
  /// tree-shaken by the compiler when [kDebugMode] is false.
  static SceneGraphDebugInfo? collect(SceneGraph graph) {
    if (!kDebugMode) return null;

    int totalNodes = 0;
    int maxDepth = 0;
    int nodesWithEffects = 0;
    int totalEffects = 0;
    final typeCounts = <String, int>{};

    void walk(CanvasNode node, int depth) {
      totalNodes++;
      if (depth > maxDepth) maxDepth = depth;

      final typeName = node.runtimeType.toString();
      typeCounts[typeName] = (typeCounts[typeName] ?? 0) + 1;

      if (node.effects.isNotEmpty) {
        nodesWithEffects++;
        totalEffects += node.effects.length;
      }

      if (node is GroupNode) {
        for (final child in node.children) {
          walk(child, depth + 1);
        }
      }
    }

    walk(graph.rootNode, 0);

    return SceneGraphDebugInfo._(
      totalNodes: totalNodes,
      maxDepth: maxDepth,
      layerCount: graph.layerCount,
      nodeCountByType: typeCounts,
      nodesWithEffects: nodesWithEffects,
      totalEffects: totalEffects,
      dirtyCount: graph.dirtyTracker.dirtyCount,
    );
  }

  /// Serialize for telemetry or logging.
  Map<String, dynamic> toJson() => {
    'totalNodes': totalNodes,
    'maxDepth': maxDepth,
    'layerCount': layerCount,
    'nodeCountByType': nodeCountByType,
    'nodesWithEffects': nodesWithEffects,
    'totalEffects': totalEffects,
    'dirtyCount': dirtyCount,
  };

  @override
  String toString() {
    final typeBreakdown = nodeCountByType.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
    return 'SceneGraph: $totalNodes nodes (max depth $maxDepth), '
        '$layerCount layers, $totalEffects effects '
        '[$typeBreakdown]';
  }
}
