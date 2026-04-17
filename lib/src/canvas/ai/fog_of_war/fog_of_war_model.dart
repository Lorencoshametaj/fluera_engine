// ============================================================================
// 🌫️ FOG OF WAR MODEL — Data structures for Step 10 (Exam Preparation)
//
// Specifica: P10-01 → P10-29
//
// The Fog of War is a DIAGNOSTIC tool, not an exam. It reveals a mastery
// heatmap showing exactly what the student knows and doesn't know.
//
// AI STATE: N/A — pure data model.
// ============================================================================

/// The 3 fog density levels (P10-03).
///
/// The 3 fog density levels (P10-03).
///
/// Pedagogical gradient — each level removes more contextual information,
/// forcing deeper retrieval (§2 Active Recall, §5 Desirable Difficulties):
///
/// Pedagogical gradient — each level removes more contextual information,
/// forcing deeper retrieval (§2 Active Recall, §5 Desirable Difficulties):
///
/// | Level  | Silhouettes | Content | What it tests            | Difficulty |
/// |--------|-------------|---------|--------------------------|------------|
/// | light  | Clear       | Hidden  | WHAT is in each node     | Medium     |
/// | medium | Very faint  | Hidden  | WHERE (hard) + WHAT      | High       |
/// | total  | None        | Hidden  | WHERE + WHAT from memory | Maximum    |
enum FogLevel {
  /// Clear silhouettes visible — student knows WHERE every node is,
  /// must recall WHAT each one contains.
  /// (§3 Generation Effect: "cosa avevo scritto lì?")
  light,

  /// Very faint silhouettes — student must actively search to find nodes.
  /// Harder to locate than light, easier than total.
  /// (§5 Desirable Difficulties: degraded cues force deeper processing)
  medium,

  /// Complete darkness — zero visual cues.
  /// (§2 Active Recall at maximum difficulty)
  total,
}

/// Per-node result status during/after a Fog of War session.
enum FogNodeStatus {
  /// Not yet visited by the student.
  hidden,

  /// Student tapped and self-evaluated as ✅ (remembered).
  recalled,

  /// Student tapped and self-evaluated as ❌ (forgot).
  forgotten,

  /// Session ended without the student visiting this node.
  blindSpot,
}

/// Per-node entry tracked during the session.
class FogNodeEntry {
  final String clusterId;

  FogNodeStatus status;

  /// When the node was revealed (tapped).
  DateTime? revealedAt;

  /// Self-evaluation confidence (1-5), if provided.
  int? confidence;

  /// Time from tap to self-evaluation.
  Duration? responseTime;

  FogNodeEntry({
    required this.clusterId,
    this.status = FogNodeStatus.hidden,
    this.revealedAt,
    this.confidence,
    this.responseTime,
  });

  /// Whether the node has been visited (tapped).
  bool get isVisited => status != FogNodeStatus.hidden;

  /// Whether the node was successfully recalled.
  bool get isRecalled => status == FogNodeStatus.recalled;

  Map<String, dynamic> toJson() => {
        'clusterId': clusterId,
        'status': status.name,
        'revealedAt': revealedAt?.toIso8601String(),
        'confidence': confidence,
        'responseTime_ms': responseTime?.inMilliseconds,
      };
}

/// Fog of War session phases.
enum FogPhase {
  /// No fog session active.
  inactive,

  /// Fog overlay active — student navigating and tapping nodes.
  active,

  /// Cinematic fog-lift animation playing (2-3s, P10-18).
  revealing,

  /// Mastery heatmap visible — student can explore results.
  masteryMap,
}

/// Complete Fog of War session data (P10-08 data schema).
class FogOfWarSession {
  final String sessionId;
  final String canvasId;
  final String zoneId;
  final FogLevel fogLevel;
  final DateTime startedAt;
  DateTime? completedAt;
  final int totalNodes;

  /// Per-node tracking entries.
  final Map<String, FogNodeEntry> nodeEntries;

  FogOfWarSession({
    required this.sessionId,
    required this.canvasId,
    required this.zoneId,
    required this.fogLevel,
    required this.startedAt,
    this.completedAt,
    required this.totalNodes,
    Map<String, FogNodeEntry>? nodeEntries,
  }) : nodeEntries = nodeEntries ?? {};

  // ── Computed Metrics ──────────────────────────────────────────────────────

  /// Nodes successfully recalled (✅).
  int get recalledCount =>
      nodeEntries.values.where((e) => e.status == FogNodeStatus.recalled).length;

  /// Nodes forgotten (❌).
  int get forgottenCount =>
      nodeEntries.values
          .where((e) => e.status == FogNodeStatus.forgotten)
          .length;

  /// Nodes never visited — blind spots (P10-20).
  int get blindSpotCount =>
      nodeEntries.values
          .where((e) => e.status == FogNodeStatus.blindSpot)
          .length;

  /// Nodes currently still hidden (session in progress).
  int get hiddenCount =>
      nodeEntries.values.where((e) => e.status == FogNodeStatus.hidden).length;

  /// Nodes visited so far (recalled + forgotten).
  int get visitedCount => recalledCount + forgottenCount;

  /// IDs of nodes that need priority SRS reset (P10-23).
  List<String> get surgicalPlanNodeIds => nodeEntries.entries
      .where((e) =>
          e.value.status == FogNodeStatus.forgotten ||
          e.value.status == FogNodeStatus.blindSpot)
      .map((e) => e.key)
      .toList();

  /// Session duration in seconds (I: Duration Tracking).
  int get durationSeconds {
    if (completedAt == null) return 0;
    return completedAt!.difference(startedAt).inSeconds;
  }

  /// Average response time in milliseconds across visited nodes (I).
  int get avgResponseTimeMs {
    final withResponse = nodeEntries.values
        .where((e) => e.responseTime != null)
        .toList();
    if (withResponse.isEmpty) return 0;
    final totalMs = withResponse.fold<int>(
      0, (sum, e) => sum + e.responseTime!.inMilliseconds,
    );
    return totalMs ~/ withResponse.length;
  }

  /// Average confidence across recalled nodes (K: Confidence Trend).
  double get avgConfidence {
    final withConf = nodeEntries.values
        .where((e) => e.confidence != null && e.status == FogNodeStatus.recalled)
        .toList();
    if (withConf.isEmpty) return 0.0;
    final total = withConf.fold<int>(0, (sum, e) => sum + e.confidence!);
    return total / withConf.length;
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'timestamp': startedAt.toIso8601String(),
        'fogLevel': fogLevel.name,
        'zone': zoneId,
        'aiExaminer': false, // V1: no AI examiner
        'totalNodes': totalNodes,
        'durationSeconds': durationSeconds,
        'avgResponseTimeMs': avgResponseTimeMs,
        'avgConfidence': avgConfidence,
        'results': {
          'recalled': recalledCount,
          'forgotten': forgottenCount,
          'blind_spots': blindSpotCount,
        },
        'nodeResults':
            nodeEntries.values.map((e) => e.toJson()).toList(),
      };
}

/// Result of tapping a node during mastery map phase (P10-21).
class MasteryMapTapResult {
  final String clusterId;
  final FogNodeStatus status;

  const MasteryMapTapResult({
    required this.clusterId,
    required this.status,
  });
}
