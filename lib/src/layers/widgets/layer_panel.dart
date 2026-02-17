import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import '../../l10n/nebula_localizations.dart';
import '../nebula_layer_controller.dart';
import '../../core/models/canvas_layer.dart';

/// Stati del layer panel
enum LayerPanelVisibility {
  closed, // Nascosto completamente
  open, // Aperto con contenuto
  minimized, // Only an arrow visibile
}

/// Pannello laterale per gestire i layer
/// Opens/closes from the left or right edge of the screen
class LayerPanel extends StatefulWidget {
  final NebulaLayerController controller;
  final bool isDark;
  final ValueNotifier<bool> isDrawingNotifier;
  final bool isRightSide; // true if the pannello is sul lato destro

  const LayerPanel({
    super.key,
    required this.controller,
    required this.isDark,
    required this.isDrawingNotifier,
    this.isRightSide = false, // default: lato sinistro
  });

  @override
  State<LayerPanel> createState() => LayerPanelState();
}

class LayerPanelState extends State<LayerPanel>
    with SingleTickerProviderStateMixin {
  LayerPanelVisibility _visibility = LayerPanelVisibility.closed;
  bool _shouldBeTransparent =
      false; // The slide deve rimanere trasparente fino al click dell'utente
  bool _userRequestedOpaque =
      false; // L'utente ha cliccato per rendere il opaque panel
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Called from the layer button in the toolbar
  /// Toggle tra closed <-> open (salta minimized)
  void togglePanel() {
    setState(() {
      if (_visibility == LayerPanelVisibility.closed) {
        _visibility = LayerPanelVisibility.open;
        _animationController.forward();
      } else {
        // If is open o minimized, chiude completamente
        _visibility = LayerPanelVisibility.closed;
        _animationController.reverse();
      }
    });
  }

  /// Called from an arrow in the panel
  /// Toggle tra open <-> minimized
  void _toggleMinimize() {
    setState(() {
      if (_visibility == LayerPanelVisibility.open) {
        _visibility = LayerPanelVisibility.minimized;
        _animationController.reverse(); // Anima il rientro
      } else if (_visibility == LayerPanelVisibility.minimized) {
        _visibility = LayerPanelVisibility.open;
        _animationController.forward(); // Anima l'uscita
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        const panelWidth = 180.0;

        // Calculate altezza dinamica
        final layerCount = widget.controller.layers.length;
        const headerHeight = 40.0;
        const actionHeight = 50.0;
        const layerItemHeight = 70.0;
        const maxVisibleLayers = 3;

        final visibleLayerCount = layerCount.clamp(1, maxVisibleLayers);
        final calculatedHeight =
            headerHeight + actionHeight + (visibleLayerCount * layerItemHeight);
        final panelHeight = calculatedHeight.toDouble();

        return AnimatedBuilder(
          animation: _slideAnimation,
          builder: (context, child) {
            // If closed e animazione terminata, non mostrare nulla
            if (_visibility == LayerPanelVisibility.closed &&
                _slideAnimation.value == 0) {
              return const SizedBox.shrink();
            }

            return SizedBox(
              width: panelWidth + 48,
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.center,
                  children: [
                    // Layer panel (visible both when open and minimized for animation)
                    if (_visibility != LayerPanelVisibility.closed)
                      Align(
                        alignment: Alignment.center,
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
                                // Rendi trasparente only if l'utente sta disegnando
                                // E NON ha richiesto esplicitamente il opaque panel
                                if (isDrawing &&
                                    !_shouldBeTransparent &&
                                    !_userRequestedOpaque) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) {
                                      setState(() {
                                        _shouldBeTransparent = true;
                                      });
                                    }
                                  });
                                }

                                // Quando finisce di disegnare, resetta il flag utente
                                if (!isDrawing && _userRequestedOpaque) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) {
                                      setState(() {
                                        _userRequestedOpaque = false;
                                      });
                                    }
                                  });
                                }

                                return GestureDetector(
                                  onTap: () {
                                    if (_shouldBeTransparent) {
                                      setState(() {
                                        _shouldBeTransparent = false;
                                        _userRequestedOpaque =
                                            true; // The user wants the opaque panel
                                      });
                                    }
                                  },
                                  child: AnimatedOpacity(
                                    opacity: _shouldBeTransparent ? 0.35 : 1.0,
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeInOut,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color:
                                            widget.isDark
                                                ? Colors.grey[900]
                                                : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                              widget.isDark
                                                  ? Colors.white24
                                                  : Colors.grey[300]!,
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.3,
                                            ),
                                            blurRadius: 12,
                                            // Inverti ombra if it is sul lato destro
                                            offset:
                                                widget.isRightSide
                                                    ? const Offset(-2, 0)
                                                    : const Offset(2, 0),
                                          ),
                                        ],
                                      ),
                                      child: _buildPanelContent(),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                    // Toggle button
                    if (_visibility != LayerPanelVisibility.closed &&
                        !_shouldBeTransparent)
                      Align(
                        alignment: Alignment.center,
                        child: Transform.translate(
                          offset: Offset(
                            widget.isRightSide
                                ? -(panelWidth / 2) -
                                    16 +
                                    (panelWidth * (1 - _slideAnimation.value))
                                : (panelWidth / 2) +
                                    16 -
                                    (panelWidth * (1 - _slideAnimation.value)),
                            0,
                          ),
                          child: _buildToggleButton(),
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

  Widget _buildToggleButton() {
    return GestureDetector(
      onTap: _toggleMinimize,
      child: Container(
        width: 32,
        height: 80,
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.grey[800] : Colors.grey[200],
          // Inverti bordi arrotondati if it is sul lato destro
          borderRadius:
              widget.isRightSide
                  ? const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  )
                  : const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
          border: Border.all(
            color: widget.isDark ? Colors.white24 : Colors.grey[300]!,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 4,
              // Inverti ombra if it is sul lato destro
              offset:
                  widget.isRightSide ? const Offset(-2, 0) : const Offset(2, 0),
            ),
          ],
        ),
        child: Icon(
          // Inverti direzione frecce if it is sul lato destro
          _visibility == LayerPanelVisibility.open
              ? (widget.isRightSide
                  ? Icons
                      .chevron_right // Minimizza (chiudi verso destra)
                  : Icons.chevron_left) // Minimizza (chiudi verso sinistra)
              : (widget.isRightSide
                  ? Icons
                      .chevron_left // Espandi (apri verso sinistra)
                  : Icons.chevron_right), // Espandi (apri verso destra)
          color: widget.isDark ? Colors.white70 : Colors.black87,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildPanelContent() {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        return Column(
          children: [
            // Header
            _buildHeader(),

            // Lista layer
            Expanded(child: _buildLayerList()),

            // Azioni
            _buildActions(),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isDark ? Colors.grey[850] : Colors.grey[100],
        border: Border(
          bottom: BorderSide(
            color: widget.isDark ? Colors.white24 : Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.layers,
            color: widget.isDark ? Colors.white70 : Colors.black87,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            NebulaLocalizations.of(context).proCanvas_layers,
            style: TextStyle(
              color: widget.isDark ? Colors.white : Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerList() {
    final layers = widget.controller.layers.reversed.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: layers.length,
      itemBuilder: (context, index) {
        final layer = layers[index];
        final isActive = layer.id == widget.controller.activeLayerId;
        return _buildLayerItem(layer, isActive);
      },
    );
  }

  Widget _buildLayerItem(CanvasLayer layer, bool isActive) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color:
            isActive
                ? (widget.isDark ? Colors.purple[900] : Colors.purple[50])
                : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              isActive
                  ? (widget.isDark ? Colors.purple : Colors.purple[300]!)
                  : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.controller.selectLayer(layer.id);
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Prima riga: nome layer
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    layer.name,
                    style: TextStyle(
                      color: widget.isDark ? Colors.white : Colors.black87,
                      fontSize: 12,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Seconda riga: pulsanti + conteggio
                Row(
                  children: [
                    // Visibility toggle
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: IconButton(
                        icon: Icon(
                          layer.isVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 14,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          widget.controller.toggleLayerVisibility(layer.id);
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: widget.isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),

                    const SizedBox(width: 4),

                    // Lock toggle
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: IconButton(
                        icon: Icon(
                          layer.isLocked ? Icons.lock : Icons.lock_open,
                          size: 14,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          widget.controller.toggleLayerLock(layer.id);
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color:
                            layer.isLocked
                                ? (widget.isDark ? Colors.red[300] : Colors.red)
                                : (widget.isDark
                                    ? Colors.white70
                                    : Colors.black87),
                      ),
                    ),

                    const SizedBox(width: 4),

                    // More options
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          size: 14,
                          color:
                              widget.isDark ? Colors.white70 : Colors.black87,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        itemBuilder: (ctx) {
                          final l10n = NebulaLocalizations.of(ctx);
                          return [
                            PopupMenuItem(
                              value: 'rename',
                              child: Row(
                                children: [
                                  const Icon(Icons.edit, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    l10n.proCanvas_rename,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'blendMode',
                              child: Row(
                                children: [
                                  const Icon(Icons.blender, size: 14),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Blend Mode',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'duplicate',
                              child: Row(
                                children: [
                                  const Icon(Icons.content_copy, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    l10n.proCanvas_duplicate,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'clear',
                              child: Row(
                                children: [
                                  const Icon(Icons.clear_all, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    l10n.proCanvas_clear,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.delete,
                                    size: 14,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    l10n.delete,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ];
                        },
                        onSelected: (value) => _handleLayerAction(value, layer),
                      ),
                    ),

                    const Spacer(),

                    // Blend mode indicator (if not default)
                    if (layer.blendMode != ui.BlendMode.srcOver)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          _blendModeLabel(layer.blendMode),
                          style: TextStyle(
                            color:
                                widget.isDark
                                    ? Colors.purple[200]
                                    : Colors.purple,
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                    // Conteggio elementi
                    Text(
                      '${layer.elementCount}',
                      style: TextStyle(
                        color: widget.isDark ? Colors.white54 : Colors.black54,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Human-readable blend mode label
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
        _showRenameDialog(layer);
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
    }
  }

  void _showRenameDialog(CanvasLayer layer) {
    final controller = TextEditingController(text: layer.name);
    final l10n = NebulaLocalizations.of(context);

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(l10n.proCanvas_renameLayer),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.proCanvas_nameLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    widget.controller.renameLayer(layer.id, controller.text);
                  }
                  Navigator.pop(context);
                },
                child: Text(l10n.ok),
              ),
            ],
          ),
    );
  }

  /// 🎨 Shows blend mode selection dialog
  void _showBlendModeDialog(CanvasLayer layer) {
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
            title: Text('Blend Mode: ${layer.name}'),
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
                          color: isSelected ? Colors.purple : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(
                            fontWeight:
                                isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
          ),
    );
  }

  Widget _buildActions() {
    final l10n = NebulaLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: widget.isDark ? Colors.grey[850] : Colors.grey[100],
        border: Border(
          top: BorderSide(
            color: widget.isDark ? Colors.white24 : Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                widget.controller.addLayer();
              },
              icon: const Icon(Icons.add, size: 14),
              label: Text(
                l10n.proCanvas_new,
                style: const TextStyle(fontSize: 11),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    widget.isDark ? Colors.purple[700] : Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
