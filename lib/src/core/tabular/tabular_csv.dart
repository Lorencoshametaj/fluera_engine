import 'cell_address.dart';
import 'cell_node.dart';
import 'cell_value.dart';
import 'spreadsheet_model.dart';

/// 📊 CSV import/export for the tabular engine.
///
/// Converts between [SpreadsheetModel] and CSV strings.
///
/// ## Import
/// ```dart
/// final model = TabularCsv.import('Name,Age\nAlice,30\nBob,25');
/// // A1="Name", B1="Age", A2="Alice", B2=30, ...
/// ```
///
/// ## Export
/// ```dart
/// final csv = TabularCsv.export(model);
/// ```
class TabularCsv {
  TabularCsv._();

  // =========================================================================
  // Import
  // =========================================================================

  /// Import a CSV string into a [SpreadsheetModel].
  ///
  /// Numbers are auto-detected and stored as [NumberValue].
  /// `TRUE`/`FALSE` are stored as [BoolValue].
  /// Everything else becomes [TextValue].
  /// Formulas starting with `=` become [FormulaValue].
  static SpreadsheetModel import(
    String csv, {
    String delimiter = ',',
    bool hasHeaders = false,
  }) {
    final model = SpreadsheetModel();
    final rows = _parseCsvRows(csv, delimiter);

    for (int r = 0; r < rows.length; r++) {
      final row = rows[r];
      for (int c = 0; c < row.length; c++) {
        final raw = row[c].trim();
        if (raw.isEmpty) continue;

        final value = _detectValue(raw);
        model.setCell(CellAddress(c, r), CellNode(value: value));
      }
    }

    return model;
  }

  // =========================================================================
  // Export
  // =========================================================================

  /// Export a [SpreadsheetModel] to a CSV string.
  ///
  /// Uses computed values for formula cells.
  static String export(
    SpreadsheetModel model, {
    String delimiter = ',',
    bool includeEmpty = false,
  }) {
    if (model.cellCount == 0) return '';

    final maxCol = model.maxColumn;
    final maxRow = model.maxRow;
    if (maxCol < 0 || maxRow < 0) return '';

    final buf = StringBuffer();

    for (int r = 0; r <= maxRow; r++) {
      for (int c = 0; c <= maxCol; c++) {
        if (c > 0) buf.write(delimiter);

        final cell = model.getCell(CellAddress(c, r));
        if (cell == null) continue;

        final display = cell.displayValue;
        final text = display.displayString;

        // Quote fields that contain delimiter, newline, or quotes.
        if (_needsQuoting(text, delimiter)) {
          buf.write('"');
          buf.write(text.replaceAll('"', '""'));
          buf.write('"');
        } else {
          buf.write(text);
        }
      }
      if (r < maxRow) buf.writeln();
    }

    return buf.toString();
  }

  // =========================================================================
  // CSV parsing (RFC 4180 compliant)
  // =========================================================================

  /// Parse CSV text into a list of rows, each row a list of fields.
  static List<List<String>> _parseCsvRows(String csv, String delimiter) {
    final rows = <List<String>>[];
    final fields = <String>[];
    final buf = StringBuffer();
    bool inQuotes = false;
    int i = 0;

    while (i < csv.length) {
      final ch = csv[i];

      if (inQuotes) {
        if (ch == '"') {
          // Check for escaped quote.
          if (i + 1 < csv.length && csv[i + 1] == '"') {
            buf.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        buf.write(ch);
        i++;
        continue;
      }

      if (ch == '"') {
        inQuotes = true;
        i++;
        continue;
      }

      if (csv.startsWith(delimiter, i)) {
        fields.add(buf.toString());
        buf.clear();
        i += delimiter.length;
        continue;
      }

      if (ch == '\n') {
        fields.add(buf.toString());
        rows.add(List<String>.from(fields));
        fields.clear();
        buf.clear();
        i++;
        // Skip \r\n.
        continue;
      }

      if (ch == '\r') {
        i++;
        continue;
      }

      buf.write(ch);
      i++;
    }

    // Last field.
    if (buf.isNotEmpty || fields.isNotEmpty) {
      fields.add(buf.toString());
      rows.add(List<String>.from(fields));
    }

    return rows;
  }

  /// Auto-detect cell value type from a raw string.
  static CellValue _detectValue(String raw) {
    // Formula.
    if (raw.startsWith('=')) {
      return FormulaValue(raw.substring(1));
    }

    // Boolean.
    final upper = raw.toUpperCase();
    if (upper == 'TRUE') return const BoolValue(true);
    if (upper == 'FALSE') return const BoolValue(false);

    // Number.
    final num? n = num.tryParse(raw);
    if (n != null) return NumberValue(n);

    // Text.
    return TextValue(raw);
  }

  /// Whether a field needs quoting in CSV output.
  static bool _needsQuoting(String text, String delimiter) {
    return text.contains(delimiter) ||
        text.contains('\n') ||
        text.contains('\r') ||
        text.contains('"');
  }
}
