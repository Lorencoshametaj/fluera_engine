import 'dart:async';
import 'package:flutter/foundation.dart';
import '../reflow/knowledge_connection.dart';
import '../reflow/content_cluster.dart';
import '../reflow/knowledge_flow_controller.dart';
import '../reflow/connection_suggestion_engine.dart';
import '../drawing/models/pro_drawing_point.dart';

/// 👻 GHOST CONNECTION WATCHER — Anticipatory Intelligence Engine.
///
/// Background service that monitors canvas activity and transcription
/// to discover semantic relationships between clusters *before* the user
/// explicitly creates connections.
///
/// ARCHITECTURE:
///
/// Two trigger modes:
///
/// 1. **LIVE (Feature 2)**: While audio is being recorded/transcribed,
///    compares new keywords in real-time against all existing clusters.
///    Triggered by [onTranscriptionUpdate].
///
/// 2. **IDLE (Feature II-2, Auto-Tessitura)**: Periodic background scan
///    when the user pauses writing. Triggered by [_idleScanTimer].
///
/// Both modes produce ghost connections via [KnowledgeFlowController.addConnection]
/// with `isGhost: true`. Ghost connections render as dashed pulsating lines
/// and can be materialized (accepted) or dismissed by the user.
///
/// GHOST LIFECYCLE:
///   1. Watcher discovers high-scoring pair → ghost connection created
///   2. Ghost connection rendered with pulsating dashed line + glow
///   3. User taps/swipes → [materializeGhost] promotes to solid connection
///   4. User dismisses → [dismissGhost] removes and remembers pair
///   5. If no interaction after [ghostLifetimeMs] → ghost fades out
///
/// CONSTRAINTS:
///   - Max [maxActiveGhosts] ghost connections at any time
///   - Minimum [ghostCooldownMs] between creating ghosts (prevent spam)
///   - Dismissed pairs are remembered for the session (no re-suggestion)
///   - Ghost score threshold is higher than basic suggestions (0.55 vs 0.42)
class GhostConnectionWatcher {
  /// The knowledge flow controller (for creating/managing ghost connections).
  final KnowledgeFlowController _flowController;

  /// The suggestion engine (for scoring cluster pairs).
  final ConnectionSuggestionEngine _suggestionEngine;

  // ===========================================================================
  // CONFIGURATION
  // ===========================================================================

  /// Maximum ghost connections visible at any time.
  static const int maxActiveGhosts = 3;

  /// Minimum score threshold for a ghost connection (higher than normal suggestions).
  static const double ghostScoreThreshold = 0.55;

  /// Minimum ms between creating new ghost connections (anti-spam).
  static const int ghostCooldownMs = 5000;

  /// Lifetime (ms) of a ghost connection before it auto-dismisses.
  static const int ghostLifetimeMs = 30000;

  /// Idle scan interval (ms) — how often to scan when user is idle.
  static const int idleScanIntervalMs = 30000;

  /// Time (ms) of no input before considered "idle".
  static const int idleThresholdMs = 10000;

  // ===========================================================================
  // STATE
  // ===========================================================================

  /// Whether the watcher is active and monitoring.
  bool _isActive = false;
  bool get isActive => _isActive;

  /// Dismissed ghost pair keys (no re-suggestion within session).
  final Set<String> _dismissedGhostPairs = {};

  /// Last time a ghost connection was created (for cooldown).
  int _lastGhostCreatedMs = 0;

  /// Last time the user interacted with the canvas (for idle detection).
  int _lastUserActivityMs = 0;

  /// Timer for periodic idle scanning.
  Timer? _idleScanTimer;

  /// Timer for ghost lifetime auto-dismiss.
  Timer? _ghostLifetimeTimer;

  /// Currently cached cluster/stroke data for scoring.
  List<ContentCluster> _cachedClusters = [];
  List<ProStroke> _cachedStrokes = [];
  Map<String, String> _cachedClusterTexts = {};

  /// Callback invoked when ghost connections change (for painter repaint).
  VoidCallback? onGhostConnectionsChanged;

