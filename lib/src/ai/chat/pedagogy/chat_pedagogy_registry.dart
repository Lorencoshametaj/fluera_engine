// 💬 ChatPedagogyRegistry — central dispatcher for Chat AI V3.4 ω.
//
// Single entry point used by `AtlasAiService` to build the lang-aware
// `_chatModel` cache. Routes langCode → cell.
//
// Tier dispatch logic:
//   - 'it', 'en' → hand-written native cells (production_native)
//   - all others → AI-bootstrap fallback (with EN-cell fallback when
//     the bootstrap entry is missing or truncated)
//
// Mirror of `pedagogy_registry.dart` (Socratic) and
// `exam_pedagogy_registry.dart` (Exam) but for the single Chat surface.
// Chat has 1 phase (respond), discipline-agnostic, multi-turn streaming.
//
// The validation_status side-channel is also exposed here (mirrors
// AiLanguagePreference.validationStatusFor), so Chat telemetry callers
// can tag events with the lang quality tier without importing the
// preference module transitively.

import '../../../utils/ai_language_preference.dart'
    show AiLanguagePreference, SocraticValidationStatus;
import '../../experiments/variant_overrides_provider.dart';
import 'chat_pedagogy_bootstrap.dart';
import 'chat_pedagogy_en.dart';
import 'chat_pedagogy_it.dart';

class ChatPedagogyRegistry {
  ChatPedagogyRegistry._();

  /// 🧪 Sprint AB-D — optional A/B variant override resolver. Mirror of
  /// `PedagogyRegistry.variantOverrides` and `ExamPedagogyRegistry.variantOverrides`.
  /// Null by default; host app injects at startup. Additive — no-op when null.
  static VariantOverridesProvider? variantOverrides;

  /// Returns the full Chat system prompt cell for [langCode]. This string
  /// becomes the cached `systemInstruction` of the `_chatModel` in
  /// `AtlasAiService.initialize()`.
  ///
  /// Truncation-fallback canonical marker: the EN/IT cells contain
  /// `"HARD RULES"` (universal token that survives most translations
  /// — bootstrap may translate to "REGLAS"/"REGELN"/etc, so we use a
  /// secondary marker too). Combined check: the cell must contain
  /// either `"HARD"` OR `"Fluera AI"` (the latter is a brand name
  /// kept verbatim across all languages per bootstrap rules).
  static String chatPromptFor(String langCode) {
    // 🧪 Sprint AB-D: variant override hook (Chat has 1 phase named 'chat').
    final override = variantOverrides?.cellOverrideFor(
      feature: 'chat',
      unit: 'chat',
      langCode: langCode,
    );
    if (override != null) return override;
    return switch (langCode) {
      'it' => chatPedagogyIt,
      'en' => chatPedagogyEn,
      _ => _resolveBootstrap(langCode),
    };
  }

  static String _resolveBootstrap(String langCode) {
    final cell = bootstrapChatPedagogyFor(langCode);
    if (cell == null || cell.isEmpty) return chatPedagogyEn;
    if (!_isCellComplete(cell)) return chatPedagogyEn;
    return cell;
  }

  static bool _isCellComplete(String cell) {
    // Brand name "Fluera AI" is preserved verbatim in all bootstrap
    // translations (per script rule). It's the most reliable marker
    // that a translated cell is structurally complete.
    return cell.contains('Fluera AI');
  }

  /// Mirror of [AiLanguagePreference.validationStatusFor]. Exposed here
  /// so Chat telemetry callers can tag events with the lang quality tier
  /// without importing the preference module transitively.
  static SocraticValidationStatus validationStatusFor(String langCode) =>
      AiLanguagePreference.validationStatusFor(langCode);
}
