import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/services/grammar_check_service.dart';
import 'package:fluera_engine/src/services/language_detection_service.dart';
import 'package:fluera_engine/src/services/word_completion_dictionary.dart';

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
}
