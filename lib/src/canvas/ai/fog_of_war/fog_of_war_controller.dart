// ============================================================================
// 🌫️ FOG OF WAR CONTROLLER — State machine for Step 10 (Exam Preparation)
//
// Specifica: P10-01 → P10-29
//
// Manages the complete lifecycle of a Fog of War session:
//   1. Activation → fog overlay appears on selected zone
//   2. Navigation → student explores blind, tapping to reveal nodes
//   3. Self-evaluation → ✅/❌ per node (no feedback during session)
//   4. Cinematic reveal → fog lifts from center outward (2-3s)
//   5. Mastery map → heatmap visible, navigable, summary shown
//
// AI STATE: 💤 DORMANT — no AI calls. All logic is spatial and local.
//
// ❌ ANTI-PATTERNS ENFORCED:
//   P10-10: No timer/countdown
//   P10-11: No node counter shown during session
//   P10-12: No feedback during exploration
// ============================================================================

import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../ai/telemetry_recorder.dart';
import '../../../l10n/generated/fluera_localizations.g.dart';
import '../../../reflow/content_cluster.dart';
import 'fog_of_war_model.dart';

/// 🌫️ Controller for the Fog of War (Step 10).
///
/// Provides state queries and mutations for all fog mechanics.
/// Subsystems (overlays, gestures) observe this via [addListener].
///
/// Usage:
/// ```dart
/// fogController.activate(zone: rect, clusters: clusters, fogLevel: FogLevel.medium);
/// // ... student navigates ...
/// fogController.handleTap(canvasPosition); // → hit-tests clusters
/// fogController.recordResult('cluster_123', recalled: true);
/// // ... student decides to end ...
/// fogController.endSession(); // → cinematic reveal
/// fogController.dismiss(); // → back to normal canvas
/// ```
class FogOfWarController extends ChangeNotifier {
  FogOfWarController({TelemetryRecorder? telemetry})
      : _telemetry = telemetry ?? TelemetryRecorder.noop;

  final TelemetryRecorder _telemetry;

  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  FogPhase _phase = FogPhase.inactive;

  /// The active session (null when inactive).
  FogOfWarSession? _session;

  /// The selected zone in canvas coordinates.
  Rect? _selectedZone;

  /// Medium fog: fixed torch center in canvas coordinates. Set once at
  /// activation to the zone center — does NOT follow panning. Forces
  /// the student to remember node locations relative to this anchor.
  Offset _torchCenter = Offset.zero;

  /// Original clusters within the selected zone.
  List<ContentCluster> _originalClusters = const [];

  /// The fog density level for this session.
  FogLevel _fogLevel = FogLevel.light;

  /// IDs of clusters that have been revealed (tapped).
  final Set<String> _revealedNodeIds = {};

  /// The cluster currently awaiting self-evaluation (tap → popup).
  String? _pendingEvalClusterId;

  /// Stopwatch for individual node response time tracking.
  final Stopwatch _nodeStopwatch = Stopwatch();

  /// Cinematic reveal progress: 0.0 (fully fogged) → 1.0 (fully clear).
  double _revealProgress = 0.0;

  /// 🧠 Partial Zone Memory (E): Cluster IDs that were failed (forgotten/
  /// blind spot) in the PREVIOUS session for the same zone.
  /// Empty if no prior session or no failures.
  Set<String> _priorFailureNodeIds = {};

  // ─────────────────────────────────────────────────────────────────────────
  // GETTERS
  // ─────────────────────────────────────────────────────────────────────────

  /// Current phase of the Fog of War.
  FogPhase get phase => _phase;

  /// Whether any Fog of War phase is active.
  bool get isActive => _phase != FogPhase.inactive;

  /// Whether the fog overlay is rendering.
  bool get isFogActive => _phase == FogPhase.active;

  /// Whether the cinematic reveal is playing.
  bool get isRevealing => _phase == FogPhase.revealing;

  /// Whether the mastery heatmap is displayed.
  bool get isMasteryMap => _phase == FogPhase.masteryMap;

  /// The active session.
  FogOfWarSession? get session => _session;

  /// The selected zone rectangle (canvas coordinates).
  Rect? get selectedZone => _selectedZone;

  /// Original clusters in the zone.
  List<ContentCluster> get originalClusters => _originalClusters;

  /// Medium fog: the fixed torch center (canvas coordinates).
  Offset get torchCenter => _torchCenter;

  /// The fog density level.
  FogLevel get fogLevel => _fogLevel;

  /// IDs of revealed (tapped) nodes.
  Set<String> get revealedNodeIds => _revealedNodeIds;

