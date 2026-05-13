import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../../ai/ai_provider.dart';
import '../../ai/cluster_action.dart';
import '../../ai/cluster_action_executor.dart';
import '../../ai/telemetry_recorder.dart';
import '../../layers/layer_controller.dart';
import '../../reflow/knowledge_connection.dart';
import '../../reflow/knowledge_flow_controller.dart';
import '../../reflow/content_cluster.dart';
import '../../services/cross_zone_bridge_persistence.dart';
import 'cluster_concept.dart';
import 'cluster_concept_index.dart';

// ============================================================================
// 🌉 CROSS-ZONE BRIDGE CONTROLLER — Passo 9 orchestrator
//
// Manages the complete cross-domain bridge workflow:
// - AI-driven bridge suggestions (Socratic questions, P9-08-11)
// - Student-created bridge tracking (P9-12: 💡 icon)
// - Bridge stats for session data (P9-18)
// - Accept/dismiss lifecycle for ghost bridges
//
// Design principles:
// - IA suggests bridges as QUESTIONS, never as assertions (P9-09)
// - Student must trace over the dashed line to accept (P9-10)
// - All bridges annotated by the student at the midpoint (P9-06)
// - Zero allocations in the hot path (rendering is in painter)
// ============================================================================

/// Fired once when the student accepts a bridge suggestion. Carries the
/// pair of cluster IDs and the bridge type so the host canvas can drive
/// FSRS consolidation (Bjork 1994 desirable difficulty: a transferred
/// concept earns a small stability bump on both sides) and surface
/// downstream affordances (Ghost Map golden tint, Socratic seed entry).
typedef BridgeAcceptedCallback = void Function({
  required String sourceClusterId,
  required String targetClusterId,
  required CrossZoneBridgeType bridgeType,
  required String socraticQuestion,
});

/// A single AI-suggested cross-zone bridge candidate.
class CrossZoneBridgeSuggestion {
  /// Unique ID for this suggestion.
  final String id;

  /// Source cluster ID.
  final String sourceClusterId;

  /// Target cluster ID.
  final String targetClusterId;

  /// Socratic question (P9-09): never an assertion, always a question.
  /// e.g., "Hai notato che X in Biologia e Y in Economia condividono
  /// la stessa struttura? Cosa hanno in comune?"
  final String socraticQuestion;

  /// Bridge type classification (A/B/C).
  final CrossZoneBridgeType bridgeType;

  /// Confidence score (0.0–1.0) from AI.
  final double confidence;

  /// Whether this suggestion has been dismissed.
  bool dismissed;

  /// Timestamp when this suggestion was surfaced (ms since epoch).
  final int surfacedAtMs;

  CrossZoneBridgeSuggestion({
    required this.id,
    required this.sourceClusterId,
    required this.targetClusterId,
    required this.socraticQuestion,
    required this.bridgeType,
    this.confidence = 0.7,
    this.dismissed = false,
    int? surfacedAt,
  }) : surfacedAtMs = surfacedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceClusterId': sourceClusterId,
        'targetClusterId': targetClusterId,
        'socraticQuestion': socraticQuestion,
        'bridgeType': bridgeType.name,
        'confidence': confidence,
        'dismissed': dismissed,
        'surfacedAtMs': surfacedAtMs,
      };

  factory CrossZoneBridgeSuggestion.fromJson(Map<String, dynamic> json) {
    return CrossZoneBridgeSuggestion(
      id: json['id'] as String,
      sourceClusterId: json['sourceClusterId'] as String,
      targetClusterId: json['targetClusterId'] as String,
      socraticQuestion: json['socraticQuestion'] as String,
      bridgeType: CrossZoneBridgeType.values
          .where((e) => e.name == json['bridgeType'])
          .firstOrNull ?? CrossZoneBridgeType.analogyStructural,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.7,
      dismissed: json['dismissed'] as bool? ?? false,
      surfacedAt: json['surfacedAtMs'] as int?,
    );
  }
}

/// Accumulated stats for the bridge session (P9-18).
class BridgeSessionStats {
  /// Total bridges in the canvas.
  int totalBridges;

  /// Bridges discovered autonomously by the student.
  int studentDiscovered;

  /// Bridges accepted from AI suggestions.
  int aiSuggested;

  /// Number of distinct zones connected.
  int zonesConnected;

  /// Number of AI suggestions dismissed.
  int suggestionsDismissed;

  BridgeSessionStats({
    this.totalBridges = 0,
    this.studentDiscovered = 0,
    this.aiSuggested = 0,
    this.zonesConnected = 0,
    this.suggestionsDismissed = 0,
  });

  Map<String, dynamic> toJson() => {
    'totalBridges': totalBridges,
    'studentDiscovered': studentDiscovered,
    'aiSuggested': aiSuggested,
    'zonesConnected': zonesConnected,
    'suggestionsDismissed': suggestionsDismissed,
  };

