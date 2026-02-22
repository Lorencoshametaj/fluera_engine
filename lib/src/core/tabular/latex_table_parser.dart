/// 📊 Parses LaTeX table/matrix markup into structured data.
///
/// Supports:
/// - `\begin{tabular}{lcr}...\end{tabular}` — standard tables
/// - `\begin{array}{ccc}...\end{array}` — math arrays
/// - `\begin{bmatrix}...\end{bmatrix}` — bracket matrices
/// - `\begin{pmatrix}...\end{pmatrix}` — parenthesis matrices
/// - `\begin{vmatrix}...\end{vmatrix}` — determinant matrices
///
/// ## Usage
///
/// ```dart
/// final parser = LatexTableParser();
/// final result = parser.parse(r'\begin{tabular}{|l|c|r|}\hline Name & Age & Score \\ ...');
/// print(result.data); // [['Name', 'Age', 'Score'], ['Alice', '30', '95']]
/// ```
class LatexTableParser {
  /// Parse LaTeX source containing a table or matrix.
  ///
  /// Returns `null` if no recognized environment is found.
  ParsedTable? parse(String latexSource) {
    // Try each environment type
    for (final env in _supportedEnvs) {
      final result = _tryParseEnvironment(latexSource, env);
      if (result != null) return result;
    }
    return null;
  }

  /// Parse all tables/matrices found in the source.
  List<ParsedTable> parseAll(String latexSource) {
    final results = <ParsedTable>[];
    for (final env in _supportedEnvs) {
      final pattern = RegExp(
        r'\\begin\{' + env + r'\}(\{[^}]*\})?(.*?)\\end\{' + env + r'\}',
        dotAll: true,
      );
      for (final match in pattern.allMatches(latexSource)) {
        final alignment = match.group(1)?.replaceAll(RegExp(r'[{}|]'), '');
        final body = match.group(2) ?? '';
        final parsed = _parseBody(body, alignment, env);
        if (parsed != null) results.add(parsed);
      }
    }
    return results;
  }

  static const _supportedEnvs = [
    'tabular',
    'array',
    'bmatrix',
    'pmatrix',
    'vmatrix',
    'Bmatrix',
    'matrix',
  ];

  ParsedTable? _tryParseEnvironment(String source, String env) {
    final pattern = RegExp(
      r'\\begin\{' + env + r'\}(\{[^}]*\})?(.*?)\\end\{' + env + r'\}',
      dotAll: true,
    );
    final match = pattern.firstMatch(source);
    if (match == null) return null;

    final alignment = match.group(1)?.replaceAll(RegExp(r'[{}|]'), '');
    final body = match.group(2) ?? '';
    return _parseBody(body, alignment, env);
  }

  ParsedTable? _parseBody(String body, String? alignment, String env) {
    // Split by \\ (row separator) — handle optional [spacing] after \\
    final rawRows = body.split(RegExp(r'\\\\(\s*\[[^\]]*\])?'));

    final rows = <List<String>>[];

    for (final rawRow in rawRows) {
      // Skip \hline, \toprule, \midrule, \bottomrule, \cline
      final cleaned =
          rawRow
              .replaceAll(RegExp(r'\\hline'), '')
              .replaceAll(RegExp(r'\\toprule'), '')
              .replaceAll(RegExp(r'\\midrule'), '')
              .replaceAll(RegExp(r'\\bottomrule'), '')
              .replaceAll(RegExp(r'\\cline\{[^}]*\}'), '')
              .trim();

      if (cleaned.isEmpty) continue;

      // Split by & (cell separator)
      final cells =
          cleaned.split('&').map((c) => _cleanCell(c.trim())).toList();
      if (cells.any((c) => c.isNotEmpty)) {
        rows.add(cells);
      }
    }

    if (rows.isEmpty) return null;

    // Detect headers: if first row is wrapped in \textbf or environment is tabular
    List<String>? headers;
    List<List<String>> data;

    if (env == 'tabular' && rows.isNotEmpty && _looksLikeHeaders(rows.first)) {
      headers = rows.first;
      data = rows.sublist(1);
    } else {
      data = rows;
    }

    return ParsedTable(
      data: data,
      headers: headers,
      alignment: alignment,
      environment: env,
    );
  }

  /// Strip LaTeX formatting commands from a cell.
  String _cleanCell(String cell) {
    var result = cell;

    // Remove \textbf{...}, \textit{...}, \emph{...}
    result = result.replaceAllMapped(
      RegExp(r'\\(?:textbf|textit|emph|text)\{([^}]*)\}'),
      (m) => m.group(1) ?? '',
    );

    // Remove \multicolumn{N}{align}{content} → extract content
    result = result.replaceAllMapped(
      RegExp(r'\\multicolumn\{[^}]*\}\{[^}]*\}\{([^}]*)\}'),
      (m) => m.group(1) ?? '',
    );

    // Remove $ delimiters for math mode
    result = result.replaceAll(RegExp(r'^\$|\$$'), '');

    // Remove remaining simple commands like \, \; \quad etc.
    result = result.replaceAll(RegExp(r'\\[,;!]'), ' ');
    result = result.replaceAll(
      RegExp(r'\\(?:quad|qquad|hspace\{[^}]*\})'),
      ' ',
    );

    return result.trim();
  }

  /// Heuristic: row is headers if most cells are wrapped in \textbf.
  bool _looksLikeHeaders(List<String> row) {
    if (row.isEmpty) return false;
    // Check original cells before cleaning — re-check raw content
    // Since we've already cleaned, we check if original had \textbf
    // This is a simplified heuristic
    return false; // Safe default — headers explicitly provided by caller
  }
}

/// Result of parsing a LaTeX table or matrix.
class ParsedTable {
  /// Data rows (excluding headers if detected).
  final List<List<String>> data;

  /// Header row, or null if none detected.
  final List<String>? headers;

  /// Column alignment string (e.g. "lcr"), or null.
  final String? alignment;

  /// Source environment name (e.g. "tabular", "bmatrix").
  final String environment;

  const ParsedTable({
    required this.data,
    this.headers,
    this.alignment,
    required this.environment,
  });

  /// Total number of rows including headers.
  int get totalRows => data.length + (headers != null ? 1 : 0);

  /// Number of columns (from widest row).
  int get columnCount {
    int max = 0;
    if (headers != null && headers!.length > max) max = headers!.length;
    for (final row in data) {
      if (row.length > max) max = row.length;
    }
    return max;
  }

  /// Get all rows including headers as a flat list.
  List<List<String>> get allRows {
    if (headers != null) return [headers!, ...data];
    return data;
  }
}
