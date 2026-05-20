import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/services/dict_entry.dart';

// =============================================================================
// 📖 Unit tests for the dictionary TSV parser
//
// Schema invariants enforced by Stage 1:
//   - `#` comment lines are skipped
//   - First non-comment line is the column header (also skipped)
//   - Body rows have exactly 9 cells, tab-separated
//   - Empty / malformed rows are silently dropped (parser is forgiving so
//     a single bad asset row never bricks startup)
// =============================================================================

void main() {
  group('parseDictTsv', () {
    test('parses well-formed 9-column TSV with header and comments', () {
      const tsv = '# fluera-dict v1 lang=en built=2026-05-19 rows=2\n'
          '# schema=word,freq_rank,pos,domains,root,cefr,concrete,aoa,flags\n'
          'word\tfreq_rank\tpos\tdomains\troot\tcefr\tconcrete\taoa\tflags\n'
          'a\t6\tdet\t-\t-\tA1\t-\t-\t-\n'
          'anatomy\t8420\tn\tmed,stem\t-\tB2\t4.10\t11.20\t-\n';
      final rows = parseDictTsv(tsv);
      expect(rows, hasLength(2));

      expect(rows[0].word, 'a');
      expect(rows[0].freqRank, 6);
      expect(rows[0].pos, 'det');
      expect(rows[0].domains, isEmpty);
      expect(rows[0].cefrRaw, 'A1');
      expect(rows[0].concrete, isNull);

      expect(rows[1].word, 'anatomy');
      expect(rows[1].freqRank, 8420);
      expect(rows[1].pos, 'n');
      expect(rows[1].domains, ['med', 'stem']);
      expect(rows[1].cefrRaw, 'B2');
      expect(rows[1].concrete, 4.10);
      expect(rows[1].aoa, 11.20);
    });

    test('skips rows with the wrong cell count', () {
      // 8-cell body row (missing trailing flags column) must be dropped.
      const tsv = 'word\tfreq_rank\tpos\tdomains\troot\tcefr\tconcrete\taoa\tflags\n'
          'broken\t1\tn\t-\t-\t-\t-\t-\n'
          'good\t2\tv\t-\t-\t-\t-\t-\t-\n';
      final rows = parseDictTsv(tsv);
      expect(rows, hasLength(1));
      expect(rows[0].word, 'good');
    });

    test('treats `-` as null/empty across all optional columns', () {
      const tsv = 'word\tfreq_rank\tpos\tdomains\troot\tcefr\tconcrete\taoa\tflags\n'
          'foo\t1\tn\t-\t-\t-\t-\t-\t-\n';
      final r = parseDictTsv(tsv).single;
      expect(r.domains, isEmpty);
      expect(r.root, isNull);
      expect(r.cefrRaw, isNull);
      expect(r.concrete, isNull);
      expect(r.aoa, isNull);
      expect(r.flags, isEmpty);
    });

    test('rejects rows with non-positive freq_rank', () {
      const tsv = 'word\tfreq_rank\tpos\tdomains\troot\tcefr\tconcrete\taoa\tflags\n'
          'zero\t0\tn\t-\t-\t-\t-\t-\t-\n'
          'neg\t-3\tn\t-\t-\t-\t-\t-\t-\n'
          'ok\t1\tn\t-\t-\t-\t-\t-\t-\n';
      final rows = parseDictTsv(tsv);
      expect(rows.map((r) => r.word), ['ok']);
    });

    test('tolerates blank lines and a trailing newline', () {
      const tsv = 'word\tfreq_rank\tpos\tdomains\troot\tcefr\tconcrete\taoa\tflags\n'
          '\n'
          'a\t6\tdet\t-\t-\t-\t-\t-\t-\n'
          '\n';
      final rows = parseDictTsv(tsv);
      expect(rows, hasLength(1));
      expect(rows[0].word, 'a');
    });

    test('handles CRLF line endings', () {
      const tsv = 'word\tfreq_rank\tpos\tdomains\troot\tcefr\tconcrete\taoa\tflags\r\n'
          'a\t6\tdet\t-\t-\t-\t-\t-\t-\r\n';
      final rows = parseDictTsv(tsv);
      expect(rows, hasLength(1));
      expect(rows[0].word, 'a');
    });

    test('multi-valued csv-in-cell domains and flags split correctly', () {
      const tsv = 'word\tfreq_rank\tpos\tdomains\troot\tcefr\tconcrete\taoa\tflags\n'
          'tort\t9000\tn\tlaw\t-\tC1\t-\t-\t-\n'
          'fuck\t2100\tv\t-\t-\tC1\t-\t-\tprof,slur\n';
      final rows = parseDictTsv(tsv);
      expect(rows[0].domains, ['law']);
      expect(rows[1].flags, ['prof', 'slur']);
    });
  });

  group('DictEntry', () {
    test('isProfane true when any of prof/slur/sexual flags set', () {
      const profOnly = DictEntry(word: 'a', freqRank: 1, pos: 'n', flags: {'prof'});
      const slur = DictEntry(word: 'a', freqRank: 1, pos: 'n', flags: {'slur'});
      const sexual = DictEntry(word: 'a', freqRank: 1, pos: 'n', flags: {'sexual'});
      const none = DictEntry(word: 'a', freqRank: 1, pos: 'n');
      expect(profOnly.isProfane, isTrue);
      expect(slur.isProfane, isTrue);
      expect(sexual.isProfane, isTrue);
      expect(none.isProfane, isFalse);
    });
  });

  group('cefrFromString', () {
    test('maps case-insensitive level labels', () {
      expect(cefrFromString('A1'), CefrLevel.a1);
      expect(cefrFromString('a2'), CefrLevel.a2);
      expect(cefrFromString('C2'), CefrLevel.c2);
    });
    test('returns null for empty / sentinel / unknown', () {
      expect(cefrFromString(null), isNull);
      expect(cefrFromString(''), isNull);
      expect(cefrFromString('-'), isNull);
      expect(cefrFromString('zz'), isNull);
    });
  });

  group('integration with real Stage 1 emission', () {
    test('a body row from the real en.tsv asset parses', () {
      // Synthetic line exactly matching the fluera-dict v1 emitter output
      // for the most common entry. Keeps the test hermetic (no rootBundle).
      const realRow = 'a\t6\tdet\t-\t-\t-\t-\t-\t-';
      final r = parseDictRow(realRow);
      expect(r, isNotNull);
      expect(r!.word, 'a');
      expect(r.freqRank, 6);
      expect(r.pos, 'det');
    });
  });
}
