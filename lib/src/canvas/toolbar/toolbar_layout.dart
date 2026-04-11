import 'package:flutter/material.dart';
import 'toolbar_tokens.dart';

// ============================================================================
// TOOLBAR LAYOUT — Layout buttons (legacy, used by forceLeftAlign mode)
//
// NOTE: In the standard 3-zone top row, layout buttons are rendered as
// `_LayoutChip` widgets defined in `_toolbar_top_row.dart`.
// `ToolbarLayoutButton` and `ToolbarSyncButton` are kept for compatibility
// with the `forceLeftAlign` configuration and external consumers.
// ============================================================================

/// Layout button (Canvas, H-Split, V-Split, etc.)
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
    return Tooltip(
      message: label,
      waitDuration: ToolbarTokens.tooltipDelay,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
          child: Container(
            height: ToolbarTokens.chipHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
              border: Border.all(
                color: color.withValues(alpha: 0.30),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: ToolbarTokens.iconSizeSmall, color: color),
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

/// Sync toggle button (legacy — see `_SyncChip` for the new top-row version)
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
    final color =
        isEnabled
            ? const Color(0xFF16A34A) // green-600
            : (isDark ? Colors.white38 : Colors.black38);

    return Tooltip(
      message: isEnabled ? 'Disable Sync' : 'Enable Sync',
      waitDuration: ToolbarTokens.tooltipDelay,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
          child: Container(
            height: ToolbarTokens.chipHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
              border: Border.all(
                color: color.withValues(alpha: 0.30),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isEnabled ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                  size: ToolbarTokens.iconSizeSmall,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  'Sync',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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
