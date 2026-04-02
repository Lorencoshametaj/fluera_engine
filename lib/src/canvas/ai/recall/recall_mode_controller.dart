// ============================================================================
// 🧠 RECALL MODE CONTROLLER — State machine for Step 2 (Ricostruzione)
//
// Specifica: P2-01 → P2-70
//
// This controller manages the complete lifecycle of a recall session:
//   1. Zone selection → activation (Free or Spatial Recall)
//   2. Active recall phase (writing, peek, "non ricordo" markers)
//   3. Comparison phase (reveal, gap highlighting, navigation)
//   4. Self-evaluation + session persistence
//   5. Transition to Step 3 (gap map handoff)
//
// AI STATE: 💤 DORMANT — this controller NEVER invokes AI.
// All logic is purely local: visual, spatial, structural.
//
// THREAD SAFETY: Main isolate only (Flutter UI).
// ============================================================================

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../reflow/content_cluster.dart';
import '../../../utils/uid.dart';
import 'recall_session_model.dart';

/// Peek cost escalation table (P2-66).
///
/// | Peek # | Duration | Color     |
/// |--------|----------|-----------|
/// | 1      | 3.0s     | Yellow    |
/// | 2      | 2.0s     | Orange    |
/// | 3      | 1.5s     | Red-Orange|
/// | 4+     | 1.0s     | Red       |
class _PeekCost {
  static Duration duration(int peekNumber) {
    switch (peekNumber) {
      case 1:
        return const Duration(milliseconds: 3000);
      case 2:
        return const Duration(milliseconds: 2000);
      case 3:
        return const Duration(milliseconds: 1500);
      default:
        return const Duration(milliseconds: 1000);
    }
  }

  static int colorValue(int peekNumber) {
    switch (peekNumber) {
      case 1:
        return 0xFFFFCC00; // Yellow
      case 2:
        return 0xFFFF9500; // Orange
      case 3:
        return 0xFFFF6B00; // Red-orange
      default:
        return 0xFFFF3B30; // Red
    }
  }
}

/// 🧠 Controller for the Recall Mode (Step 2).
///
/// Provides state queries and mutations for all recall mechanics.
/// Subsystems (overlays, gestures) observe this via [addListener].
///
/// Usage:
/// ```dart
/// recallController.activate(zone, clusters, RecallPhase.freeRecall);
/// // ... student writes from memory ...
/// recallController.peekNode('cluster_123');
/// // ... later ...
/// recallController.startComparison();
/// ```
class RecallModeController extends ChangeNotifier {
  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  RecallPhase _phase = RecallPhase.inactive;

  /// The active recall session (null when inactive).
  RecallSession? _session;

  /// The selected zone in canvas coordinates.
  Rect? _selectedZone;

  /// Original clusters within the selected zone (hidden during recall).
  List<ContentCluster> _originalClusters = const [];

  /// Clusters reconstructed by the student (tracked during comparison).
  List<ContentCluster> _reconstructedClusters = const [];

  /// Currently peeked node ID (null when no peek is active).
  String? _activePeekClusterId;

  /// Timer for auto-reblur after peek (P2-16).
  Timer? _peekTimer;

  /// "Non ricordo" markers placed by the student (P2-14).
  final List<RecallMissedMarker> _missedMarkers = [];

  /// Gap navigation index for comparison phase (P2-28).
  int _gapNavigationIndex = -1;

  /// Session count for the current zone (for adaptive blur, P2-54).
  int _zoneSessionCount = 0;

  /// Timer for the session duration display (P2-04).
  final Stopwatch _sessionStopwatch = Stopwatch();

  /// Whether self-evaluation mode is active (P2-43).
  bool _selfEvaluationActive = false;

  // ─────────────────────────────────────────────────────────────────────────
  // GETTERS
  // ─────────────────────────────────────────────────────────────────────────

  /// Current phase of the Recall Mode.
  RecallPhase get phase => _phase;

  /// Whether the Recall Mode is active (any phase except inactive).
  bool get isActive => _phase != RecallPhase.inactive;

  /// Whether we're in the comparison phase.
  bool get isComparing => _phase == RecallPhase.comparison;

  /// Whether we're in Free Recall (no positional cues).
  bool get isFreeRecall => _phase == RecallPhase.freeRecall;

