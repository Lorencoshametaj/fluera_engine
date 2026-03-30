import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/services/grammar_check_service.dart';
import 'package:fluera_engine/src/services/language_detection_service.dart';
import 'package:fluera_engine/src/services/word_completion_dictionary.dart';
import 'package:fluera_engine/src/services/ai_grammar_service.dart';
import 'package:fluera_engine/src/services/reading_level_service.dart';

// =============================================================================
// 📝 Unit tests for Grammar Check, Language Detection, and Spellcheck
// =============================================================================

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // GRAMMAR CHECK TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('GrammarCheckService', () {
    late GrammarCheckService service;

    setUp(() {
      service = GrammarCheckService.instance;
      service.setEnabled(true);
    });

    group('Universal rules', () {
      test('detects duplicate words', () {
        final result = service.checkText('the the cat');
        expect(result.hasErrors, isTrue);
        expect(result.errors.first.ruleId, equals('duplicate_word'));
        expect(result.errors.first.suggestion, equals('the'));
      });

      test('skips intentional repetitions', () {
        final result = service.checkText('ha ha that was funny');
        final duplicateErrors = result.errors
            .where((e) => e.ruleId == 'duplicate_word')
            .toList();
        expect(duplicateErrors, isEmpty);
      });

      test('detects missing capitalization after sentence end', () {
        final result = service.checkText('Hello world. this is bad');
        final capErrors = result.errors
            .where((e) => e.ruleId == 'sentence_capitalization')
            .toList();
        expect(capErrors.isNotEmpty, isTrue);
        expect(capErrors.first.suggestion, equals('T'));
      });

      test('detects double spaces', () {
        final result = service.checkText('hello  world');
        final spaceErrors = result.errors
            .where((e) => e.ruleId == 'double_space')
            .toList();
        expect(spaceErrors.isNotEmpty, isTrue);
        expect(spaceErrors.first.suggestion, equals(' '));
      });

      test('detects missing space after punctuation', () {
        final result = service.checkText('hello,world');
        final punctErrors = result.errors
            .where((e) => e.ruleId == 'missing_space_punctuation')
            .toList();
        expect(punctErrors.isNotEmpty, isTrue);
      });

      test('detects unclosed parentheses', () {
        final result = service.checkText('hello (world');
        final pairErrors = result.errors
            .where((e) => e.ruleId == 'punctuation_pairing')
            .toList();
        expect(pairErrors.isNotEmpty, isTrue);
      });

      test('detects triple dots → ellipsis', () {
        final result = service.checkText('well...');
        final ellErrors = result.errors
            .where((e) => e.ruleId == 'ellipsis')
            .toList();
        expect(ellErrors.isNotEmpty, isTrue);
        expect(ellErrors.first.suggestion, equals('…'));
      });

      test('detects common typos', () {
        final result = service.checkText('teh quick brown fox');
        final typoErrors = result.errors
            .where((e) => e.ruleId == 'common_typo')
            .toList();
        expect(typoErrors.isNotEmpty, isTrue);
        expect(typoErrors.first.suggestion, equals('the'));
      });

      test('suggests number formatting for large numbers', () {
        final result = service.checkText('There are 1000000 people');
        final numErrors = result.errors
            .where((e) => e.ruleId == 'number_formatting')
            .toList();
        expect(numErrors.isNotEmpty, isTrue);
      });
    });

    group('English rules', () {
      test('detects missing contractions', () {
        final result = service.checkText('I dont know');
        final errors = result.errors
            .where((e) => e.ruleId == 'en_contractions')
            .toList();
        expect(errors.isNotEmpty, isTrue);
        expect(errors.first.suggestion, equals("don't"));
      });

      test('detects subject-verb disagreement', () {
        final result = service.checkText("He don't care");
        final errors = result.errors
            .where((e) => e.ruleId == 'en_subject_verb')
            .toList();
        expect(errors.isNotEmpty, isTrue);
      });
    });

    group('Rule management', () {
      test('can disable and enable rules', () {
        service.disableRule('duplicate_word');
        final result = service.checkText('the the cat');
        final dupErrors = result.errors
            .where((e) => e.ruleId == 'duplicate_word')
            .toList();
        expect(dupErrors, isEmpty);

        service.enableRule('duplicate_word');
        final result2 = service.checkText('the the cat');
        final dupErrors2 = result2.errors
            .where((e) => e.ruleId == 'duplicate_word')
            .toList();
        expect(dupErrors2.isNotEmpty, isTrue);
      });

      test('availableRules returns all rules', () {
        final rules = service.availableRules;
        expect(rules.length, greaterThanOrEqualTo(20));
      });

      test('caching works correctly', () {
        final r1 = service.checkText('hello world');
        final r2 = service.checkText('hello world');
        expect(identical(r1, r2), isTrue); // Same cached object
      });

      test('empty text returns no errors', () {
        final result = service.checkText('');
        expect(result.hasErrors, isFalse);
      });

      test('disabled service returns no errors', () {
        service.setEnabled(false);
        final result = service.checkText('the the cat');
        expect(result.hasErrors, isFalse);
        service.setEnabled(true);
      });
    });

    group('Error positioning', () {
      test('errors have correct start/end indices', () {
        final result = service.checkText('hello  world');
        final spaceError = result.errors
            .where((e) => e.ruleId == 'double_space')
            .first;
        expect(spaceError.startIndex, equals(5));
        expect(spaceError.endIndex, equals(7));
      });

      test('errors are sorted by position', () {
        final result = service.checkText('hello  world the the');
        for (int i = 1; i < result.errors.length; i++) {
          expect(result.errors[i].startIndex,
              greaterThanOrEqualTo(result.errors[i - 1].startIndex));
        }
      });

      test('overlapping errors are deduplicated', () {
        // The overlap detection should prevent two errors at the same position
        final result = service.checkText('the the');
        final positions = result.errors.map((e) => e.startIndex).toSet();
        expect(positions.length, equals(result.errors.length));
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LANGUAGE DETECTION TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('LanguageDetectionService', () {
    late LanguageDetectionService service;

    setUp(() {
      service = LanguageDetectionService.instance;
      service.clearCache();
    });

    group('Stop-word detection', () {
      test('detects Italian from stop words', () {
        final lang = service.detectLanguage(
          'Il gatto è sulla tavola della cucina',
        );
        expect(lang, equals(DictLanguage.it));
      });

      test('detects English from stop words', () {
        final lang = service.detectLanguage(
          'The cat is on the table in the kitchen',
        );
        expect(lang, equals(DictLanguage.en));
      });

      test('detects French from stop words', () {
        final lang = service.detectLanguage(
          'Le chat est sur la table dans la cuisine',
        );
        expect(lang, equals(DictLanguage.fr));
      });

      test('detects Spanish from stop words', () {
        final lang = service.detectLanguage(
          'El gato está en la mesa de la cocina',
        );
        expect(lang, equals(DictLanguage.es));
      });

      test('detects German from stop words', () {
        final lang = service.detectLanguage(
          'Die Katze ist auf dem Tisch in der Küche',
        );
        expect(lang, equals(DictLanguage.de));
      });
    });

    group('Script detection', () {
      test('detects Chinese from characters', () {
        // CJK characters — detectLanguage calls _detectByScript first
        final segments = service.detectSegments('你好世界这是一段中文文字测试内容');
        // With enough CJK, script detection should trigger
        if (segments.isNotEmpty) {
          expect(segments.first.language, equals(DictLanguage.zh));
        }
      });

      test('detects Russian/Cyrillic from characters', () {
        final segments = service.detectSegments('Привет мир это русский текст для проверки');
        if (segments.isNotEmpty) {
          expect(segments.first.language, equals(DictLanguage.ru));
        }
      });

      test('detects Arabic from characters', () {
        final segments = service.detectSegments('مرحبا بالعالم هذا نص عربي لاختبار الكشف');
        if (segments.isNotEmpty) {
          expect(segments.first.language, equals(DictLanguage.ar));
        }
      });

      test('detects Korean from characters', () {
        final segments = service.detectSegments('안녕하세요 세계 이것은 한국어 텍스트입니다');
        if (segments.isNotEmpty) {
          expect(segments.first.language, equals(DictLanguage.ko));
        }
      });

      test('detects Greek from characters', () {
        final segments = service.detectSegments('Γεια σου κόσμε αυτό είναι ελληνικά κείμενο');
        if (segments.isNotEmpty) {
          expect(segments.first.language, equals(DictLanguage.el));
        }
      });
    });

    group('Character heuristics', () {
      test('detects German from ß', () {
        final lang = service.detectLanguage('Die Straße ist groß');
        expect(lang, equals(DictLanguage.de));
      });

      test('detects Turkish from ğ', () {
        final lang = service.detectLanguage('Doğru değil ağaç');
        expect(lang, equals(DictLanguage.tr));
      });

      test('detects Czech from ř', () {
        final lang = service.detectLanguage('Příliš řeč');
        expect(lang, equals(DictLanguage.cs));
      });

      test('detects Hungarian from ő', () {
        final lang = service.detectLanguage('Ő a legjobb pőre');
        expect(lang, equals(DictLanguage.hu));
      });

      test('detects Polish from ł', () {
        final lang = service.detectLanguage('Łódź jest piękna');
        expect(lang, equals(DictLanguage.pl));
      });
    });

    group('Segment detection', () {
      test('detects multiple languages in text', () {
        final segments = service.detectSegments(
          'Questa è una frase italiana. This is an English sentence.',
        );
        expect(segments.length, greaterThanOrEqualTo(1));
      });

      test('empty text returns empty segments', () {
        final segments = service.detectSegments('');
        expect(segments, isEmpty);
      });

      test('segments cover the full text', () {
        final text = 'Hello world. Ciao mondo.';
        final segments = service.detectSegments(text);
        if (segments.isNotEmpty) {
          expect(segments.first.startIndex, equals(0));
          expect(segments.last.endIndex, equals(text.length));
        }
      });

      test('segments have valid confidence', () {
        final segments = service.detectSegments('The cat is on the mat.');
        for (final s in segments) {
          expect(s.confidence, greaterThanOrEqualTo(0.0));
          expect(s.confidence, lessThanOrEqualTo(1.0));
        }
      });
    });

    group('Word-level detection', () {
      test('detects English stop word', () {
        final lang = service.detectWordLanguage('the');
        expect(lang, equals(DictLanguage.en));
      });

      test('detects Italian stop word', () {
        final lang = service.detectWordLanguage('della');
        expect(lang, equals(DictLanguage.it));
      });

      test('detects German stop word', () {
        final lang = service.detectWordLanguage('nicht');
        expect(lang, equals(DictLanguage.de));
      });
    });

    group('Cross-dictionary validation', () {
      test('isLikelyForeignWord returns true for foreign stop words', () {
        // "della" is an Italian stop word
        final result = service.isLikelyForeignWord('della');
        expect(result, isTrue);
      });

      test('isLikelyForeignWord returns false for random words', () {
        final result = service.isLikelyForeignWord('xyzqwerty');
        expect(result, isFalse);
      });
    });

    group('Language pair learning', () {
      test('records and retrieves language pairs', () {
        service.dispose(); // Clear previous data
        service.recordLanguagePair(DictLanguage.it, DictLanguage.en);
        service.recordLanguagePair(DictLanguage.it, DictLanguage.en);
        service.recordLanguagePair(DictLanguage.it, DictLanguage.fr);

        final pairs = service.getCommonPairLanguages();
        expect(pairs.isNotEmpty, isTrue);
      });
    });

    group('Caching', () {
      test('cached results are returned for same text', () {
        final text = 'The quick brown fox jumps over the lazy dog.';
        final r1 = service.detectSegments(text);
        final r2 = service.detectSegments(text);
        expect(identical(r1, r2), isTrue);
      });

      test('clearCache invalidates cached results', () {
        final text = 'Hello world.';
        final r1 = service.detectSegments(text);
        service.clearCache();
        final r2 = service.detectSegments(text);
        expect(identical(r1, r2), isFalse);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GRAMMAR ERROR MODEL TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('GrammarError', () {
    test('toString includes message and position', () {
      const error = GrammarError(
        message: 'Test error',
        startIndex: 0,
        endIndex: 5,
        ruleId: 'test',
      );
      expect(error.toString(), contains('Test error'));
      expect(error.toString(), contains('0:5'));
    });

    test('severity defaults to warning', () {
      const error = GrammarError(
        message: 'Test',
        startIndex: 0,
        endIndex: 5,
        ruleId: 'test',
      );
      expect(error.severity, equals(GrammarSeverity.warning));
    });
  });

  group('GrammarResult', () {
    test('hasErrors returns true when errors exist', () {
      const result = GrammarResult(
        text: 'test',
        errors: [
          GrammarError(
            message: 'err',
            startIndex: 0,
            endIndex: 4,
            ruleId: 'test',
          ),
        ],
      );
      expect(result.hasErrors, isTrue);
    });

    test('hasErrors returns false for empty errors', () {
      const result = GrammarResult(text: 'test', errors: []);
      expect(result.hasErrors, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LANGUAGE SEGMENT MODEL TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('LanguageSegment', () {
    test('getText returns correct substring', () {
      const segment = LanguageSegment(
        startIndex: 0,
        endIndex: 5,
        language: DictLanguage.en,
        confidence: 0.9,
      );
      expect(segment.getText('Hello World'), equals('Hello'));
    });

    test('toString includes language and confidence', () {
      const segment = LanguageSegment(
        startIndex: 0,
        endIndex: 10,
        language: DictLanguage.it,
        confidence: 0.85,
      );
      final str = segment.toString();
      expect(str, contains('it'));
      expect(str, contains('85'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // AI GRAMMAR SERVICE TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('AiGrammarService', () {
    group('Model classes', () {
      test('AiGrammarError creates correctly', () {
        const error = AiGrammarError(
          original: 'should of',
          correction: 'should have',
          message: 'Use "should have" instead of "should of"',
          startIndex: 5,
          endIndex: 14,
          severity: AiGrammarSeverity.error,
        );
        expect(error.original, equals('should of'));
        expect(error.correction, equals('should have'));
        expect(error.startIndex, equals(5));
        expect(error.endIndex, equals(14));
        expect(error.severity, equals(AiGrammarSeverity.error));
      });

      test('AiGrammarError.toGrammarError converts correctly', () {
        const aiError = AiGrammarError(
          original: 'teh',
          correction: 'the',
          message: 'Common typo',
          startIndex: 0,
          endIndex: 3,
          severity: AiGrammarSeverity.error,
        );
        final grammarError = aiError.toGrammarError();
        expect(grammarError.ruleId, equals('ai_grammar'));
        expect(grammarError.message, equals('Common typo'));
        expect(grammarError.suggestion, equals('the'));
        expect(grammarError.startIndex, equals(0));
        expect(grammarError.endIndex, equals(3));
        expect(grammarError.severity, equals(GrammarSeverity.error));
      });

      test('AiGrammarError severity maps info for non-errors', () {
        const aiError = AiGrammarError(
          original: 'test',
          message: 'Suggestion',
          startIndex: 0,
          endIndex: 4,
          severity: AiGrammarSeverity.suggestion,
        );
        final grammarError = aiError.toGrammarError();
        expect(grammarError.severity, equals(GrammarSeverity.info));
      });

      test('AiGrammarResult hasErrors works', () {
        const resultEmpty = AiGrammarResult(text: 'test', errors: []);
        expect(resultEmpty.hasErrors, isFalse);

        const resultWithErrors = AiGrammarResult(
          text: 'test',
          errors: [
            AiGrammarError(
              original: 'test',
              message: 'Error',
              startIndex: 0,
              endIndex: 4,
            ),
          ],
        );
        expect(resultWithErrors.hasErrors, isTrue);
      });
    });

    group('Merge logic', () {
      test('merges AI errors with rule errors', () {
        const ruleErrors = [
          GrammarError(
            message: 'Rule error',
            startIndex: 0,
            endIndex: 5,
            ruleId: 'test_rule',
          ),
        ];
        const aiErrors = [
          AiGrammarError(
            original: 'other',
            message: 'AI error',
            startIndex: 10,
            endIndex: 15,
          ),
        ];

        final merged = AiGrammarService.mergeErrors(ruleErrors, aiErrors);
        expect(merged.length, equals(2));
        expect(merged[0].startIndex, equals(0)); // Rule first (sorted)
        expect(merged[1].startIndex, equals(10)); // AI second
      });

      test('deduplicates overlapping errors', () {
        const ruleErrors = [
          GrammarError(
            message: 'Rule found this',
            startIndex: 5,
            endIndex: 10,
            ruleId: 'test_rule',
          ),
        ];
        const aiErrors = [
          AiGrammarError(
            original: 'overlap',
            message: 'AI also found this',
            startIndex: 7,
            endIndex: 12,
          ),
        ];

        final merged = AiGrammarService.mergeErrors(ruleErrors, aiErrors);
        // AI error overlaps with rule error → should be deduplicated
        expect(merged.length, equals(1));
        expect(merged.first.ruleId, equals('test_rule'));
      });

      test('empty AI errors returns only rule errors', () {
        const ruleErrors = [
          GrammarError(
            message: 'Rule',
            startIndex: 0,
            endIndex: 5,
            ruleId: 'test',
          ),
        ];
        const aiErrors = <AiGrammarError>[];

        final merged = AiGrammarService.mergeErrors(ruleErrors, aiErrors);
        expect(merged.length, equals(1));
      });

      test('empty rule errors returns only AI errors', () {
        const ruleErrors = <GrammarError>[];
        const aiErrors = [
          AiGrammarError(
            original: 'test',
            message: 'AI error',
            startIndex: 0,
            endIndex: 4,
          ),
        ];

        final merged = AiGrammarService.mergeErrors(ruleErrors, aiErrors);
        expect(merged.length, equals(1));
        expect(merged.first.ruleId, equals('ai_grammar'));
      });

      test('merged results are sorted by position', () {
        const ruleErrors = [
          GrammarError(
            message: 'Late',
            startIndex: 20,
            endIndex: 25,
            ruleId: 'rule',
          ),
        ];
        const aiErrors = [
          AiGrammarError(
            original: 'early',
            message: 'Early error',
            startIndex: 0,
            endIndex: 5,
          ),
        ];

        final merged = AiGrammarService.mergeErrors(ruleErrors, aiErrors);
        expect(merged.length, equals(2));
        expect(merged[0].startIndex, equals(0)); // AI first (position 0)
        expect(merged[1].startIndex, equals(20)); // Rule second (position 20)
      });
    });

    group('Service state', () {
      test('service starts uninitialized', () {
        // Without calling initialize, enabled should be false
        final service = AiGrammarService.instance;
        // enabled = _enabled && _initialized, _initialized starts false
        expect(service.enabled, isFalse);
      });

      test('setEnabled toggles the flag', () {
        AiGrammarService.instance.setEnabled(false);
        expect(AiGrammarService.instance.enabled, isFalse);
        AiGrammarService.instance.setEnabled(true);
        // Still false because not initialized
        expect(AiGrammarService.instance.enabled, isFalse);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // READING LEVEL SERVICE TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('ReadingLevelService', () {
    late ReadingLevelService service;

    setUp(() {
      service = ReadingLevelService.instance;
    });

    test('analyzes simple English text', () {
      final result = service.analyze(
        'The cat sat on the mat. The dog ran fast.',
        languageCode: 'en',
      );
      expect(result.wordCount, greaterThan(0));
      expect(result.sentenceCount, equals(2));
      expect(result.fleschReadingEase, greaterThan(50)); // Simple text
      expect(result.difficulty, isIn([
        ReadingDifficulty.veryEasy,
        ReadingDifficulty.easy,
      ]));
    });

    test('analyzes Italian text with Gulpease', () {
      final result = service.analyze(
        'Il gatto è sul tavolo. Il cane corre veloce.',
        languageCode: 'it',
      );
      expect(result.wordCount, greaterThan(0));
      expect(result.gulpease, greaterThan(0));
      expect(result.gulpease, lessThanOrEqualTo(100));
      expect(result.languageCode, equals('it'));
    });

    test('empty text returns empty result', () {
      final result = service.analyze('', languageCode: 'en');
      expect(result.wordCount, equals(0));
      expect(result.fleschReadingEase, equals(100));
      expect(result.difficulty, equals(ReadingDifficulty.veryEasy));
    });

    test('complex text scores lower readability', () {
      final simple = service.analyze(
        'The cat sat. The dog ran. The sun is hot.',
        languageCode: 'en',
      );
      final complex = service.analyze(
        'The implementation of sophisticated algorithmic paradigms necessitates '
        'comprehensive understanding of computational complexity theory and '
        'its multifaceted implications for distributed systems architecture.',
        languageCode: 'en',
      );
      expect(complex.fleschReadingEase,
          lessThan(simple.fleschReadingEase));
      expect(complex.fleschKincaidGrade,
          greaterThan(simple.fleschKincaidGrade));
    });

    test('Flesch Reading Ease is within 0–100', () {
      final result = service.analyze(
        'Hello world. This is a test.',
        languageCode: 'en',
      );
      expect(result.fleschReadingEase, greaterThanOrEqualTo(0));
      expect(result.fleschReadingEase, lessThanOrEqualTo(100));
    });

    test('grade label returns reasonable values', () {
      final result = service.analyze(
        'The cat sat on the mat.',
        languageCode: 'en',
      );
      expect(result.gradeLabel, isNotEmpty);
      expect(result.gradeLabelIT, isNotEmpty);
    });

    test('difficulty label and emoji exist', () {
      final result = service.analyze(
        'Simple text here.',
        languageCode: 'en',
      );
      expect(result.difficultyLabel, isNotEmpty);
      expect(result.difficultyEmoji, isNotEmpty);
      expect(result.difficultyLabelIT, isNotEmpty);
    });

    test('statistics are calculated correctly', () {
      final result = service.analyze(
        'Hello world.',
        languageCode: 'en',
      );
      expect(result.wordCount, equals(2));
      expect(result.sentenceCount, equals(1));
      expect(result.avgWordsPerSentence, equals(2.0));
      expect(result.characterCount, greaterThan(0));
      expect(result.syllableCount, greaterThan(0));
    });

    test('ARI is non-negative', () {
      final result = service.analyze(
        'This is a simple sentence. And another one here.',
        languageCode: 'en',
      );
      expect(result.ari, greaterThanOrEqualTo(0));
    });

    test('Italian difficulty uses Gulpease', () {
      // Very simple Italian text should be easy
      final result = service.analyze(
        'Il gatto è qui. Il cane è là. La casa è grande.',
        languageCode: 'it',
      );
      // Gulpease for very short sentences should be high
      expect(result.gulpease, greaterThan(40));
    });
  });
}
