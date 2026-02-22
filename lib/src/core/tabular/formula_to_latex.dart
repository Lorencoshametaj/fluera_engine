import 'cell_address.dart';
import 'cell_value.dart';
import 'formula_ast.dart';
import 'formula_parser.dart';
import 'spreadsheet_evaluator.dart';

/// Mode for formula translation.
enum FormulaTranslateMode {
  /// Keep cell references as symbolic variables (e.g. A1 → a_{1}).
  symbolic,

  /// Substitute cell references with their evaluated values.
  evaluated,
}

/// 📊 Translates Excel-style formula ASTs into LaTeX math expressions.
///
/// Walks the [FormulaNode] AST produced by [FormulaParser] and generates
/// semantically correct LaTeX math notation.
///
/// ## Translation Rules
///
/// | Excel | LaTeX |
/// |---|---|
/// | `A1 + B1` | `a_{1} + b_{1}` |
/// | `A1 / B1` | `\frac{a_{1}}{b_{1}}` |
/// | `SUM(A1:A5)` | `\sum_{i=1}^{5} a_{i}` |
/// | `SQRT(A1)` | `\sqrt{a_{1}}` |
/// | `ABS(A1)` | `\left\|a_{1}\right\|` |
/// | `A1 ^ 2` | `{a_{1}}^{2}` |
///
/// ## Usage
///
/// ```dart
/// final translator = FormulaToLatex(evaluator);
/// final latex = translator.translateFormula('=SUM(A1:A5)/COUNT(A1:A5)');
/// // → \frac{\sum_{i=1}^{5} a_{i}}{5}
/// ```
class FormulaToLatex {
  final SpreadsheetEvaluator? _evaluator;

  FormulaToLatex([this._evaluator]);

  /// Translate an Excel formula string (with or without `=` prefix) to LaTeX.
  String translateFormula(
    String formula, {
    FormulaTranslateMode mode = FormulaTranslateMode.symbolic,
  }) {
    var src = formula.trim();
    if (src.startsWith('=')) src = src.substring(1);
    if (src.isEmpty) return '';

    try {
      final ast = FormulaParser.parse(src);
      return translate(ast, mode: mode);
    } catch (_) {
      // If parsing fails, return the raw formula escaped
      return '\\text{$src}';
    }
  }

  /// Translate a [FormulaNode] AST to LaTeX math string.
  String translate(
    FormulaNode node, {
    FormulaTranslateMode mode = FormulaTranslateMode.symbolic,
  }) {
    return _visit(node, mode);
  }

  // ---------------------------------------------------------------------------
  // AST visitor
  // ---------------------------------------------------------------------------

  String _visit(FormulaNode node, FormulaTranslateMode mode) {
    return switch (node) {
      NumberLiteral n => _visitNumber(n),
      StringLiteral s => _visitString(s),
      BoolLiteral b => _visitBool(b),
      CellRef c => _visitCellRef(c, mode),
      RangeRef r => _visitRangeRef(r),
      BinaryOp b => _visitBinary(b, mode),
      UnaryOp u => _visitUnary(u, mode),
      FunctionCall f => _visitFunction(f, mode),
      SheetCellRef s => _visitSheetCellRef(s, mode),
      SheetRangeRef s => _visitSheetRangeRef(s),
    };
  }

  String _visitNumber(NumberLiteral n) {
    final val = n.value;
    if (val == val.toInt().toDouble()) return val.toInt().toString();
    return val.toString();
  }

  String _visitString(StringLiteral s) => '\\text{${s.value}}';

  String _visitBool(BoolLiteral b) =>
      b.value ? '\\text{TRUE}' : '\\text{FALSE}';

  String _visitCellRef(CellRef ref, FormulaTranslateMode mode) {
    if (mode == FormulaTranslateMode.evaluated && _evaluator != null) {
      final val = _evaluator.getComputedValue(ref.address);
      if (val is NumberValue)
        return _visitNumber(NumberLiteral(val.value.toDouble()));
      if (val is TextValue) return '\\text{${val.value}}';
      return '0';
    }
    // Symbolic: A1 → a_{1}, B3 → b_{3}
    return _cellToSymbol(ref.address);
  }

  String _visitRangeRef(RangeRef ref) {
    return '${_cellToSymbol(ref.range.start)}:{${_cellToSymbol(ref.range.end)}}';
  }

  String _visitSheetCellRef(SheetCellRef ref, FormulaTranslateMode mode) {
    return _visitCellRef(CellRef(ref.address), mode);
  }

  String _visitSheetRangeRef(SheetRangeRef ref) {
    return _visitRangeRef(RangeRef(ref.range));
  }

