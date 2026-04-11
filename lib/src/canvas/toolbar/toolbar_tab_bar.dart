import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'toolbar_tokens.dart';

// =============================================================================
// 🗂️ TOOLBAR TAB BAR — Navigable tab chips for multi-toolbar system
// =============================================================================

/// Identifies which toolbar context is currently active.
enum ToolbarTab {
  /// Main drawing tools: brush, eraser, lasso, colors, width, opacity, shapes
  main(Icons.brush_rounded, 'Draw'),

  /// PDF tools: pages, search, annotate, layout, doc switcher
  pdf(Icons.picture_as_pdf_rounded, 'PDF'),

  /// Scientific / math tools: LaTeX, pen tool, shape recognition
  scientific(Icons.functions_rounded, 'Math'),

  /// Excel / Spreadsheet tools: create tables, presets
  excel(Icons.table_chart_rounded, 'Excel'),

  /// Media & extras: digital text, image picker, recording, view recordings
  media(Icons.perm_media_rounded, 'Media'),

  /// Design tools: prototype, animate, inspect, responsive, components, quality
  design(Icons.design_services_rounded, 'Design');

  const ToolbarTab(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// Extended description for each tab — shown in tooltip.
extension _ToolbarTabTooltip on ToolbarTab {
  String get tooltipMessage => switch (this) {
    ToolbarTab.main => 'Drawing tools: brush, eraser, shapes, colors',
    ToolbarTab.pdf => 'PDF tools: pages, annotate, search, layout',
    ToolbarTab.scientific =>
      'Math tools: LaTeX editor, pen tool, shape recognition',
    ToolbarTab.excel => 'Spreadsheet tools: tables, formulas, CSV',
    ToolbarTab.media => 'Media: images, digital text, audio recording',
    ToolbarTab.design => 'Design tools: prototype, inspect, dev handoff',
  };
}

/// Compact tab bar for switching between toolbar contexts.
///
/// Only shows tabs that are in the [availableTabs] list, so contextual tabs
/// (e.g. PDF) can appear/disappear based on canvas state.
class ToolbarTabBar extends StatelessWidget {
  final ToolbarTab activeTab;
  final List<ToolbarTab> availableTabs;
  final ValueChanged<ToolbarTab> onTabChanged;
  final bool isDark;

  const ToolbarTabBar({
    super.key,
    required this.activeTab,
    required this.availableTabs,
    required this.onTabChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: ToolbarTokens.tabBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < availableTabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              _ToolbarTabChip(
                tab: availableTabs[i],
                isActive: availableTabs[i] == activeTab,
                isDark: isDark,
                onTap: () {
                  if (availableTabs[i] != activeTab) {
                    HapticFeedback.selectionClick();
                    onTabChanged(availableTabs[i]);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Individual tab chip with animated active state and tooltip.
class _ToolbarTabChip extends StatelessWidget {
  final ToolbarTab tab;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _ToolbarTabChip({
    required this.tab,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = cs.primary;
    final inactiveColor = cs.onSurface.withValues(alpha: 0.5);

    return Tooltip(
      message: tab.tooltipMessage,
      waitDuration: ToolbarTokens.tooltipDelay,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ToolbarTokens.tabRadius),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(
              horizontal: ToolbarTokens.tabChipPadH,
              vertical: ToolbarTokens.tabChipPadV,
            ),
            decoration: BoxDecoration(
              color:
                  isActive
                      ? activeColor.withValues(alpha: isDark ? 0.18 : 0.08)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(ToolbarTokens.tabRadius),
              border:
                  isActive
                      ? Border.all(
                        color: activeColor.withValues(alpha: 0.35),
                        width: 1.5,
                      )
                      : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  tab.icon,
                  size: ToolbarTokens.iconSizeSmall,
                  color: isActive ? activeColor : inactiveColor,
                ),
                const SizedBox(width: 4),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  style: TextStyle(
                    fontSize: ToolbarTokens.tabFontSize,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? activeColor : inactiveColor,
                  ),
                  child: Text(tab.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