  /// The cluster awaiting self-evaluation.
  String? get pendingEvalClusterId => _pendingEvalClusterId;

  /// Cinematic reveal progress (0.0 → 1.0).
  double get revealProgress => _revealProgress;

  /// Per-node entries for the current session.
  Map<String, FogNodeEntry> get nodeEntries =>
      _session?.nodeEntries ?? const {};

  /// 🧠 Partial Zone Memory: IDs of nodes that failed in the previous
  /// session in the same zone. For '⚠️ critico l'ultima volta' markers.
  Set<String> get priorFailureNodeIds => _priorFailureNodeIds;

  /// Inject prior failure IDs (called from wiring after loading history).
  set priorFailureNodeIds(Set<String> ids) {
    _priorFailureNodeIds = ids;
    notifyListeners();
  }

  /// Summary text (P10-22): localized version.
  ///
  /// Applies **Muro Rosso** emotional protection (§XI.4):
  /// When >70% of nodes are forgotten/blindspot, the language shifts
  /// from deficit-focused to metacognitive-constructive.
  ///
  /// Also includes slow recall analytics for fragile consolidation.
  ///
  /// [l10n] must be provided by the UI layer (which has BuildContext).
  /// If null, falls back to the old hardcoded Italian strings.
  String localizedSummaryText(FlueraLocalizations? l10n) {
    if (_session == null) return '';
    final s = _session!;

    // Count slow recalls (>8s response time).
    final slowRecallCount = s.nodeEntries.values
        .where((e) =>
            e.status == FogNodeStatus.recalled &&
            e.responseTime != null &&
            e.responseTime!.inSeconds >= 8)
        .length;

    // §XI.4: Muro Rosso detection — if >70% red/grey, activate protection.
    final failedCount = s.forgottenCount + s.blindSpotCount;
    final failureRatio = s.totalNodes > 0 ? failedCount / s.totalNodes : 0.0;

    if (failureRatio > 0.7 && s.totalNodes >= 3) {
      // Protective messaging: focus on what was identified, not what failed.
      final parts = <String>[];
      if (s.recalledCount > 0) {
        parts.add(l10n?.fow_muroRossoNodesYours(s.recalledCount)
            ?? '✅ ${s.recalledCount} nodi sono tuoi');
      }
      parts.add(l10n?.fow_muroRossoPreciseZones(failedCount)
          ?? '🎯 Hai identificato $failedCount zone precise da rafforzare');
      parts.add(l10n?.fow_muroRossoNowYouKnow
          ?? 'Ora sai esattamente dove lavorare');

      // Coaching: tactical suggestion.
      final coaching = l10n?.fow_muroRossoCoaching
          ?? '💡 Prova a riscrivere a memoria i concetti '
              'che ti sembravano più familiari — il Generation Effect '
              'rafforzerà la traccia mnemonica.';

      return '${parts.join('. ')}.\n\n$coaching';
    }

    // Standard summary (P10-22).
    final base = l10n?.fow_summaryStandard(
          s.recalledCount, s.totalNodes, s.forgottenCount, s.blindSpotCount)
        ?? 'Hai ricostruito ${s.recalledCount} nodi su ${s.totalNodes}. '
            '${s.forgottenCount} dimenticati. '
            '${s.blindSpotCount} non visitati.';

    // Append slow recall note if relevant.
    if (slowRecallCount > 0) {
      final slowNote = l10n?.fow_summarySlowRecall(slowRecallCount)
          ?? '⏱️ $slowRecallCount con recall lento (>8s) — consolidamento fragile.';
      return '$base\n$slowNote';
    }
    return base;
  }

  /// Legacy getter — delegates to [localizedSummaryText] with no l10n.
  String get summaryText => localizedSummaryText(null);

  /// Whether the Muro Rosso (§XI.4) emotional protection is active.
  ///
  /// Returns true when >70% of nodes are forgotten or blind spots.
  /// UI should soften red visuals and emphasize green achievements.
  bool get isMuroRossoActive {
    if (_session == null) return false;
    final s = _session!;
    if (s.totalNodes < 3) return false;
    final failedCount = s.forgottenCount + s.blindSpotCount;
    return (failedCount / s.totalNodes) > 0.7;
  }

  /// Fog level description for UI — localized.
  String localizedFogLevelLabel(FlueraLocalizations? l10n) {
    switch (_fogLevel) {
      case FogLevel.light:
        return l10n?.fow_fogLevelLight ?? 'Nebbia Leggera';
      case FogLevel.medium:
        return l10n?.fow_fogLevelMedium ?? 'Nebbia Media';
      case FogLevel.total:
        return l10n?.fow_fogLevelTotal ?? 'Nebbia Totale';
    }
  }

