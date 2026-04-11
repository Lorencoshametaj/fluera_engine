// ============================================================================
// 📋 CANVAS CREATION OPTIONS — SDK API for canvas initialization
//
// Provides a type-safe enum for all supported paper types and a model
// class for canvas creation parameters.
// ============================================================================

import 'package:flutter/material.dart';

/// All supported paper/background pattern types.
///
/// Each value maps to a storage key used by [BackgroundPainter] and
/// [PaperPatternPainter] for rendering.
///
/// Usage:
/// ```dart
/// final options = CanvasCreationOptions(
///   title: 'Math — Integrals',
///   paperType: CanvasPaperType.grid5mm,
///   backgroundColor: Color(0xFFFFFBF0), // cream
/// );
/// await storageAdapter.createCanvas(options);
/// ```
enum CanvasPaperType {
  // ── Basic ──────────────────────────────────────────────────────────────────
  blank(
    storageKey: 'blank',
    label: 'Blank',
    icon: Icons.crop_landscape_rounded,
    category: PaperCategory.basic,
  ),
  lines(
    storageKey: 'lines',
    label: 'Lined',
    icon: Icons.horizontal_rule_rounded,
    category: PaperCategory.ruled,
  ),
  linesNarrow(
    storageKey: 'lines_narrow',
    label: 'Narrow Lined',
    icon: Icons.density_small_rounded,
    category: PaperCategory.ruled,
  ),

  // ── Grid ───────────────────────────────────────────────────────────────────
  grid5mm(
    storageKey: 'grid_5mm',
    label: 'Grid 5mm',
    icon: Icons.grid_4x4_rounded,
    category: PaperCategory.grid,
  ),
  grid1cm(
    storageKey: 'grid_1cm',
    label: 'Grid 1cm',
    icon: Icons.grid_on_rounded,
    category: PaperCategory.grid,
  ),
  grid2cm(
    storageKey: 'grid_2cm',
    label: 'Grid 2cm',
    icon: Icons.grid_3x3_rounded,
    category: PaperCategory.grid,
  ),
  graph(
    storageKey: 'graph',
    label: 'Graph Paper',
    icon: Icons.border_all_rounded,
    category: PaperCategory.grid,
  ),

  // ── Dots ───────────────────────────────────────────────────────────────────
  dots(
    storageKey: 'dots',
    label: 'Dots',
    icon: Icons.grain_rounded,
    category: PaperCategory.dotted,
  ),
  dotsDense(
    storageKey: 'dots_dense',
    label: 'Dense Dots',
    icon: Icons.blur_on_rounded,
    category: PaperCategory.dotted,
  ),
  dotGrid(
    storageKey: 'dot_grid',
    label: 'Dot Grid',
    icon: Icons.apps_rounded,
    category: PaperCategory.dotted,
  ),

  // ── Special ────────────────────────────────────────────────────────────────
  hex(
    storageKey: 'hex',
    label: 'Hexagonal',
    icon: Icons.hexagon_rounded,
    category: PaperCategory.special,
  ),
  isometric(
    storageKey: 'isometric',
    label: 'Isometric',
    icon: Icons.change_history_rounded,
    category: PaperCategory.special,
  ),
  music(
    storageKey: 'music',
    label: 'Music Staff',
    icon: Icons.music_note_rounded,
    category: PaperCategory.special,
  ),
  cornell(
    storageKey: 'cornell',
    label: 'Cornell Notes',
    icon: Icons.vertical_split_rounded,
    category: PaperCategory.special,
  ),
  storyboard(
    storageKey: 'storyboard',
    label: 'Storyboard',
    icon: Icons.view_comfy_rounded,
    category: PaperCategory.special,
  ),
  planner(
    storageKey: 'planner',
    label: 'Planner',
    icon: Icons.calendar_view_week_rounded,
    category: PaperCategory.special,
  ),
  calligraphy(
    storageKey: 'calligraphy',
    label: 'Calligraphy',
    icon: Icons.edit_rounded,
    category: PaperCategory.special,
  );

