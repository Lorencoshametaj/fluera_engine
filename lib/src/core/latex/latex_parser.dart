import 'latex_ast.dart';

/// 🧮 LaTeX Parser — recursive descent parser for LaTeX math expressions.
///
/// Converts a LaTeX source string into an [LatexAstNode] tree.
///
/// **Supported syntax:**
/// - Single characters: `x`, `2`, `+`, `=`
/// - Groups: `{a + b}`
/// - Fractions: `\frac{n}{d}`
/// - Super/subscripts: `x^2`, `x_i`, `x_i^2`
/// - Square roots: `\sqrt{x}`, `\sqrt[3]{x}`
/// - Big operators: `\int`, `\sum`, `\prod` (with limits)
/// - Greek letters: `\alpha`, `\beta`, ..., `\omega`
/// - Accents: `\hat{x}`, `\bar{x}`, `\vec{x}`, `\dot{x}`, `\tilde{x}`
/// - Delimiters: `\left( ... \right)`
/// - Text: `\text{hello}`
/// - Spacing: `\,`, `\;`, `\quad`, `\qquad`, `\!`
/// - Limits: `\lim`
/// - Matrices: `\begin{matrix}...\end{matrix}`
/// - Error recovery: returns [LatexErrorNode] for unparseable segments
///
/// Example:
/// ```dart
/// final ast = LatexParser.parse(r'\frac{a}{b} + \sqrt{c}');
/// ```
class LatexParser {
  final String _source;
  int _pos = 0;

  LatexParser._(this._source);

  /// Parse a LaTeX string into an AST.
  static LatexAstNode parse(String source) {
    if (source.trim().isEmpty) {
      return const LatexGroup([]);
    }
    final parser = LatexParser._(source);
    return parser._parseExpression();
  }

  // ---------------------------------------------------------------------------
  // Top-Level
  // ---------------------------------------------------------------------------

  /// Parse a full expression (sequence of atoms).
  LatexAstNode _parseExpression() {
    final nodes = <LatexAstNode>[];

    while (_pos < _source.length) {
      final c = _source[_pos];

      // End of group
      if (c == '}') break;

      // Handle '&' as column separator in matrix (stop parsing current cell)
      if (c == '&') break;

      final atom = _parseAtom();
      if (atom == null) break;

      // Check for sub/superscript after atom
      nodes.add(_parsePostfix(atom));
    }

    if (nodes.isEmpty) return const LatexGroup([]);
    if (nodes.length == 1) return nodes.first;
    return LatexGroup(nodes);
  }

  /// Parse a single atom (one element before potential ^/_ postfix).
  LatexAstNode? _parseAtom() {
    if (_pos >= _source.length) return null;

    _skipWhitespace();
    if (_pos >= _source.length) return null;

    final c = _source[_pos];

    // Backslash command
    if (c == '\\') {
      return _parseCommand();
    }

    // Braced group
    if (c == '{') {
      return _parseGroup();
    }

    // Single character (letter, digit, operator)
    if (c == '}' || c == '&') return null;

    _pos++;
    final isLetter = _isLetter(c);
    return LatexSymbol(c, italic: isLetter);
  }

  // ---------------------------------------------------------------------------
  // Commands
  // ---------------------------------------------------------------------------

