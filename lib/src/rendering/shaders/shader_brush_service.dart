import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

import '../optimization/optimization.dart';
import '../../core/engine_scope.dart';
import '../../core/engine_error.dart';

/// 🎨 SHADER BRUSH SERVICE — GPU-accelerated brush rendering
///
/// ARCHITECTURE:
/// - Loads GLSL fragment shaders at startup
/// - Per-segment quad rendering: 1 drawRect per segment → O(1) per pixel
/// - Falls back to CPU rendering if GPU unavailable
/// - Singleton — shared across all painters
///
/// FEATURES:
/// - Pencil: graphite noise texture, pressure gradient
/// - Fountain pen: ink bleed, fiber texture, velocity accumulation
///
/// Render methods are provided via extensions:
/// - [ShaderPencilRenderer] in `shader_pencil_renderer.dart`
/// - [ShaderFountainPenRenderer] in `shader_fountain_pen_renderer.dart`
/// - [ShaderStampRenderer] in `shader_stamp_renderer.dart`
/// - [ShaderTextureRenderer] in `shader_texture_renderer.dart`
/// - [ShaderWatercolorRenderer] in `shader_watercolor_renderer.dart`
/// - [ShaderMarkerRenderer] in `shader_marker_renderer.dart`
/// - [ShaderCharcoalRenderer] in `shader_charcoal_renderer.dart`
/// - [ShaderOilPaintRenderer] in `shader_oil_paint_renderer.dart`
/// - [ShaderSprayPaintRenderer] in `shader_spray_paint_renderer.dart`
/// - [ShaderNeonGlowRenderer] in `shader_neon_glow_renderer.dart`
/// - [ShaderInkWashRenderer] in `shader_ink_wash_renderer.dart`
class ShaderBrushService {
  // ═══════════════════════════════════════════════════════════════════════════
  // SINGLETON
  // ═══════════════════════════════════════════════════════════════════════════
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static ShaderBrushService get instance =>
      EngineScope.current.shaderBrushService;

  /// Creates a new instance (used by [EngineScope]).
  ShaderBrushService.create();

  // ═══════════════════════════════════════════════════════════════════════════
  // SHADER STATE
  // ═══════════════════════════════════════════════════════════════════════════

  ui.FragmentProgram? _pencilProgram;
  ui.FragmentProgram? _fountainPenProgram;
  ui.FragmentProgram? _textureOverlayProgram;
  ui.FragmentProgram? _brushStampProgram;
  ui.FragmentProgram? _watercolorProgram;
  ui.FragmentProgram? _markerProgram;
  ui.FragmentProgram? _charcoalProgram;
  ui.FragmentProgram? _oilPaintProgram;
  ui.FragmentProgram? _sprayPaintProgram;
  ui.FragmentProgram? _neonGlowProgram;
  ui.FragmentProgram? _inkWashProgram;

  bool _initialized = false;
  bool _initAttempted = false;

  /// Whether GPU shaders are loaded and ready
  bool get isAvailable => _initialized;

  /// Whether the texture overlay GPU shader is ready (always available)
  bool get isTextureOverlayAvailable => _textureOverlayShader != null;

  /// Whether Pro shader effects are enabled (currently always true).
  bool get isProEnabled => _initialized;

  // Reusable shader instances (avoid re-creation per frame)
  // Exposed via getters for extension method access.
  ui.FragmentShader? _pencilShader;
  ui.FragmentShader? _fountainPenShader;
  ui.FragmentShader? _textureOverlayShader;
  ui.FragmentShader? _brushStampShader;
  ui.FragmentShader? _watercolorShader;
  ui.FragmentShader? _markerShader;
  ui.FragmentShader? _charcoalShader;
  ui.FragmentShader? _oilPaintShader;
  ui.FragmentShader? _sprayPaintShader;
  ui.FragmentShader? _neonGlowShader;
  ui.FragmentShader? _inkWashShader;

