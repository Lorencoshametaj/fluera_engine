// ============================================================================
// 🔒 LLM PAYLOAD ANONYMIZER — Privacy-by-design (Art. 25)
//
// Specifica: A16-16 → A16-20
//
// Before sending ANY text to an LLM (Atlas AI, Socratic, Chat),
// this filter strips personally identifiable information (PII):
//
// STRIPPED:
//   - Email addresses
//   - Phone numbers
//   - Italian fiscal codes (codice fiscale)
//   - Names (when preceded by "Prof.", "Dott.", "Sig.", etc.)
//   - Dates of birth patterns
//   - Street addresses
//   - Student IDs / matricola
//
// REPLACEMENT:
//   All PII is replaced with [REDACTED] placeholder.
//   The LLM never sees the original PII.
//
// ARCHITECTURE:
//   Pure function — no state, no dependencies.
//   Called in the AI service layer before every LLM request.
//
// THREAD SAFETY: Stateless, safe from any isolate.
// ============================================================================

/// 🔒 LLM Payload Anonymizer (A16, Art. 25).
///
/// Strips PII from text before sending to external AI services.
///
/// Usage:
/// ```dart
/// final clean = LlmPayloadAnonymizer.anonymize(
///   'Il Prof. Rossi ha detto che mario.rossi@gmail.com...',
/// );
/// // → 'Il [REDACTED] ha detto che [REDACTED]...'
/// ```
class LlmPayloadAnonymizer {
  LlmPayloadAnonymizer._();

  /// The replacement placeholder.
  static const String redacted = '[REDACTED]';

  /// Anonymize text by stripping all detected PII.
  ///
  /// Returns the cleaned text and the number of redactions made.
  static AnonymizationResult anonymize(String text) {
    if (text.isEmpty) {
      return const AnonymizationResult(text: '', redactionCount: 0);
    }

    String result = text;
    int count = 0;

    // Apply each filter in order.
    for (final filter in _filters) {
      final matches = filter.allMatches(result);
      count += matches.length;
      result = result.replaceAll(filter, redacted);
    }

    return AnonymizationResult(text: result, redactionCount: count);
  }

  /// Check if text contains any detectable PII.
  static bool containsPii(String text) {
    return _filters.any((filter) => filter.hasMatch(text));
  }

  // ── PII Patterns ──────────────────────────────────────────────────────

  static final List<RegExp> _filters = [
    // Email addresses
    RegExp(
      r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
      caseSensitive: false,
    ),

    // Phone numbers (Italian + international)
    RegExp(
      r'(?:\+39\s?)?(?:3[0-9]{2}[\s.-]?\d{3}[\s.-]?\d{4}|0[0-9]{1,3}[\s.-]?\d{4,8})',
    ),

    // Italian fiscal code (codice fiscale)
    RegExp(
      r'\b[A-Z]{6}\d{2}[A-EHLMPRST]\d{2}[A-Z]\d{3}[A-Z]\b',
      caseSensitive: false,
    ),

    // Titled names (Prof., Dott., Sig., Ing., Avv., Dr.)
    RegExp(
      r'(?:Prof\.?(?:ssa)?|Dott\.?(?:ssa)?|Sig\.?(?:ra)?|Ing\.?|Avv\.?|Dr\.?)\s+[A-Z][a-zà-ú]+(?:\s+[A-Z][a-zà-ú]+)?',
    ),

    // Student ID / Matricola patterns
    RegExp(
      r'(?:matricola|student\s*id)[:\s]*\d{5,10}',
      caseSensitive: false,
    ),

    // Italian street addresses
    RegExp(
      r'(?:Via|Viale|Piazza|Corso|Largo|Vicolo)\s+[A-Z][a-zà-ú]+(?:\s+[A-Z]?[a-zà-ú]+)*\s*,?\s*\d{1,5}',
      caseSensitive: false,
    ),

    // Date of birth patterns (dd/mm/yyyy or dd-mm-yyyy)
    RegExp(
      r'(?:nato|nata|nascit[ao]|data di nascita|born)(?:[:\s]+(?:il|del|di|on)?[:\s]*)?\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}',
      caseSensitive: false,
    ),
  ];
}

/// 🔒 Result of anonymization.
class AnonymizationResult {
  /// The anonymized text.
  final String text;

  /// Number of PII items redacted.
  final int redactionCount;

  const AnonymizationResult({
    required this.text,
    required this.redactionCount,
  });

  /// Whether any PII was found and redacted.
  bool get hadPii => redactionCount > 0;
}
