/// 🌊 FLUID TOPOLOGY ENGINE — L2 Adaptive Intelligence Subsystem.
///
/// Coordinates the fluid simulation across the engine:
/// - **Gravity** — wet pigment sags downward
/// - **Diffusion** — 8-connected Gaussian kernel with noise perturbation
/// - **Capillary flow** — wetness wicks into dry paper fibers
/// - **Advection** — velocity field transport with momentum conservation
/// - **Edge darkening** — cauliflower pigment concentration at drying boundaries
/// - **Drying** — exponential wetness decay
/// - **Absorption** — surface-dependent pigment fixation
/// - **Pruning** — remove dead cells to keep grid sparse
///
/// ## Architecture
///
/// Extends [IntelligenceSubsystem] to participate in the Conscious Architecture.
/// Context-dependent gating via [OrganicBehaviorEngine.intensity].
library;

import 'dart:math' as math;
import 'dart:ui';

import '../../core/conscious_architecture.dart';
import '../../systems/organic_behavior_engine.dart';
import '../models/fluid_grid.dart';
import '../models/fluid_topology_config.dart';

/// L2 Intelligence: fluid topology simulation.
class FluidTopologyEngine extends IntelligenceSubsystem {
  // ─── Static access ─────────────────────────────────────────────────

  static FluidTopologyEngine? _instance;
  static FluidTopologyEngine? get instance => _instance;

  // ─── Instance state ────────────────────────────────────────────────

  final FluidGrid grid;
  FluidTopologyConfig config;

  bool _isActive = true;
  int _tickCount = 0;
  double _lastTickMs = 0.0;
  double _intensity = 1.0;

  /// Pooled delta buffer — reused across ticks to avoid GC pressure.
  final Map<int, _DiffusionDelta> _deltaPool = {};

  /// Cardinal neighbor offsets (4-connected, weight 1.0).
  static const _neighbors = [
    (0, -1), // up
    (0, 1), // down
    (-1, 0), // left
    (1, 0), // right
  ];

  /// Diagonal neighbor offsets (weight ≈ 0.707).
  static const _diagonals = [(-1, -1), (1, -1), (-1, 1), (1, 1)];

  FluidTopologyEngine({FluidTopologyConfig? config, FluidGrid? grid})
    : config = config ?? const FluidTopologyConfig(),
      grid = grid ?? FluidGrid() {
    _instance = this;
  }

  // ─── IntelligenceSubsystem contract ─────────────────────────────────

  @override
  IntelligenceLayer get layer => IntelligenceLayer.adaptive;

  @override
  String get name => 'FluidTopologyEngine';

  @override
  bool get isActive => _isActive && config.enabled;

  @override
  void onContextChanged(EngineContext context) {
    if (!config.enabled) {
      _intensity = 0.0;
      return;
    }

    final tool = context.activeTool ?? '';
    final isWetTool = const {
      'watercolor',
      'inkWash',
      'ink_wash',
      'oilPaint',
      'oil_paint',
      'brush',
    }.contains(tool);

    if (context.isPdfDocument || (!isWetTool && !context.isDrawing)) {
      _intensity = 0.0;
      return;
    }

    final zoom = context.zoom;
    if (zoom >= 0.5) {
      _intensity = 1.0;
    } else if (zoom >= 0.2) {
      _intensity = (zoom - 0.2) / 0.3;
    } else {
      _intensity = 0.0;
    }

    _intensity *= OrganicBehaviorEngine.intensity;
  }

  @override
  void onIdle(Duration idleDuration) {
    if (!config.enabled) return;
    if (idleDuration.inSeconds >= 2) {
      // Accelerated drying during idle — 5× evaporation rate
      final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
      final rate = config.evaporationRate * 5.0;
      for (final cell in grid.activeCells) {
        if (cell.wetness < 0.001) continue;
        final elapsed = nowMs - cell.lastUpdateMs;
        if (elapsed <= 0) continue;
        cell.wetness *= math.exp(-rate * elapsed);
        cell.lastUpdateMs = nowMs;
        if (cell.wetness < 0.001) cell.wetness = 0.0;
      }
      grid.prune(config.pruneThreshold, config.pruneThreshold);
    }
  }

