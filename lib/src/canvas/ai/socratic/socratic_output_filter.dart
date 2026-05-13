// ============================================================================
// 🛡️ SOCRATIC OUTPUT FILTER — Guardrail G2 (A2-04)
//
// Post-processing filter that scans every LLM output for prohibited patterns
// BEFORE showing it to the student. This is the second level of defense:
//
//   G1 (Prompt-Level): System prompt rules → prevents generation
//   G2 (Output Filter): Regex scan → catches leaks       ← THIS FILE
//   G3 (Structural):    JSON/format constraint → limits structure
//
// If a violation is detected:
//   1. Log the violation (A2-07)
//   2. Flag the output for regeneration
//   3. After 2 retries, substitute a safe fallback question
//
// Performance: O(n) per pattern × output length. Runs on UI isolate
// because output texts are small (< 200 chars typically).
// ============================================================================

import 'package:flutter/foundation.dart';
import '../../../utils/ai_language_preference.dart';
import 'socratic_model.dart' show SocraticQuestionType, SocraticStage;

/// Result of scanning LLM output through the G2 filter.
class OutputFilterResult {
  /// Whether the output passed the filter (no violations).
  final bool passed;

  /// The type of violation detected, if any.
  final OutputViolationType? violationType;

  /// The specific pattern that matched, for logging.
  final String? matchedPattern;

  /// The original raw output from the LLM.
  final String rawOutput;

  const OutputFilterResult._({
    required this.passed,
    required this.rawOutput,
    this.violationType,
    this.matchedPattern,
  });

  /// Clean output — no violations detected.
  const OutputFilterResult.clean(String output)
      : this._(passed: true, rawOutput: output);

  /// Violation detected — output should be regenerated.
  const OutputFilterResult.violation({
    required String output,
    required OutputViolationType type,
    required String pattern,
  }) : this._(
          passed: false,
          rawOutput: output,
          violationType: type,
          matchedPattern: pattern,
        );
}

/// Categories of prohibited output patterns (A2-04).
enum OutputViolationType {
  /// Direct declaration: "X è Y", "X means Y"
  declaration,

  /// Explanation: "perché X succede è che...", "the reason is..."
  explanation,

  /// Definition: "X significa...", "X is defined as..."
  definition,

  /// Direct answer: "The answer is...", "La risposta è..."
  directAnswer,

  /// Missing question mark — output doesn't end with "?" (A2-06)
  missingQuestionMark,
}

/// Log entry for G2 violations (A2-07).
class ViolationLogEntry {
  final DateTime timestamp;
  final OutputViolationType type;
  final String originalOutput;
  final String? correctedOutput;

  const ViolationLogEntry({
    required this.timestamp,
    required this.type,
    required this.originalOutput,
    this.correctedOutput,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'violation_type': type.name,
        'original_output': originalOutput,
        'corrected_output': correctedOutput,
      };
}

/// 🛡️ Socratic Output Filter — G2 guardrail implementation.
///
/// Scans LLM-generated questions for prohibited patterns that indicate
/// the model is giving answers instead of asking questions.
///
/// Usage:
/// ```dart
/// final result = SocraticOutputFilter.scan(llmOutput);
/// if (!result.passed) {
///   // Regenerate or use fallback
/// }
/// ```
class SocraticOutputFilter {
  SocraticOutputFilter._();

  // ── Violation log (A2-07) ─────────────────────────────────────────────

  static final List<ViolationLogEntry> _violationLog = [];

  /// Read-only access to the violation log for diagnostics.
  static List<ViolationLogEntry> get violationLog =>
      List.unmodifiable(_violationLog);

  /// Clear the violation log (e.g. on session end).
  static void clearLog() => _violationLog.clear();

  // ── Cached regexes and lookup table (O13/O14 optimization) ──────────

  /// Cached interrogative regex — avoids per-call compilation.
  static final _interrogativeRegex = RegExp(
    r"^(?:cos['\u2019]?è|com['\u2019]?è|perch[eé]|quale|quali|quando|dove|chi|"
    r"come|cosa|how|what|why|which|where|when|who)\b",
    caseSensitive: false,
  );

