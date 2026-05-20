import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/safe_path_provider.dart';
import '../storage/fluera_cloud_adapter.dart';
import 'dict_entry.dart';

// =============================================================================
// 📚 PERSONAL DICTIONARY SERVICE — User-specific words with cloud sync
//
// Stores words the user has added (ignored spellcheck words, custom
// vocabulary). Persists locally to JSON and syncs via FlueraCloudStorageAdapter.
//
// Schema (v2, 2026-05-19):
//   { "schema": 2, "entries": [ {"w": "<lowercase>", "t": <addedAtMs>} ] }
//
// Migration from v1 (plain `["word1", "word2"]` list): detected at load time
// by checking the JSON root type. Migration runs in-memory; the next
// debounced save rewrites the file in v2. No destructive operations on the
// v1 file — if v2 save fails, the v1 data stays intact on disk.
// =============================================================================

class _PersonalEntry {
  final int addedAtMs;
  const _PersonalEntry({required this.addedAtMs});
}

class PersonalDictionaryService {
  PersonalDictionaryService._();
  static final PersonalDictionaryService instance = PersonalDictionaryService._();

  /// User-added words keyed by lowercased canonical form, with per-entry
  /// metadata (currently just `addedAtMs`; room to grow for source-of-truth
  /// tagging, scope, etc. without another migration).
  final Map<String, _PersonalEntry> _entries = {};

  /// Whether the dictionary has been loaded from disk.
  bool _loaded = false;

  /// Cloud adapter for sync (set via [setCloudAdapter]).
  FlueraCloudStorageAdapter? _cloudAdapter;

  /// User ID for cloud storage key.
  String? _userId;

  /// Cloud sync key prefix.
  static const String _cloudKey = '__personal_dictionary__';

  /// Debounce timer for local save.
  Timer? _saveTimer;

  // ── Public API ─────────────────────────────────────────────────────────

  /// Check if a word exists in the personal dictionary.
  bool contains(String word) => _entries.containsKey(word.toLowerCase());

  /// Number of words in the dictionary.
  int get wordCount => _entries.length;

  /// All words (read-only).
  Set<String> get words => Set.unmodifiable(_entries.keys);

  /// Synthetic [DictEntry] for a personal word — used as the fallback when
  /// `WordCompletionDictionary.lookUp` misses the shared asset. Returns
  /// `null` when the word is not in the personal set.
  ///
  /// The synthetic entry advertises `domain=['user']` so downstream
  /// consumers (e.g., mlkit reranker length-weight boost) can distinguish
  /// user-added terms from baseline dict hits.
  DictEntry? lookUp(String word) {
    final lower = word.toLowerCase().trim();
    if (!_entries.containsKey(lower)) return null;
    return DictEntry(
      word: lower,
      freqRank: 999999, // last-resort rank — never beats a real dict entry
      pos: 'x',
      domains: const ['user'],
    );
  }

