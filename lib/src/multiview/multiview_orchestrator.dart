import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../canvas/infinite_canvas_controller.dart';
import '../canvas/fluera_canvas_config.dart';
import '../canvas/overlays/canvas_radial_menu.dart';
import '../config/advanced_split_layout.dart';
import '../config/split_panel_content.dart';
import '../config/wheel_mode_pref.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../layers/layer_controller.dart';
import '../tools/unified_tool_controller.dart';
import './multiview_state.dart';
import './multiview_panel.dart';
import './multiview_layout_renderer.dart';
import './multiview_tool_palette.dart';

// =============================================================================
// MULTIVIEW ORCHESTRATOR — Top-level coordinator for multi-panel canvas
// =============================================================================

/// Orchestrates a multi-panel canvas workspace.
///
/// Architecture: **Shared Document, Independent Cameras**
/// - Single [LayerController] holds all canvas content (strokes, shapes, etc.)
/// - Single [UnifiedToolController] manages tool state (color, width, tool)
/// - Each panel gets its own [InfiniteCanvasController] for independent
///   zoom, pan, and rotation
///
/// Drawing on any panel writes to the shared [LayerController], and all panels
/// repaint automatically via [ChangeNotifier].
class MultiviewOrchestrator extends StatefulWidget {
  /// SDK configuration (shared across all panels).
  final FlueraCanvasConfig config;

  /// Initial layout configuration.
  final AdvancedSplitLayout initialLayout;

  /// Canvas ID being edited.
  final String canvasId;

  /// The ACTUAL layer controller from the main canvas.
  /// Must be the same instance used for drawing, NOT config.layerController.
  final LayerController layerController;

  /// Callback to exit multiview mode.
  final VoidCallback onExitMultiview;

  /// Optional title for the canvas.
  final String? title;

  /// Initial viewport offset (from main canvas).
  final Offset initialOffset;

  /// Initial viewport scale (from main canvas).
  final double initialScale;

  const MultiviewOrchestrator({
    super.key,
    required this.config,
    required this.initialLayout,
    required this.canvasId,
    required this.layerController,
    required this.onExitMultiview,
    this.title,
    this.initialOffset = Offset.zero,
    this.initialScale = 1.0,
  });

  @override
  State<MultiviewOrchestrator> createState() => _MultiviewOrchestratorState();
}

