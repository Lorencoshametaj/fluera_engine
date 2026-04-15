import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import '../../l10n/fluera_localizations.dart';
import '../fluera_layer_controller.dart';
import '../../core/models/canvas_layer.dart';
import './adjustment_panel_dialog.dart';

/// Stati del layer panel
enum LayerPanelVisibility { closed, open, minimized }

/// 🎨 Material Design 3 — Pannello laterale per gestire i layer.
///
/// Features:
/// - Color tags per layer identification
/// - Collapsible opacity slider
/// - Drag-to-reorder layers
/// - Swipe to delete/duplicate
/// - Long press → inline rename
/// - Effects summary line
/// - Double-tap opacity → cycle presets
/// - M3 ColorScheme tokens throughout
class LayerPanel extends StatefulWidget {
  final FlueraLayerController controller;
  final bool isDark;
  final ValueNotifier<bool> isDrawingNotifier;
  final bool isRightSide;

  const LayerPanel({
    super.key,
    required this.controller,
    required this.isDark,
    required this.isDrawingNotifier,
    this.isRightSide = false,
  });

  @override
  State<LayerPanel> createState() => LayerPanelState();
}

/// Available color tags for layers
const _kColorTags = <Color>[
  Colors.transparent, // No tag
  Color(0xFFEF5350), // Red
  Color(0xFFFF7043), // Orange
  Color(0xFFFFCA28), // Yellow
  Color(0xFF66BB6A), // Green
  Color(0xFF42A5F5), // Blue
  Color(0xFFAB47BC), // Purple
  Color(0xFFEC407A), // Pink
];

class LayerPanelState extends State<LayerPanel> with TickerProviderStateMixin {
  LayerPanelVisibility _visibility = LayerPanelVisibility.closed;
  bool _shouldBeTransparent = false;
  bool _userRequestedOpaque = false;
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  // Pulsating border for active layer
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Inline rename
  String? _renamingLayerId;
  late TextEditingController _renameController;

  // Color tags (layerId → color)
  final Map<String, Color> _colorTags = {};

  // Which layer has expanded opacity slider
  String? _expandedOpacityLayerId;

  // Global expand/collapse for all opacity sliders
  bool _allOpacityExpanded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _renameController = TextEditingController();

