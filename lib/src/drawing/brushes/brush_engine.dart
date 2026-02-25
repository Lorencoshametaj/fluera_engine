import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../models/pro_brush_settings.dart';
import '../models/pro_drawing_point.dart';
import '../models/surface_material.dart';
import '../models/wetness_state.dart';
import '../../rendering/shaders/shader_brush_service.dart';
import '../../rendering/shaders/shader_stamp_renderer.dart';
import '../../rendering/shaders/shader_texture_renderer.dart';
import '../../rendering/gpu/gpu_texture_service.dart';
import '../../rendering/shaders/shader_watercolor_renderer.dart';
import '../../rendering/shaders/shader_marker_renderer.dart';
import '../../rendering/shaders/shader_charcoal_renderer.dart';
import '../../rendering/shaders/shader_oil_paint_renderer.dart';
import '../../rendering/shaders/shader_spray_paint_renderer.dart';
import '../../rendering/shaders/shader_neon_glow_renderer.dart';
import '../../rendering/shaders/shader_ink_wash_renderer.dart';
import '../../systems/organic_behavior_engine.dart';
import '../filters/organic_noise.dart';
import '../filters/fluid_topology_engine.dart';
import './brushes.dart';

/// 🎨 Unified Brush Engine — Single point of dispatch
///
/// Replace le 7+ duplicazioni identiche di `_drawStroke/switch(penType)`
/// scattered across renderers, painters, optimizers and cache managers.
///
/// PRIMA: ogni file conteneva ~60 righe di switch/case identico.
/// ORA:   ogni file chiama `BrushEngine.renderStroke()` in 1 riga.
///
/// Adding a new brush requires:
///   1. Create the brush class (es. `MarkerBrush`)
///   2. Add the case in `ProPenType`
///   3. Add the case HERE — automatically available everywhere.
class BrushEngine {
  BrushEngine._(); // Non-instantiable

  // 🚀 Pre-allocated buffer for pressure-remapped points (avoids per-frame allocation)
  static List<dynamic> _remappedPointsBuffer = List<dynamic>.filled(2048, null);

  // 🚀 Pre-allocated buffer for organic-modulated points (avoids per-frame allocation)
  static List<dynamic> _organicPointsBuffer = List<dynamic>.filled(2048, null);

  // 🚀 Incremental bounds tracking for live strokes
  static double _liveMinX = double.infinity;
  static double _liveMinY = double.infinity;
  static double _liveMaxX = double.negativeInfinity;
  static double _liveMaxY = double.negativeInfinity;
  static int _liveBoundsPointCount = 0;

  // 🌱 Canvas surface wetness state — tracks drying over time
  static final WetnessState _canvasWetness = WetnessState();

  /// 🧬 Active canvas surface material.
  /// Set by the canvas when the user changes surface. Used as fallback
  /// when `renderStroke` is called without an explicit `surface` param
  /// (tile cache, scene graph renderer, etc.).
  static SurfaceMaterial? activeSurface;

  /// Reset live bounds tracking (call when stroke ends/starts).
  static void resetLiveBounds() {
    _liveMinX = double.infinity;
    _liveMinY = double.infinity;
    _liveMaxX = double.negativeInfinity;
    _liveMaxY = double.negativeInfinity;
    _liveBoundsPointCount = 0;
  }

  /// 🎨 ColorFilter statico: converte luminanza RGB → alpha (invertito).
  /// Aree scure of the texture → alpha alto → more erosione.
  /// Riusato per tutti gli stroke (immutabile).
  static final _luminanceToAlpha = ui.ColorFilter.matrix(<double>[
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    -0.299,
    -0.587,
    -0.114,
    0,
    255,
  ]);

  /// 🛡️ Current rendering engine version.
  ///
  /// Incrementare when modifica il COMPORTAMENTO di un brush
  /// (not when adding new brushes — those are backward compatible).
  ///
  /// Cronologia:
  /// - v1: strokes pre-versioning (no 'ev' tag in JSON)
  /// - v2: first tagged version (Feb 2026) — same logic as v1
  ///
  /// Quando cambi un algoritmo di brush:
  /// 1. Incrementa [currentEngineVersion]
  /// 2. Move old code into a method `_renderStrokeVN()`
  /// 3. Add routing in block `engineVersion` below
  static const int currentEngineVersion = 2;

