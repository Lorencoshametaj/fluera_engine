part of 'layer_controller.dart';

// ============================================================================
// LayerController — Spatial index management
// ============================================================================

extension _LayerSpatialIdx on LayerController {
  /// Rebuild the spatial index from all visible layers.
  void _rebuildSpatialIndexImpl() {
    final allStrokes = _getAllVisibleStrokesImpl();
    final allShapes = _getAllVisibleShapesImpl();
    final allTexts = _getAllVisibleTextsImpl();
    _spatialIndex.build(
      strokes: allStrokes,
      shapes: allShapes,
      texts: allTexts,
    );
    _spatialIndexDirty = false;
  }

  /// Force a spatial index rebuild.
  void _invalidateSpatialIndexImpl() {
    _spatialIndexDirty = true;
    _invalidateSceneGraph();
  }
}
