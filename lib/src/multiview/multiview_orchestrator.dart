import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../canvas/infinite_canvas_controller.dart';
import '../canvas/fluera_canvas_config.dart';
import '../config/advanced_split_layout.dart';
import '../config/split_panel_content.dart';
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
  // ── Shared state ───────────────────────────────────────────────────────────
  late final LayerController _layerController;
  late final UnifiedToolController _toolController;

  // ── Per-panel state ────────────────────────────────────────────────────────
  final Map<int, InfiniteCanvasController> _panelControllers = {};

  // ── Multiview session state ────────────────────────────────────────────────
  late MultiviewState _state;

  // ── Cross-panel cursor (canvas coords of active drawing position) ──────────
  final ValueNotifier<Offset?> _cursorPosition = ValueNotifier(null);

  // ── Cinematic animation ───────────────────────────────────────────────────
  late final AnimationController _viewportAnim;

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

    _viewportAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void dispose() {
    _viewportAnim.dispose();
    _cursorPosition.dispose();
    for (final controller in _panelControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
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

        // 🗺️ Minimap (bottom-left)
        Positioned(
          bottom: 8,
          left: 8,
          child: _MultiviewMinimap(
            layerController: _layerController,
            panelControllers: _panelControllers,
            activePanelIndex: _state.activePanelIndex,
            onNavigate: (canvasPos) {
              final c = _panelControllers[_state.activePanelIndex];
              if (c == null) return;
              // Center the active panel's viewport on canvasPos
              final screenSize = MediaQuery.of(context).size;
              final panelW = screenSize.width / 2;
              final panelH = screenSize.height / 2;
              final newOffset = Offset(
                panelW / 2 - canvasPos.dx * c.scale,
                panelH / 2 - canvasPos.dy * c.scale,
              );
              c.updateTransform(offset: newOffset, scale: c.scale);
            },
          ),
        ),

        // 🔧 Floating controls (top-right)
        Positioned(
          top: 8,
          right: 8,
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
                                  : () {},
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
                                  : () {},
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
      ],
    );
  }

  // ============================================================================
  // PANEL CREATION
  // ============================================================================

  List<Widget> _buildPanels() {
    return List.generate(_state.panelCount, (index) {
      final controller = _panelControllers[index];
      if (controller == null) return const SizedBox();

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
    });
  }

  // ============================================================================
  // PANEL CONTEXT MENU (Long-press — touch-first UX)
  // ============================================================================

  void _showPanelContextMenu(int panelIndex, Offset globalPosition) {
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
        PopupMenuItem(
          value: 'fit',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.fit_screen_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(
                'Fit to Content',
                style: TextStyle(fontSize: 13, color: cs.onSurface),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'reset',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.restart_alt_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(
                'Reset Zoom',
                style: TextStyle(fontSize: 13, color: cs.onSurface),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'eraser',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _toolController.isEraserMode
                    ? Icons.edit_rounded
                    : Icons.auto_fix_high_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(
                _toolController.isEraserMode
                    ? 'Switch to Pen'
                    : 'Switch to Eraser',
                style: TextStyle(fontSize: 13, color: cs.onSurface),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'undo',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.undo_rounded, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text('Undo', style: TextStyle(fontSize: 13, color: cs.onSurface)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'fit':
          _fitToContent(panelIndex);
        case 'reset':
          final c = _panelControllers[panelIndex];
          if (c != null) {
            _animateToTransform(c, targetOffset: Offset.zero, targetScale: 1.0);
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

    // Remove excess controllers
    final toRemove = <int>[];
    for (final key in _panelControllers.keys) {
      if (key >= newType.panelCount) toRemove.add(key);
    }
    for (final key in toRemove) {
      _panelControllers[key]?.dispose();
      _panelControllers.remove(key);
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
    for (final controller in _panelControllers.values) {
      _animateToTransform(
        controller,
        targetOffset: Offset.zero,
        targetScale: 1.0,
      );
      if (controller.rotation != 0.0) {
        controller.resetRotation();
      }
    }
  }

  // ============================================================================
  // FIT TO CONTENT
  // ============================================================================

  void _fitToContent(int panelIndex) {
    final controller = _panelControllers[panelIndex];
    if (controller == null) return;

    final bounds = _computeContentBounds();
    if (bounds == null || bounds.isEmpty) return;

    // Get panel size (approximate — use screen width / panel count)
    final screenSize = MediaQuery.of(context).size;
    final panelW = screenSize.width / 2;
    final panelH = screenSize.height / 2;

    // Compute scale to fit content with 10% padding
    final scaleX = panelW / (bounds.width * 1.1);
    final scaleY = panelH / (bounds.height * 1.1);
    final fitScale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.1, 5.0);

    // Center content in viewport
    final centerX = bounds.center.dx;
    final centerY = bounds.center.dy;
    final offset = Offset(
      panelW / 2 - centerX * fitScale,
      panelH / 2 - centerY * fitScale,
    );

    _animateToTransform(
      controller,
      targetOffset: offset,
      targetScale: fitScale,
    );
    HapticFeedback.lightImpact();
  }

  // ============================================================================
  // CINEMATIC VIEWPORT ANIMATION
  // ============================================================================

  void _animateToTransform(
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

    _viewportAnim.stop();
    _viewportAnim.reset();

    void listener() {
      final t = Curves.easeInOutCubic.transform(_viewportAnim.value);
      final lerpedOffset = Offset.lerp(startOffset, targetOffset, t)!;
      final lerpedScale = startScale + (targetScale - startScale) * t;
      controller.updateTransform(offset: lerpedOffset, scale: lerpedScale);
    }

    _viewportAnim.addListener(listener);
    _viewportAnim.forward().then((_) {
      _viewportAnim.removeListener(listener);
    });
  }

  Rect? _computeContentBounds() {
    Rect? bounds;
    for (final layer in _layerController.layers) {
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

class _FloatingChip extends StatelessWidget {
  final Widget child;
  const _FloatingChip({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6),
        ],
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
  final VoidCallback onPressed;
  final bool enabled;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
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

    final listenables = <Listenable>[
      widget.layerController,
      ...widget.panelControllers.values,
    ];

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
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
                painter: _MinimapPainter(
                  layerController: widget.layerController,
                  panelControllers: widget.panelControllers,
                  activePanelIndex: widget.activePanelIndex,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Keep mapping in sync with what _MinimapPainter computes.
  void _updateMapping() {
    Rect? contentBounds;
    for (final layer in widget.layerController.layers) {
      for (final stroke in layer.strokes) {
        if (stroke.points.isEmpty) continue;
        contentBounds =
            contentBounds?.expandToInclude(stroke.bounds) ?? stroke.bounds;
      }
      for (final shape in layer.shapes) {
        final sr = Rect.fromPoints(shape.startPoint, shape.endPoint);
        contentBounds = contentBounds?.expandToInclude(sr) ?? sr;
      }
    }
    contentBounds ??= const Rect.fromLTWH(-500, -500, 1000, 1000);

    for (final entry in widget.panelControllers.entries) {
      final c = entry.value;
      if (c.scale <= 0) continue;
      final vpTopLeft = Offset(-c.offset.dx / c.scale, -c.offset.dy / c.scale);
      final vpRect = Rect.fromLTWH(
        vpTopLeft.dx,
        vpTopLeft.dy,
        _MultiviewMinimap._width * 3 / c.scale,
        _MultiviewMinimap._height * 3 / c.scale,
      );
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

class _MinimapPainter extends CustomPainter {
  final LayerController layerController;
  final Map<int, InfiniteCanvasController> panelControllers;
  final int activePanelIndex;

  _MinimapPainter({
    required this.layerController,
    required this.panelControllers,
    required this.activePanelIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Compute content bounds
    Rect? contentBounds;
    for (final layer in layerController.layers) {
      for (final stroke in layer.strokes) {
        if (stroke.points.isEmpty) continue;
        final sb = stroke.bounds;
        contentBounds = contentBounds?.expandToInclude(sb) ?? sb;
      }
      for (final shape in layer.shapes) {
        final sr = Rect.fromPoints(shape.startPoint, shape.endPoint);
        contentBounds = contentBounds?.expandToInclude(sr) ?? sr;
      }
    }

    if (contentBounds == null || contentBounds.isEmpty) {
      // Empty canvas — just show viewport indicators
      contentBounds = const Rect.fromLTWH(-500, -500, 1000, 1000);
    }

    // 2. Expand bounds to include all viewports
    for (final entry in panelControllers.entries) {
      final c = entry.value;
      final scale = c.scale;
      if (scale <= 0) continue;
      final vpTopLeft = Offset(-c.offset.dx / scale, -c.offset.dy / scale);
      final vpRect = Rect.fromLTWH(
        vpTopLeft.dx,
        vpTopLeft.dy,
        size.width * 3 / scale,
        size.height * 3 / scale,
      );
      contentBounds = contentBounds!.expandToInclude(vpRect);
    }

    // 3. Map from content coords to minimap coords
    final cb = contentBounds!.inflate(contentBounds.shortestSide * 0.1);
    final scaleX = size.width / cb.width;
    final scaleY = size.height / cb.height;
    final mapScale = scaleX < scaleY ? scaleX : scaleY;

    final offsetX = (size.width - cb.width * mapScale) / 2;
    final offsetY = (size.height - cb.height * mapScale) / 2;

    Offset mapPoint(double x, double y) => Offset(
      offsetX + (x - cb.left) * mapScale,
      offsetY + (y - cb.top) * mapScale,
    );

    // 4. Draw content dots (simplified strokes)
    final dotPaint =
        Paint()
          ..color = const Color(0x55000000)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;

    for (final layer in layerController.layers) {
      if (!layer.isVisible) continue;
      for (final stroke in layer.strokes) {
        if (stroke.points.isEmpty) continue;
        // Draw simplified representation (first + last + middle points)
        final pts = stroke.points;
        final indices = [0, pts.length ~/ 2, pts.length - 1];
        for (final i in indices) {
          if (i >= pts.length) continue;
          final p = mapPoint(pts[i].position.dx, pts[i].position.dy);
          canvas.drawCircle(p, 0.8, dotPaint);
        }
      }
    }

    // 5. Draw viewport rectangles for each panel
    for (final entry in panelControllers.entries) {
      final idx = entry.key;
      final c = entry.value;
      final scale = c.scale;
      if (scale <= 0) continue;

      final vpTopLeft = Offset(-c.offset.dx / scale, -c.offset.dy / scale);
      // Use approximate panel size (screen / 2)
      final vpW = 400 / scale;
      final vpH = 300 / scale;

      final topLeft = mapPoint(vpTopLeft.dx, vpTopLeft.dy);
      final bottomRight = mapPoint(vpTopLeft.dx + vpW, vpTopLeft.dy + vpH);

      final color =
          _MultiviewMinimap._panelColors[idx %
              _MultiviewMinimap._panelColors.length];
      final isActive = idx == activePanelIndex;

      final vpPaint =
          Paint()
            ..color = color.withValues(alpha: isActive ? 0.3 : 0.15)
            ..style = PaintingStyle.fill;

      final vpBorderPaint =
          Paint()
            ..color = color.withValues(alpha: isActive ? 0.9 : 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isActive ? 1.5 : 0.8;

      final vpRect = Rect.fromPoints(topLeft, bottomRight);
      canvas.drawRect(vpRect, vpPaint);
      canvas.drawRect(vpRect, vpBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) => true;
}