  /// Backup interrogative regex with fixes for `Qual` apocope and
  /// accented-char trailing boundary. Used as fallback when the primary
  /// pattern misses — see `scanQuestion`.
  ///
  /// 2026-05-10 (device): primary regex misclassified:
  ///   - "Qual è il meccanismo?" (apocope not in alternation)
  ///   - "Perché un corpo a riposo…" (\b after `é` fails in ASCII regex)
  static final _interrogativeRegexV2 = RegExp(
    r"^\W*(?:cos['’]?è|com['’]?è|perch[eé]|qual|quale|quali|"
    r"quando|dove|chi|come|cosa|how|what|why|which|where|when|who)"
    r"(?:\W|$)",
    caseSensitive: false,
  );

  /// Ordered checks list — avoids Map allocation on every scanQuestion call.
  static final _orderedChecks = <(OutputViolationType, List<RegExp>)>[
    (OutputViolationType.directAnswer, _directAnswerPatterns),
    (OutputViolationType.definition, _definitionPatterns),
    (OutputViolationType.explanation, _explanationPatterns),
    (OutputViolationType.declaration, _declarationPatterns),
  ];

  /// Declarative patterns: "X è Y", "X is Y" — the LLM is stating a fact.
  /// NOTE: Must NOT match interrogative phrases like "Qual è la...",
  /// "Com'è il...", "Cos'è il..." — these are valid questions.
  static final List<RegExp> _declarationPatterns = [
    // Italian declarations — exclude when preceded by interrogative words
    // AND when the subject word IS an interrogative/relative pronoun
    // (relative "che" introduces a clause, not a declaration).
    // "La forza è una grandezza" (statement) → MATCH
    // "Qual è la grandezza?" (question) → exclude (lookbehind)
    // "un oggetto che è un corpo a riposo" (relative clause, NOT
    //   declaration) → exclude via lookahead on the subject
    // 🛡️ 2026-05-13 device fix: previously matched "che è un CORPO" as
    // declaration when it was a relative clause inside a scenario setup.
    RegExp(
      r"(?<!\b(?:qual|cos|com|dov|perch[ée]|quando|chi|che)\W{0,2})"
      r"\b(?!(?:che|chi|qual|cos|com|dov|quando|cui|cosa)\b)"
      r"\w+\s+è\s+(?:un|una|il|la|lo|l'|i|le|gli)\s+\w+",
      caseSensitive: false,
    ),
    RegExp(r'(?<!\?.*)\b\w+\s+sono\s+(?:dei|delle|degli)\s+\w+',
        caseSensitive: false),
    // English declarations (for mixed-language LLM outputs) — same fix:
    // exclude relative pronouns ("that", "which") from being the subject.
    // "An object that is a body" (relative) vs "Newton is a physicist"
    // (declaration). Add negative lookahead on the subject word.
    RegExp(
      r'(?<!\b(?:what|how|why|where|when|who)\W{0,2})'
      r'\b(?!(?:that|which|what|who|whom|whose|how|why|where|when)\b)'
      r'\w+\s+is\s+(?:a|an|the)\s+\w+',
      caseSensitive: false,
    ),
    RegExp(
      r'(?<!\b(?:what|how|why|where|when|who)\W{0,2})'
      r'\b(?!(?:that|which|what|who)\b)'
      r'\w+\s+are\s+\w+\s+that\b',
      caseSensitive: false,
    ),
    // 🛡️ Theorem/law statements: "X afferma/dice/dichiara/stabilisce/
    // sostiene che Y" — the LLM is enunciating the textbook content
    // before asking, which gives away the answer (generation effect
    // violation). Device 2026-05-12: "La prima legge di Newton afferma
    // che un corpo a riposo rimane a riposo. Ma se il corpo è già in
    // moto uniforme, cosa implica la prima legge?"
    RegExp(
      r'\b(?:afferma|dice|dichiara|stabilisce|sostiene|enuncia|recita|prevede|implica|garantisce|asserisce)\s+che\b',
      caseSensitive: false,
    ),
    // 🛡️ "Sai che X" / "Ricordi che X" openers — pretend to be
    // retrieval cues but actually enunciate the content. Device prompt
    // example "Sai che F=ma. Ma se la massa varia…" trained the model
    // on this pattern; we now reject it.
    RegExp(
      r'^\s*(?:sai|ricordi|conosci|hai\s+visto|hai\s+studiato|hai\s+imparato|ti\s+ricordi)\s+(?:che|come|cos[aàa]|quale)\b',
      caseSensitive: false,
    ),
    // English equivalents.
    RegExp(
      r'\b(?:states|asserts|declares|claims|posits|maintains)\s+that\b',
      caseSensitive: false,
    ),
    RegExp(
      r'^\s*(?:you\s+know|you\s+remember|recall|as\s+you\s+know)\s+that\b',
      caseSensitive: false,
    ),
  ];

