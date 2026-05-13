// ============================================================================
// 🧪 UNIT TESTS — Socratic Output Filter (G2 Guardrail)
//
// QA Criteria: CA-A2-01 → CA-A2-08
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_output_filter.dart';

void main() {
  group('SocraticOutputFilter', () {
    // ── Clean questions (should pass) ─────────────────────────────────────

    group('valid Socratic questions pass', () {
      test('simple Italian question', () {
        final result =
            SocraticOutputFilter.scanQuestion('Come pensi che funzioni?');
        expect(result.passed, isTrue);
      });

      test('elaboration question', () {
        final result = SocraticOutputFilter.scanQuestion(
            'Puoi spiegare questo concetto con le tue parole?');
        expect(result.passed, isTrue);
      });

      test('English question', () {
        final result = SocraticOutputFilter.scanQuestion(
            'What do you think happens when X increases?');
        expect(result.passed, isTrue);
      });

      test('multi-clause question', () {
        final result = SocraticOutputFilter.scanQuestion(
            'Se questa variabile cambia, cosa succede al risultato finale?');
        expect(result.passed, isTrue);
      });
    });

    // ── Missing question mark (A2-06) ────────────────────────────────────

    group('missing question mark detection (A2-06)', () {
      test('detects missing question mark', () {
        final result = SocraticOutputFilter.scanQuestion(
            'Come pensi che funzioni');
        expect(result.passed, isFalse);
        expect(result.violationType,
            OutputViolationType.missingQuestionMark);
      });

      test('auto-corrects missing question mark', () {
        final result = SocraticOutputFilter.scanQuestion(
            'Come pensi che funzioni');
        final corrected = SocraticOutputFilter.tryAutoCorrect(result);
        expect(corrected, 'Come pensi che funzioni?');
      });
    });

    // ── Declaration violations (A2-04) ───────────────────────────────────

    group('declaration violations', () {
      test('catches Italian declaration "X è un Y"', () {
        final result = SocraticOutputFilter.scanQuestion(
            'La fotosintesi è un processo chimico?');
        expect(result.passed, isFalse);
        expect(result.violationType, OutputViolationType.declaration);
      });

      test('catches English declaration "X is a Y"', () {
        final result = SocraticOutputFilter.scanQuestion(
            'Mitosis is a process of cell division?');
        expect(result.passed, isFalse);
        expect(result.violationType, OutputViolationType.declaration);
      });

      test('cannot auto-correct declarations', () {
        final result = SocraticOutputFilter.scanQuestion(
            'La fotosintesi è un processo chimico?');
        final corrected = SocraticOutputFilter.tryAutoCorrect(result);
        expect(corrected, isNull);
      });

      // Device 2026-05-12: model enunciated the principle in a
      // declarative premise before the question, giving away the
      // content the student should retrieve (Generation Effect
      // violation — Slamecka & Graf 1978).
      test('catches "X afferma che Y. Ma se Z..."', () {
        final result = SocraticOutputFilter.scanQuestion(
            'La prima legge di Newton afferma che un corpo a riposo '
            'rimane a riposo. Ma se il corpo è già in moto uniforme, '
            'cosa implica la prima legge?');
        expect(result.passed, isFalse);
        expect(result.violationType, OutputViolationType.declaration);
      });

      test('catches "Sai che F=ma. Ma se..." opener', () {
        final result = SocraticOutputFilter.scanQuestion(
            'Sai che F=ma. Ma se la massa varia nel tempo, F=ma è '
            'ancora valida?');
        expect(result.passed, isFalse);
        expect(result.violationType, OutputViolationType.declaration);
      });

      test('catches "X stabilisce che Y" theorem statement', () {
        final result = SocraticOutputFilter.scanQuestion(
            'Il teorema di Pitagora stabilisce che la somma dei '
            'quadrati dei cateti è uguale al quadrato dell\'ipotenusa. '
            'Cosa succede in geometria sferica?');
        expect(result.passed, isFalse);
        expect(result.violationType, OutputViolationType.declaration);
      });

      // True challenge framing — no enunciation premise. Should pass.
      test('challenge without enunciation premise PASSES', () {
        final result = SocraticOutputFilter.scanQuestion(
            'In un ascensore in caduta libera, un corpo è davvero '
            'a riposo secondo la prima legge?');
        expect(result.passed, isTrue);
      });
    });

    // ── Direct answer violations ─────────────────────────────────────────

    group('direct answer violations', () {
      test('catches "ecco la risposta"', () {
        final result = SocraticOutputFilter.scanQuestion(
            'Ecco la risposta che cercavi?');
        expect(result.passed, isFalse);
        expect(result.violationType, OutputViolationType.directAnswer);
      });

      test('catches "the answer is"', () {
        final result = SocraticOutputFilter.scanQuestion(
            'The answer is photosynthesis?');
        expect(result.passed, isFalse);
        expect(result.violationType, OutputViolationType.directAnswer);
      });
    });

    // ── Definition violations ────────────────────────────────────────────

    group('definition violations', () {
      test('catches "X significa"', () {
        final result = SocraticOutputFilter.scanQuestion(
            'Osmosi significa il passaggio di acqua?');
        expect(result.passed, isFalse);
        expect(result.violationType, OutputViolationType.definition);
      });

      test('catches "is defined as"', () {
        final result = SocraticOutputFilter.scanQuestion(
            'Entropy is defined as disorder?');
        expect(result.passed, isFalse);
        expect(result.violationType, OutputViolationType.definition);
      });
    });

    // ── Batch scanning ───────────────────────────────────────────────────

    group('batch scanning', () {
      test('scans multiple questions preserving order', () {
        final results = SocraticOutputFilter.scanBatch([
          'Come funziona?',
          'La fotosintesi è un processo?', // violation
          'Cosa pensi succeda?',
        ]);
        expect(results.length, 3);
        expect(results[0].passed, isTrue);
        expect(results[1].passed, isFalse);
        expect(results[2].passed, isTrue);
      });
    });

    // ── Fallback question (A2-05) ────────────────────────────────────────

    test('fallback question is pedagogically safe', () {
      expect(SocraticOutputFilter.fallbackQuestion,
          'Puoi spiegare questo concetto con le tue parole?');
      // The fallback itself must pass the filter!
      final check = SocraticOutputFilter.scanQuestion(
          SocraticOutputFilter.fallbackQuestion);
      expect(check.passed, isTrue);
    });

    // ── Violation log (A2-07) ────────────────────────────────────────────

    group('violation logging (A2-07)', () {
      setUp(() => SocraticOutputFilter.clearLog());

      test('logs violations', () {
        SocraticOutputFilter.scanQuestion(
            'The answer is mitochondria?');
        expect(SocraticOutputFilter.violationLog.length, 1);
        expect(SocraticOutputFilter.violationLog.first.type,
            OutputViolationType.directAnswer);
      });

      test('does not log clean questions', () {
        SocraticOutputFilter.scanQuestion('Come funziona?');
        expect(SocraticOutputFilter.violationLog.length, 0);
      });

      test('log entries serialize to JSON', () {
        SocraticOutputFilter.scanQuestion('The answer is X?');
        final json = SocraticOutputFilter.violationLog.first.toJson();
        expect(json['violation_type'], 'directAnswer');
        expect(json['original_output'], isNotEmpty);
        expect(json['timestamp'], isNotNull);
      });
    });

    // ──────────────────────────────────────────────────────────────────
    // Device 2026-05-10: 3 legitimate Socratic questions were rejected
    // as "declaration" because:
    //   - "Qual" (apocope of "Quale") wasn't in the interrogative regex
    //   - `\b` after accented chars like "é" fails in Dart ASCII regex
    // The V2 backup regex (`_interrogativeRegexV2`) covers both cases.
    // ──────────────────────────────────────────────────────────────────
    group('Device 2026-05-10 — Italian interrogative edge cases', () {
      setUp(SocraticOutputFilter.clearLog);

      test('"Qual è la relazione…" is recognised as interrogative', () {
        final result = SocraticOutputFilter.scanQuestion(
          "Qual è la relazione tra la legge di Newton e il concetto di inerzia?",
        );
        expect(result.passed, isTrue,
            reason: 'Qual è is a question, not a declaration');
      });

      test('"Qual è il meccanismo fisico…" is recognised as interrogative',
          () {
        final result = SocraticOutputFilter.scanQuestion(
          "Qual è il meccanismo fisico per cui l'azione e la reazione si manifestano insieme?",
        );
        expect(result.passed, isTrue);
      });

      test('"Perché un corpo…" matches even with accented opener', () {
        final result = SocraticOutputFilter.scanQuestion(
          "Perché un corpo a riposo rimane a riposo in assenza di forza risultante?",
        );
        expect(result.passed, isTrue,
            reason: 'Perché should match the interrogative alternation '
                'despite the accented é breaking ASCII boundary');
      });

      test('Statement appended with "?" is STILL flagged (no over-accept)',
          () {
        // Defense-in-depth: the V2 regex must not over-accept. A clear
        // declaration appended with "?" should still be caught.
        final result = SocraticOutputFilter.scanQuestion(
          'La fotosintesi è un processo metabolico che genera ossigeno?',
        );
        expect(result.passed, isFalse,
            reason: 'Declaration with trailing ? is not a Socratic question');
      });
    });

    // ── Sprint F.3 (2026-05-13) — relative pronoun regression ──────────────
    // Device repro: G2 was flagging "un oggetto che è un CORPO A RIPOSO" as
    // a declaration because "che è un X" matched the IT declaration regex.
    // "che" as RELATIVE pronoun introduces a clause, not a declarative
    // statement. The regex was tightened with negative lookahead to exclude
    // che/that/which/cui/cosa/qual/chi from being the SUBJECT of a match.
    group('G2 declaration filter — relative pronoun exclusion (Sprint F.3)',
        () {
      test('"un oggetto che è un CORPO A RIPOSO" NOT flagged as declaration',
          () {
        final result = SocraticOutputFilter.scanQuestion(
          "Immagina un oggetto che è un CORPO A RIPOSO. Quale condizione "
          "fondamentale devono soddisfare le forze che agiscono su di esso?",
        );
        expect(result.passed, isTrue,
            reason:
                'IT relative "che è" must not trigger declaration regex — '
                'scenario-setting clause, not declaration');
      });

      test('"an object that is a body at rest" NOT flagged (EN relative)',
          () {
        final result = SocraticOutputFilter.scanQuestion(
          'Imagine an object that is a body at rest on a frictionless '
          'surface. What conditions must the forces satisfy?',
        );
        expect(result.passed, isTrue,
            reason: 'EN relative "that is" must not trigger declaration regex');
      });

      test('"...sistema che è in equilibrio" NOT flagged (IT relative)', () {
        final result = SocraticOutputFilter.scanQuestion(
          "Considera un sistema che è in equilibrio termodinamico — "
          "cosa puoi dedurre sulla variazione di entropia?",
        );
        expect(result.passed, isTrue,
            reason: 'Relative clause inside a question must pass');
      });

      test('"Newton è un fisico italiano" STILL flagged (legit IT declaration)',
          () {
        final result = SocraticOutputFilter.scanQuestion(
          "Newton è un fisico italiano nato nel 1643.",
        );
        expect(result.passed, isFalse,
            reason:
                'Genuine declarative statement (subject + è + article + noun) '
                'must still be caught');
        expect(result.violationType, OutputViolationType.declaration);
      });

      test('"Force is a vector quantity" STILL flagged (legit EN declaration)',
          () {
        final result = SocraticOutputFilter.scanQuestion(
          'Force is a vector quantity with both magnitude and direction.',
        );
        expect(result.passed, isFalse,
            reason: 'Genuine EN declaration must still be caught');
        expect(result.violationType, OutputViolationType.declaration);
      });
    });
  });
}