  @override
  void dispose() {
    _isActive = false;
    grid.clear();
    if (_instance == this) _instance = null;
  }

  // ─── Public API ─────────────────────────────────────────────────────

  /// Deposit pigment along a stroke (called from BrushEngine).
  static void depositStroke(
    List<dynamic> points,
    Color color,
    double width,
    double pressure,
  ) {
    final engine = _instance;
    if (engine == null || !engine.config.enabled) return;

    final offsets = <Offset>[];
    for (final p in points) {
      if (p is Offset) {
        offsets.add(p);
      } else {
        try {
          offsets.add((p as dynamic).position as Offset);
        } catch (_) {
          continue;
        }
      }
    }
    if (offsets.isEmpty) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    engine.grid.depositAlongPath(
      offsets,
      color: color,
      width: width,
      pressure: pressure,
      nowMs: nowMs,
    );
  }

  /// Run one simulation tick with time budgeting.
  ///
  /// **Performance guarantees:**
  /// - Hard time budget of 2ms per tick (configurable)
  /// - LOD-based phase skipping at low zoom / high cell count
  /// - Merged gravity+drying+absorption into single pass
  /// - Emergency prune at cell count hard limit
  /// - Adaptive tick skip for high cell counts
  void tick(double nowMs) {
    if (!config.enabled || _intensity <= 0.0) return;

    final cellCount = grid.simulatableCells.length;
    if (cellCount == 0) return;

    // ── Adaptive tick skip ──────────────────────────────────────
    // High cell count → skip ticks to maintain frame budget
    if (cellCount > 3000 && _tickCount % 2 != 0) {
      _tickCount++;
      return;
    }
    if (cellCount > 6000 && _tickCount % 3 != 0) {
      _tickCount++;
      return;
    }

    final dt =
        _lastTickMs > 0
            ? (nowMs - _lastTickMs) / 1000.0
            : 1.0 / config.tickRate;
    _lastTickMs = nowMs;

    // ── Cell count hard limit ───────────────────────────────────
    if (cellCount > config.maxActiveCells) {
      grid.prune(config.pruneThreshold * 5.0, config.pruneThreshold * 5.0);
    }

    // ── Time-budgeted phases ────────────────────────────────────
    final sw = Stopwatch()..start();
    const budgetUs = 2000; // 2ms budget per tick
    final effectiveDiffusion = config.diffusionRate * _intensity;

    // LOD level: 0 = full quality, 1 = reduced, 2 = minimal
    final lod =
        cellCount > 5000
            ? 2
            : cellCount > 2000
            ? 1
            : 0;

    // Phase A: Single-pass — gravity + drying + absorption + staining
    // Merges 3 phases into 1 loop iteration for cache efficiency.
    _applyCombinedPass(dt, nowMs);

    // Phase B: Diffusion (always runs — core behavior)
    if (sw.elapsedMicroseconds < budgetUs) {
      _applyDiffusion(effectiveDiffusion);
    }

    // Phase C: Capillary (skip at LOD 2)
    if (lod < 2 &&
        config.capillaryRate > 0.0 &&
        sw.elapsedMicroseconds < budgetUs) {
      _applyCapillary();
    }

    // Phase D: Advection (always runs)
    if (sw.elapsedMicroseconds < budgetUs) {
      _applyAdvection(dt);
    }

    // Phase E: Edge darkening (skip at LOD 1+)
    if (lod < 1 &&
        config.edgeDarkeningStrength > 0.0 &&
        sw.elapsedMicroseconds < budgetUs) {
      _applyEdgeDarkening();
    }

    // Phase F: Backrun (skip at LOD 2)
    if (lod < 2 &&
        config.backrunThreshold > 0.0 &&
        sw.elapsedMicroseconds < budgetUs) {
      _applyBackrun();
    }

    // Phase G: Granulation (skip at LOD 1+)
    if (lod < 1 &&
        config.granulationStrength > 0.0 &&
        sw.elapsedMicroseconds < budgetUs) {
      _applyGranulation();
    }

    // Phase H: Wet-on-wet turbulence (skip at LOD 1+)
    if (lod < 1 &&
        config.wetOnWetTurbulence > 0.0 &&
        sw.elapsedMicroseconds < budgetUs) {
      _applyWetOnWetTurbulence();
    }

    sw.stop();
    _lastTickUs = sw.elapsedMicroseconds;

    // Periodic prune
    if (_tickCount % 10 == 0) {
      grid.prune(config.pruneThreshold, config.pruneThreshold);
    }

    _tickCount++;
    grid.invalidateCache();
  }

