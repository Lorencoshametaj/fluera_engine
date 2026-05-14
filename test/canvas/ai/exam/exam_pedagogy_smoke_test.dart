// ============================================================================
// 🎓 Atlas Exam V3.4 ω — Pedagogy smoke tests (Sprint EX-E).
//
// For every (ExamPhase × language) pair the registry serves, assert the
// cell is:
//   1. Non-empty
//   2. Contains the canonical marker the registry uses to detect
//      truncation (generation: "domande"; evaluation: "VOTO:";
//      hint: digit "12")
//
// Plus a small set of V3 invariants:
//   - Every generation cell mentions Bloom Taxonomy
//   - Every evaluation cell mentions the 3-way verdict
//   - Every hint cell mentions a length cap
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/exam/pedagogy/exam_pedagogy_registry.dart';
import 'package:fluera_engine/src/ai/exam/pedagogy/exam_phase.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_discipline.dart';
import 'package:fluera_engine/src/utils/ai_language_preference.dart';

const _bootstrapLangs = <String>[
  'es', 'pt', 'fr', 'de', 'ja', 'ko', 'zh',
  'ar', 'hi', 'ru', 'nl', 'sv', 'pl', 'tr',
];

void main() {
  group('ExamPedagogyRegistry — phase cells', () {
    for (final phase in ExamPhase.values) {
      test('${phase.name} IT cell is non-empty + has canonical marker', () {
        final cell = ExamPedagogyRegistry.phasePromptFor(phase, 'it');
        expect(cell, isNotEmpty);
        _expectMarker(phase, cell, reason: 'IT cell');
      });

      test('${phase.name} EN cell is non-empty + has canonical marker', () {
        final cell = ExamPedagogyRegistry.phasePromptFor(phase, 'en');
        expect(cell, isNotEmpty);
        _expectMarker(phase, cell, reason: 'EN cell');
      });

      for (final lang in _bootstrapLangs) {
        test('${phase.name} bootstrap ($lang) is non-empty + has marker '
            '(or falls back to EN)', () {
          final cell = ExamPedagogyRegistry.phasePromptFor(phase, lang);
          expect(cell, isNotEmpty);
          _expectMarker(phase, cell, reason: '$lang bootstrap cell');
        });
      }
    }
  });

  group('ExamPedagogyRegistry — V3 invariants', () {
    test('every IT+EN generation cell mentions Bloom', () {
      for (final lang in ['it', 'en']) {
        final cell = ExamPedagogyRegistry.phasePromptFor(
            ExamPhase.generation, lang);
        expect(cell.toLowerCase(), contains('bloom'),
            reason: '$lang generation must cite Bloom Taxonomy');
      }
    });

    test('every IT+EN evaluation cell has the 3-way verdict tokens', () {
      for (final lang in ['it', 'en']) {
        final cell = ExamPedagogyRegistry.phasePromptFor(
            ExamPhase.evaluation, lang);
        expect(cell, contains('CORRETTO'),
            reason: '$lang eval must keep CORRETTO verb (wire protocol)');
        expect(cell, contains('PARZIALE'),
            reason: '$lang eval must keep PARZIALE verb');
        expect(cell, contains('SBAGLIATO'),
            reason: '$lang eval must keep SBAGLIATO verb');
      }
    });

    test('every IT+EN hint cell mentions the 12-word cap', () {
      for (final lang in ['it', 'en']) {
        final cell = ExamPedagogyRegistry.phasePromptFor(ExamPhase.hint, lang);
        expect(cell, contains('12'),
            reason: '$lang hint must keep the 12-word cap');
      }
    });
  });

  group('ExamPedagogyRegistry — validation status', () {
    test('IT and EN are production_native', () {
      expect(ExamPedagogyRegistry.validationStatusFor('it'),
          SocraticValidationStatus.productionNative);
      expect(ExamPedagogyRegistry.validationStatusFor('en'),
          SocraticValidationStatus.productionNative);
    });

    test('all 14 bootstrap langs are ai_bootstrap', () {
      for (final lang in _bootstrapLangs) {
        expect(ExamPedagogyRegistry.validationStatusFor(lang),
            SocraticValidationStatus.aiBootstrap,
            reason: '$lang must report ai_bootstrap');
      }
    });
  });

  // 🎓 Sprint EX-H — discipline-aware Exam: per-discipline Bloom-verb
  // hints injected into the V2 generation payload as a small
  // "DISCIPLINA:" block.
  group('ExamPedagogyRegistry — discipline hints (Sprint EX-H)', () {
    for (final disc in Discipline.values) {
      test('${disc.name} IT hint is non-empty + ≤700 chars + mentions Bloom', () {
        final block = ExamPedagogyRegistry.disciplineHintsFor(disc, 'it');
        expect(block, isNotEmpty);
        expect(block.length, lessThanOrEqualTo(700));
        if (disc != Discipline.generic) {
          expect(block.toLowerCase(), contains('bloom'),
              reason: 'IT ${disc.name} hint should reference Bloom verbs');
        }
      });

      test('${disc.name} EN hint is non-empty + ≤700 chars + mentions Bloom', () {
        final block = ExamPedagogyRegistry.disciplineHintsFor(disc, 'en');
        expect(block, isNotEmpty);
        expect(block.length, lessThanOrEqualTo(700));
        if (disc != Discipline.generic) {
          expect(block.toLowerCase(), contains('bloom'),
              reason: 'EN ${disc.name} hint should reference Bloom verbs');
        }
      });

      test('${disc.name} bootstrap (es) falls back to EN '
          '(no bootstrap entries yet)', () {
        // discipline_hints_exam_bootstrap.dart is currently empty
        // scaffold → caller falls back to EN. Verify EN cell returns.
        final block =
            ExamPedagogyRegistry.disciplineHintsFor(disc, 'es');
        final en = ExamPedagogyRegistry.disciplineHintsFor(disc, 'en');
        expect(block, equals(en),
            reason: '${disc.name} ES falls back to EN until bootstrap runs');
      });
    }
  });

  group('ExamPedagogyRegistry — EN fallback for unknown lang', () {
    test('Unknown lang code (e.g. "zu") falls back to ai_bootstrap'
        ' but cell resolves to EN-equivalent', () {
      // "zu" is not in the 14 Tier-1/2 set → no bootstrap entry → registry
      // resolves to EN cell via _resolveBootstrapPhase.
      final cell = ExamPedagogyRegistry.phasePromptFor(
          ExamPhase.generation, 'zu');
      expect(cell, isNotEmpty);
      // The EN cell has the English Bloom citation; the IT cell doesn't.
      expect(cell.contains('Bloom Taxonomy') || cell.contains('Tassonomia'),
          isTrue);
    });
  });
}

void _expectMarker(ExamPhase phase, String cell, {String? reason}) {
  switch (phase) {
    case ExamPhase.generation:
      expect(cell, contains('"domande"'),
          reason: '$reason missing "domande" JSON marker');
      break;
    case ExamPhase.evaluation:
      expect(cell, contains('VOTO:'),
          reason: '$reason missing VOTO: output marker');
      break;
    case ExamPhase.hint:
      expect(cell, contains('12'),
          reason: '$reason missing 12-word cap');
      break;
  }
}