  /// The string stored in [CanvasMetadata.paperType].
  final String storageKey;

  /// Human-readable label for UI display.
  final String label;

  /// Material icon for UI display.
  final IconData icon;

  /// Category for grouping in creation dialogs.
  final PaperCategory category;

  const CanvasPaperType({
    required this.storageKey,
    required this.label,
    required this.icon,
    required this.category,
  });

  /// Look up a [CanvasPaperType] from its [storageKey].
  ///
  /// Returns [blank] if not found.
  static CanvasPaperType fromStorageKey(String key) {
    return CanvasPaperType.values.firstWhere(
      (t) => t.storageKey == key,
      orElse: () => CanvasPaperType.blank,
    );
  }
}

/// Category for grouping paper types in the creation UI.
enum PaperCategory {
  basic('Basic'),
  ruled('Ruled'),
  grid('Grid'),
  dotted('Dotted'),
  special('Special');

  final String label;
  const PaperCategory(this.label);
}

/// Preset background colors for canvas creation.
///
/// Each preset has a name, color value, and whether it's a dark theme.
class CanvasBackgroundPreset {
  final String name;
  final Color color;
  final bool isDark;

  const CanvasBackgroundPreset({
    required this.name,
    required this.color,
    this.isDark = false,
  });

  /// Standard presets covering common use cases.
  static const List<CanvasBackgroundPreset> defaults = [
    CanvasBackgroundPreset(name: 'White', color: Color(0xFFFFFFFF)),
    CanvasBackgroundPreset(name: 'Cream', color: Color(0xFFFFFBF0)),
    CanvasBackgroundPreset(name: 'Sepia', color: Color(0xFFF5E6CC)),
    CanvasBackgroundPreset(name: 'Light Gray', color: Color(0xFFF0F0F0)),
    CanvasBackgroundPreset(name: 'Light Blue', color: Color(0xFFE8F0FE)),
    CanvasBackgroundPreset(name: 'Light Green', color: Color(0xFFE6F4EA)),
    CanvasBackgroundPreset(name: 'Light Yellow', color: Color(0xFFFFF9E6)),
    CanvasBackgroundPreset(
      name: 'Dark',
      color: Color(0xFF1E1E1E),
      isDark: true,
    ),
  ];
}

/// Options for creating a new canvas via [FlueraStorageAdapter.createCanvas].
///
/// Example:
/// ```dart
/// final options = CanvasCreationOptions(
///   title: 'Physics — Wave Equations',
///   paperType: CanvasPaperType.grid5mm,
///   backgroundColor: CanvasBackgroundPreset.defaults[1].color, // Cream
/// );
///
/// final canvasId = await storage.createCanvas(options);
/// ```
class CanvasCreationOptions {
  /// Canvas title (null = untitled).
  final String? title;

  /// Paper/pattern type.
  final CanvasPaperType paperType;

  /// Background color.
  final Color backgroundColor;

  /// Optional pre-defined canvas ID. If null, auto-generated.
  final String? canvasId;

  /// Optional folder ID to create the canvas in.
  final String? folderId;

  /// Optional list of initial section names to pre-create on the canvas.
  ///
  /// When non-empty, the storage adapter will create [SectionNode] objects
  /// at A4 Portrait size (595 × 842), arranged vertically with 80px gap.
  ///
  /// Example:
  /// ```dart
  /// CanvasCreationOptions(
  ///   title: 'Fisica I',
  ///   initialSections: ['Cinematica', 'Dinamica', 'Termodinamica'],
  /// )
  /// ```
  final List<String> initialSections;

  const CanvasCreationOptions({
    this.title,
    this.paperType = CanvasPaperType.blank,
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.canvasId,
    this.folderId,
    this.initialSections = const [],
  });

  /// Generate a canvas ID based on current timestamp.
  String resolveCanvasId() =>
      canvasId ?? 'canvas_${DateTime.now().millisecondsSinceEpoch}';
}
