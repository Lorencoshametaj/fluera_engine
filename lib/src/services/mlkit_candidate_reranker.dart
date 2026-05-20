// ============================================================================
// 🎯 ML Kit Candidate Reranker — Dictionary-based re-rank for top-N output
//
// ML Kit Digital Ink returns up to N candidates ranked best-first by its own
// language model. The top candidate is correct most of the time, but mid-list
// candidates often contain the right answer when handwriting is stylized,
// contains accents, or has tight letter spacing.
//
// Two-stage quality pipeline:
//
//   1️⃣ Re-rank by dictionary coverage
//      • Score = (Σ length-weighted dict hits + personal-vocab boost)
//                / (# eligible words)
//      • Pick the highest-scoring candidate; ties → ML Kit's order
//      • Restores most of the per-word JIIX re-rank quality we lost
//        when removing MyScript (2026-05-19), cross-language by default
//
//   2️⃣ Fuzzy per-word correction (when re-rank result is still poor)
//      • Walks each word in the chosen candidate
//      • For out-of-dict words, asks the dictionary for the closest
//        suggestion within bounded edit distance
//      • Preserves original casing pattern
//      • Triggered only when score < fuzzyThreshold (default 0.5) —
//        avoids over-correcting cases where ML Kit already got most
//        words right
//
// Dictionary backing (Stage 2, 2026-05-19): delegates to the shared
// `WordCompletionDictionary` singleton — no parallel asset load, no second
// in-RAM Set<String>. Saves ~500 KB and a startup I/O for the EN dict.
//
// Personal vocab support: callers can pass a `personalVocab` set (e.g.,
// terms the student has previously written + accepted across canvases).
// Personal-vocab hits are weighted higher than baseline dict hits so the
// reranker actively prefers candidates matching the user's domain
// (medicina / legge / specific field vocabulary). When [personalVocab] is
// null the reranker reads from [PersonalDictionaryService.instance].
// ============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'ink_recognition_engine.dart' show InkCandidate;
import 'personal_dictionary_service.dart';
import 'word_completion_dictionary.dart';

class MlKitCandidateReranker {
  MlKitCandidateReranker._();

  /// Languages with a bundled dictionary asset. Kept as a public API so
  /// callers can skip the rerank machinery when no improvement is possible
  /// (e.g., niche scripts not yet shipped).
  static const Set<String> supportedLanguages = {
    'ar', 'bg', 'bn', 'ca', 'cs', 'da', 'de', 'el', 'en', 'es', 'et', 'fa',
    'fi', 'fr', 'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'ko', 'lt', 'lv',
    'mr', 'ms', 'nl', 'no', 'pl', 'pt', 'ro', 'ru', 'sk', 'sl', 'sv', 'sw',
    'ta', 'te', 'th', 'tl', 'tr', 'uk', 'ur', 'vi', 'zh',
  };

  /// Default threshold under which fuzzy per-word correction kicks in.
  /// Empirically: candidates with <50% dict coverage are likely garbage
  /// whose words individually need correction (e.g., "ciamo modno"); above
  /// 50% the candidate is "mostly right" and we trust the dictionary
  /// re-rank pick as-is.
  static const double defaultFuzzyThreshold = 0.5;

  // ──────────────────────────────────────────────────────────────────────────
  // Stage 1 — Dictionary re-rank
  // ──────────────────────────────────────────────────────────────────────────

  /// Backwards-compatible entry point (no fuzzy correction, no personal vocab).
  /// Equivalent to `pickWithFuzzy(..., applyFuzzy: false)`.
  static Future<String?> pickByDictionary(
    List<InkCandidate> candidates, {
    required String langCode,
  }) {
    return pickWithFuzzy(
      candidates,
      langCode: langCode,
      applyFuzzy: false,
    );
  }

  /// Full pipeline: re-rank by dictionary, then optionally apply per-word
  /// fuzzy correction.
  ///
  /// Always returns the top-quality string the pipeline can produce.
  /// Returns `null` only when [candidates] is empty.
  ///
  /// Parameters:
  ///   • [langCode] — BCP-47 language tag. Switches the shared
  ///     dictionary's active language for the duration of the call.
  ///   • [personalVocab] — optional set of user-specific terms; hits
  ///     get a 1.5× weight in scoring. Defaults to the persistent
  ///     [PersonalDictionaryService] set when null.
  ///   • [applyFuzzy] — enable stage 2 fuzzy correction.
  ///   • [fuzzyThreshold] — score below which fuzzy correction fires.
  static Future<String?> pickWithFuzzy(
    List<InkCandidate> candidates, {
    required String langCode,
    Set<String>? personalVocab,
    bool applyFuzzy = true,
    double fuzzyThreshold = defaultFuzzyThreshold,
  }) async {
    if (candidates.isEmpty) return null;
    final fallback = candidates.first.text;
    if (candidates.length == 1 && !applyFuzzy) return fallback;

    final dict = WordCompletionDictionary.instance;
    dict.setLanguageFromCode(langCode);
    final personal = personalVocab ?? PersonalDictionaryService.instance.words;

    // Stage 1: pick highest-scoring candidate, with personal vocab boost
    // and length-weighted dict hits. Ties go to ML Kit's order.
    double bestScore = _scoreCandidate(fallback, dict, personal);
    String bestText = fallback;
    for (var i = 1; i < candidates.length; i++) {
      final text = candidates[i].text;
      if (text.isEmpty) continue;
      final score = _scoreCandidate(text, dict, personal);
      if (score > bestScore) {
        bestScore = score;
        bestText = text;
      }
    }

    if (bestText != fallback) {
      debugPrint(
        '[MlKitRerank] "$fallback" → "$bestText" '
        '(lang=$langCode, score ${bestScore.toStringAsFixed(2)})',
      );
    }

    // Stage 2: if the best candidate is still mostly out-of-dict,
    // attempt per-word fuzzy correction.
    if (applyFuzzy && bestScore < fuzzyThreshold) {
      final corrected = _correctPerWord(bestText, dict, personal);
      if (corrected != bestText) {
        debugPrint(
          '[MlKitRerank.fuzzy] "$bestText" → "$corrected" '
          '(lang=$langCode, pre-score ${bestScore.toStringAsFixed(2)})',
        );
        return corrected;
      }
    }
    return bestText;
  }

