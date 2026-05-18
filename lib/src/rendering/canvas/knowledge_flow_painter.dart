import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../reflow/content_cluster.dart';
import '../../reflow/knowledge_connection.dart';
import '../../reflow/knowledge_flow_controller.dart';
import '../../reflow/connection_suggestion_engine.dart';
import '../../canvas/ai/srs_stage_indicator.dart';
import '../../reflow/semantic_morph_controller.dart';
import '../../reflow/text_label_picker.dart';
import '../../reflow/zone_labeler.dart';
import '../../canvas/ai/fsrs_scheduler.dart';

/// 🧠 KNOWLEDGE FLOW PAINTER — Premium glassmorphism mind-map visualization.
///
/// VISUAL LAYERS (per bubble, back to front):
///   1. Drop shadow (blurred, offset down-right)
///   2. Glassmorphism fill (gradient: top-left light → bottom-right dark)
///   3. Inner highlight (top edge, 1px white line for glass refraction)
///   4. Luminous border (gradient stroke matching cluster color)
///   5. Mini-thumbnail preview (clipped, semi-transparent)
///   6. Label pill (dark bg + white text, above bubble)
///
/// CONNECTIONS:
///   - Gradient arrow: color transitions from source → target cluster
///   - Flowing particles with radial gradient + trailing fade
///   - Arrowhead with matching gradient fill
///
/// LOD LEVELS:
///   - Level 0 (zoom > 0.5): Underlines only — connections hidden
///   - Level 1 (zoom 0.15–0.5): Full premium + glassmorphic cluster bubbles
///   - Level 2 (zoom < 0.15): Satellite — luminous dots + importance arrows
class KnowledgeFlowPainter extends CustomPainter {
  final List<ContentCluster> clusters;
  final KnowledgeFlowController controller;
  final double canvasScale;
  final bool enabled;

  /// 💡 Show suggestion hints? Only true in pan mode.
  final bool showSuggestions;

  /// Connection drag state
  final Offset? dragSourcePoint;
  final Offset? dragCurrentPoint;
  final String? dragSourceClusterId;
  final String? snapTargetClusterId;

  /// 🖼️ Mini-thumbnail previews
  final Map<String, ui.Image> thumbnails;

  /// 🔤 Recognized text per cluster (from DigitalInk + _clusterTextCache).
  /// Raw OCR — may contain MyScript artefacts ("Prima lelle o' newtn").
  final Map<String, String> clusterTexts;

  /// 🧹 AI-cleaned OCR per cluster (from ClusterConceptIndex.cleanedOcr).
  /// Preferred over [clusterTexts] for any user-visible surface — the
  /// flashcard mini-card, keyword extraction, and OCR preview all read
  /// `cleanedOcrTexts[id] ?? clusterTexts[id]` so they show normalised
  /// text while the AI cleanup is in-flight or absent.
  final Map<String, String> cleanedOcrTexts;

  /// ✨ Animation time (seconds) for breathing + particle effects
  final double animationTime;

  /// 🔵 Currently selected connection (for highlight effect)
  final String? selectedConnectionId;

  /// 🧠 SEMANTIC MORPHING: morph progress (0.0 = ink, 1.0 = semantic)
  final double semanticMorphProgress;

  /// 🧠 SEMANTIC MORPHING: controller with titles and stats
  final SemanticMorphController? semanticController;

  /// 🎬 CINEMATIC FLIGHT: Flight animation progress (0.0—1.0).
  final double flightProgress;

  /// 🎬 CINEMATIC FLIGHT: Current phase index (-1 = no flight).
  final int flightPhase;

  /// 🎯 CINEMATIC FLIGHT: Source cluster ID (for connection-specific glow).
  final String? flightSourceClusterId;

  /// 🎯 CINEMATIC FLIGHT: Target cluster ID (for connection-specific glow).
  final String? flightTargetClusterId;

  /// 🎬 LANDING PULSE: Expanding ring progress (0.0—1.0). 0 = inactive.
  final double landingPulseProgress;

  /// 🎬 LANDING PULSE: Center of the pulse in canvas coordinates.
  final Offset landingPulseCenter;

  // ---------------------------------------------------------------------------
  // 🎤 AUDIO-INK SYNC: Highlight state for Flow Playback
  // ---------------------------------------------------------------------------

  /// ID of the stroke currently highlighted by audio-ink sync (tap-to-seek).
  final String? audioHighlightStrokeId;

  /// ID of the connection currently highlighted by audio-ink sync.
  final String? audioHighlightConnectionId;

  /// Highlight intensity for audio-ink sync (0.0—1.0, decaying).
  final double audioHighlightIntensity;

  // ---------------------------------------------------------------------------
  // 🃏 FLASHCARD ENHANCEMENTS
  // ---------------------------------------------------------------------------

  /// 💡 Proactive knowledge gaps per cluster (clusterId → list of gap concepts).
  final Map<String, List<String>> proactiveGaps;

  /// 💡 Proactive scan text per cluster (clusterId → AI-generated description).
  final Map<String, String> proactiveScan;

  /// 📅 Spaced repetition schedule (concept → FSRS card data).
  final Map<String, SrsCardData> reviewSchedule;

  /// 🚀 P99 FIX: Whether the canvas is actively being panned/zoomed.
  /// When true, paint() early-returns and shouldRepaint suppresses animation diffs.
  final bool isPanning;

  /// 🏛️ Cluster IDs classified as "monuments" by the [MonumentResolver].
  /// At LOD 2 these are rendered with a persistent title label + landmark
  /// dot, so the student sees named anchors on the mappamondo (§1098).
  /// Empty set → no monuments rendered (backward-compatible default).
  final Set<String> monumentIds;

  /// 🏛️ Normalized importance score 0..1 per cluster (optional).
  /// Drives size/opacity of the monument glyph at LOD 2.
  final Map<String, double> monumentImportance;

  /// 🗺️ Auto-derived macro-zone labels rendered at extreme zoom-out
  /// ("mappamondo con i nomi delle materie", §1098, §1981).
  /// Empty list → no zone layer rendered.
  final List<ZoneLabel> zoneLabels;

  /// 🗺️ Cluster ID → zone ID membership (from [ZoneLabeler]).
  /// Used by the LOD 2 connection filter to *keep* inter-zone connections
  /// even if they're geometrically short — they're structural bridges
  /// between macro-regions (§1578 "frecce che attraversano zone distanti").
  final Map<String, String> zoneMembership;

  /// 🧠 Cluster IDs currently concealed for Active Recall (SRS blur or
  /// Fog of War). Monument pills on these clusters are suppressed so the
  /// student isn't spoiled with the cluster's title text while attempting
  /// to recall its content (§2 teoria, Active Recall). Zones stay visible
  /// because they name the macro-region, not individual items.
  final Set<String> hiddenForRecallClusterIds;

  /// 🌡️ FSRS stage per cluster (worst-of matched concepts). Same map
  /// already consumed by `FsrsHeatMapPainter` — passed through here so
  /// `_paintGodView` can derive a "continent stage" by taking the worst
  /// stage across each super-node's member clusters (and the meta tier's
  /// member super-nodes by transitivity). The continent glow gets a
  /// subtle tint toward that stage color so the student sees at a glance
  /// which area of the Palazzo is fragile vs solid (§1416-1420).
  ///
  /// `null` value = cluster never matched any FSRS concept (untouched);
  /// missing key = same. Empty map disables the propagation entirely.
  final Map<String, SrsStage?> clusterStages;

  // LOD thresholds
  static const double _lodLevel1Min = 0.15;
  static const double _lodLevel1Max = 0.5;

  // Bubble geometry
  static const double _bubblePadding = 20.0;
  static const double _bubbleCornerRadius = 16.0;

