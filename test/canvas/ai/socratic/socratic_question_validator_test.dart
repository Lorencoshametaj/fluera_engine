// ============================================================================
// 🛡️ SocraticQuestionValidator — single-gate validation tests.
//
// Verifies the consolidated validator handles:
//   • Empty / too-short → reject
//   • Generic ceremonial → reject
//   • Language drift → retry
//   • Cross-language (source ≠ target) → accept
//   • Source unknown + question matches target → accept
//   • Same-language anchor/elaboration/comparative + no overlap → retry
//   • Same-language scenario stages + no overlap → accept
//   • Same-language + overlap → accept
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_model.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_question_validator.dart';

SocraticQuestionValidator _v({
  String targetLang = 'en',
  String clusterTopic = 'Newtons Laws of Motion',
  String? clusterRawOcr,
  SocraticStage stage = SocraticStage.anchor,
  SocraticQuestionType type = SocraticQuestionType.lacuna,
}) =>
    SocraticQuestionValidator(
      targetLang: targetLang,
      clusterTopic: clusterTopic,
      clusterRawOcr: clusterRawOcr,
      stage: stage,
      type: type,
    );

void main() {
  group('Empty / short input', () {
    test('empty string → reject', () {
      expect(_v().validate('').outcome, ValidationOutcome.reject);
    });
    test('whitespace only → reject', () {
      expect(_v().validate('   ').outcome, ValidationOutcome.reject);
    });
    test('too short → reject', () {
      expect(_v().validate('Hi?').outcome, ValidationOutcome.reject);
    });
  });

  group('Generic ceremonial → reject', () {
    test('EN "what can you tell me"', () {
      final result = _v().validate(
          'What can you tell me about Newton in your own words?');
      expect(result.outcome, ValidationOutcome.reject);
      expect(result.reason, 'generic_ceremonial');
    });
    test('IT "cosa puoi spiegare"', () {
      final result = _v(targetLang: 'it', clusterTopic: 'Leggi di Newton')
          .validate('Cosa puoi spiegare con le tue parole di Newton?');
      expect(result.outcome, ValidationOutcome.reject);
    });
  });

  group('Language drift → retry', () {
    test('EN question on IT target', () {
      final result = _v(
        targetLang: 'it',
        clusterTopic: 'Leggi di Newton',
        clusterRawOcr: 'le leggi di newton sulla dinamica',
      ).validate(
          'What is the meaning of the first law of motion in physics?');
      expect(result.outcome, ValidationOutcome.retry);
      expect(result.reason, 'language_drift');
    });
  });

  group('Cross-language → accept', () {
    test('EN question on IT source (confident cross-lang)', () {
      final result = _v(
        targetLang: 'en',
        clusterTopic: 'Leggi di Newton',
        clusterRawOcr: 'le leggi di newton sulla dinamica del moto',
      ).validate(
          'How would you explain the first law of motion to a friend?');
      expect(result.outcome, ValidationOutcome.accept);
      expect(result.reason, 'cross_language');
    });
    test('Source unknown + question matches target', () {
      // "Primo principio termodinamica" has 0 function words → unknown.
      final result = _v(
        targetLang: 'en',
        clusterTopic: 'Primo principio termodinamica',
        clusterRawOcr: 'Primo principio termodinamica',
      ).validate(
          'How would you explain the first law of thermodynamics?');
      expect(result.outcome, ValidationOutcome.accept);
      expect(result.reason, 'cross_language');
    });
  });

  group('Same-language no overlap', () {
    test('anchor stage → retry (direct-mention required)', () {
      // Cluster source has EN function words so srcLang=='en' (matches
      // target). Question has no concept overlap (no "photosynthesis"/
      // "chloroplast"/"leaf"). Anchor stage requires direct mention.
      final result = _v(
        targetLang: 'en',
        clusterTopic: 'photosynthesis in chloroplasts',
        clusterRawOcr:
            'the process of photosynthesis happens in the chloroplasts '
            'of the plant leaves where light energy is converted',
        stage: SocraticStage.anchor,
      ).validate(
          'What comes to mind when you consider the matter at hand right now?');
      expect(result.outcome, ValidationOutcome.retry);
      expect(result.reason, 'no_specificity');
    });
    test('counterfactual stage → accept (scenario stem)', () {
      final result = _v(
        targetLang: 'en',
        clusterTopic: 'photosynthesis in chloroplasts',
        clusterRawOcr:
            'the process of photosynthesis happens in the chloroplasts '
            'of the plant leaves where light energy is converted',
        stage: SocraticStage.counterfactual,
      ).validate(
          'Imagine an astronaut in deep space with no plants. How could '
          'they synthesize their own oxygen, and what would the bottleneck '
          'be in such a system?');
      expect(result.outcome, ValidationOutcome.accept);
    });
  });

  group('Same-language with overlap → accept', () {
    test('EN question mentions cluster concept', () {
      final result = _v(
        targetLang: 'en',
        clusterTopic: 'photosynthesis in chloroplasts',
        clusterRawOcr:
            'the process of photosynthesis happens in the chloroplasts '
            'of the plant leaves where light energy is converted',
        stage: SocraticStage.anchor,
      ).validate(
          'When you think about photosynthesis, what is the first '
          'mechanism that comes to mind?');
      expect(result.outcome, ValidationOutcome.accept);
      expect(result.reason, 'overlap_match');
    });
    test('IT question mentions cluster concept', () {
      final result = _v(
        targetLang: 'it',
        clusterTopic: 'leggi di newton',
        clusterRawOcr: 'le leggi di newton sulla dinamica',
        stage: SocraticStage.elaboration,
      ).validate('Perché la prima legge di newton vale anche nello '
          'spazio profondo, secondo la tua intuizione?');
      expect(result.outcome, ValidationOutcome.accept);
    });
  });

  group('Edge: empty topic pool', () {
    test('clusterTopic empty + question generic → accept (no concept to match)',
        () {
      final result = _v(
        targetLang: 'en',
        clusterTopic: '',
        stage: SocraticStage.anchor,
      ).validate('What comes to mind first about the topic?');
      expect(result.outcome, ValidationOutcome.accept);
    });
  });
}
