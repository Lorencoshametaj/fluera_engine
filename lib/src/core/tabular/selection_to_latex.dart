import 'cell_address.dart';
import 'cell_node.dart';
import 'cell_value.dart';
import '../nodes/tabular_node.dart';

/// 📊 Converts a selected cell range from a [TabularNode] into LaTeX
/// `\begin{tabular}...\end{tabular}` source code.
///
/// Supports:
/// - Header row formatting (`\textbf{}`)
/// - Booktabs style (`\toprule`, `\midrule`, `\bottomrule`)
/// - Merged cells: `\multicolumn`, `\multirow`, combined 2D merges
/// - `\cline` partial rules for row-spanning merges
/// - LaTeX special character escaping
///
/// ## Usage
///
/// ```dart
/// final latex = SelectionToLatex.convert(tabularNode, range);
/// // → \begin{tabular}{|c|c|c|} ... \end{tabular}
///
/// final booktabs = SelectionToLatex.convert(
///   tabularNode, range,
///   includeHeaders: true,
///   useBooktabs: true,
/// );
/// ```
class SelectionToLatex {
  // Characters that must be escaped in LaTeX.
  static const _specialChars = <String, String>{
    r'\': r'\textbackslash{}',
    '%': r'\%',
    '&': r'\&',
    '_': r'\_',
    '#': r'\#',
    r'$': r'\$',
    '{': r'\{',
    '}': r'\}',
    '~': r'\textasciitilde{}',
    '^': r'\textasciicircum{}',
  };

