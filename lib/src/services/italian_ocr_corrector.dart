// ============================================================================
// 🇮🇹 ITALIAN OCR CORRECTOR — Dictionary-based re-rank for MyScript candidates.
//
// MyScript's text editor surfaces per-word alternatives (`words[].candidates`)
// when OCR confidence is low. The top candidate isn't always the correct
// word in Italian (the engine uses a generic Latin model — `mul_Latn_hybrid`
// — not Italian-specific). We re-rank: for each word, if the top candidate
// is NOT in the Italian dictionary but a lower-ranked candidate IS, we
// promote the dictionary hit.
//
// This is a SAFETY-FIRST corrector — when in doubt, it returns the original
// candidate. Specifically:
//   • If the top candidate is already in the dictionary → preserved
//     (no overcorrection of correctly-recognised words).
//   • If NO candidate is in the dictionary → preserved (proper nouns,
//     technical terms, foreign words are left alone).
//   • Only when top is OUT but a lower candidate is IN do we swap.
//
// The dictionary is loaded lazily and cached in memory for the lifetime of
// the Isolate. Lookup is O(1) via [HashSet]; ~25k entries occupy ~500 KB.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class ItalianOcrCorrector {
  ItalianOcrCorrector._();

  /// Loaded asynchronously on first call; cached for the rest of the
  /// session. `null` until [_loadDictionary] resolves.
  static Set<String>? _dictionary;
  static Future<Set<String>>? _loadingFuture;

  /// Path of the dictionary asset bundled with `fluera_engine`.
  static const String _assetPath =
      'packages/fluera_engine/assets/dictionaries/it.txt';

  /// Load the Italian word list lazily. Returns the cached set on
  /// subsequent calls. Empty set on load failure (defensive — better
  /// to skip correction than crash).
  static Future<Set<String>> _loadDictionary() {
    final cached = _dictionary;
    if (cached != null) return Future.value(cached);
    return _loadingFuture ??= () async {
      try {
        final raw = await rootBundle.loadString(_assetPath);
        final words = raw
            .split('\n')
            .map((w) => w.trim().toLowerCase())
            .where((w) => w.isNotEmpty)
            .toSet();
        _dictionary = words;
        debugPrint('🇮🇹 ItalianOcrCorrector: loaded ${words.length} words');
        return words;
      } catch (e) {
        debugPrint('🇮🇹 ItalianOcrCorrector: load error: $e');
        _dictionary = const {};
        return _dictionary!;
      } finally {
        _loadingFuture = null;
      }
    }();
  }

  /// Re-rank a single word's [candidates] against the Italian
  /// dictionary. The first element of [candidates] is the engine's
  /// top pick; subsequent elements are alternatives (best-first).
  ///
  /// Returns the corrected word, or the input top candidate when no
  /// swap is warranted (already in dict / no dict hit / empty input).
  ///
  /// Case-insensitive lookup; preserves the original casing of the
  /// chosen candidate (so "Newton" stays "Newton" if it's the dict hit).
  static Future<String> bestMatch(List<String> candidates) async {
    if (candidates.isEmpty) return '';
    final top = candidates.first;
    if (top.isEmpty) return top;

    // Skip very short words — too risky to correct (e.g. "io" / "è"
    // are valid but might match longer dictionary entries by accident).
    if (top.length < 3) return top;

    // Skip words with digits, punctuation, or LaTeX residue — proper
    // nouns / formulas / mixed content shouldn't be re-ranked.
    if (RegExp(r'[0-9\\\$_^{}=+]').hasMatch(top)) return top;

    final dict = await _loadDictionary();
    if (dict.isEmpty) return top; // load failed — pass-through

    final topLower = top.toLowerCase();
    if (dict.contains(topLower)) return top; // already correct

    // Top is NOT in dict → walk alternatives.
    for (var i = 1; i < candidates.length; i++) {
      final alt = candidates[i];
      if (alt.isEmpty) continue;
      if (alt.length < 3) continue;
      if (RegExp(r'[0-9\\\$_^{}=+]').hasMatch(alt)) continue;
      final altLower = alt.toLowerCase();
      if (dict.contains(altLower)) {
        debugPrint('🇮🇹 OCR re-rank: "$top" → "$alt"');
        return alt;
      }
    }
    return top; // no alternative is in dict either — keep original
  }

  /// Re-rank an entire text using per-word [wordCandidates] from
  /// MyScript's JIIX. The output preserves the original text when the
  /// candidates list is empty or shorter than expected — defensive
  /// fallback for content where the engine didn't surface alternatives.
  ///
  /// Joins corrected words with spaces (matches MyScript's tokenisation
  /// for prose; punctuation tokens are skipped at the native layer).
  static Future<String> correctText(
    String original,
    List<List<String>> wordCandidates,
  ) async {
    if (wordCandidates.isEmpty) return original;
    final out = <String>[];
    for (final cands in wordCandidates) {
      if (cands.isEmpty) continue;
      out.add(await bestMatch(cands));
    }
    if (out.isEmpty) return original;
    return out.join(' ');
  }

  /// Force-load (or pre-warm) the dictionary. Useful at app boot to
  /// avoid a first-call latency spike. No-op on subsequent calls.
  static Future<void> warmUp() => _loadDictionary().then((_) {});

  /// Test hook — reset the loaded cache so unit tests can stub the
  /// asset bundle. Production code should never call this.
  @visibleForTesting
  static void resetForTesting() {
    _dictionary = null;
    _loadingFuture = null;
  }

  /// Test hook — inject a dictionary directly without going through
  /// the asset bundle.
  @visibleForTesting
  static void seedForTesting(Set<String> words) {
    _dictionary = words;
  }
}
