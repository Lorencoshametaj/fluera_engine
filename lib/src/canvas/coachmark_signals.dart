/// 🎯 CANVAS COACHMARK SIGNALS — One-shot hooks fired by the canvas
/// when user actions cross pedagogically significant thresholds.
///
/// The engine doesn't depend on the host app's onboarding/coachmark
/// state store. Instead it exposes lightweight static callbacks that
/// the host wires up at startup. Each signal fires AT MOST ONCE per
/// app process (idempotent re-trigger guard) so the host can safely
/// rely on it as a "fact of having happened" without de-bouncing.
///
/// Wire-up (host side, e.g. Fluera/lib/main.dart on app init):
/// ```dart
/// CanvasCoachmarkSignals.onFirstMappamondoDezoom =
///     () => CoachmarkEngine.markMappamondoDezoom();
/// ```
class CanvasCoachmarkSignals {
  CanvasCoachmarkSignals._();

  /// Fired the first time the user zooms below
  /// [SemanticMorphController.morphStartScale] in a process — when
  /// the satellite view of the Memory Palace appears (§22 + §1098).
  /// Host typically uses this to surface a one-time tip explaining
  /// the colored zones + monument pills.
  static void Function()? onFirstMappamondoDezoom;
  static bool _firedMappamondo = false;

  /// Idempotent fire. Safe to call from a high-frequency callback
  /// (e.g. every-frame scale update) — only the first call propagates.
  static void notifyMappamondoDezoom() {
    if (_firedMappamondo) return;
    _firedMappamondo = true;
    onFirstMappamondoDezoom?.call();
  }

  /// 🏛️ Host-controlled toggle for the Monument Elaboration Nudge
  /// (§504-507 — "i nodi-monumento devono essere visivamente distintivi").
  /// When true, the canvas shows a one-shot SnackBar the first time per
  /// session a new cluster crosses [MonumentResolver.monumentThreshold]
  /// suggesting the student make it visually distinctive. Default true;
  /// host app may flip this from a Settings toggle.
  static bool monumentNudgeEnabled = true;

  /// 🌡️ Host-controlled toggle for the FSRS Stage Heat-Map overlay
  /// (§1416-1420 — "specchio metacognitivo"). When true AND the canvas
  /// is zoomed out below `FsrsHeatMapPainter.kActivationScale` (0.25),
  /// every cluster gets a thin ring colored by the worst-of SrsStage of
  /// matched concepts in the review schedule. Default **true** — it's
  /// passive and informational, not invasive. Toggleable from Settings.
  static bool fsrsHeatMapEnabled = true;

  /// 🔁 Host-controlled toggle for the Return-to-Canvas Cognitive Ritual
  /// (§1047-1062 — PASSO 6: Active Recall Spaziale). When true AND the
  /// host wires [loadCanvasVisitState], the canvas opens slightly more
  /// zoomed-out at each return (visit-count-modulated) and applies a
  /// transient blur on cluster ink that the student must clear by
  /// recall+touch. Default **false** (opt-in difficoltà desiderabili).
  static bool returnRitualEnabled = false;

  /// 🆓 Free Background AI consent gate (Bundle A, 2026-05-17). When
  /// `false`, the engine's [BackgroundAiController] skips every auto-
  /// trigger — no cleanOcr / clusterTitle Gemini call fires until the
  /// user opts back in from Settings. Default **true** (marketing
  /// pillar: "L'AI di Fluera pulisce automaticamente i tuoi appunti").
  ///
  /// Host wires this from `cognitive_preferences.backgroundAiEnabled`
  /// during boot. Mirrors the server-side `user_preferences.consent_ai_
  /// background` column (migration 017) — the local flag short-circuits
  /// before the RPC call to avoid the round-trip cost on every batch.
  static bool backgroundAiEnabled = true;

  /// Loads per-canvas visit state. App-side reads/writes (SharedPreferences
  /// or equivalent). Engine queries this at canvas open to compute
  /// `daysSinceLastVisit` and `visitCount` for ritual modulation.
  /// Returning null disables ritual (treated as "first visit ever").
  ///
  /// Returns a record `(visitCount, lastVisitedMs)` where:
  ///   - `visitCount` = total opens so far (≥ 0)
  ///   - `lastVisitedMs` = epoch ms of last open (0 if never)
  static Future<({int visitCount, int lastVisitedMs})?> Function(
    String canvasId,
  )? loadCanvasVisitState;

  /// Persists per-canvas visit state. Called by the engine immediately
  /// after [loadCanvasVisitState] so the next session reads fresh
  /// `visitCount + 1` and `lastVisitedMs = now`.
  static Future<void> Function(
    String canvasId,
    int visitCount,
    int lastVisitedMs,
  )? saveCanvasVisitState;

  /// Test seam — resets all one-shot guards.
  static void resetForTesting() {
    _firedMappamondo = false;
    monumentNudgeEnabled = true;
    returnRitualEnabled = false;
    fsrsHeatMapEnabled = true;
  }
}
