// ============================================================================
// 🧠 RECALL SESSION MODEL — Data models for Step 2 (Ricostruzione Solitaria)
//
// Specifica Implementativa: Passo 2 (P2-01 → P2-70)
//
// These models capture the full state of a recall session:
//   - Which mode is active (Free / Spatial / Comparison)
//   - Per-node recall status (5-level + peeked)
//   - Session history for Successive Relearning (Rawson & Dunlosky 2011)
//   - Peek tracking with progressive cost
//
// NO AI DEPENDENCY — all logic is local and offline.
// ============================================================================

/// The active phase of the Recall Mode.
///
/// Transitions:
///   inactive → freeRecall | spatialRecall → comparison → inactive
///   freeRecall → spatialRecall (unidirectional, P2-41)
enum RecallPhase {
  /// Recall Mode is not active.
  inactive,

  /// Free Recall: canvas completely blank — no positional cues.
  /// The student writes everything from memory (P2-39).
  freeRecall,

  /// Spatial Recall: colored blobs visible as positional cues.
  /// Text is 100% illegible, but shapes/colors hint at node positions (P2-40).
  spatialRecall,

  /// Comparison phase: blur removed, both sets visible side-by-side (P2-23→P2-30).
  comparison,
}

/// 5-level recall quality for a single node (P2-43, P2-44).
///
/// The student self-evaluates after comparison. If they don't,
/// the system falls back to binary (recalled=5 / missed=1) (P2-46).
enum RecallLevel {
  /// Level 0 — Peeked: the student used the peek function (P2-70).
  /// Does NOT count as autonomous recall.
  peeked(0, '👁️', 'Sbirciato', 0xFFFFCC00),

  /// Level 1 — Total miss: the student didn't remember this node existed (P2-15).
  missed(1, '❌', 'Non ricordato', 0xFFFF3B30),

  /// Level 2 — Tip-of-tongue: knows something was there but can't evoke it.
  tipOfTongue(2, '🟠', 'Sulla punta della lingua', 0xFFFF9500),

  /// Level 3 — Partial recall: fragmentary or imprecise.
  partial(3, '🟡', 'Parziale', 0xFFFF9F0A),

  /// Level 4 — Substantial recall: concept present, missing details.
  substantial(4, '🟢', 'Sostanziale', 0xFF34C759),

  /// Level 5 — Perfect recall: accurate content in approximately correct position.
  perfect(5, '✅', 'Perfetto', 0xFF30D158);

  const RecallLevel(this.level, this.icon, this.label, this.colorValue);

  /// Numeric level (0–5). Higher = better recall.
  final int level;

  /// Display icon for UI.
  final String icon;

  /// Human-readable label (Italian, P2-61: no negative language).
  final String label;

  /// Color value (ARGB) for the overlay indicator.
  final int colorValue;

  /// Whether this counts as successful autonomous recall (level ≥ 4).
  bool get isSuccessful => level >= 4;

  /// Whether this node should be high-priority for Step 3 Socratic (P2-45).
  bool get isHighPriority => level <= 2;
}

/// Per-node recall status within a session (P2-30, P2-44).
///
/// Persisted as part of the session metadata and passed to Step 3 as
/// the "gap map" (mappa di lacune, P2-36).
class RecallNodeEntry {
  /// The cluster ID this entry refers to.
  final String clusterId;

  /// Self-evaluated recall level (defaults to binary fallback if not set).
  RecallLevel recallLevel;

  /// Whether the student used peek on this node (P2-17, P2-70).
  bool peeked;

  /// How the node was recalled: 'free' or 'spatial' (P2-44).
  final String recallType;

  /// Timestamp when the recall status was determined.
  DateTime timestamp;

  /// Number of peek uses specifically on this node in this session.
  int peekCount;

  /// For comparison: whether the student wrote a correction (P2-29).
  bool correctionWritten;

  /// Successive Relearning: how many times this node was recalled
  /// correctly (level ≥ 4) across separate sessions ≥24h apart (P2-56).
  int consecutiveCorrectSessions;

  /// Whether this node has been mastered (3 correct recalls, P2-56).
  bool mastered;