  /// Explanation patterns: the LLM is explaining WHY something happens.
  static final List<RegExp> _explanationPatterns = [
    RegExp(r'\bperch[ée]\s+\w+\s+(?:è|sono|avviene|succede|funziona)',
        caseSensitive: false),
    RegExp(r'\bthe reason (?:is|why)\b', caseSensitive: false),
    RegExp(r'\bthis (?:is because|happens because|works because)\b',
        caseSensitive: false),
    RegExp(r'\bil motivo (?:è|per cui)\b', caseSensitive: false),
    RegExp(r'\bquesto (?:avviene|succede|è dovuto)\s+(?:perch|a causa)',
        caseSensitive: false),
  ];

  /// Definition patterns: "X significa…", "X is defined as…"
  static final List<RegExp> _definitionPatterns = [
    RegExp(r'\b\w+\s+significa\b', caseSensitive: false),
    RegExp(r'\b\w+\s+(?:is|are)\s+defined\s+as\b', caseSensitive: false),
    RegExp(r'\bla definizione di\b', caseSensitive: false),
    RegExp(r'\bper definizione\b', caseSensitive: false),
    RegExp(r'\bsi definisce come\b', caseSensitive: false),
  ];

  /// Direct answer patterns: "The answer is…", "La risposta è…"
  static final List<RegExp> _directAnswerPatterns = [
    RegExp(r'\b(?:la |the )?risposta (?:è|corretta è)\b',
        caseSensitive: false),
    RegExp(r'\b(?:the )?answer (?:is|would be)\b', caseSensitive: false),
    RegExp(r'\bin realtà\s*,?\s*\w+\s+(?:è|sono|significa)\b',
        caseSensitive: false),
    RegExp(r'\b(?:actually|in fact)\s*,?\s*\w+\s+(?:is|are|means)\b',
        caseSensitive: false),
    RegExp(r'\bla soluzione (?:è|sarebbe)\b', caseSensitive: false),
    RegExp(r'\becco (?:la risposta|cosa|perché)\b', caseSensitive: false),
  ];

  // ── Core scan ─────────────────────────────────────────────────────────

  /// Scan a single question text for prohibited patterns.
  ///
  /// Returns [OutputFilterResult.clean] if no violations found.
  /// Returns [OutputFilterResult.violation] if a prohibited pattern matches.
  static OutputFilterResult scanQuestion(String questionText) {
    final text = questionText.trim();
    if (text.isEmpty) {
      return const OutputFilterResult.clean('');
    }

    // 🛡️ Detect interrogative sentences to avoid false positives on
    // declaration patterns. Legitimate questions like "Cos'è il vantaggio?"
    // START with a question word. But "La fotosintesi è un processo?" is
    // a declaration with "?" appended — it should still be flagged.
    // 2026-05-10: use BOTH regexes — V2 catches `Qual` apocope and
    // accented-char trailing boundary cases the primary regex misses.
    final isInterrogative = _interrogativeRegex.hasMatch(text) ||
        _interrogativeRegexV2.hasMatch(text);

    // Check each pattern category in order of severity.
    for (final (type, patterns) in _orderedChecks) {
      if (isInterrogative &&
          type == OutputViolationType.declaration) {
        continue;
      }

      for (final pattern in patterns) {
        final match = pattern.firstMatch(text);
        if (match != null) {
          final violation = OutputFilterResult.violation(
            output: text,
            type: type,
            pattern: match.group(0) ?? pattern.pattern,
          );
          _logViolation(violation);
          return violation;
        }
      }
    }

    // A2-06: Question must end with a question mark (multi-script).
    // 🛡️ Sprint F.2-post (2026-05-13 PM): device repro showed
    // Japanese/Arabic/Chinese sessions producing native questions ending
    // with `？` (full-width CJK U+FF1F) or `؟` (Arabic U+061F) — not
    // ASCII `?`. Previously G2 flagged these as missing-question-mark
    // → replaced with IT fallback template. Now accept all 3 scripts.
    if (!_endsWithQuestionMark(text)) {
      return OutputFilterResult.violation(
        output: text,
        type: OutputViolationType.missingQuestionMark,
        pattern: 'missing_question_mark',
      );
    }

    return OutputFilterResult.clean(text);
  }

