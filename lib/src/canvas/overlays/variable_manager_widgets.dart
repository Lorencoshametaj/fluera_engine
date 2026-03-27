part of 'variable_manager_panel.dart';

// ═══════════════════════════════════════
// 🎨 Variable Manager — Helper Widgets
// ═══════════════════════════════════════


// =============================================================================
// Helper Widgets
// =============================================================================

/// Compact icon button.
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final ColorScheme cs;
  final double size;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.onTap,
    required this.cs,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: size,
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// Type icon for design variables.
class _VariableTypeIcon extends StatelessWidget {
  final DesignVariableType type;
  const _VariableTypeIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      DesignVariableType.color => (Icons.palette_outlined, Colors.pink),
      DesignVariableType.number => (Icons.numbers_rounded, Colors.blue),
      DesignVariableType.string => (Icons.text_fields_rounded, Colors.orange),
      DesignVariableType.boolean => (Icons.toggle_on_outlined, Colors.green),
    };
    return Icon(icon, size: 14, color: color);
  }
}

/// Inline value preview widget.
class _ValuePreview extends StatelessWidget {
  final DesignVariableType type;
  final dynamic value;
  final ColorScheme cs;

  const _ValuePreview({required this.type, this.value, required this.cs});

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return Text(
        '—',
        style: TextStyle(
          fontSize: 11,
          color: cs.onSurface.withValues(alpha: 0.3),
        ),
      );
    }

    if (type == DesignVariableType.color && value is int) {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: Color(value as int),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        ),
      );
    }

    final label = switch (type) {
      DesignVariableType.number =>
        (value is num) ? value.toStringAsFixed(1) : '$value',
      DesignVariableType.boolean => (value == true) ? '✓' : '✗',
      _ => '$value',
    };

    return Container(
      constraints: const BoxConstraints(maxWidth: 60),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: cs.onSurface.withValues(alpha: 0.6),
          fontFamily: 'monospace',
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
