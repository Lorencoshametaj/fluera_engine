import 'dart:async';
import 'package:flutter/foundation.dart';
import 'word_completion_dictionary.dart';
import 'personal_dictionary_service.dart';
import 'language_detection_service.dart';

// =============================================================================
// 🔍 SPELLCHECK SERVICE — Real-time text validation using Trie dictionary
//
// Validates words from DigitalTextElement.plainText against the current
// language dictionary. Caches results per text string.
// =============================================================================

/// A single spellcheck error with position and corrections.
class SpellcheckError {
  final String word;
  final int startIndex;
  final int endIndex;
  final List<String> suggestions;

  const SpellcheckError({
    required this.word,
    required this.startIndex,
    required this.endIndex,
    required this.suggestions,
  });

  @override
  String toString() => 'SpellcheckError("$word" [$startIndex:$endIndex])';
}

/// Result of checking a full text.
class SpellcheckResult {
  final String text;
  final List<SpellcheckError> errors;

  const SpellcheckResult({required this.text, required this.errors});

  bool get hasErrors => errors.isNotEmpty;
}

class SpellcheckService {
  SpellcheckService._();
  static final SpellcheckService instance = SpellcheckService._();

  /// Whether spellcheck is enabled.
  bool _enabled = true;
  bool get enabled => _enabled;
  void setEnabled(bool value) => _enabled = value;

  /// Words the user chose to ignore (session-scoped).
  final Set<String> _ignoredWords = {};

  /// Cache: text → result (invalidated on language change).
  final Map<String, SpellcheckResult> _cache = {};
  DictLanguage? _cachedLanguage;
  static const int _maxCacheSize = 32;

  /// Auto-trigger: debounce timer for running spellcheck after edits.
  Timer? _autoTriggerTimer;
  VoidCallback? _onAutoTrigger;

  /// Register a callback for auto-triggered spellcheck.
  void setAutoTriggerCallback(VoidCallback callback) {
    _onAutoTrigger = callback;
  }

  /// Schedule an auto-triggered spellcheck (debounced 500ms).
  void scheduleCheck() {
    if (!_enabled) return;
    _autoTriggerTimer?.cancel();
    _autoTriggerTimer = Timer(const Duration(milliseconds: 500), () {
      _onAutoTrigger?.call();
    });
  }

  /// 🔍 Check a text string for spelling errors.
  SpellcheckResult checkText(String text) {
    if (!_enabled || text.isEmpty) {
      return SpellcheckResult(text: text, errors: []);
    }

    // Invalidate cache on language change
    final currentLang = WordCompletionDictionary.instance.language;
    if (_cachedLanguage != currentLang) {
      _cache.clear();
      _cachedLanguage = currentLang;
    }

    // Check cache
    final cached = _cache[text];
    if (cached != null) return cached;

    // Split text into words with position tracking
    final errors = <SpellcheckError>[];
    final wordPattern = RegExp(r"[\w\u0080-\uFFFF]+(?:'[\w\u0080-\uFFFF]+)?");

    for (final match in wordPattern.allMatches(text)) {
      final word = match.group(0)!;

      // Skip rules:
      if (word.length < 2) continue;                           // Single chars
      if (_isNumeric(word)) continue;                          // Numbers
      if (_isAllCaps(word) && word.length <= 5) continue;      // Acronyms
      if (_ignoredWords.contains(word.toLowerCase())) continue; // Ignored
      if (PersonalDictionaryService.instance.contains(word)) continue; // Personal dict

      // Validate against dictionary
      if (!WordCompletionDictionary.instance.isValidWord(word)) {
        final suggestions = WordCompletionDictionary.instance
            .suggestCorrections(word, maxResults: 3);
        errors.add(SpellcheckError(
          word: word,
          startIndex: match.start,
          endIndex: match.end,
          suggestions: suggestions,
        ));
      }
    }

    final result = SpellcheckResult(text: text, errors: errors);

    // LRU cache
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[text] = result;

    return result;
  }

