import 'dart:ui' as ui show Image;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import './infinite_canvas_controller.dart';
import '../config/adaptive_rendering_config.dart';
import '../core/models/digital_text_element.dart';
import '../core/models/image_element.dart';
import '../core/models/shape_type.dart';
import '../drawing/models/surface_material.dart';
import '../reflow/content_cluster.dart';
import '../reflow/knowledge_flow_controller.dart';
import '../layers/layer_controller.dart';
import '../rendering/canvas/collab_overlay_painters.dart';
import '../rendering/canvas/eraser_overlay_painters.dart';
import '../rendering/canvas/pdf_page_painter.dart';
import '../rendering/canvas/scratch_out_particles.dart';
import '../tools/pdf/pdf_search_controller.dart';
import '../time_travel/controllers/synchronized_playback_controller.dart';
import '../rendering/canvas/image_memory_manager.dart';
import '../rendering/optimization/spatial_index.dart';
import './smart_guides/smart_guide_engine.dart';
import '../tools/echo_search_controller.dart';
import '../tools/image/image_tool.dart';
import '../tools/lasso/lasso_tool.dart';
import '../tools/ruler/ruler_guide_system.dart';
import '../tools/unified_tool_controller.dart';
import '../l10n/fluera_localizations.dart';
import './ai/socratic/socratic_controller.dart';
import './ai/recall/recall_mode_controller.dart';
import './ai/fog_of_war/fog_of_war_controller.dart';
import './ai/ghost_map_controller.dart';
import './ai/tier_gate_controller.dart';
import './ai/learning_step_controller.dart';
import './ai/cross_zone_bridge_controller.dart';
import './ai/exam_session_controller.dart';
import './ai/srs_review_session.dart';

// ============================================================================
// 🏗️ CANVAS SCOPE — Shared canvas-document state for descendant widgets
//
// Replaces `part of` coupling by publishing key controllers and caches
// into the widget tree via InheritedWidget.
//
// Scope: 1 instance per canvas DOCUMENT.
// - Multiple FlueraCanvasView panels viewing the SAME document share one
//   CanvasScope (cognitive features, undo/redo, autosave are document-scoped).
// - Each FlueraCanvasView owns its own InfiniteCanvasController internally
//   (per-viewport), so canvasController is intentionally NOT in this scope.
//
// Usage:  CanvasScope.of(context).layerController
//
// Added: God Object Decomposition — Phase 1 (extends Phase 0 scaffold).
// Phase 2 (cognitive painters): added cross-zone, exam, srs, knowledgeFlow.
// Phase 3 (overlay widgets): added lassoTool, imageTool, atlas response,
//   zeigarnik / golden shimmer animation+bounds.
// ============================================================================

/// Snapshot of an in-progress inline text edit — bundles the active
/// [DigitalTextElement] + the editor's style state + submit / cancel
/// callbacks. When non-null, [FlueraCanvasView] mounts an
/// `InlineTextOverlay` anchored to the element's canvas position.
class InlineTextEditingSnapshot {
  final DigitalTextElement element;
  final Color color;
  final double fontSize;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final String fontFamily;
  final Shadow? shadow;
  final Color? backgroundColor;
  final Color? outlineColor;
  final double outlineWidth;
  final List<Color>? gradientColors;
  final double opacity;
  final double letterSpacing;
  final TextDecoration textDecoration;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;
  final ValueChanged<TextSelection> onSelectionChanged;

  const InlineTextEditingSnapshot({
    required this.element,
    required this.color,
    required this.fontSize,
    required this.fontWeight,
    required this.fontStyle,
    required this.fontFamily,
    this.shadow,
    this.backgroundColor,
    this.outlineColor,
    this.outlineWidth = 0.0,
    this.gradientColors,
    this.opacity = 1.0,
    this.letterSpacing = 0.0,
    this.textDecoration = TextDecoration.none,
    required this.onSubmit,
    required this.onCancel,
    required this.onSelectionChanged,
  });
}

