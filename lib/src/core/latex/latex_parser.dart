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

    // Percentage: \%
    if (nextChar == '%') {
      _pos++;
      return const LatexSymbol('%');
    }

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

      // Binomial coefficient — stacked without bar, wrapped in parens
      case 'binom':
      case 'tbinom':
      case 'dbinom':
        final num = _parseRequiredArg();
        final den = _parseRequiredArg();
        return LatexDelimited(
          '(', ')',
          LatexFraction(num, den, showBar: false),
        );

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

      // Font style commands
      case 'mathbf':
      case 'boldsymbol':
      case 'textbf':
        return _parseFontCommand(bold: true);
      case 'mathit':
      case 'textit':
        return _parseFontCommand(italic: true);
      case 'mathsf':
      case 'textsf':
        return _parseTextCommand(); // sans-serif handled as text
      case 'mathtt':
      case 'texttt':
        return _parseTextCommand(); // monospace handled as text
      case 'mathscr':
        return _parseMathcal(); // script ≈ calligraphic
      case 'mathbb':
        return _parseMathbb();
      case 'mathcal':
        return _parseMathcal();

      // Accents
      case 'hat':
        return _parseAccent('hat');
      case 'bar':
      case 'overline':
        return _parseAccent('bar');
      case 'underline':
        return _parseAccent('underline');
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
      case 'acute':
        return _parseAccent('acute');
      case 'grave':
        return _parseAccent('grave');
      case 'breve':
        return _parseAccent('breve');
      case 'check':
        return _parseAccent('check');

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

      // Floor / Ceil delimiters (standalone usage)
      case 'lfloor':
        return const LatexSymbol('⌊');
      case 'rfloor':
        return const LatexSymbol('⌋');
      case 'lceil':
        return const LatexSymbol('⌈');
      case 'rceil':
        return const LatexSymbol('⌉');

      // Spacing
      case 'quad':
        return const LatexSpace(1.0);
      case 'qquad':
        return const LatexSpace(2.0);

      // Environments
      case 'begin':
        return _parseEnvironment();

      // ── New constructs ──

      // Color
      case 'color':
        return _parseColor();

      // Boxed
      case 'boxed':
        return LatexBoxed(_parseRequiredArg());

      // Cancel / strikethrough
      case 'cancel':
        return LatexCancel(_parseRequiredArg(), direction: 'forward');
      case 'bcancel':
        return LatexCancel(_parseRequiredArg(), direction: 'back');
      case 'xcancel':
        return LatexCancel(_parseRequiredArg(), direction: 'cross');

      // Under/overbrace
      case 'underbrace':
        return _parseUnderOverBrace(above: false);
      case 'overbrace':
        return _parseUnderOverBrace(above: true);

      // Overset / underset / stackrel
      case 'overset':
        final anno = _parseRequiredArg();
        final body = _parseRequiredArg();
        return LatexUnderOver(body, anno, above: true);
      case 'underset':
        final anno = _parseRequiredArg();
        final body = _parseRequiredArg();
        return LatexUnderOver(body, anno, above: false);
      case 'stackrel':
        final anno = _parseRequiredArg();
        final body = _parseRequiredArg();
        return LatexUnderOver(body, anno, above: true);

      // Phantom
      case 'phantom':
      case 'hphantom':
      case 'vphantom':
        return LatexPhantom(_parseRequiredArg());

      // Negation
      case 'not':
        // \not= → ≠, \not\in → ∉, etc.
        return _parseNot();

      // Display/text style — currently treated as no-op passthrough
      case 'displaystyle':
      case 'textstyle':
      case 'scriptstyle':
      case 'scriptscriptstyle':
        return _parseRequiredArg();

      // Fraktur font
      case 'mathfrak':
        return _parseMathfrak();

      // Substack
      case 'substack':
        return _parseSubstack();

      // Extensible arrows
      case 'xrightarrow':
        return _parseExtensibleArrow('right');
      case 'xleftarrow':
        return _parseExtensibleArrow('left');
      case 'xleftrightarrow':
        return _parseExtensibleArrow('both');

      // Extra symbols
      case 'dagger':
        return const LatexSymbol('†');
      case 'ddagger':
        return const LatexSymbol('‡');

      // Colorbox
      case 'colorbox':
        return _parseColorBox();

      // Rule
      case 'rule':
        return _parseRule();

      // Custom operator name
      case 'operatorname':
        final name = _parseBracedText();
        return LatexText(name);

      // Horizontal line in matrices (treated as thin separator)
      case 'hline':
        return const LatexSpace(0.0);

      // Modulo notation
      case 'pmod':
        final arg = _parseRequiredArg();
        return LatexGroup([
          const LatexSpace(0.25),
          const LatexSymbol('('),
          const LatexText('mod'),
          const LatexSpace(0.15),
          arg,
          const LatexSymbol(')'),
        ]);
      case 'bmod':
        return const LatexGroup([
          LatexSpace(0.25),
          LatexText('mod'),
          LatexSpace(0.25),
        ]);
      case 'pod':
        final arg = _parseRequiredArg();
        return LatexGroup([
          const LatexSpace(0.25),
          const LatexSymbol('('),
          arg,
          const LatexSymbol(')'),
        ]);

      // Extra big operators
      case 'coprod':
        return const LatexBigOperator('∐');
      case 'bigcup':
        return const LatexBigOperator('⋃');
      case 'bigcap':
        return const LatexBigOperator('⋂');
      case 'bigoplus':
        return const LatexBigOperator('⨁');
      case 'bigotimes':
        return const LatexBigOperator('⨂');
      case 'bigsqcup':
        return const LatexBigOperator('⨆');

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

      // ── Standard math function operators (upright/roman font) ──
      case 'log':
        return const LatexText('log');
      case 'ln':
        return const LatexText('ln');
      case 'lg':
        return const LatexText('lg');
      case 'exp':
        return const LatexText('exp');
      case 'sin':
        return const LatexText('sin');
      case 'cos':
        return const LatexText('cos');
      case 'tan':
        return const LatexText('tan');
      case 'cot':
        return const LatexText('cot');
      case 'sec':
        return const LatexText('sec');
      case 'csc':
        return const LatexText('csc');
      case 'arcsin':
        return const LatexText('arcsin');
      case 'arccos':
        return const LatexText('arccos');
      case 'arctan':
        return const LatexText('arctan');
      case 'sinh':
        return const LatexText('sinh');
      case 'cosh':
        return const LatexText('cosh');
      case 'tanh':
        return const LatexText('tanh');
      case 'coth':
        return const LatexText('coth');
      case 'min':
        return const LatexText('min');
      case 'max':
        return const LatexText('max');
      case 'sup':
        return const LatexText('sup');
      case 'inf':
        return const LatexText('inf');
      case 'arg':
        return const LatexText('arg');
      case 'det':
        return const LatexText('det');
      case 'gcd':
        return const LatexText('gcd');
      case 'deg':
        return const LatexText('deg');
      case 'dim':
        return const LatexText('dim');
      case 'hom':
        return const LatexText('hom');
      case 'ker':
        return const LatexText('ker');
      case 'Pr':
        return const LatexText('Pr');
      case 'mod':
        return const LatexText('mod');

      // Escaped percent sign (percentage symbol)
      case '%':
        return const LatexSymbol('%');

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

  /// Parse a font command like `\mathbf{x}` or `\mathit{y}`
  LatexAstNode _parseFontCommand({bool bold = false, bool italic = false}) {
    final arg = _parseRequiredArg();
    // Wrap the content — apply the bold/italic flag
    if (arg is LatexSymbol) {
      return LatexSymbol(arg.value, italic: italic || arg.italic, bold: bold);
    }
    // For groups, recursively apply bold/italic to all symbol children
    if (arg is LatexGroup && bold) {
      final mapped = arg.children.map((child) {
        if (child is LatexSymbol) {
          return LatexSymbol(child.value, italic: italic || child.italic, bold: true);
        }
        return child;
      }).toList();
      return LatexGroup(mapped);
    }
    return arg;
  }

  /// Parse `\mathbb{R}` — blackboard bold (double-struck)
  LatexAstNode _parseMathbb() {
    _skipWhitespace();
    if (_pos >= _source.length) {
      return const LatexErrorNode('\\mathbb', 'Expected argument');
    }
    // Read a single character or braced group
    String letter;
    if (_source[_pos] == '{') {
      _pos++;
      letter = '';
      if (_pos < _source.length && _source[_pos] != '}') {
        letter = _source[_pos];
        _pos++;
      }
      if (_pos < _source.length && _source[_pos] == '}') _pos++;
    } else {
      letter = _source[_pos];
      _pos++;
    }

    // Map common letters to Unicode double-struck
    const bbMap = {
      'A': '𝔸',
      'B': '𝔹',
      'C': 'ℂ',
      'D': '𝔻',
      'E': '𝔼',
      'F': '𝔽',
      'G': '𝔾',
      'H': 'ℍ',
      'I': '𝕀',
      'J': '𝕁',
      'K': '𝕂',
      'L': '𝕃',
      'M': '𝕄',
      'N': 'ℕ',
      'O': '𝕆',
      'P': 'ℙ',
      'Q': 'ℚ',
      'R': 'ℝ',
      'S': '𝕊',
      'T': '𝕋',
      'U': '𝕌',
      'V': '𝕍',
      'W': '𝕎',
      'X': '𝕏',
      'Y': '𝕐',
      'Z': 'ℤ',
      '0': '𝟘',
      '1': '𝟙',
      '2': '𝟚',
      '3': '𝟛',
      '4': '𝟜',
      '5': '𝟝',
      '6': '𝟞',
      '7': '𝟟',
      '8': '𝟠',
      '9': '𝟡',
    };
    return LatexSymbol(bbMap[letter] ?? letter);
  }

  /// Parse `\mathcal{A}` — calligraphic font
  LatexAstNode _parseMathcal() {
    _skipWhitespace();
    if (_pos >= _source.length) {
      return const LatexErrorNode('\\mathcal', 'Expected argument');
    }
    String letter;
    if (_source[_pos] == '{') {
      _pos++;
      letter = '';
      if (_pos < _source.length && _source[_pos] != '}') {
        letter = _source[_pos];
        _pos++;
      }
      if (_pos < _source.length && _source[_pos] == '}') _pos++;
    } else {
      letter = _source[_pos];
      _pos++;
    }

    // Map uppercase to Unicode Script Mathematical Alphanumeric Symbols
    final code = letter.codeUnitAt(0);
    if (code >= 65 && code <= 90) {
      // U+1D49C (𝒜) offset = 0x1D49C - 0x41
      final calChar = String.fromCharCode(0x1D49C + (code - 65));
      return LatexSymbol(calChar);
    }
    return LatexSymbol(letter);
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

    // Read opening delimiter — may be a single char or a \command like \lfloor
    String open;
    if (_source[_pos] == '.') {
      open = '';
      _pos++;
    } else if (_source[_pos] == '\\') {
      // Backslash-command delimiter: \lfloor, \lceil, etc.
      _pos++;
      final cmd = _readCommandName();
      open = switch (cmd) {
        'lfloor' => '⌊',
        'lceil' => '⌈',
        'langle' => '⟨',
        'lvert' => '|',
        'lVert' => '‖',
        _ => cmd,
      };
    } else {
      open = _source[_pos].toString();
      _pos++;
    }

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
          String close;
          if (_source[_pos] == '.') {
            close = '';
            _pos++;
          } else if (_source[_pos] == '\\') {
            _pos++;
            final cmd = _readCommandName();
            close = switch (cmd) {
              'rfloor' => '⌋',
              'rceil' => '⌉',
              'rangle' => '⟩',
              'rvert' => '|',
              'rVert' => '‖',
              _ => cmd,
            };
          } else {
            close = _source[_pos].toString();
            _pos++;
          }
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

    // Cases environment.
    if (envName == 'cases') {
      return _parseCases(envName);
    }

    // Align / gather environments.
    if (envName == 'align' || envName == 'align*' || envName == 'gather' || envName == 'gather*') {
      return _parseAlign(envName);
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

  /// Parse `\color{name}{body}`.
  LatexAstNode _parseColor() {
    _skipWhitespace();
    final colorName = _parseBracedText();
    final body = _parseRequiredArg();
    return LatexColored(colorName, body);
  }

  /// Parse `\underbrace{body}_{annotation}` or `\overbrace{body}^{annotation}`.
  LatexAstNode _parseUnderOverBrace({required bool above}) {
    final body = _parseRequiredArg();
    // Check for subscript/superscript annotation
    _skipWhitespace();
    LatexAstNode annotation = const LatexGroup([]);
    if (_pos < _source.length) {
      if (!above && _source[_pos] == '_') {
        _pos++;
        annotation = _parseRequiredArg();
      } else if (above && _source[_pos] == '^') {
        _pos++;
        annotation = _parseRequiredArg();
      }
    }
    return LatexUnderOver(body, annotation, above: above, braceStyle: 'brace');
  }

  /// Parse `\not` followed by a symbol → negated Unicode.
  LatexAstNode _parseNot() {
    _skipWhitespace();
    if (_pos >= _source.length) {
      return const LatexSymbol('̸'); // combining slash
    }

    // Map next character or command to negated version
    if (_source[_pos] == '\\') {
      _pos++;
      final cmd = _readCommandName();
      return switch (cmd) {
        'in' => const LatexSymbol('∉'),
        'subset' => const LatexSymbol('⊄'),
        'supset' => const LatexSymbol('⊅'),
        'exists' => const LatexSymbol('∄'),
        'equiv' => const LatexSymbol('≢'),
        _ => LatexSymbol('̸'), // fallback combining slash
      };
    }

    final c = _source[_pos];
    _pos++;
    return switch (c) {
      '=' => const LatexSymbol('≠'),
      '<' => const LatexSymbol('≮'),
      '>' => const LatexSymbol('≯'),
      _ => LatexSymbol('$c̸'), // char + combining slash
    };
  }

  /// Parse `\mathfrak{A}` → fraktur Unicode.
  LatexAstNode _parseMathfrak() {
    _skipWhitespace();
    if (_pos >= _source.length) {
      return const LatexErrorNode('\\mathfrak', 'Expected argument');
    }
    String letter;
    if (_source[_pos] == '{') {
      _pos++;
      letter = '';
      if (_pos < _source.length && _source[_pos] != '}') {
        letter = _source[_pos];
        _pos++;
      }
      if (_pos < _source.length && _source[_pos] == '}') _pos++;
    } else {
      letter = _source[_pos];
      _pos++;
    }

    // Map uppercase to Mathematical Fraktur (U+1D504–U+1D537)
    final code = letter.codeUnitAt(0);
    if (code >= 65 && code <= 90) {
      // Some fraktur letters have special Unicode mappings
      const special = {'C': 'ℭ', 'H': 'ℌ', 'I': 'ℑ', 'R': 'ℜ', 'Z': 'ℨ'};
      if (special.containsKey(letter)) return LatexSymbol(special[letter]!);
      return LatexSymbol(String.fromCharCode(0x1D504 + (code - 65)));
    }
    if (code >= 97 && code <= 122) {
      return LatexSymbol(String.fromCharCode(0x1D51E + (code - 97)));
    }
    return LatexSymbol(letter);
  }

  /// Parse `\substack{a \\ b \\ c}` → stacked group.
  LatexAstNode _parseSubstack() {
    _skipWhitespace();
    if (_pos >= _source.length || _source[_pos] != '{') {
      return const LatexErrorNode('\\substack', 'Expected {');
    }
    _pos++; // skip {

    final rows = <List<LatexAstNode>>[];
    var currentRow = <LatexAstNode>[];

    int depth = 1;
    while (_pos < _source.length && depth > 0) {
      if (_source[_pos] == '{') depth++;
      if (_source[_pos] == '}') {
        depth--;
        if (depth == 0) { _pos++; break; }
      }
      // Row separator \\
      if (_pos < _source.length - 1 &&
          _source[_pos] == '\\' && _source[_pos + 1] == '\\') {
        _pos += 2;
        currentRow.add(_parseExpression());
        rows.add(currentRow);
        currentRow = [];
        continue;
      }
      currentRow.add(_parseExpression());
    }
    if (currentRow.isNotEmpty) rows.add(currentRow);

    // Render as a simple matrix without delimiters.
    return LatexMatrix(rows);
  }

  /// Parse `\xrightarrow[below]{above}` or `\xleftarrow{above}`.
  LatexAstNode _parseExtensibleArrow(String direction) {
    _skipWhitespace();
    LatexAstNode? below;
    LatexAstNode? above;

    // Optional [below]
    if (_pos < _source.length && _source[_pos] == '[') {
      _pos++; // skip [
      final buf = StringBuffer();
      while (_pos < _source.length && _source[_pos] != ']') {
        buf.write(_source[_pos]);
        _pos++;
      }
      if (_pos < _source.length) _pos++; // skip ]
      below = LatexParser.parse(buf.toString());
    }

    // Required {above}
    _skipWhitespace();
    if (_pos < _source.length && _source[_pos] == '{') {
      above = _parseRequiredArg();
    }

    return LatexExtensibleArrow(direction, above: above, below: below);
  }

  /// Parse `\begin{cases}...\end{cases}` — like matrix but with left brace.
  LatexAstNode _parseCases(String envName) {
    final rows = <List<LatexAstNode>>[];
    var currentRow = <LatexAstNode>[];
    final endMarker = '\\end{$envName}';

    while (_pos < _source.length) {
      // Check for \end{cases}
      if (_source.length >= _pos + endMarker.length &&
          _source.substring(_pos, _pos + endMarker.length) == endMarker) {
        _pos += endMarker.length;
        break;
      }

      // Row separator \\
      if (_pos < _source.length - 1 &&
          _source[_pos] == '\\' && _source[_pos + 1] == '\\') {
        _pos += 2;
        currentRow.add(_parseExpression());
        rows.add(currentRow);
        currentRow = [];
        continue;
      }

      // Column separator &
      if (_source[_pos] == '&') {
        _pos++;
        currentRow.add(_parseExpression());
        continue;
      }

      currentRow.add(_parseExpression());
    }

    if (currentRow.isNotEmpty) rows.add(currentRow);
    return LatexCases(rows);
  }

  /// Parse `\colorbox{color}{body}`.
  LatexAstNode _parseColorBox() {
    _skipWhitespace();
    final colorName = _parseBracedText();
    final body = _parseRequiredArg();
    return LatexColorBox(colorName, body);
  }

  /// Parse `\rule{width}{height}` — dimensions as TeX strings.
  LatexAstNode _parseRule() {
    _skipWhitespace();
    final widthStr = _parseBracedText();
    final heightStr = _parseBracedText();
    // Parse simple dimension strings like '1em', '2pt', '0.5cm'
    final w = _parseDimension(widthStr);
    final h = _parseDimension(heightStr);
    return LatexRule(w, h);
  }

  /// Parse a simple TeX dimension string to em units.
  double _parseDimension(String dim) {
    final trimmed = dim.trim();
    if (trimmed.endsWith('em')) {
      return double.tryParse(trimmed.substring(0, trimmed.length - 2).trim()) ?? 1.0;
    }
    if (trimmed.endsWith('pt')) {
      final pt = double.tryParse(trimmed.substring(0, trimmed.length - 2).trim()) ?? 10;
      return pt / 10; // rough pt→em
    }
    if (trimmed.endsWith('cm')) {
      final cm = double.tryParse(trimmed.substring(0, trimmed.length - 2).trim()) ?? 1;
      return cm * 2.84; // rough cm→em
    }
    if (trimmed.endsWith('mm')) {
      final mm = double.tryParse(trimmed.substring(0, trimmed.length - 2).trim()) ?? 10;
      return mm * 0.284; // rough mm→em
    }
    // Plain number — treat as em.
    return double.tryParse(trimmed) ?? 1.0;
  }

  /// Parse `\begin{align}...\end{align}` — rows with & alignment.
  LatexAstNode _parseAlign(String envName) {
    final rows = <List<LatexAstNode>>[];
    var currentRow = <LatexAstNode>[];
    final endMarker = '\\end{$envName}';

    while (_pos < _source.length) {
      if (_source.length >= _pos + endMarker.length &&
          _source.substring(_pos, _pos + endMarker.length) == endMarker) {
        _pos += endMarker.length;
        break;
      }

      // Row separator \\
      if (_pos < _source.length - 1 &&
          _source[_pos] == '\\' && _source[_pos + 1] == '\\') {
        _pos += 2;
        currentRow.add(_parseExpression());
        rows.add(currentRow);
        currentRow = [];
        continue;
      }

      // Column separator &
      if (_source[_pos] == '&') {
        _pos++;
        currentRow.add(_parseExpression());
        continue;
      }

      currentRow.add(_parseExpression());
    }

    if (currentRow.isNotEmpty) rows.add(currentRow);
    return LatexAlign(rows);
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

    // No postfix found → return as-is
    if (!hasSub && !hasSup) return base;

    // ── Special handling: BigOperator limits ──
    // \int_0^1, \sum_{n=1}^{N}, \prod_{k}, etc.
    // Fill the operator's own lower/upper fields so the layout engine
    // uses the correct stacking (display) or inline positioning.
    if (base is LatexBigOperator) {
      return LatexBigOperator(
        base.operator,
        lower: sub,
        upper: sup,
      );
    }

    // ── Special handling: \lim subscript ──
    // \lim_{x \to 0} → LatexLimit(subscript: x → 0)
    if (base is LatexLimit && hasSub) {
      return LatexLimit(subscript: sub);
    }

    // ── Standard sub/superscript ──
    if (hasSub && hasSup) {
      return LatexSubSuperscript(base, sub!, sup!);
    } else if (hasSup) {
      return LatexSuperscript(base, sup!);
    } else {
      return LatexSubscript(base, sub!);
    }
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
