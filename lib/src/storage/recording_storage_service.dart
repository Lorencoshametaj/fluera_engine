// ============================================================================
// 🎤 RECORDING STORAGE SERVICE — Enterprise SQLite persistence for recordings
//
// Singleton service managing CRUD operations for SynchronizedRecording objects.
// Uses the same SQLite database as SqliteStorageAdapter (via shared Database).
// ============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';
import '../time_travel/models/synchronized_recording.dart';

/// Table name for recordings.
const String _kRecordingsTable = 'recordings';

/// 🎤 Enterprise recording storage service.
///
/// Provides full CRUD for [SynchronizedRecording] objects, persisted in
/// the same SQLite database used by `SqliteStorageAdapter`.
///
/// ## Usage
/// ```dart
/// // Initialize (called once during canvas load)
/// RecordingStorageService.instance.initialize(db);
///
/// // Save a recording
/// await RecordingStorageService.instance.saveRecording(recording);
///
/// // Load all recordings for a canvas
/// final recordings = await RecordingStorageService.instance
///     .loadRecordingsForCanvas('canvas_123');
/// ```
class RecordingStorageService {
  RecordingStorageService._();

  /// Singleton instance.
  static final RecordingStorageService instance = RecordingStorageService._();

  Database? _db;

  /// Whether the service has been initialized with a database reference.
  bool get isInitialized => _db != null;

  /// Initialize with a shared [Database] instance.
  ///
  /// This should be called after [SqliteStorageAdapter.initialize()] since
  /// the adapter creates the schema (including the `recordings` table).
  void initialize(Database db) {
    _db = db;
    debugPrint('[RecordingStorage] Initialized with shared database');
  }

  /// Persist a [SynchronizedRecording] to the database.
  ///
  /// Uses INSERT OR REPLACE so re-saving the same recording (by id) updates it.
  Future<void> saveRecording(SynchronizedRecording recording) async {
    _ensureInitialized();

    // Encode synced strokes as JSON text (null if no strokes)
    final strokesJson =
        recording.syncedStrokes.isNotEmpty
            ? jsonEncode(
              recording.syncedStrokes.map((s) => s.toJson()).toList(),
            )
            : null;

    await _db!.insert(_kRecordingsTable, {
      'id': recording.id,
      'canvas_id': recording.canvasId ?? '',
      'audio_path': recording.audioPath,
      'note_title': recording.noteTitle,
      'recording_type': recording.recordingType,
      'total_duration_ms': recording.totalDuration.inMilliseconds,
      'start_time': recording.startTime.toIso8601String(),
      'strokes_json': strokesJson,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    debugPrint(
      '[RecordingStorage] Saved recording ${recording.id} '
      '(${recording.syncedStrokes.length} strokes, '
      '${recording.totalDuration.inSeconds}s)',
    );
  }

  /// Load all recordings associated with a canvas.
  ///
  /// Returns an empty list if no recordings exist for the given canvas.
  Future<List<SynchronizedRecording>> loadRecordingsForCanvas(
    String canvasId,
  ) async {
    _ensureInitialized();

    final rows = await _db!.query(
      _kRecordingsTable,
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
      orderBy: 'created_at ASC',
    );

    final recordings = <SynchronizedRecording>[];

    for (final row in rows) {
      try {
        // Decode synced strokes from JSON
        final strokesJsonStr = row['strokes_json'] as String?;
        final syncedStrokes = <SyncedStroke>[];
        if (strokesJsonStr != null && strokesJsonStr.isNotEmpty) {
          final decoded = jsonDecode(strokesJsonStr) as List<dynamic>;
          syncedStrokes.addAll(
            decoded.map(
              (s) => SyncedStroke.fromJson(s as Map<String, dynamic>),
            ),
          );
        }

        recordings.add(
          SynchronizedRecording(
            id: row['id'] as String,
            audioPath: row['audio_path'] as String,
            totalDuration: Duration(
              milliseconds: row['total_duration_ms'] as int,
            ),
            startTime: DateTime.parse(row['start_time'] as String),
            syncedStrokes: syncedStrokes,
            canvasId: row['canvas_id'] as String?,
            noteTitle: row['note_title'] as String?,
            recordingType: row['recording_type'] as String?,
          ),
        );
      } catch (e) {
        debugPrint(
          '[RecordingStorage] Failed to decode recording ${row['id']}: $e',
        );
      }
    }

    debugPrint(
      '[RecordingStorage] Loaded ${recordings.length} recordings '
      'for canvas $canvasId',
    );
    return recordings;
  }

  /// Delete a single recording by its ID.
  Future<int> deleteRecording(String id) async {
    _ensureInitialized();

    final count = await _db!.delete(
      _kRecordingsTable,
      where: 'id = ?',
      whereArgs: [id],
    );

    debugPrint('[RecordingStorage] Deleted recording $id (rows=$count)');
    return count;
  }

  /// Delete a recording by its audio file path (avoids O(N) lookup).
  Future<int> deleteByAudioPath(String audioPath) async {
    _ensureInitialized();

    final count = await _db!.delete(
      _kRecordingsTable,
      where: 'audio_path = ?',
      whereArgs: [audioPath],
    );

    debugPrint(
      '[RecordingStorage] Deleted by audioPath $audioPath (rows=$count)',
    );
    return count;
  }

  /// Delete all recordings for a canvas (cascade cleanup).
  Future<int> deleteRecordingsForCanvas(String canvasId) async {
    _ensureInitialized();

    final count = await _db!.delete(
      _kRecordingsTable,
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );

    debugPrint(
      '[RecordingStorage] Deleted $count recordings for canvas $canvasId',
    );
    return count;
  }

  /// Ensure the service is initialized.
  void _ensureInitialized() {
    if (_db == null) {
      throw StateError(
        'RecordingStorageService not initialized. '
        'Call initialize(db) after SqliteStorageAdapter.initialize().',
      );
    }
  }
}
