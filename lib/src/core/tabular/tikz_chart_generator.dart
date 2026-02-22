import 'cell_address.dart';
import 'cell_value.dart';
import 'spreadsheet_evaluator.dart';

/// Supported chart types for TikZ/pgfplots generation.
enum TikzChartType { line, bar, scatter, pie }

/// Options for TikZ chart generation.
class TikzChartOptions {
  /// Chart title.
  final String? title;

  /// X-axis label.
  final String? xlabel;

  /// Y-axis label.
  final String? ylabel;

  /// Whether the first row of data contains series headers.
  final bool headers;

  /// Width of the chart (LaTeX dimension).
  final String width;

  /// Height of the chart (LaTeX dimension).
  final String height;

  /// Color cycle for multiple series.
  final List<String> colors;

  /// Whether to show a legend.
  final bool legend;

  /// Whether to show grid lines.
  final bool grid;

  const TikzChartOptions({
    this.title,
    this.xlabel,
    this.ylabel,
    this.headers = true,
    this.width = '10cm',
    this.height = '7cm',
    this.colors = const ['blue', 'red', 'green!60!black', 'orange', 'purple'],
    this.legend = true,
    this.grid = true,
  });
}

/// 📊 Generates TikZ/pgfplots LaTeX code from spreadsheet data ranges.
///
/// Reads data from a [SpreadsheetEvaluator] and produces complete
/// `\begin{tikzpicture}` blocks with `\begin{axis}` environments.
///
/// ## Supported chart types
///
/// | Type | Description |
/// |---|---|
/// | `line` | Line plot with markers (`\addplot`) |
/// | `bar` | Grouped bar chart (`ybar`) |
/// | `scatter` | Scatter plot (`only marks`) |
/// | `pie` | Pie chart (via `\pie` slices) |
///
/// ## Usage
///
/// ```dart
/// final gen = TikzChartGenerator(evaluator);
/// final tikz = gen.generate(
///   CellRange(CellAddress(0, 0), CellAddress(3, 10)),
///   TikzChartType.bar,
///   opts: TikzChartOptions(title: 'Revenue Q1'),
/// );
/// ```
class TikzChartGenerator {
  final SpreadsheetEvaluator _evaluator;

  TikzChartGenerator(this._evaluator);

  /// Generate TikZ/pgfplots code from a data range.
  ///
  /// The [range] should be organized as:
  /// - Column 0 = X-axis labels/values (categories)
  /// - Columns 1..N = Y-axis data series
  /// - If [opts.headers] is true, row 0 = series names
  String generate(
    CellRange range,
    TikzChartType type, {
    TikzChartOptions opts = const TikzChartOptions(),
  }) {
    final data = _extractData(range, opts.headers);
    if (data.categories.isEmpty) return '% Empty range — no data to chart';

    switch (type) {
      case TikzChartType.line:
        return _generateLinePlot(data, opts);
      case TikzChartType.bar:
        return _generateBarChart(data, opts);
      case TikzChartType.scatter:
        return _generateScatterPlot(data, opts);
      case TikzChartType.pie:
        return _generatePieChart(data, opts);
    }
  }

  // ---------------------------------------------------------------------------
  // Data extraction
  // ---------------------------------------------------------------------------

  _ChartData _extractData(CellRange range, bool hasHeaders) {
    final startCol = range.start.column;
    final endCol = range.end.column;
    final startRow = range.start.row;
    final endRow = range.end.row;

    final dataStartRow = hasHeaders ? startRow + 1 : startRow;

    // Series headers (column names)
    final seriesNames = <String>[];
    if (hasHeaders) {
      for (int c = startCol + 1; c <= endCol; c++) {
        seriesNames.add(_getCellString(CellAddress(c, startRow)));
      }
    } else {
      for (int c = startCol + 1; c <= endCol; c++) {
        seriesNames.add('Series ${c - startCol}');
      }
    }

    // Categories (first column values)
    final categories = <String>[];
    for (int r = dataStartRow; r <= endRow; r++) {
      categories.add(_getCellString(CellAddress(startCol, r)));
    }

    // Data series (one list per column)
    final seriesData = <List<double>>[];
    for (int c = startCol + 1; c <= endCol; c++) {
      final series = <double>[];
      for (int r = dataStartRow; r <= endRow; r++) {
        series.add(_getCellNum(CellAddress(c, r)));
      }
      seriesData.add(series);
    }

    return _ChartData(
      categories: categories,
      seriesNames: seriesNames,
      seriesData: seriesData,
    );
  }

