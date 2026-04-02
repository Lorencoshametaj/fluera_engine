// ============================================================================
// 💾 RECALL PERSISTENCE SERVICE — Local storage for recall sessions
//
// Saves/loads recall session history to a JSON file in the app's
// documents directory. Follows the same pattern as ExamSessionController.
//
// Schema (P2-52):
//   recall_sessions(zone_id, timestamp, total_nodes, recalled, missed,
//                   peeked, recall_type)
//
// Also tracks per-node mastery flags (P2-56) and session summaries
// for mini-timeline display (P2-53).
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../utils/safe_path_provider.dart';
import 'recall_session_model.dart';

/// 💾 Persistence service for recall session data.
///
/// Thread-safe: all I/O is async and runs on the main isolate with
/// await semantics — no concurrent writes.
class RecallPersistenceService {
  /// Maximum number of sessions to retain per canvas.
  static const int maxSessionsPerCanvas = 100;

  /// In-memory cache of loaded sessions (keyed by canvasId).
  final Map<String, List<RecallSession>> _cache = {};

  /// Per-node mastery data across sessions.
  final Map<String, _NodeMasteryRecord> _masteryCache = {};

  // ─────────────────────────────────────────────────────────────────────────
  // FILE PATHS
  // ─────────────────────────────────────────────────────────────────────────

