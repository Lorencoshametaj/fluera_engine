// ============================================================================
// 🌐 Super-node theme bootstrap — smoke (Bundle C, 2026-05-17)
//
// Enumerates all 16 supported languages and verifies that the theme
// prompt registry produces a non-empty template containing the runtime
// placeholder substitution. Mirrors the pattern of
// `chat_pedagogy_smoke_test.dart`.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/super_node_theme_bootstrap.dart';
import 'package:fluera_engine/src/ai/super_node_theme_registry.dart';
import 'package:fluera_engine/src/utils/ai_language_preference.dart';

void main() {
  group('SuperNodeThemeRegistry — multilang bootstrap (Bundle C)', () {
    const sampleTopicGroups = '1. ARGOMENTI: Newton, F=ma, Gravità';

    test(
        'every Tier 1+2 language (16) has a bootstrap cell that interpolates '
        'the {topic_groups} placeholder', () {
      final langs = AiLanguagePreference.supportedLanguages().keys.toList();
      expect(langs.length, 16,
          reason: 'AiLanguagePreference must list 16 Tier 1+2 langs.');

      for (final lang in langs) {
        final cell = bootstrapSuperNodeThemeCellFor(lang);
        expect(cell, isNotNull,
            reason: 'bootstrap cell missing for $lang — every Tier 1+2 '
                'language must have a cell (production-native or stub).');
        expect(cell, contains('{topic_groups}'),
            reason: 'cell for $lang missing the {topic_groups} placeholder — '
                'the registry interpolation depends on it.');

        final rendered = SuperNodeThemeRegistry.promptFor(
          lang,
          sampleTopicGroups,
        );
        expect(rendered, isNotEmpty);
        expect(rendered, contains(sampleTopicGroups),
            reason: 'rendered prompt for $lang must contain the interpolated '
                'topic groups verbatim.');
        expect(rendered, isNot(contains('{topic_groups}')),
            reason: 'rendered prompt for $lang must not still contain the '
                'unsubstituted placeholder.');
      }
    });

    test(
        'unknown language code falls back to the English cell (never returns '
        'a null / empty prompt)', () {
      final rendered = SuperNodeThemeRegistry.promptFor('xx', sampleTopicGroups);
      final enRendered =
          SuperNodeThemeRegistry.promptFor('en', sampleTopicGroups);
      expect(rendered, enRendered,
          reason: 'unknown lang must reuse the English template verbatim.');
    });

    test(
        'IT + EN are flagged productionNative; the other 14 are aiBootstrap '
        '(matches the Phase split documented in the bootstrap file)', () {
      expect(
        SuperNodeThemeRegistry.validationStatusFor('it'),
        BackgroundAiValidationStatus.productionNative,
      );
      expect(
        SuperNodeThemeRegistry.validationStatusFor('en'),
        BackgroundAiValidationStatus.productionNative,
      );
      final others = AiLanguagePreference.supportedLanguages()
          .keys
          .where((k) => k != 'it' && k != 'en');
      for (final lang in others) {
        expect(
          SuperNodeThemeRegistry.validationStatusFor(lang),
          BackgroundAiValidationStatus.aiBootstrap,
          reason: 'language $lang should be flagged aiBootstrap until a '
              'native review lifts it to productionNative.',
        );
      }
    });

    test(
        'unknown language defaults to aiBootstrap (safe pessimistic '
        'fallback for any future ISO code we forget to register)', () {
      expect(
        SuperNodeThemeRegistry.validationStatusFor('xx'),
        BackgroundAiValidationStatus.aiBootstrap,
      );
    });

    test(
        'Phase 2 (2026-05-17): the 14 non-IT/EN cells contain native '
        'content (not just an English fallback copy)', () {
      // Marker strings from each language\'s native body. Verifies that
      // Phase 2 actually wrote native content instead of leaving the
      // English stub from Phase 1.
      const nativeMarkers = <String, String>{
        'es': 'analista temático',
        'pt': 'analista temático',
        'fr': 'analyste thématique',
        'de': 'thematischer Analyst',
        'ja': 'テーマ分析者',
        'ko': '주제 분석가',
        'hi': 'विषयगत विश्लेषक',
        'ar': 'محلل موضوعي',
        'zh': '主题分析师',
        'ru': 'тематический аналитик',
        'nl': 'thematisch analist',
        'sv': 'tematisk analytiker',
        'pl': 'analitykiem tematycznym',
        'tr': 'tema analistisin',
      };
      for (final entry in nativeMarkers.entries) {
        final cell = bootstrapSuperNodeThemeCellFor(entry.key)!;
        expect(cell, contains(entry.value),
            reason: 'super-node theme cell for ${entry.key} must contain '
                'native-language marker "${entry.value}" — if missing, the '
                'cell has been reverted to an English stub.');
      }
    });
  });
}
