import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../canvas/ai/fsrs_scheduler.dart';
import '../../canvas/ai/srs_stage_indicator.dart';
import '../../reflow/content_cluster.dart';

/// 🧠 SRS BLUR OVERLAY PAINTER — Frosted-glass blur on due-for-review clusters.
///
/// When the student returns to a canvas and clusters have SRS cards that are
/// `isDue`, this painter renders an animated frosted blur overlay on each
/// cluster. The student must tap to reveal, then self-evaluate.
///
/// Visual layers per blurred cluster:
///   1. Blur mask: `BackdropFilter`-style blur via `saveLayer` + `ImageFilter`
///   2. Frosted glass tint: semi-transparent dark/light overlay
///   3. Pulsing icon: 🔒 lock or 🧠 brain emoji indicating "tap to reveal"
///   4. After reveal: green ring (remembered) or red ring (forgot)
///
/// This painter does NOT use BackdropFilter widget (would require per-cluster
/// widgets). Instead, it uses `canvas.saveLayer` with `ImageFilter.blur()` to
/// achieve the same effect in a single CustomPaint.
class SrsBlurOverlayPainter extends CustomPainter {
  /// All clusters on the canvas.
  final List<ContentCluster> clusters;

  /// IDs of clusters that are due for review (should be blurred).
  final Set<String> blurredClusterIds;

  /// IDs of clusters that have been revealed (no longer blurred).
  final Set<String> revealedClusterIds;

  /// Reveal result: cluster ID → true (remembered) / false (forgot).
  final Map<String, bool> revealResults;

  /// Animation time in seconds (for pulsing effects).
  final double animationTime;

  /// Canvas scale (for proper sizing of UI elements).
  final double canvasScale;

  /// SRS card data per concept (for stage indicator rendering).
  /// Key: concept name, Value: card data.
  final Map<String, SrsCardData> reviewSchedule;

  /// Whether the overlay is in dark mode.
  final bool isDarkMode;

  // Reusable paints
  static final Paint _p = Paint();
  static final Paint _blurPaint = Paint();

  SrsBlurOverlayPainter({
    required this.clusters,
    required this.blurredClusterIds,
    required this.revealedClusterIds,
    required this.revealResults,
    required this.animationTime,
    required this.canvasScale,
    this.reviewSchedule = const {},
    this.isDarkMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (blurredClusterIds.isEmpty) return;

    for (final cluster in clusters) {
      if (blurredClusterIds.contains(cluster.id)) {
        if (revealedClusterIds.contains(cluster.id)) {
          // Already revealed — show result ring
          _paintRevealedRing(canvas, cluster);
        } else {
          // Still blurred — show frosted overlay
          _paintBlurOverlay(canvas, cluster);
        }
      }
    }
  }

  /// Paints the frosted-glass blur overlay on a cluster.
  void _paintBlurOverlay(Canvas canvas, ContentCluster cluster) {
    final bounds = cluster.bounds.inflate(12.0);
    final rrect = RRect.fromRectAndRadius(
      bounds,
      const Radius.circular(16.0),
    );

    // ── 1. Blur layer via saveLayer + ImageFilter ──
    // This captures everything beneath and blurs it.
    final sigma = 12.0 + 3.0 * math.sin(animationTime * 1.5);
    _blurPaint
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.decal,
      );

    canvas.saveLayer(bounds.inflate(4.0), _blurPaint);
    // Draw a filled rect to act as the blur capture area
    _p
      ..style = PaintingStyle.fill
      ..color = Colors.transparent;
    canvas.drawRRect(rrect, _p);
    canvas.restore();

    // ── 2. Frosted tint overlay ──
    final breathe = 0.85 + 0.15 * math.sin(animationTime * 2.0);
    final tintAlpha = (0.55 * breathe).clamp(0.0, 1.0);

    _p
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = isDarkMode
          ? Color.fromRGBO(20, 20, 30, tintAlpha)
          : Color.fromRGBO(240, 240, 255, tintAlpha);
    canvas.drawRRect(rrect, _p);

    // ── 3. Border (subtle glass edge) ──
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = isDarkMode
          ? Color.fromRGBO(100, 140, 255, 0.3 * breathe)
          : Color.fromRGBO(80, 120, 220, 0.25 * breathe);
    canvas.drawRRect(rrect, _p);

    // ── 4. Pulsing brain icon in the center ──
    _paintCenterIcon(canvas, bounds.center, '🧠', breathe);

    // ── 5. "Tocca per rivelare" label ──
    _paintTapLabel(canvas, bounds);

    // ── 6. SRS stage badge (top-right corner) ──
    _paintStageBadge(canvas, cluster, bounds);
  }

  /// Paints the brain icon in the center of a blurred cluster.
  void _paintCenterIcon(
    Canvas canvas,
    Offset center,
    String emoji,
    double breathe,
  ) {
    final iconSize = 28.0 / canvasScale.clamp(0.3, 2.0);
    final scale = 0.9 + 0.1 * breathe;

    // Circular glow behind icon
    _p
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? Color.fromRGBO(60, 80, 200, 0.3 * breathe)
          : Color.fromRGBO(100, 130, 255, 0.25 * breathe)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16.0);
    canvas.drawCircle(center, iconSize * 1.5 * scale, _p);
    _p.maskFilter = null;