  /// Returns true if [text] ends with any recognised question mark:
  /// ASCII `?`, CJK full-width `？` (U+FF1F), or Arabic `؟` (U+061F).
  /// Trims trailing whitespace before checking so "...?  " still passes.
  static bool _endsWithQuestionMark(String text) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) return false;
    final last = trimmed.codeUnitAt(trimmed.length - 1);
    // 0x3F = ASCII '?', 0xFF1F = CJK full-width '？',
    // 0x061F = Arabic '؟'
    return last == 0x3F || last == 0xFF1F || last == 0x061F;
  }

  /// Scan a batch of questions from the LLM response.
  ///
  /// Returns a list of results, one per question, preserving order.
  /// Questions that fail the filter are marked with their violation type.
  static List<OutputFilterResult> scanBatch(List<String> questions) {
    return questions.map(scanQuestion).toList(growable: false);
  }

  // ── Auto-correction (A2-05, A2-06) ────────────────────────────────────

  /// Attempt to fix minor violations automatically.
  ///
  /// - Missing "?" → appends "?"
  /// - Other violations → returns null (requires regeneration)
  static String? tryAutoCorrect(OutputFilterResult result) {
    if (result.passed) return result.rawOutput;

    if (result.violationType == OutputViolationType.missingQuestionMark) {
      // A2-06: Simply append "?" if missing.
      return '${result.rawOutput.trimRight()}?';
    }

    // All other violations require regeneration — cannot auto-correct.
    return null;
  }

  // ── Fallback questions (A2-05) ────────────────────────────────────────

  /// Safe fallback question when 2 retries fail (A2-05).
  static const String fallbackQuestion =
      'Puoi spiegare questo concetto con le tue parole?';

  /// Cluster + type-aware fallback. Replaces the previous generic
  /// "Riguardo a X, cosa puoi spiegare" template that collapsed all
  /// 4 question types into the same Depth-style prompt — empirically
  /// the dominant failure mode reported on Xiaomi 2026-05-10.
  ///
  /// Each branch produces a phrasing aligned with the type's pedagogical
  /// intent (lacuna = missing-link, sfida = edge case, profondità =
  /// mechanism, transfer = cross-domain) so a fallback still teaches
  /// instead of asking a recognition-style "spiegami X" question.
  static String fallbackForCluster(String? clusterText,
      [SocraticQuestionType? type]) {
    final hasTopic = clusterText != null && clusterText.isNotEmpty;
    final t = hasTopic ? '"$clusterText"' : 'questo concetto';
    switch (type) {
      case SocraticQuestionType.lacuna:
        return hasTopic
            ? 'Quali concetti mancano nella tua comprensione di $t? Cosa lo collega a quello che sai già?'
            : fallbackQuestion;
      case SocraticQuestionType.challenge:
        return hasTopic
            ? 'Sei sicuro/a di aver compreso $t? E se ci fosse un caso limite in cui non vale, come lo riconosceresti?'
            : fallbackQuestion;
      case SocraticQuestionType.depth:
        return hasTopic
            ? 'Riguardo a $t, qual è il MECCANISMO sottostante? Spiega il perché, non la definizione.'
            : fallbackQuestion;
      case SocraticQuestionType.transfer:
        return hasTopic
            ? '$t ti ricorda qualcosa di un\'altra disciplina o di un caso fuori dal tuo argomento?'
            : fallbackQuestion;
      case null:
        if (!hasTopic) return fallbackQuestion;
        return 'Riguardo a $t, cosa CONNETTE questo concetto a quello che hai già studiato?';
    }
  }

  /// 🎭 Stage-aware fallback (2026-05-12 pedagogical redesign,
  /// Sprint 4 2026-05-12 PM: now language-aware).
  ///
  /// Returns a question template scoped to the pedagogical stage rather
  /// than the FSRS recall type. Used in the no-AI fallback path so each
  /// emitted question still respects the session-level cognitive
  /// trajectory. Every output is an interrogative ending with `?` so it
  /// passes the G2 filter's declarative/explanation regexes.
  ///
  /// Reads `AiLanguagePreference.code()` to pick the target language.
  /// IT and EN have hand-crafted stems; other Tier-1 languages fall
  /// back to EN until native validation (see
  /// `docs/socratic_native_validation_protocol.md`).
  static String fallbackForStage(SocraticStage stage, String? clusterText) {
    final code = AiLanguagePreference.code();
    final hasTopic = clusterText != null && clusterText.isNotEmpty;
    switch (code) {
      case 'it':
        final t = hasTopic ? '"$clusterText"' : 'questo argomento';
        switch (stage) {
          case SocraticStage.anchor:
            return 'Cosa ti viene in mente per primo quando pensi a $t?';
          case SocraticStage.elaboration:
            return 'Perché $t funziona come funziona, secondo te?';
          case SocraticStage.comparative:
            return 'Cosa distingue $t da un concetto vicino che hai già studiato?';
          case SocraticStage.counterfactual:
            return 'Immagina di rimuovere un\'ipotesi chiave alla base di '
                '$t: cosa cambierebbe nel risultato osservato?';
          case SocraticStage.application:
            return 'In quale situazione concreta useresti $t per primo, e come?';
          case SocraticStage.interleave:
            return 'Quale altro concetto nei tuoi appunti è in tensione '
                'o sintonia con $t?';
          case SocraticStage.metacognitive:
            return 'Quale domanda ti farai la prossima volta che incontri $t?';
        }
      case 'en':
      default:
        final t = hasTopic ? '"$clusterText"' : 'this topic';
        switch (stage) {
          case SocraticStage.anchor:
            return 'What comes to mind first when you think about $t?';
          case SocraticStage.elaboration:
            return 'Why does $t work the way it does, in your view?';
          case SocraticStage.comparative:
            return 'What distinguishes $t from a closely related concept '
                'you have already studied?';
          case SocraticStage.counterfactual:
            return 'Imagine removing one key assumption behind $t: what '
                'would change in the observed outcome?';
          case SocraticStage.application:
            return 'In which concrete situation would you apply $t first, '
                'and how?';
          case SocraticStage.interleave:
            return 'Which other concept in your notes is in tension or '
                'harmony with $t?';
          case SocraticStage.metacognitive:
            return 'What question will you ask yourself the next time you '
                'encounter $t?';
        }
    }
  }

  // ── Logging (A2-07) ───────────────────────────────────────────────────

  static void _logViolation(OutputFilterResult result) {
    if (result.passed) return;

    final entry = ViolationLogEntry(
      timestamp: DateTime.now(),
      type: result.violationType!,
      originalOutput: result.rawOutput,
    );

    _violationLog.add(entry);

    // Keep log bounded — retain last 200 entries.
    if (_violationLog.length > 200) {
      _violationLog.removeRange(0, _violationLog.length - 200);
    }

    debugPrint(
      '🛡️ G2 violation: ${result.violationType?.name} '
      '— matched: "${result.matchedPattern}" '
      '— output: "${result.rawOutput.length > 80 ? '${result.rawOutput.substring(0, 80)}...' : result.rawOutput}"',
    );
  }
}