  String _getCellString(CellAddress addr) {
    final v = _evaluator.getComputedValue(addr);
    if (v is EmptyValue) return '';
    if (v is TextValue) return v.value;
    if (v is NumberValue) return v.value.toString();
    return v.toString();
  }

  double _getCellNum(CellAddress addr) {
    final v = _evaluator.getComputedValue(addr);
    if (v is NumberValue) return v.value.toDouble();
    if (v is TextValue) return double.tryParse(v.value) ?? 0.0;
    return 0.0;
  }

  // ---------------------------------------------------------------------------
  // Axis preamble
  // ---------------------------------------------------------------------------

  String _axisOptions(TikzChartOptions opts, {String? extraOpts}) {
    final parts = <String>[];
    parts.add('width=${opts.width}');
    parts.add('height=${opts.height}');
    if (opts.title != null) parts.add('title={${opts.title}}');
    if (opts.xlabel != null) parts.add('xlabel={${opts.xlabel}}');
    if (opts.ylabel != null) parts.add('ylabel={${opts.ylabel}}');
    if (opts.grid) parts.add('grid=major');
    if (extraOpts != null) parts.add(extraOpts);
    return parts.join(',\n    ');
  }

  String _legendBlock(_ChartData data, TikzChartOptions opts) {
    if (!opts.legend || data.seriesNames.isEmpty) return '';
    final entries = data.seriesNames.map((n) => _escapeLatex(n)).join(', ');
    return '  \\legend{$entries}\n';
  }

  // ---------------------------------------------------------------------------
  // Line plot
  // ---------------------------------------------------------------------------