/// Bag of auxiliary state used by overlay painters/widgets that haven't
/// graduated into their own controller yet. Owned by [_FlueraCanvasScreenState],
/// exposed read-only via [CanvasScope.legacyState] so [FlueraCanvasView]
/// (and other extracted widgets) can read it without a `part of` dependency.
///
/// Animations are passed as raw [Listenable] (any AnimationController is
/// also a Listenable). Plain values are passed by reference; the screen
/// is expected to call `setState` (which rebuilds CanvasScope and triggers
/// `updateShouldNotify`) when these change.
///
/// `null` is permitted everywhere — the screen wrapper sets only what it
/// has; missing fields cause the related painter to skip rendering.
class CanvasLegacyState {
  /// Atlas AI response card — text + canvas-space anchor + loading.
  final String? atlasResponseText;
  final Offset? atlasResponsePosition;
  final bool atlasIsLoading;

  /// Zeigarnik incomplete-node bounds (canvas coords) + animation source.
  /// Bounds are `const []` when no incomplete nodes; the animation
  /// [Listenable] (typically an AnimationController, .value 0..1 looping)
  /// drives the pulsing effect.
  final List<Rect> zeigarnikIncompleteBounds;
  final Listenable? zeigarnikAnimation;

  /// Golden shimmer (mastered SRS Stage 4+) — bounds + animation source
  /// + on/off toggle (user setting).
  final List<Rect> goldenShimmerBounds;
  final Listenable? goldenShimmerAnimation;
  final bool goldenShimmerEnabled;

  /// Selection / lasso UI repaint trigger — fires when the lasso selection
  /// changes (selected ids, drag state, transform handles). The screen owns
  /// a generic `_uiRebuildNotifier` that's bumped on selection changes.
  final Listenable? selectionRepaint;

  /// Image transform repaint trigger — fires when the selected image moves,
  /// resizes, rotates, or its crop changes. Used by image transform handles
  /// overlay to redraw without full setState.
  final Listenable? imageRepaint;

  /// Eraser preview — strokes that are about to be erased (whole-stroke
  /// mode). Highlighted while pointer is held; committed on pointer-up.
  final Set<String> eraserPreviewIds;

  /// Scratch-out preview — strokes targeted by the scratch-out gesture.
  /// `dissolveMap` carries per-stroke 0..1 dissolve progress for the
  /// fade-out animation when the gesture completes.
  final Set<String> scratchOutPreviewIds;
  final Map<String, double> scratchOutDissolveMap;

  /// Recall mode — reconstruction zone rect (for the split-view PASSO 2
  /// "originale ↔ tentativo" UX) + flag for which side is being shown
  /// + the set of stroke IDs that should be hidden during reconstruction.
  final Rect recallReconstructionZone;
  final bool recallShowingOriginals;
  final Set<String> recallHiddenStrokeIds;

  /// Image rendering pipeline state (separate from DrawingPainter — the
  /// dedicated [ImagePainter] handles selection handles + decode lifecycle).
  ///
  /// Owned by the screen wrapper (image import flow); `imageVersion` ticks
  /// when the working set changes (add/remove/transform/decode).
  final List<ImageElement> imageElements;
  final Map<String, ui.Image> loadedImages;
  final int imageVersion;
  final RTree<ImageElement>? imageSpatialIndex;
  final ImageMemoryManager? imageMemoryManager;

  /// Eraser visual FX — trail + particle puffs, rendered while the eraser
  /// is dragged. Trail points fade after 300ms, particles emit at erase
  /// intersection points.
  final List<EraserTrailPoint> eraserTrail;
  final List<EraserParticle> eraserParticles;

  /// Eraser cursor (canvas-space) — non-null while the eraser tool is
  /// active and the pointer is hovering / dragging over the canvas.
  /// Drives the auxiliary overlays' visibility.
  final Offset? eraserCursorPosition;

  /// Eraser lasso mode state — when active, the user defines a lasso
  /// area and only strokes inside are erased.
  final bool eraserLassoMode;
  final List<Offset> eraserLassoPoints;
  final bool eraserLassoAnimating;

