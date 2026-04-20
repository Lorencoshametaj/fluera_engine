import 'package:flutter/foundation.dart';
import '../../ai/telemetry_recorder.dart';
import '../ai/fsrs_scheduler.dart';
import '../ai/red_wall_controller.dart';
import '../ai/srs_camera_policy.dart';
import '../../reflow/content_cluster.dart';
import '../widgets/srs_review_type_selector.dart';

/// 🧠 SRS REVIEW SESSION — manages the blur-on-return experience.
///
/// When the student opens a canvas, this controller:
/// 1. Scans the review schedule for overdue concepts
/// 2. Matches them to clusters via text content
/// 3. Provides the set of cluster IDs that should be blurred
/// 4. Handles reveal + self-evaluation → FSRS update
///
/// FSRS Integration (A5.4):
///   - Tracks peek count, breadcrumb usage, zoom state, and response time
///     per cluster for Fluera modifier application at session end.
///   - Modifiers are applied AFTER the base FSRS calculation (A5-02).
///
/// Lifecycle:
///   1. `beginSession(clusters, reviewSchedule, clusterTexts)` on canvas open
///   2. UI renders blur overlay using `blurredClusterIds` / `revealedClusterIds`
///   3. `revealCluster(id)` when student taps a blurred cluster
///   4. `recordResult(id, remembered)` for self-evaluation
///   5. `endSession()` returns the FSRS updates to persist
class SrsReviewSession extends ChangeNotifier {
  SrsReviewSession({TelemetryRecorder? telemetry})
      : _telemetry = telemetry ?? TelemetryRecorder.noop;

  final TelemetryRecorder _telemetry;
  DateTime? _sessionStartedAt;

  // ── State ─────────────────────────────────────────────────────────────────

  /// Clusters that have overdue SRS cards and should be blurred.
  final Set<String> _blurredClusterIds = {};

  /// Clusters that have been revealed (tapped) but not yet evaluated.
  final Set<String> _revealedClusterIds = {};

  /// Evaluation results: cluster ID → true (remembered) / false (forgot).
  final Map<String, bool> _revealResults = {};

  /// Mapping from cluster ID → list of overdue concept names in that cluster.
  final Map<String, List<String>> _clusterToConcepts = {};

  /// Whether a review session is currently active.
  bool _isActive = false;

  /// The type of review session (micro or deep).
  SrsReviewType _reviewType = SrsReviewType.micro;

  /// Clusters where the student answered incorrectly (deep-review only).
  /// These require mandatory rewrite.
  final Set<String> _requiresRewrite = {};

  // ── Modifier Tracking (A5.4) ─────────────────────────────────────────────

  /// Per-cluster peek tracking: true if student peeked at this cluster.
  final Map<String, bool> _peeked = {};

  /// Per-cluster breadcrumb count: how many hints were used.
  final Map<String, int> _hintsUsed = {};

  /// Per-cluster zoom tracking: true if student zoomed in to read.
  final Map<String, bool> _zoomedIn = {};

  /// Per-cluster response time: seconds from reveal to evaluation.
  final Map<String, double> _responseTimes = {};

  /// Per-cluster confidence level (1–5) from metacognitive slider.
  final Map<String, int> _confidence = {};

  /// Timestamp when each cluster was revealed (for response time calculation).
  final Map<String, DateTime> _revealTimestamps = {};

  // ── Progressive Zoom-Out on Return (§1010, §1549-1554) ───────────────────

  /// Target zoom scale for the *next* `beginSession` return, computed from
  /// the student's accumulated review count.
  ///
  /// Null until the first `beginSession` that receives a non-zero
  /// `reviewCount`. The UI reads this after `beginSession` and applies it
  /// to the canvas camera.
  double? _targetInitialZoomScale;

  /// Target LOD tier the student will land in for this return.
  int? _targetInitialLodTier;

  /// Human-readable hint to show the student on session open.
  String? _returnZoomHint;

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isActive => _isActive;

  Set<String> get blurredClusterIds => Set.unmodifiable(_blurredClusterIds);

