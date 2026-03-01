import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// TOOLBAR LAYOUT — Layout and Sync buttons
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

/// Sync toggle button
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
