// ============================================================================
// 📊 P2P SESSION DATA — Telemetry and output model (P7-07)
//
// Captures all data generated during a P2P session for:
//   - SRS integration (what was learned from the peer)
//   - Pedagogical telemetry (session quality metrics)
//   - Post-session review prompts
//
// Data format matches the spec JSON (P7-07 section 7.7).
//
// ARCHITECTURE: Pure model, fully serializable.
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'p2p_session_state.dart';

/// 📊 Complete P2P session data (P7-07).
///
/// Generated at the end of a session. Serializable for storage.
class P2PSessionData {
  /// Unique session identifier.
  final String sessionId;

  /// Session start time.
  final DateTime startedAt;

  /// Session end time.
  DateTime? endedAt;

  /// Active mode during the session.
  final P2PCollabMode mode;

  /// Participants (local + remote display names).
  final List<String> participants;

  /// Zone/topic that was studied.
  final String zoneId;

  /// Mode-specific data.
  final VisitData? visitData; // 7a
  final TeachingData? teachingData; // 7b
  final DuelData? duelData; // 7c

  /// Total session duration in milliseconds.
  int get durationMs =>
      endedAt != null
          ? endedAt!.difference(startedAt).inMilliseconds
          : DateTime.now().difference(startedAt).inMilliseconds;

  P2PSessionData({
    required this.sessionId,
    required this.startedAt,
    this.endedAt,
    required this.mode,
    required this.participants,
    required this.zoneId,
    this.visitData,
    this.teachingData,
    this.duelData,
  });

  /// End the session.
  void end() {
    endedAt = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'timestamp': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'mode': '7${mode.name[0]}', // '7a', '7b', '7c'
        'participants': participants,
        'zone': zoneId,
        'durationMs': durationMs,
        if (visitData != null) '7a_data': visitData!.toJson(),
        if (teachingData != null) '7b_data': teachingData!.toJson(),
        if (duelData != null) '7c_data': duelData!.toJson(),
      };
}

/// 📊 Mode 7a data — Read-only visit.
class VisitData {
  /// Markers placed on the peer's canvas (P7-08).
  int markersPlaced;

  /// Number of different nodes observed.
  int nodesDifferent;

  /// Total view duration (ms).
  int viewDurationMs;

  VisitData({
    this.markersPlaced = 0,
    this.nodesDifferent = 0,
    this.viewDurationMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'markersPlaced': markersPlaced,
        'nodesDifferent': nodesDifferent,
        'viewDuration_ms': viewDurationMs,
      };
}

/// 📊 Mode 7b data — Teaching reciprocal.
class TeachingData {
  /// Who taught (display name).
  String? whoTaught;

  /// Nodes explained during teaching.
  int nodesExplained;

  /// Nodes that were hard to explain (P7-17).
  int nodesHardToExplain;

  /// Nodes rewritten after receiving teaching.
  int rewrittenAfter;

  /// Teaching session duration (ms).
  int teachingDurationMs;

  TeachingData({
    this.whoTaught,
    this.nodesExplained = 0,
    this.nodesHardToExplain = 0,
    this.rewrittenAfter = 0,
    this.teachingDurationMs = 0,
  });

  Map<String, dynamic> toJson() => {
        if (whoTaught != null) 'whoTaught': whoTaught,
        'nodesExplained': nodesExplained,
        'nodesHardToExplain': nodesHardToExplain,
        'rewrittenAfter': rewrittenAfter,
        'teachingDuration_ms': teachingDurationMs,
      };
}

/// 📊 Mode 7c data — Recall duel.
class DuelData {
  /// Nodes recalled by local student.
  int nodesRecalledLocal;

  /// Nodes recalled by remote student.
  int nodesRecalledRemote;

  /// Nodes unique to local student.
  int uniqueToLocal;

  /// Nodes unique to remote student.
  int uniqueToRemote;

  /// Nodes rewritten after the duel.
  int rewrittenAfter;

  /// Recall duration for local student (ms).
  int recallDurationLocalMs;

  /// Recall duration for remote student (ms).
  int recallDurationRemoteMs;

  DuelData({
    this.nodesRecalledLocal = 0,
    this.nodesRecalledRemote = 0,
    this.uniqueToLocal = 0,
    this.uniqueToRemote = 0,
    this.rewrittenAfter = 0,
    this.recallDurationLocalMs = 0,
    this.recallDurationRemoteMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'nodesRecalledLocal': nodesRecalledLocal,
        'nodesRecalledRemote': nodesRecalledRemote,
        'uniqueToLocal': uniqueToLocal,
        'uniqueToRemote': uniqueToRemote,
        'rewrittenAfter': rewrittenAfter,
        'recallDuration_local_ms': recallDurationLocalMs,
        'recallDuration_remote_ms': recallDurationRemoteMs,
      };
}