  RecallNodeEntry({
    required this.clusterId,
    this.recallLevel = RecallLevel.missed,
    this.peeked = false,
    this.recallType = 'free',
    DateTime? timestamp,
    this.peekCount = 0,
    this.correctionWritten = false,
    this.consecutiveCorrectSessions = 0,
    this.mastered = false,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Serialize for persistence and Step 3 handoff (P2-36).
  Map<String, dynamic> toJson() => {
        'clusterId': clusterId,
        'recallLevel': recallLevel.level,
        'peeked': peeked,
        'recallType': recallType,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'peekCount': peekCount,
        'correctionWritten': correctionWritten,
        'consecutiveCorrectSessions': consecutiveCorrectSessions,
        'mastered': mastered,
      };

  factory RecallNodeEntry.fromJson(Map<String, dynamic> j) {
    final level = (j['recallLevel'] as num?)?.toInt() ?? 1;
    return RecallNodeEntry(
      clusterId: j['clusterId'] as String? ?? '',
      recallLevel: RecallLevel.values.firstWhere(
        (e) => e.level == level,
        orElse: () => RecallLevel.missed,
      ),
      peeked: j['peeked'] as bool? ?? false,
      recallType: j['recallType'] as String? ?? 'free',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (j['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
      peekCount: (j['peekCount'] as num?)?.toInt() ?? 0,
      correctionWritten: j['correctionWritten'] as bool? ?? false,
      consecutiveCorrectSessions:
          (j['consecutiveCorrectSessions'] as num?)?.toInt() ?? 0,
      mastered: j['mastered'] as bool? ?? false,
    );
  }
}

/// A complete recall session snapshot (P2-52).
///
/// One instance per "Recall Mode" activation. Persisted for:
/// - Successive Relearning tracking (P2-52→P2-56)
/// - Session-over-session improvement display (P2-59)
/// - Gap map handoff to Step 3 (P2-36)
class RecallSession {
  /// Unique session identifier.
  final String sessionId;

  /// Canvas ID this session belongs to.
  final String canvasId;

  /// Zone ID (derived from the selected area's hash).
  final String zoneId;

  /// When the session started.
  final DateTime startedAt;

  /// When the session ended (null if still active).
  DateTime? completedAt;

  /// Which phase was used: 'free', 'spatial', or 'free_then_spatial'.
  String recallType;

  /// If the student switched from Free to Spatial, record when (P2-42).
  DateTime? switchedToSpatialAt;

  /// Number of nodes recalled before switching to Spatial (P2-42).
  int nodesRecalledBeforeSwitch;

  /// Per-node recall data.
  final Map<String, RecallNodeEntry> nodeEntries;

  /// Total peek count for this session (resets per session, P2-68).
  int totalPeekCount;

  /// Total number of original nodes in the selected zone.
  int totalOriginalNodes;

  RecallSession({
    required this.sessionId,
    required this.canvasId,
    required this.zoneId,
    required this.startedAt,
    this.completedAt,
    this.recallType = 'free',
    this.switchedToSpatialAt,
    this.nodesRecalledBeforeSwitch = 0,
    Map<String, RecallNodeEntry>? nodeEntries,
    this.totalPeekCount = 0,
    this.totalOriginalNodes = 0,
  }) : nodeEntries = nodeEntries ?? {};

  // ─────────────────────────────────────────────────────────────────────────
  // DERIVED METRICS
  // ─────────────────────────────────────────────────────────────────────────

  /// Nodes the student recalled successfully (level ≥ 4).
  int get recalledCount =>
      nodeEntries.values.where((e) => e.recallLevel.isSuccessful).length;

  /// Nodes the student missed (level ≤ 2, not peeked).
  int get missedCount => nodeEntries.values
      .where((e) => !e.peeked && e.recallLevel.level <= 2)
      .length;

  /// Nodes the student peeked at.
  int get peekedCount => nodeEntries.values.where((e) => e.peeked).length;

  /// Recall percentage (for display, P2-58).
  double get recallPercentage =>
      totalOriginalNodes > 0 ? recalledCount / totalOriginalNodes : 0.0;

  /// Duration of the session.
  Duration get duration =>
      (completedAt ?? DateTime.now()).difference(startedAt);

  // ─────────────────────────────────────────────────────────────────────────
  // GAP MAP — handoff to Step 3 (P2-36)
  // ─────────────────────────────────────────────────────────────────────────

  /// Generate the gap map payload for Step 3 (P2-36).
  ///
  /// Returns a JSON-serializable list of node statuses that the Socratic AI
  /// will use to calibrate its questions.
  List<Map<String, dynamic>> toGapMap() => nodeEntries.values
      .map((e) => {
            'nodeId': e.clusterId,
            'status': e.peeked
                ? 'peeked'
                : e.recallLevel.isSuccessful
                    ? 'recalled'
                    : 'missed',
            'recallLevel': e.recallLevel.level,
            'peeked': e.peeked,
            'recallType': e.recallType,
          })
      .toList();

  // ─────────────────────────────────────────────────────────────────────────
  // SERIALIZATION
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'canvasId': canvasId,
        'zoneId': zoneId,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'completedAt': completedAt?.millisecondsSinceEpoch,
        'recallType': recallType,
        'switchedToSpatialAt': switchedToSpatialAt?.millisecondsSinceEpoch,
        'nodesRecalledBeforeSwitch': nodesRecalledBeforeSwitch,
        'totalPeekCount': totalPeekCount,
        'totalOriginalNodes': totalOriginalNodes,
        'nodeEntries': {
          for (final e in nodeEntries.entries) e.key: e.value.toJson(),
        },
      };

  factory RecallSession.fromJson(Map<String, dynamic> j) {
    final entries = <String, RecallNodeEntry>{};
    final rawEntries = j['nodeEntries'] as Map<String, dynamic>? ?? {};
    for (final e in rawEntries.entries) {
      if (e.value is Map<String, dynamic>) {
        entries[e.key] = RecallNodeEntry.fromJson(e.value as Map<String, dynamic>);
      }
    }

    return RecallSession(
      sessionId: j['sessionId'] as String? ?? '',
      canvasId: j['canvasId'] as String? ?? '',
      zoneId: j['zoneId'] as String? ?? '',
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        (j['startedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
      completedAt: j['completedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((j['completedAt'] as num).toInt())
          : null,
      recallType: j['recallType'] as String? ?? 'free',
      switchedToSpatialAt: j['switchedToSpatialAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (j['switchedToSpatialAt'] as num).toInt())
          : null,
      nodesRecalledBeforeSwitch:
          (j['nodesRecalledBeforeSwitch'] as num?)?.toInt() ?? 0,
      totalPeekCount: (j['totalPeekCount'] as num?)?.toInt() ?? 0,
      totalOriginalNodes: (j['totalOriginalNodes'] as num?)?.toInt() ?? 0,
      nodeEntries: entries,
    );
  }
}

/// Summary of a past recall session for history display (P2-53).
class RecallSessionSummary {
  final String sessionId;
  final String zoneId;
  final DateTime date;
  final int totalNodes;
  final int recalled;
  final int missed;
  final int peeked;
  final String recallType;

  const RecallSessionSummary({
    required this.sessionId,
    required this.zoneId,
    required this.date,
    required this.totalNodes,
    required this.recalled,
    required this.missed,
    required this.peeked,
    required this.recallType,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'zoneId': zoneId,
        'date': date.millisecondsSinceEpoch,
        'totalNodes': totalNodes,
        'recalled': recalled,
        'missed': missed,
        'peeked': peeked,
        'recallType': recallType,
      };

  factory RecallSessionSummary.fromJson(Map<String, dynamic> j) =>
      RecallSessionSummary(
        sessionId: j['sessionId'] as String? ?? '',
        zoneId: j['zoneId'] as String? ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(
          (j['date'] as num?)?.toInt() ?? 0,
        ),
        totalNodes: (j['totalNodes'] as num?)?.toInt() ?? 0,
        recalled: (j['recalled'] as num?)?.toInt() ?? 0,
        missed: (j['missed'] as num?)?.toInt() ?? 0,
        peeked: (j['peeked'] as num?)?.toInt() ?? 0,
        recallType: j['recallType'] as String? ?? 'free',
      );
}
