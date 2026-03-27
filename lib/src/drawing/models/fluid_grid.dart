/// 🌊 FLUID GRID — Sparse 2D pigment density field.
///
/// Stores pigment color, density, wetness, and velocity at each cell
/// of a world-space grid. Only cells that contain ink are allocated
/// (HashMap-based), keeping memory usage proportional to painted area.
///
/// ## Performance
///
/// - O(1) cell lookup via hash key
/// - Zero-alloc iteration over active cells (pre-allocated list)
/// - Spatial key: `(gx << 20) | gy` for grids up to ~1M cells per axis
///
/// ```dart
/// final grid = FluidGrid(resolution: 6);
/// grid.deposit(100.0, 200.0, color: Color(0xFFFF0000), amount: 0.8);
/// final cell = grid.getCellAt(100.0, 200.0);
/// print(cell?.density); // ~0.8
/// ```
library;

import 'dart:math' as math;
import 'dart:ui';

// =============================================================================
// FLUID CELL
// =============================================================================

/// A single cell in the fluid grid.
///
/// Mutable for simulation performance — the engine updates cells in-place
/// rather than allocating new objects each tick.
class FluidCell {
  /// Grid coordinates.
  final int gx;
  final int gy;

  /// Pigment color channels [0.0–1.0].
  double pigmentR;
  double pigmentG;
  double pigmentB;

  /// Pigment density [0.0–1.0]. 0 = empty, 1 = fully saturated.
  double density;

  /// Surface wetness [0.0–1.0]. Controls diffusion speed and mixing.
  double wetness;

  /// Flow velocity (world px/tick).
  double velocityX;
  double velocityY;

  /// Absorbed pigment — permanently fixed to the surface.
  double absorption;

  /// Paper granulation value [0.0–1.0].
  /// Represents how much pigment settles into paper grain valleys.
  double granulation;

  /// Staining strength [0.0–1.0].
  /// Staining pigments resist lifting during backrun/rewetting.
  /// 0.0 = non-staining (easily moved), 1.0 = fully staining (permanent).
  double staining;

  /// Timestamp of last update (ms since epoch). Used for temporal decay.
  double lastUpdateMs;

  FluidCell({
    required this.gx,
    required this.gy,
    this.pigmentR = 0.0,
    this.pigmentG = 0.0,
    this.pigmentB = 0.0,
    this.density = 0.0,
    this.wetness = 0.0,
    this.velocityX = 0.0,
    this.velocityY = 0.0,
    this.absorption = 0.0,
    this.granulation = 0.0,
    this.staining = 0.0,
    this.lastUpdateMs = 0.0,
  });

  /// Whether this cell has significant pigment (for rendering).
  bool get isActive => density > 0.001 || wetness > 0.001;

  /// Whether this cell needs simulation (for physics).
  /// Frozen cells (dry, stationary, absorbed) are rendered but skip physics.
  bool get needsSimulation =>
      wetness > 0.001 ||
      speed > 0.01 ||
      (density > 0.01 && absorption < density * 0.95);

  /// Total velocity magnitude.
  double get speed => math.sqrt(velocityX * velocityX + velocityY * velocityY);

  /// Mix another color into this cell.
  ///
  /// Uses a hybrid linear + subtractive model inspired by Kubelka-Munk
  /// pigment theory. When both surfaces are wet, RGB channels are combined
  /// with a multiplicative (subtractive) term weighted by [subtractiveWeight],
  /// producing realistic pigment interactions (yellow+blue → green).
  /// Falls back to linear blending when surfaces are drier.
  void mixColor(
    double r,
    double g,
    double b,
    double ratio, {
    double subtractiveWeight = 0.0,
  }) {
    final keep = 1.0 - ratio;

    // Linear additive blend (traditional)
    final linR = pigmentR * keep + r * ratio;
    final linG = pigmentG * keep + g * ratio;
    final linB = pigmentB * keep + b * ratio;

    if (subtractiveWeight < 0.01) {
      // Pure linear path (fast)
      pigmentR = linR.clamp(0.0, 1.0);
      pigmentG = linG.clamp(0.0, 1.0);
      pigmentB = linB.clamp(0.0, 1.0);
      return;
    }

    // Subtractive blend: multiply channels (simulates pigment absorption)
    // K-M simplified: mixed reflectance ≈ R₁ × R₂ at overlap
    final subR = pigmentR * r;
    final subG = pigmentG * g;
    final subB = pigmentB * b;

    // Weighted combination of linear and subtractive
    final w = subtractiveWeight.clamp(0.0, 1.0);
    pigmentR = (linR * (1.0 - w) + subR * w).clamp(0.0, 1.0);
    pigmentG = (linG * (1.0 - w) + subG * w).clamp(0.0, 1.0);
    pigmentB = (linB * (1.0 - w) + subB * w).clamp(0.0, 1.0);
  }

