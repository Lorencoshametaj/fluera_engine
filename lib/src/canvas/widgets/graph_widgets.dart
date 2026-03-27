import 'package:flutter/material.dart';

// =============================================================================
// GRAPH HELPER WIDGETS — Material Design 3
// =============================================================================

/// A floating badge for graph info (zoom level, domain).
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: c,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tooltip label for the crosshair value display — M3 Card style.
class GraphValueTooltip extends StatelessWidget {
  final double x;
  final double y;
  final List<(Color, double)> extraValues;

  const GraphValueTooltip({
    super.key,
    required this.x,
    required this.y,
    this.extraValues = const [],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gps_fixed_rounded, size: 10, color: cs.onPrimaryContainer),
              const SizedBox(width: 4),
              Text(
                'Crosshair',
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'x = ${x.toStringAsFixed(3)}',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'f₁ = ${y.toStringAsFixed(3)}',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          // Extra function values
          ...extraValues.map((entry) {
            final (color, val) = entry;
            final idx = extraValues.indexOf(entry) + 2;
            const subs = '₀₁₂₃₄₅₆₇₈₉';
            final sub = String.fromCharCodes(
              idx.toString().codeUnits.map((c) => subs.codeUnitAt(c - 48)),
            );
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'f$sub = ${val.isFinite ? val.toStringAsFixed(3) : "∞"}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// A floating zoom control cluster.
class GraphZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onAutoFit;
  final VoidCallback onReset;

  const GraphZoomControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onAutoFit,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _zoomBtn(context, Icons.add_rounded, onZoomIn),
          Divider(height: 1, indent: 6, endIndent: 6, color: cs.outlineVariant.withValues(alpha: 0.3)),
          _zoomBtn(context, Icons.remove_rounded, onZoomOut),
          Divider(height: 1, indent: 6, endIndent: 6, color: cs.outlineVariant.withValues(alpha: 0.3)),
          _zoomBtn(context, Icons.fit_screen_rounded, onAutoFit),
          Divider(height: 1, indent: 6, endIndent: 6, color: cs.outlineVariant.withValues(alpha: 0.3)),
          _zoomBtn(context, Icons.restart_alt_rounded, onReset),
        ],
      ),
    );
  }

  Widget _zoomBtn(BuildContext context, IconData icon, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        color: cs.onSurfaceVariant,
        padding: EdgeInsets.zero,
        splashRadius: 16,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

/// A toolbar tab button (for Analisi / Display / Strumenti).
class GraphToolbarTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const GraphToolbarTab({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSecondaryContainer,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
