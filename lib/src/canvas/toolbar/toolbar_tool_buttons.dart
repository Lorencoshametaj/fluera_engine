import 'package:flutter/material.dart';
import 'toolbar_tokens.dart';

// ============================================================================
// TOOLBAR TOOL BUTTONS — Pan, Stylus, Lasso, Ruler, PenTool, Text, Image
//
// All active-state colors are sourced from ToolbarTokens for visual
// consistency. Do NOT use raw Colors.* values here.
// ============================================================================

/// Reusable toggle button for toolbar tools.
/// Each tool has its own semantic accent color from [ToolbarTokens].
class _ToolToggleButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;
  final IconData icon;
  final Color activeColor;
  final String? tooltip;

  const _ToolToggleButton({
    required this.isActive,
    required this.onTap,
    required this.isDark,
    required this.icon,
    required this.activeColor,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ToolbarTokens.radius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(
            horizontal: ToolbarTokens.buttonPadH,
            vertical: ToolbarTokens.buttonPadV,
          ),
          decoration: BoxDecoration(
            color:
                isActive
                    ? ToolbarTokens.activeBackground(
                      activeColor,
                      isDark: isDark,
                    )
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(ToolbarTokens.radius),
            border:
                isActive
                    ? Border.all(
                      color: ToolbarTokens.activeBorder(activeColor),
                      width: 1.5,
                    )
                    : null,
          ),
          child: Icon(
            icon,
            size: ToolbarTokens.iconSize,
            color:
                isActive ? activeColor : cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        waitDuration: ToolbarTokens.tooltipDelay,
        child: child,
      );
    }
    return child;
  }
}

/// Pan Mode (Navigation) button
class ToolbarPanModeButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarPanModeButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.pan_tool_rounded,
      activeColor: ToolbarTokens.panActive,
      tooltip: 'Pan Mode',
    );
  }
}

/// Stylus Mode button
class ToolbarStylusModeButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarStylusModeButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.edit_outlined,
      activeColor: primary,
      tooltip: 'Stylus Only Mode',
    );
  }
}

/// Lasso selection button
class ToolbarLassoButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarLassoButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.gesture_rounded,
      activeColor: ToolbarTokens.lassoActive,
      tooltip: 'Lasso Selection',
    );
  }
}

/// Ruler / guide overlay toggle
class ToolbarRulerButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarRulerButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.straighten,
      activeColor: ToolbarTokens.rulerActive,
      tooltip: 'Ruler',
    );
  }
}

/// 🗺️ Minimap toggle button
class ToolbarMinimapButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarMinimapButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.map_outlined,
      activeColor: ToolbarTokens.minimapActive,
      tooltip: 'Minimap',
    );
  }
}

/// Vector Pen Tool button
class ToolbarPenToolButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarPenToolButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.timeline_rounded,
      activeColor: primary,
      tooltip: 'Vector Pen Tool',
    );
  }
}

/// Digital Text toggle button
class ToolbarDigitalTextButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarDigitalTextButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.text_fields_rounded,
      activeColor: ToolbarTokens.textActive,
      tooltip: 'Digital Text',
    );
  }
}

/// Image picker button
class ToolbarImagePickerButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarImagePickerButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.image_rounded,
      activeColor: ToolbarTokens.mediaActive,
      tooltip: 'Insert Image',
    );
  }
}

/// 🧮 LaTeX editor button
class ToolbarLatexButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarLatexButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.functions_rounded,
      activeColor: ToolbarTokens.latexActive,
      tooltip: 'LaTeX / Math Editor',
    );
  }
}

/// 📊 Tabular (spreadsheet) button
class ToolbarTabularButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarTabularButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.grid_on_rounded,
      activeColor: ToolbarTokens.lassoActive,
      tooltip: 'Spreadsheet',
    );
  }
}

/// Shape Recognition toggle button.
/// Shows a colored dot indicating sensitivity level (green=high, yellow=medium, red=low).
/// Shows a 👻 indicator when ghost suggestion mode is active.
class ToolbarShapeRecognitionButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final bool isDark;
  final bool ghostEnabled;

  /// 0 = low, 1 = medium, 2 = high
  final int sensitivityIndex;

  const ToolbarShapeRecognitionButton({
    super.key,
    required this.isActive,
    required this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    required this.isDark,
    this.sensitivityIndex = 1,
    this.ghostEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Sensitivity dot color
    final dotColor = switch (sensitivityIndex) {
      0 => const Color(0xFFDC2626), // red
      1 => const Color(0xFFD97706), // amber
      _ => const Color(0xFF16A34A), // green
    };
    return Tooltip(
      message:
          'Shape Recognition${isActive ? ' (${['Low', 'Medium', 'High'][sensitivityIndex]})' : ''}',
      waitDuration: ToolbarTokens.tooltipDelay,
      child: GestureDetector(
        onLongPress: onLongPress,
        onDoubleTap: onDoubleTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _ToolToggleButton(
              isActive: isActive,
              onTap: onTap,
              isDark: isDark,
              icon: Icons.auto_fix_high_rounded,
              activeColor: ToolbarTokens.shapeRecognitionActive,
            ),
            // Sensitivity dot (top-right)
            if (isActive)
              Positioned(
                right: 4,
                top: 2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.surface, width: 1.5),
                  ),
                ),
              ),
            // Ghost mode indicator (top-left)
            if (isActive && ghostEnabled)
              Positioned(
                left: 4,
                top: 1,
                child: Text(
                  '👻',
                  style: TextStyle(
                    fontSize: 10,
                    shadows: [Shadow(color: cs.surface, blurRadius: 2)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 📐 Section (artboard) button
class ToolbarSectionButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarSectionButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.dashboard_outlined,
      activeColor: ToolbarTokens.sectionActive,
      tooltip: 'Section / Artboard',
    );
  }
}

/// 🔍 Handwriting Search button (ML Kit powered)
class ToolbarSearchButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarSearchButton({
    super.key,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.search_rounded,
      activeColor: ToolbarTokens.searchActive,
      tooltip: 'Search Handwriting',
    );
  }
}
