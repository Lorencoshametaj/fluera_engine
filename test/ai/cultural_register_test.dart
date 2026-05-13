// ============================================================================
// 🎭 Cultural register dispatcher tests.
//
// Verifies that `GeminiProvider.culturalRegisterFor(langName)` returns
// language-appropriate register cues per Tier-1 i18n language.
// Reference: docs/prompt_engineering_cognitive.md §9.6.5, §9.8, §9.9.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/atlas_ai_service.dart';

void main() {
  group('culturalRegisterFor — language-specific cues', () {
    test('Italian: tu form + softeners + avoid bare imperative', () {
      final reg = GeminiProvider.culturalRegisterFor('Italian');
      expect(reg, contains('tu'));
      expect(reg, contains('potresti'));
      expect(reg, contains('considera'));
    });

    test('Japanese: NEVER keigo (research arxiv 2402.14531)', () {
      final reg = GeminiProvider.culturalRegisterFor('Japanese');
      expect(reg, contains('keigo'));
      expect(reg, contains('DEGRADES'));
      expect(reg, contains('です/ます'));
    });

    test('Arabic: MSA preference, NO dialect', () {
      final reg = GeminiProvider.culturalRegisterFor('Arabic');
      expect(reg, contains('MSA'));
      expect(reg.toLowerCase(), contains('dialect'));
    });

    test('Hindi: Devanagari script + āp formal', () {
      final reg = GeminiProvider.culturalRegisterFor('Hindi');
      expect(reg, contains('Devanagari'));
      expect(reg, contains('आप'));
    });

    test('German: Sie form + Konjunktiv II', () {
      final reg = GeminiProvider.culturalRegisterFor('German');
      expect(reg, contains('Sie'));
      expect(reg, contains('Konjunktiv'));
    });

    test('Korean: haeyo-che, NOT banmal NOR hapsyo-che', () {
      final reg = GeminiProvider.culturalRegisterFor('Korean');
      expect(reg, contains('haeyo-che'));
      expect(reg, contains('banmal'));
    });

    test('Chinese: over-politeness DEGRADES (research)', () {
      final reg = GeminiProvider.culturalRegisterFor('Chinese');
      expect(reg, contains('DEGRADES'));
    });

    test('Unknown language: fallback non-empty + has softeners', () {
      final reg = GeminiProvider.culturalRegisterFor('Swahili');
      expect(reg.isNotEmpty, isTrue);
      expect(reg.toLowerCase(), contains('softening'));
    });
  });

  group('maxOutTokensForLang — fertility ratio table', () {
    test('EN baseline ratio 1.0', () {
      expect(GeminiProvider.maxOutTokensForLang('en', 800), 800);
    });

    test('Romance/Germanic ratio 1.3', () {
      expect(GeminiProvider.maxOutTokensForLang('it', 800), 1040);
      expect(GeminiProvider.maxOutTokensForLang('es', 800), 1040);
      expect(GeminiProvider.maxOutTokensForLang('de', 800), 1040);
      expect(GeminiProvider.maxOutTokensForLang('fr', 800), 1040);
    });

    test('Nordic/Slavic ratio 1.6', () {
      expect(GeminiProvider.maxOutTokensForLang('fi', 800), 1280);
      expect(GeminiProvider.maxOutTokensForLang('pl', 800), 1280);
      expect(GeminiProvider.maxOutTokensForLang('sv', 800), 1280);
    });

    test('Russian/Arabic ratio 2.2', () {
      // 800 * 2.2 = 1760.000…01 (floating-point) → ceil = 1761
      expect(GeminiProvider.maxOutTokensForLang('ru', 800), 1761);
      expect(GeminiProvider.maxOutTokensForLang('ar', 800), 1761);
    });

    test('CJK ratio 2.8', () {
      expect(GeminiProvider.maxOutTokensForLang('ja', 800), 2240);
      expect(GeminiProvider.maxOutTokensForLang('ko', 800), 2240);
      expect(GeminiProvider.maxOutTokensForLang('zh', 800), 2240);
    });

    test('Hindi ratio 3.2 (highest)', () {
      expect(GeminiProvider.maxOutTokensForLang('hi', 800), 2560);
    });

    test('Unknown locale fallback 1.5', () {
      expect(GeminiProvider.maxOutTokensForLang('xyz', 800), 1200);
    });
  });
}
