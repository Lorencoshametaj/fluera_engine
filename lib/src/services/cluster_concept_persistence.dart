// ============================================================================
// 💾 ClusterConceptPersistence — JSON-on-disk store for cognitive concepts.
//
// Persists the per-canvas [ClusterConcept] map so AI titles / cleaned OCR
// survive app restarts. Without this, every cold-start re-runs the
// Atlas batch + cleanOcrItalian Gemini calls — expensive AND laggy
// (semantic titles only show once the batch returns ~2-5s in).
//
// FORMAT: one JSON file per canvas under
//   {appDocs}/fluera_concepts/canvas_{canvasId}.json
// Schema:
//   { "version": 1,
//     "concepts": [ ClusterConcept.toJson(), ... ],
//     "savedAt": "2026-05-10T..." }
//
// TTL: entries older than 30 days are pruned at hydration time. The
// cluster bounds may have shifted (reflow / pan-zoom) and the AI title
// for a stale concept usually mismatches the current location.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../canvas/ai/cluster_concept.dart';
import '../utils/safe_path_provider.dart';

class ClusterConceptPersistence {
  ClusterConceptPersistence._();
  static final ClusterConceptPersistence instance =
      ClusterConceptPersistence._();

  /// Schema version of the on-disk JSON. Bump on incompatible changes.
  static const int _schemaVersion = 1;

  /// Entries older than this are dropped at hydrate time. Trade-off:
  /// preserves cache across days/weeks of light usage, drops stale
  /// AI titles whose cluster bounds have likely drifted.
  static const Duration _maxAge = Duration(days: 30);

  Future<File?> _fileFor(String canvasId) async {
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return null;
      final conceptsDir = Directory('${dir.path}/fluera_concepts');
      if (!await conceptsDir.exists()) {
        await conceptsDir.create(recursive: true);
      }
      return File('${conceptsDir.path}/canvas_$canvasId.json');
    } catch (e) {
      debugPrint('🧠 ConceptPersistence file path error: $e');
      return null;
    }
  }

  /// Save the entire concept map for [canvasId]. Atomic write via
  /// `.tmp` + rename so a crash mid-write can't corrupt the JSON.
  Future<void> save(
    String canvasId,
    Map<String, ClusterConcept> concepts,
  ) async {
    if (concepts.isEmpty) return;
    final file = await _fileFor(canvasId);
    if (file == null) return;
    try {
      final payload = {
        'version': _schemaVersion,
        'savedAt': DateTime.now().toIso8601String(),
        'concepts': concepts.values.map((c) => c.toJson()).toList(),
      };
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(payload));
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('🧠 ConceptPersistence save error: $e');
    }
  }

  /// Load concepts for [canvasId]. Returns an empty map on first run,
  /// missing file, or unreadable JSON. Stale entries (older than
  /// [_maxAge]) are filtered out.
  Future<Map<String, ClusterConcept>> load(String canvasId) async {
    final file = await _fileFor(canvasId);
    if (file == null) return {};
    if (!await file.exists()) return {};
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return {};
      final version = json['version'] as int? ?? 0;
      if (version != _schemaVersion) {
        debugPrint('🧠 ConceptPersistence: schema mismatch — drop cache');
        return {};
      }
      final list = json['concepts'] as List? ?? const [];
      final cutoff = DateTime.now().subtract(_maxAge);
      final out = <String, ClusterConcept>{};
      for (final entry in list) {
        if (entry is! Map<String, dynamic>) continue;
        try {
          final concept = ClusterConcept.fromJson(entry);
          if (concept.lastUpdated.isBefore(cutoff)) continue;
          out[concept.clusterId] = concept;
        } catch (_) {
          // Skip malformed entries; don't fail the whole load.
        }
      }
      debugPrint(
          '🧠 ConceptPersistence: hydrated ${out.length} concepts for canvas=$canvasId');
      return out;
    } catch (e) {
      debugPrint('🧠 ConceptPersistence load error: $e');
      return {};
    }
  }

  /// Delete the concept file for [canvasId]. Called when a canvas is
  /// deleted from the gallery — no orphan files lingering on disk.
  Future<void> delete(String canvasId) async {
    final file = await _fileFor(canvasId);
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('🧠 ConceptPersistence delete error: $e');
    }
  }
}