  Future<File?> _sessionsFile(String canvasId) async {
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return null;
      final recallDir = Directory('${dir.path}/fluera_recall');
      if (!await recallDir.exists()) {
        await recallDir.create(recursive: true);
      }
      return File('${recallDir.path}/sessions_$canvasId.json');
    } catch (_) {
      return null;
    }
  }

  Future<File?> _masteryFile(String canvasId) async {
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return null;
      final recallDir = Directory('${dir.path}/fluera_recall');
      if (!await recallDir.exists()) {
        await recallDir.create(recursive: true);
      }
      return File('${recallDir.path}/mastery_$canvasId.json');
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SESSION PERSISTENCE
  // ─────────────────────────────────────────────────────────────────────────

  /// Save a completed recall session.
  Future<void> saveSession(RecallSession session) async {
    try {
      // Add to in-memory cache.
      _cache.putIfAbsent(session.canvasId, () => []);
      _cache[session.canvasId]!.insert(0, session);

      // Trim to max.
      final list = _cache[session.canvasId]!;
      if (list.length > maxSessionsPerCanvas) {
        _cache[session.canvasId] = list.take(maxSessionsPerCanvas).toList();
      }

      // Persist to disk.
      final file = await _sessionsFile(session.canvasId);
      if (file == null) return;
      final json = _cache[session.canvasId]!
          .map((s) => s.toJson())
          .toList();
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('⚠️ RecallPersistence.saveSession error: $e');
    }
  }

  /// Load all sessions for a canvas (lazy, cached).
  Future<List<RecallSession>> loadSessions(String canvasId) async {
    if (_cache.containsKey(canvasId)) return _cache[canvasId]!;

    try {
      final file = await _sessionsFile(canvasId);
      if (file == null || !await file.exists()) return [];

      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      final sessions = list
          .whereType<Map<String, dynamic>>()
          .map(RecallSession.fromJson)
          .toList();

      _cache[canvasId] = sessions;
      return sessions;
    } catch (e) {
      debugPrint('⚠️ RecallPersistence.loadSessions error: $e');
      return [];
    }
  }

  /// Get session history summaries for a specific zone (P2-53).
  Future<List<RecallSessionSummary>> getZoneHistory(
    String canvasId,
    String zoneId,
  ) async {
    final sessions = await loadSessions(canvasId);
    return sessions
        .where((s) => s.zoneId == zoneId)
        .map((s) => RecallSessionSummary(
              sessionId: s.sessionId,
              zoneId: s.zoneId,
              date: s.startedAt,
              totalNodes: s.totalOriginalNodes,
              recalled: s.recalledCount,
              missed: s.missedCount,
              peeked: s.peekedCount,
              recallType: s.recallType,
            ))
        .toList();
  }

  /// Count how many sessions exist for a specific zone (for adaptive blur, P2-54).
  Future<int> getZoneSessionCount(String canvasId, String zoneId) async {
    final sessions = await loadSessions(canvasId);
    return sessions.where((s) => s.zoneId == zoneId).length;
  }

  /// Get the most recent session for a zone (for delta display, P2-59).
  Future<RecallSessionSummary?> getLastZoneSession(
    String canvasId,
    String zoneId,
  ) async {
    final history = await getZoneHistory(canvasId, zoneId);
    // Skip the first (current) if it was just saved.
    return history.length > 1 ? history[1] : history.firstOrNull;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MASTERY PERSISTENCE (P2-56)
  // ─────────────────────────────────────────────────────────────────────────

  /// Save mastery data for a canvas.
  Future<void> saveMastery(
    String canvasId,
    Map<String, _NodeMasteryRecord> mastery,
  ) async {
    try {
      _masteryCache.addAll(mastery);
      final file = await _masteryFile(canvasId);
      if (file == null) return;
      final json = {
        for (final e in mastery.entries) e.key: e.value.toJson(),
      };
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('⚠️ RecallPersistence.saveMastery error: $e');
    }
  }

  /// Load mastery data for a canvas.
  Future<Map<String, _NodeMasteryRecord>> loadMastery(String canvasId) async {
    try {
      final file = await _masteryFile(canvasId);
      if (file == null || !await file.exists()) return {};

      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in json.entries)
          if (e.value is Map<String, dynamic>)
            e.key: _NodeMasteryRecord.fromJson(e.value as Map<String, dynamic>),
      };
    } catch (e) {
      debugPrint('⚠️ RecallPersistence.loadMastery error: $e');
      return {};
    }
  }

  /// Check if a specific node is mastered (P2-56).
  Future<bool> isNodeMastered(String canvasId, String clusterId) async {
    final mastery = await loadMastery(canvasId);
    return mastery[clusterId]?.mastered ?? false;
  }

  /// Update mastery record after a session completes.
  Future<void> updateMasteryAfterSession(
    String canvasId,
    RecallSession session,
  ) async {
    final mastery = await loadMastery(canvasId);

    for (final entry in session.nodeEntries.entries) {
      final record = mastery.putIfAbsent(
        entry.key,
        () => _NodeMasteryRecord(clusterId: entry.key),
      );

      if (entry.value.recallLevel.isSuccessful && !entry.value.peeked) {
        // Check 24h gap.
        final lastDate = record.lastCorrectDate;
        final hasGap = lastDate == null ||
            DateTime.now().difference(lastDate).inHours >= 24;

        if (hasGap) {
          record.consecutiveCorrect++;
          record.lastCorrectDate = DateTime.now();
        }

        if (record.consecutiveCorrect >= 3) {
          record.mastered = true;
        }
      } else {
        record.consecutiveCorrect = 0;
      }
    }

    await saveMastery(canvasId, mastery);
  }

  /// Invalidate cache for a canvas (e.g., on canvas close).
  void invalidateCache(String canvasId) {
    _cache.remove(canvasId);
  }
}

/// Per-node mastery tracking across sessions (P2-56).
class _NodeMasteryRecord {
  final String clusterId;
  int consecutiveCorrect;
  DateTime? lastCorrectDate;
  bool mastered;

  _NodeMasteryRecord({
    required this.clusterId,
    this.consecutiveCorrect = 0,
    this.lastCorrectDate,
    this.mastered = false,
  });

  Map<String, dynamic> toJson() => {
        'clusterId': clusterId,
        'consecutiveCorrect': consecutiveCorrect,
        'lastCorrectDate': lastCorrectDate?.millisecondsSinceEpoch,
        'mastered': mastered,
      };

  factory _NodeMasteryRecord.fromJson(Map<String, dynamic> j) =>
      _NodeMasteryRecord(
        clusterId: j['clusterId'] as String? ?? '',
        consecutiveCorrect:
            (j['consecutiveCorrect'] as num?)?.toInt() ?? 0,
        lastCorrectDate: j['lastCorrectDate'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (j['lastCorrectDate'] as num).toInt())
            : null,
        mastered: j['mastered'] as bool? ?? false,
      );
}
