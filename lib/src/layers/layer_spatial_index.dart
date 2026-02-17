part of 'layer_controller.dart';

// ============================================================================
// LayerController — Spatial index management
// ============================================================================

extension _LayerSpatialIdx on LayerController {
  /// Rebuild the spatial index from all visible layers.
  void _rebuildSpatialIndexImpl() {
    final allStrokes = _getAllVisibleStrokesImpl();
    final allShapes = _getAllVisibleShapesImpl();
    // TODO: Add text elements to spatial index for hit testing
    _spatialIndex.build(strokes: allStrokes, shapes: allShapes);
    _spatialIndexDirty = false;
  }

  /// Force a spatial index rebuild.
  void _invalidateSpatialIndexImpl() {
    _spatialIndexDirty = true;
    _invalidateSceneGraph();
  }
}