    // Pulsating active layer border
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.25, end: 0.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    _renameController.dispose();
    super.dispose();
  }

  void togglePanel() {
    setState(() {
      if (_visibility == LayerPanelVisibility.closed) {
        _visibility = LayerPanelVisibility.open;
        _animationController.forward();
      } else {
        _visibility = LayerPanelVisibility.closed;
        _animationController.reverse();
      }
    });
  }

  void _toggleMinimize() {
    setState(() {
      if (_visibility == LayerPanelVisibility.open) {
        _visibility = LayerPanelVisibility.minimized;
        _animationController.reverse();
      } else if (_visibility == LayerPanelVisibility.minimized) {
        _visibility = LayerPanelVisibility.open;
        _animationController.forward();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        const panelWidth = 200.0;

        final layerCount = widget.controller.layers.length;
        const headerHeight = 44.0;
        const actionHeight = 52.0;
        const layerItemBaseHeight = 58.0;
        const opacityExtra = 20.0;
        const maxVisibleLayers = 4;

        final visibleLayerCount = layerCount.clamp(1, maxVisibleLayers);
        // Add extra height if any opacity slider is expanded
        final avgItemHeight =
            _allOpacityExpanded
                ? layerItemBaseHeight + opacityExtra
                : layerItemBaseHeight + 4; // a tiny buffer
        final calculatedHeight =
            headerHeight + actionHeight + (visibleLayerCount * avgItemHeight);
        final panelHeight = calculatedHeight.toDouble();

        return AnimatedBuilder(
          animation: _slideAnimation,
          builder: (context, child) {
            if (_visibility == LayerPanelVisibility.closed &&
                _slideAnimation.value == 0) {
              return const SizedBox.shrink();
            }

            return SizedBox(
              width: panelWidth + 48,
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  alignment:
                      widget.isRightSide
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                  children: [
                    if (_visibility != LayerPanelVisibility.closed)
                      Align(
                        alignment:
                            widget.isRightSide
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                        child: Transform.translate(
                          offset: Offset(
                            widget.isRightSide
                                ? (_visibility == LayerPanelVisibility.minimized
                                    ? panelWidth * 2
                                    : panelWidth -
                                        (_slideAnimation.value * panelWidth))
                                : (_visibility == LayerPanelVisibility.minimized
                                    ? -panelWidth * 2
                                    : -panelWidth +
                                        (_slideAnimation.value * panelWidth)),
                            0,
                          ),
                          child: SizedBox(
                            width: panelWidth,
                            height: panelHeight,
                            child: ValueListenableBuilder<bool>(
                              valueListenable: widget.isDrawingNotifier,
                              builder: (context, isDrawing, child) {
                                if (isDrawing &&
                                    !_shouldBeTransparent &&
                                    !_userRequestedOpaque) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) {
                                      setState(
                                        () => _shouldBeTransparent = true,
                                      );
                                    }
                                  });
                                }
                                if (!isDrawing && _userRequestedOpaque) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) {
                                      setState(
                                        () => _userRequestedOpaque = false,
                                      );
                                    }
                                  });
                                }

                                return GestureDetector(
                                  onTap: () {
                                    if (_shouldBeTransparent) {
                                      setState(() {
                                        _shouldBeTransparent = false;
                                        _userRequestedOpaque = true;
                                      });
                                    }
                                  },
                                  child: AnimatedOpacity(
                                    opacity: _shouldBeTransparent ? 0.35 : 1.0,
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeInOut,
                                    child: Material(
                                      elevation: 1,
                                      surfaceTintColor: cs.surfaceTint,
                                      color: cs.surfaceContainerLow,
                                      borderRadius:
                                          widget.isRightSide
                                              ? const BorderRadius.only(
                                                topLeft: Radius.circular(16),
                                                bottomLeft: Radius.circular(16),
                                              )
                                              : const BorderRadius.only(
                                                topRight: Radius.circular(16),
                                                bottomRight: Radius.circular(
                                                  16,
                                                ),
                                              ),
                                      clipBehavior: Clip.antiAlias,
                                      child: _buildPanelContent(cs),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                    // Toggle button (chevron)
                    if (_visibility != LayerPanelVisibility.closed &&
                        !_shouldBeTransparent)
                      Align(
                        alignment:
                            widget.isRightSide
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                        child: Transform.translate(
                          offset: Offset(
                            widget.isRightSide
                                ? (panelWidth + 48) -
                                    (panelWidth * _slideAnimation.value) -
                                    24
                                : panelWidth * _slideAnimation.value,
                            0,
                          ),
                          child: _buildToggleButton(cs),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildToggleButton(ColorScheme cs) {
    final isOpen = _visibility == LayerPanelVisibility.open;
    return Material(
      elevation: 1,
      surfaceTintColor: cs.surfaceTint,
      color: cs.surfaceContainerLow,
      borderRadius:
          widget.isRightSide
              ? const BorderRadius.only(
                topLeft: Radius.circular(10),
                bottomLeft: Radius.circular(10),
              )
              : const BorderRadius.only(
                topRight: Radius.circular(10),
                bottomRight: Radius.circular(10),
              ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _toggleMinimize,
        child: Container(
          width: 24,
          height: 64,
          decoration: BoxDecoration(
            border: Border(
              left:
                  widget.isRightSide
                      ? BorderSide.none
                      : BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.2),
                        width: 0.5,
                      ),
              right:
                  widget.isRightSide
                      ? BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.2),
                        width: 0.5,
                      )
                      : BorderSide.none,
            ),
          ),
          child: Icon(
            isOpen
                ? (widget.isRightSide
                    ? Icons.chevron_right
                    : Icons.chevron_left)
                : (widget.isRightSide
                    ? Icons.chevron_left
                    : Icons.chevron_right),
            color: cs.onSurfaceVariant,
            size: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildPanelContent(ColorScheme cs) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        return Column(
          children: [
            _buildHeader(cs),
            Expanded(child: _buildLayerList(cs)),
            _buildActions(cs),
          ],
        );
      },
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.layers_outlined, color: cs.primary, size: 14),
          const SizedBox(width: 4),
          Text(
            FlueraLocalizations.of(context)!.proCanvas_layers,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const Spacer(),

          // Expand/collapse all opacity sliders
          SizedBox(
            width: 20,
            height: 20,
            child: IconButton(
              icon: Icon(
                _allOpacityExpanded ? Icons.unfold_less : Icons.unfold_more,
                size: 12,
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _allOpacityExpanded = !_allOpacityExpanded;
                  if (!_allOpacityExpanded) {
                    _expandedOpacityLayerId = null;
                  }
                });
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              color: cs.onSurfaceVariant,
              tooltip: _allOpacityExpanded ? 'Collapse all' : 'Expand all',
            ),
          ),

          const SizedBox(width: 4),

          Text(
            '${widget.controller.layers.length}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerList(ColorScheme cs) {
    final layers = widget.controller.layers.reversed.toList();

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      itemCount: layers.length,
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            // Bounce scale with slight overshoot
            final t = Curves.elasticOut.transform(animation.value);
            final scale = 1.0 + 0.03 * t;
            // Subtle tilt based on drag
            final rotation = 0.01 * (1 - animation.value);
            return Transform(
              alignment: Alignment.center,
              transform:
                  Matrix4.identity()
                    ..scaleByDouble(scale, scale, scale, 1.0)
                    ..rotateZ(rotation),
              child: Material(
                elevation: 6 * animation.value,
                shadowColor: cs.primary.withValues(alpha: 0.3),
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                child: child,
              ),
            );
          },
          child: child,
        );
      },
      onReorder: (oldIndex, newIndex) {
        HapticFeedback.mediumImpact();
        final dataLayers = widget.controller.layers;
        final dataOldIndex = dataLayers.length - 1 - oldIndex;
        final dataNewIndex =
            dataLayers.length -
            1 -
            (newIndex > oldIndex ? newIndex - 1 : newIndex);

        final layerId = dataLayers[dataOldIndex].id;
        if (dataNewIndex > dataOldIndex) {
          for (int i = 0; i < dataNewIndex - dataOldIndex; i++) {
            widget.controller.moveLayerUp(layerId);
          }
        } else {
          for (int i = 0; i < dataOldIndex - dataNewIndex; i++) {
            widget.controller.moveLayerDown(layerId);
          }
        }
      },
      itemBuilder: (context, index) {
        final layer = layers[index];
        final isActive = layer.id == widget.controller.activeLayerId;
        return _buildLayerItem(layer, isActive, cs, index);
      },
    );
  }

  Widget _buildLayerItem(
    CanvasLayer layer,
    bool isActive,
    ColorScheme cs,
    int index,
  ) {
    final isRenaming = _renamingLayerId == layer.id;
    final colorTag = _colorTags[layer.id] ?? Colors.transparent;
    final hasColorTag = colorTag != Colors.transparent;
    final showOpacity =
        _allOpacityExpanded ||
        _expandedOpacityLayerId == layer.id ||
        layer.opacity < 1.0;

    // Build effects summary
    final summary = _buildEffectsSummary(layer);

    Widget item = AnimatedContainer(
      key: ValueKey('layer-${layer.id}'),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color:
            isActive
                ? cs.primaryContainer.withValues(alpha: 0.6)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.controller.selectLayer(layer.id);
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _startInlineRename(layer);
          },
          borderRadius: BorderRadius.circular(12),
          splashColor: cs.primary.withValues(alpha: 0.08),
          highlightColor: cs.primary.withValues(alpha: 0.04),
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.fromLTRB(4, 5, 4, 4),
                decoration:
                    isActive
                        ? BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.primary.withValues(
                              alpha: _pulseAnimation.value,
                            ),
                            width: 1.5,
                          ),
                        )
                        : null,
                child: child,
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Row 1: color tag + drag handle + name
                Row(
                  children: [
                    // 🏷️ Color tag dot
                    GestureDetector(
                      onTap: () => _showColorTagPicker(layer.id, cs),
                      child: Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              hasColorTag
                                  ? colorTag
                                  : cs.onSurfaceVariant.withValues(alpha: 0.15),
                          border:
                              hasColorTag
                                  ? null
                                  : Border.all(
                                    color: cs.outlineVariant.withValues(
                                      alpha: 0.3,
                                    ),
                                    width: 0.5,
                                  ),
                        ),
                      ),
                    ),

                    // Drag handle
                    ReorderableDragStartListener(
                      index: index,
                      child: Icon(
                        Icons.drag_indicator,
                        size: 12,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    const SizedBox(width: 2),

                    // Name or inline rename
                    Expanded(
                      child:
                          isRenaming
                              ? SizedBox(
                                height: 20,
                                child: TextField(
                                  controller: _renameController,
                                  autofocus: true,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurface,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 3,
                                    ),
                                    filled: true,
                                    fillColor: cs.surfaceContainerHighest,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(4),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(4),
                                      borderSide: BorderSide(
                                        color: cs.primary,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  onSubmitted:
                                      (v) => _finishInlineRename(layer.id, v),
                                  onTapOutside:
                                      (_) => _finishInlineRename(
                                        layer.id,
                                        _renameController.text,
                                      ),
                                ),
                              )
                              : Text(
                                layer.name,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color:
                                      isActive
                                          ? cs.onPrimaryContainer
                                          : cs.onSurface,
                                  fontWeight:
                                      isActive
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                    ),
                  ],
                ),

                // Effects summary (if any effects active)
                if (summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 23, top: 1),
                    child: Text(
                      summary,
                      style: TextStyle(
                        fontSize: 7,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                const SizedBox(height: 2),

                // Row 2: actions + indicators
                Row(
                  children: [
                    _buildIconAction(
                      cs: cs,
                      icon:
                          layer.isVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                      color:
                          layer.isVisible
                              ? cs.onSurfaceVariant
                              : cs.onSurfaceVariant.withValues(alpha: 0.3),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.controller.toggleLayerVisibility(layer.id);
                      },
                    ),
                    _buildIconAction(
                      cs: cs,
                      icon:
                          layer.isLocked
                              ? Icons.lock_outlined
                              : Icons.lock_open_outlined,
                      color: layer.isLocked ? cs.error : cs.onSurfaceVariant,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.controller.toggleLayerLock(layer.id);
                      },
                    ),

                    // Opacity toggle button
                    _buildIconAction(
                      cs: cs,
                      icon: Icons.opacity,
                      color:
                          layer.opacity < 1.0
                              ? cs.primary
                              : cs.onSurfaceVariant.withValues(alpha: 0.4),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (_expandedOpacityLayerId == layer.id) {
                            _expandedOpacityLayerId = null;
                          } else {
                            _expandedOpacityLayerId = layer.id;
                          }
                        });
                      },
                      // Double-tap → cycle opacity presets
                      onDoubleTap: () {
                        HapticFeedback.mediumImpact();
                        _cycleOpacityPreset(layer);
                      },
                    ),

                    // More options
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_horiz,
                          size: 12,
                          color: cs.onSurfaceVariant,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        color: cs.surfaceContainerHighest,
                        elevation: 3,
                        itemBuilder: (ctx) {
                          final l10n = FlueraLocalizations.of(ctx)!;
                          return [
                            _buildMenuItem(
                              'rename',
                              Icons.edit_outlined,
                              l10n.proCanvas_rename,
                              cs,
                            ),
                            _buildMenuItem(
                              'blendMode',
                              Icons.blender_outlined,
                              'Blend Mode',
                              cs,
                            ),
                            _buildMenuItem(
                              'adjustments',
                              Icons.tune,
                              'Adjustments',
                              cs,
                              isHighlighted:
                                  layer.node.adjustmentNodes.isNotEmpty,
                            ),
                            _buildMenuItem(
                              'colorTag',
                              Icons.circle,
                              'Color Tag',
                              cs,
                            ),
                            _buildMenuItem(
                              'duplicate',
                              Icons.content_copy_outlined,
                              l10n.proCanvas_duplicate,
                              cs,
                            ),
                            _buildMenuItem(
                              'clear',
                              Icons.clear_all_outlined,
                              l10n.proCanvas_clear,
                              cs,
                            ),
                            _buildMenuItem(
                              'delete',
                              Icons.delete_outline,
                              l10n.delete,
                              cs,
                              isDestructive: true,
                            ),
                          ];
                        },
                        onSelected: (value) => _handleLayerAction(value, layer),
                      ),
                    ),

                    const Spacer(),

                    // Blend mode badge
                    if (layer.blendMode != ui.BlendMode.srcOver)
                      Container(
                        margin: const EdgeInsets.only(right: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _blendModeLabel(layer.blendMode),
                          style: TextStyle(
                            color: cs.onTertiaryContainer,
                            fontSize: 7,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                    // Adjustment indicator
                    if (layer.node.adjustmentNodes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Icon(Icons.tune, size: 9, color: cs.primary),
                      ),

                    // Element count (smooth transition)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.3),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        '${layer.elementCount}',
                        key: ValueKey('ec-${layer.elementCount}'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ),

                // 🎚️ Collapsible opacity slider
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child:
                      showOpacity
                          ? SizedBox(
                            height: 18,
                            child: Row(
                              children: [
                                const SizedBox(width: 2),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 1.5,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 4,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 8,
                                          ),
                                      activeTrackColor: cs.primary,
                                      inactiveTrackColor: cs.onSurfaceVariant
                                          .withValues(alpha: 0.12),
                                      thumbColor: cs.primary,
                                      overlayColor: cs.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                    ),
                                    child: Slider(
                                      value: layer.opacity,
                                      min: 0.0,
                                      max: 1.0,
                                      onChanged: (v) {
                                        widget.controller.setLayerOpacity(
                                          layer.id,
                                          v,
                                        );
                                      },
                                      onChangeEnd:
                                          (_) =>
                                              HapticFeedback.selectionClick(),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 22,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    transitionBuilder: (child, animation) {
                                      return FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      );
                                    },
                                    child: Text(
                                      '${(layer.opacity * 100).round()}',
                                      key: ValueKey(
                                        'op-${(layer.opacity * 100).round()}',
                                      ),
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: cs.onSurfaceVariant,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                          : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Swipe to delete (left) / duplicate (right)
    return Dismissible(
      key: ValueKey('dismiss-${layer.id}'),
      direction:
          widget.controller.layers.length > 1
              ? DismissDirection.horizontal
              : DismissDirection.startToEnd,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          HapticFeedback.mediumImpact();
          widget.controller.removeLayer(layer.id);
          return false;
        } else {
          HapticFeedback.lightImpact();
          widget.controller.duplicateLayer(layer.id);
          return false;
        }
      },
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.content_copy, size: 12, color: cs.onPrimaryContainer),
            const SizedBox(width: 4),
            Text(
              'Duplicate',
              style: TextStyle(fontSize: 9, color: cs.onPrimaryContainer),
            ),
          ],
        ),
      ),
      secondaryBackground:
          widget.controller.layers.length > 1
              ? Container(
                margin: const EdgeInsets.symmetric(vertical: 1),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Delete',
                      style: TextStyle(fontSize: 9, color: cs.onErrorContainer),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.delete_outline,
                      size: 12,
                      color: cs.onErrorContainer,
                    ),
                  ],
                ),
              )
              : null,
      child: item,
    );
  }

  // ── Effects summary builder ──

  String _buildEffectsSummary(CanvasLayer layer) {
    final parts = <String>[];

    final strokes = layer.strokes.length;
    final shapes = layer.shapes.length;
    final texts = layer.texts.length;
    final adjustments = layer.node.adjustmentNodes.length;

    if (strokes > 0) parts.add('$strokes stroke${strokes > 1 ? 's' : ''}');
    if (shapes > 0) parts.add('$shapes shape${shapes > 1 ? 's' : ''}');
    if (texts > 0) parts.add('$texts text${texts > 1 ? 's' : ''}');
    if (adjustments > 0) parts.add('$adjustments fx');

    if (layer.blendMode != ui.BlendMode.srcOver) {
      parts.add(_blendModeLabel(layer.blendMode));
    }
    if (layer.opacity < 1.0) {
      parts.add('${(layer.opacity * 100).round()}%');
    }

    return parts.join(' · ');
  }

  // ── Color tag picker ──

  void _showColorTagPicker(String layerId, ColorScheme cs) {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: cs.surfaceContainerHigh,
            surfaceTintColor: cs.surfaceTint,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            contentPadding: const EdgeInsets.all(16),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _kColorTags.map((color) {
                    final isSelected =
                        (_colorTags[layerId] ?? Colors.transparent) == color;
                    final isNone = color == Colors.transparent;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isNone) {
                            _colorTags.remove(layerId);
                          } else {
                            _colorTags[layerId] = color;
                          }
                        });
                        Navigator.pop(ctx);
                        HapticFeedback.selectionClick();
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isNone ? cs.surfaceContainer : color,
                          border: Border.all(
                            color:
                                isSelected
                                    ? cs.primary
                                    : cs.outlineVariant.withValues(alpha: 0.3),
                            width: isSelected ? 2.5 : 1,
                          ),
                        ),
                        child:
                            isNone
                                ? Icon(
                                  Icons.block,
                                  size: 14,
                                  color: cs.onSurfaceVariant,
                                )
                                : isSelected
                                ? const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: Colors.white,
                                )
                                : null,
                      ),
                    );
                  }).toList(),
            ),
          ),
    );
  }

  // ── Opacity presets ──

  void _cycleOpacityPreset(CanvasLayer layer) {
    const presets = [0.25, 0.50, 0.75, 1.0];
    final current = layer.opacity;

    // Find next preset above current value
    double next = presets[0];
    for (final p in presets) {
      if (p > current + 0.01) {
        next = p;
        break;
      }
    }
    // If already at or above 1.0, wrap to 25%
    if (current >= 0.99) next = 0.25;

    widget.controller.setLayerOpacity(layer.id, next);
  }

  // ── Inline rename ──

  void _startInlineRename(CanvasLayer layer) {
    setState(() {
      _renamingLayerId = layer.id;
      _renameController.text = layer.name;
      _renameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: layer.name.length,
      );
    });
  }

  void _finishInlineRename(String layerId, String newName) {
    if (newName.trim().isNotEmpty) {
      widget.controller.renameLayer(layerId, newName.trim());
    }
    setState(() => _renamingLayerId = null);
  }

  Widget _buildIconAction({
    required ColorScheme cs,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    VoidCallback? onDoubleTap,
  }) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: SizedBox(
        width: 20,
        height: 20,
        child: IconButton(
          icon: Icon(icon, size: 11),
          onPressed: onTap,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          color: color,
          splashRadius: 10,
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildMenuItem(
    String value,
    IconData icon,
    String label,
    ColorScheme cs, {
    bool isDestructive = false,
    bool isHighlighted = false,
  }) {
    final color =
        isDestructive
            ? cs.error
            : isHighlighted
            ? cs.primary
            : cs.onSurface;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: isHighlighted ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  static String _blendModeLabel(ui.BlendMode mode) {
    const labels = {
      ui.BlendMode.srcOver: 'Normal',
      ui.BlendMode.multiply: 'Multiply',
      ui.BlendMode.screen: 'Screen',
      ui.BlendMode.overlay: 'Overlay',
      ui.BlendMode.darken: 'Darken',
      ui.BlendMode.lighten: 'Lighten',
      ui.BlendMode.colorDodge: 'Dodge',
      ui.BlendMode.colorBurn: 'Burn',
      ui.BlendMode.softLight: 'Soft Light',
      ui.BlendMode.hardLight: 'Hard Light',
      ui.BlendMode.difference: 'Diff',
    };
    return labels[mode] ?? mode.name;
  }

  void _handleLayerAction(String action, CanvasLayer layer) {
    HapticFeedback.selectionClick();

    switch (action) {
      case 'rename':
        _startInlineRename(layer);
        break;
      case 'duplicate':
        widget.controller.duplicateLayer(layer.id);
        break;
      case 'clear':
        widget.controller.clearActiveLayer();
        break;
      case 'delete':
        widget.controller.removeLayer(layer.id);
        break;
      case 'blendMode':
        _showBlendModeDialog(layer);
        break;
      case 'adjustments':
        AdjustmentPanelDialog.show(
          context,
          controller: widget.controller,
          layer: layer,
          isDark: widget.isDark,
        );
        break;
      case 'colorTag':
        _showColorTagPicker(layer.id, Theme.of(context).colorScheme);
        break;
    }
  }

  void _showBlendModeDialog(CanvasLayer layer) {
    final cs = Theme.of(context).colorScheme;

    const modes = [
      (ui.BlendMode.srcOver, 'Normal'),
      (ui.BlendMode.multiply, 'Multiply'),
      (ui.BlendMode.screen, 'Screen'),
      (ui.BlendMode.overlay, 'Overlay'),
      (ui.BlendMode.darken, 'Darken'),
      (ui.BlendMode.lighten, 'Lighten'),
      (ui.BlendMode.colorDodge, 'Color Dodge'),
      (ui.BlendMode.colorBurn, 'Color Burn'),
      (ui.BlendMode.softLight, 'Soft Light'),
      (ui.BlendMode.hardLight, 'Hard Light'),
      (ui.BlendMode.difference, 'Difference'),
    ];

    showDialog(
      context: context,
      builder:
          (context) => SimpleDialog(
            backgroundColor: cs.surfaceContainerHigh,
            surfaceTintColor: cs.surfaceTint,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Blend Mode: ${layer.name}',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: cs.onSurface),
            ),
            children:
                modes.map((entry) {
                  final (mode, label) = entry;
                  final isSelected = layer.blendMode == mode;
                  return SimpleDialogOption(
                    onPressed: () {
                      widget.controller.setLayerBlendMode(layer.id, mode);
                      Navigator.pop(context);
                    },
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                          color: isSelected ? cs.primary : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: TextStyle(
                            fontWeight:
                                isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                            color:
                                isSelected ? cs.onSurface : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
          ),
    );
  }

  Widget _buildActions(ColorScheme cs) {
    final l10n = FlueraLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                widget.controller.addLayer();
              },
              icon: const Icon(Icons.add, size: 14),
              label: Text(
                l10n.proCanvas_new,
                style: const TextStyle(fontSize: 11),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
