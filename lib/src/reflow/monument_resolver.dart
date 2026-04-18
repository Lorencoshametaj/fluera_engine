import 'dart:math' as math;

import '../canvas/ai/fsrs_scheduler.dart';
import 'content_cluster.dart';
import 'knowledge_connection.dart';

/// 🏛️ MONUMENT RESOLVER — computes which clusters are "landmarks" that
/// should remain visible at extreme zoom-out (§471-474 della teoria cognitiva:
/// "il tetto del Palazzo della Memoria — vedi i quartieri dall'alto, solo i
/// nomi delle materie e i nodi-monumento più grandi").
///
/// A monument is a cluster whose **importance score** crosses a threshold.
/// Signals combined (normalized to 0..1):
///   - **Degree centrality** — number of knowledge connections touching it.
///     Proxy for structural importance in the student's graph.
///   - **Age** — time since the oldest connection anchored here.
///     Old landmarks = stable scaffolding of the palace.
///   - **FSRS stability** — avg memory stability of concepts matched to the
///     cluster's text. A well-consolidated node is a real pillar, not a draft.
///   - **Manual pin** — [ContentCluster.isPinned] is a user override.
///
/// The scoring is intentionally simple and transparent: each signal is a
/// normalized value in 0..1 and combined with fixed weights. Thresholded at
/// [monumentThreshold] to get the monument set.
///
/// Pedagogical rationale: at max zoom-out the canvas must still offer
/// *textual anchors* ("mappamondo con i nomi", §1098) — otherwise the
/// student only sees anonymous cluster blobs. Monuments are those anchors.
class MonumentResolver {
  /// Weight coefficients — must sum to ≤ 1.0.
  static const double _wDegree = 0.45;
  static const double _wAge = 0.20;
  static const double _wStability = 0.25;
  static const double _wPinned = 0.10;

  /// Default threshold: score ≥ this → monument.
  static const double monumentThreshold = 0.45;

  /// Minimum absolute degree to be *eligible* as a monument.
  ///
  /// Set to 3 to align with the HUB STAR BURST visual in
  /// [KnowledgeFlowPainter]'s `_paintClusterDots`, which draws rotating
  /// radial rays on clusters with `clusterConnCount >= 3`. Keeping these
  /// two in sync means every monument is also visually distinguished by
  /// the star burst — no incoherent "monument without star" cases — and
  /// a 2-connection cluster is never promoted to landmark status (which
  /// was pedagogically weak anyway: a true hub needs multi-way branching).
  ///
  /// Pinned clusters bypass this check entirely (manual student override).
  static const int minDegreeEligibility = 3;

  /// Stability (days) that maps to a normalized score of 1.0.
  /// 30 days of FSRS stability ≈ well-consolidated memory.
  static const double stabilityCeilingDays = 30.0;

  /// Age (days) that maps to a normalized score of 1.0.
  static const double ageCeilingDays = 90.0;

  /// Result of a resolver pass.
  final Map<String, double> importance;
  final Set<String> monumentIds;

  const MonumentResolver._({
    required this.importance,
    required this.monumentIds,
  });

  /// Compute monument classification for all [clusters].
  ///
  /// [connections] — used for degree centrality + age signal.
  /// [reviewSchedule] — optional FSRS data. Pass [clusterTexts] to match
  ///   concepts to clusters by substring (same scheme as SrsReviewSession).
  /// [clusterTexts] — clusterId → recognized handwriting text (lowercased OK).
  /// [nowMs] — injection seam for tests. Defaults to wall clock.
  /// [threshold] — override [monumentThreshold] for this call.
  factory MonumentResolver.compute({
    required List<ContentCluster> clusters,
    required List<KnowledgeConnection> connections,
    Map<String, SrsCardData> reviewSchedule = const {},
    Map<String, String> clusterTexts = const {},
    int? nowMs,
    double threshold = monumentThreshold,
  }) {
    if (clusters.isEmpty) {
      return const MonumentResolver._(importance: {}, monumentIds: {});
    }

    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;

    final degree = <String, int>{};
    final oldestConnectionMs = <String, int>{};
    for (final conn in connections) {
      if (conn.deletedAtMs > 0) continue;
      degree[conn.sourceClusterId] = (degree[conn.sourceClusterId] ?? 0) + 1;
      degree[conn.targetClusterId] = (degree[conn.targetClusterId] ?? 0) + 1;

      final ts = conn.createdAtMs;
      if (ts > 0) {
        final curSrc = oldestConnectionMs[conn.sourceClusterId];
        if (curSrc == null || ts < curSrc) {
          oldestConnectionMs[conn.sourceClusterId] = ts;
        }
        final curTgt = oldestConnectionMs[conn.targetClusterId];
        if (curTgt == null || ts < curTgt) {
          oldestConnectionMs[conn.targetClusterId] = ts;
        }
      }
    }

    final maxDegree = degree.values.fold<int>(0, math.max);
    final degreeDenom = maxDegree == 0 ? 1.0 : maxDegree.toDouble();

    final stabilityByCluster = _computeStabilityByCluster(
      clusters: clusters,
      reviewSchedule: reviewSchedule,
      clusterTexts: clusterTexts,
    );

    final importance = <String, double>{};
    final monumentIds = <String>{};

    for (final c in clusters) {
      final deg = degree[c.id] ?? 0;
      final degNorm = (deg / degreeDenom).clamp(0.0, 1.0);

      double ageNorm = 0.0;
      final oldest = oldestConnectionMs[c.id];
      if (oldest != null && oldest > 0) {
        final days = (now - oldest) / (1000.0 * 60 * 60 * 24);
        ageNorm = (days / ageCeilingDays).clamp(0.0, 1.0);
      }

      final stabNorm =
          ((stabilityByCluster[c.id] ?? 0.0) / stabilityCeilingDays)
              .clamp(0.0, 1.0);

      final pinnedNorm = c.isPinned ? 1.0 : 0.0;

      final score = _wDegree * degNorm +
          _wAge * ageNorm +
          _wStability * stabNorm +
          _wPinned * pinnedNorm;

      importance[c.id] = score;

      final eligible = deg >= minDegreeEligibility || c.isPinned;
      if (eligible && score >= threshold) {
        monumentIds.add(c.id);
      }
    }

    return MonumentResolver._(
      importance: Map.unmodifiable(importance),
      monumentIds: Set.unmodifiable(monumentIds),
    );
  }

  static Map<String, double> _computeStabilityByCluster({
    required List<ContentCluster> clusters,
    required Map<String, SrsCardData> reviewSchedule,
    required Map<String, String> clusterTexts,
  }) {
    if (reviewSchedule.isEmpty || clusterTexts.isEmpty) return const {};

    final byCluster = <String, double>{};
    for (final c in clusters) {
      final text = (clusterTexts[c.id] ?? '').toLowerCase();
      if (text.isEmpty) continue;

      double sum = 0.0;
      int n = 0;
      for (final entry in reviewSchedule.entries) {
        if (text.contains(entry.key.toLowerCase())) {
          sum += entry.value.stability;
          n++;
        }
      }
      if (n > 0) byCluster[c.id] = sum / n;
    }
    return byCluster;
  }

  /// Convenience: rank clusters by importance, descending.
  List<String> rankedByImportance() {
    final entries = importance.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).toList();
  }

  /// Top-N monument IDs (capped for rendering budget at extreme zoom-out).
  List<String> topMonuments({int limit = 12}) {
    final ranked = rankedByImportance().where(monumentIds.contains).toList();
    if (ranked.length <= limit) return ranked;
    return ranked.sublist(0, limit);
  }
}
