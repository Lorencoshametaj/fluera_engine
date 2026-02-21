import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../models/pro_brush_settings.dart';
import '../models/pro_drawing_point.dart';
import '../../rendering/shaders/shader_brush_service.dart';
import '../../rendering/shaders/shader_stamp_renderer.dart';
import '../../rendering/shaders/shader_texture_renderer.dart';
import '../../rendering/shaders/shader_watercolor_renderer.dart';
import '../../rendering/shaders/shader_marker_renderer.dart';
import '../../rendering/shaders/shader_charcoal_renderer.dart';
import '../../rendering/shaders/shader_oil_paint_renderer.dart';
import '../../rendering/shaders/shader_spray_paint_renderer.dart';
import '../../rendering/shaders/shader_neon_glow_renderer.dart';
import '../../rendering/shaders/shader_ink_wash_renderer.dart';
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

  // 🚀 Incremental bounds tracking for live strokes
  static double _liveMinX = double.infinity;
  static double _liveMinY = double.infinity;
  static double _liveMaxX = double.negativeInfinity;
  static double _liveMaxY = double.negativeInfinity;
  static int _liveBoundsPointCount = 0;

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
  }) {
    if (points.isEmpty) return;

    // 🛡️ Migration routing — when an algorithm changes in the future,
    // route to the renderer of the correct version here.
    // Currently v1 and v2 use the same renderer (no breaking changes).

    // 🎛️ Phase 4A: Remap pressures through the pressure curve
    // 🚀 PERF: Skip remapping during live drawing — brush handles pressure
    // internally, and the fast texture overlay samples only 3 points.
    // Full quality remapping is applied on finalization (isLive = false).
    List<dynamic> effectivePoints = points;
    if (!isLive && !settings.pressureCurve.isLinear) {
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

    // 🎨 Per-brush blend mode: wrap in saveLayer for compositing
    final effectiveBlendMode = blendMode ?? _defaultBlendMode(penType);
    // 🎨 Per-brush blend mode OR texture: wrap in saveLayer for compositing.
    // Texture overlay uses BlendMode.dstOut which needs layer isolation.
    final hasTexture =
        settings.textureType != 'none' && settings.textureIntensity > 0;
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
      const int _liveMaxPoints = 250;
      const int _finalizedMaxPoints = 400;
      final bool _isGpuShaderPen = switch (penType) {
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
          );
        case ProPenType.pencil:
          PencilBrush.drawStrokeWithSettings(
            canvas,
            effectivePoints,
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

    // 🎨 Phase 3A: Apply texture overlay to stroke
    // 🚀 PERF: during live drawing, only apply texture to the tail of the
    // stroke (last ~40 points). The user is looking at the pen tip, so full
    // stroke texture is unnecessary until finalization.
    _applyTextureOverlay(
      canvas,
      effectivePoints,
      baseWidth,
      settings,
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

    // 🚀 GPU PATH: per-pixel texture shader (preferred)
    final shaderService = ShaderBrushService.instance;
    if (shaderService.isTextureOverlayAvailable) {
      // 🚀 PERF: During live drawing, use a simplified single-pass overlay
      // covering the entire stroke bounds. This is O(1) instead of O(N)
      // per-segment rendering, while still showing texture on the full stroke.
      if (isLive && points.length > 30) {
        _applyFastTextureOverlay(
          canvas,
          points,
          baseWidth,
          settings,
          textureImage,
        );
      } else {
        shaderService.renderTextureOverlay(
          canvas,
          points,
          settings,
          textureImage,
          baseWidth,
        );
      }
      return;
    }

    // 🔄 CPU FALLBACK: per-segment drawRect (when GPU unavailable)

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

  /// 🚀 Fast single-pass texture overlay for live strokes.
  ///
  /// Enterprise-grade: ZERO allocations per frame.
  /// All Paint/Matrix4/ImageShader objects are cached as static fields
  /// and only rebuilt when texture type or stroke identity changes.
  /// Cost: O(1) per frame — just one canvas.drawRect.

  // ── Cached objects for fast overlay (zero alloc in paint) ──
  static Paint? _fastTexPaint;
  static ui.ImageShader? _fastTexShader;
  static final Matrix4 _fastTexMatrix = Matrix4.identity();
  static ui.Image? _fastTexCachedImage;
  static String _fastTexCachedType = '';
  static int _fastTexStrokeId = 0; // identifies stroke via first-point hash

  static void _applyFastTextureOverlay(
    Canvas canvas,
    List<dynamic> points,
    double baseWidth,
    ProBrushSettings settings,
    ui.Image textureImage,
  ) {
    final intensity = settings.textureIntensity;
    final textureType = _textureTypeFromString(settings.textureType);

    // Reuse incremental bounds (already computed by saveLayer path)
    final bounds = Rect.fromLTRB(
      _liveMinX - baseWidth * 2.0 - 4.0,
      _liveMinY - baseWidth * 2.0 - 4.0,
      _liveMaxX + baseWidth * 2.0 + 4.0,
      _liveMaxY + baseWidth * 2.0 + 4.0,
    );

    // Detect stroke identity change via first-point hash
    final firstP = points.first;
    final firstPos =
        firstP is Offset ? firstP : (firstP as ProDrawingPoint).position;
    final strokeId = firstPos.dx.hashCode ^ firstPos.dy.hashCode;

    // Rebuild shader only when texture/stroke changes (not per frame)
    final needsRebuild =
        _fastTexCachedImage != textureImage ||
        _fastTexCachedType != settings.textureType ||
        _fastTexStrokeId != strokeId;

    if (needsRebuild) {
      _fastTexCachedImage = textureImage;
      _fastTexCachedType = settings.textureType;
      _fastTexStrokeId = strokeId;

      // Texture scale
      final typeScale = switch (textureType) {
        TextureType.charcoal => 2.5,
        TextureType.kraft => 2.0,
        TextureType.watercolor => 1.8,
        TextureType.canvas => 1.5,
        TextureType.pencilGrain => 1.0,
        _ => 1.0,
      };
      final widthScale = (baseWidth / 3.0).clamp(0.5, 4.0);
      final invScale = 1.0 / (typeScale * widthScale);

      // Rotation — computed once per stroke
      final lastP = points.last;
      final lastPos =
          lastP is Offset ? lastP : (lastP as ProDrawingPoint).position;
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
          rotation =
              delta.distance > 1.0 ? math.atan2(delta.dy, delta.dx) : 0.0;
      }

      final cosR = math.cos(rotation) * invScale;
      final sinR = math.sin(rotation) * invScale;
      _fastTexMatrix.setIdentity();
      _fastTexMatrix.setEntry(0, 0, cosR);
      _fastTexMatrix.setEntry(0, 1, -sinR);
      _fastTexMatrix.setEntry(1, 0, sinR);
      _fastTexMatrix.setEntry(1, 1, cosR);
      _fastTexMatrix.setEntry(0, 3, offsetX * invScale);
      _fastTexMatrix.setEntry(1, 3, offsetY * invScale);

      _fastTexShader?.dispose();
      _fastTexShader = ui.ImageShader(
        textureImage,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        _fastTexMatrix.storage,
      );

      _fastTexPaint =
          Paint()
            ..shader = _fastTexShader
            ..colorFilter = _luminanceToAlpha
            ..blendMode = ui.BlendMode.dstOut;
    }

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
    _fastTexPaint!.color = ui.Color.fromARGB(alpha, 255, 255, 255);

    canvas.drawRect(bounds, _fastTexPaint!);
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