  /// Last tick duration in microseconds (for diagnostics).
  int _lastTickUs = 0;

  // ─── Simulation Steps ─────────────────────────────────────────────────

  /// Combined single-pass: gravity + drying + absorption + staining.
  ///
  /// Merges 3 separate O(N) loops into 1 for cache efficiency.
  void _applyCombinedPass(double dt, double nowMs) {
    final gravAccel =
        config.gravity > 0.0
            ? config.gravity * (1.0 - config.viscosity.clamp(0.0, 0.95))
            : 0.0;
    final evapRate = config.evaporationRate;
    final sFactor = config.stainingFactor;

    for (final cell in grid.activeCells) {
      // Gravity: accelerate wet pigment downward
      if (gravAccel > 0.0 && cell.wetness > 0.05 && cell.density > 0.01) {
        cell.velocityY += gravAccel * cell.wetness * dt;
      }

      // Drying: exponential wetness decay
      if (cell.wetness > 0.001) {
        final elapsed = nowMs - cell.lastUpdateMs;
        if (elapsed > 0) {
          cell.wetness *= math.exp(-evapRate * elapsed);
          cell.lastUpdateMs = nowMs;
          if (cell.wetness < 0.001) cell.wetness = 0.0;
        }
      }

      // Absorption + staining: dry pigment bonds to surface
      if (cell.density > 0.01 && cell.wetness < 0.8) {
        final dryness = 1.0 - cell.wetness;
        final absorbed = cell.density * dryness * 0.02 * dt;
        cell.absorption = (cell.absorption + absorbed).clamp(0.0, 1.0);
        final stainRate = sFactor * dryness * 0.015 * dt;
        cell.staining = (cell.staining + stainRate).clamp(0.0, 1.0);
      }
    }
  }

  /// Spatial hash for noise perturbation (breaks grid symmetry).
  static double _hash(int gx, int gy) {
    int h = gx * 73856093 ^ gy * 19349663;
    h = (h ^ (h >> 16)) & 0x7FFFFFFF;
    return (h % 10000) / 10000.0;
  }

  /// Phase 2: 8-connected diffusion with anisotropic fiber weighting.
  void _applyDiffusion(double rate) {
    final cells = grid.activeCells;
    if (cells.isEmpty) return;

    final invViscosity = 1.0 - config.viscosity.clamp(0.0, 0.95);
    final tension = config.surfaceTension;
    final noiseAmp = config.noiseAmplitude;
    final tensionGate = 1.0 - tension;
    final fiberCos = math.cos(config.fiberAngle);
    final fiberSin = math.sin(config.fiberAngle);

    // Reuse pooled delta buffer
    _deltaPool.clear();

    for (final cell in cells) {
      if (cell.wetness < 0.01 || cell.density < 0.01) continue;
      final strength = rate * cell.wetness * invViscosity;
      if (strength < 0.001) continue;

      final cellNoise = _hash(cell.gx, cell.gy);
      final noiseModulation = 1.0 + (cellNoise - 0.5) * 2.0 * noiseAmp;

      // Cardinal neighbors with anisotropic fiber weighting
      for (final (dx, dy) in _neighbors) {
        final fw = _fiberWeight(dx, dy, fiberCos, fiberSin);
        _diffuseToNeighbor(
          cell,
          dx,
          dy,
          strength * noiseModulation * fw,
          tensionGate,
          0.2,
          _deltaPool,
        );
      }

      // Diagonal neighbors
      for (final (dx, dy) in _diagonals) {
        final diagNoise =
            1.0 + (_hash(cell.gx + dx, cell.gy + dy) - 0.5) * noiseAmp;
        final fw = _fiberWeight(dx, dy, fiberCos, fiberSin);
        _diffuseToNeighbor(
          cell,
          dx,
          dy,
          strength * diagNoise * fw,
          tensionGate,
          0.1,
          _deltaPool,
        );
      }
    }

    // Apply deltas with subtractive mixing
    final subWeight = config.subtractiveBlend;
    for (final d in _deltaPool.values) {
      final target = grid.getOrCreate(d.gx, d.gy);
      if (target.density < 0.001) {
        if (d.addDensity > 0.001) {
          target.pigmentR = d.addR / d.addDensity;
          target.pigmentG = d.addG / d.addDensity;
          target.pigmentB = d.addB / d.addDensity;
        }
      } else {
        final ratio = d.addDensity / (target.density + d.addDensity);
        if (d.addDensity > 0.001) {
          target.mixColor(
            d.addR / d.addDensity,
            d.addG / d.addDensity,
            d.addB / d.addDensity,
            ratio,
            subtractiveWeight: subWeight * target.wetness,
          );
        }
      }
      target.density = (target.density + d.addDensity).clamp(0.0, 1.0);
      target.wetness = math.max(target.wetness, d.addWetness);
    }
  }

