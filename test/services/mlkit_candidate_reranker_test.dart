import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/services/ink_recognition_engine.dart'
    show InkCandidate;
import 'package:fluera_engine/src/services/mlkit_candidate_reranker.dart';

InkCandidate _c(String text, double score) =>
    InkCandidate(text: text, score: score);

void main() {
  setUp(() {
    MlKitCandidateReranker.resetForTesting();
  });

  group('MlKitCandidateReranker — empty inputs', () {
    test('empty candidate list returns null', () async {
      final out = await MlKitCandidateReranker.pickByDictionary(
        const [],
        langCode: 'it',
      );
      expect(out, isNull);
    });

    test('single candidate skips dictionary work and returns its text',
        () async {
      // Note: no dictionary seeded — pickByDictionary must still succeed
      // because the single-candidate short-circuit fires first.
      final out = await MlKitCandidateReranker.pickByDictionary(
        [_c('qualsiasi', 0)],
        langCode: 'it',
      );
      expect(out, equals('qualsiasi'));
    });
  });

  group('MlKitCandidateReranker — re-rank promotes dictionary hit', () {
    test('Italian: top non-dict candidate is overruled by lower dict hit',
        () async {
      // Real failure mode from device test 2026-05-10: cursive "prima legge"
      // fused into a non-word "Primalele" as top candidate.
      MlKitCandidateReranker.seedDictionaryForTesting(
        'it',
        {'prima', 'legge', 'leggi', 'ciao', 'mondo'},
      );

      final out = await MlKitCandidateReranker.pickByDictionary([
        _c('Primalele', 0), // ML Kit's top — score 0
        _c('prima legge', 1), // candidate #2 — both words in dict, score 1.0
        _c('prim alegge', 2), // candidate #3 — 1 word in dict, score 0.5
      ], langCode: 'it');

      expect(out, equals('prima legge'));
    });

    test('English: dictionary file naming via lang code works', () async {
      MlKitCandidateReranker.seedDictionaryForTesting(
        'en',
        {'hello', 'world', 'test'},
      );

      final out = await MlKitCandidateReranker.pickByDictionary([
        _c('helo wrld', 0), // non-words
        _c('hello world', 1), // both in dict
      ], langCode: 'en');

      expect(out, equals('hello world'));
    });
  });

  group('MlKitCandidateReranker — defensive behaviour', () {
    test('no dict loaded → falls back to ML Kit top candidate', () async {
      // Use a langCode for which no asset can be loaded in test env.
      // Seed an EMPTY dictionary (treated as load-failure) so the
      // reranker hits the fallback path deterministically.
      MlKitCandidateReranker.seedDictionaryForTesting('zz', <String>{});

      final out = await MlKitCandidateReranker.pickByDictionary([
        _c('top pick', 0),
        _c('alt pick', 1),
      ], langCode: 'zz');

      // Without a dict, the top candidate must win regardless of "quality".
      expect(out, equals('top pick'));
    });

    test('top candidate already a dict hit → preserved on true tie',
        () async {
      // Use words of identical length so length-weighted scoring produces
      // a true tie (otherwise length bonus would break the tie).
      MlKitCandidateReranker.seedDictionaryForTesting(
        'it',
        {'ciao', 'salu'}, // both 4 letters
      );
      final out = await MlKitCandidateReranker.pickByDictionary([
        _c('ciao', 0),
        _c('salu', 1), // identical weight → tie
      ], langCode: 'it');

      // Tie-break: ML Kit's #0 wins. We only override on STRICTLY better.
      expect(out, equals('ciao'));
    });

    test('no candidate matches dict → keeps ML Kit top', () async {
      MlKitCandidateReranker.seedDictionaryForTesting(
        'it',
        {'ciao', 'mondo'},
      );
      final out = await MlKitCandidateReranker.pickByDictionary([
        _c('proper noun', 0), // 0 hits
        _c('other text', 1), // 0 hits
      ], langCode: 'it');

      expect(out, equals('proper noun'),
          reason: 'Falls back to ML Kit top when no dict hits anywhere');
    });

    test('candidates with digits / LaTeX residue are ineligible (not scored)',
        () async {
      MlKitCandidateReranker.seedDictionaryForTesting('en', {'hello'});
      final out = await MlKitCandidateReranker.pickByDictionary([
        _c('hello', 0), // 1/1 hits → score 1.0
        _c('a1b2 c3d4', 1), // both contain digits → 0 eligible → score 0.0
      ], langCode: 'en');

      expect(out, equals('hello'));
    });

    test('short words (<3 chars) are skipped from scoring', () async {
      MlKitCandidateReranker.seedDictionaryForTesting('it', {'casa'});
      final out = await MlKitCandidateReranker.pickByDictionary([
        _c('a io e', 0), // all <3 chars → 0 eligible
        _c('casa di', 1), // 'casa' eligible+hit; 'di' skipped → score 1.0
      ], langCode: 'it');

      expect(out, equals('casa di'));
    });
  });

  group('MlKitCandidateReranker — case insensitivity', () {
    test('candidate text in mixed case still matches lowercased dict',
        () async {
      MlKitCandidateReranker.seedDictionaryForTesting('it', {'newton'});
      final out = await MlKitCandidateReranker.pickByDictionary([
        _c('garbled', 0),
        _c('Newton', 1), // Capitalised proper noun must match lowercase dict
      ], langCode: 'it');

      expect(out, equals('Newton'));
    });
  });

  group('MlKitCandidateReranker — length-weighted scoring', () {
    test('long dict hit outscores short dict hit on equal coverage',
        () async {
      // Both candidates have 1/1 dict hits, but the longer match should
      // win because length weight is higher.
      MlKitCandidateReranker.seedDictionaryForTesting(
        'it',
        {'biologia', 'che'}, // 8-letter vs 3-letter
      );
      final out = await MlKitCandidateReranker.pickWithFuzzy([
        _c('che', 0), // 1/1 hits, weight 1.0
        _c('biologia', 1), // 1/1 hits, weight ~1.7
      ], langCode: 'it', applyFuzzy: false);

      expect(out, equals('biologia'),
          reason: 'Long dict match must beat short on same coverage');
    });
  });

  group('MlKitCandidateReranker — personal vocab boost', () {
    test('personal-vocab term wins over generic-dict candidate', () async {
      // Generic dict has "casa" (common word). Personal vocab has "neuroni"
      // (domain-specific). The candidate containing "neuroni" should win
      // even though "casa" is in the baseline dictionary.
      MlKitCandidateReranker.seedDictionaryForTesting('it', {'casa'});
      final out = await MlKitCandidateReranker.pickWithFuzzy([
        _c('casa importante', 0), // 1 dict hit + 1 non-hit → 0.5
        _c('neuroni piramidali', 1), // 2 personal-vocab hits → boosted
      ], langCode: 'it',
          personalVocab: {'neuroni', 'piramidali'},
          applyFuzzy: false);

      expect(out, equals('neuroni piramidali'),
          reason: 'Personal vocab boost must promote domain terms');
    });

    test('personal-vocab as fallback when not in baseline dict', () async {
      // Word IS in personal vocab but NOT in baseline dict — should still
      // count as a hit (not flagged for fuzzy correction).
      MlKitCandidateReranker.seedDictionaryForTesting('it', {'la', 'casa'});
      final out = await MlKitCandidateReranker.pickWithFuzzy([
        _c('la apoptosi cellulare', 0),
      ],
          langCode: 'it',
          personalVocab: {'apoptosi', 'cellulare'},
          applyFuzzy: true);

      // Best is unchanged (personal vocab hits prevent fuzzy correction).
      expect(out, equals('la apoptosi cellulare'));
    });
  });

  group('MlKitCandidateReranker — fuzzy per-word correction', () {
    test('low-score candidate gets per-word fuzzy-corrected', () async {
      // Real failure mode: ML Kit recognises "ciamo" instead of "ciao",
      // "modno" instead of "mondo". No candidate matches dict directly.
      MlKitCandidateReranker.seedDictionaryForTesting(
        'it',
        {'ciao', 'mondo', 'come', 'stai'},
      );
      final out = await MlKitCandidateReranker.pickWithFuzzy([
        _c('ciamo modno', 0), // edit distance 1 from "ciao mondo"
      ], langCode: 'it', applyFuzzy: true);

      // Both words should be fuzzy-corrected (distance ≤2 → dict match).
      expect(out, equals('ciao mondo'));
    });

    test('fuzzy skips when re-rank score is already above threshold',
        () async {
      // Top candidate scores 1.0 (all words in dict). Fuzzy shouldn't fire.
      MlKitCandidateReranker.seedDictionaryForTesting(
        'it',
        {'ciao', 'mondo'},
      );
      final out = await MlKitCandidateReranker.pickWithFuzzy([
        _c('ciao mondo', 0), // score 1.0 — above threshold
      ], langCode: 'it', applyFuzzy: true, fuzzyThreshold: 0.5);

      expect(out, equals('ciao mondo'));
    });

    test('fuzzy keeps words too far from any dict entry', () async {
      MlKitCandidateReranker.seedDictionaryForTesting(
        'it',
        {'ciao'},
      );
      final out = await MlKitCandidateReranker.pickWithFuzzy([
        _c('xqzpwv', 0), // distance > 2 from "ciao" — should NOT be replaced
      ], langCode: 'it', applyFuzzy: true);

      expect(out, equals('xqzpwv'));
    });

    test('fuzzy preserves Capitalised casing', () async {
      MlKitCandidateReranker.seedDictionaryForTesting('en', {'newton'});
      final out = await MlKitCandidateReranker.pickWithFuzzy([
        _c('Newotn', 0), // typo, distance 1 from "newton"
      ], langCode: 'en', applyFuzzy: true);

      expect(out, equals('Newton'), reason: 'First-letter cap preserved');
    });

    test('fuzzy preserves ALL-CAPS casing', () async {
      MlKitCandidateReranker.seedDictionaryForTesting('it', {'fisica'});
      final out = await MlKitCandidateReranker.pickWithFuzzy([
        _c('FSICA', 0), // distance 1 from "fisica"
      ], langCode: 'it', applyFuzzy: true);

      expect(out, equals('FISICA'));
    });

    test('fuzzy skips very-short words (<4 chars) to avoid noise', () async {
      MlKitCandidateReranker.seedDictionaryForTesting(
        'it',
        {'casa', 'cosa'},
      );
      final out = await MlKitCandidateReranker.pickWithFuzzy([
        _c('xyz', 0), // 3 chars — unsafe to fuzzy-correct
      ], langCode: 'it', applyFuzzy: true);

      expect(out, equals('xyz'), reason: 'Very short words left alone');
    });

    test('fuzzy still applies length-weighted score above threshold',
        () async {
      // If half the words are dict hits and half aren't, score = 0.5 which
      // is at the threshold (strictly below required). Above 0.5 → skip;
      // below → fix. This verifies the boundary behaviour.
      MlKitCandidateReranker.seedDictionaryForTesting(
        'it',
        {'biologia', 'cellulare'},
      );
      // "biologia xxxx" → 1/2 eligible, weight ~1.7/2 → ~0.85 score → skip
      final out = await MlKitCandidateReranker.pickWithFuzzy([
        _c('biologia xxxx', 0),
      ], langCode: 'it', applyFuzzy: true);
      expect(out, equals('biologia xxxx'),
          reason: 'Long-word weight bumps score above fuzzy threshold');
    });
  });

  // Damerau-Levenshtein algorithm tests were removed in Stage 2 (2026-05-19)
  // when the reranker stopped owning its private edit-distance implementation
  // and delegated fuzzy correction to `WordCompletionDictionary.suggestCorrections`.
  // The fuzzy-correction tests above (group "fuzzy per-word correction")
  // continue to cover the end-to-end behaviour through that path.
}
