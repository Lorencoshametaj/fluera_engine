/// 🌊 FLUID TOPOLOGY RENDERER — GPU compositing of the fluid field.
///
/// Renders visible cells of the [FluidGrid] as colored quads using
/// the `fluid_topology.frag` shader, or falls back to CPU Paint
/// if the shader is unavailable.
///
/// Self-contained: loads its own shader program independently from
/// [ShaderBrushService] to avoid modifying the blindato service class.
///
/// ## Performance
///
/// - Only renders cells within the viewport (O(visible cells))
/// - Falls back to CPU drawRect with colored paint if shader unavailable
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../drawing/models/fluid_grid.dart';

/// Renders the fluid topology field onto a canvas.
///
/// Loads the `fluid_topology.frag` shader on first use and renders
/// visible cells as colored quads. Falls back to CPU rendering if
/// the shader is unavailable (e.g., in tests or on unsupported platforms).
class FluidTopologyRenderer {
  // ─── Singleton ──────────────────────────────────────────────────────

  static final FluidTopologyRenderer _instance = FluidTopologyRenderer._();
  static FluidTopologyRenderer get instance => _instance;
  FluidTopologyRenderer._();

  // ─── Shader state ───────────────────────────────────────────────────

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  bool _initAttempted = false;

  /// Whether the GPU shader is loaded and ready.
  bool get isAvailable => _shader != null;

  /// Initialize the shader. Safe to call multiple times.
  Future<void> initialize() async {
    if (_initAttempted) return;
    _initAttempted = true;

    try {
      const prefix = 'packages/fluera_engine/shaders';
      _program = await ui.FragmentProgram.fromAsset(
        '$prefix/fluid_topology.frag',
      );
      _shader = _program!.fragmentShader();
    } catch (_) {
      // Shader unavailable — CPU fallback will be used
      _shader = null;
    }
  }

  // ─── Rendering ──────────────────────────────────────────────────────

  /// Render the fluid topology overlay for cells within [viewport].
  ///
  /// Iterates visible cells from [grid] and draws each as a colored quad.
  /// Uses GPU shader when available, otherwise falls back to CPU rendering.
  void renderFluidOverlay(Canvas canvas, FluidGrid grid, Rect viewport) {
    final cells = grid.queryRect(viewport);
    if (cells.isEmpty) return;

    final cellSize = grid.resolution.toDouble();

    if (_shader != null) {
      _renderWithShader(canvas, cells, cellSize, _shader!, viewport);
    } else {
      _renderCpuFallback(canvas, cells, cellSize);
    }
  }

  /// GPU path: render each cell via fragment shader.
  void _renderWithShader(
    Canvas canvas,
    List<FluidCell> cells,
    double cellSize,
    ui.FragmentShader shader,
    Rect viewport,
  ) {
    final paint = Paint()..shader = shader;

    for (final cell in cells) {
      if (cell.density < 0.01) continue;

      final cellX = cell.gx * cellSize;
      final cellY = cell.gy * cellSize;
      final cellRect = Rect.fromLTWH(cellX, cellY, cellSize, cellSize);

      // Viewport culling (redundant with queryRect but cheap guard)
      if (!cellRect.overlaps(viewport)) continue;

      int idx = 0;
      shader.setFloat(idx++, 0.0); // uCellX (local)
      shader.setFloat(idx++, 0.0); // uCellY (local)
      shader.setFloat(idx++, cellSize); // uCellSize
      shader.setFloat(idx++, cell.pigmentR); // uPigmentR
      shader.setFloat(idx++, cell.pigmentG); // uPigmentG
      shader.setFloat(idx++, cell.pigmentB); // uPigmentB
      shader.setFloat(idx++, cell.density); // uDensity
      shader.setFloat(idx++, cell.wetness); // uWetness
      shader.setFloat(idx++, cell.granulation); // uGranulation
      shader.setFloat(idx++, cell.absorption); // uAbsorption
      shader.setFloat(idx++, (cell.gx * 17 + cell.gy * 31).toDouble()); // uSeed

      canvas.translate(cellX, cellY);
      canvas.drawRect(Rect.fromLTWH(0, 0, cellSize, cellSize), paint);
      canvas.translate(-cellX, -cellY);
    }
  }

  /// CPU fallback: simple colored rectangles with density-modulated alpha.
  void _renderCpuFallback(
    Canvas canvas,
    List<FluidCell> cells,
    double cellSize,
  ) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final cell in cells) {
      if (cell.density < 0.01) continue;

      final alpha = (cell.density * 0.6).clamp(0.0, 1.0);
      paint.color = Color.from(
        alpha: alpha,
        red: cell.pigmentR,
        green: cell.pigmentG,
        blue: cell.pigmentB,
      );

      final cellX = cell.gx * cellSize;
      final cellY = cell.gy * cellSize;

      canvas.drawRect(Rect.fromLTWH(cellX, cellY, cellSize, cellSize), paint);
    }
  }

  // ─── Cleanup ────────────────────────────────────────────────────────

  /// Dispose GPU resources.
  void dispose() {
    _shader?.dispose();
    _shader = null;
    _program = null;
    _initAttempted = false;
  }
}
