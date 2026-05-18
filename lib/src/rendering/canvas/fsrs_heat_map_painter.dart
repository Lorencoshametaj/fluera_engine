import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../canvas/ai/srs_stage_indicator.dart';
import '../../reflow/content_cluster.dart';

/// 🌡️ FSRS HEAT-MAP PAINTER — Stage-colored rings at zoom-out.
///
/// Pedagogical contract (§1416-1420 + §183 — "specchio metacognitivo"):
/// At dezoom the student must see *what* they know and *what* they don't.
/// Each cluster gets a thin ring colored by the SrsStage of its dominant
/// (= weakest) matched concept; clusters with no FSRS match get a neutral
/// gray ring — the "nodi rossi vuoti" of §1420 (lacunas to study next).
///
/// Layer stratification at scale ≤ 0.25:
///   paper → zone tints → ink/raster → **FSRS ring** → monument pills →
///   zone labels.
///
/// Sibling of `srs_blur_overlay_painter.dart` (same matching pattern at
/// [srs_blur_overlay_painter.dart:289]) but pedagogically distinct:
///   - SRS blur is per-cluster reveal mechanic during an active review
///     session (interrupts attention).
///   - FSRS heat-map is a passive overview of the global learning state
///     (informational, never blocks input).
///
/// Resolves stage colors via [SrsStage.color] — single source of truth.
class FsrsHeatMapPainter extends CustomPainter {
  FsrsHeatMapPainter({
    required this.clusters,
    required this.clusterStages,
    required this.canvasScale,
    this.monumentIds = const <String>{},
    this.fadeOpacity = 1.0,
    this.semanticMorphProgress = 0.0,
  });

  final List<ContentCluster> clusters;

  /// Pre-resolved cluster id → SrsStage (or null = untouched / no FSRS match).
  /// Built by host via the cached `_fsrsClusterStageList()` helper so the
  /// expensive concept-match pass doesn't run per paint frame.
  final Map<String, SrsStage?> clusterStages;

  final double canvasScale;

  /// IDs of clusters classified as monuments by `MonumentResolver`. The
  /// painter applies two monument-aware rules (Fase 4 cleanup):
  /// - **Suppress colored ring**: if `monumentIds.contains(c.id) &&
  ///   clusterStages[c.id] != null`, skip the stage-colored ring + fill.
  ///   The monument pill XXL + 1.20× node boost already signal "important";
  ///   adding a stage-color ring on top is rendundant. Exception:
  ///   `stage == null` (untouched) keeps the gray ring — §1420 "monumento
  ///   ma mai studiato = lacuna importante".
  /// - **Outer inflation**: the gray "untouched" ring on a monument is
  ///   inflated extra so it sits OUTSIDE the semantic node rect (which
  ///   uses monBoost = 1.20). Without this, the ring crosses through the
  ///   semantic node glow — geometry mismatch.
  final Set<String> monumentIds;

  /// Master alpha multiplier applied to ring + fill colors. Host uses this
  /// to drive the smoothstep fade-in across the morph range (0.30 → 0.10).
  final double fadeOpacity;

  /// Semantic morph progress propagated from `SemanticMorphController`.
  ///
  /// 2026-05-17 (FX5): the FSRS ring lives in the scale band ≤ 0.25 where
  /// the DrawingPainter Tier 2 thumbnails (colored RRect, α 0.15/0.30) are
  /// also rendered until the semantic crossfade dissolves them. In the
  /// short window 0.25 → ~0.22 we end up with two colored rectangles on
  /// the same cluster area (stroke thumbnail + FSRS ring) → conflicting
  /// signal. This early-out skips the ring whenever the morph is still
  /// weak; once `semanticMorphProgress ≥ 0.3` (around scale 0.22) the
  /// thumbnails have faded (via FX1) and the ring is again the cleanest
  /// signal on top of the semantic node.
  final double semanticMorphProgress;

  /// Neutral gray for clusters not in `_reviewSchedule` — §1420 "nodi vuoti".
  static const Color _untouchedColor = Color(0xFF9E9E9E);

  /// Below this scale the ring kicks in. Above it the ink is still legible
  /// and a ring would just be noise.
  static const double kActivationScale = 0.25;

