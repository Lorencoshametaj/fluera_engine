import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/services/italian_ocr_corrector.dart';

void main() {
  // The corrector loads its dictionary from rootBundle, but seedForTesting
  // injects a deterministic in-memory set so we don't depend on the asset
  // bundle being available in unit tests.
  setUp(() {
    ItalianOcrCorrector.resetForTesting();
    ItalianOcrCorrector.seedForTesting({
      'legge',
      'leggi',
      'newton',
      'forza',
      'massa',
      'accelerazione',
    });
  });

  tearDown(ItalianOcrCorrector.resetForTesting);

  group('ItalianOcrCorrector.bestMatch', () {
    test('preserves top candidate when already in dictionary', () async {
      final result = await ItalianOcrCorrector.bestMatch(
        ['legge', 'leggi', 'leggid'],
      );
      expect(result, 'legge');
    });

    test('promotes lower-ranked alternative when top is OUT of dict', () async {
      // Top "Leggid" is the user-reported MyScript garble; correct
      // answer "Legge" is in the dict at rank 2.
      final result = await ItalianOcrCorrector.bestMatch(
        ['Leggid', 'Legge', 'Leggi'],
      );
      expect(result, 'Legge');
    });

    test('returns top unchanged when NO candidate is in dict', () async {
      // Proper noun / foreign word case — leave alone.
      final result = await ItalianOcrCorrector.bestMatch(
        ['Schrödinger', 'Schrodinger', 'Schroedinger'],
      );
      expect(result, 'Schrödinger');
    });

    test('skips correction for short words (< 3 chars)', () async {
      // "io" is valid Italian but might collide accidentally; the
      // corrector intentionally leaves short tokens alone.
      final result = await ItalianOcrCorrector.bestMatch(['xy', 'io']);
      expect(result, 'xy');
    });

    test('skips words with digits or LaTeX residue', () async {
      final result = await ItalianOcrCorrector.bestMatch(
        [r'F=ma', 'forza', 'massa'],
      );
      expect(result, r'F=ma');
    });

    test('preserves casing of the chosen alternative', () async {
      final result = await ItalianOcrCorrector.bestMatch(
        ['Leggid', 'Legge'],
      );
      expect(result, 'Legge'); // capital L preserved, not lowered
    });

    test('returns empty string when given empty list', () async {
      expect(await ItalianOcrCorrector.bestMatch(const []), '');
    });
  });

  group('ItalianOcrCorrector.correctText', () {
    test('joins corrected words with spaces', () async {
      final result = await ItalianOcrCorrector.correctText(
        'Leggid 1 di Newton',
        [
          ['Leggid', 'Legge'],
          ['1'],
          ['di'],
          ['Newton'],
        ],
      );
      // "Leggid" → "Legge", "1" skipped (digit), "di" skipped (< 3),
      // "Newton" preserved (in dict).
      expect(result, contains('Legge'));
      expect(result, contains('Newton'));
    });

    test('returns original when wordCandidates is empty', () async {
      final result = await ItalianOcrCorrector.correctText(
        'fallback original',
        const [],
      );
      expect(result, 'fallback original');
    });
  });
}
