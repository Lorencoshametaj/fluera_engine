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

  /// ⏱️ Time Travel (replay) — impressive but not essential day 1.
  static const bool timeTravel = false;

  /// 🤝 Collaboration CRDT + P2P — Step 7, requires server infra.
  static const bool collaboration = false;

  /// 🌉 Cross-Zone Bridges — Step 9, requires months of canvas usage.
  /// Enabled for closed beta: controller backend stable, low-risk exposure,
  /// gives us telemetry on whether students actually build cross-domain links.
  static const bool crossZoneBridges = true;

  /// 📝 Exam Session — Steps 10-11, not in the first month.
  static const bool examSession = false;

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
  static const bool multiview = false;

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

  /// Brushes available in Free tier (v1).
  /// Document: "3 base (pencil, pen, marker)".
  static const Set<ProPenType> freeBrushes = {
    ProPenType.pencil,
    ProPenType.fountain,
    ProPenType.marker,
  };

  /// Whether a brush is available in v1 at all.
  static bool isBrushAvailable(ProPenType type) =>
      advancedBrushes || v1Brushes.contains(type);

  /// Whether a brush is available in the Free tier.
  static bool isBrushFree(ProPenType type) => freeBrushes.contains(type);
}
