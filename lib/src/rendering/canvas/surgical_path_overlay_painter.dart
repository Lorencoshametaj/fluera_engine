// ============================================================================
// 🩻 SURGICAL PATH OVERLAY — Sprint 6, Fog↔Exam integration
//
// Painted ABOVE the canvas (and below the exam overlay) when the Atlas exam
// was launched from the Fog of War mastery summary. Highlights:
//
//   1. Every blind-spot cluster in the original surgical plan with a soft
//      cyan glow — keeps the spatial scope visible while the student is in
//      the question card.
//   2. The cluster that the *current* question came from with a pulsing
//      orange outline — anchors each question to a node on the canvas
//      (`teoria_cognitiva_apprendimento.md` §22 spatial memory).
//   3. A directional arrow from the centre of the canvas viewport towards
//      the current cluster when it sits off-screen, so a quick zoom-out is
//      enough to find it without losing the question.
//
// Hit testing is intentionally pass-through (`hitTest` returns false): the
// canvas behind keeps responding to pinch / pan / Atlas chat taps. The
// painter is purely decorative.
//
// All rect/offset values are in **canvas (screen) coordinates** — the host
// is expected to wrap this painter in the same transform stack the canvas
// uses (`InfiniteCanvasController.transform`).
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../reflow/content_cluster.dart';

class SurgicalPathOverlayPainter extends CustomPainter {
  /// Cluster ID → live geometry. Built by the host from the same
  /// `_clusterCache` the Fog overlay reads.
  final Map<String, ContentCluster> clustersById;

  /// IDs of every cluster in the original surgical plan (forgotten +
  /// blind spots). Painted with a soft cyan glow.
  final Set<String> blindSpotClusterIds;

  /// Cluster ID the **current** exam question is sourced from. Painted
  /// with a pulsing orange outline. May be null between questions.
  final String? currentQuestionClusterId;

  /// 0..1 looped value driving the pulse animation. Caller wires this
  /// from a `RepaintBoundary`-friendly Listenable (e.g. the existing
  /// `_glowController` of the exam overlay).
  final double pulse;

  /// Visible viewport in canvas coordinates. Used to decide whether the
  /// current cluster is off-screen and an arrow should be drawn.
  final Rect visibleViewport;

  static const _cyan = Color(0xFF00E5FF);
  static const _orange = Color(0xFFFFAB40);

  const SurgicalPathOverlayPainter({
    required this.clustersById,
    required this.blindSpotClusterIds,
    required this.currentQuestionClusterId,
    required this.pulse,
    required this.visibleViewport,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (clustersById.isEmpty) return;

    // ── (1) Soft glow on every blind spot ────────────────────────────────
    final glowPaint = Paint()
      ..color = _cyan.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    final glowStroke = Paint()
      ..color = _cyan.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final id in blindSpotClusterIds) {
      final cluster = clustersById[id];
      if (cluster == null) continue;
      final rect = _padded(cluster.bounds, 6);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
      canvas.drawRRect(rrect, glowPaint);
      canvas.drawRRect(rrect, glowStroke);
    }

    // ── (2) Pulsing outline on the current question cluster ─────────────
    final current = currentQuestionClusterId == null
        ? null
        : clustersById[currentQuestionClusterId];
    if (current != null) {
      final rect = _padded(current.bounds, 8);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));

      // Pulse 0..1 → alpha 0.55..0.95, stroke 2..3.5
      final t = (math.sin(pulse * 2 * math.pi) + 1) / 2; // 0..1
      final alpha = 0.55 + 0.40 * t;
      final stroke = 2.0 + 1.5 * t;

      canvas.drawRRect(
        rrect,
        Paint()
          ..color = _orange.withValues(alpha: alpha * 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = _orange.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );

      // ── (3) Off-screen arrow ─────────────────────────────────────────
      if (!visibleViewport.overlaps(rect)) {
        _paintArrowToward(canvas, current.centroid, alpha);
      }
    }
  }

  /// Pad a rect outward by [pad] on every side. Used so the highlight
  /// floats around the cluster rather than hugging its bounds.
  Rect _padded(Rect r, double pad) =>
      Rect.fromLTRB(r.left - pad, r.top - pad, r.right + pad, r.bottom + pad);

  /// Draw a small filled-arrow from the centre of [visibleViewport] toward
  /// [target]. The arrow is anchored to the inner edge of the viewport so
  /// it's always visible.
  void _paintArrowToward(Canvas canvas, Offset target, double alpha) {
    final origin = visibleViewport.center;
    final dir = (target - origin);
    final dist = dir.distance;
    if (dist < 1.0) return;
    final unit = dir / dist;

    // Anchor 60 px from the viewport edge along the ray.
    final maxFromCenter = math.min(
          visibleViewport.width / 2,
          visibleViewport.height / 2,
        ) -
        60;
    if (maxFromCenter <= 0) return;
    final tip = origin + unit * maxFromCenter;

    // Equilateral triangle pointing at [tip], 18 px tall.
    const len = 18.0;
    final perp = Offset(-unit.dy, unit.dx);
    final base = tip - unit * len;
    final left = base + perp * (len * 0.5);
    final right = base - perp * (len * 0.5);

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = _orange.withValues(alpha: alpha),
    );
  }

  @override
  bool? hitTest(Offset position) => false; // pass-through

  @override
  bool shouldRepaint(SurgicalPathOverlayPainter old) =>
      old.pulse != pulse ||
      old.currentQuestionClusterId != currentQuestionClusterId ||
      old.blindSpotClusterIds != blindSpotClusterIds ||
      old.visibleViewport != visibleViewport ||
      !identical(old.clustersById, clustersById);
}
