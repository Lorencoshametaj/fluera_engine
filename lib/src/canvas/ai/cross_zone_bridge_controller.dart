import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../../ai/ai_provider.dart';
import '../../reflow/knowledge_connection.dart';
import '../../reflow/knowledge_flow_controller.dart';
import '../../reflow/content_cluster.dart';

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
  }) : _flowController = flowController;

  // ===========================================================================
  // BRIDGE QUERY & RETRIEVAL
  // ===========================================================================

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
  /// [clusterTexts] — clusterId → OCR recognized text.
  /// [clusterTitles] — clusterId → AI-generated semantic title.
  ///
  /// Returns the number of suggestions generated.
  /// The suggestions appear as ghost dashed golden lines.
  Future<int> requestBridgeSuggestions({
    required AiProvider aiProvider,
    required List<ContentCluster> clusters,
    required Map<String, String> clusterTexts,
    Map<String, String> clusterTitles = const {},
  }) async {
    if (_isLoading) return 0;
    if (!aiProvider.isInitialized) return 0;

    // Need at least 2 zones (P9 gate: ≥2 zones with ≥10 nodes)
    if (clusters.length < 2) return 0;

    _isLoading = true;
    version.value++;

    try {
      // Build prompt with zone data
      final prompt = _buildBridgePrompt(
        clusters: clusters,
        clusterTexts: clusterTexts,
        clusterTitles: clusterTitles,
      );

      // Query AI
      final response = await aiProvider.askFreeText(prompt);
      if (response.isEmpty) return 0;

      // Parse suggestions from AI response
      final parsed = _parseBridgeSuggestions(response, clusters);
      _suggestions.addAll(parsed);

      // Create ghost connections for each suggestion
      for (final suggestion in parsed) {
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

      return parsed.length;
    } catch (e) {
      debugPrint('🌉 [CrossZoneBridge] AI error: $e');
      return 0;
    } finally {
      _isLoading = false;
      version.value++;
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

    version.value++;
    return ghost;
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

  /// Dismiss a bridge suggestion — remove the ghost connection.
  void dismissBridge(String suggestionId) {
    final suggestion = _suggestions
        .where((s) => s.id == suggestionId)
        .firstOrNull;
    if (suggestion == null) return;

    suggestion.dismissed = true;

    // Remove the ghost connection
    final ghost = _flowController.connections
        .where((c) =>
            c.isGhost &&
            c.sourceClusterId == suggestion.sourceClusterId &&
            c.targetClusterId == suggestion.targetClusterId)
        .firstOrNull;
    if (ghost != null) {
      _flowController.removeConnection(ghost.id);
    }

    stats.suggestionsDismissed++;
    version.value++;
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
    // Build compact representation of zones
    final parts = <String>[];
    int index = 0;
    for (final cluster in clusters) {
      final text = clusterTexts[cluster.id];
      if (text == null || text.trim().length < 10) continue;
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
</HARD_CONSTRAINTS>

<STUDENT_ZONES>
$zonesSummary
</STUDENT_ZONES>

${existingStr.isNotEmpty ? '<EXISTING_BRIDGES>\n$existingStr\n</EXISTING_BRIDGES>' : ''}

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

  List<CrossZoneBridgeSuggestion> _parseBridgeSuggestions(
    String response,
    List<ContentCluster> clusters,
  ) {
    try {
      // Extract JSON array from response
      final jsonStr = _extractJsonArray(response);
      if (jsonStr == null) return [];

      final List<dynamic> items;
      try {
        items = _decodeJsonArray(jsonStr);
      } catch (_) {
        return [];
      }

      // Build zone index → cluster ID mapping
      final validClusters = <ContentCluster>[];
      for (final c in clusters) {
        if (c.elementCount > 0) validClusters.add(c);
        if (validClusters.length >= 12) break;
      }

      final suggestions = <CrossZoneBridgeSuggestion>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;

        final srcZone = (item['source_zone'] as num?)?.toInt();
        final tgtZone = (item['target_zone'] as num?)?.toInt();
        if (srcZone == null || tgtZone == null) continue;
        if (srcZone < 1 || srcZone > validClusters.length) continue;
        if (tgtZone < 1 || tgtZone > validClusters.length) continue;
        if (srcZone == tgtZone) continue;

        final srcCluster = validClusters[srcZone - 1];
        final tgtCluster = validClusters[tgtZone - 1];

        final question = item['socratic_question'] as String? ?? '';
        if (question.isEmpty) continue;

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
      }

      return suggestions;
    } catch (e) {
      debugPrint('🌉 [CrossZoneBridge] Parse error: $e');
      return [];
    }
  }

  /// Extract a JSON array from a possibly-wrapped response.
  String? _extractJsonArray(String text) {
    final trimmed = text
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    // Find first '[' and last ']'
    final start = trimmed.indexOf('[');
    final end = trimmed.lastIndexOf(']');
    if (start < 0 || end <= start) return null;
    return trimmed.substring(start, end + 1);
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
