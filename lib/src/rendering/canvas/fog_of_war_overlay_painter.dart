import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../canvas/ai/fog_of_war/fog_of_war_controller.dart';
import '../../canvas/ai/fog_of_war/fog_of_war_model.dart';
import '../../reflow/content_cluster.dart';

/// 🌫️ FOG OF WAR OVERLAY PAINTER — Renders the fog overlay on the canvas.
///
/// Implements the 3 fog density levels (P10-05, P10-06, P10-07):
///
/// | Level   | Rendering                                              |
/// |---------|--------------------------------------------------------|
/// | Light   | Dark overlay + node silhouettes at 15% opacity          |
/// | Medium  | Full fog + circular visibility radius (300px) from      |
/// |         | viewport center                                         |
/// | Total   | Solid dark canvas, nodes only on tap                    |
///
/// During the **revealing** phase (P10-18), the fog dissolves from center
/// outward with a cinematic ease-out animation (2-3 seconds).
///
/// During the **mastery map** phase (P10-19):
///   - 🟢 Green ring (30% opacity) = recalled correctly
///   - 🔴 Red ring = forgotten
///   - ⬜ Grey dashed ring + 👁‍🗨 = blind spot (not visited)
///
/// Performance: viewport culling — only renders visible clusters.
class FogOfWarOverlayPainter extends CustomPainter {
  /// The fog of war controller (for state queries).
  final FogOfWarController controller;

  /// All clusters in the fog zone.
  final List<ContentCluster> clusters;

  /// Canvas scale (for proper sizing of UI elements).
  final double canvasScale;

  /// Animation time in seconds (for pulsing effects).
  final double animationTime;

  /// The center of the viewport in canvas coordinates.
  /// Used for medium fog visibility radius.
  final Offset viewportCenterCanvas;

  /// The visible viewport rect in canvas coordinates (for culling).
  final Rect viewportCanvasRect;

  /// Whether the overlay is in dark mode.
  final bool isDarkMode;

  /// §XI.4 Muro Rosso: When true, soften red nodes to neutral grey
  /// and enhance green nodes with celebratory glow.
  final bool isMuroRossoActive;

  /// 🗺️ Surgical Path (P10-24): IDs of critical nodes in the review path.
  /// Empty when surgical path is not active.
  final List<String> surgicalPathNodeIds;

  /// 🗺️ Surgical Path: IDs of nodes already visited in the review.
  final Set<String> surgicalVisitedIds;

  // ── 🚀 PERF: Static reusable objects ─────────────────────────────────────

  /// Reusable paint objects — avoid per-frame allocations.
  static final Paint _p = Paint();
  static final Paint _fogPaint = Paint();
  static final Paint _auxPaint = Paint(); // OPT-2: third reusable paint

  /// OPT-1: Static TextPainter cache keyed by (text + fontSize).
  /// LRU eviction at 64 entries to bound memory.
  static final Map<String, TextPainter> _textCache = {};
  static const int _textCacheMaxSize = 64;

  /// 🚀 OPT-7: Pre-computed MaskFilter buckets for fog particles.
  /// Avoids allocating a new MaskFilter per particle per frame.
  /// 4 buckets cover radius ranges: ~16, ~22, ~28, ~34 px.
  static final List<MaskFilter> _particleBlurBuckets = [
    const MaskFilter.blur(BlurStyle.normal, 12.8),  // baseRadius ~16
    const MaskFilter.blur(BlurStyle.normal, 17.6),  // baseRadius ~22
    const MaskFilter.blur(BlurStyle.normal, 22.4),  // baseRadius ~28
    const MaskFilter.blur(BlurStyle.normal, 27.2),  // baseRadius ~34
  ];

  /// Pick the closest pre-computed blur bucket for a given radius.
  static MaskFilter _blurForRadius(double radius) {
    if (radius < 19) return _particleBlurBuckets[0];
    if (radius < 25) return _particleBlurBuckets[1];
    if (radius < 31) return _particleBlurBuckets[2];
    return _particleBlurBuckets[3];
  }

  /// OPT-4: Lazy cluster lookup map — built once per paint call.
  Map<String, ContentCluster>? _clusterMapCache;
  Map<String, ContentCluster> get _clusterMap {
    if (_clusterMapCache != null) return _clusterMapCache!;
    final map = <String, ContentCluster>{};
    for (final c in clusters) {
      map[c.id] = c;
    }
    return _clusterMapCache = map;
  }