class _MultiviewOrchestratorState extends State<MultiviewOrchestrator>
    with TickerProviderStateMixin {
  // ── Constants ──────────────────────────────────────────────────────────────
  static const _kAnimDuration = Duration(milliseconds: 350);
  static const _kFitPadding = 1.1; // 10% padding for fit-to-content
  static const _kMinScale = 0.1;
  static const _kMaxScale = 5.0;

  // ── Shared state ───────────────────────────────────────────────────────────
  late final LayerController _layerController;
  late final UnifiedToolController _toolController;

  // ── Per-panel state ────────────────────────────────────────────────────────
  final Map<int, InfiniteCanvasController> _panelControllers = {};

  // ── Per-panel viewport sizes (updated by LayoutBuilder) ────────────────────
  final Map<int, Size> _panelSizes = {};

  // ── Multiview session state ────────────────────────────────────────────────
  late MultiviewState _state;

  // ── Cross-panel cursor (canvas coords of active drawing position) ──────────
  final ValueNotifier<Offset?> _cursorPosition = ValueNotifier(null);

  // ── Cinematic animation (per-panel to avoid collisions) ────────────────────
  final Map<int, AnimationController> _viewportAnims = {};
  // OPT #4: Track current animation listeners to avoid leaks on rapid re-calls
  final Map<int, VoidCallback> _viewportAnimListeners = {};

  // ── Radial menu (toolwheel mode) ───────────────────────────────────────────
  bool _showRadialMenu = false;
  Offset _radialMenuCenter = Offset.zero;
  final _radialMenuKey = GlobalKey<CanvasRadialMenuState>();

  // ── Staggered panel init (prevents raster spike) ───────────────────────
  int _readyPanelCount = 0;

  // ── Entrance fade-in (masks first-time shader compilation) ──────────────
  late final AnimationController _entranceAnim;

  @override
  void initState() {
    super.initState();
    _layerController = widget.layerController;
    _toolController = UnifiedToolController();

    _state = MultiviewState.fromLayout(widget.initialLayout);

    // Create controllers for each panel — inherit main canvas viewport
    for (int i = 0; i < _state.panelCount; i++) {
      final c = InfiniteCanvasController();
      c.updateTransform(
        offset: widget.initialOffset,
        scale: widget.initialScale,
      );
      _panelControllers[i] = c;
    }

    // 🚀 Stagger panel initialization: build 1 panel per frame to avoid
    // rasterizing all BrushEngine painters in the same frame (≈16ms spike).
    _staggerPanels();

    // 🎦 Entrance fade-in: renders at opacity 0.01 on first frame so GPU
    // actually paints widgets (compiling shader pipelines). At 0.01 the result
    // is invisible to the human eye. RenderOpacity at exactly 0.0 skips
    // painting entirely, so we MUST start above zero.
    _entranceAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 0.01, // 🚀 Start above zero to force first-frame paint
    );
    _entranceAnim.forward(); // Start immediately (not in postFrameCallback)
  }

  void _staggerPanels() {
    if (_readyPanelCount >= _state.panelCount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _readyPanelCount++);
      _staggerPanels(); // Schedule next panel
    });
  }

  @override
  void dispose() {
    _entranceAnim.dispose();
    for (final anim in _viewportAnims.values) {
      anim.dispose();
    }
    _cursorPosition.dispose();
    _toolController.dispose();
    for (final controller in _panelControllers.values) {
      controller.dispose();
    }
    // 🚀 Release GPU Picture cache to avoid memory leak
    invalidateMultiviewPanelCache();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 🎦 FadeTransition masks first-time shader compilation:
    // Frame 0: opacity=0, widgets paint (GPU compiles pipelines invisibly)
    // Frame 1+: opacity fades to 1.0 (pipelines cached, no jank)
    return FadeTransition(
      opacity: _entranceAnim,
      child: Stack(
        children: [
        // ── Panel Grid (fills all available space) ──────────────────────
        Positioned.fill(
          child: MultiviewLayoutRenderer(
            layout: _state.layout,
            activePanelIndex: _state.activePanelIndex,
            panels: _buildPanels(),
            onProportionsChanged: _onProportionsChanged,
          ),
        ),

        // 🗺️ Minimap (bottom-left) — deferred until panels ready to avoid
        // minimap's first paint (stroke dot iteration) causing raster spike
        if (_readyPanelCount >= _state.panelCount)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 8,
            left: 8,
            child: _MultiviewMinimap(
              layerController: _layerController,
              panelControllers: _panelControllers,
              activePanelIndex: _state.activePanelIndex,
              panelSizes: _panelSizes, // OPT #3: pass real sizes
              onNavigate: (canvasPos) {
                final c = _panelControllers[_state.activePanelIndex];
                if (c == null) return;
                final panelSize = _panelSizes[_state.activePanelIndex];
                final panelW = panelSize?.width ?? MediaQuery.of(context).size.width / 2;
                final panelH = panelSize?.height ?? MediaQuery.of(context).size.height / 2;
                final newOffset = Offset(
                  panelW / 2 - canvasPos.dx * c.scale,
                  panelH / 2 - canvasPos.dy * c.scale,
                );
                c.updateTransform(offset: newOffset, scale: c.scale);
              },
            ),
          ),

        // 🔧 Floating controls (top-right) — deferred to avoid first-frame cost
        // 🚀 P99 FIX: RepaintBoundary isolates undo/redo repaints from panel grid
        if (_readyPanelCount >= _state.panelCount)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: RepaintBoundary(
              child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Undo / Redo
                ListenableBuilder(
                  listenable: _layerController,
                  builder: (context, _) {
                    return _FloatingChip(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ToolbarIconButton(
                            icon: Icons.undo_rounded,
                            tooltip: 'Undo',
                            onPressed:
                                _layerController.canUndo
                                    ? () {
                                      HapticFeedback.lightImpact();
                                      _layerController.undo();
                                    }
                                    : null,
                            enabled: _layerController.canUndo,
                          ),
                          _ToolbarIconButton(
                            icon: Icons.redo_rounded,
                            tooltip: 'Redo',
                            onPressed:
                                _layerController.canRedo
                                    ? () {
                                      HapticFeedback.lightImpact();
                                      _layerController.redo();
                                    }
                                    : null,
                            enabled: _layerController.canRedo,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                // Layout selector
                _FloatingChip(
                  child: _LayoutTypeSelector(
                    currentType: _state.layout.type,
                    onSelected: _changeLayout,
                  ),
                ),
                const SizedBox(width: 6),
                // Exit multiview
                _FloatingChip(
                  child: _ToolbarIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Exit Multiview',
                    onPressed: widget.onExitMultiview,
                  ),
                ),
              ],
            ),
            ),
          ),

        // 🎯 Radial menu (toolwheel mode)
        if (_showRadialMenu)
          Positioned.fill(
            child: CanvasRadialMenu(
              key: _radialMenuKey,
              center: _radialMenuCenter,
              currentBrushIndex: _toolController.penType.index,
              currentColor: _toolController.color,
              canUndo: _layerController.canUndo,
              canRedo: _layerController.canRedo,
              hasLastAction: _layerController.canUndo,
              onResult: _handleRadialResult,
            ),
          ),
      ],
      ),
    );
  }

  // ============================================================================
  // PANEL CREATION
  // ============================================================================

  List<Widget> _buildPanels() {
    return List.generate(_state.panelCount, (index) {
      final controller = _panelControllers[index];
      if (controller == null) return const SizedBox();

      // 🚀 Stagger: show lightweight placeholder until this panel is ready
      // NOTE: No CircularProgressIndicator — its gradient/arc shaders cause
      // expensive first-time pipeline compilation on the GPU.
      if (index >= _readyPanelCount) {
        return LayoutBuilder(
          builder: (context, constraints) {
            _panelSizes[index] = Size(constraints.maxWidth, constraints.maxHeight);
            return Container(
              color: Theme.of(context).colorScheme.surface,
            );
          },
        );
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          // Track actual panel size for accurate fit-to-content & minimap nav
          _panelSizes[index] = Size(constraints.maxWidth, constraints.maxHeight);
          return MultiviewPanel(
            key: ValueKey('multiview_panel_$index'),
            layerController: _layerController,
            toolController: _toolController,
            canvasController: controller,
            panelIndex: index,
            isActive: index == _state.activePanelIndex,
            onActivate: () => _setActivePanel(index),
            cursorPosition: _cursorPosition,
            onCursorMoved: (pos) => _cursorPosition.value = pos,
            onDoubleTap: () => _fitToContent(index),
            onLongPress: (pos) => _showPanelContextMenu(index, pos),
          );
        },
      );
    });
  }

  // ============================================================================
  // PANEL CONTEXT MENU (Long-press — touch-first UX)
  // ============================================================================

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    ColorScheme cs,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface)),
        ],
      ),
    );
  }

  void _showPanelContextMenu(int panelIndex, Offset globalPosition) {
    // Branch: wheel mode → radial menu, toolbar mode → popup context menu
    if (WheelModePref.enabled) {
      _setActivePanel(panelIndex);
      HapticFeedback.mediumImpact();
      setState(() {
        _showRadialMenu = true;
        _radialMenuCenter = globalPosition;
      });
      return;
    }

    HapticFeedback.mediumImpact();
    final cs = Theme.of(context).colorScheme;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      items: [
        _menuItem('fit', Icons.fit_screen_rounded, 'Fit to Content', cs),
        _menuItem('reset', Icons.restart_alt_rounded, 'Reset Zoom', cs),
        _menuItem(
          'eraser',
          _toolController.isEraserMode
              ? Icons.edit_rounded
              : Icons.auto_fix_high_rounded,
          _toolController.isEraserMode ? 'Switch to Pen' : 'Switch to Eraser',
          cs,
        ),
        _menuItem('undo', Icons.undo_rounded, 'Undo', cs),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'fit':
          _fitToContent(panelIndex);
        case 'reset':
          final c = _panelControllers[panelIndex];
          if (c != null) {
            _animateToTransform(panelIndex, c, targetOffset: Offset.zero, targetScale: 1.0);
            HapticFeedback.lightImpact();
          }
        case 'eraser':
          _toolController.toggleEraser();
          HapticFeedback.selectionClick();
        case 'undo':
          if (_layerController.canUndo) {
            _layerController.undo();
            HapticFeedback.lightImpact();
          }
      }
    });
  }

  // ============================================================================
  // RADIAL MENU RESULT HANDLER (toolwheel mode)
  // ============================================================================

  void _handleRadialResult(RadialMenuResult result) {
    setState(() => _showRadialMenu = false);

    // Quick-repeat: replay last undo
    if (result.quickRepeat) {
      if (_layerController.canUndo) {
        _layerController.undo();
        HapticFeedback.mediumImpact();
      }
      return;
    }

    if (result.item == null) return;

    switch (result.item!) {
      case RadialMenuItem.undo:
        if (_layerController.canUndo) {
          _layerController.undo();
        } else if (_layerController.canRedo) {
          _layerController.redo();
        }
        HapticFeedback.mediumImpact();

      case RadialMenuItem.brush:
        if (result.brushItem != null) {
          final penType = ProPenType.values[
            result.brushItem!.index.clamp(0, ProPenType.values.length - 1)
          ];
          _toolController.setPenType(penType);
          _toolController.resetToDrawingMode();
          HapticFeedback.selectionClick();
        } else if (result.selectedColor != null) {
          _toolController.setColor(result.selectedColor!);
          HapticFeedback.selectionClick();
        }

      case RadialMenuItem.shape:
        _toolController.toggleShapeRecognition();
        HapticFeedback.selectionClick();

      case RadialMenuItem.text:
        _toolController.toggleDigitalTextMode();
        HapticFeedback.selectionClick();

      case RadialMenuItem.tools:
        if (result.toolItem != null) {
          switch (result.toolItem!) {
            case RadialToolItem.lasso:
              _toolController.toggleLassoMode();
              HapticFeedback.selectionClick();
            case RadialToolItem.multiview:
              break; // Already in multiview — no-op
            default:
              break; // Other tools not applicable in multiview
          }
        }

      default:
        break; // Atlas, KnowledgeMap, Insert — not applicable in multiview
    }
  }

  // ============================================================================
  // STATE MANAGEMENT
  // ============================================================================

  void _setActivePanel(int index) {
    if (index == _state.activePanelIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      _state = _state.copyWith(activePanelIndex: index);
    });
  }

  void _changeLayout(SplitLayoutType newType) {
    HapticFeedback.mediumImpact();

    final newLayout = AdvancedSplitLayout(
      type: newType,
      primaryOrientation: SplitOrientation.horizontal,
      secondaryOrientation: SplitOrientation.vertical,
      panelContents: {
        for (int i = 0; i < newType.panelCount; i++)
          i: SplitPanelContent.canvas(),
      },
      proportions: {
        for (int i = 0; i < newType.panelCount; i++)
          'panel_$i': 1.0 / newType.panelCount,
      },
    );

    // Add new controllers if needed
    for (int i = _panelControllers.length; i < newType.panelCount; i++) {
      _panelControllers[i] = InfiniteCanvasController();
    }

    // Remove excess controllers and associated state
    final toRemove = <int>[];
    for (final key in _panelControllers.keys) {
      if (key >= newType.panelCount) toRemove.add(key);
    }
    for (final key in toRemove) {
      _panelControllers[key]?.dispose();
      _panelControllers.remove(key);
      _viewportAnims[key]?.dispose();
      _viewportAnims.remove(key);
      _panelSizes.remove(key);
    }

    setState(() {
      _state = MultiviewState.fromLayout(newLayout).copyWith(
        activePanelIndex: _state.activePanelIndex.clamp(
          0,
          newType.panelCount - 1,
        ),
      );
    });
  }

  void _onProportionsChanged(Map<String, double> proportions) {
    // Update layout proportions
    final updated = _state.layout.copyWith(proportions: proportions);
    setState(() {
      _state = _state.copyWith(layout: updated);
    });
  }

  void _resetAllViewports() {
    HapticFeedback.mediumImpact();
    for (final entry in _panelControllers.entries) {
      _animateToTransform(
        entry.key,
        entry.value,
        targetOffset: Offset.zero,
        targetScale: 1.0,
      );
      if (entry.value.rotation != 0.0) {
        entry.value.resetRotation();
      }
    }
  }

  // ============================================================================
  // FIT TO CONTENT
  // ============================================================================

  void _fitToContent(int panelIndex) {
    final controller = _panelControllers[panelIndex];
    if (controller == null) return;

    final bounds = computeContentBounds(_layerController);
    if (bounds == null || bounds.isEmpty) return;

    // Use actual panel size (tracked by LayoutBuilder), fallback to estimate
    final panelSize = _panelSizes[panelIndex];
    final panelW = panelSize?.width ?? MediaQuery.of(context).size.width / 2;
    final panelH = panelSize?.height ?? MediaQuery.of(context).size.height / 2;

    // Compute scale to fit content with padding
    final scaleX = panelW / (bounds.width * _kFitPadding);
    final scaleY = panelH / (bounds.height * _kFitPadding);
    final fitScale = (scaleX < scaleY ? scaleX : scaleY).clamp(
      _kMinScale,
      _kMaxScale,
    );

    // Center content in viewport
    final centerX = bounds.center.dx;
    final centerY = bounds.center.dy;
    final offset = Offset(
      panelW / 2 - centerX * fitScale,
      panelH / 2 - centerY * fitScale,
    );

    _animateToTransform(
      panelIndex,
      controller,
      targetOffset: offset,
      targetScale: fitScale,
    );
    HapticFeedback.lightImpact();
  }

  // ============================================================================
  // CINEMATIC VIEWPORT ANIMATION (per-panel controllers)
  // ============================================================================

  void _animateToTransform(
    int panelIndex,
    InfiniteCanvasController controller, {
    required Offset targetOffset,
    required double targetScale,
  }) {
    final startOffset = controller.offset;
    final startScale = controller.scale;

    // Skip animation if already at target
    if ((startOffset - targetOffset).distance < 0.5 &&
        (startScale - targetScale).abs() < 0.001) {
      return;
    }

    // Get or create a per-panel AnimationController to avoid collisions
    var anim = _viewportAnims[panelIndex];
    if (anim == null) {
      anim = AnimationController(vsync: this, duration: _kAnimDuration);
      _viewportAnims[panelIndex] = anim;
    }

    // OPT #4: Remove previous listener to prevent closure leaks on rapid re-calls
    final oldListener = _viewportAnimListeners[panelIndex];
    if (oldListener != null) {
      anim.removeListener(oldListener);
    }

    anim.stop();
    anim.reset();

    void listener() {
      final t = Curves.easeInOutCubic.transform(anim!.value);
      final lerpedOffset = Offset.lerp(startOffset, targetOffset, t)!;
      final lerpedScale = startScale + (targetScale - startScale) * t;
      controller.updateTransform(offset: lerpedOffset, scale: lerpedScale);
    }

    _viewportAnimListeners[panelIndex] = listener;
    anim.addListener(listener);
    anim.forward().then((_) {
      // OPT #5: Guard against dispose during animation
      if (!mounted) return;
      anim!.removeListener(listener);
      _viewportAnimListeners.remove(panelIndex);
    });
  }

  // ============================================================================
  // SHARED UTILITY — Content bounds computation
  // ============================================================================

  /// Computes the bounding rect of all strokes and shapes across all layers.
  /// Returns null if the canvas is empty.
  static Rect? computeContentBounds(LayerController lc) {
    Rect? bounds;
    for (final layer in lc.layers) {
      for (final stroke in layer.strokes) {
        if (stroke.points.isEmpty) continue;
        final sb = stroke.bounds;
        bounds = bounds?.expandToInclude(sb) ?? sb;
      }
      for (final shape in layer.shapes) {
        final sr = Rect.fromPoints(shape.startPoint, shape.endPoint);
        bounds = bounds?.expandToInclude(sr) ?? sr;
      }
    }
    return bounds;
  }
}