  /// Fiber anisotropy weight: boost diffusion along paper fiber direction.
  static double _fiberWeight(int dx, int dy, double fiberCos, double fiberSin) {
    // Dot product of neighbor direction with fiber direction
    final dirLen = math.sqrt(dx * dx + dy * dy + 0.001);
    final dot = (dx * fiberCos + dy * fiberSin) / dirLen;
    // 1.0 → along fibers = 1.3x boost; perpendicular = 0.85x
    return 0.85 + dot.abs() * 0.45;
  }

  /// Diffusion helper: transfer pigment from cell to neighbor (dx,dy).
  void _diffuseToNeighbor(
    FluidCell cell,
    int dx,
    int dy,
    double strength,
    double tensionGate,
    double fraction,
    Map<int, _DiffusionDelta> deltas,
  ) {
    final nx = cell.gx + dx;
    final ny = cell.gy + dy;
    final neighborDensity = grid.getCell(nx, ny)?.density ?? 0.0;

    final gradient = cell.density - neighborDensity;
    if (gradient <= 0.0) return;

    final transfer = gradient * strength * tensionGate * fraction;
    if (transfer < 0.001) return;

    final key = FluidGrid.spatialKey(nx, ny);
    final d = deltas.putIfAbsent(key, () => _DiffusionDelta(nx, ny));
    d.addDensity += transfer;
    d.addR += cell.pigmentR * transfer;
    d.addG += cell.pigmentG * transfer;
    d.addB += cell.pigmentB * transfer;
    d.addWetness = math.max(d.addWetness, cell.wetness * 0.5);

    cell.density -= transfer;
  }

  /// Phase 3: Capillary flow — wetness wicks into dry neighbors.
  void _applyCapillary() {
    final rate = config.capillaryRate;
    for (final cell in grid.activeCells) {
      if (cell.wetness < 0.1) continue;
      for (final (dx, dy) in _neighbors) {
        final neighborWetness =
            grid.getCell(cell.gx + dx, cell.gy + dy)?.wetness ?? 0.0;
        final gradient = cell.wetness - neighborWetness;
        if (gradient < 0.05) continue;

        final transfer = gradient * rate;
        if (transfer < 0.001) continue;

        final target = grid.getOrCreate(cell.gx + dx, cell.gy + dy);
        target.wetness = (target.wetness + transfer).clamp(0.0, 1.0);
        cell.wetness -= transfer * 0.3;
      }
    }
  }