  /// Eraser protected regions (canvas-space) — rectangles the eraser
  /// will skip. Owned by `_eraserTool.protectedRegions`.
  final List<Rect> eraserProtectedRegions;

  /// Magnetic snap target (canvas-space) — set when the eraser is near
  /// a snap point (typically a stroke end-point).
  final Offset? eraserMagneticSnapTarget;
  final bool eraserMagneticSnapEnabled;

  /// Scratch-out particle dissolve — colored fragments thrown outwards
  /// from a freshly-deleted stroke set, with gravity. Active for ~500ms
  /// after a multi-stroke delete gesture.
  final bool scratchOutAnimating;
  final Rect scratchOutBounds;
  final List<ScratchOutParticle> scratchOutParticles;

  /// Local audio-sync playback controller (live recording playback) +
  /// optional page index when the audio spans multiple pages.
  /// Wired by the FlueraCanvasConfig.externalPlaybackController.
  final SynchronizedPlaybackController? externalPlaybackController;
  final int? playbackPageIndex;

  /// Recorded playback (cinematic stroke replay from saved recording)
  /// — controller + onClose + onAutoFollow callbacks. Both null when
  /// no playback session is active.
  final SynchronizedPlaybackController? recordedPlaybackController;
  final VoidCallback? onStopRecordedPlayback;
  final ValueChanged<Offset>? onPlaybackAutoFollow;
  final bool isPlayingSyncedRecording;

  /// Live audio recording — mic on + transcription enabled + transcript.
  /// When all three present, a "Listening… / live transcript" overlay
  /// shows at the bottom of the canvas during recording.
  final bool isRecordingAudio;
  final bool liveTranscriptionEnabled;
  final ValueListenable<String>? liveTranscriptionText;

  /// Inline text editing — non-null while the user is typing into an
  /// existing or freshly-tapped [DigitalTextElement]. The view mounts
  /// the `InlineTextOverlay` widget anchored to the element's canvas
  /// position; callbacks bridge submit / cancel / selection-change back
  /// to the screen wrapper's text editing flow.
  final InlineTextEditingSnapshot? inlineTextEditing;

  /// Collab — in-progress strokes from remote peers (Pro tier real-time
  /// CRDT sync). Maps + controller wired by the screen.
  final Map<String, List<Offset>> remoteLiveStrokes;
  final Map<String, int> remoteLiveStrokeColors;
  final Map<String, double> remoteLiveStrokeWidths;

  /// Collab — PDF documents being uploaded by a remote peer; rendered
  /// as placeholder cards with progress indicator until the real data
  /// arrives.
  final List<PdfLoadingPlaceholder> pdfLoadingPlaceholders;

  /// Lasso closing-ripple FX — center point (in screen-space) + animation
  /// driver (typically an AnimationController whose .value is in 0..1).
  /// When both non-null and t<1.0, the ripple is rendered with
  /// radius = 20 + t*60 and opacity = (1-t)*0.5.
  final Offset? lassoRippleCenter;
  final Listenable? lassoRippleAnimation;

  /// Selection transform — invoked when the user finishes a translate /
  /// scale / rotate gesture on the lasso selection (typically the screen
  /// wrapper bumps the selection-repaint notifier and triggers autosave).
  final VoidCallback? onSelectionTransformComplete;

  /// Smart guide alignment lines drawn during a drag (active guides
  /// computed by `SmartGuideEngine` while the user moves an element).
  final List<SmartGuideLine> activeSmartGuides;

  /// Section creation preview — start/end points (canvas-space) of the
  /// rectangle being dragged out to define a new section. Both null
  /// when no section is being created.
  final Offset? sectionStartPoint;
  final Offset? sectionEndPoint;

