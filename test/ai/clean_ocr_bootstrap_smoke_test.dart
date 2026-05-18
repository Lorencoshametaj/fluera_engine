// ============================================================================
// 🧹 cleanOcr bootstrap — smoke (Bundle A, 2026-05-17)
//
// Enumerates all 16 supported languages and verifies the cleanOcr
// registry produces a non-empty template containing the runtime input
// substitution. Mirrors the pattern of
// `super_node_theme_bootstrap_smoke_test.dart`.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/clean_ocr_bootstrap.dart';
import 'package:fluera_engine/src/ai/clean_ocr_registry.dart';
import 'package:fluera_engine/src/ai/super_node_theme_bootstrap.dart'
    show BackgroundAiValidationStatus;
import 'package:fluera_engine/src/utils/ai_language_preference.dart';

void main() {
  group('CleanOcrRegistry — multilang bootstrap (Bundle A)', () {
    const sample = 'LEGGITI NEWTON';

    test(
        'every Tier 1+2 language (16) has a bootstrap cell that interpolates '
        'the {input} placeholder', () {
      final langs = AiLanguagePreference.supportedLanguages().keys.toList();
      expect(langs.length, 16,
          reason: 'AiLanguagePreference must list 16 Tier 1+2 langs.');

      for (final lang in langs) {
        final cell = bootstrapCleanOcrCellFor(lang);
        expect(cell, isNotNull,
            reason: 'bootstrap cell missing for $lang — every Tier 1+2 '
                'language must have a cell (production-native or stub).');
        expect(cell, contains('{input}'),
            reason: 'cell for $lang missing the {input} placeholder — '
                'the registry interpolation depends on it.');

        final rendered = CleanOcrRegistry.promptFor(lang, sample);
        expect(rendered, isNotEmpty);
        expect(rendered, contains(sample),
            reason: 'rendered prompt for $lang must contain the interpolated '
                'sample input verbatim.');
        expect(rendered, isNot(contains('{input}')),
            reason: 'rendered prompt for $lang must not still contain the '
                'unsubstituted placeholder.');
      }
    });

    test(
        'unknown language code falls back to the English cell (never returns '
        'a null / empty prompt)', () {
      final rendered = CleanOcrRegistry.promptFor('xx', sample);
      final enRendered = CleanOcrRegistry.promptFor('en', sample);
      expect(rendered, enRendered,
          reason: 'unknown lang must reuse the English template verbatim.');
    });

    test(
        'IT + EN are flagged productionNative; the other 14 are aiBootstrap',
        () {
      expect(
        CleanOcrRegistry.validationStatusFor('it'),
        BackgroundAiValidationStatus.productionNative,
      );
      expect(
        CleanOcrRegistry.validationStatusFor('en'),
        BackgroundAiValidationStatus.productionNative,
      );
      final others = AiLanguagePreference.supportedLanguages()
          .keys
          .where((k) => k != 'it' && k != 'en');
      for (final lang in others) {
        expect(
          CleanOcrRegistry.validationStatusFor(lang),
          BackgroundAiValidationStatus.aiBootstrap,
          reason: 'language $lang should be flagged aiBootstrap until a '
              'native review lifts it to productionNative.',
        );
      }
    });

    test(
        'unknown language defaults to aiBootstrap (safe pessimistic '
        'fallback)', () {
      expect(
        CleanOcrRegistry.validationStatusFor('xx'),
        BackgroundAiValidationStatus.aiBootstrap,
      );
    });

    test(
        'IT cell preserves the production-native examples that protect '
        'against OCR fusions (regression guard for the cells we wrote by hand)',
        () {
      final itCell = bootstrapCleanOcrCellFor('it')!;
      // These markers come straight from the production prompt body.
      // If a future edit accidentally strips them the cleanup quality
      // drops a lot, so we lock them down here.
      expect(itCell, contains('LEGGITI NEWTON'));
      expect(itCell, contains('LEGGI DI NEWTON'));
      expect(itCell, contains('anti-LaTeX hallucination'));
    });

    test(
        'EN cell preserves the production-native anti-LaTeX guard '
        '(regression guard for the cells we wrote by hand)', () {
      final enCell = bootstrapCleanOcrCellFor('en')!;
      expect(enCell, contains('anti-LaTeX hallucination'));
      expect(enCell, contains('NEVER convert'));
    });

    test(
        'Phase 2 (2026-05-17): the 14 non-IT/EN cells contain native '
        'content (not just an English fallback copy with a TODO marker)',
        () {
      // Marker strings from each language\'s native body. If any of these
      // disappear, the cell has likely been reverted to an English stub.
      const nativeMarkers = <String, String>{
        'es': 'palabras españolas',
        'pt': 'palavras portuguesas',
        'fr': 'mots français',
        'de': 'deutscher Wörter',
        'ja': '日本語',
        'ko': '한국어',
        'hi': 'हिन्दी',
        'ar': 'العربية',
        'zh': '中文',
        'ru': 'русский',
        'nl': 'Nederlandse',
        'sv': 'svenska',
        'pl': 'polskim',
        'tr': 'Türkçe',
      };
      for (final entry in nativeMarkers.entries) {
        final cell = bootstrapCleanOcrCellFor(entry.key)!;
        expect(cell, contains(entry.value),
            reason: 'cleanOcr cell for ${entry.key} must contain native-'
                'language marker "${entry.value}" — if missing, the cell '
                'has been reverted to an English stub.');
        // Sanity: no leftover TODO marker pointing at this cell.
        expect(cell, isNot(contains('TODO(ai-bootstrap-14-langs)')),
            reason: 'cleanOcr cell for ${entry.key} still has the Phase 2 '
                'TODO marker — content was not actually written.');
      }
    });
  });
}