  /// OPT-1: Get or create a cached TextPainter.
  static TextPainter _cachedTextPainter(
    String text,
    double fontSize, {
    Color color = const Color(0xFF000000),
    FontWeight fontWeight = FontWeight.normal,
    double maxWidth = double.infinity,
  }) {
    final key = '$text|$fontSize|${color.toARGB32()}|${fontWeight.index}';
    final cached = _textCache[key];
    if (cached != null) return cached;

    // Evict oldest if at capacity.
    if (_textCache.length >= _textCacheMaxSize) {
      _textCache.remove(_textCache.keys.first);
    }

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    _textCache[key] = tp;
    return tp;
  }

  FogOfWarOverlayPainter({
    required this.controller,
    required this.clusters,
    required this.canvasScale,
    required this.animationTime,
    required this.viewportCenterCanvas,
    required this.viewportCanvasRect,
    this.isDarkMode = false,
    this.isMuroRossoActive = false,
    this.surgicalPathNodeIds = const [],
    this.surgicalVisitedIds = const {},
  });

  // All UI elements (badges, labels, rings) are painted in pure canvas-space
  // with fixed dimensions — they scale naturally with zoom, exactly like
  // strokes. No zoom compensation (_s / _paintScreenSpace) is applied.

  @override
  void paint(Canvas canvas, Size size) {
    final zone = controller.selectedZone;
    if (zone == null) return;

    final phase = controller.phase;

    if (phase == FogPhase.active) {
      _paintActiveFog(canvas, zone);
    } else if (phase == FogPhase.revealing) {
      _paintRevealingFog(canvas, zone);
    } else if (phase == FogPhase.masteryMap) {
      _paintMasteryMap(canvas);
      // 🗺️ Surgical Path overlay — drawn on top of mastery map.
      if (surgicalPathNodeIds.isNotEmpty) {
        _paintSurgicalPath(canvas);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVE FOG — The 3 density levels
  // ─────────────────────────────────────────────────────────────────────────
  // 🚀 OPT-4: Static Paint for saveLayer — avoid allocation per frame.
  static final Paint _saveLayerPaint = Paint();

  void _paintActiveFog(Canvas canvas, Rect zone) {
    final fogLevel = controller.fogLevel;
    final revealed = controller.revealedNodeIds;
    final hasRevealed = revealed.isNotEmpty;

    // 🚀 OPT-1: Only use saveLayer when we need to punch holes.
    // saveLayer is expensive on mobile GPUs (offscreen buffer allocation).
    if (hasRevealed) {
      canvas.saveLayer(zone, _saveLayerPaint);
    }

    switch (fogLevel) {
      case FogLevel.light:
        _paintLightFog(canvas, zone);
      case FogLevel.medium:
        _paintMediumFog(canvas, zone);
      case FogLevel.total:
        _paintTotalFog(canvas, zone);
    }

    // 🚀 OPT-3: Single-pass cluster iteration for both punch + border.
    if (hasRevealed) {
      for (final cluster in clusters) {
        if (!_isInViewport(cluster)) continue;
        if (!revealed.contains(cluster.id)) continue;
        _punchRevealHole(canvas, cluster);
      }
      canvas.restore(); // end saveLayer

      // Borders outside saveLayer (so they render on top).
      for (final cluster in clusters) {
        if (!_isInViewport(cluster)) continue;
        if (!revealed.contains(cluster.id)) continue;
        _paintRevealedNodeBorder(canvas, cluster);
      }
    }

    // 🌀 FOG PARTICLES — atmospheric drift animation.
    _paintFogParticles(canvas, zone, fogLevel);
  }

  /// Nebbia Leggera (P10-05): silhouettes visible, content hidden.
  void _paintLightFog(Canvas canvas, Rect zone) {
    // Fully opaque overlay — content must be COMPLETELY invisible.
    // Only the silhouettes painted on top by the painter are visible.
    _fogPaint
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(10, 10, 20, 0.97)
          : const Color.fromRGBO(20, 20, 40, 0.96);
    canvas.drawRect(zone, _fogPaint);

    // Node silhouettes: subtle rounded rects so you know WHERE nodes are.
    for (final cluster in clusters) {
      if (!_isInViewport(cluster)) continue;
      if (controller.revealedNodeIds.contains(cluster.id)) continue;

      final bounds = cluster.bounds;
      final rrect = RRect.fromRectAndRadius(
        bounds,
        const Radius.circular(12.0),
      );

      // Desaturated silhouette fill (P10-05).
      _p
        ..style = PaintingStyle.fill
        ..color = isDarkMode
            ? const Color.fromRGBO(80, 80, 100, 0.22)
            : const Color.fromRGBO(100, 100, 120, 0.20);
      canvas.drawRRect(rrect, _p);

      // Faint border.
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = isDarkMode
            ? const Color.fromRGBO(100, 100, 130, 0.18)
            : const Color.fromRGBO(120, 120, 140, 0.15);
      canvas.drawRRect(rrect, _p);
    }
  }

  /// Nebbia Media: uniform fog with faint silhouettes everywhere.
  ///
  /// Pedagogical design (§5 Desirable Difficulties):
  /// - Stronger overlay than light fog → silhouettes are barely visible
  /// - Student knows roughly WHERE nodes are but must work harder to
  ///   distinguish them from the fog
  /// - Content is fully hidden → must recall WHAT each node contains
  /// - No circles, no radius, no torch — uniform difficulty across the zone
  ///
  /// Difficulty gradient across the 3 levels:
  ///   Light:  clear silhouettes (opacity 0.20) → easy to locate nodes
  ///   Medium: faint silhouettes (opacity 0.10) → must squint to find them
  ///   Total:  zero silhouettes → must remember from scratch
  void _paintMediumFog(Canvas canvas, Rect zone) {
    // Fully opaque overlay — content must be COMPLETELY invisible.
    _fogPaint
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(8, 8, 16, 0.97)
          : const Color.fromRGBO(15, 15, 30, 0.96);
    canvas.drawRect(zone, _fogPaint);

    // Very faint silhouettes — barely visible, forces the student to
    // actively search rather than passively scan.
    for (final cluster in clusters) {
      if (!_isInViewport(cluster)) continue;
      if (controller.revealedNodeIds.contains(cluster.id)) continue;

      final bounds = cluster.bounds;
      final rrect = RRect.fromRectAndRadius(
        bounds,
        const Radius.circular(12.0),
      );

      // Much fainter than light fog (0.10 vs 0.20).
      _p
        ..style = PaintingStyle.fill
        ..color = isDarkMode
            ? const Color.fromRGBO(80, 80, 100, 0.10)
            : const Color.fromRGBO(100, 100, 120, 0.09);
      canvas.drawRRect(rrect, _p);

      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = isDarkMode
            ? const Color.fromRGBO(100, 100, 130, 0.08)
            : const Color.fromRGBO(120, 120, 140, 0.07);
      canvas.drawRRect(rrect, _p);
    }
  }

  /// Nebbia Totale (P10-07): pitch black, nodes only on exact tap.
  void _paintTotalFog(Canvas canvas, Rect zone) {
    // Fully opaque — zero light leaks, even at extreme zoom.
    _fogPaint
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(5, 5, 10, 1.0)
          : const Color.fromRGBO(10, 10, 15, 1.0);
    canvas.drawRect(zone, _fogPaint);

    // Zero visual cues. No silhouettes. No borders. Nothing.
    // The only way to find nodes is to tap exactly on them.
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REVEALED NODE — Visible during active fog (P10-09)
  // ─────────────────────────────────────────────────────────────────────────

  /// Punch a transparent hole in the fog layer for a revealed node.
  void _punchRevealHole(Canvas canvas, ContentCluster cluster) {
    final bounds = cluster.bounds.inflate(8.0);
    final rrect = RRect.fromRectAndRadius(bounds, Radius.circular(12.0));

    _p
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF000000)
      ..blendMode = BlendMode.clear;
    canvas.drawRRect(rrect, _p);
    _p.blendMode = BlendMode.srcOver;
  }

  /// Paint border/glow decoration on top of fog for revealed nodes.
  void _paintRevealedNodeBorder(Canvas canvas, ContentCluster cluster) {
    final bounds = cluster.bounds.inflate(6.0);
    final rrect = RRect.fromRectAndRadius(bounds, Radius.circular(12.0));

    // Subtle glow to mark it as discovered.
    _p
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(40, 50, 80, 0.15)
          : const Color.fromRGBO(200, 210, 240, 0.1)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16.0);
    canvas.drawRRect(rrect.inflate(8.0), _p);
    _p.maskFilter = null;

    // Thin breathing border indicating "discovered territory".
    final breathe = 0.7 + 0.3 * math.sin(animationTime * 1.5);
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Color.fromRGBO(130, 160, 255, 0.4 * breathe);
    canvas.drawRRect(rrect, _p);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CINEMATIC REVEAL (P10-18)
  // ─────────────────────────────────────────────────────────────────────────

  // 🚀 PERF: Reusable Paint for reveal gradient — avoids per-frame allocation.
  static final Paint _revealHolePaint = Paint()..blendMode = BlendMode.dstOut;
  static const MaskFilter _revealGlowBlur =
      MaskFilter.blur(BlurStyle.normal, 10.0);
  static const MaskFilter _revealPopBlur =
      MaskFilter.blur(BlurStyle.normal, 6.0);

  void _paintRevealingFog(Canvas canvas, Rect zone) {
    final progress = controller.revealProgress;
    if (progress >= 1.0) return;

    final center = zone.center;
    final maxRadius =
        math.sqrt(zone.width * zone.width + zone.height * zone.height) / 2;
    final easedProgress = Curves.easeOutCubic.transform(progress);
    final clearRadius = maxRadius * easedProgress;

    // 🚀 ZERO-ALLOC REVEAL: No saveLayer, no shader allocation, no clipPath.
    //
    // Strategy: draw the fog as a thick ring (donut) whose inner radius
    // grows outward. This is achieved by clipping OUT the clear circle
    // using an inverted path (rect + counterclockwise oval), then drawing
    // a simple filled rect. Only 1 drawRect + 1 clipPath per frame.
    //
    // The feathered edge is simulated by drawing a second translucent ring
    // at the boundary — much cheaper than a gradient shader.

    // Build inverted clip path: everything OUTSIDE the clear circle.
    final clearRect = Rect.fromCircle(center: center, radius: clearRadius);
    final clipPath = Path()
      ..addRect(zone)
      ..addOval(clearRect)
      ..fillType = PathFillType.evenOdd;

    canvas.save();
    canvas.clipPath(clipPath);

    // Fog fill — simple rect, no saveLayer.
    _fogPaint
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(8, 8, 16, 0.85)
          : const Color.fromRGBO(15, 15, 30, 0.80);
    canvas.drawRect(zone, _fogPaint);

    canvas.restore();

    // Feathered edge — a soft translucent ring at the boundary.
    // Drawn as a thick stroke with low opacity, simulating gradient.
    if (clearRadius > 5.0) {
      final featherWidth = 30.0 + clearRadius * 0.08;
      final fogAlpha = (1.0 - easedProgress) * 0.4;
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = featherWidth
        ..color = isDarkMode
            ? Color.fromRGBO(8, 8, 16, fogAlpha)
            : Color.fromRGBO(15, 15, 30, fogAlpha);
      canvas.drawCircle(center, clearRadius + featherWidth * 0.3, _p);
    }

    // Glow ring at the reveal boundary — thin crisp line, no blur.
    if (progress > 0.03 && progress < 0.92) {
      final glowAlpha = (1.0 - progress) * 0.3;
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = isDarkMode
            ? Color.fromRGBO(160, 190, 255, glowAlpha)
            : Color.fromRGBO(120, 150, 230, glowAlpha);
      canvas.drawCircle(center, clearRadius, _p);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MASTERY MAP (P10-19 → P10-22)
  // ─────────────────────────────────────────────────────────────────────────

  void _paintMasteryMap(Canvas canvas) {
    final entries = controller.nodeEntries;
    final priorFailures = controller.priorFailureNodeIds;

    for (final cluster in clusters) {
      if (!_isInViewport(cluster)) continue;

      final entry = entries[cluster.id];
      if (entry == null) continue;

      // P10-21: Check if this node was explored during mastery map.
      final isExplored = controller.isMasteryExplored(cluster.id);
      // 🧠 Partial Zone Memory: Was this node a failure in the prior session?
      final wasPriorFailure = priorFailures.contains(cluster.id);

      switch (entry.status) {
        case FogNodeStatus.recalled:
          _paintMasteryNode(canvas, cluster, _MasteryStyle.recalled,
              confidence: entry.confidence, responseTime: entry.responseTime,
              wasPriorFailure: wasPriorFailure);
        case FogNodeStatus.forgotten:
          _paintMasteryNode(canvas, cluster, _MasteryStyle.forgotten,
              isExplored: isExplored, wasPriorFailure: wasPriorFailure);
        case FogNodeStatus.blindSpot:
          _paintMasteryNode(canvas, cluster, _MasteryStyle.blindSpot,
              isExplored: isExplored, wasPriorFailure: wasPriorFailure);
        case FogNodeStatus.hidden:
          _paintMasteryNode(canvas, cluster, _MasteryStyle.blindSpot,
              isExplored: isExplored, wasPriorFailure: wasPriorFailure);
      }
    }
  }

  void _paintMasteryNode(
    Canvas canvas,
    ContentCluster cluster,
    _MasteryStyle style, {
    int? confidence,
    Duration? responseTime,
    bool isExplored = false,
    bool wasPriorFailure = false,
  }) {
    final bounds = cluster.bounds.inflate(8.0);
    final rrect = RRect.fromRectAndRadius(bounds, Radius.circular(12.0));

    // Ring color and opacity (P10-19: 30%).
    Color ringColor;
    String emoji;
    bool isDashed;

    switch (style) {
      case _MasteryStyle.recalled:
        final conf = (confidence ?? 5).clamp(3, 5);
        final greenAlpha = isMuroRossoActive
            ? 0.5 + (conf - 3) * 0.15
            : 0.35 + (conf - 3) * 0.15;
        ringColor = Color.fromRGBO(76, 175, 80, greenAlpha);
        emoji = conf == 5 ? '✅' : conf == 4 ? '😊' : '🤔';
        isDashed = false;
      case _MasteryStyle.forgotten:
        ringColor = isMuroRossoActive
            ? const Color.fromRGBO(158, 158, 158, 0.45)
            : const Color.fromRGBO(244, 67, 54, 0.6);
        emoji = isExplored
            ? '📖'
            : isMuroRossoActive ? '📝' : '❌';
        isDashed = false;
      case _MasteryStyle.blindSpot:
        ringColor = const Color.fromRGBO(158, 158, 158, 0.5);
        emoji = isExplored ? '📖' : '👁\u200D🗨';
        isDashed = !isExplored;
    }

    // P10-21: Explored nodes get a subtle "discovered" tint.
    if (isExplored) {
      _p
        ..style = PaintingStyle.fill
        ..color = const Color.fromRGBO(100, 140, 255, 0.08)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8.0);
      canvas.drawRRect(rrect.inflate(4.0), _p);
      _p.maskFilter = null;
    }

    // Background tint.
    _p
      ..style = PaintingStyle.fill
      ..color = ringColor.withValues(alpha: 0.12);
    canvas.drawRRect(rrect, _p);

    // Ring (solid or dashed).
    if (isDashed) {
      _paintDashedRRect(canvas, rrect, ringColor, 2.5);
    } else {
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = isExplored ? 1.5 : 2.5
        ..color = ringColor;
      canvas.drawRRect(rrect, _p);
    }

    // 🧠 Partial Zone Memory: Extra amber warning ring for prior failures.
    if (wasPriorFailure) {
      _auxPaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color.fromRGBO(255, 183, 77, 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0);
      canvas.drawRRect(rrect.inflate(4.0), _auxPaint);
      _auxPaint.maskFilter = null;
    }

    // Badge emoji at top-right corner — canvas-space, scales with zoom.
    const badgeSize = 18.0;
    final badgePos = Offset(
      bounds.right - badgeSize * 0.4,
      bounds.top - badgeSize * 0.4,
    );
    _p
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(20, 20, 30, 0.9)
          : const Color.fromRGBO(255, 255, 255, 0.95);
    canvas.drawCircle(badgePos, badgeSize * 0.7, _p);
    _paintEmoji(canvas, badgePos, emoji, badgeSize * 0.75);

    // Blind spot label (P10-20).
    if (style == _MasteryStyle.blindSpot && !isExplored) {
      _paintLabel(canvas, bounds, 'Non cercato',
          const Color.fromRGBO(158, 158, 158, 0.7));
    }

    // ⏱️ Slow recall indicator — canvas-space.
    if (style == _MasteryStyle.recalled &&
        responseTime != null &&
        responseTime.inSeconds >= 8) {
      const timerSize = 14.0;
      final timerPos = Offset(
        bounds.left + timerSize * 0.4,
        bounds.top - timerSize * 0.4,
      );
      _p
        ..style = PaintingStyle.fill
        ..color = isDarkMode
            ? const Color.fromRGBO(20, 20, 30, 0.9)
            : const Color.fromRGBO(255, 255, 255, 0.95);
      canvas.drawCircle(timerPos, timerSize * 0.65, _p);
      _paintEmoji(canvas, timerPos, '⏱️', timerSize * 0.7);
    }

    // Confidence label for recalled nodes.
    if (style == _MasteryStyle.recalled && confidence != null) {
      _paintLabel(canvas, bounds, '$confidence/5',
          Color.fromRGBO(76, 175, 80, confidence >= 4 ? 0.6 : 0.4));
    }

    // 🧠 Partial Zone Memory: "Critico l'ultima volta" label — canvas-space.
    if (wasPriorFailure && style != _MasteryStyle.recalled) {
      const warningFontSize = 9.0;
      final tp = _cachedTextPainter(
        '⚠️ critico l\'ultima volta',
        warningFontSize,
        color: const Color.fromRGBO(255, 183, 77, 0.8),
        fontWeight: FontWeight.w600,
        maxWidth: bounds.width + 60,
      );
      final labelPos = Offset(bounds.left, bounds.bottom + 20.0);
      final pillRect = Rect.fromLTWH(
        labelPos.dx - 4, labelPos.dy - 2,
        tp.width + 8, tp.height + 4,
      );
      _p
        ..style = PaintingStyle.fill
        ..color = isDarkMode
            ? const Color.fromRGBO(25, 20, 10, 0.85)
            : const Color.fromRGBO(255, 248, 230, 0.9);
      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(5)),
        _p,
      );
      tp.paint(canvas, labelPos);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🌀 FOG PARTICLES — Atmospheric drift animation
  // ─────────────────────────────────────────────────────────────────────────

  /// Renders drifting fog particles across the fog zone for immersive atmosphere.
  ///
  /// Uses deterministic pseudo-random seeding (golden ratio) for consistent
  /// particle placement. Motion is driven by [animationTime] via sin/cos
  /// displacement — no extra animation controller needed.
  void _paintFogParticles(Canvas canvas, Rect zone, FogLevel fogLevel) {
    // Particle count and opacity vary by density.
    final int count;
    final double baseAlpha;
    final double baseRadius;
    switch (fogLevel) {
      case FogLevel.light:
        count = 15;
        baseAlpha = 0.06;
        baseRadius = 20.0;
      case FogLevel.medium:
        count = 22;
        baseAlpha = 0.10;
        baseRadius = 28.0;
      case FogLevel.total:
        count = 30;
        baseAlpha = 0.14;
        baseRadius = 35.0;
    }

    // Clamp to viewport for performance.
    final drawZone = viewportCanvasRect.intersect(zone);
    if (drawZone.isEmpty) return;

    final t = animationTime;

    for (int i = 0; i < count; i++) {
      // Golden-ratio seed for even distribution.
      final seed = (i * 0.618033988749895) % 1.0;
      final seed2 = ((i + 7) * 0.381966011250105) % 1.0;

      // Base position across the zone.
      final baseX = zone.left + seed * zone.width;
      final baseY = zone.top + seed2 * zone.height;

      // Perlin-like drift: each particle has a unique phase.
      final phase = i * 1.7;
      final driftX = math.sin(t * 0.15 + phase) * 60.0 +
          math.cos(t * 0.08 + phase * 0.5) * 30.0;
      final driftY = math.cos(t * 0.12 + phase * 0.7) * 40.0 +
          math.sin(t * 0.06 + phase * 0.3) * 25.0;

      final x = baseX + driftX;
      final y = baseY + driftY;

      // Skip if outside viewport.
      if (x < drawZone.left - 50 || x > drawZone.right + 50) continue;
      if (y < drawZone.top - 50 || y > drawZone.bottom + 50) continue;

      // Pulsing opacity: each particle breathes independently.
      final breathe = 0.6 + 0.4 * math.sin(t * 0.3 + phase * 1.3);
      final alpha = baseAlpha * breathe;

      // Varying radius.
      final radius = baseRadius + 8.0 * math.sin(t * 0.2 + phase * 0.9);

      // 🚀 OPT-7: Use pre-computed blur bucket instead of per-particle allocation.
      _p
        ..style = PaintingStyle.fill
        ..color = isDarkMode
            ? Color.fromRGBO(180, 190, 220, alpha)
            : Color.fromRGBO(120, 130, 160, alpha)
        ..maskFilter = _blurForRadius(radius);
      canvas.drawCircle(Offset(x, y), radius, _p);
      _p.maskFilter = null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🗺️ SURGICAL PATH (P10-24) — Guided review path overlay
  // ─────────────────────────────────────────────────────────────────────────

  /// Renders the guided review path: solid lines connecting critical nodes,
  /// small sequence dots OUTSIDE node bounds, and a clear current-target
  /// indicator that doesn't overlap content.
  void _paintSurgicalPath(Canvas canvas) {
    // OPT-4: Use cached cluster map instead of rebuilding per-frame.
    final pathClusters = <ContentCluster>[];
    for (final id in surgicalPathNodeIds) {
      final c = _clusterMap[id];
      if (c != null) pathClusters.add(c);
    }
    if (pathClusters.isEmpty) return;

    // OPT-5: Inflated viewport for culling segments/nodes.
    final vpInflated = viewportCanvasRect.inflate(100.0);
    final t = animationTime;

    // ── 1. Connecting Lines — solid with gradient progress ──
    for (int i = 0; i < pathClusters.length - 1; i++) {
      final from = pathClusters[i].bounds.center;
      final to = pathClusters[i + 1].bounds.center;

      final segBounds = Rect.fromPoints(from, to);
      if (!vpInflated.overlaps(segBounds)) continue;

      final fromVisited = surgicalVisitedIds.contains(pathClusters[i].id);
      final toVisited = surgicalVisitedIds.contains(pathClusters[i + 1].id);
      final bothVisited = fromVisited && toVisited;

      // Completed segments: solid green. Pending: dashed subtle grey.
      if (bothVisited) {
        _auxPaint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color.fromRGBO(76, 175, 80, 0.5)
          ..strokeCap = StrokeCap.round
          ..maskFilter = null;
        canvas.drawLine(from, to, _auxPaint);
      } else {
        _paintDashedLine(canvas, from, to,
            const Color.fromRGBO(158, 158, 158, 0.3), (1.5));
      }

      // Arrow indicator on pending segments (midpoint arrow).
      if (!bothVisited && fromVisited) {
        final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
        final dir = (to - from);
        final len = dir.distance;
        if (len > 10) {
          final dx = dir.dx / len;
          final dy = dir.dy / len;
          final arrowSize = (8.0);
          final pulse = 0.6 + 0.4 * math.sin(t * 2.5);

          final tip = mid + Offset(dx * arrowSize, dy * arrowSize);
          final left = mid + Offset(
            -dx * arrowSize * 0.5 + dy * arrowSize * 0.5,
            -dy * arrowSize * 0.5 - dx * arrowSize * 0.5,
          );
          final right = mid + Offset(
            -dx * arrowSize * 0.5 - dy * arrowSize * 0.5,
            -dy * arrowSize * 0.5 + dx * arrowSize * 0.5,
          );
          final arrowPath = Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(left.dx, left.dy)
            ..lineTo(right.dx, right.dy)
            ..close();

          _p
            ..style = PaintingStyle.fill
            ..color = Color.fromRGBO(255, 152, 0, pulse * 0.7);
          canvas.drawPath(arrowPath, _p);
        }
      }
    }

    // ── 2. Node markers — small dots BELOW the node, not overlapping ──
    for (int i = 0; i < pathClusters.length; i++) {
      final cluster = pathClusters[i];
      if (!vpInflated.overlaps(cluster.bounds)) continue;

      final isVisited = surgicalVisitedIds.contains(cluster.id);
      final isCurrentTarget = !isVisited &&
          (i == 0 || surgicalVisitedIds.contains(pathClusters[i > 0 ? i - 1 : 0].id));

      // Small sequence dot BELOW the node — canvas-space.
      const dotRadius = 9.0;
      final dotPos = Offset(
        cluster.bounds.center.dx,
        cluster.bounds.bottom + dotRadius * 2.5,
      );
      final dotColor = isVisited
          ? const Color.fromRGBO(76, 175, 80, 0.85)
          : isCurrentTarget
              ? const Color.fromRGBO(255, 152, 0, 0.9)
              : const Color.fromRGBO(158, 158, 158, 0.5);
      final label = isVisited ? '✓' : '${i + 1}';

      _p
        ..style = PaintingStyle.fill
        ..color = dotColor;
      canvas.drawCircle(dotPos, dotRadius, _p);

      final fontSize = dotRadius * 0.85;
      final tp = _cachedTextPainter(
        label, fontSize,
        color: const Color(0xFFFFFFFF),
        fontWeight: FontWeight.w800,
      );
      tp.paint(canvas, dotPos - Offset(tp.width / 2, tp.height / 2));

      // Current target: highlighted border around the node.
      if (isCurrentTarget) {
        final pulse = 0.5 + 0.5 * math.sin(t * 2.0);
        final highlightRect = cluster.bounds.inflate(10.0);
        final rrect = RRect.fromRectAndRadius(
          highlightRect,
          Radius.circular(12.0),
        );

        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..color = Color.fromRGBO(255, 152, 0, pulse * 0.4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6.0);
        canvas.drawRRect(rrect, _p);
        _p.maskFilter = null;

        _p
          ..strokeWidth = 2.0
          ..color = Color.fromRGBO(255, 152, 0, 0.5 + pulse * 0.3);
        canvas.drawRRect(rrect, _p);
      }
    }
  }

  /// Draws a dashed line between two points.
  void _paintDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Color color,
    double width,
  ) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1.0) return;

    // OPT-2: Reuse _auxPaint.
    _auxPaint
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color
      ..strokeCap = StrokeCap.round
      ..maskFilter = null;

    const dashLen = 12.0;
    const gapLen = 8.0;
    final unitX = dx / length;
    final unitY = dy / length;

    double dist = 0;
    bool draw = true;
    while (dist < length) {
      final end = (dist + (draw ? dashLen : gapLen)).clamp(0.0, length);
      if (draw) {
        canvas.drawLine(
          Offset(from.dx + unitX * dist, from.dy + unitY * dist),
          Offset(from.dx + unitX * end, from.dy + unitY * end),
          _auxPaint,
        );
      }
      dist = end;
      draw = !draw;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether a cluster is within the visible viewport (culling).
  bool _isInViewport(ContentCluster cluster) {
    return viewportCanvasRect.overlaps(cluster.bounds.inflate(50.0));
  }

  void _paintDashedRRect(
    Canvas canvas,
    RRect rrect,
    Color color,
    double width,
  ) {
    final path = Path()..addRRect(rrect);
    // OPT-2: Reuse _auxPaint.
    _auxPaint
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color
      ..maskFilter = null;

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      const dashLen = 10.0;
      const gapLen = 6.0;
      bool draw = true;
      while (distance < metric.length) {
        final end = distance + (draw ? dashLen : gapLen);
        if (draw) {
          final extractPath = metric.extractPath(
            distance,
            end.clamp(0, metric.length),
          );
          canvas.drawPath(extractPath, _auxPaint);
        }
        distance = end;
        draw = !draw;
      }
    }
  }

  void _paintEmoji(Canvas canvas, Offset center, String emoji, double size) {
    final tp = _cachedTextPainter(emoji, size);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintLabel(Canvas canvas, Rect bounds, String text, Color color) {
    const fontSize = 10.0;
    final tp = _cachedTextPainter(
      text,
      fontSize,
      color: color,
      fontWeight: FontWeight.w500,
      maxWidth: bounds.width + 40,
    );

    final labelPos = Offset(
      bounds.center.dx - tp.width / 2,
      bounds.bottom + 6.0,
    );

    // Background pill.
    final pillRect = Rect.fromLTWH(
      labelPos.dx - 6, labelPos.dy - 2,
      tp.width + 12, tp.height + 4,
    );
    _p
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(25, 25, 35, 0.75)
          : const Color.fromRGBO(255, 255, 255, 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, const Radius.circular(7)),
      _p,
    );
    tp.paint(canvas, labelPos);
  }

  @override
  SemanticsBuilderCallback? get semanticsBuilder {
    // Only provide semantics during mastery map phase.
    if (controller.phase != FogPhase.masteryMap) return null;

    return (Size size) {
      final nodes = <CustomPainterSemantics>[];
      final entries = controller.nodeEntries;

      for (final cluster in clusters) {
        final entry = entries[cluster.id];
        if (entry == null) continue;

        // Build descriptive label.
        final parts = <String>[];

        switch (entry.status) {
          case FogNodeStatus.recalled:
            parts.add('Nodo ricordato');
            if (entry.confidence != null) {
              parts.add('confidenza ${entry.confidence} su 5');
            }
            if (entry.responseTime != null) {
              parts.add(
                'tempo risposta ${entry.responseTime!.inSeconds} secondi',
              );
              if (entry.responseTime!.inSeconds >= 8) {
                parts.add('consolidamento fragile');
              }
            }
          case FogNodeStatus.forgotten:
            parts.add('Nodo dimenticato');
          case FogNodeStatus.blindSpot:
            parts.add('Punto cieco, non visitato durante la sessione');
          case FogNodeStatus.hidden:
            parts.add('Nodo nascosto');
        }

        // Cross-session marker.
        if (controller.priorFailureNodeIds.contains(cluster.id)) {
          parts.add('critico nella sessione precedente');
        }

        // Explored marker.
        if (controller.isMasteryExplored(cluster.id)) {
          parts.add('contenuto rivelato');
        }

        nodes.add(CustomPainterSemantics(
          rect: cluster.bounds.inflate(8.0),
          properties: SemanticsProperties(
            label: parts.join(', '),
            textDirection: TextDirection.ltr,
          ),
        ));
      }

      return nodes;
    };
  }

  @override
  bool shouldRepaint(covariant FogOfWarOverlayPainter oldDelegate) {
    // OPT-4: Invalidate cluster map cache when clusters change.
    if (!identical(clusters, oldDelegate.clusters)) {
      _clusterMapCache = null;
    }

    // OPT-3: Complete set of comparisons.
    return controller.phase != oldDelegate.controller.phase ||
        controller.revealedNodeIds.length !=
            oldDelegate.controller.revealedNodeIds.length ||
        controller.revealProgress != oldDelegate.controller.revealProgress ||
        (animationTime - oldDelegate.animationTime).abs() > 0.016 ||
        viewportCenterCanvas != oldDelegate.viewportCenterCanvas ||
        viewportCanvasRect != oldDelegate.viewportCanvasRect ||
        isDarkMode != oldDelegate.isDarkMode ||
        isMuroRossoActive != oldDelegate.isMuroRossoActive ||
        surgicalPathNodeIds.length != oldDelegate.surgicalPathNodeIds.length ||
        surgicalVisitedIds.length != oldDelegate.surgicalVisitedIds.length;
  }
}

/// Internal mastery heatmap visual classification.
enum _MasteryStyle {
  recalled,
  forgotten,
  blindSpot,
}
