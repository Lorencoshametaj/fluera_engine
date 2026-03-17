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

  /// 🔵 Currently selected connection (for highlight effect)
  final String? selectedConnectionId;

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
    this.selectedConnectionId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled || !controller.enabled) return;
    if (clusters.isEmpty && controller.connections.isEmpty) return;

    final lod = _getLodLevel();
    final fade = _computeFade();

    if (lod == 0) {
      // LOD 0: Still show connections clearly (not just ghost)
      // so newly created connections are immediately visible
      _paintWordUnderlines(canvas, fade.clamp(0.3, 1.0));
      _paintConnections(canvas, lod, 1.0);
      // 🎯 Drag preview must be visible at ALL zoom levels
      if (dragSourcePoint != null && dragCurrentPoint != null) {
        _paintDragPreview(canvas);
      }
      return;
    }

    // Render order: network glow → underlines → connections → drag preview
    final lod2Fade = _computeLod2Fade();
    if (lod2Fade > 0.01) {
      _paintNetworkGlow(canvas, fade * lod2Fade);
    }
    _paintWordUnderlines(canvas, fade);
    _paintConnections(canvas, lod, fade);

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
    int connIndex = 0;
    for (final conn in controller.connections) {
      final src = cMap[conn.sourceClusterId];
      final tgt = cMap[conn.targetClusterId];
      if (src == null || tgt == null) continue;

      // 🎯 Smart anchor 4-WAY: pick the closest side (top/bottom/left/right)
      // based on relative position of clusters. Prevents curve crossing text.
      final dx = (tgt.centroid.dx - src.centroid.dx).abs();
      final dy = (tgt.centroid.dy - src.centroid.dy).abs();
      final Offset srcPt;
      final Offset tgtPt;
      if (dx > dy * 1.5) {
        // Primarily HORIZONTAL separation → use left/right anchors
        if (tgt.centroid.dx > src.centroid.dx) {
          srcPt = Offset(src.bounds.right + 4, src.bounds.center.dy);
          tgtPt = Offset(tgt.bounds.left - 4, tgt.bounds.center.dy);
        } else {
          srcPt = Offset(src.bounds.left - 4, src.bounds.center.dy);
          tgtPt = Offset(tgt.bounds.right + 4, tgt.bounds.center.dy);
        }
      } else {
        // Primarily VERTICAL separation → use top/bottom anchors
        if (tgt.centroid.dy < src.centroid.dy) {
          srcPt = Offset(src.bounds.center.dx, src.bounds.top - 4);
          tgtPt = Offset(tgt.bounds.center.dx, tgt.bounds.bottom + 4);
        } else {
          srcPt = Offset(src.bounds.center.dx, src.bounds.bottom + 4);
          tgtPt = Offset(tgt.bounds.center.dx, tgt.bounds.top - 4);
        }
      }

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
      final labelBonus = hasLabel ? 0.5 : 0.0;
      final isSelected = selectedConnectionId == conn.id;
      final selectBonus = isSelected ? 1.0 : 0.0;
      final effectiveFade = fade * dissolveFade;
      final lineW = ((lod == 2 ? 3.0 : 2.5) + labelBonus + selectBonus) * dissolveScale;
      final lineAlpha = ((lod == 2 ? 0.85 : 0.80) + (hasLabel ? 0.08 : 0.0) + birthFlash + (isSelected ? 0.15 : 0.0)).clamp(0.0, 1.0);

      // Outer glow — visible, atmospheric (boosted for selected)
      // 🌊 BREATHING: selected connection glow pulses gently at 2Hz
      final breathingPulse = isSelected
          ? (math.sin(animationTime * 4.0) * 0.5 + 0.5) * 0.15
          : 0.0;
      final networkPulse = lod == 2
          ? (math.sin(animationTime * 2.0 + srcPt.dx * 0.001) * 0.5 + 0.5)
          : 0.5;
      final glowOpacity = (lod == 2 ? (0.25 + networkPulse * 0.10) : 0.20) + birthFlash * 0.3 + (isSelected ? 0.20 : 0.0) + breathingPulse;

      // Build full bezier path
      _reusePath.reset();
      _reusePath.moveTo(srcPt.dx, srcPt.dy);
      _reusePath.quadraticBezierTo(cp.dx, cp.dy, tgtPt.dx, tgtPt.dy);

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
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineW + (lod == 2 ? 8 : 6) + (isSelected ? 4 : 0)
        ..strokeCap = StrokeCap.round
        ..maskFilter = isSelected ? _blurLod2 : (lod == 2 ? _blurLod2 : _blurLod1)
        ..shader = null
        ..color = connColor.withValues(alpha: glowOpacity * effectiveFade);
      canvas.drawPath(drawPath, _p);
      _p.maskFilter = null;

      // 📐 VARIABLE THICKNESS: Draw as 16 segments with bell-curve stroke width
      // Thinnest at endpoints (60%), thickest at center (110%)
      const segments = 16;
      final maxT = isBirthAnimating ? birthProgress : 1.0;
      for (int s = 0; s < segments; s++) {
        final t0 = (s / segments) * maxT;
        final t1 = ((s + 1) / segments) * maxT;
        final tMid = (t0 + t1) * 0.5;
        // Bell curve: 0.6 at edges, 1.1 at center
        final widthFactor = 0.6 + 0.5 * math.sin(tMid * math.pi);
        final segW = lineW * widthFactor;

        final p0 = controller.pointOnQuadBezier(srcPt, cp, tgtPt, t0);
        final p1 = controller.pointOnQuadBezier(srcPt, cp, tgtPt, t1);

        // Gradient color at this segment position
        final segColor = Color.lerp(gradStart, gradEnd, tMid)!;
        // Blend with connColor at center for vibrance
        final finalColor = Color.lerp(segColor, connColor, (math.sin(tMid * math.pi) * 0.4))!;

        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = segW
          ..strokeCap = StrokeCap.round
          ..shader = null
          ..color = finalColor.withValues(alpha: lineAlpha * effectiveFade);
        canvas.drawLine(p0, p1, _p);
      }

      // === Birth flash: propagating glow wavefront ===
      if (isBirthAnimating) {
        final flashPos = controller.pointOnQuadBezier(srcPt, cp, tgtPt, birthProgress);
        final flashSize = 15.0 * (1.0 - birthProgress) + 4.0;
        _softGlowPaint.color = Colors.white.withValues(alpha: (0.6 * (1.0 - birthProgress)) * effectiveFade);
        canvas.drawCircle(flashPos, flashSize, _softGlowPaint);
      }

      // === 🔵 Endpoint dots — small, clean ===
      final dotRadius = lod == 2 ? 3.0 : 2.5;
      final dotAlpha = (0.55 + birthFlash * 0.3).clamp(0.0, 0.85) * effectiveFade;
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
          _softGlowPaint.color = connColor.withValues(alpha: 0.25 * effectiveFade);
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
            ..color = connColor.withValues(alpha: lineAlpha * effectiveFade);
          canvas.drawPath(arrowPath, _p);
        }
      }

      // === ✨ Selected endpoint glow ===
      if (isSelected) {
        final pulseR = 6.0 + (math.sin(animationTime * 3.0) * 2.0);
        _softGlowPaint.color = connColor.withValues(alpha: 0.35 * effectiveFade);
        canvas.drawCircle(srcPt, pulseR, _softGlowPaint);
        canvas.drawCircle(tgtPt, pulseR, _softGlowPaint);
      }

      // === 🌟 Bidirectional shimmer — flowing energy both ways ===
      if (!isBirthAnimating) {
        final shimmerSize = lod == 2 ? 5.0 : 3.5;
        // Forward shimmer
        final shimmerT1 = ((animationTime * 0.25 + connIndex * 0.3) % 1.0);
        final shimmerPos1 = controller.pointOnQuadBezier(srcPt, cp, tgtPt, shimmerT1);
        _softGlowPaint.color = Colors.white.withValues(alpha: 0.45 * effectiveFade);
        canvas.drawCircle(shimmerPos1, shimmerSize * 0.4, _softGlowPaint);
        _softGlowPaint.color = connColor.withValues(alpha: 0.25 * effectiveFade);
        canvas.drawCircle(shimmerPos1, shimmerSize, _softGlowPaint);
        // Reverse shimmer (offset by 0.5, slightly slower)
        final shimmerT2 = ((1.0 - (animationTime * 0.20 + connIndex * 0.5)) % 1.0).abs();
        final shimmerPos2 = controller.pointOnQuadBezier(srcPt, cp, tgtPt, shimmerT2);
        _softGlowPaint.color = Colors.white.withValues(alpha: 0.30 * effectiveFade);
        canvas.drawCircle(shimmerPos2, shimmerSize * 0.35, _softGlowPaint);
        _softGlowPaint.color = connColor.withValues(alpha: 0.18 * effectiveFade);
        canvas.drawCircle(shimmerPos2, shimmerSize * 0.9, _softGlowPaint);
      }

      // === 🏷️ Label pill at midpoint ===
      if (conn.label != null && conn.label!.isNotEmpty) {
        final midPt = controller.pointOnQuadBezier(srcPt, cp, tgtPt, 0.5);
        _paintLabelPill(canvas, midPt, conn.label!, connColor, fade);
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
      selectedConnectionId != oldDelegate.selectedConnectionId ||
      animationTime != oldDelegate.animationTime;
}
