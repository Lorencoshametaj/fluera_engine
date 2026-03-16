import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../reflow/content_cluster.dart';
import '../../reflow/knowledge_connection.dart';
import '../../reflow/knowledge_flow_controller.dart';
import '../../reflow/connection_suggestion_engine.dart';

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
///   - Level 0 (zoom > 0.5): Ghost lines only (2% opacity)
///   - Level 1 (zoom 0.15–0.5): Full premium visualization
///   - Level 2 (zoom < 0.15): Satellite — bold bubbles + thick arrows
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
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled || !controller.enabled) return;
    if (clusters.isEmpty) return;

    final lod = _getLodLevel();
    final fade = _computeFade();

    if (lod == 0) {
      // Always show connections at zoom-in, just subtler
      _paintGhostConnections(canvas);
      // 💡 Show suggestions only in pan mode (no distraction while writing)
      if (showSuggestions) _paintSuggestions(canvas, lod, fade.clamp(0.3, 1.0));
      return;
    }

    // Render order: network glow → shadows → bubbles → connections → labels → drag preview
    // Smooth LOD 2 transition: network glow fades in gradually
    final lod2Fade = _computeLod2Fade();
    if (lod2Fade > 0.01) {
      _paintNetworkGlow(canvas, fade * lod2Fade);
    }
    _paintBubbleShadows(canvas, lod, fade);
    _paintBubbles(canvas, lod, fade);
    // 🚀 DISABLED: DrawingPainter already renders strokes at all LOD levels.
    // Thumbnails at LOD 1+ caused visual doubling — both the rasterized 120×120
    // thumbnail AND the actual strokes were drawn at the same canvas coordinates.
    // _paintThumbnails(canvas, lod, fade);
    _paintConnections(canvas, lod, fade);
    if (showSuggestions) _paintSuggestions(canvas, lod, fade);
    _paintLabels(canvas, lod, fade);

    if (dragSourcePoint != null && dragCurrentPoint != null) {
      _paintDragPreview(canvas);
    }

    // 📊 Network stats badge (LOD 2 only)
    if (lod == 2) {
      _paintNetworkStats(canvas);
    }
  }

  int _getLodLevel() {
    if (canvasScale > _lodLevel1Max) return 0;
    if (canvasScale > _lodLevel1Min) return 1;
    return 2;
  }

  // ===========================================================================
  // PHASE 0: NETWORK GLOW (LOD 2 only — "connected world" effect)
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
  // PHASE 1: BUBBLE SHADOWS
  // ===========================================================================

  void _paintBubbleShadows(Canvas canvas, int lod, double fade) {
    for (final cluster in clusters) {
      if (cluster.elementCount < 1) continue;
      final bounds = cluster.bounds.inflate(_bubblePadding);
      if (bounds.isEmpty || bounds.width < 2) continue;

      final color = _clusterColor(cluster);
      final cr = lod == 2 ? _bubbleCornerRadius * 1.5 : _bubbleCornerRadius;

      // Drop shadow: offset 4px down-right, blur 8px, cluster color at 12%
      final shadowRect = RRect.fromRectAndRadius(
        bounds.shift(const Offset(3, 4)),
        Radius.circular(cr),
      );
      _shadowPaint.color = color.withValues(alpha: 0.12 * fade);
      canvas.drawRRect(shadowRect, _shadowPaint);
    }
  }

  // ===========================================================================
  // PHASE 2: GLASSMORPHISM BUBBLES
  // ===========================================================================

  void _paintBubbles(Canvas canvas, int lod, double fade) {
    // Pre-compute connection counts (all LODs — used for hub indicator)
    final connCounts = <String, int>{};
    for (final conn in controller.connections) {
      connCounts[conn.sourceClusterId] = (connCounts[conn.sourceClusterId] ?? 0) + 1;
      connCounts[conn.targetClusterId] = (connCounts[conn.targetClusterId] ?? 0) + 1;
    }

    for (final cluster in clusters) {
      if (cluster.elementCount < 1) continue;

      // 🌟 HUB INDICATOR: more connections → larger padding + thicker border
      final connCount = connCounts[cluster.id] ?? 0;
      final hubBonus = (connCount * 3.0).clamp(0.0, 15.0); // +3px per connection, max +15
      final bounds = cluster.bounds.inflate(_bubblePadding + hubBonus);
      if (bounds.isEmpty || bounds.width < 2) continue;

      final color = _clusterColor(cluster);
      final cr = lod == 2 ? _bubbleCornerRadius * 1.5 : _bubbleCornerRadius;
      final rrect = RRect.fromRectAndRadius(bounds, Radius.circular(cr));

      // === Layer 1: Gradient fill with breathing pulsation ===
      final breathOffset = cluster.centroid.dx * 0.003 + cluster.centroid.dy * 0.002;
      final breathPhase = math.sin(animationTime * 1.2 + breathOffset) * 0.5 + 0.5;
      final breathMod = 1.0 + breathPhase * 0.06;

      final fillOpacity = (lod == 2 ? 0.18 : 0.10) * breathMod;
      _p
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: fillOpacity * fade * 1.3),
            color.withValues(alpha: fillOpacity * fade * 0.5),
          ],
        ).createShader(bounds);
      canvas.drawRRect(rrect, _p);
      _p.shader = null;

      // === Breathing glow: luminous halo ===
      if (lod == 2) {
        // 🌟 Hub glow: proportional to connections
        final connectBonus = connCount * 8.0;
        final alphaBonus = connCount * 0.04;
        final glowRadius = math.max(bounds.width, bounds.height) * 0.5 + 15 + connectBonus;
        final glowAlpha = (0.12 + breathPhase * 0.06 + alphaBonus) * fade;
        _softGlowPaint
          ..color = color.withValues(alpha: glowAlpha.clamp(0.0, 0.35))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * 0.4);
        canvas.drawCircle(bounds.center, glowRadius, _softGlowPaint);
        _softGlowPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);
      } else if (lod == 1 && breathPhase > 0.6) {
        final glowAlpha = (breathPhase - 0.6) * 0.08 * fade;
        _softGlowPaint.color = color.withValues(alpha: glowAlpha.clamp(0.0, 0.05));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            bounds.inflate(4.0),
            Radius.circular(cr + 4),
          ),
          _softGlowPaint,
        );
      }

      // === Layer 2: Inner highlight (glass refraction line at top) ===
      final highlightPath = Path();
      final hlRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          bounds.left + cr * 0.8,
          bounds.top + 1.5,
          bounds.right - cr * 0.8,
          bounds.top + 2.5,
        ),
        const Radius.circular(1),
      );
      highlightPath.addRRect(hlRect);
      _p
        ..style = PaintingStyle.fill
        ..shader = null
        ..color = Colors.white.withValues(alpha: 0.12 * fade);
      canvas.drawPath(highlightPath, _p);

      // === Layer 3: Luminous gradient border ===
      // 🌟 Hub border: thicker for highly-connected clusters
      final borderOpacity = lod == 2 ? 0.40 : 0.28;
      final borderWidth = (lod == 2 ? 2.0 : 1.5) + connCount * 0.3;
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth.clamp(1.5, 4.0)
        ..shader = SweepGradient(
          center: Alignment.center,
          colors: [
            color.withValues(alpha: borderOpacity * fade),
            Colors.white.withValues(alpha: borderOpacity * fade * 0.6),
            color.withValues(alpha: borderOpacity * fade * 0.8),
            Colors.white.withValues(alpha: borderOpacity * fade * 0.4),
            color.withValues(alpha: borderOpacity * fade),
          ],
        ).createShader(bounds);
      canvas.drawRRect(rrect, _p);
      _p.shader = null;

      // === 📊 ELEMENT COUNT BADGE (LOD 1-2) ===
      if (cluster.elementCount >= 2) {
        final badgeText = '${cluster.elementCount}';
        final badgeFontSize = lod == 2 ? 12.0 : 9.0;
        final badgeTp = TextPainter(
          text: TextSpan(
            text: badgeText,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85 * fade),
              fontSize: badgeFontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final badgeW = badgeTp.width + 10;
        final badgeH = badgeTp.height + 6;
        final badgeRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(bounds.right - badgeW / 2 - 4, bounds.top + badgeH / 2 + 4),
            width: badgeW,
            height: badgeH,
          ),
          const Radius.circular(8),
        );

        // Badge background
        _p
          ..style = PaintingStyle.fill
          ..shader = null
          ..color = color.withValues(alpha: 0.65 * fade);
        canvas.drawRRect(badgeRect, _p);

        // Badge text
        badgeTp.paint(canvas, Offset(
          badgeRect.outerRect.center.dx - badgeTp.width / 2,
          badgeRect.outerRect.center.dy - badgeTp.height / 2,
        ));
      }

      // === Snap glow (magnetic target during connection drag) ===
      if (snapTargetClusterId == cluster.id) {
        _softGlowPaint.color = color.withValues(alpha: 0.35 * fade);
        canvas.drawRRect(rrect.inflate(6), _softGlowPaint);
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = color.withValues(alpha: 0.5 * fade);
        canvas.drawRRect(rrect, _p);
      }
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

  void _paintGhostConnections(Canvas canvas) {
    if (controller.connections.isEmpty) return;

    final cMap = _buildClusterMap();
    for (final conn in controller.connections) {
      final src = cMap[conn.sourceClusterId];
      final tgt = cMap[conn.targetClusterId];
      if (src == null || tgt == null) continue;

      // Ghost arrows use cluster-specific gradient colors
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
        ).createShader(Rect.fromPoints(src.centroid, tgt.centroid));

      final path = controller.computeBezierPath(
        source: src.centroid,
        target: tgt.centroid,
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
    int connIndex = 0;
    for (final conn in controller.connections) {
      final src = cMap[conn.sourceClusterId];
      final tgt = cMap[conn.targetClusterId];
      if (src == null || tgt == null) continue;

      final srcPt = src.centroid;
      final tgtPt = tgt.centroid;

      // 🔀 Smart curve offset for multiple connections between same pair
      final pairKey = conn.sourceClusterId.hashCode ^ conn.targetClusterId.hashCode;
      final idx = pairIndexMap[pairKey] ?? 0;
      pairIndexMap[pairKey] = idx + 1;
      final pairTotal = pairCountMap[pairKey] ?? 1;
      // Vary curve strength: alternate sign and increase magnitude
      final routeOffset = pairTotal > 1
          ? (idx - (pairTotal - 1) / 2.0) * 0.3
          : 0.0;
      final effectiveCurveStrength = conn.curveStrength + routeOffset;
      final cp = controller.getControlPoint(srcPt, tgtPt, effectiveCurveStrength);
      final srcColor = _clusterColor(src);
      final tgtColor = _clusterColor(tgt);

      // === Connection birth animation (1s flash) ===
      // 🚀 PERF: Skip entirely for loaded connections (createdAtMs == 0)
      final isBirth = conn.createdAtMs > 0;
      final birthAge = isBirth ? (nowMs - conn.createdAtMs) / 1000.0 : 2.0;
      final isBirthAnimating = isBirth && birthAge < 1.0;
      final birthProgress = isBirthAnimating ? birthAge.clamp(0.0, 1.0) : 1.0;
      final birthFlash = isBirthAnimating ? (1.0 - birthProgress) * 0.4 : 0.0;

      // === Gradient arrow line ===
      // Labeled connections are thicker and more prominent
      final hasLabel = conn.label != null && conn.label!.isNotEmpty;
      final labelBonus = hasLabel ? 1.0 : 0.0;
      final lineW = (lod == 2 ? 3.0 : 1.8) + labelBonus;
      final lineAlpha = ((lod == 2 ? 0.50 : 0.35) + (hasLabel ? 0.10 : 0.0) + birthFlash).clamp(0.0, 0.95);

      // Outer glow line — extra bright during birth
      final networkPulse = lod == 2
          ? (math.sin(animationTime * 2.0 + srcPt.dx * 0.001) * 0.5 + 0.5)
          : 0.5;
      final glowOpacity = (lod == 2 ? (0.10 + networkPulse * 0.12) : 0.08) + birthFlash * 0.3;
      _glowPaint.color = conn.color.withValues(alpha: glowOpacity * fade);
      // 🚀 PERF: Reuse single Path instead of allocating new Path() per connection
      _reusePath.reset();
      _reusePath.moveTo(srcPt.dx, srcPt.dy);
      _reusePath.quadraticBezierTo(cp.dx, cp.dy, tgtPt.dx, tgtPt.dy);
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = lod == 2 ? lineW + 8 : lineW + 4
        ..strokeCap = StrokeCap.round
        // 🚀 PERF: Use pre-cached MaskFilter constants
        ..maskFilter = lod == 2 ? _blurLod2 : _blurLod1
        ..color = conn.color.withValues(alpha: glowOpacity * fade);
      canvas.drawPath(_reusePath, _p);
      _p.maskFilter = null;

      // Core arrow with gradient — reuse path
      _reusePath.reset();
      _reusePath.moveTo(srcPt.dx, srcPt.dy);
      _reusePath.quadraticBezierTo(cp.dx, cp.dy, tgtPt.dx, tgtPt.dy);
      _p
        ..strokeWidth = lineW
        ..shader = LinearGradient(
          colors: [
            srcColor.withValues(alpha: lineAlpha * fade),
            tgtColor.withValues(alpha: lineAlpha * fade),
          ],
        ).createShader(Rect.fromPoints(srcPt, tgtPt));
      canvas.drawPath(_reusePath, _p);
      _p.shader = null;

      // === Arrowhead ===
      final arrowSize = lod == 2 ? 16.0 : 11.0;
      final ahPath = controller.computeArrowhead(
        target: tgtPt,
        controlPoint: cp,
        size: arrowSize,
      );
      _p
        ..style = PaintingStyle.fill
        ..color = tgtColor.withValues(alpha: lineAlpha * fade);
      canvas.drawPath(ahPath, _p);

      // === Bi-directional: use pre-computed hash set O(1) lookup ===
      final hasBidir = bidirSet != null &&
          controller.connections.any((c) =>
              c != conn &&
              (c.sourceClusterId.hashCode ^ c.targetClusterId.hashCode) ==
              (conn.targetClusterId.hashCode ^ conn.sourceClusterId.hashCode) &&
              c.sourceClusterId == conn.targetClusterId);
      if (hasBidir) {
        // Draw arrowhead at source end too
        final revAhPath = controller.computeArrowhead(
          target: srcPt,
          controlPoint: cp,
          size: arrowSize * 0.8, // Slightly smaller for visual hierarchy
        );
        _p.color = srcColor.withValues(alpha: lineAlpha * fade * 0.8);
        canvas.drawPath(revAhPath, _p);
      }

      // === Birth flash: propagating glow wavefront ===
      if (isBirthAnimating) {
        final flashT = birthProgress; // 0→1 along the path
        final flashPos = controller.pointOnQuadBezier(srcPt, cp, tgtPt, flashT);
        final flashSize = 20.0 * (1.0 - birthProgress) + 5.0;
        _softGlowPaint.color = Colors.white.withValues(alpha: (0.5 * (1.0 - birthProgress)) * fade);
        canvas.drawCircle(flashPos, flashSize, _softGlowPaint);
      }

      // === Flowing particles with trail ===
      // 🚀 PARTICLE BUDGET: Skip particles on excess connections
      // to avoid draw call explosion. First 8 connections get particles;
      // beyond that, only the arrow line is drawn.
      if (connIndex < 8) {
        _paintParticlesWithTrail(
          canvas, conn, srcPt, cp, tgtPt, srcColor, tgtColor, lod, fade,
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

      final isPrimary = rendered == 0;
      final opacityMul = isPrimary ? 1.0 : 0.5;

      _paintSingleSuggestion(
        canvas, lod, fade, active, src, tgt, nowMs, opacityMul,
        glowedClusterIds, labelMidpoints,
      );

      usedClusterIds.add(active.sourceClusterId);
      usedClusterIds.add(active.targetClusterId);
      rendered++;
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

    // Breathing pulsation
    final breath = math.sin(animationTime * 1.2) * 0.5 + 0.5;

    // LOD 0 visibility boost
    final visBoost = lod == 0 ? 4.0 : 1.0;

    // === 🌟 CLUSTER HIGHLIGHT GLOW (deduped — each cluster glows only once) ===
    if (opacityMul >= 1.0) {
      final glowAlpha = (0.08 + breath * 0.06) * fade * decayFactor * entranceFade;
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
        * entranceFade * opacityMul).clamp(0.0, 0.35);

    final srcColor = _clusterColor(src);
    final tgtColor = _clusterColor(tgt);

    // Draw arc as gradient segments (source color → target color)
    final arcSteps = 24;
    final maxStep = entranceT < 1.0
        ? (arcSteps * entranceEase.clamp(0.0, 1.0)).round()
        : arcSteps;
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = lod == 0 ? 1.5 : 0.8
      ..strokeCap = StrokeCap.round
      ..shader = null
      ..maskFilter = null;
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

    // === '+' dot at midpoint (scales with entrance) ===
    final score = active.score.clamp(0.0, 1.0);
    final baseRadius = (6.0 + score * 3.0) * (lod == 0 ? 1.8 : 1.0);
    final dotRadius = baseRadius * entranceEase;
    final dotAlpha = ((0.15 + breath * 0.08) * fade * decayFactor * visBoost
        * entranceFade * opacityMul).clamp(0.0, 0.7);

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
  // PHASE 5: LABELS
  // ===========================================================================

  void _paintLabels(Canvas canvas, int lod, double fade) {
    if (lod < 1) return;

    // Pre-compute connection counts for hub status display
    final connCounts = <String, int>{};
    for (final conn in controller.connections) {
      connCounts[conn.sourceClusterId] = (connCounts[conn.sourceClusterId] ?? 0) + 1;
      connCounts[conn.targetClusterId] = (connCounts[conn.targetClusterId] ?? 0) + 1;
    }

    // Smart label positioning: track placed label rects for collision avoidance
    final placedRects = <Rect>[];

    for (final cluster in clusters) {
      if (cluster.elementCount < 2) continue;

      final bounds = cluster.bounds;
      final color = _clusterColor(cluster);

      // 🔤 Use recognized text if available, fallback to type label
      final recognizedText = clusterTexts[cluster.id];
      String labelText;
      if (recognizedText != null && recognizedText.isNotEmpty) {
        // Truncate to 20 chars max for readability
        labelText = recognizedText.length > 20
            ? '${recognizedText.substring(0, 18)}…'
            : recognizedText;
      } else {
        // Fallback: show content type
        final hasStrokes = cluster.strokeIds.isNotEmpty;
        final hasText = cluster.textIds.isNotEmpty;
        final hasImages = cluster.imageIds.isNotEmpty;
        if (hasText) labelText = '📝 Testo';
        else if (hasImages) labelText = '🖼️ Immagine';
        else if (hasStrokes) labelText = '✍️ Nota';
        else labelText = '📌 Nota';
      }

      // 🌟 Hub indicator: append connection count for hubs
      final connCount = connCounts[cluster.id] ?? 0;
      if (connCount >= 2) {
        labelText = '$labelText  ⚡$connCount';
      }

      // Position: above the bubble
      final hubBonus = (connCount * 3.0).clamp(0.0, 15.0);
      final cx = bounds.center.dx;
      var cy = bounds.top - _bubblePadding - hubBonus - 10;

      final fontSize = lod == 2 ? 16.0 : 11.0;
      final tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85 * fade),
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final pillW = tp.width + 20;
      final pillH = tp.height + 10;

      // Collision avoidance: shift up if overlapping with existing labels
      var labelRect = Rect.fromCenter(center: Offset(cx, cy), width: pillW, height: pillH);
      for (int attempt = 0; attempt < 5; attempt++) {
        bool collides = false;
        for (final placed in placedRects) {
          if (labelRect.overlaps(placed.inflate(4))) {
            collides = true;
            break;
          }
        }
        if (!collides) break;
        cy -= pillH + 6;
        labelRect = Rect.fromCenter(center: Offset(cx, cy), width: pillW, height: pillH);
      }
      placedRects.add(labelRect);

      final pillRect = RRect.fromRectAndRadius(
        labelRect,
        const Radius.circular(12),
      );

      // Pill shadow
      _shadowPaint.color = Colors.black.withValues(alpha: 0.18 * fade);
      canvas.drawRRect(pillRect.shift(const Offset(1, 2)), _shadowPaint);

      // Pill gradient fill
      _p
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.60 * fade),
            color.withValues(alpha: 0.38 * fade),
          ],
        ).createShader(pillRect.outerRect);
      canvas.drawRRect(pillRect, _p);
      _p.shader = null;

      // Pill border
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.18 * fade);
      canvas.drawRRect(pillRect, _p);

      // Label text
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    }
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
    const dashLen = 10.0;
    const gapLen = 7.0;

    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = dragColor.withValues(alpha: 0.65);

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

    // 🔮 SNAP TARGET PULSATION: Pulsing glow ring on candidate target
    if (snapTargetClusterId != null) {
      final snapCluster = clusters
          .where((c) => c.id == snapTargetClusterId)
          .firstOrNull;
      if (snapCluster != null) {
        final snapBounds = snapCluster.bounds.inflate(_bubblePadding);
        final snapColor = _clusterColor(snapCluster);
        final pulse = math.sin(animationTime * 4.0) * 0.5 + 0.5;
        final ringRadius = math.max(snapBounds.width, snapBounds.height) * 0.5 + 8 + pulse * 10;

        // Pulsing outer glow ring
        _softGlowPaint.color = snapColor.withValues(alpha: 0.15 + pulse * 0.15);
        canvas.drawCircle(snapBounds.center, ringRadius, _softGlowPaint);

        // Inner bright ring
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 + pulse
          ..color = snapColor.withValues(alpha: 0.4 + pulse * 0.3);
        canvas.drawCircle(snapBounds.center, ringRadius - 4, _p);
      }
    }

    // Animated glow dot at cursor
    _softGlowPaint.color = dragColor.withValues(alpha: 0.25);
    canvas.drawCircle(cur, 16, _softGlowPaint);

    _glowPaint.color = dragColor.withValues(alpha: 0.35);
    canvas.drawCircle(cur, 8, _glowPaint);

    _p
      ..style = PaintingStyle.fill
      ..color = dragColor.withValues(alpha: 0.8);
    canvas.drawCircle(cur, 4, _p);

    _p.color = Colors.white.withValues(alpha: 0.6);
    canvas.drawCircle(cur, 1.5, _p);
  }

  // ===========================================================================
  // Utilities
  // ===========================================================================

  double _computeFade() {
    // Smooth LOD transition: wider fade zone (0.1) for gentle crossfade
    const fadeZone = 0.10;
    if (canvasScale > _lodLevel1Max) {
      // Above LOD 1 boundary — fade to zero over fadeZone
      return 1.0 - ((canvasScale - _lodLevel1Max) / fadeZone).clamp(0.0, 1.0);
    }
    if (canvasScale > _lodLevel1Max - fadeZone) {
      // Approaching LOD 1 boundary from below — ease in with cubic
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

  Map<String, ContentCluster> _buildClusterMap() {
    final m = <String, ContentCluster>{};
    for (final c in clusters) {
      m[c.id] = c;
    }
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

  @override
  bool shouldRepaint(KnowledgeFlowPainter oldDelegate) =>
      clusters != oldDelegate.clusters ||
      canvasScale != oldDelegate.canvasScale ||
      enabled != oldDelegate.enabled ||
      dragSourcePoint != oldDelegate.dragSourcePoint ||
      dragCurrentPoint != oldDelegate.dragCurrentPoint ||
      snapTargetClusterId != oldDelegate.snapTargetClusterId ||
      controller.version.value != oldDelegate.controller.version.value;
}
