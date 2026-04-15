import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../canvas/ai/ghost_map_model.dart';
import '../../reflow/content_cluster.dart';

/// 🗺️ GHOST MAP OVERLAY PAINTER — Renders the AI-generated knowledge gap overlay.
///
/// Visual layers:
///   1. **Missing nodes**: Dashed rounded rect outline (red-orange), pulsing ❓
///      - **Hypercorrection** (P4-21): Wavy border + ⚡ icon, shown first
///      - **Below-ZPD** (P4-22): Grey dashed outline + "Da approfondire" label
///   2. **Weak nodes**: Yellow halo around existing cluster, ⚠️ badge
///   3. **Correct nodes**: Green border around existing cluster, ✅ badge
///      - **High-confidence** (P4-23): Brighter green (#00C853, 3px, 80%)
///   4. **Wrong connections** (P4-11): Yellow halo on existing connection + "?"
///   5. **Ghost connections**: Dotted Bézier curves (blue-purple)
///   6. **Revealed nodes**: Solid outline with concept text visible
///
/// Performance optimizations:
///   - Static TextPainter cache (emoji + labels) — avoids layout every frame
///   - Viewport culling — skips nodes outside visible area
///   - Reusable Paint objects (static)
///   - Cached dashed path segments per RRect hash
///   - shouldRepaint is granular: animation-only repaints don't re-layout text
class GhostMapOverlayPainter extends CustomPainter {
  /// The ghost map result from Atlas AI.
  final GhostMapResult result;

  /// Set of revealed ghost node IDs.
  final Set<String> revealedNodeIds;

  /// Existing clusters (for positioning weak/correct halos).
  final List<ContentCluster> clusters;

  /// Canvas scale (for proper sizing of UI elements).
  final double canvasScale;

  /// Animation time in seconds (for pulsing effects).
  final double animationTime;

  /// Whether the overlay is in dark mode.
  final bool isDarkMode;

  /// Set of individually dismissed ghost node IDs (P4-20).
  final Set<String> dismissedNodeIds;

  /// Optional viewport rect for culling (canvas coordinates).
  final Rect? viewportRect;

  /// 🗺️ P4-31: Set of visible missing node IDs (progressive chunking).
  /// If null, all missing nodes are shown.
  final Set<String>? visibleMissingNodeIds;

  // ─── Reusable objects (static to avoid per-frame allocation) ──────────
  static final Paint _p = Paint();
  static final Paint _dashPaint = Paint();
  static final Path _reusablePath = Path();

  // ─── Text layout cache ───────────────────────────────────────────────
  // Key: "emoji:size" or "label:text:maxWidth:size"
  // TextPainters are expensive to create+layout. Cache them across frames.
  static final Map<String, TextPainter> _textCache = {};
  static double _lastCacheScale = -1;
  static bool _lastCacheDarkMode = false;
  static const int _maxCacheSize = 64;

  /// Clear text cache when scale or dark mode changes.
  static void _ensureCacheValid(double scale, bool darkMode) {
    if ((_lastCacheScale - scale).abs() > 0.01 || _lastCacheDarkMode != darkMode) {
      for (final tp in _textCache.values) {
        tp.dispose();
      }
      _textCache.clear();
      _lastCacheScale = scale;
      _lastCacheDarkMode = darkMode;
    }
  }

  // ─── Dashed path cache ───────────────────────────────────────────────
  // Caches extracted dash segments per RRect bounds hash.
  // Invalidated when result changes (new node positions).
  static final Map<int, List<Path>> _dashCache = {};
  static GhostMapResult? _lastDashResult;

  // ─── Fix #16: Gradient shader cache ─────────────────────────────────
  // Key: boundsHash ^ quantizedBreathe ^ darkMode
  // Reduces Skia shader allocations from 300/sec to ~3/sec.
  static final Map<int, ui.Gradient> _gradientCache = {};
  static const int _maxGradientCacheSize = 32;

