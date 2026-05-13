// ============================================================================
// 💾 CrossZoneBridgePersistence — JSON-on-disk cache for Passo 9 suggestions.
//
// Caches the most recent set of `CrossZoneBridgeSuggestion`s emitted by the
// AI for a canvas, keyed by a hash of the prompt inputs. On the next request,
// if the prompt-hash matches and the cache is fresh, we skip the Gemini call
// entirely — same UX, near-zero latency, zero token cost.
//
// FORMAT: one JSON file per canvas under
//   {appDocs}/fluera_bridges/canvas_{canvasId}.json
// Schema:
//   { "version": 1,
//     "savedAt": "ISO8601",
//     "promptHash": "<deterministic hash>",
//     "suggestions": [ CrossZoneBridgeSuggestion.toJson(), ... ] }
//
// TTL: 7 days. Cross-domain suggestion quality decays fast as the student
// adds notes, so a long TTL would serve stale links. 7d balances "don't
// re-pay the token cost every week" with "stay relevant as content grows".
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../canvas/ai/cross_zone_bridge_controller.dart';
import '../utils/safe_path_provider.dart';

class CrossZoneBridgePersistence {
  CrossZoneBridgePersistence._();
  static final CrossZoneBridgePersistence instance =
      CrossZoneBridgePersistence._();

  static const int _schemaVersion = 1;
  static const Duration _maxAge = Duration(days: 7);

  Future<File?> _fileFor(String canvasId) async {
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return null;
      final bridgesDir = Directory('${dir.path}/fluera_bridges');
      if (!await bridgesDir.exists()) {
        await bridgesDir.create(recursive: true);
      }
      return File('${bridgesDir.path}/canvas_$canvasId.json');
    } catch (e) {
      debugPrint('🌉 BridgePersistence file path error: $e');
      return null;
    }
  }

  /// Persist [suggestions] for [canvasId] keyed by [promptHash].
  /// Atomic write via `.tmp` + rename.
  Future<void> save(
    String canvasId,
    String promptHash,
    List<CrossZoneBridgeSuggestion> suggestions,
  ) async {
    if (suggestions.isEmpty) return;
    final file = await _fileFor(canvasId);
    if (file == null) return;
    try {
      final payload = {
        'version': _schemaVersion,
        'savedAt': DateTime.now().toIso8601String(),
        'promptHash': promptHash,
        'suggestions': suggestions.map((s) => s.toJson()).toList(),
      };
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(payload));
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('🌉 BridgePersistence save error: $e');
    }
  }

  /// Returns the cached suggestions for [canvasId] if and only if the cache
  /// was written for the same [promptHash] AND is within [_maxAge]. Returns
  /// null otherwise (caller must call the AI).
  Future<List<CrossZoneBridgeSuggestion>?> loadIfFresh(
    String canvasId,
    String promptHash,
  ) async {
    final file = await _fileFor(canvasId);
    if (file == null) return null;
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;

      final version = json['version'] as int? ?? 0;
      if (version != _schemaVersion) {
        debugPrint('🌉 BridgePersistence: schema mismatch — drop cache');
        return null;
      }

      final cachedHash = json['promptHash'] as String? ?? '';
      if (cachedHash != promptHash) return null;

      final savedAtStr = json['savedAt'] as String?;
      if (savedAtStr == null) return null;
      final savedAt = DateTime.tryParse(savedAtStr);
      if (savedAt == null) return null;
      if (DateTime.now().difference(savedAt) > _maxAge) return null;

      final list = json['suggestions'] as List? ?? const [];
      final out = <CrossZoneBridgeSuggestion>[];
      for (final entry in list) {
        if (entry is! Map<String, dynamic>) continue;
        try {
          out.add(CrossZoneBridgeSuggestion.fromJson(entry));
        } catch (_) {
          // Skip malformed entries; don't fail the whole load.
        }
      }
      return out;
    } catch (e) {
      debugPrint('🌉 BridgePersistence load error: $e');
      return null;
    }
  }

  /// Delete the cache file for [canvasId]. Called on canvas removal.
  Future<void> delete(String canvasId) async {
    final file = await _fileFor(canvasId);
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('🌉 BridgePersistence delete error: $e');
    }
  }
}