  String _visitBinary(BinaryOp op, FormulaTranslateMode mode) {
    final left = _visit(op.left, mode);
    final right = _visit(op.right, mode);

    switch (op.op) {
      case '/':
        return '\\frac{$left}{$right}';
      case '*':
        return '$left \\cdot $right';
      case '^':
        return '{$left}^{$right}';
      case '+':
        return '$left + $right';
      case '-':
        return '$left - $right';
      case '>=':
        return '$left \\geq $right';
      case '<=':
        return '$left \\leq $right';
      case '<>':
      case '!=':
        return '$left \\neq $right';
      case '>':
        return '$left > $right';
      case '<':
        return '$left < $right';
      case '=':
        return '$left = $right';
      default:
        return '$left \\; \\text{${op.op}} \\; $right';
    }
  }

  String _visitUnary(UnaryOp op, FormulaTranslateMode mode) {
    final operand = _visit(op.operand, mode);
    switch (op.op) {
      case '-':
        return '-$operand';
      case '+':
        return operand;
      default:
        return '${op.op}$operand';
    }
  }

  String _visitFunction(FunctionCall func, FormulaTranslateMode mode) {
    final name = func.name.toUpperCase();

    switch (name) {
      case 'SUM':
        return _translateSum(func, mode);
      case 'AVERAGE':
      case 'AVG':
        return _translateAverage(func, mode);
      case 'SQRT':
        if (func.args.length == 1) {
          return '\\sqrt{${_visit(func.args[0], mode)}}';
        }
        break;
      case 'ABS':
        if (func.args.length == 1) {
          return '\\left|${_visit(func.args[0], mode)}\\right|';
        }
        break;
      case 'MIN':
        return '\\min\\left(${func.args.map((a) => _visit(a, mode)).join(', ')}\\right)';
      case 'MAX':
        return '\\max\\left(${func.args.map((a) => _visit(a, mode)).join(', ')}\\right)';
      case 'COUNT':
        if (func.args.length == 1 && func.args[0] is RangeRef) {
          final range = (func.args[0] as RangeRef).range;
          final n =
              (range.end.row - range.start.row + 1) *
              (range.end.column - range.start.column + 1);
          return n.toString();
        }
        break;
      case 'LOG':
        if (func.args.length == 1) {
          return '\\log\\left(${_visit(func.args[0], mode)}\\right)';
        } else if (func.args.length == 2) {
          return '\\log_{${_visit(func.args[1], mode)}}\\left(${_visit(func.args[0], mode)}\\right)';
        }
        break;
      case 'LN':
        if (func.args.length == 1) {
          return '\\ln\\left(${_visit(func.args[0], mode)}\\right)';
        }
        break;
      case 'SIN':
      case 'COS':
      case 'TAN':
        if (func.args.length == 1) {
          return '\\${name.toLowerCase()}\\left(${_visit(func.args[0], mode)}\\right)';
        }
        break;
      case 'PI':
        return '\\pi';
      case 'EXP':
        if (func.args.length == 1) {
          return 'e^{${_visit(func.args[0], mode)}}';
        }
        break;
      case 'POWER':
        if (func.args.length == 2) {
          return '{${_visit(func.args[0], mode)}}^{${_visit(func.args[1], mode)}}';
        }
        break;
      case 'IF':
        if (func.args.length == 3) {
          return '\\begin{cases} ${_visit(func.args[1], mode)} & \\text{if } ${_visit(func.args[0], mode)} \\\\ ${_visit(func.args[2], mode)} & \\text{otherwise} \\end{cases}';
        }
        break;
    }

    // Fallback: generic function notation
    final args = func.args.map((a) => _visit(a, mode)).join(', ');
    return '\\operatorname{${name.toLowerCase()}}\\left($args\\right)';
  }

  // ---------------------------------------------------------------------------
  // Specialized translations
  // ---------------------------------------------------------------------------

  String _translateSum(FunctionCall func, FormulaTranslateMode mode) {
    if (func.args.length == 1 && func.args[0] is RangeRef) {
      final range = (func.args[0] as RangeRef).range;
      if (range.start.column == range.end.column) {
        // Vertical sum: Σ_{i=start}^{end} col_i
        final col = String.fromCharCode(97 + range.start.column); // lowercase
        return '\\sum_{i=${range.start.row + 1}}^{${range.end.row + 1}} ${col}_{i}';
      }
    }
    // Fallback
    final args = func.args.map((a) => _visit(a, mode)).join(', ');
    return '\\sum\\left($args\\right)';
  }

  String _translateAverage(FunctionCall func, FormulaTranslateMode mode) {
    if (func.args.length == 1 && func.args[0] is RangeRef) {
      final range = (func.args[0] as RangeRef).range;
      if (range.start.column == range.end.column) {
        final col = String.fromCharCode(97 + range.start.column);
        final n = range.end.row - range.start.row + 1;
        return '\\frac{1}{$n}\\sum_{i=${range.start.row + 1}}^{${range.end.row + 1}} ${col}_{i}';
      }
    }
    final args = func.args.map((a) => _visit(a, mode)).join(', ');
    return '\\overline{$args}';
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  /// Convert a CellAddress to a mathematical symbol (A1 → a₁).
  String _cellToSymbol(CellAddress addr) {
    final col = String.fromCharCode(97 + addr.column); // a, b, c...
    return '${col}_{${addr.row + 1}}';
  }
}
