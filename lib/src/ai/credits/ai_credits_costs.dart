// ============================================================================
// 💎 AI CREDITS COSTS — Fixed cost per AI feature (V1 split decision 2026-05-14)
//
// Centralised cost table so a single source of truth governs how many credits
// each AI invocation consumes. Fixed cost per feature (NOT per token) keeps
// pricing predictable for the user — "Ghost Map = 8 credits, always" is the
// promise.
//
// Decision plan: .claude/plans/analizza-tutta-fluera-app-floating-pebble.md §2
//
// RULES:
//   • Atlas canvas actions and Chat are 0/1 credit — high-frequency UX touch
//     points; gating them would break the product.
//   • Multi-stage features (Socratic, Exam) charge PER STAGE / PER QUESTION
//     so abandoning mid-session refunds naturally — "pay for what you use".
//   • Costs are immutable constants. Tweaks ship through code review, not a
//     server-side toggle (predictability over flexibility in V1).
// ============================================================================

/// 💎 Identifies an AI feature for credit accounting.
///
/// One enum value per metered touch-point. The string [name] doubles as the
/// `feature_id` argument to the Supabase RPC `consume_ai_credits`.
enum AiCreditFeature {
  /// Atlas canvas action ("create sticky", "move zone"). 0 credits — UX core.
  atlas,

  /// Single "Chiedi a Fluera AI" chat message. High-frequency, low-cost.
  chat,

  /// One page processed by background OCR (proactive cluster indexing).
  backgroundOcr,

  /// One Ghost Map comparison run (centaur diff overlay).
  ghostMap,

  /// One stage of a Socratic V3.4 ω dialogue (7 stages total per session).
  /// Charged per stage so abandoning mid-dialogue stops the meter.
  socraticStage,

  /// One Exam Session question — generation + open-answer evaluation pass.
  /// Charged per question so abandoning the exam stops the meter.
  examQuestion,
}

/// 💎 Fixed cost per AI feature, in credits.
abstract final class AiCreditsCosts {
  AiCreditsCosts._(); // No instantiation.

  /// Atlas canvas actions are free for everyone (0 credits).
  /// Costs $0.0004 per call (Flash Lite, 500 tokens). Gating would destroy
  /// the conversational canvas UX. Still TRACKED for abuse telemetry.
  static const int atlas = 0;

  /// Chat is 1 credit per message — the touch-point AI at the highest
  /// frequency. Hard server-side rate limit at 60 msg/hour stops scripts.
  static const int chat = 1;

  /// Background OCR is 1 credit per page. Only enabled in Pro tier.
  static const int backgroundOcr = 1;

  /// Ghost Map costs 8 credits (~3500 tokens Flash, ≈ $0.005).
  static const int ghostMap = 8;

  /// One Socratic stage costs 4 credits (~2000 tokens Flash Lite, ≈ $0.003).
  /// A full 7-stage session totals 28 credits if completed.
  static const int socraticStage = 4;

  /// One Exam question costs 12 credits (~6000 tokens Flash, ≈ $0.014).
  /// Includes generation + open-answer evaluation. Charged per question.
  static const int examQuestion = 12;

  /// Returns the cost in credits for [feature].
  static int costOf(AiCreditFeature feature) {
    return switch (feature) {
      AiCreditFeature.atlas => atlas,
      AiCreditFeature.chat => chat,
      AiCreditFeature.backgroundOcr => backgroundOcr,
      AiCreditFeature.ghostMap => ghostMap,
      AiCreditFeature.socraticStage => socraticStage,
      AiCreditFeature.examQuestion => examQuestion,
    };
  }

  /// Monthly credit allowance per subscription tier.
  ///
  /// These are the V1 numbers from the pricing decision 2026-05-14. They are
  /// surfaced to the UI for the "≈ N Ghost Map" estimator and to the
  /// paywall comparison table.
  static const Map<String, int> monthlyAllowance = {
    'free': 100,
    'plus': 500,
    'pro': 2000,
  };

  /// Spark Pack top-up sizes (consumable IAP). Maps RevenueCat product ID
  /// suffix to the credits granted.
  static const Map<String, int> sparkPackCredits = {
    'spark.250': 250, // €1.99
    'spark.500': 500, // €2.99
  };
}