  /// Reset cell to empty state.
  void clear() {
    pigmentR = 0.0;
    pigmentG = 0.0;
    pigmentB = 0.0;
    density = 0.0;
    wetness = 0.0;
    velocityX = 0.0;
    velocityY = 0.0;
    absorption = 0.0;
    granulation = 0.0;
    staining = 0.0;
  }

  Map<String, dynamic> toJson() => {
    'gx': gx,
    'gy': gy,
    'r': pigmentR,
    'g': pigmentG,
    'b': pigmentB,
    'd': density,
    'w': wetness,
    'vx': velocityX,
    'vy': velocityY,
    'a': absorption,
    'gn': granulation,
    'st': staining,
    't': lastUpdateMs,
  };

  factory FluidCell.fromJson(Map<String, dynamic> json) => FluidCell(
    gx: (json['gx'] as num).toInt(),
    gy: (json['gy'] as num).toInt(),
    pigmentR: (json['r'] as num?)?.toDouble() ?? 0.0,
    pigmentG: (json['g'] as num?)?.toDouble() ?? 0.0,
    pigmentB: (json['b'] as num?)?.toDouble() ?? 0.0,
    density: (json['d'] as num?)?.toDouble() ?? 0.0,
    wetness: (json['w'] as num?)?.toDouble() ?? 0.0,
    velocityX: (json['vx'] as num?)?.toDouble() ?? 0.0,
    velocityY: (json['vy'] as num?)?.toDouble() ?? 0.0,
    absorption: (json['a'] as num?)?.toDouble() ?? 0.0,
    granulation: (json['gn'] as num?)?.toDouble() ?? 0.0,
    staining: (json['st'] as num?)?.toDouble() ?? 0.0,
    lastUpdateMs: (json['t'] as num?)?.toDouble() ?? 0.0,
  );

  @override
  String toString() =>
      'FluidCell($gx,$gy d=$density w=$wetness g=$granulation '
      'rgb=(${pigmentR.toStringAsFixed(2)},${pigmentG.toStringAsFixed(2)},${pigmentB.toStringAsFixed(2)}))';
}

// =============================================================================
// FLUID GRID
// =============================================================================

/// Sparse 2D grid storing the fluid topology field.
///
/// Cells are addressed by grid coordinates (gx, gy) derived from world
/// coordinates via `world ~/ resolution`. Only cells containing pigment
/// or wetness are stored.
class FluidGrid {
  /// World pixels per grid cell.
  final int resolution;

  /// Sparse cell storage keyed by spatial hash.
  final Map<int, FluidCell> _cells = {};

  /// Pre-built active cell list for zero-alloc iteration.
  List<FluidCell> _activeCellsCache = [];
  bool _activeCellsDirty = true;

  /// Active region bounding box (grid coordinates).
  /// Enables O(1) viewport overlap checks.
  int _minGx = 0, _maxGx = 0, _minGy = 0, _maxGy = 0;
  bool _boundsDirty = true;

  FluidGrid({this.resolution = 6});

  // ===========================================================================
  // SPATIAL HASH
  // ===========================================================================

  /// Encode grid coords to a single int key.
  ///
  /// Uses bit-shifting: gx occupies upper bits, gy occupies lower 20 bits.
  /// Supports grid coordinates in range [-524287, 524288].
  static int spatialKey(int gx, int gy) =>
      ((gx + 524288) << 20) | (gy + 524288);

  /// Convert world coordinate to grid coordinate.
  int _worldToGrid(double world) => world ~/ resolution;

  // ===========================================================================
  // CELL ACCESS
  // ===========================================================================

  /// Get cell at grid coordinates. Returns null if empty.
  FluidCell? getCell(int gx, int gy) => _cells[spatialKey(gx, gy)];

  /// Get cell at world coordinates. Returns null if empty.
  FluidCell? getCellAt(double worldX, double worldY) =>
      getCell(_worldToGrid(worldX), _worldToGrid(worldY));

  /// Get or create cell at grid coordinates.
  FluidCell getOrCreate(int gx, int gy) {
    final key = spatialKey(gx, gy);
    return _cells.putIfAbsent(key, () {
      _activeCellsDirty = true;
      _expandBounds(gx, gy);
      return FluidCell(gx: gx, gy: gy);
    });
  }

  /// Expand active region bounds to include (gx, gy).
  void _expandBounds(int gx, int gy) {
    if (_boundsDirty || _cells.length <= 1) {
      _minGx = gx;
      _maxGx = gx;
      _minGy = gy;
      _maxGy = gy;
      _boundsDirty = false;
    } else {
      if (gx < _minGx) _minGx = gx;
      if (gx > _maxGx) _maxGx = gx;
      if (gy < _minGy) _minGy = gy;
      if (gy > _maxGy) _maxGy = gy;
    }
  }

