import '../../../ai/ai_provider.dart' show detectLanguageSignature;
import 'socratic_model.dart' show SocraticStage, SocraticQuestionType;

/// 🛡️ Sprint 2 — Single source of truth for Socratic question validation.
///
/// Consolidates what used to be three scattered gates in the pipeline:
///   • B4 specificity check (lexical concept-word overlap)
///   • G4 chain-of-verification heuristic (length, interrogative, ?)
///   • Drift detection (target ≠ question language)
///
/// Old architecture:
///   ```
///   Q ─→ B4 (reject? retry?)
///       ─→ G4 (reject? retry?)
///       ─→ Drift detector inside G4
///       ─→ Retry path (B4 retry + G4 retry, two separate paths)
///   ```
///
/// New architecture:
///   ```
///   Q ─→ validator.validate() ─→ accept | retry(reason) | reject(reason)
///   ```
///
/// One class, one outcome, one decision. Caller code is now:
///   ```dart
///   final result = validator.validate(question);
///   if (result.outcome == accept) use as-is;
///   if (result.outcome == retry) retryOnce → revalidate;
///   if (result.outcome == reject) richFallback(stage, topic);
///   ```
///
/// Trust the model semantics + accept gracefully degraded output rather
/// than relentlessly re-validate. See plan file
/// `analizza-tutto-il-fluera-structured-snail.md` Strategic Reset.
class SocraticQuestionValidator {
  final String targetLang; // ISO 639-1 (e.g. 'it', 'en')
  final String clusterTopic;
  final String? clusterRawOcr;
  final SocraticStage stage;
  final SocraticQuestionType type;

  SocraticQuestionValidator({
    required this.targetLang,
    required this.clusterTopic,
    this.clusterRawOcr,
    required this.stage,
    required this.type,
  });

  /// Single-pass validation. Examines:
  ///   1. Empty / too-short → reject
  ///   2. Language drift (qLang != target, both detected) → retry
  ///   3. Cross-language session (source ≠ target OR source unknown +
  ///      question matches target) → accept (semantic trust)
  ///   4. Same-language sessions with no concept overlap:
  ///      • anchor / elaboration / comparative stages → retry
  ///        (these stages have direct concept-mention stems)
  ///      • counterfactual / application / interleave / metacognitive
  ///        stages → accept (these use scenario stems by design)
  ///   5. Generic ceremonial phrasings → reject
  ///   6. Else → accept
  ValidationResult validate(String questionText) {
    final text = questionText.trim();
    if (text.isEmpty) {
      return const ValidationResult(
          ValidationOutcome.reject, reason: 'empty');
    }
    if (text.length < 20) {
      return const ValidationResult(
          ValidationOutcome.reject, reason: 'too_short');
    }

    // Generic ceremonial detector (regex of well-known meaningless openers
    // we've observed in production). Stage-independent.
    if (_isGenericCeremonial(text)) {
      return const ValidationResult(
          ValidationOutcome.reject, reason: 'generic_ceremonial');
    }

    // Language detection.
    final qLang = detectLanguageSignature(text);
    final sourceSample = clusterRawOcr ?? clusterTopic;
    final srcLang = detectLanguageSignature(sourceSample);

    // Step 1 — confident language drift. qLang detected AND ≠ target.
    if (qLang != 'unknown' && qLang != targetLang) {
      return const ValidationResult(
          ValidationOutcome.retry, reason: 'language_drift');
    }

    // Step 2 — cross-language session. Source confidently differs from
    // target OR source unknown + question in target. Accept: lexical
    // overlap is 0 by design; trust the model's semantic match.
    final confidentCrossLang =
        srcLang != 'unknown' && srcLang != targetLang;
    final unknownSourceTargetQ =
        srcLang == 'unknown' && qLang == targetLang;
    if (confidentCrossLang || unknownSourceTargetQ) {
      return const ValidationResult(ValidationOutcome.accept,
          reason: 'cross_language');
    }

    // Step 2b — cross-SCRIPT session. Sprint F.2-post (2026-05-13 PM):
    // function-word signature returns 'unknown' for non-Latin scripts
    // (Korean/Japanese/Chinese/Arabic/Hindi/Cyrillic — our dict only
    // covers IT/ES/FR/DE/PT/EN). For these scripts the cross-lang
    // detection above misses, and B4 specificity (Step 3) fails because
    // lexical overlap with Latin content is 0 by design.
    // Fix: detect cross-script via Unicode block. If q and source use
    // different writing systems, lexical overlap is meaningless →
    // accept and trust the model's semantic match.
    if (_isNonLatinScript(text) != _isNonLatinScript(sourceSample)) {
      return const ValidationResult(ValidationOutcome.accept,
          reason: 'cross_script');
    }

    // Step 3 — same-language session. Lexical concept overlap check.
    final hasOverlap = _mentionsClusterConcept(text);
    if (!hasOverlap) {
      // Stages whose stems mention the concept directly: reject so
      // caller produces a rich fallback. Other stages use scenarios
      // (counterfactual, application, interleave, metacognitive) — accept
      // and trust the model's semantic specificity.
      final stagesRequiringDirectMention = const {
        SocraticStage.anchor,
        SocraticStage.elaboration,
        SocraticStage.comparative,
      };
      if (stagesRequiringDirectMention.contains(stage)) {
        return const ValidationResult(ValidationOutcome.retry,
            reason: 'no_specificity');
      }
      return const ValidationResult(ValidationOutcome.accept,
          reason: 'scenario_stage_semantic');
    }

    return const ValidationResult(ValidationOutcome.accept,
        reason: 'overlap_match');
  }

