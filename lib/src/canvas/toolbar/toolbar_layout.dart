import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// TOOLBAR LAYOUT — Layout, Sync, and MultiView buttons
// ============================================================================

/// Layout button (Canvas, PDF, H-Split, V-Split, etc.)
class ToolbarLayoutButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isDark;
  final Color color;

  const ToolbarLayoutButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.isDark,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: color,
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

/// Sync toggle button (PDF-Canvas synchronization)
class ToolbarSyncButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isEnabled;
  final bool isDark;

  const ToolbarSyncButton({
    super.key,
    required this.onPressed,
    required this.isEnabled,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isEnabled ? Colors.green : Colors.grey;

    return Container(
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: activeColor.withValues(alpha: 0.3), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isEnabled ? Icons.sync : Icons.sync_disabled,
                  size: 16,
                  color: activeColor,
                ),
                const SizedBox(width: 4),
                Text(
                  'Sync',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: activeColor,
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

/// Compact MultiView button with long-press mode selection
class ToolbarMultiViewCompactButton extends StatelessWidget {
  final VoidCallback onPressed;
  final ValueChanged<int>? onModeSelected;
  final bool isDark;

  const ToolbarMultiViewCompactButton({
    super.key,
    required this.onPressed,
    this.onModeSelected,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onPressed,
      onLongPress: () => _showModeSelectionMenu(context),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onPressed,
            onLongPress: () => _showModeSelectionMenu(context),
            child: Icon(
              Icons.view_quilt_rounded,
              size: 16,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }

  void _showModeSelectionMenu(BuildContext context) async {
    HapticFeedback.heavyImpact();

    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final cs = Theme.of(context).colorScheme;
    final selected = await showMenu<int>(
      context: context,
      position: position,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      elevation: 8,
      items: [
        PopupMenuItem<int>(
          value: 1,
          child: _buildModeItem(
            context,
            icon: Icons.view_agenda_rounded,
            title: 'Single View',
            subtitle: '1 page',
          ),
        ),
        PopupMenuItem<int>(
          value: 2,
          child: _buildModeItem(
            context,
            icon: Icons.view_sidebar_rounded,
            title: 'Dual View',
            subtitle: '2 pages',
          ),
        ),
        PopupMenuItem<int>(
          value: 3,
          child: _buildModeItem(
            context,
            icon: Icons.view_column_rounded,
            title: 'Triple View',
            subtitle: '3 pages',
          ),
        ),
        PopupMenuItem<int>(
          value: 4,
          child: _buildModeItem(
            context,
            icon: Icons.grid_view_rounded,
            title: 'Quad View',
            subtitle: '4 pages (2×2)',
          ),
        ),
      ],
    );

    if (selected != null && onModeSelected != null) {
      HapticFeedback.selectionClick();
      onModeSelected!(selected);
    }
  }

  Widget _buildModeItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