  GhostMapOverlayPainter({
    required this.result,
    required this.revealedNodeIds,
    required this.clusters,
    required this.canvasScale,
    required this.animationTime,
    this.isDarkMode = false,
    this.dismissedNodeIds = const {},
    this.viewportRect,
    this.visibleMissingNodeIds,
    // O-8: Localized strings passed from the widget layer
    this.labelTapToAttempt = 'Tocca per tentare',
    this.labelHypercorrection = 'Ipercorrezione — eri sicuro!',
    this.labelBelowZPD = 'Da approfondire',
    // U-1: Entry animation progress (0.0 = just appeared, 1.0+ = fully visible)
    this.entryProgress = 1.0,
  });

  /// U-1: Entry animation progress (seconds since activation).
  /// Nodes stagger their appearance based on index.
  final double entryProgress;

  /// O-8: Localized label strings (passed from widget layer with BuildContext).
  final String labelTapToAttempt;
  final String labelHypercorrection;
  final String labelBelowZPD;

  @override
  void paint(Canvas canvas, Size size) {
    if (result.nodes.isEmpty && result.connections.isEmpty) return;

    // O-12: Defensive reset — clear residual state from previous frame/painter.
    // Static Paint objects are shared; stale maskFilter/shader causes visual corruption.
    _p
      ..maskFilter = null
      ..shader = null
      ..style = PaintingStyle.fill
      ..strokeWidth = 1.0;

    // Invalidate caches if needed
    _ensureCacheValid(canvasScale, isDarkMode);
    if (!identical(_lastDashResult, result)) {
      _dashCache.clear();
      _gradientCache.clear(); // Fix #16: invalidate with new positions
      _lastDashResult = result;
    }

    // Build cluster centroid map for connection rendering
    final clusterCentroids = <String, Offset>{};
    for (final c in clusters) {
      clusterCentroids[c.id] = c.centroid;
    }

    // Also add ghost node positions
    final ghostPositions = <String, Offset>{};
    for (final node in result.nodes) {
      ghostPositions[node.id] = node.estimatedPosition;
    }

    // 1. Render ghost connections (behind nodes)
    for (final conn in result.connections) {
      _paintGhostConnection(canvas, conn, clusterCentroids, ghostPositions);
    }

    // 2. Render ghost nodes (skip dismissed ones — P4-20)
    for (int i = 0; i < result.nodes.length; i++) {
      final node = result.nodes[i];
      if (dismissedNodeIds.contains(node.id)) continue;

      // 🗺️ P4-31: Skip missing nodes not in the current visible chunk
      if (node.isMissing && visibleMissingNodeIds != null &&
          !visibleMissingNodeIds!.contains(node.id)) {
        continue;
      }

      // 🚀 Viewport culling — skip nodes outside visible area
      if (viewportRect != null && !viewportRect!.overlaps(node.bounds.inflate(40))) {
        continue;
      }

      // U-1: Staggered entry animation — each node delays 0.08s after previous
      final nodeDelay = i * 0.08;
      final nodeProgress = ((entryProgress - nodeDelay) / 0.4).clamp(0.0, 1.0);
      if (nodeProgress <= 0.0) continue; // Not yet visible

      // U-1: Apply scale + fade transform
      if (nodeProgress < 1.0) {
        // Ease-out cubic
        final t = 1.0 - math.pow(1.0 - nodeProgress, 3).toDouble();
        final center = node.bounds.center;
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.scale(t, t);
        canvas.translate(-center.dx, -center.dy);
      }

      final isRevealed = revealedNodeIds.contains(node.id);
      switch (node.status) {
        case GhostNodeStatus.missing:
          if (isRevealed) {
            _paintRevealedGhostNode(canvas, node);
          } else if (node.isBelowZPD) {
            // 🗺️ P4-22: Below-ZPD nodes get grey styling
            _paintBelowZPDNode(canvas, node);
          } else if (node.isHypercorrection) {
            // 🗺️ P4-21: Hypercorrection nodes get wavy border + ⚡
            _paintHypercorrectionNode(canvas, node);
          } else {
            _paintMissingGhostNode(canvas, node);
          }
          break;
        case GhostNodeStatus.weak:
          _paintWeakNode(canvas, node, clusterCentroids);
          break;
        case GhostNodeStatus.correct:
          if (node.isHighConfidenceCorrect) {
            // 🗺️ P4-23: High-confidence correct nodes get brighter green
            _paintHighConfidenceCorrectNode(canvas, node, clusterCentroids);
          } else {
            _paintCorrectNode(canvas, node, clusterCentroids);
          }
          break;
        case GhostNodeStatus.wrongConnection:
          // 🗺️ P4-11: Wrong connections get yellow halo + "?" icon
          _paintWrongConnectionNode(canvas, node, clusterCentroids);
          break;
      }

      // U-1: Restore canvas if we applied entry transform
      if (nodeProgress < 1.0) {
        canvas.restore();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MISSING NODE — Dashed outline with ❓ icon
  // ─────────────────────────────────────────────────────────────────────────

  void _paintMissingGhostNode(Canvas canvas, GhostNode node) {
    final bounds = node.bounds.inflate(4.0);
    final rrect = RRect.fromRectAndRadius(bounds, const Radius.circular(14.0));

    // Breathing animation
    final breathe = 0.7 + 0.3 * math.sin(animationTime * 2.0);

    // Fix #16: Cache gradient shader — quantize breathe to 10 levels
    final gradientCenter = bounds.center;
    final quantizedBreathe = (breathe * 10).round();
    final gradientKey = bounds.hashCode ^ quantizedBreathe ^ isDarkMode.hashCode;

    var shader = _gradientCache[gradientKey];
    if (shader == null) {
      if (_gradientCache.length >= _maxGradientCacheSize) {
        _gradientCache.clear(); // Evict all on overflow
      }
      shader = ui.Gradient.radial(
        gradientCenter,
        bounds.longestSide * 0.6,
        [
          isDarkMode
              ? Color.fromRGBO(255, 100, 60, 0.10 * breathe)
              : Color.fromRGBO(255, 120, 80, 0.08 * breathe),
          isDarkMode
              ? Color.fromRGBO(255, 80, 40, 0.02)
              : Color.fromRGBO(255, 100, 60, 0.01),
        ],
      );
      _gradientCache[gradientKey] = shader;
    }

    _p
      ..style = PaintingStyle.fill
      ..shader = shader;
    canvas.drawRRect(rrect, _p);
    _p.shader = null;

    // Dashed border (cached path segments)
    _paintDashedRRect(canvas, rrect, Color.fromRGBO(255, 120, 80, 0.6 * breathe), 2.0);

    // Double-ring outer glow
    final outerRrect = rrect.inflate(3.0 * breathe);
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Color.fromRGBO(255, 120, 80, 0.12 * breathe)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
    canvas.drawRRect(outerRrect, _p);
    _p.maskFilter = null;

    // Pulsing glow behind icon
    final center = bounds.center;
    final iconSize = 24.0 / canvasScale.clamp(0.3, 2.0);
    _p
      ..style = PaintingStyle.fill
      ..color = Color.fromRGBO(255, 120, 80, 0.18 * breathe)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14.0);
    canvas.drawCircle(center, iconSize * 1.3, _p);
    _p.maskFilter = null;

    // Icon background circle
    _p
      ..color = isDarkMode
          ? Color.fromRGBO(40, 25, 20, 0.85)
          : Color.fromRGBO(255, 250, 245, 0.9);
    canvas.drawCircle(center, iconSize * 0.8, _p);

    // ❓ Emoji (cached)
    _paintCachedEmoji(canvas, center, '❓', iconSize * 0.9);

    // Label (cached, O-8: localized)
    _paintCachedLabel(canvas, bounds, labelTapToAttempt,
        Color.fromRGBO(255, 140, 100, 0.7));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REVEALED NODE — Solid outline with concept text
  // ─────────────────────────────────────────────────────────────────────────

  void _paintRevealedGhostNode(Canvas canvas, GhostNode node) {
    final bounds = node.bounds.inflate(4.0);
    final rrect = RRect.fromRectAndRadius(bounds, const Radius.circular(14.0));

    final isCorrect = node.attemptCorrect == true;
    final color = isCorrect
        ? const Color(0xFF4CAF50) // green
        : const Color(0xFFFF9800); // orange

    // Background fill
    _p
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = isDarkMode
          ? color.withValues(alpha: 0.08)
          : color.withValues(alpha: 0.06);
    canvas.drawRRect(rrect, _p);

    // Solid border
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = color.withValues(alpha: 0.7);
    canvas.drawRRect(rrect, _p);

    // Concept text (cached)
    final fontSize = 11.0 / canvasScale.clamp(0.3, 2.0);
    final cacheKey = 'revealed:${node.id}:$fontSize';
    final tp = _getOrCreateText(cacheKey, () {
      return TextPainter(
        text: TextSpan(
          text: node.concept,
          style: TextStyle(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.85)
                : Colors.black87,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: bounds.width - 16);
    });
    tp.paint(canvas, Offset(
      bounds.left + 8,
      bounds.center.dy - tp.height / 2,
    ));

    // Result badge (cached)
    final emoji = isCorrect ? '✅' : '📝';
    final badgeSize = 14.0 / canvasScale.clamp(0.3, 2.0);
    final badgePos = Offset(bounds.right - badgeSize / 2, bounds.top - badgeSize / 2);
    _p
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(30, 35, 50, 0.9)
          : const Color.fromRGBO(255, 255, 255, 0.95);
    canvas.drawCircle(badgePos, badgeSize * 0.8, _p);
    _paintCachedEmoji(canvas, badgePos, emoji, badgeSize * 0.85);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WEAK NODE — Yellow halo on existing cluster
  // ─────────────────────────────────────────────────────────────────────────

  void _paintWeakNode(Canvas canvas, GhostNode node,
      Map<String, Offset> clusterCentroids) {
    final bounds = node.bounds.inflate(10.0);
    final rrect = RRect.fromRectAndRadius(bounds, const Radius.circular(12.0));
    final breathe = 0.8 + 0.2 * math.sin(animationTime * 1.8);

    // Yellow glow
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Color.fromRGBO(255, 193, 7, 0.4 * breathe)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);
    canvas.drawRRect(rrect, _p);
    _p.maskFilter = null;

    // Yellow border
    _p
      ..strokeWidth = 2.0
      ..color = Color.fromRGBO(255, 193, 7, 0.6 * breathe);
    canvas.drawRRect(rrect, _p);

    // ⚠️ Badge (cached)
    final badgeSize = 16.0 / canvasScale.clamp(0.3, 2.0);
    final badgePos = Offset(bounds.right - badgeSize / 2, bounds.top - badgeSize / 2);
    _p
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(40, 35, 15, 0.9)
          : const Color.fromRGBO(255, 255, 240, 0.95);
    canvas.drawCircle(badgePos, badgeSize * 0.8, _p);
    _paintCachedEmoji(canvas, badgePos, '⚠️', badgeSize * 0.85);

    // Explanation label (cached)
    if (node.explanation != null) {
      _paintCachedLabel(canvas, bounds, node.explanation!,
          const Color.fromRGBO(255, 193, 7, 0.7));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CORRECT NODE — Green border on existing cluster
  // ─────────────────────────────────────────────────────────────────────────

  void _paintCorrectNode(Canvas canvas, GhostNode node,
      Map<String, Offset> clusterCentroids) {
    final bounds = node.bounds.inflate(8.0);
    final rrect = RRect.fromRectAndRadius(bounds, const Radius.circular(12.0));
    final fadeIn = (animationTime % 3.0 < 1.5)
        ? (animationTime % 3.0) / 1.5
        : 1.0;

    // Shimmer glow aura
    final shimmerPhase = math.sin(animationTime * 1.2) * 0.5 + 0.5;
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = Color.fromRGBO(76, 175, 80, 0.12 * shimmerPhase)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    canvas.drawRRect(rrect.inflate(2.0), _p);
    _p.maskFilter = null;

    // Green border
    _p
      ..strokeWidth = 2.0
      ..color = Color.fromRGBO(76, 175, 80, 0.5 * fadeIn);
    canvas.drawRRect(rrect, _p);

    // ✅ Badge (cached)
    final badgeSize = 14.0 / canvasScale.clamp(0.3, 2.0);
    final badgePos = Offset(bounds.right - badgeSize / 2, bounds.top - badgeSize / 2);
    _p
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(25, 40, 25, 0.9)
          : const Color.fromRGBO(245, 255, 245, 0.95);
    canvas.drawCircle(badgePos, badgeSize * 0.8, _p);
    _paintCachedEmoji(canvas, badgePos, '✅', badgeSize * 0.85);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // P4-21: HYPERCORRECTION NODE — Wavy red border + ⚡ icon
  // ───────────────────────────────────────────────────────────────────────────

  void _paintHypercorrectionNode(Canvas canvas, GhostNode node) {
    final bounds = node.bounds.inflate(4.0);
    final rrect = RRect.fromRectAndRadius(bounds, const Radius.circular(14.0));

    // O-1: Cache gradient shader for hypercorrection node (same pattern as missing node)
    final breathe = 0.6 + 0.4 * math.sin(animationTime * 3.0);
    final quantizedBreathe = (breathe * 10).round();
    final gradientKey = bounds.hashCode ^ quantizedBreathe ^ isDarkMode.hashCode ^ 0x48C;

    var shader = _gradientCache[gradientKey];
    if (shader == null) {
      if (_gradientCache.length >= _maxGradientCacheSize) {
        _gradientCache.clear();
      }
      shader = ui.Gradient.radial(
        bounds.center,
        bounds.longestSide * 0.7,
        [
          isDarkMode
              ? Color.fromRGBO(255, 50, 30, 0.18 * breathe)
              : Color.fromRGBO(255, 60, 40, 0.14 * breathe),
          isDarkMode
              ? Color.fromRGBO(255, 30, 10, 0.03)
              : Color.fromRGBO(255, 40, 20, 0.02),
        ],
      );
      _gradientCache[gradientKey] = shader;
    }

    _p
      ..style = PaintingStyle.fill
      ..shader = shader;
    canvas.drawRRect(rrect, _p);
    _p.shader = null;

    // 🗺️ P4-21: Wavy border (simulate with multiple offset dashed paths)
    for (int wave = 0; wave < 3; wave++) {
      final waveOffset = math.sin(animationTime * 4.0 + wave * 1.2) * 2.0;
      final wavyRrect = rrect.inflate(waveOffset);
      _paintDashedRRect(
        canvas,
        wavyRrect,
        Color.fromRGBO(255, 60, 40, (0.7 - wave * 0.15) * breathe),
        2.5 - wave * 0.5,
      );
    }

    // Outer dramatic glow
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Color.fromRGBO(255, 50, 30, 0.25 * breathe)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);
    canvas.drawRRect(rrect.inflate(4.0), _p);
    _p.maskFilter = null;

    // ⚡ Icon (cached) — centered, larger than standard
    final center = bounds.center;
    final iconSize = 28.0 / canvasScale.clamp(0.3, 2.0);

    // Glow behind icon
    _p
      ..style = PaintingStyle.fill
      ..color = Color.fromRGBO(255, 60, 30, 0.25 * breathe)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16.0);
    canvas.drawCircle(center, iconSize * 1.4, _p);
    _p.maskFilter = null;

    // Icon background
    _p.color = isDarkMode
        ? Color.fromRGBO(50, 20, 15, 0.9)
        : Color.fromRGBO(255, 245, 240, 0.95);
    canvas.drawCircle(center, iconSize * 0.85, _p);

    _paintCachedEmoji(canvas, center, '⚡', iconSize * 0.95);

    // Label (O-8: localized)
    _paintCachedLabel(canvas, bounds, labelHypercorrection,
        Color.fromRGBO(255, 80, 50, 0.8));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // P4-22: BELOW-ZPD NODE — Grey dashed outline + "Da approfondire"
  // ───────────────────────────────────────────────────────────────────────────

  void _paintBelowZPDNode(Canvas canvas, GhostNode node) {
    final bounds = node.bounds.inflate(4.0);
    final rrect = RRect.fromRectAndRadius(bounds, const Radius.circular(14.0));

    // Grey fill (muted, non-urgent)
    _p
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = isDarkMode
          ? const Color.fromRGBO(136, 136, 136, 0.06)
          : const Color.fromRGBO(136, 136, 136, 0.04);
    canvas.drawRRect(rrect, _p);

    // Grey dashed border (no animation — these nodes are low priority)
    _paintDashedRRect(
      canvas,
      rrect,
      isDarkMode
          ? const Color.fromRGBO(160, 160, 160, 0.4)
          : const Color.fromRGBO(136, 136, 136, 0.4),
      1.5,
    );

    // 📚 Icon (cached)
    final center = bounds.center;
    final iconSize = 22.0 / canvasScale.clamp(0.3, 2.0);
    _p
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(45, 45, 50, 0.85)
          : const Color.fromRGBO(250, 250, 250, 0.9);
    canvas.drawCircle(center, iconSize * 0.8, _p);
    _paintCachedEmoji(canvas, center, '📚', iconSize * 0.85);

    // Label (O-8: localized)
    _paintCachedLabel(canvas, bounds, labelBelowZPD,
        isDarkMode
            ? const Color.fromRGBO(180, 180, 180, 0.6)
            : const Color.fromRGBO(120, 120, 120, 0.6));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // P4-23: HIGH-CONFIDENCE CORRECT NODE — Brighter green border
  // ───────────────────────────────────────────────────────────────────────────

  void _paintHighConfidenceCorrectNode(Canvas canvas, GhostNode node,
      Map<String, Offset> clusterCentroids) {
    final bounds = node.bounds.inflate(8.0);
    final rrect = RRect.fromRectAndRadius(bounds, const Radius.circular(12.0));
    final fadeIn = (animationTime % 3.0 < 1.5)
        ? (animationTime % 3.0) / 1.5
        : 1.0;

    // 🗺️ P4-23: Brighter shimmer glow (#00C853)
    final shimmerPhase = math.sin(animationTime * 1.2) * 0.5 + 0.5;
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..color = Color.fromRGBO(0, 200, 83, 0.2 * shimmerPhase)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);
    canvas.drawRRect(rrect.inflate(3.0), _p);
    _p.maskFilter = null;

    // Brighter green border (#00C853, 3px, 80% opacity — P4-23)
    _p
      ..strokeWidth = 3.0
      ..color = Color.fromRGBO(0, 200, 83, 0.8 * fadeIn);
    canvas.drawRRect(rrect, _p);

    // ⭐ Badge (cached) — star instead of checkmark for high confidence
    final badgeSize = 16.0 / canvasScale.clamp(0.3, 2.0);
    final badgePos = Offset(bounds.right - badgeSize / 2, bounds.top - badgeSize / 2);
    _p
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(15, 50, 25, 0.9)
          : const Color.fromRGBO(240, 255, 245, 0.95);
    canvas.drawCircle(badgePos, badgeSize * 0.8, _p);
    _paintCachedEmoji(canvas, badgePos, '⭐', badgeSize * 0.85);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // P4-11: WRONG CONNECTION NODE — Yellow halo + "?" icon
  // ───────────────────────────────────────────────────────────────────────────

  void _paintWrongConnectionNode(Canvas canvas, GhostNode node,
      Map<String, Offset> clusterCentroids) {
    final bounds = node.bounds.inflate(10.0);
    final rrect = RRect.fromRectAndRadius(bounds, const Radius.circular(12.0));
    final breathe = 0.7 + 0.3 * math.sin(animationTime * 2.2);

    // 🗺️ P4-11: Yellow halo (#FFCC00) on the erroneous connection
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = Color.fromRGBO(255, 204, 0, 0.35 * breathe)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);
    canvas.drawRRect(rrect, _p);
    _p.maskFilter = null;

    // Yellow pulsing border
    _p
      ..strokeWidth = 2.5
      ..color = Color.fromRGBO(255, 204, 0, 0.55 * breathe);
    canvas.drawRRect(rrect, _p);

    // ❓ Badge (cached) — P4-11: just "?" without correction hint
    final badgeSize = 18.0 / canvasScale.clamp(0.3, 2.0);
    final badgePos = Offset(bounds.right - badgeSize / 2, bounds.top - badgeSize / 2);
    _p
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(50, 45, 15, 0.9)
          : const Color.fromRGBO(255, 255, 230, 0.95);
    canvas.drawCircle(badgePos, badgeSize * 0.8, _p);
    _paintCachedEmoji(canvas, badgePos, '❓', badgeSize * 0.85);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GHOST CONNECTION — Dotted Bézier curve
  // ─────────────────────────────────────────────────────────────────────────

  void _paintGhostConnection(
    Canvas canvas,
    GhostConnection conn,
    Map<String, Offset> clusterCentroids,
    Map<String, Offset> ghostPositions,
  ) {
    final srcPos = clusterCentroids[conn.sourceId] ?? ghostPositions[conn.sourceId];
    final tgtPos = clusterCentroids[conn.targetId] ?? ghostPositions[conn.targetId];
    if (srcPos == null || tgtPos == null) return;

    final breathe = 0.6 + 0.4 * math.sin(animationTime * 1.5);
    final isCross = conn.isCrossDomain;

    // Compute control point for Bézier
    final midX = (srcPos.dx + tgtPos.dx) / 2;
    final midY = (srcPos.dy + tgtPos.dy) / 2;
    final dx = tgtPos.dx - srcPos.dx;
    final dy = tgtPos.dy - srcPos.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    // P4-34: Cross-domain connections curve more dramatically
    final curvature = isCross ? 50.0 : 30.0;
    final perpX = len > 0 ? -dy / len * curvature : 0.0;
    final perpY = len > 0 ? dx / len * curvature : 0.0;
    final cp = Offset(midX + perpX, midY + perpY);

    // Build dashed path (reuse path object)
    _reusablePath
      ..reset()
      ..moveTo(srcPos.dx, srcPos.dy)
      ..quadraticBezierTo(cp.dx, cp.dy, tgtPos.dx, tgtPos.dy);

    // P4-34: Cross-domain = thicker purple; regular = thin blue
    _dashPaint
      ..style = PaintingStyle.stroke
      ..strokeWidth = isCross ? 2.5 : 1.5
      ..color = isCross
          ? (isDarkMode
              ? Color.fromRGBO(180, 100, 255, 0.5 * breathe)
              : Color.fromRGBO(140, 70, 220, 0.45 * breathe))
          : (isDarkMode
              ? Color.fromRGBO(120, 140, 255, 0.4 * breathe)
              : Color.fromRGBO(100, 120, 220, 0.35 * breathe));

    // O-2: Cache dash segments per connection ID
    final connDashKey = conn.id.hashCode;
    var connSegments = _dashCache[connDashKey];
    if (connSegments == null) {
      connSegments = <Path>[];
      final metrics = _reusablePath.computeMetrics();
      for (final metric in metrics) {
        double distance = 0;
        final dashLen = isCross ? 12.0 : 8.0;
        final gapLen = isCross ? 4.0 : 6.0;
        bool draw = true;
        while (distance < metric.length) {
          final end = distance + (draw ? dashLen : gapLen);
          if (draw) {
            connSegments.add(metric.extractPath(
              distance,
              end.clamp(0, metric.length),
            ));
          }
          distance = end;
          draw = !draw;
        }
      }
      _dashCache[connDashKey] = connSegments;
    }

    for (final segment in connSegments) {
      canvas.drawPath(segment, _dashPaint);
    }

    // P4-35: Cross-domain icon (🔗) at midpoint
    if (isCross) {
      final emojiSize = 16.0 / canvasScale.clamp(0.3, 2.0);
      final crossKey = 'crossicon:${conn.id}:$emojiSize';
      final crossTp = _getOrCreateText(crossKey, () {
        return TextPainter(
          text: TextSpan(
            text: '🔗',
            style: TextStyle(fontSize: emojiSize),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      });
      crossTp.paint(canvas, Offset(
        midX - crossTp.width / 2,
        midY - crossTp.height / 2 - 18,
      ));
    }

    // Label at midpoint (cached)
    if (conn.label != null) {
      final fontSize = 9.0 / canvasScale.clamp(0.3, 2.0);
      final cacheKey = 'conn:${conn.id}:$fontSize';
      final tp = _getOrCreateText(cacheKey, () {
        return TextPainter(
          text: TextSpan(
            text: conn.label,
            style: TextStyle(
              color: isCross
                  ? (isDarkMode
                      ? Color.fromRGBO(190, 140, 255, 0.7)
                      : Color.fromRGBO(120, 60, 200, 0.6))
                  : (isDarkMode
                      ? Color.fromRGBO(160, 180, 255, 0.6)
                      : Color.fromRGBO(80, 100, 180, 0.5)),
              fontSize: fontSize,
              fontWeight: isCross ? FontWeight.w700 : FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      });

      // Background pill
      final labelPos = Offset(midX - tp.width / 2, midY - tp.height / 2 - 10);
      final pillRect = Rect.fromLTWH(
        labelPos.dx - 6, labelPos.dy - 2,
        tp.width + 12, tp.height + 4,
      );
      _p
        ..style = PaintingStyle.fill
        ..color = isDarkMode
            ? const Color.fromRGBO(20, 25, 40, 0.7)
            : const Color.fromRGBO(255, 255, 255, 0.8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(6)),
        _p,
      );
      tp.paint(canvas, labelPos);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS — Cached text rendering
  // ─────────────────────────────────────────────────────────────────────────

  /// Get or create a cached TextPainter.
  TextPainter _getOrCreateText(String key, TextPainter Function() factory) {
    var tp = _textCache[key];
    if (tp != null) return tp;

    // Evict oldest if cache is full
    if (_textCache.length >= _maxCacheSize) {
      final firstKey = _textCache.keys.first;
      _textCache[firstKey]?.dispose();
      _textCache.remove(firstKey);
    }

    tp = factory();
    _textCache[key] = tp;
    return tp;
  }

  /// Paint an emoji with TextPainter caching.
  void _paintCachedEmoji(Canvas canvas, Offset center, String emoji, double size) {
    final cacheKey = 'emoji:$emoji:${size.toStringAsFixed(1)}';
    final tp = _getOrCreateText(cacheKey, () {
      return TextPainter(
        text: TextSpan(
          text: emoji,
          style: TextStyle(fontSize: size),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  /// Paint a label with background pill and TextPainter caching.
  void _paintCachedLabel(Canvas canvas, Rect bounds, String text, Color color) {
    final fontSize = 10.0 / canvasScale.clamp(0.3, 2.0);
    final maxWidth = bounds.width + 40;
    final cacheKey = 'label:$text:${fontSize.toStringAsFixed(1)}:${maxWidth.toStringAsFixed(0)}';
    final tp = _getOrCreateText(cacheKey, () {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
    });

    final labelPos = Offset(
      bounds.center.dx - tp.width / 2,
      bounds.bottom + 6.0,
    );

    // Background pill
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

  /// Paint a dashed RRect outline with cached dash segments.
  void _paintDashedRRect(Canvas canvas, RRect rrect, Color color, double width) {
    _dashPaint
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;

    // 🚀 Use cached dash segments if available
    final boundsHash = rrect.outerRect.hashCode;
    var segments = _dashCache[boundsHash];
    if (segments == null) {
      segments = <Path>[];
      _reusablePath
        ..reset()
        ..addRRect(rrect);
      final metrics = _reusablePath.computeMetrics();
      for (final metric in metrics) {
        double distance = 0;
        const dashLen = 10.0;
        const gapLen = 6.0;
        bool draw = true;
        while (distance < metric.length) {
          final end = distance + (draw ? dashLen : gapLen);
          if (draw) {
            segments.add(metric.extractPath(
              distance,
              end.clamp(0, metric.length),
            ));
          }
          distance = end;
          draw = !draw;
        }
      }
      _dashCache[boundsHash] = segments;
    }

    for (final segment in segments) {
      canvas.drawPath(segment, _dashPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GhostMapOverlayPainter oldDelegate) {
    return result != oldDelegate.result ||
        revealedNodeIds != oldDelegate.revealedNodeIds ||
        dismissedNodeIds != oldDelegate.dismissedNodeIds ||
        isDarkMode != oldDelegate.isDarkMode ||
        (canvasScale - oldDelegate.canvasScale).abs() > 0.01 ||
        (animationTime - oldDelegate.animationTime).abs() > 0.016 ||
        // U-1: Repaint during entry animation (first ~2s)
        (entryProgress < 3.0 && entryProgress != oldDelegate.entryProgress);
  }
}
