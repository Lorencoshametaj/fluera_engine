/// 📐 GRID LAYOUT SOLVER — CSS-like grid with auto-placement.
///
/// Places children on a 2D grid defined by column and row tracks.
/// Supports fractional (`fr`) units, fixed pixel sizes, and auto-placement.
///
/// ```dart
/// final result = GridLayoutSolver.solve(
///   config: GridLayoutConfig(
///     columns: [TrackDefinition.fr(1), TrackDefinition.fr(2)],
///     rows: [TrackDefinition.fixed(60), TrackDefinition.fr(1)],
///     columnGap: 8,
///     rowGap: 8,
///   ),
///   containerSize: Size(600, 400),
///   children: [
///     GridChild(), // auto-placed at (0,0)
///     GridChild(column: 1, row: 1), // explicit placement
///   ],
/// );
/// ```
library;

import 'dart:ui';
import 'dart:math' as math;

// =============================================================================
// TRACK DEFINITION
// =============================================================================

/// Defines the size of a grid column or row.
class TrackDefinition {
  /// Fixed pixel size (null if using fr).
  final double? fixedSize;

  /// Fractional unit (like CSS `fr`). Null if using fixed.
  final double? frFraction;

  /// Minimum size constraint.
  final double minSize;

  /// Maximum size constraint (null = unbounded).
  final double? maxSize;

  const TrackDefinition._({
    this.fixedSize,
    this.frFraction,
    this.minSize = 0,
    this.maxSize,
  });

  /// Fixed pixel size track.
  const TrackDefinition.fixed(double size)
    : fixedSize = size,
      frFraction = null,
      minSize = size,
      maxSize = size;

  /// Fractional unit track (like CSS `1fr`, `2fr`).
  const TrackDefinition.fr(double fraction)
    : fixedSize = null,
      frFraction = fraction,
      minSize = 0,
      maxSize = null;

  /// Auto-sized track with min/max constraints.
  const TrackDefinition.minmax(double min, double max)
    : fixedSize = null,
      frFraction = null,
      minSize = min,
      maxSize = max;

  /// Whether this track uses fractional sizing.
  bool get isFr => frFraction != null;

  /// Whether this track has a fixed size.
  bool get isFixed => fixedSize != null;

  Map<String, dynamic> toJson() => {
    if (fixedSize != null) 'fixedSize': fixedSize,
    if (frFraction != null) 'fr': frFraction,
    'minSize': minSize,
    if (maxSize != null) 'maxSize': maxSize,
  };

  @override
  String toString() {
    if (isFixed) return '${fixedSize}px';
    if (isFr) return '${frFraction}fr';
    return 'minmax($minSize, $maxSize)';
  }
}

// =============================================================================
// GRID AUTO FLOW
// =============================================================================

/// How auto-placed children fill the grid.
enum GridAutoFlow {
  /// Fill row by row (left to right, then next row).
  rowFirst,

  /// Fill column by column (top to bottom, then next column).
  columnFirst,
}

// =============================================================================
// GRID LAYOUT CONFIG
// =============================================================================

/// Configuration for a CSS-like grid layout.
class GridLayoutConfig {
  /// Column track definitions.
  final List<TrackDefinition> columns;

  /// Row track definitions.
  final List<TrackDefinition> rows;

  /// Gap between columns in pixels.
  final double columnGap;

  /// Gap between rows in pixels.
  final double rowGap;

  /// Auto-placement flow direction.
  final GridAutoFlow autoFlow;

  const GridLayoutConfig({
    required this.columns,
    required this.rows,
    this.columnGap = 0,
    this.rowGap = 0,
    this.autoFlow = GridAutoFlow.rowFirst,
  });

  /// Total number of cells.
  int get cellCount => columns.length * rows.length;

  Map<String, dynamic> toJson() => {
    'columns': columns.map((t) => t.toJson()).toList(),
    'rows': rows.map((t) => t.toJson()).toList(),
    'columnGap': columnGap,
    'rowGap': rowGap,
    'autoFlow': autoFlow.name,
  };

