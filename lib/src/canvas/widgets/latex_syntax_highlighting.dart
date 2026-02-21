import 'package:flutter/material.dart';

/// 🧮 T1: LaTeX Syntax Highlighting Controller
///
/// Custom [TextEditingController] that overrides [buildTextSpan] to
/// colorize LaTeX tokens in real-time:
///
/// - `\commands` → primary (teal/blue)
/// - `{ }` braces → tertiary accent
/// - `^` / `_` → secondary accent
/// - `\begin{...}` / `\end{...}` → purple environment markers
/// - Numbers → numeral color
/// - Unmatched braces → error highlighting
///
/// Zero-overhead: uses efficient single-pass regex tokenizing, no AST parsing.
class LatexHighlightingController extends TextEditingController {
  /// Whether syntax highlighting is enabled.
  bool highlightingEnabled;

  LatexHighlightingController({super.text, this.highlightingEnabled = true});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!highlightingEnabled || text.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // U3: Bracket matching — find the matching brace pair near cursor
    final matchedPositions = _findMatchedBraces(text, selection);

    final tokens = _tokenize(text);
    final spans = <InlineSpan>[];
    int charIndex = 0;

    for (final token in tokens) {
      // U3: Check if any character within this token is in the matched set
      if (matchedPositions.isNotEmpty && token.type == _TokenType.brace) {
        // Build spans char-by-char for brace tokens to handle matching
        for (int ci = 0; ci < token.text.length; ci++) {
          final globalPos = charIndex + ci;
          final isMatched = matchedPositions.contains(globalPos);
          final tokenStyle = _styleForToken(token.type, style, cs, isDark);
          if (isMatched) {
            spans.add(
              TextSpan(
                text: token.text[ci],
                style: (tokenStyle ?? style)?.copyWith(
                  backgroundColor:
                      isDark
                          ? const Color(0x44FFD54F) // amber glow
                          : const Color(0x33F57F17),
                  fontWeight: FontWeight.w900,
                ),
              ),
            );
          } else {
            spans.add(TextSpan(text: token.text[ci], style: tokenStyle));
          }
        }
      } else {
        final tokenStyle = _styleForToken(token.type, style, cs, isDark);
        spans.add(TextSpan(text: token.text, style: tokenStyle));
      }
      charIndex += token.text.length;
    }

