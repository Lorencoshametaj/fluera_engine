import 'cell_address.dart';
import 'cell_node.dart';
import 'cell_number_formatter.dart';
import 'cell_value.dart';
import 'formula_to_latex.dart';
import 'merge_region_manager.dart';
import 'spreadsheet_evaluator.dart';
import 'tikz_chart_generator.dart';

/// 📊 Reactive report template engine for LaTeX generation.
///
/// Converts a template string containing placeholders into fully
/// resolved LaTeX, pulling live data from a [SpreadsheetEvaluator].
///
/// ## Template syntax
///
/// ### Value substitution
/// ```
/// Revenue: \EUR{{B2}}         → Revenue: \EUR{1000}
/// Margin: {D2:0.00%}          → Margin: 23.50%
/// Total: {SUM(B2:B5):#,##0}   → Total: 4,200
/// ```
///
/// ### Auto-tabular generation
/// ```
/// {TABLE(A1:D5)}
/// {TABLE(A1:D5, headers=true, align=lcrr)}
/// ```
///
/// ### Conditional sections
/// ```
/// {IF(A1>0)}Profit: \EUR{{A1}}{ELSE}Loss: \EUR{{A1}}{ENDIF}
/// ```
///
/// ### Range iteration
/// ```
/// {FOR(row in A2:C10)}
///   {row.A} & {row.B} & {row.C} \\
/// {ENDFOR}
/// ```
///
/// ## Usage
///
/// ```dart
/// final template = LatexReportTemplate(evaluator);
/// final latex = template.render(r'''
///   Revenue Q1: \EUR{{B2}}, growth {C2}\%
///   {TABLE(A1:D5, headers=true)}
/// ''');
/// ```
class LatexReportTemplate {
  final SpreadsheetEvaluator _evaluator;
  final MergeRegionManager? _mergeManager;

  /// Separator used for range expansion (e.g. `{A1:A5}`).
  final String rangeSeparator;

  LatexReportTemplate(
    this._evaluator, {
    this.rangeSeparator = ', ',
    MergeRegionManager? mergeManager,
  }) : _mergeManager = mergeManager;

  // =========================================================================
  // Public API
  // =========================================================================

  /// Render a template string into resolved LaTeX.
  ///
  /// Processes directives in order:
  /// 1. `{FOR}...{ENDFOR}` loops
  /// 2. `{IF}...{ELSE}...{ENDIF}` conditionals
  /// 3. `{TABLE(...)}` auto-tabular
  /// 4. `{CHART(...)}` TikZ chart generation
  /// 5. `{FORMULA(...)}` formula-to-LaTeX translation
  /// 6. Value/range/aggregate placeholders
  String render(String template) {
    var result = template;
    result = _processForLoops(result);
    result = _processConditionals(result);
    result = _processTableDirectives(result);
    result = _processChartDirectives(result);
    result = _processFormulaDirectives(result);
    result = _processPlaceholders(result);
    return result;
  }

  // =========================================================================
  // FOR loops
  // =========================================================================

  static final RegExp _forPattern = RegExp(
    r'\{FOR\((\w+)\s+in\s+([A-Z]+\d+):([A-Z]+\d+)\)\}(.*?)\{ENDFOR\}',
    dotAll: true,
  );

  String _processForLoops(String template) {
    return template.replaceAllMapped(_forPattern, (match) {
      final varName = match.group(1)!;
      final start = CellAddress.fromLabel(match.group(2)!);
      final end = CellAddress.fromLabel(match.group(3)!);
      final body = match.group(4)!;

      final buf = StringBuffer();
      for (int row = start.row; row <= end.row; row++) {
        var rowResult = body;

        // Replace {varName.COL} references with cell values.
        final varPattern = RegExp('{$varName\\.([A-Z]+)}');
        rowResult = rowResult.replaceAllMapped(varPattern, (m) {
          final colLabel = m.group(1)!;
          // Parse column index from letter (e.g. 'A' → 0, 'B' → 1).
          final tempAddr = CellAddress.fromLabel('${colLabel}1');
          final addr = CellAddress(tempAddr.column, row);
          return _evaluator.getComputedValue(addr).displayString;
        });

        buf.write(rowResult);
      }

      return buf.toString();
    });
  }

  // =========================================================================
  // Conditionals
  // =========================================================================

  static final RegExp _ifPattern = RegExp(
    r'\{IF\(([^)]+)\)\}(.*?)(?:\{ELSE\}(.*?))?\{ENDIF\}',
    dotAll: true,
  );