  /// Fog-of-war zone preview — start/end points (canvas-space) of the
  /// rectangle being dragged out to define a new fog zone (PASSO 10).
  /// `pendingFogLevel` is the eventual density level (light/medium/total)
  /// committed once the user releases the drag.
  final Offset? fogZoneStartPoint;
  final Offset? fogZoneEndPoint;
  final Object? pendingFogLevel;

  /// Whether the ruler / smart-guides overlay is currently active.
  final bool showRulers;

  /// Whether the echo-search "Query Pen" mode is currently active. When
  /// true and [CanvasScope.echoSearchController] is non-null, the
  /// `EchoSearchPenOverlay` neon glow is rendered on top of strokes.
  final bool isEchoSearchMode;

  /// Socratic bubble state — set of question IDs the user swiped away
  /// (only resolved bubbles are dismissable). Owned by the screen wrapper.
  final Set<String> dismissedSocraticIds;

  /// Callback to display the Socratic session summary modal (called when
  /// the session completes via skip/next). The screen wrapper's modal
  /// sheet is the canonical UI; the view delegates to it.
  final VoidCallback? onShowSocraticSummary;

  /// Ghost ink — predicted text rendered as faint ink ahead of the pen.
  /// `Anchor` is screen-space; the painter converts to canvas internally.
  final Offset? predictionAnchorScreen;
  final String? predictionLabel;

  /// Paper template — string id understood by `BackgroundPainter`
  /// (e.g. 'blank', 'grid', 'lines', 'dots', ...). Canvas-document
  /// scoped: all panels of the same document share the same template.
  final String paperType;

  /// Background color behind the paper pattern. Combined with `paperType`
  /// to fully describe the substrate.
  final Color paperBackgroundColor;

  /// 📄 PDF — per-page painters keyed by page id. When a `PdfPageNode`
  /// is in the scene graph, `DrawingPainter` looks up its painter here
  /// to draw the rasterized page. Empty map → no PDFs visible.
  final Map<String, PdfPagePainter> pdfPainters;

  /// 📄 PDF — callback fired when an async page render completes.
  /// The screen wrapper uses this to bump `pdfLayoutVersion` and
  /// trigger a repaint of all panels mirroring the document.
  final VoidCallback? onPdfRepaint;

  /// 📄 PDF — search highlights overlay for in-document text search.
  final PdfSearchController? pdfSearchController;

  /// 📄 PDF — counter bumped whenever PDF layout mutates (page added,
  /// resized, reordered). DrawingPainter rebuild key.
  final int pdfLayoutVersion;

  /// 📄 PDF — whether page numbers are rendered as chrome below pages.
  final bool showPdfPageNumbers;

  /// 🔺 Live shape preview — non-null while the shape tool is mid-drag.
  /// The shape (rectangle/ellipse/triangle/etc.) is rendered as a
  /// translucent outline above the scene graph until pointer-up.
  final ValueListenable<GeometricShape?>? currentShapeNotifier;

  /// 🖼️ Image edit mode — true when the user is editing a single image
  /// in isolation (zoomed-in mode). Enables clipping in DrawingPainter
  /// so strokes outside the image bounds are discarded.
  final bool isImageEditFromInfiniteCanvas;

  /// 📐 Finite canvas size — when the document is bound to a fixed paper
  /// size (A4, letter, ...) instead of the infinite canvas, this carries
  /// the bounded dimensions. Null = infinite canvas mode.
  final Size? dynamicCanvasSize;

  /// 🚀 Rendering config — adaptive LOD / quality / framerate settings
  /// derived from device capabilities + user preference. Null = engine
  /// defaults.
  final AdaptiveRenderingConfig? renderingConfig;

  /// 🧬 Active surface material — programmable materiality for shader-
  /// aware brushes (watercolor wet diffusion on cold-press paper, etc.).
  /// Null = no special surface (plain raster).
  final SurfaceMaterial? activeSurface;

  /// 🖼️ Image micro-thumbnails (decoded ImageStub renders) — used as
  /// lightweight previews during scroll/zoom on large image elements.
  final Map<String, ui.Image> microThumbnails;