  Set<String> get revealedClusterIds => Set.unmodifiable(_revealedClusterIds);

  Map<String, bool> get revealResults => Map.unmodifiable(_revealResults);

  int get totalDue => _blurredClusterIds.length;

  int get totalRevealed => _revealedClusterIds.length;

  int get totalRemembered =>
      _revealResults.values.where((v) => v).length;

  int get totalForgot =>
      _revealResults.values.where((v) => !v).length;

  bool get allRevealed => _blurredClusterIds.length == _revealedClusterIds.length;

  bool get allEvaluated => _blurredClusterIds.length == _revealResults.length;

  /// The current review type.
  SrsReviewType get reviewType => _reviewType;

  /// Clusters that require mandatory rewrite (deep-review failures).
  Set<String> get requiresRewrite => Set.unmodifiable(_requiresRewrite);

  /// Returns the overdue concepts for a given cluster.
  List<String> conceptsForCluster(String clusterId) =>
      _clusterToConcepts[clusterId] ?? const [];

  /// Target zoom scale the UI should apply on session open, per the
  /// progressive zoom-out policy (§1549). Null → no override.
  double? get targetInitialZoomScale => _targetInitialZoomScale;

  /// Target LOD tier for the return, derived from the target scale.
  int? get targetInitialLodTier => _targetInitialLodTier;

  /// Localized hint to surface to the student on session open.
  String? get returnZoomHint => _returnZoomHint;

  // ── Session Lifecycle ─────────────────────────────────────────────────────

  /// Begins an SRS review session. Scans the review schedule for overdue
  /// concepts and matches them to clusters via text content.
  ///
  /// Returns the number of clusters that are due for review.
  int beginSession({
    required List<ContentCluster> clusters,
    required Map<String, SrsCardData> reviewSchedule,
    required Map<String, String> clusterTexts,
    SrsReviewType reviewType = SrsReviewType.micro,
    int maxNodes = 12,
    int canvasReviewCount = 0,
    double userBaseScale = 1.0,
  }) {
    _blurredClusterIds.clear();
    _revealedClusterIds.clear();
    _revealResults.clear();
    _clusterToConcepts.clear();
    _requiresRewrite.clear();
    _peeked.clear();
    _hintsUsed.clear();
    _zoomedIn.clear();
    _responseTimes.clear();
    _confidence.clear();
    _revealTimestamps.clear();
    _targetInitialZoomScale = null;
    _targetInitialLodTier = null;
    _returnZoomHint = null;
    _reviewType = reviewType;

    if (canvasReviewCount > 0) {
      final scale = SrsCameraPolicy.targetScaleForReturn(
        reviewCount: canvasReviewCount,
        userBaseScale: userBaseScale,
      );
      final tier = SrsCameraPolicy.targetLodTier(
        reviewCount: canvasReviewCount,
        userBaseScale: userBaseScale,
      );
      _targetInitialZoomScale = scale;
      _targetInitialLodTier = tier;
      _returnZoomHint = SrsCameraPolicy.hintForTier(tier);
    }

    final now = DateTime.now();

    // Find all overdue concepts
    final overdueKeys = <String>[];
    for (final entry in reviewSchedule.entries) {
      if (entry.value.nextReview.isBefore(now)) {
        overdueKeys.add(entry.key);
      }
    }

    if (overdueKeys.isEmpty) {
      _isActive = false;
      notifyListeners();
      return 0;
    }

    // Match overdue concepts to clusters via text content
    for (final cluster in clusters) {
      final text = (clusterTexts[cluster.id] ?? '').toLowerCase();
      if (text.isEmpty) continue;

      final matchedConcepts = <String>[];
      for (final concept in overdueKeys) {
        if (text.contains(concept.toLowerCase())) {
          matchedConcepts.add(concept);
        }
      }

      if (matchedConcepts.isNotEmpty) {
        _blurredClusterIds.add(cluster.id);
        _clusterToConcepts[cluster.id] = matchedConcepts;
      }
    }

    _isActive = _blurredClusterIds.isNotEmpty;

    // For micro-review, cap to the top-N most urgent clusters.
    // Spec A5.6: prioritize by urgency = overdue_days / scheduled_days
    if (reviewType == SrsReviewType.micro &&
        _blurredClusterIds.length > maxNodes) {
      final urgencyMap = <String, double>{};
      for (final clusterId in _blurredClusterIds) {
        final concepts = _clusterToConcepts[clusterId] ?? [];
        double maxUrgency = 0;
        for (final concept in concepts) {
          final card = reviewSchedule[concept];
          if (card != null) {
            final urgency = FsrsScheduler.urgencyScore(card);
            if (urgency > maxUrgency) maxUrgency = urgency;
          }
        }
        urgencyMap[clusterId] = maxUrgency;
      }

      // Keep only top-N by urgency
      final sorted = urgencyMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final keep = sorted.take(maxNodes).map((e) => e.key).toSet();
      _blurredClusterIds.removeWhere((id) => !keep.contains(id));
      _clusterToConcepts.removeWhere((id, _) => !keep.contains(id));
    }

    // 📊 Telemetry: emit only when a real review session is activated
    // (i.e. at least one overdue cluster matched on the canvas).
    if (_isActive) {
      _sessionStartedAt = DateTime.now();
      _telemetry.logEvent('step_6_srs_review_started', properties: {
        'review_type': reviewType.name,
        'cluster_count': _blurredClusterIds.length,
        'overdue_concepts': overdueKeys.length,
        'canvas_review_count': canvasReviewCount,
      });
    }

    notifyListeners();
    return _blurredClusterIds.length;
  }

