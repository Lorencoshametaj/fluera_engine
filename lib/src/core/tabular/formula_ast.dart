import 'cell_address.dart';

/// 📊 Formula AST nodes for the tabular engine.
///
/// A recursive tree structure representing parsed spreadsheet formulas.
/// The evaluator walks this tree to compute cell values.
///
/// ```dart
/// // =A1 + SUM(B1:B10) * 2
/// BinaryOp(
///   left: CellRef(CellAddress(0, 0)),
///   op: '+',
///   right: BinaryOp(
///     left: FunctionCall('SUM', [RangeRef(...)]),
///     op: '*',
///     right: NumberLiteral(2),
///   ),
/// )
/// ```
sealed class FormulaNode {
  const FormulaNode();
}

/// A numeric literal: `42`, `3.14`.
class NumberLiteral extends FormulaNode {
  final double value;
  const NumberLiteral(this.value);

  @override
  String toString() => 'NumberLiteral($value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NumberLiteral && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// A string literal: `"hello"`.
class StringLiteral extends FormulaNode {
  final String value;
  const StringLiteral(this.value);

  @override
  String toString() => 'StringLiteral("$value")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StringLiteral && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// A boolean literal: `TRUE`, `FALSE`.
class BoolLiteral extends FormulaNode {
  final bool value;
  const BoolLiteral(this.value);

  @override
  String toString() => 'BoolLiteral($value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BoolLiteral && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// A single cell reference: `A1`, `$B$3`.
class CellRef extends FormulaNode {
  final CellAddress address;

  /// Whether the column is absolute (`$A`).
  final bool absoluteColumn;

  /// Whether the row is absolute (`$1`).
  final bool absoluteRow;

  const CellRef(
    this.address, {
    this.absoluteColumn = false,
    this.absoluteRow = false,
  });

  @override
  String toString() => 'CellRef(${address.label})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CellRef && address == other.address;

  @override
  int get hashCode => address.hashCode;
}

/// A range reference: `A1:C5`.
class RangeRef extends FormulaNode {
  final CellRange range;
  const RangeRef(this.range);

  @override
  String toString() => 'RangeRef(${range.label})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RangeRef && range == other.range;

  @override
  int get hashCode => range.hashCode;
}

/// A binary operation: `left op right`.
///
/// Supported operators: `+`, `-`, `*`, `/`, `^`, `%`,
/// `=`, `<>`, `<`, `>`, `<=`, `>=`, `&` (concatenation).
class BinaryOp extends FormulaNode {
  final FormulaNode left;
  final FormulaNode right;
  final String op;

  const BinaryOp({required this.left, required this.right, required this.op});

  @override
  String toString() => 'BinaryOp($left $op $right)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BinaryOp &&
          op == other.op &&
          left == other.left &&
          right == other.right;

  @override
  int get hashCode => Object.hash(op, left, right);
}

/// A unary operation: `op operand`.
///
/// Supported operators: `-` (negation), `+` (no-op), `%` (percentage).
class UnaryOp extends FormulaNode {
  final FormulaNode operand;
  final String op;

  const UnaryOp({required this.operand, required this.op});

  @override
  String toString() => 'UnaryOp($op $operand)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnaryOp && op == other.op && operand == other.operand;

  @override
  int get hashCode => Object.hash(op, operand);
}

/// A function call: `SUM(A1:A10, B1)`.
class FunctionCall extends FormulaNode {
  /// Function name (uppercase normalized).
  final String name;

  /// Arguments (may include ranges, expressions, etc.).
  final List<FormulaNode> args;

  const FunctionCall(this.name, this.args);

  @override
  String toString() => 'FunctionCall($name, $args)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FunctionCall &&
          name == other.name &&
          _listEquals(args, other.args);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(args));

  static bool _listEquals(List<FormulaNode> a, List<FormulaNode> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A cross-sheet cell reference: `Sheet2!A1`.
class SheetCellRef extends FormulaNode {
  /// The sheet name.
  final String sheetName;

  /// The cell address within that sheet.
  final CellAddress address;

  const SheetCellRef(this.sheetName, this.address);

  @override
  String toString() => 'SheetCellRef($sheetName!${address.label})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SheetCellRef &&
          sheetName == other.sheetName &&
          address == other.address;

  @override
  int get hashCode => Object.hash(sheetName, address);
}

/// A cross-sheet range reference: `Sheet2!A1:B10`.
class SheetRangeRef extends FormulaNode {
  /// The sheet name.
  final String sheetName;

  /// The cell range within that sheet.
  final CellRange range;

  const SheetRangeRef(this.sheetName, this.range);

  @override
  String toString() => 'SheetRangeRef($sheetName!${range.label})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SheetRangeRef &&
          sheetName == other.sheetName &&
          range == other.range;

  @override
  int get hashCode => Object.hash(sheetName, range);
}
