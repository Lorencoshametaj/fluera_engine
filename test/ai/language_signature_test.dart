// ============================================================================
// 🌍 Language signature detector — language-agnostic drift detection tests.
//
// Validates:
//   - detectLanguageSignature returns correct ISO 639-1 code for IT/ES/FR/DE/PT/EN
//   - Mixed scientific content (loanwords like DNA, ATP) is identified by
//     function-word signature, not by the loanwords themselves
//   - Short / ambiguous text returns 'unknown' (conservative — accept)
//   - socraticLanguageDriftsFromSource detects cross-language drift
//   - The device repro (IT counterfactual with "restare/profondo") does
//     NOT trigger drift (was a false positive with substring matching)
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/ai_provider.dart';

void main() {
  group('detectLanguageSignature — IT', () {
    test('Plain Italian sentence', () {
      expect(
        detectLanguageSignature(
          'La prima legge di Newton afferma che un corpo permane nel suo stato di quiete.',
        ),
        'it',
      );
    });

    test('IT scientific notes (loanwords + function words)', () {
      expect(
        detectLanguageSignature(
          'I mitocondri sintetizzano ATP attraverso la fosforilazione ossidativa.',
        ),
        'it',
      );
    });

    test('IT accented characters strengthen signal', () {
      expect(
        detectLanguageSignature(
          'L\'energia cinetica di un corpo è proporzionale al quadrato della velocità.',
        ),
        'it',
      );
    });
  });

  group('detectLanguageSignature — EN', () {
    test('Plain English sentence', () {
      expect(
        detectLanguageSignature(
          'Newton\'s first law states that an object at rest stays at rest unless acted upon by a net force.',
        ),
        'en',
      );
    });

    test('Classic FCI counterfactual (the device repro)', () {
      expect(
        detectLanguageSignature(
          'Imagine an astronaut in deep space gives a small object a push. '
          'If it were true that motion requires a continuous force, what would happen?',
        ),
        'en',
      );
    });
  });

  group('detectLanguageSignature — other Tier-1 languages', () {
    test('Spanish (diacritic + function words)', () {
      expect(
        detectLanguageSignature(
          'La primera ley de Newton establece que un cuerpo en reposo permanece en reposo. ¿Por qué?',
        ),
        'es',
      );
    });

    test('French', () {
      expect(
        detectLanguageSignature(
          'La première loi de Newton stipule qu\'un corps au repos reste au repos.',
        ),
        'fr',
      );
    });

    test('German', () {
      expect(
        detectLanguageSignature(
          'Das erste Newtonsche Gesetz besagt, dass ein Körper in Ruhe bleibt.',
        ),
        'de',
      );
    });

    test('Portuguese', () {
      expect(
        detectLanguageSignature(
          'A primeira lei de Newton afirma que um corpo em repouso permanece em repouso.',
        ),
        'pt',
      );
    });
  });

  group('detectLanguageSignature — edge cases', () {
    test('Empty string → unknown', () {
      expect(detectLanguageSignature(''), 'unknown');
    });

    test('Very short ambiguous text → unknown', () {
      expect(detectLanguageSignature('Newton'), 'unknown');
    });

    test('Single-language formula only → unknown (no function words)', () {
      expect(detectLanguageSignature('F=ma E=mc²'), 'unknown');
    });
  });

  group('socraticLanguageDriftsFromSource', () {
    test('Device repro 2026-05-12: IT counterfactual with "restare/profondo" '
        '→ NO drift (was false positive with substring matching)', () {
      final question = 'Considera l\'ipotesi che un corpo in moto richieda una '
          'forza continua per restare in moto. Se un astronauta nello spazio '
          'profondo dà un calcio a una piccola sfera, cosa dovrebbe succedere '
          'alla sfera dopo il calcio?';
      final source = 'Leggi di Newton prima corpo a riposo seconda legge';
      expect(
        socraticLanguageDriftsFromSource(question, source),
        isFalse,
        reason: 'IT question on IT source is NOT drift — fixes substring bug',
      );
    });

    test('EN counterfactual on IT source → drift detected', () {
      final question = 'Imagine an astronaut in deep space gives a small object '
          'a push. If it were true that motion requires a continuous force, what '
          'would happen to the object?';
      final source = 'Leggi di Newton prima corpo a riposo seconda legge';
      expect(
        socraticLanguageDriftsFromSource(question, source),
        isTrue,
      );
    });

    test('EN question on EN source → NO drift', () {
      final question = 'What comes to mind first when you think about Newton\'s '
          'first law of motion?';
      final source = 'Newton\'s laws of motion: body at rest, net force, '
          'second law F=ma';
      expect(
        socraticLanguageDriftsFromSource(question, source),
        isFalse,
      );
    });

    test('ES question on ES source → NO drift (extensibility check)', () {
      final question = 'Considera la hipótesis de que un cuerpo en movimiento '
          'requiere una fuerza continua para mantenerse en movimiento.';
      final source = 'Primera ley de Newton, los cuerpos en reposo, la fuerza neta.';
      expect(
        socraticLanguageDriftsFromSource(question, source),
        isFalse,
      );
    });

    test('Short ambiguous source → NO drift (conservative)', () {
      final question = 'What is X?';
      final source = 'X';
      expect(
        socraticLanguageDriftsFromSource(question, source),
        isFalse,
        reason: 'unknown source language → accept by default',
      );
    });
  });
}
