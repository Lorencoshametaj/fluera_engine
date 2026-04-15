part of 'layer_controller.dart';

// ============================================================================
// LayerController — Scene graph management
// ============================================================================

extension _LayerSceneGr on LayerController {
  /// Get the LayerNode for a given CanvasLayer.
  LayerNode _getLayerNodeImpl(CanvasLayer layer) => layer.node;

  /// Find any node by ID anywhere in the scene graph.
  CanvasNode? _findNodeByIdImpl(String nodeId) =>
      sceneGraph.findNodeById(nodeId);

  /// Rebuild the scene graph from current layers.
  ///
  /// 🐛 FIX: Preserve monotonically-increasing version across rebuilds.
  /// `SceneGraph()` starts at version 0, and `addLayer` only bumps it by
  /// 1 per layer. On the second undo, the old and new scene graphs both
  /// have version = layerCount, so `DrawingPainter.shouldRepaint()` returns
  /// false → no visual update. By restoring the version to be > the old
  /// version, shouldRepaint always detects the change.
  void _rebuildSceneGraphImpl() {
    final oldVersion = _sceneGraph.version;
    _sceneGraph = SceneGraph();
    for (final layer in _layers) {
      _sceneGraph.addLayer(layer.node);
    }
    // Ensure version is strictly greater than old version so that
    // DrawingPainter.shouldRepaint() detects the structural change.
    if (_sceneGraph.version <= oldVersion) {
      _sceneGraph.restoreVersion(oldVersion + 1);
    }
    _sceneGraphDirty = false;
  }
}
