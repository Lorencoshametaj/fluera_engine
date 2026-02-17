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
import './brushes.dart';

/// 🎨 Unified Brush Engine — Single point of dispatch
///
/// Replace le 7+ duplicazioni identiche di `_drawStroke/switch(penType)`
/// scattered across renderers, painters, optimizers and cache managers.
///
/// PRIMA: ogni file conteneva ~60 righe di switch/case identico.
/// ORA:   ogni file chiama `BrushEngine.renderStroke()` in 1 riga.
///
/// Addere un nuovo brush richiede:
///   1. Create the brush class (es. `MarkerBrush`)
///   2. Add the case in `ProPenType`
///   3. Add the case HERE — automatically available everywhere.
class BrushEngine {
  BrushEngine._(); // Do not istanziabile

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
  /// (non when aggiungono nuovi brush — quelli sono backward compatible).
  ///
  /// Cronologia:
  /// - v1: strokes pre-versioning (no 'ev' tag in JSON)
  /// - v2: first tagged version (Feb 2026) — same logic as v1
  ///
  /// Quando cambi un algoritmo di brush:
  /// 1. Incrementa [currentEngineVersion]
  /// 2. Sposta il vecchio codice in un metodo `_renderStrokeVN()`
  /// 3. Aggiungi il routing nel blocco `engineVersion` sotto
  static const int currentEngineVersion = 2;

  /// Render uno stroke usando il brush corretto based onl [penType].
  ///
  /// This is the ONLY point where pen type → brush dispatch occurs.
  /// All renderers, painters, cache managers and optimizers delegate here.
  ///
  /// [engineVersion] Versione del motore che ha prodotto lo stroke.
  ///   Se omesso, usa [currentEngineVersion] (stroke live/nuovo).
  ///   Per strokes caricati da disco, passare `stroke.engineVersion`.
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

    // 🛡️ Migration routing — quando in futuro cambierà un algoritmo,
    // qui si instrada verso il renderer della versione corretta.
    // For ora v1 e v2 usano lo stesso renderer (nessun breaking change).
    // final ev = engineVersion ?? currentEngineVersion;
    // if (ev < 3) { _renderStrokeV2(...); return; }

    // 🎛️ Phase 4A: Remap pressures through the pressure curve
    List<dynamic> effectivePoints = points;
    if (!settings.pressureCurve.isLinear) {
      effectivePoints =
          effectivePoints.map((p) {
            if (p is ProDrawingPoint) {
              final remapped = settings.pressureCurve.evaluate(p.pressure);
              return p.copyWith(pressure: remapped);
            }
            return p; // Offset points have no pressure
          }).toList();
    }

    // 🎯 Phase 4B: Stroke stabilizer — now applied in real-time
    // via DrawingInputHandler (not post-hoc here)

    // 🎨 Per-brush blend mode: wrap in saveLayer for compositing
    final effectiveBlendMode = blendMode ?? _defaultBlendMode(penType);
    // 🎨 Per-brush blend mode OR texture: wrap in saveLayer for compositing.
    // Texture overlay uses BlendMode.modulate which would affect the
    // background without layer isolation.
    final hasTexture =
        settings.textureType != 'none' && settings.textureIntensity > 0;
    final useCompositing =
        effectiveBlendMode != ui.BlendMode.srcOver || hasTexture;

    if (useCompositing) {
      canvas.saveLayer(null, Paint()..blendMode = effectiveBlendMode);
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
      switch (penType) {
        case ProPenType.ballpoint:
          BallpointBrush.drawStrokeWithSettings(
            canvas,
            effectivePoints,
            color,
            baseWidth,
            minPressure: settings.ballpointMinPressure,
            maxPressure: settings.ballpointMaxPressure,
          );
        case ProPenType.fountain:
          FountainPenBrush.drawStrokeWithSettings(
            canvas,
            effectivePoints,
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
            liveStroke: isLive,
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
              effectivePoints,
              color,
              baseWidth,
              spread: settings.watercolorSpread,
            );
          } else {
            WatercolorBrush.drawStroke(
              canvas,
              effectivePoints,
              color,
              baseWidth,
            );
          }
        case ProPenType.marker:
          final mSvc = ShaderBrushService.instance;
          if (mSvc.isAvailable && mSvc.markerShader != null) {
            mSvc.renderMarkerPro(
              canvas,
              effectivePoints,
              color,
              baseWidth,
              flatness: settings.markerFlatness,
            );
          } else {
            MarkerBrush.drawStroke(canvas, effectivePoints, color, baseWidth);
          }
        case ProPenType.charcoal:
          final cSvc = ShaderBrushService.instance;
          if (cSvc.isAvailable && cSvc.charcoalShader != null) {
            cSvc.renderCharcoalPro(
              canvas,
              effectivePoints,
              color,
              baseWidth,
              grain: settings.charcoalGrain,
            );
          } else {
            CharcoalBrush.drawStroke(canvas, effectivePoints, color, baseWidth);
          }
      }
    }

    // 🎨 Phase 3A: Apply texture overlay to stroke
    _applyTextureOverlay(canvas, effectivePoints, baseWidth, settings);

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
    ProBrushSettings settings,
  ) {
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
      shaderService.renderTextureOverlay(
        canvas,
        points,
        settings,
        textureImage,
        baseWidth,
      );
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

  /// Calculatates pressione media e speed for a sotto-segmento di punti.
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

  /// Calculatates erosion alpha da intensity, pressione e speed.
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