  /// Reveals a blurred cluster (student tapped it).
  void revealCluster(String clusterId) {
    if (!_blurredClusterIds.contains(clusterId)) return;
    if (_revealedClusterIds.contains(clusterId)) return;

    _revealedClusterIds.add(clusterId);
    _revealTimestamps[clusterId] = DateTime.now();
    notifyListeners();
  }

  /// Records the student's self-evaluation for a revealed cluster.
  ///
  /// [remembered]: true = "sì, ricordavo", false = "no, dimenticato".
  void recordResult(String clusterId, bool remembered) {
    if (!_revealedClusterIds.contains(clusterId)) return;
    _revealResults[clusterId] = remembered;

    // Calculate response time from reveal to evaluation
    final revealTime = _revealTimestamps[clusterId];
    if (revealTime != null) {
      _responseTimes[clusterId] =
          DateTime.now().difference(revealTime).inMilliseconds / 1000.0;
    }

    // Deep-review: track failed nodes for mandatory rewrite (P8-16)
    if (!remembered && _reviewType == SrsReviewType.deep) {
      _requiresRewrite.add(clusterId);
    }

    notifyListeners();
  }

  // ── Modifier Tracking API ─────────────────────────────────────────────────
  // Called by the UI during the review session to track pedagogical signals.

  /// Records that the student peeked at a cluster's content.
  /// Spec A5.4: Malus stability ×0.8
  void recordPeek(String clusterId) {
    _peeked[clusterId] = true;
  }

  /// Records a breadcrumb/hint usage for a cluster.
  /// Spec A5.4: Malus stability ×0.85^hintsUsed
  void recordHintUsed(String clusterId) {
    _hintsUsed[clusterId] = (_hintsUsed[clusterId] ?? 0) + 1;
  }

  /// Records that the student zoomed in to read a cluster.
  /// Spec A5.4: Malus stability ×0.9
  void recordZoomIn(String clusterId) {
    _zoomedIn[clusterId] = true;
  }

  /// Records the student's confidence level for a cluster.
  /// Used for hypercorrection effect (A5.4).
  void recordConfidence(String clusterId, int level) {
    _confidence[clusterId] = level.clamp(1, 5);
  }

  // ── Session End ───────────────────────────────────────────────────────────

