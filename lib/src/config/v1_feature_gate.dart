// ============================================================================
// 🚀 V1 FEATURE GATE — Centralized kill switch for v1.5/v2 features
//
// All features listed in "lancio_v1_strategia_e_scope.md §5 DEFER" are gated
// here. Set a flag to `true` to re-enable a feature when ready for v1.5/v2.
//
// RULES:
//   - const booleans → tree-shaken by the compiler (zero runtime cost)
//   - DO NOT import UI/Flutter dependencies here (pure config)
//   - Backend code (controllers, renderers) stays intact for retrocompatibility
//   - Only UI entry points are gated
// ============================================================================

import '../drawing/models/pro_drawing_point.dart';

/// 🚀 v1 Feature Gate — compile-time kill switches.
///
/// Usage:
/// ```dart
/// if (V1FeatureGate.timeTravel) {
///   _enterTimeTravelMode();
/// }
/// ```
class V1FeatureGate {
  V1FeatureGate._(); // No instantiation

  // ═══════════════════════════════════════════════════════════════════════════
  // DEFERRED FEATURES — set to `true` when ready for v1.5/v2
  // ═══════════════════════════════════════════════════════════════════════════

  /// ⏱️ Time Travel (replay) — Pro pillar #1 (V1 split 2026-05-14).
  /// Backend code (recorder, playback engine, scrubber overlay) is
  /// compile-time enabled. Per-tier access is gated at runtime through
  /// `TierGateController.canUseFeature(GatedFeature.timeTravel)`:
  /// Pro → playback UI on. Free / Plus → upgrade affordance only.
  /// See [TimeTravelRetentionPolicy] for the per-tier retention window
  /// (Free: 90 d ring buffer, Plus / Pro: unlimited).
  static const bool timeTravel = true;

  /// 💎 Spark Pack consumable visibility (V1 split 2026-05-14).
  /// When false, the top-up CTAs are HIDDEN from the UI:
  ///   • paywall comparison table omits the Spark Pack section
  ///   • credits badge details sheet hides the "Aggiungi Spark Pack" button
  ///   • credit-exhausted events no longer auto-launch the purchase sheet
  ///     — the host shows a generic upgrade banner instead
  /// The Supabase RPC + product IDs stay wired so flipping this back to
  /// true re-enables the flow without code changes.
  static const bool sparkPackVisible = false;

  /// 🤝 Collaboration CRDT + P2P — Pro pillar #2 (V1 split 2026-05-14).
  /// Backend CRDT validated end-to-end on device (memory: Linux↔Xiaomi
  /// over Supabase Broadcast, 2026-05-06). Per-tier access is gated at
  /// runtime through `TierGateController.canUseFeature(GatedFeature.collaboration)`:
  /// Pro → share + live sync. Free / Plus → upgrade affordance only.
  static const bool collaboration = true;

  /// 🌉 Cross-Zone Bridges — Step 9, requires months of canvas usage.
  /// Enabled for closed beta: controller backend stable, low-risk exposure,
  /// gives us telemetry on whether students actually build cross-domain links.
  static const bool crossZoneBridges = true;

  /// 📝 Exam Session — Steps 10-11. Killer feature per medicina/legge/concorsi
  /// e magistrale. Backend + UI completamente wired, FSRS spaced repetition
  /// integrato in onComplete. Sbloccato per V1 launch (decisione 2026-05-05,
  /// Path 3 audit). Comparable: Anki/Memorang ma genera Q&A dai tuoi appunti.
  static const bool examSession = true;

  /// 🏪 Marketplace — requires critical user mass.
  static const bool marketplace = false;

  /// 🚶 Passeggiata — contemplative mode, nice-to-have.
  static const bool passeggiata = false;

  /// 🧮 LaTeX Recognition (ONNX) — useful for STEM, not for all at launch.
  static const bool latexRecognition = false;

  /// 🎨 8 Advanced Brushes — watercolor, charcoal, oil, spray, neon,
  /// ink wash, texture, stamp → Pro/v2.
  static const bool advancedBrushes = false;