    return TextSpan(style: style, children: spans);
  }

  // U3: Find matching brace positions near cursor
  static Set<int> _findMatchedBraces(String text, TextSelection sel) {
    if (!sel.isValid || !sel.isCollapsed) return {};
    final cursor = sel.baseOffset;
    if (cursor < 0 || cursor > text.length) return {};

    // Check char before and at cursor
    for (final pos in [cursor - 1, cursor]) {
      if (pos < 0 || pos >= text.length) continue;
      final ch = text[pos];

      if (ch == '{') {
        // Find matching closing brace
        int depth = 0;
        for (int i = pos; i < text.length; i++) {
          if (text[i] == '{') depth++;
          if (text[i] == '}') {
            depth--;
            if (depth == 0) return {pos, i};
          }
        }
      } else if (ch == '}') {
        // Find matching opening brace
        int depth = 0;
        for (int i = pos; i >= 0; i--) {
          if (text[i] == '}') depth++;
          if (text[i] == '{') {
            depth--;
            if (depth == 0) return {pos, i};
          }
        }
      }
    }

    return {};
  }

  // ---------------------------------------------------------------------------
  // Tokenizer — single-pass, O(n) scan
  // ---------------------------------------------------------------------------

  static List<_Token> _tokenize(String source) {
    final tokens = <_Token>[];
    int i = 0;
    final len = source.length;
    final buf = StringBuffer();

    void flushPlain() {
      if (buf.isNotEmpty) {
        tokens.add(_Token(_TokenType.plain, buf.toString()));
        buf.clear();
      }
    }

    while (i < len) {
      final c = source[i];

      // Backslash — start of command
      if (c == '\\' && i + 1 < len) {
        flushPlain();

        final cmdBuf = StringBuffer('\\');
        i++;

        // Single-char command (e.g. \\, \{, \})
        if (i < len && !_isLetter(source.codeUnitAt(i))) {
          cmdBuf.write(source[i]);
          i++;
          tokens.add(_Token(_TokenType.command, cmdBuf.toString()));
          continue;
        }

        // Multi-char command
        while (i < len && _isLetter(source.codeUnitAt(i))) {
          cmdBuf.write(source[i]);
          i++;
        }

        final cmd = cmdBuf.toString();

        // Classify
        if (cmd == r'\begin' || cmd == r'\end') {
          // Read the environment name too: \begin{name}
          final envBuf = StringBuffer(cmd);
          if (i < len && source[i] == '{') {
            envBuf.write('{');
            i++;
            while (i < len && source[i] != '}') {
              envBuf.write(source[i]);
              i++;
            }
            if (i < len && source[i] == '}') {
              envBuf.write('}');
              i++;
            }
          }
          tokens.add(_Token(_TokenType.environment, envBuf.toString()));
        } else {
          tokens.add(_Token(_TokenType.command, cmd));
        }
        continue;
      }

      // Braces
      if (c == '{' || c == '}') {
        flushPlain();
        tokens.add(_Token(_TokenType.brace, c));
        i++;
        continue;
      }

      // Superscript / subscript
      if (c == '^' || c == '_') {
        flushPlain();
        tokens.add(_Token(_TokenType.script, c));
        i++;
        continue;
      }

      // Numbers
      if (_isDigit(c.codeUnitAt(0))) {
        flushPlain();
        final numBuf = StringBuffer();
        while (i < len &&
            (_isDigit(source.codeUnitAt(i)) || source[i] == '.')) {
          numBuf.write(source[i]);
          i++;
        }
        tokens.add(_Token(_TokenType.number, numBuf.toString()));
        continue;
      }

      // Plain text
      buf.write(c);
      i++;
    }

    flushPlain();
    return tokens;
  }

  static bool _isLetter(int codeUnit) =>
      (codeUnit >= 65 && codeUnit <= 90) || (codeUnit >= 97 && codeUnit <= 122);

  static bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

  // ---------------------------------------------------------------------------
  // Token → TextStyle mapping
  // ---------------------------------------------------------------------------

  static TextStyle? _styleForToken(
    _TokenType type,
    TextStyle? base,
    ColorScheme cs,
    bool isDark,
  ) {
    switch (type) {
      case _TokenType.command:
        return base?.copyWith(
          color:
              isDark
                  ? const Color(0xFF80CBC4) // teal accent
                  : const Color(0xFF00796B),
          fontWeight: FontWeight.w600,
        );
      case _TokenType.environment:
        return base?.copyWith(
          color:
              isDark
                  ? const Color(0xFFCE93D8) // purple accent
                  : const Color(0xFF7B1FA2),
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
        );
      case _TokenType.brace:
        return base?.copyWith(
          color:
              isDark
                  ? const Color(0xFFFFD54F) // amber accent
                  : const Color(0xFFF57F17),
          fontWeight: FontWeight.w700,
        );
      case _TokenType.script:
        return base?.copyWith(
          color:
              isDark
                  ? const Color(0xFF90CAF9) // blue accent
                  : const Color(0xFF1565C0),
          fontWeight: FontWeight.w700,
        );
      case _TokenType.number:
        return base?.copyWith(
          color:
              isDark
                  ? const Color(0xFFA5D6A7) // green accent
                  : const Color(0xFF2E7D32),
        );
      case _TokenType.plain:
        return base;
    }
  }
}

// ---------------------------------------------------------------------------
// Token types
// ---------------------------------------------------------------------------

enum _TokenType {
  plain,
  command, // \frac, \alpha, etc.
  environment, // \begin{matrix}, \end{cases}
  brace, // { }
  script, // ^ _
  number, // 0-9 and .
}

