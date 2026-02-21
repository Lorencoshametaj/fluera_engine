import 'cell_address.dart';
import 'formula_ast.dart';
import 'formula_token.dart';

/// 📊 Recursive-descent formula parser for the tabular engine.
///
/// Parses tokenized formula strings into [FormulaNode] ASTs.
///
/// Operator precedence (low → high):
/// 1. Comparison: `=`, `<>`, `<`, `>`, `<=`, `>=`
/// 2. Concatenation: `&`
/// 3. Addition/Subtraction: `+`, `-`
/// 4. Multiplication/Division: `*`, `/`
/// 5. Power: `^`
/// 6. Unary: `-`, `+`
/// 7. Postfix: `%`
/// 8. Atoms: number, string, bool, cell ref, range, function call, parens
///
/// ```dart
/// final ast = FormulaParser.parse('SUM(A1:A10) + B1 * 2');
/// ```
class FormulaParser {
  final List<FormulaToken> _tokens;
  int _pos = 0;

  /// Optional set of recognized custom function names (uppercase).
  final Set<String> customFunctions;

  FormulaParser._(this._tokens, {this.customFunctions = const {}});

  /// Parse a formula expression string and return the AST.
  ///
  /// The leading `=` should already be stripped.
  /// Throws [FormatException] on syntax errors.
  static FormulaNode parse(String expression, {Set<String>? customFunctions}) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty formula expression');
    }

    // Strip leading `=` if present.
    final source = trimmed.startsWith('=') ? trimmed.substring(1) : trimmed;
    final tokens = FormulaTokenizer.tokenize(source);
    final parser = FormulaParser._(
      tokens,
      customFunctions: customFunctions ?? const {},
    );
    final result = parser._parseExpression();

    // Ensure all tokens were consumed.
    if (parser._current.type != TokenType.eof) {
      throw FormatException(
        'Unexpected token: ${parser._current.lexeme}',
        source,
        parser._current.position,
      );
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // Token access
  // -------------------------------------------------------------------------

  FormulaToken get _current => _tokens[_pos];

  FormulaToken _advance() {
    final token = _tokens[_pos];
    if (_pos < _tokens.length - 1) _pos++;
    return token;
  }

  bool _match(TokenType type) {
    if (_current.type == type) {
      _advance();
      return true;
    }
    return false;
  }

  FormulaToken _expect(TokenType type, String context) {
    if (_current.type == type) return _advance();
    throw FormatException(
      'Expected $type in $context, got ${_current.type} ("${_current.lexeme}")',
    );
  }

  // -------------------------------------------------------------------------
  // Grammar rules
  // -------------------------------------------------------------------------

  /// expression → comparison
  FormulaNode _parseExpression() => _parseComparison();

  /// comparison → concatenation ( ('=' | '<>' | '<' | '>' | '<=' | '>=') concatenation )*
  FormulaNode _parseComparison() {
    var left = _parseConcatenation();
    while (_current.type == TokenType.equals ||
        _current.type == TokenType.notEquals ||
        _current.type == TokenType.lt ||
        _current.type == TokenType.gt ||
        _current.type == TokenType.lte ||
        _current.type == TokenType.gte) {
      final op = _advance().lexeme;
      final right = _parseConcatenation();
      left = BinaryOp(left: left, right: right, op: op);
    }
    return left;
  }

  /// concatenation → addition ( '&' addition )*
  FormulaNode _parseConcatenation() {
    var left = _parseAddition();
    while (_current.type == TokenType.ampersand) {
      _advance();
      final right = _parseAddition();
      left = BinaryOp(left: left, right: right, op: '&');
    }
    return left;
  }

  /// addition → multiplication ( ('+' | '-') multiplication )*
  FormulaNode _parseAddition() {
    var left = _parseMultiplication();
    while (_current.type == TokenType.plus ||
        _current.type == TokenType.minus) {
      final op = _advance().lexeme;
      final right = _parseMultiplication();
      left = BinaryOp(left: left, right: right, op: op);
    }
    return left;
  }

  /// multiplication → power ( ('*' | '/') power )*
  FormulaNode _parseMultiplication() {
    var left = _parsePower();
    while (_current.type == TokenType.multiply ||
        _current.type == TokenType.divide) {
      final op = _advance().lexeme;
      final right = _parsePower();
      left = BinaryOp(left: left, right: right, op: op);
    }
    return left;
  }

  /// power → unary ( '^' unary )*
  FormulaNode _parsePower() {
    var left = _parseUnary();
    while (_current.type == TokenType.power) {
      _advance();
      final right = _parseUnary();
      left = BinaryOp(left: left, right: right, op: '^');
    }
    return left;
  }

  /// unary → ('-' | '+') unary | postfix
  FormulaNode _parseUnary() {
    if (_current.type == TokenType.minus) {
      _advance();
      final operand = _parseUnary();
      return UnaryOp(operand: operand, op: '-');
    }
    if (_current.type == TokenType.plus) {
      _advance();
      return _parseUnary();
    }
    return _parsePostfix();
  }

  /// postfix → atom '%'?
  FormulaNode _parsePostfix() {
    var node = _parseAtom();
    if (_current.type == TokenType.percent) {
      _advance();
      node = UnaryOp(operand: node, op: '%');
    }
    return node;
  }

  /// atom → NUMBER | STRING | BOOL | cellRef (':' cellRef)? | IDENT '(' args ')' | '(' expr ')'
  FormulaNode _parseAtom() {
    switch (_current.type) {
      case TokenType.number:
        final token = _advance();
        return NumberLiteral(token.numericValue!);

      case TokenType.string:
        final token = _advance();
        return StringLiteral(token.lexeme);

      case TokenType.boolean:
        final token = _advance();
        return BoolLiteral(token.lexeme == 'TRUE');

      case TokenType.cellRef:
        final token = _advance();
        final addr = CellAddress.fromLabel(token.lexeme);
        final absCol = token.lexeme.startsWith('\$');
        final absRow = token.lexeme.contains(RegExp(r'\$\d'));

        // Check for range operator.
        if (_current.type == TokenType.rangeOp) {
          _advance();
          final endToken = _expect(TokenType.cellRef, 'range end');
          final endAddr = CellAddress.fromLabel(endToken.lexeme);
          return RangeRef(CellRange(addr, endAddr));
        }
        return CellRef(addr, absoluteColumn: absCol, absoluteRow: absRow);

      case TokenType.identifier:
        final name = _advance().lexeme;
        // If followed by '!', it's a cross-sheet reference: Sheet2!A1 or Sheet2!A1:B10.
        if (_current.type == TokenType.exclamation) {
          _advance(); // consume '!'
          final cellToken = _expect(
            TokenType.cellRef,
            'cell reference after !',
          );
          final startAddr = CellAddress.fromLabel(cellToken.lexeme);
          // Check for range operator to handle Sheet!A1:B10.
          if (_match(TokenType.rangeOp)) {
            final endToken = _expect(TokenType.cellRef, 'range end');
            final endAddr = CellAddress.fromLabel(endToken.lexeme);
            return SheetRangeRef(name, CellRange(startAddr, endAddr));
          }
          return SheetCellRef(name, startAddr);
        }
        // If followed by '(', it's a function call.
        if (_current.type == TokenType.lparen) {
          _advance(); // consume '('
          final args = <FormulaNode>[];
          if (_current.type != TokenType.rparen) {
            args.add(_parseExpression());
            while (_match(TokenType.comma)) {
              args.add(_parseExpression());
            }
          }
          _expect(TokenType.rparen, 'function arguments');
          return FunctionCall(name, args);
        }
        // Otherwise, treat as a named range reference (zero-arg FunctionCall).
        // The evaluator resolves this against model.namedRanges.
        return FunctionCall(name, const []);

      case TokenType.lparen:
        _advance();
        final inner = _parseExpression();
        _expect(TokenType.rparen, 'parenthesized expression');
        return inner;

      default:
        throw FormatException(
          'Unexpected token: ${_current.type} ("${_current.lexeme}") at position ${_current.position}',
        );
    }
  }
}
