import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/nebula_localizations.dart';
import './compact_action_button.dart';

/// Grouped action categories for the selection menu
enum _MenuCategory { none, transform, arrange, advanced }

/// Action menu for lasso selection — mobile-optimized with grouped categories.
///
/// Layout:
/// - **Primary bar** (always visible): count, copy, duplicate, delete, close, "more"
/// - **Expandable panel**: 3 category tabs (Transform, Arrange, Advanced)
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
  _MenuCategory _expanded = _MenuCategory.none;

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

  void _toggleCategory(_MenuCategory cat) {
    setState(() {
      _expanded = _expanded == cat ? _MenuCategory.none : cat;
    });
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white70 : Colors.black87;

    return SlideTransition(
      position: _slideAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Expandable category panel ──
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child:
                    _expanded != _MenuCategory.none
                        ? _buildCategoryPanel(isDark, bgColor)
                        : const SizedBox.shrink(),
              ),

              const SizedBox(height: 6),

              // ── Primary action bar ──
              _buildPrimaryBar(isDark, bgColor, textColor),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Primary Action Bar
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildPrimaryBar(bool isDark, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
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
          // Selection count badge
          Tooltip(
            message: widget.statsSummary ?? 'Selected',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.blue,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.selectionCount}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 4),

          // Copy
          if (widget.onCopy != null)
            CompactActionButton(
              icon: Icons.copy_rounded,
              color: Colors.indigo,
              tooltip: 'Copy',
              onTap: widget.onCopy!,
            ),

          // Duplicate
          if (widget.onDuplicate != null)
            CompactActionButton(
              icon: Icons.library_add_rounded,
              color: Colors.cyan,
              tooltip: 'Duplicate',
              onTap: widget.onDuplicate!,
            ),

          // Paste (only when clipboard has content)
          if (widget.onPaste != null && widget.hasClipboard)
            CompactActionButton(
              icon: Icons.paste_rounded,
              color: Colors.green,
              tooltip: 'Paste',
              onTap: widget.onPaste!,
            ),

          // Delete
          CompactActionButton(
            icon: Icons.delete_rounded,
            color: Colors.red,
            tooltip: NebulaLocalizations.of(context).proCanvas_delete,
            onTap: widget.onDelete,
          ),

          // Close selection
          CompactActionButton(
            icon: Icons.close_rounded,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
            tooltip: NebulaLocalizations.of(context).proCanvas_close,
            onTap: widget.onClearSelection,
          ),

          // Divider
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color:
                isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.1),
          ),

          // "More" overflow toggle
          _buildCategoryToggle(
            icon: Icons.more_horiz_rounded,
            label: 'More',
            isActive: _expanded != _MenuCategory.none,
            color: Colors.blueGrey,
            onTap: () {
              if (_expanded == _MenuCategory.none) {
                _toggleCategory(_MenuCategory.transform);
              } else {
                _toggleCategory(_MenuCategory.none);
              }
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Category Panel (expanded)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildCategoryPanel(bool isDark, Color bgColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Category tab row
          Row(
            children: [
              _buildCategoryTab(
                icon: Icons.rotate_90_degrees_ccw_rounded,
                label: 'Transform',
                category: _MenuCategory.transform,
                color: Colors.blue,
                isDark: isDark,
              ),
              const SizedBox(width: 6),
              _buildCategoryTab(
                icon: Icons.dashboard_customize_rounded,
                label: 'Arrange',
                category: _MenuCategory.arrange,
                color: Colors.deepOrange,
                isDark: isDark,
              ),
              const SizedBox(width: 6),
              _buildCategoryTab(
                icon: Icons.tune_rounded,
                label: 'Advanced',
                category: _MenuCategory.advanced,
                color: Colors.purple,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Category content
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _buildCategoryContent(_expanded),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTab({
    required IconData icon,
    required String label,
    required _MenuCategory category,
    required Color color,
    required bool isDark,
  }) {
    final isActive = _expanded == category;
    return Expanded(
      child: GestureDetector(
        onTap: () => _toggleCategory(category),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color:
                isActive
                    ? color.withValues(alpha: 0.15)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.withValues(alpha: 0.08)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  isActive ? color.withValues(alpha: 0.4) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isActive ? color : Colors.grey),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color:
                      isActive
                          ? color
                          : (isDark ? Colors.white60 : Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Category Contents
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildCategoryContent(_MenuCategory category) {
    switch (category) {
      case _MenuCategory.transform:
        return _buildTransformContent();
      case _MenuCategory.arrange:
        return _buildArrangeContent();
      case _MenuCategory.advanced:
        return _buildAdvancedContent();
      case _MenuCategory.none:
        return const SizedBox.shrink();
    }
  }

  // ── Transform ──
  Widget _buildTransformContent() {
    return Row(
      key: const ValueKey('transform'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CompactActionButton(
          icon: Icons.rotate_90_degrees_ccw_rounded,
          color: Colors.blue,
          tooltip: 'Rotate 90°',
          onTap: widget.onRotate,
        ),
        CompactActionButton(
          icon: Icons.flip,
          color: Colors.orange,
          tooltip: NebulaLocalizations.of(context).proCanvas_flipHorizontal,
          onTap: widget.onFlipHorizontal,
        ),
        CompactActionButton(
          icon: Icons.flip,
          color: Colors.teal,
          tooltip: NebulaLocalizations.of(context).proCanvas_flipVertical,
          rotation: 90,
          onTap: widget.onFlipVertical,
        ),
      ],
    );
  }

  // ── Arrange ──
  Widget _buildArrangeContent() {
    return SingleChildScrollView(
      key: const ValueKey('arrange'),
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onBringToFront != null)
            CompactActionButton(
              icon: Icons.flip_to_front_rounded,
              color: Colors.amber.shade700,
              tooltip: 'Bring to Front',
              onTap: widget.onBringToFront!,
            ),
          if (widget.onSendToBack != null)
            CompactActionButton(
              icon: Icons.flip_to_back_rounded,
              color: Colors.brown,
              tooltip: 'Send to Back',
              onTap: widget.onSendToBack!,
            ),

          // Separator
          _buildDivider(),

          // Align buttons
          if (widget.onAlignLeft != null)
            CompactActionButton(
              icon: Icons.align_horizontal_left_rounded,
              color: Colors.deepOrange,
              tooltip: 'Align Left',
              onTap: widget.onAlignLeft!,
            ),
          if (widget.onAlignCenterH != null)
            CompactActionButton(
              icon: Icons.align_horizontal_center_rounded,
              color: Colors.deepOrange,
              tooltip: 'Align Center',
              onTap: widget.onAlignCenterH!,
            ),
          if (widget.onAlignRight != null)
            CompactActionButton(
              icon: Icons.align_horizontal_right_rounded,
              color: Colors.deepOrange,
              tooltip: 'Align Right',
              onTap: widget.onAlignRight!,
            ),
          if (widget.onAlignTop != null)
            CompactActionButton(
              icon: Icons.align_vertical_top_rounded,
              color: Colors.deepOrange.shade300,
              tooltip: 'Align Top',
              onTap: widget.onAlignTop!,
            ),
          if (widget.onAlignCenterV != null)
            CompactActionButton(
              icon: Icons.align_vertical_center_rounded,
              color: Colors.deepOrange.shade300,
              tooltip: 'Align Middle',
              onTap: widget.onAlignCenterV!,
            ),
          if (widget.onAlignBottom != null)
            CompactActionButton(
              icon: Icons.align_vertical_bottom_rounded,
              color: Colors.deepOrange.shade300,
              tooltip: 'Align Bottom',
              onTap: widget.onAlignBottom!,
            ),

          // Separator
          _buildDivider(),

          // Distribute
          if (widget.onDistributeH != null)
            CompactActionButton(
              icon: Icons.horizontal_distribute_rounded,
              color: Colors.indigo.shade300,
              tooltip: 'Distribute H',
              onTap: widget.onDistributeH!,
            ),
          if (widget.onDistributeV != null)
            CompactActionButton(
              icon: Icons.vertical_distribute_rounded,
              color: Colors.indigo.shade300,
              tooltip: 'Distribute V',
              onTap: widget.onDistributeV!,
            ),
        ],
      ),
    );
  }

  // ── Advanced ──
  Widget _buildAdvancedContent() {
    return SingleChildScrollView(
      key: const ValueKey('advanced'),
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Select All
          if (widget.onSelectAll != null)
            CompactActionButton(
              icon: Icons.select_all_rounded,
              color: Colors.blueGrey,
              tooltip: 'Select All',
              onTap: widget.onSelectAll!,
            ),

          // Undo
          if (widget.onUndo != null)
            CompactActionButton(
              icon: Icons.undo_rounded,
              color: Colors.grey.shade600,
              tooltip: 'Undo',
              onTap: widget.onUndo!,
            ),

          _buildDivider(),

          // Group / Ungroup
          if (widget.onGroup != null)
            CompactActionButton(
              icon: Icons.group_work_rounded,
              color: Colors.purple,
              tooltip: 'Group',
              onTap: widget.onGroup!,
            ),
          if (widget.onUngroup != null)
            CompactActionButton(
              icon: Icons.workspaces_outline,
              color: Colors.pink,
              tooltip: 'Ungroup',
              onTap: widget.onUngroup!,
            ),

          _buildDivider(),

          // Lock toggle
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
              tooltip: widget.isSelectionLocked ? 'Unlock' : 'Lock',
              onTap: () {
                if (widget.isSelectionLocked) {
                  widget.onUnlock?.call();
                } else {
                  widget.onLock!();
                }
              },
            ),

          // Snap toggle
          if (widget.onToggleSnap != null)
            CompactActionButton(
              icon: Icons.grid_4x4_rounded,
              color: widget.snapEnabled ? Colors.lime.shade700 : Colors.grey,
              tooltip: widget.snapEnabled ? 'Snap: ON' : 'Snap: OFF',
              onTap: widget.onToggleSnap!,
            ),

          // Multi-Layer toggle
          if (widget.onToggleMultiLayer != null)
            CompactActionButton(
              icon: Icons.layers_rounded,
              color: widget.multiLayerMode ? Colors.teal.shade600 : Colors.grey,
              tooltip:
                  widget.multiLayerMode
                      ? 'Multi-Layer: ON'
                      : 'Multi-Layer: OFF',
              onTap: widget.onToggleMultiLayer!,
            ),

          _buildDivider(),

          // OCR Convert to text
          CompactActionButton(
            icon: Icons.text_fields_rounded,
            color: Colors.deepPurple,
            tooltip: NebulaLocalizations.of(context).proCanvas_convertToText,
            onTap: widget.onConvertToText,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.grey.withValues(alpha: 0.25),
    );
  }

  Widget _buildCategoryToggle({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? color.withValues(alpha: 0.4) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? Icons.expand_more_rounded : icon,
              size: 18,
              color: isActive ? color : Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isActive ? color : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
