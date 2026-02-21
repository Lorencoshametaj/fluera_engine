import 'cell_address.dart';
import 'cell_node.dart';
import 'cell_validation.dart';
import 'cell_value.dart';
import 'conditional_format.dart';

/// 📊 Sparse spreadsheet data model.
///
/// Stores cells in a [HashMap] keyed by [CellAddress]. Only occupied cells
/// consume memory — an empty 10,000×10,000 grid uses zero cell storage.
///
/// Column widths and row heights are also sparse maps with configurable
/// defaults.
///
/// ```dart
/// final model = SpreadsheetModel();
/// model.setCell(CellAddress(0, 0), CellNode(value: NumberValue(42)));
/// model.setCell(CellAddress(1, 0), CellNode(value: FormulaValue('A1*2')));
/// ```
class SpreadsheetModel {
  // -------------------------------------------------------------------------
  // Cell storage
  // -------------------------------------------------------------------------

  /// Sparse cell storage: only non-empty cells exist in memory.
  final Map<CellAddress, CellNode> _cells = {};

  /// Column widths (0-indexed). Missing keys use [defaultColumnWidth].
  final Map<int, double> _columnWidths = {};

  /// Row heights (0-indexed). Missing keys use [defaultRowHeight].
  final Map<int, double> _rowHeights = {};

  /// Default column width in logical pixels.
  double defaultColumnWidth;

  /// Default row height in logical pixels.
  double defaultRowHeight;

  /// Number of frozen columns (scroll lock).
  int frozenColumns;

  /// Number of frozen rows (scroll lock).
  int frozenRows;

  /// Sparse validation rules per cell address.
  final Map<CellAddress, CellValidation> _validations = {};

  /// Conditional formatting rule engine.
  final ConditionalFormatEngine conditionalFormats = ConditionalFormatEngine();

  /// Named ranges: maps a name (e.g. "Revenue") to a [CellRange].
  final Map<String, CellRange> _namedRanges = {};

  SpreadsheetModel({
    this.defaultColumnWidth = 100.0,
    this.defaultRowHeight = 28.0,
    this.frozenColumns = 0,
    this.frozenRows = 0,
  });

  // -------------------------------------------------------------------------
  // Cell CRUD
  // -------------------------------------------------------------------------

  /// Get the cell at [addr], or `null` if empty.
  CellNode? getCell(CellAddress addr) => _cells[addr];

  /// Set the cell at [addr]. Overwrites any existing cell.
  void setCell(CellAddress addr, CellNode cell) {
    _cells[addr] = cell;
  }

  /// Remove the cell at [addr]. Returns the removed cell, or `null`.
  CellNode? clearCell(CellAddress addr) => _cells.remove(addr);

  /// Whether a cell exists at [addr].
  bool hasCell(CellAddress addr) => _cells.containsKey(addr);

  /// Get all cells in a [range].
  Map<CellAddress, CellNode> getCellsInRange(CellRange range) {
    final result = <CellAddress, CellNode>{};
    for (final addr in range.addresses) {
      final cell = _cells[addr];
      if (cell != null) {
        result[addr] = cell;
      }
    }
    return result;
  }

  /// All occupied cell addresses.
  Iterable<CellAddress> get occupiedAddresses => _cells.keys;

  /// Number of occupied cells.
  int get cellCount => _cells.length;

  /// Read-only view of all cells.
  Map<CellAddress, CellNode> get cells => Map.unmodifiable(_cells);

  // -------------------------------------------------------------------------
  // Validation
  // -------------------------------------------------------------------------

  /// Set a validation rule for [addr].
  void setValidation(CellAddress addr, CellValidation validation) {
    _validations[addr] = validation;
  }

  /// Get the validation rule for [addr], or `null` if none.
  CellValidation? getValidation(CellAddress addr) => _validations[addr];

  /// Remove the validation rule for [addr].
  CellValidation? removeValidation(CellAddress addr) =>
      _validations.remove(addr);

  /// Whether a cell has a validation rule.
  bool hasValidation(CellAddress addr) => _validations.containsKey(addr);

