import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Paper type definition with metadata for the picker.
class PaperTypeOption {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final String category;

  const PaperTypeOption({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
  });
}

/// All available paper types, grouped by category.
const List<PaperTypeOption> kPaperTypes = [
  // ─── Blank ──────────────────────────────────────────
  PaperTypeOption(
    id: 'blank',
    name: 'Blank',
    description: 'No pattern',
    icon: Icons.crop_square_rounded,
    category: 'Basic',
  ),

  // ─── Grids ──────────────────────────────────────────
  PaperTypeOption(
    id: 'grid_5mm',
    name: 'Grid 5mm',
    description: 'Fine grid (5mm squares)',
    icon: Icons.grid_on_rounded,
    category: 'Grids',
  ),
  PaperTypeOption(
    id: 'grid_1cm',
    name: 'Grid 1cm',
    description: 'Standard grid (1cm squares)',
    icon: Icons.grid_on_rounded,
    category: 'Grids',
  ),
  PaperTypeOption(
    id: 'grid_2cm',
    name: 'Grid 2cm',
    description: 'Large grid (2cm squares)',
    icon: Icons.grid_on_rounded,
    category: 'Grids',
  ),
  PaperTypeOption(
    id: 'graph',
    name: 'Graph Paper',
    description: 'Millimeter grid with major lines',
    icon: Icons.grid_4x4_rounded,
    category: 'Grids',
  ),

  // ─── Lines ──────────────────────────────────────────
  PaperTypeOption(
    id: 'lines',
    name: 'Lined',
    description: 'Wide ruled (12mm)',
    icon: Icons.format_align_left_rounded,
    category: 'Lines',
  ),
  PaperTypeOption(
    id: 'lines_narrow',
    name: 'Narrow Lined',
    description: 'College ruled (8mm)',
    icon: Icons.format_align_left_rounded,
    category: 'Lines',
  ),

  // ─── Dots ──────────────────────────────────────────
  PaperTypeOption(
    id: 'dots',
    name: 'Dotted',
    description: 'Dot grid (1cm spacing)',
    icon: Icons.more_horiz_rounded,
    category: 'Dots',
  ),
  PaperTypeOption(
    id: 'dots_dense',
    name: 'Dense Dots',
    description: 'Dense dot grid (5mm spacing)',
    icon: Icons.more_horiz_rounded,
    category: 'Dots',
  ),
  PaperTypeOption(
    id: 'dot_grid',
    name: 'Dot Grid',
    description: 'Grid with dots at intersections',
    icon: Icons.blur_on_rounded,
    category: 'Dots',
  ),

  // ─── Specialty ──────────────────────────────────────
  PaperTypeOption(
    id: 'hex',
    name: 'Hexagonal',
    description: 'Hex grid (RPG/Chemistry)',
    icon: Icons.hexagon_rounded,
    category: 'Specialty',
  ),
  PaperTypeOption(
    id: 'isometric',
    name: 'Isometric',
    description: 'Triangular grid (3D drawing)',
    icon: Icons.change_history_rounded,
    category: 'Specialty',
  ),
  PaperTypeOption(
    id: 'music',
    name: 'Music Staff',
    description: 'Pentagram for musical notation',
    icon: Icons.music_note_rounded,
    category: 'Specialty',
  ),
  PaperTypeOption(
    id: 'cornell',
    name: 'Cornell Notes',
    description: 'Cue-Notes-Summary layout',
    icon: Icons.view_column_rounded,
    category: 'Specialty',
  ),
  PaperTypeOption(
    id: 'storyboard',
    name: 'Storyboard',
    description: '2×3 frame grid for storyboarding',
    icon: Icons.video_library_rounded,
    category: 'Specialty',
  ),
  PaperTypeOption(
    id: 'planner',
    name: 'Weekly Planner',
    description: '7-column planner layout',
    icon: Icons.calendar_view_week_rounded,
    category: 'Specialty',
  ),
  PaperTypeOption(
    id: 'calligraphy',
    name: 'Calligraphy',
    description: 'Baseline, x-height, ascender guides',
    icon: Icons.text_fields_rounded,
    category: 'Specialty',
  ),
];

/// Bottom sheet widget for selecting a paper type.
class PaperTypePickerSheet extends StatelessWidget {
  final String currentPaperType;
  final ValueChanged<String> onPaperTypeChanged;

  const PaperTypePickerSheet({
    super.key,
    required this.currentPaperType,
    required this.onPaperTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Group by category
    final categories = <String, List<PaperTypeOption>>{};
    for (final option in kPaperTypes) {
      categories.putIfAbsent(option.category, () => []).add(option);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder:
          (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.note_alt_rounded,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Paper Type',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // List
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    children: [
                      for (final entry in categories.entries) ...[
                        // Category header
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 8,
                            top: 12,
                            bottom: 4,
                          ),
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),

                        // Paper type options
                        ...entry.value.map(
                          (option) => _PaperTile(
                            option: option,
                            isSelected: option.id == currentPaperType,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onPaperTypeChanged(option.id);
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

class _PaperTile extends StatelessWidget {
  final PaperTypeOption option;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaperTile({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color:
          isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? colorScheme.primary.withValues(alpha: 0.15)
                          : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  option.icon,
                  size: 22,
                  color:
                      isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color:
                            isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      option.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle_rounded,
                  color: colorScheme.primary,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
