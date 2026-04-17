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
    // Italian declarations — exclude when preceded by interrogative words.
    // "La forza è una grandezza" (statement) vs "Qual è la grandezza?" (question)
    RegExp(r"(?<!\b(?:qual|cos|com|dov|perch[ée]|quando|chi|che)\W{0,2})\b\w+\s+è\s+(?:un|una|il|la|lo|l'|i|le|gli)\s+\w+",
        caseSensitive: false),
    RegExp(r'(?<!\?.*)\b\w+\s+sono\s+(?:dei|delle|degli)\s+\w+',
        caseSensitive: false),
    // English declarations (for mixed-language LLM outputs)
    RegExp(r'(?<!\b(?:what|how|why|where|when|who)\W{0,2})\b\w+\s+is\s+(?:a|an|the)\s+\w+', caseSensitive: false),
    RegExp(r'(?<!\b(?:what|how|why|where|when|who)\W{0,2})\b\w+\s+are\s+\w+\s+that\b', caseSensitive: false),
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
    final isInterrogative = _interrogativeRegex.hasMatch(text);

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

    // A2-06: Question must end with "?"
    if (!text.endsWith('?')) {
      return OutputFilterResult.violation(
        output: text,
        type: OutputViolationType.missingQuestionMark,
        pattern: 'missing_question_mark',
      );
    }

    return OutputFilterResult.clean(text);
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

  /// Cluster-aware fallback with minimal context.
  static String fallbackForCluster(String? clusterText) {
    if (clusterText == null || clusterText.isEmpty) {
      return fallbackQuestion;
    }
    // Include cluster topic so the question has a clear subject.
    return 'Riguardo a "$clusterText", cosa puoi spiegare con le tue parole?';
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
