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
  });
}