  /// Convert a [CellRange] selection from a [TabularNode] into LaTeX code.
  ///
  /// Parameters:
  /// - [node] — the tabular node containing the data.
  /// - [range] — the cell range to export (normalized automatically).
  /// - [includeHeaders] — if `true`, wraps the first row in `\textbf{}`.
  /// - [useBooktabs] — if `true`, uses `\toprule`/`\midrule`/`\bottomrule`
  ///   instead of `\hline`.
  /// - [alignment] — override column alignment string (e.g. `"lcr"`).
  ///   Defaults to centered (`c`) for every column.
  static String convert(
    TabularNode node,
    CellRange range, {
    bool includeHeaders = false,
    bool useBooktabs = false,
    String? alignment,
  }) {
    var minCol = range.startColumn;
    var maxCol = range.endColumn;
    var minRow = range.startRow;
    var maxRow = range.endRow;

    // Auto-expand range to include all merge regions that intersect.
    bool expanded = true;
    while (expanded) {
      expanded = false;
      for (final region in node.mergeManager.regions) {
        if (region.endColumn >= minCol &&
            region.startColumn <= maxCol &&
            region.endRow >= minRow &&
            region.startRow <= maxRow) {
          if (region.endRow > maxRow) {
            maxRow = region.endRow;
            expanded = true;
          }
          if (region.endColumn > maxCol) {
            maxCol = region.endColumn;
            expanded = true;
          }
        }
      }
    }

    final colCount = maxCol - minCol + 1;

    // Build alignment spec.
    final rawAlign = alignment ?? List.filled(colCount, 'c').join();
    final alignChars = rawAlign.split('');

    // Collect all merge regions that intersect the selection.
    final merges = <CellRange>[];
    for (final region in node.mergeManager.regions) {
      if (region.endColumn >= minCol &&
          region.startColumn <= maxCol &&
          region.endRow >= minRow &&
          region.startRow <= maxRow) {
        merges.add(region);
      }
    }

    // Track which cells are "occupied" by a vertically continuing merge
    // (i.e. the master was in a previous row, so this row needs an empty
    // placeholder to keep the column count correct).
    // Key: "col:row", value: true if this cell should emit an empty slot.
    final vertContinuation = <String, bool>{};
    for (final m in merges) {
      for (int r = m.startRow + 1; r <= m.endRow; r++) {
        for (int c = m.startColumn; c <= m.endColumn; c++) {
          if (r >= minRow && r <= maxRow && c >= minCol && c <= maxCol) {
            vertContinuation['$c:$r'] = true;
          }
        }
      }
    }

    final needsMultirow = merges.any((m) => m.endRow > m.startRow);

    final buf = StringBuffer();

    // Helper to get borders for a cell.
    CellBorders _borders(int c, int r) {
      return node.model.getCell(CellAddress(c, r))?.format?.borders ??
          CellBorders.all;
    }

    // Build border-aware column spec.
    // E.g. |c|c|c| when all borders, or c c c when none.
    if (useBooktabs) {
      buf.writeln('\\begin{tabular}{${alignChars.join(' ')}}');
      buf.writeln('\\toprule');
    } else {
      final colSpec = StringBuffer();
      for (int i = 0; i < colCount; i++) {
        final c = minCol + i;
        final leftBorder = _borders(c, minRow).left;
        // Left pipe: for first col, check its .left; for others, check
        // previous col's .right OR this col's .left.
        if (i == 0) {
          if (leftBorder) colSpec.write('|');
        } else {
          final prevRight = _borders(c - 1, minRow).right;
          if (prevRight || leftBorder) colSpec.write('|');
        }
        colSpec.write(alignChars[i]);
      }
      // Right pipe of last column.
      if (_borders(maxCol, minRow).right) colSpec.write('|');
      buf.writeln('\\begin{tabular}{$colSpec}');
      // Top rule: check if first row has .top borders.
      final hasTopBorder = List.generate(
        colCount,
        (i) => _borders(minCol + i, minRow).top,
      ).any((b) => b);
      if (hasTopBorder) buf.writeln('\\hline');
    }

    // Rows.
    for (int r = minRow; r <= maxRow; r++) {
      final isHeader = includeHeaders && r == minRow;
      final cells = <String>[];

      int col = minCol;
      while (col <= maxCol) {
        final addr = CellAddress(col, r);

        // Check if this cell is a vertical continuation of a merge from above.
        if (vertContinuation['$col:$r'] == true) {
          // For multicolumn merges continuing vertically, we must emit
          // the right number of empty columns.
          final merge = _findMerge(merges, col, r);
          if (merge != null) {
            final colSpan = merge.endColumn - merge.startColumn + 1;
            if (colSpan > 1) {
              final lB = _borders(merge.startColumn, r).left ? '|' : '';
              final rB = _borders(merge.endColumn, r).right ? '|' : '';
              final colAlign = useBooktabs ? 'c' : '${lB}c$rB';
              cells.add('\\multicolumn{$colSpan}{$colAlign}{}');
            } else {
              cells.add('');
            }
            col = merge.endColumn + 1;
          } else {
            cells.add('');
            col++;
          }
          continue;
        }

        // Check if this cell is the master of a merge region.
        final merge = _findMasterMerge(merges, col, r);
        if (merge != null) {
          // Clamp spans to visible range.
          final clampedEndCol = merge.endColumn.clamp(minCol, maxCol);
          final clampedEndRow = merge.endRow.clamp(minRow, maxRow);
          final colSpan = clampedEndCol - merge.startColumn + 1;
          final rowSpan = clampedEndRow - merge.startRow + 1;

          String cellText = _getCellDisplay(node, addr);
          if (isHeader) cellText = '\\textbf{$cellText}';

          // Build the cell content with multirow/multicolumn.
          if (colSpan > 1 && rowSpan > 1) {
            // 2D merge: \multicolumn wrapping \multirow
            final lB = _borders(col, r).left ? '|' : '';
            final rB = _borders(clampedEndCol, r).right ? '|' : '';
            final colAlign = useBooktabs ? 'c' : '${lB}c$rB';
            cellText =
                '\\multicolumn{$colSpan}{$colAlign}'
                '{\\multirow{$rowSpan}{*}{$cellText}}';
          } else if (colSpan > 1) {
            // Horizontal-only merge.
            final lB = _borders(col, r).left ? '|' : '';
            final rB = _borders(clampedEndCol, r).right ? '|' : '';
            final colAlign = useBooktabs ? 'c' : '${lB}c$rB';
            cellText = '\\multicolumn{$colSpan}{$colAlign}{$cellText}';
          } else if (rowSpan > 1) {
            // Vertical-only merge.
            cellText = '\\multirow{$rowSpan}{*}{$cellText}';
          }

          cells.add(cellText);
          col = clampedEndCol + 1;
          continue;
        }

        // Normal cell.
        String cellText = _getCellDisplay(node, addr);
        if (isHeader) cellText = '\\textbf{$cellText}';
        cells.add(cellText);
        col++;
      }

      buf.writeln('${cells.join(' & ')} \\\\');

      // Row separator — use \cline for partial rules when merges or
      // borderless cells require skipping segments.
      if (r == maxRow) {
        // Last row: bottom rule (if cells have bottom borders).
        if (useBooktabs) {
          buf.writeln('\\bottomrule');
        } else {
          final hasBottom = List.generate(
            colCount,
            (i) => _borders(minCol + i, maxRow).bottom,
          ).any((b) => b);
          if (hasBottom) {
            // Check if ALL have bottom border → \hline, else cline.
            final allBottom = List.generate(
              colCount,
              (i) => _borders(minCol + i, maxRow).bottom,
            ).every((b) => b);
            if (allBottom) {
              buf.writeln('\\hline');
            } else {
              _writeBorderCline(buf, minCol, maxCol, maxRow, _borders);
            }
          }
        }
      } else if (isHeader) {
        buf.writeln(useBooktabs ? '\\midrule' : '\\hline');
      } else {
        // Determine if any merge region spans from this row into the next.
        final clineSegments = _computeClineSegments(
          merges,
          r,
          minCol,
          maxCol,
          colCount,
          node,
        );
        if (clineSegments == null) {
          // No merges cross — but check cell borders.
          final allBottom = List.generate(
            colCount,
            (i) => _borders(minCol + i, r).bottom,
          ).every((b) => b);
          if (allBottom) {
            if (!useBooktabs) buf.writeln('\\hline');
          } else {
            final anyBottom = List.generate(
              colCount,
              (i) => _borders(minCol + i, r).bottom,
            ).any((b) => b);
            if (anyBottom) {
              _writeBorderCline(buf, minCol, maxCol, r, _borders);
            }
            // If no bottom borders at all → skip rule.
          }
        } else if (clineSegments.isNotEmpty) {
          // Partial rules via \cline.
          for (final seg in clineSegments) {
            buf.writeln('\\cline{${seg.$1}-${seg.$2}}');
          }
        }
        // If clineSegments is empty → no rules at all (entire row boundary
        // is covered by vertical merges).
      }
    }

    buf.write('\\end{tabular}');
    return buf.toString();
  }

