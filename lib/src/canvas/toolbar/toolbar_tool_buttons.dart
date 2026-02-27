import 'package:flutter/material.dart';

// ============================================================================
// TOOLBAR TOOL BUTTONS — Pan, Stylus, Lasso, Ruler, PenTool, Text, Image
// ============================================================================

/// Reusable toggle button for toolbar tools.
/// Each tool has its own accent color and icon.
class _ToolToggleButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;
  final IconData icon;
  final Color activeColor;

  const _ToolToggleButton({
    required this.isActive,
    required this.onTap,
    required this.isDark,
    required this.icon,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
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
                icon,
                size: 20,
                color:
                    isActive
                        ? activeColor
                        : cs.onSurface.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
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
      activeColor: Colors.orange,
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
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.edit_outlined,
      activeColor: Colors.blue,
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
      activeColor: Colors.purple,
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
      activeColor: Colors.amber,
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
      activeColor: Colors.teal,
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
    return _ToolToggleButton(
      isActive: isActive,
      onTap: onTap,
      isDark: isDark,
      icon: Icons.timeline_rounded,
      activeColor: Colors.teal,
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
      activeColor: Colors.deepPurple,
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
      activeColor: Colors.green,
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
      activeColor: Colors.teal,
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
      activeColor: Colors.indigo,
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
      0 => Colors.red,
      1 => Colors.amber,
      _ => Colors.green,
    };
    return GestureDetector(
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
            activeColor: Colors.indigo,
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
      activeColor: const Color(0xFF2196F3),
    );
  }
}
