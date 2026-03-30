import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'grammar_check_service.dart';
import 'language_detection_service.dart';
import 'word_completion_dictionary.dart';

// =============================================================================
// 🧠 AI GRAMMAR SERVICE — Gemini-powered advanced grammar checking
//
// Supplements rule-based GrammarCheckService with AI-powered analysis.
// Uses Gemini Flash for deep contextual understanding:
//  - Detects errors that rules can't (should of → should have)
//  - Understands context across sentences
//  - Multi-language without language-specific rules
//  - Style and clarity suggestions
//
// Architecture: rule-based (instant, offline) + AI (background, deeper)
// =============================================================================

/// An AI-detected grammar issue.
class AiGrammarError {
  final String original;    // The problematic text
  final String? correction; // Suggested fix
  final String message;     // Human-readable explanation
  final int startIndex;     // Start position in the full text
  final int endIndex;       // End position in the full text
  final AiGrammarSeverity severity;

  const AiGrammarError({
    required this.original,
    this.correction,
    required this.message,
    required this.startIndex,
    required this.endIndex,
    this.severity = AiGrammarSeverity.suggestion,
  });

  /// Convert to standard GrammarError for unified rendering.
  GrammarError toGrammarError() => GrammarError(
    message: message,
    startIndex: startIndex,
    endIndex: endIndex,
    ruleId: 'ai_grammar',
    suggestion: correction,
    severity: severity == AiGrammarSeverity.error
        ? GrammarSeverity.error
        : GrammarSeverity.info,
  );
}

enum AiGrammarSeverity { error, warning, suggestion }

/// Result of an AI grammar check.
class AiGrammarResult {
  final String text;
  final List<AiGrammarError> errors;
  final Duration processingTime;

  const AiGrammarResult({
    required this.text,
    required this.errors,
    this.processingTime = Duration.zero,
  });

  bool get hasErrors => errors.isNotEmpty;
}

// ── Service ──────────────────────────────────────────────────────────────

class AiGrammarService {
  AiGrammarService._();
  static final AiGrammarService instance = AiGrammarService._();

  GenerativeModel? _model;
  bool _initialized = false;
  bool _enabled = true;

  /// Whether AI grammar is enabled.
  bool get enabled => _enabled && _initialized;

  /// Enable/disable AI grammar checking.
  void setEnabled(bool value) => _enabled = value;

  // ── Initialization ─────────────────────────────────────────────────────

  /// Initialize with the Gemini API key (same key as Atlas).
  Future<void> initialize(String apiKey) async {
    if (_initialized) return;
    if (apiKey.isEmpty) return;

    try {
      _model = GenerativeModel(
        model: 'gemini-3.1-flash-lite-preview',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          temperature: 0.1, // Low temperature for precise corrections
          maxOutputTokens: 1024,
        ),
        systemInstruction: Content.system(_systemPrompt),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('[AiGrammar] Init error: $e');
    }
  }

  // ── Debounce ───────────────────────────────────────────────────────────

  Timer? _debounceTimer;
  static const _debounceDelay = Duration(milliseconds: 1500);

  /// The latest AI grammar result (set after background check completes).
  AiGrammarResult? lastResult;

  /// Callback invoked when AI check completes.
  VoidCallback? onResultReady;

