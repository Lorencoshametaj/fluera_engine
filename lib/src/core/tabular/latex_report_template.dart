import 'cell_address.dart';
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
    final colCount = end.column - start.column + 1;
    final rowCount = end.row - start.row + 1;

    // Build alignment spec.
    final alignSpec = opts.align ?? List.filled(colCount, 'c').join();
    final buf = StringBuffer();

    buf.writeln('\\begin{tabular}{|${alignSpec.split('').join('|')}|}');
    buf.writeln('\\hline');

    for (int r = 0; r < rowCount; r++) {
      final row = start.row + r;
      final isHeader = opts.headers && r == 0;
      final cells = <String>[];

      int col = start.column;
      while (col <= end.column) {
        final addr = CellAddress(col, row);

        // Check for merge regions.
        if (_mergeManager != null && _mergeManager.isHiddenByMerge(addr)) {
          col++;
          continue;
        }

        String cellText = _getCellDisplay(addr);

        if (_mergeManager != null && _mergeManager.isMasterCell(addr)) {
          final region = _mergeManager.getRegion(addr)!;
          final span = region.endColumn - region.startColumn + 1;
          if (span > 1) {
            cellText = '\\multicolumn{$span}{|c|}{$cellText}';
            col += span;
            cells.add(cellText);
            continue;
          }
        }

        if (isHeader) cellText = '\\textbf{$cellText}';
        cells.add(cellText);
        col++;
      }

      buf.writeln('${cells.join(' & ')} \\\\');
      if (isHeader) buf.writeln('\\hline');
    }

    buf.writeln('\\hline');
    buf.write('\\end{tabular}');

    return buf.toString();
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