  /// Find a merge region whose master cell is at (col, row).
  static CellRange? _findMasterMerge(List<CellRange> merges, int col, int row) {
    for (final m in merges) {
      if (m.startColumn == col && m.startRow == row) return m;
    }
    return null;
  }

  /// Find any merge region that contains (col, row).
  static CellRange? _findMerge(List<CellRange> merges, int col, int row) {
    for (final m in merges) {
      if (col >= m.startColumn &&
          col <= m.endColumn &&
          row >= m.startRow &&
          row <= m.endRow) {
        return m;
      }
    }
    return null;
  }

  /// Compute `\cline` segments for the boundary after [row].
  ///
  /// Returns `null` if the full boundary is open (no merges cross it) →
  ///   caller should emit `\hline`.
  /// Returns an empty list if the entire boundary is blocked by merges.
  /// Returns a list of `(startCol1-indexed, endCol1-indexed)` for partial rules.
  static List<(int, int)>? _computeClineSegments(
    List<CellRange> merges,
    int row,
    int minCol,
    int maxCol,
    int colCount,
    TabularNode node,
  ) {
    // Collect columns blocked by vertical merges or borderless cells.
    final blocked = List.filled(colCount, false);
    bool anyBlocked = false;
    for (final m in merges) {
      if (m.startRow <= row && m.endRow > row) {
        for (int c = m.startColumn; c <= m.endColumn; c++) {
          final idx = c - minCol;
          if (idx >= 0 && idx < colCount) {
            blocked[idx] = true;
            anyBlocked = true;
          }
        }
      }
    }
    // Also block columns where cells have no bottom border.
    for (int i = 0; i < colCount; i++) {
      final c = minCol + i;
      final borders = node.model.getCell(CellAddress(c, row))?.format?.borders;
      if (borders != null && !borders.bottom) {
        blocked[i] = true;
        anyBlocked = true;
      }
    }

    if (!anyBlocked) return null; // Full \hline.

    // Build segments of non-blocked columns.
    final segments = <(int, int)>[];
    int? segStart;
    for (int i = 0; i < colCount; i++) {
      if (!blocked[i]) {
        segStart ??= i;
      } else {
        if (segStart != null) {
          // 1-indexed columns for \cline.
          segments.add((segStart + 1, i));
          segStart = null;
        }
      }
    }
    if (segStart != null) {
      segments.add((segStart + 1, colCount));
    }
    return segments;
  }

  /// Get the display text for a cell, with LaTeX special character escaping.
  static String _getCellDisplay(TabularNode node, CellAddress addr) {
    final val = node.evaluator.getComputedValue(addr);
    if (val is EmptyValue) return '';
    return _escapeLatex(val.displayString);
  }

  /// Escape LaTeX special characters in a string.
  static String _escapeLatex(String text) {
    if (text.isEmpty) return text;

    final buf = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      final escaped = _specialChars[ch];
      if (escaped != null) {
        buf.write(escaped);
      } else {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  /// Write \cline segments for columns where cells have bottom borders.
  static void _writeBorderCline(
    StringBuffer buf,
    int minCol,
    int maxCol,
    int row,
    CellBorders Function(int col, int row) getBorders,
  ) {
    final colCount = maxCol - minCol + 1;
    int? segStart;
    for (int i = 0; i < colCount; i++) {
      final hasBorder = getBorders(minCol + i, row).bottom;
      if (hasBorder) {
        segStart ??= i;
      } else {
        if (segStart != null) {
          buf.writeln('\\cline{${segStart + 1}-$i}');
          segStart = null;
        }
      }
    }
    if (segStart != null) {
      buf.writeln('\\cline{${segStart + 1}-$colCount}');
    }
  }
}
