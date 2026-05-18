// ============================================================================
// 🌐 SUPER-NODE THEME REGISTRY — dispatch + fallback for the multilang
// theme prompt (Bundle C, 2026-05-17)
//
// Mirrors `chat_pedagogy_registry.dart` / `exam_pedagogy_registry.dart`:
// a static façade over `super_node_theme_bootstrap.dart` that picks the
// right cell for the user's language, falls back to English on miss, and
// interpolates the runtime placeholder (`{topic_groups}`).
//
// Callers should ONLY use this class — never reach into the bootstrap
// map directly. This guarantees the fallback chain is always applied
// and language switches don't accidentally leak past the index lookup.
// ============================================================================

import 'super_node_theme_bootstrap.dart';

/// Static façade for the super-node theme prompt. Resolves the language
/// cell + interpolates the runtime topic groups.
class SuperNodeThemeRegistry {
  SuperNodeThemeRegistry._();

  /// Returns the fully-rendered prompt for [langCode] with the topic-
  /// groups block interpolated. Falls back to English when [langCode]
  /// has no bootstrap cell — guarantees a non-null prompt for every
  /// supported language (16 Tier 1+2) plus any future addition.
  ///
  /// [topicGroupsBlock] is the pre-formatted multiline string the caller
  /// builds from the active super-nodes, e.g.:
  ///
  /// ```
  /// 1. ARGOMENTI: Newton, Forze, Energia
  /// 2. ARGOMENTI: Termodinamica, Entropia
  /// ```
  ///
  /// The caller is responsible for the numbering and ordering. The
  /// placeholder `{topic_groups}` in the template is replaced verbatim
  /// with this block.
  static String promptFor(String langCode, String topicGroupsBlock) {
    final cell = bootstrapSuperNodeThemeCellFor(langCode) ??
        bootstrapSuperNodeThemeCellFor('en')!;
    return cell.replaceAll('{topic_groups}', topicGroupsBlock);
  }

  /// Returns the validation status of the cell that would be used for
  /// [langCode]. UI components (e.g. a "this language is AI-bootstrapped"
  /// disclaimer) can read this to drive banners.
  static BackgroundAiValidationStatus validationStatusFor(String langCode) =>
      superNodeThemeStatusFor(langCode);
}
