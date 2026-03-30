import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'word_completion_dictionary.dart';
import 'language_detection_service.dart';

// =============================================================================
// 📖 DICTIONARY LOOKUP SERVICE — Word definitions, synonyms, examples
//
// Adapter-pattern service for looking up word definitions.
// Default: Free Dictionary API (no API key required).
// Supports: EN, IT, ES, FR, DE, PT, NL, TR, RU, AR.
// =============================================================================

// ── Models ───────────────────────────────────────────────────────────────

/// A single definition of a word.
class WordDefinition {
  final String partOfSpeech; // noun, verb, adjective, etc.
  final String definition;
  final String? example;
  final List<String> synonyms;
  final List<String> antonyms;

  const WordDefinition({
    required this.partOfSpeech,
    required this.definition,
    this.example,
    this.synonyms = const [],
    this.antonyms = const [],
  });

  Map<String, dynamic> toJson() => {
    'pos': partOfSpeech,
    'def': definition,
    if (example != null) 'ex': example,
    if (synonyms.isNotEmpty) 'syn': synonyms,
    if (antonyms.isNotEmpty) 'ant': antonyms,
  };

  factory WordDefinition.fromJson(Map<String, dynamic> j) => WordDefinition(
    partOfSpeech: j['pos'] as String? ?? 'other',
    definition: j['def'] as String? ?? '',
    example: j['ex'] as String?,
    synonyms: (j['syn'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    antonyms: (j['ant'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
  );
}

/// Complete lookup result for a word.
class DictionaryLookupResult {
  final String word;
  final String? phonetic; // IPA pronunciation
  final String? audioUrl; // Pronunciation audio URL
  final List<WordDefinition> definitions;
  final String? origin; // Etymology
  final String languageCode; // Source language

  const DictionaryLookupResult({
    required this.word,
    this.phonetic,
    this.audioUrl,
    required this.definitions,
    this.origin,
    required this.languageCode,
  });

  bool get hasDefinitions => definitions.isNotEmpty;

  /// Get all unique synonyms across all definitions.
  List<String> get allSynonyms {
    final syns = <String>{};
    for (final d in definitions) {
      syns.addAll(d.synonyms);
    }
    return syns.toList();
  }

  /// Get all unique antonyms across all definitions.
  List<String> get allAntonyms {
    final ants = <String>{};
    for (final d in definitions) {
      ants.addAll(d.antonyms);
    }
    return ants.toList();
  }

  Map<String, dynamic> toJson() => {
    'w': word,
    if (phonetic != null) 'ph': phonetic,
    if (audioUrl != null) 'au': audioUrl,
    'd': definitions.map((d) => d.toJson()).toList(),
    if (origin != null) 'or': origin,
    'l': languageCode,
  };

  factory DictionaryLookupResult.fromJson(Map<String, dynamic> j) {
    return DictionaryLookupResult(
      word: j['w'] as String? ?? '',
      phonetic: j['ph'] as String?,
      audioUrl: j['au'] as String?,
      definitions: (j['d'] as List<dynamic>?)
          ?.map((e) => WordDefinition.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      origin: j['or'] as String?,
      languageCode: j['l'] as String? ?? 'en',
    );
  }
}

// ── Adapter Interface ────────────────────────────────────────────────────

/// Abstract adapter for dictionary lookup providers.
/// Implement this to use a different dictionary API.
abstract class DictionaryLookupAdapter {
  /// Look up a word in the given language.
  /// Returns null if not found or error.
  Future<DictionaryLookupResult?> lookUp(String word, String languageCode);

  /// Whether this adapter supports the given language.
  bool supportsLanguage(String languageCode);
}

// ── Free Dictionary API Adapter ──────────────────────────────────────────

/// Concrete adapter using the Free Dictionary API.
/// https://dictionaryapi.dev — Free, no API key required.
class FreeDictionaryAdapter implements DictionaryLookupAdapter {
  static const _baseUrl = 'https://api.dictionaryapi.dev/api/v2/entries';

  /// Languages supported by the Free Dictionary API.
  static const _supportedLanguages = {
    'en', 'es', 'fr', 'de', 'it', 'pt', 'nl', 'tr', 'ru', 'ar',
    'hi', 'ja', 'ko', 'zh',
  };

  @override
  bool supportsLanguage(String languageCode) {
    return _supportedLanguages.contains(languageCode.toLowerCase());
  }

  @override
  Future<DictionaryLookupResult?> lookUp(
    String word,
    String languageCode,
  ) async {
    final lang = languageCode.toLowerCase();
    if (!supportsLanguage(lang)) return null;

    try {
      final uri = Uri.parse('$_baseUrl/$lang/${Uri.encodeComponent(word)}');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode != 200) return null;

      final List<dynamic> data = json.decode(response.body);
      if (data.isEmpty) return null;

      return _parseResponse(data.first as Map<String, dynamic>, lang);
    } catch (e) {
      debugPrint('[DictionaryLookup] Error: $e');
      return null;
    }
  }

  DictionaryLookupResult _parseResponse(
    Map<String, dynamic> entry,
    String languageCode,
  ) {
    final word = entry['word'] as String? ?? '';

    // Phonetic
    String? phonetic;
    String? audioUrl;
    final phonetics = entry['phonetics'] as List<dynamic>?;
    if (phonetics != null && phonetics.isNotEmpty) {
      for (final p in phonetics) {
        final m = p as Map<String, dynamic>;
        phonetic ??= m['text'] as String?;
        final audio = m['audio'] as String?;
        if (audio != null && audio.isNotEmpty) {
          audioUrl = audio;
          phonetic = m['text'] as String? ?? phonetic;
          break;
        }
      }
    }
    phonetic ??= entry['phonetic'] as String?;

    // Definitions
    final definitions = <WordDefinition>[];
    final meanings = entry['meanings'] as List<dynamic>?;
    if (meanings != null) {
      for (final meaning in meanings) {
        final m = meaning as Map<String, dynamic>;
        final pos = m['partOfSpeech'] as String? ?? 'other';
        final meaningSynonyms = (m['synonyms'] as List<dynamic>?)
            ?.map((s) => s.toString())
            .toList() ?? [];
        final meaningAntonyms = (m['antonyms'] as List<dynamic>?)
            ?.map((s) => s.toString())
            .toList() ?? [];

        final defs = m['definitions'] as List<dynamic>?;
        if (defs != null) {
          for (final def in defs) {
            final d = def as Map<String, dynamic>;
            final defSynonyms = (d['synonyms'] as List<dynamic>?)
                ?.map((s) => s.toString())
                .toList() ?? [];
            final defAntonyms = (d['antonyms'] as List<dynamic>?)
                ?.map((s) => s.toString())
                .toList() ?? [];

            definitions.add(WordDefinition(
              partOfSpeech: pos,
              definition: d['definition'] as String? ?? '',
              example: d['example'] as String?,
              synonyms: {...meaningSynonyms, ...defSynonyms}.toList(),
              antonyms: {...meaningAntonyms, ...defAntonyms}.toList(),
            ));
          }
        }
      }
    }

    return DictionaryLookupResult(
      word: word,
      phonetic: phonetic,
      audioUrl: audioUrl,
      definitions: definitions,
      origin: entry['origin'] as String?,
      languageCode: languageCode,
    );
  }
}

// ── Service (Singleton) ──────────────────────────────────────────────────

class DictionaryLookupService {
  DictionaryLookupService._();
  static final DictionaryLookupService instance = DictionaryLookupService._();

  /// The active adapter. Default: Free Dictionary API.
  DictionaryLookupAdapter _adapter = FreeDictionaryAdapter();

  /// Swap the adapter (e.g. for premium/offline dictionaries).
  void setAdapter(DictionaryLookupAdapter adapter) {
    _adapter = adapter;
  }

  // ── In-Memory Cache ────────────────────────────────────────────────────
  final Map<String, DictionaryLookupResult?> _cache = {};
  static const int _maxMemCacheSize = 64;

  void clearCache() {
    _cache.clear();
  }

  // ── Persistent Disk Cache ──────────────────────────────────────────────
  Map<String, dynamic>? _diskCache;
  bool _diskCacheLoaded = false;
  static const int _maxDiskCacheSize = 500;
  static const String _cacheFileName = 'dictionary_cache.json';

  /// Load the disk cache from the app documents directory.
  Future<void> _ensureDiskCacheLoaded() async {
    if (_diskCacheLoaded) return;
    _diskCacheLoaded = true;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');
      if (await file.exists()) {
        final str = await file.readAsString();
        _diskCache = json.decode(str) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[DictionaryCache] Load error: $e');
    }
    _diskCache ??= {};
  }

  /// Persist a result to disk.
  Future<void> _saveToDisk(String key, DictionaryLookupResult result) async {
    try {
      await _ensureDiskCacheLoaded();

      // Evict oldest entries if exceeding max size
      while (_diskCache!.length >= _maxDiskCacheSize) {
        _diskCache!.remove(_diskCache!.keys.first);
      }

      _diskCache![key] = result.toJson();

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');
      await file.writeAsString(json.encode(_diskCache));
    } catch (e) {
      debugPrint('[DictionaryCache] Save error: $e');
    }
  }

  /// Read a result from disk cache.
  Future<DictionaryLookupResult?> _readFromDisk(String key) async {
    await _ensureDiskCacheLoaded();
    final data = _diskCache?[key];
    if (data == null) return null;

    try {
      return DictionaryLookupResult.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[DictionaryCache] Parse error: $e');
      return null;
    }
  }

  /// Get the number of cached definitions on disk.
  Future<int> get diskCacheSize async {
    await _ensureDiskCacheLoaded();
    return _diskCache?.length ?? 0;
  }

  /// Clear the persistent disk cache.
  Future<void> clearDiskCache() async {
    _diskCache = {};
    _diskCacheLoaded = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ── Public API ─────────────────────────────────────────────────────────

  /// Look up a word, auto-detecting language.
  /// Checks: memory cache → disk cache → API (with disk save).
  Future<DictionaryLookupResult?> lookUp(String word) async {
    final lower = word.toLowerCase().trim();
    if (lower.isEmpty) return null;

    // 1. Check memory cache
    if (_cache.containsKey(lower)) return _cache[lower];

    // 2. Check disk cache
    final diskResult = await _readFromDisk(lower);
    if (diskResult != null) {
      _cache[lower] = diskResult; // Promote to memory
      return diskResult;
    }

    // 3. Detect language & call API
    final lang = LanguageDetectionService.instance.detectWordLanguage(word);
    final langCode = lang.name;

    DictionaryLookupResult? result;
    if (_adapter.supportsLanguage(langCode)) {
      result = await _adapter.lookUp(lower, langCode);
    }

    // Fallback: try English if not found in detected language
    if (result == null && langCode != 'en' && _adapter.supportsLanguage('en')) {
      result = await _adapter.lookUp(lower, 'en');
    }

    // 4. Cache in memory
    if (_cache.length >= _maxMemCacheSize) _cache.remove(_cache.keys.first);
    _cache[lower] = result;

    // 5. Persist to disk (only successful results)
    if (result != null) {
      unawaited(_saveToDisk(lower, result));
    }

    return result;
  }

  /// Look up with explicit language.
  Future<DictionaryLookupResult?> lookUpInLanguage(
    String word,
    String languageCode,
  ) async {
    final lower = word.toLowerCase().trim();
    final key = '$languageCode:$lower';

    // Memory
    if (_cache.containsKey(key)) return _cache[key];

    // Disk
    final diskResult = await _readFromDisk(key);
    if (diskResult != null) {
      _cache[key] = diskResult;
      return diskResult;
    }

    // API
    final result = await _adapter.lookUp(lower, languageCode);

    if (_cache.length >= _maxMemCacheSize) _cache.remove(_cache.keys.first);
    _cache[key] = result;

    if (result != null) {
      unawaited(_saveToDisk(key, result));
    }

    return result;
  }

  /// Check if the adapter supports a language.
  bool supportsLanguage(String languageCode) {
    return _adapter.supportsLanguage(languageCode);
  }
}