// =============================================================================
// FLOATING CHIP — Semi-transparent container for floating overlays
// =============================================================================

/// OPT #6: Caches decoration to avoid per-build allocation of BoxDecoration + BoxShadow list.
class _FloatingChip extends StatelessWidget {
  final Widget child;
  const _FloatingChip({required this.child});

  // Shadow list is theme-independent — safe to cache as static const
  static const _shadow = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 6),
  ];
  static const _borderRadius = BorderRadius.all(Radius.circular(10));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.85),
        borderRadius: _borderRadius,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 0.5,
        ),
        boxShadow: _shadow,
      ),
      child: child,
    );
  }
}

// =============================================================================
// TOOLBAR WIDGETS
// =============================================================================

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool enabled;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              icon,
              size: 18,
              color:
                  enabled
                      ? cs.onSurfaceVariant
                      : cs.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

/// Layout type selector popup button.
class _LayoutTypeSelector extends StatelessWidget {
  final SplitLayoutType currentType;
  final ValueChanged<SplitLayoutType> onSelected;

  const _LayoutTypeSelector({
    required this.currentType,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopupMenuButton<SplitLayoutType>(
      tooltip: 'Change layout',
      onSelected: onSelected,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      offset: const Offset(0, 40),
      itemBuilder:
          (context) =>
              SplitLayoutType.values.map((type) {
                final isSelected = type == currentType;
                return PopupMenuItem<SplitLayoutType>(
                  value: type,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        type.icon,
                        size: 18,
                        color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              type.displayName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                color: isSelected ? cs.primary : cs.onSurface,
                              ),
                            ),
                            Text(
                              '${type.panelCount} panels',
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_rounded, size: 16, color: cs.primary),
                    ],
                  ),
                );
              }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(currentType.icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              currentType.displayName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// MINIMAP — Shows panel viewports relative to content
// =============================================================================

class _MultiviewMinimap extends StatefulWidget {
  final LayerController layerController;
  final Map<int, InfiniteCanvasController> panelControllers;
  final int activePanelIndex;
  final Map<int, Size> panelSizes; // OPT #3: real panel sizes
  final void Function(Offset canvasPosition) onNavigate;

  static const double _width = 140;
  static const double _height = 90;

  static const _panelColors = [
    Color(0xFF2196F3), // Blue
    Color(0xFFFF9800), // Orange
    Color(0xFF4CAF50), // Green
    Color(0xFFE91E63), // Pink
  ];

  const _MultiviewMinimap({
    required this.layerController,
    required this.panelControllers,
    required this.activePanelIndex,
    required this.onNavigate,
    this.panelSizes = const {},
  });

  @override
  State<_MultiviewMinimap> createState() => _MultiviewMinimapState();
}

class _MultiviewMinimapState extends State<_MultiviewMinimap> {
  // Cached mapping info (updated on each build by painter)
  Rect _contentBounds = const Rect.fromLTWH(-500, -500, 1000, 1000);
  double _mapScale = 1.0;
  double _mapOffsetX = 0.0;
  double _mapOffsetY = 0.0;

  // Cached merged listenable to avoid per-build allocation
  late Listenable _mergedListenable;

  @override
  void initState() {
    super.initState();
    _mergedListenable = _createMergedListenable();
  }

  @override
  void didUpdateWidget(covariant _MultiviewMinimap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layerController != widget.layerController ||
        oldWidget.panelControllers != widget.panelControllers) {
      _mergedListenable = _createMergedListenable();
    }
  }

  Listenable _createMergedListenable() => Listenable.merge([
    widget.layerController,
    ...widget.panelControllers.values,
  ]);

  /// Convert a local position on the minimap widget to canvas coordinates.
  Offset _minimapToCanvas(Offset localPos) {
    final canvasX =
        _contentBounds.left + (localPos.dx - _mapOffsetX) / _mapScale;
    final canvasY =
        _contentBounds.top + (localPos.dy - _mapOffsetY) / _mapScale;
    return Offset(canvasX, canvasY);
  }

  void _handleTapOrDrag(Offset localPos) {
    final canvasPos = _minimapToCanvas(localPos);
    widget.onNavigate(canvasPos);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _mergedListenable,
      builder: (context, _) {
        // Pre-calculate mapping for gesture conversion
        _updateMapping();

        return GestureDetector(
          onTapDown: (d) => _handleTapOrDrag(d.localPosition),
          onPanUpdate: (d) => _handleTapOrDrag(d.localPosition),
          onPanStart: (d) {
            HapticFeedback.selectionClick();
            _handleTapOrDrag(d.localPosition);
          },
          child: Container(
            width: _MultiviewMinimap._width,
            height: _MultiviewMinimap._height,
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.3),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                // OPT #2: Pass pre-computed mapping to painter (avoids double computation)
                painter: _MinimapPainter(
                  layerController: widget.layerController,
                  panelControllers: widget.panelControllers,
                  activePanelIndex: widget.activePanelIndex,
                  panelSizes: widget.panelSizes, // OPT #3
                  mappedBounds: _contentBounds,
                  mapScale: _mapScale,
                  mapOffsetX: _mapOffsetX,
                  mapOffsetY: _mapOffsetY,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Keep mapping in sync — single source of truth for gesture conversion.
  void _updateMapping() {
    Rect? contentBounds =
        _MultiviewOrchestratorState.computeContentBounds(widget.layerController);
    contentBounds ??= const Rect.fromLTWH(-500, -500, 1000, 1000);

    for (final entry in widget.panelControllers.entries) {
      final c = entry.value;
      if (c.scale <= 0) continue;
      // OPT #3: Use real panel sizes instead of hardcoded estimates
      final ps = widget.panelSizes[entry.key];
      final vpW = (ps?.width ?? _MultiviewMinimap._width * 3) / c.scale;
      final vpH = (ps?.height ?? _MultiviewMinimap._height * 3) / c.scale;
      final vpTopLeft = Offset(-c.offset.dx / c.scale, -c.offset.dy / c.scale);
      final vpRect = Rect.fromLTWH(vpTopLeft.dx, vpTopLeft.dy, vpW, vpH);
      contentBounds = contentBounds!.expandToInclude(vpRect);
    }

    final cb = contentBounds!.inflate(contentBounds.shortestSide * 0.1);
    final scaleX = _MultiviewMinimap._width / cb.width;
    final scaleY = _MultiviewMinimap._height / cb.height;
    _mapScale = scaleX < scaleY ? scaleX : scaleY;
    _mapOffsetX = (_MultiviewMinimap._width - cb.width * _mapScale) / 2;
    _mapOffsetY = (_MultiviewMinimap._height - cb.height * _mapScale) / 2;
    _contentBounds = cb;
  }
}

/// OPT #1/#2/#3: Pre-allocated Paints, uses pre-computed mapping, real panel sizes.
class _MinimapPainter extends CustomPainter {
  final LayerController layerController;
  final Map<int, InfiniteCanvasController> panelControllers;
  final int activePanelIndex;
  final Map<int, Size> panelSizes;
  // OPT #2: Pre-computed mapping from _updateMapping()
  final Rect mappedBounds;
  final double mapScale;
  final double mapOffsetX;
  final double mapOffsetY;

  // OPT #1: Pre-allocated static Paints
  static final Paint _dotPaint = Paint()
    ..color = const Color(0x55000000)
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;
  static final Paint _vpFillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _vpBorderPaint = Paint()..style = PaintingStyle.stroke;

  _MinimapPainter({
    required this.layerController,
    required this.panelControllers,
    required this.activePanelIndex,
    required this.panelSizes,
    required this.mappedBounds,
    required this.mapScale,
    required this.mapOffsetX,
    required this.mapOffsetY,
  });

  Offset _mapPoint(double x, double y) => Offset(
    mapOffsetX + (x - mappedBounds.left) * mapScale,
    mapOffsetY + (y - mappedBounds.top) * mapScale,
  );

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw content dots (simplified strokes)
    for (final layer in layerController.layers) {
      if (!layer.isVisible) continue;
      for (final stroke in layer.strokes) {
        if (stroke.points.isEmpty) continue;
        final pts = stroke.points;
        final indices = [0, pts.length ~/ 2, pts.length - 1];
        for (final i in indices) {
          if (i >= pts.length) continue;
          final p = _mapPoint(pts[i].position.dx, pts[i].position.dy);
          canvas.drawCircle(p, 0.8, _dotPaint);
        }
      }
    }

    // 2. Draw viewport rectangles for each panel
    for (final entry in panelControllers.entries) {
      final idx = entry.key;
      final c = entry.value;
      final scale = c.scale;
      if (scale <= 0) continue;

      final vpTopLeft = Offset(-c.offset.dx / scale, -c.offset.dy / scale);
      // OPT #3: Use real panel sizes instead of hardcoded 400x300
      final ps = panelSizes[idx];
      final vpW = (ps?.width ?? 400) / scale;
      final vpH = (ps?.height ?? 300) / scale;

      final topLeft = _mapPoint(vpTopLeft.dx, vpTopLeft.dy);
      final bottomRight = _mapPoint(vpTopLeft.dx + vpW, vpTopLeft.dy + vpH);

      final color = _MultiviewMinimap._panelColors[
          idx % _MultiviewMinimap._panelColors.length];
      final isActive = idx == activePanelIndex;

      _vpFillPaint.color = color.withValues(alpha: isActive ? 0.3 : 0.15);
      _vpBorderPaint
        ..color = color.withValues(alpha: isActive ? 0.9 : 0.5)
        ..strokeWidth = isActive ? 1.5 : 0.8;

      final vpRect = Rect.fromPoints(topLeft, bottomRight);
      canvas.drawRect(vpRect, _vpFillPaint);
      canvas.drawRect(vpRect, _vpBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) => true;
}