  /// 🖥️ Multiview — UX complexity not necessary day 1.
  static const bool multiview = true;

  /// 🏗️ FlueraCanvasView extraction (main canvas) — God Object Decomposition
  /// Phase 1. When true, FlueraCanvasScreen delegates the viewport+input
  /// pipeline to the new FlueraCanvasView widget. Off by default until
  /// device-validated end-to-end (pixel-match harness is already green).
  static const bool flueraCanvasViewExtraction = false;

  /// 🏗️ FlueraCanvasView in multiview panels — same extraction, scoped to
  /// the multiview orchestrator only. Default ON because the legacy
  /// `MultiviewPanel` is canvas-lite (no PDFs, no images, no cognitive
  /// overlays, no paper template). Activating FlueraCanvasView here can
  /// only improve panel fidelity vs the legacy path.
  static const bool flueraCanvasViewExtractionMultiview = true;

  /// 📊 Tabular — advanced tool.
  static const bool tabular = false;

  /// 🪣 Flood Fill — artistic tool, not pedagogical.
  static const bool floodFill = false;

  /// 🔀 Interleaving Paths — requires multiple zones, too early.
  static const bool interleavingPaths = false;

  /// 🏢 Enterprise RBAC — B2B is v2.
  static const bool enterpriseRbac = false;

  /// 💬 Design Comments — collaboration feature.
  static const bool designComment = false;

  /// 🎨 Design Tools Tab — Responsive preview, Design Quality, Dev Handoff,
  /// Animation Timeline, Variable Manager. These are Figma-adjacent features
  /// that dilute the "study tool" positioning for the beta. Backend panels
  /// remain intact (overlays/) — only the toolbar tab entry point is gated.
  static const bool designTools = false;

  /// 📋 GDPR export/consent/deletion — prepare for EU but not user-facing.
  static const bool gdprUi = false;

  /// 📊 Pedagogical Telemetry — analytics = v2.
  static const bool pedagogicalTelemetry = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // BRUSH GATING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Brushes available in v1 (both Free and Pro).
  /// Advanced GPU brushes (watercolor, charcoal, oil, spray, neon, inkWash)
  /// are deferred to v2.
  static const Set<ProPenType> v1Brushes = {
    ProPenType.pencil,
    ProPenType.fountain,
    ProPenType.marker,
    ProPenType.ballpoint,
    ProPenType.highlighter,
    ProPenType.technicalPen,
  };

  /// ⚠️ DEPRECATED gate keyed on [ProPenType] — kept for back-compat with
  /// hosts that may import it. The actual paywall logic now keys on
  /// [BrushPreset.freePresetIds] (preset id, not pen type) because the
  /// 3 free preset IDs use a different mix of pen types than the
  /// previous "writing brushes" whitelist:
  ///
  ///   • builtin_everyday_pen → ballpoint  (NOT in old whitelist!)
  ///   • builtin_soft_pencil  → pencil
  ///   • builtin_highlighter  → highlighter (NOT in old whitelist!)
  ///
  /// Values updated 2026-05-16 to match the real free presets so any
  /// lingering caller still gets correct answers. Prefer
  /// `BrushPreset.freePresetIds.contains(preset.id)` for new code.
  static const Set<ProPenType> freeBrushes = {
    ProPenType.ballpoint,
    ProPenType.pencil,
    ProPenType.highlighter,
  };

  /// Whether a brush is available in v1 at all.
  static bool isBrushAvailable(ProPenType type) =>
      advancedBrushes || v1Brushes.contains(type);

  /// ⚠️ Prefer `BrushPreset.freePresetIds.contains(preset.id)` — see the
  /// note on [freeBrushes] above. This pen-type-based check can produce
  /// false-positives when a Plus/Pro preset shares a pen type with a
  /// free preset (e.g. fountain pen comes in both Calligraphy Nib /
  /// Plus and Fine Pen / Plus — neither is free).
  static bool isBrushFree(ProPenType type) => freeBrushes.contains(type);
}