  GhostConnectionWatcher({
    required KnowledgeFlowController flowController,
    ConnectionSuggestionEngine? suggestionEngine,
  }) : _flowController = flowController,
       _suggestionEngine = suggestionEngine ?? ConnectionSuggestionEngine();

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  /// Start the ghost connection watcher.
  ///
  /// Call when the canvas is loaded and has clusters to analyze.
  void start() {
    if (_isActive) return;
    _isActive = true;
    _lastUserActivityMs = DateTime.now().millisecondsSinceEpoch;

    // Start idle scan timer
    _idleScanTimer?.cancel();
    _idleScanTimer = Timer.periodic(
      const Duration(milliseconds: idleScanIntervalMs),
      (_) => _onIdleScanTick(),
    );

    // Start ghost lifetime checker
    _ghostLifetimeTimer?.cancel();
    _ghostLifetimeTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _cleanExpiredGhosts(),
    );

    debugPrint('👻 [GhostWatcher] Started');
  }

  /// Stop the watcher and clean up.
  void stop() {
    _isActive = false;
    _idleScanTimer?.cancel();
    _idleScanTimer = null;
    _ghostLifetimeTimer?.cancel();
    _ghostLifetimeTimer = null;
    debugPrint('👻 [GhostWatcher] Stopped');
  }

  /// Update cached canvas data. Call whenever clusters or strokes change.
  void updateCanvasData({
    required List<ContentCluster> clusters,
    required List<ProStroke> allStrokes,
    Map<String, String>? clusterTexts,
  }) {
    _cachedClusters = clusters;
    _cachedStrokes = allStrokes;
    _cachedClusterTexts = clusterTexts ?? {};
  }

  /// Notify the watcher that the user is active (resets idle timer).
  void notifyUserActivity() {
    _lastUserActivityMs = DateTime.now().millisecondsSinceEpoch;
  }

  // ===========================================================================
  // 🎤 LIVE MODE — Real-time transcription trigger
  // ===========================================================================

  /// Called when new transcription text becomes available during recording.
  ///
  /// [newText] — the latest transcribed text segment.
  /// [activeClusterId] — the cluster the user is currently writing in.
  ///
  /// This is the "Feature 2" trigger: AI hears the professor say something
  /// that matches an older cluster → ghost connection appears.
  void onTranscriptionUpdate({
    required String newText,
    required String activeClusterId,
  }) {
    if (!_isActive) return;
    if (newText.trim().isEmpty) return;

    // Cooldown check
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastGhostCreatedMs < ghostCooldownMs) return;

    // Check if we already have max ghosts
    if (_activeGhostCount >= maxActiveGhosts) return;

    // Update cluster texts with new transcription for the active cluster
    final updatedTexts = Map<String, String>.from(_cachedClusterTexts);
    final existing = updatedTexts[activeClusterId] ?? '';
    updatedTexts[activeClusterId] = '$existing $newText'.trim();

    // Score all pairs involving the active cluster
    _findAndCreateGhosts(
      focusClusterId: activeClusterId,
      clusterTexts: updatedTexts,
    );
  }

  // ===========================================================================
  // 🕐 IDLE MODE — Periodic background scan (Auto-Tessitura)
  // ===========================================================================

  /// Periodic idle scan callback.
  void _onIdleScanTick() {
    if (!_isActive) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final idleDuration = now - _lastUserActivityMs;

    // Only scan when user has been idle long enough
    if (idleDuration < idleThresholdMs) return;

    // Cooldown check
    if (now - _lastGhostCreatedMs < ghostCooldownMs) return;

    // Check if we already have max ghosts
    if (_activeGhostCount >= maxActiveGhosts) return;

    debugPrint('👻 [GhostWatcher] Idle scan triggered '
        '(idle ${idleDuration}ms)');

    // Scan all pairs (no focus cluster — full canvas scan)
    _findAndCreateGhosts(clusterTexts: _cachedClusterTexts);
  }

  // ===========================================================================
  // GHOST CREATION
  // ===========================================================================

  /// Find high-scoring pairs and create ghost connections.
  ///
  /// [focusClusterId] — if provided, only consider pairs involving this cluster.
  /// [clusterTexts] — recognized text per cluster for semantic scoring.
  void _findAndCreateGhosts({
    String? focusClusterId,
    required Map<String, String> clusterTexts,
  }) {
    if (_cachedClusters.length < 2) return;

    // Use the suggestion engine with a higher threshold for ghosts
    final suggestions = _suggestionEngine.computeSuggestions(
      clusters: _cachedClusters,
      allStrokes: _cachedStrokes,
      existingConnections: _flowController.connections,
      clusterTexts: clusterTexts,
      threshold: ghostScoreThreshold,
      maxSuggestions: maxActiveGhosts,
    );

    for (final suggestion in suggestions) {
      // Skip if we're focus-scanning and this pair doesn't involve focus cluster
      if (focusClusterId != null &&
          suggestion.sourceClusterId != focusClusterId &&
          suggestion.targetClusterId != focusClusterId) {
        continue;
      }

      // Skip dismissed pairs
      if (_dismissedGhostPairs.contains(suggestion.pairKey)) continue;

      // Skip if ghost already exists for this pair
      if (_hasGhostForPair(
        suggestion.sourceClusterId,
        suggestion.targetClusterId,
      )) continue;

      // Check max limit
      if (_activeGhostCount >= maxActiveGhosts) break;

      // Create ghost connection!
      final ghost = _flowController.addConnection(
        sourceClusterId: suggestion.sourceClusterId,
        targetClusterId: suggestion.targetClusterId,
        label: suggestion.sharedKeywords.isNotEmpty
            ? suggestion.sharedKeywords.take(2).join(', ')
            : suggestion.reason,
        isGhost: true,
      );

      if (ghost != null) {
        _lastGhostCreatedMs = DateTime.now().millisecondsSinceEpoch;
        onGhostConnectionsChanged?.call();
        debugPrint('👻 [GhostWatcher] Created ghost: '
            '${suggestion.sourceClusterId} → ${suggestion.targetClusterId} '
            '(score: ${suggestion.score.toStringAsFixed(2)}, '
            'reason: ${suggestion.reason})');
      }
    }
  }

  // ===========================================================================
  // GHOST MANAGEMENT
  // ===========================================================================

  /// Materialize a ghost connection into a solid (user-confirmed) connection.
  ///
  /// Returns true if the ghost was found and materialized.
  bool materializeGhost(String connectionId) {
    final conn = _flowController.connections
        .where((c) => c.id == connectionId && c.isGhost)
        .firstOrNull;

    if (conn == null) return false;

    conn.materialize();

    // Reinforce the learning signal
    _suggestionEngine.reinforceAccept(
      conn.label ?? 'Related content',
    );

    onGhostConnectionsChanged?.call();
    debugPrint('👻 [GhostWatcher] Materialized ghost ${conn.id}');
    return true;
  }

  /// Dismiss a ghost connection (removes it and remembers the pair).
  ///
  /// Returns true if the ghost was found and dismissed.
  bool dismissGhost(String connectionId) {
    final conn = _flowController.connections
        .where((c) => c.id == connectionId && c.isGhost)
        .firstOrNull;

    if (conn == null) return false;

    // Remember this pair to avoid re-suggesting
    final pairKey = _makePairKey(conn.sourceClusterId, conn.targetClusterId);
    _dismissedGhostPairs.add(pairKey);

    // Penalize the learning signal
    _suggestionEngine.reinforceDismiss(
      conn.label ?? 'Related content',
    );

    // Remove the ghost connection
    _flowController.removeConnection(connectionId);

    onGhostConnectionsChanged?.call();
    debugPrint('👻 [GhostWatcher] Dismissed ghost ${conn.id}');
    return true;
  }

  // ===========================================================================
  // GHOST LIFETIME
  // ===========================================================================

  /// Remove ghost connections that have exceeded their lifetime.
  void _cleanExpiredGhosts() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expired = <String>[];

    for (final conn in _flowController.connections) {
      if (!conn.isGhost) continue;
      if (now - conn.createdAtMs > ghostLifetimeMs) {
        expired.add(conn.id);
      }
    }

    for (final id in expired) {
      _flowController.removeConnection(id);
      debugPrint('👻 [GhostWatcher] Expired ghost $id');
    }

    if (expired.isNotEmpty) {
      onGhostConnectionsChanged?.call();
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  /// Count of currently active ghost connections.
  int get _activeGhostCount =>
      _flowController.connections.where((c) => c.isGhost).length;

  /// Check if a ghost connection already exists for a cluster pair.
  bool _hasGhostForPair(String clusterA, String clusterB) {
    return _flowController.connections.any(
      (c) => c.isGhost &&
          ((c.sourceClusterId == clusterA && c.targetClusterId == clusterB) ||
           (c.sourceClusterId == clusterB && c.targetClusterId == clusterA)),
    );
  }

  /// Create an order-independent pair key.
  String _makePairKey(String a, String b) {
    return a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
  }

  // ===========================================================================
  // CLEANUP
  // ===========================================================================

  /// Dispose all resources.
  void dispose() {
    stop();
    _dismissedGhostPairs.clear();
  }
}