  /// Render uno stroke usando il brush corretto based onl [penType].
  ///
  /// This is the ONLY point where pen type → brush dispatch occurs.
  /// All renderers, painters, cache managers and optimizers delegate here.
  ///
  /// [engineVersion] Versione del motore che ha prodotto lo stroke.
  ///   Se omesso, usa [currentEngineVersion] (stroke live/nuovo).
  ///   For strokes loaded from disk, passare `stroke.engineVersion`.
  static void renderStroke(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth,
    ProPenType penType,
    ProBrushSettings settings, {
    bool isLive = false,
    ui.BlendMode? blendMode,
    int? engineVersion,
    int drawFromIndex = 0,
    SurfaceMaterial? surface,
  }) {
    if (points.isEmpty) return;

    // 🧬 Fallback: use active canvas surface when caller doesn't pass one
    final effectiveSurface = surface ?? activeSurface;

    // 🛡️ Migration routing — when an algorithm changes in the future,
    // route to the renderer of the correct version here.
    // Currently v1 and v2 use the same renderer (no breaking changes).

    // 🎛️ Phase 4A: Remap pressures through the pressure curve
    // 🚀 PERF: Skip remapping during live drawing — brush handles pressure
    // internally, and the fast texture overlay samples only 3 points.
    // Full quality remapping is applied on finalization (isLive = false).
    List<dynamic> effectivePoints = points;
    if (!settings.pressureCurve.isLinear) {
      final n = points.length;
      if (_remappedPointsBuffer.length < n) {
        _remappedPointsBuffer = List<dynamic>.filled(n * 2, null);
      }
      for (int i = 0; i < n; i++) {
        final p = points[i];
        if (p is ProDrawingPoint) {
          final remapped = settings.pressureCurve.evaluate(p.pressure);
          _remappedPointsBuffer[i] = p.copyWith(pressure: remapped);
        } else {
          _remappedPointsBuffer[i] = p;
        }
      }
      // Use sublist view — no copy needed for finalization path
      effectivePoints = _remappedPointsBuffer.sublist(0, n);
    }

    // 🎯 Phase 4B: Stroke stabilizer — now applied in real-time
    // via DrawingInputHandler (not post-hoc here)

    // 🌱 Phase 4C: Organic micro-variation — biological tremor, fatigue,
    // breathing. Zero-cost when OrganicBehaviorEngine.intensity == 0.
    if (OrganicBehaviorEngine.tremorEnabled && effectivePoints.length > 3) {
      effectivePoints = _applyOrganicModulation(
        effectivePoints,
        baseWidth,
        penType,
      );
    }

    // 🧬 Surface material: compute modifiers if surface is provided.
    // 🌱 Include current canvas wetness for wet-on-wet interaction.
    // 🚀 PERF: derive timestamp from points instead of DateTime.now() syscall
    final double nowMs;
    if (effectivePoints.length > 1) {
      final midP = effectivePoints[effectivePoints.length ~/ 2];
      nowMs =
          midP is ProDrawingPoint
              ? midP.timestamp.toDouble()
              : DateTime.now().millisecondsSinceEpoch.toDouble();
    } else {
      nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    }
    final currentWetness = _canvasWetness.getWetness(nowMs: nowMs);
    final materialMods = effectiveSurface?.computeModifiers(
      pressure: 0.5, // average pressure for compositing decision
      velocity: 500.0,
      wetness: currentWetness,
    );
    final effectiveWidth =
        materialMods != null
            ? baseWidth * materialMods.widthMultiplier
            : baseWidth;

    // 🎨 Per-brush blend mode: wrap in saveLayer for compositing
    final effectiveBlendMode = blendMode ?? _defaultBlendMode(penType);
    // 🎨 Per-brush blend mode OR texture: wrap in saveLayer for compositing.
    // Texture overlay uses BlendMode.dstOut which needs layer isolation.
    // 🧬 Surface grain also requires texture compositing.
    final hasBrushTexture =
        settings.textureType != 'none' && settings.textureIntensity > 0;
    // ⚠️ Surface-aware shader brushes handle grain in the fragment shader —
    // skip the surface grain compositing layer for them to prevent
    // live/finalized mismatch (different saveLayer bounds = different alpha).
    final bool _shaderHandlesSurface =
        penType == ProPenType.pencil || penType == ProPenType.charcoal;
    final hasSurfaceGrain =
        !_shaderHandlesSurface &&
        effectiveSurface != null &&
        effectiveSurface.grainTexture != 'none';
    final hasTexture = hasBrushTexture || hasSurfaceGrain;
    final useCompositing =
        effectiveBlendMode != ui.BlendMode.srcOver || hasTexture;

    if (useCompositing) {
      // 🚀 PERF: For live strokes, use incremental bounds tracking (O(ΔN)).
      // For finalized strokes, compute full bounds (O(N) — runs only once).
      final bounds =
          isLive
              ? _updateLiveBounds(effectivePoints, baseWidth)
              : _computeStrokeBounds(effectivePoints, baseWidth);
      canvas.saveLayer(bounds, Paint()..blendMode = effectiveBlendMode);
    }

    // Resolve texture image for GPU shader passthrough
    ui.Image? textureImg;
    double texScale = 0.0;
    if (settings.textureType != 'none') {
      final texType = _textureTypeFromString(settings.textureType);
      textureImg = BrushTexture.getCached(texType);
      if (textureImg != null) {
        // Scale: smaller value = larger texture tiles
        texScale = 1.0 / (baseWidth.clamp(1.0, 12.0) * 0.8);
      }
    }

    // 🖌️ Stamp-based rendering (Procreate-style)
    if (settings.stampEnabled &&
        ShaderBrushService.instance.isStampAvailable &&
        effectivePoints.length >= 2 &&
        (penType == ProPenType.pencil || penType == ProPenType.fountain)) {
      // Resolve dual brush texture
      ui.Image? dualImg;
      if (settings.stampDualTexture != 'none' && settings.stampDualBlend > 0) {
        final dualType = _textureTypeFromString(settings.stampDualTexture);
        dualImg = BrushTexture.getCached(dualType);
      }

      ShaderBrushService.instance.renderStampBrush(
        canvas,
        effectivePoints,
        color,
        baseWidth,
        minPressure:
            penType == ProPenType.pencil
                ? settings.pencilMinPressure
                : settings.fountainMinPressure,
        maxPressure:
            penType == ProPenType.pencil
                ? settings.pencilMaxPressure
                : settings.fountainMaxPressure,
        spacing: settings.stampSpacing,
        sizeJitter: settings.stampSizeJitter,
        rotationJitter: settings.stampRotationJitter,
        scatterAmount: settings.stampScatter,
        softness: settings.stampSoftness,
        elongation: settings.stampElongation,
        baseOpacity:
            penType == ProPenType.pencil ? settings.pencilBaseOpacity : 0.9,
        flow: settings.stampFlow,
        opacityJitter: settings.stampOpacityJitter,
        wetEdges: settings.stampWetEdges,
        minSizePct: settings.stampMinSize,
        taperEntry: settings.stampTaperEntry,
        taperExit: settings.stampTaperExit,
        velocitySizeInfluence: settings.stampVelocitySize,
        velocityFlowInfluence: settings.stampVelocityFlow,
        glazeMode: settings.stampGlazeMode,
        hueJitter: settings.stampHueJitter,
        saturationJitter: settings.stampSatJitter,
        brightnessJitter: settings.stampBrightJitter,
        tiltRotation: settings.stampTiltRotation,
        tiltElongation: settings.stampTiltElongation,
        tipTexture: textureImg,
        dualTexture: dualImg,
        dualScale: settings.stampDualScale,
        dualBlend: settings.stampDualBlend,
        pressureColorInfluence: settings.stampPressureColor,
        wetMixStrength: settings.stampWetMix,
        roundnessJitter: settings.stampRoundnessJitter,
        colorGradient: settings.stampColorGradient,
        accumCap: settings.stampAccumCap,
        spacingPressure: settings.stampSpacingPressure,
        transferVelocity: settings.stampTransferVelocity,
        symmetryAxes: settings.stampSymmetryAxes,
        eraserMode: settings.stampEraserMode,
        grainScreenSpace: settings.stampGrainScreenSpace,
        shapeType: settings.stampShapeType,
        grainScale: settings.stampGrainScale,
        colorPressure: settings.stampColorPressure,
        secondaryColor:
            (settings.stampColorGradient > 0 || settings.stampColorPressure > 0)
                ? const Color(0xFFFFFFFF)
                : null,
      );
    } else {
      // 🚀 LIVE PERF: For GPU shader pens, decimate points to bound
      // per-frame cost. NOT applied to fountain pen — its velocity-based
      // width calculation depends on original point spacing (decimation
      // alters spacing → stroke shrinks). Fountain pen performance is
      // handled by live optimizations in FountainPenPathBuilder instead
      // (1 Chaikin pass, no feathering, no arc-length reparameterization).
      const int _liveMaxPoints = 200;
      const int _finalizedMaxPoints = 300;
      final bool _isGpuShaderPen = switch (penType) {
        ProPenType.pencil ||
        ProPenType.watercolor ||
        ProPenType.marker ||
        ProPenType.charcoal ||
        ProPenType.oilPaint ||
        ProPenType.sprayPaint ||
        ProPenType.neonGlow ||
        ProPenType.inkWash => true,
        _ => false,
      };

      final maxPts = isLive ? _liveMaxPoints : _finalizedMaxPoints;
      List<dynamic> renderPoints = effectivePoints;
      if (_isGpuShaderPen && effectivePoints.length > maxPts) {
        renderPoints = _decimatePoints(effectivePoints, maxPts);
      }

      switch (penType) {
        case ProPenType.ballpoint:
          BallpointBrush.drawStrokeWithSettings(
            canvas,
            effectivePoints,
            color,
            baseWidth,
            minPressure: settings.ballpointMinPressure,
            maxPressure: settings.ballpointMaxPressure,
            isLive: isLive,
          );
        case ProPenType.fountain:
          FountainPenBrush.drawStrokeWithSettings(
            canvas,
            renderPoints,
            color,
            baseWidth,
            minPressure: settings.fountainMinPressure,
            maxPressure: settings.fountainMaxPressure,
            taperEntry: settings.fountainTaperEntry,
            taperExit: settings.fountainTaperExit,
            velocityInfluence: settings.fountainVelocityInfluence,
            curvatureInfluence: settings.fountainCurvatureInfluence,
            tiltEnable: settings.fountainTiltEnable,
            tiltInfluence: settings.fountainTiltInfluence,
            tiltEllipseRatio: settings.fountainTiltEllipseRatio,
            jitter: settings.fountainJitter,
            velocitySensitivity: settings.fountainVelocitySensitivity,
            inkAccumulation: settings.fountainInkAccumulation,
            smoothPath: settings.fountainSmoothPath,
            thinning: settings.fountainThinning,
            pressureRate: settings.fountainPressureRate,
            nibAngleRad: settings.fountainNibAngleDeg * 3.14159265 / 180.0,
            nibStrength: settings.fountainNibStrength,
            // 🚀 Always use live-quality rendering: eliminates the visual
            // "jump" on pointer-up. 1 Chaikin + no feathering is visually
            // indistinguishable on-screen and ensures consistency.
            liveStroke: true,
            textureImage: textureImg,
            textureScale: texScale,
            drawFromIndex: drawFromIndex,
          );
        case ProPenType.pencil:
          PencilBrush.drawStrokeWithSettings(
            canvas,
            renderPoints,
            color,
            baseWidth,
            baseOpacity: settings.pencilBaseOpacity,
            maxOpacity: settings.pencilMaxOpacity,
            blurRadius: settings.pencilBlurRadius,
            minPressure: settings.pencilMinPressure,
            maxPressure: settings.pencilMaxPressure,
            liveStroke: isLive,
            textureImage: textureImg,
            textureScale: texScale,
            drawFromIndex: drawFromIndex,
            surfaceRoughness: effectiveSurface?.roughness ?? 0.0,
            surfaceAbsorption: effectiveSurface?.absorption ?? 0.0,
            surfacePigmentRetention: effectiveSurface?.pigmentRetention ?? 1.0,
          );
        case ProPenType.highlighter:
          HighlighterBrush.drawStrokeWithSettings(
            canvas,
            effectivePoints,
            color,
            baseWidth,
            opacity: settings.highlighterOpacity,
            widthMultiplier: settings.highlighterWidthMultiplier,
          );
        case ProPenType.watercolor:
          final wSvc = ShaderBrushService.instance;
          if (wSvc.isAvailable && wSvc.watercolorShader != null) {
            wSvc.renderWatercolorPro(
              canvas,
              renderPoints,
              color,
              baseWidth,
              spread: settings.watercolorSpread,
              wetness: currentWetness,
            );
          } else {
            WatercolorBrush.drawStroke(canvas, renderPoints, color, baseWidth);
          }
        case ProPenType.marker:
          final mSvc = ShaderBrushService.instance;
          if (mSvc.isAvailable && mSvc.markerShader != null) {
            mSvc.renderMarkerPro(
              canvas,
              renderPoints,
              color,
              baseWidth,
              flatness: settings.markerFlatness,
            );
          } else {
            MarkerBrush.drawStroke(canvas, renderPoints, color, baseWidth);
          }
        case ProPenType.charcoal:
          final cSvc = ShaderBrushService.instance;
          if (cSvc.isAvailable && cSvc.charcoalShader != null) {
            cSvc.renderCharcoalPro(
              canvas,
              renderPoints,
              color,
              baseWidth,
              grain: settings.charcoalGrain,
              surfaceRoughness: effectiveSurface?.roughness ?? 0.0,
              surfaceAbsorption: effectiveSurface?.absorption ?? 0.0,
              surfacePigmentRetention:
                  effectiveSurface?.pigmentRetention ?? 1.0,
            );
          } else {
            CharcoalBrush.drawStroke(canvas, renderPoints, color, baseWidth);
          }
        case ProPenType.oilPaint:
          final oSvc = ShaderBrushService.instance;
          if (oSvc.isAvailable && oSvc.oilPaintShader != null) {
            oSvc.renderOilPaintPro(canvas, renderPoints, color, baseWidth);
          } else {
            BallpointBrush.drawStrokeWithSettings(
              canvas,
              renderPoints,
              color,
              baseWidth,
              minPressure: settings.ballpointMinPressure,
              maxPressure: settings.ballpointMaxPressure,
            );
          }
        case ProPenType.sprayPaint:
          final sSvc = ShaderBrushService.instance;
          if (sSvc.isAvailable && sSvc.sprayPaintShader != null) {
            sSvc.renderSprayPaintPro(canvas, renderPoints, color, baseWidth);
          } else {
            BallpointBrush.drawStrokeWithSettings(
              canvas,
              renderPoints,
              color,
              baseWidth,
              minPressure: settings.ballpointMinPressure,
              maxPressure: settings.ballpointMaxPressure,
            );
          }
        case ProPenType.neonGlow:
          final nSvc = ShaderBrushService.instance;
          if (nSvc.isAvailable && nSvc.neonGlowShader != null) {
            nSvc.renderNeonGlowPro(canvas, renderPoints, color, baseWidth);
          } else {
            BallpointBrush.drawStrokeWithSettings(
              canvas,
              renderPoints,
              color,
              baseWidth,
              minPressure: settings.ballpointMinPressure,
              maxPressure: settings.ballpointMaxPressure,
            );
          }
        case ProPenType.inkWash:
          final iSvc = ShaderBrushService.instance;
          if (iSvc.isAvailable && iSvc.inkWashShader != null) {
            iSvc.renderInkWashPro(canvas, renderPoints, color, baseWidth);
          } else {
            BallpointBrush.drawStrokeWithSettings(
              canvas,
              renderPoints,
              color,
              baseWidth,
              minPressure: settings.ballpointMinPressure,
              maxPressure: settings.ballpointMaxPressure,
            );
          }
      }
    }

    // 🌱 Wetness deposit: wet brushes increase canvas wetness
    final isWetBrush =
        penType == ProPenType.watercolor || penType == ProPenType.inkWash;
    if (isWetBrush && effectivePoints.length > 2) {
      // Average pressure as deposit amount
      double avgP = 0.5;
      final midP = effectivePoints[effectivePoints.length ~/ 2];
      if (midP is ProDrawingPoint) avgP = midP.pressure;
      _canvasWetness.deposit(0.3 * avgP, nowMs: nowMs);

      // 🌊 Fluid topology: deposit pigment into the spatial field
      FluidTopologyEngine.depositStroke(
        effectivePoints,
        color,
        effectiveWidth,
        avgP,
      );
    }

    // 🎨 Phase 3A: Apply texture overlay to stroke
    // 🚀 PERF: during live drawing, only apply texture to the tail of the
    // stroke (last ~40 points). The user is looking at the pen tip, so full
    // stroke texture is unnecessary until finalization.
    // 🧬 Surface material can override/augment texture settings.
    // ⚠️ Skip surface→texture merge for brushes with surface-aware shaders
    // (pencil, charcoal) — they already handle roughness/absorption in the
    // fragment shader via uniforms. Double-dipping causes live/finalized
    // mismatch (live = partial overlay, finalized = full overlay = darker).
    final bool hasSurfaceShader =
        penType == ProPenType.pencil || penType == ProPenType.charcoal;
    final effectiveSettings =
        hasSurfaceShader
            ? settings
            : _applySurfaceToSettings(settings, effectiveSurface);
    _applyTextureOverlay(
      canvas,
      effectivePoints,
      effectiveWidth,
      effectiveSettings,
      isLive: isLive,
    );

    if (useCompositing) {
      canvas.restore();
    }
  }

