part of 'lasso_tool.dart';

// =============================================================================
// LassoTool — Warp Mesh Deformation
// =============================================================================

/// Grid dimensions for warp mesh.
class WarpMeshGrid {
  /// Number of control points horizontally (columns).
  final int cols;

  /// Number of control points vertically (rows).
  final int rows;

  /// Control point positions in canvas space.
  /// Stored as a flat list in row-major order: [row0col0, row0col1, ..., row1col0, ...]
  final List<Offset> controlPoints;

  /// Original (undeformed) control point positions.
  final List<Offset> originalPoints;

  WarpMeshGrid({
    required this.cols,
    required this.rows,
    List<Offset>? controlPoints,
    List<Offset>? originalPoints,
  })  : controlPoints = controlPoints ?? [],
        originalPoints = originalPoints ?? [];

  /// Get the control point at grid position (row, col).
  Offset getPoint(int row, int col) => controlPoints[row * cols + col];

  /// Set the control point at grid position (row, col).
  void setPoint(int row, int col, Offset point) {
    controlPoints[row * cols + col] = point;
  }

  /// Get the original (undeformed) control point at grid position (row, col).
  Offset getOriginal(int row, int col) => originalPoints[row * cols + col];

  /// Create a uniform grid spanning [bounds] with [rows] × [cols] control points.
  factory WarpMeshGrid.uniform(Rect bounds, {int rows = 4, int cols = 4}) {
    final points = <Offset>[];
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final u = cols > 1 ? c / (cols - 1) : 0.5;
        final v = rows > 1 ? r / (rows - 1) : 0.5;
        points.add(Offset(
          bounds.left + u * bounds.width,
          bounds.top + v * bounds.height,
        ));
      }
    }
    return WarpMeshGrid(
      cols: cols,
      rows: rows,
      controlPoints: points,
      originalPoints: List.of(points), // copy
    );
  }

  /// Reset all control points to their original positions.
  void reset() {
    for (int i = 0; i < controlPoints.length; i++) {
      controlPoints[i] = originalPoints[i];
    }
  }

  /// Find the closest control point to [position] (screen or canvas space).
  /// Returns the index or -1 if none within [threshold].
  int findClosest(Offset position, {double threshold = 20.0}) {
    int bestIdx = -1;
    double bestDist = threshold * threshold;

    for (int i = 0; i < controlPoints.length; i++) {
      final d = (controlPoints[i] - position).distanceSquared;
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }
}

extension LassoWarp on LassoTool {
  /// Active warp mesh (null when not warping).
  WarpMeshGrid? get warpMesh => _warpMesh;

  /// Initialize a warp mesh grid over the current selection.
  ///
  /// [rows] and [cols] define the density of control points.
  /// Typical values: 3×3 for simple warp, 4×4 for detailed deformation.
  WarpMeshGrid? initWarpMesh({int rows = 4, int cols = 4}) {
    if (!hasSelection) return null;

    final bounds = selectionManager.aggregateBounds;
    if (bounds == Rect.zero || bounds.isEmpty) return null;

    _warpMesh = WarpMeshGrid.uniform(bounds, rows: rows, cols: cols);
    return _warpMesh;
  }

  /// Move a warp mesh control point to a new position.
  ///
  /// [controlIndex] is the flat index into the control points array.
  void moveWarpPoint(int controlIndex, Offset newPosition) {
    if (_warpMesh == null) return;
    if (controlIndex < 0 || controlIndex >= _warpMesh!.controlPoints.length) {
      return;
    }
    _warpMesh!.controlPoints[controlIndex] = newPosition;
  }

  /// Apply the current warp mesh deformation to all selected elements
  /// and dispose the mesh.
  ///
  /// Each point in each selected StrokeNode is mapped from its normalized
  /// position in the original bounding box through the deformed mesh using
  /// bilinear interpolation per mesh cell.
  void applyWarp() {
    if (_warpMesh == null || !hasSelection) return;

    final mesh = _warpMesh!;
    final bounds = selectionManager.aggregateBounds;
    if (bounds == Rect.zero || bounds.isEmpty) {
      _warpMesh = null;
      return;
    }

    for (final node in selectionManager.selectedNodes) {
      if (node.isLocked) continue;

      if (node is StrokeNode) {
        final warpedPoints = node.stroke.points.map((p) {
          final mapped = _mapThroughMesh(p.position, bounds, mesh);
          return p.copyWith(position: mapped);
        }).toList();

        node.stroke = node.stroke.copyWith(points: warpedPoints);
        node.localTransform = Matrix4.identity();
        node.invalidateTransformCache();
      } else {
        // For non-stroke nodes — approximate with center mapping + scale
        final center = node.worldBounds.center;
        final mapped = _mapThroughMesh(center, bounds, mesh);
        node.translate(mapped.dx - center.dx, mapped.dy - center.dy);
      }
    }

    _warpMesh = null;
    _selectionBounds = null;
  }

  /// Cancel the active warp mesh without applying.
  void cancelWarp() {
    _warpMesh?.reset();
    _warpMesh = null;
  }

  /// Map a point through the warp mesh using bilinear interpolation
  /// within the mesh cell that contains the point.
  Offset _mapThroughMesh(Offset point, Rect bounds, WarpMeshGrid mesh) {
    // Normalize point to [0,1] × [0,1] within the source bounds
    final u = bounds.width > 0
        ? (point.dx - bounds.left) / bounds.width
        : 0.5;
    final v = bounds.height > 0
        ? (point.dy - bounds.top) / bounds.height
        : 0.5;

    // Map to mesh cell coordinates
    final cellU = u * (mesh.cols - 1);
    final cellV = v * (mesh.rows - 1);

    // Determine which cell we're in
    final col = cellU.floor().clamp(0, mesh.cols - 2);
    final row = cellV.floor().clamp(0, mesh.rows - 2);

    // Local coordinates within the cell [0,1]
    final localU = cellU - col;
    final localV = cellV - row;

    // Bilinear interpolation of the 4 corners of this mesh cell
    final tl = mesh.getPoint(row, col);
    final tr = mesh.getPoint(row, col + 1);
    final bl = mesh.getPoint(row + 1, col);
    final br = mesh.getPoint(row + 1, col + 1);

    final x = (1 - localU) * (1 - localV) * tl.dx +
        localU * (1 - localV) * tr.dx +
        localU * localV * br.dx +
        (1 - localU) * localV * bl.dx;
    final y = (1 - localU) * (1 - localV) * tl.dy +
        localU * (1 - localV) * tr.dy +
        localU * localV * br.dy +
        (1 - localU) * localV * bl.dy;

    return Offset(x, y);
  }
}
