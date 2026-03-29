import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/safe_path_provider.dart';
import '../storage/fluera_cloud_adapter.dart';

// =============================================================================
// 📚 PERSONAL DICTIONARY SERVICE — User-specific words with cloud sync
//
// Stores words the user adds (ignored spellcheck words, custom vocabulary).
// Persists locally to JSON and syncs via FlueraCloudStorageAdapter.
// =============================================================================

class PersonalDictionaryService {
  PersonalDictionaryService._();
  static final PersonalDictionaryService instance = PersonalDictionaryService._();

  /// All personal words (lowercase).
  final Set<String> _words = {};

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
  bool contains(String word) => _words.contains(word.toLowerCase());

  /// Number of words in the dictionary.
  int get wordCount => _words.length;

  /// All words (read-only).
  Set<String> get words => Set.unmodifiable(_words);

  /// Add a word to the personal dictionary.
  void addWord(String word) {
    final lower = word.toLowerCase().trim();
    if (lower.length < 2 || _words.contains(lower)) return;

    _words.add(lower);
    debugPrint('[PersonalDict] Added "$lower" (${_words.length} total)');
    _scheduleSave();
  }

  /// Remove a word from the personal dictionary.
  void removeWord(String word) {
    final lower = word.toLowerCase().trim();
    if (_words.remove(lower)) {
      debugPrint('[PersonalDict] Removed "$lower"');
      _scheduleSave();
    }
  }

  /// Clear all words.
  void clear() {
    _words.clear();
    _scheduleSave();
  }

  // ── Initialization ─────────────────────────────────────────────────────

  /// Initialize the service. Call once at app start.
  Future<void> initialize() async {
    if (_loaded) return;
    await _loadFromDisk();
    _loaded = true;
    debugPrint('[PersonalDict] Loaded ${_words.length} words from disk');
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
      final List<dynamic> list = jsonDecode(content) as List<dynamic>;
      _words.addAll(list.cast<String>());
    } catch (e) {
      debugPrint('[PersonalDict] Load error: $e');
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _localFile;
      if (file == null) return;
      await file.writeAsString(jsonEncode(_words.toList()));
    } catch (e) {
      debugPrint('[PersonalDict] Save error: $e');
    }
  }

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
        'words': _words.toList(),
        'updatedAt': DateTime.now().toIso8601String(),
        'version': 1,
      });
      debugPrint('[PersonalDict] Pushed ${_words.length} words to cloud');
    } catch (e) {
      debugPrint('[PersonalDict] Cloud push error: $e');
    }
  }

  Future<void> _pullFromCloud() async {
    if (_cloudAdapter == null || _userId == null) return;
    try {
      final data = await _cloudAdapter!.loadCanvas('$_cloudKey$_userId');
      if (data == null) return;

      final cloudWords = (data['words'] as List<dynamic>?)?.cast<String>() ?? [];
      final before = _words.length;
      _words.addAll(cloudWords); // Merge: union of local + cloud
      if (_words.length > before) {
        debugPrint('[PersonalDict] Merged ${_words.length - before} new words from cloud');
        await _saveToDisk(); // Persist merged result
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
