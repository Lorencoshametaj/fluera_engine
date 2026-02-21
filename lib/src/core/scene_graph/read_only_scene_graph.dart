import 'dart:ui';
import './frozen_node_view.dart';
import './scene_graph_snapshot.dart';
import './node_id.dart';
import './scene_graph.dart';

/// Read-only view of a [SceneGraph].
///
/// Exposes query-only methods, preventing plugins and renderers from
/// accidentally mutating the scene graph. Use this interface when
/// handing graph access to external consumers (plugin API, exporters).
abstract class ReadOnlySceneGraph {
  FrozenNodeView get rootNode;
  List<FrozenNodeView> get layers;
  int get layerCount;
  FrozenNodeView? findNodeById(NodeId nodeId);
  bool containsNode(NodeId nodeId);
  List<FrozenNodeView> nodesInBounds(Rect viewport);
  FrozenNodeView? hitTestAt(Offset worldPoint);
  Iterable<FrozenNodeView> get allNodes;
  int get totalElementCount;
  int get version;
  Map<String, dynamic> toJson();
  SceneGraphSnapshot snapshot();
}

/// Read-consistent, epoch-guarded view of a [SceneGraph].
///
/// Ensures that asynchronous consumers do not read a torn state if the
/// scene graph mutates mid-operation. If the underlying `SceneGraph`'s
/// version increments after this view is created, any read triggers a `StateError`.
class ReadConsistentView implements ReadOnlySceneGraph {
  final SceneGraph _graph;
  final int _epoch;

  ReadConsistentView(this._graph) : _epoch = _graph.version;

  void _checkEpoch() {
    if (_graph.version != _epoch) {
      throw StateError(
        'Scene graph was mutated after this read view was created '
        '(epoch $_epoch -> ${_graph.version}). Obtain a fresh readView.',
      );
    }
  }

  @override
  FrozenNodeView get rootNode {
    _checkEpoch();
    return _graph.rootNode.freeze();
  }

  @override
  List<FrozenNodeView> get layers {
    _checkEpoch();
    return _graph.layers.map((l) => l.freeze()).toList();
  }

  @override
  int get layerCount {
    _checkEpoch();
    return _graph.layerCount;
  }

  @override
  FrozenNodeView? findNodeById(NodeId nodeId) {
    _checkEpoch();
    return _graph.findNodeById(nodeId)?.freeze();
  }

  @override
  bool containsNode(NodeId nodeId) {
    _checkEpoch();
    return _graph.containsNode(nodeId);
  }

  @override
  List<FrozenNodeView> nodesInBounds(Rect viewport) {
    _checkEpoch();
    return _graph.nodesInBounds(viewport).map((n) => n.freeze()).toList();
  }

  @override
  FrozenNodeView? hitTestAt(Offset worldPoint) {
    _checkEpoch();
    return _graph.hitTestAt(worldPoint)?.freeze();
  }

  @override
  Iterable<FrozenNodeView> get allNodes {
    _checkEpoch();
    return _graph.allNodes.map((n) => n.freeze());
  }

  @override
  int get totalElementCount {
    _checkEpoch();
    return _graph.totalElementCount;
  }

  @override
  int get version {
    _checkEpoch();
    return _graph.version;
  }

  @override
  Map<String, dynamic> toJson() {
    _checkEpoch();
    return _graph.toJson();
  }

  @override
  SceneGraphSnapshot snapshot() {
    _checkEpoch();
    return _graph.snapshot();
  }
}