  /// Apply texture overlay to the stroke with per-segment variation.
  ///
  /// Technique: BlendMode.dstOut "erodes" the stroke where the texture is light.
  /// The erosion varies ALONG the stroke: local pressure and speed
  /// determinano quanta grana mostrare in ogni segmento.
  ///
  /// Segmenti di ~15 punti per bilanciare variazione vs performance.
  /// Short strokes (<30 points) use a single pass.
  static void _applyTextureOverlay(
    Canvas canvas,
    List<dynamic> points,
    double baseWidth,
    ProBrushSettings settings, {
    bool isLive = false,
  }) {
    if (settings.textureType == 'none' || settings.textureIntensity <= 0) {
      return;
    }
    if (points.length < 2) return;

    // Convert stringa → TextureType
    final textureType = _textureTypeFromString(settings.textureType);
    if (textureType == TextureType.none) return;

    // Prendi texture from the cache (sincrona)
    final textureImage = BrushTexture.getCached(textureType);
    if (textureImage == null) return;

    // ── dart:gpu PATH ── single render pass, no accumulation ──
    // Generates a procedural erosion mask via GPU compute, then draws
    // with dstOut. Only for finalized strokes with enough points.
    final gpuSvc = GpuTextureService.instance;
    if (!isLive && gpuSvc.isAvailable && points.length > 5) {
      // Compute stroke bounds for the mask dimensions
      double minX = double.infinity, minY = double.infinity;
      double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (int i = 0; i < points.length; i++) {
        final p = points[i];
        final pos = p is Offset ? p : (p as ProDrawingPoint).position;
        if (pos.dx < minX) minX = pos.dx;
        if (pos.dy < minY) minY = pos.dy;
        if (pos.dx > maxX) maxX = pos.dx;
        if (pos.dy > maxY) maxY = pos.dy;
      }
      final pad = baseWidth * 2.0 + 4.0;
      final bounds = Rect.fromLTRB(
        minX - pad,
        minY - pad,
        maxX + pad,
        maxY + pad,
      );

      // Determine noise type from texture
      final noiseType = switch (settings.textureType) {
        'charcoal' || 'kraft' => 1, // coarse
        'canvas' => 2, // fibrous
        _ => 0, // fine (pencil, watercolor)
      };

      // Deterministic seed from stroke position
      final firstP = points.first;
      final firstPos =
          firstP is Offset ? firstP : (firstP as ProDrawingPoint).position;
      final seed = firstPos.dx.toInt() ^ firstPos.dy.toInt();

      final mask = gpuSvc.renderErosionMask(
        width: bounds.width.ceil(),
        height: bounds.height.ceil(),
        intensity: settings.textureIntensity,
        grainScale: 50.0 * (baseWidth / 3.0).clamp(0.5, 4.0),
        rotation: 0.0,
        noiseType: noiseType,
        seed: seed,
      );

      if (mask != null) {
        canvas.drawImage(
          mask,
          bounds.topLeft,
          Paint()..blendMode = ui.BlendMode.dstOut,
        );
        mask.dispose();
        return;
      }
      // Fall through to ImageShader if GPU failed
    }

    // 🚀 FAST PATH: single drawRect with ImageShader (live + GPU fallback).
    if (points.length > 2) {
      _applyFastTextureOverlay(
        canvas,
        points,
        baseWidth,
        settings,
        textureImage,
      );
      return;
    }

    // 🔄 CPU FALLBACK: per-segment drawRect (finalized strokes only)

    // Scala per tipo
    final typeScale = switch (textureType) {
      TextureType.charcoal => 2.5,
      TextureType.kraft => 2.0,
      TextureType.watercolor => 1.8,
      TextureType.canvas => 1.5,
      TextureType.pencilGrain => 1.0,
      _ => 1.0,
    };
    final widthScale = (baseWidth / 3.0).clamp(0.5, 4.0);
    final totalScale = typeScale * widthScale;

    // Rotation based on textureRotationMode
    final firstPos =
        points.first is Offset
            ? points.first as Offset
            : (points.first as ProDrawingPoint).position;
    final lastPos =
        points.last is Offset
            ? points.last as Offset
            : (points.last as ProDrawingPoint).position;

    final rng = math.Random(firstPos.dx.toInt() ^ firstPos.dy.toInt());
    final offsetX = rng.nextDouble() * textureImage.width;
    final offsetY = rng.nextDouble() * textureImage.height;

    double rotation;
    switch (settings.textureRotationMode) {
      case 'fixed':
        rotation = 0.0;
      case 'random':
        rotation = rng.nextDouble() * math.pi * 2;
      case 'followStroke':
      default:
        final delta = lastPos - firstPos;
        final strokeAngle =
            delta.distance > 1.0 ? math.atan2(delta.dy, delta.dx) : 0.0;
        final jitter = (rng.nextDouble() - 0.5) * 0.174; // ±5°
        rotation = strokeAngle + jitter;
    }

    final invScale = 1.0 / totalScale;
    final cosR = math.cos(rotation) * invScale;
    final sinR = math.sin(rotation) * invScale;
    final mat = Matrix4.identity();
    mat.setEntry(0, 0, cosR);
    mat.setEntry(0, 1, -sinR);
    mat.setEntry(1, 0, sinR);
    mat.setEntry(1, 1, cosR);
    mat.setEntry(0, 3, offsetX * invScale);
    mat.setEntry(1, 3, offsetY * invScale);

    final shader = ui.ImageShader(
      textureImage,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      mat.storage,
    );

    // Paint base — shader e colorFilter condivisi, alpha cambia per segmento
    final texturePaint =
        Paint()
          ..shader = shader
          ..colorFilter = _luminanceToAlpha
          ..blendMode = ui.BlendMode.dstOut;

    final halfWidth = baseWidth;
    final intensity = settings.textureIntensity;

    // --- Per-segment rendering ---
    // Segmenti di ~15 punti. Short strokes → singolo pass.
    const segmentSize = 15;
    final useSegments = points.length >= segmentSize * 2;

    if (!useSegments) {
      // Short stroke: singolo pass con medie globali
      final result = _computeSegmentMetrics(points, 0, points.length);
      final bounds = result.bounds.inflate(halfWidth);
      final alpha = _erosionAlpha(
        intensity,
        result.avgPressure,
        result.velocityFactor,
      );
      texturePaint.color = ui.Color.fromARGB(alpha, 255, 255, 255);
      canvas.drawRect(bounds, texturePaint);
    } else {
      // Long stroke: per-segment con overlap di 2 punti per seamless join
      for (int start = 0; start < points.length; start += segmentSize) {
        final end = (start + segmentSize + 2).clamp(0, points.length);
        final result = _computeSegmentMetrics(points, start, end);
        final bounds = result.bounds.inflate(halfWidth);
        final alpha = _erosionAlpha(
          intensity,
          result.avgPressure,
          result.velocityFactor,
        );
        texturePaint.color = ui.Color.fromARGB(alpha, 255, 255, 255);
        canvas.drawRect(bounds, texturePaint);
      }
    }
  }

