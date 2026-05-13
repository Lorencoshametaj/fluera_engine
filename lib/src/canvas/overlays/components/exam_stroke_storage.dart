// ============================================================================
// 🖋️ EXAM STROKE STORAGE — Atomic per-question persistence of student strokes.
//
// Saves the raw [ProStroke]s the student drew on a specific question's
// MiniCanvasScratchpad, keyed by `<sessionId>__<questionId>`. The flow:
//
//   • on `MiniCanvasScratchpad.dispose()` (or after pen-up) → save
//   • on `ExamAnswerFullscreen.initState()` → load → repaint
//   • on user "Discard" → delete (so re-opening starts fresh)
//
// Atomic write pattern: `.tmp + rename + .bak fallback` mirrors the
// `_persistCheckpoint` helper in [exam_session_controller.dart] — a crash
// mid-write doesn't lose previous saves.
//
// Files live under `${appDocs}/fluera_exam_strokes/`. Per-key file size is
// typically <30KB even for verbose answers (200 strokes × 50 points each).
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../drawing/models/pro_drawing_point.dart';
import '../../../utils/safe_path_provider.dart';

class ExamStrokeStorage {
  ExamStrokeStorage._();

  static const _dirName = 'fluera_exam_strokes';

  /// Sanitises a key into a filesystem-safe filename. Allows alphanumerics,
  /// underscore, dash; everything else is replaced with `_`. Caps length at
  /// 200 chars to avoid hitting platform path limits on Android.
  static String _sanitise(String key) {
    final cleaned = key.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    if (cleaned.length <= 200) return cleaned;
    return cleaned.substring(0, 200);
  }

  /// Returns the file handle for [key]. Creates the parent directory if
  /// missing. Returns null when the platform documents dir is unreachable
  /// (rare — sandbox issue, no storage permission).
  static Future<File?> _fileFor(String key) async {
    try {
      final docs = await getSafeDocumentsDirectory();
      if (docs == null) return null;
      final dir = Directory('${docs.path}/$_dirName');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File('${dir.path}/${_sanitise(key)}.json');
    } catch (e) {
      debugPrint('🖋️ ExamStrokeStorage: dir resolve error: $e');
      return null;
    }
  }

  /// Loads strokes for [key]. Returns `null` if no file (or unreadable / empty).
  /// Tries the primary `.json` then the `.bak` shadow on parse failure.
  static Future<List<ProStroke>?> load(String key) async {
    final file = await _fileFor(key);
    if (file == null) return null;
    final candidates = [file, File('${file.path}.bak')];
    for (final candidate in candidates) {
      try {
        if (!await candidate.exists()) continue;
        final raw = await candidate.readAsString();
        if (raw.trim().isEmpty) continue;
        final list = jsonDecode(raw);
        if (list is! List) continue;
        final strokes = <ProStroke>[];
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          try {
            strokes.add(ProStroke.fromJson(item));
          } catch (e) {
            debugPrint('🖋️ ExamStrokeStorage: skip malformed stroke: $e');
          }
        }
        if (strokes.isNotEmpty) return strokes;
      } catch (e) {
        debugPrint('🖋️ ExamStrokeStorage: load error from ${candidate.path}: $e');
      }
    }
    return null;
  }

  /// Persists [strokes] under [key]. Atomic: writes to `.tmp`, renames the
  /// previous file to `.bak`, then renames `.tmp` to the canonical path.
  /// A crash mid-write leaves either the previous good copy at `.json` or
  /// at `.bak` — never a half-written file.
  static Future<void> save(String key, List<ProStroke> strokes) async {
    final file = await _fileFor(key);
    if (file == null) return;
    if (strokes.isEmpty) {
      // No content → delete any prior persistence to keep the dir clean.
      await delete(key);
      return;
    }
    try {
      final tmp = File('${file.path}.tmp');
      final bak = File('${file.path}.bak');
      final encoded = jsonEncode(strokes.map((s) => s.toJson()).toList());
      await tmp.writeAsString(encoded, flush: true);
      // Promote previous canonical → .bak (defensive: kill old .bak first).
      if (await file.exists()) {
        if (await bak.exists()) await bak.delete();
        await file.rename(bak.path);
      }
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('🖋️ ExamStrokeStorage: save error for $key: $e');
    }
  }

  /// Deletes the persisted strokes for [key] plus its `.bak` shadow.
  /// Silent if no file exists.
  static Future<void> delete(String key) async {
    final file = await _fileFor(key);
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
      final bak = File('${file.path}.bak');
      if (await bak.exists()) await bak.delete();
    } catch (e) {
      debugPrint('🖋️ ExamStrokeStorage: delete error for $key: $e');
    }
  }

  /// Lists all persisted keys whose name starts with `${sessionId}__`.
  /// Used by the V1.1 dashboard "Review answers" feature.
  static Future<List<String>> listKeysForSession(String sessionId) async {
    try {
      final docs = await getSafeDocumentsDirectory();
      if (docs == null) return const [];
      final dir = Directory('${docs.path}/$_dirName');
      if (!await dir.exists()) return const [];
      final prefix = '${_sanitise(sessionId)}__';
      final out = <String>[];
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (!name.startsWith(prefix)) continue;
        if (!name.endsWith('.json')) continue;
        out.add(name.substring(0, name.length - 5));
      }
      return out;
    } catch (e) {
      debugPrint('🖋️ ExamStrokeStorage: list error for session $sessionId: $e');
      return const [];
    }
  }
}
