import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/shape_type.dart';
import '../drawing/brushes/brushes.dart';
import '../drawing/input/drawing_input_handler.dart';
import '../drawing/models/pro_brush_settings.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../rendering/canvas/background_painter.dart';
import '../rendering/canvas/collab_overlay_painters.dart';
import '../rendering/canvas/current_stroke_painter.dart';
import '../rendering/canvas/drawing_painter.dart';
import '../rendering/canvas/echo_search_pen_painter.dart';
import '../rendering/canvas/eraser_overlay_painters.dart';
import '../rendering/canvas/fog_of_war_overlay_painter.dart';
import '../rendering/canvas/ghost_map_overlay_painter.dart';
import '../rendering/canvas/golden_shimmer_painter.dart';
import '../rendering/canvas/image_painter.dart';
import '../rendering/canvas/knowledge_flow_painter.dart';
import '../rendering/canvas/predicted_tail_painter.dart';
import '../rendering/canvas/preview_overlay_painters.dart';
import '../rendering/canvas/scratch_out_particles.dart';
import '../rendering/canvas/srs_blur_overlay_painter.dart';
import '../rendering/canvas/zeigarnik_pulse_painter.dart';
import '../time_travel/widgets/synchronized_playback_overlay.dart';
import '../tools/lasso/lasso_path_painter.dart';
import '../tools/lasso/lasso_ripple_painter.dart';
import '../tools/lasso/lasso_selection_overlay.dart';
import '../tools/lasso/lasso_tool.dart' show SelectionMode;
import '../tools/ruler/ruler_interactive_overlay.dart';
import './overlays/ghost_ink_painter.dart';
import '../utils/uid.dart';
import './ai/recall/recall_level_l10n.dart';
import './ai/recall/recall_mode_controller.dart';
import './ai/recall/recall_node_overlay_painter.dart';
import './ai/recall/recall_session_model.dart';
import './canvas_scope.dart';
import './canvas_view_tier.dart';
import './infinite_canvas_controller.dart';
import './infinite_canvas_gesture_detector.dart';
import './overlays/inline_text_overlay.dart';
import './overlays/selection_transform_overlay.dart';
import './overlays/stylus_hover_overlay.dart';
import './smart_guides/smart_guide_overlay.dart';
import './widgets/socratic_bubble.dart';

// ============================================================================
// 🏗️ FLUERA CANVAS VIEW — Reusable viewport widget
//
// God Object Decomposition Phase 2: this widget owns the per-view state
// (viewport controller, drawing input handler, live stroke notifier) and
// reuses the existing painter pipeline (DrawingPainter + SceneGraphRenderer)
// to render all 24 scene-graph node types.
//
// Reads canvas-document state from CanvasScope:
//   - LayerController, ToolController
//   - 8 cognitive controllers (cognitive overlay painters wired in Phase 3)
//
// Tier modes (CanvasViewTier):
//   .full     — main canvas (default)
//   .panel    — multiview active panel
//   .preview  — multiview inactive panel (no input, no live stroke)
//
// Currently dormant behind V1FeatureGate.flueraCanvasViewExtraction.
// Phase 3 wires the 25-painter overlay stack (lasso, ruler, smart guides,
// cognitive overlays). Phase 4 implements `.preview` tier degradation.
// ============================================================================

/// Reusable canvas viewport widget used both full-screen and inside multiview
/// panels. Consumes shared state from the nearest [CanvasScope].
class FlueraCanvasView extends StatefulWidget {
  /// Optional viewport controller. When null, the view creates and owns one.
  /// In multiview, the orchestrator passes a per-panel controller so the
  /// orchestrator can drive viewport-fit / focus operations across panels.
  final InfiniteCanvasController? canvasController;

  /// Performance/feature tier — see [CanvasViewTier] and
  /// [CanvasViewTierConfig].
  final CanvasViewTier tier;

  /// Cache namespace for [TileCacheManager] / Picture cache pools.
  /// Use `'main'` for the screen canvas, `'panel_<index>'` for multiview.
  // ignore: unused_field
  final String cacheName;

  /// Tap callback — used by inactive multiview panels to request promotion
  /// (`.preview` → `.panel`).
  final VoidCallback? onTap;

  /// Long-press callback (canvas-space coordinates).
  final ValueChanged<Offset>? onLongPress;

  /// Cross-panel cursor broadcast — emits the current canvas-space cursor
  /// position so other panels can render a remote crosshair.
  final ValueChanged<Offset?>? onCursorMoved;

  /// Background color (paper substrate).
  final Color backgroundColor;

  /// Optional notifier of Apple Pencil predicted touches (iOS only).
  /// When provided and tier permits, [PredictedTailPainter] renders the
  /// fade-out tail above the live stroke for visual anti-lag.
  /// Each entry must already be in canvas-space (see
  /// `fluera_canvas_screen.onPredictedPointsUpdated`).
  final ValueNotifier<List<ProDrawingPoint>>? predictedTailNotifier;

  const FlueraCanvasView({
    super.key,
    this.canvasController,
    this.tier = CanvasViewTier.full,
    this.cacheName = 'main',
    this.onTap,
    this.onLongPress,
    this.onCursorMoved,
    this.backgroundColor = Colors.white,
    this.predictedTailNotifier,
  });

  /// When true, the cognitive overlay animation controller is created in the
  /// stopped state (value=0.0) instead of `.repeat()`. Pixel-match golden
  /// tests need a deterministic frame: `.repeat()` keeps the test clock
  /// pumping indefinitely, deadlocking `pumpAndSettle()`.
  @visibleForTesting
  static bool disableCognitiveAnimationForTesting = false;

  @override
  State<FlueraCanvasView> createState() => _FlueraCanvasViewState();
}

