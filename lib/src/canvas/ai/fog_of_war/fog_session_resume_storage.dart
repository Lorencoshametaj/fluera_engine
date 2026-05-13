// ============================================================================
// 🌫️ FOG SESSION RESUME STORAGE — Sprint 6 reverse-return persistence
//
// When the student finishes a Fog of War session and taps "Interrogami sui
// blind spot", the controller is dismissed (we free the GPU from the blur
// backdrop) and the Atlas Exam overlay mounts. To preserve the spatial
// context after the exam, we persist the completed [FogOfWarSession] here
// just before dismiss; the [_handleExamCompleteFromFog] hook reads it back
// and re-activates the controller in mastery-map mode.
//
// Pattern is identical to the exam history checkpoint:
//   • atomic write via .tmp + rename
//   • single pending file (one in-flight reverse-return at a time)
//   • silent self-cleanup on corrupted JSON
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../utils/safe_path_provider.dart';
import 'fog_of_war_model.dart';

class FogSessionResumeStorage {
  const FogSessionResumeStorage();

  /// Single-instance pending file — only one reverse-return is allowed in
  /// flight at a time. Starting a new fog→exam handoff overwrites the
  /// previous (atomically), so a stale checkpoint never lingers.
  static const _kFileName = 'fluera_fog_pending.json';

  Future<File?> _file() async {
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return null;
      return File('${dir.path}/$_kFileName');
    } catch (_) {
      return null;
    }
  }

  /// Persist [session] for later restoration. Atomic: writes to `.tmp`
  /// then renames in one syscall, so a crash mid-write never leaves the
  /// reader with half a JSON document.
  Future<void> save(FogOfWarSession session) async {
    try {
      final file = await _file();
      if (file == null) return;
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(session.toJson()), flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('⚠️ FogSessionResume save error: $e');
    }
  }

  /// Read the pending session, if any. Returns null on missing or
  /// corrupted file (and silently deletes the corrupted file so the
  /// student isn't blocked on every subsequent flow).
  Future<FogOfWarSession?> read() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return FogOfWarSession.fromJson(j);
    } catch (e) {
      debugPrint('⚠️ FogSessionResume read error (purging): $e');
      await clear();
      return null;
    }
  }

  /// Remove any pending checkpoint. Called once the heatmap is dismissed
  /// (success path) or when the user starts a fresh fog session.
  Future<void> clear() async {
    try {
      final file = await _file();
      if (file != null && await file.exists()) await file.delete();
      final tmp = File('${(await _file())?.path}.tmp');
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {
      // best-effort cleanup
    }
  }
}
