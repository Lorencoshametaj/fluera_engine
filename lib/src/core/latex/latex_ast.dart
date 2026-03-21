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

  /// Whether this symbol should be rendered in bold.
  /// Set by `\mathbf`, `\boldsymbol`, `\textbf`.
  final bool bold;

  const LatexSymbol(this.value, {this.italic = false, this.bold = false});
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

  /// When false, the vinculum (horizontal bar) is not drawn.
  /// Used for `\binom` and similar stacked notation.
  final bool showBar;

  const LatexFraction(this.numerator, this.denominator, {this.showBar = true});
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

// ---------------------------------------------------------------------------
// Extended AST Nodes (Batch 4 — new constructs)
// ---------------------------------------------------------------------------

/// A colored expression: `\color{red}{x+y}`
class LatexColored extends LatexAstNode {
  /// Color name (e.g. 'red', 'blue', '#FF0000').
  final String colorName;

  /// The body to render in that color.
  final LatexAstNode body;

  const LatexColored(this.colorName, this.body);
}

/// A boxed expression: `\boxed{E=mc^2}`
class LatexBoxed extends LatexAstNode {
  final LatexAstNode body;

  const LatexBoxed(this.body);
}

/// Under/over annotation: covers `\underbrace`, `\overbrace`,
/// `\stackrel`, `\overset`, `\underset`.
class LatexUnderOver extends LatexAstNode {
  /// The main body expression.
  final LatexAstNode body;

  /// The annotation (above or below).
  final LatexAstNode annotation;

  /// Whether the annotation goes above (true) or below (false).
  final bool above;

  /// Optional brace style: 'brace', 'none', or null.
  /// 'brace' draws a curly brace between body and annotation.
  final String? braceStyle;

  const LatexUnderOver(this.body, this.annotation, {
    required this.above,
    this.braceStyle,
  });
}

/// A cancelled (struck-through) expression: `\cancel{x}`, `\bcancel{x}`
class LatexCancel extends LatexAstNode {
  final LatexAstNode body;

  /// Cancel direction: 'forward' (/), 'back' (\), 'cross' (X).
  final String direction;

  const LatexCancel(this.body, {this.direction = 'forward'});
}

/// An invisible spacer: `\phantom{x}` — takes the space of x but renders nothing.
class LatexPhantom extends LatexAstNode {
  final LatexAstNode body;

  const LatexPhantom(this.body);
}

/// A cases environment: `\begin{cases} a & b \\ c & d \end{cases}`
///
/// Renders as a left brace followed by rows of condition/value pairs.
class LatexCases extends LatexAstNode {
  /// Each row is a list of cells (typically 2: expression and condition).
  final List<List<LatexAstNode>> rows;

  const LatexCases(this.rows);
}

/// An extensible arrow: `\xrightarrow{text}` or `\xleftarrow[below]{above}`
class LatexExtensibleArrow extends LatexAstNode {
  /// Arrow direction: 'right', 'left'.
  final String direction;

  /// Text above the arrow.
  final LatexAstNode? above;

  /// Text below the arrow.
  final LatexAstNode? below;

  const LatexExtensibleArrow(this.direction, {this.above, this.below});
}

/// Multi-line aligned equations: `\begin{align} a &= b \\ c &= d \end{align}`
///
/// Each row is split at `&` into left and right halves.
/// The `&` marks the alignment point (typically before `=`).
class LatexAlign extends LatexAstNode {
  /// Rows of equation pairs. Each row has 1 or 2 cells.
  final List<List<LatexAstNode>> rows;

  const LatexAlign(this.rows);
}

/// A colored background box: `\colorbox{yellow}{x+y}`
class LatexColorBox extends LatexAstNode {
  /// Background color name.
  final String colorName;

  /// The body to render with colored background.
  final LatexAstNode body;

  const LatexColorBox(this.colorName, this.body);
}

/// A horizontal rule: `\rule{width}{height}`
class LatexRule extends LatexAstNode {
  /// Width in em units.
  final double widthEm;

  /// Height in em units.
  final double heightEm;

  const LatexRule(this.widthEm, this.heightEm);
}