  /// 🌍 Multi-language spellcheck: detects language per sentence.
  /// Returns errors with correct language validation per segment.
  SpellcheckResult checkTextMultiLang(String text) {
    if (!_enabled || text.isEmpty) {
      return SpellcheckResult(text: text, errors: []);
    }

    final segments = LanguageDetectionService.instance.detectSegments(text);
    if (segments.length <= 1) {
      // Single language — use standard path
      return checkText(text);
    }

    final errors = <SpellcheckError>[];
    final dict = WordCompletionDictionary.instance;
    final wordPattern = RegExp(r"[\w\u0080-\uFFFF]+(?:'[\w\u0080-\uFFFF]+)?");

    for (final segment in segments) {
      final segText = segment.getText(text);

      for (final match in wordPattern.allMatches(segText)) {
        final word = match.group(0)!;
        final absStart = segment.startIndex + match.start;
        final absEnd = segment.startIndex + match.end;

        // Skip rules
        if (word.length < 2) continue;
        if (_isNumeric(word)) continue;
        if (_isAllCaps(word) && word.length <= 5) continue;
        if (_ignoredWords.contains(word.toLowerCase())) continue;
        if (PersonalDictionaryService.instance.contains(word)) continue;

        // Validate against the segment's detected language dictionary
        if (!dict.isValidWord(word)) {
          // Cross-dictionary validation: check if word is valid elsewhere
          final langService = LanguageDetectionService.instance;
          final crossLang = langService.validateWordAcrossLanguages(word);
          if (crossLang != null) continue; // Valid in another language

          // Check if it's a known foreign word
          if (langService.isLikelyForeignWord(word)) continue;

          // Check loanwords
          if (_isCommonLoanword(word)) continue;

          final suggestions = dict.suggestCorrections(word, maxResults: 3);
          errors.add(SpellcheckError(
            word: word,
            startIndex: absStart,
            endIndex: absEnd,
            suggestions: suggestions,
          ));
        }
      }
    }

    return SpellcheckResult(text: text, errors: errors);
  }

  /// Check if a word is a common loanword (used across many languages).
  bool _isCommonLoanword(String word) {
    return _loanwords.contains(word.toLowerCase());
  }

  static const _loanwords = {
    // Tech terms used in all languages
    'computer', 'software', 'hardware', 'internet', 'email', 'web',
    'smartphone', 'app', 'cloud', 'server', 'browser', 'file',
    'link', 'blog', 'online', 'offline', 'download', 'upload',
    'database', 'startup', 'login', 'password', 'wifi', 'usb',
    // Common English loanwords
    'ok', 'cool', 'weekend', 'sport', 'business', 'marketing',
    'design', 'brand', 'team', 'manager', 'meeting', 'deadline',
    'feedback', 'workshop', 'brainstorming', 'goal', 'budget',
    'stress', 'hobby', 'party', 'baby', 'shopping', 'fitness',
    // Academic terms
    'campus', 'curriculum', 'versus', 'status', 'bonus', 'focus',
    'agenda', 'data', 'media', 'forum', 'index', 'formula',
  };

  /// 🚫 Ignore a word for this session.
  void ignoreWord(String word) {
    _ignoredWords.add(word.toLowerCase());
    _cache.clear(); // Invalidate cache since ignored set changed
    debugPrint('[Spellcheck] Ignored "$word"');
  }

  /// Clear all ignored words.
  void clearIgnored() {
    _ignoredWords.clear();
    _cache.clear();
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  bool _isNumeric(String s) {
    for (int i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) {
        // Also allow decimals and negatives
        if (c != 0x2E && c != 0x2D) return false;
      }
    }
    return true;
  }

  bool _isAllCaps(String s) {
    for (int i = 0; i < s.length; i++) {
      final c = s[i];
      if (c != c.toUpperCase()) return false;
    }
    return true;
  }
}