  // Reusable paints (zero-alloc per frame)
  static final Paint _p = Paint();
  static final Paint _shadowPaint = Paint()
    ..style = PaintingStyle.fill
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
  static final Paint _glowPaint = Paint()
    ..style = PaintingStyle.fill
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
  static final Paint _softGlowPaint = Paint()
    ..style = PaintingStyle.fill
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);

  // 🚀 PERF: Reusable Path to avoid GC churn (reset() instead of new Path())
  static final Path _reusePath = Path();

  // 🚀 PERF: Pre-cached MaskFilter constants (avoid per-frame allocation)
  static const MaskFilter _blurLod1 = MaskFilter.blur(BlurStyle.normal, 3.0);
  static const MaskFilter _blurLod2 = MaskFilter.blur(BlurStyle.normal, 6.0);

  // 🚀 PERF: TextPainter cache for semantic node titles/icons.
  // Key = clusterId + content hash. Avoids re-layout every frame.
  // Auto-prunes at 100 entries.
  static final Map<String, TextPainter> _cachedTitlePainters = {};

  KnowledgeFlowPainter({
    required this.clusters,
    required this.controller,
    required this.canvasScale,
    this.enabled = true,
    this.showSuggestions = false,
    this.dragSourcePoint,
    this.dragCurrentPoint,
    this.dragSourceClusterId,
    this.snapTargetClusterId,
    this.thumbnails = const {},
    this.clusterTexts = const {},
    this.cleanedOcrTexts = const {},
    this.animationTime = 0.0,
    this.selectedConnectionId,
    this.semanticMorphProgress = 0.0,
    this.semanticController,
    this.flightProgress = 0.0,
    this.flightPhase = -1,
    this.flightSourceClusterId,
    this.flightTargetClusterId,
    this.landingPulseProgress = 0.0,
    this.landingPulseCenter = Offset.zero,
    this.audioHighlightStrokeId,
    this.audioHighlightConnectionId,
    this.audioHighlightIntensity = 0.0,
    this.proactiveGaps = const {},
    this.proactiveScan = const {},
    this.reviewSchedule = const {},
    this.isPanning = false,
    this.monumentIds = const <String>{},
    this.monumentImportance = const <String, double>{},
    this.zoneLabels = const <ZoneLabel>[],
    this.zoneMembership = const <String, String>{},
    this.hiddenForRecallClusterIds = const <String>{},
    this.clusterStages = const <String, SrsStage?>{},
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled || !controller.enabled) return;
    if (clusters.isEmpty && controller.connections.isEmpty) return;

    // 🚀 P99 FIX: During pan/zoom, shouldRepaint returns false so this
    // method is NOT called. The GPU raster cache from the last idle frame
    // persists. DO NOT early-return here — that would produce an empty
    // canvas and invalidate the raster cache (causes 24ms regression).

    final lod = _getLodLevel();
    final fade = _computeFade();

    // 📚 LOW-ZOOM GATE: gate the costly cosmetic layers (glow, halos,
    // badges, underlines, network stats, flight VFX) when they are
    // sub-pixel on screen.
    //
    // Threshold lowered 0.20 → 0.08 (2026-05-16) to make room for the
    // mappamondo tier (§22, §26, §1098): with the new SemanticMorphController
    // thresholds (morph 0.30→0.18, god view 0.16→0.10), the range 0.20→0.10
    // is the satellite view where monument pills + zone names + super-nodes
    // are the *primary* legible artifact. The pill rendering self-scales
    // via inverseScale so legibility holds down to the user clamp 0.10.
    final bool _isLowZoom = canvasScale < 0.08;

    // 🧠 SEMANTIC MORPHING: When morph is active, overlay semantic nodes
    final morphT = semanticMorphProgress.clamp(0.0, 1.0);
    final hasMorph = morphT > 0.01 && semanticController != null;

    if (lod == 0) {
      // FX4 — hub halo Tier 0: at scale ≥ 0.50 the user is in active
      // drawing mode and no cluster is explicitly shown. A faint colored
      // halo around hub clusters (≥3 connections) hints "there's a key
      // concept here — try zooming out to see the map". Generation Effect
      // §3: anticipate the cluster discovery instead of revealing it
      // "by surprise" below scale 0.30. Hub-only, alpha kept low so it
      // never competes with the ink. Cluster non-hub invariati.
      _paintHubHalosTier0(canvas, fade);
      // LOD 0: Clean connections visible at zoomed-in level too.
      // No glow/particles, just underlines + connections + badges.
      _paintWordUnderlines(canvas, fade.clamp(0.3, 1.0));
      _paintConnections(canvas, lod, 1.0);
      _paintGhostConnectionsDashed(canvas, 1.0);
      _paintConnectionBadges(canvas, lod, 1.0);
      // 🎯 Drag preview must be visible at ALL zoom levels
      if (dragSourcePoint != null && dragCurrentPoint != null) {
        _paintDragPreview(canvas);
      }
      return;
    }

    // Render order: zone tints → network glow → halos → cluster visuals →
    // underlines → connections → badges → drag
    final lod2Fade = _computeLod2Fade();

    // 🗺️ ZONE TINTS: soft colored regions per super-node, emergent on
    // the mappamondo (§22 "i quartieri del Palazzo", §1133). Renders
    // FIRST so every later layer overlays the tinted regions.
    //
    // 2026-05-17 fix: was gated `lod == 2` (= scale ≤ 0.15), which
    // hid zone tints in the 0.30→0.15 morph transition where the
    // teoria-cognitiva mappamondo tier promised "20% → ink quasi
    // sparito, zone tint emergente". Now gated only by `hasMorph`,
    // letting the alpha modulation (morphT × fade) handle the fade-in.
    if (hasMorph) {
      _paintZoneTints(canvas, fade);
    }

    // 📚 LOW-ZOOM SKIP: network glow is a sub-pixel ambient halo.
    if (lod2Fade > 0.01 && !_isLowZoom) {
      _paintNetworkGlow(canvas, fade * lod2Fade);
    }

    // LOD 2: Cluster grouping halos for nearby clusters
    // 📚 LOW-ZOOM SKIP: O(N²) halo loop, illegible at this zoom.
    if (lod == 2 && !_isLowZoom) {
      _paintClusterGroupHalos(canvas, fade);
    }

    // LOD 2: Luminous cluster dots (satellite view)
    // 🧠 SEMANTIC MORPHING: Fade out dots as semantic nodes fade in
    if (lod == 2 && !hasMorph) {
      _paintClusterDots(canvas, fade);
    } else if (lod == 2 && hasMorph) {
      // Crossfade: dots fade out, semantic nodes fade in
      _paintClusterDots(canvas, fade * (1.0 - morphT));
    }
    // LOD 1: Glassmorphic cluster bubbles with recognized text
    if (lod == 1) {
      _paintClusterBubbles(canvas, fade);
    }

    // 📚 LOW-ZOOM SKIP: word underlines are 1-2 px decorations under
    // each recognized word — sub-pixel below scale 0.20.
    if (!_isLowZoom) {
      _paintWordUnderlines(canvas, fade);
    }
    _paintConnections(canvas, lod, fade);
    // 📚 LOW-ZOOM SKIP: dashed ghost connections are visual hints,
    // unreadable at extreme zoom-out (already drawn by base
    // _paintConnections at LOD 2).
    if (!_isLowZoom) {
      _paintGhostConnectionsDashed(canvas, fade);
    }

    // 📍 Connection count badges (LOD 1-2)
    // 📚 LOW-ZOOM SKIP: numeric badges are 5×8 px, illegible.
    if (!_isLowZoom) {
      _paintConnectionBadges(canvas, lod, fade);
    }

    // 🏛️ MONUMENT LABELS (LOD 2 satellite view): named landmarks of the
    // student's Memory Palace (§1098). Kept visible through most of the
    // semantic-morph crossfade and faded out as AI super-nodes / semantic
    // nodes start dominating (morphT > 0.5). This prevents the 4-layer
    // cognitive overload we measured during visual QA: student-derived
    // monuments coexist with early morph, but yield to AI labels when
    // the morph is clearly taking over.
    final landmarkGate = _landmarkLayerFade(morphT);
    // 📚 LOW-ZOOM SKIP: monument pills + glow are gradient saveLayer ops
    // (most expensive in this painter). At scale<0.20 the glow halo is
    // sub-pixel and the pill text < 4 px — invisible anyway.
    if (lod == 2 &&
        monumentIds.isNotEmpty &&
        landmarkGate > 0.01 &&
        !_isLowZoom) {
      _paintMonumentLabels(canvas, fade * landmarkGate);
    }

    // 🗺️ ZONE LABELS (LOD 2 mappamondo): auto-derived macro-region names
    // from the student's own handwriting (§1981 "i nomi delle macro-zone").
    // Same crossfade gate as monuments.
    // 📚 LOW-ZOOM SKIP: large text labels with shadows, illegible.
    if (lod == 2 &&
        zoneLabels.isNotEmpty &&
        landmarkGate > 0.01 &&
        !_isLowZoom) {
      _paintZoneLabels(canvas, fade * landmarkGate);
    }

    // 🔮 EARLY TITLE PREVIEW: AI titles as floating labels above clusters
    // BEFORE ink starts to fade. Tells the user "qualcosa sta per cambiare"
    // so the mappamondo transition doesn't feel abrupt.
    //
    // 🌍 FASE 5 fix — window triplicata: was (0.305, 0.35] with smoothstep
    // alpha 0 at endpoints → effective sweet-spot only 0.31-0.32, user
    // never saw the preview pills during device test (screenshot a 0.35
    // e 0.30: nessun pill flottante). Now (0.30, 0.40] — 3× larger band,
    // with explicit strict `>` on morphStartScale so monument pills
    // (which kick in at morphT > 0.01 = scale just below 0.30) never
    // overlap with the preview pills geometrically.
    if (!hasMorph &&
        canvasScale <=
            SemanticMorphController.aiPreloadScale + 0.05 && // 0.40
        canvasScale > SemanticMorphController.morphStartScale && // > 0.30 strict
        semanticController != null) {
      _paintEarlyTitlePreview(canvas, fade);
    }

    // 🧠 SEMANTIC MORPHING: Paint semantic nodes on top with morph alpha
    if (hasMorph) {
      // 🌍 GOD VIEW crossfade: semantic nodes fade out as super-nodes appear
      final godT = semanticController?.godViewProgress ?? 0.0;
      final semanticFade = fade * morphT * (1.0 - godT);

      if (semanticFade > 0.01) {
        _paintSemanticNodes(canvas, semanticFade);
        _paintSuggestions(canvas, lod, semanticFade);
      }

      // 🌍 GOD VIEW: Paint super-nodes on top
      if (godT > 0.01) {
        _paintGodView(canvas, fade * morphT * godT);
      }

      // 🃏 FLASHCARD PREVIEW: Mini-card on tapped semantic node
      if (semanticController?.flashcardClusterId != null ||
          semanticController?.isFlashcardDismissing == true) {
        _paintFlashcard(canvas, fade * morphT);
      }
    }

    if (dragSourcePoint != null && dragCurrentPoint != null) {
      _paintDragPreview(canvas);
    }

    // 📊 Network stats badge (LOD 2 only)
    // 📚 LOW-ZOOM SKIP: tiny corner badge, sub-pixel readability.
    if (lod == 2 && !_isLowZoom) {
      _paintNetworkStats(canvas);
    }

    // 🎬 CINEMATIC FLIGHT: Speed-glow + vignette during camera flight
    // 📚 LOW-ZOOM SKIP: flight VFX are full-screen glow/vignette, very
    // expensive (saveLayer + gradients). User rarely triggers a flight
    // animation at scale<0.20 — and if they do, the visuals collapse
    // to indistinct color anyway.
    if (flightProgress > 0.01 && flightProgress < 0.99 && !_isLowZoom) {
      _paintFlightEffects(canvas, size, fade);
    }
  }

  int _getLodLevel() {
    if (canvasScale > _lodLevel1Max) return 0;
    if (canvasScale > _lodLevel1Min) return 1;
    return 2;
  }

  // ===========================================================================
  // PHASE 0: NETWORK GLOW (LOD 2 only — \"connected world\" effect)
  // ===========================================================================
  //
  // Paints wide, blurred luminous lines between connected nodes.
  // Creates the satellite night-view / neural network aesthetic.

  void _paintNetworkGlow(Canvas canvas, double fade) {
    final cMap = _buildClusterMap();

    // ── Constellation lines: faint links between nearby unconnected clusters ──
    // Capped to max 8 pairs to avoid O(n²) performance death
    if (clusters.length <= 20) {
      final connectedPairs = <int>{};
      for (final conn in controller.connections) {
        connectedPairs.add(conn.sourceClusterId.hashCode ^ conn.targetClusterId.hashCode);
      }
      var drawn = 0;
      for (int i = 0; i < clusters.length && drawn < 8; i++) {
        for (int j = i + 1; j < clusters.length && drawn < 8; j++) {
          final a = clusters[i];
          final b = clusters[j];
          final pairHash = a.id.hashCode ^ b.id.hashCode;
          if (connectedPairs.contains(pairHash)) continue;
          final dist = (a.centroid - b.centroid).distance;
          if (dist > 1200 || dist < 80) continue;

          final proximity = 1.0 - (dist / 1200.0);
          final alpha = proximity * 0.03 * fade;
          // Single solid line (NOT dashed — dashed was too many drawcalls)
          _p
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0)
            ..color = Colors.white.withValues(alpha: alpha);
          canvas.drawLine(a.centroid, b.centroid, _p);
          _p.maskFilter = null;
          drawn++;
        }
      }
    }

    // ── Luminous connection glow ──
    final glowConns = controller.visibleConnections;
    if (glowConns.isEmpty) return;

    for (final conn in glowConns) {
      final src = cMap[conn.sourceClusterId];
      final tgt = cMap[conn.targetClusterId];
      if (src == null || tgt == null) continue;

      final srcPt = src.centroid;
      final tgtPt = tgt.centroid;
      final cp = controller.getControlPoint(srcPt, tgtPt, conn.curveStrength);
      final srcColor = _clusterColor(src);
      final tgtColor = _clusterColor(tgt);

      // Staggered pulse per connection — creates organic "data flow" feel
      final pulse = math.sin(animationTime * 1.5 + srcPt.dx * 0.002 + tgtPt.dy * 0.001) * 0.5 + 0.5;
      final glowAlpha = (0.06 + pulse * 0.08) * fade;

      // Wide blurred "light thread" — the ambient network glow
      // 🚀 P99 FIX: Reuse _reusePath instead of allocating Path() per connection.
      // 🚀 P99 FIX: Use Color.lerp instead of LinearGradient.createShader() —
      // at LOD 2 (~6% opacity), the gradient is imperceptible.
      _reusePath.reset();
      _reusePath.moveTo(srcPt.dx, srcPt.dy);
      _reusePath.quadraticBezierTo(cp.dx, cp.dy, tgtPt.dx, tgtPt.dy);
      final blendedColor = Color.lerp(srcColor, tgtColor, 0.5)!;

      // Layer 1: Very wide ambient glow
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0)
        ..shader = null
        ..color = blendedColor.withValues(alpha: glowAlpha * 0.7);
      canvas.drawPath(_reusePath, _p);

      // Layer 2: Narrower, brighter core glow
      _p
        ..strokeWidth = 8.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0)
        ..color = blendedColor.withValues(alpha: glowAlpha * 1.2);
      canvas.drawPath(_reusePath, _p);

      _p
        ..maskFilter = null
        ..shader = null;
    }
  }

  // ===========================================================================
  // PHASE 1: WORD UNDERLINES — Clean underlines under connected clusters
  // ===========================================================================

  void _paintWordUnderlines(Canvas canvas, double fade) {
    final underlineConns = controller.visibleConnections;
    if (underlineConns.isEmpty && snapTargetClusterId == null &&
        dragSourceClusterId == null) return;

    // Collect IDs of clusters that participate in connections
    final connectedIds = <String>{};
    final connColors = <String, Color>{};
    for (final conn in underlineConns) {
      connectedIds.add(conn.sourceClusterId);
      connectedIds.add(conn.targetClusterId);
      connColors[conn.sourceClusterId] = conn.color;
      connColors[conn.targetClusterId] = conn.color;
    }

    // Also include drag source/target for live feedback
    if (dragSourceClusterId != null) connectedIds.add(dragSourceClusterId!);
    if (snapTargetClusterId != null) connectedIds.add(snapTargetClusterId!);

    for (final cluster in clusters) {
      if (!connectedIds.contains(cluster.id)) continue;
      if (cluster.bounds.isEmpty || cluster.bounds.width < 2) continue;

      final color = connColors[cluster.id] ?? _clusterColor(cluster);
      final bounds = cluster.bounds;
      final underlineY = bounds.bottom + 3.0;
      final left = bounds.left;
      final right = bounds.right;

      final isSnapTarget = snapTargetClusterId == cluster.id;
      final isDragSource = dragSourceClusterId == cluster.id;

      // Breathing pulsation for active drag targets
      final breath = isSnapTarget
          ? (math.sin(animationTime * 4.0) * 0.5 + 0.5)
          : (isDragSource ? 0.8 : 0.0);

      // === Glow layer (blurred underline) ===
      final glowAlpha = isSnapTarget
          ? (0.45 + breath * 0.30) * fade
          : isDragSource
              ? 0.35 * fade
              : 0.30 * fade;
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSnapTarget ? 8.0 : 5.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0)
        ..color = color.withValues(alpha: glowAlpha);
      canvas.drawLine(
        Offset(left, underlineY),
        Offset(right, underlineY),
        _p,
      );
      _p.maskFilter = null;

      // === Core underline ===
      final lineAlpha = isSnapTarget
          ? (0.75 + breath * 0.20) * fade
          : isDragSource
              ? 0.65 * fade
              : 0.60 * fade;
      _p
        ..strokeWidth = isSnapTarget ? 3.0 : 2.2
        ..color = color.withValues(alpha: lineAlpha);
      canvas.drawLine(
        Offset(left, underlineY),
        Offset(right, underlineY),
        _p,
      );
    }
  }

  // ===========================================================================
  // PHASE 3: MINI-THUMBNAILS
  // ===========================================================================

  void _paintThumbnails(Canvas canvas, int lod, double fade) {
    if (lod < 1 || thumbnails.isEmpty) return;

    for (final cluster in clusters) {
      final thumb = thumbnails[cluster.id];
      if (thumb == null) continue;

      final bounds = cluster.bounds.inflate(_bubblePadding);
      final cr = lod == 2 ? _bubbleCornerRadius * 1.5 : _bubbleCornerRadius;
      final rrect = RRect.fromRectAndRadius(bounds, Radius.circular(cr));

      canvas.save();
      canvas.clipRRect(rrect);

      // Fit thumbnail inside bubble with padding
      final inner = bounds.deflate(_bubblePadding * 0.6);
      final thumbAspect = thumb.width / thumb.height;
      final innerAspect = inner.width / inner.height;

      Rect dst;
      if (thumbAspect > innerAspect) {
        final h = inner.width / thumbAspect;
        dst = Rect.fromCenter(
          center: inner.center,
          width: inner.width,
          height: h,
        );
      } else {
        final w = inner.height * thumbAspect;
        dst = Rect.fromCenter(
          center: inner.center,
          width: w,
          height: inner.height,
        );
      }

      _p
        ..style = PaintingStyle.fill
        ..shader = null
        ..color = Color.fromRGBO(255, 255, 255, 0.65 * fade)
        ..filterQuality = FilterQuality.low;
      canvas.drawImageRect(
        thumb,
        Rect.fromLTWH(0, 0, thumb.width.toDouble(), thumb.height.toDouble()),
        dst,
        _p,
      );
      canvas.restore();
    }
  }

  // ===========================================================================
  // PHASE 4: CONNECTIONS — Gradient arrows + particle trails
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // 👻 GHOST CONNECTIONS — Dashed pulsating spectral lines (Feature 2)
  // ---------------------------------------------------------------------------
  //
  // Ghost connections are AI-generated anticipatory links. They render as:
  //   - Dashed line with animated scrolling effect
  //   - Spectral cyan glow that pulses at 1.5Hz
  //   - Directional particles flowing along the dashes
  //   - 🎤 Audio-ink highlight: golden glow burst when tapped for seek

  /// Shared LOD-2 long-distance filter predicate.
  ///
  /// Returns true when [conn] should be culled at the satellite view
  /// because it's micro-cablaggio: short, unlabeled, intra-zone, not
  /// cross-zone, not currently interactive (selected / audio-highlighted).
  /// Applied both to solid connections and ghost-dashed connections so
  /// the mappamondo stays legible regardless of which layer owns the
  /// short link (§1578 "frecce lunghe che attraversano zone distanti").
  bool _shouldSkipAtLod2(
    KnowledgeConnection conn,
    Offset srcPt,
    Offset tgtPt,
  ) {
    if (conn.isCrossZone) return false;
    if (conn.label != null && conn.label!.isNotEmpty) return false;
    if (conn.id == selectedConnectionId) return false;
    if (conn.id == audioHighlightConnectionId) return false;

    final srcZone = zoneMembership[conn.sourceClusterId];
    final tgtZone = zoneMembership[conn.targetClusterId];
    final isInterZoneBridge =
        srcZone != null && tgtZone != null && srcZone != tgtZone;
    if (isInterZoneBridge) return false;

    final ddx = tgtPt.dx - srcPt.dx;
    final ddy = tgtPt.dy - srcPt.dy;
    final connLen = math.sqrt(ddx * ddx + ddy * ddy);
    const lod2MinLen = KnowledgeConnection.crossZoneDistanceThreshold / 2;
    return connLen < lod2MinLen;
  }

  void _paintGhostConnectionsDashed(Canvas canvas, double fade) {
    // Dismissed ghosts are kept in the scene as tombstones (avoid-list source)
    // but never rendered — see CrossZoneBridgeController.dismissBridge.
    final ghostConns = controller.connections
        .where((c) => c.isGhost && !c.bridgeSuggestionDismissed);
    if (ghostConns.isEmpty) return;

    final cMap = _buildClusterMap();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final atLod2 = _getLodLevel() == 2;

    for (final conn in ghostConns) {
      final src = cMap[conn.sourceClusterId];
      final tgt = cMap[conn.targetClusterId];
      if (src == null || tgt == null) continue;

      // === Anchor points ===
      // Ghosts use the live centroid every frame so the suggestion line
      // tracks cluster mutations (anchor-drift fix, Passo 9). Materialized
      // bridges keep their frozen anchor for visual stability after accept.
      final srcCenter = src.centroid;
      final tgtCenter = tgt.centroid;
      final dx = (tgtCenter.dx - srcCenter.dx).abs();
      final dy = (tgtCenter.dy - srcCenter.dy).abs();
      final Offset srcPt;
      final Offset tgtPt;
      if (dx > dy * 1.5) {
        srcPt = tgtCenter.dx > srcCenter.dx
            ? Offset(src.bounds.right + 4, srcCenter.dy)
            : Offset(src.bounds.left - 4, srcCenter.dy);
        tgtPt = tgtCenter.dx > srcCenter.dx
            ? Offset(tgt.bounds.left - 4, tgtCenter.dy)
            : Offset(tgt.bounds.right + 4, tgtCenter.dy);
      } else {
        srcPt = tgtCenter.dy < srcCenter.dy
            ? Offset(srcCenter.dx, src.bounds.top - 4)
            : Offset(srcCenter.dx, src.bounds.bottom + 4);
        tgtPt = tgtCenter.dy < srcCenter.dy
            ? Offset(tgtCenter.dx, tgt.bounds.bottom + 4)
            : Offset(tgtCenter.dx, tgt.bounds.top - 4);
      }

      // 🏛️ LOD 2 long-distance filter — ghosts participate too, so short
      // intra-zone ghost arrows don't clutter the satellite view.
      if (atLod2 && _shouldSkipAtLod2(conn, srcPt, tgtPt)) continue;

      final cp = controller.getControlPoint(srcPt, tgtPt, conn.curveStrength);

      // === Ghost birth fade-in (500ms) ===
      final ghostAge = (nowMs - conn.createdAtMs) / 500.0;
      final ghostFadeIn = ghostAge.clamp(0.0, 1.0);

      // === Breathing pulse (1.5Hz) — creates the "alive" feel ===
      final pulse = math.sin(animationTime * 3.0 + conn.id.hashCode * 0.5) *
              0.5 +
          0.5;
      final breathAlpha = (0.25 + pulse * 0.35) * fade * ghostFadeIn;

      // === Audio-ink highlight (golden glow when tapped for seek) ===
      final isAudioHighlighted = audioHighlightConnectionId == conn.id;
      final audioGlow = isAudioHighlighted ? audioHighlightIntensity : 0.0;

      // Ghost spectral color — cyan/teal for AI-generated connections
      const ghostColor = Color(0xFF00E5FF); // Cyan A400
      final glowColor = isAudioHighlighted
          ? Color.lerp(ghostColor, const Color(0xFFFFD54F), audioGlow)!
          : ghostColor;

      // === Outer glow (diffuse spectral haze) ===
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12.0 + audioGlow * 8.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0)
        ..shader = null
        ..color = glowColor.withValues(alpha: breathAlpha * 0.3);

      _reusePath.reset();
      _reusePath.moveTo(srcPt.dx, srcPt.dy);
      _reusePath.quadraticBezierTo(cp.dx, cp.dy, tgtPt.dx, tgtPt.dy);
      canvas.drawPath(_reusePath, _p);
      _p.maskFilter = null;

      // === Animated dashed line (scrolling dash offset) ===
      final pathMetrics = _reusePath.computeMetrics().firstOrNull;
      if (pathMetrics == null) continue;
      final pathLen = pathMetrics.length;

      final dashLen = 16.0;
      final gapLen = 10.0;
      final dashCycle = dashLen + gapLen;

      // Scroll speed: dashes flow along the connection
      final scrollOffset = (animationTime * 40.0) % dashCycle;

      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 + audioGlow * 2.0
        ..strokeCap = StrokeCap.round
        ..shader = null
        ..color = glowColor.withValues(alpha: breathAlpha);

      double dist = -scrollOffset;
      while (dist < pathLen) {
        final start = dist.clamp(0.0, pathLen);
        final end = (dist + dashLen).clamp(0.0, pathLen);
        if (end > start + 0.5) {
          final dashPath = pathMetrics.extractPath(start, end);
          canvas.drawPath(dashPath, _p);
        }
        dist += dashCycle;
      }

      // 2026-05-17: ghost-connection "flowing spectral particle" rimosso —
      // user-facing era visivamente confondibile come "stelline gialle che
      // si muovono" senza significato chiaro.

      // === "AI" indicator pill at midpoint ===
      final midT = 0.5;
      final midPt = controller.pointOnQuadBezier(srcPt, cp, tgtPt, midT);

      // Pill background
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: midPt, width: 24, height: 14),
        const Radius.circular(7),
      );
      _p
        ..style = PaintingStyle.fill
        ..color = glowColor.withValues(alpha: breathAlpha * 0.5);
      canvas.drawRRect(pillRect, _p);

      // "AI" text
      final cacheKey = '__ghost_ai_pill';
      var tp = _cachedTitlePainters[cacheKey];
      if (tp == null) {
        tp = TextPainter(
          text: const TextSpan(
            text: 'AI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        _cachedTitlePainters[cacheKey] = tp;
      }
      tp.paint(
        canvas,
        Offset(midPt.dx - tp.width / 2, midPt.dy - tp.height / 2),
      );
    }
  }


  void _paintGhostConnections(Canvas canvas) {
    final visibleConns = controller.visibleConnections;
    if (visibleConns.isEmpty) return;

    final cMap = _buildClusterMap();
    for (final conn in visibleConns) {
      final src = cMap[conn.sourceClusterId];
      final tgt = cMap[conn.targetClusterId];
      if (src == null || tgt == null) continue;

      // 🎯 Anchor to bottom-center of word bounds (not centroid)
      final srcPt = Offset(src.bounds.center.dx, src.bounds.bottom + 4);
      final tgtPt = Offset(tgt.bounds.center.dx, tgt.bounds.bottom + 4);
      final srcColor = _clusterColor(src);
      final tgtColor = _clusterColor(tgt);
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round
        ..shader = null
        ..color = Color.lerp(srcColor, tgtColor, 0.5)!.withValues(alpha: 0.06);

      final path = controller.computeBezierPath(
        source: srcPt,
        target: tgtPt,
        curveStrength: conn.curveStrength,
      );
      canvas.drawPath(path, _p);
      _p.shader = null;
    }
  }

  void _paintConnections(Canvas canvas, int lod, double fade) {
    if (controller.connections.isEmpty) return;

    final cMap = _buildClusterMap();

    // 🚀 PERF: Cache DateTime.now() once per paint call (not per connection)
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 🏷️ LOD 2 LABEL GROUPING: at extreme dezoom, multiple connections with
    // the same label pile up near hub clusters into unreadable pill spam.
    // Group by normalized label: only the *first* connection in each group
    // renders the pill, with a "×N" suffix when more than one shares it.
    // Computed once pre-loop; canonical membership is consulted inside.
    final Map<String, String> labelGroupCanonical = {};
    final Map<String, int> labelGroupCount = {};
    if (lod == 2) {
      for (final c in controller.connections) {
        if (c.isGhost) continue;
        final raw = c.label;
        if (raw == null || raw.isEmpty) continue;
        final key = raw.trim().toLowerCase();
        labelGroupCount[key] = (labelGroupCount[key] ?? 0) + 1;
        labelGroupCanonical.putIfAbsent(key, () => c.id);
      }
    }

    // 🚀 PERF: Pre-compute bi-directional set O(n) instead of O(n²) per-connection
    Set<int>? bidirSet;
    if (controller.connections.length > 1) {
      bidirSet = <int>{};
      for (final c in controller.connections) {
        bidirSet.add(c.sourceClusterId.hashCode ^ c.targetClusterId.hashCode);
      }
    }
    // 🔀 SMART ROUTING: Count parallel connections between same cluster pairs
    // to offset their curve strengths and avoid overlap.
    final pairIndexMap = <int, int>{};
    final pairCountMap = <int, int>{};
    for (final conn in controller.connections) {
      final pairKey = conn.sourceClusterId.hashCode ^ conn.targetClusterId.hashCode;
      pairCountMap[pairKey] = (pairCountMap[pairKey] ?? 0) + 1;
    }

    final connCount = controller.connections.length;

    // 🌐 HUB-NODE SCALING: Count connections per cluster for thickness bonus
    final clusterConnCount = <String, int>{};
    for (final conn in controller.connections) {
      clusterConnCount[conn.sourceClusterId] =
          (clusterConnCount[conn.sourceClusterId] ?? 0) + 1;
      clusterConnCount[conn.targetClusterId] =
          (clusterConnCount[conn.targetClusterId] ?? 0) + 1;
    }

    int connIndex = 0;
    for (final conn in controller.connections) {
      // 👻 Skip ghost connections — rendered separately by _paintGhostConnectionsDashed
      if (conn.isGhost) { connIndex++; continue; }
      final src = cMap[conn.sourceClusterId];
      final tgt = cMap[conn.targetClusterId];
      if (src == null || tgt == null) continue;

      // 🎯 Smart anchor 4-WAY: pick the closest side (top/bottom/left/right)
      // based on relative position of clusters. Prevents curve crossing text.
      // 📌 Use frozen anchors when available to prevent endpoint shifts
      final srcCenter = conn.sourceAnchor ?? src.centroid;
      final tgtCenter = conn.targetAnchor ?? tgt.centroid;
      final dx = (tgtCenter.dx - srcCenter.dx).abs();
      final dy = (tgtCenter.dy - srcCenter.dy).abs();
      final Offset srcPt;
      final Offset tgtPt;
      if (dx > dy * 1.5) {
        // Primarily HORIZONTAL separation → use left/right anchors
        if (tgtCenter.dx > srcCenter.dx) {
          srcPt = Offset(src.bounds.right + 4, srcCenter.dy);
          tgtPt = Offset(tgt.bounds.left - 4, tgtCenter.dy);
        } else {
          srcPt = Offset(src.bounds.left - 4, srcCenter.dy);
          tgtPt = Offset(tgt.bounds.right + 4, tgtCenter.dy);
        }
      } else {
        // Primarily VERTICAL separation → use top/bottom anchors
        if (tgtCenter.dy < srcCenter.dy) {
          srcPt = Offset(srcCenter.dx, src.bounds.top - 4);
          tgtPt = Offset(tgtCenter.dx, tgt.bounds.bottom + 4);
        } else {
          srcPt = Offset(srcCenter.dx, src.bounds.bottom + 4);
          tgtPt = Offset(tgtCenter.dx, tgt.bounds.top - 4);
        }
      }

      // 🏛️ LOD 2 LONG-DISTANCE FILTER — see [_shouldSkipAtLod2].
      if (lod == 2 && _shouldSkipAtLod2(conn, srcPt, tgtPt)) {
        connIndex++;
        continue;
      }

      // 🔀 Smart curve offset for multiple connections between same pair
      final pairKey = conn.sourceClusterId.hashCode ^ conn.targetClusterId.hashCode;
      final idx = pairIndexMap[pairKey] ?? 0;
      pairIndexMap[pairKey] = idx + 1;
      final pairTotal = pairCountMap[pairKey] ?? 1;
      // 🔀 ENHANCED: Wider spread for 3+ parallel connections (0.4 instead of 0.3)
      final spreadFactor = pairTotal > 2 ? 0.4 : 0.3;
      final routeOffset = pairTotal > 1
          ? (idx - (pairTotal - 1) / 2.0) * spreadFactor
          : 0.0;
      final effectiveCurveStrength = conn.curveStrength + routeOffset;

      // 🌊 LIVING CURVE: Subtle sinusoidal oscillation of control point
      // Each connection gets a unique phase so they don't move in lockstep
      final livingWave = math.sin(animationTime * 0.6 + connIndex * 1.7) * 0.02;
      final animatedCurveStrength = effectiveCurveStrength + livingWave;
      final cp = controller.getControlPoint(srcPt, tgtPt, animatedCurveStrength);

      // 🎨 Connection color — assigned from palette at creation, user-changeable
      // 🌉 CROSS-ZONE: Golden override for inter-zone bridges (P9-05)
      final connColor = conn.isCrossZone
          ? KnowledgeConnection.crossZoneColor
          : conn.color;
      // Gradient flows from a bright tint to a deeper shade within the connection
      final gradStart = Color.lerp(connColor, Colors.white, 0.30)!;
      final gradEnd = Color.lerp(connColor, const Color(0xFF1A1A2E), 0.25)!;

      // === Connection birth animation (1.5s draw-in with ease-out) ===
      // 🚀 PERF: Skip entirely for loaded connections (createdAtMs == 0)
      final isBirth = conn.createdAtMs > 0;
      final birthAge = isBirth ? (nowMs - conn.createdAtMs) / 1500.0 : 2.0; // 1.5s
      final isBirthAnimating = isBirth && birthAge < 1.0;
      // Cubic ease-out: fast start, smooth deceleration → 1-(1-t)³
      final linearT = isBirthAnimating ? birthAge.clamp(0.0, 1.0) : 1.0;
      final birthProgress = isBirthAnimating
          ? (1.0 - math.pow(1.0 - linearT, 3.0))
          : 1.0;
      final birthFlash = isBirthAnimating ? (1.0 - linearT) * 0.3 : 0.0;

      // 🔦 PATH TRACE: Sequential illumination flash from cluster tap
      final traceFlash = controller.getTraceFlash(conn.id, nowMs);

      // 💨 DISSOLVE: Fading out dying connections (500ms)
      final isDying = conn.deletedAtMs > 0;
      final dissolveAge = isDying ? (nowMs - conn.deletedAtMs) / 500.0 : 0.0;
      if (isDying && dissolveAge >= 1.0) {
        connIndex++;
        continue; // Fully dissolved, skip rendering
      }
      final dissolveFade = isDying ? (1.0 - dissolveAge.clamp(0.0, 1.0)) : 1.0;
      // Scale down slightly as it dissolves
      final dissolveScale = isDying ? (0.8 + 0.2 * dissolveFade) : 1.0;

      // === Smooth gradient curve — vibrant, luminous ===
      final hasLabel = conn.label != null && conn.label!.isNotEmpty;
      // 🏋️ LOD 2 IMPORTANCE WEIGHTING: connections with labels are 2x thicker
      final labelBonus = hasLabel ? (lod == 2 ? 1.5 : 0.5) : 0.0;
      final isSelected = selectedConnectionId == conn.id;
      final isMultiSelected = controller.selectedConnectionIds.contains(conn.id);
      final selectBonus = (isSelected || isMultiSelected) ? 1.0 : 0.0;
      final effectiveFade = fade * dissolveFade;
      // 🌐 HUB SCALING: +0.3 per extra connection (capped at +1.5)
      final srcConns = clusterConnCount[conn.sourceClusterId] ?? 1;
      final tgtConns = clusterConnCount[conn.targetClusterId] ?? 1;
      final hubBonus = ((math.max(srcConns, tgtConns) - 1) * 0.3).clamp(0.0, 1.5);

      // 🔗 TYPE BONUS: causality connections are thicker + brighter
      final typeBonus = conn.connectionType == ConnectionType.causality ? 1.5 : 0.0;
      // 🌉 CROSS-ZONE BONUS: inter-zone bridges (P9-05) are the "autostrade"
      // of the Memory Palace (§22 "frecce lunghe = autostrade", §1150).
      // Base +1.0 always; an extra +2.0 ramps in with morphProgress so on the
      // mappamondo (scale ≤ 0.18) they read as ~3× thicker than intra-zone
      // links — the long-distance pattern is the signature of expertise.
      final crossZoneBonus = conn.isCrossZone
          ? 1.0 + 2.0 * semanticMorphProgress.clamp(0.0, 1.0)
          : 0.0;
      final lineW = ((lod == 2 ? 3.5 : 2.5) + labelBonus + selectBonus + hubBonus + typeBonus + crossZoneBonus) * dissolveScale;
      final lineAlpha = ((lod == 2 ? 0.90 : 0.80) + (hasLabel ? 0.08 : 0.0) + birthFlash + traceFlash * 0.3 + ((isSelected || isMultiSelected) ? 0.15 : 0.0)).clamp(0.0, 1.0);

      // 🎨 TYPE COLOR: contradiction overrides with red tint
      final typeColor = conn.connectionType == ConnectionType.contradiction
          ? Color.lerp(connColor, const Color(0xFFEF5350), 0.6)!
          : connColor;

      // 🔦 FOCUS MODE: When a connection is selected, dim all unrelated connections
      final focusDim = ((selectedConnectionId != null || controller.isMultiSelecting) && !isSelected && !isMultiSelected) ? 0.30 : 1.0;
      final focusedFade = effectiveFade * focusDim;

      // Outer glow — visible, atmospheric (boosted for selected)
      // 🌊 BREATHING: selected connection glow pulses gently at 2Hz
      final breathingPulse = isSelected
          ? (math.sin(animationTime * 4.0) * 0.5 + 0.5) * 0.15
          : 0.0;
      final networkPulse = lod == 2
          ? (math.sin(animationTime * 2.0 + srcPt.dx * 0.001) * 0.5 + 0.5)
          : 0.5;
      final glowOpacity = (lod == 2 ? (0.25 + networkPulse * 0.10) : 0.20) + birthFlash * 0.3 + traceFlash * 0.5 + (isSelected ? 0.20 : 0.0) + breathingPulse;

      // Build full path (bezier for curved/dashed, straight for straight/zigzag)
      final isStraightStyle = conn.connectionStyle == ConnectionStyle.straight ||
          conn.connectionStyle == ConnectionStyle.zigzag;
      _reusePath.reset();
      _reusePath.moveTo(srcPt.dx, srcPt.dy);
      if (isStraightStyle) {
        _reusePath.lineTo(tgtPt.dx, tgtPt.dy);
      } else {
        _reusePath.quadraticBezierTo(cp.dx, cp.dy, tgtPt.dx, tgtPt.dy);
      }

      // 🎬 DRAW-IN: During birth, clip path to only show up to birthProgress
      Path drawPath;
      if (isBirthAnimating) {
        final metrics = _reusePath.computeMetrics().firstOrNull;
        if (metrics != null) {
          drawPath = metrics.extractPath(0, metrics.length * birthProgress);
        } else {
          drawPath = _reusePath;
        }
      } else {
        drawPath = _reusePath;
      }

      // 1) Soft glow — clean, single color
      // Causality gets stronger glow with energy pulse
      final causalityPulse = conn.connectionType == ConnectionType.causality
          ? (math.sin(animationTime * 3.0 + connIndex * 2.0) * 0.5 + 0.5) * 0.2
          : 0.0;
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineW + (lod == 2 ? 8 : 6) + (isSelected ? 4 : 0) + (conn.connectionType == ConnectionType.causality ? 4 : 0)
        ..strokeCap = StrokeCap.round
        ..maskFilter = isSelected ? _blurLod2 : (lod == 2 ? _blurLod2 : _blurLod1)
        ..shader = null
        ..color = typeColor.withValues(alpha: (glowOpacity + causalityPulse) * focusedFade);
      canvas.drawPath(drawPath, _p);
      _p.maskFilter = null;

      // 📐 VARIABLE THICKNESS: Draw as 16 segments with bell-curve stroke width
      // Thinnest at endpoints (60%), thickest at center (110%)
      const segments = 16;
      final maxT = isBirthAnimating ? birthProgress : 1.0;

      // 🔗 HIERARCHY: Double parallel lines (offset perpendicular)
      final isHierarchy = conn.connectionType == ConnectionType.hierarchy;
      // 🔗 CONTRADICTION: Zigzag offset
      final isContradiction = conn.connectionType == ConnectionType.contradiction;
      // 🎨 CONNECTION STYLE
      final isDashedStyle = conn.connectionStyle == ConnectionStyle.dashed;
      final isZigzagStyle = conn.connectionStyle == ConnectionStyle.zigzag;

      for (int s = 0; s < segments; s++) {
        // 🎨 DASHED: skip odd segments to create gaps
        if (isDashedStyle && s.isOdd) continue;

        final t0 = (s / segments) * maxT;
        final t1 = ((s + 1) / segments) * maxT;
        final tMid = (t0 + t1) * 0.5;
        // Bell curve: 0.6 at edges, 1.1 at center
        final widthFactor = 0.6 + 0.5 * math.sin(tMid * math.pi);
        final segW = lineW * widthFactor;

        Offset p0, p1;
        if (isStraightStyle) {
          // Straight: linear interpolation between endpoints
          p0 = Offset(
            srcPt.dx + (tgtPt.dx - srcPt.dx) * t0,
            srcPt.dy + (tgtPt.dy - srcPt.dy) * t0,
          );
          p1 = Offset(
            srcPt.dx + (tgtPt.dx - srcPt.dx) * t1,
            srcPt.dy + (tgtPt.dy - srcPt.dy) * t1,
          );
        } else {
          p0 = controller.pointOnQuadBezier(srcPt, cp, tgtPt, t0);
          p1 = controller.pointOnQuadBezier(srcPt, cp, tgtPt, t1);
        }

        // Gradient color at this segment position
        final segColor = Color.lerp(gradStart, gradEnd, tMid)!;
        // Blend with typeColor at center for vibrance
        final finalColor = Color.lerp(segColor, typeColor, (math.sin(tMid * math.pi) * 0.4))!;

        if (isContradiction) {
          // Zigzag: offset points perpendicular to the curve
          final tangent = Offset(p1.dx - p0.dx, p1.dy - p0.dy);
          final tLen = tangent.distance;
          if (tLen > 0.01) {
            final perpOff = Offset(-tangent.dy / tLen, tangent.dx / tLen);
            final zigzag = math.sin(tMid * math.pi * 6) * lineW * 0.8;
            p0 = Offset(p0.dx + perpOff.dx * zigzag, p0.dy + perpOff.dy * zigzag);
            p1 = Offset(p1.dx + perpOff.dx * zigzag, p1.dy + perpOff.dy * zigzag);
          }
        } else if (isZigzagStyle && !isContradiction) {
          // 🎨 ZIGZAG STYLE: stepped perpendicular offsets (8 zigs)
          final tangent = Offset(p1.dx - p0.dx, p1.dy - p0.dy);
          final tLen = tangent.distance;
          if (tLen > 0.01) {
            final perpOff = Offset(-tangent.dy / tLen, tangent.dx / tLen);
            final zigzag = math.sin(tMid * math.pi * 8) * lineW * 1.2;
            p0 = Offset(p0.dx + perpOff.dx * zigzag, p0.dy + perpOff.dy * zigzag);
            p1 = Offset(p1.dx + perpOff.dx * zigzag, p1.dy + perpOff.dy * zigzag);
          }
        }

        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHierarchy ? segW * 0.5 : segW
          ..strokeCap = isDashedStyle ? StrokeCap.butt : StrokeCap.round
          ..shader = null
          ..color = finalColor.withValues(alpha: lineAlpha * focusedFade);
        canvas.drawLine(p0, p1, _p);

        // Hierarchy: draw second parallel line
        if (isHierarchy) {
          final tangent = Offset(p1.dx - p0.dx, p1.dy - p0.dy);
          final tLen = tangent.distance;
          if (tLen > 0.01) {
            final perpOff = Offset(-tangent.dy / tLen, tangent.dx / tLen);
            final offset = lineW * 0.6;
            canvas.drawLine(
              Offset(p0.dx + perpOff.dx * offset, p0.dy + perpOff.dy * offset),
              Offset(p1.dx + perpOff.dx * offset, p1.dy + perpOff.dy * offset),
              _p,
            );
            canvas.drawLine(
              Offset(p0.dx - perpOff.dx * offset, p0.dy - perpOff.dy * offset),
              Offset(p1.dx - perpOff.dx * offset, p1.dy - perpOff.dy * offset),
              _p,
            );
          }
        }
      }

      // === Birth flash: propagating glow wavefront ===
      if (isBirthAnimating) {
        final flashPos = controller.pointOnQuadBezier(srcPt, cp, tgtPt, birthProgress);
        final flashSize = 15.0 * (1.0 - birthProgress) + 4.0;
        _softGlowPaint.color = Colors.white.withValues(alpha: (0.6 * (1.0 - birthProgress)) * focusedFade);
        canvas.drawCircle(flashPos, flashSize, _softGlowPaint);
      }

      // === 🔵 Endpoint dots — small, clean ===
      final dotRadius = lod == 2 ? 3.0 : 2.5;
      final dotAlpha = (0.55 + birthFlash * 0.3).clamp(0.0, 0.85) * focusedFade;
      _p
        ..style = PaintingStyle.fill
        ..shader = null
        ..maskFilter = null
        ..color = connColor.withValues(alpha: dotAlpha);
      canvas.drawCircle(srcPt, dotRadius, _p);
      if (!isBirthAnimating) {
        canvas.drawCircle(tgtPt, dotRadius, _p);

        // === 🏹 MIND-MAP ARROWHEAD — soft, organic triangle at target ===
        // Compute direction from curve tangent near endpoint (t=0.95→1.0)
        final nearEnd = controller.pointOnQuadBezier(srcPt, cp, tgtPt, 0.92);
        final dir = Offset(tgtPt.dx - nearEnd.dx, tgtPt.dy - nearEnd.dy);
        final len = dir.distance;
        if (len > 0.01) {
          final norm = Offset(dir.dx / len, dir.dy / len);
          final perp = Offset(-norm.dy, norm.dx);
          final arrowSize = (lod == 2 ? 8.0 : 6.0) * dissolveScale;
          final arrowWidth = arrowSize * 0.55;
          // Three vertices of the arrowhead triangle
          final tip = Offset(tgtPt.dx + norm.dx * 2, tgtPt.dy + norm.dy * 2);
          final wing1 = Offset(
            tgtPt.dx - norm.dx * arrowSize + perp.dx * arrowWidth,
            tgtPt.dy - norm.dy * arrowSize + perp.dy * arrowWidth,
          );
          final wing2 = Offset(
            tgtPt.dx - norm.dx * arrowSize - perp.dx * arrowWidth,
            tgtPt.dy - norm.dy * arrowSize - perp.dy * arrowWidth,
          );

          // Glow behind arrowhead
          _softGlowPaint.color = typeColor.withValues(alpha: 0.25 * effectiveFade);
          canvas.drawCircle(tgtPt, arrowSize * 0.8, _softGlowPaint);

          // Filled arrowhead
          final arrowPath = Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(wing1.dx, wing1.dy)
            ..quadraticBezierTo(
              tgtPt.dx - norm.dx * arrowSize * 0.3,
              tgtPt.dy - norm.dy * arrowSize * 0.3,
              wing2.dx, wing2.dy,
            )
            ..close();
          _p
            ..style = PaintingStyle.fill
            ..color = typeColor.withValues(alpha: lineAlpha * effectiveFade);
          canvas.drawPath(arrowPath, _p);
        }

        // ↔️ BIDIRECTIONAL: Mirror arrowhead at source point
        if (conn.isBidirectional) {
          final nearStart = controller.pointOnQuadBezier(srcPt, cp, tgtPt, 0.08);
          final dirB = Offset(srcPt.dx - nearStart.dx, srcPt.dy - nearStart.dy);
          final lenB = dirB.distance;
          if (lenB > 0.01) {
            final normB = Offset(dirB.dx / lenB, dirB.dy / lenB);
            final perpB = Offset(-normB.dy, normB.dx);
            final arrowSize = (lod == 2 ? 8.0 : 6.0) * dissolveScale;
            final arrowWidth = arrowSize * 0.55;
            final tipB = Offset(srcPt.dx + normB.dx * 2, srcPt.dy + normB.dy * 2);
            final wing1B = Offset(
              srcPt.dx - normB.dx * arrowSize + perpB.dx * arrowWidth,
              srcPt.dy - normB.dy * arrowSize + perpB.dy * arrowWidth,
            );
            final wing2B = Offset(
              srcPt.dx - normB.dx * arrowSize - perpB.dx * arrowWidth,
              srcPt.dy - normB.dy * arrowSize - perpB.dy * arrowWidth,
            );

            _softGlowPaint.color = typeColor.withValues(alpha: 0.25 * effectiveFade);
            canvas.drawCircle(srcPt, arrowSize * 0.8, _softGlowPaint);

            final arrowPathB = Path()
              ..moveTo(tipB.dx, tipB.dy)
              ..lineTo(wing1B.dx, wing1B.dy)
              ..quadraticBezierTo(
                srcPt.dx - normB.dx * arrowSize * 0.3,
                srcPt.dy - normB.dy * arrowSize * 0.3,
                wing2B.dx, wing2B.dy,
              )
              ..close();
            _p
              ..style = PaintingStyle.fill
              ..color = typeColor.withValues(alpha: lineAlpha * effectiveFade);
            canvas.drawPath(arrowPathB, _p);
          }
        }
      }

      // === ✨ Selected endpoint glow ===
      if (isSelected) {
        final pulseR = 6.0 + (math.sin(animationTime * 3.0) * 2.0);
        _softGlowPaint.color = connColor.withValues(alpha: 0.35 * effectiveFade);
        canvas.drawCircle(srcPt, pulseR, _softGlowPaint);
        canvas.drawCircle(tgtPt, pulseR, _softGlowPaint);
      }

      // === 🌟 Shimmers — flowing energy (enhanced for bidirectional) ===
      if (!isBirthAnimating) {
        final shimmerSize = lod == 2 ? 5.0 : 3.5;
        // Forward shimmer
        final shimmerT1 = ((animationTime * 0.25 + connIndex * 0.3) % 1.0);
        final shimmerPos1 = controller.pointOnQuadBezier(srcPt, cp, tgtPt, shimmerT1);
        _softGlowPaint.color = Colors.white.withValues(alpha: 0.45 * effectiveFade);
        canvas.drawCircle(shimmerPos1, shimmerSize * 0.4, _softGlowPaint);
        _softGlowPaint.color = typeColor.withValues(alpha: 0.25 * effectiveFade);
        canvas.drawCircle(shimmerPos1, shimmerSize, _softGlowPaint);
        // Reverse shimmer (stronger for bidirectional connections)
        final reverseAlpha = conn.isBidirectional ? 0.50 : 0.30;
        final reverseSize = conn.isBidirectional ? 1.0 : 0.9;
        final shimmerT2 = ((1.0 - (animationTime * 0.20 + connIndex * 0.5)) % 1.0).abs();
        final shimmerPos2 = controller.pointOnQuadBezier(srcPt, cp, tgtPt, shimmerT2);
        _softGlowPaint.color = Colors.white.withValues(alpha: reverseAlpha * effectiveFade);
        canvas.drawCircle(shimmerPos2, shimmerSize * 0.35, _softGlowPaint);
        _softGlowPaint.color = typeColor.withValues(alpha: 0.22 * effectiveFade);
        canvas.drawCircle(shimmerPos2, shimmerSize * reverseSize, _softGlowPaint);
        // Bidirectional: third counter-flow particle for richer effect
        if (conn.isBidirectional) {
          final shimmerT3 = ((1.0 - (animationTime * 0.30 + connIndex * 0.7)) % 1.0).abs();
          final shimmerPos3 = controller.pointOnQuadBezier(srcPt, cp, tgtPt, shimmerT3);
          _softGlowPaint.color = Colors.white.withValues(alpha: 0.35 * effectiveFade);
          canvas.drawCircle(shimmerPos3, shimmerSize * 0.3, _softGlowPaint);
        }
      }

      // =================================================================
      // 🌉 CROSS-ZONE BRIDGE ENHANCEMENTS (Passo 9, P9-05/12)
      // =================================================================
      //
      // 2026-05-17: golden shimmer particles removed. Pedagogically they
      // were meant to signal "ponti cross-dominio = autostrade", but
      // without context users read them as random "stelline che si
      // muovono". A one-shot coachmark could have explained — but the
      // simpler call is to drop the visual entirely. Cross-zone bridges
      // are still distinguishable via stroke thickness (3× at dezoom,
      // see crossZoneBonus in _paintConnections lineW), color (gold via
      // KnowledgeConnection.crossZoneColor), and the discovery icon
      // (💡 / 🤖) below.
      if (conn.isCrossZone && !conn.isGhost && !isBirthAnimating) {
        // --- Discovery Icon: 💡 (student) or 🤖 (AI suggested) (P9-12) ---
        // Painted at t=0.35 along the curve (offset from midpoint label)
        final iconT = 0.35;
        final iconPos = controller.pointOnQuadBezier(srcPt, cp, tgtPt, iconT);
        final iconText = conn.discoveredBy == BridgeDiscoveryOrigin.aiSuggested
            ? '🤖'
            : '💡';
        final iconKey = '${conn.id}_bridgeIcon_$iconText';
        final iconPainter = _cachedTitlePainters.putIfAbsent(iconKey, () {
          final tp = TextPainter(
            text: TextSpan(
              text: iconText,
              style: TextStyle(fontSize: lod == 2 ? 14.0 : 10.0),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          // Auto-prune cache
          if (_cachedTitlePainters.length > 100) {
            _cachedTitlePainters.remove(_cachedTitlePainters.keys.first);
          }
          return tp;
        });
        // Background pill for icon
        final iconRect = Rect.fromCenter(
          center: iconPos,
          width: iconPainter.width + 8,
          height: iconPainter.height + 6,
        );
        _p
          ..style = PaintingStyle.fill
          ..shader = null
          ..maskFilter = null
          ..color = const Color(0xDD1A1A2E);
        canvas.drawRRect(
          RRect.fromRectAndRadius(iconRect, const Radius.circular(6)),
          _p,
        );
        iconPainter.paint(
          canvas,
          Offset(
            iconPos.dx - iconPainter.width / 2,
            iconPos.dy - iconPainter.height / 2,
          ),
        );

        // --- Bridge Type Badge (A/B/C pill at t=0.65) ---
        if (conn.bridgeType != null) {
          final badgeT = 0.65;
          final badgePos = controller.pointOnQuadBezier(srcPt, cp, tgtPt, badgeT);
          final badgeLabel = switch (conn.bridgeType!) {
            CrossZoneBridgeType.analogyStructural => 'A',
            CrossZoneBridgeType.sharedMechanism => 'B',
            CrossZoneBridgeType.complementaryPerspective => 'C',
          };
          final badgeKey = '${conn.id}_bridgeBadge_$badgeLabel';
          final badgePainter = _cachedTitlePainters.putIfAbsent(badgeKey, () {
            final tp = TextPainter(
              text: TextSpan(
                text: badgeLabel,
                style: TextStyle(
                  fontSize: lod == 2 ? 11.0 : 9.0,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            if (_cachedTitlePainters.length > 100) {
              _cachedTitlePainters.remove(_cachedTitlePainters.keys.first);
            }
            return tp;
          });
          final badgeRect = Rect.fromCenter(
            center: badgePos,
            width: badgePainter.width + 10,
            height: badgePainter.height + 6,
          );
          // Golden pill background
          _p
            ..style = PaintingStyle.fill
            ..color = const Color(0xFFFFD700).withValues(alpha: 0.90 * effectiveFade);
          canvas.drawRRect(
            RRect.fromRectAndRadius(badgeRect, const Radius.circular(5)),
            _p,
          );
          badgePainter.paint(
            canvas,
            Offset(
              badgePos.dx - badgePainter.width / 2,
              badgePos.dy - badgePainter.height / 2,
            ),
          );
        }
      }

      // === ✕ CONTRADICTION MARKER — Red X at midpoint ===
      if (conn.connectionType == ConnectionType.contradiction && !isBirthAnimating) {
        final midPt = controller.pointOnQuadBezier(srcPt, cp, tgtPt, 0.5);
        final xSize = lineW * 1.5;
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = lineW * 0.6
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFEF5350).withValues(alpha: 0.85 * effectiveFade);
        canvas.drawLine(
          Offset(midPt.dx - xSize, midPt.dy - xSize),
          Offset(midPt.dx + xSize, midPt.dy + xSize),
          _p,
        );
        canvas.drawLine(
          Offset(midPt.dx + xSize, midPt.dy - xSize),
          Offset(midPt.dx - xSize, midPt.dy + xSize),
          _p,
        );
        // Red glow behind X
        _softGlowPaint.color = const Color(0xFFEF5350).withValues(alpha: 0.25 * effectiveFade);
        canvas.drawCircle(midPt, xSize * 1.5, _softGlowPaint);
      }

      // === 🔦 PATH TRACE WAVEFRONT ===
      if (traceFlash > 0.0) {
        // Propagating bright flash along the connection
        final traceT = (1.0 - traceFlash).clamp(0.0, 1.0);
        final tracePt = controller.pointOnQuadBezier(srcPt, cp, tgtPt, traceT);
        final traceSize = 12.0 * traceFlash + 4.0;
        _softGlowPaint.color = Colors.white.withValues(alpha: 0.7 * traceFlash * effectiveFade);
        canvas.drawCircle(tracePt, traceSize * 0.5, _softGlowPaint);
        _softGlowPaint.color = typeColor.withValues(alpha: 0.4 * traceFlash * effectiveFade);
        canvas.drawCircle(tracePt, traceSize, _softGlowPaint);
      }

      // === 🏷️ Label pill at midpoint (auto-scaled at LOD 2) ===
      if (conn.label != null && conn.label!.isNotEmpty) {
        final midPt = controller.pointOnQuadBezier(srcPt, cp, tgtPt, 0.5);
        if (lod == 2) {
          // Only the canonical connection in each label-group renders the
          // pill — others are suppressed to avoid hub-cluster pill spam.
          final key = conn.label!.trim().toLowerCase();
          final canonical = labelGroupCanonical[key];
          if (canonical == conn.id) {
            final count = labelGroupCount[key] ?? 1;
            final displayLabel = count > 1
                ? '${conn.label!} ×$count'
                : conn.label!;
            _paintAutoScaledLabelPill(
              canvas, midPt, displayLabel, typeColor, fade);
          }
        } else {
          _paintLabelPill(canvas, midPt, conn.label!, typeColor, fade);
        }
      }

      // 2026-05-17: LOD 2 "Flowing particles with trail" rimosso — user
      // segnalava "stelline gialle che si muovono" come distrazione
      // senza significato chiaro per l'utente. Connection sono ancora
      // chiaramente visibili a LOD 2 via stroke, label pill, e icona.
      connIndex++;
    }
  }

  // 2026-05-17: _paintParticlesWithTrail rimosso integralmente — i
  // particle "comet-style" lungo le connection a LOD 2 venivano
  // percepiti come "stelline gialle che si muovono" senza significato.

  // ===========================================================================
  // PHASE 4B: SUGGESTED CONNECTIONS — Animated ghost hint
  // ===========================================================================

  void _paintSuggestions(Canvas canvas, int lod, double fade) {
    final suggestions = controller.suggestions;
    if (suggestions.isEmpty) return;

    final cMap = _buildClusterMap();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 🎯 SCALABILITY: Visual budget + crossing prevention
    const maxVisible = 3; // Never render more than 3 suggestions
    int rendered = 0;
    final usedClusterIds = <String>{}; // Prevent arc crossing
    final glowedClusterIds = <String>{}; // Glow dedup
    final labelMidpoints = <Offset>[]; // Label overlap avoidance

    // ✨ STAGGERED REVEAL: Find the earliest surfacedAt as the reference
    int earliestMs = nowMs;
    for (final s in suggestions) {
      if (s.surfacedAtMs < earliestMs) earliestMs = s.surfacedAtMs;
    }

    int revealIndex = 0;
    for (final active in suggestions) {
      if (rendered >= maxVisible) break;

      final src = cMap[active.sourceClusterId];
      final tgt = cMap[active.targetClusterId];
      if (src == null || tgt == null) continue;

      // 🚫 CROSSING PREVENTION: Skip if a cluster is already used
      // by another rendered suggestion (arcs from same point = confusing)
      if (usedClusterIds.contains(active.sourceClusterId) ||
          usedClusterIds.contains(active.targetClusterId)) {
        continue;
      }

      // ✨ STAGGERED: Override surfacedAt so each ghost appears 400ms apart
      const staggerDelayMs = 400;
      final staggeredSurfacedAt = earliestMs + (revealIndex * staggerDelayMs);
      if (nowMs < staggeredSurfacedAt) {
        revealIndex++;
        continue; // This ghost hasn't "arrived" yet
      }
      // Temporarily adjust timing for this ghost's entrance animation
      final originalSurfacedAt = active.surfacedAtMs;
      active.surfacedAtMs = staggeredSurfacedAt;

      final isPrimary = rendered == 0;
      final opacityMul = isPrimary ? 1.0 : 0.5;

      _paintSingleSuggestion(
        canvas, lod, fade, active, src, tgt, nowMs, opacityMul,
        glowedClusterIds, labelMidpoints,
      );

      // Restore original surfacedAt (don't mutate permanently)
      active.surfacedAtMs = originalSurfacedAt;

      usedClusterIds.add(active.sourceClusterId);
      usedClusterIds.add(active.targetClusterId);
      rendered++;
      revealIndex++;
    }
  }

  /// Paint a single suggestion arc + dot + particles + label.
  void _paintSingleSuggestion(
    Canvas canvas, int lod, double fade,
    SuggestedConnection active,
    ContentCluster src, ContentCluster tgt,
    int nowMs, double opacityMul,
    Set<String> glowedClusterIds,
    List<Offset> labelMidpoints,
  ) {
    final srcPt = src.centroid;
    final tgtPt = tgt.centroid;
    final midPt = Offset(
      (srcPt.dx + tgtPt.dx) / 2,
      (srcPt.dy + tgtPt.dy) / 2,
    );

    // === Timing ===
    final ageSec = (nowMs - active.surfacedAtMs) / 1000.0;
    if (ageSec > 60) {
      active.dismissed = true;
      return;
    }
    final decayFactor = ageSec < 30.0
        ? 1.0
        : (1.0 - ((ageSec - 30.0) / 30.0)).clamp(0.0, 1.0);

    // ✨ ENTRANCE ANIMATION: Scale + fade over 600ms with elastic overshoot
    const entranceDuration = 0.6; // seconds
    final entranceT = (ageSec / entranceDuration).clamp(0.0, 1.0);
    // Smoothstep with 1.15x overshoot for premium bounce
    final entranceEase = entranceT < 1.0
        ? _elasticOut(entranceT)
        : 1.0;
    final entranceFade = (entranceT * 2.0).clamp(0.0, 1.0); // fade in faster

    if (entranceEase < 0.01) return; // Not visible yet

    final blendColor = Color.lerp(
      _clusterColor(src), _clusterColor(tgt), 0.5,
    ) ?? _clusterColor(src);

    // 📊 SCORE-BASED WEIGHT: Stronger suggestions appear more prominent
    final score = active.score.clamp(0.0, 1.0);
    final scoreWeight = 0.4 + score * 0.6; // 0.4–1.0 multiplier

    // Breathing pulsation
    final breath = math.sin(animationTime * 1.2) * 0.5 + 0.5;

    // 🧲 MAGNETIC PULSE: Ghost pulses when finger is near midpoint
    double magneticBoost = 1.0;
    if (dragCurrentPoint != null) {
      final fingerDist = (dragCurrentPoint! - midPt).distance;
      if (fingerDist < 80.0) {
        // Proximity factor: 1.0 at midpoint, 0.0 at 80px
        final proximity = (1.0 - fingerDist / 80.0).clamp(0.0, 1.0);
        // Pulse amplitude increases with proximity
        final magneticPulse = math.sin(animationTime * 4.0) * 0.3 + 0.7;
        magneticBoost = 1.0 + proximity * 0.6 * magneticPulse;
      }
    }

    // LOD 0 visibility boost
    final visBoost = lod == 0 ? 4.0 : 1.0;

    // === 🌟 CLUSTER HIGHLIGHT GLOW (deduped — each cluster glows only once) ===
    if (opacityMul >= 1.0) {
      final glowAlpha = (0.08 + breath * 0.06) * fade * decayFactor
          * entranceFade * scoreWeight;
      final glowRadius = lod == 0 ? 25.0 : 15.0;
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0)
        ..color = blendColor.withValues(alpha: glowAlpha);
      if (glowedClusterIds.add(active.sourceClusterId)) {
        canvas.drawCircle(
          srcPt, _clusterRadius(src) + glowRadius * entranceEase, _p,
        );
      }
      if (glowedClusterIds.add(active.targetClusterId)) {
        canvas.drawCircle(
          tgtPt, _clusterRadius(tgt) + glowRadius * entranceEase, _p,
        );
      }
      _p.maskFilter = null;
    }

    // === 🌈 GRADIENT ARC: Color flows from source → target ===
    final dx = tgtPt.dx - srcPt.dx;
    final dy = tgtPt.dy - srcPt.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) return;

    final perpX = -dy * 0.15;
    final perpY = dx * 0.15;
    final cp = Offset(midPt.dx + perpX, midPt.dy + perpY);

    final arcAlpha = ((0.03 + breath * 0.02) * fade * decayFactor * visBoost
        * entranceFade * opacityMul * scoreWeight * magneticBoost)
        .clamp(0.0, 0.45);

    final srcColor = _clusterColor(src);
    final tgtColor = _clusterColor(tgt);

    // 📊 SCORE-BASED STROKE WIDTH: 0.5px (weak) → 2.5px (strong)
    final baseStroke = lod == 0
        ? (0.8 + score * 1.7) * magneticBoost
        : (0.4 + score * 1.0) * magneticBoost;

    // ⚡ ADAPTIVE ARC STEPS: fewer segments for low-score ghosts
    final arcSteps = score > 0.6 ? 24 : (score > 0.4 ? 16 : 12);
    final maxStep = entranceT < 1.0
        ? (arcSteps * entranceEase.clamp(0.0, 1.0)).round()
        : arcSteps;
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseStroke
      ..strokeCap = StrokeCap.round
      ..shader = null
      ..maskFilter = null;

    // 📊 High-score PRIMARY ghosts get a soft blur glow underneath
    // ⚡ OPT: Skip glow pass for secondary ghosts (opacityMul < 1.0)
    if (score > 0.65 && opacityMul >= 1.0) {
      _p.maskFilter = MaskFilter.blur(BlurStyle.normal, 2.0 + score * 2.0);
      for (int i = 0; i < maxStep; i++) {
        final t0 = i / arcSteps;
        final t1 = (i + 1) / arcSteps;
        final segColor = Color.lerp(srcColor, tgtColor, (t0 + t1) / 2)!;
        _p.color = segColor.withValues(alpha: arcAlpha * 0.4);
        final p0 = _quadBezierPt(srcPt, cp, tgtPt, t0);
        final p1 = _quadBezierPt(srcPt, cp, tgtPt, t1);
        canvas.drawLine(p0, p1, _p);
      }
      _p.maskFilter = null;
    }

    // Main arc segments
    for (int i = 0; i < maxStep; i++) {
      final t0 = i / arcSteps;
      final t1 = (i + 1) / arcSteps;
      final segColor = Color.lerp(srcColor, tgtColor, (t0 + t1) / 2)!;
      _p.color = segColor.withValues(alpha: arcAlpha);
      final p0 = _quadBezierPt(srcPt, cp, tgtPt, t0);
      final p1 = _quadBezierPt(srcPt, cp, tgtPt, t1);
      canvas.drawLine(p0, p1, _p);
    }

    // === ✨ FLOWING PARTICLES along the arc ===
    if (entranceT >= 1.0) {
      const particleCount = 4;
      final particleAlpha = (0.25 * fade * decayFactor * visBoost * opacityMul).clamp(0.0, 0.5);
      for (int i = 0; i < particleCount; i++) {
        // Each particle at a different phase, wrapping around
        final phase = (animationTime * 0.4 + i / particleCount) % 1.0;
        final pt = _quadBezierPt(srcPt, cp, tgtPt, phase);
        final pColor = Color.lerp(srcColor, tgtColor, phase)!;
        // Radial fade: large soft glow + small bright core
        _softGlowPaint.color = pColor.withValues(alpha: particleAlpha * 0.4);
        canvas.drawCircle(pt, 3.0, _softGlowPaint);
        _p
          ..style = PaintingStyle.fill
          ..color = pColor.withValues(alpha: particleAlpha);
        canvas.drawCircle(pt, 1.2, _p);
      }
    }

    // === '+' dot at midpoint (scales with entrance + magnetic pulse) ===
    final baseRadius = (6.0 + score * 3.0) * (lod == 0 ? 1.8 : 1.0)
        * magneticBoost;
    final dotRadius = baseRadius * entranceEase;
    final dotAlpha = ((0.15 + breath * 0.08) * fade * decayFactor * visBoost
        * entranceFade * opacityMul * magneticBoost).clamp(0.0, 0.85);

    if (dotRadius < 0.5) return;

    // Soft glow
    _softGlowPaint.color = blendColor.withValues(alpha: dotAlpha * 0.3);
    canvas.drawCircle(midPt, dotRadius * 1.5, _softGlowPaint);

    // Dot fill
    _p
      ..style = PaintingStyle.fill
      ..color = blendColor.withValues(alpha: dotAlpha * 0.6);
    canvas.drawCircle(midPt, dotRadius, _p);

    // === 📊 SCORE RING: Confidence arc around "+" ===
    final ringRadius = dotRadius + 3.0;
    final sweepAngle = score * 2 * math.pi; // 0→360° based on score
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = blendColor.withValues(alpha: (dotAlpha * 1.2).clamp(0.0, 0.8));
    // Background ring (dim)
    _p.color = Colors.white.withValues(alpha: dotAlpha * 0.15);
    canvas.drawCircle(midPt, ringRadius, _p);
    // Score arc (bright)
    _reusePath.reset();
    _reusePath.addArc(
      Rect.fromCircle(center: midPt, radius: ringRadius),
      -math.pi / 2, // start from top
      sweepAngle,
    );
    _p.color = blendColor.withValues(alpha: (dotAlpha * 1.3).clamp(0.0, 0.9));
    canvas.drawPath(_reusePath, _p);

    // Dot border
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: dotAlpha * 0.9);
    canvas.drawCircle(midPt, dotRadius, _p);

    // '+' icon
    final iconSize = dotRadius * 0.5;
    _p
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: (dotAlpha * 1.5).clamp(0.0, 0.8));
    canvas.drawLine(
      Offset(midPt.dx - iconSize, midPt.dy),
      Offset(midPt.dx + iconSize, midPt.dy),
      _p,
    );
    canvas.drawLine(
      Offset(midPt.dx, midPt.dy - iconSize),
      Offset(midPt.dx, midPt.dy + iconSize),
      _p,
    );

    // === Reason label (fades in after entrance, skips if overlapping) ===
    if (entranceT > 0.7) {
      // 📏 OVERLAP AVOIDANCE: Skip label if midpoint is too close to existing
      bool tooClose = false;
      for (final existingMid in labelMidpoints) {
        if ((existingMid - midPt).distance < 40.0) {
          tooClose = true;
          break;
        }
      }
      if (!tooClose) {
        labelMidpoints.add(midPt);
        final labelFade = ((entranceT - 0.7) / 0.3).clamp(0.0, 1.0);
        final labelFontSize = lod == 0 ? 10.0 : 8.0;
        final tp = TextPainter(
          text: TextSpan(
            text: active.reason,
            style: TextStyle(
              color: blendColor.withValues(
                alpha: (0.35 * fade * decayFactor * visBoost * labelFade
                    * opacityMul).clamp(0.0, 0.6),
              ),
              fontSize: labelFontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(midPt.dx - tp.width / 2, midPt.dy + dotRadius + 3),
        );
      }
    }
  }

  /// Elastic ease-out curve: overshoots to ~1.15 then settles to 1.0
  static double _elasticOut(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    // Simple overshoot: cubic ease-out with peak at ~1.15
    final s = 1.0 - t;
    return 1.0 - s * s * s + (math.sin(t * math.pi) * 0.15 * (1.0 - t));
  }

  /// Helper: approximate cluster visual radius from bounds
  double _clusterRadius(ContentCluster cluster) {
    final w = cluster.bounds.width;
    final h = cluster.bounds.height;
    return math.sqrt(w * w + h * h) * 0.5;
  }

  /// Helper: compute point on quadratic Bézier at t ∈ [0,1]
  static Offset _quadBezierPt(Offset p0, Offset cp, Offset p1, double t) {
    final u = 1.0 - t;
    return Offset(
      u * u * p0.dx + 2 * u * t * cp.dx + t * t * p1.dx,
      u * u * p0.dy + 2 * u * t * cp.dy + t * t * p1.dy,
    );
  }

  // ===========================================================================
  // CLUSTER BUBBLES — Glassmorphic bubbles with text (LOD 1)
  // ===========================================================================

  void _paintClusterBubbles(Canvas canvas, double fade) {
    if (clusters.isEmpty) return;

    // ✨ LOD CROSSFADE: Smooth bubble appearance at LOD 0→1 boundary
    final bubbleFade = fade * _computeLod1Fade();

    // Only show bubbles for clusters that have connections
    final connectedIds = <String>{};
    for (final conn in controller.connections) {
      connectedIds.add(conn.sourceClusterId);
      connectedIds.add(conn.targetClusterId);
    }
    // Also include active drag clusters
    if (dragSourceClusterId != null) connectedIds.add(dragSourceClusterId!);
    if (snapTargetClusterId != null) connectedIds.add(snapTargetClusterId!);

    for (final cluster in clusters) {
      if (!connectedIds.contains(cluster.id)) continue;
      if (cluster.bounds.isEmpty || cluster.bounds.width < 2) continue;

      final color = _clusterColor(cluster);
      final bounds = cluster.bounds.inflate(_bubblePadding * 0.5);
      final rrect = RRect.fromRectAndRadius(
        bounds, const Radius.circular(_bubbleCornerRadius),
      );

      // 1. Drop shadow
      _shadowPaint.color = Colors.black.withValues(alpha: 0.15 * bubbleFade);
      canvas.drawRRect(rrect.shift(const Offset(1, 2)), _shadowPaint);

      // 2. Glassmorphism fill — gradient from top-left light to bottom-right dark
      final fillGradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color.withValues(alpha: 0.08 * bubbleFade),
          color.withValues(alpha: 0.03 * bubbleFade),
        ],
      );
      _p
        ..style = PaintingStyle.fill
        ..shader = fillGradient.createShader(bounds)
        ..maskFilter = null;
      canvas.drawRRect(rrect, _p);
      _p.shader = null;

      // 3. Inner highlight — 1px white at top for glass refraction
      final highlightRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(bounds.left + 4, bounds.top, bounds.width - 8, 1.0),
        const Radius.circular(0.5),
      );
      _p
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.12 * bubbleFade);
      canvas.drawRRect(highlightRect, _p);

      // 4. Luminous border
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = color.withValues(alpha: 0.25 * bubbleFade);
      canvas.drawRRect(rrect, _p);

      // 5. 🖼️ Mini-thumbnail preview inside bubble (if available)
      final thumb = thumbnails[cluster.id];
      if (thumb != null) {
        canvas.save();
        canvas.clipRRect(rrect);
        final inner = bounds.deflate(_bubblePadding * 0.3);
        final thumbAspect = thumb.width / thumb.height;
        final innerAspect = inner.width / inner.height;
        Rect dst;
        if (thumbAspect > innerAspect) {
          final h = inner.width / thumbAspect;
          dst = Rect.fromCenter(center: inner.center, width: inner.width, height: h);
        } else {
          final w = inner.height * thumbAspect;
          dst = Rect.fromCenter(center: inner.center, width: w, height: inner.height);
        }
        _p
          ..style = PaintingStyle.fill
          ..shader = null
          ..color = Color.fromRGBO(255, 255, 255, 0.45 * bubbleFade)
          ..filterQuality = FilterQuality.low;
        canvas.drawImageRect(
          thumb,
          Rect.fromLTWH(0, 0, thumb.width.toDouble(), thumb.height.toDouble()),
          dst,
          _p,
        );
        canvas.restore();
      }

      // 6. Recognized text label below bubble
      final text = clusterTexts[cluster.id];
      if (text != null && text.isNotEmpty) {
        final displayText = text.length > 20 ? '${text.substring(0, 18)}…' : text;
        final tp = TextPainter(
          text: TextSpan(
            text: displayText,
            style: TextStyle(
              color: Color.lerp(color, Colors.white, 0.6)!.withValues(alpha: 0.55 * bubbleFade),
              fontSize: 8.0,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(bounds.center.dx - tp.width / 2, bounds.bottom + 3),
        );
      }

      // 7. 🌟 CLUSTER GLOW ON CONNECTION SELECTION — pulse when a connected edge is selected
      if (selectedConnectionId != null) {
        final selConn = controller.connections
            .where((c) => c.id == selectedConnectionId).firstOrNull;
        if (selConn != null &&
            (selConn.sourceClusterId == cluster.id || selConn.targetClusterId == cluster.id)) {
          final selColor = selConn.color;
          final pulse = (math.sin(animationTime * 3.0) * 0.15 + 0.35) * bubbleFade;
          _softGlowPaint.color = selColor.withValues(alpha: pulse);
          canvas.drawRRect(rrect.inflate(4), _softGlowPaint);
          _softGlowPaint.color = selColor.withValues(alpha: pulse * 0.5);
          canvas.drawRRect(rrect.inflate(8), _softGlowPaint);
        }
      }

      // 8. 🔗 GRAPH HIGHLIGHT — dim glow for 2-hop connected clusters
      if (selectedConnectionId != null) {
        final selConn = controller.connections
            .where((c) => c.id == selectedConnectionId).firstOrNull;
        if (selConn != null) {
          final graphIds = controller.getConnectedGraph(
            selConn.sourceClusterId, maxHops: 2);
          graphIds.addAll(controller.getConnectedGraph(
            selConn.targetClusterId, maxHops: 2));
          if (graphIds.contains(cluster.id) &&
              selConn.sourceClusterId != cluster.id &&
              selConn.targetClusterId != cluster.id) {
            _softGlowPaint.color = color.withValues(alpha: 0.15 * bubbleFade);
            canvas.drawRRect(rrect.inflate(3), _softGlowPaint);
          }
        }
      }

      // 9. 📊 CONNECTION STATS BADGE — "↗N ↙M" at top-right of bubble
      final stats = controller.connectionStatsForCluster(cluster.id);
      if (stats.outgoing + stats.incoming > 0) {
        final statText = '↗${stats.outgoing} ↙${stats.incoming}';
        final statTp = TextPainter(
          text: TextSpan(
            text: statText,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5 * bubbleFade),
              fontSize: 6.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // Draw tiny pill background
        final badgeRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            bounds.right - statTp.width - 6,
            bounds.top - 4,
            statTp.width + 4,
            statTp.height + 2,
          ),
          const Radius.circular(4),
        );
        _p
          ..style = PaintingStyle.fill
          ..color = const Color(0xCC0D0D14);
        canvas.drawRRect(badgeRect, _p);
        statTp.paint(
          canvas,
          Offset(bounds.right - statTp.width - 4, bounds.top - 3),
        );
      }
    }
  }

  // ===========================================================================
  // CLUSTER DOTS — Luminous pulsing dots (LOD 2 satellite view)
  // ===========================================================================

  /// FX4 — sub-percettivo halo on hub clusters at Tier 0 (scale ≥ 0.45).
  ///
  /// Pedagogically anticipates the existence of the cluster system before
  /// the user zooms out enough to trigger the morph. Hub = `connCount ≥ 3`
  /// (same threshold MonumentResolver uses for star-burst eligibility).
  /// Cluster non-hub: silenziati per evitare rumore visivo durante il
  /// disegno attivo. Alpha intentionally low (0.18 × fade) — invito
  /// soft, non distrazione. Hub-only e blur largo per non interferire
  /// con i tratti sottostanti.
  void _paintHubHalosTier0(Canvas canvas, double fade) {
    if (clusters.isEmpty) return;
    if (controller.connections.isEmpty) return;

    // Count incidence per cluster (degree).
    final connCounts = <String, int>{};
    for (final conn in controller.connections) {
      connCounts[conn.sourceClusterId] =
          (connCounts[conn.sourceClusterId] ?? 0) + 1;
      connCounts[conn.targetClusterId] =
          (connCounts[conn.targetClusterId] ?? 0) + 1;
    }

    _softGlowPaint.maskFilter =
        const MaskFilter.blur(BlurStyle.normal, 30.0);
    for (final cluster in clusters) {
      final cc = connCounts[cluster.id] ?? 0;
      if (cc < 3) continue; // hub-only
      final bounds = cluster.bounds;
      if (bounds.isEmpty || !bounds.isFinite) continue;
      final color = _clusterColor(cluster);
      // Radius scales mildly with degree so super-hubs (5+) read slightly
      // bigger but stay subtle.
      final hubBoost = (1.0 + (cc - 3) * 0.10).clamp(1.0, 1.5);
      final radius = bounds.longestSide * 0.55 * hubBoost;
      _softGlowPaint.color = color.withValues(alpha: 0.18 * fade);
      canvas.drawCircle(bounds.center, radius, _softGlowPaint);
    }
    _softGlowPaint.maskFilter = null;
  }

  void _paintClusterDots(Canvas canvas, double fade) {
    if (clusters.isEmpty) return;

    // Collect connected clusters and count connections per cluster
    final connectedIds = <String>{};
    final connCounts = <String, int>{};
    for (final conn in controller.connections) {
      connectedIds.add(conn.sourceClusterId);
      connectedIds.add(conn.targetClusterId);
      connCounts[conn.sourceClusterId] = (connCounts[conn.sourceClusterId] ?? 0) + 1;
      connCounts[conn.targetClusterId] = (connCounts[conn.targetClusterId] ?? 0) + 1;
    }

    for (final cluster in clusters) {
      final color = _clusterColor(cluster);
      final center = cluster.centroid;
      final isConnected = connectedIds.contains(cluster.id);

      // Base radius proportional to cluster size
      final baseRadius = _clusterRadius(cluster).clamp(8.0, 25.0);

      // Network pulse: synchronized wave across all clusters every ~5s
      final wavePulse = math.sin(
        animationTime * 1.2 + center.dx * 0.002 + center.dy * 0.002,
      ) * 0.5 + 0.5;

      // Connected clusters pulse brighter
      final alpha = isConnected
          ? (0.30 + wavePulse * 0.15) * fade
          : (0.10 + wavePulse * 0.05) * fade;

      // Outer glow — atmospheric halo
      _softGlowPaint.color = color.withValues(alpha: alpha * 0.5);
      canvas.drawCircle(center, baseRadius * 1.8, _softGlowPaint);

      // Inner glow — concentrated light
      _glowPaint.color = color.withValues(alpha: alpha * 0.8);
      canvas.drawCircle(center, baseRadius * 0.8, _glowPaint);

      // Core dot — bright center
      _p
        ..style = PaintingStyle.fill
        ..shader = null
        ..maskFilter = null
        ..color = color.withValues(alpha: (alpha * 1.5).clamp(0.0, 0.85));
      canvas.drawCircle(center, baseRadius * 0.35, _p);

      // White sparkle at center of connected dots
      if (isConnected) {
        _p.color = Colors.white.withValues(alpha: alpha * 0.6);
        canvas.drawCircle(center, baseRadius * 0.12, _p);
      }

      // ✨ HUB STAR BURST: Clusters with 3+ connections get rotating radial rays
      final clusterConnCount = connCounts[cluster.id] ?? 0;
      if (clusterConnCount >= 3) {
        final rayCount = math.min(clusterConnCount * 2, 12);
        final rayLength = baseRadius * (1.2 + clusterConnCount * 0.15).clamp(1.2, 2.5);
        // Slow rotation animated
        final rotationOffset = animationTime * 0.3 + cluster.id.hashCode * 0.1;
        final rayAlpha = alpha * 0.4;

        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5)
          ..color = color.withValues(alpha: rayAlpha);

        for (int r = 0; r < rayCount; r++) {
          final angle = (r / rayCount) * math.pi * 2 + rotationOffset;
          final innerR = baseRadius * 0.5;
          final outerR = rayLength;
          final p1 = Offset(
            center.dx + math.cos(angle) * innerR,
            center.dy + math.sin(angle) * innerR,
          );
          final p2 = Offset(
            center.dx + math.cos(angle) * outerR,
            center.dy + math.sin(angle) * outerR,
          );
          canvas.drawLine(p1, p2, _p);
        }
        _p.maskFilter = null;
      }

      // 🔤 Auto-scaled text label under dot (recognized text)
      //
      // 🧠 Active Recall protection: skip the sublabel for clusters
      // currently concealed by SRS blur or Fog of War. Otherwise the
      // student would see "Glicolisi..." beneath a blurred cluster and
      // bypass the retrieval exercise (§2 teoria). Parallels the
      // monument-pill suppression above.
      final text =
          hiddenForRecallClusterIds.contains(cluster.id)
              ? null
              : clusterTexts[cluster.id];
      if (text != null && text.isNotEmpty) {
        final inverseScale = (1.0 / canvasScale).clamp(2.0, 8.0);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.scale(inverseScale * 0.3);
        canvas.translate(-center.dx, -center.dy);

        final displayText = text.length > 15 ? '${text.substring(0, 13)}…' : text;
        final tp = TextPainter(
          text: TextSpan(
            text: displayText,
            style: TextStyle(
              color: Color.lerp(color, Colors.white, 0.5)!.withValues(
                alpha: (isConnected ? 0.70 : 0.40) * fade,
              ),
              fontSize: 10.0,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(center.dx - tp.width / 2, center.dy + baseRadius * 0.5 + 4),
        );
        canvas.restore();
      }
    }
  }

  // ===========================================================================
  // CLUSTER GROUP HALOS — Shared glow for nearby clusters (LOD 2)
  // ===========================================================================

  void _paintClusterGroupHalos(Canvas canvas, double fade) {
    if (clusters.length < 2) return;

    // Find groups of nearby clusters (within 300px) using simple proximity
    // Cap at 6 halos for performance
    final used = <int>{};
    var drawnHalos = 0;

    for (int i = 0; i < clusters.length && drawnHalos < 6; i++) {
      if (used.contains(i)) continue;
      final group = <ContentCluster>[clusters[i]];
      used.add(i);

      for (int j = i + 1; j < clusters.length; j++) {
        if (used.contains(j)) continue;
        // Check distance to any cluster already in group
        for (final member in group) {
          final dist = (clusters[j].centroid - member.centroid).distance;
          if (dist < 300) {
            group.add(clusters[j]);
            used.add(j);
            break;
          }
        }
      }

      if (group.length < 2) continue; // No halo for single clusters

      // Compute bounding rect of the group
      var minX = double.infinity, minY = double.infinity;
      var maxX = -double.infinity, maxY = -double.infinity;
      Color blendColor = _clusterColor(group.first);
      for (final c in group) {
        final b = c.bounds;
        if (b.left < minX) minX = b.left;
        if (b.top < minY) minY = b.top;
        if (b.right > maxX) maxX = b.right;
        if (b.bottom > maxY) maxY = b.bottom;
        blendColor = Color.lerp(blendColor, _clusterColor(c), 0.3)!;
      }

      final groupRect = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(40);
      final groupRRect = RRect.fromRectAndRadius(
        groupRect, Radius.circular(groupRect.shortestSide * 0.3),
      );

      // Breathing pulse for the halo
      final pulse = math.sin(animationTime * 0.8 + i * 0.5) * 0.5 + 0.5;
      final haloAlpha = (0.03 + pulse * 0.02) * fade;

      // Soft fill halo
      _p
        ..style = PaintingStyle.fill
        ..shader = null
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20.0)
        ..color = blendColor.withValues(alpha: haloAlpha);
      canvas.drawRRect(groupRRect, _p);
      _p.maskFilter = null;

      // Subtle border
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = blendColor.withValues(alpha: haloAlpha * 0.8);
      canvas.drawRRect(groupRRect, _p);

      drawnHalos++;
    }
  }

  // ===========================================================================
  // CONNECTION COUNT BADGES — Small count indicators on clusters
  // ===========================================================================

  void _paintConnectionBadges(Canvas canvas, int lod, double fade) {
    if (controller.connections.isEmpty) return;

    // Count connections per cluster
    final counts = <String, int>{};
    for (final conn in controller.connections) {
      counts[conn.sourceClusterId] = (counts[conn.sourceClusterId] ?? 0) + 1;
      counts[conn.targetClusterId] = (counts[conn.targetClusterId] ?? 0) + 1;
    }

    for (final cluster in clusters) {
      final count = counts[cluster.id];
      if (count == null || count < 2) continue; // Only show badge for 2+ connections

      final color = _clusterColor(cluster);
      // Position badge at top-right of cluster bounds
      final badgeCenter = Offset(
        cluster.bounds.right + 4,
        cluster.bounds.top - 4,
      );

      // At LOD 2, scale badge inversely
      if (lod == 2) {
        final inverseScale = (1.0 / canvasScale).clamp(2.0, 8.0);
        canvas.save();
        canvas.translate(badgeCenter.dx, badgeCenter.dy);
        canvas.scale(inverseScale * 0.35);
        canvas.translate(-badgeCenter.dx, -badgeCenter.dy);
      }

      final badgeRadius = 7.0;

      // Badge background — frosted circle
      _p
        ..style = PaintingStyle.fill
        ..shader = null
        ..maskFilter = null
        ..color = Color.lerp(color, const Color(0xFF0D1117), 0.4)!.withValues(alpha: 0.85 * fade);
      canvas.drawCircle(badgeCenter, badgeRadius, _p);

      // Badge border
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = color.withValues(alpha: 0.50 * fade);
      canvas.drawCircle(badgeCenter, badgeRadius, _p);

      // Count text
      final tp = TextPainter(
        text: TextSpan(
          text: '$count',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.90 * fade),
            fontSize: 8.0,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(badgeCenter.dx - tp.width / 2, badgeCenter.dy - tp.height / 2),
      );

      if (lod == 2) {
        canvas.restore();
      }
    }
  }

  // ===========================================================================
  // LABEL PILL — Glassmorphic pill at connection midpoint
  // ===========================================================================

  void _paintLabelPill(Canvas canvas, Offset center, String label, Color color, double fade) {
    // All-caps for clean tag look
    final displayLabel = (label.length > 25 ? '${label.substring(0, 23)}…' : label).toUpperCase();
    final tp = TextPainter(
      text: TextSpan(
        text: displayLabel,
        style: TextStyle(
          color: Color.lerp(color, Colors.white, 0.7)!.withValues(alpha: 0.90 * fade),
          fontSize: 9.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // ✏️ Edit hint icon
    final editHint = TextPainter(
      text: TextSpan(
        text: ' ✎',
        style: TextStyle(
          color: Color.lerp(color, Colors.white, 0.5)!.withValues(alpha: 0.50 * fade),
          fontSize: 8.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final totalTextW = tp.width + editHint.width;
    final pillW = totalTextW + 18;
    final pillH = tp.height + 10;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: pillW, height: pillH),
      Radius.circular(pillH / 2), // Fully rounded
    );

    // Shadow — subtle depth
    _shadowPaint.color = Colors.black.withValues(alpha: 0.30 * fade);
    canvas.drawRRect(pillRect.shift(const Offset(0.5, 1.5)), _shadowPaint);

    // Fill: frosted glass tinted with connection color
    final fillColor = Color.lerp(color, const Color(0xFF0D1117), 0.55)!;
    _p
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = fillColor.withValues(alpha: 0.75 * fade);
    canvas.drawRRect(pillRect, _p);

    // Border — connection color, subtle
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = color.withValues(alpha: 0.40 * fade);
    canvas.drawRRect(pillRect, _p);

    // Text + edit hint
    final textX = center.dx - totalTextW / 2;
    tp.paint(canvas, Offset(textX, center.dy - tp.height / 2));
    editHint.paint(canvas, Offset(textX + tp.width, center.dy - editHint.height / 2));
  }

  // ===========================================================================
  // AUTO-SCALED LABEL PILL — LOD 2: inverse-scaled to stay readable
  // ===========================================================================

  void _paintAutoScaledLabelPill(Canvas canvas, Offset center, String label, Color color, double fade) {
    // At LOD 2, everything is tiny. Scale the pill inversely to canvasScale
    // so it remains readable. Clamp to prevent massive pills at extreme dezoom.
    final inverseScale = (1.0 / canvasScale).clamp(2.0, 8.0);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(inverseScale * 0.4); // 0.4 factor to keep pills compact
    canvas.translate(-center.dx, -center.dy);

    // Reuse the standard label pill renderer
    final displayLabel = (label.length > 20 ? '${label.substring(0, 18)}…' : label).toUpperCase();
    final tp = TextPainter(
      text: TextSpan(
        text: displayLabel,
        style: TextStyle(
          color: Color.lerp(color, Colors.white, 0.7)!.withValues(alpha: 0.90 * fade),
          fontSize: 11.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final pillW = tp.width + 20;
    final pillH = tp.height + 12;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: pillW, height: pillH),
      Radius.circular(pillH / 2),
    );

    // Shadow
    _shadowPaint.color = Colors.black.withValues(alpha: 0.40 * fade);
    canvas.drawRRect(pillRect.shift(const Offset(0.5, 1.5)), _shadowPaint);

    // Frosted fill
    final fillColor = Color.lerp(color, const Color(0xFF0D1117), 0.50)!;
    _p
      ..style = PaintingStyle.fill
      ..shader = null
      ..maskFilter = null
      ..color = fillColor.withValues(alpha: 0.85 * fade);
    canvas.drawRRect(pillRect, _p);

    // Luminous border
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = color.withValues(alpha: 0.50 * fade);
    canvas.drawRRect(pillRect, _p);

    // Text
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );

    canvas.restore();
  }

  // ===========================================================================
  // NETWORK STATS BADGE
  // ===========================================================================

  void _paintNetworkStats(Canvas canvas) {
    if (clusters.isEmpty) return;

    // Compute centroid of all clusters
    double sumX = 0, sumY = 0;
    double minY = double.infinity;
    for (final c in clusters) {
      sumX += c.centroid.dx;
      sumY += c.centroid.dy;
      if (c.bounds.top < minY) minY = c.bounds.top;
    }
    final cx = sumX / clusters.length;
    // Position above the topmost cluster
    final cy = minY - 60;

    final connCount = controller.connections.length;
    final text = '${clusters.length} cluster${clusters.length > 1 ? 's' : ''} \u2022 $connCount connection${connCount != 1 ? 's' : ''}';

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.40),
          fontSize: 11.0,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Subtle pill background
    final pillW = tp.width + 16;
    final pillH = tp.height + 8;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: pillW, height: pillH),
      const Radius.circular(8),
    );

    _p
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = Colors.white.withValues(alpha: 0.04);
    canvas.drawRRect(pillRect, _p);

    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawRRect(pillRect, _p);

    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  // ===========================================================================
  // DRAG PREVIEW
  // ===========================================================================

  void _paintDragPreview(Canvas canvas) {
    final src = dragSourcePoint!;
    final cur = dragCurrentPoint!;

    // Get source cluster color for themed drag line
    Color dragColor = const Color(0xFF64B5F6);
    if (dragSourceClusterId != null) {
      final srcCluster = clusters
          .where((c) => c.id == dragSourceClusterId)
          .firstOrNull;
      if (srcCluster != null) dragColor = _clusterColor(srcCluster);
    }

    final dx = cur.dx - src.dx;
    final dy = cur.dy - src.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 5) return;

    final nx = dx / length;
    final ny = dy / length;

    // Glowing dashed line with source color
    // 🚨 CRITICAL: Clear shader/maskFilter from previous paint operations —
    // when shader is set, color is completely ignored by Flutter's Canvas!
    const dashLen = 10.0;
    const gapLen = 7.0;

    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..shader = null
      ..maskFilter = null
      ..color = dragColor.withValues(alpha: 0.85);

    double pos = 0;
    while (pos < length) {
      final endPos = math.min(pos + dashLen, length);
      canvas.drawLine(
        Offset(src.dx + nx * pos, src.dy + ny * pos),
        Offset(src.dx + nx * endPos, src.dy + ny * endPos),
        _p,
      );
      pos = endPos + gapLen;
    }

    // 🔮 SNAP TARGET: Pulsing underline glow on candidate target word
    if (snapTargetClusterId != null) {
      // Snap feedback is handled by _paintWordUnderlines
      // (breathing pulsation on the target cluster underline)
    }

    // Animated glow dot at cursor
    _softGlowPaint.color = dragColor.withValues(alpha: 0.25);
    canvas.drawCircle(cur, 16, _softGlowPaint);

    _glowPaint.color = dragColor.withValues(alpha: 0.35);
    canvas.drawCircle(cur, 8, _glowPaint);

    _p
      ..style = PaintingStyle.fill
      ..shader = null
      ..maskFilter = null
      ..color = dragColor.withValues(alpha: 0.8);
    canvas.drawCircle(cur, 4, _p);

    _p.color = Colors.white.withValues(alpha: 0.6);
    canvas.drawCircle(cur, 1.5, _p);
  }

  // ===========================================================================
  // Utilities
  // ===========================================================================

  double _computeFade() {
    // Word-level connections should be visible as soon as we enter LOD 1.
    // Short smoothstep transition at the LOD 0→1 boundary only.
    const fadeZone = 0.05; // Narrow zone for quick fade-in on dezoom
    if (canvasScale > _lodLevel1Max + fadeZone) {
      // Well above LOD 1 boundary — fully transparent (LOD 0 handles its own)
      return 0.0;
    }
    if (canvasScale > _lodLevel1Max) {
      // Transition zone: quick fade from 0→1
      final t = 1.0 - ((canvasScale - _lodLevel1Max) / fadeZone).clamp(0.0, 1.0);
      return t * t * (3.0 - 2.0 * t); // smoothstep
    }
    // LOD 1-2: fully visible
    return 1.0;
  }

  /// ✨ Smooth crossfade for LOD 0→1 transition (bubbles appearance)
  double _computeLod1Fade() {
    const fadeZone = 0.08; // Wider zone for smoother bubble fade-in
    if (canvasScale > _lodLevel1Max) return 0.0;
    if (canvasScale > _lodLevel1Max - fadeZone) {
      final t = ((_lodLevel1Max - canvasScale) / fadeZone).clamp(0.0, 1.0);
      return t * t * (3.0 - 2.0 * t); // smoothstep
    }
    return 1.0;
  }

  /// 🏛️ Crossfade gate for monuments + zones vs AI semantic-morph layer.
  ///
  /// Returns 1.0 while the student-derived landmark layer is the primary
  /// naming system. Starts fading at morphT = 0.5 and reaches 0 at 0.9 —
  /// by that point the AI semantic nodes are fully in charge of titling.
  /// This prevents the 4-layer pile-up (dots + semantic + monument + zone)
  /// that we measured as cognitive overload during visual QA.
  double _landmarkLayerFade(double morphT) {
    if (morphT <= 0.5) return 1.0;
    if (morphT >= 0.9) return 0.0;
    final t = 1.0 - ((morphT - 0.5) / 0.4).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t); // smoothstep
  }

  /// Smooth fade for LOD 1→2 transition
  double _computeLod2Fade() {
    const fadeZone = 0.04;
    if (canvasScale > _lodLevel1Min + fadeZone) return 0.0;
    if (canvasScale > _lodLevel1Min) {
      final t = ((_lodLevel1Min + fadeZone - canvasScale) / fadeZone).clamp(0.0, 1.0);
      return t * t * (3.0 - 2.0 * t); // smoothstep
    }
    return 1.0;
  }

  // 🚀 PERF: Per-frame cluster map cache. Rebuilt only when clusters change.
  static List<ContentCluster>? _lastClusters;
  static Map<String, ContentCluster> _cachedClusterMap = {};

  Map<String, ContentCluster> _buildClusterMap() {
    if (identical(clusters, _lastClusters) && _cachedClusterMap.isNotEmpty) {
      return _cachedClusterMap;
    }
    final m = <String, ContentCluster>{};
    for (final c in clusters) {
      m[c.id] = c;
    }
    _lastClusters = clusters;
    _cachedClusterMap = m;
    return m;
  }

  Color _clusterColor(ContentCluster cluster) {
    final hasStrokes = cluster.strokeIds.isNotEmpty;
    final hasShapes = cluster.shapeIds.isNotEmpty;
    final hasText = cluster.textIds.isNotEmpty;
    final hasImages = cluster.imageIds.isNotEmpty;

    final types = (hasStrokes ? 1 : 0) +
        (hasShapes ? 1 : 0) +
        (hasText ? 1 : 0) +
        (hasImages ? 1 : 0);

    if (types > 1) return const Color(0xFF7EC8E3); // Teal mixed
    if (hasStrokes) return const Color(0xFF5C9CE6); // Sapphire blue
    if (hasShapes) return const Color(0xFF6BCB7F); // Emerald green
    if (hasText) return const Color(0xFFA87FDB); // Amethyst purple
    if (hasImages) return const Color(0xFFE8A84C); // Amber gold

    return const Color(0xFF7EC8E3);
  }

  // ===========================================================================
  // ===========================================================================
  // ===========================================================================
  // 🃏 FLASHCARD PREVIEW — Mini-card on semantic node tap
  // ===========================================================================

  // 🚀 PERF: Cached related suggestions for flashcard (avoid per-frame filter)
  static String? _fcCachedClusterId;
  static List<SuggestedConnection> _fcCachedRelated = [];
  static String? _fcCachedKeywordsClusterId;
  static String? _fcCachedKeywordsText;
  static String? _fcCachedKeywords;
  // (Removed `_fcAnimBaseTime` / `_fcAnimBaseMs`: the calibration that
  // derived flashcard `nowMs` from `animationTime` delta was wrong —
  // `animationTime` wraps every 10 s, so `nowMs` would freeze in time.
  // We now read DateTime.now().millisecondsSinceEpoch directly.)

  void _paintFlashcard(Canvas canvas, double fade) {
    if (semanticController == null) return;

    // Determine which cluster to render (active or dismissing)
    final isDismissing = semanticController!.isFlashcardDismissing &&
        semanticController!.flashcardClusterId == null;
    final clusterId = isDismissing
        ? semanticController!.dismissingClusterId
        : semanticController!.flashcardClusterId;
    if (clusterId == null) return;

    final cMap = _buildClusterMap();
    final cluster = cMap[clusterId];
    if (cluster == null) {
      if (!isDismissing) semanticController!.dismissFlashcard();
      semanticController!.clearDismissing();
      return;
    }

    // 🔧 2026-05-18 fix: use DateTime.now() directly. The previous
    // calibration trick that derived `nowMs` from `animationTime`
    // delta was BROKEN: `animationTime` is
    // `DateTime.now().millisecondsSinceEpoch % 10000 / 1000.0`
    // (see _ui_canvas_layer.dart), so it wraps every 10 seconds.
    // After the first wrap, `nowMs` stopped advancing and clung to
    // the calibration timestamp ±10 s. When a flashcard was shown
    // long after app start (e.g. zoom-in → dezoom → tap again),
    // `flashcardShowTime = DateTime.now()` was much larger than
    // the stuck `nowMs`, giving a NEGATIVE `ageSec`, an entranceT
    // clamped to 0, animEase=0 — i.e. the card painted at alpha 0
    // and the user saw NOTHING.
    //
    // The DateTime.now() syscall is well under a microsecond on
    // Android; the "perf" the old trick was buying never mattered.
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 🎬 Entrance / Exit animation
    double animEase;
    if (isDismissing) {
      final exitSec = (nowMs - semanticController!.flashcardDismissTime) / 1000.0;
      final exitT = (exitSec / 0.3).clamp(0.0, 1.0);
      animEase = 1.0 - (exitT * exitT * (3.0 - 2.0 * exitT));
      if (animEase < 0.01) {
        semanticController!.clearDismissing();
        return;
      }
    } else {
      final ageSec = (nowMs - semanticController!.flashcardShowTime) / 1000.0;
      final entranceT = (ageSec / 0.4).clamp(0.0, 1.0);
      animEase = entranceT < 1.0
          ? entranceT * entranceT * (3.0 - 2.0 * entranceT)
          : 1.0;
      if (animEase < 0.01) return;
    }

    final alpha = fade * animEase;
    final inverseScale = (1.0 / canvasScale).clamp(3.0, 16.0);
    final center = cluster.centroid;
    final importance = semanticController!.clusterImportance[clusterId] ?? 0.5;
    // Use actual cluster bounds + padding (matches _paintSemanticNodes)
    final nodePadding = (10.0 + importance * 6.0) * inverseScale;
    final clusterRect = cluster.bounds.inflate(nodePadding);
    final accentColor = _clusterColor(cluster);

    const cardW = 200.0;
    const cardPad = 12.0;

    // ── PRE-COMPUTE content to determine dynamic height ──
    final title = semanticController!.aiTitles[clusterId] ??
        semanticController!.semanticTitles[clusterId] ?? 'Cluster';

    double contentH = cardPad; // top padding

    // Title
    contentH += 18; // title line height

    // Stats bar
    final stats = semanticController!.clusterStats[clusterId];
    if (stats != null && stats.totalElements > 0) {
      contentH += 22; // stats row
    }

    // Keywords (cached per cluster to avoid RegExp work every frame).
    // 🧹 2026-05-18: prefer cleanedOcr so keyword extraction sees
    // normalised tokens ("Prima · Legge · Newton") instead of MyScript
    // raw artefacts ("Prima · Lelle · Newtn").
    final text = cleanedOcrTexts[clusterId] ?? clusterTexts[clusterId] ?? '';
    String? keywords;
    if (text.isNotEmpty) {
      if (_fcCachedKeywordsClusterId == clusterId && _fcCachedKeywordsText == text) {
        keywords = _fcCachedKeywords;
      } else {
        keywords = SemanticMorphController.extractLocalKeywords(text);
        _fcCachedKeywordsClusterId = clusterId;
        _fcCachedKeywordsText = text;
        _fcCachedKeywords = keywords;
      }
    }
    if (keywords != null) {
      contentH += 20; // keyword row
    }

    // 🚀 PERF: Pre-filtered suggestion cache
    if (_fcCachedClusterId != clusterId) {
      _fcCachedClusterId = clusterId;
      _fcCachedRelated = controller.suggestions.where((s) =>
          !s.dismissed &&
          (s.sourceClusterId == clusterId || s.targetClusterId == clusterId))
          .take(2).toList();
    }
    final related = _fcCachedRelated;
    contentH += related.length * 16; // ghost rows

    // 💡 PROACTIVE SCAN: AI description line
    final scanText = proactiveScan[clusterId];
    if (scanText != null && scanText.isNotEmpty) {
      contentH += 30; // 2 lines of scan text
    }

    // 💡 PROACTIVE GAPS: knowledge gap chips
    final gaps = proactiveGaps[clusterId];
    if (gaps != null && gaps.isNotEmpty) {
      contentH += 20; // gap chips row
    }

    // 📝 OCR PREVIEW: first 2 lines of recognized text.
    // 🧹 2026-05-18: prefer cleanedOcr so the user sees "Prima legge
    // di Newton" instead of the MyScript raw "Prima lelle o' newtn".
    final ocrText = cleanedOcrTexts[clusterId] ?? clusterTexts[clusterId] ?? '';
    final hasOcrPreview = ocrText.trim().length > 5;
    if (hasOcrPreview) {
      contentH += 24; // preview lines
    }

    // 📅 SR PROGRESS BAR
    final gapsForSr = gaps ?? <String>[];
    int masteredCount = 0;
    for (final g in gapsForSr) {
      final nextReview = reviewSchedule[g];
      if (nextReview != null && nextReview.nextReview.millisecondsSinceEpoch > nowMs) {
        masteredCount++;
      }
    }
    final hasSrBar = gapsForSr.isNotEmpty;
    if (hasSrBar) contentH += 14;

    // Hint + bottom padding
    contentH += 22 + cardPad;

    final cardH = contentH.clamp(80.0, 330.0);

    // ── SMART ORIENTATION: place card left or right of node ──
    // Convert node center to approximate screen X to decide placement.
    // The card is always ~200px wide on screen (scaled by 1/canvasScale).
    // If the node is in the right half of a ~400px viewport, place card left.
    final approxScreenX = center.dx * canvasScale;
    final placeLeft = approxScreenX > 200; // heuristic: right-ish → card goes left

    final double cardX;
    final double cardY = center.dy - cardH * 0.3;
    if (placeLeft) {
      // Card to the LEFT of the node
      cardX = clusterRect.left - 15 - cardW * (1.0 / canvasScale);
    } else {
      // Card to the RIGHT of the node (default)
      cardX = clusterRect.right + 15;
    }

    // ── 0. 🔗 CONNECTOR LINE: node → card ──
    final connNodeSide = placeLeft
        ? Offset(clusterRect.left, center.dy)
        : Offset(clusterRect.right, center.dy);
    final connCardSide = placeLeft
        ? Offset(cardX + cardW * (1.0 / canvasScale), cardY + cardH * 0.3)
        : Offset(cardX, cardY + cardH * 0.3);
    final connCp = Offset(
      (connNodeSide.dx + connCardSide.dx) / 2,
      connNodeSide.dy - 10,
    );
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = accentColor.withValues(alpha: 0.30 * alpha)
      ..maskFilter = null;
    const connSteps = 10;
    for (int i = 0; i < connSteps; i++) {
      final t0 = i / connSteps;
      final t1 = (i + 1) / connSteps;
      _p.color = accentColor.withValues(
        alpha: (0.15 + t0 * 0.20) * alpha,
      );
      canvas.drawLine(
        _quadBezierPt(connNodeSide, connCp, connCardSide, t0),
        _quadBezierPt(connNodeSide, connCp, connCardSide, t1),
        _p,
      );
    }

    // ── CARD BODY ──
    canvas.save();
    canvas.translate(cardX, cardY);
    // Scale so the card is ~200px wide on screen regardless of zoom
    final cardScale = (1.0 / canvasScale) * animEase;
    canvas.scale(cardScale);

    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, cardW, cardH),
      const Radius.circular(12),
    );

    // ── 1. Frosted background ──
    _p
      ..style = PaintingStyle.fill
      ..color = Color.fromARGB((0xDD * alpha).round(), 0x1A, 0x1A, 0x2E)
      ..shader = null
      ..maskFilter = null;
    canvas.drawRRect(cardRect, _p);

    // ── 2. Accent border ──
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = accentColor.withValues(alpha: 0.60 * alpha);
    canvas.drawRRect(cardRect, _p);

    // ── 3. Top edge glow ──
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.12 * alpha);
    canvas.drawLine(
      const Offset(16, 1), Offset(cardW - 16, 1), _p,
    );

    // ── 4. Title (cached) ──
    double curY = cardPad;
    final titleKey = '${clusterId}_fc_$title';
    var titleTp = _cachedTitlePainters[titleKey];
    if (titleTp == null) {
      titleTp = TextPainter(
        text: TextSpan(
          text: title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: 14.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: cardW - cardPad * 2);
      _cachedTitlePainters[titleKey] = titleTp;
    }
    titleTp.paint(canvas, Offset(cardPad, curY));
    curY += titleTp.height + 4;

    // ── 4b. 💡 PROACTIVE SCAN TEXT — AI description ──
    if (scanText != null && scanText.isNotEmpty) {
      final scanKey = '${clusterId}_fcscan_${scanText.hashCode}';
      var scanTp = _cachedTitlePainters[scanKey];
      if (scanTp == null) {
        scanTp = TextPainter(
          text: TextSpan(
            text: scanText,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 9.0,
              height: 1.3,
              fontStyle: FontStyle.italic,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: cardW - cardPad * 2);
        _cachedTitlePainters[scanKey] = scanTp;
      }
      scanTp.paint(canvas, Offset(cardPad, curY));
      curY += scanTp.height + 6;
    }

    // ── 5. Content type dots + stats ──
    if (stats != null && stats.totalElements > 0) {
      final items = <MapEntry<Color, String>>[];
      if (stats.strokeCount > 0) {
        items.add(MapEntry(const Color(0xFF5C9CE6), '${stats.strokeCount} tratti'));
      }
      if (stats.textCount > 0) {
        items.add(MapEntry(const Color(0xFFA87FDB), '${stats.textCount} testi'));
      }
      if (stats.shapeCount > 0) {
        items.add(MapEntry(const Color(0xFF6BCB7F), '${stats.shapeCount} forme'));
      }
      if (stats.imageCount > 0) {
        items.add(MapEntry(const Color(0xFFE8A84C), '${stats.imageCount} img'));
      }

      double dotX = cardPad;
      for (final item in items) {
        _p
          ..style = PaintingStyle.fill
          ..color = item.key.withValues(alpha: 0.80 * alpha);
        canvas.drawCircle(Offset(dotX + 4, curY + 5), 3.5, _p);

        final statKey = '${clusterId}_fcs_${item.value}';
        var statTp = _cachedTitlePainters[statKey];
        if (statTp == null) {
          statTp = TextPainter(
            text: TextSpan(
              text: item.value,
              style: const TextStyle(
                color: Color(0x8CFFFFFF),
                fontSize: 9.0,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          _cachedTitlePainters[statKey] = statTp;
        }
        statTp.paint(canvas, Offset(dotX + 10, curY));
        dotX += statTp.width + 18;
      }
      curY += 18;
    }

    // ── 6. Keywords ──
    if (keywords != null) {
      final kwKey = '${clusterId}_fckw_$keywords';
      var kwTp = _cachedTitlePainters[kwKey];
      if (kwTp == null) {
        kwTp = TextPainter(
          text: TextSpan(
            text: '🔑 $keywords',
            style: TextStyle(
              color: accentColor.withValues(alpha: 0.70),
              fontSize: 10.0,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: cardW - cardPad * 2);
        _cachedTitlePainters[kwKey] = kwTp;
      }
      kwTp.paint(canvas, Offset(cardPad, curY));
      curY += kwTp.height + 6;
    }

    // ── 6b. 💡 PROACTIVE GAPS — knowledge gap chips ──
    if (gaps != null && gaps.isNotEmpty) {
      double chipX = cardPad;
      const chipH = 14.0;
      const chipPad = 6.0;
      for (final gap in gaps.take(3)) {
        final gapKey = '${clusterId}_fcgap_$gap';
        var gapTp = _cachedTitlePainters[gapKey];
        if (gapTp == null) {
          gapTp = TextPainter(
            text: TextSpan(
              text: gap,
              style: const TextStyle(
                color: Color(0xE600E5FF), // cyan
                fontSize: 8.0,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          _cachedTitlePainters[gapKey] = gapTp;
        }
        final chipW = gapTp.width + chipPad * 2;
        if (chipX + chipW > cardW - cardPad) break; // overflow

        // Chip background
        final chipRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(chipX, curY, chipW, chipH),
          const Radius.circular(7),
        );
        _p
          ..style = PaintingStyle.fill
          ..color = const Color(0xFF00E5FF).withValues(alpha: 0.10 * alpha);
        canvas.drawRRect(chipRect, _p);
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = const Color(0xFF00E5FF).withValues(alpha: 0.30 * alpha);
        canvas.drawRRect(chipRect, _p);

        gapTp.paint(canvas, Offset(chipX + chipPad, curY + 2));
        chipX += chipW + 4;
      }
      curY += chipH + 6;
    }

    // ── 6c. 📝 OCR PREVIEW — first lines of recognized text ──
    if (hasOcrPreview) {
      final previewText = ocrText.trim().replaceAll('\n', ' ');
      final prevKey = '${clusterId}_fcocr_${previewText.hashCode}';
      var prevTp = _cachedTitlePainters[prevKey];
      if (prevTp == null) {
        prevTp = TextPainter(
          text: TextSpan(
            text: '📝 $previewText',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 8.5,
              height: 1.2,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: cardW - cardPad * 2);
        _cachedTitlePainters[prevKey] = prevTp;
      }
      prevTp.paint(canvas, Offset(cardPad, curY));
      curY += prevTp.height + 4;
    }

    // ── 7. Connected ghost suggestions ──
    for (final ghost in related) {
      final otherId = ghost.sourceClusterId == clusterId
          ? ghost.targetClusterId
          : ghost.sourceClusterId;
      final otherTitle = semanticController!.aiTitles[otherId] ??
          semanticController!.semanticTitles[otherId] ?? '…';
      final ghostLabel = '👻 ${ghost.reason} → $otherTitle';
      final ghostKey = '${clusterId}_fcg_$ghostLabel';
      var ghostTp = _cachedTitlePainters[ghostKey];
      if (ghostTp == null) {
        ghostTp = TextPainter(
          text: TextSpan(
            text: ghostLabel,
            style: const TextStyle(
              color: Color(0x66FFFFFF),
              fontSize: 9.0,
              fontStyle: FontStyle.italic,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: cardW - cardPad * 2);
        _cachedTitlePainters[ghostKey] = ghostTp;
      }
      ghostTp.paint(canvas, Offset(cardPad, curY));
      curY += ghostTp.height + 3;
    }

    // ── 7b. 📅 SR PROGRESS BAR — mastery indicator ──
    if (hasSrBar) {
      final barW = cardW - cardPad * 2;
      const barH = 5.0;
      final barY = curY + 2;
      // Background
      _p
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.08 * alpha)
        ..maskFilter = null
        ..shader = null;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cardPad, barY, barW, barH),
          const Radius.circular(2.5),
        ),
        _p,
      );
      // Fill
      final progress = gapsForSr.isEmpty
          ? 0.0
          : (masteredCount / gapsForSr.length).clamp(0.0, 1.0);
      if (progress > 0) {
        final fillColor = progress > 0.7
            ? const Color(0xFF4CAF50) // green
            : progress > 0.3
                ? const Color(0xFFFFC107) // amber
                : const Color(0xFFFF5722); // deep orange
        _p.color = fillColor.withValues(alpha: 0.60 * alpha);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cardPad, barY, barW * progress, barH),
            const Radius.circular(2.5),
          ),
          _p,
        );
      }
      // Label
      final srLabel = '$masteredCount/${gapsForSr.length} reviewed';
      final srKey = '${clusterId}_fcsr_$srLabel';
      var srTp = _cachedTitlePainters[srKey];
      if (srTp == null) {
        srTp = TextPainter(
          text: TextSpan(
            text: '📅 $srLabel',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 7.5,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        _cachedTitlePainters[srKey] = srTp;
      }
      srTp.paint(canvas, Offset(cardPad, barY + barH + 1));
      curY += 14;
    }

    // ── 8. "Zoom in" hint ──
    final hintKey = '${clusterId}_fch';
    var hintTp = _cachedTitlePainters[hintKey];
    if (hintTp == null) {
      hintTp = TextPainter(
        text: TextSpan(
          text: '⟲ Tap → Zoom in',
          style: TextStyle(
            color: accentColor.withValues(alpha: 0.45),
            fontSize: 9.0,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _cachedTitlePainters[hintKey] = hintTp;
    }
    hintTp.paint(canvas,
        Offset(cardW - cardPad - hintTp.width, cardH - cardPad - hintTp.height));

    canvas.restore();

    // 🃏 2026-05-18: publish the card's CANVAS-space bounds so the tap
    // handler can detect "tap on card body" reliably. Width / height
    // are `cardW / canvasScale` and `cardH / canvasScale` because the
    // inner draws use `canvas.scale(1/canvasScale)` to keep the card
    // ~200 px wide on screen regardless of zoom. Stored without the
    // `animEase` factor so a half-entered card still has a usable
    // hit-target (avoids "card is animating in, my tap missed"
    // glitches at the very start of the show animation).
    if (!isDismissing) {
      semanticController!.flashcardCardCanvasRect = Rect.fromLTWH(
        cardX,
        cardY,
        cardW / canvasScale,
        cardH / canvasScale,
      );
    }
  }


  // ===========================================================================
  // 🗺️ ZONE TINTS — Colored regions per super-node on the mappamondo
  // ===========================================================================
  //
  // Pedagogical contract (§22 "i quartieri del Palazzo", §1133):
  //   At extreme zoom-out the student must see *quartieri* — colored
  //   regions that codify the spatial geography of their knowledge.
  //   Color is consistent per super-node so neighbourhoods become
  //   recognizable across sessions (Place Cells §22, Memoria di Luogo).
  //
  // Visual recipe:
  //   - Color: deterministic HSL from hash(superNode.id) → consistent
  //     across sessions. Low saturation (~0.30) to coexist with ink.
  //   - Shape: rounded bounding box of all member cluster bounds,
  //     inflated by 80 canvas-px. Cheap, no convex hull required.
  //   - Alpha: 0.08 × morphProgress × (1 - 0.5 × godViewProgress).
  //     Fades in at scale ≤ 0.30 (with morph), softens at god view.
  //   - MaskFilter blur: 60-120 px depending on inverseScale.
  //
  // PERF: O(N) per super-node + per member cluster (single bbox union).
  // Skipped when superNodes empty (controller pre-computes only when
  // scale ≤ morphStartScale — see _lifecycle_helpers.dart).
  //
  // 🚀 IMAGE CACHE: the blurred RRects are baked into a [ui.Image] keyed by
  // super-node-set + zone-label-set. Per-frame cost collapses from
  // N × (drawRRect+MaskFilter.blur saveLayer) to a single drawImageRect call.
  //
  // 2026-05-18 (Impeller fix): the previous implementation cached a
  // [ui.Picture] and replayed via `saveLayer(alpha) + drawPicture +
  // restore`. On Vulkan-Impeller (Adreno 660) the picture contains
  // MaskFilter.blur ops which declare `CanAcceptOpacity = false`, so
  // the saveLayer trying to propagate the inherited opacity flooded the
  // log with `ImpellerValidationBreak` during every morph fade
  // (scale 0.30 → 0.10). Switching to `drawImageRect(image, …, paint
  // ..color=Color.fromRGBO(255,255,255, alpha))` avoids the saveLayer
  // entirely — image-sampling paints accept inherited opacity natively.
  //
  // The image is baked at a downsample factor (0.25) and capped at
  // 2048×2048 pixels so memory stays bounded even on multi-thousand
  // cluster canvases. Since the source content is intrinsically blurry
  // (`MaskFilter.blur(sigma=50)`), the downsample is visually invisible
  // at the scales (0.30–0.10) where this layer renders.

  /// 🚀 Static Image cache for the zone-tint blob layer. Static so it
  /// survives painter rebuilds (CustomPaint re-instantiates KFP every
  /// frame). Replaced on cache-miss only; the previous image is
  /// disposed at the same point to bound GPU memory.
  static ui.Image? _zoneTintImage;

  /// Canvas-space bounds of the baked image, used as `dst` of the
  /// `drawImageRect` replay so the painted region matches the original
  /// per-frame variant pixel-for-pixel modulo the downsample.
  static Rect _zoneTintImageBounds = Rect.zero;

  static String _zoneTintCacheKey = '';

  /// Downsample factor used when baking the zone-tint image. 0.25 keeps
  /// per-pixel density well above the perceptual threshold for the
  /// blurred content while quartering memory vs. a 1:1 bake.
  static const double _kZoneTintBakeDownsample = 0.25;

  /// Hard ceiling on the baked image dimension (each side). Without
  /// this a 50k×50k canvas-space union at downsample 0.25 would still
  /// try to allocate a 12500² image (≈600 MB RGBA). Cap at 2048 keeps
  /// the texture bounded; quality at scale 0.10 is unaffected (the
  /// viewport-equivalent at full zoom-out is well under 2k pixels).
  static const int _kZoneTintMaxBakeDim = 2048;

  /// Sigma + inflation chosen so the baked Picture is visually close to
  /// the per-frame version across the entire (0.30 → 0.10) zoom range.
  ///
  /// Fase 5 fix 2.1: sigma 80 → 50. The previous 80 spalmava il blob
  /// così tanto che l'intensità per-pixel scendeva sotto la soglia di
  /// percezione anche con alpha 0.15 e saturation 0.40. 50 keeps the
  /// blur generous enough da non vedere bordi netti ma concentrata
  /// abbastanza da preservare il colore visibile.
  static const double _kZoneTintBakedSigma = 50.0;
  static const double _kZoneTintBakedInflate = 100.0;

  void _paintZoneTints(Canvas canvas, double fade) {
    if (semanticController == null) return;
    final superNodes = semanticController!.superNodes;
    if (superNodes.isEmpty) return;
    if (fade < 0.01) return;

    final morphT = semanticController!.morphProgress.clamp(0.0, 1.0);
    if (morphT < 0.05) return;
    final godT = semanticController!.godViewProgress.clamp(0.0, 1.0);

    // Reduce tint intensity as god view takes over (super-nodes themselves
    // dominate the visual at scale ≤ 0.10 — keep tints subordinate).
    // Fase 5 fix 2.1: alpha 0.15 → 0.22. Device retest a 0.20-0.10
    // still showed white/grey background — even alpha 0.15 with
    // saturation 0.40 + lightness 0.55 was sub-threshold of perception
    // because blur sigma 80 spalmava il blob su un'area grande, cuocendo
    // l'intensità per-pixel. Bumped to 0.22 → effective ~0.22 on white
    // bg, percepito come "colored atmosphere" senza essere fluo.
    // Plus blur sigma reduced to 50 (vedi `_kZoneTintBakedSigma`).
    // At god view (godT=1) → 0.11, comunque sub-ordinazione ai super-nodi.
    final tintAlphaBase = 0.22 * morphT * (1.0 - 0.5 * godT);
    if (tintAlphaBase < 0.005) return;

    // ── 1. Build cache key from cluster set + zone-label identities.
    //    morphT and scale are EXCLUDED — they only modulate alpha,
    //    which is applied at replay time via saveLayer.
    final keyBuf = StringBuffer()..write(superNodes.length);
    for (final sn in superNodes) {
      keyBuf
        ..write('|')
        ..write(sn.id)
        ..write(':')
        ..write(sn.memberClusterIds.length);
    }
    for (final z in zoneLabels) {
      keyBuf
        ..write('z')
        ..write(z.id)
        ..write('=')
        ..write(z.label.toLowerCase());
    }
    final cacheKey = keyBuf.toString();

    // ── 2. Rebuild Image on cache miss only.
    if (cacheKey != _zoneTintCacheKey || _zoneTintImage == null) {
      final baked = _bakeZoneTintImage();
      // Dispose the previous image to bound GPU memory across rebuilds.
      _zoneTintImage?.dispose();
      _zoneTintImage = baked?.image;
      _zoneTintImageBounds = baked?.bounds ?? Rect.zero;
      _zoneTintCacheKey = cacheKey;
    }
    final img = _zoneTintImage;
    final bounds = _zoneTintImageBounds;
    if (img == null || bounds.isEmpty) return;

    // ── 3. Replay via drawImageRect — paint.color alpha is honoured by
    //    the image-sampling pipeline natively (no saveLayer required).
    //    This is what unlocks the Impeller fix; the inherited-opacity
    //    assertion only fires when an external saveLayer wraps content
    //    that declares `CanAcceptOpacity = false`.
    final globalAlpha = (tintAlphaBase * fade).clamp(0.0, 1.0);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      bounds,
      Paint()..color = Color.fromRGBO(255, 255, 255, globalAlpha),
    );
  }

  /// 🎨 COLOR PERSISTENCE: hash on the zone *label text* (stable across
  /// sessions and cluster-add/remove churn) rather than super-node id
  /// (= root cluster from Union-Find, which can flip when a neighbour
  /// joins or leaves the merge cluster). Without this anchor, the same
  /// region of the Palazzo could change color between sessions and
  /// break Place Cells encoding (§22, "il rosso era in alto a destra").
  /// Fallback to super-node id only when no zone label is available yet
  /// (early sessions where ZoneLabeler hasn't found a stable name).
  String? _zoneLabelTextForCluster(String clusterId) {
    final zoneId = zoneMembership[clusterId];
    if (zoneId == null) return null;
    for (final z in zoneLabels) {
      if (z.id == zoneId) {
        final l = z.label.trim().toLowerCase();
        return l.isEmpty ? null : l;
      }
    }
    return null;
  }

  /// Bake all super-node tint blobs into a single [ui.Picture] at full
  /// opacity. Called only on cache miss (cluster/zone identity change).
  /// 🔥 Bakes the zone-tint RRects into a ui.Image with bounded memory.
  ///
  /// Two-pass design:
  ///   • Pass 1 — iterate super-nodes, compute each cluster-union RRect
  ///     and color, accumulate the global union bounds (inflated by the
  ///     blur sigma so feathered edges aren't clipped).
  ///   • Pass 2 — compute image pixel size (downsample × bounds,
  ///     capped at [_kZoneTintMaxBakeDim]), record into a PictureRecorder
  ///     that translates origin to the bounds top-left and scales to
  ///     image-pixel space, then convert via `Picture.toImageSync`.
  ///
  /// Returns `null` if no super-nodes contribute valid bounds.
  ({ui.Image image, Rect bounds})? _bakeZoneTintImage() {
    final superNodes = semanticController!.superNodes;
    if (superNodes.isEmpty) return null;
    final cMap = _buildClusterMap();

    // ── Pass 1: collect items + accumulate union (with blur margin).
    // MaskFilter.blur spreads each shape by ~3 × sigma. Inflate the
    // recorded item bounds by that margin so the union covers the
    // feathered halo too; otherwise drawImageRect would clip the
    // outer fade.
    final blurPad = _kZoneTintBakedSigma * 3.0;
    final items = <({RRect rrect, Color color})>[];
    Rect? unionAll;
    for (final sn in superNodes) {
      Rect? union;
      final zoneLabelCount = <String, int>{};
      for (final mid in sn.memberClusterIds) {
        final c = cMap[mid];
        if (c == null) continue;
        final b = c.bounds;
        if (b.isEmpty || !b.isFinite) continue;
        union = (union == null) ? b : union.expandToInclude(b);
        final zl = _zoneLabelTextForCluster(mid);
        if (zl != null) {
          zoneLabelCount[zl] = (zoneLabelCount[zl] ?? 0) + 1;
        }
      }
      if (union == null) continue;

      final padded = union.inflate(_kZoneTintBakedInflate);
      final radius = Radius.circular(
        math.min(padded.width, padded.height) * 0.20,
      );
      final rr = RRect.fromRectAndRadius(padded, radius);

      String hashSeed;
      if (zoneLabelCount.isNotEmpty) {
        hashSeed = zoneLabelCount.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;
      } else {
        hashSeed = sn.id;
      }
      final h = (hashSeed.hashCode & 0x7FFFFFFF) % 360;
      // 2026-05-17: saturation 0.40 → 0.50. Quartieri colorati (§22)
      // now read as "soft pastel zones" instead of "barely-tinted
      // atmosphere". Lightness 0.45 stays — yields mid-tone colors,
      // not fluo. Compounded with alpha 0.22 + drawImageRect paint
      // alpha + blur sigma 50 the visual is "regione colorata"
      // without overpowering the semantic nodes layered above.
      final color = HSLColor.fromAHSL(1.0, h.toDouble(), 0.50, 0.45).toColor();
      items.add((rrect: rr, color: color));

      final withBlur = padded.inflate(blurPad);
      unionAll =
          (unionAll == null) ? withBlur : unionAll.expandToInclude(withBlur);
    }
    if (unionAll == null || items.isEmpty) return null;

    // ── Pass 2: compute image dimensions with downsample + cap, then
    // record at image-pixel scale and convert to ui.Image.
    double pxW = unionAll.width * _kZoneTintBakeDownsample;
    double pxH = unionAll.height * _kZoneTintBakeDownsample;
    final maxDim = _kZoneTintMaxBakeDim.toDouble();
    if (pxW > maxDim || pxH > maxDim) {
      final fit = math.min(maxDim / pxW, maxDim / pxH);
      pxW *= fit;
      pxH *= fit;
    }
    final w = pxW.ceil().clamp(1, _kZoneTintMaxBakeDim);
    final h = pxH.ceil().clamp(1, _kZoneTintMaxBakeDim);
    final scaleX = w / unionAll.width;
    final scaleY = h / unionAll.height;

    final recorder = ui.PictureRecorder();
    final recCanvas = Canvas(recorder)
      ..scale(scaleX, scaleY)
      ..translate(-unionAll.left, -unionAll.top);

    final bakePaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(
        BlurStyle.normal,
        _kZoneTintBakedSigma,
      );
    for (final item in items) {
      bakePaint.color = item.color;
      recCanvas.drawRRect(item.rrect, bakePaint);
    }

    final pic = recorder.endRecording();
    try {
      final img = pic.toImageSync(w, h);
      return (image: img, bounds: unionAll);
    } finally {
      pic.dispose();
    }
  }


  // ===========================================================================
  // 🔮 EARLY TITLE PREVIEW — Floating titles in the pre-morph window
  // ===========================================================================
  //
  // Activated when canvasScale ∈ (morphStartScale, aiPreloadScale] = (0.30, 0.35].
  // Cluster ink is still fully visible (no morph yet), but AI titles are
  // already cached (controller fetched them at aiPreloadScale). Painting
  // them as small floating labels above each cluster gives the student a
  // "mapping mode is coming" affordance — reduces the perceptual cliff
  // at scale 0.30 where the semantic morph begins.
  //
  // Visual recipe: small text pill above the cluster centroid, alpha
  // ramps 0 → 1 across (0.35 → 0.30) via smoothstep. No node box, no
  // glow — kept minimal so it reads as overlay, not transformation.

  void _paintEarlyTitlePreview(Canvas canvas, double fade) {
    if (clusters.isEmpty || semanticController == null) return;
    if (fade < 0.01) return;

    // Smoothstep: alpha 0 at scale 0.35, 1 at scale 0.30.
    // Fase 5 fix: extended start 0.35 → 0.40 to match the widened gate
    // upstream (3× larger preview window) so the smoothstep saturates
    // at scale 0.30 (max alpha just before morph kicks in).
    const start = SemanticMorphController.aiPreloadScale + 0.05; // 0.40
    const end = SemanticMorphController.morphStartScale; // 0.30
    final t = ((start - canvasScale) / (start - end)).clamp(0.0, 1.0);
    final previewAlpha = t * t * (3.0 - 2.0 * t);
    if (previewAlpha < 0.05) return;

    final inverseScale = (1.0 / canvasScale).clamp(2.0, 8.0);

    for (final cluster in clusters) {
      final raw = clusterTexts[cluster.id];
      if (raw == null || raw.isEmpty) continue;
      // Pick a short display string — same tokenizer used by zone/monument.
      final display = TextLabelPicker.pickFromMany([raw], maxChars: 22);
      if (display.isEmpty) continue;

      canvas.save();
      final center = cluster.centroid;
      // Anchor label above the cluster bounds (use bounds.top so it
      // doesn't collide with the still-fully-visible ink).
      final anchor = Offset(
        center.dx,
        (cluster.bounds.isFinite ? cluster.bounds.top : center.dy) - 12,
      );
      canvas.translate(anchor.dx, anchor.dy);
      canvas.scale(inverseScale * 0.55);
      canvas.translate(-anchor.dx, -anchor.dy);

      final cacheKey = 'pre_${display.hashCode}';
      var tp = _cachedTitlePainters[cacheKey];
      if (tp == null) {
        tp = TextPainter(
          text: TextSpan(
            text: display,
            style: const TextStyle(
              color: Color(0xFFB0D4FF),
              fontSize: 11.0,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        if (_cachedTitlePainters.length > 100) {
          _cachedTitlePainters.remove(_cachedTitlePainters.keys.first);
        }
        _cachedTitlePainters[cacheKey] = tp;
      }

      final pillW = tp.width + 12;
      final pillH = tp.height + 6;
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: anchor, width: pillW, height: pillH),
        Radius.circular(pillH / 2),
      );

      _p
        ..style = PaintingStyle.fill
        ..shader = null
        ..maskFilter = null
        ..color = const Color(0xCC0A0E1A).withValues(alpha: 0.70 * previewAlpha * fade);
      canvas.drawRRect(pillRect, _p);

      tp.paint(
        canvas,
        Offset(anchor.dx - tp.width / 2, anchor.dy - tp.height / 2),
      );
      canvas.restore();
    }
  }


  // ===========================================================================
  // 🏛️ MONUMENT LABELS — Named landmarks on the satellite view (LOD 2)
  // ===========================================================================
  //
  // Pedagogical contract (§471-474, §1098):
  //   Zooming out, the student must still see *named* anchors of their
  //   Memory Palace — "il tetto: i quartieri dall'alto, solo i nomi delle
  //   materie e i nodi-monumento più grandi". Without these the satellite
  //   view collapses into anonymous dots and the palace loses its map.
  //
  // Inputs:
  //   - [monumentIds]: pre-computed by MonumentResolver (controller-side).
  //   - [clusterTexts]: recognized handwriting per cluster (label source).
  //   - [monumentImportance]: 0..1 score → size/opacity weight.

  void _paintMonumentLabels(Canvas canvas, double fade) {
    if (monumentIds.isEmpty || fade < 0.01) return;

    final cMap = _buildClusterMap();
    // Upper clamp bumped from 12 → 30 so labels stay readable below
    // scale 0.083 where the tighter cap would start shrinking text again.
    final inverseScale = (1.0 / canvasScale).clamp(2.0, 30.0);

    // Breath synchronized slowly — landmarks "exist", they don't dance.
    final breath = 0.88 + 0.12 * math.sin(animationTime * 0.6);

    for (final id in monumentIds) {
      final cluster = cMap[id];
      if (cluster == null) continue;

      // 🧠 Active Recall protection: hide the label on clusters currently
      // concealed by SRS blur or Fog of War. Showing the monument title
      // would pre-reveal the answer the student is trying to recall
      // (§2 teoria — Active Recall requires retrieval, not recognition).
      if (hiddenForRecallClusterIds.contains(id)) continue;

      final importance = (monumentImportance[id] ?? 0.5).clamp(0.0, 1.0);
      final label = _monumentLabel(id);
      if (label.isEmpty) continue;

      final color = _clusterColor(cluster);
      final center = cluster.centroid;

      // ── 1. Subtle accent halo — replaces the redundant landmark dot.
      // [_paintClusterDots] already drew the baseline dot for this cluster;
      // we only add a soft breathing glow to distinguish monuments at a
      // glance without stacking another opaque circle on top (which would
      // compound with the drawing-painter tile stroke-count label, halos,
      // and connection badges into visual clutter).
      final accentRadius = (6.0 + importance * 4.0) * inverseScale * 0.35;
      _softGlowPaint.color = color.withValues(
        alpha: (0.18 + 0.12 * importance) * fade * breath,
      );
      canvas.drawCircle(center, accentRadius * 1.6, _softGlowPaint);

      // ── 2. Title pill ABOVE the cluster dot, inverse-scaled to stay
      // readable. Generous gap so the pill never collides with the
      // tile-level "140 tratti" label that the drawing painter draws
      // at extreme dezoom on busy clusters.
      final pillGap = accentRadius * 3.2 + 10;
      final labelCenter = Offset(center.dx, center.dy - pillGap);
      _paintMonumentPill(
        canvas,
        labelCenter,
        label,
        color,
        fade,
        importance,
        inverseScale,
      );
    }
  }

  /// Render a readable monument title pill. Scaled inversely to canvasScale so
  /// it stays legible at extreme dezoom. Higher [importance] → larger font.
  void _paintMonumentPill(
    Canvas canvas,
    Offset center,
    String label,
    Color color,
    double fade,
    double importance,
    double inverseScale,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    // Multiplier 0.9: renders the pill at ~90% of native screen size at any
    // LOD 2 zoom (inverseScale is clamped at [2,12] to keep extremes sane).
    // Previous 0.45 produced unreadable ~5pt text at scale 0.10 — monuments
    // are landmarks and must be the most-legible element on the mappamondo.
    canvas.scale(inverseScale * 0.9);
    canvas.translate(-center.dx, -center.dy);

    final display = (label.length > 22 ? '${label.substring(0, 20)}…' : label)
        .toUpperCase();
    final fontSize = 11.0 + importance * 3.0;
    final cacheKey = 'mon_${display.hashCode}_${fontSize.toStringAsFixed(1)}';

    var tp = _cachedTitlePainters[cacheKey];
    if (tp == null) {
      tp = TextPainter(
        text: TextSpan(
          text: display,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (_cachedTitlePainters.length > 100) {
        _cachedTitlePainters.remove(_cachedTitlePainters.keys.first);
      }
      _cachedTitlePainters[cacheKey] = tp;
    }

    final pillW = tp.width + 18;
    final pillH = tp.height + 10;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: pillW, height: pillH),
      Radius.circular(pillH / 2),
    );

    // Drop shadow
    _shadowPaint.color = Colors.black.withValues(alpha: 0.55 * fade);
    canvas.drawRRect(pillRect.shift(const Offset(0, 1.8)), _shadowPaint);

    // Fill — darker than regular label pill to stand out as a landmark
    final fillColor = Color.lerp(color, const Color(0xFF050812), 0.65)!;
    _p
      ..style = PaintingStyle.fill
      ..shader = null
      ..maskFilter = null
      ..color = fillColor.withValues(alpha: 0.92 * fade);
    canvas.drawRRect(pillRect, _p);

    // Luminous border — thicker for monuments
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = color.withValues(alpha: 0.70 * fade);
    canvas.drawRRect(pillRect, _p);

    // Text
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );

    canvas.restore();
  }

  /// Pick a short label for a monument cluster.
  ///
  /// Delegates to [TextLabelPicker] — same tokenizer + stopword set as
  /// [ZoneLabeler]. Keeps the two labeling layers coherent.
  ///
  /// First-token dedup with zone label: if this cluster is a member of
  /// a zone whose label matches the monument's first token, that first
  /// token is dropped so monument ≠ zone textually. Example:
  ///   zone = "FISICA", monument text = "Fisica quantistica introduzione"
  ///   → monument renders as "QUANTISTICA INTRODUZIONE", not
  ///   "FISICA QUANTISTICA INTRODUZIONE" (which would duplicate zone).
  String _monumentLabel(String clusterId) {
    final text = clusterTexts[clusterId]?.trim() ?? '';
    if (text.isEmpty) return '';
    final tokens =
        TextLabelPicker.tokenize(text).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return '';

    // Drop the first token if it matches this cluster's zone label.
    final zoneId = zoneMembership[clusterId];
    if (zoneId != null) {
      final zoneTok = _zoneFirstToken(zoneId);
      if (zoneTok != null && tokens.first == zoneTok) {
        if (tokens.length > 1) {
          tokens.removeAt(0);
        } else {
          // Only word is the zone name; keep it — the zone label itself
          // will be suppressed at render time so the monument can shine.
        }
      }
    }

    return TextLabelPicker.pickFromMany(
      [tokens.join(' ')],
      maxChars: 22,
    );
  }

  /// Lookup the lowercased first token of a zone label (for dedup above).
  String? _zoneFirstToken(String zoneId) {
    for (final z in zoneLabels) {
      if (z.id == zoneId) {
        final label = z.label.trim();
        if (label.isEmpty) return null;
        return label.split(RegExp(r'\s+')).first.toLowerCase();
      }
    }
    return null;
  }

  // ===========================================================================
  // 🗺️ ZONE LABELS — Auto-derived macro-region names (LOD 2 mappamondo)
  // ===========================================================================
  //
  // Pedagogical contract (§1981, §1961-1963):
  //   Zones are *emergent* from the student's spatial organization, not
  //   imposed. The label is the most frequent significant word from the
  //   student's own handwriting inside that spatial cluster-of-clusters.

  void _paintZoneLabels(Canvas canvas, double fade) {
    if (zoneLabels.isEmpty || fade < 0.01) return;

    // Upper clamp bumped from 16 → 36 — zone labels must remain readable
    // even at satellite-satellite zoom (< 0.07) where 16 would render
    // them as micro-text again.
    final inverseScale = (1.0 / canvasScale).clamp(2.0, 36.0);

    for (final zone in zoneLabels) {
      final display = zone.label.toUpperCase();
      if (display.isEmpty) continue;

      // Size proportional to cluster count — bigger subjects, bigger names.
      final magnitude = (zone.clusterCount.clamp(3, 30) - 3) / 27.0;
      final fontSize = 14.0 + magnitude * 6.0;

      final cacheKey =
          'zone_${display.hashCode}_${fontSize.toStringAsFixed(1)}';
      var tp = _cachedTitlePainters[cacheKey];
      if (tp == null) {
        tp = TextPainter(
          text: TextSpan(
            text: display,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        if (_cachedTitlePainters.length > 100) {
          _cachedTitlePainters.remove(_cachedTitlePainters.keys.first);
        }
        _cachedTitlePainters[cacheKey] = tp;
      }

      // Position the label OUTSIDE the zone bounds — just above the
      // top edge — so it never overlaps member clusters or their
      // monument pills. The centroid-based positioning used previously
      // routinely dropped the label on top of a central cluster when
      // the zone was spatially balanced, occluding content.
      // Gap (40 canvas units) stays constant at native scale; the
      // inverse-scale transform inside the pill render handles
      // perceptual size, so no per-zoom compensation needed here.
      const gapAboveBounds = 40.0;
      final screenCenter = Offset(
        zone.centroid.dx,
        zone.bounds.top - gapAboveBounds,
      );

      canvas.save();
      canvas.translate(screenCenter.dx, screenCenter.dy);
      // Multiplier 1.1: zone labels should be visually LARGER than monument
      // pills (they name whole subjects, not individual landmarks). Combined
      // with the 14–20pt base, this yields ~15–22pt at native screen size
      // regardless of LOD 2 zoom — readable at a glance, "continent name"
      // feel as specified in §1098.
      canvas.scale(inverseScale * 1.1);
      canvas.translate(-screenCenter.dx, -screenCenter.dy);

      // Soft diffuse glow behind the title — feels like a continent name
      // floating above the terrain.
      _softGlowPaint.color =
          Colors.white.withValues(alpha: 0.08 * fade);
      canvas.drawCircle(
        screenCenter,
        tp.width * 0.7,
        _softGlowPaint,
      );

      // Drop shadow for contrast against any color bg (cached separately
      // from the main title painter — same geometry, pre-faded black ink).
      // Alpha is baked at 0.65: at LOD 2 the enclosing _computeFade() is
      // always 1.0, so no per-frame alpha multiplier is needed.
      final shadowKey =
          'zone_sh_${display.hashCode}_${fontSize.toStringAsFixed(1)}';
      var shadowTp = _cachedTitlePainters[shadowKey];
      if (shadowTp == null) {
        shadowTp = TextPainter(
          text: TextSpan(
            text: display,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.65),
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        if (_cachedTitlePainters.length > 100) {
          _cachedTitlePainters.remove(_cachedTitlePainters.keys.first);
        }
        _cachedTitlePainters[shadowKey] = shadowTp;
      }
      shadowTp.paint(
        canvas,
        Offset(
          screenCenter.dx - shadowTp.width / 2 + 1.5,
          screenCenter.dy - shadowTp.height / 2 + 2.0,
        ),
      );

      // Main text
      tp.paint(
        canvas,
        Offset(
          screenCenter.dx - tp.width / 2,
          screenCenter.dy - tp.height / 2,
        ),
      );

      canvas.restore();
    }
  }

  // ===========================================================================
  // 🌍 GOD VIEW — Thematic super-nodes at extreme zoom-out
  // ===========================================================================

  void _paintGodView(Canvas canvas, double fade) {
    if (semanticController == null) return;
    // 🌐 META TIER (Tier 5) — on dense canvases (≥12 super-nodes) deep
    // god view (scale ≤ 0.13) renders meta-super-nodes ("continents")
    // instead of individual super-nodes, so 30 dots collapse to 5-8.
    // Sparse canvases keep the regular super-node rendering unchanged.
    final superNodes = semanticController!.effectiveSuperNodes(canvasScale);
    if (superNodes.isEmpty) return;
    if (fade < 0.01) return;

    // When the meta tier is active, two existing visual artifacts must
    // change:
    //  - The member-composition ring (one arc per memberClusterId) would
    //    produce 30+ micro-arcs unreadable as a single line. Skipped.
    //  - The gravity-lines block uses `memberToSuperNodeIndex` which is
    //    keyed on the *original* superNodes — indexing into the meta
    //    list with those indices would be wrong. Skipped at meta tier.
    final isMetaTier =
        !identical(superNodes, semanticController!.superNodes);

    final inverseScale = (1.0 / canvasScale).clamp(3.0, 32.0);
    final cMap = _buildClusterMap();

    for (final sn in superNodes) {
      final center = sn.centroid;

      // Radius proportional to total elements + member count
      final baseR = 35.0 + sn.totalElements.clamp(0, 100) * 0.5 +
          sn.memberCount * 8.0;
      final nodeRadius = baseR;

      // Blend color from member clusters
      Color blendColor = const Color(0xFF7EC8E3);
      int colorCount = 0;
      double r = 0, g = 0, b = 0;
      for (final mid in sn.memberClusterIds) {
        final cluster = cMap[mid];
        if (cluster != null) {
          final cc = _clusterColor(cluster);
          r += cc.r;
          g += cc.g;
          b += cc.b;
          colorCount++;
        }
      }
      if (colorCount > 0) {
        blendColor = Color.from(
            alpha: 1.0,
            red: r / colorCount, green: g / colorCount,
            blue: b / colorCount);
      }

      // 🌡️ FSRS STAGE PROPAGATION — worst-of stage across this super-node's
      // (or meta-super-node's) member clusters. Worst = lowest SrsStage.index
      // (fragile=0). When dominant stage is non-null, lerp the natural
      // zone-color blend toward the stage color with a moderate weight so
      // the area's identity is preserved but the urgency is communicated.
      // Untouched/missing entries are skipped (no contribution).
      if (clusterStages.isNotEmpty) {
        SrsStage? dominantStage;
        for (final mid in sn.memberClusterIds) {
          final s = clusterStages[mid];
          if (s == null) continue;
          if (dominantStage == null || s.index < dominantStage.index) {
            dominantStage = s;
            if (dominantStage == SrsStage.fragile) break; // can't get worse
          }
        }
        if (dominantStage != null) {
          blendColor = Color.lerp(blendColor, dominantStage.color, 0.35)!;
        }
      }

      // Breathing pulse
      final breath = math.sin(animationTime * 0.8 +
          center.dx * 0.001) * 0.5 + 0.5;

      // ── 1. Outer glow ──
      _softGlowPaint.color = blendColor.withValues(
        alpha: (0.12 + breath * 0.06) * fade,
      );
      canvas.drawCircle(center, nodeRadius + 15, _softGlowPaint);

      // ── 2. Fill ──
      final nodeRect = Rect.fromCircle(center: center, radius: nodeRadius);
      final gradient = RadialGradient(
        colors: [
          blendColor.withValues(alpha: 0.20 * fade),
          blendColor.withValues(alpha: 0.08 * fade),
        ],
      );
      _p
        ..style = PaintingStyle.fill
        ..shader = gradient.createShader(nodeRect)
        ..maskFilter = null;
      canvas.drawCircle(center, nodeRadius, _p);
      _p.shader = null;

      // ── 3. Border ──
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = blendColor.withValues(alpha: 0.50 * fade);
      canvas.drawCircle(center, nodeRadius, _p);

      // ── 4. 🎨 MEMBER COMPOSITION RING ──
      // Each segment colored by its member cluster type. Skipped at meta
      // tier — meta-super-nodes can carry 30+ member ids that would
      // produce a ring of micro-arcs visually indistinguishable from a
      // continuous line. The continent visual reads on its own without
      // the per-member segmentation.
      if (sn.memberCount > 1 && !isMetaTier) {
        final memberPulse = math.sin(animationTime * 1.5) * 0.5 + 0.5;
        final ringRadius = nodeRadius + 8 + memberPulse * 3;
        final sweepPerMember = 2 * math.pi / sn.memberClusterIds.length;
        final gapAngle = 0.08; // Small gap between segments

        for (int mi = 0; mi < sn.memberClusterIds.length; mi++) {
          final memberId = sn.memberClusterIds[mi];
          final memberCluster = cMap[memberId];
          final memberColor = memberCluster != null
              ? _clusterColor(memberCluster)
              : blendColor;
          final startAngle = -math.pi / 2 + mi * sweepPerMember + gapAngle / 2;
          final actualSweep = sweepPerMember - gapAngle;

          _reusePath.reset();
          _reusePath.addArc(
            Rect.fromCircle(center: center, radius: ringRadius),
            startAngle, actualSweep,
          );
          _p
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0
            ..strokeCap = StrokeCap.round
            ..color = memberColor.withValues(
              alpha: (0.35 + memberPulse * 0.15) * fade,
            );
          canvas.drawPath(_reusePath, _p);
        }
      }

      // ── 4.5 ✨ SHIMMER LOADING for pending AI themes ──
      final isPending = semanticController!.pendingGodViewAi.contains(sn.id);
      if (isPending) {
        final shimmerPhase = (animationTime * 1.5 +
            center.dx * 0.002) % (2.0 * math.pi);
        final shimmerX = math.cos(shimmerPhase) * nodeRadius * 0.8;
        final shimmerGradient = LinearGradient(
          begin: Alignment(-1.0 + shimmerX / nodeRadius, -0.5),
          end: Alignment(1.0 + shimmerX / nodeRadius, 0.5),
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.06 * fade),
            Colors.white.withValues(alpha: 0.15 * fade),
            Colors.white.withValues(alpha: 0.06 * fade),
            Colors.transparent,
          ],
          stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
        );
        _p
          ..style = PaintingStyle.fill
          ..shader = shimmerGradient.createShader(nodeRect);
        canvas.drawCircle(center, nodeRadius, _p);
        _p.shader = null;
      }

      // ── 5. Theme title ──
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(inverseScale * 0.5);
      canvas.translate(-center.dx, -center.dy);

      final themeName = semanticController!.superNodeThemes[sn.id];
      final title = themeName ??
          (sn.memberCount > 1
              ? '${sn.memberCount} gruppi'
              : semanticController!.semanticTitles[sn.memberClusterIds.first]
                  ?? 'Cluster');

      final titleCacheKey = '${sn.id}_god_$title';
      var tp = _cachedTitlePainters[titleCacheKey];
      if (tp == null) {
        tp = TextPainter(
          text: TextSpan(
            text: title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.90 * fade),
              fontSize: 14.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        tp.layout(maxWidth: nodeRadius * 2.0 / (inverseScale * 0.5) * 0.8);
        _cachedTitlePainters[titleCacheKey] = tp;
        if (_cachedTitlePainters.length > 120) {
          final keys = _cachedTitlePainters.keys.toList();
          for (int i = 0; i < 40; i++) {
            _cachedTitlePainters.remove(keys[i]);
          }
        }
      }
      tp.paint(canvas,
          Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

      // ── 6. Stats subtitle ──
      final subtitle = '${sn.memberCount} cluster • ${sn.totalElements} elem';
      final subCacheKey = '${sn.id}_godsub_$subtitle';
      var subTp = _cachedTitlePainters[subCacheKey];
      if (subTp == null) {
        subTp = TextPainter(
          text: TextSpan(
            text: subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45 * fade),
              fontSize: 9.0,
              fontWeight: FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        subTp.layout();
        _cachedTitlePainters[subCacheKey] = subTp;
      }
      subTp.paint(canvas,
          Offset(center.dx - subTp.width / 2,
              center.dy + (tp.height / 2) + 4));

      canvas.restore();
    }

    // ── 7. 🔗 GRAVITY LINES between super-nodes with shared connections ──
    // Picks the right pre-computed membership map: super-node tier uses
    // `memberToSuperNodeIndex`, meta tier uses `memberToMetaSuperNodeIndex`
    // (populated in `_computeMetaSuperNodes`). Both maps are clusterId →
    // index into the *currently rendered* node list (`superNodes` local),
    // so the same downstream code works for both tiers.
    if (superNodes.length > 1) {
      // 🚀 PERF: Use pre-computed membership map from controller
      final memberToSuperNode = isMetaTier
          ? semanticController!.memberToMetaSuperNodeIndex
          : semanticController!.memberToSuperNodeIndex;

      // Check existing connections for cross-super-node links
      final drawnPairs = <String>{};
      for (final conn in controller.connections) {
        final snA = memberToSuperNode[conn.sourceClusterId];
        final snB = memberToSuperNode[conn.targetClusterId];
        if (snA == null || snB == null || snA == snB) continue;

        final pairKey = snA < snB ? '$snA|$snB' : '$snB|$snA';
        if (!drawnPairs.add(pairKey)) continue; // Already drawn

        final a = superNodes[snA];
        final b = superNodes[snB];
        final midPt = Offset(
          (a.centroid.dx + b.centroid.dx) / 2,
          (a.centroid.dy + b.centroid.dy) / 2,
        );
        final dx = b.centroid.dx - a.centroid.dx;
        final dy = b.centroid.dy - a.centroid.dy;
        final perpX = -dy * 0.08;
        final perpY = dx * 0.08;
        final cp = Offset(midPt.dx + perpX, midPt.dy + perpY);

        // Gradient arc
        const _defaultGodColor = Color(0xFF7EC8E3);
        final colorA = cMap[a.memberClusterIds.first] != null
            ? _clusterColor(cMap[a.memberClusterIds.first]!)
            : _defaultGodColor;
        final colorB = cMap[b.memberClusterIds.first] != null
            ? _clusterColor(cMap[b.memberClusterIds.first]!)
            : _defaultGodColor;

        final gravBreath = math.sin(animationTime * 0.6) * 0.5 + 0.5;
        final gravAlpha = ((0.06 + gravBreath * 0.04) * fade).clamp(0.0, 0.25);

        // Soft glow pass
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
        const gravSteps = 16;
        for (int i = 0; i < gravSteps; i++) {
          final t0 = i / gravSteps;
          final t1 = (i + 1) / gravSteps;
          _p.color = Color.lerp(colorA, colorB, (t0 + t1) / 2)!
              .withValues(alpha: gravAlpha * 0.4);
          canvas.drawLine(
            _quadBezierPt(a.centroid, cp, b.centroid, t0),
            _quadBezierPt(a.centroid, cp, b.centroid, t1),
            _p,
          );
        }
        _p.maskFilter = null;

        // Main arc
        _p.strokeWidth = 2.0;
        for (int i = 0; i < gravSteps; i++) {
          final t0 = i / gravSteps;
          final t1 = (i + 1) / gravSteps;
          _p.color = Color.lerp(colorA, colorB, (t0 + t1) / 2)!
              .withValues(alpha: gravAlpha);
          canvas.drawLine(
            _quadBezierPt(a.centroid, cp, b.centroid, t0),
            _quadBezierPt(a.centroid, cp, b.centroid, t1),
            _p,
          );
        }
      }
    }
  }

  // ===========================================================================
  // SEMANTIC NODES — Clean circles with AI titles & stats (morph layer)
  // ===========================================================================

  void _paintSemanticNodes(Canvas canvas, double fade) {
    if (clusters.isEmpty || semanticController == null) return;
    if (fade < 0.01) return;

    // Inverse scale for text readability at extreme zoom-out
    final inverseScale = (1.0 / canvasScale).clamp(3.0, 16.0);

    // 🚀 PERF: Pre-compute loop invariants
    final textScale = inverseScale * 0.65;
    final badgeScale = inverseScale * 0.55;
    final importanceThreshold = semanticController!.importanceTopThreshold;
    final multiCluster = clusters.length > 2;
    final flashcardId = semanticController!.flashcardClusterId;

    // 🚀 PERF: Shadow color is cluster-independent — set once
    _shadowPaint.color = Colors.black.withValues(alpha: 0.12 * fade);

    // Collect connected clusters and count connections per cluster
    final connCounts = <String, int>{};
    for (final conn in controller.connections) {
      connCounts[conn.sourceClusterId] =
          (connCounts[conn.sourceClusterId] ?? 0) + 1;
      connCounts[conn.targetClusterId] =
          (connCounts[conn.targetClusterId] ?? 0) + 1;
    }

    for (final cluster in clusters) {
      final hasAiTitle = clusterTexts[cluster.id]?.isNotEmpty == true;
      if (cluster.strokeIds.length < 20 && !hasAiTitle) continue;

      final color = _clusterColor(cluster);
      final center = cluster.centroid;
      final stats = semanticController!.clusterStats[cluster.id];
      final connCount = connCounts[cluster.id] ?? 0;

      final importance = semanticController!.getSmoothedImportance(cluster.id);
      final isTopNode = importance >= importanceThreshold && multiCluster;
      // 🏛️ MONUMENT BOOST: clusters classified by MonumentResolver get
      // +20% padding and +20% glow so they read as visual capitals at
      // mappamondo scale (§22 §504-507: "i grossi nodi rossi in alto").
      // MonumentResolver eligibility (min degree 3 + threshold 0.45) is
      // stricter than isTopNode (importance percentile), so this is a
      // strict superset of star-badge nodes.
      final isMonument = monumentIds.contains(cluster.id);
      final monBoost = isMonument ? 1.20 : 1.0;

      // ── Node rect from actual cluster bounds ──
      final bounds = cluster.bounds;
      if (bounds.isEmpty || !bounds.isFinite) continue;
      final nodePadding = (10.0 + importance * 6.0) * inverseScale * monBoost;
      final shortSide = math.min(bounds.width + nodePadding * 2,
          bounds.height + nodePadding * 2);
      final cornerRadius = Radius.circular(
          (shortSide * 0.06).clamp(4.0 * inverseScale, 16.0 * inverseScale));
      final nodeRect = bounds.inflate(nodePadding);
      final nodeRRect = RRect.fromRectAndRadius(nodeRect, cornerRadius);

      // ── Breathing pulse for connected nodes ──
      final breathRRect = connCount > 0
          ? (() {
              final breathPhase = animationTime +
                  center.dx * 0.001 + center.dy * 0.001;
              final breathInflate =
                  (math.sin(breathPhase) * 0.03) * nodePadding;
              return breathInflate > 0.1
                  ? RRect.fromRectAndRadius(
                      nodeRect.inflate(breathInflate), cornerRadius)
                  : nodeRRect;
            })()
          : nodeRRect;

      // ── 0. Drop shadow ──
      canvas.drawRRect(
        breathRRect.shift(Offset(1.5 * inverseScale, 3.0 * inverseScale)),
        _shadowPaint,
      );

      // ── 1. Outer glow ──
      final glowInflate = (4.0 + importance * 8.0) * inverseScale * monBoost;
      _softGlowPaint.color = color.withValues(
          alpha: (0.10 + importance * 0.15 + (isMonument ? 0.08 : 0.0)) * fade);
      canvas.drawRRect(
        RRect.fromRectAndRadius(nodeRect.inflate(glowInflate), cornerRadius),
        _softGlowPaint,
      );

      // ── 2. Glass fill ──
      // 🚀 PERF: Only 2 colors, create shader directly on rect
      _p
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.06 * fade),
            color.withValues(alpha: 0.04 * fade),
          ],
        ).createShader(nodeRect)
        ..maskFilter = null;
      canvas.drawRRect(breathRRect, _p);
      _p.shader = null;

      // ── 3. Luminous border ──
      final borderWidth =
          (0.8 + importance * 1.5) * (inverseScale * 0.3).clamp(0.5, 2.5);
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..color = color.withValues(alpha: (0.30 + importance * 0.20) * fade);
      canvas.drawRRect(breathRRect, _p);

      // ── 4. Inner highlight ──
      // 🚀 PERF: White→transparent gradient is cluster-independent
      final highlightH = 3.0 * inverseScale;
      final hlRect = Rect.fromLTWH(
        nodeRect.left + cornerRadius.x,
        nodeRect.top,
        nodeRect.width - cornerRadius.x * 2,
        highlightH,
      );
      _p
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.18 * fade),
            Colors.transparent,
          ],
        ).createShader(hlRect);
      canvas.drawRect(hlRect, _p);
      _p.shader = null;

      // ── 5. Connection glow ring ──
      if (connCount >= 2) {
        // Fix 6: per-cluster phase shift so two neighbouring clusters
        // never pulse in sync. `% 628 / 100` → 0..6.28 rad ≈ 0..2π.
        final clusterPhase = (cluster.id.hashCode % 628) / 100.0;
        final glowPulse =
            math.sin(animationTime * 2.0 + connCount * 0.5 + clusterPhase)
                * 0.5 + 0.5;
        _softGlowPaint.color = color.withValues(
          alpha: (0.06 + glowPulse * 0.05) * fade,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              nodeRect.inflate(6 * inverseScale), cornerRadius),
          _softGlowPaint,
        );
      }

      // ── 5.2 Flashcard selection ring ──
      if (flashcardId == cluster.id) {
        final pulse = math.sin(animationTime * 3.0) * 0.3 + 0.7;
        _softGlowPaint.color = const Color(0xFF00E5FF).withValues(
          alpha: 0.20 * pulse * fade,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              nodeRect.inflate(14 * inverseScale), cornerRadius),
          _softGlowPaint,
        );
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = const Color(0xFF00E5FF).withValues(
            alpha: 0.45 * pulse * fade,
          );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              nodeRect.inflate(5 * inverseScale), cornerRadius),
          _p,
        );
      }

      // ── 5.5 Shimmer (only for pending AI) ──
      if (semanticController!.pendingAiRequests.contains(cluster.id)) {
        final shimmerPhase = (animationTime * 1.5 +
            center.dx * 0.002) % (2.0 * math.pi);
        final halfW = nodeRect.width / 2;
        final shimmerX = math.cos(shimmerPhase) * halfW * 0.8;
        _p
          ..style = PaintingStyle.fill
          ..shader = LinearGradient(
            begin: Alignment(-1.0 + shimmerX / halfW, -0.5),
            end: Alignment(1.0 + shimmerX / halfW, 0.5),
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: 0.06 * fade),
              Colors.white.withValues(alpha: 0.14 * fade),
              Colors.white.withValues(alpha: 0.06 * fade),
              Colors.transparent,
            ],
            stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
          ).createShader(nodeRect);
        canvas.drawRRect(breathRRect, _p);
        _p.shader = null;
      }

      // =================================================================
      // ── 6. FROSTED TITLE BAR ──
      // =================================================================

      final (displayTitle, titleOpacity) =
          semanticController!.getCrossfadeTitle(cluster.id);
      final icon = semanticController!.contentIcon(cluster.id);

      // 🚀 PERF: Cache title TextPainter (layout is the expensive part)
      final titleCacheKey = '${cluster.id}_sembar_$displayTitle';
      var titleTp = _cachedTitlePainters[titleCacheKey];
      final maxTitleW = nodeRect.width / textScale * 0.90;
      final clampedMaxW = maxTitleW.clamp(50.0, 280.0);
      if (titleTp == null) {
        titleTp = TextPainter(
          text: TextSpan(
            text: displayTitle,
            style: TextStyle(
              // 🔧 2026-05-18 readability fix: alpha is `0.95 * titleOpacity`
              // (no `fade` multiplier). Matches the bar-background change a
              // few lines above — the whole `_paintSemanticNodes` pass is
              // gated by `semanticFade > 0.01` upstream, so we don't need
              // to smoothly fade individual atoms. Keeping alpha high
              // ensures white-on-dark-navy contrast stays > 7:1 even during
              // the god-view crossfade window.
              color: Colors.white.withValues(alpha: 0.95 * titleOpacity),
              fontSize: 12.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              height: 1.25,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: clampedMaxW);
        _cachedTitlePainters[titleCacheKey] = titleTp;
        if (_cachedTitlePainters.length > 150) {
          final keys = _cachedTitlePainters.keys.toList();
          for (int i = 0; i < 50; i++) {
            _cachedTitlePainters.remove(keys[i]);
          }
        }
      }

      // Title bar dimensions
      final barH = (titleTp.height + 10) * textScale;
      final barRect = Rect.fromLTWH(
        nodeRect.left,
        nodeRect.top - barH - 2.0 * inverseScale,
        nodeRect.width,
        barH,
      );
      final barRRect = RRect.fromRectAndRadius(barRect, cornerRadius);

      // Bar background — solid dark, contrast-floor.
      //
      // 🔧 2026-05-18 readability fix: previous formula
      //   `Color.lerp(color, #0D1117, 0.75).withValues(alpha: 0.85 * fade)`
      // produced a low-contrast bar at dezoom: when `fade` drops to ~0.6
      // during the god-view crossfade (scale 0.13→0.10), bar effective
      // alpha falls to 0.51 → bar washes out to mid-gray when composed
      // over the white paper, and white title text at 0.92*0.6=0.55
      // alpha becomes nearly invisible (contrast ratio ~2:1).
      //
      // New formula:
      //  • Solid dark navy independent of cluster colour (no lerp with a
      //    pastel that washes out at low alpha).
      //  • Alpha floored at 0.85 — independent of `fade`. The whole
      //    `_paintSemanticNodes` pass is already gated by
      //    `semanticFade > 0.01` at the caller (knowledge_flow_painter
      //    line 388), so the entire card disappears wholesale below
      //    that threshold; we don't need to fade the bar smoothly to
      //    achieve the god-view transition.
      _p
        ..style = PaintingStyle.fill
        ..shader = null
        ..maskFilter = null
        ..color = const Color(0xFF1A2230).withValues(alpha: 0.92);
      canvas.drawRRect(barRRect, _p);

      // Bar border — kept tied to cluster colour for identity, but with
      // a higher floor so the seam against the body stays visible.
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = color.withValues(alpha: 0.55);
      canvas.drawRRect(barRRect, _p);

      // ── Paint icon + title inside bar ──
      canvas.save();
      final barCenter = barRect.center;
      canvas.translate(barCenter.dx, barCenter.dy);
      canvas.scale(textScale);
      canvas.translate(-barCenter.dx, -barCenter.dy);

      // 🚀 PERF: Icon cached via _cachedTitlePainters
      final iconCacheKey = '${cluster.id}_icon_$icon';
      var iconTp = _cachedTitlePainters[iconCacheKey];
      if (iconTp == null) {
        iconTp = TextPainter(
          text: TextSpan(text: icon, style: TextStyle(
            fontSize: 10.0, height: 1.0,
            // 🔧 2026-05-18: removed `* fade` (see title-text comment).
            color: Colors.white.withValues(alpha: 0.80),
          )),
          textDirection: TextDirection.ltr,
        )..layout();
        _cachedTitlePainters[iconCacheKey] = iconTp;
      }

      final totalContentW = iconTp.width + 4.0 + titleTp.width;
      final contentStartX = barCenter.dx - totalContentW / 2;

      iconTp.paint(canvas, Offset(
        contentStartX,
        barCenter.dy - iconTp.height / 2,
      ));
      titleTp.paint(canvas, Offset(
        contentStartX + iconTp.width + 4.0,
        barCenter.dy - titleTp.height / 2,
      ));

      // Previous title (fading out) — only during crossfade transitions
      final previousTitle = semanticController!.previousTitles[cluster.id];
      if (previousTitle != null && titleOpacity < 1.0) {
        // 🚀 PERF: Cache previous title too
        final prevCacheKey = '${cluster.id}_semprev_$previousTitle';
        var prevTp = _cachedTitlePainters[prevCacheKey];
        if (prevTp == null) {
          prevTp = TextPainter(
            text: TextSpan(
              text: previousTitle,
              style: TextStyle(
                // 🔧 2026-05-18: removed `* fade` for the same contrast
                // reason as the current-title text above.
                color: Colors.white.withValues(
                    alpha: 0.85 * (1.0 - titleOpacity)),
                fontSize: 12.0,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                height: 1.25,
              ),
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            maxLines: 2,
            ellipsis: '…',
          )..layout(maxWidth: clampedMaxW);
          _cachedTitlePainters[prevCacheKey] = prevTp;
        }
        prevTp.paint(canvas, Offset(
          contentStartX + iconTp.width + 4.0,
          barCenter.dy - prevTp.height / 2,
        ));
      }

      // 2026-05-17: ⭐ star badge for top-20% importance rimosso. Stesso
      // ragionamento delle golden shimmer particles: senza affordance
      // esplicativa, l'utente vede "stelline gialle" e non capisce.
      // L'importance dei cluster è già comunicata via node padding +
      // glow boost (importance-modulated) — niente badge esplicito.

      canvas.restore();

      // ── 7. Stats mini-badges ──
      if (stats != null && (stats.totalElements > 1 || connCount > 0)) {
        _paintSemanticStatBadges(
          canvas, center, nodeRect, stats, connCount, color, fade,
          inverseScale, badgeScale,
        );
      }
    }
  }

  /// Paint stat badges along the bottom edge of a semantic node.
  void _paintSemanticStatBadges(
    Canvas canvas,
    Offset center,
    Rect nodeRect,
    ClusterStats stats,
    int connCount,
    Color color,
    double fade,
    double inverseScale,
    double badgeScale,
  ) {
    final badges = <(String, String)>[]; // (icon, value)
    if (stats.strokeCount > 0) {
      badges.add(('✏', '${stats.strokeCount}'));
    }
    if (stats.shapeCount > 0) {
      badges.add(('◆', '${stats.shapeCount}'));
    }
    if (stats.textCount > 0) {
      badges.add(('T', '${stats.textCount}'));
    }
    if (stats.imageCount > 0) {
      badges.add(('🖼', '${stats.imageCount}'));
    }
    if (connCount > 0) {
      badges.add(('⟷', '$connCount'));
    }
    if (badges.isEmpty) return;

    // 🚀 PERF: Compute HSL once for all badges, not per-badge
    final badgeHsl = HSLColor.fromColor(color);
    final badgeDark = badgeHsl.withLightness(0.20).toColor();
    final badgeTextColor = badgeDark.withValues(alpha: 0.90 * fade);
    final pillBgColor = Color.lerp(color, const Color(0xFF0D1117), 0.6)!
        .withValues(alpha: 0.80 * fade);
    final pillBorderColor = color.withValues(alpha: 0.35 * fade);

    // 2026-05-17: i pill stat sono renderizzati con `canvas.scale(badgeScale)`
    // attorno al loro centro (badgeScale ≈ 2.75× a scale 0.20), quindi le
    // larghezze "visibili" sono pillW * badgeScale. L'avanzamento X deve
    // usare la larghezza scalata, altrimenti pill adiacenti si sovrappongono.
    final badgeSpacing = 6.0 * inverseScale;
    // 🚀 PERF: Measure using cached TextPainters
    double totalW = 0;
    final widths = <double>[]; // scaled (visible) widths
    final heights = <double>[]; // scaled (visible) heights
    final pillWsUnscaled = <double>[]; // raw pillW for RRect draw
    final pillHsUnscaled = <double>[];
    final painters = <TextPainter>[];

    for (final badge in badges) {
      final text = '${badge.$1} ${badge.$2}';
      final cacheKey = '__badge_${text}__';
      var tp = _cachedTitlePainters[cacheKey];
      if (tp == null) {
        tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: badgeTextColor,
              fontSize: 11.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        _cachedTitlePainters[cacheKey] = tp;
      }
      final pillW = tp.width + 10;
      final pillH = tp.height + 6;
      painters.add(tp);
      pillWsUnscaled.add(pillW);
      pillHsUnscaled.add(pillH);
      widths.add(pillW * badgeScale);
      heights.add(pillH * badgeScale);
      totalW += pillW * badgeScale;
    }
    totalW += (painters.length - 1) * badgeSpacing;

    var x = center.dx - totalW / 2;
    final y = nodeRect.bottom + 6.0 * inverseScale;

    for (int i = 0; i < painters.length; i++) {
      final visibleW = widths[i]; // pillW * badgeScale
      final visibleH = heights[i];
      final pillW = pillWsUnscaled[i];
      final pillH = pillHsUnscaled[i];
      // Posiziona il pill nello spazio "visibile" (scalato), poi applica
      // canvas.scale(badgeScale) attorno al suo centro per disegnare i
      // contenuti raw a dimensione corretta.
      final badgeCenter = Offset(x + visibleW / 2, y + visibleH / 2);

      canvas.save();
      canvas.translate(badgeCenter.dx, badgeCenter.dy);
      canvas.scale(badgeScale);
      canvas.translate(-badgeCenter.dx, -badgeCenter.dy);

      final pillRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: badgeCenter, width: pillW, height: pillH),
        Radius.circular(pillH / 2),
      );

      _p
        ..style = PaintingStyle.fill
        ..shader = null
        ..maskFilter = null
        ..color = pillBgColor;
      canvas.drawRRect(pillRect, _p);
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = pillBorderColor;
      canvas.drawRRect(pillRect, _p);

      painters[i].paint(canvas, Offset(
        badgeCenter.dx - painters[i].width / 2,
        badgeCenter.dy - painters[i].height / 2,
      ));

      canvas.restore();
      x += visibleW + badgeSpacing;
    }
  }

  // ===========================================================================
  // 🎬 CINEMATIC FLIGHT — Enhanced visual effects during camera flights
  // ===========================================================================

  void _paintFlightEffects(Canvas canvas, Size size, double fade) {
    final cMap = _buildClusterMap();
    final t = flightProgress;

    // Global intensity: peaks at midpoint of flight (sine wave)
    final glowIntensity = math.sin(t * math.pi) * 0.7;

    // ── 1. CONNECTION-SPECIFIC GLOW ──
    // Only the active connection glows (not all connections)
    if (glowIntensity > 0.01 &&
        flightSourceClusterId != null &&
        flightTargetClusterId != null) {
      // Find the active connection
      for (final conn in controller.connections) {
        final isActive =
            (conn.sourceClusterId == flightSourceClusterId &&
             conn.targetClusterId == flightTargetClusterId) ||
            (conn.sourceClusterId == flightTargetClusterId &&
             conn.targetClusterId == flightSourceClusterId);
        if (!isActive) continue;

        final src = cMap[conn.sourceClusterId];
        final tgt = cMap[conn.targetClusterId];
        if (src == null || tgt == null) continue;

        final srcPt = src.centroid;
        final tgtPt = tgt.centroid;
        final cp = controller.getControlPoint(srcPt, tgtPt, conn.curveStrength);
        final connColor = conn.color;

        // Outer glow — wide, diffuse
        final glowPath = Path()
          ..moveTo(srcPt.dx, srcPt.dy)
          ..quadraticBezierTo(cp.dx, cp.dy, tgtPt.dx, tgtPt.dy);
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18.0 + glowIntensity * 12.0
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14.0)
          ..shader = null
          ..color = connColor.withValues(alpha: glowIntensity * 0.30 * fade);
        canvas.drawPath(glowPath, _p);

        // Core glow — brighter, narrower
        _p
          ..strokeWidth = 6.0 + glowIntensity * 4.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
          ..color = connColor.withValues(alpha: glowIntensity * 0.50 * fade);
        canvas.drawPath(glowPath, _p);
        _p.maskFilter = null;

        // ── 2. TRAIL PARTICLES ──
        // Multiple sparks traveling along the connection in formation
        const sparkCount = 5;
        for (int i = 0; i < sparkCount; i++) {
          final sparkPhase = (t * 1.8 + i * 0.18) % 1.0;
          final sparkPt = controller.pointOnQuadBezier(
            srcPt, cp, tgtPt, sparkPhase,
          );

          // Sine-wave shimmer perpendicular to path
          final pathDx = tgtPt.dx - srcPt.dx;
          final pathDy = tgtPt.dy - srcPt.dy;
          final pathLen = math.sqrt(pathDx * pathDx + pathDy * pathDy);
          final perpDx = pathLen > 0 ? -pathDy / pathLen : 0.0;
          final perpDy = pathLen > 0 ? pathDx / pathLen : 0.0;
          final shimmer = math.sin(sparkPhase * math.pi * 4 + i * 1.2) * 6.0;
          final shimmerPt = Offset(
            sparkPt.dx + perpDx * shimmer,
            sparkPt.dy + perpDy * shimmer,
          );

          // Spark brightness fades at start/end of path
          final sparkAlpha = math.sin(sparkPhase * math.pi) * glowIntensity;
          final sparkRadius = 3.0 + glowIntensity * 3.0 - i * 0.3;

          // Spark core (bright white)
          _p
            ..style = PaintingStyle.fill
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0)
            ..color = Colors.white.withValues(
              alpha: (sparkAlpha * 0.7 * fade).clamp(0.0, 1.0),
            );
          canvas.drawCircle(shimmerPt, sparkRadius.clamp(1.0, 8.0), _p);

          // Spark halo (colored)
          _p
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0)
            ..color = connColor.withValues(
              alpha: (sparkAlpha * 0.4 * fade).clamp(0.0, 1.0),
            );
          canvas.drawCircle(shimmerPt, sparkRadius * 2.0, _p);
          _p.maskFilter = null;
        }

        // ── Leading spark — brightest point at flight progress ──
        final leadPt = controller.pointOnQuadBezier(srcPt, cp, tgtPt, t);
        _p
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0)
          ..color = Colors.white.withValues(
            alpha: (glowIntensity * 0.85 * fade).clamp(0.0, 1.0),
          );
        canvas.drawCircle(leadPt, 5.0 + glowIntensity * 4.0, _p);
        _p
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16.0)
          ..color = connColor.withValues(
            alpha: (glowIntensity * 0.45 * fade).clamp(0.0, 1.0),
          );
        canvas.drawCircle(leadPt, 12.0 + glowIntensity * 8.0, _p);
        _p.maskFilter = null;

        break; // Only process the active connection
      }
    }

    // ── 3. DEPTH-OF-FIELD — Darken non-involved clusters ──
    if (glowIntensity > 0.05 &&
        flightSourceClusterId != null &&
        flightTargetClusterId != null) {
      final dofAlpha = (glowIntensity * 0.35).clamp(0.0, 0.3);
      for (final cluster in clusters) {
        if (cluster.id == flightSourceClusterId ||
            cluster.id == flightTargetClusterId) {
          continue; // Skip source and target
        }
        // Dark overlay on non-involved cluster bounds
        final bounds = cluster.bounds.inflate(10.0);
        final dofRRect = RRect.fromRectAndRadius(
          bounds, const Radius.circular(12.0),
        );
        _p
          ..style = PaintingStyle.fill
          ..shader = null
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0)
          ..color = const Color(0xFF0D1117).withValues(
            alpha: dofAlpha * fade,
          );
        canvas.drawRRect(dofRRect, _p);
        _p.maskFilter = null;
      }
    }

    // ── 4. RADIAL VIGNETTE — Darkened edges during hyper-jump ──
    // Active during ascent/transit phases (0-2) at low zoom
    if (flightPhase <= 2 && canvasScale < 0.15) {
      final vignetteAlpha = (0.35 * glowIntensity).clamp(0.0, 0.28);
      if (vignetteAlpha > 0.01) {
        final viewportRect = Rect.fromLTWH(0, 0, size.width, size.height);
        final center = viewportRect.center;
        final radius = viewportRect.longestSide * 0.65;

        // Use connection color for vignette tint
        final vignetteColor = (flightSourceClusterId != null)
            ? controller.connections
                .where((c) =>
                    c.sourceClusterId == flightSourceClusterId &&
                    c.targetClusterId == flightTargetClusterId)
                .firstOrNull?.color ?? Colors.black
            : Colors.black;
        final darkTint = Color.lerp(vignetteColor, Colors.black, 0.85)!;

        _p
          ..style = PaintingStyle.fill
          ..shader = RadialGradient(
            colors: [
              Colors.transparent,
              darkTint.withValues(alpha: vignetteAlpha * 0.5),
              darkTint.withValues(alpha: vignetteAlpha),
            ],
            stops: const [0.35, 0.7, 1.0],
          ).createShader(
            Rect.fromCircle(center: center, radius: radius),
          );
        canvas.drawRect(viewportRect, _p);
        _p.shader = null;
      }
    }

    // ── 5. STAR-FIELD — Streaking dots at satellite zoom (hyper-jump) ──
    if (canvasScale < 0.12 && glowIntensity > 0.05) {
      final starCount = 30;
      final starSeed = (animationTime * 100).toInt();
      for (int i = 0; i < starCount; i++) {
        // Deterministic pseudo-random positions using simple hash
        final hash = (i * 2654435761 + starSeed) & 0xFFFFFFFF;
        final fx = (hash & 0xFFFF) / 65535.0;
        final fy = ((hash >> 16) & 0xFFFF) / 65535.0;

        // Stars move outward from center based on flight progress
        final cx = size.width / 2;
        final cy = size.height / 2;
        final starDx = (fx - 0.5) * size.width * 2.0;
        final starDy = (fy - 0.5) * size.height * 2.0;
        final expansion = 0.3 + t * 0.7; // Expand outward with progress
        final sx = cx + starDx * expansion;
        final sy = cy + starDy * expansion;

        // Only draw stars inside the viewport
        if (sx < -10 || sx > size.width + 10 || sy < -10 || sy > size.height + 10) {
          continue;
        }

        // Streak length proportional to speed
        final streakLen = glowIntensity * 8.0;
        final angle = math.atan2(sy - cy, sx - cx);
        final startX = sx - math.cos(angle) * streakLen;
        final startY = sy - math.sin(angle) * streakLen;

        final starAlpha = (glowIntensity * 0.4 * fade * (1.0 - (i / starCount) * 0.5))
            .clamp(0.0, 0.5);
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..maskFilter = null
          ..shader = null
          ..color = Colors.white.withValues(alpha: starAlpha);
        canvas.drawLine(Offset(startX, startY), Offset(sx, sy), _p);
      }
    }

    // ── 6. SPEED LINES — Radial streaks during fast transit ──
    if (flightPhase == 2 && glowIntensity > 0.2) {
      final lineCount = 16;
      final cx = size.width / 2;
      final cy = size.height / 2;
      final maxLen = size.longestSide * 0.35;

      for (int i = 0; i < lineCount; i++) {
        final angle = (i / lineCount) * math.pi * 2 + t * 1.5;
        final innerR = size.shortestSide * 0.25;
        final outerR = innerR + maxLen * glowIntensity;

        final x1 = cx + math.cos(angle) * innerR;
        final y1 = cy + math.sin(angle) * innerR;
        final x2 = cx + math.cos(angle) * outerR;
        final y2 = cy + math.sin(angle) * outerR;

        final lineAlpha = (glowIntensity * 0.15 * fade).clamp(0.0, 0.2);
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0)
          ..shader = null
          ..color = Colors.white.withValues(alpha: lineAlpha);
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), _p);
      }
      _p.maskFilter = null;
    }

    // ── 7. LANDING PULSE — Expanding ring at target ──
    if (landingPulseProgress > 0.0 && landingPulseProgress < 1.0) {
      final pulseT = landingPulseProgress;
      final eased = Curves.easeOut.transform(pulseT);
      final maxRadius = 80.0 + 60.0 * eased;
      final pulseAlpha = (1.0 - pulseT) * 0.5 * fade;

      // Find the connection color for pulse tint
      Color pulseColor = const Color(0xFF4FC3F7); // default cyan
      if (flightSourceClusterId != null && flightTargetClusterId != null) {
        pulseColor = controller.connections
            .where((c) =>
                (c.sourceClusterId == flightSourceClusterId &&
                 c.targetClusterId == flightTargetClusterId) ||
                (c.sourceClusterId == flightTargetClusterId &&
                 c.targetClusterId == flightSourceClusterId))
            .firstOrNull?.color ?? pulseColor;
      }

      // Outer ring
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0 - eased * 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0)
        ..shader = null
        ..color = pulseColor.withValues(alpha: pulseAlpha.clamp(0.0, 1.0));
      canvas.drawCircle(landingPulseCenter, maxRadius, _p);

      // Inner fill (subtle)
      _p
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0)
        ..color = pulseColor.withValues(
          alpha: (pulseAlpha * 0.15).clamp(0.0, 1.0),
        );
      canvas.drawCircle(landingPulseCenter, maxRadius * 0.7, _p);
      _p.maskFilter = null;
    }

    // ── 8. CHROMATIC ABERRATION — Color fringe at edges during speed ──
    if (flightPhase == 2 && glowIntensity > 0.15) {
      final aberrationAlpha = (glowIntensity * 0.12 * fade).clamp(0.0, 0.15);
      final stripWidth = 3.0 + glowIntensity * 4.0;

      // Red fringe on leading edge (right side)
      _p
        ..style = PaintingStyle.fill
        ..shader = null
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
        ..color = const Color(0xFFFF4444).withValues(alpha: aberrationAlpha);
      canvas.drawRect(
        Rect.fromLTWH(size.width - stripWidth, 0, stripWidth, size.height),
        _p,
      );

      // Cyan fringe on trailing edge (left side)
      _p.color = const Color(0xFF44FFFF).withValues(alpha: aberrationAlpha);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, stripWidth, size.height),
        _p,
      );

      // Top/bottom subtle fringe
      _p
        ..color = const Color(0xFF8844FF).withValues(
          alpha: (aberrationAlpha * 0.5).clamp(0.0, 0.1),
        );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, stripWidth * 0.7),
        _p,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - stripWidth * 0.7, size.width, stripWidth * 0.7),
        _p,
      );
      _p.maskFilter = null;
    }
  }

  @override
  bool shouldRepaint(KnowledgeFlowPainter oldDelegate) {
    // 🚀 P99 FIX: Suppress ALL repaints during active pan/zoom.
    // The Transform widget handles visual movement via GPU compositing.
    // The raster cache from the last idle frame persists = 0ms raster cost.
    // On gesture END (isPanning: true→false), the state change triggers
    // a full repaint at the correct scale/LOD.
    if (isPanning && oldDelegate.isPanning) return false;

    // Gesture boundary: isPanning changed → force repaint
    if (isPanning != oldDelegate.isPanning) return true;

    return clusters != oldDelegate.clusters ||
        canvasScale != oldDelegate.canvasScale ||
        enabled != oldDelegate.enabled ||
        animationTime != oldDelegate.animationTime ||
        dragSourcePoint != oldDelegate.dragSourcePoint ||
        dragCurrentPoint != oldDelegate.dragCurrentPoint ||
        snapTargetClusterId != oldDelegate.snapTargetClusterId ||
        selectedConnectionId != oldDelegate.selectedConnectionId ||
        semanticMorphProgress != oldDelegate.semanticMorphProgress ||
        flightProgress != oldDelegate.flightProgress ||
        flightSourceClusterId != oldDelegate.flightSourceClusterId ||
        landingPulseProgress != oldDelegate.landingPulseProgress ||
        // FSRS stage propagation: identity check (cluster screen rebuilds
        // the map only on signature change in `_fsrsClusterStageList`).
        !identical(clusterStages, oldDelegate.clusterStages);
  }
}
