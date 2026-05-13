// ============================================================================
// 🏗️ CANVAS VIEW TIER — Performance configuration for FlueraCanvasView
//
// Three tiers control which subsystems are enabled per view instance:
//   .full     — main canvas, full feature set
//   .panel    — multiview active panel, equivalent of .full
//   .preview  — multiview inactive panel, read-only mirror
//
// Tier promotion happens on tap: a .preview panel becomes .panel when the
// user activates it; the previously-active panel demotes to .preview.
// ============================================================================

/// Performance/feature tier for a [FlueraCanvasView] instance.
enum CanvasViewTier {
  /// Main canvas — full pipeline.
  full,

  /// Multiview active panel — equivalent of [full] but with a distinct
  /// tile cache namespace.
  panel,

  /// Multiview inactive panel — read-only mirror with degraded rendering.
  preview,
}

/// Resolves runtime feature flags from a [CanvasViewTier].
///
/// Centralized here so the call sites in [FlueraCanvasView] don't have to
/// reason about the matrix directly.
class CanvasViewTierConfig {
  /// Whether the tile pyramid (TileCacheManager) is enabled.
  /// `.preview` panels fall back to a simple Picture cache.
  final bool useTilePyramid;

  /// Whether R-tree spatial index is queried for viewport culling.
  /// `.preview` panels use naive bounds-overlap culling.
  final bool useSpatialIndex;

  /// Whether the native Vulkan/Metal stroke overlay is initialized.
  /// `.preview` panels never have native overlay (memory + GPU saving).
  final bool useNativeStrokeOverlay;

  /// Whether the Apple Pencil predicted-tail overlay is rendered.
  final bool usePredictedTail;

  /// Whether the live stroke painter (drawing in progress) is rendered.
  /// `.preview` panels don't accept input until promoted, so no live stroke.
  final bool useLiveStrokePainter;

  /// Whether the gesture detector accepts drawing input.
  /// `.preview` panels only accept tap-to-activate.
  final bool acceptsDrawingInput;

  const CanvasViewTierConfig({
    required this.useTilePyramid,
    required this.useSpatialIndex,
    required this.useNativeStrokeOverlay,
    required this.usePredictedTail,
    required this.useLiveStrokePainter,
    required this.acceptsDrawingInput,
  });

  /// Returns the runtime config for a given [tier].
  factory CanvasViewTierConfig.forTier(CanvasViewTier tier) {
    switch (tier) {
      case CanvasViewTier.full:
      case CanvasViewTier.panel:
        return const CanvasViewTierConfig(
          useTilePyramid: true,
          useSpatialIndex: true,
          useNativeStrokeOverlay: true,
          usePredictedTail: true,
          useLiveStrokePainter: true,
          acceptsDrawingInput: true,
        );
      case CanvasViewTier.preview:
        return const CanvasViewTierConfig(
          useTilePyramid: false,
          useSpatialIndex: false,
          useNativeStrokeOverlay: false,
          usePredictedTail: false,
          useLiveStrokePainter: false,
          acceptsDrawingInput: false,
        );
    }
  }
}