  /// 🚀 Fast single-pass texture overlay.
  ///
  /// Always computes shader fresh from deterministic parameters (firstPos RNG).
  /// ImageShader creation costs ~0.05ms — negligible per stroke per frame.
  /// No static caching = no texture shift between live and finalized.
  static void _applyFastTextureOverlay(
    Canvas canvas,
    List<dynamic> points,
    double baseWidth,
    ProBrushSettings settings,
    ui.Image textureImage,
  ) {
    // Skip for very short strokes — texture is invisible and causes artifacts
    if (points.length < 5) return;

    final intensity = settings.textureIntensity;
    final textureType = _textureTypeFromString(settings.textureType);

    // Compute bounds from actual points
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final pos = p is Offset ? p : (p as ProDrawingPoint).position;
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }
    final pad = baseWidth * 2.0 + 4.0;
    final bounds = Rect.fromLTRB(
      minX - pad,
      minY - pad,
      maxX + pad,
      maxY + pad,
    );

    // Deterministic shader parameters from first point (RNG seeded by position)
    final firstP = points.first;
    final firstPos =
        firstP is Offset ? firstP : (firstP as ProDrawingPoint).position;

    final rng = math.Random(firstPos.dx.toInt() ^ firstPos.dy.toInt());
    final offsetX = rng.nextDouble() * textureImage.width;
    final offsetY = rng.nextDouble() * textureImage.height;

