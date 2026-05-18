// ============================================================================
// 🌍 ClusterConceptIndex — title prompt multilang (Bundle B, 2026-05-17)
//
// Verifies that `_buildTitlePrompt` (exposed via `buildTitlePromptForTest`)
// produces a prompt for every supported language (16 Tier 1+2 codes), with
// the right display name interpolation + the native-language enforcement
// instruction at the top whenever the resolved language is not English.
// ============================================================================
//
// Covers two paths:
//   - Detected language (Latin Latin-script detector via `detectLanguageSignature`):
//     short distinctive text → detector recognises IT/EN/ES/FR/DE/PT directly.
//   - Fallback to AiLanguagePreference (10 non-detected langs JA/KO/HI/AR/ZH
//     /RU/NL/SV/PL/TR): detector returns 'unknown', the prompt builder must
//     fall back to the user preference display name.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/cluster_concept_index.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';
import 'package:fluera_engine/src/utils/ai_language_preference.dart';

ClusterConceptIndex _index({required String language}) {
  return ClusterConceptIndex(
    providerFn: () => null,
    strokeMapFn: () => const {},
    reviewScheduleFn: () => const {},
    languageNameFn: () => language,
  );
}

ContentCluster _cluster() => ContentCluster(
      id: 'c1',
      strokeIds: const ['s1', 's2'],
      bounds: const Rect.fromLTWH(0, 0, 100, 50),
      centroid: const Offset(50, 25),
    );

void main() {
  group('cluster title prompt — multilang interpolation (Bundle B)', () {
    test(
        'every AiLanguagePreference language produces a non-empty prompt that '
        'mentions the language display name at least once', () {
      // Use a text the detector will mark as "unknown" so the prompt
      // builder falls back to the languageNameFn — this is the path that
      // covers all 16 languages, including JA/KO/HI/AR not handled by the
      // 6-Latin detector.
      const unknownText = '???';
      final supported = AiLanguagePreference.supportedLanguages();
      expect(supported.length, 16,
          reason: 'AiLanguagePreference must list exactly 16 Tier 1+2 langs.');

      for (final entry in supported.entries) {
        final displayName = entry.value;
        final index = _index(language: displayName);
        final prompt = index.buildTitlePromptForTest(unknownText);
        expect(prompt, isNotEmpty,
            reason: 'prompt empty for language $displayName');
        expect(prompt, contains('OUTPUT LANGUAGE = $displayName'),
            reason: 'prompt for $displayName must interpolate display name '
                'into the OUTPUT LANGUAGE header.');
        expect(prompt, contains('TITLE (in $displayName):'),
            reason: 'prompt for $displayName must close with the language-'
                'qualified TITLE marker.');
      }
    });

    test(
        'non-English languages get the native-language instruction injected '
        'at the top of the prompt (anti-drift safeguard)', () {
      const cases = <String, String>{
        'Italian': 'RISPONDI ESCLUSIVAMENTE IN ITALIANO',
        'Japanese': '必ず日本語で回答してください',
        'Arabic': 'أجب باللغة العربية فقط',
        'Hindi': 'केवल हिन्दी में उत्तर दें',
      };
      for (final entry in cases.entries) {
        final index = _index(language: entry.key);
        final prompt = index.buildTitlePromptForTest('???');
        expect(prompt, contains(entry.value),
            reason: 'prompt for ${entry.key} must contain the native-language '
                'instruction "${entry.value}" at the top.');
        // Sanity: instruction precedes the English body.
        final instrIdx = prompt.indexOf(entry.value);
        final bodyIdx = prompt.indexOf('You label concept clusters');
        expect(instrIdx, lessThan(bodyIdx),
            reason: 'native instruction must come BEFORE the English body so '
                'the model reads it first.');
      }
    });

    test(
        'English target produces no native-language instruction block '
        '(no enforcement needed → empty string from AiLanguagePreference)', () {
      final index = _index(language: 'English');
      final prompt = index.buildTitlePromptForTest('???');
      // Body must still be there.
      expect(prompt, contains('OUTPUT LANGUAGE = English'));
      // But none of the native enforcement strings should appear.
      const nativeMarkers = [
        'RISPONDI ESCLUSIVAMENTE',
        '必ず日本語',
        'أجب باللغة',
        'केवल हिन्दी',
      ];
      for (final marker in nativeMarkers) {
        expect(prompt, isNot(contains(marker)),
            reason: 'English target must not include the $marker enforcement.');
      }
    });

    test(
        'short distinctive Italian text triggers the detector path and the '
        'prompt is built in Italian even when languageNameFn says English', () {
      // The detector recognises this as Italian (multiple IT function
      // words). Despite languageNameFn returning English, the title must
      // be built in Italian because cluster titles label CONTENT, not
      // AI preference (see _resolveTitleLang doc).
      const itText =
          'le leggi del moto di newton sono i principi fondamentali della dinamica';
      final index = _index(language: 'English');
      final prompt = index.buildTitlePromptForTest(itText);
      expect(prompt, contains('OUTPUT LANGUAGE = Italian'),
          reason: 'detector should override languageNameFn when the OCR text '
              'is clearly Italian.');
      expect(prompt, contains('RISPONDI ESCLUSIVAMENTE IN ITALIANO'),
          reason: 'native IT instruction must be injected when the resolved '
              'language is Italian.');
    });
  });

  group('AiLanguagePreference.nativeLangInstruction (single source of truth)',
      () {
    test('returns non-empty native instruction for all non-English languages',
        () {
      for (final iso in AiLanguagePreference.supportedLanguages().keys) {
        final instr = AiLanguagePreference.nativeLangInstruction(iso);
        if (iso == 'en') {
          expect(instr, isEmpty,
              reason: 'English instruction must be empty (no enforcement).');
        } else {
          expect(instr, isNotEmpty,
              reason: 'non-English language $iso must have a native '
                  'instruction string.');
        }
      }
    });

    test('unknown iso codes return empty string (safe fallback)', () {
      expect(AiLanguagePreference.nativeLangInstruction('xx'), isEmpty);
      expect(AiLanguagePreference.nativeLangInstruction(''), isEmpty);
    });
  });
}
