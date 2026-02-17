import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/nebula_localizations.dart';
import './compact_action_button.dart';

/// Action menu for lasso selection (animated entry)
class SelectionActionsMenu extends StatefulWidget {
  final int selectionCount;
  final VoidCallback onDelete;
  final VoidCallback onClearSelection;
  final VoidCallback onRotate;
  final VoidCallback onFlipHorizontal;
  final VoidCallback onFlipVertical;
  final VoidCallback onConvertToText;
  final VoidCallback? onCopy;
  final VoidCallback? onDuplicate;
  final VoidCallback? onSelectAll;
  final VoidCallback? onBringToFront;
  final VoidCallback? onSendToBack;
  final VoidCallback? onGroup;
  final VoidCallback? onUngroup;
  final VoidCallback? onPaste;
  final VoidCallback? onToggleSnap;
  final VoidCallback? onUndo;
  final bool snapEnabled;
  final bool hasClipboard;

  // Round 3 — Enterprise
  final VoidCallback? onLock;
  final VoidCallback? onUnlock;
  final bool isSelectionLocked;
  final VoidCallback? onAlignLeft;
  final VoidCallback? onAlignCenterH;
  final VoidCallback? onAlignRight;
  final VoidCallback? onAlignTop;
  final VoidCallback? onAlignCenterV;
  final VoidCallback? onAlignBottom;
  final VoidCallback? onDistributeH;
  final VoidCallback? onDistributeV;
  final VoidCallback? onToggleMultiLayer;
  final bool multiLayerMode;
  final String? statsSummary;

  const SelectionActionsMenu({
    super.key,
    required this.selectionCount,
    required this.onDelete,
    required this.onClearSelection,
    required this.onRotate,
    required this.onFlipHorizontal,
    required this.onFlipVertical,
    required this.onConvertToText,
    this.onCopy,
    this.onDuplicate,
    this.onSelectAll,
    this.onBringToFront,
    this.onSendToBack,
    this.onGroup,
    this.onUngroup,
    this.onPaste,
    this.onToggleSnap,
    this.onUndo,
    this.snapEnabled = false,
    this.hasClipboard = false,
    this.onLock,
    this.onUnlock,
    this.isSelectionLocked = false,
    this.onAlignLeft,
    this.onAlignCenterH,
    this.onAlignRight,
    this.onAlignTop,
    this.onAlignCenterV,
    this.onAlignBottom,
    this.onDistributeH,
    this.onDistributeV,
    this.onToggleMultiLayer,
    this.multiLayerMode = false,
    this.statsSummary,
  });

  @override
  State<SelectionActionsMenu> createState() => _SelectionActionsMenuState();
}

