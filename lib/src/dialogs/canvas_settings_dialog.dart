import 'package:flutter/material.dart';
import '../l10n/fluera_localizations.dart';
import '../rendering/canvas/paper_pattern_painter.dart';
import '../core/engine_scope.dart';
import '../drawing/models/surface_material.dart';

/// Dialog per le impostazioni avanzate del canvas — Material Design 3
class CanvasSettingsDialog extends StatefulWidget {
  final bool isDark;
  final Color currentBackgroundColor;
  final String currentPaperType;
  final Function(Color) onBackgroundColorChanged;
  final Function(String) onPaperTypeChanged;
  final SurfaceMaterial? currentSurface;
  final Function(SurfaceMaterial?)? onSurfaceChanged;

  const CanvasSettingsDialog({
    super.key,
    required this.isDark,
    required this.currentBackgroundColor,
    required this.currentPaperType,
    required this.onBackgroundColorChanged,
    required this.onPaperTypeChanged,
    this.currentSurface,
    this.onSurfaceChanged,
  });

  @override
  State<CanvasSettingsDialog> createState() => _CanvasSettingsDialogState();

  static Future<void> show(
    BuildContext context, {
    required bool isDark,
    required Color currentBackgroundColor,
    required String currentPaperType,
    required Function(Color) onBackgroundColorChanged,
    required Function(String) onPaperTypeChanged,
    SurfaceMaterial? currentSurface,
    Function(SurfaceMaterial?)? onSurfaceChanged,
  }) {
    return showDialog(
      context: context,
      builder:
          (context) => CanvasSettingsDialog(
            isDark: isDark,
            currentBackgroundColor: currentBackgroundColor,
            currentPaperType: currentPaperType,
            onBackgroundColorChanged: onBackgroundColorChanged,
            onPaperTypeChanged: onPaperTypeChanged,
            currentSurface: currentSurface,
            onSurfaceChanged: onSurfaceChanged,
          ),
    );
  }
}

class _CanvasSettingsDialogState extends State<CanvasSettingsDialog> {
  late String _selectedPaperType;
  late Color _selectedColor;
  late SurfaceMaterial? _selectedSurface;
  String _selectedCategory = 'basic';

  // Icone per i tipi di carta (per la griglia visuale)
  static const Map<String, IconData> paperTypeIcons = {
    'blank': Icons.crop_landscape_rounded,
    'lines': Icons.horizontal_rule_rounded,
    'lines_narrow': Icons.density_medium_rounded,
    'grid_5mm': Icons.grid_on_rounded,
    'grid_1cm': Icons.grid_on_rounded,
    'grid_2cm': Icons.grid_4x4_rounded,
    'dots': Icons.blur_on_rounded,
    'dots_dense': Icons.grain_rounded,
    'graph': Icons.border_all_rounded,
    'hex': Icons.hexagon_outlined,
    'isometric': Icons.change_history_rounded,
    'music': Icons.music_note_rounded,
    'cornell': Icons.view_agenda_rounded,
    'storyboard': Icons.view_comfy_rounded,
  };

  // Icone per le categorie
  static const Map<String, IconData> categoryIcons = {
    'basic': Icons.description_outlined,
    'grid': Icons.grid_on_rounded,
    'technical': Icons.architecture_rounded,
  };

  // Paper types organized by category
  Map<String, Map<String, String>> _getPaperTypesByCategory(
    FlueraLocalizations l10n,
  ) {
    return {
      'basic': {
        'blank': l10n.proCanvas_paperBlank,
        'lines': l10n.proCanvas_paperWideLines,
        'lines_narrow': l10n.proCanvas_paperNarrowLines,
        'calligraphy': l10n.proCanvas_paperCalligraphy,
      },
      'grid': {
        'grid_5mm': '5mm',
        'grid_1cm': '1cm',
        'grid_2cm': '2cm',
        'dots': l10n.proCanvas_paperDots,
        'dots_dense': l10n.proCanvas_paperDotsDense,
        'dot_grid': l10n.proCanvas_paperDotGrid,
      },
      'technical': {
        'graph': l10n.proCanvas_paperGraph,
        'hex': l10n.proCanvas_paperHex,
        'isometric': l10n.proCanvas_paperIsometric,
        'music': l10n.proCanvas_paperMusic,
        'cornell': l10n.proCanvas_paperCornell,
        'storyboard': l10n.proCanvas_paperStoryboard,
        'planner': l10n.proCanvas_paperPlanner,
      },
    };
  }

  // Category names
  Map<String, String> _getCategoryNames(FlueraLocalizations l10n) {
    return {
      'basic': l10n.proCanvas_categoryBasic,
      'grid': l10n.proCanvas_categoryGrid,
      'technical': l10n.proCanvas_categoryTechnical,
    };
  }

