// 🎓 PedagogyRegistry — central dispatcher for Socratic V3.4 ω.
//
// Single entry point used by `AtlasAiService.initialize` to build the
// per-stage GenerativeModel cache. Routes (stage, langCode) →
// system_prompt cell, and (discipline, langCode) → hints module.
//
// Tier dispatch logic:
//   - 'it', 'en' → hand-written native cells (production_native)
//   - all others → AI-bootstrap fallback (lang-pin + EN cell)
//
// The validation_status side-channel is also exposed here (mirrors
// AiLanguagePreference.validationStatusFor) for telemetry.

import '../../../canvas/ai/socratic/socratic_model.dart'
    show Discipline, SocraticStage;
import '../../../utils/ai_language_preference.dart'
    show AiLanguagePreference, SocraticValidationStatus;
import 'discipline_hints_en.dart';
import 'discipline_hints_it.dart';
import 'stage_pedagogy_bootstrap.dart';
import 'stage_pedagogy_en.dart';
import 'stage_pedagogy_it.dart';

class PedagogyRegistry {
  PedagogyRegistry._();

  /// Returns the full system_prompt for the given (stage, langCode).
  /// This string becomes the cached `systemInstruction` of the
  /// per-stage `GenerativeModel` in `AtlasAiService`.
  ///
  /// 🛡️ Sprint F.2-exec (2026-05-13): runtime fallback for truncated
  /// bootstrap cells. The Gemini Flash 2.5 translation occasionally
  /// truncates mid-cell (initial bootstrap had ~17% cells missing the
  /// OUTPUT JSON block). When detected, fall back to the EN cell —
  /// guarantees the model gets a complete pedagogy prompt, accepting
  /// that those rare sessions degrade to cross-language mode (EN
  /// questions on non-EN target). The `ai_bootstrap` UI banner
  /// already warns the user about this tier.
  ///
  /// Completeness signal: the JSON OUTPUT template (`{"q":` + `"h":`)
  /// is the canonical "this cell tells the model what to emit" marker.
  /// Length thresholds are unreliable for CJK languages (zh/ja/ko)
  /// where a 700-char cell can be complete because each character
  /// carries more meaning than in Latin scripts.
  static String stagePedagogyFor(SocraticStage stage, String langCode) {
    return switch (langCode) {
      'it' => _stageIt(stage),
      'en' => _stageEn(stage),
      _ => _resolveBootstrapStage(stage, langCode),
    };
  }

  static String _resolveBootstrapStage(SocraticStage stage, String langCode) {
    final cell = bootstrapStagePedagogy(stage, langCode);
    final hasOutputTemplate = cell.contains('"q"') && cell.contains('"h"');
    if (!hasOutputTemplate) {
      // Truncated translation: missing the JSON OUTPUT template means
      // the model has no instruction on what shape to emit. Fall back
      // to EN to guarantee a complete pedagogy prompt.
      return _stageEn(stage);
    }
    return cell;
  }

  /// Returns the small per-call "DISCIPLINE: ..." block to inject in
  /// the per-call payload. Kept ≤400 chars to preserve output budget.
  static String disciplineHintsFor(Discipline d, String langCode) {
    return switch (langCode) {
      'it' => disciplineHintsIt(d),
      'en' => disciplineHintsEn(d),
      _ => bootstrapDisciplineHints(d, langCode),
    };
  }

  /// Mirror of [AiLanguagePreference.validationStatusFor]. Exposed here
  /// so telemetry callers don't need to import the preference module
  /// transitively.
  static SocraticValidationStatus validationStatusFor(String langCode) =>
      AiLanguagePreference.validationStatusFor(langCode);

  static String _stageIt(SocraticStage s) => switch (s) {
        SocraticStage.anchor => anchorStagePedagogyIt,
        SocraticStage.elaboration => elaborationStagePedagogyIt,
        SocraticStage.comparative => comparativeStagePedagogyIt,
        SocraticStage.counterfactual => counterfactualStagePedagogyIt,
        SocraticStage.application => applicationStagePedagogyIt,
        SocraticStage.interleave => interleaveStagePedagogyIt,
        SocraticStage.metacognitive => metacognitiveStagePedagogyIt,
      };

  static String _stageEn(SocraticStage s) => switch (s) {
        SocraticStage.anchor => anchorStagePedagogyEn,
        SocraticStage.elaboration => elaborationStagePedagogyEn,
        SocraticStage.comparative => comparativeStagePedagogyEn,
        SocraticStage.counterfactual => counterfactualStagePedagogyEn,
        SocraticStage.application => applicationStagePedagogyEn,
        SocraticStage.interleave => interleaveStagePedagogyEn,
        SocraticStage.metacognitive => metacognitiveStagePedagogyEn,
      };
}