  /// Active region in world coordinates. Rect.zero if empty.
  Rect get activeRegion {
    if (_cells.isEmpty) return Rect.zero;
    return Rect.fromLTRB(
      _minGx.toDouble() * resolution,
      _minGy.toDouble() * resolution,
      (_maxGx + 1).toDouble() * resolution,
      (_maxGy + 1).toDouble() * resolution,
    );
  }

  /// Whether any active cells overlap the given viewport.
  bool overlapsViewport(Rect viewport) {
    if (_cells.isEmpty) return false;
    return activeRegion.overlaps(viewport);
  }

  /// Number of allocated cells.
  int get cellCount => _cells.length;

  /// All active cells — for rendering (cached, rebuilt only when dirty).
  List<FluidCell> get activeCells {
    if (_activeCellsDirty) {
      _activeCellsCache = _cells.values.where((c) => c.isActive).toList();
      _simulatableCellsCache =
          _activeCellsCache.where((c) => c.needsSimulation).toList();
      _activeCellsDirty = false;
    }
    return _activeCellsCache;
  }

  /// Cells that need physics simulation (subset of activeCells).
  /// Frozen cells (dry, stationary, absorbed) are excluded.
  List<FluidCell> _simulatableCellsCache = [];
  List<FluidCell> get simulatableCells {
    if (_activeCellsDirty) activeCells; // triggers rebuild
    return _simulatableCellsCache;
  }

  /// Iterate all cells (including inactive — for full grid operations).
  Iterable<FluidCell> get allCells => _cells.values;

  /// Mark active cells cache as needing rebuild.
  void invalidateCache() => _activeCellsDirty = true;

  // ===========================================================================
  // DEPOSIT
  // ===========================================================================

  /// Deposit pigment at world coordinates.
  ///
  /// [amount] adds to density (clamped to 1.0).
  /// [wetness] sets the cell wetness for diffusion.
  /// Color is mixed proportionally to the new deposit ratio.
  void deposit(
    double worldX,
    double worldY, {
    required Color color,
    required double amount,
    double wetness = 0.8,
    double nowMs = 0.0,
  }) {
    final gx = _worldToGrid(worldX);
    final gy = _worldToGrid(worldY);
    final cell = getOrCreate(gx, gy);

    // Mix color proportionally to the deposit ratio
    final existingDensity = cell.density;
    final newDensity = (existingDensity + amount).clamp(0.0, 1.0);

    if (existingDensity < 0.001) {
      // Fresh cell — set color directly
      cell.pigmentR = color.r;
      cell.pigmentG = color.g;
      cell.pigmentB = color.b;
    } else {
      // Existing pigment — blend based on deposit ratio
      final ratio = amount / (existingDensity + amount);
      cell.mixColor(color.r, color.g, color.b, ratio);
    }

    cell.density = newDensity;
    cell.wetness = math.max(cell.wetness, wetness);
    cell.lastUpdateMs = nowMs;
    _activeCellsDirty = true;
  }

  /// Deposit pigment along a stroke path with velocity injection.
  ///
  /// Walks from point to point, depositing in every cell the path crosses.
  /// [width] controls the deposition radius (cells within width/2 get ink).
  /// [pressure] modulates deposit amount.
  ///
  /// **Velocity injection**: each deposited cell receives a velocity vector
  /// matching the stroke direction, giving pigment natural momentum.
  void depositAlongPath(
    List<Offset> points, {
    required Color color,
    required double width,
    double pressure = 0.5,
    double nowMs = 0.0,
  }) {
    if (points.isEmpty) return;

    final halfW = width * 0.5;
    final cellRadius = (halfW / resolution).ceil();
    final amount = (0.3 * pressure).clamp(0.05, 0.5);
    final wetness = (0.6 + pressure * 0.3).clamp(0.3, 0.95);

    // Deposit at each point with radius coverage + velocity injection
    for (int pi = 0; pi < points.length; pi++) {
      final pt = points[pi];
      final centerGx = _worldToGrid(pt.dx);
      final centerGy = _worldToGrid(pt.dy);

      // Compute stroke direction for velocity injection
      double dirX = 0.0;
      double dirY = 0.0;
      if (pi < points.length - 1) {
        final next = points[pi + 1];
        dirX = next.dx - pt.dx;
        dirY = next.dy - pt.dy;
      } else if (pi > 0) {
        final prev = points[pi - 1];
        dirX = pt.dx - prev.dx;
        dirY = pt.dy - prev.dy;
      }
      // Normalize to a velocity magnitude proportional to stroke speed
      final dirLen = math.sqrt(dirX * dirX + dirY * dirY);
      if (dirLen > 0.01) {
        dirX /= dirLen;
        dirY /= dirLen;
      }
      // Velocity scaled by speed (clamped) — fast strokes inject more momentum
      final velMag = (dirLen * pressure * 0.5).clamp(0.0, 30.0);

      for (int dx = -cellRadius; dx <= cellRadius; dx++) {
        for (int dy = -cellRadius; dy <= cellRadius; dy++) {
          final gx = centerGx + dx;
          final gy = centerGy + dy;

          // Distance from cell center to point in world coords
          final cellCenterX = (gx + 0.5) * resolution;
          final cellCenterY = (gy + 0.5) * resolution;
          final dist = math.sqrt(
            (cellCenterX - pt.dx) * (cellCenterX - pt.dx) +
                (cellCenterY - pt.dy) * (cellCenterY - pt.dy),
          );

          if (dist > halfW) continue;

          // Falloff: full deposit at center, linear decay at edges
          final falloff = 1.0 - (dist / halfW);
          final cellAmount = amount * falloff;

          final cell = getOrCreate(gx, gy);
          final existing = cell.density;
          final newDensity = (existing + cellAmount).clamp(0.0, 1.0);

          if (existing < 0.001) {
            cell.pigmentR = color.r;
            cell.pigmentG = color.g;
            cell.pigmentB = color.b;
          } else {
            final ratio = cellAmount / (existing + cellAmount);
            cell.mixColor(color.r, color.g, color.b, ratio);
          }

          cell.density = newDensity;
          cell.wetness = math.max(cell.wetness, wetness * falloff);
          cell.lastUpdateMs = nowMs;

          // Inject velocity from stroke direction
          if (velMag > 0.1) {
            final velFactor = falloff * 0.6; // center gets more velocity
            cell.velocityX += dirX * velMag * velFactor;
            cell.velocityY += dirY * velMag * velFactor;
          }
        }
      }
    }
    _activeCellsDirty = true;
  }