  // Curated background colors
  static const List<Color> backgroundColors = [
    Color(0xFFFFFFFF), // Bianco puro
    Color(0xFFFAF8F5), // Avorio caldo
    Color(0xFFF5F5DC), // Beige
    Color(0xFFE6F3FF), // Azzurro tenue
    Color(0xFFE8F5E9), // Verde menta
    Color(0xFFFFF3E0), // Pesca
    Color(0xFFF3E5F5), // Lavanda
    Color(0xFFECEFF1), // Grigio freddo
    Color(0xFF37474F), // Ardesia
    Color(0xFF263238), // Antracite
    Color(0xFF1A1A2E), // Navy scuro
    Color(0xFF000000), // Nero
  ];

  @override
  void initState() {
    super.initState();
    _selectedPaperType = widget.currentPaperType;
    _selectedColor = widget.currentBackgroundColor;
    _selectedSurface = widget.currentSurface;

    // Auto-seleziona la categoria corretta
    const paperTypeToCategory = {
      'blank': 'basic',
      'lines': 'basic',
      'lines_narrow': 'basic',
      'calligraphy': 'basic',
      'grid_5mm': 'grid',
      'grid_1cm': 'grid',
      'grid_2cm': 'grid',
      'dots': 'grid',
      'dots_dense': 'grid',
      'dot_grid': 'grid',
      'graph': 'technical',
      'hex': 'technical',
      'isometric': 'technical',
      'music': 'technical',
      'cornell': 'technical',
      'storyboard': 'technical',
      'planner': 'technical',
    };
    _selectedCategory = paperTypeToCategory[_selectedPaperType] ?? 'basic';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = widget.isDark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1B1F) : colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, colorScheme, isDark),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🖼️ Live Preview
                    _buildLivePreview(isDark, colorScheme),
                    const SizedBox(height: 20),

                    // 📂 Category Tabs
                    _buildCategorySegments(colorScheme, isDark),
                    const SizedBox(height: 16),

                    // 📄 Paper Type Grid
                    _buildPaperTypeGrid(colorScheme, isDark),
                    const SizedBox(height: 24),

                    // 🎨 Background Color
                    _buildSectionHeader(
                      FlueraLocalizations.of(context).proCanvas_backgroundColor,
                      Icons.palette_rounded,
                      colorScheme,
                      isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildColorGrid(colorScheme),

                    // 🧬 Surface Material
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                      'Surface Texture',
                      Icons.texture_rounded,
                      colorScheme,
                      isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildSurfaceSection(colorScheme, isDark),

                    // ✨ Pro Shader Toggle
                    if (EngineScope.hasScope &&
                        (EngineScope
                                .current
                                .drawingModule
                                ?.shaderBrushService
                                .isAvailable ??
                            false)) ...[
                      const SizedBox(height: 24),
                      _buildProShaderToggle(isDark, colorScheme),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _buildFooter(context, colorScheme, isDark),
          ],
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // HEADER
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final l10n = FlueraLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.auto_awesome_mosaic_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.proCanvas_paperMode,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: isDark ? Colors.white : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.proCanvas_customizeYourSheet,
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        isDark ? Colors.white54 : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              color: isDark ? Colors.white54 : colorScheme.onSurfaceVariant,
            ),
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // LIVE PREVIEW
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildLivePreview(bool isDark, ColorScheme colorScheme) {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: CustomPaint(
            key: ValueKey('${_selectedPaperType}_${_selectedColor.toARGB32()}'),
            painter: PaperPatternPainter(
              paperType: _selectedPaperType,
              backgroundColor: _selectedColor,
              scale: 37.8, // 1cm = 37.8px (stessa scala del BackgroundPainter)
            ),
            size: const Size(double.infinity, 180),
          ),
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // CATEGORY SEGMENTS (MD3 SegmentedButton)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildCategorySegments(ColorScheme colorScheme, bool isDark) {
    final l10n = FlueraLocalizations.of(context);
    final categoryNames = _getCategoryNames(l10n);

    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        segments:
            categoryNames.entries.map((entry) {
              return ButtonSegment<String>(
                value: entry.key,
                label: Text(entry.value, style: const TextStyle(fontSize: 13)),
                icon: Icon(categoryIcons[entry.key], size: 18),
              );
            }).toList(),
        selected: {_selectedCategory},
        onSelectionChanged: (selection) {
          setState(() {
            _selectedCategory = selection.first;
          });
        },
        style: SegmentedButton.styleFrom(
          backgroundColor:
              isDark
                  ? const Color(0xFF2C2C2C)
                  : colorScheme.surfaceContainerLow,
          selectedBackgroundColor: colorScheme.secondaryContainer,
          selectedForegroundColor: colorScheme.onSecondaryContainer,
          foregroundColor:
              isDark ? Colors.white60 : colorScheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // PAPER TYPE GRID
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildPaperTypeGrid(ColorScheme colorScheme, bool isDark) {
    final l10n = FlueraLocalizations.of(context);
    final paperTypesByCategory = _getPaperTypesByCategory(l10n);
    final currentTypes = paperTypesByCategory[_selectedCategory]!;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          currentTypes.entries.map((entry) {
            final isSelected = _selectedPaperType == entry.key;
            final icon = paperTypeIcons[entry.key] ?? Icons.description;

            return _PaperTypeCard(
              label: entry.value,
              icon: icon,
              isSelected: isSelected,
              isDark: isDark,
              colorScheme: colorScheme,
              onTap: () {
                setState(() {
                  _selectedPaperType = entry.key;
                });
              },
            );
          }).toList(),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // COLOR GRID
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildColorGrid(ColorScheme colorScheme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children:
          backgroundColors.map((color) {
            final isSelected = _selectedColor == color;
            return _ColorSwatch(
              color: color,
              isSelected: isSelected,
              accentColor: colorScheme.primary,
              onTap: () {
                setState(() {
                  _selectedColor = color;
                });
              },
            );
          }).toList(),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // SURFACE MATERIAL SECTION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildSurfaceSection(ColorScheme colorScheme, bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          _surfacePresets.map((preset) {
            final isSelected = _selectedSurface == preset.surface;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedSurface = preset.surface;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? colorScheme.secondaryContainer
                            : (isDark
                                ? const Color(0xFF2C2C2C)
                                : colorScheme.surfaceContainerLow),
                    border: Border.all(
                      color:
                          isSelected
                              ? colorScheme.primary.withValues(alpha: 0.5)
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : colorScheme.outlineVariant.withValues(
                                    alpha: 0.3,
                                  )),
                      width: isSelected ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(preset.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        preset.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          color:
                              isSelected
                                  ? colorScheme.onSecondaryContainer
                                  : (isDark
                                      ? Colors.white70
                                      : colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // SECTION HEADER
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: isDark ? Colors.white : colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // PRO SHADER TOGGLE
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildProShaderToggle(bool isDark, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color:
            isDark
                ? Colors.deepPurple.withValues(alpha: 0.12)
                : Colors.deepPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.deepPurple.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            color: Colors.deepPurple.shade300,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GPU Shader Engine',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  'Active — per-pixel texture rendering',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle_rounded,
            color: Colors.deepPurple.shade300,
            size: 22,
          ),
        ],
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // FOOTER
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildFooter(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final l10n = FlueraLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              foregroundColor:
                  isDark ? Colors.white60 : colorScheme.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(l10n.cancel, style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {
              widget.onBackgroundColorChanged(_selectedColor);
              widget.onPaperTypeChanged(_selectedPaperType);
              widget.onSurfaceChanged?.call(_selectedSurface);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.secondaryContainer,
              foregroundColor: colorScheme.onSecondaryContainer,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_rounded, size: 18),
                const SizedBox(width: 8),
                Text(
                  l10n.proCanvas_applyButton,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SURFACE MATERIAL PRESETS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _SurfacePreset {
  final String label;
  final String emoji;
  final SurfaceMaterial? surface;

  const _SurfacePreset(this.label, this.emoji, this.surface);
}

const _surfacePresets = [
  _SurfacePreset('None', '❌', null),
  _SurfacePreset('Glass', '🪟', SurfaceMaterial.glass()),
  _SurfacePreset('Smooth', '📄', SurfaceMaterial.smoothPaper()),
  _SurfacePreset('Watercolor', '💧', SurfaceMaterial.watercolorPaper()),
  _SurfacePreset('Canvas', '🖼️', SurfaceMaterial.canvas()),
  _SurfacePreset('Wood', '🪵', SurfaceMaterial.rawWood()),
  _SurfacePreset('Chalk', '📝', SurfaceMaterial.chalkboard()),
];

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PAPER TYPE CARD — chip con icona e label
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _PaperTypeCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _PaperTypeCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isDark,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:
                isSelected
                    ? colorScheme.secondaryContainer
                    : (isDark
                        ? const Color(0xFF2C2C2C)
                        : colorScheme.surfaceContainerLow),
            border: Border.all(
              color:
                  isSelected
                      ? colorScheme.primary.withValues(alpha: 0.5)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : colorScheme.outlineVariant.withValues(alpha: 0.3)),
              width: isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : icon,
                size: 18,
                color:
                    isSelected
                        ? colorScheme.primary
                        : (isDark
                            ? Colors.white54
                            : colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color:
                      isSelected
                          ? colorScheme.onSecondaryContainer
                          : (isDark ? Colors.white70 : colorScheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// COLOR SWATCH — cerchio colore con check MD3
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? accentColor : _getBorderColor(),
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: accentColor.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child:
            isSelected
                ? Icon(
                  Icons.check_rounded,
                  color: _getContrastColor(color),
                  size: 22,
                )
                : null,
      ),
    );
  }

  Color _getBorderColor() {
    final luminance = color.computeLuminance();
    if (luminance > 0.9) return Colors.grey.shade300;
    if (luminance < 0.1) return Colors.grey.shade600;
    return Colors.transparent;
  }

  Color _getContrastColor(Color bg) {
    return bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
  }
}