  factory BridgeSessionStats.fromJson(Map<String, dynamic> json) =>
      BridgeSessionStats(
        totalBridges: (json['totalBridges'] as num?)?.toInt() ?? 0,
        studentDiscovered: (json['studentDiscovered'] as num?)?.toInt() ?? 0,
        aiSuggested: (json['aiSuggested'] as num?)?.toInt() ?? 0,
        zonesConnected: (json['zonesConnected'] as num?)?.toInt() ?? 0,
        suggestionsDismissed:
            (json['suggestionsDismissed'] as num?)?.toInt() ?? 0,
      );
}

/// 🌉 Controller for Passo 9 — Cross-Domain Bridges.
///
/// Orchestrates the complete bridge workflow:
/// 1. Student invokes "Suggeriscimi connessioni" (P9-08)
/// 2. AI analyzes cross-zone clusters and returns Socratic questions
/// 3. Ghost dashed golden lines appear between suggested clusters
/// 4. Student traces over a suggestion → materializes into solid bridge
/// 5. Student writes annotation at the midpoint (P9-06)
///
/// This controller is pure logic — no UI, no BuildContext.
class CrossZoneBridgeController {
  final KnowledgeFlowController _flowController;

  /// Current pending suggestions (not yet accepted or dismissed).
  final List<CrossZoneBridgeSuggestion> _suggestions = [];

  /// Unmodifiable view of active suggestions (cached).
  List<CrossZoneBridgeSuggestion> _activeSuggestionsCache = const [];
  int _activeSuggestionsCacheVersion = -1;

  List<CrossZoneBridgeSuggestion> get suggestions {
    if (_activeSuggestionsCacheVersion != version.value) {
      _activeSuggestionsCache = List.unmodifiable(
        _suggestions.where((s) => !s.dismissed),
      );
      _activeSuggestionsCacheVersion = version.value;
    }
    return _activeSuggestionsCache;
  }

  /// Whether the AI is currently generating suggestions.
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Session stats.
  final BridgeSessionStats stats = BridgeSessionStats();

  /// Version counter — for UI repaint triggers.
  final ValueNotifier<int> version = ValueNotifier(0);

  CrossZoneBridgeController({
    required KnowledgeFlowController flowController,
    TelemetryRecorder? telemetry,
    String? canvasId,
    BridgeAcceptedCallback? onBridgeAccepted,
  })  : _flowController = flowController,
        _telemetry = telemetry ?? TelemetryRecorder.noop,
        _canvasId = canvasId,
        _onBridgeAccepted = onBridgeAccepted;

  final TelemetryRecorder _telemetry;

  /// Canvas ID for [CrossZoneBridgePersistence] cache. When null, the
  /// suggestion cache is disabled (every request hits the AI).
  final String? _canvasId;

  /// Optional fire-and-forget callback invoked once the student accepts a
  /// bridge. Drives downstream cognitive consolidation (FSRS bump on the
  /// concepts of both sides, Ghost Map golden tint, Socratic seed entry).
  /// Kept here as a callback so the controller stays pure-logic and
  /// testable without dragging in FSRS / Ghost Map dependencies.
  final BridgeAcceptedCallback? _onBridgeAccepted;

  // ===========================================================================
  // BRIDGE QUERY & RETRIEVAL
  // ===========================================================================

  /// Cluster IDs that are currently linked by an accepted cross-zone bridge.
  ///
  /// Consumed by Ghost Map to apply a golden tint on connected clusters so
  /// the student can see at a glance which zones share a transfer link.
  Set<String> get crossZoneConnectedClusters {
    final ids = <String>{};
    for (final b in getCrossZoneBridges()) {
      ids.add(b.sourceClusterId);
      ids.add(b.targetClusterId);
    }
    return ids;
  }

  /// Recently accepted cross-zone bridges (default: last 7 days), most
  /// recent first. Consumed by Socratic Mode to surface "Approfondisci
  /// questo ponte" follow-up sessions seeded by the bridge's question.
  List<KnowledgeConnection> recentAcceptedBridges({int withinDays = 7}) {
    final cutoffMs = DateTime.now()
        .subtract(Duration(days: withinDays))
        .millisecondsSinceEpoch;
    final bridges = getCrossZoneBridges()
        .where((b) =>
            b.discoveredBy == BridgeDiscoveryOrigin.aiSuggested &&
            b.createdAtMs >= cutoffMs &&
            b.bridgeSocraticQuestion != null)
        .toList();
    bridges.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return bridges;
  }

  /// Get all cross-zone bridges from the flow controller.
  List<KnowledgeConnection> getCrossZoneBridges() {
    return _flowController.connections
        .where((c) => c.isCrossZone && c.deletedAtMs == 0)
        .toList();
  }

  /// Count distinct zones connected by cross-zone bridges.
  int countConnectedZones() {
    final zoneIds = <String>{};
    for (final conn in getCrossZoneBridges()) {
      zoneIds.add(conn.sourceClusterId);
      zoneIds.add(conn.targetClusterId);
    }
    return zoneIds.length;
  }