  @override
  String toString() =>
      'GridLayoutConfig(${columns.length}×${rows.length}, '
      'gaps=$columnGap/$rowGap)';
}

// =============================================================================
// GRID CHILD
// =============================================================================

/// Input: a child to be placed on the grid.
class GridChild {
  /// Explicit column placement (null = auto-place).
  final int? column;

  /// Explicit row placement (null = auto-place).
  final int? row;

  /// Number of columns this child spans.
  final int columnSpan;

  /// Number of rows this child spans.
  final int rowSpan;

  const GridChild({
    this.column,
    this.row,
    this.columnSpan = 1,
    this.rowSpan = 1,
  });

  @override
  String toString() =>
      'GridChild(col=$column, row=$row, span=${columnSpan}x$rowSpan)';
}

// =============================================================================
// GRID LAYOUT RESULT
// =============================================================================

/// Output: computed rectangles for each child on the grid.
class GridLayoutResult {
  /// Position and size for each child (same order as input).
  final List<Rect> childRects;

  /// Resolved column widths.
  final List<double> columnWidths;

  /// Resolved row heights.
  final List<double> rowHeights;

  /// Total content size.
  final Size contentSize;

  const GridLayoutResult({
    required this.childRects,
    required this.columnWidths,
    required this.rowHeights,
    required this.contentSize,
  });

  @override
  String toString() =>
      'GridLayoutResult(children=${childRects.length}, '
      'grid=${columnWidths.length}×${rowHeights.length})';
}

// =============================================================================
// GRID LAYOUT SOLVER
// =============================================================================

/// CSS-like grid layout solver with auto-placement.
class GridLayoutSolver {
  const GridLayoutSolver._();

  /// Solve grid layout for the given config, container, and children.
  static GridLayoutResult solve({
    required GridLayoutConfig config,
    required Size containerSize,
    required List<GridChild> children,
  }) {
    if (config.columns.isEmpty || config.rows.isEmpty) {
      return GridLayoutResult(
        childRects: List.filled(children.length, Rect.zero),
        columnWidths: const [],
        rowHeights: const [],
        contentSize: Size.zero,
      );
    }

    // 1. Resolve track sizes
    final colWidths = _resolveTracks(
      config.columns,
      containerSize.width,
      config.columnGap,
    );
    final rowHeights = _resolveTracks(
      config.rows,
      containerSize.height,
      config.rowGap,
    );

    // 2. Compute track positions (cumulative)
    final colPositions = _trackPositions(colWidths, config.columnGap);
    final rowPositions = _trackPositions(rowHeights, config.rowGap);

    // 3. Place children
    final occupied = <String>{};
    final rects = <Rect>[];
    int autoCol = 0, autoRow = 0;

    for (final child in children) {
      int col, row;

      if (child.column != null && child.row != null) {
        col = child.column!;
        row = child.row!;
      } else {
        // Auto-place
        final pos = _findNextFree(
          occupied,
          autoCol,
          autoRow,
          child.columnSpan,
          child.rowSpan,
          config.columns.length,
          config.rows.length,
          config.autoFlow,
        );
        col = pos.$1;
        row = pos.$2;
        // Advance cursor
        if (config.autoFlow == GridAutoFlow.rowFirst) {
          autoCol = col + child.columnSpan;
          autoRow = row;
          if (autoCol >= config.columns.length) {
            autoCol = 0;
            autoRow++;
          }
        } else {
          autoRow = row + child.rowSpan;
          autoCol = col;
          if (autoRow >= config.rows.length) {
            autoRow = 0;
            autoCol++;
          }
        }
      }

      // Mark cells as occupied
      for (int c = col; c < col + child.columnSpan; c++) {
        for (int r = row; r < row + child.rowSpan; r++) {
          occupied.add('$c,$r');
        }
      }

      // Compute rect from track positions
      if (col < colPositions.length && row < rowPositions.length) {
        final endCol = math.min(
          col + child.columnSpan - 1,
          colWidths.length - 1,
        );
        final endRow = math.min(row + child.rowSpan - 1, rowHeights.length - 1);

        final x = colPositions[col];
        final y = rowPositions[row];
        final w = colPositions[endCol] + colWidths[endCol] - x;
        final h = rowPositions[endRow] + rowHeights[endRow] - y;

        rects.add(Rect.fromLTWH(x, y, w, h));
      } else {
        rects.add(Rect.zero);
      }
    }

    // Content size
    final totalWidth =
        colWidths.isEmpty ? 0.0 : colPositions.last + colWidths.last;
    final totalHeight =
        rowHeights.isEmpty ? 0.0 : rowPositions.last + rowHeights.last;

    return GridLayoutResult(
      childRects: rects,
      columnWidths: colWidths,
      rowHeights: rowHeights,
      contentSize: Size(totalWidth, totalHeight),
    );
  }