  // ─── Internals ──────────────────────────────────────────────────────

  static const _ceremonialPatterns = [
    // English
    'what can you tell me',
    'what do you know about',
    'tell me about',
    'in your own words',
    // Italian
    'cosa puoi dirmi',
    'cosa sai di',
    'cosa puoi spiegare',
    'puoi spiegare con le tue parole',
    'con le tue parole',
    'parlami di',
  ];

  bool _isGenericCeremonial(String text) {
    final lower = text.toLowerCase();
    return _ceremonialPatterns.any(lower.contains);
  }

  /// True when [text] is predominantly written in a non-Latin script
  /// (CJK ideographs, Japanese kana, Korean Hangul, Arabic, Hebrew,
  /// Cyrillic, Devanagari, Thai, etc.). Skips ASCII digits/punctuation/
  /// whitespace; counts the ratio of non-Latin code points among
  /// "content" runes. ≥50% non-Latin → returns true.
  ///
  /// Used for cross-script session detection where function-word
  /// signatures fail (our dictionaries only cover IT/ES/FR/DE/PT/EN).
  /// Sprint F.2-post (2026-05-13 PM).
  static bool _isNonLatinScript(String text) {
    int contentRunes = 0;
    int nonLatin = 0;
    for (final rune in text.runes) {
      // Skip ASCII control + space + digits + basic punctuation.
      if (rune < 0x30) continue; // controls + whitespace + a few puncts
      if (rune >= 0x30 && rune <= 0x39) continue; // digits
      if (rune == 0x20) continue; // space
      if (rune >= 0x21 && rune <= 0x2F) continue; // ! to /
      if (rune >= 0x3A && rune <= 0x40) continue; // : to @
      if (rune >= 0x5B && rune <= 0x60) continue; // [ to `
      if (rune >= 0x7B && rune <= 0x7E) continue; // { to ~
      contentRunes++;
      // Latin script ranges: Basic Latin letters, Latin-1 supplement,
      // Latin Extended-A/B (accents, Italian/Spanish/French chars).
      if ((rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A) ||
          (rune >= 0xC0 && rune <= 0x024F)) {
        continue; // Latin
      }
      // Non-Latin scripts of interest:
      //   CJK punct + Hiragana + Katakana + CJK Unified: 0x3000-0x9FFF
      //   CJK Extension B-G: 0x20000-0x2FFFF
      //   Hangul (Korean): 0xAC00-0xD7AF
      //   Arabic: 0x0600-0x06FF + 0xFE70-0xFEFF (Arabic Presentation)
      //   Devanagari (Hindi): 0x0900-0x097F
      //   Cyrillic (Russian): 0x0400-0x04FF
      //   Hebrew: 0x0590-0x05FF
      //   Thai: 0x0E00-0x0E7F
      if ((rune >= 0x3000 && rune <= 0x9FFF) ||
          (rune >= 0xAC00 && rune <= 0xD7AF) ||
          (rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0xFE70 && rune <= 0xFEFF) ||
          (rune >= 0x0900 && rune <= 0x097F) ||
          (rune >= 0x0400 && rune <= 0x04FF) ||
          (rune >= 0x0590 && rune <= 0x05FF) ||
          (rune >= 0x0E00 && rune <= 0x0E7F) ||
          (rune >= 0x20000 && rune <= 0x2FFFF)) {
        nonLatin++;
      }
    }
    if (contentRunes == 0) return false;
    return nonLatin / contentRunes > 0.5;
  }

  // Stopwords kept short — only what's necessary to avoid false matches.
  static const _stopwords = {
    'allora', 'come', 'cosa', 'dove', 'oppure', 'parole', 'perché',
    'quale', 'quali', 'quando', 'quindi', 'questa', 'questo', 'sempre',
    'tutti', 'about', 'these', 'those', 'their', 'there', 'when',
    'where', 'which', 'while', 'something', 'concept',
  };

  bool _mentionsClusterConcept(String text) {
    String normalise(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final qWords = normalise(text)
        .split(' ')
        .where((w) => w.length >= 4 && !_stopwords.contains(w))
        .toSet();
    final pool = <String>{
      ...normalise(clusterTopic)
          .split(' ')
          .where((w) => w.length >= 4 && !_stopwords.contains(w)),
      if (clusterRawOcr != null)
        ...normalise(clusterRawOcr!)
            .split(' ')
            .where((w) => w.length >= 4 && !_stopwords.contains(w)),
    };
    if (pool.isEmpty) return true; // no concept words → nothing to match
    return qWords.intersection(pool).isNotEmpty;
  }
}

enum ValidationOutcome { accept, retry, reject }

class ValidationResult {
  final ValidationOutcome outcome;
  final String reason;
  const ValidationResult(this.outcome, {required this.reason});

  bool get isAccept => outcome == ValidationOutcome.accept;
  bool get isRetry => outcome == ValidationOutcome.retry;
  bool get isReject => outcome == ValidationOutcome.reject;

  @override
  String toString() =>
      'ValidationResult(${outcome.name}, reason=$reason)';
}