  /// 📄 PDF zoom-to-enter trigger — invoked by an active multiview panel
  /// when its own [InfiniteCanvasController] scales past the entry
  /// threshold. The screen wrapper runs the immersive Wormhole Dive
  /// transition using the supplied controller (panel-local), not the
  /// main-canvas controller. Null = the feature is disabled (e.g.
  /// when the FlueraCanvasView is used outside a screen wrapper).
  final ValueChanged<InfiniteCanvasController>? onPanelZoomCheck;

  const CanvasLegacyState({
    this.atlasResponseText,
    this.atlasResponsePosition,
    this.atlasIsLoading = false,
    this.zeigarnikIncompleteBounds = const [],
    this.zeigarnikAnimation,
    this.goldenShimmerBounds = const [],
    this.goldenShimmerAnimation,
    this.goldenShimmerEnabled = false,
    this.selectionRepaint,
    this.imageRepaint,
    this.eraserPreviewIds = const {},
    this.scratchOutPreviewIds = const {},
    this.scratchOutDissolveMap = const {},
    this.recallReconstructionZone = Rect.zero,
    this.recallShowingOriginals = true,
    this.recallHiddenStrokeIds = const {},
    this.imageElements = const [],
    this.loadedImages = const {},
    this.imageVersion = 0,
    this.imageSpatialIndex,
    this.imageMemoryManager,
    this.eraserTrail = const [],
    this.eraserParticles = const [],
    this.eraserCursorPosition,
    this.eraserLassoMode = false,
    this.eraserLassoPoints = const [],
    this.eraserLassoAnimating = false,
    this.eraserProtectedRegions = const [],
    this.eraserMagneticSnapTarget,
    this.eraserMagneticSnapEnabled = false,
    this.scratchOutAnimating = false,
    this.scratchOutBounds = Rect.zero,
    this.scratchOutParticles = const [],
    this.externalPlaybackController,
    this.playbackPageIndex,
    this.recordedPlaybackController,
    this.onStopRecordedPlayback,
    this.onPlaybackAutoFollow,
    this.isPlayingSyncedRecording = false,
    this.isRecordingAudio = false,
    this.liveTranscriptionEnabled = false,
    this.liveTranscriptionText,
    this.inlineTextEditing,
    this.remoteLiveStrokes = const {},
    this.remoteLiveStrokeColors = const {},
    this.remoteLiveStrokeWidths = const {},
    this.pdfLoadingPlaceholders = const [],
    this.lassoRippleCenter,
    this.lassoRippleAnimation,
    this.onSelectionTransformComplete,
    this.activeSmartGuides = const [],
    this.sectionStartPoint,
    this.sectionEndPoint,
    this.fogZoneStartPoint,
    this.fogZoneEndPoint,
    this.pendingFogLevel,
    this.showRulers = false,
    this.isEchoSearchMode = false,
    this.predictionAnchorScreen,
    this.predictionLabel,
    this.dismissedSocraticIds = const {},
    this.onShowSocraticSummary,
    this.paperType = 'blank',
    this.paperBackgroundColor = const Color(0xFFFFFFFF),
    this.pdfPainters = const {},
    this.onPdfRepaint,
    this.pdfSearchController,
    this.pdfLayoutVersion = 0,
    this.showPdfPageNumbers = true,
    this.currentShapeNotifier,
    this.isImageEditFromInfiniteCanvas = false,
    this.dynamicCanvasSize,
    this.renderingConfig,
    this.activeSurface,
    this.microThumbnails = const {},
    this.onPanelZoomCheck,
  });

  /// All-default sentinel — used when the screen wrapper hasn't supplied
  /// any legacy state (e.g. early in initState, in standalone widget tests).
  static const empty = CanvasLegacyState();
}

/// Provides shared canvas-document state to descendant widgets without
/// requiring `part of fluera_canvas_screen.dart`.
///
/// Each [FlueraCanvasView] descendant owns its own viewport controller;
/// the controllers exposed here are the ones legitimately shared across
/// all panels of the same document.
class CanvasScope extends InheritedWidget {
  // ── Core controllers (canvas-document scoped) ─────────────────────────
  final LayerController layerController;
  final UnifiedToolController toolController;
  final LearningStepController learningStepController;

