// ============================================================================
// 🗺️ GHOST MAP CONTROLLER — Confronto Centauro lifecycle manager
//
// Manages the Ghost Map overlay session:
// - Triggers Atlas AI to generate the ghost map
// - Tracks reveal state for ghost nodes
// - Handles user attempts (Hypercorrection Principle)
// - Provides summary statistics on dismiss
//
// Follows the same ChangeNotifier pattern as ExamSessionController.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../ai/ai_provider.dart';
import '../../ai/atlas_ai_service.dart';
import '../../l10n/fluera_localizations.dart';
import '../../reflow/content_cluster.dart';
import '../../reflow/knowledge_connection.dart';
import 'ghost_map_model.dart';

/// 🗺️ Controller for the Ghost Map / Confronto Centauro feature.
///
/// Lifecycle:
/// 1. [generateGhostMap] — Sends visible clusters to Atlas AI
/// 2. Atlas returns [GhostMapResult] with missing/weak/correct nodes
/// 3. User interacts: taps ghost nodes to attempt, reveals answers
/// 4. [dismiss] — Closes overlay, shows summary
class GhostMapController extends ChangeNotifier {
  final AiProvider _provider;

  /// O-10: Pre-compiled whitespace splitter — avoids RegExp recompilation per attempt.
  static final RegExp _whitespace = RegExp(r'\s+');

  /// L10n instance injected from the widget layer.
  /// Updated via setter in didChangeDependencies.
  FlueraLocalizations? _l10n;
  set l10n(FlueraLocalizations value) => _l10n = value;

  /// Current ghost map result (null = no active session).
  GhostMapResult? _result;
  GhostMapResult? get result => _result;

  /// Test-only: inject a result and activate the overlay.
  @visibleForTesting
  void setResultForTest(GhostMapResult result) {
    _result = result;
    _isActive = true;
    _revealedNodeIds.clear();
    _userAttempts.clear();
    _attemptResults.clear();
    _dismissedNodeIds.clear();
    version.value++;
  }

  /// Whether the ghost map overlay is active.
  bool get isActive => _result != null && _isActive;
  bool _isActive = false;

  /// Whether Atlas is currently generating the ghost map.
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Loading hint for the user.
  String? _loadingHint;
  String? get loadingHint => _loadingHint;

  /// Error message (null = no error).
  String? _error;
  String? get error => _error;

  /// Version counter — incremented on state changes for painter repaint.
  final ValueNotifier<int> version = ValueNotifier(0);

  // ─── Attempt tracking ────────────────────────────────────────────────

  /// Ghost node IDs that have been revealed.
  final Set<String> _revealedNodeIds = {};
  Set<String> get revealedNodeIds => Set.unmodifiable(_revealedNodeIds);

  /// User attempts: ghostNodeId → attempted text.
  final Map<String, String> _userAttempts = {};

  /// Attempt results: ghostNodeId → correct (true/false).
  final Map<String, bool> _attemptResults = {};

  /// Currently active attempt node (user is writing).
  String? _activeAttemptNodeId;
  String? get activeAttemptNodeId => _activeAttemptNodeId;

  /// 🗺️ P4-09: Timestamp when the current attempt started.
  /// Used to enforce the 10s minimum before reveal is allowed.
  DateTime? _attemptStartTime;
  DateTime? get attemptStartTime => _attemptStartTime;

  /// 🗺️ P4-09: Whether the reveal button can be pressed.
  /// Requires at least 10 seconds since attempt started.
  bool get canRevealCurrentAttempt {
    if (_attemptStartTime == null) return false;
    return DateTime.now().difference(_attemptStartTime!).inSeconds >= 10;
  }

  /// 🗺️ P4-09: Seconds remaining before reveal is allowed.
  int get secondsUntilReveal {
    if (_attemptStartTime == null) return 10;
    final elapsed = DateTime.now().difference(_attemptStartTime!).inSeconds;
    return (10 - elapsed).clamp(0, 10);
  }