  /// Length-weighted scoring:
  ///   • short dict hits (3 chars) weigh 1.0
  ///   • medium hits (6 chars) weigh ~1.4
  ///   • long hits (10+ chars) weigh 2.0 (capped)
  /// Personal vocab matches weigh 1.5× the equivalent length weight.
  ///
  /// Rationale: longer recognised words carry more confidence because
  /// random chance of a long-word collision is low. A 3-letter dict hit
  /// like "che" or "the" can be coincidental; a 10-letter hit like
  /// "biologia" is almost certainly correct.
  static double _scoreCandidate(
    String text,
    WordCompletionDictionary dict,
    Set<String> personalVocab,
  ) {
    if (text.isEmpty) return 0.0;
    final words = text.split(RegExp(r'\s+'));
    double weightedHits = 0.0;
    int eligible = 0;
    for (final w in words) {
      if (w.length < 3) continue;
      if (RegExp(r'[0-9\\$_^{}=+]').hasMatch(w)) continue;
      eligible++;
      final lower = w.toLowerCase();
      final lengthWeight = _lengthWeight(lower.length);
      if (dict.isValidWord(lower)) {
        weightedHits += lengthWeight;
      } else if (personalVocab.contains(lower)) {
        weightedHits += lengthWeight * 1.5; // boost user-specific terms
      }
    }
    if (eligible == 0) return 0.0;
    return weightedHits / eligible;
  }

  /// 3 chars → 1.0; 6 chars → 1.4; 10+ chars → 2.0 (clamped).
  static double _lengthWeight(int len) {
    if (len <= 3) return 1.0;
    return math.min(2.0, 1.0 + (len - 3) * 0.14);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Stage 2 — Per-word fuzzy correction (delegated to the dict's
  // bounded suggestCorrections — same Damerau-Levenshtein ≤2 algorithm,
  // but using the Trie for early termination instead of scanning a flat set).
  // ──────────────────────────────────────────────────────────────────────────

  static String _correctPerWord(
    String text,
    WordCompletionDictionary dict,
    Set<String> personalVocab,
  ) {
    final words = text.split(RegExp(r'\s+'));
    final fixed = <String>[];
    for (final w in words) {
      if (w.length < 4) {
        // Very short words are unsafe to fuzzy-correct (too many
        // close neighbours; risk of replacing valid short tokens).
        fixed.add(w);
        continue;
      }
      if (RegExp(r'[0-9\\$_^{}=+]').hasMatch(w)) {
        fixed.add(w);
        continue;
      }
      final lower = w.toLowerCase();
      if (dict.isValidWord(lower) || personalVocab.contains(lower)) {
        fixed.add(w);
        continue;
      }
      // Out of dict — ask for the single best dict match within distance ≤2.
      final suggestions = dict.suggestCorrections(lower, maxResults: 1);
      if (suggestions.isEmpty) {
        fixed.add(w);
      } else {
        fixed.add(_preserveCasing(w, suggestions.first));
      }
    }
    return fixed.join(' ');
  }

  /// Apply the casing pattern of [original] to [correction].
  ///   ALL-CAPS source → all caps correction
  ///   Capitalised source → capitalised correction
  ///   lower / mixed → unchanged correction
  static String _preserveCasing(String original, String correction) {
    if (original.isEmpty || correction.isEmpty) return correction;
    if (original == original.toUpperCase()) return correction.toUpperCase();
    final firstCh = original.substring(0, 1);
    if (firstCh == firstCh.toUpperCase() && firstCh != firstCh.toLowerCase()) {
      return correction.substring(0, 1).toUpperCase() + correction.substring(1);
    }
    return correction;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Test hooks
  // ──────────────────────────────────────────────────────────────────────────

  /// Reset the shared dictionary's test seed. Pair with [setUp].
  @visibleForTesting
  static void resetForTesting() {
    // ignore: invalid_use_of_visible_for_testing_member
    WordCompletionDictionary.instance.resetForTesting();
  }

  /// Seed the shared dictionary with a hermetic word set for the given
  /// language. Replaces the old per-reranker cache seed.
  @visibleForTesting
  static void seedDictionaryForTesting(String langCode, Set<String> words) {
    // ignore: invalid_use_of_visible_for_testing_member
    WordCompletionDictionary.instance.seedForTesting(
      langCode: langCode,
      words: words,
    );
  }
}