  /// Resolve track sizes from definitions, distributing fr units.
  static List<double> _resolveTracks(
    List<TrackDefinition> tracks,
    double available,
    double gap,
  ) {
    final sizes = List<double>.filled(tracks.length, 0);
    final totalGap = gap * math.max(0, tracks.length - 1);
    double fixedTotal = 0;
    double frTotal = 0;

    for (int i = 0; i < tracks.length; i++) {
      if (tracks[i].isFixed) {
        sizes[i] = tracks[i].fixedSize!;
        fixedTotal += sizes[i];
      } else if (tracks[i].isFr) {
        frTotal += tracks[i].frFraction!;
      } else {
        // minmax — start at min
        sizes[i] = tracks[i].minSize;
        fixedTotal += sizes[i];
      }
    }

    // Distribute remaining space to fr tracks
    final frSpace = math.max(0, available - fixedTotal - totalGap);
    if (frTotal > 0) {
      for (int i = 0; i < tracks.length; i++) {
        if (tracks[i].isFr) {
          sizes[i] = (tracks[i].frFraction! / frTotal) * frSpace;
          // Apply min/max constraints
          sizes[i] = math.max(sizes[i], tracks[i].minSize);
          if (tracks[i].maxSize != null) {
            sizes[i] = math.min(sizes[i], tracks[i].maxSize!);
          }
        }
      }
    }

    return sizes;
  }

  /// Compute cumulative positions from sizes and gap.
  static List<double> _trackPositions(List<double> sizes, double gap) {
    final positions = List<double>.filled(sizes.length, 0);
    double pos = 0;
    for (int i = 0; i < sizes.length; i++) {
      positions[i] = pos;
      pos += sizes[i] + gap;
    }
    return positions;
  }

  /// Find next free cell for auto-placement.
  static (int, int) _findNextFree(
    Set<String> occupied,
    int startCol,
    int startRow,
    int colSpan,
    int rowSpan,
    int totalCols,
    int totalRows,
    GridAutoFlow flow,
  ) {
    if (flow == GridAutoFlow.rowFirst) {
      for (int r = startRow; r < totalRows; r++) {
        final colStart = (r == startRow) ? startCol : 0;
        for (int c = colStart; c <= totalCols - colSpan; c++) {
          if (_canPlace(
            occupied,
            c,
            r,
            colSpan,
            rowSpan,
            totalCols,
            totalRows,
          )) {
            return (c, r);
          }
        }
      }
    } else {
      for (int c = startCol; c < totalCols; c++) {
        final rowStart = (c == startCol) ? startRow : 0;
        for (int r = rowStart; r <= totalRows - rowSpan; r++) {
          if (_canPlace(
            occupied,
            c,
            r,
            colSpan,
            rowSpan,
            totalCols,
            totalRows,
          )) {
            return (c, r);
          }
        }
      }
    }
    // Fallback: place at 0,0 if grid is full
    return (0, 0);
  }

  /// Check if a span can be placed at (col, row).
  static bool _canPlace(
    Set<String> occupied,
    int col,
    int row,
    int colSpan,
    int rowSpan,
    int totalCols,
    int totalRows,
  ) {
    if (col + colSpan > totalCols || row + rowSpan > totalRows) return false;
    for (int c = col; c < col + colSpan; c++) {
      for (int r = row; r < row + rowSpan; r++) {
        if (occupied.contains('$c,$r')) return false;
      }
    }
    return true;
  }
}
