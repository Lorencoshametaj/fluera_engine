/// 🧮 LaTeX Abstract Syntax Tree — node types for parsed LaTeX expressions.
///
/// The AST is produced by [LatexParser] from a LaTeX source string.
/// Each node represents a semantic element in the mathematical expression
/// (fraction, superscript, symbol, etc.).
///
/// The tree is consumed by [LatexLayoutEngine] to compute positioned
/// draw commands for rendering.

/// Base class for all LaTeX AST nodes.
sealed class LatexAstNode {
  const LatexAstNode();
}

/// A single character: letter, digit, or Unicode math symbol.
///
/// Examples: `x`, `2`, `α`, `+`, `=`
class LatexSymbol extends LatexAstNode {
  /// The character or symbol string.
  final String value;

  /// Whether this symbol should be rendered in italic.
  /// By convention, single latin letters in math are italic.
  final bool italic;

  const LatexSymbol(this.value, {this.italic = false});
}

/// A group of consecutive AST nodes (like `{a + b}`).
class LatexGroup extends LatexAstNode {
  final List<LatexAstNode> children;

  const LatexGroup(this.children);
}

/// A fraction: `\frac{numerator}{denominator}`
class LatexFraction extends LatexAstNode {
  final LatexAstNode numerator;
  final LatexAstNode denominator;

  const LatexFraction(this.numerator, this.denominator);
}

/// A superscript: `base^{exponent}`
class LatexSuperscript extends LatexAstNode {
  final LatexAstNode base;
  final LatexAstNode exponent;

  const LatexSuperscript(this.base, this.exponent);
}

/// A subscript: `base_{subscript}`
class LatexSubscript extends LatexAstNode {
  final LatexAstNode base;
  final LatexAstNode subscript;

  const LatexSubscript(this.base, this.subscript);
}

/// Combined sub/superscript: `base_{sub}^{sup}`
class LatexSubSuperscript extends LatexAstNode {
  final LatexAstNode base;
  final LatexAstNode subscript;
  final LatexAstNode superscript;

  const LatexSubSuperscript(this.base, this.subscript, this.superscript);
}

/// A square root: `\sqrt{radicand}` or `\sqrt[degree]{radicand}`
class LatexSqrt extends LatexAstNode {
  final LatexAstNode radicand;

  /// Optional degree (e.g. cube root `\sqrt[3]{x}`)
  final LatexAstNode? degree;

  const LatexSqrt(this.radicand, {this.degree});
}

/// A big operator with optional limits: `\int_{lower}^{upper} body`
///
/// Covers: `\int`, `\sum`, `\prod`, `\oint`, `\iint`, `\iiint`
class LatexBigOperator extends LatexAstNode {
  /// The operator symbol string (e.g. `∫`, `∑`, `∏`).
  final String operator;

  /// Lower limit (subscript position).
  final LatexAstNode? lower;

  /// Upper limit (superscript position).
  final LatexAstNode? upper;

  const LatexBigOperator(this.operator, {this.lower, this.upper});
}

/// A matrix or array: `\begin{matrix}...\end{matrix}`
class LatexMatrix extends LatexAstNode {
  /// Rows of cells, each cell being an AST node.
  final List<List<LatexAstNode>> rows;

  /// Matrix style (plain, parenthesized, bracketed, etc.)
  final MatrixStyle style;

  const LatexMatrix(this.rows, {this.style = MatrixStyle.plain});
}

/// Matrix delimiter styles.
enum MatrixStyle {
  /// No delimiters: `matrix`
  plain,

  /// Parentheses: `pmatrix`
  parenthesized,

  /// Square brackets: `bmatrix`
  bracketed,

  /// Curly braces: `Bmatrix`
  braced,

  /// Vertical bars: `vmatrix`
  verticalBar,

  /// Double vertical bars: `Vmatrix`
  doubleVerticalBar,
}

/// Delimited expression: `\left( ... \right)`
class LatexDelimited extends LatexAstNode {
  /// Opening delimiter character (e.g. `(`, `[`, `{`, `|`)
  final String open;

  /// Closing delimiter character
  final String close;

  /// The body inside the delimiters.
  final LatexAstNode body;

  const LatexDelimited(this.open, this.close, this.body);
}

/// A `\text{...}` block — renders in upright (roman) font.
class LatexText extends LatexAstNode {
  final String text;

  const LatexText(this.text);
}

/// Explicit spacing: `\,`, `\;`, `\quad`, `\qquad`, `\!`
class LatexSpace extends LatexAstNode {
  /// Space width in em units.
  final double emWidth;

  const LatexSpace(this.emWidth);
}

/// A limit expression: `\lim_{x \to 0}`
class LatexLimit extends LatexAstNode {
  /// The expression under the limit.
  final LatexAstNode? subscript;

  const LatexLimit({this.subscript});
}

/// An accent on a base: `\hat{x}`, `\bar{x}`, `\vec{x}`, etc.
class LatexAccent extends LatexAstNode {
  /// The accent type identifier (e.g. 'hat', 'bar', 'vec', 'dot', 'tilde')
  final String accentType;

  /// The base expression under the accent.
  final LatexAstNode base;

  const LatexAccent(this.accentType, this.base);
}

/// An error node for unparseable segments.
///
/// Allows the parser to recover from errors without crashing,
/// preserving as much of the expression as possible.
class LatexErrorNode extends LatexAstNode {
  /// The raw text that could not be parsed.
  final String rawText;

  /// Human-readable error message.
  final String message;

  const LatexErrorNode(this.rawText, this.message);
}
