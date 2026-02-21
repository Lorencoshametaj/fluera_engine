/// 📊 Cell address and range types for the tabular engine.
///
/// [CellAddress] is an immutable, hashable coordinate pair (column, row)
/// used as the primary key for sparse cell storage.
///
/// [CellRange] represents a rectangular region of cells for range
/// operations like `SUM(A1:C5)`.

// ---------------------------------------------------------------------------
// CellAddress
// ---------------------------------------------------------------------------

/// An immutable cell coordinate in a spreadsheet grid.
///
/// Columns and rows are 0-indexed internally. Use [fromLabel] for
/// Excel-style parsing (`A1` → column 0, row 0).
///
/// ```dart
/// final a1 = CellAddress(0, 0);      // A1
/// final b3 = CellAddress(1, 2);      // B3
/// final aa1 = CellAddress.fromLabel('AA1');
/// ```
class CellAddress implements Comparable<CellAddress> {
  /// 0-indexed column.
  final int column;

  /// 0-indexed row.
  final int row;

  const CellAddress(this.column, this.row);

  // -------------------------------------------------------------------------
  // Excel-style conversion
  // -------------------------------------------------------------------------

  /// Parse an Excel-style label like `A1`, `AB99`, `$C$5`.
  ///
  /// Dollar signs (absolute references) are stripped but recognized.
  factory CellAddress.fromLabel(String label) {
    final cleaned = label.replaceAll('\$', '').toUpperCase();
    int col = 0;
    int i = 0;
    while (i < cleaned.length && _isAlpha(cleaned.codeUnitAt(i))) {
      col = col * 26 + (cleaned.codeUnitAt(i) - 64); // A=1
      i++;
    }
    final row = int.parse(cleaned.substring(i));
    return CellAddress(col - 1, row - 1); // 0-indexed
  }

  /// Convert column index to Excel-style letters: 0→A, 25→Z, 26→AA.
  String get columnLabel {
    final buf = StringBuffer();
    int c = column + 1; // 1-indexed
    while (c > 0) {
      c--; // adjust for 0-based mod
      buf.write(String.fromCharCode(65 + c % 26));
      c ~/= 26;
    }
    // Reverse since we built least-significant first.
    return String.fromCharCodes(buf.toString().codeUnits.reversed);
  }

  /// Excel-style label: `A1`, `AA100`.
  String get label => '$columnLabel${row + 1}';

  // -------------------------------------------------------------------------
  // Comparable / equality
  // -------------------------------------------------------------------------

  @override
  int compareTo(CellAddress other) {
    final rowCmp = row.compareTo(other.row);
    if (rowCmp != 0) return rowCmp;
    return column.compareTo(other.column);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CellAddress && column == other.column && row == other.row;

  @override
  int get hashCode => Object.hash(column, row);

  @override
  String toString() => label;

  // -------------------------------------------------------------------------
  // JSON
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {'c': column, 'r': row};

  factory CellAddress.fromJson(Map<String, dynamic> json) =>
      CellAddress(json['c'] as int, json['r'] as int);

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static bool _isAlpha(int codeUnit) =>
      (codeUnit >= 65 && codeUnit <= 90) || // A-Z
      (codeUnit >= 97 && codeUnit <= 122); // a-z
}

// ---------------------------------------------------------------------------
// CellRange
// ---------------------------------------------------------------------------

/// A rectangular range of cells, e.g. `A1:C5`.
///
/// The range is inclusive on both ends. Iteration yields addresses in
/// row-major order.
///
/// ```dart
/// final range = CellRange(CellAddress(0, 0), CellAddress(2, 4));
/// for (final addr in range.addresses) { ... }
/// ```
class CellRange {
  /// Top-left corner (inclusive).
  final CellAddress start;

  /// Bottom-right corner (inclusive).
  final CellAddress end;

  CellRange(this.start, this.end);

  /// Parse from Excel-style string like `A1:C5`.
  factory CellRange.fromLabel(String label) {
    final parts = label.split(':');
    if (parts.length != 2) {
      throw FormatException('Invalid range label: $label');
    }
    return CellRange(
      CellAddress.fromLabel(parts[0]),
      CellAddress.fromLabel(parts[1]),
    );
  }

  /// Normalized start column (min of both).
  int get startColumn => start.column < end.column ? start.column : end.column;

  /// Normalized end column (max of both).
  int get endColumn => start.column > end.column ? start.column : end.column;

  /// Normalized start row (min of both).
  int get startRow => start.row < end.row ? start.row : end.row;

  /// Normalized end row (max of both).
  int get endRow => start.row > end.row ? start.row : end.row;

  /// Number of columns in the range.
  int get columnCount => endColumn - startColumn + 1;

  /// Number of rows in the range.
  int get rowCount => endRow - startRow + 1;

  /// Whether [addr] falls within this range.
  bool contains(CellAddress addr) =>
      addr.column >= startColumn &&
      addr.column <= endColumn &&
      addr.row >= startRow &&
      addr.row <= endRow;

  /// All addresses in row-major order.
  Iterable<CellAddress> get addresses sync* {
    for (int r = startRow; r <= endRow; r++) {
      for (int c = startColumn; c <= endColumn; c++) {
        yield CellAddress(c, r);
      }
    }
  }

  /// Excel-style label: `A1:C5`.
  String get label => '${start.label}:${end.label}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CellRange && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => label;

  Map<String, dynamic> toJson() => {
    'start': start.toJson(),
    'end': end.toJson(),
  };

  factory CellRange.fromJson(Map<String, dynamic> json) => CellRange(
    CellAddress.fromJson(json['start'] as Map<String, dynamic>),
    CellAddress.fromJson(json['end'] as Map<String, dynamic>),
  );
}
