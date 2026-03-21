import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../reflow/content_cluster.dart';
import '../../reflow/knowledge_connection.dart';
import '../../reflow/knowledge_flow_controller.dart';
import '../../reflow/connection_suggestion_engine.dart';
import '../../reflow/semantic_morph_controller.dart';

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

  /// 🔤 Recognized text per cluster (from DigitalInk + _clusterTextCache)
  final Map<String, String> clusterTexts;

  /// ✨ Animation time (seconds) for breathing + particle effects
  final double animationTime;

  /// 🔵 Currently selected connection (for highlight effect)
  final String? selectedConnectionId;

  /// 🧠 SEMANTIC MORPHING: morph progress (0.0 = ink, 1.0 = semantic)
  final double semanticMorphProgress;

  /// 🧠 SEMANTIC MORPHING: controller with titles and stats
  final SemanticMorphController? semanticController;

  /// ✂️ SPACE-SPLIT: Split line Y position (canvas space). null = no split.
  final double? spaceSplitLineY;

  /// ✂️ SPACE-SPLIT: Spread progress (0.0 = just started, 1.0 = full spread).
  final double spaceSplitSpreadProgress;

  /// ✂️ SPACE-SPLIT: Ghost displacements per cluster (for preview rendering).
  final Map<String, Offset> spaceSplitGhostDisplacements;

  /// ✂️ SPACE-SPLIT: Whether this is a horizontal split (↔) vs vertical (↕).
  final bool spaceSplitIsHorizontal;

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
    this.animationTime = 0.0,
    this.selectedConnectionId,
    this.semanticMorphProgress = 0.0,
    this.semanticController,
    this.spaceSplitLineY,
    this.spaceSplitSpreadProgress = 0.0,
    this.spaceSplitGhostDisplacements = const {},
    this.spaceSplitIsHorizontal = false,
    this.flightProgress = 0.0,
    this.flightPhase = -1,
    this.flightSourceClusterId,
    this.flightTargetClusterId,
    this.landingPulseProgress = 0.0,
    this.landingPulseCenter = Offset.zero,
    this.audioHighlightStrokeId,
    this.audioHighlightConnectionId,
    this.audioHighlightIntensity = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled || !controller.enabled) return;
    if (clusters.isEmpty && controller.connections.isEmpty) return;

    final lod = _getLodLevel();
    final fade = _computeFade();

    // 🧠 SEMANTIC MORPHING: When morph is active, overlay semantic nodes
    final morphT = semanticMorphProgress.clamp(0.0, 1.0);
    final hasMorph = morphT > 0.01 && semanticController != null;

    if (lod == 0) {
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

    // Render order: network glow → halos → cluster visuals → underlines → connections → badges → drag
    final lod2Fade = _computeLod2Fade();
    if (lod2Fade > 0.01) {
      _paintNetworkGlow(canvas, fade * lod2Fade);
    }

    // LOD 2: Cluster grouping halos for nearby clusters
    if (lod == 2) {
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

    _paintWordUnderlines(canvas, fade);
    _paintConnections(canvas, lod, fade);
    _paintGhostConnectionsDashed(canvas, fade);

    // 📍 Connection count badges (LOD 1-2)
    _paintConnectionBadges(canvas, lod, fade);

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
    if (lod == 2) {
      _paintNetworkStats(canvas);
    }

    // 🎬 CINEMATIC FLIGHT: Speed-glow + vignette during camera flight
    if (flightProgress > 0.01 && flightProgress < 0.99) {
      _paintFlightEffects(canvas, size, fade);
    }

    // ✂️ SPACE-SPLIT: Draw split line indicator
    if (spaceSplitLineY != null && spaceSplitSpreadProgress > 0.01) {
      _paintSplitLine(canvas, size);
      // Ghost cluster outlines at displaced positions
      if (spaceSplitGhostDisplacements.isNotEmpty) {
        _paintGhostClusters(canvas);
      }
    }
  }

  int _getLodLevel() {
    if (canvasScale > _lodLevel1Max) return 0;
    if (canvasScale > _lodLevel1Min) return 1;
    return 2;
  }

  // ===========================================================================
  // ✂️ SPACE-SPLIT LINE INDICATOR
  // ===========================================================================

  /// Paints a breathing dashed line with animated directional arrows.
  /// Supports both horizontal (Y-axis) and vertical (X-axis) split lines.
  void _paintSplitLine(Canvas canvas, Size size) {
    final pos = spaceSplitLineY!;
    final progress = spaceSplitSpreadProgress;
    final alpha = (progress * 255).clamp(0, 255).toInt();
    final time = animationTime;
    final isH = spaceSplitIsHorizontal;

    const extent = 50000.0;

    // ── Breathing pulse: opacity oscillates gently ──
    final breathe = 0.7 + 0.3 * math.sin(time * 3.0);
    final breathAlpha = (alpha * breathe).toInt().clamp(0, 255);

    // ── Outer glow (diffuse) ──
    _p
      ..color = Color.fromARGB(breathAlpha ~/ 3, 100, 180, 255)
      ..strokeWidth = 14.0 / canvasScale
      ..style = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10.0 / canvasScale);
    if (isH) {
      canvas.drawLine(Offset(pos, -extent), Offset(pos, extent), _p);
    } else {
      canvas.drawLine(Offset(-extent, pos), Offset(extent, pos), _p);
    }

    // ── Core dashed line ──
    final dashLen = 24.0 / canvasScale;
    final gapLen = 12.0 / canvasScale;
    final lineWidth = 2.5 / canvasScale;
    _p
      ..color = Color.fromARGB(breathAlpha, 130, 200, 255)
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round
      ..maskFilter = null;

    // Draw dashes with animated offset (scrolling effect)
    final dashOffset = (time * 40.0 / canvasScale) % (dashLen + gapLen);
    for (double t = -extent - dashOffset; t < extent; t += dashLen + gapLen) {
      final start = t;
      final end = math.min(t + dashLen, extent);
      if (isH) {
        canvas.drawLine(Offset(pos, start), Offset(pos, end), _p);
      } else {
        canvas.drawLine(Offset(start, pos), Offset(end, pos), _p);
      }
    }

    // ── Animated directional arrows (drift + pulse) ──
    final arrowSize = 8.0 / canvasScale;
    final arrowSpacing = 180.0 / canvasScale;
    final arrowAlpha = (breathAlpha * 0.7).toInt();
    // Drift: arrows slowly move in the push direction
    final drift = math.sin(time * 2.0) * arrowSize * 0.6;
    // Pulse scale
    final pulse = 1.0 + 0.15 * math.sin(time * 4.0);
    final scaledArrow = arrowSize * pulse;

    _p
      ..color = Color.fromARGB(arrowAlpha, 130, 200, 255)
      ..style = PaintingStyle.fill
      ..maskFilter = null;

    for (double a = -extent; a < extent; a += arrowSpacing) {
      if (isH) {
        // Arrows pointing RIGHT (+X)
        final path = Path()
          ..moveTo(pos + scaledArrow * 0.5 + drift, a - scaledArrow)
          ..lineTo(pos + scaledArrow * 0.5 + drift, a + scaledArrow)
          ..lineTo(pos + scaledArrow * 2.5 + drift, a)
          ..close();
        canvas.drawPath(path, _p);
        // Arrows pointing LEFT (-X)
        final path2 = Path()
          ..moveTo(pos - scaledArrow * 0.5 - drift, a - scaledArrow)
          ..lineTo(pos - scaledArrow * 0.5 - drift, a + scaledArrow)
          ..lineTo(pos - scaledArrow * 2.5 - drift, a)
          ..close();
        canvas.drawPath(path2, _p);
      } else {
        // Arrows pointing DOWN (+Y)
        final path = Path()
          ..moveTo(a - scaledArrow, pos + scaledArrow * 0.5 + drift)
          ..lineTo(a + scaledArrow, pos + scaledArrow * 0.5 + drift)
          ..lineTo(a, pos + scaledArrow * 2.5 + drift)
          ..close();
        canvas.drawPath(path, _p);
        // Arrows pointing UP (-Y)
        final path2 = Path()
          ..moveTo(a - scaledArrow, pos - scaledArrow * 0.5 - drift)
          ..lineTo(a + scaledArrow, pos - scaledArrow * 0.5 - drift)
          ..lineTo(a, pos - scaledArrow * 2.5 - drift)
          ..close();
        canvas.drawPath(path2, _p);
      }
    }
  }

  /// ✂️ Paints ghost cluster silhouettes at displaced positions.
  ///
  /// Instead of a plain rectangle, draws the individual element bounds
  /// within each cluster as smaller translucent rects — approximating
  /// the stroke layout ("silhouette").
  void _paintGhostClusters(Canvas canvas) {
    final alpha = (spaceSplitSpreadProgress * 160).clamp(0, 160).toInt();
    final pulse = 0.85 + 0.15 * math.sin(animationTime * 3.5);
    final pulseAlpha = (alpha * pulse).toInt().clamp(0, 180);

    for (final cluster in clusters) {
      final displacement = spaceSplitGhostDisplacements[cluster.id];
      if (displacement == null || displacement == Offset.zero) continue;

      final ghostBounds = cluster.bounds.shift(displacement);
      final r = Radius.circular(8.0 / canvasScale);

      // Outer ghost outline (dashed feel via reduced opacity)
      _p
        ..color = Color.fromARGB(pulseAlpha, 130, 200, 255)
        ..strokeWidth = 1.5 / canvasScale
        ..style = PaintingStyle.stroke
        ..maskFilter = null;
      canvas.drawRRect(RRect.fromRectAndRadius(ghostBounds, r), _p);

      // Inner silhouette: subdivide cluster bounds into element-sized rects
      // Use stroke IDs count to approximate subdivision
      final elementCount = cluster.strokeIds.length +
          cluster.shapeIds.length +
          cluster.imageIds.length;
      if (elementCount > 1 && elementCount <= 20) {
        // Approximate: divide bounds into rows of elements
        final cols = math.min(elementCount, 4);
        final rows = (elementCount / cols).ceil();
        final cellW = ghostBounds.width / cols;
        final cellH = ghostBounds.height / rows;
        final innerAlpha = (pulseAlpha * 0.3).toInt();
        _p
          ..color = Color.fromARGB(innerAlpha, 130, 200, 255)
          ..strokeWidth = 0.8 / canvasScale
          ..style = PaintingStyle.stroke;
        for (int i = 0; i < elementCount && i < cols * rows; i++) {
          final col = i % cols;
          final row = i ~/ cols;
          final cellRect = Rect.fromLTWH(
            ghostBounds.left + col * cellW + cellW * 0.1,
            ghostBounds.top + row * cellH + cellH * 0.1,
            cellW * 0.8,
            cellH * 0.8,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(cellRect, Radius.circular(4.0 / canvasScale)),
            _p,
          );
        }
      }

      // Ghost fill
      _p
        ..color = Color.fromARGB(pulseAlpha ~/ 8, 130, 200, 255)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(RRect.fromRectAndRadius(ghostBounds, r), _p);

      // Directional arrow inside the ghost showing displacement direction
      final arrowLen = 12.0 / canvasScale;
      final cx = ghostBounds.center.dx;
      final cy = ghostBounds.center.dy;
      _p
        ..color = Color.fromARGB(pulseAlpha ~/ 2, 200, 230, 255)
        ..style = PaintingStyle.fill;
      if (displacement.dy.abs() > displacement.dx.abs()) {
        // Vertical arrow
        final sign = displacement.dy > 0 ? 1.0 : -1.0;
        final path = Path()
          ..moveTo(cx - arrowLen * 0.5, cy)
          ..lineTo(cx + arrowLen * 0.5, cy)
          ..lineTo(cx, cy + arrowLen * sign)
          ..close();
        canvas.drawPath(path, _p);
      } else {
        // Horizontal arrow
        final sign = displacement.dx > 0 ? 1.0 : -1.0;
        final path = Path()
          ..moveTo(cx, cy - arrowLen * 0.5)
          ..lineTo(cx, cy + arrowLen * 0.5)
          ..lineTo(cx + arrowLen * sign, cy)
          ..close();
        canvas.drawPath(path, _p);
      }
    }
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
    if (controller.connections.isEmpty) return;

    for (final conn in controller.connections) {
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
      final glowPath = Path()
        ..moveTo(srcPt.dx, srcPt.dy)
        ..quadraticBezierTo(cp.dx, cp.dy, tgtPt.dx, tgtPt.dy);

      // Layer 1: Very wide ambient glow
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0)
        ..shader = LinearGradient(
          colors: [
            srcColor.withValues(alpha: glowAlpha * 0.7),
            tgtColor.withValues(alpha: glowAlpha * 0.7),
          ],
        ).createShader(Rect.fromPoints(srcPt, tgtPt));
      canvas.drawPath(glowPath, _p);

      // Layer 2: Narrower, brighter core glow
      _p
        ..strokeWidth = 8.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0)
        ..shader = LinearGradient(
          colors: [
            srcColor.withValues(alpha: glowAlpha * 1.2),
            tgtColor.withValues(alpha: glowAlpha * 1.2),
          ],
        ).createShader(Rect.fromPoints(srcPt, tgtPt));
      canvas.drawPath(glowPath, _p);

      _p
        ..maskFilter = null
        ..shader = null;
    }
  }

  // ===========================================================================
  // PHASE 1: WORD UNDERLINES — Clean underlines under connected clusters
  // ===========================================================================

  void _paintWordUnderlines(Canvas canvas, double fade) {
    if (controller.connections.isEmpty && snapTargetClusterId == null &&
        dragSourceClusterId == null) return;

    // Collect IDs of clusters that participate in connections
    final connectedIds = <String>{};
    final connColors = <String, Color>{};
    for (final conn in controller.connections) {
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

  void _paintGhostConnectionsDashed(Canvas canvas, double fade) {
    final ghostConns = controller.connections.where((c) => c.isGhost);
    if (ghostConns.isEmpty) return;

    final cMap = _buildClusterMap();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    for (final conn in ghostConns) {
      final src = cMap[conn.sourceClusterId];
      final tgt = cMap[conn.targetClusterId];
      if (src == null || tgt == null) continue;

      // === Anchor points (same logic as solid connections) ===
      final srcCenter = conn.sourceAnchor ?? src.centroid;
      final tgtCenter = conn.targetAnchor ?? tgt.centroid;
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

      // === Flowing spectral particle (a single bright dot traveling along) ===
      final particleT = (animationTime * 0.4 + conn.id.hashCode * 0.3) % 1.0;
      final particlePos = controller.pointOnQuadBezier(
        srcPt, cp, tgtPt, particleT,
      );
      _p
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
        ..color = glowColor.withValues(alpha: breathAlpha * 1.5);
      canvas.drawCircle(particlePos, 3.5 + pulse * 1.5, _p);
      _p.maskFilter = null;

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
    if (controller.connections.isEmpty) return;

    final cMap = _buildClusterMap();
    for (final conn in controller.connections) {
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
        ..shader = LinearGradient(
          colors: [
            srcColor.withValues(alpha: 0.06),
            tgtColor.withValues(alpha: 0.06),
          ],
        ).createShader(Rect.fromPoints(srcPt, tgtPt));

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
      final connColor = conn.color;
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
      final lineW = ((lod == 2 ? 3.5 : 2.5) + labelBonus + selectBonus + hubBonus + typeBonus) * dissolveScale;
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
          _paintAutoScaledLabelPill(canvas, midPt, conn.label!, typeColor, fade);
        } else {
          _paintLabelPill(canvas, midPt, conn.label!, typeColor, fade);
        }
      }

      // === Flowing particles with trail (LOD 2 only — satellite view) ===
      if (lod == 2 && connIndex < 8) {
        _paintParticlesWithTrail(
          canvas, conn, srcPt, cp, tgtPt, gradStart, gradEnd, lod, fade,
          skipGhosts: connCount > 5,
        );
      }
      connIndex++;
    }
  }

  void _paintParticlesWithTrail(
    Canvas canvas,
    KnowledgeConnection conn,
    Offset srcPt,
    Offset cpPt,
    Offset tgtPt,
    Color srcColor,
    Color tgtColor,
    int lod,
    double fade, {
    bool skipGhosts = false,
  }) {
    final coreSize = lod == 2 ? 5.0 : 3.0;
    final glowSize = lod == 2 ? 14.0 : 8.0;
    const trailSegments = 6; // More segments for comet-like trail
    const trailStep = 0.025; // Tighter spacing for denser trail

    // At LOD 2: add 1 ghost particle at fixed offset for busier network feel
    // 🚀 SKIP GHOSTS when connection count is high (particle budget)
    final positions = <double>[...conn.particlePositions];
    if (lod == 2 && !skipGhosts && conn.particlePositions.isNotEmpty) {
      for (final t in conn.particlePositions) {
        positions.add((t + 0.5) % 1.0);
      }
    }

    for (int pi = 0; pi < positions.length; pi++) {
      final t = positions[pi];
      final isGhost = pi >= conn.particlePositions.length;
      final sizeScale = isGhost ? 0.6 : 1.0;
      final alphaScale = isGhost ? 0.5 : 1.0;

      // Interpolate color along the path
      final particleColor = Color.lerp(srcColor, tgtColor, t)!;

      // ---- Comet-style trailing fade (behind the particle) ----
      if (!isGhost) { // Skip trails for ghost particles (performance)
        for (int i = trailSegments; i >= 1; i--) {
          final trailT = (t - trailStep * i).clamp(0.0, 1.0);
          final trailPos = controller.pointOnQuadBezier(
            srcPt, cpPt, tgtPt, trailT,
          );
          // Exponential falloff for comet-like tail
          final falloff = math.pow(1.0 - i / (trailSegments + 1), 1.5);
          final trailAlpha = falloff * 0.22 * fade;
          // Shrink segments progressively with elongation effect
          final trailSize = coreSize * (1.0 - i * 0.12) * sizeScale;

          _p
            ..style = PaintingStyle.fill
            ..color = particleColor.withValues(alpha: trailAlpha);
          canvas.drawCircle(trailPos, math.max(trailSize, 0.5), _p);
        }
      }

      final pos = controller.pointOnQuadBezier(srcPt, cpPt, tgtPt, t);

      // ---- Outer glow (pulsing) ----
      final glowPulse = 1.0 + math.sin(animationTime * 3.0 + t * 6.28) * 0.15;
      _glowPaint.color = particleColor.withValues(alpha: 0.22 * fade * alphaScale);
      canvas.drawCircle(pos, glowSize * sizeScale * glowPulse, _glowPaint);

      // ---- Core circle ----
      _p
        ..style = PaintingStyle.fill
        ..color = particleColor.withValues(alpha: 0.8 * fade * alphaScale);
      canvas.drawCircle(pos, coreSize * sizeScale, _p);

      // ---- Bright center highlight ----
      _p.color = Colors.white.withValues(alpha: 0.65 * fade * alphaScale);
      canvas.drawCircle(pos, coreSize * 0.4 * sizeScale, _p);
    }
  }

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
      final text = clusterTexts[cluster.id];
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
  // 🚀 PERF: animationTime → ms offset for animation timing
  static double _fcAnimBaseTime = 0.0;
  static int _fcAnimBaseMs = 0;

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

    // 🚀 PERF: Derive ms from animationTime (avoid DateTime.now syscall)
    // Calibrate once, then use animationTime delta
    if (_fcAnimBaseMs == 0) {
      _fcAnimBaseMs = DateTime.now().millisecondsSinceEpoch;
      _fcAnimBaseTime = animationTime;
    }
    final nowMs = _fcAnimBaseMs +
        ((animationTime - _fcAnimBaseTime) * 1000).round();

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
    final importanceScale = 0.7 + importance * 0.6;
    final nodeRadius = (20.0 + cluster.elementCount.clamp(0, 50) * 0.8) * importanceScale;
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

    // Keywords
    final text = clusterTexts[clusterId] ?? '';
    final keywords = text.isNotEmpty
        ? SemanticMorphController.extractLocalKeywords(text) : null;
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

    // Hint + bottom padding
    contentH += 22 + cardPad;

    final cardH = contentH.clamp(80.0, 250.0);

    // Position card to the right of the node
    final cardX = center.dx + nodeRadius + 15;
    final cardY = center.dy - cardH * 0.3;

    // ── 0. 🔗 CONNECTOR LINE: node → card ──
    final connStart = Offset(
      center.dx + nodeRadius,
      center.dy,
    );
    final connEnd = Offset(cardX, cardY + cardH * 0.3);
    final connCp = Offset(
      (connStart.dx + connEnd.dx) / 2,
      connStart.dy - 10,
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
        _quadBezierPt(connStart, connCp, connEnd, t0),
        _quadBezierPt(connStart, connCp, connEnd, t1),
        _p,
      );
    }

    // ── CARD BODY ──
    canvas.save();
    canvas.translate(cardX, cardY);
    canvas.scale(inverseScale * 0.4 * animEase);

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
    curY += titleTp.height + 8;

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

    // ── 8. "Zoom in" hint ──
    final hintKey = '${clusterId}_fch';
    var hintTp = _cachedTitlePainters[hintKey];
    if (hintTp == null) {
      hintTp = TextPainter(
        text: TextSpan(
          text: 'Zoom in →',
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
  }

  // ===========================================================================
  // 🌍 GOD VIEW — Thematic super-nodes at extreme zoom-out
  // ===========================================================================

  void _paintGodView(Canvas canvas, double fade) {
    if (semanticController == null) return;
    final superNodes = semanticController!.superNodes;
    if (superNodes.isEmpty) return;
    if (fade < 0.01) return;

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
      // Each segment colored by its member cluster type
      if (sn.memberCount > 1) {
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
    if (superNodes.length > 1) {
      // 🚀 PERF: Use pre-computed membership map from controller
      final memberToSuperNode = semanticController!.memberToSuperNodeIndex;

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

    // Collect connected clusters and count connections per cluster
    final connCounts = <String, int>{};
    for (final conn in controller.connections) {
      connCounts[conn.sourceClusterId] =
          (connCounts[conn.sourceClusterId] ?? 0) + 1;
      connCounts[conn.targetClusterId] =
          (connCounts[conn.targetClusterId] ?? 0) + 1;
    }

    for (final cluster in clusters) {
      final color = _clusterColor(cluster);
      final center = cluster.centroid;
      final stats = semanticController!.clusterStats[cluster.id];
      final connCount = connCounts[cluster.id] ?? 0;

      // ── Node radius proportional to element count × importance ──
      final elementCount = stats?.totalElements ?? 1;
      final importance = semanticController!.getSmoothedImportance(cluster.id);
      final importanceScale = 0.7 + importance * 0.6; // 0.7x–1.3x
      final baseNodeRadius = ((math.sqrt(elementCount.toDouble()) * 18.0 + 24.0)
          .clamp(30.0, 120.0)) * importanceScale;
      final isTopNode = importance >= semanticController!.importanceTopThreshold
          && clusters.length > 2;

      // ── Breathing pulse for connected nodes ──
      final breathPhase = animationTime * 1.0 +
          center.dx * 0.001 + center.dy * 0.001;
      final breath = connCount > 0
          ? (math.sin(breathPhase) * 0.08 + 1.0)
          : 1.0;
      final nodeRadius = baseNodeRadius * breath;

      // ── 1. Outer glow — importance scales halo ──
      final glowMultiplier = 1.4 + importance * 0.6; // 1.4x—2.0x
      final glowAlpha = (0.15 + importance * 0.20) * fade; // 0.15—0.35
      _softGlowPaint.color = color.withValues(alpha: glowAlpha);
      canvas.drawCircle(center, nodeRadius * glowMultiplier, _softGlowPaint);

      // ── 2. Glass fill — radial gradient ──
      final fillGradient = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 1.0,
        colors: [
          color.withValues(alpha: 0.18 * fade),
          color.withValues(alpha: 0.06 * fade),
          const Color(0xFF0D1117).withValues(alpha: 0.12 * fade),
        ],
        stops: const [0.0, 0.6, 1.0],
      );
      final nodeRect = Rect.fromCircle(center: center, radius: nodeRadius);
      _p
        ..style = PaintingStyle.fill
        ..shader = fillGradient.createShader(nodeRect)
        ..maskFilter = null;
      canvas.drawCircle(center, nodeRadius, _p);
      _p.shader = null;

      // ── 3. Inner highlight — glass refraction arc at top ──
      _reusePath.reset();
      _reusePath.addArc(
        Rect.fromCircle(center: center, radius: nodeRadius * 0.92),
        -math.pi * 0.85,
        math.pi * 0.7,
      );
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.15 * fade);
      canvas.drawPath(_reusePath, _p);

      // ── 4. Luminous border — thickness scales with importance ──
      final borderWidth = 1.0 + importance * 2.0; // 1.0—3.0
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..color = color.withValues(alpha: (0.35 + importance * 0.20) * fade);
      canvas.drawCircle(center, nodeRadius, _p);

      // ── 5. Connection glow ring (for highly connected nodes) ──
      if (connCount >= 2) {
        final glowPulse = math.sin(animationTime * 2.0 + connCount * 0.5)
            * 0.5 + 0.5;
        _softGlowPaint.color = color.withValues(
          alpha: (0.08 + glowPulse * 0.06) * fade,
        );
        canvas.drawCircle(center, nodeRadius + 8, _softGlowPaint);
      }

      // ── 5.5 Shimmer loading effect for pending AI title nodes ──
      final isPending = semanticController!.pendingAiRequests.contains(cluster.id);
      if (isPending) {
        // Animated shimmer sweep across the node
        final shimmerPhase = (animationTime * 1.5 +
            center.dx * 0.002) % (2.0 * math.pi);
        final shimmerX = math.cos(shimmerPhase) * nodeRadius * 0.8;

        final shimmerGradient = LinearGradient(
          begin: Alignment(-1.0 + shimmerX / nodeRadius, -0.5),
          end: Alignment(1.0 + shimmerX / nodeRadius, 0.5),
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.08 * fade),
            Colors.white.withValues(alpha: 0.18 * fade),
            Colors.white.withValues(alpha: 0.08 * fade),
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

      // ── 6. Title text — centered, auto-scaled, with AI crossfade ──
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(inverseScale * 0.35);
      canvas.translate(-center.dx, -center.dy);

      // Constrain width to node diameter (inverse-scaled)
      final maxTextWidth = nodeRadius * 2.0 / (inverseScale * 0.35) * 0.75;
      final constrainedWidth = maxTextWidth.clamp(60.0, 300.0);

      // 🏷️ Content type icon — cached TextPainter
      final icon = semanticController!.contentIcon(cluster.id);
      final iconAlpha = (0.70 * fade);
      final iconCacheKey = '${cluster.id}_icon_$icon';
      var iconTp = _cachedTitlePainters[iconCacheKey];
      if (iconTp == null) {
        iconTp = TextPainter(
          text: TextSpan(text: icon, style: TextStyle(
            fontSize: 11.0, height: 1.0,
            color: Colors.white.withValues(alpha: iconAlpha),
          )),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        iconTp.layout();
        _cachedTitlePainters[iconCacheKey] = iconTp;
      }
      iconTp.paint(
        canvas,
        Offset(center.dx - iconTp.width / 2, center.dy - iconTp.height - 8),
      );

      // ── ⭐ Star badge for top-20% importance nodes ──
      if (isTopNode) {
        // 🚀 PERF: Reuse _softGlowPaint (already has blur) instead of modifying _p
        _softGlowPaint.color = const Color(0xFFFFD700).withValues(alpha: 0.15 * fade);
        canvas.drawCircle(
          Offset(center.dx + nodeRadius * 0.7, center.dy - nodeRadius * 0.7),
          8.0, _softGlowPaint,
        );

        // Star icon (cached)
        const starKey = '__star_badge__';
        var starTp = _cachedTitlePainters[starKey];
        if (starTp == null) {
          starTp = TextPainter(
            text: const TextSpan(
              text: '⭐',
              style: TextStyle(fontSize: 10.0),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          _cachedTitlePainters[starKey] = starTp;
        }
        starTp.paint(canvas, Offset(
          center.dx + nodeRadius * 0.7 - starTp.width / 2,
          center.dy - nodeRadius * 0.7 - starTp.height / 2,
        ));
      }
      final (displayTitle, titleOpacity) =
          semanticController!.getCrossfadeTitle(cluster.id);
      final previousTitle = semanticController!.previousTitles[cluster.id];

      // Paint PREVIOUS title (fading out) if mid-transition
      if (previousTitle != null && titleOpacity < 1.0) {
        final prevStyle = TextStyle(
          color: Colors.white.withValues(alpha: 0.92 * fade * (1.0 - titleOpacity)),
          fontSize: 13.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          height: 1.2,
        );
        final prevTp = TextPainter(
          text: TextSpan(text: previousTitle, style: prevStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          maxLines: 2,
          ellipsis: '…',
        );
        prevTp.layout(maxWidth: constrainedWidth);
        prevTp.paint(
          canvas,
          Offset(center.dx - prevTp.width / 2, center.dy - prevTp.height / 2 + 4),
        );
      }

      // Paint CURRENT title (fading in, or fully visible)
      final titleStyle = TextStyle(
        color: Colors.white.withValues(alpha: 0.92 * fade * titleOpacity),
        fontSize: 13.0,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        height: 1.2,
      );
      final tp = TextPainter(
        text: TextSpan(text: displayTitle, style: titleStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
        ellipsis: '…',
      );
      tp.layout(maxWidth: constrainedWidth);
      tp.paint(
        canvas,
        Offset(center.dx - tp.width / 2, center.dy - tp.height / 2 + 4),
      );

      canvas.restore();

      // ── 7. Stats mini-badges orbiting the node ──
      if (stats != null && (stats.totalElements > 1 || connCount > 0)) {
        _paintSemanticStatBadges(
          canvas, center, nodeRadius, stats, connCount, color, fade,
          inverseScale,
        );
      }
    }
  }

  /// Paint small orbiting stat badges around a semantic node.
  void _paintSemanticStatBadges(
    Canvas canvas,
    Offset center,
    double nodeRadius,
    ClusterStats stats,
    int connCount,
    Color color,
    double fade,
    double inverseScale,
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

    // Slow orbit animation
    final orbitOffset = animationTime * 0.15;
    final orbitRadius = nodeRadius + 18.0;
    final angleStep = (2 * math.pi) / badges.length;

    for (int i = 0; i < badges.length; i++) {
      final angle = angleStep * i + orbitOffset - math.pi / 2;
      final badgeCenter = Offset(
        center.dx + math.cos(angle) * orbitRadius,
        center.dy + math.sin(angle) * orbitRadius,
      );

      canvas.save();
      canvas.translate(badgeCenter.dx, badgeCenter.dy);
      canvas.scale(inverseScale * 0.28);
      canvas.translate(-badgeCenter.dx, -badgeCenter.dy);

      final badgeText = '${badges[i].$1} ${badges[i].$2}';
      final badgeTp = TextPainter(
        text: TextSpan(
          text: badgeText,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85 * fade),
            fontSize: 9.0,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final pillW = badgeTp.width + 10;
      final pillH = badgeTp.height + 6;
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: badgeCenter,
          width: pillW,
          height: pillH,
        ),
        Radius.circular(pillH / 2),
      );

      // Frosted pill background
      _p
        ..style = PaintingStyle.fill
        ..shader = null
        ..maskFilter = null
        ..color = Color.lerp(color, const Color(0xFF0D1117), 0.6)!
            .withValues(alpha: 0.80 * fade);
      canvas.drawRRect(pillRect, _p);

      // Border
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = color.withValues(alpha: 0.35 * fade);
      canvas.drawRRect(pillRect, _p);

      // Text
      badgeTp.paint(
        canvas,
        Offset(
          badgeCenter.dx - badgeTp.width / 2,
          badgeCenter.dy - badgeTp.height / 2,
        ),
      );

      canvas.restore();
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
  bool shouldRepaint(KnowledgeFlowPainter oldDelegate) =>
      clusters != oldDelegate.clusters ||
      canvasScale != oldDelegate.canvasScale ||
      enabled != oldDelegate.enabled ||
      dragSourcePoint != oldDelegate.dragSourcePoint ||
      dragCurrentPoint != oldDelegate.dragCurrentPoint ||
      snapTargetClusterId != oldDelegate.snapTargetClusterId ||
      selectedConnectionId != oldDelegate.selectedConnectionId ||
      animationTime != oldDelegate.animationTime ||
      semanticMorphProgress != oldDelegate.semanticMorphProgress ||
      flightProgress != oldDelegate.flightProgress ||
      flightSourceClusterId != oldDelegate.flightSourceClusterId ||
      landingPulseProgress != oldDelegate.landingPulseProgress;
}
