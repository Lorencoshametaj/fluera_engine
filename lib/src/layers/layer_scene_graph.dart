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
  void _rebuildSceneGraphImpl() {
    _sceneGraph = SceneGraph();
    for (final layer in _layers) {
      _sceneGraph.addLayer(layer.node);
    }
    _sceneGraphDirty = false;
  }
}
