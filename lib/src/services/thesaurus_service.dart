import 'package:flutter/services.dart';

// =============================================================================
// 📖 OFFLINE THESAURUS SERVICE — Synonym lookup without network
//
// Loads thesaurus data from assets/thesaurus/{lang}.txt
// Format: word|syn1,syn2,syn3,...
// Lazy-loaded per language, sorted for binary search.
// Tier 1: EN, IT, FR, ES, DE, PT, NL
// =============================================================================

class ThesaurusService {
  ThesaurusService._();
  static final ThesaurusService instance = ThesaurusService._();

  /// Supported languages.
  static const supportedLanguages = {'en', 'it', 'fr', 'es', 'de', 'pt', 'nl'};

  /// Cache: lang → {word → synonyms}
  final Map<String, Map<String, List<String>>> _cache = {};

  /// Whether a language is loaded.
  bool isLoaded(String langCode) => _cache.containsKey(langCode);

  /// Check if language is supported.
  bool supportsLanguage(String langCode) =>
      supportedLanguages.contains(langCode);

  /// Look up synonyms for a word (offline, instant).
  /// Returns empty list if not found.
  Future<List<String>> lookUp(String word, String languageCode) async {
    final lang = languageCode.toLowerCase();
    if (!supportsLanguage(lang)) return [];

    // Lazy load
    if (!_cache.containsKey(lang)) {
      await _loadLanguage(lang);
    }

    final dict = _cache[lang];
    if (dict == null) return [];

    return dict[word.toLowerCase()] ?? [];
  }

  /// Synchronous lookup (only works if language is already loaded).
  List<String> lookUpSync(String word, String languageCode) {
    final dict = _cache[languageCode.toLowerCase()];
    if (dict == null) return [];
    return dict[word.toLowerCase()] ?? [];
  }

  /// Preload a language into memory.
  Future<void> preload(String languageCode) async {
    if (!_cache.containsKey(languageCode)) {
      await _loadLanguage(languageCode);
    }
  }

  /// Load thesaurus file for a language.
  Future<void> _loadLanguage(String langCode) async {
    try {
      final data = await rootBundle.loadString(
        'packages/fluera_engine/assets/thesaurus/$langCode.txt',
      );
      final dict = <String, List<String>>{};
      for (final line in data.split('\n')) {
        if (line.isEmpty) continue;
        final pipe = line.indexOf('|');
        if (pipe < 0) continue;
        final word = line.substring(0, pipe).trim().toLowerCase();
        final syns = line
            .substring(pipe + 1)
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (word.isNotEmpty && syns.isNotEmpty) {
          dict[word] = syns;
        }
      }
      _cache[langCode] = dict;
    } catch (_) {
      // Asset not found — mark as loaded but empty
      _cache[langCode] = {};
    }
  }

  /// Number of entries for a loaded language.
  int entryCount(String langCode) => _cache[langCode]?.length ?? 0;

  /// Clear cache (for testing).
  void clearCache() => _cache.clear();
}
