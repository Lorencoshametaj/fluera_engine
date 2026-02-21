/// 📊 Formula tokenizer for the tabular engine.
///
/// Converts a raw formula string (e.g. `SUM(A1:A10) + B1 * 2`)
/// into a list of [FormulaToken]s for the parser.

// ---------------------------------------------------------------------------
// Token types
// ---------------------------------------------------------------------------

/// The type of a formula token.
enum TokenType {
  /// Numeric literal: `42`, `3.14`.
  number,

  /// String literal: `"hello"`.
  string,

  /// Boolean literal: `TRUE`, `FALSE`.
  boolean,

  /// Cell reference: `A1`, `$B$3`, `AA100`.
  cellRef,

  /// Range operator: `:`.
  rangeOp,

  /// Identifier (function name): `SUM`, `AVERAGE`.
  identifier,

  /// `+`
  plus,

  /// `-`
  minus,

  /// `*`
  multiply,

  /// `/`
  divide,

  /// `^`
  power,

  /// `%`
  percent,

  /// `&` (string concatenation)
  ampersand,

  /// `=` (comparison equals)
  equals,

  /// `<>` (not equals)
  notEquals,

  /// `<`
  lt,

  /// `>`
  gt,

  /// `<=`
  lte,

  /// `>=`
  gte,

  /// `(`
  lparen,

  /// `)`
  rparen,

  /// `,`
  comma,

  /// `!` (sheet reference separator)
  exclamation,

  /// End of formula.
  eof,
}

// ---------------------------------------------------------------------------
// FormulaToken
// ---------------------------------------------------------------------------

/// A single token from the formula tokenizer.
class FormulaToken {
  final TokenType type;

  /// The raw text of the token.
  final String lexeme;

  /// Numeric value (for [TokenType.number]).
  final double? numericValue;

  /// Position in the source string (for error reporting).
  final int position;

  const FormulaToken(
    this.type,
    this.lexeme,
    this.position, {
    this.numericValue,
  });

  @override
  String toString() => 'Token($type, "$lexeme", pos=$position)';
}

// ---------------------------------------------------------------------------
// Tokenizer
// ---------------------------------------------------------------------------