    // Texture scale — multiplied by 5 so the 640px texture tiles every
    // ~130-320 screen pixels instead of 640-1600. This makes the texture
    // grain visible at stroke width scale (~10px).
    final typeScale = switch (textureType) {
      TextureType.charcoal => 2.5,
      TextureType.kraft => 2.0,
      TextureType.watercolor => 1.8,
      TextureType.canvas => 1.5,
      TextureType.pencilGrain => 1.0,
      _ => 1.0,
    };
    final widthScale = (baseWidth / 3.0).clamp(0.5, 4.0);
    final invScale = 5.0 / (typeScale * widthScale);

    // Rotation — deterministic from stable early points (not lastPos which changes)
    double rotation;
    switch (settings.textureRotationMode) {
      case 'fixed':
        rotation = 0.0;
      case 'random':
        rotation = rng.nextDouble() * math.pi * 2;
      case 'followStroke':
      default:
        // Use a stable early reference point (index ~10 or 25% of stroke).
        // This won't change as the stroke grows or gets trimmed at the tail.
        final refIdx = math
            .min(10, points.length ~/ 4)
            .clamp(1, points.length - 1);
        final refP = points[refIdx];
        final refPos =
            refP is Offset ? refP : (refP as ProDrawingPoint).position;
        final delta = refPos - firstPos;
        rotation = delta.distance > 1.0 ? math.atan2(delta.dy, delta.dx) : 0.0;
    }