  /// Whether we're in Spatial Recall (colored blobs visible).
  bool get isSpatialRecall => _phase == RecallPhase.spatialRecall;

  /// The active session.
  RecallSession? get session => _session;

  /// The selected zone rectangle (canvas coordinates).
  Rect? get selectedZone => _selectedZone;

  /// Original clusters in the zone (for rendering blur/blobs).
  List<ContentCluster> get originalClusters => _originalClusters;

  /// The currently peeked cluster ID.
  String? get activePeekClusterId => _activePeekClusterId;

  /// "Non ricordo" markers.
  List<RecallMissedMarker> get missedMarkers =>
      List.unmodifiable(_missedMarkers);

  /// Elapsed time in the session (for timer display, P2-04).
  Duration get elapsed => _sessionStopwatch.elapsed;

  /// Number of nodes reconstructed so far (for counter, P2-05).
  int get reconstructedCount => _reconstructedClusters.length;

  /// Total original nodes (for counter, P2-05).
  int get originalCount => _originalClusters.length;

  /// Peek count in the current session (P2-68).
  int get sessionPeekCount => _session?.totalPeekCount ?? 0;

  /// Whether self-evaluation is active.
  bool get isSelfEvaluationActive => _selfEvaluationActive;

  /// Gap navigation index (current position in gaps list).
  int get gapNavigationIndex => _gapNavigationIndex;

  /// Session history count for adaptive blur (P2-54).
  int get zoneSessionCount => _zoneSessionCount;

  /// Blob opacity for Spatial Recall, decreasing with sessions (P2-54).
  /// Session 1 = 50%, Session 2 = 30%, Session 3+ = 15%.
  double get adaptiveBlobOpacity {
    if (_zoneSessionCount <= 1) return 0.50;
    if (_zoneSessionCount == 2) return 0.30;
    return 0.15;
  }

  /// Whether we should show the "too many peeks" suggestion (P2-67).
  bool get shouldShowPeekWarning => sessionPeekCount >= 4;

  /// Ordered list of gap cluster IDs for navigation (P2-28).
  List<String> get gapClusterIds {
    if (_session == null) return const [];
    return _session!.nodeEntries.entries
        .where((e) =>
            e.value.recallLevel.level <= 2 &&
            !e.value.peeked)
        .map((e) => e.key)
        .toList();
  }

  /// All node entries for the current session.
  Map<String, RecallNodeEntry> get nodeEntries =>
      _session?.nodeEntries ?? const {};

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVATION (P2-01)
  // ─────────────────────────────────────────────────────────────────────────

  /// Activate Recall Mode for the given zone.
  ///
  /// [zone] is the selected area in canvas coordinates (P2-62, P2-63).
  /// [clustersInZone] are the original clusters within that zone.
  /// [canvasId] identifies the canvas for persistence.
  /// [initialPhase] defaults to Free Recall (P2-38).
  /// [sessionCount] is the number of previous sessions on this zone (P2-54).
  void activate({
    required Rect zone,
    required List<ContentCluster> clustersInZone,
    required String canvasId,
    RecallPhase initialPhase = RecallPhase.freeRecall,
    int sessionCount = 0,
  }) {
    if (isActive) return;

    _selectedZone = zone;
    _originalClusters = List.unmodifiable(clustersInZone);
    _zoneSessionCount = sessionCount;

    // Compute zone ID from bounds hash (deterministic).
    final zoneId =
        'zone_${zone.left.toInt()}_${zone.top.toInt()}_${zone.width.toInt()}_${zone.height.toInt()}';

    _session = RecallSession(
      sessionId: 'recall_${DateTime.now().millisecondsSinceEpoch}',
      canvasId: canvasId,
      zoneId: zoneId,
      startedAt: DateTime.now(),
      recallType: initialPhase == RecallPhase.freeRecall ? 'free' : 'spatial',
      totalOriginalNodes: clustersInZone.length,
    );

    // Initialize entries for all original clusters.
    for (final cluster in clustersInZone) {
      _session!.nodeEntries[cluster.id] = RecallNodeEntry(
        clusterId: cluster.id,
        recallType: initialPhase == RecallPhase.freeRecall ? 'free' : 'spatial',
      );
    }

    _phase = initialPhase;
    _missedMarkers.clear();
    _gapNavigationIndex = -1;
    _selfEvaluationActive = false;
    _sessionStopwatch
      ..reset()
      ..start();

    notifyListeners();
  }

