import 'dart:math' as math;

import 'latex_ast.dart';
import 'latex_parser.dart';

// =============================================================================
// LATEX EVALUATOR — Scientific Calculator
// =============================================================================

/// 🧮 Exception thrown when a LaTeX expression cannot be evaluated numerically.
class EvaluationException implements Exception {
  final String message;
  const EvaluationException(this.message);

  @override
  String toString() => 'EvaluationException: $message';
}

/// 🧮 LatexEvaluator — tree-walking evaluator for numeric LaTeX expressions.
///
/// Walks the [LatexAstNode] tree produced by [LatexParser] and computes a
/// numeric `double` result. Pure Dart, zero external dependencies.
///
/// ## Supported
/// - Arithmetic: `+`, `-`, `×`/`·`/`\times`/`\cdot`, `÷`/`\div`
/// - Fractions: `\frac{a}{b}`
/// - Exponents: `x^{n}`
/// - Square/nth roots: `\sqrt{x}`, `\sqrt[n]{x}`
/// - Constants: `\pi`, `e`
/// - Variables: `x`, `y`, `t` (with binding map via [evaluateWith])
/// - Functions: `\sin`, `\cos`, `\tan`, `\ln`, `\log`, `\arcsin`, `\arccos`,
///   `\arctan`, `\sinh`, `\cosh`, `\tanh`
/// - Absolute value: `|x|` via `\left| \right|`
/// - Parentheses / delimiters (grouping)
/// - Implicit multiplication: `2\pi`, `3(4+5)`
/// - Unary minus: `-3`, `-(2+1)`
/// - Factorial: `n!`
///
/// ## Usage
/// ```dart
/// // Constant evaluation
/// LatexEvaluator.evaluate(r'\frac{1+2}{3}'); // 1.0
///
/// // Function of x
/// LatexEvaluator.evaluateWith(r'x^2', {'x': 3}); // 9.0
///
/// // Generate plot points
/// LatexEvaluator.generatePoints(r'\sin{x}', 'x', -3.14, 3.14, 200);
/// ```
class LatexEvaluator {
  const LatexEvaluator._();

  /// Current variable bindings — set during [evaluateWith] / [generatePoints].
  static Map<String, double> _bindings = const {};

  /// When `true`, trigonometric functions expect arguments in degrees.
  /// Default is `false` (radians).
  static bool useDegrees = false;

  static double _degToRad(double d) => d * math.pi / 180;
  static double _radToDeg(double r) => r * 180 / math.pi;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Evaluate a LaTeX string and return the numeric result.
  ///
  /// Throws [EvaluationException] if the expression contains unbound
  /// variables, unsupported constructs, or is otherwise not evaluable.
  static double evaluate(String latex) {
    if (latex.trim().isEmpty) {
      throw const EvaluationException('Espressione vuota');
    }
    final ast = LatexParser.parse(latex);
    _bindings = const {};
    try {
      return _evaluateNode(ast);
    } finally {
      _bindings = const {};
    }
  }

  /// Evaluate a LaTeX string with variable bindings.
  ///
  /// ```dart
  /// LatexEvaluator.evaluateWith(r'x^2 + 1', {'x': 3}); // 10.0
  /// ```
  static double evaluateWith(String latex, Map<String, double> variables) {
    if (latex.trim().isEmpty) {
      throw const EvaluationException('Espressione vuota');
    }
    final ast = LatexParser.parse(latex);
    _bindings = variables;
    try {
      return _evaluateNode(ast);
    } finally {
      _bindings = const {};
    }
  }