  // ── AI controllers (always present) ───────────────────────────────────
  final SocraticController socraticController;
  final RecallModeController recallModeController;
  final FogOfWarController fogOfWarController;
  final GhostMapController ghostMapController;
  final TierGateController tierGateController;
  final SrsReviewSession srsReviewSession;

  // ── AI controllers (lazy-init, may be null until first use) ───────────
  final CrossZoneBridgeController? crossZoneBridgeController;
  final ExamSessionController? examSessionController;
  final KnowledgeFlowController? knowledgeFlowController;

  // ── Tools (per-document, but state lives on the screen wrapper) ───────
  final LassoTool? lassoTool;
  final ImageTool? imageTool;

  /// Ruler & smart-guides state. Drawn on top of the canvas via
  /// `RulerInteractiveOverlay` when [CanvasLegacyState.showRulers] is true.
  final RulerGuideSystem? rulerGuideSystem;

  /// Echo search controller — drives the "Query Pen" neon glow overlay
  /// drawn on top of strokes when the search mode is active.
  final EchoSearchController? echoSearchController;

  // ── Caches ────────────────────────────────────────────────────────────
  final List<ContentCluster> clusterCache;

  // ── Localization ──────────────────────────────────────────────────────
  final FlueraLocalizations l10n;

  // ── Canvas identity ───────────────────────────────────────────────────
  final String canvasId;

  // ── Legacy state bag (auxiliary screen state still owned by the
  //    god-object FlueraCanvasScreen — see [CanvasLegacyState]) ─────────
  final CanvasLegacyState legacyState;

  const CanvasScope({
    super.key,
    required this.layerController,
    required this.toolController,
    required this.learningStepController,
    required this.socraticController,
    required this.recallModeController,
    required this.fogOfWarController,
    required this.ghostMapController,
    required this.tierGateController,
    required this.srsReviewSession,
    required this.clusterCache,
    required this.l10n,
    required this.canvasId,
    this.crossZoneBridgeController,
    this.examSessionController,
    this.knowledgeFlowController,
    this.lassoTool,
    this.imageTool,
    this.rulerGuideSystem,
    this.echoSearchController,
    this.legacyState = CanvasLegacyState.empty,
    required super.child,
  });

  /// Retrieves the nearest [CanvasScope] from the widget tree.
  ///
  /// Throws if no scope is found — callers must ensure they are
  /// descendants of a [CanvasScope].
  static CanvasScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CanvasScope>();
    assert(scope != null, 'No CanvasScope found in context');
    return scope!;
  }

  /// Like [of], but returns null if no scope is found.
  /// Useful during widget testing or when scope is optional.
  static CanvasScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CanvasScope>();
  }

  @override
  bool updateShouldNotify(CanvasScope oldWidget) {
    // Non-null controller references are stable (late final on the screen
    // state), so we check only the values that legitimately change:
    //   - clusterCache: re-detected on stroke commit
    //   - l10n: rebuilds on locale change
    //   - lazy-init nullable controllers: transition null → non-null
    //     when the corresponding feature is first used
    //   - lazy-init tools: same null → non-null transition
    //   - legacyState: identity changes when the screen swaps the bag
    return clusterCache != oldWidget.clusterCache ||
        l10n != oldWidget.l10n ||
        crossZoneBridgeController != oldWidget.crossZoneBridgeController ||
        examSessionController != oldWidget.examSessionController ||
        knowledgeFlowController != oldWidget.knowledgeFlowController ||
        lassoTool != oldWidget.lassoTool ||
        imageTool != oldWidget.imageTool ||
        rulerGuideSystem != oldWidget.rulerGuideSystem ||
        echoSearchController != oldWidget.echoSearchController ||
        legacyState != oldWidget.legacyState;
  }
}
