import 'package:flutter/foundation.dart';
import 'package:flutter_langdetect/flutter_langdetect.dart' as langdetect;
import 'digital_ink_service.dart';

/// 🌐 Language Detection Service
///
/// Pure Dart language detection using n-gram models.
/// Works on ALL platforms (mobile, desktop, web) — no native dependencies.
///
/// Ported from Python's `langdetect` library. Supports 55 languages.
///
/// DESIGN:
/// - Singleton: one instance, shared across the app
/// - Zero native deps: pure Dart, no ML Kit needed
/// - Graceful fallback: returns null for short text or unknown languages
/// - Maps detected language codes → Digital Ink supported language codes
class LanguageDetectionService {
  LanguageDetectionService._();
  static final LanguageDetectionService instance = LanguageDetectionService._();

  bool _initialized = false;

  /// Minimum text length to attempt language identification.
  /// The detector needs enough text for reliable detection.
  static const int _minTextLength = 10;

  /// Whether the service is available on this platform.
  /// With pure Dart, it's always available.
  bool get isAvailable => true;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initialize the language detector.
  ///
  /// Must be called once before first use. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    await langdetect.initLangDetect();
    _initialized = true;
    debugPrint('🌐 [LangDetect] Initialized (pure Dart)');
  }

  /// Release resources (no-op for pure Dart implementation).
  void dispose() {
    // No native resources to release.
    // Keep _initialized = true since the global state persists.
  }

  // ── Detection ──────────────────────────────────────────────────────────────

  /// Identify the language of [text].
  ///
  /// Returns a BCP-47 language code that matches one of
  /// [DigitalInkService.supportedLanguages], or `null` if:
  /// - Text is too short (< [_minTextLength] chars)
  /// - Language can't be identified
  /// - Detected language is not supported by Digital Ink
  Future<String?> identifyLanguage(String text) async {
    if (!_initialized) await init();

    final trimmed = text.trim();
    if (trimmed.length < _minTextLength) return null;

    try {
      final code = langdetect.detect(trimmed);

      if (code.isEmpty) {
        debugPrint('🌐 [LangDetect] No result for "${_truncate(trimmed)}"');
        return null;
      }

      // Map to Digital Ink supported code
      final mapped = _mapToDigitalInkCode(code);
      if (mapped != null) {
        debugPrint(
          '🌐 [LangDetect] Detected "$mapped" '
          '(raw: "$code") for "${_truncate(trimmed)}"',
        );
      }
      return mapped;
    } catch (e) {
      debugPrint('🌐 [LangDetect] Error: $e');
      return null;
    }
  }

  /// Identify language with confidence scores.
  ///
  /// Returns the best matching Digital Ink language code and its confidence,
  /// or `null` if no match found.
  Future<({String code, double confidence})?> identifyWithConfidence(
    String text,
  ) async {
    if (!_initialized) await init();

    final trimmed = text.trim();
    if (trimmed.length < _minTextLength) return null;

    try {
      final languages = langdetect.detectLangs(trimmed);

      // Find the first detected language that maps to a Digital Ink code
      for (final lang in languages) {
        final mapped = _mapToDigitalInkCode(lang.lang);
        if (mapped != null) {
          debugPrint(
            '🌐 [LangDetect] Best match: "$mapped" '
            '(${(lang.prob * 100).toStringAsFixed(0)}%) '
            'for "${_truncate(trimmed)}"',
          );
          return (code: mapped, confidence: lang.prob);
        }
      }
      return null;
    } catch (e) {
      debugPrint('🌐 [LangDetect] Error: $e');
      return null;
    }
  }

  // ── Mapping ────────────────────────────────────────────────────────────────

  /// Maps a detected language code to a Digital Ink supported code.
  ///
  /// `flutter_langdetect` returns ISO 639-1 codes like "en", "it", "zh-cn".
  /// Digital Ink uses slightly different codes (e.g., "zh-Hani" for Chinese).
  /// Returns `null` if the language is not supported by Digital Ink.
  String? _mapToDigitalInkCode(String detectedCode) {
    // Direct match
    if (DigitalInkService.supportedLanguages.containsKey(detectedCode)) {
      return detectedCode;
    }

    // Special mappings (detected code → Digital Ink code)
    const specialMappings = <String, String>{
      'zh-cn': 'zh-Hani',
      'zh-tw': 'zh-Hani',
      'zh': 'zh-Hani',
      'no': 'da', // Norwegian → closest supported (Danish)
    };

    if (specialMappings.containsKey(detectedCode)) {
      return specialMappings[detectedCode];
    }

    // Try base language code (e.g., "pt-BR" → "pt")
    if (detectedCode.contains('-')) {
      final base = detectedCode.split('-').first;
      if (DigitalInkService.supportedLanguages.containsKey(base)) {
        return base;
      }
    }

    debugPrint(
      '🌐 [LangDetect] Unsupported language: "$detectedCode"',
    );
    return null;
  }

  /// Truncate text for debug logging.
  static String _truncate(String text, [int maxLen = 30]) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}…';
  }
}