    // Icon background circle
    _p
      ..color = isDarkMode
          ? Color.fromRGBO(30, 35, 60, 0.85)
          : Color.fromRGBO(255, 255, 255, 0.85);
    canvas.drawCircle(center, iconSize * 0.9 * scale, _p);

    // Emoji text
    final tp = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(fontSize: iconSize * scale),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      center - Offset(tp.width / 2, tp.height / 2),
    );
    tp.dispose();
  }

  /// Paints the "Tocca per rivelare" label below the cluster.
  void _paintTapLabel(Canvas canvas, Rect bounds) {
    final fontSize = 11.0 / canvasScale.clamp(0.3, 2.0);
    final tp = TextPainter(
      text: TextSpan(
        text: 'Tocca per rivelare',
        style: TextStyle(
          color: isDarkMode
              ? const Color.fromRGBO(180, 200, 255, 0.7)
              : const Color.fromRGBO(80, 100, 180, 0.6),
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    final labelPos = Offset(
      bounds.center.dx - tp.width / 2,
      bounds.bottom + 8.0,
    );

    // Background pill
    final pillRect = Rect.fromLTWH(
      labelPos.dx - 8,
      labelPos.dy - 3,
      tp.width + 16,
      tp.height + 6,
    );
    _p
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(30, 35, 50, 0.7)
          : const Color.fromRGBO(255, 255, 255, 0.8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, const Radius.circular(8)),
      _p,
    );

    tp.paint(canvas, labelPos);
    tp.dispose();
  }

  /// Paints a green/red result ring on a revealed cluster.
  void _paintRevealedRing(Canvas canvas, ContentCluster cluster) {
    final remembered = revealResults[cluster.id];
    if (remembered == null) return;

    final bounds = cluster.bounds.inflate(8.0);
    final rrect = RRect.fromRectAndRadius(
      bounds,
      const Radius.circular(14.0),
    );

    // Glow
    final color = remembered
        ? const Color(0xFF4CAF50)  // green
        : const Color(0xFFF44336); // red
    final fadeOut = (1.0 - (animationTime % 3.0) / 3.0).clamp(0.3, 1.0);

    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = color.withValues(alpha: 0.5 * fadeOut)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    canvas.drawRRect(rrect, _p);
    _p.maskFilter = null;

    // Solid ring
    _p
      ..strokeWidth = 2.5
      ..color = color.withValues(alpha: 0.8 * fadeOut);
    canvas.drawRRect(rrect, _p);

    // Small icon badge
    final emoji = remembered ? '✅' : '❌';
    final iconSize = 16.0 / canvasScale.clamp(0.3, 2.0);
    final badgePos = Offset(
      bounds.right - iconSize / 2,
      bounds.top - iconSize / 2,
    );

    // Badge background
    _p
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? const Color.fromRGBO(30, 35, 50, 0.9)
          : const Color.fromRGBO(255, 255, 255, 0.95);
    canvas.drawCircle(badgePos, iconSize * 0.8, _p);

    final tp = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(fontSize: iconSize * 0.9),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, badgePos - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  /// Paints the SRS mastery stage badge (🌱→🌿→🌳→⭐→👻) at the
  /// top-right corner of a blurred cluster.
  ///
  /// Spec P8-06: each node shows its current mastery stage icon.
  void _paintStageBadge(
    Canvas canvas,
    ContentCluster cluster,
    Rect bounds,
  ) {
    // Determine the best-matching stage for this cluster.
    // A cluster may contain multiple concepts; use the lowest stage.
    SrsStage? worstStage;
    for (final entry in reviewSchedule.entries) {
      // Match concepts to clusters via the blurred cluster IDs.
      // The SRS review session already matched concepts → clusters.
      if (!blurredClusterIds.contains(cluster.id)) continue;

      final stage = stageFromCard(entry.value);
      if (worstStage == null || stage.index < worstStage.index) {
        worstStage = stage;
      }
    }

    if (worstStage == null) return;

    final badgeRadius = 12.0 / canvasScale.clamp(0.3, 2.0);
    final badgeCenter = Offset(
      bounds.right - badgeRadius,
      bounds.top + badgeRadius,
    );

    // Badge background circle
    _p
      ..style = PaintingStyle.fill
      ..color = isDarkMode
          ? Color.fromRGBO(30, 35, 50, 0.9)
          : Color.fromRGBO(255, 255, 255, 0.95)
      ..maskFilter = null;
    canvas.drawCircle(badgeCenter, badgeRadius, _p);

    // Badge border (stage color)
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = worstStage.color.withValues(alpha: 0.7);
    canvas.drawCircle(badgeCenter, badgeRadius, _p);

    // Stage emoji
    final fontSize = badgeRadius * 1.2;
    final tp = TextPainter(
      text: TextSpan(
        text: worstStage.emoji,
        style: TextStyle(fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      badgeCenter - Offset(tp.width / 2, tp.height / 2),
    );
    tp.dispose();
  }

  @override
  bool shouldRepaint(covariant SrsBlurOverlayPainter oldDelegate) {
    // Repaint on animation time changes (for pulsing) or state changes
    return blurredClusterIds != oldDelegate.blurredClusterIds ||
        revealedClusterIds != oldDelegate.revealedClusterIds ||
        revealResults != oldDelegate.revealResults ||
        (animationTime - oldDelegate.animationTime).abs() > 0.016; // ~60fps
  }
}