  /// Legacy getter — delegates to [localizedFogLevelLabel] with no l10n.
  String get fogLevelLabel => localizedFogLevelLabel(null);

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVATION (P10-01, P10-02, P10-03)
  // ─────────────────────────────────────────────────────────────────────────

  /// Activate Fog of War for the given zone.
  ///
  /// [zone] is the selected area in canvas coordinates.
  /// [clustersInZone] are the original clusters within that zone.
  /// [canvasId] identifies the canvas for persistence.
  /// [fogLevel] is the chosen fog density (P10-03).
  void activate({
    required Rect zone,
    required List<ContentCluster> clustersInZone,
    required String canvasId,
    required FogLevel fogLevel,
  }) {
    if (isActive) return;

    _selectedZone = zone;
    _originalClusters = List.unmodifiable(clustersInZone);
    _fogLevel = fogLevel;
    _torchCenter = zone.center; // Fixed anchor for medium fog.
    _revealedNodeIds.clear();
    _pendingEvalClusterId = null;
    _revealProgress = 0.0;
    _hintsUsed = 0;

    // Compute deterministic zone ID.
    final zoneId =
        'zone_${zone.left.toInt()}_${zone.top.toInt()}_'
        '${zone.width.toInt()}_${zone.height.toInt()}';

    _session = FogOfWarSession(
      sessionId: 'fog_${DateTime.now().millisecondsSinceEpoch}',
      canvasId: canvasId,
      zoneId: zoneId,
      fogLevel: fogLevel,
      startedAt: DateTime.now(),
      totalNodes: clustersInZone.length,
    );

    // Initialize entries for all clusters.
    for (final cluster in clustersInZone) {
      _session!.nodeEntries[cluster.id] = FogNodeEntry(
        clusterId: cluster.id,
      );
    }

    _phase = FogPhase.active;
    _telemetry.logEvent('step_10_fog_of_war_aperture', properties: {
      'fog_level': fogLevel.name,
      'total_nodes': clustersInZone.length,
      'zone_id': zoneId,
    });
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HINT SYSTEM — "Non ricordo dove sono i nodi"
  // ─────────────────────────────────────────────────────────────────────────

  /// Number of hints used in this session.
  int _hintsUsed = 0;

  /// Number of hints used.
  int get hintsUsed => _hintsUsed;

  /// Get a hint: returns the centroid of a random unrevealed node,
  /// or null if all nodes are already revealed.
  ///
  /// Pedagogically, using a hint marks the node as a "blind spot" —
  /// the student couldn't recall its position, which is meaningful data.
  Offset? getHintPosition() {
    if (_phase != FogPhase.active) return null;

    final unrevealed = _originalClusters
        .where((c) => !_revealedNodeIds.contains(c.id))
        .toList();
    if (unrevealed.isEmpty) return null;

    _hintsUsed++;
    // Return the first unrevealed node's approximate area (centroid).
    return unrevealed.first.centroid;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAP HANDLING (P10-05, P10-06, P10-07)
  // ─────────────────────────────────────────────────────────────────────────

  /// Handle a tap at a canvas-space position.
  ///
  /// Returns the cluster ID if a node was hit, null otherwise.
  /// For [FogLevel.total], uses 50px tolerance (P10-07).
  /// For other levels, uses standard bounds hit-test.
  ///
  /// [canvasScale] is needed to scale the hit tolerance inversely with
  /// zoom — at low zoom a finger tap covers a large canvas area, so the
  /// tolerance must grow to remain usable.
  String? handleTap(Offset canvasPosition, {double canvasScale = 1.0}) {
    if (_phase != FogPhase.active) return null;
    if (_pendingEvalClusterId != null) return null; // Already evaluating.

    // Scale-independent tolerance: ~44px finger size in screen space,
    // converted to canvas space. Minimum 20px canvas units.
    final fingerRadius = (22.0 / canvasScale).clamp(20.0, 300.0);

    for (final cluster in _originalClusters) {
      // Skip already revealed nodes.
      if (_revealedNodeIds.contains(cluster.id)) continue;

      bool hit = false;
      if (_fogLevel == FogLevel.total) {
        // P10-07: generous tolerance from centroid (scales with zoom).
        final distance = (cluster.centroid - canvasPosition).distance;
        hit = distance <= fingerRadius.clamp(50.0, 300.0);
      } else {
        // Standard bounds hit-test with scale-aware inflation.
        hit = cluster.bounds.inflate(fingerRadius).contains(canvasPosition);
      }

      if (hit) {
        _revealNode(cluster.id);
        return cluster.id;
      }
    }

    return null; // P10-07: "Se tocca e non c'è nulla: nessun feedback"
  }

  /// Get the SQUARED distance from [canvasPosition] to the nearest
  /// unrevealed node. Returns null if all nodes are revealed.
  ///
  /// 🚀 OPT-5: Uses distanceSquared to avoid sqrt on every missed tap.
  /// Caller should compare against threshold² (e.g., 100² = 10000).
  double? getNearestUnrevealedDistanceSq(Offset canvasPosition) {
    double? minDistSq;
    for (final cluster in _originalClusters) {
      if (_revealedNodeIds.contains(cluster.id)) continue;
      final delta = cluster.centroid - canvasPosition;
      final dSq = delta.dx * delta.dx + delta.dy * delta.dy;
      if (minDistSq == null || dSq < minDistSq) {
        minDistSq = dSq;
      }
    }
    return minDistSq;
  }

  /// Mark a node as tapped, awaiting self-evaluation.
  ///
  /// The node is NOT visually revealed yet — it stays fogged until
  /// the student completes the self-evaluation via [recordResult].
  /// This ensures the student declares confidence BEFORE seeing content
  /// (explicit metacognition, P10-08).
  void _revealNode(String clusterId) {
    // Do NOT add to _revealedNodeIds here — visual reveal happens
    // only after self-evaluation in recordResult().
    _pendingEvalClusterId = clusterId;
    _nodeStopwatch
      ..reset()
      ..start();

    final entry = _session?.nodeEntries[clusterId];
    if (entry != null) {
      entry.revealedAt = DateTime.now();
    }

    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SELF-EVALUATION (P10-08)
  // ─────────────────────────────────────────────────────────────────────────

  /// Record the student's self-evaluation for the pending node.
  ///
  /// [recalled] is true for ✅ (remembered) and false for ❌ (forgot).
  /// [confidence] is the metacognitive confidence rating (1-5),
  /// per P10-08 / P6-07→P6-14 integration.
  void recordResult(
    String clusterId, {
    required bool recalled,
    int? confidence,
  }) {
    if (_session == null) return;
    if (_pendingEvalClusterId != clusterId) return;

    _nodeStopwatch.stop();

    final entry = _session!.nodeEntries[clusterId];
    if (entry != null) {
      entry.status =
          recalled ? FogNodeStatus.recalled : FogNodeStatus.forgotten;
      entry.responseTime = _nodeStopwatch.elapsed;
      entry.confidence = confidence;
    }

    // Visual reveal happens NOW — after the student declared confidence.
    // This guarantees the metacognitive judgment is uncontaminated (P10-08).
    _revealedNodeIds.add(clusterId);
    _pendingEvalClusterId = null;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MASTERY MAP NAVIGATION (P10-21)
  // ─────────────────────────────────────────────────────────────────────────

  /// Set of cluster IDs explored during mastery map (tapped red/grey nodes).
  final Set<String> _masteryExploredIds = {};

  /// Whether a cluster has been explored during mastery map post-reveal.
  bool isMasteryExplored(String clusterId) =>
      _masteryExploredIds.contains(clusterId);

  /// Handle tap on a node during mastery map phase — marks as "reviewed".
  ///
  /// Content is already visible after the cinematic reveal. This tap
  /// marks the node as acknowledged by the student (visual state change
  /// from ❌/👁‍🗨 to 📖) and triggers a zoom for closer reading.
  ///
  /// Returns a [MasteryMapTapResult] with the cluster ID and its status,
  /// or null if the tap didn't hit a red/grey node.
  MasteryMapTapResult? handleMasteryMapTap(
    Offset canvasPosition, {
    double canvasScale = 1.0,
  }) {
    if (_phase != FogPhase.masteryMap) return null;

    final fingerRadius = (22.0 / canvasScale).clamp(20.0, 300.0);
    for (final cluster in _originalClusters) {
      if (cluster.bounds.inflate(fingerRadius).contains(canvasPosition)) {
        final entry = _session?.nodeEntries[cluster.id];
        if (entry != null &&
            (entry.status == FogNodeStatus.forgotten ||
             entry.status == FogNodeStatus.blindSpot)) {
          // Mark as reviewed — painter changes icon to 📖.
          _masteryExploredIds.add(cluster.id);
          _revealedNodeIds.add(cluster.id);
          notifyListeners();
          return MasteryMapTapResult(
            clusterId: cluster.id,
            status: entry.status,
          );
        }
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SESSION END (P10-18 → P10-22)
  // ─────────────────────────────────────────────────────────────────────────

  /// End the active session — transition to cinematic reveal.
  ///
  /// All unvisited nodes become "blind spots" (P10-20).
  void endSession() {
    if (_phase != FogPhase.active) return;

    // Cancel any pending evaluation.
    _pendingEvalClusterId = null;

    // Mark all hidden nodes as blind spots.
    if (_session != null) {
      for (final entry in _session!.nodeEntries.values) {
        if (entry.status == FogNodeStatus.hidden) {
          entry.status = FogNodeStatus.blindSpot;
        }
      }
      _session!.completedAt = DateTime.now();
    }

    _phase = FogPhase.revealing;
    _revealProgress = 0.0;
    notifyListeners();
  }

  /// Update the cinematic reveal progress (driven by animation controller).
  ///
  /// When progress reaches 1.0, transitions to mastery map phase.
  void updateRevealProgress(double progress) {
    _revealProgress = progress.clamp(0.0, 1.0);
    if (_revealProgress >= 1.0 && _phase == FogPhase.revealing) {
      _phase = FogPhase.masteryMap;
    }
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISMISS
  // ─────────────────────────────────────────────────────────────────────────

  /// Dismiss Fog of War and return to normal canvas.
  ///
  /// Session data is preserved — call [session] to retrieve for persistence.
  void dismiss() {
    if (!isActive) return;

    // If still active (not ended), end the session first.
    if (_phase == FogPhase.active) {
      endSession();
    }

    _phase = FogPhase.inactive;
    _revealProgress = 0.0;
    _pendingEvalClusterId = null;
    _revealedNodeIds.clear();
    _masteryExploredIds.clear();
    _priorFailureNodeIds.clear();
    _overriddenSurgicalPlanIds = null;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SRS INTEGRATION (P10-23)
  // ─────────────────────────────────────────────────────────────────────────

  /// IDs of nodes that need priority SRS reset (P10-23).
  ///
  /// Returns cluster IDs for nodes that were forgotten or never visited
  /// (blind spots). These should have their SRS interval reset to 1 day.
  List<String> get surgicalPlanNodeIds =>
      _overriddenSurgicalPlanIds ?? _session?.surgicalPlanNodeIds ?? const [];

  /// Overridden surgical plan order (M: Spatial Ordering).
  List<String>? _overriddenSurgicalPlanIds;

  /// Replace the surgical plan node order with a spatially optimized path.
  void overrideSurgicalPlanOrder(List<String> orderedIds) {
    _overriddenSurgicalPlanIds = orderedIds;
    notifyListeners();
  }

  /// Export the completed session as JSON for persistence (P10-25).
  ///
  /// Returns null if no session has been completed.
  Map<String, dynamic>? exportSessionJson() => _session?.toJson();

  // ─────────────────────────────────────────────────────────────────────────
  // VISIBILITY HELPERS (for painter)
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether a node should be visible given the current fog level and
  /// viewport center position.
  ///
  /// Used by the overlay painter for per-node fog rendering.
  bool isNodeVisible(
    ContentCluster cluster, {
    required Offset viewportCenterCanvas,
  }) {
    // Always visible if already revealed.
    if (_revealedNodeIds.contains(cluster.id)) return true;

    // During mastery map / revealing, all are visible.
    if (_phase == FogPhase.masteryMap || _phase == FogPhase.revealing) {
      return true;
    }

    switch (_fogLevel) {
      case FogLevel.light:
        // Silhouettes always visible (at 15% opacity — handled by painter).
        return true;
      case FogLevel.medium:
        // Faint silhouettes visible everywhere (like light, but harder to
        // see). Visibility handled by painter opacity, not by radius.
        return true;
      case FogLevel.total:
        // Never visible until tapped (P10-07).
        return false;
    }
  }

  /// Get the fog opacity for a node (for silhouette rendering in Light fog).
  ///
  /// Returns 0.15 for Light fog silhouettes (P10-05),
  /// 0.0 for hidden nodes in Medium/Total.
  double nodeOpacity(ContentCluster cluster, {
    required Offset viewportCenterCanvas,
  }) {
    if (_revealedNodeIds.contains(cluster.id)) return 1.0;
    if (_phase == FogPhase.masteryMap) return 1.0;

    switch (_fogLevel) {
      case FogLevel.light:
        return 0.15; // P10-05: silhouettes at 15% opacity
      case FogLevel.medium:
        // Faint silhouettes everywhere — opacity handled by painter.
        return 0.10;
      case FogLevel.total:
        return 0.0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _nodeStopwatch.stop();
    super.dispose();
  }

  @override
  String toString() =>
      'FogOfWarController(phase: $_phase, '
      'fogLevel: $_fogLevel, '
      'revealed: ${_revealedNodeIds.length}/${_originalClusters.length})';
}