  /// 🗺️ P4-26: Session start timestamp for growth metrics.
  DateTime? _sessionStartTime;
  DateTime? get sessionStartTime => _sessionStartTime;

  /// 🗺️ Cache key from last successful generation (A3-04).
  /// If the canvas hasn't changed, reuse the previous result.
  String? _lastCacheKey;

  /// Set of individually dismissed ghost node IDs (P4-20).
  final Set<String> _dismissedNodeIds = {};

  /// Fix #11: Guard against double auto-complete dismiss.
  bool _autoCompleteScheduled = false;

  /// 🔒 SEC-05: Rate limiter — timestamp of last API call.
  DateTime? _lastGenerationTime;

  // ─── O-6: Notify batching ─────────────────────────────────────────────
  bool _notifyScheduled = false;

  /// Batch multiple state changes into a single notifyListeners() call.
  /// Coalesces rapid-fire mutations (e.g. submitAttempt → revealNode → checkAutoComplete)
  /// into one rebuild per microtask.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    Future.microtask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  // ─── O-7: Summary cache ───────────────────────────────────────────────
  String? _cachedSummary;

  /// Invalidate cached computations on any state mutation.
  void _invalidateCaches() {
    _cachedSummary = null;
    _visibleMissingIdsCache = null;
    _activeNodesCache = null; // O-11
  }

  // ─── O-3: Visible missing IDs cache ───────────────────────────────────
  Set<String>? _visibleMissingIdsCache;

  /// Pre-computed Set<String> of visible missing node IDs.
  /// Avoids creating a new Set every frame in the painter builder.
  Set<String> get visibleMissingNodeIdsSet {
    return _visibleMissingIdsCache ??=
        visibleMissingNodes.map((n) => n.id).toSet();
  }

  // ─── O-5: Addressed missing count (pre-computed) ──────────────────────

  /// Number of missing nodes that have been addressed (revealed + dismissed).
  /// Avoids creating temporary sets in the progress widget on every rebuild.
  int get addressedMissingCount {
    if (_result == null) return 0;
    return _result!.nodes
        .where((n) => n.isMissing &&
            (_revealedNodeIds.contains(n.id) || _dismissedNodeIds.contains(n.id)))
        .length;
  }

  /// Total number of missing nodes (for progress denominator).
  int get totalMissingNodeCount {
    return _result?.nodes.where((n) => n.isMissing).length ?? 0;
  }

  // ─── P4-31/32: Progressive Chunking ───────────────────────────────────

  /// Maximum number of missing nodes visible at once (P4-31).
  static const int _maxVisibleMissing = 5;

  /// How many chunks of missing nodes have been revealed so far.
  int _revealedChunkCount = 1;

  // ─── P4-14: Navigation by Type ─────────────────────────────────────

  /// Current navigation focus type.
  GhostNodeStatus? _navigationFocusType;
  GhostNodeStatus? get navigationFocusType => _navigationFocusType;

  /// Index within the current navigation type.
  int _navigationIndex = 0;
  int get navigationIndex => _navigationIndex;

  // ─── Statistics ──────────────────────────────────────────────────────

  int get totalMissing => _result?.totalMissing ?? 0;
  int get totalWeak => _result?.totalWeak ?? 0;
  int get totalCorrect => _result?.totalCorrect ?? 0;
  int get totalHypercorrection => _result?.totalHypercorrection ?? 0;
  int get attemptedCount => _userAttempts.length;
  int get correctAttempts =>
      _attemptResults.values.where((v) => v).length;

  GhostMapController({required AiProvider provider}) : _provider = provider;

  // ─────────────────────────────────────────────────────────────────────────
  // Generation
  // ─────────────────────────────────────────────────────────────────────────

