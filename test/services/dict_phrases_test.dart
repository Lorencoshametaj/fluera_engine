import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/services/dict_entry.dart';
import 'package:fluera_engine/src/services/word_completion_dictionary.dart';

// =============================================================================
// 🔤 Stage 6 — multi-word expression (phrases) tests
//
// Covers the `en.phrases.tsv` parser + the WordCompletionDictionary
// phrase-lookup API, hermetically (no rootBundle).
// =============================================================================

void main() {
  setUp(() {
    WordCompletionDictionary.instance.resetForTesting();
  });

  group('parsePhrasesTsv', () {
    test('parses a well-formed phrases TSV with header + comments', () {
      const tsv = '# fluera-phrases v1 lang=en built=2026-05-19 rows=3\n'
          'phrase\tdomains\tkind\n'
          'in vivo\tmed\tlatin\n'
          'machine learning\tcs,stem\tgeneral\n'
          'burden of proof\tlaw\tlegal\n';
      final out = parsePhrasesTsv(tsv);
      expect(out, hasLength(3));
      expect(out['in vivo'], ['med']);
      expect(out['machine learning'], ['cs', 'stem']);
      expect(out['burden of proof'], ['law']);
    });

    test('treats `-` domains as empty list', () {
      const tsv = 'phrase\tdomains\tkind\n'
          'et cetera\t-\tlatin\n';
      final out = parsePhrasesTsv(tsv);
      expect(out['et cetera'], isEmpty);
    });

    test('skips malformed rows (wrong cell count)', () {
      const tsv = 'phrase\tdomains\tkind\n'
          'broken row\tmed\n'
          'good phrase\tmed\tmedical\n';
      final out = parsePhrasesTsv(tsv);
      expect(out.keys, ['good phrase']);
    });

    test('handles CRLF line endings', () {
      const tsv = 'phrase\tdomains\tkind\r\n'
          'in vitro\tmed\tlatin\r\n';
      expect(parsePhrasesTsv(tsv)['in vitro'], ['med']);
    });
  });

  group('WordCompletionDictionary phrase API', () {
    test('isKnownPhrase / phraseDomains return seeded data', () {
      WordCompletionDictionary.instance.seedPhrasesForTesting({
        'machine learning': ['cs', 'stem'],
        'in vivo': ['med'],
        'et cetera': [],
      });
      final dict = WordCompletionDictionary.instance;
      expect(dict.isKnownPhrase('machine learning'), isTrue);
      expect(dict.isKnownPhrase('in vivo'), isTrue);
      expect(dict.isKnownPhrase('unknown phrase here'), isFalse);
      expect(dict.phraseDomains('machine learning'), {'cs', 'stem'});
      expect(dict.phraseDomains('in vivo'), {'med'});
      expect(dict.phraseDomains('et cetera'), isEmpty);
    });

    test('lookup is case-insensitive and whitespace-tolerant', () {
      WordCompletionDictionary.instance.seedPhrasesForTesting({
        'burden of proof': ['law'],
      });
      final dict = WordCompletionDictionary.instance;
      expect(dict.isKnownPhrase('Burden Of Proof'), isTrue);
      expect(dict.isKnownPhrase('  burden   of   proof  '), isTrue);
      expect(dict.phraseDomains('BURDEN OF PROOF'), {'law'});
    });

    test('empty phrase store → all lookups miss gracefully', () {
      final dict = WordCompletionDictionary.instance;
      expect(dict.isKnownPhrase('machine learning'), isFalse);
      expect(dict.phraseDomains('machine learning'), isEmpty);
    });

    test('resetForTesting clears the phrase store', () {
      WordCompletionDictionary.instance
          .seedPhrasesForTesting({'in vivo': ['med']});
      expect(WordCompletionDictionary.instance.isKnownPhrase('in vivo'), isTrue);
      WordCompletionDictionary.instance.resetForTesting();
      expect(WordCompletionDictionary.instance.isKnownPhrase('in vivo'), isFalse);
    });
  });
}