  String _generateLinePlot(_ChartData data, TikzChartOptions opts) {
    final buf = StringBuffer();
    buf.writeln('\\begin{tikzpicture}');
    buf.writeln('\\begin{axis}[');
    buf.writeln('    ${_axisOptions(opts)},');
    buf.writeln(
      '    symbolic x coords={${data.categories.map(_escapeLatex).join(", ")}},',
    );
    buf.writeln('    xtick=data,');
    buf.writeln(']');

    for (int s = 0; s < data.seriesData.length; s++) {
      final color = opts.colors[s % opts.colors.length];
      buf.writeln('\\addplot[color=$color, mark=*] coordinates {');
      for (int i = 0; i < data.categories.length; i++) {
        buf.writeln(
          '  (${_escapeLatex(data.categories[i])}, ${data.seriesData[s][i]})',
        );
      }
      buf.writeln('};');
    }

    buf.write(_legendBlock(data, opts));
    buf.writeln('\\end{axis}');
    buf.writeln('\\end{tikzpicture}');
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Bar chart
  // ---------------------------------------------------------------------------

  String _generateBarChart(_ChartData data, TikzChartOptions opts) {
    final buf = StringBuffer();
    buf.writeln('\\begin{tikzpicture}');
    buf.writeln('\\begin{axis}[');
    buf.writeln('    ${_axisOptions(opts, extraOpts: 'ybar')},');
    buf.writeln(
      '    symbolic x coords={${data.categories.map(_escapeLatex).join(", ")}},',
    );
    buf.writeln('    xtick=data,');
    buf.writeln('    nodes near coords,');
    buf.writeln('    nodes near coords align={vertical},');
    buf.writeln(']');

    for (int s = 0; s < data.seriesData.length; s++) {
      final color = opts.colors[s % opts.colors.length];
      buf.writeln('\\addplot[fill=$color] coordinates {');
      for (int i = 0; i < data.categories.length; i++) {
        buf.writeln(
          '  (${_escapeLatex(data.categories[i])}, ${data.seriesData[s][i]})',
        );
      }
      buf.writeln('};');
    }

    buf.write(_legendBlock(data, opts));
    buf.writeln('\\end{axis}');
    buf.writeln('\\end{tikzpicture}');
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Scatter plot
  // ---------------------------------------------------------------------------

  String _generateScatterPlot(_ChartData data, TikzChartOptions opts) {
    final buf = StringBuffer();
    buf.writeln('\\begin{tikzpicture}');
    buf.writeln('\\begin{axis}[');
    buf.writeln('    ${_axisOptions(opts, extraOpts: 'only marks')},');
    buf.writeln(']');

    for (int s = 0; s < data.seriesData.length; s++) {
      final color = opts.colors[s % opts.colors.length];
      buf.writeln('\\addplot[color=$color, mark=o] coordinates {');
      // For scatter, use categories as numeric indices if not numeric
      for (int i = 0; i < data.categories.length; i++) {
        final x = double.tryParse(data.categories[i]) ?? i.toDouble();
        buf.writeln('  ($x, ${data.seriesData[s][i]})');
      }
      buf.writeln('};');
    }

    buf.write(_legendBlock(data, opts));
    buf.writeln('\\end{axis}');
    buf.writeln('\\end{tikzpicture}');
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Pie chart
  // ---------------------------------------------------------------------------

  String _generatePieChart(_ChartData data, TikzChartOptions opts) {
    if (data.seriesData.isEmpty) return '% No series data for pie chart';

    // Pie uses first series only
    final values = data.seriesData[0];
    final total = values.fold(0.0, (a, b) => a + b);
    if (total == 0) return '% Total is zero — cannot generate pie chart';

    final buf = StringBuffer();
    if (opts.title != null)
      buf.writeln(
        '\\begin{center}\\textbf{${_escapeLatex(opts.title!)}}\\end{center}',
      );
    buf.writeln('\\begin{tikzpicture}');

    double startAngle = 0;
    for (int i = 0; i < values.length; i++) {
      final pct = values[i] / total * 100;
      final endAngle = startAngle + (values[i] / total * 360);
      final color = opts.colors[i % opts.colors.length];
      final label =
          i < data.categories.length ? _escapeLatex(data.categories[i]) : '';
      buf.writeln(
        '  \\fill[$color!60] (0,0) -- ($startAngle:2cm) arc ($startAngle:$endAngle:2cm) -- cycle;',
      );
      // Label at midpoint
      final midAngle = (startAngle + endAngle) / 2;
      buf.writeln(
        '  \\node at ($midAngle:2.5cm) {\\small $label (${pct.toStringAsFixed(1)}\\%)};',
      );
      startAngle = endAngle;
    }

    buf.writeln('\\end{tikzpicture}');
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  static String _escapeLatex(String text) {
    return text
        .replaceAll('\\', '\\textbackslash{}')
        .replaceAll('&', '\\&')
        .replaceAll('%', '\\%')
        .replaceAll(r'$', '\\\$')
        .replaceAll('#', '\\#')
        .replaceAll('_', '\\_')
        .replaceAll('{', '\\{')
        .replaceAll('}', '\\}')
        .replaceAll('~', '\\textasciitilde{}')
        .replaceAll('^', '\\textasciicircum{}');
  }
}

// =============================================================================
// Internal data structures
// =============================================================================

class _ChartData {
  final List<String> categories;
  final List<String> seriesNames;
  final List<List<double>> seriesData;

  const _ChartData({
    required this.categories,
    required this.seriesNames,
    required this.seriesData,
  });
}
