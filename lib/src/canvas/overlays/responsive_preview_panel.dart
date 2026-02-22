import 'package:flutter/material.dart';
import '../../systems/responsive_breakpoint.dart';
import '../../systems/responsive_variant.dart';

// ============================================================================
// 📐 RESPONSIVE PREVIEW PANEL — Breakpoint preview with viewport resize
// ============================================================================

class ResponsivePreviewPanel extends StatelessWidget {
  final String breakpointName;
  final Size targetSize;

  const ResponsivePreviewPanel({
    super.key,
    required this.breakpointName,
    required this.targetSize,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = switch (breakpointName) {
      'mobile' => Icons.phone_android_rounded,
      'tablet' => Icons.tablet_rounded,
      'desktop' => Icons.desktop_windows_rounded,
      _ => Icons.devices_rounded,
    };

    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.2,
      maxChildSize: 0.7,
      builder:
          (ctx, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: cs.primary, size: 28),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${breakpointName[0].toUpperCase()}${breakpointName.substring(1)} Preview',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            '${targetSize.width.toInt()} × ${targetSize.height.toInt()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Breakpoint chips
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _BreakpointChip(
                        label: 'Mobile',
                        size: '375×812',
                        icon: Icons.phone_android_rounded,
                        isSelected: breakpointName == 'mobile',
                        cs: cs,
                      ),
                      _BreakpointChip(
                        label: 'Tablet',
                        size: '768×1024',
                        icon: Icons.tablet_rounded,
                        isSelected: breakpointName == 'tablet',
                        cs: cs,
                      ),
                      _BreakpointChip(
                        label: 'Desktop',
                        size: '1440×900',
                        icon: Icons.desktop_windows_rounded,
                        isSelected: breakpointName == 'desktop',
                        cs: cs,
                      ),
                    ],
                  ),
                ),
                // Preview area
                Expanded(
                  child: Center(
                    child: Container(
                      width: targetSize.width * 0.2,
                      height: targetSize.height * 0.2,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          icon,
                          size: 32,
                          color: cs.primary.withValues(alpha: 0.4),
                        ),
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

class _BreakpointChip extends StatelessWidget {
  final String label;
  final String size;
  final IconData icon;
  final bool isSelected;
  final ColorScheme cs;

  const _BreakpointChip({
    required this.label,
    required this.size,
    required this.icon,
    required this.isSelected,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color:
            isSelected
                ? cs.primaryContainer
                : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border:
            isSelected
                ? Border.all(color: cs.primary.withValues(alpha: 0.4))
                : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 20,
            color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
          ),
          Text(
            size,
            style: TextStyle(
              fontSize: 9,
              color: (isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant)
                  .withValues(alpha: 0.7),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
