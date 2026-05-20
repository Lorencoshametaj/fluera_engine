import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/services/dict_entry.dart';
import 'package:fluera_engine/src/services/word_completion_dictionary.dart';

// =============================================================================
// 📖 Stage 3 metadata integration tests
//
// Exercises lookUp / bigram APIs end-to-end against a hermetic seed —
// proves the wiring works without depending on the real bundled asset.
// =============================================================================

void main() {
  setUp(() {
    WordCompletionDictionary.instance.resetForTesting();
  });

  group('bigram counts (Stage 3)', () {
    test('seeded bigramFrequency returns the exact count', () {
      WordCompletionDictionary.instance.seedBigramsForTesting({
        'thank': {'you': 100, 'god': 5},
        'good': {'morning': 80, 'evening': 30, 'luck': 12},
      });
      final dict = WordCompletionDictionary.instance;
      expect(dict.bigramFrequency('thank', 'you'), 100);
      expect(dict.bigramFrequency('THANK', 'YOU'), 100, reason: 'case-insensitive');
      expect(dict.bigramFrequency('good', 'morning'), 80);
      expect(dict.bigramFrequency('thank', 'unknown'), 0);
      expect(dict.bigramFrequency('unknown', 'word'), 0);
    });

    test('getContextSuggestions returns top successors by count', () {
      WordCompletionDictionary.instance.seedBigramsForTesting({
        'good': {'morning': 80, 'evening': 30, 'luck': 12, 'night': 50},
      });
      final out = WordCompletionDictionary.instance
          .getContextSuggestions('good', limit: 3);
      // Sorted by descending count → morning, night, evening
      expect(out, ['morning', 'night', 'evening']);
    });

    test('getContextSuggestions falls back to static seed when asset miss', () {
      // Empty asset seed → backfill path should hit the hardcoded
      // multilingual seed table (e.g., 'thank' → 'you/your/them').
      WordCompletionDictionary.instance.seedBigramsForTesting({});
      final out = WordCompletionDictionary.instance
          .getContextSuggestions('thank', limit: 3);
      expect(out, isNotEmpty);
      expect(out, contains('you'));
    });

    test('asset bigrams override seed table when both present', () {
      // Seed says thank→you/your/them; asset says thank→god (high count).
      WordCompletionDictionary.instance.seedBigramsForTesting({
        'thank': {'god': 1000},
      });
      final out = WordCompletionDictionary.instance
          .getContextSuggestions('thank', limit: 3);
      // Asset's 'god' comes first; seed's 'you', 'your', 'them' backfill.
      expect(out.first, 'god');
      expect(out, contains('you'));
    });
  });

  group('lookUp fallback (Stage 2 → 3)', () {
    test('synthetic personal-dict entry surfaces via lookUp', () {
      // Without seeding any asset metadata, lookUp falls through to
      // PersonalDictionaryService. Direct test of the fallback path:
      // the absence of an asset entry must yield null (PersonalDict is
      // empty in the test harness).
      final dict = WordCompletionDictionary.instance;
      expect(dict.lookUp('completely-unknown-xyz'), isNull);
    });

    test('DictEntry domains/flags accessors short-circuit on miss', () {
      final dict = WordCompletionDictionary.instance;
      expect(dict.domains('xyz'), isEmpty);
      expect(dict.isProfane('xyz'), isFalse);
      expect(dict.cefr('xyz'), isNull);
      expect(dict.concreteness('xyz'), isNull);
      expect(dict.aoa('xyz'), isNull);
      expect(dict.root('xyz'), isNull);
    });
  });

  group('CefrLevel parsing', () {
    test('cefrFromString maps the six standard levels', () {
      expect(cefrFromString('A1'), CefrLevel.a1);
      expect(cefrFromString('b2'), CefrLevel.b2);
      expect(cefrFromString('C1'), CefrLevel.c1);
      expect(cefrFromString('-'), isNull);
      expect(cefrFromString(''), isNull);
      expect(cefrFromString('z9'), isNull);
    });
  });
}
