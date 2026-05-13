import '../core/scene_graph/canvas_node.dart';
import '../core/scene_graph/scene_graph_observer.dart';
import 'scene_graph_crdt.dart';

// =============================================================================
// 🔌 CRDT SCENE GRAPH OBSERVER
//
// Bridges the scene graph mutation pipeline to the CRDT layer. Register one
// instance per [SceneGraph] via `sceneGraph.addObserver(observer)` and every
// add / remove / property change automatically produces a [CRDTOperation]
// that can be persisted, broadcast, and merged on remote peers.
//
// Single point of capture: covers brush commits, AI atlas mutations, undo/redo
// — anything that ultimately mutates the scene graph routes through here.
//
// What this class does NOT do (yet):
//   • Does not subscribe to a transport. Pass [onLocalOperation] to broadcast.
//   • Does not handle reorder (event has no nodeId). Wired separately when
//     T0.2 step 2 lands the broadcast/receive refactor.
//   • Does not detect reverting-to-default property values that disappear from
//     `node.toJson()` due to compact-JSON encoding. Caller passes [readProperty]
//     to override extraction; otherwise the change is dropped silently.
// =============================================================================

/// Bridges [SceneGraph] mutations into a [CRDTSceneGraph].
///
/// ```dart
/// final crdt = CRDTSceneGraph(localPeerId: deviceId);
/// final observer = CRDTSceneGraphObserver(
///   crdt,
///   onLocalOperation: (op) => realtimeAdapter.broadcast(canvasId, op),
/// );
/// sceneGraph.addObserver(observer);
/// ```
class CRDTSceneGraphObserver implements SceneGraphObserver {
  /// Target CRDT graph kept in sync with the local scene graph.
  final CRDTSceneGraph crdt;

  /// Invoked for every operation generated locally — the host wires this to
  /// the realtime adapter for broadcast and to the persistent op-log.
  final void Function(CRDTOperation op)? onLocalOperation;

  /// Optional override for reading a single property value from a node.
  ///
  /// Default implementation derives values from `node.toJson()`. That misses
  /// fields that compact serialization elides (e.g. opacity=1.0). Pass a
  /// custom resolver when you need full coverage.
  final Object? Function(CanvasNode node, String property)? readProperty;

  CRDTSceneGraphObserver(
    this.crdt, {
    this.onLocalOperation,
    this.readProperty,
  });

  @override
  void onNodeAdded(CanvasNode node, String parentId) {
    final op = crdt.addNode(
      nodeId: node.id.value,
      nodeType: node.runtimeType.toString(),
      parentId: parentId,
      properties: _initialProperties(node),
    );
    onLocalOperation?.call(op);
  }

  @override
  void onNodeRemoved(CanvasNode node, String parentId) {
    final op = crdt.removeNode(node.id.value);
    onLocalOperation?.call(op);
  }

  @override
  void onNodeChanged(CanvasNode node, String property) {
    final value = _readProperty(node, property);
    if (value == null) {
      // Compact-JSON serialization may omit default values. Skip silently;
      // a custom [readProperty] resolver can reach the actual field.
      return;
    }
    final op = crdt.setProperty(node.id.value, property, value);
    onLocalOperation?.call(op);
  }

  @override
  void onNodeReordered(String parentId, int oldIndex, int newIndex) {
    // SceneGraphObserver doesn't carry a nodeId for reorders — bridging this
    // to crdt.moveNode requires looking up the moved node from the SceneGraph
    // by parent + index. Wired in T0.2 step 2 (broadcast/receive refactor).
  }

  Map<String, dynamic> _initialProperties(CanvasNode node) {
    try {
      final json = Map<String, dynamic>.from(node.toJson());
      // Strip fields the CRDT layer manages explicitly so we don't mirror
      // them as LWW properties (would diverge from the dedicated registers).
      json.remove('id');
      json.remove('children');
      return json;
    } catch (_) {
      return const {};
    }
  }

  Object? _readProperty(CanvasNode node, String property) {
    final resolver = readProperty;
    if (resolver != null) {
      return resolver(node, property);
    }
    try {
      final json = node.toJson();
      return json[property];
    } catch (_) {
      return null;
    }
  }
}
