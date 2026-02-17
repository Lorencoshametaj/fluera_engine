import 'dart:math' as math;
import 'dart:ui';
import '../../drawing/models/pro_drawing_point.dart';
import 'eraser_hit_tester.dart';

// ============================================================================
// 🗺️ ERASER SPATIAL INDEX — Grid-based O(1) stroke lookup
// ============================================================================

/// Grid-based spatial index for fast nearby-stroke queries.
/// Cells are keyed by a hash of grid coordinates (cell size = 50px).
///
/// After stroke mutations (add/remove), call [markDirty] to trigger
/// a lazy rebuild on the next [getNearbyStrokeIds] call.
class EraserSpatialIndex {
  static const double _gridCellSize = 50.0;

  final Map<int, Set<String>> _grid = {};
  bool _isDirty = true;

  /// Whether the grid needs rebuilding.
  bool get isDirty => _isDirty;

  /// Mark the grid as dirty (rebuilds lazily on next query).
  void markDirty() {
    _isDirty = true;
  }

  /// Force a full rebuild from the given strokes.
  void rebuild(List<ProStroke> strokes) {
    _grid.clear();
    for (final stroke in strokes) {
      _insertStroke(stroke);
    }
    _isDirty = false;
  }

  /// Get stroke IDs in cells near [position] within shape-aware bounds.
  /// Returns empty set when dirty (bypasses filter → all strokes checked).
  Set<String> getNearbyStrokeIds(
    Offset position, {
    required double eraserRadius,
    required EraserShape eraserShape,
    double eraserShapeWidth = 30.0,
    double eraserShapeAngle = 0.0,
  }) {
    // When dirty, return empty → caller skips spatial filter
    if (_isDirty) return <String>{};

    // Compute shape-aware bounding box
    double extentX = eraserRadius;
    double extentY = eraserRadius;
    if (eraserShape == EraserShape.rectangle) {
      final halfW = eraserShapeWidth / 2;
      final halfH = eraserRadius;
      final cosA = math.cos(eraserShapeAngle).abs();
      final sinA = math.sin(eraserShapeAngle).abs();
      extentX = halfW * cosA + halfH * sinA + 5;
      extentY = halfW * sinA + halfH * cosA + 5;
    } else if (eraserShape == EraserShape.line) {
      final cosA = math.cos(eraserShapeAngle).abs();
      final sinA = math.sin(eraserShapeAngle).abs();
      extentX = eraserRadius * cosA + 5;
      extentY = eraserRadius * sinA + 5;
    }

    final result = <String>{};
    final minCellX = ((position.dx - extentX) / _gridCellSize).floor();
    final maxCellX = ((position.dx + extentX) / _gridCellSize).floor();
    final minCellY = ((position.dy - extentY) / _gridCellSize).floor();
    final maxCellY = ((position.dy + extentY) / _gridCellSize).floor();

    for (int cx = minCellX; cx <= maxCellX; cx++) {
      for (int cy = minCellY; cy <= maxCellY; cy++) {
        final key = cx * 100003 + cy;
        final cell = _grid[key];
        if (cell != null) result.addAll(cell);
      }
    }
    return result;
  }

  /// Incremental add — insert a stroke without full rebuild.
  void incrementalAdd(ProStroke stroke) {
    if (_isDirty) return; // Will rebuild anyway
    _insertStroke(stroke);
  }

  /// Incremental remove — remove a stroke without full rebuild.
  void incrementalRemove(ProStroke stroke) {
    if (_isDirty) return; // Will rebuild anyway
    final bbox = EraserHitTester.strokeBBox(stroke);
    if (bbox == null) return;

    final minCellX = (bbox.left / _gridCellSize).floor();
    final maxCellX = (bbox.right / _gridCellSize).floor();
    final minCellY = (bbox.top / _gridCellSize).floor();
    final maxCellY = (bbox.bottom / _gridCellSize).floor();

    for (int cx = minCellX; cx <= maxCellX; cx++) {
      for (int cy = minCellY; cy <= maxCellY; cy++) {
        final key = cx * 100003 + cy;
        _grid[key]?.remove(stroke.id);
      }
    }
  }

  /// Clear the entire grid.
  void clear() {
    _grid.clear();
    _isDirty = true;
  }

  // ─── Internal ──────────────────────────────────────────────────────

  void _insertStroke(ProStroke stroke) {
    final bbox = EraserHitTester.strokeBBox(stroke);
    if (bbox == null) return;

    final minCellX = (bbox.left / _gridCellSize).floor();
    final maxCellX = (bbox.right / _gridCellSize).floor();
    final minCellY = (bbox.top / _gridCellSize).floor();
    final maxCellY = (bbox.bottom / _gridCellSize).floor();

    for (int cx = minCellX; cx <= maxCellX; cx++) {
      for (int cy = minCellY; cy <= maxCellY; cy++) {
        final key = cx * 100003 + cy;
        (_grid[key] ??= <String>{}).add(stroke.id);
      }
    }
  }
}
