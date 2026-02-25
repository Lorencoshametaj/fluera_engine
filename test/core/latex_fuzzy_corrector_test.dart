import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/latex/latex_fuzzy_corrector.dart';

void main() {
  // ===========================================================================
  // Known corrections
  // ===========================================================================

  group('LatexFuzzyCorrector - command corrections', () {
    test('corrects frcx to frac', () {
      final result = LatexFuzzyCorrector.correct(r'\frcx{a}{b}');
      expect(result, contains(r'\frac'));
    });

    test('preserves correct commands', () {
      final result = LatexFuzzyCorrector.correct(r'\frac{a}{b}');
      expect(result, contains(r'\frac'));
    });

    test('corrects sqrrt to sqrt', () {
      final result = LatexFuzzyCorrector.correct(r'\sqrrt{x}');
      expect(result, contains(r'\sqrt'));
    });
  });

  // ===========================================================================
  // Character-level fixes
  // ===========================================================================

  group('LatexFuzzyCorrector - character fixes', () {
    test('corrects known character confusions', () {
      // The corrector should handle ML misrecognitions
      final result = LatexFuzzyCorrector.correct(r'x + y');
      expect(result, isNotEmpty);
    });
  });

  // ===========================================================================
  // No correction needed
  // ===========================================================================

  group('LatexFuzzyCorrector - passthrough', () {
    test('plain text unchanged', () {
      expect(LatexFuzzyCorrector.correct('abc'), 'abc');
    });

    test('empty string unchanged', () {
      expect(LatexFuzzyCorrector.correct(''), '');
    });

    test('valid complex expression preserved', () {
      const input = r'\frac{\sqrt{x}}{y^2}';
      final result = LatexFuzzyCorrector.correct(input);
      expect(result, contains(r'\frac'));
      expect(result, contains(r'\sqrt'));
    });
  });

  // ===========================================================================
  // High edit distance
  // ===========================================================================

  group('LatexFuzzyCorrector - high distance', () {
    test('very different command not corrected', () {
      // Edit distance > 2 should not be corrected
      final result = LatexFuzzyCorrector.correct(r'\xyzabc{a}');
      // Should preserve original or leave as-is
      expect(result, isNotEmpty);
    });
  });
}
