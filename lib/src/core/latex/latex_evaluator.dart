import 'dart:math' as math;

import 'latex_ast.dart';
import 'latex_parser.dart';

/// 🧮 LaTeX Expression Evaluator — evaluates a LaTeX AST for a given variable.
///
/// Walks the [LatexAstNode] tree produced by [LatexParser] and computes
/// a numeric [double] result.
///
/// ## Usage
/// ```dart
/// final ast = LatexParser.parse(r'\frac{x^2}{2}');
/// final y = LatexEvaluator.evaluate(ast, 3.0); // => 4.5
/// ```
///
/// ## Supported
/// - Arithmetic: `+`, `-`, `*`, `/`, implicit multiplication
/// - Powers: `x^{n}`
/// - Fractions: `\frac{a}{b}`
/// - Roots: `\sqrt{x}`, `\sqrt[3]{x}`
/// - Functions: `\sin`, `\cos`, `\tan`, `\log`, `\ln`, `\exp`, `\abs`
/// - Constants: `\pi`, `e`, `\infty`
/// - Parentheses/delimiters: `\left(...\right)`
///
/// Returns [double.nan] for undefined values.
class LatexEvaluator {
  LatexEvaluator._();

  /// Evaluate a LaTeX source string for the given [x] value.
  static double evaluateSource(String source, double x) {
    try {
      final ast = LatexParser.parse(source);
      return evaluate(ast, x);
    } catch (_) {
      return double.nan;
    }
  }

  /// Evaluate an AST node for the given [x] value.
  static double evaluate(LatexAstNode node, double x) {
    return _eval(node, x);
  }

  static double _eval(LatexAstNode node, double x) {
    switch (node) {
      case LatexSymbol():
        return _evalSymbol(node, x);

      case LatexGroup():
        return _evalGroup(node.children, x);

      case LatexFraction():
        final n = _eval(node.numerator, x);
        final d = _eval(node.denominator, x);
        if (d == 0) return double.nan;
        return n / d;

      case LatexSuperscript():
        final base = _eval(node.base, x);
        final exp = _eval(node.exponent, x);
        return math.pow(base, exp).toDouble();

      case LatexSubscript():
        // Subscripts don't change value — just evaluate the base
        return _eval(node.base, x);

      case LatexSubSuperscript():
        final base = _eval(node.base, x);
        final exp = _eval(node.superscript, x);
        return math.pow(base, exp).toDouble();

      case LatexSqrt():
        final radicand = _eval(node.radicand, x);
        if (node.degree != null) {
          final deg = _eval(node.degree!, x);
          if (deg == 0) return double.nan;
          return math.pow(radicand, 1.0 / deg).toDouble();
        }
        if (radicand < 0) return double.nan;
        return math.sqrt(radicand);

      case LatexBigOperator():
        // Simple evaluation: just return the symbol value (not evaluable as function)
        return double.nan;

      case LatexMatrix():
        return double.nan;

      case LatexDelimited():
        return _eval(node.body, x);

      case LatexText():
        return double.tryParse(node.text) ?? double.nan;

      case LatexSpace():
        return 0; // Spacing has no numeric value

      case LatexLimit():
        return double.nan; // Limits not evaluable

      case LatexAccent():
        return _eval(node.base, x);

      case LatexErrorNode():
        return double.nan;
    }
  }

  static double _evalSymbol(LatexSymbol sym, double x) {
    final v = sym.value;

    // Variable
    if (v == 'x' || v == 'X') return x;

    // Known constants
    if (v == 'π' || v == 'pi') return math.pi;
    if (v == 'e') return math.e;
    if (v == '∞' || v == 'infty') return double.infinity;

    // Digits
    final d = double.tryParse(v);
    if (d != null) return d;

    // Operators (returned as special markers for group evaluation)
    if (v == '+' ||
        v == '-' ||
        v == '*' ||
        v == '/' ||
        v == '×' ||
        v == '÷' ||
        v == '·' ||
        v == '(' ||
        v == ')' ||
        v == '=' ||
        v == '<' ||
        v == '>') {
      return double.nan; // Handled in group context
    }

    return double.nan;
  }