  String _processConditionals(String template) {
    return template.replaceAllMapped(_ifPattern, (match) {
      final condition = match.group(1)!;
      final trueBranch = match.group(2)!;
      final falseBranch = match.group(3) ?? '';

      final result = _evaluateCondition(condition);
      return result ? trueBranch : falseBranch;
    });
  }

  /// Evaluate a simple condition like `A1>0`, `B2>=100`, `C3=5`.
  bool _evaluateCondition(String condition) {
    // Parse: CELL OPERATOR VALUE
    final condPattern = RegExp(r'([A-Z]+\d+)\s*(>=|<=|!=|>|<|=)\s*(.+)');
    final match = condPattern.firstMatch(condition.trim());
    if (match == null) return false;

    final addr = CellAddress.fromLabel(match.group(1)!);
    final op = match.group(2)!;
    final rightStr = match.group(3)!.trim();

    final leftVal = _evaluator.getComputedValue(addr);

    // Try numeric comparison.
    final leftNum = _toNum(leftVal);
    final rightNum = num.tryParse(rightStr);

    if (leftNum != null && rightNum != null) {
      return switch (op) {
        '>' => leftNum > rightNum,
        '<' => leftNum < rightNum,
        '>=' => leftNum >= rightNum,
        '<=' => leftNum <= rightNum,
        '=' => leftNum == rightNum,
        '!=' => leftNum != rightNum,
        _ => false,
      };
    }

    // Fall back to string comparison for = and !=.
    final leftStr = leftVal.displayString;
    return switch (op) {
      '=' => leftStr == rightStr,
      '!=' => leftStr != rightStr,
      _ => false,
    };
  }

  // =========================================================================
  // TABLE directive
  // =========================================================================

  static final RegExp _tablePattern = RegExp(
    r'\{TABLE\(([A-Z]+\d+):([A-Z]+\d+)(?:,\s*(.+?))?\)\}',
  );

  String _processTableDirectives(String template) {
    return template.replaceAllMapped(_tablePattern, (match) {
      final start = CellAddress.fromLabel(match.group(1)!);
      final end = CellAddress.fromLabel(match.group(2)!);
      final options = match.group(3);

      final opts = _parseTableOptions(options);
      return _generateTabular(start, end, opts);
    });
  }

  _TableOptions _parseTableOptions(String? raw) {
    bool headers = false;
    String? align;

    if (raw != null) {
      // Parse key=value pairs.
      final parts = raw.split(',');
      for (final part in parts) {
        final kv = part.trim().split('=');
        if (kv.length == 2) {
          final key = kv[0].trim().toLowerCase();
          final value = kv[1].trim();
          if (key == 'headers') headers = value.toLowerCase() == 'true';
          if (key == 'align') align = value;
        }
      }
    }

    return _TableOptions(headers: headers, align: align);
  }

