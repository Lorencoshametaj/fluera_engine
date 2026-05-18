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

  // 🗑️ Media tab removed 2026-05-16: its buttons (image picker, note
  // import, recording, view recordings) merged into [main]. Keeping
  // this comment so anyone hunting for "media" finds the move.

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
                // PDF gets a bespoke icon: stylized page + folded corner +
                // red "PDF" badge. Reads at a glance (Notability/Acrobat
                // pattern) instead of the generic Material picture_as_pdf
                // glyph. Other tabs use the standard Material icon.
                if (tab == ToolbarTab.pdf)
                  _PdfTabIcon(
                    size: ToolbarTokens.iconSizeSmall,
                    color: isActive ? activeColor : inactiveColor,
                    isActive: isActive,
                  )
                else
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

/// 📄 Bespoke PDF tab icon — stylized sheet of paper with a folded
/// upper-right corner and a small red "PDF" badge over the bottom
/// half. Replaces `Icons.picture_as_pdf_rounded` for instant
/// recognition; the generic Material glyph reads as just "document".
///
/// Scales cleanly from 16–32 logical pixels. Layout is fraction-based
/// off [size] so changes to `ToolbarTokens.iconSizeSmall` propagate.
class _PdfTabIcon extends StatelessWidget {
  final double size;
  final Color color;
  final bool isActive;

  const _PdfTabIcon({
    required this.size,
    required this.color,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PdfIconPainter(color: color, isActive: isActive),
      ),
    );
  }
}

class _PdfIconPainter extends CustomPainter {
  final Color color;
  final bool isActive;
  // Material Red 600 — Acrobat-style ink red, but only when active so
  // inactive tabs blend into the toolbar neutral palette.
  static const _badgeRedActive = Color(0xFFD32F2F);

  _PdfIconPainter({required this.color, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = (size.shortestSide * 0.085).clamp(1.2, 1.8);

    // ── Page outline with folded upper-right corner ─────────────────
    final pageInsetX = w * 0.14;
    final foldStartX = w * 0.66;
    final foldDepth = h * 0.24;
    final pagePath = Path()
      ..moveTo(pageInsetX, h * 0.06)
      ..lineTo(foldStartX, h * 0.06)
      ..lineTo(w * 0.92, h * 0.06 + foldDepth)
      ..lineTo(w * 0.92, h * 0.94)
      ..lineTo(pageInsetX, h * 0.94)
      ..close();

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(pagePath, strokePaint);

    // Folded corner — small triangle showing the back of the page.
    final foldPath = Path()
      ..moveTo(foldStartX, h * 0.06)
      ..lineTo(foldStartX, h * 0.06 + foldDepth)
      ..lineTo(w * 0.92, h * 0.06 + foldDepth);
    canvas.drawPath(foldPath, strokePaint);

    // ── Red "PDF" badge over the lower portion of the page ─────────
    // Active tabs use Acrobat-style red so the brand cue lands; on
    // inactive tabs the badge inherits the muted icon color so the
    // tab bar doesn't fight for attention.
    final badgeColor = isActive ? _badgeRedActive : color;
    final badgeRect = RRect.fromLTRBR(
      pageInsetX + stroke,
      h * 0.56,
      w * 0.92 - stroke,
      h * 0.86,
      Radius.circular(size.shortestSide * 0.08),
    );
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = badgeColor
        ..style = PaintingStyle.fill,
    );

    // Tiny "PDF" wordmark inside the badge. At 16-20px icon sizes the
    // letters won't be legible character-by-character, but the
    // silhouette + ratio still reads as "PDF label" thanks to the
    // wide aspect of the wordmark.
    final tp = TextPainter(
      text: TextSpan(
        text: 'PDF',
        style: TextStyle(
          color: Colors.white,
          fontSize: h * 0.20,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w);
    tp.paint(
      canvas,
      Offset(
        (w - tp.width) / 2,
        h * 0.71 - tp.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _PdfIconPainter old) =>
      old.color != color || old.isActive != isActive;
}