  /// Evaluate a group of children with infix operators.
  static double _evalGroup(List<LatexAstNode> children, double x) {
    if (children.isEmpty) return double.nan;
    if (children.length == 1) return _eval(children.first, x);

    // Flatten to a sequence of (values, operators)
    final values = <double>[];
    final ops = <String>[];

    for (int i = 0; i < children.length; i++) {
      final child = children[i];

      // Check if it's a function call (sin, cos, etc.) followed by arg
      if (child is LatexSymbol &&
          _isFunction(child.value) &&
          i + 1 < children.length) {
        final arg = _eval(children[i + 1], x);
        values.add(_applyFunction(child.value, arg));
        i++; // skip the argument
        continue;
      }

      // Check if it's an operator symbol
      if (child is LatexSymbol && _isOperator(child.value)) {
        final op = child.value;
        if (values.isEmpty && op == '-') {
          // Unary minus
          values.add(0);
        }
        ops.add(op);
        continue;
      }

      final val = _eval(child, x);
      if (!val.isNaN) {
        // Implicit multiplication if previous value exists and no operator
        if (values.length > ops.length) {
          ops.add('*');
        }
        values.add(val);
      }
    }

    if (values.isEmpty) return double.nan;
    if (values.length == 1) return values.first;

    // Apply operator precedence: first * and /, then + and -
    // Phase 1: multiply and divide
    final v2 = <double>[values.first];
    final o2 = <String>[];
    for (int i = 0; i < ops.length && i < values.length - 1; i++) {
      final op = ops[i];
      final right = values[i + 1];
      if (op == '*' || op == '×' || op == '·') {
        v2[v2.length - 1] = v2.last * right;
      } else if (op == '/' || op == '÷') {
        if (right == 0) return double.nan;
        v2[v2.length - 1] = v2.last / right;
      } else {
        v2.add(right);
        o2.add(op);
      }
    }

    // Phase 2: add and subtract
    var result = v2.first;
    for (int i = 0; i < o2.length && i < v2.length - 1; i++) {
      if (o2[i] == '+') {
        result += v2[i + 1];
      } else if (o2[i] == '-') {
        result -= v2[i + 1];
      }
    }

    return result;
  }

  static bool _isOperator(String v) {
    return v == '+' ||
        v == '-' ||
        v == '*' ||
        v == '/' ||
        v == '×' ||
        v == '÷' ||
        v == '·';
  }

  static bool _isFunction(String v) {
    return const {
      'sin',
      'cos',
      'tan',
      'log',
      'ln',
      'exp',
      'abs',
      'asin',
      'acos',
      'atan',
      'sinh',
      'cosh',
      'tanh',
      'sec',
      'csc',
      'cot',
    }.contains(v);
  }

  static double _applyFunction(String name, double arg) {
    switch (name) {
      case 'sin':
        return math.sin(arg);
      case 'cos':
        return math.cos(arg);
      case 'tan':
        return math.tan(arg);
      case 'log':
        return arg > 0 ? math.log(arg) / math.ln10 : double.nan;
      case 'ln':
        return arg > 0 ? math.log(arg) : double.nan;
      case 'exp':
        return math.exp(arg);
      case 'abs':
        return arg.abs();
      case 'asin':
        return arg >= -1 && arg <= 1 ? math.asin(arg) : double.nan;
      case 'acos':
        return arg >= -1 && arg <= 1 ? math.acos(arg) : double.nan;
      case 'atan':
        return math.atan(arg);
      case 'sinh':
        return (math.exp(arg) - math.exp(-arg)) / 2;
      case 'cosh':
        return (math.exp(arg) + math.exp(-arg)) / 2;
      case 'tanh':
        final ep = math.exp(arg);
        final em = math.exp(-arg);
        return (ep - em) / (ep + em);
      case 'sec':
        final c = math.cos(arg);
        return c == 0 ? double.nan : 1 / c;
      case 'csc':
        final s = math.sin(arg);
        return s == 0 ? double.nan : 1 / s;
      case 'cot':
        final t = math.tan(arg);
        return t == 0 ? double.nan : 1 / t;
      default:
        return double.nan;
    }
  }
}