    final cosR = math.cos(rotation) * invScale;
    final sinR = math.sin(rotation) * invScale;
    final mat = Matrix4.identity();
    mat.setEntry(0, 0, cosR);
    mat.setEntry(0, 1, -sinR);
    mat.setEntry(1, 0, sinR);
    mat.setEntry(1, 1, cosR);
    mat.setEntry(0, 3, offsetX * invScale);
    mat.setEntry(1, 3, offsetY * invScale);

    final shader = ui.ImageShader(
      textureImage,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      mat.storage,
    );

    final paint =
        Paint()
          ..shader = shader
          ..colorFilter = _luminanceToAlpha
          ..blendMode = ui.BlendMode.dstOut;

    // Average pressure from 3 sampled points (zero allocation)
    double avgPressure = 0.5;
    if (points.length >= 3) {
      final mid = points.length ~/ 2;
      double sum = 0;
      int count = 0;
      for (int idx = 0; idx < 3; idx++) {
        final pi = idx == 0 ? 0 : (idx == 1 ? mid : points.length - 1);
        final p = points[pi];
        if (p is ProDrawingPoint) {
          sum += p.pressure;
          count++;
        }
      }
      if (count > 0) avgPressure = sum / count;
    }

    final alpha = _erosionAlpha(intensity, avgPressure, 0.65);
    paint.color = ui.Color.fromARGB(alpha, 255, 255, 255);