  /// Recompute session stats from current state.
  void refreshStats() {
    final bridges = getCrossZoneBridges();
    stats.totalBridges = bridges.length;
    stats.studentDiscovered = bridges
        .where((b) => b.discoveredBy == BridgeDiscoveryOrigin.student)
        .length;
    stats.aiSuggested = bridges
        .where((b) => b.discoveredBy == BridgeDiscoveryOrigin.aiSuggested)
        .length;
    stats.zonesConnected = countConnectedZones();
  }

  // ===========================================================================
  // AI BRIDGE SUGGESTIONS (P9-08-11)
  // ===========================================================================

  /// Request AI bridge suggestions for the current canvas.
  ///
  /// [aiProvider] — the AI service to query.
  /// [clusters] — all content clusters on the canvas.
  /// [clusterTexts] — clusterId → OCR recognized text (legacy fallback).
  /// [clusterTitles] — clusterId → AI-generated semantic title (legacy
  ///   fallback). When [index] is provided, the index supersedes both maps.
  /// [index] — [ClusterConceptIndex] for OCR/title consolidation (shared
  ///   with Ghost Map, Socratic, Atlas Exam — eliminates redundant
  ///   Gemini calls per [project_cluster_concept_index]).
  ///
  /// Returns the number of suggestions generated.
  /// The suggestions appear as ghost dashed golden lines.
  Future<int> requestBridgeSuggestions({
    required AiProvider aiProvider,
    required List<ContentCluster> clusters,
    Map<String, String> clusterTexts = const {},
    Map<String, String> clusterTitles = const {},
    ClusterConceptIndex? index,
    String? tier,
  }) async {
    if (_isLoading) return 0;
    if (!aiProvider.isInitialized) return 0;

    // Need at least 2 zones (P9 gate: ≥2 zones with ≥10 nodes)
    if (clusters.length < 2) return 0;

    _isLoading = true;
    version.value++;

    // 🎓 Triennial-scale hygiene: opportunistic tombstone prune. On a
    // 3-year canvas this is the natural moment to GC: we're about to scan
    // tombstones anyway for the avoid-list, so dropping 90+-day stale ones
    // costs nothing extra and keeps the scan O(active dismisses).
    pruneOldDismissedTombstones();

    // If a ClusterConceptIndex is provided, prefer its consolidated OCR
    // and titles over the legacy maps. Resolve all candidate clusters in
    // parallel (idempotent + de-duplicated by the index itself).
    Map<String, String> resolvedTexts = clusterTexts;
    Map<String, String> resolvedTitles = clusterTitles;
    if (index != null) {
      final indexedTexts = <String, String>{};
      final indexedTitles = <String, String>{};
      await Future.wait(clusters.take(12).map((c) async {
        try {
          final concept = await index.resolve(
            c,
            needsCleanedOcr: true,
            needsConcepts: true,
            needsTitle: true,
          );
          final src = concept.bestPromptSource;
          if (src != null && src.trim().isNotEmpty) {
            indexedTexts[c.id] = src;
          }
          final lbl = concept.bestLabel;
          if (lbl.trim().isNotEmpty) indexedTitles[c.id] = lbl;
        } catch (_) {
          // Resolve never throws but be defensive — fall back to legacy maps.
        }
      }));
      if (indexedTexts.isNotEmpty) resolvedTexts = indexedTexts;
      if (indexedTitles.isNotEmpty) resolvedTitles = indexedTitles;
    }

    final sw = Stopwatch()..start();
    int suggestionCount = 0;
    int parseFailures = 0;
    int clustersInPrompt = 0;
    String resultStatus = 'error';
    bool cacheHit = false;

    try {
      // Build prompt with zone data
      final prompt = _buildBridgePrompt(
        clusters: clusters,
        clusterTexts: resolvedTexts,
        clusterTitles: resolvedTitles,
      );

      // Count clusters that actually made it into the prompt (≥10 char text).
      clustersInPrompt = '[[Zone '.allMatches(prompt).length;

      if (prompt.isEmpty) {
        resultStatus = 'empty_prompt';
        return 0;
      }

      // Cache check: deterministic hash of prompt — if a previous request
      // produced suggestions for the same inputs within TTL, replay them.
      final promptHash = _hashPrompt(prompt, clusters);
      final canvasId = _canvasId;
      final dismissedKeys = _dismissedPairKeys();
      if (canvasId != null) {
        final cached = await CrossZoneBridgePersistence.instance
            .loadIfFresh(canvasId, promptHash);
        if (cached != null && cached.isNotEmpty) {
          final cachedFiltered = cached
              .where((s) => !dismissedKeys.contains(
                  _pairKey(s.sourceClusterId, s.targetClusterId)))
              .toList();
          if (cachedFiltered.isNotEmpty) {
            _suggestions.addAll(cachedFiltered);
            _createGhostsFor(cachedFiltered, clusters);
            cacheHit = true;
            suggestionCount = cachedFiltered.length;
            resultStatus = 'cache_hit';
            return suggestionCount;
          }
        }
      }

      // Query AI
      final response = await aiProvider.askFreeText(prompt);
      if (response.isEmpty) {
        resultStatus = 'empty_response';
        return 0;
      }

      // Parse suggestions from AI response
      final parsed = _parseBridgeSuggestions(response, clusters);
      parseFailures = parsed.parseFailures;

      // Filter out pairs the student already dismissed (cross-session).
      final filtered = parsed.suggestions
          .where((s) => !dismissedKeys.contains(
              _pairKey(s.sourceClusterId, s.targetClusterId)))
          .toList();

      _suggestions.addAll(filtered);

      // Persist the *unfiltered* parsed list so a later dismiss/undismiss
      // cycle on the same prompt-hash still replays the full AI output.
      if (canvasId != null && parsed.suggestions.isNotEmpty) {
        unawaited(CrossZoneBridgePersistence.instance
            .save(canvasId, promptHash, parsed.suggestions));
      }

      // Create ghost connections for each suggestion
      _createGhostsFor(filtered, clusters);

      // Cross-feature avoid: tell the index what we just asked about each
      // cluster so Socratic / Exam won't ask the same question 2 min later.
      if (index != null) {
        for (final s in filtered) {
          index.recordQuestionAsked(
              s.sourceClusterId, s.socraticQuestion, AskedBy.crossZone);
          index.recordQuestionAsked(
              s.targetClusterId, s.socraticQuestion, AskedBy.crossZone);
        }
      }

      suggestionCount = filtered.length;
      final filteredOut = parsed.suggestions.length - filtered.length;
      resultStatus = suggestionCount == 0
          ? (filteredOut > 0 ? 'all_dismissed' : 'empty_suggestions')
          : 'success';
      return suggestionCount;
    } catch (e) {
      debugPrint('🌉 [CrossZoneBridge] AI error: $e');
      resultStatus = 'error';
      return 0;
    } finally {
      sw.stop();
      _isLoading = false;
      version.value++;

      _telemetry.logEvent('cross_zone_bridge_request', properties: {
        'latency_ms': sw.elapsedMilliseconds,
        'suggestion_count': suggestionCount,
        'parse_failures': parseFailures,
        'clusters_in_prompt': clustersInPrompt,
        // 🎓 Triennial-scale visibility: how much of the canvas the AI
        // actually saw. A drift between `total_canvas_clusters` (full
        // size of the working set) and `clusters_in_prompt` (12 cap)
        // shows on a 3-year canvas the AI is only inspecting the
        // top-N largest zones — flag for "should we raise the cap?"
        'total_canvas_clusters': clusters.length,
        'result': resultStatus,
        'cache_hit': cacheHit,
        if (tier != null) 'tier': tier,
      });
    }
  }