  /// Deactivate Recall Mode and return to normal canvas (P2-37).
  ///
  /// Session data is preserved — call [session] to retrieve before deactivating.
  void deactivate() {
    if (!isActive) return;

    _sessionStopwatch.stop();
    _session?.completedAt = DateTime.now();
    _peekTimer?.cancel();
    _peekTimer = null;
    _activePeekClusterId = null;

    _phase = RecallPhase.inactive;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FREE → SPATIAL TRANSITION (P2-41)
  // ─────────────────────────────────────────────────────────────────────────

  /// Switch from Free Recall to Spatial Recall (unidirectional, P2-41).
  ///
  /// Records the moment of switch and how many nodes were recalled before.
  void switchToSpatial() {
    if (_phase != RecallPhase.freeRecall) return;

    _session?.switchedToSpatialAt = DateTime.now();
    _session?.nodesRecalledBeforeSwitch = reconstructedCount;
    _session?.recallType = 'free_then_spatial';

    _phase = RecallPhase.spatialRecall;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PEEK SYSTEM (P2-16, P2-66 → P2-70)
  // ─────────────────────────────────────────────────────────────────────────

  /// Peek at a single node — temporary reveal (P2-16).
  ///
  /// The node is revealed for a decreasing duration (3s→2s→1.5s→1s)
  /// and permanently marked with escalating color (P2-66).
  ///
  /// Connections/arrows are NOT revealed (P2-69).
  /// The node CANNOT be promoted to 'recalled' this session (P2-70).
  ///
  /// Returns `true` if the peek was started, `false` if already peeking.
  bool peekNode(String clusterId) {
    if (_activePeekClusterId != null) return false;
    if (!isActive || isComparing) return false;

    // Increment session peek count.
    _session?.totalPeekCount = (_session?.totalPeekCount ?? 0) + 1;
    final peekNumber = _session!.totalPeekCount;

    // Update node entry.
    final entry = _session?.nodeEntries[clusterId];
    if (entry != null) {
      entry.peeked = true;
      entry.peekCount++;
      entry.recallLevel = RecallLevel.peeked;
    }

    // Start reveal timer.
    _activePeekClusterId = clusterId;
    final revealDuration = _PeekCost.duration(peekNumber);

    _peekTimer?.cancel();
    _peekTimer = Timer(revealDuration, () {
      _activePeekClusterId = null;
      _peekTimer = null;
      notifyListeners(); // Re-blur the node.
    });

    notifyListeners();
    return true;
  }

  /// Color for the peek marker on a specific node (P2-66).
  int peekMarkerColor(String clusterId) {
    final entry = _session?.nodeEntries[clusterId];
    if (entry == null || !entry.peeked) return 0x00000000;
    return _PeekCost.colorValue(entry.peekCount);
  }

  /// Cancel an active peek early (e.g., if user taps elsewhere).
  void cancelPeek() {
    if (_activePeekClusterId == null) return;
    _peekTimer?.cancel();
    _peekTimer = null;
    _activePeekClusterId = null;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // "NON RICORDO" MARKER (P2-14, P2-15)
  // ─────────────────────────────────────────────────────────────────────────

  /// Add a "non ricordo" marker at the given canvas position.
  ///
  /// Creates a red dashed empty node with "?" icon (P2-15).
  /// Gesture: double tap on empty area in Recall Mode (P2-14).
  RecallMissedMarker addMissedMarker(Offset canvasPosition) {
    final marker = RecallMissedMarker(
      id: 'missed_${generateUid()}',
      position: canvasPosition,
      createdAt: DateTime.now(),
    );
    _missedMarkers.add(marker);
    notifyListeners();
    return marker;
  }

  /// Remove a missed marker by ID.
  void removeMissedMarker(String markerId) {
    _missedMarkers.removeWhere((m) => m.id == markerId);
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMPARISON PHASE (P2-23 → P2-30)
  // ─────────────────────────────────────────────────────────────────────────

  /// Start the comparison phase — reveal original nodes (P2-23).
  ///
  /// This is triggered by an EXPLICIT student action (never automatic).
  /// [reconstructedClusters] are the clusters the student produced.
  void startComparison(List<ContentCluster> reconstructedClusters) {
    if (!isActive || isComparing) return;

    _reconstructedClusters = List.unmodifiable(reconstructedClusters);
    _sessionStopwatch.stop();

    // Auto-assign binary recall status for nodes (P2-46 fallback).
    _autoAssignRecallStatus(reconstructedClusters);

    _phase = RecallPhase.comparison;
    _gapNavigationIndex = -1;
    notifyListeners();
  }

  /// Auto-assign binary recall levels (P2-46).
  ///
  /// Matching is spatial: if a reconstructed cluster overlaps with an original
  /// cluster's area, it's considered "recalled" (level 5).
  /// Original clusters with no matching reconstruction are "missed" (level 1).
  void _autoAssignRecallStatus(List<ContentCluster> reconstructed) {
    if (_session == null) return;

    for (final entry in _session!.nodeEntries.entries) {
      if (entry.value.peeked) continue; // Peeked stays peeked.

      // Check if any reconstructed cluster spatially matches.
      final originalCluster = _originalClusters
          .where((c) => c.id == entry.key)
          .firstOrNull;
      if (originalCluster == null) continue;

      final matched = reconstructed.any((rc) {
        // Generous overlap: if the reconstructed cluster's center is
        // within 200px of the original cluster's center, consider it a match.
        final distance = (rc.centroid - originalCluster.centroid).distance;
        return distance < 200.0;
      });

      entry.value.recallLevel =
          matched ? RecallLevel.perfect : RecallLevel.missed;
    }
  }

  /// Navigate to the next gap (missed node) in comparison (P2-28).
  ///
  /// Returns the cluster ID of the next gap, or null if at the end.
  String? navigateToNextGap() {
    final gaps = gapClusterIds;
    if (gaps.isEmpty) return null;

    _gapNavigationIndex = (_gapNavigationIndex + 1) % gaps.length;
    notifyListeners();
    return gaps[_gapNavigationIndex];
  }

  /// Navigate to the previous gap.
  String? navigateToPreviousGap() {
    final gaps = gapClusterIds;
    if (gaps.isEmpty) return null;

    _gapNavigationIndex--;
    if (_gapNavigationIndex < 0) _gapNavigationIndex = gaps.length - 1;
    notifyListeners();
    return gaps[_gapNavigationIndex];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SELF-EVALUATION (P2-43 → P2-46)
  // ─────────────────────────────────────────────────────────────────────────

  /// Activate self-evaluation mode (P2-43).
  void startSelfEvaluation() {
    if (!isComparing) return;
    _selfEvaluationActive = true;
    notifyListeners();
  }

  /// Set the recall level for a specific node (P2-43).
  ///
  /// [level] is 1–5 (or 0 for peeked, which is auto-set).
  void setRecallLevel(String clusterId, RecallLevel level) {
    final entry = _session?.nodeEntries[clusterId];
    if (entry == null) return;
    if (entry.peeked) return; // Peeked nodes can't be promoted (P2-70).

    entry.recallLevel = level;
    entry.timestamp = DateTime.now();
    notifyListeners();
  }

  /// Cycle the recall level for a node (P2-43: "swipe or repeated tap").
  ///
  /// Cycles: 1 → 2 → 3 → 4 → 5 → 1.
  void cycleRecallLevel(String clusterId) {
    final entry = _session?.nodeEntries[clusterId];
    if (entry == null || entry.peeked) return;

    const levels = [
      RecallLevel.missed,
      RecallLevel.tipOfTongue,
      RecallLevel.partial,
      RecallLevel.substantial,
      RecallLevel.perfect,
    ];

    final currentIdx =
        levels.indexWhere((l) => l.level == entry.recallLevel.level);
    final nextIdx = (currentIdx + 1) % levels.length;
    entry.recallLevel = levels[nextIdx];
    entry.timestamp = DateTime.now();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MASTERY TRACKING (P2-56)
  // ─────────────────────────────────────────────────────────────────────────

  /// Update mastery tracking for a node after session completion.
  ///
  /// A node is mastered after 3 consecutive correct recalls (level ≥ 4)
  /// in sessions distanced ≥ 24h (P2-56).
  void updateMastery(
    String clusterId,
    RecallLevel currentLevel,
    int previousConsecutiveCorrect,
    DateTime? lastSessionDate,
  ) {
    final entry = _session?.nodeEntries[clusterId];
    if (entry == null) return;

    if (currentLevel.isSuccessful) {
      // Check if ≥24h since last session.
      final sufficientGap = lastSessionDate == null ||
          DateTime.now().difference(lastSessionDate).inHours >= 24;

      if (sufficientGap) {
        entry.consecutiveCorrectSessions = previousConsecutiveCorrect + 1;
      }

      // Mastered: 3 correct in separated sessions (P2-56).
      if (entry.consecutiveCorrectSessions >= 3) {
        entry.mastered = true;
      }
    } else {
      // Failed — reset consecutive count.
      entry.consecutiveCorrectSessions = 0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMPARISON VISUAL CLASSIFICATION (P2-26)
  // ─────────────────────────────────────────────────────────────────────────

  /// Get the overlay color classification for a cluster in comparison.
  ///
  /// Returns one of:
  /// - Red (0xFFFF3B30, 30% opacity): present only in original (gap)
  /// - Green (0xFF30D158, 20% opacity): present in both (recalled)
  /// - Blue (0xFF007AFF, 20% opacity): present only in reconstruction (addition)
  /// - Yellow (0xFFFFCC00): peeked node
  ComparisonNodeStatus comparisonStatus(String clusterId) {
    final entry = _session?.nodeEntries[clusterId];

    if (entry != null && entry.peeked) {
      return ComparisonNodeStatus.peeked;
    }
    if (entry != null && entry.recallLevel.isSuccessful) {
      return ComparisonNodeStatus.recalled;
    }
    if (entry != null) {
      return ComparisonNodeStatus.missed;
    }
    // Cluster exists only in reconstruction — it's an addition.
    return ComparisonNodeStatus.added;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRANSITION TO STEP 3 (P2-35, P2-36)
  // ─────────────────────────────────────────────────────────────────────────

  /// Generate the gap map payload for Step 3 handoff (P2-36).
  ///
  /// Returns null if no session is active.
  List<Map<String, dynamic>>? getGapMapForStep3() => _session?.toGapMap();

  // ─────────────────────────────────────────────────────────────────────────
  // SUMMARY METRICS (P2-58, P2-59)
  // ─────────────────────────────────────────────────────────────────────────

  /// Summary text for the positive message (P2-58).
  ///
  /// "Hai ricostruito 8 nodi su 12 dalla memoria!"
  String get summaryText {
    final recalled = _session?.recalledCount ?? 0;
    final total = _session?.totalOriginalNodes ?? 0;
    return 'Hai ricostruito $recalled nodi su $total dalla memoria!';
  }

  /// Delta improvement vs previous session (P2-59).
  ///
  /// Returns null if no previous session is available.
  int? deltaImprovement(RecallSessionSummary? previousSession) {
    if (previousSession == null || _session == null) return null;
    return (_session!.recalledCount) - previousSession.recalled;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _peekTimer?.cancel();
    _sessionStopwatch.stop();
    super.dispose();
  }

  @override
  String toString() =>
      'RecallModeController(phase: $_phase, '
      'original: ${_originalClusters.length}, '
      'peeks: $sessionPeekCount, '
      'elapsed: ${elapsed.inSeconds}s)';
}

// =============================================================================
// SUPPORTING TYPES
// =============================================================================

/// A "non ricordo" marker placed by the student (P2-14, P2-15).
class RecallMissedMarker {
  final String id;
  final Offset position;
  final DateTime createdAt;

  const RecallMissedMarker({
    required this.id,
    required this.position,
    required this.createdAt,
  });
}

/// Visual classification for clusters in comparison view (P2-26).
enum ComparisonNodeStatus {
  /// Present only in original — gap (red, P2-26).
  missed,

  /// Present in both — successfully recalled (green, P2-26).
  recalled,

  /// Present only in reconstruction — student addition (blue, P2-26).
  added,

  /// Student used peek (yellow, P2-27).
  peeked,
}
