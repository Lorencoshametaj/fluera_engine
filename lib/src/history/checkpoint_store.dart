/// 📍 CHECKPOINT STORE — filesystem persistence for [VersionHistory] entries.
///
/// Each canvas keeps its checkpoints in a single JSON file at
/// `{timeTravelPath}/checkpoints.json` — one file per canvas, all entries in
/// chronological order. The blob inside each entry's `data` is opaque
/// (typically a serialized layer list — see `_lifecycle_branching.dart`).
///
/// Reuses [TimeTravelStorageService.getTimeTravelPathForCanvas] so the
/// directory layout stays consistent with branches.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../services/phase2_service_stubs.dart';
import 'version_history.dart';

class CheckpointStore {
  final FlueraTimeTravelStorage _storage;

  CheckpointStore({FlueraTimeTravelStorage? storage})
      : _storage = storage ?? TimeTravelStorageService();

  Future<File> _fileFor(String canvasId) async {
    final ttPath = await _storage.getTimeTravelPathForCanvas(canvasId);
    return File(p.join(ttPath, 'checkpoints.json'));
  }

  /// Load checkpoints for [canvasId]. Returns an empty [VersionHistory] if no
  /// file exists yet (first-time use) or on corruption (defensive).
  Future<VersionHistory> load(String canvasId) async {
    try {
      final file = await _fileFor(canvasId);
      if (!await file.exists()) return VersionHistory();
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return VersionHistory();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return VersionHistory.fromJson(decoded);
    } catch (_) {
      // Corrupt file — start fresh rather than crashing.
      return VersionHistory();
    }
  }

  /// Persist [history] for [canvasId]. Creates parent directory if needed.
  /// Best-effort: swallows IO errors silently (UI already updated optimistically).
  Future<void> save(String canvasId, VersionHistory history) async {
    try {
      final file = await _fileFor(canvasId);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(history.toJson()));
    } catch (_) {
      // Storage failure — checkpoint stays in memory for the session at least.
    }
  }
}