  /// Validate a value against the cell's rule. Returns `true` if valid
  /// or if no rule exists.
  bool validateCell(CellAddress addr, CellValue value) {
    final rule = _validations[addr];
    if (rule == null) return true;
    return rule.validate(value);
  }

  /// All validation entries.
  Map<CellAddress, CellValidation> get validations =>
      Map.unmodifiable(_validations);

  // -------------------------------------------------------------------------
  // Named Ranges
  // -------------------------------------------------------------------------

  /// Define a named range.
  void setNamedRange(String name, CellRange range) {
    _namedRanges[name.toUpperCase()] = range;
  }

  /// Get a named range by name (case-insensitive).
  CellRange? getNamedRange(String name) => _namedRanges[name.toUpperCase()];

  /// Remove a named range. Returns the removed range, or null.
  CellRange? removeNamedRange(String name) =>
      _namedRanges.remove(name.toUpperCase());

  /// Whether a named range exists.
  bool hasNamedRange(String name) =>
      _namedRanges.containsKey(name.toUpperCase());

  /// All named ranges.
  Map<String, CellRange> get namedRanges => Map.unmodifiable(_namedRanges);

  // -------------------------------------------------------------------------
  // Grid bounds
  // -------------------------------------------------------------------------

  /// The maximum occupied column index, or -1 if empty.
  int get maxColumn {
    if (_cells.isEmpty) return -1;
    int max = -1;
    for (final addr in _cells.keys) {
      if (addr.column > max) max = addr.column;
    }
    return max;
  }

  /// The maximum occupied row index, or -1 if empty.
  int get maxRow {
    if (_cells.isEmpty) return -1;
    int max = -1;
    for (final addr in _cells.keys) {
      if (addr.row > max) max = addr.row;
    }
    return max;
  }

  // -------------------------------------------------------------------------
  // Column / Row sizing
  // -------------------------------------------------------------------------

  /// Get column width (uses default if not explicitly set).
  double getColumnWidth(int column) =>
      _columnWidths[column] ?? defaultColumnWidth;

  /// Set column width explicitly.
  void setColumnWidth(int column, double width) {
    _columnWidths[column] = width;
  }

  /// Get row height (uses default if not explicitly set).
  double getRowHeight(int row) => _rowHeights[row] ?? defaultRowHeight;

  /// Set row height explicitly.
  void setRowHeight(int row, double height) {
    _rowHeights[row] = height;
  }

  /// Total width of columns [0, columnCount).
  double totalWidth(int columnCount) {
    double total = 0;
    for (int c = 0; c < columnCount; c++) {
      total += getColumnWidth(c);
    }
    return total;
  }

  /// Total height of rows [0, rowCount).
  double totalHeight(int rowCount) {
    double total = 0;
    for (int r = 0; r < rowCount; r++) {
      total += getRowHeight(r);
    }
    return total;
  }

  /// X offset of the left edge of column [col].
  double columnOffset(int col) {
    double offset = 0;
    for (int c = 0; c < col; c++) {
      offset += getColumnWidth(c);
    }
    return offset;
  }

