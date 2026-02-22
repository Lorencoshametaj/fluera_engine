/// 📐 LAYOUT GRID — Overlay grids for frame alignment and spacing.
///
/// Supports rows, columns, and uniform grids (Figma-compatible).
///
/// ```dart
/// final grid = LayoutGrid(
///   type: LayoutGridType.columns,
///   count: 12,
///   gutterSize: 20,
///   margin: 40,
///   color: Color(0x33FF0000),
/// );
/// frame.layoutGrids.add(grid);
/// ```
library;

import 'dart:ui' as ui;

// =============================================================================
// LAYOUT GRID TYPE
// =============================================================================

/// The type of layout grid.
enum LayoutGridType {
  /// Vertical column grid (e.g., 12-column).
  columns,

  /// Horizontal row grid.
  rows,

  /// Uniform square grid (pixel grid).
  grid,
}

/// How columns/rows are distributed within the frame.
enum LayoutGridAlignment {
  /// Aligned to the start (left or top).
  min,

  /// Centered within the frame.
  center,

  /// Aligned to the end (right or bottom).
  max,

  /// Stretched to fill the frame.
  stretch,
}

// =============================================================================
// LAYOUT GRID
// =============================================================================

/// A single layout grid configuration for a frame.
///
/// Frames can have multiple grids (e.g., a 12-column grid + an 8px baseline).
class LayoutGrid {
  /// Unique ID for this grid.
  final String id;

  /// Grid type: columns, rows, or uniform grid.
  LayoutGridType type;

  /// Number of columns/rows (ignored for uniform grid).
  int count;

  /// Size of each cell in a uniform grid (px). Ignored for columns/rows.
  double cellSize;

  /// Gutter (gap) between columns/rows.
  double gutterSize;

  /// Margin on both sides (left/right for columns, top/bottom for rows).
  double margin;

  /// Alignment of columns/rows within the frame.
  LayoutGridAlignment alignment;

  /// Overlay color for the grid.
  ui.Color color;

  /// Whether the grid is visible in the editor.
  bool isVisible;

  LayoutGrid({
    required this.id,
    this.type = LayoutGridType.columns,
    this.count = 12,
    this.cellSize = 8,
    this.gutterSize = 20,
    this.margin = 0,
    this.alignment = LayoutGridAlignment.stretch,
    this.color = const ui.Color(0x33FF0000),
    this.isVisible = true,
  });

  // ---------------------------------------------------------------------------
  // Computed values
  // ---------------------------------------------------------------------------

  /// Calculate column/row widths for a given frame dimension.
  ///
  /// Returns a list of (offset, width) pairs for each column/row.
  List<({double offset, double size})> computeCells(double frameDimension) {
    if (type == LayoutGridType.grid) {
      return _computeUniformGrid(frameDimension);
    }

    if (count <= 0) return [];

    final totalGutters = (count - 1) * gutterSize;
    final totalMargin = margin * 2;
    final available = frameDimension - totalMargin - totalGutters;
    final cellWidth = available / count;

    if (cellWidth <= 0) return [];

    double startOffset;
    switch (alignment) {
      case LayoutGridAlignment.min:
      case LayoutGridAlignment.stretch:
        startOffset = margin;
      case LayoutGridAlignment.center:
        final totalWidth = count * cellWidth + totalGutters;
        startOffset = (frameDimension - totalWidth) / 2;
      case LayoutGridAlignment.max:
        final totalWidth = count * cellWidth + totalGutters;
        startOffset = frameDimension - totalWidth - margin;
    }

    final cells = <({double offset, double size})>[];
    for (int i = 0; i < count; i++) {
      cells.add((
        offset: startOffset + i * (cellWidth + gutterSize),
        size: cellWidth,
      ));
    }
    return cells;
  }

  List<({double offset, double size})> _computeUniformGrid(double dimension) {
    if (cellSize <= 0) return [];
    final cells = <({double offset, double size})>[];
    double pos = 0;
    while (pos < dimension) {
      cells.add((offset: pos, size: cellSize));
      pos += cellSize;
    }
    return cells;
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'count': count,
    'cellSize': cellSize,
    'gutterSize': gutterSize,
    'margin': margin,
    'alignment': alignment.name,
    'color': color.toARGB32(),
    'isVisible': isVisible,
  };

  factory LayoutGrid.fromJson(Map<String, dynamic> json) => LayoutGrid(
    id: json['id'] as String,
    type: LayoutGridType.values.byName(json['type'] as String),
    count: json['count'] as int? ?? 12,
    cellSize: (json['cellSize'] as num?)?.toDouble() ?? 8,
    gutterSize: (json['gutterSize'] as num?)?.toDouble() ?? 20,
    margin: (json['margin'] as num?)?.toDouble() ?? 0,
    alignment: LayoutGridAlignment.values.byName(
      json['alignment'] as String? ?? 'stretch',
    ),
    color: ui.Color(json['color'] as int? ?? 0x33FF0000),
    isVisible: json['isVisible'] as bool? ?? true,
  );

  LayoutGrid copyWith({
    LayoutGridType? type,
    int? count,
    double? cellSize,
    double? gutterSize,
    double? margin,
    LayoutGridAlignment? alignment,
    ui.Color? color,
    bool? isVisible,
  }) => LayoutGrid(
    id: id,
    type: type ?? this.type,
    count: count ?? this.count,
    cellSize: cellSize ?? this.cellSize,
    gutterSize: gutterSize ?? this.gutterSize,
    margin: margin ?? this.margin,
    alignment: alignment ?? this.alignment,
    color: color ?? this.color,
    isVisible: isVisible ?? this.isVisible,
  );
}

// =============================================================================
// LAYOUT GRID SET — Convenience for multiple grids on a frame
// =============================================================================

/// Manages a collection of layout grids for a frame.
class LayoutGridSet {
  final List<LayoutGrid> _grids = [];

  /// Read-only view of grids.
  List<LayoutGrid> get grids => List.unmodifiable(_grids);

  /// Number of grids.
  int get length => _grids.length;

  /// Add a grid.
  void add(LayoutGrid grid) => _grids.add(grid);

  /// Remove a grid by ID.
  bool remove(String gridId) {
    final len = _grids.length;
    _grids.removeWhere((g) => g.id == gridId);
    return _grids.length < len;
  }

  /// Get a grid by ID.
  LayoutGrid? find(String gridId) {
    for (final g in _grids) {
      if (g.id == gridId) return g;
    }
    return null;
  }

  /// Toggle visibility of all grids.
  void toggleAll(bool visible) {
    for (final g in _grids) {
      g.isVisible = visible;
    }
  }

  Map<String, dynamic> toJson() => {
    'grids': _grids.map((g) => g.toJson()).toList(),
  };

  static LayoutGridSet fromJson(Map<String, dynamic> json) {
    final set = LayoutGridSet();
    for (final g in (json['grids'] as List<dynamic>? ?? [])) {
      set._grids.add(LayoutGrid.fromJson(g as Map<String, dynamic>));
    }
    return set;
  }
}