  /// Parse a backslash command.
  LatexAstNode _parseCommand() {
    assert(_source[_pos] == '\\');
    _pos++; // skip backslash

    if (_pos >= _source.length) {
      return const LatexErrorNode('\\', 'Unexpected end after backslash');
    }

    // Special single-char commands
    final nextChar = _source[_pos];
    if (nextChar == ',' ||
        nextChar == ';' ||
        nextChar == '!' ||
        nextChar == ' ') {
      _pos++;
      return LatexSpace(_spacingWidth(nextChar));
    }

    // Read command name
    final cmdName = _readCommandName();

    switch (cmdName) {
      // Fractions
      case 'frac':
        return _parseFraction();

      // Square roots
      case 'sqrt':
        return _parseSqrt();

      // Big operators
      case 'int':
        return const LatexBigOperator('∫');
      case 'iint':
        return const LatexBigOperator('∬');
      case 'iiint':
        return const LatexBigOperator('∭');
      case 'oint':
        return const LatexBigOperator('∮');
      case 'sum':
        return const LatexBigOperator('∑');
      case 'prod':
        return const LatexBigOperator('∏');

      // Limits
      case 'lim':
        return const LatexLimit();

      // Text
      case 'text':
      case 'mathrm':
      case 'textrm':
        return _parseTextCommand();

      // Accents
      case 'hat':
        return _parseAccent('hat');
      case 'bar':
      case 'overline':
        return _parseAccent('bar');
      case 'vec':
        return _parseAccent('vec');
      case 'dot':
        return _parseAccent('dot');
      case 'ddot':
        return _parseAccent('ddot');
      case 'tilde':
        return _parseAccent('tilde');
      case 'widehat':
        return _parseAccent('widehat');
      case 'widetilde':
        return _parseAccent('widetilde');

      // Greek letters
      case 'alpha':
        return const LatexSymbol('α');
      case 'beta':
        return const LatexSymbol('β');
      case 'gamma':
        return const LatexSymbol('γ');
      case 'Gamma':
        return const LatexSymbol('Γ');
      case 'delta':
        return const LatexSymbol('δ');
      case 'Delta':
        return const LatexSymbol('Δ');
      case 'epsilon':
      case 'varepsilon':
        return const LatexSymbol('ε');
      case 'zeta':
        return const LatexSymbol('ζ');
      case 'eta':
        return const LatexSymbol('η');
      case 'theta':
      case 'vartheta':
        return const LatexSymbol('θ');
      case 'Theta':
        return const LatexSymbol('Θ');
      case 'iota':
        return const LatexSymbol('ι');
      case 'kappa':
        return const LatexSymbol('κ');
      case 'lambda':
        return const LatexSymbol('λ');
      case 'Lambda':
        return const LatexSymbol('Λ');
      case 'mu':
        return const LatexSymbol('μ');
      case 'nu':
        return const LatexSymbol('ν');
      case 'xi':
        return const LatexSymbol('ξ');
      case 'Xi':
        return const LatexSymbol('Ξ');
      case 'pi':
        return const LatexSymbol('π');
      case 'Pi':
        return const LatexSymbol('Π');
      case 'rho':
      case 'varrho':
        return const LatexSymbol('ρ');
      case 'sigma':
        return const LatexSymbol('σ');
      case 'Sigma':
        return const LatexSymbol('Σ');
      case 'tau':
        return const LatexSymbol('τ');
      case 'upsilon':
        return const LatexSymbol('υ');
      case 'phi':
      case 'varphi':
        return const LatexSymbol('φ');
      case 'Phi':
        return const LatexSymbol('Φ');
      case 'chi':
        return const LatexSymbol('χ');
      case 'psi':
        return const LatexSymbol('ψ');
      case 'Psi':
        return const LatexSymbol('Ψ');
      case 'omega':
        return const LatexSymbol('ω');
      case 'Omega':
        return const LatexSymbol('Ω');

      // Special symbols
      case 'infty':
        return const LatexSymbol('∞');
      case 'partial':
        return const LatexSymbol('∂');
      case 'nabla':
        return const LatexSymbol('∇');
      case 'forall':
        return const LatexSymbol('∀');
      case 'exists':
        return const LatexSymbol('∃');
      case 'nexists':
        return const LatexSymbol('∄');
      case 'in':
        return const LatexSymbol('∈');
      case 'notin':
        return const LatexSymbol('∉');
      case 'subset':
        return const LatexSymbol('⊂');
      case 'supset':
        return const LatexSymbol('⊃');
      case 'cup':
        return const LatexSymbol('∪');
      case 'cap':
        return const LatexSymbol('∩');
      case 'emptyset':
        return const LatexSymbol('∅');

      // Relational operators
      case 'leq':
      case 'le':
        return const LatexSymbol('≤');
      case 'geq':
      case 'ge':
        return const LatexSymbol('≥');
      case 'neq':
      case 'ne':
        return const LatexSymbol('≠');
      case 'approx':
        return const LatexSymbol('≈');
      case 'equiv':
        return const LatexSymbol('≡');
      case 'sim':
        return const LatexSymbol('∼');
      case 'propto':
        return const LatexSymbol('∝');
      case 'pm':
        return const LatexSymbol('±');
      case 'mp':
        return const LatexSymbol('∓');
      case 'times':
        return const LatexSymbol('×');
      case 'div':
        return const LatexSymbol('÷');
      case 'cdot':
        return const LatexSymbol('·');
      case 'circ':
        return const LatexSymbol('∘');

      // Arrows
      case 'to':
      case 'rightarrow':
        return const LatexSymbol('→');
      case 'leftarrow':
        return const LatexSymbol('←');
      case 'leftrightarrow':
        return const LatexSymbol('↔');
      case 'Rightarrow':
        return const LatexSymbol('⇒');
      case 'Leftarrow':
        return const LatexSymbol('⇐');
      case 'Leftrightarrow':
        return const LatexSymbol('⇔');
      case 'mapsto':
        return const LatexSymbol('↦');

      // Delimiters
      case 'left':
        return _parseLeftRight();
      case 'right':
        // Should not appear standalone — handled by \left
        return const LatexErrorNode('\\right', 'Unmatched \\right');

      // Spacing
      case 'quad':
        return const LatexSpace(1.0);
      case 'qquad':
        return const LatexSpace(2.0);

      // Environments
      case 'begin':
        return _parseEnvironment();

      // Misc
      case 'ldots':
      case 'dots':
        return const LatexSymbol('…');
      case 'cdots':
        return const LatexSymbol('⋯');
      case 'vdots':
        return const LatexSymbol('⋮');
      case 'ddots':
        return const LatexSymbol('⋱');

      default:
        // Unknown command — return as error node.
        return LatexErrorNode('\\$cmdName', 'Unknown command: \\$cmdName');
    }
  }