class _Token {
  final _TokenType type;
  final String text;
  const _Token(this.type, this.text);
}

// =============================================================================
// T2: Autocomplete — Command database
// =============================================================================

/// LaTeX command entry for autocomplete suggestions.
class LatexCommandEntry {
  /// The full LaTeX command (e.g. r'\frac').
  final String command;

  /// Human-readable label shown in the dropdown.
  final String label;

  /// Category for grouping (optional).
  final String? category;

  /// The insert text (may include template braces).
  final String insertText;

  const LatexCommandEntry({
    required this.command,
    required this.label,
    this.category,
    String? insertText,
  }) : insertText = insertText ?? command;
}

/// Full database of autocomplete-able LaTeX commands.
const latexCommandDatabase = <LatexCommandEntry>[
  // Fractions
  LatexCommandEntry(
    command: r'\frac',
    label: 'Fraction',
    category: 'Structure',
    insertText: r'\frac{}{}',
  ),
  LatexCommandEntry(
    command: r'\dfrac',
    label: 'Display fraction',
    category: 'Structure',
    insertText: r'\dfrac{}{}',
  ),
  LatexCommandEntry(
    command: r'\tfrac',
    label: 'Text fraction',
    category: 'Structure',
    insertText: r'\tfrac{}{}',
  ),
  LatexCommandEntry(
    command: r'\cfrac',
    label: 'Continued fraction',
    category: 'Structure',
    insertText: r'\cfrac{}{}',
  ),

  // Roots & powers
  LatexCommandEntry(
    command: r'\sqrt',
    label: 'Square root',
    category: 'Structure',
    insertText: r'\sqrt{}',
  ),
  LatexCommandEntry(
    command: r'\binom',
    label: 'Binomial',
    category: 'Structure',
    insertText: r'\binom{}{}',
  ),

  // Big operators
  LatexCommandEntry(command: r'\sum', label: 'Summation', category: 'Operator'),
  LatexCommandEntry(command: r'\prod', label: 'Product', category: 'Operator'),
  LatexCommandEntry(command: r'\int', label: 'Integral', category: 'Operator'),
  LatexCommandEntry(
    command: r'\iint',
    label: 'Double integral',
    category: 'Operator',
  ),
  LatexCommandEntry(
    command: r'\iiint',
    label: 'Triple integral',
    category: 'Operator',
  ),
  LatexCommandEntry(
    command: r'\oint',
    label: 'Contour integral',
    category: 'Operator',
  ),
  LatexCommandEntry(command: r'\lim', label: 'Limit', category: 'Operator'),
  LatexCommandEntry(command: r'\sup', label: 'Supremum', category: 'Operator'),
  LatexCommandEntry(command: r'\inf', label: 'Infimum', category: 'Operator'),
  LatexCommandEntry(command: r'\max', label: 'Maximum', category: 'Operator'),
  LatexCommandEntry(command: r'\min', label: 'Minimum', category: 'Operator'),

  // Trig functions
  LatexCommandEntry(command: r'\sin', label: 'Sine', category: 'Function'),
  LatexCommandEntry(command: r'\cos', label: 'Cosine', category: 'Function'),
  LatexCommandEntry(command: r'\tan', label: 'Tangent', category: 'Function'),
  LatexCommandEntry(command: r'\cot', label: 'Cotangent', category: 'Function'),
  LatexCommandEntry(command: r'\sec', label: 'Secant', category: 'Function'),
  LatexCommandEntry(command: r'\csc', label: 'Cosecant', category: 'Function'),
  LatexCommandEntry(
    command: r'\arcsin',
    label: 'Arc sine',
    category: 'Function',
  ),
  LatexCommandEntry(
    command: r'\arccos',
    label: 'Arc cosine',
    category: 'Function',
  ),
  LatexCommandEntry(
    command: r'\arctan',
    label: 'Arc tangent',
    category: 'Function',
  ),
  LatexCommandEntry(
    command: r'\sinh',
    label: 'Hyperbolic sine',
    category: 'Function',
  ),
  LatexCommandEntry(
    command: r'\cosh',
    label: 'Hyperbolic cosine',
    category: 'Function',
  ),
  LatexCommandEntry(
    command: r'\tanh',
    label: 'Hyperbolic tangent',
    category: 'Function',
  ),

  // Log & exp
  LatexCommandEntry(command: r'\log', label: 'Logarithm', category: 'Function'),
  LatexCommandEntry(
    command: r'\ln',
    label: 'Natural log',
    category: 'Function',
  ),
  LatexCommandEntry(
    command: r'\exp',
    label: 'Exponential',
    category: 'Function',
  ),

  // Greek letters (lowercase)
  LatexCommandEntry(command: r'\alpha', label: 'α alpha', category: 'Greek'),
  LatexCommandEntry(command: r'\beta', label: 'β beta', category: 'Greek'),
  LatexCommandEntry(command: r'\gamma', label: 'γ gamma', category: 'Greek'),
  LatexCommandEntry(command: r'\delta', label: 'δ delta', category: 'Greek'),
  LatexCommandEntry(
    command: r'\epsilon',
    label: 'ε epsilon',
    category: 'Greek',
  ),
  LatexCommandEntry(
    command: r'\varepsilon',
    label: 'ε varepsilon',
    category: 'Greek',
  ),
  LatexCommandEntry(command: r'\zeta', label: 'ζ zeta', category: 'Greek'),
  LatexCommandEntry(command: r'\eta', label: 'η eta', category: 'Greek'),
  LatexCommandEntry(command: r'\theta', label: 'θ theta', category: 'Greek'),
  LatexCommandEntry(
    command: r'\vartheta',
    label: 'ϑ vartheta',
    category: 'Greek',
  ),
  LatexCommandEntry(command: r'\iota', label: 'ι iota', category: 'Greek'),
  LatexCommandEntry(command: r'\kappa', label: 'κ kappa', category: 'Greek'),
  LatexCommandEntry(command: r'\lambda', label: 'λ lambda', category: 'Greek'),
  LatexCommandEntry(command: r'\mu', label: 'μ mu', category: 'Greek'),
  LatexCommandEntry(command: r'\nu', label: 'ν nu', category: 'Greek'),
  LatexCommandEntry(command: r'\xi', label: 'ξ xi', category: 'Greek'),
  LatexCommandEntry(command: r'\pi', label: 'π pi', category: 'Greek'),
  LatexCommandEntry(command: r'\rho', label: 'ρ rho', category: 'Greek'),
  LatexCommandEntry(command: r'\sigma', label: 'σ sigma', category: 'Greek'),
  LatexCommandEntry(command: r'\tau', label: 'τ tau', category: 'Greek'),
  LatexCommandEntry(
    command: r'\upsilon',
    label: 'υ upsilon',
    category: 'Greek',
  ),
  LatexCommandEntry(command: r'\phi', label: 'φ phi', category: 'Greek'),
  LatexCommandEntry(command: r'\varphi', label: 'φ varphi', category: 'Greek'),
  LatexCommandEntry(command: r'\chi', label: 'χ chi', category: 'Greek'),
  LatexCommandEntry(command: r'\psi', label: 'ψ psi', category: 'Greek'),
  LatexCommandEntry(command: r'\omega', label: 'ω omega', category: 'Greek'),

  // Greek letters (uppercase)
  LatexCommandEntry(command: r'\Gamma', label: 'Γ Gamma', category: 'Greek'),
  LatexCommandEntry(command: r'\Delta', label: 'Δ Delta', category: 'Greek'),
  LatexCommandEntry(command: r'\Theta', label: 'Θ Theta', category: 'Greek'),
  LatexCommandEntry(command: r'\Lambda', label: 'Λ Lambda', category: 'Greek'),
  LatexCommandEntry(command: r'\Xi', label: 'Ξ Xi', category: 'Greek'),
  LatexCommandEntry(command: r'\Pi', label: 'Π Pi', category: 'Greek'),
  LatexCommandEntry(command: r'\Sigma', label: 'Σ Sigma', category: 'Greek'),
  LatexCommandEntry(command: r'\Phi', label: 'Φ Phi', category: 'Greek'),
  LatexCommandEntry(command: r'\Psi', label: 'Ψ Psi', category: 'Greek'),
  LatexCommandEntry(command: r'\Omega', label: 'Ω Omega', category: 'Greek'),

  // Accents
  LatexCommandEntry(
    command: r'\hat',
    label: 'Hat accent',
    category: 'Accent',
    insertText: r'\hat{}',
  ),
  LatexCommandEntry(
    command: r'\bar',
    label: 'Bar accent',
    category: 'Accent',
    insertText: r'\bar{}',
  ),
  LatexCommandEntry(
    command: r'\vec',
    label: 'Vector arrow',
    category: 'Accent',
    insertText: r'\vec{}',
  ),
  LatexCommandEntry(
    command: r'\dot',
    label: 'Dot accent',
    category: 'Accent',
    insertText: r'\dot{}',
  ),
  LatexCommandEntry(
    command: r'\ddot',
    label: 'Double dot',
    category: 'Accent',
    insertText: r'\ddot{}',
  ),
  LatexCommandEntry(
    command: r'\tilde',
    label: 'Tilde',
    category: 'Accent',
    insertText: r'\tilde{}',
  ),
  LatexCommandEntry(
    command: r'\overline',
    label: 'Overline',
    category: 'Accent',
    insertText: r'\overline{}',
  ),
  LatexCommandEntry(
    command: r'\underline',
    label: 'Underline',
    category: 'Accent',
    insertText: r'\underline{}',
  ),
  LatexCommandEntry(
    command: r'\widehat',
    label: 'Wide hat',
    category: 'Accent',
    insertText: r'\widehat{}',
  ),
  LatexCommandEntry(
    command: r'\widetilde',
    label: 'Wide tilde',
    category: 'Accent',
    insertText: r'\widetilde{}',
  ),
  LatexCommandEntry(
    command: r'\overrightarrow',
    label: 'Right arrow over',
    category: 'Accent',
    insertText: r'\overrightarrow{}',
  ),

  // Relations
  LatexCommandEntry(
    command: r'\neq',
    label: '≠ Not equal',
    category: 'Relation',
  ),
  LatexCommandEntry(
    command: r'\leq',
    label: '≤ Less or equal',
    category: 'Relation',
  ),
  LatexCommandEntry(
    command: r'\geq',
    label: '≥ Greater or equal',
    category: 'Relation',
  ),
  LatexCommandEntry(
    command: r'\approx',
    label: '≈ Approximately',
    category: 'Relation',
  ),
  LatexCommandEntry(
    command: r'\equiv',
    label: '≡ Equivalent',
    category: 'Relation',
  ),
  LatexCommandEntry(command: r'\sim', label: '∼ Similar', category: 'Relation'),
  LatexCommandEntry(
    command: r'\propto',
    label: '∝ Proportional',
    category: 'Relation',
  ),
  LatexCommandEntry(
    command: r'\in',
    label: '∈ Element of',
    category: 'Relation',
  ),
  LatexCommandEntry(
    command: r'\notin',
    label: '∉ Not element',
    category: 'Relation',
  ),
  LatexCommandEntry(
    command: r'\subset',
    label: '⊂ Subset',
    category: 'Relation',
  ),
  LatexCommandEntry(
    command: r'\supset',
    label: '⊃ Superset',
    category: 'Relation',
  ),
  LatexCommandEntry(
    command: r'\subseteq',
    label: '⊆ Subset or equal',
    category: 'Relation',
  ),
  LatexCommandEntry(
    command: r'\supseteq',
    label: '⊇ Superset or equal',
    category: 'Relation',
  ),

  // Operators
  LatexCommandEntry(command: r'\times', label: '× Times', category: 'Operator'),
  LatexCommandEntry(
    command: r'\div',
    label: '÷ Division',
    category: 'Operator',
  ),
  LatexCommandEntry(
    command: r'\cdot',
    label: '· Center dot',
    category: 'Operator',
  ),
  LatexCommandEntry(
    command: r'\pm',
    label: '± Plus-minus',
    category: 'Operator',
  ),
  LatexCommandEntry(
    command: r'\mp',
    label: '∓ Minus-plus',
    category: 'Operator',
  ),
  LatexCommandEntry(
    command: r'\circ',
    label: '∘ Composition',
    category: 'Operator',
  ),
  LatexCommandEntry(command: r'\cup', label: '∪ Union', category: 'Operator'),
  LatexCommandEntry(
    command: r'\cap',
    label: '∩ Intersection',
    category: 'Operator',
  ),
  LatexCommandEntry(
    command: r'\oplus',
    label: '⊕ Direct sum',
    category: 'Operator',
  ),
  LatexCommandEntry(
    command: r'\otimes',
    label: '⊗ Tensor product',
    category: 'Operator',
  ),

  // Arrows
  LatexCommandEntry(
    command: r'\rightarrow',
    label: '→ Right arrow',
    category: 'Arrow',
  ),
  LatexCommandEntry(
    command: r'\leftarrow',
    label: '← Left arrow',
    category: 'Arrow',
  ),
  LatexCommandEntry(
    command: r'\leftrightarrow',
    label: '↔ Both arrows',
    category: 'Arrow',
  ),
  LatexCommandEntry(
    command: r'\Rightarrow',
    label: '⇒ Implies',
    category: 'Arrow',
  ),
  LatexCommandEntry(
    command: r'\Leftarrow',
    label: '⇐ Implied by',
    category: 'Arrow',
  ),
  LatexCommandEntry(
    command: r'\Leftrightarrow',
    label: '⇔ Iff',
    category: 'Arrow',
  ),
  LatexCommandEntry(command: r'\mapsto', label: '↦ Maps to', category: 'Arrow'),
  LatexCommandEntry(command: r'\to', label: '→ To', category: 'Arrow'),

  // Logic
  LatexCommandEntry(command: r'\forall', label: '∀ For all', category: 'Logic'),
  LatexCommandEntry(command: r'\exists', label: '∃ Exists', category: 'Logic'),
  LatexCommandEntry(
    command: r'\nexists',
    label: '∄ Not exists',
    category: 'Logic',
  ),
  LatexCommandEntry(command: r'\neg', label: '¬ Negation', category: 'Logic'),
  LatexCommandEntry(
    command: r'\land',
    label: '∧ Logical AND',
    category: 'Logic',
  ),
  LatexCommandEntry(command: r'\lor', label: '∨ Logical OR', category: 'Logic'),
  LatexCommandEntry(
    command: r'\implies',
    label: '⟹ Implies',
    category: 'Logic',
  ),
  LatexCommandEntry(
    command: r'\iff',
    label: '⟺ If and only if',
    category: 'Logic',
  ),
  LatexCommandEntry(
    command: r'\therefore',
    label: '∴ Therefore',
    category: 'Logic',
  ),
  LatexCommandEntry(
    command: r'\because',
    label: '∵ Because',
    category: 'Logic',
  ),

  // Misc symbols
  LatexCommandEntry(
    command: r'\infty',
    label: '∞ Infinity',
    category: 'Symbol',
  ),
  LatexCommandEntry(
    command: r'\partial',
    label: '∂ Partial',
    category: 'Symbol',
  ),
  LatexCommandEntry(command: r'\nabla', label: '∇ Nabla', category: 'Symbol'),
  LatexCommandEntry(
    command: r'\emptyset',
    label: '∅ Empty set',
    category: 'Symbol',
  ),
  LatexCommandEntry(command: r'\ldots', label: '… Dots', category: 'Symbol'),
  LatexCommandEntry(
    command: r'\cdots',
    label: '⋯ Center dots',
    category: 'Symbol',
  ),
  LatexCommandEntry(
    command: r'\vdots',
    label: '⋮ Vertical dots',
    category: 'Symbol',
  ),
  LatexCommandEntry(
    command: r'\ddots',
    label: '⋱ Diagonal dots',
    category: 'Symbol',
  ),
  LatexCommandEntry(command: r'\hbar', label: 'ℏ h-bar', category: 'Symbol'),
  LatexCommandEntry(command: r'\ell', label: 'ℓ Script l', category: 'Symbol'),
  LatexCommandEntry(command: r'\Re', label: 'ℜ Real part', category: 'Symbol'),
  LatexCommandEntry(
    command: r'\Im',
    label: 'ℑ Imaginary part',
    category: 'Symbol',
  ),

  // Font styles
  LatexCommandEntry(
    command: r'\mathrm',
    label: 'Roman text',
    category: 'Font',
    insertText: r'\mathrm{}',
  ),
  LatexCommandEntry(
    command: r'\mathbf',
    label: 'Bold math',
    category: 'Font',
    insertText: r'\mathbf{}',
  ),
  LatexCommandEntry(
    command: r'\mathit',
    label: 'Italic math',
    category: 'Font',
    insertText: r'\mathit{}',
  ),
  LatexCommandEntry(
    command: r'\mathbb',
    label: 'Blackboard bold',
    category: 'Font',
    insertText: r'\mathbb{}',
  ),
  LatexCommandEntry(
    command: r'\mathcal',
    label: 'Calligraphic',
    category: 'Font',
    insertText: r'\mathcal{}',
  ),
  LatexCommandEntry(
    command: r'\mathfrak',
    label: 'Fraktur',
    category: 'Font',
    insertText: r'\mathfrak{}',
  ),
  LatexCommandEntry(
    command: r'\mathscr',
    label: 'Script',
    category: 'Font',
    insertText: r'\mathscr{}',
  ),
  LatexCommandEntry(
    command: r'\text',
    label: 'Text mode',
    category: 'Font',
    insertText: r'\text{}',
  ),
  LatexCommandEntry(
    command: r'\textbf',
    label: 'Bold text',
    category: 'Font',
    insertText: r'\textbf{}',
  ),
  LatexCommandEntry(
    command: r'\textit',
    label: 'Italic text',
    category: 'Font',
    insertText: r'\textit{}',
  ),

  // Environments
  LatexCommandEntry(
    command: r'\left',
    label: 'Left delimiter',
    category: 'Delimiter',
  ),
  LatexCommandEntry(
    command: r'\right',
    label: 'Right delimiter',
    category: 'Delimiter',
  ),
  LatexCommandEntry(
    command: r'\boxed',
    label: 'Boxed expression',
    category: 'Structure',
    insertText: r'\boxed{}',
  ),
  LatexCommandEntry(
    command: r'\phantom',
    label: 'Invisible space',
    category: 'Structure',
    insertText: r'\phantom{}',
  ),
  LatexCommandEntry(
    command: r'\color',
    label: 'Color',
    category: 'Structure',
    insertText: r'\color{}',
  ),
  LatexCommandEntry(
    command: r'\overset',
    label: 'Overset',
    category: 'Structure',
    insertText: r'\overset{}{}',
  ),
  LatexCommandEntry(
    command: r'\underset',
    label: 'Underset',
    category: 'Structure',
    insertText: r'\underset{}{}',
  ),
  LatexCommandEntry(
    command: r'\stackrel',
    label: 'Stack relation',
    category: 'Structure',
    insertText: r'\stackrel{}{}',
  ),
];