  /// Y offset of the top edge of row [row].
  double rowOffset(int row) {
    double offset = 0;
    for (int r = 0; r < row; r++) {
      offset += getRowHeight(r);
    }
    return offset;
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() {
    final cellsJson = <Map<String, dynamic>>[];
    for (final entry in _cells.entries) {
      cellsJson.add({'addr': entry.key.toJson(), 'cell': entry.value.toJson()});
    }

    final colWidthsJson = <String, double>{};
    for (final entry in _columnWidths.entries) {
      colWidthsJson[entry.key.toString()] = entry.value;
    }

    final rowHeightsJson = <String, double>{};
    for (final entry in _rowHeights.entries) {
      rowHeightsJson[entry.key.toString()] = entry.value;
    }

    return {
      'cells': cellsJson,
      'defaultColumnWidth': defaultColumnWidth,
      'defaultRowHeight': defaultRowHeight,
      if (colWidthsJson.isNotEmpty) 'columnWidths': colWidthsJson,
      if (rowHeightsJson.isNotEmpty) 'rowHeights': rowHeightsJson,
      if (frozenColumns > 0) 'frozenColumns': frozenColumns,
      if (frozenRows > 0) 'frozenRows': frozenRows,
      if (_validations.isNotEmpty)
        'validations': [
          for (final e in _validations.entries)
            {'addr': e.key.toJson(), 'rule': e.value.toJson()},
        ],
      if (conditionalFormats.ruleCount > 0)
        'conditionalFormats': conditionalFormats.toJson(),
      if (_namedRanges.isNotEmpty)
        'namedRanges': {
          for (final e in _namedRanges.entries) e.key: e.value.toJson(),
        },
    };
  }

  factory SpreadsheetModel.fromJson(Map<String, dynamic> json) {
    final model = SpreadsheetModel(
      defaultColumnWidth:
          (json['defaultColumnWidth'] as num?)?.toDouble() ?? 100.0,
      defaultRowHeight: (json['defaultRowHeight'] as num?)?.toDouble() ?? 28.0,
      frozenColumns: json['frozenColumns'] as int? ?? 0,
      frozenRows: json['frozenRows'] as int? ?? 0,
    );

    final cellsList = json['cells'] as List<dynamic>? ?? [];
    for (final item in cellsList) {
      final map = item as Map<String, dynamic>;
      final addr = CellAddress.fromJson(map['addr'] as Map<String, dynamic>);
      final cell = CellNode.fromJson(map['cell'] as Map<String, dynamic>);
      model.setCell(addr, cell);
    }

    final colWidths = json['columnWidths'] as Map<String, dynamic>?;
    if (colWidths != null) {
      for (final entry in colWidths.entries) {
        model.setColumnWidth(
          int.parse(entry.key),
          (entry.value as num).toDouble(),
        );
      }
    }

    final rowHeights = json['rowHeights'] as Map<String, dynamic>?;
    if (rowHeights != null) {
      for (final entry in rowHeights.entries) {
        model.setRowHeight(
          int.parse(entry.key),
          (entry.value as num).toDouble(),
        );
      }
    }

    // Validations.
    final valList = json['validations'] as List<dynamic>? ?? [];
    for (final item in valList) {
      final map = item as Map<String, dynamic>;
      final addr = CellAddress.fromJson(map['addr'] as Map<String, dynamic>);
      final rule = CellValidation.fromJson(map['rule'] as Map<String, dynamic>);
      model.setValidation(addr, rule);
    }

    // Conditional formats.
    final cfList = json['conditionalFormats'] as List<dynamic>?;
    if (cfList != null) {
      model.conditionalFormats.loadFromJson(cfList);
    }

    // Named ranges.
    final namedRangesMap = json['namedRanges'] as Map<String, dynamic>?;
    if (namedRangesMap != null) {
      for (final e in namedRangesMap.entries) {
        model.setNamedRange(
          e.key,
          CellRange.fromJson(e.value as Map<String, dynamic>),
        );
      }
    }

    return model;
  }

  /// Create a deep copy.
  SpreadsheetModel clone() {
    final copy = SpreadsheetModel(
      defaultColumnWidth: defaultColumnWidth,
      defaultRowHeight: defaultRowHeight,
      frozenColumns: frozenColumns,
      frozenRows: frozenRows,
    );
    for (final entry in _cells.entries) {
      copy.setCell(entry.key, entry.value.clone());
    }
    for (final entry in _columnWidths.entries) {
      copy._columnWidths[entry.key] = entry.value;
    }
    for (final entry in _rowHeights.entries) {
      copy._rowHeights[entry.key] = entry.value;
    }
    for (final entry in _validations.entries) {
      copy._validations[entry.key] = entry.value;
    }
    // Clone conditional format rules.
    if (conditionalFormats.ruleCount > 0) {
      copy.conditionalFormats.loadFromJson(conditionalFormats.toJson());
    }
    for (final e in _namedRanges.entries) {
      copy._namedRanges[e.key] = e.value;
    }
    return copy;
  }

  @override
  String toString() =>
      'SpreadsheetModel(cells: $cellCount, maxCol: $maxColumn, maxRow: $maxRow)';
}
