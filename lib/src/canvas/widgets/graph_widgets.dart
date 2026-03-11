import 'package:flutter/material.dart';

// =============================================================================
// GRAPH HELPER WIDGETS
// =============================================================================

/// A labeled group of toolbar chips for the graph widget.
class GraphToolbarGroup extends StatelessWidget {
  /// Group label displayed above the chips.
  final String label;

  /// Chip items to display horizontally.
  final List<Widget> children;

  const GraphToolbarGroup({
    super.key,
    required this.label,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children:
                children
                    .map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: c,
                      ),
                    )
                    .toList(),
          ),
        ),
      ],
    );
  }
}

/// A floating badge displayed in the top-right of the graph.
class GraphInfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const GraphInfoBadge({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: c)),
        ],
      ),
    );
  }
}

/// A tooltip label for the crosshair value display.
class GraphValueTooltip extends StatelessWidget {
  final double x;
  final double y;

  const GraphValueTooltip({super.key, required this.x, required this.y});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        'x=${x.toStringAsFixed(2)}, y=${y.toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          color: cs.onInverseSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