  @override
  void paint(Canvas canvas, Size size) {
    if (clusters.isEmpty) return;
    if (canvasScale > kActivationScale) return;
    if (fadeOpacity < 0.02) return;
    // FX5 — suppress the ring while the stroke Tier 2 thumbnails are still
    // visible. Once the semantic crossfade is past ~30% the thumbnails are
    // dim enough (via FX1) that the ring becomes the cleanest signal.
    if (semanticMorphProgress < 0.3) return;

    // Inverse scale to keep the ring readable at extreme dezoom.
    // 2026-05-17: ring width 2.0 → 2.8 (40% thicker) so the grey
    // "untouched" ring reads clearly on white paper at 0.20-0.25
    // where the FSRS layer first kicks in.
    final inverseScale = (1.0 / canvasScale).clamp(4.0, 24.0);
    final ringWidth = 2.8 * inverseScale;
    final inflate = 6.0 * (inverseScale * 0.25).clamp(1.0, 3.0);

    final ringPaint = Paint()..style = PaintingStyle.stroke;
    final fillPaint = Paint()..style = PaintingStyle.fill;

    // Extra inflation for monument clusters so their ring stays OUTSIDE
    // the semantic node rect (which uses monBoost=1.20). Without this
    // the ring would cross through the node glow. Canvas-space units.
    final monumentExtraInflate = 8.0 * (inverseScale * 0.20).clamp(1.0, 3.0);

    for (final cluster in clusters) {
      // Skip empty / tiny clusters — sub-perceptual at this zoom.
      if (cluster.strokeIds.length < 5) continue;
      final bounds = cluster.bounds;
      if (bounds.isEmpty || !bounds.isFinite) continue;

      final stage = clusterStages[cluster.id];
      final isMonument = monumentIds.contains(cluster.id);

      // 🏛️ Fix 1: suppress the colored stage ring on monuments — the
      // monument pill + 1.20× node boost already say "important". The
      // gray "untouched" ring on a monument is the exception: it
      // signals "monumento ma mai studiato → lacuna" (§1420).
      if (isMonument && stage != null) continue;

      final color = stage?.color ?? _untouchedColor;

      // Fix 4: monuments get extra outer inflation so the (gray)
      // ring sits outside the inflated semantic node rect.
      final effectiveInflate = isMonument ? inflate + monumentExtraInflate : inflate;
      final padded = bounds.inflate(effectiveInflate);
      final cornerRadius = Radius.circular(
        math.min(padded.width, padded.height) * 0.15,
      );
      final rr = RRect.fromRectAndRadius(padded, cornerRadius);

      // ── 1. Light fill — reinforces the color without overpowering
      //    the zone tints below. 2026-05-17: bumped 0.07→0.10 (untouched)
      //    / 0.05→0.08 (stage) so the band is perceivable at 0.20 where
      //    fadeOpacity is only 0.5 (mid-smoothstep).
      final fillAlpha = (stage == null ? 0.10 : 0.08) * fadeOpacity;
      fillPaint.color = color.withValues(alpha: fillAlpha);
      canvas.drawRRect(rr, fillPaint);

      // ── 2. Crisp ring — primary stage signal.
      //    2026-05-17: ring alpha 0.65 → 0.85 → 0.95 (full opacity with
      //    fade modulation). Combined with stroke width 2.8 (was 2.0)
      //    so the gray "untouched" ring reads as a real bordo on white
      //    paper at scale 0.20 where the layer first fades in.
      ringPaint
        ..strokeWidth = ringWidth
        ..color = color.withValues(alpha: (0.95 * fadeOpacity).clamp(0.0, 1.0));
      canvas.drawRRect(rr, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FsrsHeatMapPainter old) =>
      !identical(old.clusters, clusters) ||
      !identical(old.clusterStages, clusterStages) ||
      !identical(old.monumentIds, monumentIds) ||
      old.canvasScale != canvasScale ||
      old.fadeOpacity != fadeOpacity ||
      (old.semanticMorphProgress - semanticMorphProgress).abs() > 0.02;

  /// Smoothstep fade-in factor for the heat-map across the morph range.
  ///
  /// 2026-05-17: range shortened from 0.30→0.10 to 0.27→0.15 so the ring
  /// reaches full visibility at scale 0.15 (= LOD 2 boundary), not 0.10
  /// (= clamp minimo). Previous curve had alpha 0.5 at scale 0.20 which
  /// the user described as "ring grigi non visibili" on white paper.
  /// Above 0.27 → 0 (invisible). Below 0.15 → 1 (full).
  static double fadeFromScale(double scale) {
    const start = 0.27;
    const end = 0.15;
    if (scale >= start) return 0.0;
    if (scale <= end) return 1.0;
    final t = (start - scale) / (start - end);
    return t * t * (3.0 - 2.0 * t);
  }
}

