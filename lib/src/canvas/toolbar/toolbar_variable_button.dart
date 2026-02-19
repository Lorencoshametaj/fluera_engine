import 'package:flutter/material.dart';

// =============================================================================
// 🎛️ TOOLBAR VARIABLE BUTTON
//
// Toggle button for opening the VariableManagerPanel.
// Follows the existing _ToolToggleButton pattern.
// =============================================================================

/// Toolbar button for toggling the design variables panel.
class ToolbarVariableButton extends StatelessWidget {
  /// Whether the variable panel is currently open.
  final bool isActive;

  /// Called when the button is tapped.
  final VoidCallback onTap;

  /// Whether the app is in dark mode.
  final bool isDark;

  /// Count of total variables (shown as badge).
  final int variableCount;

  const ToolbarVariableButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
    this.variableCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const activeColor = Colors.teal;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:
                    isActive
                        ? activeColor.withValues(alpha: isDark ? 0.25 : 0.08)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border:
                    isActive
                        ? Border.all(
                          color: activeColor.withValues(alpha: 0.5),
                          width: 2,
                        )
                        : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color:
                        isActive
                            ? activeColor
                            : cs.onSurface.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
            // Variable count badge.
            if (variableCount > 0)
              Positioned(
                right: 4,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: cs.surface, width: 1.5),
                  ),
                  child: Text(
                    '$variableCount',
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
