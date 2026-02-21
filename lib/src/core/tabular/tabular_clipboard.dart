import 'package:flutter/services.dart';

import 'cell_address.dart';
import 'cell_node.dart';
import 'cell_value.dart';
import 'spreadsheet_model.dart';
import 'tabular_csv.dart';

/// 📋 Clipboard operations for the tabular engine.
///
/// Provides copy, cut, and paste of cell ranges using the system clipboard.
/// Data is serialized as tab-separated values (TSV) for compatibility with
/// external spreadsheet applications (Excel, Google Sheets, etc.).
class TabularClipboard {
  TabularClipboard._();

  // =========================================================================
  // Copy
  // =========================================================================

  /// Copy a range of cells to the system clipboard as TSV.
  ///
  /// Returns the copied text for convenience.
  static Future<String> copy(SpreadsheetModel model, CellRange range) async {
    final tsv = _rangeToTsv(model, range);
    await Clipboard.setData(ClipboardData(text: tsv));
    return tsv;
  }

  /// Copy a range and clear the source cells (cut operation).
  ///
  /// Returns the list of addresses that were cleared.
  static Future<List<CellAddress>> cut(
    SpreadsheetModel model,
    CellRange range,
  ) async {
    await copy(model, range);

    final cleared = <CellAddress>[];
    for (final addr in range.addresses) {
      if (model.getCell(addr) != null) {
        model.clearCell(addr);
        cleared.add(addr);
      }
    }
    return cleared;
  }

  // =========================================================================
  // Paste
  // =========================================================================

  /// Read TSV from the system clipboard and return parsed cell values.
  ///
  /// Returns a 2D list suitable for [PasteRangeCommand].
  /// Returns `null` if the clipboard is empty.
  static Future<List<List<CellValue>>?> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null || data.text!.isEmpty) return null;

    return parseTsv(data.text!);
  }

  /// Parse a TSV string into a 2D list of [CellValue]s.
  ///
  /// Exposed for testability without clipboard access.
  static List<List<CellValue>> parseTsv(String tsv) {
    final rows = tsv.split('\n');
    return rows.where((r) => r.isNotEmpty).map((row) {
      return row.split('\t').map((field) {
        return _detectValue(field.trim());
      }).toList();
    }).toList();
  }

  // =========================================================================
  // Internal
  // =========================================================================

  /// Serialize a range to TSV (tab-separated values).
  static String _rangeToTsv(SpreadsheetModel model, CellRange range) {
    final buf = StringBuffer();

    for (int r = range.startRow; r <= range.endRow; r++) {
      for (int c = range.startColumn; c <= range.endColumn; c++) {
        if (c > range.startColumn) buf.write('\t');

        final cell = model.getCell(CellAddress(c, r));
        if (cell != null) {
          buf.write(cell.displayValue.displayString);
        }
      }
      if (r < range.endRow) buf.writeln();
    }

    return buf.toString();
  }

  /// Auto-detect value type from a raw string.
  static CellValue _detectValue(String raw) {
    if (raw.isEmpty) return const EmptyValue();

    // Formula.
    if (raw.startsWith('=')) {
      return FormulaValue(raw.substring(1));
    }

    // Boolean.
    final upper = raw.toUpperCase();
    if (upper == 'TRUE') return const BoolValue(true);
    if (upper == 'FALSE') return const BoolValue(false);

    // Number.
    final n = num.tryParse(raw);
    if (n != null) return NumberValue(n);

    // Text.
    return TextValue(raw);
  }
}