  // ---------------------------------------------------------------------------
  // Specific Parsers
  // ---------------------------------------------------------------------------

  /// Parse `\frac{numerator}{denominator}`
  LatexAstNode _parseFraction() {
    final num = _parseRequiredArg();
    final den = _parseRequiredArg();
    return LatexFraction(num, den);
  }

  /// Parse `\sqrt{radicand}` or `\sqrt[degree]{radicand}`
  LatexAstNode _parseSqrt() {
    LatexAstNode? degree;
    _skipWhitespace();

    // Optional degree: \sqrt[n]{...}
    if (_pos < _source.length && _source[_pos] == '[') {
      _pos++; // skip [
      final degreeChars = StringBuffer();
      while (_pos < _source.length && _source[_pos] != ']') {
        degreeChars.write(_source[_pos]);
        _pos++;
      }
      if (_pos < _source.length) _pos++; // skip ]
      degree = LatexParser.parse(degreeChars.toString());
    }

    final radicand = _parseRequiredArg();
    return LatexSqrt(radicand, degree: degree);
  }

  /// Parse `\text{...}`
  LatexAstNode _parseTextCommand() {
    _skipWhitespace();
    if (_pos >= _source.length || _source[_pos] != '{') {
      return const LatexErrorNode('\\text', 'Expected { after \\text');
    }
    _pos++; // skip {
    final buf = StringBuffer();
    int depth = 1;
    while (_pos < _source.length && depth > 0) {
      if (_source[_pos] == '{') {
        depth++;
      } else if (_source[_pos] == '}') {
        depth--;
        if (depth == 0) break;
      }
      buf.write(_source[_pos]);
      _pos++;
    }
    if (_pos < _source.length) _pos++; // skip }
    return LatexText(buf.toString());
  }

  /// Parse an accent command: `\hat{base}`
  LatexAstNode _parseAccent(String accentType) {
    final base = _parseRequiredArg();
    return LatexAccent(accentType, base);
  }

  /// Parse `\left( ... \right)`
  LatexAstNode _parseLeftRight() {
    _skipWhitespace();
    if (_pos >= _source.length) {
      return const LatexErrorNode('\\left', 'Unexpected end after \\left');
    }

    // Read opening delimiter
    final open = _source[_pos] == '.' ? '' : _source[_pos].toString();
    _pos++;

    // Parse body until \right
    final bodyNodes = <LatexAstNode>[];
    while (_pos < _source.length) {
      _skipWhitespace();
      // Check for \right
      if (_pos < _source.length - 5 &&
          _source.substring(_pos, _pos + 6) == '\\right') {
        _pos += 6; // skip \right
        _skipWhitespace();
        if (_pos < _source.length) {
          final close = _source[_pos] == '.' ? '' : _source[_pos].toString();
          _pos++;
          final body =
              bodyNodes.length == 1 ? bodyNodes.first : LatexGroup(bodyNodes);
          return LatexDelimited(open, close, body);
        }
        break;
      }

      final atom = _parseAtom();
      if (atom == null) break;
      bodyNodes.add(_parsePostfix(atom));
    }

    // Unmatched \left
    final body =
        bodyNodes.length == 1 ? bodyNodes.first : LatexGroup(bodyNodes);
    return LatexDelimited(open, '', body);
  }

  /// Parse `\begin{env}...\end{env}`
  LatexAstNode _parseEnvironment() {
    final envName = _parseBracedText();

    final matrixStyle = _matrixStyleFromName(envName);
    if (matrixStyle != null) {
      return _parseMatrix(envName, matrixStyle);
    }

    // Unknown environment — skip to \end{env}
    final endMarker = '\\end{$envName}';
    final endIdx = _source.indexOf(endMarker, _pos);
    if (endIdx >= 0) {
      _pos = endIdx + endMarker.length;
    }
    return LatexErrorNode('\\begin{$envName}', 'Unknown environment: $envName');
  }