  /// Add a word to the personal dictionary.
  void addWord(String word) {
    final lower = word.toLowerCase().trim();
    if (lower.length < 2 || _entries.containsKey(lower)) return;

    _entries[lower] = _PersonalEntry(
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    debugPrint('[PersonalDict] Added "$lower" (${_entries.length} total)');
    _scheduleSave();
  }

  /// Remove a word from the personal dictionary.
  void removeWord(String word) {
    final lower = word.toLowerCase().trim();
    if (_entries.remove(lower) != null) {
      debugPrint('[PersonalDict] Removed "$lower"');
      _scheduleSave();
    }
  }

  /// Clear all words.
  void clear() {
    _entries.clear();
    _scheduleSave();
  }

  // ── Initialization ─────────────────────────────────────────────────────

  /// Initialize the service. Call once at app start.
  Future<void> initialize() async {
    if (_loaded) return;
    await _loadFromDisk();
    _loaded = true;
    debugPrint('[PersonalDict] Loaded ${_entries.length} words from disk');
  }

  /// Set cloud adapter for sync. Call after user login.
  void setCloudAdapter(FlueraCloudStorageAdapter? adapter, {String? userId}) {
    _cloudAdapter = adapter;
    _userId = userId;
    if (adapter != null && userId != null) {
      // Pull cloud words on login
      _pullFromCloud();
    }
  }

  // ── Local persistence ──────────────────────────────────────────────────

  Future<File?> get _localFile async {
    final dir = await getSafeDocumentsDirectory();
    if (dir == null) return null;
    return File('${dir.path}/.fluera_personal_dict.json');
  }

  Future<void> _loadFromDisk() async {
    try {
      final file = await _localFile;
      if (file == null || !file.existsSync()) return;
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is List) {
        // v1 — plain string list. Migrate in-memory; next save rewrites v2.
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        for (final raw in decoded.cast<String>()) {
          _entries[raw] = _PersonalEntry(addedAtMs: nowMs);
        }
        debugPrint('[PersonalDict] migrated ${_entries.length} words v1 → v2');
        _scheduleSave();
      } else if (decoded is Map<String, dynamic>) {
        // v2 — schema-tagged object.
        final entries = (decoded['entries'] as List<dynamic>?) ?? const [];
        for (final e in entries) {
          if (e is! Map<String, dynamic>) continue;
          final w = e['w'] as String?;
          final t = e['t'];
          if (w == null) continue;
          final tMs = t is int ? t : (t is num ? t.toInt() : 0);
          _entries[w] = _PersonalEntry(addedAtMs: tMs);
        }
      }
    } catch (e) {
      debugPrint('[PersonalDict] Load error: $e');
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _localFile;
      if (file == null) return;
      await file.writeAsString(jsonEncode(_v2Payload()));
    } catch (e) {
      debugPrint('[PersonalDict] Save error: $e');
    }
  }

  Map<String, dynamic> _v2Payload() => {
        'schema': 2,
        'entries': _entries.entries
            .map((e) => {'w': e.key, 't': e.value.addedAtMs})
            .toList(),
      };

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () {
      _saveToDisk();
      _pushToCloud();
    });
  }

  // ── Cloud sync ─────────────────────────────────────────────────────────

  Future<void> _pushToCloud() async {
    if (_cloudAdapter == null || _userId == null) return;
    try {
      await _cloudAdapter!.saveCanvas('$_cloudKey$_userId', {
        ..._v2Payload(),
        'updatedAt': DateTime.now().toIso8601String(),
        'version': 2,
      });
      debugPrint('[PersonalDict] Pushed ${_entries.length} words to cloud');
    } catch (e) {
      debugPrint('[PersonalDict] Cloud push error: $e');
    }
  }

  Future<void> _pullFromCloud() async {
    if (_cloudAdapter == null || _userId == null) return;
    try {
      final data = await _cloudAdapter!.loadCanvas('$_cloudKey$_userId');
      if (data == null) return;

      final before = _entries.length;
      // Tolerate both shapes: v1 had `words: ["w1", "w2"]`; v2 carries the
      // full {schema, entries} payload alongside cloud-only `updatedAt`.
      final entries = data['entries'];
      if (entries is List) {
        for (final e in entries) {
          if (e is! Map<String, dynamic>) continue;
          final w = e['w'] as String?;
          if (w == null) continue;
          final t = e['t'];
          final tMs = t is int ? t : (t is num ? t.toInt() : 0);
          _entries.putIfAbsent(w, () => _PersonalEntry(addedAtMs: tMs));
        }
      } else {
        final cloudWords = (data['words'] as List<dynamic>?)?.cast<String>() ?? [];
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        for (final w in cloudWords) {
          _entries.putIfAbsent(w, () => _PersonalEntry(addedAtMs: nowMs));
        }
      }

      if (_entries.length > before) {
        debugPrint('[PersonalDict] Merged ${_entries.length - before} new words from cloud');
        await _saveToDisk();
      }
    } catch (e) {
      debugPrint('[PersonalDict] Cloud pull error: $e');
    }
  }

  /// Force a cloud sync (e.g. on app background).
  Future<void> syncNow() async {
    await _saveToDisk();
    await _pushToCloud();
  }

  void dispose() {
    _saveTimer?.cancel();
  }
}
