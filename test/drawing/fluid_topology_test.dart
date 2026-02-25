import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/conscious_architecture.dart';
import 'package:nebula_engine/src/drawing/models/fluid_topology_config.dart';
import 'package:nebula_engine/src/drawing/models/fluid_grid.dart';
import 'package:nebula_engine/src/drawing/filters/fluid_topology_engine.dart';

void main() {
  // ===========================================================================
  // FluidTopologyConfig
  // ===========================================================================

  group('FluidTopologyConfig', () {
    test('default values are sensible', () {
      const config = FluidTopologyConfig();
      expect(config.diffusionRate, 0.08);
      expect(config.evaporationRate, 0.002);
      expect(config.surfaceTension, 0.3);
      expect(config.viscosity, 0.2);
      expect(config.gridResolution, 6);
      expect(config.enabled, true);
    });

    test('watercolor preset has fast diffusion', () {
      const wc = FluidTopologyConfig.watercolor;
      expect(wc.diffusionRate, greaterThan(0.1));
      expect(wc.viscosity, lessThan(0.1));
      expect(wc.surfaceTension, lessThan(0.2));
      expect(wc.enabled, true);
    });

    test('oilPaint preset has slow diffusion and high viscosity', () {
      const oil = FluidTopologyConfig.oilPaint;
      expect(oil.diffusionRate, lessThan(0.05));
      expect(oil.viscosity, greaterThan(0.8));
      expect(oil.surfaceTension, greaterThan(0.7));
    });

    test('disabled preset has enabled=false', () {
      const d = FluidTopologyConfig.disabled;
      expect(d.enabled, false);
    });

    test('serialization roundtrip preserves all fields', () {
      const original = FluidTopologyConfig(
        diffusionRate: 0.12,
        evaporationRate: 0.003,
        surfaceTension: 0.5,
        viscosity: 0.4,
        gridResolution: 8,
        maxActiveCells: 5000,
        tickRate: 20.0,
        pruneThreshold: 0.01,
        enabled: true,
      );

      final json = original.toJson();
      final restored = FluidTopologyConfig.fromJson(json);

      expect(restored.diffusionRate, original.diffusionRate);
      expect(restored.evaporationRate, original.evaporationRate);
      expect(restored.surfaceTension, original.surfaceTension);
      expect(restored.viscosity, original.viscosity);
      expect(restored.gridResolution, original.gridResolution);
      expect(restored.maxActiveCells, original.maxActiveCells);
      expect(restored.tickRate, original.tickRate);
      expect(restored.pruneThreshold, original.pruneThreshold);
      expect(restored.gravity, original.gravity);
      expect(restored.capillaryRate, original.capillaryRate);
      expect(restored.edgeDarkeningStrength, original.edgeDarkeningStrength);
      expect(restored.noiseAmplitude, original.noiseAmplitude);
      expect(restored.enabled, original.enabled);
    });

    test('fromJson handles null gracefully', () {
      final config = FluidTopologyConfig.fromJson(null);
      expect(config.diffusionRate, 0.08);
      expect(config.enabled, true);
    });

    test('copyWith creates modified copy', () {
      const original = FluidTopologyConfig();
      final modified = original.copyWith(diffusionRate: 0.5, enabled: false);

      expect(modified.diffusionRate, 0.5);
      expect(modified.enabled, false);
      expect(modified.viscosity, original.viscosity); // unchanged
    });
  });

  // ===========================================================================
  // FluidCell
  // ===========================================================================

  group('FluidCell', () {
    test('fresh cell is inactive', () {
      final cell = FluidCell(gx: 0, gy: 0);
      expect(cell.isActive, false);
      expect(cell.density, 0.0);
      expect(cell.wetness, 0.0);
    });

    test('cell with density is active', () {
      final cell = FluidCell(gx: 1, gy: 2, density: 0.5);
      expect(cell.isActive, true);
    });

    test('mixColor blends proportionally', () {
      final cell = FluidCell(
        gx: 0,
        gy: 0,
        pigmentR: 1.0,
        pigmentG: 0.0,
        pigmentB: 0.0,
      );

      // 50/50 mix of red and blue → purple
      cell.mixColor(0.0, 0.0, 1.0, 0.5);

      expect(cell.pigmentR, closeTo(0.5, 0.01));
      expect(cell.pigmentG, closeTo(0.0, 0.01));
      expect(cell.pigmentB, closeTo(0.5, 0.01));
    });

    test('clear resets all fields', () {
      final cell = FluidCell(
        gx: 0,
        gy: 0,
        density: 0.8,
        wetness: 0.5,
        pigmentR: 1.0,
      );
      cell.clear();
      expect(cell.density, 0.0);
      expect(cell.wetness, 0.0);
      expect(cell.pigmentR, 0.0);
    });

    test('serialization roundtrip', () {
      final original = FluidCell(
        gx: 5,
        gy: -3,
        pigmentR: 0.8,
        pigmentG: 0.2,
        pigmentB: 0.6,
        density: 0.7,
        wetness: 0.4,
        velocityX: 1.5,
        velocityY: -0.5,
        absorption: 0.1,
        lastUpdateMs: 12345.0,
      );

      final json = original.toJson();
      final restored = FluidCell.fromJson(json);

      expect(restored.gx, original.gx);
      expect(restored.gy, original.gy);
      expect(restored.pigmentR, original.pigmentR);
      expect(restored.density, original.density);
      expect(restored.wetness, original.wetness);
      expect(restored.velocityX, original.velocityX);
      expect(restored.absorption, original.absorption);
    });

    test('speed computes Euclidean magnitude', () {
      final cell = FluidCell(gx: 0, gy: 0, velocityX: 3.0, velocityY: 4.0);
      expect(cell.speed, closeTo(5.0, 0.001));
    });
  });

  // ===========================================================================
  // FluidGrid
  // ===========================================================================

  group('FluidGrid', () {
    test('starts empty', () {
      final grid = FluidGrid(resolution: 6);
      expect(grid.cellCount, 0);
      expect(grid.activeCells, isEmpty);
    });

    test('deposit creates cell at correct grid position', () {
      final grid = FluidGrid(resolution: 10);
      grid.deposit(25.0, 35.0, color: const Color(0xFFFF0000), amount: 0.5);

      // 25 ~/ 10 = 2, 35 ~/ 10 = 3
      final cell = grid.getCell(2, 3);
      expect(cell, isNotNull);
      expect(cell!.density, closeTo(0.5, 0.01));
      expect(cell.pigmentR, closeTo(1.0, 0.01));
      expect(cell.pigmentG, closeTo(0.0, 0.01));
    });

    test('getCellAt returns cell at world coordinates', () {
      final grid = FluidGrid(resolution: 10);
      grid.deposit(25.0, 35.0, color: const Color(0xFFFF0000), amount: 0.5);

      final cell = grid.getCellAt(25.0, 35.0);
      expect(cell, isNotNull);
      expect(cell!.density, greaterThan(0.0));
    });

    test('deposit on same cell accumulates density', () {
      final grid = FluidGrid(resolution: 10);

      grid.deposit(15.0, 15.0, color: const Color(0xFFFF0000), amount: 0.3);
      grid.deposit(
        18.0,
        18.0, // same grid cell (1, 1)
        color: const Color(0xFF0000FF),
        amount: 0.3,
      );

      final cell = grid.getCell(1, 1);
      expect(cell, isNotNull);
      expect(cell!.density, closeTo(0.6, 0.01));
      // Color should be blended
      expect(cell.pigmentB, greaterThan(0.0));
    });

    test('density is clamped to 1.0', () {
      final grid = FluidGrid(resolution: 10);

      for (int i = 0; i < 10; i++) {
        grid.deposit(5.0, 5.0, color: const Color(0xFFFF0000), amount: 0.3);
      }

      final cell = grid.getCell(0, 0);
      expect(cell!.density, 1.0);
    });

    test('depositAlongPath creates cells along stroke', () {
      final grid = FluidGrid(resolution: 10);
      final points = [
        const Offset(10, 10),
        const Offset(50, 10),
        const Offset(100, 10),
      ];

      grid.depositAlongPath(
        points,
        color: const Color(0xFF00FF00),
        width: 10.0,
        pressure: 0.5,
      );

      // Should have cells along x-axis from grid 1 to grid 10
      expect(grid.cellCount, greaterThan(3));

      // Cell near first point
      final cellNear = grid.getCell(1, 1);
      expect(cellNear, isNotNull);
      expect(cellNear!.density, greaterThan(0.0));
    });

    test('queryRect returns only cells in viewport', () {
      final grid = FluidGrid(resolution: 10);

      // Place cells at (0,0), (50,0), (200,0)
      grid.deposit(5.0, 5.0, color: const Color(0xFFFF0000), amount: 0.5);
      grid.deposit(55.0, 5.0, color: const Color(0xFF00FF00), amount: 0.5);
      grid.deposit(205.0, 5.0, color: const Color(0xFF0000FF), amount: 0.5);

      // Query only the first 100px
      final visible = grid.queryRect(const Rect.fromLTWH(0, 0, 100, 100));

      // Should include cells at grid (0,0) and (5,0) but not (20,0)
      expect(visible.length, 2);
    });

    test('prune removes dead cells', () {
      final grid = FluidGrid(resolution: 10);

      grid.deposit(5.0, 5.0, color: const Color(0xFFFF0000), amount: 0.5);
      grid.deposit(55.0, 5.0, color: const Color(0xFF00FF00), amount: 0.001);

      final before = grid.cellCount;
      final pruned = grid.prune(0.01, 0.01);

      expect(pruned, 1);
      expect(grid.cellCount, before - 1);
    });

    test('clear removes all cells', () {
      final grid = FluidGrid(resolution: 10);
      grid.deposit(5.0, 5.0, color: const Color(0xFFFF0000), amount: 0.5);
      grid.deposit(55.0, 5.0, color: const Color(0xFF00FF00), amount: 0.5);

      grid.clear();
      expect(grid.cellCount, 0);
      expect(grid.activeCells, isEmpty);
    });

    test('freeze returns independent copy', () {
      final grid = FluidGrid(resolution: 10);
      grid.deposit(5.0, 5.0, color: const Color(0xFFFF0000), amount: 0.5);

      final snapshot = grid.freeze();
      expect(snapshot.length, 1);

      // Mutate original — snapshot should be independent
      grid.clear();
      expect(snapshot.length, 1);
      expect(snapshot.first.density, closeTo(0.5, 0.01));
    });

    test('serialization roundtrip preserves grid', () {
      final grid = FluidGrid(resolution: 8);
      grid.deposit(10.0, 20.0, color: const Color(0xFFFF0000), amount: 0.6);
      grid.deposit(50.0, 50.0, color: const Color(0xFF0000FF), amount: 0.4);

      final json = grid.toJson();
      final restored = FluidGrid.fromJson(json);

      expect(restored.resolution, 8);
      expect(restored.cellCount, grid.cellCount);

      // Check a specific cell
      final cell = restored.getCell(1, 2);
      expect(cell, isNotNull);
      expect(cell!.density, closeTo(0.6, 0.01));
    });

    test('spatialKey is deterministic', () {
      final k1 = FluidGrid.spatialKey(10, 20);
      final k2 = FluidGrid.spatialKey(10, 20);
      final k3 = FluidGrid.spatialKey(20, 10);

      expect(k1, k2);
      expect(k1, isNot(k3));
    });

    test('spatialKey handles negative coordinates', () {
      final k1 = FluidGrid.spatialKey(-5, -10);
      final k2 = FluidGrid.spatialKey(-5, -10);
      final k3 = FluidGrid.spatialKey(5, 10);

      expect(k1, k2);
      expect(k1, isNot(k3));
    });
  });

  // ===========================================================================
  // FluidTopologyEngine
  // ===========================================================================

  group('FluidTopologyEngine', () {
    late FluidTopologyEngine engine;

    setUp(() {
      engine = FluidTopologyEngine(
        config: const FluidTopologyConfig(
          diffusionRate: 0.15,
          evaporationRate: 0.002,
          viscosity: 0.1,
        ),
      );
    });

    tearDown(() {
      engine.dispose();
    });

    test('initializes with correct subsystem properties', () {
      expect(engine.name, 'FluidTopologyEngine');
      expect(engine.isActive, true);
      expect(FluidTopologyEngine.instance, engine);
    });

    test('dispose clears instance', () {
      engine.dispose();
      expect(FluidTopologyEngine.instance, isNull);
    });

    test('depositStroke adds pigment to grid', () {
      FluidTopologyEngine.depositStroke(
        [const Offset(50, 50), const Offset(60, 50)],
        const Color(0xFFFF0000),
        10.0,
        0.5,
      );

      expect(engine.grid.cellCount, greaterThan(0));
      expect(engine.grid.activeCells, isNotEmpty);
    });

    test('depositStroke is no-op when disabled', () {
      engine.config = const FluidTopologyConfig(enabled: false);

      FluidTopologyEngine.depositStroke(
        [const Offset(50, 50), const Offset(60, 50)],
        const Color(0xFFFF0000),
        10.0,
        0.5,
      );

      expect(engine.grid.cellCount, 0);
    });

    test('diffusion spreads pigment to neighbors', () {
      // Deposit concentrated pigment
      engine.grid.deposit(
        50.0,
        50.0,
        color: const Color(0xFFFF0000),
        amount: 0.8,
        wetness: 0.9,
        nowMs: 1000.0,
      );

      final centerCell = engine.grid.getCellAt(50.0, 50.0)!;
      final initialDensity = centerCell.density;

      // Run several ticks
      for (int i = 0; i < 10; i++) {
        engine.tick(1000.0 + i * 33.0);
      }

      // Center should have less density (spread to neighbors)
      expect(centerCell.density, lessThan(initialDensity));

      // Neighbors should have gained some density
      final gx = 50 ~/ engine.grid.resolution;
      final gy = 50 ~/ engine.grid.resolution;
      final neighbor = engine.grid.getCell(gx + 1, gy);
      expect(neighbor, isNotNull);
      expect(neighbor!.density, greaterThan(0.0));
    });

    test('drying reduces wetness over time', () {
      engine.grid.deposit(
        50.0,
        50.0,
        color: const Color(0xFFFF0000),
        amount: 0.5,
        wetness: 0.9,
        nowMs: 0.0,
      );

      final cell = engine.grid.getCellAt(50.0, 50.0)!;
      final initialWetness = cell.wetness;

      // Tick with large time delta to see drying
      engine.tick(5000.0);

      expect(cell.wetness, lessThan(initialWetness));
    });

    test('pruning removes dead cells', () {
      // Add a very faint deposit
      engine.grid.deposit(
        50.0,
        50.0,
        color: const Color(0xFFFF0000),
        amount: 0.003,
        nowMs: 0.0,
      );

      expect(engine.grid.cellCount, greaterThan(0));

      // Prune with threshold above the deposit
      final pruned = engine.grid.prune(0.01, 0.01);
      expect(pruned, greaterThan(0));
    });

    test('tick is no-op when intensity is zero', () {
      engine.grid.deposit(
        50.0,
        50.0,
        color: const Color(0xFFFF0000),
        amount: 0.5,
        wetness: 0.9,
        nowMs: 0.0,
      );

      final cell = engine.grid.getCellAt(50.0, 50.0)!;
      final densityBefore = cell.density;

      // Simulate disabled context
      engine.onContextChanged(
        const EngineContext(
          activeTool: 'select',
          zoom: 1.0,
          viewport: Rect.fromLTWH(0, 0, 800, 600),
          panVelocity: Offset.zero,
          isDrawing: false,
          strokeCount: 0,
          isPdfDocument: false,
        ),
      );

      engine.tick(1000.0);

      // Density should not change
      expect(cell.density, densityBefore);
    });

    test('diagnosticsMap returns expected keys', () {
      final diag = engine.diagnosticsMap;
      expect(diag.containsKey('intensity'), true);
      expect(diag.containsKey('cellCount'), true);
      expect(diag.containsKey('activeCells'), true);
      expect(diag.containsKey('tickCount'), true);
      expect(diag.containsKey('enabled'), true);
      expect(diag.containsKey('gravity'), true);
      expect(diag.containsKey('edgeDarkening'), true);
    });

    test('gravity adds downward velocity to wet cells', () {
      engine.config = const FluidTopologyConfig(
        gravity: 20.0,
        diffusionRate: 0.0, // disable diffusion
        viscosity: 0.0,
      );

      engine.grid.deposit(
        50.0,
        50.0,
        color: const Color(0xFFFF0000),
        amount: 0.5,
        wetness: 0.9,
        nowMs: 0.0,
      );

      final cell = engine.grid.getCellAt(50.0, 50.0)!;
      expect(cell.velocityY, 0.0);

      engine.tick(33.0); // ~30ms

      // Gravity should have added downward velocity
      expect(cell.velocityY, greaterThan(0.0));
    });

    test('capillary flow spreads wetness to dry neighbors', () {
      engine.config = const FluidTopologyConfig(
        capillaryRate: 0.2,
        diffusionRate: 0.0,
        gravity: 0.0,
      );

      engine.grid.deposit(
        50.0,
        50.0,
        color: const Color(0xFFFF0000),
        amount: 0.5,
        wetness: 0.9,
        nowMs: 0.0,
      );

      final gx = 50 ~/ engine.grid.resolution;
      final gy = 50 ~/ engine.grid.resolution;

      // Run several ticks
      for (int i = 0; i < 5; i++) {
        engine.tick(i * 33.0);
      }

      // Neighbor should have gained wetness from capillary wicking
      final neighbor = engine.grid.getCell(gx + 1, gy);
      expect(neighbor, isNotNull);
      expect(neighbor!.wetness, greaterThan(0.0));
    });

    test('velocity injection from stroke path', () {
      final grid = FluidGrid(resolution: 10);

      // Deposit along a horizontal path — should inject rightward velocity
      grid.depositAlongPath(
        [const Offset(10, 50), const Offset(100, 50)],
        color: const Color(0xFFFF0000),
        width: 10.0,
        pressure: 0.8,
      );

      // Check a cell near the middle — should have positive velocityX
      final cell = grid.getCellAt(50.0, 50.0);
      expect(cell, isNotNull);
      expect(cell!.velocityX, greaterThan(0.0));
    });

    test('8-connected diffusion spreads diagonally', () {
      engine.config = const FluidTopologyConfig(
        diffusionRate: 0.3,
        viscosity: 0.0,
        surfaceTension: 0.0,
        gravity: 0.0,
        noiseAmplitude: 0.0, // no noise for deterministic test
      );

      engine.grid.deposit(
        50.0,
        50.0,
        color: const Color(0xFFFF0000),
        amount: 0.9,
        wetness: 0.9,
        nowMs: 0.0,
      );

      final gx = 50 ~/ engine.grid.resolution;
      final gy = 50 ~/ engine.grid.resolution;

      for (int i = 0; i < 5; i++) {
        engine.tick(i * 33.0);
      }

      // Diagonal neighbor should have gained density (8-connected)
      final diag = engine.grid.getCell(gx + 1, gy + 1);
      expect(diag, isNotNull);
      expect(diag!.density, greaterThan(0.0));
    });

    test('watercolor preset has stronger effects than oil', () {
      const wc = FluidTopologyConfig.watercolor;
      const oil = FluidTopologyConfig.oilPaint;

      expect(wc.gravity, greaterThan(oil.gravity));
      expect(wc.capillaryRate, greaterThan(oil.capillaryRate));
      expect(wc.edgeDarkeningStrength, greaterThan(oil.edgeDarkeningStrength));
      expect(wc.noiseAmplitude, greaterThan(oil.noiseAmplitude));
    });
  });
}