  // ===========================================================================
  // ACCEPT / DISMISS (P9-10)
  // ===========================================================================

  /// Accept a bridge suggestion — materialize the ghost connection.
  ///
  /// Returns the materialized [KnowledgeConnection], or null if not found.
  KnowledgeConnection? acceptBridge(String suggestionId) {
    final suggestion = _suggestions
        .where((s) => s.id == suggestionId)
        .firstOrNull;
    if (suggestion == null) return null;

    // Find the ghost connection
    final ghost = _flowController.connections
        .where((c) =>
            c.isGhost &&
            c.sourceClusterId == suggestion.sourceClusterId &&
            c.targetClusterId == suggestion.targetClusterId)
        .firstOrNull;
    if (ghost == null) return null;

    // Materialize the ghost into a solid cross-zone bridge
    ghost.materialize();
    ghost.isCrossZone = true;
    ghost.color = KnowledgeConnection.crossZoneColor;
    ghost.bridgeType = suggestion.bridgeType;
    ghost.discoveredBy = BridgeDiscoveryOrigin.aiSuggested;
    ghost.bridgeSocraticQuestion = suggestion.socraticQuestion;

    // Remove from suggestions
    _suggestions.removeWhere((s) => s.id == suggestionId);

    // Update stats
    stats.aiSuggested++;
    stats.totalBridges++;
    stats.zonesConnected = countConnectedZones();

    _telemetry.logEvent('step_9_cross_zone_bridge', properties: {
      'bridge_type': suggestion.bridgeType.name,
      'origin': 'ai_suggested',
      'total_bridges': stats.totalBridges,
      'zones_connected': stats.zonesConnected,
    });

    version.value++;

    // Notify host: drives FSRS bump + Ghost Map color sync + Socratic seed.
    // Fire-and-forget — never block accept on downstream consolidation.
    try {
      _onBridgeAccepted?.call(
        sourceClusterId: suggestion.sourceClusterId,
        targetClusterId: suggestion.targetClusterId,
        bridgeType: suggestion.bridgeType,
        socraticQuestion: suggestion.socraticQuestion,
      );
    } catch (e) {
      debugPrint('🌉 [CrossZoneBridge] onBridgeAccepted error: $e');
    }

    return ghost;
  }