  /// Phase 4: Semi-Lagrangian advection with momentum conservation.
  void _applyAdvection(double dt) {
    for (final cell in grid.activeCells) {
      if (cell.speed < 0.01) continue;

      // Viscosity-dependent damping
      final damp = 0.92 - config.viscosity * 0.15;
      cell.velocityX *= damp;
      cell.velocityY *= damp;

      final transferRatio = (cell.speed * dt * 0.1).clamp(0.0, 0.3);
      if (transferRatio < 0.001 || cell.density < 0.01) continue;

      final tgx = cell.gx + (cell.velocityX * dt / grid.resolution).round();
      final tgy = cell.gy + (cell.velocityY * dt / grid.resolution).round();
      if (tgx == cell.gx && tgy == cell.gy) continue;

      final target = grid.getOrCreate(tgx, tgy);
      final amount = cell.density * transferRatio;

      if (target.density < 0.001) {
        target.pigmentR = cell.pigmentR;
        target.pigmentG = cell.pigmentG;
        target.pigmentB = cell.pigmentB;
      } else {
        target.mixColor(
          cell.pigmentR,
          cell.pigmentG,
          cell.pigmentB,
          amount / (target.density + amount),
        );
      }

      target.density = (target.density + amount).clamp(0.0, 1.0);
      target.wetness = math.max(target.wetness, cell.wetness * 0.3);
      target.velocityX += cell.velocityX * transferRatio * 0.5;
      target.velocityY += cell.velocityY * transferRatio * 0.5;
      cell.density -= amount;
    }
  }

  /// Phase 5: Edge darkening — cauliflower pigment concentration.
  ///
  /// As boundary cells dry, pigment migrates from interior toward them,
  /// creating the characteristic dark edge ring of real watercolor.
  void _applyEdgeDarkening() {
    final strength = config.edgeDarkeningStrength;
    for (final cell in grid.activeCells) {
      // Only at drying boundary: wetness ∈ [0.1, 0.5]
      if (cell.wetness < 0.1 || cell.wetness > 0.5 || cell.density < 0.01) {
        continue;
      }

      int wetterCount = 0;
      double sourceDensity = 0.0;

      for (final (dx, dy) in _neighbors) {
        final n = grid.getCell(cell.gx + dx, cell.gy + dy);
        if (n != null && n.wetness > cell.wetness + 0.1 && n.density > 0.02) {
          wetterCount++;
          sourceDensity += n.density;
        }
      }

      // Boundary cell: 1–3 wetter neighbors (not fully interior)
      if (wetterCount >= 1 && wetterCount <= 3) {
        final pull = sourceDensity * strength * 0.02;
        cell.density = (cell.density + pull).clamp(0.0, 1.0);

        for (final (dx, dy) in _neighbors) {
          final n = grid.getCell(cell.gx + dx, cell.gy + dy);
          if (n != null && n.wetness > cell.wetness + 0.1 && n.density > 0.02) {
            n.density = (n.density - pull / wetterCount).clamp(0.0, 1.0);
          }
        }
      }
    }
  }

  /// Phase 6: Backrun — wet water pushes old pigment outward.
  ///
  /// When a wet cell encounters a nearly-dry cell (wetness above threshold),
  /// the fresh water pushes the existing pigment toward the boundary,
  /// creating the characteristic watercolor "backrun" or "bloom" effect.
  void _applyBackrun() {
    final threshold = config.backrunThreshold;

    for (final cell in grid.activeCells) {
      // Source: high wetness, moderate density
      if (cell.wetness < 0.6 || cell.density < 0.05) continue;

      for (final (dx, dy) in _neighbors) {
        final nx = cell.gx + dx;
        final ny = cell.gy + dy;
        final neighbor = grid.getCell(nx, ny);
        if (neighbor == null) continue;

        // Target: drying (wetness in threshold zone) with pigment
        final wetDiff = cell.wetness - neighbor.wetness;
        if (wetDiff < threshold || neighbor.density < 0.02) continue;

        // Push pigment away — but stained pigment resists lifting
        final liftable = neighbor.density * (1.0 - neighbor.staining);
        final pushAmount = liftable * wetDiff * 0.08;
        if (pushAmount < 0.001) continue;

        // Find the cell on the far side (away from source)
        final farGx = nx + dx;
        final farGy = ny + dy;
        final farCell = grid.getOrCreate(farGx, farGy);

        // Transfer pigment outward
        if (farCell.density < 0.001) {
          farCell.pigmentR = neighbor.pigmentR;
          farCell.pigmentG = neighbor.pigmentG;
          farCell.pigmentB = neighbor.pigmentB;
        } else {
          final ratio = pushAmount / (farCell.density + pushAmount);
          farCell.mixColor(
            neighbor.pigmentR,
            neighbor.pigmentG,
            neighbor.pigmentB,
            ratio,
            subtractiveWeight: config.subtractiveBlend * neighbor.wetness,
          );
        }

        farCell.density = (farCell.density + pushAmount).clamp(0.0, 1.0);
        farCell.wetness = math.max(farCell.wetness, cell.wetness * 0.3);
        neighbor.density -= pushAmount;
      }
    }
  }