  /// Shader accessors for renderer extensions.
  @internal
  ui.FragmentShader? get pencilShader => _pencilShader;
  @internal
  ui.FragmentShader? get fountainPenShader => _fountainPenShader;
  @internal
  ui.FragmentShader? get textureOverlayShader => _textureOverlayShader;
  @internal
  ui.FragmentShader? get brushStampShader => _brushStampShader;
  @internal
  ui.FragmentShader? get watercolorShader => _watercolorShader;
  @internal
  ui.FragmentShader? get markerShader => _markerShader;
  @internal
  ui.FragmentShader? get charcoalShader => _charcoalShader;
  @internal
  ui.FragmentShader? get oilPaintShader => _oilPaintShader;
  @internal
  ui.FragmentShader? get sprayPaintShader => _sprayPaintShader;
  @internal
  ui.FragmentShader? get neonGlowShader => _neonGlowShader;
  @internal
  ui.FragmentShader? get inkWashShader => _inkWashShader;

  /// Whether the stamp brush GPU shader is ready
  bool get isStampAvailable => _initialized && _brushStampShader != null;

  // Random seed for noise variation (changes per stroke)
  final math.Random _random = math.Random();
  @internal
  math.Random get random => _random;

  // Dummy 1x1 image for sampler fallback (required by Flutter when shader
  // declares sampler2D but no texture is provided)
  ui.Image? _dummyImage;
  @internal
  ui.Image get fallbackImage {
    if (_dummyImage == null) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()..color = const Color(0x00000000),
      );
      _dummyImage = recorder.endRecording().toImageSync(1, 1);
    }
    return _dummyImage!;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> initialize() async {
    if (_initAttempted) return;
    _initAttempted = true;

    // 🎨 GPU shaders enabled — path fix: packages/nebula_engine/shaders/

    try {
      // Load all shaders in parallel
      // 🎯 Package-prefixed paths: required when nebula_engine is a
      // dependency (not the root app). Flutter resolves shader assets
      // via 'packages/<package_name>/<path>' for package dependencies.
      const prefix = 'packages/nebula_engine/shaders';
      final results = await Future.wait([
        ui.FragmentProgram.fromAsset('$prefix/pencil_pro.frag'),
        ui.FragmentProgram.fromAsset('$prefix/fountain_pen_pro.frag'),
        ui.FragmentProgram.fromAsset('$prefix/texture_overlay.frag'),
        ui.FragmentProgram.fromAsset('$prefix/brush_stamp.frag'),
        ui.FragmentProgram.fromAsset('$prefix/watercolor.frag'),
        ui.FragmentProgram.fromAsset('$prefix/marker.frag'),
        ui.FragmentProgram.fromAsset('$prefix/charcoal.frag'),
        ui.FragmentProgram.fromAsset('$prefix/oil_paint.frag'),
        ui.FragmentProgram.fromAsset('$prefix/spray_paint.frag'),
        ui.FragmentProgram.fromAsset('$prefix/neon_glow.frag'),
        ui.FragmentProgram.fromAsset('$prefix/ink_wash.frag'),
      ]);

      _pencilProgram = results[0];
      _fountainPenProgram = results[1];
      _textureOverlayProgram = results[2];
      _brushStampProgram = results[3];
      _watercolorProgram = results[4];
      _markerProgram = results[5];
      _charcoalProgram = results[6];
      _oilPaintProgram = results[7];
      _sprayPaintProgram = results[8];
      _neonGlowProgram = results[9];
      _inkWashProgram = results[10];

      _pencilShader = _pencilProgram!.fragmentShader();
      _fountainPenShader = _fountainPenProgram!.fragmentShader();
      _textureOverlayShader = _textureOverlayProgram!.fragmentShader();
      _brushStampShader = _brushStampProgram!.fragmentShader();
      _watercolorShader = _watercolorProgram!.fragmentShader();
      _markerShader = _markerProgram!.fragmentShader();
      _charcoalShader = _charcoalProgram!.fragmentShader();
      _oilPaintShader = _oilPaintProgram!.fragmentShader();
      _sprayPaintShader = _sprayPaintProgram!.fragmentShader();
      _neonGlowShader = _neonGlowProgram!.fragmentShader();
      _inkWashShader = _inkWashProgram!.fragmentShader();

      _initialized = true;
    } catch (e, stack) {
      // GPU shaders unavailable — CPU fallback will be used
      _initialized = false;
      if (EngineScope.hasScope) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            severity: ErrorSeverity.transient,
            domain: ErrorDomain.rendering,
            source:
                'ShaderBrushService.initialize: Failed to load GPU shaders. CPU fallback active.',
            original: e,
            stack: stack,
          ),
        );
      }
    }
  }

  /// Pre-compile shaders by drawing a transparent 1px rect.
  /// Call after initialize() to avoid jank on first stroke.
  void warmUpShaders(Canvas canvas) {
    if (!_initialized) return;
    try {
      final transparentPaint = Paint()..color = const Color(0x00000000);
      final warmUpRect = const Rect.fromLTWH(-9999, -9999, 1, 1);

      for (final shader in [
        _pencilShader,
        _fountainPenShader,
        _textureOverlayShader,
        _brushStampShader,
        _watercolorShader,
        _markerShader,
        _charcoalShader,
        _oilPaintShader,
        _sprayPaintShader,
        _neonGlowShader,
        _inkWashShader,
      ]) {
        if (shader != null) {
          try {
            // Set minimum required uniforms to avoid out-of-bounds
            for (int i = 0; i < 22; i++) {
              shader.setFloat(i, 0.0);
            }
            // texture_overlay has sampler2D — must set fallback image
            if (shader == _textureOverlayShader) {
              shader.setImageSampler(0, fallbackImage);
            }
            transparentPaint.shader = shader;
            canvas.drawRect(warmUpRect, transparentPaint);
          } catch (_) {
            // Individual shader warmup failure is non-fatal
          }
        }
      }
    } catch (e, stack) {
      _initialized = false; // Disable if GPU crashes on warmup
      if (EngineScope.hasScope) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            severity: ErrorSeverity.transient,
            domain: ErrorDomain.rendering,
            source:
                'ShaderBrushService.warmUpShaders: Shader warmup failed. Falling back to CPU.',
            original: e,
            stack: stack,
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHADER WARM-UP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Warm up all shaders with a tiny invisible draw.
  ///
  /// Call once from a painter's first paint() to trigger GPU program
  /// compilation upfront, preventing 50-200ms jank on the first real stroke.
  bool _warmedUp = false;
  void warmUp(Canvas canvas) {
    if (_warmedUp || !_initialized) return;
    _warmedUp = true;

    final shaders = [
      _pencilShader,
      _fountainPenShader,
      _textureOverlayShader,
      _brushStampShader,
      _watercolorShader,
      _markerShader,
      _charcoalShader,
      _oilPaintShader,
      _sprayPaintShader,
      _neonGlowShader,
      _inkWashShader,
    ];
    for (final shader in shaders) {
      if (shader == null) continue;
      try {
        // Set minimal uniforms (all zeros is fine for warm-up)
        for (int i = 0; i < 16; i++) {
          shader.setFloat(i, 0.0);
        }
        // texture_overlay has sampler2D — must set fallback image
        if (shader == _textureOverlayShader) {
          shader.setImageSampler(0, fallbackImage);
        }
        final paint = Paint()..shader = shader;
        // Clip to empty rect → zero pixels actually rendered, but GPU compiles
        canvas.save();
        canvas.clipRect(Rect.zero);
        canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), paint);
        canvas.restore();
      } catch (_) {
        // Individual shader warmup failure is non-fatal
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GEOMETRY HELPERS (shared by renderer extensions)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pre-compute all offsets once to avoid redundant getOffset() calls.
  @internal
  List<Offset> preComputeOffsets(List<dynamic> points) {
    final offsets = List<Offset>.filled(points.length, Offset.zero);
    for (int i = 0; i < points.length; i++) {
      offsets[i] = StrokeOptimizer.getOffset(points[i]);
    }
    return offsets;
  }

  /// Coalesce near-collinear consecutive points to reduce draw calls.
  /// Uses pre-cached offsets to avoid redundant getOffset() calls.
  @internal
  List<int> coalesceIndices(List<Offset> offsets, {double threshold = 0.15}) {
    if (offsets.length <= 3) {
      return List.generate(offsets.length, (i) => i);
    }

    final indices = <int>[0];
    var prevDir = segmentDirFromOffsets(offsets, 0);

    for (int i = 1; i < offsets.length - 1; i++) {
      final dir = segmentDirFromOffsets(offsets, i);
      final cross = (prevDir.dx * dir.dy - prevDir.dy * dir.dx).abs();
      if (cross > threshold) {
        indices.add(i);
        prevDir = dir;
      }
    }

    indices.add(offsets.length - 1);
    return indices;
  }

  /// Normalized direction between offsets[i] and offsets[i+1].
  @internal
  Offset segmentDirFromOffsets(List<Offset> offsets, int i) {
    if (i >= offsets.length - 1) return const Offset(1, 0);
    final d = offsets[i + 1] - offsets[i];
    final len = d.distance;
    return len > 0.01 ? Offset(d.dx / len, d.dy / len) : const Offset(1, 0);
  }

  /// Extract pressure from a raw point (handles both Offset and ProDrawingPoint).
  @internal
  double getPressure(dynamic point) {
    if (point is Offset) return 0.5;
    return (point.pressure ?? 0.5) as double;
  }

  /// Calculate normalized velocities only for coalesced index pairs.
  /// Much cheaper than computing for all N original points.
  @internal
  List<double> calculateVelocitiesForIndices(
    List<Offset> offsets,
    List<int> indices,
  ) {
    if (indices.length < 2) return [0.0];

    final velocities = List<double>.filled(indices.length, 0.0);
    double maxVel = 0.0;

    for (int k = 0; k < indices.length - 1; k++) {
      final vel = (offsets[indices[k + 1]] - offsets[indices[k]]).distance;
      velocities[k] = vel;
      if (vel > maxVel) maxVel = vel;
    }

    if (maxVel > 0) {
      for (int k = 0; k < velocities.length; k++) {
        velocities[k] /= maxVel;
      }
    }

    return velocities;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  void dispose() {
    _pencilShader?.dispose();
    _fountainPenShader?.dispose();
    _textureOverlayShader?.dispose();
    _brushStampShader?.dispose();
    _watercolorShader?.dispose();
    _markerShader?.dispose();
    _charcoalShader?.dispose();
    _oilPaintShader?.dispose();
    _sprayPaintShader?.dispose();
    _neonGlowShader?.dispose();
    _inkWashShader?.dispose();
    _pencilShader = null;
    _fountainPenShader = null;
    _textureOverlayShader = null;
    _brushStampShader = null;
    _watercolorShader = null;
    _markerShader = null;
    _charcoalShader = null;
    _oilPaintShader = null;
    _sprayPaintShader = null;
    _neonGlowShader = null;
    _inkWashShader = null;
    _pencilProgram = null;
    _fountainPenProgram = null;
    _textureOverlayProgram = null;
    _brushStampProgram = null;
    _watercolorProgram = null;
    _markerProgram = null;
    _charcoalProgram = null;
    _oilPaintProgram = null;
    _sprayPaintProgram = null;
    _neonGlowProgram = null;
    _inkWashProgram = null;
    _initialized = false;
  }
}