/// Tokenizes a formula string into a list of [FormulaToken]s.
///
/// The leading `=` should already be stripped before calling [tokenize].
///
/// ```dart
/// final tokens = FormulaTokenizer.tokenize('SUM(A1:A10) + 2');
/// ```
class FormulaTokenizer {
  /// Tokenize [source] into a list of tokens.
  ///
  /// Throws [FormatException] on unrecognized characters.
  static List<FormulaToken> tokenize(String source) {
    final tokens = <FormulaToken>[];
    int pos = 0;

    while (pos < source.length) {
      // Skip whitespace.
      if (_isWhitespace(source.codeUnitAt(pos))) {
        pos++;
        continue;
      }

      final ch = source[pos];
      final code = source.codeUnitAt(pos);

      // ----- Numbers -----
      if (_isDigit(code) ||
          (ch == '.' &&
              pos + 1 < source.length &&
              _isDigit(source.codeUnitAt(pos + 1)))) {
        final start = pos;
        while (pos < source.length && _isDigit(source.codeUnitAt(pos))) {
          pos++;
        }
        if (pos < source.length && source[pos] == '.') {
          pos++;
          while (pos < source.length && _isDigit(source.codeUnitAt(pos))) {
            pos++;
          }
        }
        // Scientific notation: 1E+10, 2.5e-3
        if (pos < source.length && (source[pos] == 'e' || source[pos] == 'E')) {
          pos++;
          if (pos < source.length &&
              (source[pos] == '+' || source[pos] == '-')) {
            pos++;
          }
          while (pos < source.length && _isDigit(source.codeUnitAt(pos))) {
            pos++;
          }
        }
        final lexeme = source.substring(start, pos);
        tokens.add(
          FormulaToken(
            TokenType.number,
            lexeme,
            start,
            numericValue: double.parse(lexeme),
          ),
        );
        continue;
      }

      // ----- Strings -----
      if (ch == '"') {
        final start = pos;
        pos++; // skip opening quote
        final buf = StringBuffer();
        while (pos < source.length && source[pos] != '"') {
          if (source[pos] == '\\' && pos + 1 < source.length) {
            pos++;
            buf.write(source[pos]);
          } else {
            buf.write(source[pos]);
          }
          pos++;
        }
        if (pos < source.length) pos++; // skip closing quote
        tokens.add(FormulaToken(TokenType.string, buf.toString(), start));
        continue;
      }

      // ----- Cell references or identifiers / booleans -----
      if (_isAlpha(code) || ch == '\$') {
        final start = pos;
        // Consume a potential cell reference: optional $ + letters + optional $ + digits
        // Or an identifier (function name / TRUE / FALSE).
        final buf = StringBuffer();
        bool hasDollar = false;

        // First, collect the whole word (letters, digits, dollars).
        while (pos < source.length &&
            (_isAlpha(source.codeUnitAt(pos)) ||
                _isDigit(source.codeUnitAt(pos)) ||
                source[pos] == '\$' ||
                source[pos] == '_')) {
          if (source[pos] == '\$') hasDollar = true;
          buf.write(source[pos]);
          pos++;
        }
        final word = buf.toString();
        final upper = word.toUpperCase();

        // Check for boolean literals.
        if (upper == 'TRUE' || upper == 'FALSE') {
          tokens.add(FormulaToken(TokenType.boolean, upper, start));
          continue;
        }

        // Check if it looks like a cell reference: [$ ]letters[$ ]digits
        if (_isCellReference(word)) {
          tokens.add(FormulaToken(TokenType.cellRef, word, start));
          continue;
        }

        // Otherwise it's an identifier (function name).
        tokens.add(FormulaToken(TokenType.identifier, upper, start));
        continue;
      }

      // ----- Operators and punctuation -----
      switch (ch) {
        case '+':
          tokens.add(FormulaToken(TokenType.plus, '+', pos));
          pos++;
        case '-':
          tokens.add(FormulaToken(TokenType.minus, '-', pos));
          pos++;
        case '*':
          tokens.add(FormulaToken(TokenType.multiply, '*', pos));
          pos++;
        case '/':
          tokens.add(FormulaToken(TokenType.divide, '/', pos));
          pos++;
        case '^':
          tokens.add(FormulaToken(TokenType.power, '^', pos));
          pos++;
        case '%':
          tokens.add(FormulaToken(TokenType.percent, '%', pos));
          pos++;
        case '&':
          tokens.add(FormulaToken(TokenType.ampersand, '&', pos));
          pos++;
        case '(':
          tokens.add(FormulaToken(TokenType.lparen, '(', pos));
          pos++;
        case ')':
          tokens.add(FormulaToken(TokenType.rparen, ')', pos));
          pos++;
        case ',':
          tokens.add(FormulaToken(TokenType.comma, ',', pos));
          pos++;
        case ':':
          tokens.add(FormulaToken(TokenType.rangeOp, ':', pos));
          pos++;
        case '=':
          tokens.add(FormulaToken(TokenType.equals, '=', pos));
          pos++;
        case '<':
          if (pos + 1 < source.length && source[pos + 1] == '>') {
            tokens.add(FormulaToken(TokenType.notEquals, '<>', pos));
            pos += 2;
          } else if (pos + 1 < source.length && source[pos + 1] == '=') {
            tokens.add(FormulaToken(TokenType.lte, '<=', pos));
            pos += 2;
          } else {
            tokens.add(FormulaToken(TokenType.lt, '<', pos));
            pos++;
          }
        case '>':
          if (pos + 1 < source.length && source[pos + 1] == '=') {
            tokens.add(FormulaToken(TokenType.gte, '>=', pos));
            pos += 2;
          } else {
            tokens.add(FormulaToken(TokenType.gt, '>', pos));
            pos++;
          }
          break;
        case '!':
          tokens.add(FormulaToken(TokenType.exclamation, '!', pos));
          pos++;
          break;
        default:
          throw FormatException('Unexpected character: "$ch"', source, pos);
      }
    }

    tokens.add(FormulaToken(TokenType.eof, '', source.length));
    return tokens;
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Check whether [word] matches a cell reference pattern.
  ///
  /// Patterns: `A1`, `$A1`, `A$1`, `$A$1`, `AA100`, `$AA$100`.
  static bool _isCellReference(String word) {
    final cleaned = word.replaceAll('\$', '').toUpperCase();
    if (cleaned.isEmpty) return false;

    int i = 0;
    // Must start with at least one letter.
    if (i >= cleaned.length || !_isAlpha(cleaned.codeUnitAt(i))) return false;
    while (i < cleaned.length && _isAlpha(cleaned.codeUnitAt(i))) {
      i++;
    }
    // Must have at least one digit after the letters.
    if (i >= cleaned.length || !_isDigit(cleaned.codeUnitAt(i))) return false;
    while (i < cleaned.length && _isDigit(cleaned.codeUnitAt(i))) {
      i++;
    }
    return i == cleaned.length;
  }

  static bool _isDigit(int code) => code >= 48 && code <= 57;
  static bool _isAlpha(int code) =>
      (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  static bool _isWhitespace(int code) =>
      code == 32 || code == 9 || code == 10 || code == 13;
}