  /// Parse matrix content: rows separated by `\\`, cells by `&`
  LatexAstNode _parseMatrix(String envName, MatrixStyle style) {
    final rows = <List<LatexAstNode>>[];
    var currentRow = <LatexAstNode>[];

    final endMarker = '\\end{$envName}';

    while (_pos < _source.length) {
      // Check for \end{envName}
      if (_source.length >= _pos + endMarker.length &&
          _source.substring(_pos, _pos + endMarker.length) == endMarker) {
        _pos += endMarker.length;
        break;
      }

      // Check for row separator \\
      if (_pos < _source.length - 1 &&
          _source[_pos] == '\\' &&
          _source[_pos + 1] == '\\') {
        _pos += 2;
        currentRow.add(_parseExpression());
        rows.add(currentRow);
        currentRow = <LatexAstNode>[];
        continue;
      }

      // Check for column separator &
      if (_source[_pos] == '&') {
        _pos++;
        currentRow.add(_parseExpression());
        continue;
      }

      // Parse cell content
      currentRow.add(_parseExpression());
    }

    if (currentRow.isNotEmpty) {
      rows.add(currentRow);
    }

    return LatexMatrix(rows, style: style);
  }

  // ---------------------------------------------------------------------------
  // Postfix (Sub/Superscript)
  // ---------------------------------------------------------------------------

  /// Check for `^` or `_` after an atom.
  LatexAstNode _parsePostfix(LatexAstNode base) {
    _skipWhitespace();
    if (_pos >= _source.length) return base;

    bool hasSub = false;
    bool hasSup = false;
    LatexAstNode? sub;
    LatexAstNode? sup;

    // Parse up to two postfix operators
    for (int i = 0; i < 2 && _pos < _source.length; i++) {
      if (_source[_pos] == '^' && !hasSup) {
        _pos++;
        sup = _parseRequiredArg();
        hasSup = true;
      } else if (_source[_pos] == '_' && !hasSub) {
        _pos++;
        sub = _parseRequiredArg();
        hasSub = true;
      } else {
        break;
      }
      _skipWhitespace();
    }

    if (hasSub && hasSup) {
      return LatexSubSuperscript(base, sub!, sup!);
    } else if (hasSup) {
      return LatexSuperscript(base, sup!);
    } else if (hasSub) {
      return LatexSubscript(base, sub!);
    }

    return base;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Parse a required braced argument `{...}` or a single character.
  LatexAstNode _parseRequiredArg() {
    _skipWhitespace();
    if (_pos >= _source.length) {
      return const LatexErrorNode('', 'Expected argument');
    }
    if (_source[_pos] == '{') {
      return _parseGroup();
    }
    // Single character shorthand (e.g. `x^2` instead of `x^{2}`)
    return _parseAtom() ?? const LatexErrorNode('', 'Expected argument');
  }

  /// Parse a braced group `{...}`
  LatexAstNode _parseGroup() {
    assert(_source[_pos] == '{');
    _pos++; // skip {
    final content = _parseExpression();
    if (_pos < _source.length && _source[_pos] == '}') {
      _pos++; // skip }
    }
    return content;
  }

  /// Read a command name (alphabetic characters after `\`).
  String _readCommandName() {
    final buf = StringBuffer();
    while (_pos < _source.length && _isLetter(_source[_pos])) {
      buf.write(_source[_pos]);
      _pos++;
    }
    return buf.toString();
  }

  /// Read text inside `{...}` as raw string.
  String _parseBracedText() {
    _skipWhitespace();
    if (_pos >= _source.length || _source[_pos] != '{') return '';
    _pos++; // skip {
    final buf = StringBuffer();
    while (_pos < _source.length && _source[_pos] != '}') {
      buf.write(_source[_pos]);
      _pos++;
    }
    if (_pos < _source.length) _pos++; // skip }
    return buf.toString();
  }

  void _skipWhitespace() {
    while (_pos < _source.length && _source[_pos] == ' ') {
      _pos++;
    }
  }

  static bool _isLetter(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  static double _spacingWidth(String c) {
    switch (c) {
      case '!':
        return -3.0 / 18.0; // negative thin space
      case ',':
        return 3.0 / 18.0; // thin space
      case ';':
        return 5.0 / 18.0; // medium space
      case ' ':
        return 4.0 / 18.0; // normal space
      default:
        return 0;
    }
  }

  static MatrixStyle? _matrixStyleFromName(String name) {
    switch (name) {
      case 'matrix':
        return MatrixStyle.plain;
      case 'pmatrix':
        return MatrixStyle.parenthesized;
      case 'bmatrix':
        return MatrixStyle.bracketed;
      case 'Bmatrix':
        return MatrixStyle.braced;
      case 'vmatrix':
        return MatrixStyle.verticalBar;
      case 'Vmatrix':
        return MatrixStyle.doubleVerticalBar;
      default:
        return null;
    }
  }
}