  /// 🧩 F9: Materialize an accepted bridge as a visible stroke connector
  /// via the Atlas cluster dispatcher.
  ///
  /// The accepted [KnowledgeConnection] already lives in `KnowledgeFlow`
  /// (logical layer — FSRS bump, Socratic seed, persistence across
  /// sessions). This method adds a parallel VISUAL layer: a real
  /// [ProStroke] connector inside the canvas scene-graph, so the bridge
  /// survives `.fluera` save/load, appears in PNG/PDF export, and folds
  /// into the F8 composite-undo model (one Ctrl+Z reverts it cleanly).
  ///
  /// Idempotent: if the bridge was already materialized, the duplicate
  /// connector is still added — accept-twice = two strokes, which is the
  /// design choice (each accept is an explicit student act).
  ///
  /// [bridge] is the [KnowledgeConnection] returned by [acceptBridge].
  /// [layerController] and [clusterResolver] are supplied by the host
  /// because this controller stays free of canvas/scene dependencies.
  Future<void> materializeAsStrokeConnector({
    required KnowledgeConnection bridge,
    required LayerController layerController,
    required ContentCluster? Function(String) clusterResolver,
  }) async {
    final label = bridge.bridgeSocraticQuestion;
    final shortLabel = label == null
        ? null
        : (label.length > 40 ? '${label.substring(0, 40)}…' : label);

    final action = ConnectClustersAction(
      fromId: bridge.sourceClusterId,
      toId: bridge.targetClusterId,
      label: shortLabel,
    );
    final executor = ClusterActionExecutor(
      clusterResolver: clusterResolver,
      layerController: layerController,
    );
    await layerController.runAsBatch(
      'Bridge: ${bridge.sourceClusterId} → ${bridge.targetClusterId}',
      () async => executor.executeAll([action]),
    );

    _telemetry.logEvent('bridge_materialized', properties: {
      'source_cluster': bridge.sourceClusterId,
      'target_cluster': bridge.targetClusterId,
      'bridge_type': bridge.bridgeType?.name ?? 'unknown',
      'origin': bridge.discoveredBy?.name ?? 'unknown',
    });
  }

  /// Create ghost connections for [suggestions] anchored to live cluster
  /// centroids. Skips entries whose source or target cluster is no longer
  /// in the canvas (cache replay after stroke deletion).
  void _createGhostsFor(
    List<CrossZoneBridgeSuggestion> suggestions,
    List<ContentCluster> clusters,
  ) {
    for (final suggestion in suggestions) {
      final srcCluster = clusters
          .where((c) => c.id == suggestion.sourceClusterId)
          .firstOrNull;
      final tgtCluster = clusters
          .where((c) => c.id == suggestion.targetClusterId)
          .firstOrNull;
      if (srcCluster == null || tgtCluster == null) continue;

      _flowController.addConnection(
        sourceClusterId: suggestion.sourceClusterId,
        targetClusterId: suggestion.targetClusterId,
        label: suggestion.socraticQuestion.length > 50
            ? '${suggestion.socraticQuestion.substring(0, 47)}…'
            : suggestion.socraticQuestion,
        sourceAnchor: srcCluster.centroid,
        targetAnchor: tgtCluster.centroid,
        isGhost: true,
      );
    }
  }

  /// Deterministic SHA-1 hash of the inputs that materially affect the AI
  /// output. Used as cache key — any change in cluster set, ordering, OCR
  /// text, existing/dismissed bridges, or the prompt template itself
  /// invalidates the cached suggestion list.
  String _hashPrompt(String prompt, List<ContentCluster> clusters) {
    final ids = clusters.map((c) => c.id).toList()..sort();
    final composite = '${clusters.length}|${ids.join(",")}|$prompt';
    return sha1.convert(utf8.encode(composite)).toString();
  }

  /// Find the suggestion associated with a ghost connection.
  ///
  /// Used by the gesture handler to determine if a tapped ghost connection
  /// is an active bridge suggestion (for accept/dismiss UX).
  CrossZoneBridgeSuggestion? findSuggestionForConnection(
    KnowledgeConnection conn,
  ) {
    if (!conn.isGhost) return null;
    return _suggestions
        .where((s) =>
            !s.dismissed &&
            s.sourceClusterId == conn.sourceClusterId &&
            s.targetClusterId == conn.targetClusterId)
        .firstOrNull;
  }