  /// Generate a Ghost Map from the visible clusters on the canvas.
  ///
  /// [clusterTexts] — clusterId → OCR recognized text.
  /// [clusterTitles] — clusterId → AI-generated semantic title.
  /// [clusters] — content clusters for position/size data.
  /// [existingConnections] — current knowledge graph connections.
  /// [socraticContext] — Passo 3 data per cluster (confidence, hypercorrection, ZPD).
  Future<void> generateGhostMap({
    required Map<String, String> clusterTexts,
    Map<String, String> clusterTitles = const {},
    required List<ContentCluster> clusters,
    List<KnowledgeConnection> existingConnections = const [],
    Map<String, Map<String, dynamic>> socraticContext = const {},
  }) async {
    if (_isLoading) return;

    // 🔒 SEC-05: Rate limit — 30s cooldown between API calls
    if (_lastGenerationTime != null) {
      final elapsed = DateTime.now().difference(_lastGenerationTime!);
      if (elapsed.inSeconds < 30) {
        debugPrint('🗺️ SEC: Rate limited (${elapsed.inSeconds}s < 30s cooldown)');
        _error = _l10n?.ghostMap_rateLimitWait(30 - elapsed.inSeconds)
            ?? 'Attendi ${30 - elapsed.inSeconds}s prima di rigenerare.';
        notifyListeners();
        return;
      }
    }

    // 🗺️ A3-04: Cache check — if canvas hasn't changed, reactivate previous result.
    final cacheKey = _computeCacheKey(clusterTexts);
    if (cacheKey == _lastCacheKey && _result != null && _result!.nodes.isNotEmpty) {
      _isActive = true;
      _dismissedNodeIds.clear();
      version.value++;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    _loadingHint = _l10n?.ghostMap_loadingAnalyzing
        ?? '🌌 Atlas sta analizzando i tuoi appunti...';
    notifyListeners();

    try {
      if (!_provider.isInitialized) await _provider.initialize();

      // Build position and size maps from clusters
      final clusterPositions = <String, Map<String, double>>{};
      final clusterSizes = <String, Map<String, double>>{};
      for (final cluster in clusters) {
        clusterPositions[cluster.id] = {
          'x': cluster.centroid.dx,
          'y': cluster.centroid.dy,
        };
        clusterSizes[cluster.id] = {
          'w': cluster.bounds.width,
          'h': cluster.bounds.height,
        };
      }

      // Build connection tuples for AI context
      final connMaps = existingConnections.map((c) => <String, String>{
            'source': c.sourceClusterId,
            'target': c.targetClusterId,
            'label': c.label ?? '',
          }).toList();

      final gemini = _provider as GeminiProvider;

      // 🗺️ Retry once on transient failures (network, 503, rate-limit)
      GhostMapResult? apiResult;
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          // O-13: 30s timeout prevents infinite loading if API hangs.
          apiResult = await gemini.generateGhostMap(
            clusterTexts: clusterTexts,
            clusterTitles: clusterTitles,
            clusterPositions: clusterPositions,
            clusterSizes: clusterSizes,
            existingConnections: connMaps,
            socraticContext: socraticContext,
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException(
              'Ghost Map generation timed out after 30s',
            ),
          );
          break; // Success — exit retry loop
        } catch (e) {
          if (attempt == 0) {
            debugPrint('🗺️ Ghost Map attempt 1 failed, retrying in 2s: $e');
            _loadingHint = _l10n?.ghostMap_retryHint ?? '🔄 Riprovo...';
            notifyListeners();
            await Future.delayed(const Duration(seconds: 2));
          } else {
            rethrow; // Second failure — propagate to outer catch
          }
        }
      }
      _result = apiResult;

      if (_result == null || _result!.nodes.isEmpty) {
        _error = _l10n?.ghostMap_emptyResultError
            ?? 'Non ho trovato abbastanza contenuto per la Ghost Map.';
        _result = null;
      } else {
        _isActive = true;
        _lastCacheKey = cacheKey;
        _lastGenerationTime = DateTime.now(); // 🔒 SEC-05
        _sessionStartTime = DateTime.now(); // P4-26: start session timer
        _revealedNodeIds.clear();
        _userAttempts.clear();
        _attemptResults.clear();
        _activeAttemptNodeId = null;
        _attemptStartTime = null; // P4-09: reset
        _dismissedNodeIds.clear();
        _revealedChunkCount = 1; // P4-31: start with first chunk
        _navigationFocusType = null;
        _navigationIndex = 0;
        _invalidateCaches();
      }
    } catch (e) {
      final msg = e.toString().length > 100 ? '${e.toString().substring(0, 100)}...' : e.toString();
      _error = _l10n?.ghostMap_errorGeneric(msg) ?? 'Errore: $msg';
      _result = null;
    } finally {
      _isLoading = false;
      _loadingHint = null;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Interaction
  // ─────────────────────────────────────────────────────────────────────────

  /// Hit-test: find a ghost node at the given canvas position.
  ///
  /// Returns the ghost node if found, null otherwise.
  GhostNode? hitTestGhostNode(Offset canvasPosition) {
    if (_result == null) return null;

    for (final node in _result!.nodes) {
      // Skip dismissed nodes (P4-20)
      if (_dismissedNodeIds.contains(node.id)) continue;
      if (node.isRevealed && !node.isMissing) continue; // Skip already-shown correct/weak

      final bounds = node.bounds.inflate(12.0);
      if (bounds.contains(canvasPosition)) {
        return node;
      }
    }
    return null;
  }

  /// Start an attempt on a missing ghost node.
  ///
  /// The student will write their attempt, then reveal Atlas's answer.
  void startAttempt(String ghostNodeId) {
    _activeAttemptNodeId = ghostNodeId;
    _attemptStartTime = DateTime.now(); // P4-09: start timer
    _scheduleNotify();
  }

  /// Cancel the current attempt.
  void cancelAttempt() {
    _activeAttemptNodeId = null;
    _attemptStartTime = null; // P4-09: reset timer
    _scheduleNotify();
  }

  /// Submit a user attempt for a ghost node.
  ///
  /// Records the attempt text and marks the node as revealed.
  /// The comparison overlay will show user text vs Atlas text.
  void submitAttempt(String ghostNodeId, String userText) {
    _userAttempts[ghostNodeId] = userText;
    _activeAttemptNodeId = null;

    // Reveal the node
    _revealNode(ghostNodeId);

    // Simple heuristic: if 30%+ of Atlas concept words appear in user text, mark correct.
    final node = _result?.nodes.where((n) => n.id == ghostNodeId).firstOrNull;
    if (node != null) {
      final conceptWords = node.concept
          .toLowerCase()
          .split(_whitespace) // O-10: static RegExp
          .where((w) => w.length > 3)
          .toSet();
      final userWords = userText
          .toLowerCase()
          .split(_whitespace) // O-10: static RegExp
          .where((w) => w.length > 3)
          .toSet();

      if (conceptWords.isNotEmpty) {
        final overlap = conceptWords.intersection(userWords).length;
        final ratio = overlap / conceptWords.length;
        _attemptResults[ghostNodeId] = ratio >= 0.3;
        node.attemptCorrect = ratio >= 0.3;
      } else {
        _attemptResults[ghostNodeId] = userText.trim().isNotEmpty;
        node.attemptCorrect = userText.trim().isNotEmpty;
      }
      node.userAttempt = userText;
    }

    _invalidateCaches();
    version.value++;
    _scheduleNotify();
    _checkAutoComplete();
  }

  /// Fix #13: Allow student to override the automatic attempt result
  /// with their own metacognitive judgment (self-evaluation).
  void overrideAttemptResult(String ghostNodeId, bool isCorrect) {
    _attemptResults[ghostNodeId] = isCorrect;
    final node = _result?.nodes.where((n) => n.id == ghostNodeId).firstOrNull;
    if (node != null) {
      node.attemptCorrect = isCorrect;
    }
    _invalidateCaches();
    version.value++;
    _scheduleNotify();
  }

  /// Reveal a ghost node without an attempt (skip / tap to reveal).
  void revealNode(String ghostNodeId) {
    _revealNode(ghostNodeId);
    _invalidateCaches();
    version.value++;
    _scheduleNotify();
    _checkAutoComplete();
  }

  void _revealNode(String ghostNodeId) {
    _revealedNodeIds.add(ghostNodeId);
    final node = _result?.nodes.where((n) => n.id == ghostNodeId).firstOrNull;
    if (node != null) {
      node.isRevealed = true;
    }
  }

  /// Whether all missing ghost nodes have been revealed.
  bool get allMissingRevealed {
    if (_result == null) return false;
    return _result!.nodes
        .where((n) => n.isMissing)
        .every((n) => n.isRevealed);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Summary & Dismiss
  // ─────────────────────────────────────────────────────────────────────────

  /// Get a summary string for the toast on dismiss.
  ///
  /// 🗺️ P4-27: Includes growth percentage and motivational framing.
  // O-7: Cached summaryText — invalidated on every state mutation.
  String get summaryText => _cachedSummary ??= _computeSummary();

  String _computeSummary() {
    if (_result == null) return '';
    final missing = totalMissing;
    final weak = totalWeak;
    final correct = totalCorrect;
    final attempted = attemptedCount;
    final correctAtt = correctAttempts;
    final filled = addressedMissingCount; // O-5: reuse pre-computed

    final parts = <String>[];
    final l = _l10n;
    if (l != null) {
      if (correct > 0) parts.add(l.ghostMap_summaryCorrect(correct));
      if (weak > 0) parts.add(l.ghostMap_summaryWeak(weak));
      if (missing > 0) parts.add(l.ghostMap_summaryMissing(missing));
      if (attempted > 0) parts.add(l.ghostMap_summaryAttempts(correctAtt, attempted));
      if (filled > 0 && missing > 0) {
        final growth = (filled / missing * 100).round();
        parts.add(l.ghostMap_summaryGrowth(growth));
      }
    } else {
      if (correct > 0) parts.add('✅ $correct corretti');
      if (weak > 0) parts.add('⚠️ $weak da migliorare');
      if (missing > 0) parts.add('❓ $missing mancanti');
      if (attempted > 0) parts.add('🎯 $correctAtt/$attempted tentativi riusciti');
      if (filled > 0 && missing > 0) {
        final growth = (filled / missing * 100).round();
        parts.add('📈 $growth% lacune colmate');
      }
    }

    return parts.join(' · ');
  }

  /// 🗺️ P4-29/30: Edge case message for nearly-perfect canvas.
  String? get edgeCaseMessage {
    if (_result == null) return null;
    final missingCount = totalMissing;
    final weakCount = totalWeak;
    final actionable = missingCount + weakCount;

    if (actionable <= 2) {
      // P4-29: Canvas almost perfect
      return _l10n?.ghostMap_edgeCaseNearlyPerfect
          ?? '🌟 Il tuo canvas è quasi completo! Solo qualche dettaglio da aggiungere.';
    } else if (missingCount > 15) {
      // P4-33: Canvas very incomplete (tone: gentle, not intimidating)
      return _l10n?.ghostMap_edgeCaseVeryIncomplete
          ?? '📖 Ho trovato diverse aree da esplorare. Iniziamo dalle basi.';
    }
    return null;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Reactivation & Per-Node Dismiss
  // ───────────────────────────────────────────────────────────────────────────

  /// 🗺️ P4-28: Reactivate the previous Ghost Map overlay without re-calling the API.
  ///
  /// Returns `true` if a previous result was available and reactivated.
  bool reactivate() {
    if (_result == null || _result!.nodes.isEmpty) return false;
    _isActive = true;
    version.value++;
    notifyListeners();
    return true;
  }

  /// Whether a previous result exists that can be reactivated.
  bool get canReactivate => _result != null && _result!.nodes.isNotEmpty && !_isActive;

  /// 🗺️ P4-20: Dismiss a single ghost node (student considers it irrelevant).
  void dismissNode(String ghostNodeId) {
    _dismissedNodeIds.add(ghostNodeId);
    _invalidateCaches();
    HapticFeedback.lightImpact();
    version.value++;
    _scheduleNotify();
    _checkAutoComplete();
  }

  /// Whether a specific ghost node has been dismissed.
  bool isNodeDismissed(String ghostNodeId) => _dismissedNodeIds.contains(ghostNodeId);

  /// Fix #14: Undo-dismiss a ghost node (re-add it to the overlay).
  void undismissNode(String ghostNodeId) {
    if (_dismissedNodeIds.remove(ghostNodeId)) {
      _invalidateCaches();
      version.value++;
      _scheduleNotify();
    }
  }

  /// The set of dismissed ghost node IDs (read-only view for the painter).
  // Fix #15: Return unmodifiable set to prevent external mutation.
  Set<String> get dismissedNodeIds => Set.unmodifiable(_dismissedNodeIds);

  // ─── O-11: Cached active nodes list ────────────────────────────────────
  List<GhostNode>? _activeNodesCache;

  /// Active ghost nodes (excluding dismissed ones).
  /// O-11: Cached — avoids re-filtering on every navigation/label call.
  List<GhostNode> get activeNodes =>
      _activeNodesCache ??=
          _result?.nodes.where((n) => !_dismissedNodeIds.contains(n.id)).toList() ?? [];

  // ───────────────────────────────────────────────────────────────────────────
  // P4-31/32: Progressive Chunking
  // ───────────────────────────────────────────────────────────────────────────

  /// 🗺️ P4-31: Missing nodes visible in the current chunk.
  /// If total missing > 5, only the first chunk of 5 is shown.
  /// After the student resolves those, the next 5 are revealed.
  List<GhostNode> get visibleMissingNodes {
    if (_result == null) return [];
    final allMissing = _result!.nodes
        .where((n) => n.isMissing && !_dismissedNodeIds.contains(n.id))
        .toList();

    // Sort: hypercorrection nodes first (P4-21), then by position
    allMissing.sort((a, b) {
      if (a.isHypercorrection && !b.isHypercorrection) return -1;
      if (!a.isHypercorrection && b.isHypercorrection) return 1;
      // Below-ZPD nodes last (P4-22)
      if (a.isBelowZPD && !b.isBelowZPD) return 1;
      if (!a.isBelowZPD && b.isBelowZPD) return -1;
      return 0;
    });

    if (allMissing.length <= _maxVisibleMissing) return allMissing;
    final maxVisible = _revealedChunkCount * _maxVisibleMissing;
    return allMissing.take(maxVisible.clamp(0, allMissing.length)).toList();
  }

  /// 🗺️ P4-32: Check if more chunks are available to reveal.
  bool get hasMoreChunks {
    if (_result == null) return false;
    final allMissing = _result!.nodes
        .where((n) => n.isMissing && !_dismissedNodeIds.contains(n.id))
        .length;
    return allMissing > _revealedChunkCount * _maxVisibleMissing;
  }

  /// 🗺️ P4-32: Reveal the next chunk of missing nodes.
  void revealNextChunk() {
    _revealedChunkCount++;
    _invalidateCaches();
    version.value++;
    _scheduleNotify();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // P4-14: Navigation by Type
  // ───────────────────────────────────────────────────────────────────────────

  /// 🗺️ P4-14: Navigate to the next ghost node of a specific type.
  /// Order: missing (red) → wrongConnection (yellow) → weak (yellow) → connections (blue).
  /// Returns the node to focus on, or null if none left.
  GhostNode? navigateNext({GhostNodeStatus? type}) {
    if (_result == null) return null;

    // Default navigation order: missing → wrongConnection → weak
    final targetType = type ?? _navigationFocusType ?? GhostNodeStatus.missing;
    _navigationFocusType = targetType;

    final candidates = activeNodes
        .where((n) => n.status == targetType && !n.isRevealed)
        .toList();

    if (candidates.isEmpty) {
      // Try next type in sequence
      final typeOrder = [
        GhostNodeStatus.missing,
        GhostNodeStatus.wrongConnection,
        GhostNodeStatus.weak,
      ];
      final currentIdx = typeOrder.indexOf(targetType);
      for (int i = currentIdx + 1; i < typeOrder.length; i++) {
        final nextCandidates = activeNodes
            .where((n) => n.status == typeOrder[i] && !n.isRevealed)
            .toList();
        if (nextCandidates.isNotEmpty) {
          _navigationFocusType = typeOrder[i];
          _navigationIndex = 0;
          _scheduleNotify();
          return nextCandidates.first;
        }
      }
      return null; // All done
    }

    _navigationIndex = (_navigationIndex + 1) % candidates.length;
    _scheduleNotify();
    return candidates[_navigationIndex.clamp(0, candidates.length - 1)];
  }

  /// 🗺️ Navigate to the previous node of the current type.
  GhostNode? navigatePrevious() {
    if (_result == null || _navigationFocusType == null) return null;

    final candidates = activeNodes
        .where((n) => n.status == _navigationFocusType! && !n.isRevealed)
        .toList();

    if (candidates.isEmpty) return null;

    _navigationIndex = (_navigationIndex - 1) % candidates.length;
    if (_navigationIndex < 0) _navigationIndex = candidates.length - 1;
    _scheduleNotify();
    return candidates[_navigationIndex.clamp(0, candidates.length - 1)];
  }

  /// Label for the current navigation state.
  String get navigationLabel {
    if (_result == null || _navigationFocusType == null) return '';
    final candidates = activeNodes
        .where((n) => n.status == _navigationFocusType!)
        .toList();
    if (candidates.isEmpty) return '';
    final typeEmoji = switch (_navigationFocusType!) {
      GhostNodeStatus.missing => '🔴',
      GhostNodeStatus.wrongConnection => '🟡',
      GhostNodeStatus.weak => '🟡',
      GhostNodeStatus.correct => '🟢',
    };
    return '$typeEmoji ${_navigationIndex + 1}/${candidates.length}';
  }

  /// Dismiss the ghost map overlay and clear state.
  void dismiss() {
    _isActive = false;
    _activeAttemptNodeId = null;
    _autoCompleteScheduled = false; // Fix #11: reset guard
    version.value++;
    notifyListeners();
  }

  /// Fully clear the ghost map (including results and cache).
  void clear() {
    _result = null;
    _isActive = false;
    _revealedNodeIds.clear();
    _userAttempts.clear();
    _attemptResults.clear();
    _activeAttemptNodeId = null;
    _error = null;
    _lastCacheKey = null;
    _dismissedNodeIds.clear();
    _revealedChunkCount = 1;
    _navigationFocusType = null;
    _navigationIndex = 0;
    _autoCompleteScheduled = false; // Fix #11: reset guard
    _invalidateCaches();
    version.value++;
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Cache Key
  // ───────────────────────────────────────────────────────────────────────────

  /// Compute a lightweight cache key from cluster texts.
  /// Only the sorted concatenation of cluster content matters —
  /// if the student hasn't modified their notes, we reuse the result.
  String _computeCacheKey(Map<String, String> clusterTexts) {
    final sorted = clusterTexts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final buffer = StringBuffer();
    for (final e in sorted) {
      buffer.write(e.key);
      buffer.write(':');
      buffer.write(e.value.hashCode);
      buffer.write(';');
    }
    return buffer.toString();
  }

  /// Whether all actionable ghost nodes have been resolved.
  ///
  /// A node is "resolved" if:
  /// - Missing → revealed or dismissed
  /// - Weak → dismissed (or tapped for explanation)
  /// Correct nodes don't count (they're informational).
  bool get allResolved {
    if (_result == null) return false;
    return _result!.nodes.every((n) {
      if (n.isCorrect) return true; // Correct nodes are always resolved
      if (_dismissedNodeIds.contains(n.id)) return true;
      if (n.isMissing && n.isRevealed) return true;
      return false;
    });
  }

  /// 🗺️ Auto-complete: if all actionable nodes are resolved, auto-dismiss
  /// the overlay after a short delay to let the student see the final state.
  void _checkAutoComplete() {
    if (!_isActive || !allResolved) return;
    if (_autoCompleteScheduled) return; // Fix #11: prevent double-schedule
    _autoCompleteScheduled = true;
    // Delay to let the student see the final state
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!_isActive || !allResolved) return; // Re-check after delay
      _autoCompleteScheduled = false;
      HapticFeedback.mediumImpact();
      dismiss();
    });
  }

  @override
  void dispose() {
    version.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // P4-39: Passo 4 Dataset Export
  // ───────────────────────────────────────────────────────────────────────────

  /// 🗺️ P4-39: Export the complete Passo 4 session as structured JSON.
  ///
  /// This dataset is used for:
  /// - FSRS spaced repetition scheduling (which concepts to review)
  /// - Long-term progress tracking (canvasGrowth over sessions)
  /// - Analytics (hypercorrection rate, ZPD distribution)
  Map<String, dynamic> toDatasetJson() {
    if (_result == null) return {};

    final nodes = _result!.nodes;
    final missing = nodes.where((n) => n.isMissing).toList();
    final weak = nodes.where((n) => n.isWeak || n.isWrongConnection).toList();
    final correct = nodes.where((n) => n.isCorrect).toList();

    // Compute growth metrics
    final totalActionable = missing.length + weak.length;
    final resolved = missing.where((n) => n.isRevealed || _dismissedNodeIds.contains(n.id)).length
        + weak.where((n) => _dismissedNodeIds.contains(n.id)).length;
    final growthPercent = totalActionable > 0
        ? ((resolved / totalActionable) * 100).round()
        : 100;

    return {
      'sessionId': 'ghost_${_sessionStartTime?.millisecondsSinceEpoch ?? 0}',
      'timestamp': DateTime.now().toIso8601String(),
      'sessionStarted': _sessionStartTime?.toIso8601String(),
      'sessionDuration': _sessionStartTime != null
          ? DateTime.now().difference(_sessionStartTime!).inSeconds
          : null,

      // Summary metrics
      'canvasGrowth': growthPercent,
      'totalNodes': nodes.length,
      'totalMissing': missing.length,
      'totalWeak': weak.length,
      'totalCorrect': correct.length,
      'totalHypercorrection': nodes.where((n) => n.isHypercorrection).length,
      'totalBelowZPD': nodes.where((n) => n.isBelowZPD).length,

      // Attempt tracking
      'attemptsCount': _userAttempts.length,
      'correctAttempts': _attemptResults.values.where((v) => v).length,
      'incorrectAttempts': _attemptResults.values.where((v) => !v).length,
      'dismissedCount': _dismissedNodeIds.length,

      // Per-node details
      'nodes': nodes.map((n) => {
        'id': n.id,
        'concept': n.isRevealed || n.isCorrect ? n.concept : null,
        'status': n.status.name,
        'relatedClusterId': n.relatedClusterId,
        'isHypercorrection': n.isHypercorrection,
        'isBelowZPD': n.isBelowZPD,
        'confidenceLevel': n.confidenceLevel,
        'isRevealed': n.isRevealed,
        'userAttempt': _userAttempts[n.id],
        'attemptCorrect': _attemptResults[n.id],
        'inputMode': n.inputMode, // Fix #8: pen or text
        'isDismissed': _dismissedNodeIds.contains(n.id),
      }).toList(),

      // Connection analysis
      'totalCrossDomain': _result!.connections.where((c) => c.isCrossDomain).length,
      'connections': _result!.connections.map((c) => {
        'id': c.id,
        'sourceId': c.sourceId,
        'targetId': c.targetId,
        'label': c.label,
        'isCrossDomain': c.isCrossDomain,
      }).toList(),
    };
  }
}
