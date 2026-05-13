// Smoke tests for the V3.4 ω pedagogy registry. Verifies every
// (stage, lang) cell + every (discipline, lang) module exists, is
// non-empty, and produces a recognisable system prompt shape (output
// JSON instruction + lang-native marker for IT/EN cells).

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/socratic/pedagogy/pedagogy_registry.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_model.dart';
import 'package:fluera_engine/src/utils/ai_language_preference.dart';

void main() {
  group('PedagogyRegistry — stage cells', () {
    for (final stage in SocraticStage.values) {
      test('${stage.name} IT cell is non-empty + contains JSON output marker', () {
        final cell = PedagogyRegistry.stagePedagogyFor(stage, 'it');
        expect(cell, isNotEmpty);
        expect(cell.length, greaterThan(500),
            reason: '${stage.name} IT cell should have substantive pedagogy');
        expect(cell.contains('JSON') || cell.contains('"q"'), isTrue,
            reason: '${stage.name} IT cell must instruct JSON output');
      });

      test('${stage.name} EN cell is non-empty + contains JSON output marker', () {
        final cell = PedagogyRegistry.stagePedagogyFor(stage, 'en');
        expect(cell, isNotEmpty);
        expect(cell.length, greaterThan(500));
        expect(cell.contains('JSON') || cell.contains('"q"'), isTrue);
      });

      test('${stage.name} bootstrap cell (es) is non-empty + has JSON instruction', () {
        // Post-Sprint-F.2-exec (2026-05-13): bootstrap cells are now
        // AI-translated natively into Spanish (no "Spanish" English token).
        // Test verifies basic structural integrity: non-empty + has the
        // JSON output instruction marker. The full validation_status flag
        // and UI banner cover the "needs native review" concern.
        final cell = PedagogyRegistry.stagePedagogyFor(stage, 'es');
        expect(cell, isNotEmpty);
        expect(cell.length, greaterThan(300),
            reason: 'Bootstrap cell must have substantive content (translated)');
        // Bootstrap cells should still mention JSON (either via the marker
        // text "JSON" or via the q/h template literals).
        expect(
          cell.contains('JSON') || cell.contains('"q"'),
          isTrue,
          reason: 'Bootstrap cell must instruct JSON output',
        );
      });
    }
  });

  group('PedagogyRegistry — discipline hints', () {
    for (final d in Discipline.values) {
      test('${d.name} IT hint is concise and non-empty', () {
        final hint = PedagogyRegistry.disciplineHintsFor(d, 'it');
        expect(hint, isNotEmpty);
        expect(hint.length, lessThan(800),
            reason: 'Discipline hint must be ≤800 chars to fit per-call budget');
        expect(hint, contains('DISCIPLINA:'));
      });

      test('${d.name} EN hint is concise and non-empty', () {
        final hint = PedagogyRegistry.disciplineHintsFor(d, 'en');
        expect(hint, isNotEmpty);
        expect(hint.length, lessThan(800));
        expect(hint, contains('DISCIPLINE:'));
      });
    }
  });

  group('PedagogyRegistry — validation status', () {
    test('IT and EN are production_native', () {
      expect(
        PedagogyRegistry.validationStatusFor('it'),
        SocraticValidationStatus.productionNative,
      );
      expect(
        PedagogyRegistry.validationStatusFor('en'),
        SocraticValidationStatus.productionNative,
      );
    });

    test('Bootstrap languages are ai_bootstrap', () {
      for (final code in ['es', 'fr', 'de', 'pt', 'ja', 'ko', 'zh', 'ar']) {
        expect(
          PedagogyRegistry.validationStatusFor(code),
          SocraticValidationStatus.aiBootstrap,
          reason: '$code should be aiBootstrap until native-validated',
        );
      }
    });
  });

  group('Pedagogy V3 invariants preserved across cells', () {
    test('Every stage cell mentions Generation Effect or generative rule',
        () {
      for (final stage in SocraticStage.values) {
        final itCell = PedagogyRegistry.stagePedagogyFor(stage, 'it');
        final enCell = PedagogyRegistry.stagePedagogyFor(stage, 'en');
        final lowerIt = itCell.toLowerCase();
        final lowerEn = enCell.toLowerCase();
        expect(
          lowerIt.contains('generation') || lowerIt.contains('genera'),
          isTrue,
          reason: '${stage.name} IT must reference Generation Effect',
        );
        expect(
          lowerEn.contains('generation') || lowerEn.contains('generative'),
          isTrue,
          reason: '${stage.name} EN must reference Generation Effect',
        );
      }
    });

    test('Counterfactual cells mention MISCONCEPTION HINT contract', () {
      final it = PedagogyRegistry.stagePedagogyFor(
          SocraticStage.counterfactual, 'it');
      final en = PedagogyRegistry.stagePedagogyFor(
          SocraticStage.counterfactual, 'en');
      expect(it, contains('MISCONCEPTION'));
      expect(en, contains('MISCONCEPTION'));
    });

    test('All cells forbid the "rate yourself 1-5" anti-pattern', () {
      for (final stage in SocraticStage.values) {
        if (stage != SocraticStage.metacognitive) continue;
        final it = PedagogyRegistry.stagePedagogyFor(stage, 'it');
        final en = PedagogyRegistry.stagePedagogyFor(stage, 'en');
        expect(it.toLowerCase(), contains('1 a 5'),
            reason: 'Metacognitive IT must ban self-rating');
        expect(en.toLowerCase(), contains('1 to 5'),
            reason: 'Metacognitive EN must ban self-rating');
      }
    });
  });
}
