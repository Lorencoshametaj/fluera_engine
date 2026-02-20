import 'dart:ui';
import '../nodes/group_node.dart';
import '../nodes/layer_node.dart';
import './canvas_node.dart';
import './scene_graph_snapshot.dart';

/// Read-only view of a [SceneGraph].
///
/// Exposes query-only methods, preventing plugins and renderers from
/// accidentally mutating the scene graph. Use this interface when
/// handing graph access to external consumers (plugin API, exporters).
///
/// ```dart
/// void renderScene(ReadOnlySceneGraph graph) {
///   for (final layer in graph.layers) {
///     // safe — no mutation methods available
///   }
/// }
/// ```
abstract class ReadOnlySceneGraph {
  /// The root group node of the tree.
  GroupNode get rootNode;

  /// All layers in the scene graph.
  List<LayerNode> get layers;

  /// Number of layers.
  int get layerCount;

  /// Look up a node by ID. Returns `null` if not found.
  CanvasNode? findNodeById(String nodeId);

  /// Whether the tree contains a node with [nodeId].
  bool containsNode(String nodeId);

  /// All nodes whose world bounds intersect [viewport].
  List<CanvasNode> nodesInBounds(Rect viewport);

  /// Hit test at a world-space point. Returns the topmost hit node.
  CanvasNode? hitTestAt(Offset worldPoint);

  /// All nodes in the tree (depth-first).
  Iterable<CanvasNode> get allNodes;

  /// Total number of leaf nodes (non-group nodes).
  int get totalElementCount;

  /// Monotonically increasing version counter.
  int get version;

  /// Serialize the graph to JSON.
  Map<String, dynamic> toJson();

  /// Capture a lightweight structural snapshot.
  SceneGraphSnapshot snapshot();
}