  /// Dismiss a bridge suggestion.
  ///
  /// The ghost connection is **not removed** — it is kept as a tombstone
  /// in the scene with `bridgeSuggestionDismissed = true` so the AI can
  /// avoid re-suggesting the same pair on future requests (cross-session
  /// when the canvas is persisted). Renderers must skip dismissed ghosts.
  void dismissBridge(String suggestionId) {
    final suggestion = _suggestions
        .where((s) => s.id == suggestionId)
        .firstOrNull;
    if (suggestion == null) return;

    suggestion.dismissed = true;

    // Mark the ghost as dismissed (keep as tombstone for avoid-list).
    final ghost = _flowController.connections
        .where((c) =>
            c.isGhost &&
            !c.bridgeSuggestionDismissed &&
            c.sourceClusterId == suggestion.sourceClusterId &&
            c.targetClusterId == suggestion.targetClusterId)
        .firstOrNull;
    if (ghost != null) {
      ghost.bridgeSuggestionDismissed = true;
      ghost.bridgeSocraticQuestion = suggestion.socraticQuestion;
      ghost.bridgeType = suggestion.bridgeType;
    }

    // Remove from active suggestions list (no longer surfaced in UI).
    _suggestions.removeWhere((s) => s.id == suggestionId);

    stats.suggestionsDismissed++;
    version.value++;
  }

  /// Return the set of cluster-pair keys (sourceId↔targetId, order-insensitive)
  /// that have been dismissed by the student. Used to filter prompt and
  /// to deduplicate future AI requests across sessions.
  Set<String> _dismissedPairKeys() {
    final keys = <String>{};
    for (final c in _flowController.connections) {
      if (!c.bridgeSuggestionDismissed) continue;
      // Filter soft-deleted tombstones — they're being dissolve-animated
      // away, e.g. via undo/redo of a dismiss. Don't block their pair.
      if (c.deletedAtMs != 0) continue;
      keys.add(_pairKey(c.sourceClusterId, c.targetClusterId));
    }
    return keys;
  }

  /// 🎓 TRIENNIAL-SCALE: prune dismissed-ghost tombstones older than
  /// [maxAge] (default 90 days). On a 3-year canvas tombstones grow
  /// unbounded and the `_dismissedPairKeys` scan becomes hot. Pruning
  /// 90+-day-old dismisses is safe — if the AI re-suggests an old pair
  /// the student has clearly forgotten the previous dismiss anyway.
  /// Returns the number of tombstones removed.
  int pruneOldDismissedTombstones({
    Duration maxAge = const Duration(days: 90),
  }) {
    final cutoffMs =
        DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    final stale = _flowController.connections
        .where((c) =>
            c.bridgeSuggestionDismissed && c.createdAtMs < cutoffMs)
        .map((c) => c.id)
        .toList();
    for (final id in stale) {
      // Hard removal (no dissolve animation) — tombstones are already
      // invisible to the painter (`bridgeSuggestionDismissed=true`), so
      // an animated remove would be a no-op visually but cost 550ms of
      // the connection lingering in the list.
      _flowController.removeConnectionImmediately(id);
    }
    if (stale.isNotEmpty) {
      _telemetry.logEvent('cross_zone_bridge_tombstones_pruned',
          properties: {'count': stale.length});
      version.value++;
    }
    return stale.length;
  }

  /// Symmetric pair key (order-insensitive) for cluster A↔B deduplication.
  String _pairKey(String a, String b) {
    return (a.compareTo(b) <= 0) ? '$a↔$b' : '$b↔$a';
  }

  // ===========================================================================
  // STUDENT BRIDGE CREATION (P9-12)
  // ===========================================================================

  /// Mark a connection as a student-discovered cross-zone bridge.
  ///
  /// Called when the student manually creates a cross-zone connection.
  /// Sets the discovery origin to `student` and the icon to 💡.
  void markAsStudentBridge(
    KnowledgeConnection connection, {
    CrossZoneBridgeType? bridgeType,
  }) {
    connection.discoveredBy = BridgeDiscoveryOrigin.student;
    connection.bridgeType = bridgeType;

    stats.studentDiscovered++;
    stats.totalBridges++;
    stats.zonesConnected = countConnectedZones();

    version.value++;
  }

  /// Link a bridge annotation cluster to a cross-zone bridge (P9-06).
  ///
  /// The student writes at the midpoint of the arrow, and the resulting
  /// cluster is linked to the bridge for rendering.
  void setAnnotationCluster(
    String connectionId,
    String annotationClusterId,
  ) {
    final conn = _flowController.connections
        .where((c) => c.id == connectionId)
        .firstOrNull;
    if (conn == null) return;
    conn.bridgeAnnotationClusterId = annotationClusterId;
    version.value++;
  }

  // ===========================================================================
  // NAVIGATION (P9-16-18)
  // ===========================================================================

  /// Get source and target centroids for cinematic flight to a bridge.
  ///
  /// Returns (sourceCentroid, targetCentroid) or null if clusters not found.
  ({Offset source, Offset target})? getBridgeEndpoints(
    KnowledgeConnection bridge,
    List<ContentCluster> clusters,
  ) {
    final srcCluster = clusters
        .where((c) => c.id == bridge.sourceClusterId)
        .firstOrNull;
    final tgtCluster = clusters
        .where((c) => c.id == bridge.targetClusterId)
        .firstOrNull;
    if (srcCluster == null || tgtCluster == null) return null;
    return (source: srcCluster.centroid, target: tgtCluster.centroid);
  }

  // ===========================================================================
  // AI PROMPT BUILDING (Component 3 — inline for encapsulation)
  // ===========================================================================