  String _generateTabular(
    CellAddress start,
    CellAddress end,
    _TableOptions opts,
  ) {
    var minCol = start.column < end.column ? start.column : end.column;
    var maxCol = start.column > end.column ? start.column : end.column;
    var minRow = start.row < end.row ? start.row : end.row;
    var maxRow = start.row > end.row ? start.row : end.row;

    // Auto-expand range to include all merge regions that intersect.
    if (_mergeManager != null) {
      bool expanded = true;
      while (expanded) {
        expanded = false;
        for (final region in _mergeManager.regions) {
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
    }

    final colCount = maxCol - minCol + 1;

    // Build alignment spec.
    final alignSpec = opts.align ?? List.filled(colCount, 'c').join();
    final buf = StringBuffer();

    // Collect merge regions intersecting the selection.
    final merges = <CellRange>[];
    if (_mergeManager != null) {
      for (final region in _mergeManager.regions) {
        if (region.endColumn >= minCol &&
            region.startColumn <= maxCol &&
            region.endRow >= minRow &&
            region.startRow <= maxRow) {
          merges.add(region);
        }
      }
    }

    // Track vertical continuation cells (non-master cells in a row-span).
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
    if (needsMultirow) {
      // Note: \multirow requires \usepackage{multirow} in the preamble.
      // We don't emit the \usepackage here since this is a fragment.
    }

    // Helper to get borders for a cell.
    CellBorders _borders(int c, int r) {
      return _evaluator.model.getCell(CellAddress(c, r))?.format?.borders ??
          CellBorders.all;
    }

    // Build border-aware column spec.
    final colSpec = StringBuffer();
    for (int i = 0; i < colCount; i++) {
      final c = minCol + i;
      if (i == 0) {
        if (_borders(c, minRow).left) colSpec.write('|');
      } else {
        final prevRight = _borders(c - 1, minRow).right;
        final curLeft = _borders(c, minRow).left;
        if (prevRight || curLeft) colSpec.write('|');
      }
      colSpec.write(alignSpec[i]);
    }
    if (_borders(maxCol, minRow).right) colSpec.write('|');
    buf.writeln('\\begin{tabular}{$colSpec}');
    // Top rule: only if at least one cell has .top border.
    final hasTopBorder = List.generate(
      colCount,
      (i) => _borders(minCol + i, minRow).top,
    ).any((b) => b);
    if (hasTopBorder) buf.writeln('\\hline');

    for (int row = minRow; row <= maxRow; row++) {
      final isHeader = opts.headers && row == minRow;
      final cells = <String>[];

      int col = minCol;
      while (col <= maxCol) {
        final addr = CellAddress(col, row);

        // Check if this cell is a vertical continuation (not the master).
        if (vertContinuation['$col:$row'] == true) {
          // Emit empty placeholder to keep column alignment.
          final merge = _findMerge(merges, col, row);
          if (merge != null) {
            final clampedEnd = merge.endColumn.clamp(minCol, maxCol);
            final colSpan = clampedEnd - merge.startColumn + 1;
            if (colSpan > 1) {
              final lB = _borders(merge.startColumn, row).left ? '|' : '';
              final rB = _borders(merge.endColumn, row).right ? '|' : '';
              cells.add('\\multicolumn{$colSpan}{${lB}c$rB}{}');
            } else {
              cells.add('');
            }
            col = clampedEnd + 1;
          } else {
            cells.add('');
            col++;
          }
          continue;
        }

        // Check if this cell is the master of a merge region.
        final merge = _findMasterMerge(merges, col, row);
        if (merge != null) {
          // Clamp spans to visible range.
          final clampedEndCol = merge.endColumn.clamp(minCol, maxCol);
          final clampedEndRow = merge.endRow.clamp(minRow, maxRow);
          final colSpan = clampedEndCol - merge.startColumn + 1;
          final rowSpan = clampedEndRow - merge.startRow + 1;

          String cellText = _getCellDisplay(addr);
          if (isHeader) cellText = '\\textbf{$cellText}';

          if (colSpan > 1 && rowSpan > 1) {
            // 2D merge: \multicolumn wrapping \multirow.
            final lB = _borders(col, row).left ? '|' : '';
            final rB = _borders(clampedEndCol, row).right ? '|' : '';
            cellText =
                '\\multicolumn{$colSpan}{${lB}c$rB}'
                '{\\multirow{$rowSpan}{*}{$cellText}}';
          } else if (colSpan > 1) {
            final lB = _borders(col, row).left ? '|' : '';
            final rB = _borders(clampedEndCol, row).right ? '|' : '';
            cellText = '\\multicolumn{$colSpan}{${lB}c$rB}{$cellText}';
          } else if (rowSpan > 1) {
            cellText = '\\multirow{$rowSpan}{*}{$cellText}';
          }

          cells.add(cellText);
          col = clampedEndCol + 1;
          continue;
        }

        // Normal cell.
        String cellText = _getCellDisplay(addr);
        if (isHeader) cellText = '\\textbf{$cellText}';
        cells.add(cellText);
        col++;
      }

      buf.writeln('${cells.join(' & ')} \\\\');

      // Row separator — use \cline for partial rules when merges or
      // borderless cells skip segments.
      if (row == maxRow) {
        // Last row bottom rule.
        final allBottom = List.generate(
          colCount,
          (i) => _borders(minCol + i, maxRow).bottom,
        ).every((b) => b);
        if (allBottom) {
          buf.writeln('\\hline');
        } else {
          final anyBottom = List.generate(
            colCount,
            (i) => _borders(minCol + i, maxRow).bottom,
          ).any((b) => b);
          if (anyBottom) {
            _writeBorderCline(buf, minCol, maxCol, maxRow, _borders);
          }
        }
      } else if (isHeader) {
        buf.writeln('\\hline');
      } else {
        final clineSegments = _computeClineSegments(
          merges,
          row,
          minCol,
          colCount,
          _borders,
        );
        if (clineSegments == null) {
          // No merges or borderless cells cross — but check cell borders.
          final allBottom = List.generate(
            colCount,
            (i) => _borders(minCol + i, row).bottom,
          ).every((b) => b);
          if (allBottom) {
            buf.writeln('\\hline');
          } else {
            final anyBottom = List.generate(
              colCount,
              (i) => _borders(minCol + i, row).bottom,
            ).any((b) => b);
            if (anyBottom) {
              _writeBorderCline(buf, minCol, maxCol, row, _borders);
            }
          }
        } else if (clineSegments.isNotEmpty) {
          for (final seg in clineSegments) {
            buf.writeln('\\cline{${seg.$1}-${seg.$2}}');
          }
        }
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

  /// Compute \cline segments for the boundary after [row].
  ///
  /// Returns null if no merges cross this boundary → full \hline.
  /// Returns empty list if entire boundary is blocked by merges.
  /// Returns (start1-indexed, end1-indexed) pairs for partial rules.
  static List<(int, int)>? _computeClineSegments(
    List<CellRange> merges,
    int row,
    int minCol,
    int colCount,
    CellBorders Function(int col, int row) getBorders,
  ) {
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
      if (!getBorders(minCol + i, row).bottom) {
        blocked[i] = true;
        anyBlocked = true;
      }
    }

    if (!anyBlocked) return null;

    final segments = <(int, int)>[];
    int? segStart;
    for (int i = 0; i < colCount; i++) {
      if (!blocked[i]) {
        segStart ??= i;
      } else {
        if (segStart != null) {
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

  // =========================================================================
  // CHART directive
  // =========================================================================

  /// Pattern: `{CHART(A1:D10, type=bar, title=Revenue)}`
  static final RegExp _chartPattern = RegExp(
    r'\{CHART\(([A-Z]+\d+):([A-Z]+\d+)(?:,\s*(.+?))?\)\}',
  );

  String _processChartDirectives(String template) {
    return template.replaceAllMapped(_chartPattern, (match) {
      final start = CellAddress.fromLabel(match.group(1)!);
      final end = CellAddress.fromLabel(match.group(2)!);
      final options = match.group(3);

      final chartOpts = _parseChartOptions(options);
      final gen = TikzChartGenerator(_evaluator);
      return gen.generate(
        CellRange(start, end),
        chartOpts.type,
        opts: chartOpts.options,
      );
    });
  }

  _ChartDirectiveOptions _parseChartOptions(String? raw) {
    var type = TikzChartType.bar;
    String? title;
    String? xlabel;
    String? ylabel;
    bool headers = true;

    if (raw != null) {
      final parts = raw.split(',');
      for (final part in parts) {
        final kv = part.trim().split('=');
        if (kv.length == 2) {
          final key = kv[0].trim().toLowerCase();
          final value = kv[1].trim();
          switch (key) {
            case 'type':
              type = TikzChartType.values.firstWhere(
                (e) => e.name == value.toLowerCase(),
                orElse: () => TikzChartType.bar,
              );
            case 'title':
              title = value;
            case 'xlabel':
              xlabel = value;
            case 'ylabel':
              ylabel = value;
            case 'headers':
              headers = value.toLowerCase() == 'true';
          }
        }
      }
    }

    return _ChartDirectiveOptions(
      type: type,
      options: TikzChartOptions(
        title: title,
        xlabel: xlabel,
        ylabel: ylabel,
        headers: headers,
      ),
    );
  }

  // =========================================================================
  // FORMULA directive
  // =========================================================================

  /// Pattern: `{FORMULA(B2)}` — renders formula of cell as LaTeX math.
  static final RegExp _formulaPattern = RegExp(r'\{FORMULA\(([A-Z]+\d+)\)\}');

  String _processFormulaDirectives(String template) {
    final translator = FormulaToLatex(_evaluator);
    return template.replaceAllMapped(_formulaPattern, (match) {
      final addr = CellAddress.fromLabel(match.group(1)!);
      final cellValue = _evaluator.model.getCell(addr)?.value;
      if (cellValue == null) return '';
      if (cellValue is FormulaValue) {
        return translator.translateFormula(cellValue.expression);
      }
      // Not a formula — just return the display value
      return _evaluator.getComputedValue(addr).displayString;
    });
  }

  // =========================================================================
  // Value placeholders
  // =========================================================================

  /// Cell label regex.
  static final RegExp _cellLabel = RegExp(r'^[A-Z]+[0-9]+$');

  /// Aggregate function regex.
  static final RegExp _aggPattern = RegExp(
    r'^(SUM|AVG|AVERAGE|MIN|MAX|COUNT)\(([A-Z]+\d+):([A-Z]+\d+)\)(?::(.+))?$',
    caseSensitive: false,
  );

  /// Process all `{...}` value placeholders (cell, formatted, range, aggregate).
  String _processPlaceholders(String template) {
    final pattern = RegExp(r'\{([^}]+)\}');
    return template.replaceAllMapped(pattern, (match) {
      final raw = match.group(1)!;
      return _resolvePlaceholder(raw);
    });
  }

  String _resolvePlaceholder(String raw) {
    // 1. Aggregate: SUM(A1:A5) or SUM(A1:A5):#,##0
    final aggMatch = _aggPattern.firstMatch(raw);
    if (aggMatch != null) {
      return _resolveAggregate(aggMatch);
    }

    // 2. Contains colon — range or formatted cell.
    if (raw.contains(':')) {
      final colonIdx = raw.indexOf(':');
      final left = raw.substring(0, colonIdx);
      final right = raw.substring(colonIdx + 1);

      if (_cellLabel.hasMatch(left) && _cellLabel.hasMatch(right)) {
        return _resolveRange(left, right);
      }

      if (_cellLabel.hasMatch(left)) {
        return _resolveFormattedCell(left, right);
      }
    }

    // 3. Simple cell reference.
    if (_cellLabel.hasMatch(raw)) {
      return _evaluator
          .getComputedValue(CellAddress.fromLabel(raw))
          .displayString;
    }

    // Not a recognized placeholder — return as-is (with braces).
    return '{$raw}';
  }

  String _resolveAggregate(RegExpMatch aggMatch) {
    final func = aggMatch.group(1)!.toUpperCase();
    final start = CellAddress.fromLabel(aggMatch.group(2)!);
    final end = CellAddress.fromLabel(aggMatch.group(3)!);
    final format = aggMatch.group(4);

    final range = CellRange(
      CellAddress(start.column, start.row),
      CellAddress(end.column, end.row),
    );

    final values = <num>[];
    int totalCount = 0;
    for (final addr in range.addresses) {
      final val = _evaluator.getComputedValue(addr);
      if (val is NumberValue) values.add(val.value);
      if (val is! EmptyValue) totalCount++;
    }

    if (values.isEmpty && func != 'COUNT') return '#N/A';

    final num result;
    switch (func) {
      case 'SUM':
        result = values.fold<num>(0, (a, b) => a + b);
      case 'AVG' || 'AVERAGE':
        result = values.fold<num>(0, (a, b) => a + b) / values.length;
      case 'MIN':
        result = values.reduce((a, b) => a < b ? a : b);
      case 'MAX':
        result = values.reduce((a, b) => a > b ? a : b);
      case 'COUNT':
        result = totalCount;
      default:
        return '#NAME?';
    }

    if (format != null) return CellNumberFormatter.format(result, format);
    return result == result.toInt()
        ? result.toInt().toString()
        : result.toString();
  }

  String _resolveRange(String startLabel, String endLabel) {
    final start = CellAddress.fromLabel(startLabel);
    final end = CellAddress.fromLabel(endLabel);
    final range = CellRange(
      CellAddress(start.column, start.row),
      CellAddress(end.column, end.row),
    );

    final values = <String>[];
    for (final addr in range.addresses) {
      final val = _evaluator.getComputedValue(addr);
      if (val is! EmptyValue) values.add(val.displayString);
    }
    return values.join(rangeSeparator);
  }

  String _resolveFormattedCell(String cellLabel, String format) {
    final val = _evaluator.getComputedValue(CellAddress.fromLabel(cellLabel));
    if (val is NumberValue) {
      return CellNumberFormatter.format(val.value, format);
    }
    return val.displayString;
  }

  // =========================================================================
  // Helpers
  // =========================================================================

  String _getCellDisplay(CellAddress addr) {
    final val = _evaluator.getComputedValue(addr);
    if (val is EmptyValue) return '';
    return val.displayString;
  }

  static num? _toNum(CellValue value) {
    if (value is NumberValue) return value.value;
    return null;
  }
}

// =============================================================================
// Internal types
// =============================================================================

class _TableOptions {
  final bool headers;
  final String? align;

  const _TableOptions({this.headers = false, this.align});
}

class _ChartDirectiveOptions {
  final TikzChartType type;
  final TikzChartOptions options;

  const _ChartDirectiveOptions({required this.type, required this.options});
}