  /// Schedule a debounced AI grammar check (call after text changes).
  void scheduleCheck(String text) {
    if (!enabled || text.trim().length < 10) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      _runCheck(text);
    });
  }

  /// Cancel any pending check.
  void cancelPending() {
    _debounceTimer?.cancel();
  }

  // ── Core Check ─────────────────────────────────────────────────────────

  Future<void> _runCheck(String text) async {
    if (!enabled || _model == null) return;

    final stopwatch = Stopwatch()..start();

    // Detect language for the prompt
    final lang = LanguageDetectionService.instance.detectLanguage(text);
    final langCode = lang.name;
    const langMap = {
      'it': 'Italian', 'en': 'English', 'es': 'Spanish',
      'fr': 'French', 'de': 'German', 'pt': 'Portuguese',
      'nl': 'Dutch', 'sv': 'Swedish', 'ro': 'Romanian',
      'tr': 'Turkish', 'pl': 'Polish', 'cs': 'Czech',
      'hr': 'Croatian', 'hu': 'Hungarian', 'ru': 'Russian',
      'ar': 'Arabic', 'ja': 'Japanese', 'ko': 'Korean',
      'zh': 'Chinese', 'hi': 'Hindi',
    };
    final langName = langMap[langCode] ?? 'English';

    final prompt = '''
TEXT_TO_CHECK ($langName):
"""
$text
"""

Analyze this text for grammar, spelling, and style issues. The text is from handwritten notes converted via OCR — be lenient with formatting but strict on grammar.''';

    try {
      final response = await _model!
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 8));

      if (response.text == null) return;

      final raw = response.text!
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final json = jsonDecode(raw) as Map<String, dynamic>;
      final issues = json['issues'] as List<dynamic>? ?? [];

      final errors = <AiGrammarError>[];
      for (final issue in issues) {
        final m = issue as Map<String, dynamic>;
        final original = m['original'] as String? ?? '';

        // Find the position in the original text
        final idx = text.indexOf(original);
        if (idx < 0) continue; // Can't locate — skip

        final severity = switch (m['severity'] as String? ?? 'suggestion') {
          'error' => AiGrammarSeverity.error,
          'warning' => AiGrammarSeverity.warning,
          _ => AiGrammarSeverity.suggestion,
        };

        errors.add(AiGrammarError(
          original: original,
          correction: m['correction'] as String?,
          message: m['message'] as String? ?? 'Grammar suggestion',
          startIndex: idx,
          endIndex: idx + original.length,
          severity: severity,
        ));
      }

      stopwatch.stop();

      lastResult = AiGrammarResult(
        text: text,
        errors: errors,
        processingTime: stopwatch.elapsed,
      );

      onResultReady?.call();
    } catch (e) {
      debugPrint('[AiGrammar] Check error: $e');
    }
  }

  /// Run a grammar check synchronously (for testing).
  Future<AiGrammarResult?> checkText(String text) async {
    if (!enabled || _model == null) return null;
    await _runCheck(text);
    return lastResult;
  }

  // ── Merge with Rule-Based ──────────────────────────────────────────────

  /// Merge AI errors with rule-based errors, deduplicating overlaps.
  static List<GrammarError> mergeErrors(
    List<GrammarError> ruleErrors,
    List<AiGrammarError> aiErrors,
  ) {
    final merged = List<GrammarError>.from(ruleErrors);

    for (final aiErr in aiErrors) {
      // Check if a rule-based error already covers this range
      final overlaps = merged.any((r) =>
          r.startIndex <= aiErr.endIndex && r.endIndex >= aiErr.startIndex);

      if (!overlaps) {
        merged.add(aiErr.toGrammarError());
      }
    }

    // Sort by position
    merged.sort((a, b) => a.startIndex.compareTo(b.startIndex));
    return merged;
  }

  void dispose() {
    _debounceTimer?.cancel();
    _model = null;
    _initialized = false;
    lastResult = null;
  }

  // ── System Prompt ──────────────────────────────────────────────────────

  static const String _systemPrompt = '''
You are a precise multilingual grammar checker for handwritten notes.
Your task: find grammar, spelling, and style errors in the given text.

RULES:
1. Be strict on grammar but lenient on formatting (this is OCR from handwriting).
2. IGNORE proper nouns, technical terms, and abbreviations.
3. IGNORE capitalization at the start of lines (handwriting often doesn't capitalize).
4. Focus on: subject-verb agreement, tense consistency, preposition errors, confusables (your/you're, its/it's, should of/should have), article agreement, missing words.
5. Return ONLY genuine errors, not style preferences.
6. The text may be multilingual — check each language segment in its own grammar.

OUTPUT FORMAT (JSON):
{
  "issues": [
    {
      "original": "exact text with error",
      "correction": "corrected text",
      "message": "brief explanation",
      "severity": "error|warning|suggestion"
    }
  ]
}

If no issues found, return: {"issues": []}
Do NOT invent issues. Only report genuine errors.''';
}