class _FlueraCanvasViewState extends State<FlueraCanvasView>
    with TickerProviderStateMixin {
  /// Resolved feature flags for the current tier.
  late CanvasViewTierConfig _tierConfig;

  /// Per-view viewport controller.
  late final InfiniteCanvasController _canvasController;
  late final bool _ownsCanvasController;

  /// Drawing input → stroke notifier pipeline.
  late final DrawingInputHandler _drawingHandler;
  final ValueNotifier<List<ProDrawingPoint>> _currentStrokeNotifier =
      ValueNotifier<List<ProDrawingPoint>>(const []);

  /// Whether a stroke is currently being drawn (used to suppress repaint
  /// of completed-stroke painter while live painter is the source of truth).
  final ValueNotifier<bool> _isDrawingNotifier = ValueNotifier<bool>(false);

  /// Throttle cursor broadcast to ~30 fps.
  int _lastCursorBroadcastUs = 0;
  static const int _cursorThrottleUs = 33000;

  /// Drives `animationTime` for cognitive overlay painters (ghost map pulse,
  /// fog of war fog density, etc.). One controller shared across all
  /// cognitive painters; their repaint cost is amortized by RepaintBoundary.
  late final AnimationController _cognitiveAnimController;

  /// Tracks when each ghost-map node was first revealed, for cross-fade
  /// animation. Cleaned up each frame against `controller.revealedNodeIds`.
  final Map<String, double> _ghostRevealTimestamps = {};

  /// Cached zoom-check callback from the [CanvasScope] (resolved in
  /// `didChangeDependencies`). Fired from the canvas controller listener,
  /// which runs outside `build` — must be cached, not looked up live.
  ValueChanged<InfiniteCanvasController>? _onPanelZoomCheck;

  @override
  void initState() {
    super.initState();
    _tierConfig = CanvasViewTierConfig.forTier(widget.tier);

    _ownsCanvasController = widget.canvasController == null;
    _canvasController =
        widget.canvasController ?? InfiniteCanvasController();
    _canvasController.attachTicker(this);

    _drawingHandler = DrawingInputHandler(
      onPointsUpdated: (points) {
        // List.unmodifiable wraps without copying — light at 120Hz.
        _currentStrokeNotifier.value = List.unmodifiable(points);
      },
      onStrokeCompleted: _onStrokeCompleted,
    );

    // Continuous animation for cognitive overlay pulses. Period chosen long
    // enough that .value (0..1) ramp produces smooth oscillation when
    // multiplied by typical pulse frequencies in the painters.
    _cognitiveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (!FlueraCanvasView.disableCognitiveAnimationForTesting) {
      _cognitiveAnimController.repeat();
    }

    // Zoom-to-enter PDF reader: in multiview the screen's listener is on
    // the main controller, not this panel's. Fire the scope callback so
    // the active panel can trigger the dive transition just like the
    // main canvas does. Skipped for `.full` (screen wires its own
    // listener directly) and `.preview` (no input → no zoom).
    if (widget.tier == CanvasViewTier.panel) {
      _canvasController.addListener(_firePanelZoomCheck);
    }
  }

  void _firePanelZoomCheck() {
    _onPanelZoomCheck?.call(_canvasController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onPanelZoomCheck = CanvasScope.of(context).legacyState.onPanelZoomCheck;
  }

  @override
  void didUpdateWidget(covariant FlueraCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tier != widget.tier) {
      _tierConfig = CanvasViewTierConfig.forTier(widget.tier);
      // Phase 4: handle tier transition (init/dispose native overlay,
      // promote/demote tile cache, etc.).
    }
  }

  @override
  void dispose() {
    if (widget.tier == CanvasViewTier.panel) {
      _canvasController.removeListener(_firePanelZoomCheck);
    }
    _cognitiveAnimController.dispose();
    _drawingHandler.dispose();
    _currentStrokeNotifier.dispose();
    _isDrawingNotifier.dispose();
    _canvasController.detachTicker();
    if (_ownsCanvasController) {
      _canvasController.dispose();
    }
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Drawing input
  // ──────────────────────────────────────────────────────────────────────

  void _onStrokeCompleted(List<ProDrawingPoint> finalPoints) {
    // 🎯 SNAP FIX: trim finalPoints to count actually rendered on-screen.
    // (Mirrors MultiviewPanel and _drawing_end.dart behaviour to avoid
    // post-pen-up extension of the committed stroke.)
    var trimmed = finalPoints;
    final renderedCount = CurrentStrokePainter.lastRenderedCount;
    if (renderedCount > 2 && renderedCount < finalPoints.length) {
      trimmed = List.unmodifiable(finalPoints.sublist(0, renderedCount));
    }

    if (trimmed.length >= 2) {
      final scope = CanvasScope.of(context);
      final tool = scope.toolController;
      final stroke = ProStroke(
        id: generateUid(),
        points: trimmed,
        color: tool.color,
        baseWidth: tool.width,
        penType: tool.penType,
        createdAt: DateTime.now(),
        settings: const ProBrushSettings(),
      );
      scope.layerController.addStroke(stroke);
    }

    _currentStrokeNotifier.value = const [];
    _isDrawingNotifier.value = false;
  }

  void _onDrawStart(
    Offset canvasPosition,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    if (!_tierConfig.acceptsDrawingInput) return;

    CurrentStrokePainter.resetForNewStroke();
    _isDrawingNotifier.value = true;
    _drawingHandler.startStroke(
      position: canvasPosition,
      pressure: pressure,
      tiltX: tiltX,
      tiltY: tiltY,
      orientation: 0.0,
    );
    _broadcastCursor(canvasPosition);
  }

  void _onDrawUpdate(
    Offset canvasPosition,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    if (!_tierConfig.acceptsDrawingInput) return;

    _drawingHandler.updateStroke(
      position: canvasPosition,
      pressure: pressure,
      tiltX: tiltX,
      tiltY: tiltY,
      orientation: 0.0,
    );
    _broadcastCursor(canvasPosition);
  }

  void _onDrawBatchUpdate(
    List<Offset> positions,
    List<double> pressures,
    List<double> tiltsX,
    List<double> tiltsY,
  ) {
    if (!_tierConfig.acceptsDrawingInput) return;

    _drawingHandler.addPointsBatch(
      positions: positions,
      pressures: pressures,
      tiltsX: tiltsX,
      tiltsY: tiltsY,
    );
  }

  void _onDrawEnd(Offset canvasPosition) {
    if (!_tierConfig.acceptsDrawingInput) return;
    _drawingHandler.endStroke();
    _broadcastCursor(null);
  }

  void _onDrawCancel() {
    _broadcastCursor(null);
    _currentStrokeNotifier.value = const [];
    if (_drawingHandler.hasStroke) {
      _drawingHandler.endStroke();
    }
    _isDrawingNotifier.value = false;
  }

  void _broadcastCursor(Offset? canvasPosition) {
    final cb = widget.onCursorMoved;
    if (cb == null) return;
    if (canvasPosition == null) {
      cb(null);
      return;
    }
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    if (nowUs - _lastCursorBroadcastUs >= _cursorThrottleUs) {
      _lastCursorBroadcastUs = nowUs;
      cb(canvasPosition);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scope = CanvasScope.of(context);
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.translucent,
      child: ColoredBox(
        // Prefer the canvas-document paper background (so all panels of the
        // same document share the same substrate). Fall back to the widget
        // parameter for standalone use (tests, embeds).
        color: scope.legacyState.paperBackgroundColor,
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewportSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              // InfiniteCanvasGestureDetector wraps the painter stack as
              // its child — pan/zoom/draw input is captured by it, the
              // painters are pure visual layers underneath.
              return _buildGestureWrapper(
                context,
                scope,
                child: Stack(
                  children: [
                    // 🎨 LAYER 0: paper template (grid / lines / dots / blank)
                    // — viewport-level, sits beneath everything. Mirrors
                    // `_buildBackgroundLayer` from the legacy canvas area.
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: BackgroundPainter(
                              paperType: scope.legacyState.paperType,
                              backgroundColor:
                                  scope.legacyState.paperBackgroundColor,
                              controller: _canvasController,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: _buildSceneGraphLayer(scope, viewportSize),
                    ),
                    if (scope.imageTool != null &&
                        scope.legacyState.imageElements.isNotEmpty)
                      Positioned.fill(child: _buildImageLayer(scope)),
                    Positioned.fill(
                      child: _buildCognitiveOverlayLayer(
                        context,
                        scope,
                        viewportSize,
                      ),
                    ),
                    if (_tierConfig.useLiveStrokePainter)
                      Positioned.fill(child: _buildLiveStrokeLayer(scope)),
                    // ☁️ Remote live strokes (collab Pro) — peers' in-
                    // progress strokes drawn as simple polylines.
                    if (scope.legacyState.remoteLiveStrokes.isNotEmpty)
                      Positioned.fill(child: _buildRemoteLiveStrokesLayer(scope)),
                    // 📄 PDF loading placeholders — cards shown when a
                    // peer is uploading a PDF, until the real document
                    // arrives.
                    if (scope.legacyState.pdfLoadingPlaceholders.isNotEmpty)
                      Positioned.fill(
                        child: _buildPdfLoadingPlaceholdersLayer(scope),
                      ),
                    if (_tierConfig.usePredictedTail &&
                        widget.predictedTailNotifier != null)
                      Positioned.fill(child: _buildPredictedTailLayer(scope)),
                    // 📏 Ruler & smart-guides overlay — drawn on top of
                    // canvas but below selection chrome. Reuses screen's
                    // selectionRepaint notifier as rebuild trigger.
                    // (RulerInteractiveOverlay was in `_buildToolOverlays`
                    // inside `_buildCanvasArea` — replaced by my view.)
                    if (scope.legacyState.showRulers &&
                        scope.rulerGuideSystem != null &&
                        scope.legacyState.selectionRepaint != null)
                      Positioned.fill(child: _buildRulerOverlay(context, scope)),
                    // NOTE: Echo Search "Query Pen", Ghost Ink, Ink
                    // prediction bubble, Socratic bubbles, Atlas response
                    // cards, Ghost Map navigation chrome, Fog of War
                    // buttons, search bars, radial menu, section navigator
                    // — all rendered by the screen wrapper as siblings of
                    // `_buildCanvasArea`. Adding them here would
                    // double-render in full-screen mode. For multiview
                    // panels they'll need a separate path (Fase 5 wire-up
                    // will introduce a `renderChrome` flag or move
                    // screen-only widgets into the wrapper layer).
                    // ✏️ Lasso path during drag — animated dashed line
                    // around the user's freehand selection (or marquee /
                    // ellipse rect, depending on `selectionMode`). Painter
                    // listens to `lassoTool.lassoPathNotifier` directly.
                    if (scope.lassoTool != null)
                      Positioned.fill(child: _buildLassoPathOverlay(scope)),
                    // 🔲 Lasso closing ripple — expanding gradient circle
                    // shown briefly at gestural-lasso completion. Center
                    // is screen-space; animation drives radius+opacity.
                    if (scope.legacyState.lassoRippleCenter != null &&
                        scope.legacyState.lassoRippleAnimation != null)
                      Positioned.fill(child: _buildLassoRippleOverlay(scope)),
                    // 🎯 Lasso selection overlay — bounds, transform handles,
                    // pulsing border. Sits ABOVE strokes/cognitive overlays
                    // but BELOW stylus hover. Self-managed Transform inside.
                    if (scope.lassoTool != null &&
                        scope.legacyState.selectionRepaint != null)
                      Positioned.fill(child: _buildLassoOverlay(scope)),
                    // 🤏 Selection transform overlay — resize/rotate/translate
                    // handles for the active lasso selection. Self-manages
                    // its gesture pipeline; we just provide the transform-
                    // complete callback (screen wrapper bumps repaint +
                    // autosave).
                    if (scope.lassoTool != null &&
                        scope.lassoTool!.hasSelection &&
                        scope.legacyState.onSelectionTransformComplete !=
                            null)
                      _buildSelectionTransformOverlay(context, scope),
                    // ✏️ Inline text editor — `InlineTextOverlay` anchored
                    // to the text element's canvas position. Self-managed
                    // IME composition + caret + grapheme handling.
                    if (scope.legacyState.inlineTextEditing != null)
                      _buildInlineTextOverlay(scope),
                    // 📐 Smart guide alignment lines during drag — magenta
                    // dashed lines snapping to nearby element edges /
                    // centers. Active set populated by the screen wrapper
                    // through `SmartGuideEngine`.
                    if (scope.legacyState.activeSmartGuides.isNotEmpty)
                      Positioned.fill(child: _buildSmartGuideOverlay(scope)),
                    // 📐 Section creation preview — drag-out rectangle
                    // shown while the user defines a new section.
                    if (scope.legacyState.sectionStartPoint != null &&
                        scope.legacyState.sectionEndPoint != null)
                      Positioned.fill(
                        child: _buildSectionPreviewOverlay(scope),
                      ),
                    // 🌫️ Fog zone selection preview — drag-out rectangle
                    // shown while the user defines a new fog-of-war zone
                    // (PASSO 10).
                    if (scope.legacyState.fogZoneStartPoint != null &&
                        scope.legacyState.fogZoneEndPoint != null &&
                        scope.legacyState.pendingFogLevel != null)
                      Positioned.fill(
                        child: _buildFogZonePreviewOverlay(scope),
                      ),
                    // 🎵 Local sync playback — live audio recording
                    // playback overlay (bottom-anchored). Driven by the
                    // FlueraCanvasConfig.externalPlaybackController.
                    if (scope.legacyState.externalPlaybackController != null)
                      Positioned.fill(
                        child: _buildLocalPlaybackOverlay(scope),
                      ),
                    // 🎤 Live subtitle overlay — "Listening…" / live
                    // transcript card pinned to the bottom while audio
                    // is recording with transcription enabled.
                    if (scope.legacyState.isRecordingAudio &&
                        scope.legacyState.liveTranscriptionEnabled &&
                        scope.legacyState.liveTranscriptionText != null)
                      _buildLiveSubtitleOverlay(context, scope),
                    // 🎬 Recorded playback overlay — cinematic stroke
                    // replay from a saved recording. Includes auto-follow
                    // pan.
                    if (scope.legacyState.isPlayingSyncedRecording &&
                        scope.legacyState.recordedPlaybackController != null)
                      Positioned.fill(
                        child: _buildRecordedPlaybackOverlay(scope),
                      ),
                    // 💥 Scratch-out particle dissolve — short-lived burst
                    // FX shown right after a multi-stroke scratch delete.
                    // Self-managed 500ms animation in the widget.
                    if (scope.legacyState.scratchOutAnimating &&
                        scope.legacyState.scratchOutParticles.isNotEmpty)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ScratchOutParticleWidget(
                            particles: scope.legacyState.scratchOutParticles,
                            bounds: scope.legacyState.scratchOutBounds,
                            canvasController: _canvasController,
                            deleteCount:
                                scope.legacyState.scratchOutParticles.length,
                          ),
                        ),
                      ),
                    // 🧽 Eraser visual FX — trail + particles + lasso path
                    // + protected regions + ghost preview + magnetic snap.
                    // Screen-space (painters do their own canvasToScreen);
                    // skip when tier doesn't accept input (no eraser in
                    // `.preview` panels).
                    if (_tierConfig.acceptsDrawingInput &&
                        scope.legacyState.eraserCursorPosition != null)
                      Positioned.fill(
                        child: _buildEraserAuxOverlays(context, scope),
                      )
                    else if (_tierConfig.acceptsDrawingInput &&
                        (scope.legacyState.eraserTrail.isNotEmpty ||
                            scope.legacyState.eraserParticles.isNotEmpty))
                      Positioned.fill(
                        child: _buildEraserOverlay(context, scope),
                      ),
                    // 🖊️ Stylus hover cursor — screen-space, hidden during
                    // active drawing (the actual stroke is the cursor at
                    // that point). Reads from StylusHoverState singleton.
                    Positioned.fill(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _isDrawingNotifier,
                        builder: (context, isDrawing, _) {
                          if (isDrawing) return const SizedBox.shrink();
                          return const IgnorePointer(
                            child: StylusHoverOverlay(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Background + scene graph (strokes, shapes, texts, images, PDFs, all
  /// 24 node types) rendered via [DrawingPainter]. Pan/zoom is applied at
  /// widget level via [Transform] for GPU compositing.
  Widget _buildSceneGraphLayer(CanvasScope scope, Size viewportSize) {
    return ListenableBuilder(
      listenable: scope.layerController,
      builder: (context, _) {
        return AnimatedBuilder(
          animation: _canvasController,
          builder: (context, child) {
            final m = Matrix4.identity()
              ..translateByDouble(
                _canvasController.offset.dx,
                _canvasController.offset.dy,
                0.0,
                1.0,
              );
            if (_canvasController.rotation != 0.0) {
              m.rotateZ(_canvasController.rotation);
            }
            final s = _canvasController.scale;
            m.scaleByDouble(s, s, 1.0, 1.0);
            return Transform(transform: m, child: child);
          },
          child: RepaintBoundary(
            child: IgnorePointer(
              child: ValueListenableBuilder<bool>(
                valueListenable: _isDrawingNotifier,
                builder: (context, isDrawing, _) {
                  final shapeNotifier =
                      scope.legacyState.currentShapeNotifier;
                  // Wrap in another builder so live shape preview triggers
                  // repaint. Null notifier → bypass the wrapper for perf.
                  return shapeNotifier == null
                      ? _buildScenePainter(
                          scope, viewportSize, context, isDrawing, null)
                      : ValueListenableBuilder<GeometricShape?>(
                          valueListenable: shapeNotifier,
                          builder: (context, currentShape, _) =>
                              _buildScenePainter(scope, viewportSize, context,
                                  isDrawing, currentShape),
                        );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the actual `CustomPaint` for the scene graph, including the
  /// optional live shape preview during a shape-tool drag. Extracted from
  /// [_buildSceneGraphLayer] to keep the conditional `ValueListenableBuilder`
  /// for the shape notifier readable.
  Widget _buildScenePainter(
    CanvasScope scope,
    Size viewportSize,
    BuildContext context,
    bool isDrawing,
    GeometricShape? currentShape,
  ) {
    final legacy = scope.legacyState;
    return CustomPaint(
      painter: DrawingPainter(
        sceneGraph: scope.layerController.sceneGraph,
        layers: scope.layerController.layers,
        spatialIndex: _tierConfig.useSpatialIndex
            ? scope.layerController.spatialIndex
            : null,
        completedShapes: _collectShapes(scope),
        currentShape: currentShape,
        canvasOffset: _canvasController.offset,
        canvasScale: _canvasController.scale,
        viewportSize: viewportSize,
        devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
        controller: _canvasController,
        // Use the canvas-document paper background so DrawingPainter's
        // layer-merge optimization paints the same substrate the
        // BackgroundPainter underneath does (no color flash).
        backgroundColor: legacy.paperBackgroundColor,
        isActivelyDrawing: isDrawing,
        eraserPreviewIds: legacy.eraserPreviewIds,
        scratchOutPreviewIds: legacy.scratchOutPreviewIds,
        scratchOutDissolveMap: legacy.scratchOutDissolveMap,
        recallHiddenIds: legacy.recallHiddenStrokeIds,
        // 🚀 LAYER MERGE: paint background/template inside DrawingPainter
        // to avoid an extra Stack layer composite per frame.
        paperType: legacy.paperType,
        // 📄 PDF — without these PDF pages are invisible in this view.
        pdfPainters: legacy.pdfPainters,
        onPdfRepaint: legacy.onPdfRepaint,
        pdfSearchController: legacy.pdfSearchController,
        pdfLayoutVersion: legacy.pdfLayoutVersion,
        showPdfPageNumbers: legacy.showPdfPageNumbers,
        // 🖼️ Clipping for in-canvas image edit mode.
        enableClipping: legacy.isImageEditFromInfiniteCanvas,
        // 📐 Finite canvas dimensions (A4, letter, ...). `Size.zero` means
        // infinite canvas mode (no bounded paper).
        canvasSize: legacy.dynamicCanvasSize ?? Size.zero,
        // 🚀 Adaptive LOD config from device + user preference.
        adaptiveConfig: legacy.renderingConfig,
        // 🧬 Programmable materiality (watercolor on cold-press, etc.).
        surface: legacy.activeSurface,
      ),
      isComplex: true,
      willChange: false,
      size: Size.infinite,
    );
  }

  /// Dedicated image layer — separate from [DrawingPainter]'s scene graph
  /// traversal. Renders [ImageElement]s with selection handles (resize,
  /// rotate corners) and the loading placeholder pulse. Reads images,
  /// loaded textures, version, spatial index, memory manager from the
  /// [CanvasLegacyState] that the screen wrapper exposes.
  Widget _buildImageLayer(CanvasScope scope) {
    final legacy = scope.legacyState;
    final imageRepaint = legacy.imageRepaint;
    return AnimatedBuilder(
      animation: _canvasController,
      builder: (context, child) {
        final m = Matrix4.identity()
          ..translateByDouble(
            _canvasController.offset.dx,
            _canvasController.offset.dy,
            0.0,
            1.0,
          );
        if (_canvasController.rotation != 0.0) {
          m.rotateZ(_canvasController.rotation);
        }
        final s = _canvasController.scale;
        m.scaleByDouble(s, s, 1.0, 1.0);
        return Transform(transform: m, child: child);
      },
      child: RepaintBoundary(
        child: IgnorePointer(
          child: CustomPaint(
            painter: ImagePainter(
              images: legacy.imageElements,
              loadedImages: legacy.loadedImages,
              selectedImage: scope.imageTool!.selectedImage,
              imageTool: scope.imageTool!,
              controller: _canvasController,
              imageVersion: legacy.imageVersion,
              devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
              spatialIndex: legacy.imageSpatialIndex,
              memoryManager: legacy.imageMemoryManager,
              imageRepaintNotifier: imageRepaint is ValueNotifier<int>
                  ? imageRepaint
                  : null,
              // 🖼️ Selection-handle alignment to surrounding strokes.
              canvasStrokes: scope.layerController.layers
                  .firstWhere(
                    (l) => l.id == scope.layerController.activeLayerId,
                    orElse: () => scope.layerController.layers.first,
                  )
                  .strokes,
              // 🖼️ Micro-thumbnails (ImageStub) for snappy scroll.
              microThumbnails: legacy.microThumbnails,
            ),
            isComplex: true,
            willChange: false,
            size: Size.infinite,
          ),
        ),
      ),
    );
  }

  /// Cognitive overlay layer — Ghost Map (knowledge gaps) and Fog of War
  /// (mastery map). Both painters draw in canvas-space, so the layer is
  /// wrapped in the same widget-level [Transform] as the scene graph
  /// painter. Repaint is triggered by the controllers' notifiers and the
  /// shared cognitive animation controller.
  Widget _buildCognitiveOverlayLayer(
    BuildContext context,
    CanvasScope scope,
    Size viewportSize,
  ) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return AnimatedBuilder(
      animation: _canvasController,
      builder: (context, child) {
        final m = Matrix4.identity()
          ..translateByDouble(
            _canvasController.offset.dx,
            _canvasController.offset.dy,
            0.0,
            1.0,
          );
        if (_canvasController.rotation != 0.0) {
          m.rotateZ(_canvasController.rotation);
        }
        final s = _canvasController.scale;
        m.scaleByDouble(s, s, 1.0, 1.0);
        return Transform(transform: m, child: child);
      },
      child: RepaintBoundary(
        child: IgnorePointer(
          child: Stack(
            children: [
              if (scope.knowledgeFlowController != null)
                Positioned.fill(
                  child: _buildKnowledgeFlowPainter(scope, viewportSize),
                ),
              // Zeigarnik pulse — incomplete-node visual cue. Painter
              // early-returns on empty bounds, so safe to mount always.
              if (scope.legacyState.zeigarnikIncompleteBounds.isNotEmpty &&
                  scope.legacyState.zeigarnikAnimation != null)
                Positioned.fill(
                  child: _buildZeigarnikPainter(scope, isDarkMode),
                ),
              // Golden shimmer — mastered SRS Stage 4+. Same idempotent
              // early-return; gated on user-toggled `goldenShimmerEnabled`.
              if (scope.legacyState.goldenShimmerEnabled &&
                  scope.legacyState.goldenShimmerBounds.isNotEmpty &&
                  scope.legacyState.goldenShimmerAnimation != null)
                Positioned.fill(
                  child: _buildGoldenShimmerPainter(scope, isDarkMode),
                ),
              if (scope.srsReviewSession.isActive)
                Positioned.fill(
                  child: _buildSrsBlurPainter(scope, isDarkMode),
                ),
              if (scope.recallModeController.isActive)
                Positioned.fill(
                  child: _buildRecallPainter(scope),
                ),
              if (scope.ghostMapController.isActive)
                Positioned.fill(
                  child: _buildGhostMapPainter(
                    scope,
                    viewportSize,
                    isDarkMode,
                    dpr,
                  ),
                ),
              if (scope.fogOfWarController.isActive)
                Positioned.fill(
                  child: _buildFogOfWarPainter(
                    scope,
                    viewportSize,
                    isDarkMode,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Knowledge Flow painter — word underlines + cluster connections + label
  /// pills. Repaints when the controller version notifier ticks (cluster
  /// connection added/removed, drag in progress, ...).
  ///
  /// Auxiliary state still owned by the screen (drag source/current points,
  /// snap target, semantic morph, audio highlight, flight animation) is
  /// passed through with safe nulls/defaults — those features degrade
  /// gracefully when the screen wrapper hasn't supplied them.
  Widget _buildKnowledgeFlowPainter(CanvasScope scope, Size viewportSize) {
    final kfc = scope.knowledgeFlowController!;
    return ListenableBuilder(
      listenable: Listenable.merge([kfc.version, _cognitiveAnimController]),
      builder: (context, _) {
        // Inflate viewport for partial connections that cross the edge.
        final viewport = _computeViewportCanvasRect(viewportSize);
        final inflated = viewport.inflate(viewport.longestSide * 0.25);
        final visible = scope.clusterCache
            .where((c) => c.bounds.overlaps(inflated))
            .toList(growable: false);
        final animTime =
            DateTime.now().millisecondsSinceEpoch % 10000 / 1000.0;
        return CustomPaint(
          painter: KnowledgeFlowPainter(
            clusters: visible,
            controller: kfc,
            canvasScale: _canvasController.scale,
            animationTime: animTime,
          ),
          size: Size.infinite,
        );
      },
    );
  }

  /// Zeigarnik pulse painter — amber pulsing border on incomplete cluster
  /// nodes (open loops kept salient by the cognitive system). Bounds are
  /// computed by the screen wrapper and pushed via [CanvasLegacyState].
  Widget _buildZeigarnikPainter(CanvasScope scope, bool isDarkMode) {
    final anim = scope.legacyState.zeigarnikAnimation!;
    final bounds = scope.legacyState.zeigarnikIncompleteBounds;
    return ListenableBuilder(
      listenable: anim,
      builder: (context, _) {
        // The animation Listenable is normally an AnimationController whose
        // .value is in [0..1]; convert to phase [0..2π] via reflection.
        final phase = _readAnimationPhase(anim);
        return CustomPaint(
          painter: ZeigarnikPulsePainter(
            incompleteNodeBounds: bounds,
            animPhase: phase,
            canvasScale: _canvasController.scale,
            isDarkMode: isDarkMode,
          ),
          size: Size.infinite,
        );
      },
    );
  }

  /// Golden shimmer painter — subtle gold glow on SRS-mastered (Stage 4+)
  /// cluster nodes. Visible only when [CanvasLegacyState.goldenShimmerEnabled]
  /// is true and the user hasn't disabled the celebratory FX.
  Widget _buildGoldenShimmerPainter(CanvasScope scope, bool isDarkMode) {
    final anim = scope.legacyState.goldenShimmerAnimation!;
    final bounds = scope.legacyState.goldenShimmerBounds;
    return ListenableBuilder(
      listenable: anim,
      builder: (context, _) {
        final phase = _readAnimationPhase(anim);
        return CustomPaint(
          painter: GoldenShimmerPainter(
            masteredNodeBounds: bounds,
            animPhase: phase,
            canvasScale: _canvasController.scale,
            isDarkMode: isDarkMode,
          ),
          size: Size.infinite,
        );
      },
    );
  }

  /// Read a normalized animation phase [0..2π] from a generic [Listenable].
  /// Accepts [Animation<double>] (.value in 0..1, mapped to 0..2π) and
  /// otherwise falls back to wall-clock — which is good enough for visual
  /// pulses but not deterministic.
  double _readAnimationPhase(Listenable l) {
    if (l is Animation<double>) {
      return l.value * 2 * 3.141592653589793;
    }
    final ms = DateTime.now().millisecondsSinceEpoch % 6000;
    return (ms / 6000.0) * 2 * 3.141592653589793;
  }

  /// Recall mode overlay (PASSO 2) — colored node status overlays + zone
  /// labels for the original/reconstruction split. Reads localized level
  /// labels from [CanvasScope.l10n] via the [RecallLevelL10n] extension.
  ///
  /// Auxiliary screen state (`reconstructionZone`, `showingOriginals`)
  /// not yet migrated — defaults render the active-recall view without the
  /// reconstruction split. Wire those once recall state graduates from
  /// FlueraCanvasScreen into either the controller or CanvasScope.
  Widget _buildRecallPainter(CanvasScope scope) {
    final ctrl = scope.recallModeController;
    return ListenableBuilder(
      listenable: Listenable.merge([ctrl, _cognitiveAnimController]),
      builder: (context, _) {
        final animTime =
            DateTime.now().millisecondsSinceEpoch % 10000 / 1000.0;
        final levelLabels = <RecallLevel, String>{
          for (final lvl in RecallLevel.values)
            lvl: lvl.localizedLabel(scope.l10n),
        };
        return CustomPaint(
          painter: RecallNodeOverlayPainter(
            controller: ctrl,
            animationTime: animTime,
            originalZone: ctrl.selectedZone,
            reconstructionZone: scope.legacyState.recallReconstructionZone,
            showingOriginals: scope.legacyState.recallShowingOriginals,
            labelOriginalZone: scope.l10n.recall_zoneOriginal,
            labelAttemptZone: scope.l10n.recall_zoneAttempt,
            labelReconstruct: scope.l10n.recall_reconstructFromMemory,
            levelLabels: levelLabels,
          ),
          size: Size.infinite,
        );
      },
    );
  }

  /// SRS Blur painter — frosted overlay on clusters scheduled for review,
  /// plus reveal rings (green/red) on revealed clusters.
  Widget _buildSrsBlurPainter(CanvasScope scope, bool isDarkMode) {
    final session = scope.srsReviewSession;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final animTime =
            DateTime.now().millisecondsSinceEpoch % 10000 / 1000.0;
        return CustomPaint(
          painter: SrsBlurOverlayPainter(
            clusters: scope.clusterCache,
            blurredClusterIds: session.blurredClusterIds,
            revealedClusterIds: session.revealedClusterIds,
            revealResults: session.revealResults,
            animationTime: animTime,
            canvasScale: _canvasController.scale,
            isDarkMode: isDarkMode,
          ),
          size: Size.infinite,
        );
      },
    );
  }

  Widget _buildGhostMapPainter(
    CanvasScope scope,
    Size viewportSize,
    bool isDarkMode,
    double devicePixelRatio,
  ) {
    final gmc = scope.ghostMapController;
    return ListenableBuilder(
      listenable: Listenable.merge([gmc.version, _cognitiveAnimController]),
      builder: (context, _) {
        final result = gmc.result;
        if (result == null) return const SizedBox.shrink();

        // Maintain reveal-timestamp map for cross-fade animation. Each
        // revealed node is stamped at first appearance; entries that
        // leave revealedNodeIds are dropped.
        final animTime =
            _cognitiveAnimController.value *
            _cognitiveAnimController.duration!.inMilliseconds /
            1000.0;
        final revealed = gmc.revealedNodeIds;
        for (final id in revealed) {
          _ghostRevealTimestamps.putIfAbsent(id, () => animTime);
        }
        _ghostRevealTimestamps.removeWhere((id, _) => !revealed.contains(id));

        return CustomPaint(
          painter: GhostMapOverlayPainter(
            result: result,
            revealedNodeIds: revealed,
            dismissedNodeIds: gmc.dismissedNodeIds,
            clusters: scope.clusterCache,
            canvasScale: _canvasController.scale,
            animationTime: animTime,
            isDarkMode: isDarkMode,
            viewportRect: _computeViewportCanvasRect(viewportSize),
            visibleMissingNodeIds: gmc.visibleMissingNodeIdsSet,
            revealTimestamps: Map<String, double>.of(_ghostRevealTimestamps),
            labelTapToAttempt: scope.l10n.ghostMap_tapToAttempt,
            labelHypercorrection: scope.l10n.ghostMap_hypercorrectionLabel,
            labelBelowZPD: scope.l10n.ghostMap_belowZPDLabel,
            labelWriteHere: scope.l10n.ghostMap_drawHereHint,
          ),
          size: Size.infinite,
        );
      },
    );
  }

  Widget _buildFogOfWarPainter(
    CanvasScope scope,
    Size viewportSize,
    bool isDarkMode,
  ) {
    final fow = scope.fogOfWarController;
    return ListenableBuilder(
      listenable: Listenable.merge([fow, _cognitiveAnimController]),
      builder: (context, _) {
        final viewportRect = _computeViewportCanvasRect(viewportSize);
        final animTime =
            _cognitiveAnimController.value *
            _cognitiveAnimController.duration!.inMilliseconds /
            1000.0;
        return CustomPaint(
          painter: FogOfWarOverlayPainter(
            controller: fow,
            clusters: scope.clusterCache,
            canvasScale: _canvasController.scale,
            animationTime: animTime,
            viewportCenterCanvas: viewportRect.center,
            viewportCanvasRect: viewportRect,
            isDarkMode: isDarkMode,
          ),
          size: Size.infinite,
        );
      },
    );
  }

  /// Compute the visible canvas-space rect from the current viewport size
  /// and viewport controller transform. Used by cognitive painters for
  /// culling and viewport-center calculations.
  Rect _computeViewportCanvasRect(Size viewportSize) {
    final scale = _canvasController.scale;
    if (scale <= 0) return Rect.largest;
    final left = -_canvasController.offset.dx / scale;
    final top = -_canvasController.offset.dy / scale;
    return Rect.fromLTWH(
      left,
      top,
      viewportSize.width / scale,
      viewportSize.height / scale,
    );
  }

  /// Socratic bubbles overlay — one bubble per question (active +
  /// resolved-not-dismissed). Each bubble is anchored to a cluster in
  /// canvas-space; we re-project to screen-space every frame via
  /// AnimatedBuilder on the canvas controller to keep them aligned with
  /// pan/zoom.
  ///
  /// Callbacks for the active bubble go directly to the [SocraticController]
  /// methods; the screen wrapper's `_socraticSetConfidence`-style methods
  /// (which add haptics + cluster-pulse animations) are NOT invoked here.
  /// View-side haptics are added inline; the cluster pulse animation
  /// stays a screen-only flourish until that state graduates from the
  /// god-object.
  Widget _buildSocraticBubbles(CanvasScope scope) {
    final ctrl = scope.socraticController;
    final dismissed = scope.legacyState.dismissedSocraticIds;
    return AnimatedBuilder(
      animation: Listenable.merge([ctrl, _canvasController]),
      builder: (context, _) {
        final questions = ctrl.allQuestions;
        final activeQ = ctrl.session?.activeQuestion;
        final mediaSize = MediaQuery.sizeOf(context);
        final children = <Widget>[];
        for (int i = 0; i < questions.length; i++) {
          final q = questions[i];
          if (!q.isResolved && q.id != activeQ?.id) continue;
          if (dismissed.contains(q.id)) continue;

          final screenPos = _canvasController.canvasToScreen(q.anchorPosition);
          // Never skip the ACTIVE bubble — auto-pan animates it into
          // view; if we `continue` it never enters the widget tree.
          // (Device fix 2026-05-12 — "non vedo le domande".)
          final isActive = q.id == activeQ?.id;
          final isOffScreen = screenPos.dx < -300 ||
              screenPos.dx > mediaSize.width + 100 ||
              screenPos.dy < -200 ||
              screenPos.dy > mediaSize.height + 100;
          if (isOffScreen && !isActive) {
            continue;
          }

          String? breadcrumbText;
          if (q.breadcrumbsUsed > 0 && q.breadcrumbs.isNotEmpty) {
            final bcIdx =
                (q.breadcrumbsUsed - 1).clamp(0, q.breadcrumbs.length - 1);
            breadcrumbText = q.breadcrumbs[bcIdx];
          }

          children.add(
            SocraticBubble(
              key: ValueKey('socratic_${q.id}'),
              question: q,
              screenPosition: screenPos,
              isActiveQuestion: isActive,
              currentIndex: i,
              totalQuestions: questions.length,
              questionResults: [
                for (final qr in questions)
                  qr.isResolved ? qr.wasCorrect : null,
              ],
              currentBreadcrumbText: breadcrumbText,
              breadcrumbsUsed: q.breadcrumbsUsed,
              canRequestBreadcrumb:
                  isActive && ctrl.canRequestBreadcrumb,
              onConfidenceSelected: isActive
                  ? (level) {
                      ctrl.setConfidence(level);
                      HapticFeedback.selectionClick();
                    }
                  : null,
              onSelfEval: isActive
                  ? (recalled) {
                      ctrl.recordResult(recalled: recalled);
                      // Hypercorrection deserves a heavier haptic (P3-21).
                      if (q.isHypercorrection) {
                        HapticFeedback.heavyImpact();
                      } else if (q.wasWrong) {
                        HapticFeedback.mediumImpact();
                      } else {
                        HapticFeedback.lightImpact();
                      }
                    }
                  : null,
              onSkip: isActive
                  ? () {
                      HapticFeedback.selectionClick();
                      ctrl.skip();
                      if (ctrl.isComplete) {
                        scope.legacyState.onShowSocraticSummary?.call();
                      }
                    }
                  : null,
              onNext: isActive
                  ? () {
                      ctrl.next();
                      if (ctrl.isComplete) {
                        scope.legacyState.onShowSocraticSummary?.call();
                      }
                    }
                  : null,
              onRequestBreadcrumb: isActive
                  ? () {
                      ctrl.requestBreadcrumb();
                      HapticFeedback.selectionClick();
                    }
                  : null,
              // Resolved bubbles can be swiped away. The screen wrapper's
              // dismissed set is a Set<String> directly — view mutates it
              // and ticks selectionRepaint to trigger re-build.
              onDismissResolved: !isActive
                  ? () {
                      dismissed.add(q.id);
                      final repaint = scope.legacyState.selectionRepaint;
                      if (repaint is ValueNotifier<int>) {
                        repaint.value++;
                      }
                    }
                  : null,
            ),
          );
        }
        return Stack(children: children);
      },
    );
  }

  /// Echo Search overlay — "Query Pen" neon glow on strokes that match
  /// the current handwriting search query. The wrapping
  /// [EchoSearchPenOverlay] manages its own breath animation; we listen
  /// to the controller version so freshly-found matches re-render.
  Widget _buildEchoSearchOverlay(CanvasScope scope) {
    final ctrl = scope.echoSearchController!;
    return AnimatedBuilder(
      animation: Listenable.merge([ctrl, _canvasController]),
      builder: (context, _) {
        return IgnorePointer(
          child: EchoSearchPenOverlay(
            controller: ctrl,
            canvasOffset: _canvasController.offset,
            canvasScale: _canvasController.scale,
          ),
        );
      },
    );
  }

  /// Ghost ink overlay — predicted text rendered as faint ink ahead of the
  /// pen tip (word autocomplete preview). Anchor is in screen-space; the
  /// painter converts internally via `_canvasController.screenToCanvas()`.
  /// Skipped silently when no prediction is active.
  Widget _buildGhostInkLayer(CanvasScope scope) {
    final label = scope.legacyState.predictionLabel!;
    final anchorScreen = scope.legacyState.predictionAnchorScreen!;
    return AnimatedBuilder(
      animation: _canvasController,
      builder: (context, _) {
        final canvasPos = _canvasController.screenToCanvas(anchorScreen);
        return RepaintBoundary(
          child: IgnorePointer(
            child: CustomPaint(
              painter: GhostInkPainter(
                text: label,
                position: canvasPos,
                canvasScale: _canvasController.scale,
                color: scope.toolController.color,
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }

  /// Ruler & smart-guides overlay — interactive guide handles, ruler
  /// strips along the canvas edges, distance / measurement annotations.
  /// The overlay is self-contained ([RulerInteractiveOverlay] manages
  /// its own gestures) — we just rebuild when the screen wrapper signals
  /// a guide-system mutation via [CanvasLegacyState.selectionRepaint]
  /// (the same `_uiRebuildNotifier` that ticks for lasso changes).
  Widget _buildRulerOverlay(BuildContext context, CanvasScope scope) {
    final repaint = scope.legacyState.selectionRepaint!;
    return ListenableBuilder(
      listenable: repaint,
      builder: (context, _) {
        return RulerInteractiveOverlay(
          guideSystem: scope.rulerGuideSystem!,
          canvasController: _canvasController,
          isDark: Theme.of(context).brightness == Brightness.dark,
          onChanged: () {
            // Trigger our own repaint by touching the notifier; the screen
            // wrapper's `onChanged` already does this, but in standalone
            // (test/multiview) usage there might be no wrapper hook.
            if (repaint is ValueNotifier<int>) {
              repaint.value++;
            }
          },
        );
      },
    );
  }

  /// Local sync playback overlay — drawn while the user records audio
  /// alongside their drawing. The overlay's controls are rendered
  /// globally (not here); this just shows the timing-driven visual
  /// markers tied to the current audio frame.
  Widget _buildLocalPlaybackOverlay(CanvasScope scope) {
    final ctrl = scope.legacyState.externalPlaybackController!;
    return ListenableBuilder(
      listenable: _canvasController,
      builder: (context, _) {
        return SynchronizedPlaybackOverlay(
          controller: ctrl,
          canvasOffset: _canvasController.offset,
          canvasScale: _canvasController.scale,
          showControls: false,
          forcePageIndex: scope.legacyState.playbackPageIndex,
        );
      },
    );
  }

  /// Recorded playback overlay — cinematic stroke replay from a saved
  /// session. Includes auto-follow that pans the canvas to keep the
  /// active stroke centered.
  Widget _buildRecordedPlaybackOverlay(CanvasScope scope) {
    final ctrl = scope.legacyState.recordedPlaybackController!;
    return AnimatedBuilder(
      animation: _canvasController,
      builder: (context, _) => SynchronizedPlaybackOverlay(
        controller: ctrl,
        canvasOffset: _canvasController.offset,
        canvasScale: _canvasController.scale,
        onClose: scope.legacyState.onStopRecordedPlayback,
        backgroundColor: scope.legacyState.paperBackgroundColor,
        onAutoFollow: scope.legacyState.onPlaybackAutoFollow,
      ),
    );
  }

  /// Live subtitle overlay — "Listening…" placeholder + live transcript
  /// pinned to the bottom of the canvas while audio is recording.
  Widget _buildLiveSubtitleOverlay(BuildContext context, CanvasScope scope) {
    final cs = Theme.of(context).colorScheme;
    final notifier = scope.legacyState.liveTranscriptionText!;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: ValueListenableBuilder<String>(
        valueListenable: notifier,
        builder: (ctx, text, _) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.15),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: text.isEmpty
                ? Container(
                    key: const ValueKey('listening'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Listening...',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
                    key: ValueKey('text_${text.length ~/ 10}'),
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }

  /// Eraser auxiliary overlays — full eraser FX stack rendered while the
  /// eraser is active (cursor non-null): trail, particles, lasso path,
  /// protected regions, ghost preview, magnetic snap. All painters are
  /// screen-space; the wrapping IgnorePointer prevents stealing input.
  Widget _buildEraserAuxOverlays(BuildContext context, CanvasScope scope) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final legacy = scope.legacyState;
    final cursorCanvas = legacy.eraserCursorPosition!;
    return ListenableBuilder(
      listenable: _cognitiveAnimController,
      builder: (context, _) {
        final now = DateTime.now().millisecondsSinceEpoch;
        return IgnorePointer(
          child: Stack(
            children: [
              // Eraser trail
              if (legacy.eraserTrail.length >= 2)
                Positioned.fill(
                  child: CustomPaint(
                    painter: EraserTrailPainter(
                      trail: legacy.eraserTrail,
                      canvasController: _canvasController,
                      now: now,
                      isDark: isDark,
                    ),
                  ),
                ),
              // Boundary particles
              if (legacy.eraserParticles.isNotEmpty)
                Positioned.fill(
                  child: CustomPaint(
                    painter: EraserParticlePainter(
                      particles: legacy.eraserParticles,
                      canvasController: _canvasController,
                      isDark: isDark,
                    ),
                  ),
                ),
              // Lasso eraser path overlay
              if (legacy.eraserLassoMode &&
                  legacy.eraserLassoPoints.length >= 2)
                Positioned.fill(
                  child: CustomPaint(
                    painter: EraserLassoPathPainter(
                      points: legacy.eraserLassoPoints,
                      canvasController: _canvasController,
                      isDark: isDark,
                      isAnimating: legacy.eraserLassoAnimating,
                    ),
                  ),
                ),
              // Protected regions overlay
              if (legacy.eraserProtectedRegions.isNotEmpty)
                Positioned.fill(
                  child: CustomPaint(
                    painter: EraserProtectedRegionPainter(
                      regions: legacy.eraserProtectedRegions,
                      canvasController: _canvasController,
                      isDark: isDark,
                    ),
                  ),
                ),
              // Ghost preview — strokes about to be erased
              if (legacy.eraserPreviewIds.isNotEmpty)
                Positioned.fill(
                  child: CustomPaint(
                    painter: EraserGhostPreviewPainter(
                      previewStrokeIds: legacy.eraserPreviewIds,
                      layerController: scope.layerController,
                      canvasController: _canvasController,
                      isDark: isDark,
                    ),
                  ),
                ),
              // Magnetic snap indicator
              if (legacy.eraserMagneticSnapEnabled &&
                  legacy.eraserMagneticSnapTarget != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: MagneticSnapIndicatorPainter(
                      cursorPos:
                          _canvasController.canvasToScreen(cursorCanvas),
                      snapTarget: _canvasController.canvasToScreen(
                        legacy.eraserMagneticSnapTarget!,
                      ),
                      isDark: isDark,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Eraser visual FX overlay — fading trail polyline + particle puffs at
  /// erase intersection points. Both painters render in screen-space and
  /// do their own [InfiniteCanvasController.canvasToScreen] conversion.
  ///
  /// Trail/particles are pushed by the screen wrapper through
  /// [CanvasLegacyState.eraserTrail] / [CanvasLegacyState.eraserParticles].
  /// Repaint is forced via a wall-clock notifier (`_eraserRepaintTicker`)
  /// to keep the fade-out animation flowing even when no new sample
  /// arrives — required for the trail to fully dissipate after pen-up.
  Widget _buildEraserOverlay(BuildContext context, CanvasScope scope) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trail = scope.legacyState.eraserTrail;
    final particles = scope.legacyState.eraserParticles;
    return ListenableBuilder(
      listenable: _cognitiveAnimController,
      builder: (context, _) {
        final now = DateTime.now().millisecondsSinceEpoch;
        return IgnorePointer(
          child: Stack(
            children: [
              if (trail.length >= 2)
                Positioned.fill(
                  child: CustomPaint(
                    painter: EraserTrailPainter(
                      trail: trail,
                      canvasController: _canvasController,
                      now: now,
                      isDark: isDark,
                    ),
                  ),
                ),
              if (particles.isNotEmpty)
                Positioned.fill(
                  child: CustomPaint(
                    painter: EraserParticlePainter(
                      particles: particles,
                      canvasController: _canvasController,
                      isDark: isDark,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Inline text editor overlay — wraps `InlineTextOverlay` at the
  /// active text element's screen-projected position. Element scale +
  /// canvas scale combine for the effective font size; element max
  /// width clamps the editing field. Submit / cancel / selection
  /// callbacks bridge back to the screen wrapper's text editing flow.
  Widget _buildInlineTextOverlay(CanvasScope scope) {
    final snap = scope.legacyState.inlineTextEditing!;
    final element = snap.element;
    return AnimatedBuilder(
      animation: _canvasController,
      builder: (context, _) {
        final scale = _canvasController.scale;
        final screenPos =
            _canvasController.canvasToScreen(element.position);
        final mediaWidth = MediaQuery.sizeOf(context).width;
        return Positioned(
          left: screenPos.dx,
          top: screenPos.dy,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: element.maxWidth != null
                  ? element.maxWidth! * scale
                  : (mediaWidth - screenPos.dx - 16).clamp(40.0, mediaWidth),
              minWidth: 40,
            ),
            child: InlineTextOverlay(
              initialText: element.text,
              color: snap.color,
              fontSize: snap.fontSize,
              fontWeight: snap.fontWeight,
              fontStyle: snap.fontStyle,
              fontFamily: snap.fontFamily,
              canvasScale: scale,
              elementScale: element.scale,
              shadow: snap.shadow,
              backgroundColor: snap.backgroundColor,
              outlineColor: snap.outlineColor,
              outlineWidth: snap.outlineWidth,
              gradientColors: snap.gradientColors,
              opacity: snap.opacity,
              letterSpacing: snap.letterSpacing,
              textDecoration: snap.textDecoration,
              onSubmit: snap.onSubmit,
              onCancel: snap.onCancel,
              onSelectionChanged: snap.onSelectionChanged,
            ),
          ),
        );
      },
    );
  }

  /// Section creation preview — drag-out rectangle shown while the
  /// user defines a new section. Painter applies the canvas transform
  /// internally; we just supply the start/end points.
  Widget _buildSectionPreviewOverlay(CanvasScope scope) {
    return AnimatedBuilder(
      animation: _canvasController,
      builder: (context, _) {
        return IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: SectionPreviewPainter(
                startPoint: scope.legacyState.sectionStartPoint!,
                endPoint: scope.legacyState.sectionEndPoint!,
                controller: _canvasController,
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }

  /// Fog zone selection preview (PASSO 10) — drag-out rectangle shown
  /// while the user defines a new fog-of-war zone. Same shape as
  /// section preview but with a teal/fog accent.
  Widget _buildFogZonePreviewOverlay(CanvasScope scope) {
    return AnimatedBuilder(
      animation: _canvasController,
      builder: (context, _) {
        return IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: FogZonePreviewPainter(
                startPoint: scope.legacyState.fogZoneStartPoint!,
                endPoint: scope.legacyState.fogZoneEndPoint!,
                controller: _canvasController,
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }

  /// Smart guides overlay — magenta dashed alignment lines drawn while
  /// the user drags an element. The active list is computed by the
  /// screen wrapper's `SmartGuideEngine` and pushed through legacyState.
  Widget _buildSmartGuideOverlay(CanvasScope scope) {
    return AnimatedBuilder(
      animation: _canvasController,
      builder: (context, _) {
        return IgnorePointer(
          child: CustomPaint(
            painter: SmartGuidePainter(
              guides: scope.legacyState.activeSmartGuides,
              controller: _canvasController,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }

  /// Selection transform overlay — resize / rotate / translate handles
  /// for the active lasso selection. Self-managed; we just provide the
  /// transform-complete callback (screen wrapper bumps the selection
  /// repaint notifier + triggers autosave).
  ///
  /// `onEdgeAutoScroll` and `onComputeSnap` are screen-coupled (smart
  /// guides + viewport edge auto-scroll) and NOT yet migrated — they
  /// degrade gracefully (no auto-scroll near edges, no snap-to-guide).
  Widget _buildSelectionTransformOverlay(BuildContext context, CanvasScope scope) {
    return SelectionTransformOverlay(
      lassoTool: scope.lassoTool!,
      canvasController: _canvasController,
      onTransformComplete: scope.legacyState.onSelectionTransformComplete!,
      isDark: Theme.of(context).brightness == Brightness.dark,
    );
  }

  /// Lasso closing ripple — expanding gradient circle drawn at the
  /// gesture's exit point when the freehand lasso closes. Center is
  /// screen-space; animation `value` drives `radius = 20 + t*60` and
  /// `opacity = (1-t)*0.5`. Hidden once `t >= 1.0`.
  Widget _buildLassoRippleOverlay(CanvasScope scope) {
    final center = scope.legacyState.lassoRippleCenter!;
    final anim = scope.legacyState.lassoRippleAnimation!;
    return ListenableBuilder(
      listenable: anim,
      builder: (context, _) {
        final t = anim is Animation<double> ? anim.value : 0.0;
        if (t >= 1.0) return const SizedBox.shrink();
        final radius = 20.0 + t * 60.0;
        final opacity = (1.0 - t) * 0.5;
        return IgnorePointer(
          child: CustomPaint(
            painter: LassoRipplePainter(
              center: center,
              radius: radius,
              opacity: opacity,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }

  /// Lasso path overlay (during drag) — animated dashed line around the
  /// user's freehand path, or the marquee/ellipse rect when in those
  /// selection modes. Repaints from `lassoTool.lassoPathNotifier`.
  ///
  /// Shown only when the user is actively drawing a selection — once the
  /// path closes, [_buildLassoOverlay] takes over with selection bounds
  /// and transform handles.
  Widget _buildLassoPathOverlay(CanvasScope scope) {
    final lasso = scope.lassoTool!;
    return ValueListenableBuilder<int>(
      valueListenable: lasso.lassoPathNotifier,
      builder: (context, _, __) {
        final mode = lasso.selectionMode;
        final hasShape = mode == SelectionMode.marquee
            ? lasso.marqueeRect != null
            : mode == SelectionMode.ellipse
                ? lasso.ellipseRect != null
                : lasso.lassoPath.isNotEmpty;
        if (!hasShape) return const SizedBox.shrink();
        return IgnorePointer(
          child: CustomPaint(
            painter: LassoPathPainter(
              path: lasso.lassoPath,
              color: Colors.blue,
              canvasController: _canvasController,
              selectionMode: mode,
              marqueeRect: mode == SelectionMode.marquee
                  ? lasso.marqueeRect
                  : mode == SelectionMode.ellipse
                      ? lasso.ellipseRect
                      : null,
              repaint: lasso.lassoPathNotifier,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }

  /// Lasso selection overlay — pulsing selection bounds + transform handles.
  /// Repaints on every increment of [CanvasLegacyState.selectionRepaint]
  /// (typically `_uiRebuildNotifier`); reads selected ids + canonical
  /// bounds from [LassoTool]. Self-managed canvas Transform inside the
  /// overlay widget — the overlay is screen-space at the outer level.
  Widget _buildLassoOverlay(CanvasScope scope) {
    final lassoTool = scope.lassoTool!;
    final repaint = scope.legacyState.selectionRepaint!;
    return ListenableBuilder(
      listenable: repaint,
      builder: (context, _) {
        final selectedIds = lassoTool.selectedIds;
        if (selectedIds.isEmpty) return const SizedBox.shrink();
        return LassoSelectionOverlay(
          selectedIds: selectedIds,
          layerController: scope.layerController,
          canvasController: _canvasController,
          isDragging: lassoTool.isDragging,
          featherRadius: lassoTool.featherRadius,
          selectionBounds: lassoTool.getSelectionBounds(),
        );
      },
    );
  }

  /// Predicted tail layer — Apple Pencil predicted touches drawn above
  /// the live stroke. Hidden when the tier doesn't permit predicted tail
  /// or no notifier is provided.
  Widget _buildPredictedTailLayer(CanvasScope scope) {
    final tailNotifier = widget.predictedTailNotifier;
    if (tailNotifier == null) return const SizedBox.shrink();
    return RepaintBoundary(
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: scope.toolController,
          builder: (context, _) {
            final tool = scope.toolController;
            return CustomPaint(
              painter: PredictedTailPainter(
                repaint: Listenable.merge([
                  _currentStrokeNotifier,
                  tailNotifier,
                ]),
                getRealStroke: () => _currentStrokeNotifier.value,
                getPredictedTail: () => tailNotifier.value,
                color: tool.color,
                width: tool.width,
                controller: _canvasController,
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }

  /// Remote live strokes (collab Pro) — peers' in-progress strokes
  /// rendered as simple polylines while the remote pen is down. Painter
  /// applies the canvas transform internally; we just give it the maps
  /// the screen wrapper threaded through `CanvasLegacyState`.
  Widget _buildRemoteLiveStrokesLayer(CanvasScope scope) {
    final legacy = scope.legacyState;
    return AnimatedBuilder(
      animation: _canvasController,
      builder: (context, _) {
        return RepaintBoundary(
          child: IgnorePointer(
            child: CustomPaint(
              painter: RemoteLiveStrokesPainter(
                strokes: legacy.remoteLiveStrokes,
                colors: legacy.remoteLiveStrokeColors,
                widths: legacy.remoteLiveStrokeWidths,
                controller: _canvasController,
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }

  /// PDF loading placeholders (collab Pro) — animated cards shown for
  /// PDFs being uploaded by a peer until the real document arrives.
  /// Pulse phase comes from the shared cognitive animation controller.
  Widget _buildPdfLoadingPlaceholdersLayer(CanvasScope scope) {
    final legacy = scope.legacyState;
    return AnimatedBuilder(
      animation: Listenable.merge([_canvasController, _cognitiveAnimController]),
      builder: (context, _) {
        return RepaintBoundary(
          child: IgnorePointer(
            child: CustomPaint(
              painter: PdfLoadingPlaceholderPainter(
                placeholders: legacy.pdfLoadingPlaceholders,
                controller: _canvasController,
                pulseValue: _cognitiveAnimController.value,
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }

  /// Live preview of the stroke being drawn. Repaints at ~120 Hz from the
  /// stroke notifier; pan/zoom transform applied via the
  /// [InfiniteCanvasController] inside [CurrentStrokePainter.paint].
  Widget _buildLiveStrokeLayer(CanvasScope scope) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: scope.toolController,
          builder: (context, _) {
            final tool = scope.toolController;
            return CustomPaint(
              painter: CurrentStrokePainter(
                strokeNotifier: _currentStrokeNotifier,
                penType: tool.penType,
                color: tool.color,
                width: tool.width,
                controller: _canvasController,
                useNativeOverlay: _tierConfig.useNativeStrokeOverlay,
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }

  /// Gesture detection — pan/zoom + draw input + multi-finger undo/redo +
  /// long-press forwarding. Mirrors the MultiviewPanel pattern: the
  /// gesture detector wraps the painter stack as its child so the
  /// painters are pure visual layers underneath the input pipeline.
  Widget _buildGestureWrapper(
    BuildContext context,
    CanvasScope scope, {
    required Widget child,
  }) {
    return InfiniteCanvasGestureDetector(
      controller: _canvasController,
      onDrawStart: _tierConfig.acceptsDrawingInput ? _onDrawStart : null,
      onDrawUpdate: _tierConfig.acceptsDrawingInput ? _onDrawUpdate : null,
      onDrawBatchUpdate:
          _tierConfig.acceptsDrawingInput ? _onDrawBatchUpdate : null,
      onDrawEnd: _tierConfig.acceptsDrawingInput ? _onDrawEnd : null,
      onDrawCancel:
          _tierConfig.acceptsDrawingInput ? _onDrawCancel : null,
      onTwoFingerTap: () {
        if (scope.layerController.canUndo) {
          scope.layerController.undo();
          HapticFeedback.mediumImpact();
        }
      },
      onThreeFingerTap: () {
        if (scope.layerController.canRedo) {
          scope.layerController.redo();
          HapticFeedback.mediumImpact();
        }
      },
      onLongPress: widget.onLongPress != null
          ? (canvasPos) => widget.onLongPress!(canvasPos)
          : null,
      child: child,
    );
  }

  /// Materialize all completed shapes from the layer tree.
  ///
  /// Used by [DrawingPainter] for shape rendering. Cheap — shapes are
  /// usually a small fraction of node count vs. strokes.
  List<GeometricShape> _collectShapes(CanvasScope scope) {
    final out = <GeometricShape>[];
    for (final layer in scope.layerController.layers) {
      if (!layer.isVisible) continue;
      out.addAll(layer.shapes);
    }
    return out;
  }
}