  /// Returns `true` if [latex] can be evaluated to a numeric value.
  static bool canEvaluate(String latex) {
    if (latex.trim().isEmpty) return false;
    try {
      final result = evaluate(latex);
      return !result.isNaN;
    } on EvaluationException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Returns `true` if [latex] contains the given variable name.
  ///
  /// Checks the AST for italic `LatexSymbol` nodes matching [varName].
  static bool containsVariable(String latex, String varName) {
    if (latex.trim().isEmpty) return false;
    try {
      final ast = LatexParser.parse(latex);
      return _nodeContainsVar(ast, varName);
    } catch (_) {
      return false;
    }
  }

  /// Generate (x, y) sample points for f(x) over [xMin, xMax].
  ///
  /// Returns a list of `(x, y)` pairs. Points where the function is
  /// undefined (NaN, ±∞, or throws) are returned as `(x, double.nan)`.
  static List<(double, double)> generatePoints(
    String latex,
    String varName,
    double xMin,
    double xMax,
    int steps,
  ) {
    if (steps < 2) steps = 2;
    final ast = LatexParser.parse(latex);
    final dx = (xMax - xMin) / (steps - 1);
    final points = <(double, double)>[];

    for (var i = 0; i < steps; i++) {
      final x = xMin + i * dx;
      _bindings = {varName: x};
      try {
        final y = _evaluateNode(ast);
        points.add((x, (y.isFinite) ? y : double.nan));
      } on EvaluationException {
        points.add((x, double.nan));
      } catch (_) {
        points.add((x, double.nan));
      }
    }

    _bindings = const {};
    return points;
  }

  /// Recursively check if an AST contains a reference to [varName].
  static bool _nodeContainsVar(LatexAstNode node, String varName) {
    return switch (node) {
      LatexSymbol() => node.italic && node.value == varName,
      LatexGroup() => node.children.any((c) => _nodeContainsVar(c, varName)),
      LatexFraction() =>
        _nodeContainsVar(node.numerator, varName) ||
            _nodeContainsVar(node.denominator, varName),
      LatexSuperscript() =>
        _nodeContainsVar(node.base, varName) ||
            _nodeContainsVar(node.exponent, varName),
      LatexSubscript() =>
        _nodeContainsVar(node.base, varName) ||
            _nodeContainsVar(node.subscript, varName),
      LatexSubSuperscript() =>
        _nodeContainsVar(node.base, varName) ||
            _nodeContainsVar(node.subscript, varName) ||
            _nodeContainsVar(node.superscript, varName),
      LatexSqrt() =>
        _nodeContainsVar(node.radicand, varName) ||
            (node.degree != null && _nodeContainsVar(node.degree!, varName)),
      LatexDelimited() => _nodeContainsVar(node.body, varName),
      LatexAccent() => _nodeContainsVar(node.base, varName),
      LatexBigOperator() => false,
      LatexLimit() => false,
      LatexMatrix() => node.rows.any(
        (r) => r.any((c) => _nodeContainsVar(c, varName)),
      ),
      LatexText() => false,
      LatexSpace() => false,
      LatexErrorNode() => false,
      LatexColored() => _nodeContainsVar(node.body, varName),
      LatexBoxed() => _nodeContainsVar(node.body, varName),
      LatexUnderOver() =>
        _nodeContainsVar(node.body, varName) ||
            _nodeContainsVar(node.annotation, varName),
      LatexCancel() => _nodeContainsVar(node.body, varName),
      LatexPhantom() => false,
      LatexCases() => node.rows.any(
        (r) => r.any((c) => _nodeContainsVar(c, varName)),
      ),
      LatexExtensibleArrow() => false,
      LatexAlign() => node.rows.any(
        (r) => r.any((c) => _nodeContainsVar(c, varName)),
      ),
      LatexColorBox() => _nodeContainsVar(node.body, varName),
      LatexRule() => false,
    };
  }

  /// Format a double result for display.
  ///
  /// - Integers are shown without decimals: `4.0` → `4`
  /// - Up to 10 significant decimal places
  /// - Scientific notation for very large/small numbers
  static String formatResult(double value) {
    if (value.isInfinite) return value.isNegative ? '-∞' : '∞';
    if (value.isNaN) return 'NaN';

    // Check if it's effectively an integer
    if (value == value.truncateToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }

    // Try fixed notation first
    final fixed = value.toStringAsFixed(10);
    // Trim trailing zeros
    var trimmed = fixed;
    if (trimmed.contains('.')) {
      trimmed = trimmed.replaceAll(RegExp(r'0+$'), '');
      trimmed = trimmed.replaceAll(RegExp(r'\.$'), '');
    }

    // Use scientific notation for very large/small numbers
    if (value.abs() >= 1e12 || (value.abs() < 1e-6 && value != 0)) {
      return value.toStringAsPrecision(6);
    }

    return trimmed;
  }

  // ---------------------------------------------------------------------------
  // Core evaluator — dispatch on AST node type
  // ---------------------------------------------------------------------------

  static double _evaluateNode(LatexAstNode node) {
    return switch (node) {
      LatexSymbol() => _evaluateSymbol(node),
      LatexGroup() => _evaluateGroup(node),
      LatexFraction() => _evaluateFraction(node),
      LatexSuperscript() => _evaluateSuperscript(node),
      LatexSubscript() => _evaluateSubscript(node),
      LatexSubSuperscript() => _evaluateSubSuperscript(node),
      LatexSqrt() => _evaluateSqrt(node),
      LatexDelimited() => _evaluateDelimited(node),
      LatexBigOperator() => _evaluateBigOperator(node),
      LatexLimit() => throw const EvaluationException('Limiti non supportati'),
      LatexMatrix() =>
        throw const EvaluationException('Matrici non supportate'),
      LatexText() => throw EvaluationException('_function_:${node.text}'),
      LatexSpace() => throw const EvaluationException('_space_'),
      LatexAccent() => _evaluateNode(node.base),
      LatexErrorNode() =>
        throw EvaluationException('Errore di parsing: ${node.message}'),
      LatexColored() => _evaluateNode(node.body),
      LatexBoxed() => _evaluateNode(node.body),
      LatexUnderOver() => _evaluateNode(node.body),
      LatexCancel() => _evaluateNode(node.body),
      LatexPhantom() => 0.0,
      LatexCases() =>
        throw const EvaluationException('Cases non supportate'),
      LatexExtensibleArrow() =>
        throw const EvaluationException('Frecce non supportate'),
      LatexAlign() =>
        throw const EvaluationException('Align non supportato'),
      LatexColorBox() => _evaluateNode(node.body),
      LatexRule() => 0.0,
    };
  }

  // ---------------------------------------------------------------------------
  // Function application
  // ---------------------------------------------------------------------------

  /// Known mathematical functions (parser emits these as LatexText nodes).
  static const _knownFunctions = {
    'sin',
    'cos',
    'tan',
    'cot',
    'sec',
    'csc',
    'arcsin',
    'arccos',
    'arctan',
    'sinh',
    'cosh',
    'tanh',
    'coth',
    'ln',
    'log',
    'lg',
    'exp',
    'abs',
    'mod',
  };

  /// Apply a named mathematical function to an argument.
  ///
  /// When [useDegrees] is `true`, trigonometric functions convert
  /// arguments from degrees to radians, and inverse functions convert
  /// results from radians to degrees.
  static double _applyFunction(String name, double arg) {
    // Degree → radian conversion for trig functions
    final a = (useDegrees && _isTrigDirect(name)) ? _degToRad(arg) : arg;

    final result = switch (name) {
      'sin' => math.sin(a),
      'cos' => math.cos(a),
      'tan' => math.tan(a),
      'cot' => 1.0 / math.tan(a),
      'sec' => 1.0 / math.cos(a),
      'csc' => 1.0 / math.sin(a),
      'arcsin' => math.asin(arg),
      'arccos' => math.acos(arg),
      'arctan' => math.atan(arg),
      'sinh' => (math.exp(arg) - math.exp(-arg)) / 2,
      'cosh' => (math.exp(arg) + math.exp(-arg)) / 2,
      'tanh' =>
        (math.exp(arg) - math.exp(-arg)) / (math.exp(arg) + math.exp(-arg)),
      'coth' =>
        (math.exp(arg) + math.exp(-arg)) / (math.exp(arg) - math.exp(-arg)),
      'ln' => math.log(arg),
      'log' => math.log(arg) / math.ln10,
      'lg' => math.log(arg) / math.ln10,
      'exp' => math.exp(arg),
      'abs' => arg.abs(),
      _ => throw EvaluationException('Funzione "$name" non supportata'),
    };

    // Radian → degree conversion for inverse trig
    if (useDegrees && _isTrigInverse(name)) return _radToDeg(result);
    return result;
  }

  static bool _isTrigDirect(String fn) =>
      const {'sin', 'cos', 'tan', 'cot', 'sec', 'csc'}.contains(fn);

  static bool _isTrigInverse(String fn) =>
      const {'arcsin', 'arccos', 'arctan'}.contains(fn);

  // ---------------------------------------------------------------------------
  // Symbol evaluation
  // ---------------------------------------------------------------------------

  static double _evaluateSymbol(LatexSymbol node) {
    final v = node.value;

    // Numeric digit
    if (_isDigitOrDot(v)) {
      return double.tryParse(v) ??
          (throw EvaluationException('Numero non valido: "$v"'));
    }

    // Constants
    if (v == 'π') return math.pi;
    if (v == 'e' && !node.italic) return math.e;
    if (v == '∞') return double.infinity;

    // Operators — returned as sentinel (handled in group evaluation)
    if (_isOperator(v)) {
      throw EvaluationException('_operator_:$v');
    }

    // Factorial symbol
    if (v == '!') {
      throw const EvaluationException('_factorial_');
    }

    // Percentage symbol
    if (v == '%') {
      throw const EvaluationException('_percent_');
    }

    // Variable resolution from bindings
    if (node.italic && v.length == 1 && _bindings.containsKey(v)) {
      return _bindings[v]!;
    }

    // Unbound variable
    throw EvaluationException('Variabile non risolvibile: "$v"');
  }

  // ---------------------------------------------------------------------------
  // Group evaluation — handles infix operators with precedence
  // ---------------------------------------------------------------------------

  static double _evaluateGroup(LatexGroup node) {
    if (node.children.isEmpty) {
      throw const EvaluationException('Espressione vuota');
    }
    if (node.children.length == 1) {
      return _evaluateNode(node.children.first);
    }

    // Tokenize group children into values and operators
    final tokens = _tokenizeGroup(node.children);

    // Evaluate using shunting-yard-style precedence
    return _evaluateTokens(tokens);
  }

  /// Collect consecutive digit symbols into a single multi-digit number.
  ///
  /// e.g. children [LatexSymbol('1'), LatexSymbol('2'), LatexSymbol('3')]
  /// → returns (123.0, 3) where 3 is how many children were consumed.
  static (double, int)? _tryParseNumber(
    List<LatexAstNode> children,
    int start,
  ) {
    final buf = StringBuffer();
    var i = start;
    while (i < children.length) {
      final child = children[i];
      if (child is LatexSymbol && _isDigitOrDot(child.value)) {
        buf.write(child.value);
        i++;
      } else {
        break;
      }
    }
    if (buf.isEmpty) return null;
    final parsed = double.tryParse(buf.toString());
    if (parsed == null) return null;
    return (parsed, i - start);
  }

  /// Convert AST children into a flat list of _Token (numbers and operators).
  static List<_Token> _tokenizeGroup(List<LatexAstNode> children) {
    final tokens = <_Token>[];

    for (var i = 0; i < children.length; i++) {
      final child = children[i];

      // Skip spaces
      if (child is LatexSpace) continue;

      // ── Multi-digit number grouping ──
      // Try to consume consecutive digit symbols as one number
      if (child is LatexSymbol && _isDigitOrDot(child.value)) {
        final numResult = _tryParseNumber(children, i);
        if (numResult != null) {
          final (value, consumed) = numResult;
          if (tokens.isNotEmpty && tokens.last.isValue) {
            tokens.add(const _Token.op('×'));
          }
          tokens.add(_Token.value(value));
          i += consumed - 1; // -1 because the for loop increments
          continue;
        }
      }

      // ── Modulo operator (binary, not unary function) ──
      if (child is LatexText && child.text == 'mod') {
        tokens.add(const _Token.op('mod'));
        continue;
      }

      // ── Function application ──
      // LatexText nodes for known functions: consume next sibling as argument
      if (child is LatexText && _knownFunctions.contains(child.text)) {
        // Look for the argument (next non-space child)
        var argIdx = i + 1;
        while (argIdx < children.length && children[argIdx] is LatexSpace) {
          argIdx++;
        }
        if (argIdx < children.length) {
          final argNode = children[argIdx];
          final argValue = _evaluateNode(argNode);
          final result = _applyFunction(child.text, argValue);
          if (tokens.isNotEmpty && tokens.last.isValue) {
            tokens.add(const _Token.op('×'));
          }
          tokens.add(_Token.value(result));
          i = argIdx; // skip consumed argument
          continue;
        }
        throw EvaluationException('Funzione "${child.text}" senza argomento');
      }

      // Try to evaluate as a value
      try {
        final value = _evaluateNode(child);
        // Check for implicit multiplication:
        // number × number, number × (group), etc.
        if (tokens.isNotEmpty && tokens.last.isValue) {
          tokens.add(const _Token.op('×'));
        }
        tokens.add(_Token.value(value));
      } on EvaluationException catch (e) {
        final msg = e.message;

        if (msg.startsWith('_operator_:')) {
          final op = msg.substring('_operator_:'.length);

          // Handle unary minus: minus at start or after another operator
          if ((op == '-' || op == '−') &&
              (tokens.isEmpty || tokens.last.isOp)) {
            tokens.add(const _Token.op('unary-'));
            continue;
          }

          // Handle unary plus: just skip it
          if (op == '+' && (tokens.isEmpty || tokens.last.isOp)) {
            continue;
          }

          tokens.add(_Token.op(op));
        } else if (msg == '_space_') {
          continue;
        } else if (msg == '_factorial_') {
          // Apply factorial to the last value
          if (tokens.isNotEmpty && tokens.last.isValue) {
            final val = tokens.removeLast().numValue;
            tokens.add(_Token.value(_factorial(val)));
          }
        } else if (msg == '_percent_') {
          // Apply percentage: divide previous value by 100
          if (tokens.isNotEmpty && tokens.last.isValue) {
            final val = tokens.removeLast().numValue;
            tokens.add(_Token.value(val / 100));
          }
        } else if (msg.startsWith('_function_:')) {
          // Standalone function without argument in a single-child context
          final fname = msg.substring('_function_:'.length);
          if (!_knownFunctions.contains(fname)) {
            throw EvaluationException('Testo non valutabile: "$fname"');
          }
          // Try to consume next child as argument
          var argIdx = i + 1;
          while (argIdx < children.length && children[argIdx] is LatexSpace) {
            argIdx++;
          }
          if (argIdx < children.length) {
            final argValue = _evaluateNode(children[argIdx]);
            final result = _applyFunction(fname, argValue);
            if (tokens.isNotEmpty && tokens.last.isValue) {
              tokens.add(const _Token.op('×'));
            }
            tokens.add(_Token.value(result));
            i = argIdx;
          } else {
            throw EvaluationException('Funzione "$fname" senza argomento');
          }
        } else if (msg.startsWith('_logbase_:')) {
          // Log with custom base: log_b{arg}
          final base = double.parse(msg.substring('_logbase_:'.length));
          var argIdx = i + 1;
          while (argIdx < children.length && children[argIdx] is LatexSpace) {
            argIdx++;
          }
          if (argIdx < children.length) {
            final argValue = _evaluateNode(children[argIdx]);
            if (argValue <= 0) {
              throw const EvaluationException(
                'Argomento del logaritmo deve essere > 0',
              );
            }
            final result = math.log(argValue) / math.log(base);
            if (tokens.isNotEmpty && tokens.last.isValue) {
              tokens.add(const _Token.op('×'));
            }
            tokens.add(_Token.value(result));
            i = argIdx;
          } else {
            throw const EvaluationException('Logaritmo senza argomento');
          }
        } else if (msg.startsWith('_sumop_:')) {
          // Finite sum or product: ∑_{i=start}^{end} body
          final parts = msg.split(':');
          // parts: ['_sumop_', '∑'|'∏', varName, start, end]
          final opSymbol = parts[1];
          final varName = parts[2];
          final start = int.parse(parts[3]);
          final end = int.parse(parts[4]);
          final isProduct = opSymbol == '∏';

          // Consume next child as the body expression
          var bodyIdx = i + 1;
          while (bodyIdx < children.length && children[bodyIdx] is LatexSpace) {
            bodyIdx++;
          }
          if (bodyIdx >= children.length) {
            throw EvaluationException(
              '${isProduct ? "Produttoria" : "Sommatoria"} senza corpo',
            );
          }

          // Save current bindings, evaluate body for each value
          final savedBindings = Map<String, double>.from(_bindings);
          var acc = isProduct ? 1.0 : 0.0;
          for (var idx = start; idx <= end; idx++) {
            _bindings = {...savedBindings, varName: idx.toDouble()};
            final bodyValue = _evaluateNode(children[bodyIdx]);
            if (isProduct) {
              acc *= bodyValue;
            } else {
              acc += bodyValue;
            }
          }
          _bindings = savedBindings;

          if (tokens.isNotEmpty && tokens.last.isValue) {
            tokens.add(const _Token.op('×'));
          }
          tokens.add(_Token.value(acc));
          i = bodyIdx;
        } else if (msg.startsWith('_integral_:')) {
          // Definite integral: ∫_{a}^{b} f(x) — Simpson's rule
          final parts = msg.substring('_integral_:'.length).split(':');
          final a = double.parse(parts[0]);
          final b = double.parse(parts[1]);

          // Consume next child as the body (integrand)
          var bodyIdx = i + 1;
          while (bodyIdx < children.length && children[bodyIdx] is LatexSpace) {
            bodyIdx++;
          }
          if (bodyIdx >= children.length) {
            throw const EvaluationException('Integrale senza integrando');
          }

          // Simpson's rule with 200 subintervals
          const n = 200;
          final h = (b - a) / n;
          final savedBindings = Map<String, double>.from(_bindings);
          var sum = 0.0;

          for (var idx = 0; idx <= n; idx++) {
            final x = a + idx * h;
            _bindings = {...savedBindings, 'x': x};
            final fx = _evaluateNode(children[bodyIdx]);
            if (!fx.isFinite) continue;
            if (idx == 0 || idx == n) {
              sum += fx;
            } else if (idx.isOdd) {
              sum += 4 * fx;
            } else {
              sum += 2 * fx;
            }
          }
          _bindings = savedBindings;
          final result = sum * h / 3;

          if (tokens.isNotEmpty && tokens.last.isValue) {
            tokens.add(const _Token.op('×'));
          }
          tokens.add(_Token.value(result));
          i = bodyIdx;
        } else if (msg.startsWith('_function_:mod')) {
          // Modulo operator: treat as binary operator
          tokens.add(const _Token.op('mod'));
        } else {
          // Re-throw real errors
          throw e;
        }
      }
    }

    return tokens;
  }

  /// Evaluate a flat token list respecting operator precedence.
  ///
  /// Precedence (low to high):
  /// 1. `+`, `-`
  /// 2. `×`, `÷`, `·`, implicit multiplication
  /// 3. Unary minus
  static double _evaluateTokens(List<_Token> tokens) {
    if (tokens.isEmpty) {
      throw const EvaluationException('Espressione vuota');
    }

    // First pass: resolve unary minus
    final resolved = <_Token>[];
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i].isOp && tokens[i].opValue == 'unary-') {
        // Consume all consecutive unary minus
        var negCount = 0;
        while (i < tokens.length &&
            tokens[i].isOp &&
            tokens[i].opValue == 'unary-') {
          negCount++;
          i++;
        }
        if (i < tokens.length && tokens[i].isValue) {
          final val = tokens[i].numValue;
          resolved.add(_Token.value(negCount.isOdd ? -val : val));
        } else {
          throw const EvaluationException('Meno unario senza operando');
        }
      } else {
        resolved.add(tokens[i]);
      }
    }

    // Second pass: handle multiplication and division (high precedence)
    final addSub = <_Token>[];
    var j = 0;
    while (j < resolved.length) {
      if (resolved[j].isValue) {
        var acc = resolved[j].numValue;
        while (j + 2 < resolved.length &&
            resolved[j + 1].isOp &&
            _isMulDiv(resolved[j + 1].opValue)) {
          final op = resolved[j + 1].opValue;
          final right = resolved[j + 2].numValue;
          if (op == '×' || op == '·' || op == '⋅') {
            acc *= right;
          } else if (op == '÷' || op == '/') {
            if (right == 0) {
              throw const EvaluationException('Divisione per zero');
            }
            acc /= right;
          } else if (op == 'mod') {
            if (right == 0) {
              throw const EvaluationException('Modulo per zero');
            }
            acc = acc % right;
          }
          j += 2;
        }
        addSub.add(_Token.value(acc));
      } else {
        addSub.add(resolved[j]);
      }
      j++;
    }

    // Third pass: handle addition and subtraction (low precedence)
    if (addSub.isEmpty) {
      throw const EvaluationException('Espressione vuota');
    }

    var result = addSub.first.numValue;
    var k = 1;
    while (k + 1 < addSub.length) {
      final op = addSub[k].opValue;
      final right = addSub[k + 1].numValue;
      if (op == '+') {
        result += right;
      } else if (op == '-' || op == '−') {
        result -= right;
      } else {
        throw EvaluationException('Operatore inatteso: "$op"');
      }
      k += 2;
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Fraction
  // ---------------------------------------------------------------------------

  static double _evaluateFraction(LatexFraction node) {
    final num = _evaluateNode(node.numerator);
    final den = _evaluateNode(node.denominator);
    if (den == 0) {
      throw const EvaluationException('Divisione per zero');
    }
    return num / den;
  }

  // ---------------------------------------------------------------------------
  // Superscript (exponent)
  // ---------------------------------------------------------------------------

  static double _evaluateSuperscript(LatexSuperscript node) {
    final base = _evaluateNode(node.base);
    final exp = _evaluateNode(node.exponent);
    return math.pow(base, exp).toDouble();
  }

  // ---------------------------------------------------------------------------
  // Subscript — log with custom base: log_b{x}
  // ---------------------------------------------------------------------------

  static double _evaluateSubscript(LatexSubscript node) {
    // Detect log_b pattern: base is LatexText('log'), subscript is the base
    if (node.base is LatexText && (node.base as LatexText).text == 'log') {
      final logBase = _evaluateNode(node.subscript);
      if (logBase <= 0 || logBase == 1) {
        throw const EvaluationException(
          'Base del logaritmo non valida (deve essere >0 e ≠1)',
        );
      }
      // This will be followed by the argument in the group;
      // throw a sentinel so _tokenizeGroup can handle it.
      throw EvaluationException('_logbase_:$logBase');
    }
    return _evaluateNode(node.base);
  }

  // ---------------------------------------------------------------------------
  // Sub+Superscript — exponentiation OR finite sum/prod
  // ---------------------------------------------------------------------------

  static double _evaluateSubSuperscript(LatexSubSuperscript node) {
    // Detect ∑ or ∏ with bounds
    if (node.base is LatexBigOperator) {
      final op = (node.base as LatexBigOperator).operator;
      if (op == '∑' || op == '∏') {
        // Throw sentinel with bounds — body consumed in _tokenizeGroup
        final lower = _extractSumLower(node.subscript);
        final upper = _evaluateNode(node.superscript).toInt();
        throw EvaluationException('_sumop_:$op:${lower.$1}:${lower.$2}:$upper');
      }
      // Definite integral: ∫_{a}^{b} f(x)
      if (op == '∫') {
        final a = _evaluateNode(node.subscript);
        final b = _evaluateNode(node.superscript);
        throw EvaluationException('_integral_:$a:$b');
      }
    }
    final base = _evaluateNode(node.base);
    final exp = _evaluateNode(node.superscript);
    return math.pow(base, exp).toDouble();
  }

  /// Extract variable name and starting value from a sum lower bound.
  ///
  /// Expects patterns like `i=1` parsed as a group `[LatexSymbol('i'), '=', '1']`.
  static (String, int) _extractSumLower(LatexAstNode node) {
    String? varName;
    int? start;
    if (node is LatexGroup) {
      for (final child in node.children) {
        if (child is LatexSymbol && child.italic && varName == null) {
          varName = child.value;
        } else if (child is LatexSymbol && _isDigitOrDot(child.value)) {
          start = int.tryParse(child.value);
        }
      }
    }
    if (varName == null || start == null) {
      throw const EvaluationException(
        'Limiti della sommatoria non riconosciuti (formato: i=N)',
      );
    }
    return (varName, start);
  }

  // ---------------------------------------------------------------------------
  // Square root
  // ---------------------------------------------------------------------------

  static double _evaluateSqrt(LatexSqrt node) {
    final radicand = _evaluateNode(node.radicand);
    if (node.degree != null) {
      final degree = _evaluateNode(node.degree!);
      if (degree == 0) {
        throw const EvaluationException('Radice di grado zero');
      }
      return math.pow(radicand, 1.0 / degree).toDouble();
    }
    if (radicand < 0) {
      throw const EvaluationException('Radice quadrata di numero negativo');
    }
    return math.sqrt(radicand);
  }

  // ---------------------------------------------------------------------------
  // Delimited expressions (parentheses, brackets, absolute value)
  // ---------------------------------------------------------------------------

  static double _evaluateDelimited(LatexDelimited node) {
    // Binomial coefficient: \binom{n}{k} → LatexDelimited('⟮', '⟯', Fraction)
    if (node.open == '⟮' && node.close == '⟯' && node.body is LatexFraction) {
      final frac = node.body as LatexFraction;
      final n = _evaluateNode(frac.numerator);
      final k = _evaluateNode(frac.denominator);
      return _binomial(n, k);
    }

    final value = _evaluateNode(node.body);

    // Absolute value: |x|
    if (node.open == '|' && node.close == '|') return value.abs();

    // Floor: ⌊x⌋
    if (node.open == '⌊' && node.close == '⌋') return value.floorToDouble();

    // Ceil: ⌈x⌉
    if (node.open == '⌈' && node.close == '⌉') return value.ceilToDouble();

    return value;
  }

  // ---------------------------------------------------------------------------
  // Big operators — sentinel for sum/prod (bounds attached via SubSuperscript)
  // ---------------------------------------------------------------------------

  static double _evaluateBigOperator(LatexBigOperator node) {
    throw EvaluationException(
      'Operatore "${node.operator}" necessita di limiti (es. \\sum_{i=1}^{n})',
    );
  }

  // ---------------------------------------------------------------------------
  // Binomial coefficient — C(n, k) = n! / (k! * (n-k)!)
  // ---------------------------------------------------------------------------

  static double _binomial(double n, double k) {
    if (n < 0 || k < 0 || k > n) {
      throw const EvaluationException(
        'Coefficiente binomiale non definito per questi valori',
      );
    }
    if (n != n.truncateToDouble() || k != k.truncateToDouble()) {
      throw const EvaluationException(
        'Coefficiente binomiale definito solo per interi',
      );
    }
    final ni = n.toInt(), ki = k.toInt();
    if (ki > ni - ki) return _binomial(n, (ni - ki).toDouble());
    var result = 1.0;
    for (var i = 0; i < ki; i++) {
      result = result * (ni - i) / (i + 1);
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static bool _isDigitOrDot(String s) {
    if (s.isEmpty) return false;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (!((c >= 48 && c <= 57) || c == 46)) return false; // 0-9 or .
    }
    return true;
  }

  static bool _isOperator(String s) {
    return const {
      '+',
      '-',
      '−',
      '×',
      '÷',
      '·',
      '⋅',
      '/',
      '=',
      '<',
      '>',
      '≤',
      '≥',
      '≠',
    }.contains(s);
  }

  static bool _isMulDiv(String op) {
    return op == '×' ||
        op == '÷' ||
        op == '·' ||
        op == '⋅' ||
        op == '/' ||
        op == 'mod';
  }

  /// Compute factorial for non-negative integers.
  static double _factorial(double n) {
    if (n < 0 || n != n.truncateToDouble()) {
      throw const EvaluationException(
        'Fattoriale definito solo per interi non negativi',
      );
    }
    if (n > 170) {
      return double.infinity; // Overflow
    }
    var result = 1.0;
    for (var i = 2; i <= n.toInt(); i++) {
      result *= i;
    }
    return result;
  }
}

// =============================================================================
// Internal token type for expression evaluation
// =============================================================================

class _Token {
  final bool isValue;
  final double _numValue;
  final String _opValue;

  const _Token.value(double v) : isValue = true, _numValue = v, _opValue = '';

  const _Token.op(String op) : isValue = false, _numValue = 0, _opValue = op;

  bool get isOp => !isValue;
  double get numValue => _numValue;
  String get opValue => _opValue;

  @override
  String toString() => isValue ? 'Val($_numValue)' : 'Op($_opValue)';
}