  String _buildBridgePrompt({
    required List<ContentCluster> clusters,
    required Map<String, String> clusterTexts,
    Map<String, String> clusterTitles = const {},
  }) {
    // 🎓 TRIENNIAL-SCALE NOTE: a Fluera canvas can hold 3 years of notes →
    // 100+ clusters. The AI prompt caps at 12 zones (token budget); naive
    // first-in-iteration-order would pick year-1 stale material and miss
    // the student's current focus. We rank by descending content size
    // (elementCount = strokes+shapes+texts+images), which is a strong
    // proxy for "zone where active study is happening right now".
    final ranked = clusters
        .where((c) {
          final t = clusterTexts[c.id];
          return t != null && t.trim().length >= 10;
        })
        .toList()
      ..sort((a, b) => b.elementCount.compareTo(a.elementCount));

    final parts = <String>[];
    int index = 0;
    for (final cluster in ranked) {
      final text = clusterTexts[cluster.id]!;
      index++;
      final title = clusterTitles[cluster.id];
      final truncated =
          text.length > 200 ? text.substring(0, 200) : text;
      final x = cluster.centroid.dx.round();
      final y = cluster.centroid.dy.round();
      parts.add(
        '[[Zone $index${title != null ? ": $title" : ""}]] '
        '(x: $x, y: $y)\n$truncated',
      );
      if (index >= 12) break; // Cap at 12 zones
    }

    if (parts.length < 2) return '';

    final zonesSummary = parts.join('\n\n---\n\n');

    // Existing cross-zone connections (avoid duplicates)
    final existingBridges = getCrossZoneBridges();
    final existingStr = existingBridges
        .map((b) => '${b.sourceClusterId} ↔ ${b.targetClusterId}'
            '${b.label != null ? " (${b.label})" : ""}')
        .join('\n');

    // Dismissed bridges (student rejected) — never re-suggest these pairs.
    // Mirror the [_dismissedPairKeys] filter: skip soft-deleted tombstones.
    final dismissedStr = _flowController.connections
        .where(
            (c) => c.bridgeSuggestionDismissed && c.deletedAtMs == 0)
        .map((c) => '${c.sourceClusterId} ↔ ${c.targetClusterId}')
        .join('\n');

    return '''
<ROLE>
You are Atlas, a cognitive tutor specialized in cross-domain thinking.
Your task: identify hidden connections between different knowledge areas
in the student's notes. You must frame each connection as a SOCRATIC
QUESTION — never as an assertion.
</ROLE>

<TASK>
Analyze the student's note zones below and find 2-4 cross-domain bridges.
Each bridge must connect concepts from DIFFERENT zones that share:
- Type A (analogyStructural): Structural similarity across domains
- Type B (sharedMechanism): Shared underlying mechanism
- Type C (complementaryPerspective): Complementary perspectives
</TASK>

<HARD_CONSTRAINTS>
1. SOCRATIC FORMAT: Each suggestion MUST be a question, never a statement.
   Good: "Hai notato che X e Y condividono la stessa struttura?"
   Bad: "X e Y sono collegati perché..."
2. LANGUAGE: Match the student's notes language. If notes are in Italian,
   respond in Italian.
3. DIFFERENT ZONES: Each bridge MUST connect concepts from different zones.
   Never suggest intra-zone bridges.
4. SPECIFICITY: Reference actual concepts from the notes, not generic ideas.
5. NO DUPLICATES: Do not suggest bridges that already exist.
6. NO DISMISSED: Do not re-suggest pairs that the student dismissed before.
</HARD_CONSTRAINTS>

<STUDENT_ZONES>
$zonesSummary
</STUDENT_ZONES>

${existingStr.isNotEmpty ? '<EXISTING_BRIDGES>\n$existingStr\n</EXISTING_BRIDGES>' : ''}

${dismissedStr.isNotEmpty ? '<DISMISSED_BRIDGES>\n$dismissedStr\n</DISMISSED_BRIDGES>' : ''}

<OUTPUT_FORMAT>
Return ONLY a JSON array. No markdown, no explanation.
[
  {
    "source_zone": 1,
    "target_zone": 3,
    "bridge_type": "analogyStructural|sharedMechanism|complementaryPerspective",
    "socratic_question": "Your Socratic question here?",
    "confidence": 0.85
  }
]
</OUTPUT_FORMAT>''';
  }

  // ===========================================================================
  // AI RESPONSE PARSING
  // ===========================================================================