  // ===========================================================================
  // QUERY
  // ===========================================================================

  /// Get all cells within a world-space rectangle (for viewport rendering).
  List<FluidCell> queryRect(Rect worldRect) {
    final minGx = _worldToGrid(worldRect.left);
    final maxGx = _worldToGrid(worldRect.right);
    final minGy = _worldToGrid(worldRect.top);
    final maxGy = _worldToGrid(worldRect.bottom);

    final result = <FluidCell>[];
    for (int gx = minGx; gx <= maxGx; gx++) {
      for (int gy = minGy; gy <= maxGy; gy++) {
        final cell = getCell(gx, gy);
        if (cell != null && cell.isActive) result.add(cell);
      }
    }
    return result;
  }

  // ===========================================================================
  // PRUNING
  // ===========================================================================

  /// Remove cells with density and wetness below threshold.
  ///
  /// Returns the number of cells pruned.
  int prune(double densityThreshold, double wetnessThreshold) {
    final keysToRemove = <int>[];

    for (final entry in _cells.entries) {
      final cell = entry.value;
      if (cell.density < densityThreshold && cell.wetness < wetnessThreshold) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _cells.remove(key);
    }

    if (keysToRemove.isNotEmpty) _activeCellsDirty = true;
    return keysToRemove.length;
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  /// Clear all cells.
  void clear() {
    _cells.clear();
    _activeCellsCache = [];
    _activeCellsDirty = true;
  }

  /// Create a frozen snapshot of current state for rendering.
  ///
  /// Returns a new list of cell copies — safe to read from render thread
  /// while simulation continues mutating the original grid.
  List<FluidCell> freeze() {
    return _cells.values
        .where((c) => c.isActive)
        .map(
          (c) => FluidCell(
            gx: c.gx,
            gy: c.gy,
            pigmentR: c.pigmentR,
            pigmentG: c.pigmentG,
            pigmentB: c.pigmentB,
            density: c.density,
            wetness: c.wetness,
            velocityX: c.velocityX,
            velocityY: c.velocityY,
            absorption: c.absorption,
            lastUpdateMs: c.lastUpdateMs,
          ),
        )
        .toList();
  }

  // ===========================================================================
  // SERIALIZATION
  // ===========================================================================

  Map<String, dynamic> toJson() => {
    'res': resolution,
    'cells':
        _cells.values.where((c) => c.isActive).map((c) => c.toJson()).toList(),
  };

  factory FluidGrid.fromJson(Map<String, dynamic> json) {
    final res = (json['res'] as num?)?.toInt() ?? 6;
    final grid = FluidGrid(resolution: res);
    final cellList = json['cells'] as List<dynamic>? ?? [];
    for (final cJson in cellList) {
      final cell = FluidCell.fromJson(cJson as Map<String, dynamic>);
      grid._cells[spatialKey(cell.gx, cell.gy)] = cell;
    }
    grid._activeCellsDirty = true;
    return grid;
  }

  @override
  String toString() =>
      'FluidGrid(res: $resolution, cells: ${_cells.length}, '
      'active: ${activeCells.length})';
}
