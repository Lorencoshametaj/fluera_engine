// ============================================================================
// 🧹 CLEAN-OCR REGISTRY — dispatch + fallback for the multilang cleanOcr
// prompt (Bundle A, 2026-05-17)
//
// Mirrors `super_node_theme_registry.dart`: static façade over
// `clean_ocr_bootstrap.dart` that picks the right cell for the user's
// language, falls back to English on miss, and interpolates the runtime
// `{input}` placeholder.
//
// Callers should ONLY use this class — never reach into the bootstrap
// map directly. This guarantees the fallback chain is always applied
// and language switches don't accidentally leak past the index lookup.
// ============================================================================

import 'clean_ocr_bootstrap.dart';
import 'super_node_theme_bootstrap.dart' show BackgroundAiValidationStatus;

/// Static façade for the cleanOcr prompt. Resolves the language cell and
/// interpolates the raw OCR text.
class CleanOcrRegistry {
  CleanOcrRegistry._();

  /// Returns the fully-rendered cleanOcr prompt for [langCode] with [raw]
  /// interpolated into the `{input}` placeholder. Falls back to English
  /// when [langCode] has no bootstrap cell — guarantees a non-null prompt
  /// for every supported language plus any future addition.
  ///
  /// [raw] must already be trimmed by the caller; the registry does not
  /// modify the content other than substituting the placeholder.
  static String promptFor(String langCode, String raw) {
    final cell = bootstrapCleanOcrCellFor(langCode) ??
        bootstrapCleanOcrCellFor('en')!;
    return cell.replaceAll('{input}', raw);
  }

  /// Returns the validation status of the cell that would be used for
  /// [langCode]. UI components (e.g. a "this language is AI-bootstrapped"
  /// disclaimer) can read this to drive banners.
  static BackgroundAiValidationStatus validationStatusFor(String langCode) =>
      cleanOcrStatusFor(langCode);
}