  /// Phase 9: Granulation — pigment settles into paper grain.
  ///
  /// Each cell computes a "grain value" from its grid position (spatial hash).
  /// Cells at grain valleys accumulate pigment slightly, while ridge cells
  /// lose it. This produces the speckled texture characteristic of
  /// cold-pressed watercolor paper.
  void _applyGranulation() {
    final strength = config.granulationStrength;

    for (final cell in grid.activeCells) {
      if (cell.density < 0.02 || cell.wetness > 0.7) continue;

      // Paper grain: deterministic per cell position
      final grain = _hash(cell.gx * 3, cell.gy * 7);

      // Grain valleys (< 0.4) accumulate, ridges (> 0.6) lose pigment
      if (grain < 0.4) {
        // Valley: pigment settles in
        final settle = (0.4 - grain) * strength * 0.01;
        cell.granulation = (cell.granulation + settle).clamp(0.0, 1.0);
        cell.density = (cell.density + settle * 0.5).clamp(0.0, 1.0);
      } else if (grain > 0.6) {
        // Ridge: pigment washes away
        final wash = (grain - 0.6) * strength * 0.008;
        cell.density = (cell.density - wash).clamp(0.0, 1.0);
        cell.granulation = (cell.granulation - wash * 0.5).clamp(0.0, 1.0);
      }
    }
  }

  /// Phase 10: Wet-on-wet turbulence.
  ///
  /// When two adjacent cells are both highly wet, inject random velocity
  /// perturbation. This creates the chaotic mixing patterns seen when
  /// a wet stroke is applied onto still-wet paint.
  void _applyWetOnWetTurbulence() {
    final strength = config.wetOnWetTurbulence;

    for (final cell in grid.activeCells) {
      if (cell.wetness < 0.5 || cell.density < 0.05) continue;

      for (final (dx, dy) in _neighbors) {
        final neighbor = grid.getCell(cell.gx + dx, cell.gy + dy);
        if (neighbor == null || neighbor.wetness < 0.5) continue;

        // Both cells are wet → turbulence!
        final combinedWet = cell.wetness * neighbor.wetness;
        final turbMag = combinedWet * strength * 5.0;

        // Use deterministic noise as pseudo-random direction
        final noiseAngle = _hash(cell.gx + _tickCount, cell.gy) * 6.2832;
        final turbVx = math.cos(noiseAngle) * turbMag;
        final turbVy = math.sin(noiseAngle) * turbMag;

        cell.velocityX += turbVx;
        cell.velocityY += turbVy;
        neighbor.velocityX -= turbVx * 0.5;
        neighbor.velocityY -= turbVy * 0.5;
      }
    }
  }

  // ─── Diagnostics ────────────────────────────────────────────────────

  Map<String, dynamic> get diagnosticsMap => {
    'intensity': _intensity,
    'cellCount': grid.cellCount,
    'activeCells': grid.activeCells.length,
    'tickCount': _tickCount,
    'enabled': config.enabled,
    'tickUs': _lastTickUs,
    'lod':
        grid.activeCells.length > 5000
            ? 2
            : grid.activeCells.length > 2000
            ? 1
            : 0,
  };
}

// =============================================================================
// Internal helpers
// =============================================================================

class _DiffusionDelta {
  final int gx;
  final int gy;
  double addDensity = 0.0;
  double addR = 0.0;
  double addG = 0.0;
  double addB = 0.0;
  double addWetness = 0.0;

  _DiffusionDelta(this.gx, this.gy);
}