class _SelectionActionsMenuState extends State<SelectionActionsMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Compact selection info
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Tooltip(
                    message: widget.statsSummary ?? 'Selected',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: Colors.blue,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.selectionCount}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Action buttons
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Copy button
                          if (widget.onCopy != null)
                            CompactActionButton(
                              icon: Icons.copy_rounded,
                              color: Colors.indigo,
                              tooltip: 'Copy',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onCopy!();
                              },
                            ),

                          // Duplicate button
                          if (widget.onDuplicate != null)
                            CompactActionButton(
                              icon: Icons.library_add_rounded,
                              color: Colors.cyan,
                              tooltip: 'Duplicate',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onDuplicate!();
                              },
                            ),

                          // Paste button (visible when clipboard has content)
                          if (widget.onPaste != null && widget.hasClipboard)
                            CompactActionButton(
                              icon: Icons.paste_rounded,
                              color: Colors.green,
                              tooltip: 'Paste',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onPaste!();
                              },
                            ),

                          // Select All button
                          if (widget.onSelectAll != null)
                            CompactActionButton(
                              icon: Icons.select_all_rounded,
                              color: Colors.blueGrey,
                              tooltip: 'Select All',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onSelectAll!();
                              },
                            ),

                          // Bring to Front button
                          if (widget.onBringToFront != null)
                            CompactActionButton(
                              icon: Icons.flip_to_front_rounded,
                              color: Colors.amber.shade700,
                              tooltip: 'Bring to Front',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onBringToFront!();
                              },
                            ),

                          // Send to Back button
                          if (widget.onSendToBack != null)
                            CompactActionButton(
                              icon: Icons.flip_to_back_rounded,
                              color: Colors.brown,
                              tooltip: 'Send to Back',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onSendToBack!();
                              },
                            ),

                          // Group button
                          if (widget.onGroup != null)
                            CompactActionButton(
                              icon: Icons.group_work_rounded,
                              color: Colors.purple,
                              tooltip: 'Group',
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                widget.onGroup!();
                              },
                            ),

                          // Ungroup button
                          if (widget.onUngroup != null)
                            CompactActionButton(
                              icon: Icons.workspaces_outline,
                              color: Colors.pink,
                              tooltip: 'Ungroup',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onUngroup!();
                              },
                            ),

                          // Snap-to-grid toggle
                          if (widget.onToggleSnap != null)
                            CompactActionButton(
                              icon: Icons.grid_4x4_rounded,
                              color:
                                  widget.snapEnabled
                                      ? Colors.lime.shade700
                                      : Colors.grey,
                              tooltip:
                                  widget.snapEnabled ? 'Snap: ON' : 'Snap: OFF',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onToggleSnap!();
                              },
                            ),

                          // Undo button
                          if (widget.onUndo != null)
                            CompactActionButton(
                              icon: Icons.undo_rounded,
                              color: Colors.grey.shade600,
                              tooltip: 'Undo',
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                widget.onUndo!();
                              },
                            ),

                          // ── Round 3: Enterprise buttons ──

                          // Lock / Unlock toggle
                          if (widget.onLock != null)
                            CompactActionButton(
                              icon:
                                  widget.isSelectionLocked
                                      ? Icons.lock_rounded
                                      : Icons.lock_open_rounded,
                              color:
                                  widget.isSelectionLocked
                                      ? Colors.red.shade400
                                      : Colors.grey.shade500,
                              tooltip:
                                  widget.isSelectionLocked ? 'Unlock' : 'Lock',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                if (widget.isSelectionLocked) {
                                  widget.onUnlock?.call();
                                } else {
                                  widget.onLock!();
                                }
                              },
                            ),

                          // Align Left
                          if (widget.onAlignLeft != null)
                            CompactActionButton(
                              icon: Icons.align_horizontal_left_rounded,
                              color: Colors.deepOrange,
                              tooltip: 'Align Left',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onAlignLeft!();
                              },
                            ),

                          // Align Center Horizontal
                          if (widget.onAlignCenterH != null)
                            CompactActionButton(
                              icon: Icons.align_horizontal_center_rounded,
                              color: Colors.deepOrange,
                              tooltip: 'Align Center',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onAlignCenterH!();
                              },
                            ),

                          // Align Right
                          if (widget.onAlignRight != null)
                            CompactActionButton(
                              icon: Icons.align_horizontal_right_rounded,
                              color: Colors.deepOrange,
                              tooltip: 'Align Right',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onAlignRight!();
                              },
                            ),

                          // Align Top
                          if (widget.onAlignTop != null)
                            CompactActionButton(
                              icon: Icons.align_vertical_top_rounded,
                              color: Colors.deepOrange.shade300,
                              tooltip: 'Align Top',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onAlignTop!();
                              },
                            ),

                          // Align Center Vertical
                          if (widget.onAlignCenterV != null)
                            CompactActionButton(
                              icon: Icons.align_vertical_center_rounded,
                              color: Colors.deepOrange.shade300,
                              tooltip: 'Align Middle',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onAlignCenterV!();
                              },
                            ),

                          // Align Bottom
                          if (widget.onAlignBottom != null)
                            CompactActionButton(
                              icon: Icons.align_vertical_bottom_rounded,
                              color: Colors.deepOrange.shade300,
                              tooltip: 'Align Bottom',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onAlignBottom!();
                              },
                            ),

                          // Distribute Horizontal
                          if (widget.onDistributeH != null)
                            CompactActionButton(
                              icon: Icons.horizontal_distribute_rounded,
                              color: Colors.indigo.shade300,
                              tooltip: 'Distribute Horizontally',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onDistributeH!();
                              },
                            ),

                          // Distribute Vertical
                          if (widget.onDistributeV != null)
                            CompactActionButton(
                              icon: Icons.vertical_distribute_rounded,
                              color: Colors.indigo.shade300,
                              tooltip: 'Distribute Vertically',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onDistributeV!();
                              },
                            ),

                          // Multi-Layer toggle
                          if (widget.onToggleMultiLayer != null)
                            CompactActionButton(
                              icon: Icons.layers_rounded,
                              color:
                                  widget.multiLayerMode
                                      ? Colors.teal.shade600
                                      : Colors.grey,
                              tooltip:
                                  widget.multiLayerMode
                                      ? 'Multi-Layer: ON'
                                      : 'Multi-Layer: OFF',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onToggleMultiLayer!();
                              },
                            ),

                          // Rotate button
                          CompactActionButton(
                            icon: Icons.rotate_90_degrees_ccw_rounded,
                            color: Colors.blue,
                            tooltip: 'Rotate',
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onRotate();
                            },
                          ),

                          // Flip horizontal button
                          CompactActionButton(
                            icon: Icons.flip,
                            color: Colors.orange,
                            tooltip:
                                NebulaLocalizations.of(
                                  context,
                                ).proCanvas_flipHorizontal,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onFlipHorizontal();
                            },
                          ),

                          // Flip vertical button
                          CompactActionButton(
                            icon: Icons.flip,
                            color: Colors.teal,
                            tooltip:
                                NebulaLocalizations.of(
                                  context,
                                ).proCanvas_flipVertical,
                            rotation: 90,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onFlipVertical();
                            },
                          ),

                          // OCR — Convert to text button
                          CompactActionButton(
                            icon: Icons.text_fields_rounded,
                            color: Colors.deepPurple,
                            tooltip:
                                NebulaLocalizations.of(
                                  context,
                                ).proCanvas_convertToText,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onConvertToText();
                            },
                          ),

                          // Delete button
                          CompactActionButton(
                            icon: Icons.delete_rounded,
                            color: Colors.red,
                            tooltip:
                                NebulaLocalizations.of(
                                  context,
                                ).proCanvas_delete,
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              widget.onDelete();
                            },
                          ),

                          // Close button
                          CompactActionButton(
                            icon: Icons.close_rounded,
                            color: Colors.grey.shade700,
                            tooltip:
                                NebulaLocalizations.of(context).proCanvas_close,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onClearSelection();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
