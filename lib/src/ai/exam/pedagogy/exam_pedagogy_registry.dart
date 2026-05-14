// 🎓 ExamPedagogyRegistry — central dispatcher for Atlas Exam V3.4 ω.
//
// Single entry point used by `AtlasAiService` to build the per-phase
// `GenerativeModel` cache. Routes (ExamPhase, langCode) → cell.
//
// Tier dispatch logic:
//   - 'it', 'en' → hand-written native cells (production_native)
//   - all others → AI-bootstrap fallback (with EN-cell fallback when
//     the bootstrap entry is missing or truncated)
//
// The validation_status side-channel is also exposed here (mirrors
// AiLanguagePreference.validationStatusFor), so telemetry callers don't
// need to import the preference module transitively.
//
// Mirror of `lib/src/ai/socratic/pedagogy/pedagogy_registry.dart` but
// for Exam phases instead of Socratic stages. Exam pedagogy is Bloom-
// driven (Anderson & Krathwohl 2001), distinct from Socratic which is
// stage-driven (Bjork/Dunlosky/Hestenes).

import '../../../canvas/ai/socratic/socratic_discipline.dart';
import '../../../utils/ai_language_preference.dart'
    show AiLanguagePreference, SocraticValidationStatus;
import 'discipline_hints_exam_bootstrap.dart';
import 'discipline_hints_exam_en.dart';
import 'discipline_hints_exam_it.dart';
import 'exam_pedagogy_bootstrap.dart';
import 'exam_pedagogy_en.dart';
import 'exam_pedagogy_it.dart';
import 'exam_phase.dart';

class ExamPedagogyRegistry {
  ExamPedagogyRegistry._();

  /// Returns the full system prompt cell for [phase] in [langCode].
  /// This string becomes the cached `systemInstruction` of the per-phase
  /// `GenerativeModel` in `AtlasAiService`.
  ///
  /// Runtime fallback for truncated bootstrap cells: same defensive net
  /// used by `PedagogyRegistry._resolveBootstrapStage`. Each phase has a
  /// canonical marker token that signals "this cell tells the model what
  /// to emit" — when missing, we fall back to the EN cell to guarantee a
  /// complete pedagogy prompt.
  ///
  /// Canonical markers per phase:
  ///   - `generation`: contains `"domande"` (JSON output schema)
  ///   - `evaluation`: contains `VOTO:` (rigid 2-line output format)
  ///   - `hint`: contains either the IT/EN word for the role ("indizio"
  ///      / "hint") AND the rule "Maximum 12" / "Massimo 12" — both must
  ///      survive translation. We use the most robust check: `12` digit
  ///      token presence (the word-limit number is universal across
  ///      languages and is the canonical hint contract).
  static String phasePromptFor(ExamPhase phase, String langCode) {
    return switch (langCode) {
      'it' => _phaseIt(phase),
      'en' => _phaseEn(phase),
      _ => _resolveBootstrapPhase(phase, langCode),
    };
  }

  static String _resolveBootstrapPhase(ExamPhase phase, String langCode) {
    final cell = bootstrapExamPedagogyFor(phase, langCode);
    if (cell == null || cell.isEmpty) return _phaseEn(phase);
    if (!_isCellComplete(phase, cell)) return _phaseEn(phase);
    return cell;
  }

  static bool _isCellComplete(ExamPhase phase, String cell) {
    return switch (phase) {
      ExamPhase.generation => cell.contains('"domande"'),
      ExamPhase.evaluation => cell.contains('VOTO:'),
      // Both IT ("12 parole") and EN ("12 words") preserve the digit
      // 12 — robust marker across all 14 bootstrap langs.
      ExamPhase.hint => cell.contains('12'),
    };
  }

  /// Returns the small per-call "DISCIPLINA: ..." block to inject in
  /// the V2 payload of [ExamPhase.generation]. Kept ≤400 chars per
  /// discipline to preserve the output token budget. Falls back to EN
  /// when the bootstrap entry is missing for [langCode].
  static String disciplineHintsFor(Discipline d, String langCode) {
    return switch (langCode) {
      'it' => disciplineHintsExamIt(d),
      'en' => disciplineHintsExamEn(d),
      _ => bootstrapExamDisciplineHintsFor(d, langCode) ??
          disciplineHintsExamEn(d),
    };
  }

  /// Mirror of [AiLanguagePreference.validationStatusFor]. Exposed here
  /// so Exam telemetry callers can tag events with the lang quality tier
  /// without importing the preference module transitively.
  static SocraticValidationStatus validationStatusFor(String langCode) =>
      AiLanguagePreference.validationStatusFor(langCode);

  static String _phaseIt(ExamPhase p) => switch (p) {
        ExamPhase.generation => examGenerationIt,
        ExamPhase.evaluation => examEvaluationIt,
        ExamPhase.hint => examHintIt,
      };

  static String _phaseEn(ExamPhase p) => switch (p) {
        ExamPhase.generation => examGenerationEn,
        ExamPhase.evaluation => examEvaluationEn,
        ExamPhase.hint => examHintEn,
      };
}