  /// Parse result returned by [_parseBridgeSuggestions].
  ///
  /// Includes a [parseFailures] count for telemetry: items that were present
  /// in the AI response but failed schema validation (missing field, invalid
  /// zone index, empty question, etc.). A sustained nonzero rate signals
  /// upstream model drift.
  ({
    List<CrossZoneBridgeSuggestion> suggestions,
    int parseFailures,
  }) _parseBridgeSuggestions(
    String response,
    List<ContentCluster> clusters,
  ) {
    final jsonStr = _extractJsonArray(response);
    if (jsonStr == null) {
      return (suggestions: const [], parseFailures: 0);
    }

    final List<dynamic> items = _decodeJsonArray(jsonStr);
    if (items.isEmpty) {
      return (suggestions: const [], parseFailures: 0);
    }

    // Build zone index → cluster ID mapping. MUST mirror the ordering in
    // [_buildBridgePrompt] (sorted by elementCount desc) — otherwise the
    // AI's `source_zone: N` references the wrong cluster on triennial-scale
    // canvases where the first-in-list order differs from size order.
    final validClusters = clusters
        .where((c) => c.elementCount > 0)
        .toList()
      ..sort((a, b) => b.elementCount.compareTo(a.elementCount));
    if (validClusters.length > 12) {
      validClusters.removeRange(12, validClusters.length);
    }

    final suggestions = <CrossZoneBridgeSuggestion>[];
    int parseFailures = 0;
    for (final item in items) {
      try {
        if (item is! Map<String, dynamic>) {
          parseFailures++;
          continue;
        }

        final srcZone = (item['source_zone'] as num?)?.toInt();
        final tgtZone = (item['target_zone'] as num?)?.toInt();
        if (srcZone == null || tgtZone == null) {
          parseFailures++;
          continue;
        }
        if (srcZone < 1 || srcZone > validClusters.length ||
            tgtZone < 1 || tgtZone > validClusters.length ||
            srcZone == tgtZone) {
          parseFailures++;
          continue;
        }

        final srcCluster = validClusters[srcZone - 1];
        final tgtCluster = validClusters[tgtZone - 1];

        final question = (item['socratic_question'] as String?)?.trim() ?? '';
        if (question.isEmpty) {
          parseFailures++;
          continue;
        }

        final typeStr = item['bridge_type'] as String? ?? '';
        final bridgeType = CrossZoneBridgeType.values
            .where((e) => e.name == typeStr)
            .firstOrNull ?? CrossZoneBridgeType.analogyStructural;

        final confidence =
            (item['confidence'] as num?)?.toDouble() ?? 0.7;

        suggestions.add(CrossZoneBridgeSuggestion(
          id: _generateId(),
          sourceClusterId: srcCluster.id,
          targetClusterId: tgtCluster.id,
          socraticQuestion: question,
          bridgeType: bridgeType,
          confidence: confidence,
        ));
      } catch (e) {
        parseFailures++;
        debugPrint('🌉 [CrossZoneBridge] Item parse error: $e');
      }
    }

    return (suggestions: suggestions, parseFailures: parseFailures);
  }

  /// Extract a JSON array from a possibly-wrapped response.
  ///
  /// Robust to: leading/trailing prose, markdown code fences (```json … ```),
  /// and the AI returning a single object `{…}` instead of an array `[{…}]`
  /// (which it occasionally does when only one suggestion is generated).
  String? _extractJsonArray(String text) {
    final trimmed = text
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    // Preferred path: array literal.
    final start = trimmed.indexOf('[');
    final end = trimmed.lastIndexOf(']');
    if (start >= 0 && end > start) {
      return trimmed.substring(start, end + 1);
    }

    // Fallback: single object — wrap it as a 1-element array.
    final objStart = trimmed.indexOf('{');
    final objEnd = trimmed.lastIndexOf('}');
    if (objStart >= 0 && objEnd > objStart) {
      return '[${trimmed.substring(objStart, objEnd + 1)}]';
    }

    return null;
  }

  /// Decode a JSON array string safely using dart:convert.
  List<dynamic> _decodeJsonArray(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) return decoded;
      return [];
    } catch (_) {
      return [];
    }
  }

  // ===========================================================================
  // UTILITIES
  // ===========================================================================

  static String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = math.Random().nextInt(0xFFFF);
    return 'czb_${now.toRadixString(36)}_${rand.toRadixString(36)}';
  }

  /// Clear all suggestions and reset loading state.
  void clearSuggestions() {
    // Remove ghost connections for pending suggestions
    for (final s in _suggestions.where((s) => !s.dismissed)) {
      final ghost = _flowController.connections
          .where((c) =>
              c.isGhost &&
              c.sourceClusterId == s.sourceClusterId &&
              c.targetClusterId == s.targetClusterId)
          .firstOrNull;
      if (ghost != null) {
        _flowController.removeConnection(ghost.id);
      }
    }
    _suggestions.clear();
    version.value++;
  }

  /// Serialize session data to JSON.
  Map<String, dynamic> toJson() => {
    'stats': stats.toJson(),
    'suggestions': _suggestions
        .map((s) => {
              'id': s.id,
              'sourceClusterId': s.sourceClusterId,
              'targetClusterId': s.targetClusterId,
              'socraticQuestion': s.socraticQuestion,
              'bridgeType': s.bridgeType.name,
              'confidence': s.confidence,
              'dismissed': s.dismissed,
            })
        .toList(),
  };

  void dispose() {
    version.dispose();
  }
}
