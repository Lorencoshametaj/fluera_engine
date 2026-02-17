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