    canvas.drawRect(bounds, paint);
    shader.dispose();
  }

  /// Calculates average pressure and speed for a sub-segment of points.
  static _SegmentMetrics _computeSegmentMetrics(
    List<dynamic> points,
    int start,
    int end,
  ) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    double pressureSum = 0;
    int pressureCount = 0;
    double totalDist = 0;
    int totalTimeMs = 0;
    Offset? prevPos;
    int? prevTs;

    for (int i = start; i < end; i++) {
      final point = points[i];
      final Offset pos =
          point is Offset ? point : (point as ProDrawingPoint).position;
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
      if (point is ProDrawingPoint) {
        pressureSum += point.pressure;
        pressureCount++;
        if (prevPos != null && prevTs != null) {
          totalDist += (pos - prevPos).distance;
          totalTimeMs += point.timestamp - prevTs;
        }
        prevPos = pos;
        prevTs = point.timestamp;
      }
    }

    final avgPressure =
        pressureCount > 0 ? (pressureSum / pressureCount).clamp(0.0, 1.0) : 0.5;
    final avgVelocity =
        totalTimeMs > 0 ? (totalDist / totalTimeMs * 1000) : 500.0;
    final velocityFactor =
        (1.0 - ((avgVelocity - 200) / 1800).clamp(0.0, 1.0)) * 0.7 + 0.3;

    return _SegmentMetrics(
      bounds: Rect.fromLTRB(minX, minY, maxX, maxY),
      avgPressure: avgPressure,
      velocityFactor: velocityFactor,
    );
  }

  /// Calculates erosion alpha da intensity, pressione e speed.
  static int _erosionAlpha(
    double intensity,
    double pressure,
    double velocityFactor,
  ) {
    final pressureFactor = 0.3 + pressure * 0.7;
    return (intensity * pressureFactor * velocityFactor * 0.7 * 255)
        .round()
        .clamp(0, 255);
  }

  /// 🚀 Compute tight stroke bounds from points, inflated by brush width.
  /// Used for bounded saveLayer to avoid full-screen GPU buffer.
  static Rect _computeStrokeBounds(List<dynamic> points, double baseWidth) {
    if (points.isEmpty) return Rect.zero;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final double x, y;
      if (p is Offset) {
        x = p.dx;
        y = p.dy;
      } else {
        final pos = (p as ProDrawingPoint).position;
        x = pos.dx;
        y = pos.dy;
      }
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    // Inflate by baseWidth + margin for texture overlap and anti-aliasing
    final padding = baseWidth * 2.0 + 4.0;
    return Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
  }

  /// 🚀 Incremental bounds: extend running min/max with only NEW points.
  /// Runs in O(ΔN) per frame instead of O(N).
  static Rect _updateLiveBounds(List<dynamic> points, double baseWidth) {
    // Reset if stroke restarted (point count decreased or is small)
    if (points.length < _liveBoundsPointCount || points.length <= 2) {
      resetLiveBounds();
    }

    // Only process new points since last call
    for (int i = _liveBoundsPointCount; i < points.length; i++) {
      final p = points[i];
      final double x, y;
      if (p is Offset) {
        x = p.dx;
        y = p.dy;
      } else {
        final pos = (p as ProDrawingPoint).position;
        x = pos.dx;
        y = pos.dy;
      }
      if (x < _liveMinX) _liveMinX = x;
      if (x > _liveMaxX) _liveMaxX = x;
      if (y < _liveMinY) _liveMinY = y;
      if (y > _liveMaxY) _liveMaxY = y;
    }
    _liveBoundsPointCount = points.length;

    final padding = baseWidth * 2.0 + 4.0;
    return Rect.fromLTRB(
      _liveMinX - padding,
      _liveMinY - padding,
      _liveMaxX + padding,
      _liveMaxY + padding,
    );
  }

  /// 🧬 Apply surface material properties to brush settings.
  ///
  /// When a [SurfaceMaterial] is provided, its grain texture and roughness
  /// augment the brush settings:
  /// - If the brush has no texture, the surface provides one
  /// - Surface roughness increases texture intensity
  /// - Surface grain scale is applied
  ///
  /// Returns [settings] unchanged when [surface] is null (zero-cost path).
  static ProBrushSettings _applySurfaceToSettings(
    ProBrushSettings settings,
    SurfaceMaterial? surface,
  ) {
    if (surface == null) return settings;

    // Determine effective texture: brush texture wins, surface is fallback
    final brushHasTexture = settings.textureType != 'none';
    final surfaceHasGrain = surface.grainTexture != 'none';

    if (!brushHasTexture && !surfaceHasGrain) return settings;

    final effectiveTexture =
        brushHasTexture ? settings.textureType : surface.grainTexture;

    // Surface roughness adds to texture intensity
    final surfaceGrainBoost = surface.roughness * 0.4;
    final effectiveIntensity =
        brushHasTexture
            ? (settings.textureIntensity + surfaceGrainBoost).clamp(0.0, 1.0)
            : (surface.roughness * 0.7).clamp(0.0, 1.0);

    return settings.copyWith(
      textureType: effectiveTexture,
      textureIntensity: effectiveIntensity,
    );
  }

  /// Converts textureType string → TextureType enum
  static TextureType _textureTypeFromString(String name) {
    switch (name) {
      case 'pencilGrain':
        return TextureType.pencilGrain;
      case 'charcoal':
        return TextureType.charcoal;
      case 'watercolor':
        return TextureType.watercolor;
      case 'canvas':
        return TextureType.canvas;
      case 'kraft':
        return TextureType.kraft;
      default:
        return TextureType.none;
    }
  }

  /// Default blend mode per pen type
  /// Highlighter uses darken for realistic marker behavior
  static ui.BlendMode _defaultBlendMode(ProPenType penType) {
    switch (penType) {
      case ProPenType.highlighter:
        return ui.BlendMode.darken;
      default:
        return ui.BlendMode.srcOver;
    }
  }

  /// 🌱 Per-brush organic profile: tremor amplitude and frequency multiplier.
  ///
  /// Different brushes have different physical characteristics:
  /// - Pencil: fine, high-frequency tremor (rigid graphite tip)
  /// - Fountain pen: smooth, medium-frequency (flexible nib absorbs tremor)
  /// - Charcoal: rough, low-frequency (soft stick has more give)
  /// - Ballpoint: minimal tremor (very rigid mechanism)
  static ({double amplitude, double freqMult}) _organicProfile(
    ProPenType penType,
  ) {
    return switch (penType) {
      ProPenType.pencil => (amplitude: 0.25, freqMult: 1.3),
      ProPenType.fountain => (amplitude: 0.35, freqMult: 0.8),
      ProPenType.charcoal => (amplitude: 0.5, freqMult: 0.6),
      ProPenType.watercolor => (amplitude: 0.4, freqMult: 0.7),
      ProPenType.inkWash => (amplitude: 0.35, freqMult: 0.75),
      ProPenType.marker => (amplitude: 0.2, freqMult: 1.0),
      ProPenType.oilPaint => (amplitude: 0.3, freqMult: 0.9),
      ProPenType.sprayPaint => (amplitude: 0.6, freqMult: 0.5),
      ProPenType.neonGlow => (amplitude: 0.15, freqMult: 1.2),
      ProPenType.highlighter => (amplitude: 0.1, freqMult: 1.0),
      ProPenType.ballpoint => (amplitude: 0.1, freqMult: 1.5),
    };
  }

  /// 🌱 Apply organic micro-variation to stroke points.
  ///
  /// Modulates position (lateral offset) and pressure with biologically
  /// plausible noise:
  /// - 1/f tremor (Simplex noise, velocity-dependent amplitude)
  /// - Muscle fatigue (amplitude increases on long strokes)
  /// - Breathing (ultra-slow sinusoidal pressure variation)
  ///
  /// 🚀 PERF: Uses pre-allocated `_organicPointsBuffer` — zero heap allocation.
  static List<dynamic> _applyOrganicModulation(
    List<dynamic> points,
    double baseWidth,
    ProPenType penType,
  ) {
    // 🌱 Adaptive multiplier: reduces organicity during annotation patterns
    final adaptive = OrganicBehaviorEngine.adaptiveMultiplier;
    final effectiveIntensity = OrganicBehaviorEngine.intensity * adaptive;
    if (effectiveIntensity <= 0) return points;

    final n = points.length;
    // 🚀 PERF: reuse pre-allocated buffer instead of List.filled(n, null)
    if (_organicPointsBuffer.length < n) {
      _organicPointsBuffer = List<dynamic>.filled(n * 2, null);
    }

    // 🌱 Canvas-based seed: absolute position determines noise pattern.
    // Overlapping strokes share the same "canvas texture" wobble.
    // The seed is NOT per-stroke — it's per-canvas-position.
    // (Per-stroke seed used only for minor variation via index offset)
    final firstP = points.first;
    final firstPos =
        firstP is ProDrawingPoint ? firstP.position : firstP as Offset;

    // 🌱 Per-brush organic profile
    final profile = _organicProfile(penType);

    // Amplitude: per-brush lateral offset, scaled by effective intensity
    final posAmplitude = profile.amplitude * effectiveIntensity;
    // Pressure variation: ±5% at full intensity
    final pressureAmplitude = 0.05 * effectiveIntensity;

    double arcLength = 0.0;
    Offset prevPos = firstPos;

    for (int i = 0; i < n; i++) {
      final p = points[i];

      final Offset pos;
      final double pressure;
      if (p is ProDrawingPoint) {
        pos = p.position;
        pressure = p.pressure;
      } else {
        pos = p as Offset;
        pressure = 0.5;
      }

      // Accumulate arc length
      if (i > 0) {
        arcLength += (pos - prevPos).distance;
      }
      prevPos = pos;

      // Skip first and last points to preserve stroke endpoints
      if (i == 0 || i == n - 1) {
        _organicPointsBuffer[i] = p;
        continue;
      }

      // Velocity estimate from adjacent points
      double velocity = 0.0;
      if (i > 0 && p is ProDrawingPoint) {
        final prevP = points[i - 1];
        if (prevP is ProDrawingPoint && p.timestamp > prevP.timestamp) {
          final dt = (p.timestamp - prevP.timestamp) / 1000000.0;
          if (dt > 0) {
            velocity = (pos - prevP.position).distance / dt;
          }
        }
      }

      // Biological tremor (1/f noise, velocity-damped)
      // 🌱 Canvas-based: seed from absolute pos, not per-stroke
      final canvasSeed = pos.dx * 7.3 + pos.dy * 13.7;
      final tremor = OrganicNoise.biologicalTremor(
        arcLength * profile.freqMult,
        velocity,
        seed: canvasSeed,
      );

      // Fatigue: amplitude grows after 200 points
      final fatigue = OrganicNoise.fatigueFactor(i);

      // Breathing: ultra-slow pressure modulation
      final breath = OrganicNoise.breathingModulation(arcLength);

      // Compute lateral offset direction (perpendicular to stroke)
      Offset lateralDir;
      if (i + 1 < n) {
        final nextP = points[i + 1];
        final nextPos =
            nextP is ProDrawingPoint ? nextP.position : nextP as Offset;
        final tangent = nextPos - pos;
        if (tangent.distance > 0.1) {
          lateralDir = Offset(-tangent.dy, tangent.dx) / tangent.distance;
        } else {
          lateralDir = Offset.zero;
        }
      } else {
        lateralDir = Offset.zero;
      }

      // Apply modulation
      final lateralOffset = tremor * posAmplitude * fatigue;

      // 🌱 Tilt-dependent tremor: bias lateral offset by stylus tilt
      // When tilted, tremor is asymmetric — biased in tilt direction
      Offset tiltBias = Offset.zero;
      if (p is ProDrawingPoint &&
          (p.tiltX.abs() > 0.05 || p.tiltY.abs() > 0.05)) {
        final tiltDir = Offset(p.tiltX, p.tiltY);
        final tiltMag = tiltDir.distance.clamp(0.0, 1.0);
        tiltBias = tiltDir * (tremor * posAmplitude * tiltMag * 0.5);
      }

      final newPos = pos + lateralDir * lateralOffset + tiltBias;
      final rawPressure = (pressure +
              tremor * pressureAmplitude * fatigue +
              breath * pressureAmplitude * 0.3)
          .clamp(0.05, 1.0);
      // 🌱 Organic S-curve: softens extremes, expands mid-range
      final newPressure = OrganicNoise.organicPressureCurve(rawPressure);

      if (p is ProDrawingPoint) {
        _organicPointsBuffer[i] = p.copyWith(
          position: newPos,
          pressure: newPressure,
        );
      } else {
        _organicPointsBuffer[i] = newPos;
      }
    }

    return _organicPointsBuffer.sublist(0, n);
  }

  /// 🚀 Decimate a point list for bounded rendering cost.
  ///
  /// Sub-samples the body (older points) while preserving full density
  /// at the tail (last ~40% of [maxCount]). This keeps the same visual
  /// quality near the pen tip while reducing total work.
  ///
  /// The stroke shape is preserved because key points (first, last,
  /// and uniformly spaced body samples) are kept.
  static List<dynamic> _decimatePoints(List<dynamic> points, int maxCount) {
    if (points.length <= maxCount) return points;

    // Tail: last 40% of budget at full density (where user is looking)
    final tailSize = (maxCount * 0.4).round().clamp(40, maxCount - 10);
    final bodyBudget = maxCount - tailSize;
    final bodyEnd = points.length - tailSize;

    // Sub-sample body uniformly
    final step = bodyEnd / bodyBudget;
    final result = <dynamic>[];

    for (int i = 0; i < bodyBudget; i++) {
      result.add(points[(i * step).floor()]);
    }

    // Full-density tail
    for (int i = bodyEnd; i < points.length; i++) {
      result.add(points[i]);
    }

    return result;
  }
}

/// Metrics for a stroke segment (used by _applyTextureOverlay).
class _SegmentMetrics {
  final Rect bounds;
  final double avgPressure;
  final double velocityFactor;
  const _SegmentMetrics({
    required this.bounds,
    required this.avgPressure,
    required this.velocityFactor,
  });
}