  /// Ends the session and returns FSRS updates to apply to the review schedule.
  ///
  /// Returns a map of concept → updated SrsCardData.
  /// Applies Fluera modifiers (A5.4) collected during the session.
  Map<String, SrsCardData> endSession({
    required Map<String, SrsCardData> currentSchedule,
  }) {
    final updates = <String, SrsCardData>{};

    for (final entry in _clusterToConcepts.entries) {
      final clusterId = entry.key;
      final concepts = entry.value;
      final result = _revealResults[clusterId];

      // Determine quality: remembered = 2 (correct), forgot = 0 (incorrect)
      // If not evaluated, treat as "saw but didn't evaluate" = quality 1 (partial)
      final quality = result == true ? 2 : (result == false ? 0 : 1);

      // Build Fluera modifiers from tracked signals
      final modifiers = FsrsModifiers(
        peeked: _peeked[clusterId] ?? false,
        hintsUsed: _hintsUsed[clusterId] ?? 0,
        zoomedIn: _zoomedIn[clusterId] ?? false,
        responseTimeSec: _responseTimes[clusterId],
        confidence: _confidence[clusterId] ?? (result != null ? 3 : 0),
      );

      for (final concept in concepts) {
        final existing = currentSchedule[concept] ?? SrsCardData.newCard();
        updates[concept] = FsrsScheduler.review(
          existing,
          quality: quality,
          confidence: _confidence[clusterId] ?? (result != null ? 3 : 0),
          modifiers: modifiers,
        );
      }
    }

    // Evaluate Red Wall protective response (A20-47).
    _lastRedWallEvaluation = RedWallController.evaluate(
      forgottenCount: totalForgot,
      totalCount: totalDue,
    );

    // 📊 Telemetry: emit completion before state is cleared.
    final startedAt = _sessionStartedAt;
    if (startedAt != null) {
      _telemetry.logEvent('step_6_srs_review_completed', properties: {
        'review_type': _reviewType.name,
        'total_due': totalDue,
        'total_remembered': totalRemembered,
        'total_forgot': totalForgot,
        'duration_sec':
            DateTime.now().difference(startedAt).inSeconds,
        'red_wall_triggered': _lastRedWallEvaluation?.isActive ?? false,
      });
      _sessionStartedAt = null;
    }

    _isActive = false;
    notifyListeners();
    return updates;
  }

  // ── Red Wall (A20.4.1) ────────────────────────────────────────────────────

  RedWallEvaluation? _lastRedWallEvaluation;

  /// Red Wall evaluation result from the last completed session.
  ///
  /// When [RedWallEvaluation.isActive], the UI should:
  ///   - Show forgotten nodes in grey (#888) instead of red (A20-48)
  ///   - Display the metacognitive message (A20-49)
  ///   - Use [suggestedNextSessionSize] to cap the next session (A20-50)
  RedWallEvaluation? get redWallEvaluation => _lastRedWallEvaluation;

  /// Whether the Red Wall protective response was triggered.
  bool get isRedWallActive => _lastRedWallEvaluation?.isActive ?? false;

  /// The protective message to show if Red Wall is active (A20-49).
  String? get redWallMessage => _lastRedWallEvaluation?.isActive == true
      ? RedWallController.protectiveMessage(
          _lastRedWallEvaluation!.forgottenCount)
      : null;

  /// Dismisses the session without recording any results.
  void dismiss() {
    _isActive = false;
    _lastRedWallEvaluation = null;
    _blurredClusterIds.clear();
    _revealedClusterIds.clear();
    _revealResults.clear();
    _clusterToConcepts.clear();
    _requiresRewrite.clear();
    _peeked.clear();
    _hintsUsed.clear();
    _zoomedIn.clear();
    _responseTimes.clear();
    _confidence.clear();
    _revealTimestamps.clear();
    _targetInitialZoomScale = null;
    _targetInitialLodTier = null;
    _returnZoomHint = null;
    notifyListeners();
  }

  /// Checks if a specific cluster is currently blurred (not yet revealed).
  bool isClusterBlurred(String clusterId) =>
      _blurredClusterIds.contains(clusterId) &&
      !_revealedClusterIds.contains(clusterId);
}
