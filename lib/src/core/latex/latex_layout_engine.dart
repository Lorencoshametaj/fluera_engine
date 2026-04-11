import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'latex_ast.dart';
import 'latex_draw_command.dart';

/// 🧮 LaTeX Layout Engine — converts an AST into positioned draw commands.
///
/// Implements TeX-inspired math typesetting rules to compute the position,
/// size, and style of every glyph and line in the expression.
///
/// The layout is deterministic and side-effect-free: given the same AST,
/// fontSize, color, and fontFamily, it always produces identical output.
///
/// Example:
/// ```dart
/// final ast = LatexParser.parse(r'\frac{a}{b}');
/// final result = LatexLayoutEngine.layout(
///   ast,
///   fontSize: 24,
///   color: Colors.white,
///   fontFamily: 'STIX Two Math',
/// );
/// // result.commands → [GlyphDrawCommand, LineDrawCommand, GlyphDrawCommand]
/// // result.size → Size(width, height)
/// ```
///
/// ## Recommended math fonts (include in pubspec.yaml assets):
/// - `STIX Two Math`   — excellent Unicode coverage, free (SIL OFL)
/// - `Latin Modern Math` — closest to LaTeX default Computer Modern
/// - `Libertinus Math` — elegant serif alternative
/// - `Fira Math`       — modern sans-serif option
class LatexLayoutEngine {
  /// Layout an AST tree into positioned draw commands.
  ///
  /// [fontFamily] sets the math font for all glyphs. Recommended: 'STIX Two Math'
  /// or 'Latin Modern Math'. Falls back to system default if null.
  /// Default math font family. Set once so all call sites automatically
  /// benefit from the bundled STIX Two Math font.
  static const String defaultMathFont = 'STIXTwoMath';

  static LatexLayoutResult layout(
    LatexAstNode node, {
    required double fontSize,
    required Color color,
    String? fontFamily,
  }) {
    final engine = LatexLayoutEngine._(
      mathFontFamily: fontFamily ?? defaultMathFont,
    );
    final box = engine._layout(node, fontSize, color);
    return LatexLayoutResult(
      commands: engine._commands,
      size: Size(box.width, box.height),
      baseline: box.baseline,
    );
  }

  LatexLayoutEngine._({String? mathFontFamily})
    : _mathFontFamily = mathFontFamily;

  final List<LatexDrawCommand> _commands = [];

  /// Math font family applied to every glyph. Setting this to a dedicated
  /// math font (e.g. 'STIX Two Math') is the single biggest visual upgrade.
  final String? _mathFontFamily;

  // L: Global measurement cache — shared across all LatexLayoutEngine
  // instances so repeated formulas don't re-measure the same glyphs.
  static final Map<String, double> _widthCache = {};

  // ---------------------------------------------------------------------------
  // TeX-Inspired Constants (proportional to fontSize / 1 em)
  //
  // Derived from The TeXbook (Knuth) and the OpenType MATH table spec.
  // All values are fractions of the current font size (1 em).
  // ---------------------------------------------------------------------------

  /// Scale factor for first-level sub/superscripts. TeX uses √½ ≈ 0.707.
  static const double _scriptScale = 0.71;

  /// Scale factor for second-level scripts (script-of-script).
  static const double _scriptScriptScale = 0.504;

  /// Superscript vertical shift (upward) as fraction of fontSize.
  /// TeX: SuperscriptShiftUp ≈ 0.413 em; bump slightly for digital clarity.
  static const double _superscriptShift = 0.45;

  /// Subscript vertical shift (downward) as fraction of fontSize.
  /// TeX: SubscriptShiftDown ≈ 0.2 em.
  static const double _subscriptShift = 0.22;

  /// Fraction bar thickness as fraction of fontSize.
  /// TeX: FractionRuleThickness ≈ 0.06 em.
  static const double _fractionBarThickness = 0.065;

  /// Gap between fraction bar and numerator/denominator.
  /// TeX: FractionNumDisplayStyleShiftUp gap contribution ≈ 0.15 em.
  static const double _fractionGap = 0.15;

  /// Horizontal padding inside fraction (left/right of bar).
  static const double _fractionPadding = 0.10;

  /// Radical symbol vertical clearance above radicand.
  static const double _radicalOverhang = 0.14;

  /// Baseline fraction (distance from top to baseline, as fraction of height).
  static const double _baselineFraction = 0.72;

  /// Math axis offset above baseline (fraction of fontSize).
  ///
  /// In TeX the math axis is the vertical center of the = sign and fraction
  /// bars. It sits above the geometric midline. TeX: AxisHeight ≈ 0.25 em.
  static const double _mathAxisOffset = 0.27;

  /// Approximate default character width as fraction of fontSize.
  static const double _charWidthFraction = 0.54;

  /// Spacing between ordinary atoms (tight kern, TeX Ord-Ord = 0).
  /// Only applied between non-operator siblings in groups; operators
  /// add their own spacing via _thinSpace / _thickSpace.
  static const double _atomSpacing = 0.02;

  /// TeX thin space (3 mu = 3/18 em ≈ 0.167 em).
  /// Used on both sides of binary operators: +, −, ×, ÷, ·, ±, ∓.
  static const double _thinSpace = 3.0 / 18.0;

  /// TeX thick space (5 mu = 5/18 em ≈ 0.278 em).
  /// Used on both sides of relational operators: =, ≠, <, >, ≤, ≥, ≈, ≡, ∼.
  static const double _thickSpace = 5.0 / 18.0;

  /// Space between big-operator glyph and inline limits (sub/superscript).
  /// Integrals need enough clearance so limits don't overlap the S-curve.
  static const double _bigOpLimitKern = 0.14;

  // ---------------------------------------------------------------------------
  // Core Layout
  // ---------------------------------------------------------------------------

  /// Layout any AST node and return its bounding box.
  _LayoutBox _layout(LatexAstNode node, double fs, Color color) {
    return switch (node) {
      LatexSymbol() => _layoutSymbol(node, fs, color),
      LatexGroup() => _layoutGroup(node, fs, color),
      LatexFraction() => _layoutFraction(node, fs, color),
      LatexSuperscript() => _layoutSuperscript(node, fs, color),
      LatexSubscript() => _layoutSubscript(node, fs, color),
      LatexSubSuperscript() => _layoutSubSuperscript(node, fs, color),
      LatexSqrt() => _layoutSqrt(node, fs, color),
      LatexBigOperator() => _layoutBigOperator(node, fs, color),
      LatexMatrix() => _layoutMatrix(node, fs, color),
      LatexDelimited() => _layoutDelimited(node, fs, color),
      LatexText() => _layoutText(node, fs, color),
      LatexSpace() => _layoutSpace(node, fs),
      LatexLimit() => _layoutLimit(node, fs, color),
      LatexAccent() => _layoutAccent(node, fs, color),
      LatexErrorNode() => _layoutError(node, fs, color),
      LatexColored() => _layoutColored(node, fs, color),
      LatexBoxed() => _layoutBoxed(node, fs, color),
      LatexUnderOver() => _layoutUnderOver(node, fs, color),
      LatexCancel() => _layoutCancel(node, fs, color),
      LatexPhantom() => _layoutPhantom(node, fs, color),
      LatexCases() => _layoutCases(node, fs, color),
      LatexExtensibleArrow() => _layoutExtensibleArrow(node, fs, color),
      LatexAlign() => _layoutAlign(node, fs, color),
      LatexColorBox() => _layoutColorBox(node, fs, color),
      LatexRule() => _layoutRule(node, fs, color),
    };
  }

  // ---------------------------------------------------------------------------
  // Layout Methods
  // ---------------------------------------------------------------------------

  _LayoutBox _layoutSymbol(LatexSymbol node, double fs, Color color) {
    final isBinary = _isBinaryOperator(node.value);
    final isRelational = _isRelationalOperator(node.value);
    final isOperator = isBinary || isRelational;

    final charWidth = _measureCharWidth(node.value, fs, italic: node.italic);
    final height = fs;
    final baseline = fs * _baselineFraction;

    // Align binary/relational operators to the math axis so that, e.g.,
    // the = sign sits centered vertically in the line.
    final yShift = isOperator ? fs * _mathAxisOffset * 0.5 : 0.0;

    _commands.add(
      GlyphDrawCommand(
        text: node.value,
        x: 0,
        y: -yShift,
        fontSize: fs,
        color: color,
        fontFamily: _mathFontFamily,
        italic: node.italic,
        bold: node.bold,
      ),
    );

    // TeX spacing around operators:
    //   relational (=, ≠, ≤, ≥ …) → thick space (5 mu each side)
    //   binary     (+, −, ×, ÷ …) → thin space  (3 mu each side)
    final double sideSpacing;
    if (isRelational) {
      sideSpacing = fs * _thickSpace;
    } else if (isBinary) {
      sideSpacing = fs * _thinSpace;
    } else {
      sideSpacing = 0.0;
    }

    final totalWidth = charWidth + sideSpacing * 2;

    return _LayoutBox(
      width: totalWidth,
      height: height,
      baseline: baseline,
      commandStart: _commands.length - 1,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutGroup(LatexGroup node, double fs, Color color) {
    if (node.children.isEmpty) {
      return _LayoutBox(width: 0, height: fs, baseline: fs * _baselineFraction);
    }

    final childBoxes = <_LayoutBox>[];
    for (final child in node.children) {
      childBoxes.add(_layout(child, fs, color));
    }

    // Compute max ascent and descent across all children.
    double maxAscent = 0;
    double maxDescent = 0;
    for (final box in childBoxes) {
      if (box.baseline > maxAscent) maxAscent = box.baseline;
      final descent = box.height - box.baseline;
      if (descent > maxDescent) maxDescent = descent;
    }

    final totalHeight = maxAscent + maxDescent;

    // Place children left-to-right, aligned on the shared baseline.
    double totalWidth = 0;
    for (int i = 0; i < childBoxes.length; i++) {
      final box = childBoxes[i];
      final dx = totalWidth;
      final dy = maxAscent - box.baseline;

      _offsetCommands(box.commandStart, box.commandEnd, dx, dy);

      totalWidth += box.width;
      // TeX-aware inter-atom spacing: operators include their own
      // padding (via _layoutSymbol), so we only add a minimal kern
      // between non-operator siblings.
      if (i < childBoxes.length - 1) {
        final child = node.children[i];
        final next = node.children[i + 1];
        final childIsOp =
            child is LatexSymbol &&
            (_isBinaryOperator(child.value) ||
                _isRelationalOperator(child.value));
        final nextIsOp =
            next is LatexSymbol &&
            (_isBinaryOperator(next.value) ||
                _isRelationalOperator(next.value));

        // K: Detect unary minus — a binary operator at position 0 or
        // immediately after another operator is unary (prefix), so we
        // skip its left spacing.
        if (nextIsOp &&
            next.value == '-' &&
            (i == 0 || childIsOp)) {
        } else if (!childIsOp && !nextIsOp) {
          totalWidth += fs * _atomSpacing;
        }
      }
    }

    return _LayoutBox(
      width: totalWidth,
      height: totalHeight,
      baseline: maxAscent,
      commandStart: childBoxes.first.commandStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutFraction(LatexFraction node, double fs, Color color) {
    final numBox = _layout(node.numerator, fs * _scriptScale, color);
    final denBox = _layout(node.denominator, fs * _scriptScale, color);

    final padding = fs * _fractionPadding;
    final barThickness = fs * _fractionBarThickness;
    final gap = fs * _fractionGap;

    final contentWidth =
        (numBox.width > denBox.width ? numBox.width : denBox.width) +
        padding * 2;
    final totalHeight =
        numBox.height + gap + barThickness + gap + denBox.height;

    // The fraction bar should sit on the math axis, not just the geometric
    // midpoint.  The math axis is _mathAxisOffset above the visual baseline.
    final barTopY = numBox.height + gap;
    final barMidY = barTopY + barThickness / 2;

    // Align baseline to math axis: bar center + axis offset from baseline.
    final baseline = barMidY + fs * _mathAxisOffset * 0.15;

    // Position numerator centered above bar.
    final numX = (contentWidth - numBox.width) / 2;
    _offsetCommands(numBox.commandStart, numBox.commandEnd, numX, 0);

    // Draw fraction bar (vinculum) — only if showBar is true.
    if (node.showBar) {
      _commands.add(
        LineDrawCommand(
          x1: 0,
          y1: barMidY,
          x2: contentWidth,
          y2: barMidY,
          thickness: barThickness,
          color: color,
        ),
      );
    }

    // Position denominator centered below bar.
    final denX = (contentWidth - denBox.width) / 2;
    final denY = barTopY + barThickness + gap;
    _offsetCommands(denBox.commandStart, denBox.commandEnd, denX, denY);

    return _LayoutBox(
      width: contentWidth,
      height: totalHeight,
      baseline: baseline,
      commandStart: numBox.commandStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutSuperscript(LatexSuperscript node, double fs, Color color) {
    final baseBox = _layout(node.base, fs, color);

    // Italic correction: if the base is italic, shift superscript right by a
    // small kern so it clears the slanted stroke (TeX: italcorr).
    final italicCorrection =
        (node.base is LatexSymbol && (node.base as LatexSymbol).italic)
            ? fs * 0.10
            : 0.0;

    // Cramped style: when superscript is itself a superscript (nested),
    // use a slightly smaller scale to avoid oversized towers.
    final isNested =
        node.exponent is LatexSuperscript ||
        node.exponent is LatexSubSuperscript;
    final supScale = isNested ? _scriptScale * 0.85 : _scriptScale;
    final supBox = _layout(node.exponent, fs * supScale, color);

    // Superscript sits above the base top edge.
    final supShift = fs * _superscriptShift;
    final supY = baseBox.baseline - supShift - supBox.height;

    _offsetCommands(
      supBox.commandStart,
      supBox.commandEnd,
      baseBox.width + italicCorrection,
      supY,
    );

    final supTop = -supY > 0 ? -supY : 0.0;
    final ascent = supTop > baseBox.baseline ? supTop : baseBox.baseline;
    final baseDescent = baseBox.height - baseBox.baseline;
    final totalHeight = ascent + baseDescent;

    return _LayoutBox(
      width: baseBox.width + italicCorrection + supBox.width,
      height: totalHeight > baseBox.height ? totalHeight : baseBox.height,
      baseline: ascent,
      commandStart: baseBox.commandStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutSubscript(LatexSubscript node, double fs, Color color) {
    final baseBox = _layout(node.base, fs, color);
    final subBox = _layout(node.subscript, fs * _scriptScale, color);

    // E: Italic correction — TeX shifts subscripts left so they tuck under
    // the italic slant rather than sticking out to the right.
    final italicCorrection =
        (node.base is LatexSymbol && (node.base as LatexSymbol).italic)
            ? -fs * 0.06
            : 0.0;

    final subY = baseBox.baseline - subBox.baseline + fs * _subscriptShift;
    _offsetCommands(
      subBox.commandStart,
      subBox.commandEnd,
      baseBox.width + italicCorrection,
      subY,
    );

    final subBottom = subY + subBox.height;
    final totalHeight = subBottom > baseBox.height ? subBottom : baseBox.height;

    return _LayoutBox(
      width: baseBox.width + subBox.width + italicCorrection,
      height: totalHeight,
      baseline: baseBox.baseline,
      commandStart: baseBox.commandStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutSubSuperscript(
    LatexSubSuperscript node,
    double fs,
    Color color,
  ) {
    final baseBox = _layout(node.base, fs, color);
    final supBox = _layout(node.superscript, fs * _scriptScale, color);
    final subBox = _layout(node.subscript, fs * _scriptScale, color);

    // Italic correction for the base glyph.
    final italicCorrection =
        (node.base is LatexSymbol && (node.base as LatexSymbol).italic)
            ? fs * 0.10
            : 0.0;

    final supShift = fs * _superscriptShift;
    final supY = baseBox.baseline - supShift - supBox.height;
    _offsetCommands(
      supBox.commandStart,
      supBox.commandEnd,
      baseBox.width + italicCorrection,
      supY,
    );

    final subY = baseBox.baseline - subBox.baseline + fs * _subscriptShift;
    _offsetCommands(
      subBox.commandStart,
      subBox.commandEnd,
      baseBox.width,
      subY,
    );

    final scriptWidth =
        (supBox.width + italicCorrection) > subBox.width
            ? (supBox.width + italicCorrection)
            : subBox.width;

    final supTop = supY < 0 ? -supY : 0.0;
    final ascent = supTop > baseBox.baseline ? supTop : baseBox.baseline;

    final baseDescent = baseBox.height - baseBox.baseline;
    final subBottom = subY + subBox.height - baseBox.baseline;
    final descent = subBottom > baseDescent ? subBottom : baseDescent;

    final totalHeight = ascent + descent;

    return _LayoutBox(
      width: baseBox.width + scriptWidth,
      height: totalHeight > baseBox.height ? totalHeight : baseBox.height,
      baseline: ascent,
      commandStart: baseBox.commandStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutSqrt(LatexSqrt node, double fs, Color color) {
    final cmdStart = _commands.length;
    final radBox = _layout(node.radicand, fs, color);
    final overhang = fs * _radicalOverhang;
    final barThickness = fs * _fractionBarThickness;

    // Proportions tuned to match TeX's Computer Modern radical glyph:
    //   symbolWidth : the horizontal span of the √ symbol itself
    //   tailWidth   : the small horizontal serif at the left
    //   veeWidth    : the diagonal run to the bottom of the V
    final symbolWidth = fs * 0.52;
    final tailWidth = symbolWidth * 0.22;
    final veeWidth = symbolWidth * 0.28;
    final strokeWidth = barThickness * 1.6;

    final symHeight = radBox.height + overhang + barThickness;

    // Radical shape — five control points (rendered as polyline):
    //   P0 (tail start)  — left end of small horizontal serif
    //   P1 (tail end)    — right end of serif, start of downstroke
    //   P2 (V bottom)    — lowest point of the check mark
    //   P3 (bar join)    — where the upstroke meets the vinculum
    //
    //   The serif sits at ~62 % height so it is clearly visible but leaves
    //   enough room for the V sweep. The downstroke angle and upstroke angle
    //   intentionally differ (TeX's radical is NOT symmetric).
    // Radical shape — classic TeX Computer Modern √ as clean polyline.
    // NOT smooth — the radical must have crisp angles at the kink and vee:
    //   P0: small horizontal tail (serif)
    //   P1: kink where serif meets downstroke
    //   P2: bottom of the V (lowest point)
    //   P3: top-right where upstroke meets vinculum
    //
    // The upstroke MUST arrive exactly at (symbolWidth, 0) to align
    // perfectly with the vinculum bar.
    _commands.add(
      PathDrawCommand(
        points: [
          Offset(0, symHeight * 0.62), // P0: tail start
          Offset(tailWidth, symHeight * 0.58), // P1: kink
          Offset(tailWidth + veeWidth, symHeight), // P2: vee bottom
          Offset(symbolWidth, 0), // P3: top (vinculum join)
        ],
        strokeWidth: strokeWidth,
        color: color,
        smooth: false, // crisp corners, NOT curved
      ),
    );

    // Vinculum (horizontal bar over radicand) — starts exactly at the
    // radical's top-right corner for a seamless join.
    _commands.add(
      LineDrawCommand(
        x1: symbolWidth - strokeWidth * 0.5,
        y1: barThickness / 2,
        x2: symbolWidth + radBox.width + overhang,
        y2: barThickness / 2,
        thickness: barThickness,
        color: color,
      ),
    );

    // Shift radicand to sit under the vinculum with the correct clearance.
    _offsetCommands(
      radBox.commandStart,
      radBox.commandEnd,
      symbolWidth,
      barThickness + overhang,
    );

    final totalWidth = symbolWidth + radBox.width + overhang;

    // Optional degree label (e.g. ³√).
    if (node.degree != null) {
      final degBox = _layout(node.degree!, fs * _scriptScriptScale, color);
      _offsetCommands(
        degBox.commandStart,
        degBox.commandEnd,
        tailWidth * 0.5,
        symHeight * 0.57 - degBox.height - fs * 0.05,
      );
    }

    return _LayoutBox(
      width: totalWidth,
      height: symHeight,
      baseline: symHeight * _baselineFraction,
      commandStart: cmdStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutBigOperator(LatexBigOperator node, double fs, Color color) {
    final cmdStart = _commands.length;
    const opScale = 1.6;
    final opSize = fs * opScale;

    final isIntegral =
        node.operator == '∫' ||
        node.operator == '∬' ||
        node.operator == '∭' ||
        node.operator == '∮';

    final isSummation = node.operator == '∑';

    double opWidth;

    if (isIntegral) {
      opWidth = opSize * 0.38;
      final strokeW = fs * _fractionBarThickness * 2.0;
      final h = opSize;
      final w = opWidth;

      final count = switch (node.operator) {
        '∬' => 2,
        '∭' => 3,
        _ => 1,
      };
      final spacing = count > 1 ? w * 0.55 : 0.0;

      for (int n = 0; n < count; n++) {
        final dx = n * spacing;
        // Integral ∫ — TeX Computer Modern style S-curve:
        //   Top serif curls right, body slants slightly right going down,
        //   bottom serif curls left. Classic mathematical typesetting.
        _commands.add(
          PathDrawCommand(
            points: [
              // Top serif (curls right)
              Offset(dx + w * 0.72, h * 0.01), // serif tip (right)
              Offset(dx + w * 0.60, 0), // serif peak
              Offset(dx + w * 0.48, h * 0.03), // serif join
              // Upper body (slight rightward lean)
              Offset(dx + w * 0.44, h * 0.12),
              Offset(dx + w * 0.42, h * 0.30),
              // Center body (straight vertical section)
              Offset(dx + w * 0.44, h * 0.45),
              Offset(dx + w * 0.50, h * 0.55),
              Offset(dx + w * 0.56, h * 0.65),
              // Lower body (slight leftward lean)
              Offset(dx + w * 0.58, h * 0.80),
              Offset(dx + w * 0.56, h * 0.90),
              // Bottom serif (curls left)
              Offset(dx + w * 0.52, h * 0.97), // serif join
              Offset(dx + w * 0.40, h), // serif peak
              Offset(dx + w * 0.28, h * 0.98), // serif tip (left)
            ],
            strokeWidth: strokeW,
            color: color,
            smooth: true,
          ),
        );
      }

      if (node.operator == '∮') {
        final cx = w * 0.50;
        final cy = h * 0.50;
        final r = fs * 0.08;
        // D: High-fidelity 16-segment smooth circle for contour integral.
        final circlePoints = <Offset>[];
        for (int i = 0; i <= 16; i++) {
          final angle = i * math.pi * 2.0 / 16;
          circlePoints.add(Offset(cx + r * _cos(angle), cy + r * _sin(angle)));
        }
        // (duplicate removed)
        _commands.add(
          PathDrawCommand(
            points: circlePoints,
            strokeWidth: strokeW * 0.7,
            color: color,
            closed: true,
            smooth: true,
          ),
        );
      }

      if (count > 1) opWidth = w + spacing * (count - 1);
    } else if (isSummation) {
      // 🚀 PERFORMANCE & ACCURACY: Draw ∑ via exact crisp Path geometry, not a font glyph.
      // This completely eliminates font side-bearing metric issues, ensuring the
      // visual vertexes of the sigma are perfectly horizontally centered so lower
      // bounds like 'n=0' align correctly.
      final h = opSize * 0.85; // A bit shorter than full opSize
      opWidth = opSize * 0.75;
      final strokeW = fs * _fractionBarThickness * 1.5;
      _commands.add(
        PathDrawCommand(
          points: [
            Offset(opWidth * 0.90, 0), // Top right serif
            Offset(opWidth * 0.10, 0), // Top left corner
            Offset(opWidth * 0.55, h * 0.5), // Middle peak (center-ish)
            Offset(opWidth * 0.10, h), // Bottom left corner
            Offset(opWidth * 0.90, h), // Bottom right serif
          ],
          strokeWidth: strokeW,
          color: color,
          smooth: false, // Sigma has crisp sharp angles
        ),
      );
      // Small visual vertical offset to center the Sigma within opSize bounds
      _offsetCommands(
        _commands.length - 1,
        _commands.length,
        0,
        (opSize - h) / 2,
      );
    } else {
      opWidth = _measureTextWidth(node.operator, opSize);
      _commands.add(
        GlyphDrawCommand(
          text: node.operator,
          x: 0,
          y: 0,
          fontSize: opSize,
          color: color,
          fontFamily: _mathFontFamily,
        ),
      );
    }

    // Simple case: no limits.
    if (node.lower == null && node.upper == null) {
      return _LayoutBox(
        width: opWidth + fs * _thickSpace,
        height: opSize,
        baseline: opSize * _baselineFraction,
        commandStart: cmdStart,
        commandEnd: _commands.length,
      );
    }

    final isInlineStyle = isIntegral;

    if (isInlineStyle) {
      // Inline style (∫, ∬ …): limits as sub/superscript positioned
      // at the TOP-RIGHT and BOTTOM-RIGHT of the integral, ensuring they
      // sit visually distinct from the S-curve.
      final limX = opWidth + fs * _bigOpLimitKern;
      double totalWidth = limX;

      // Ensure superscript stays completely clearly spaced above the integral
      // visual top body, so it doesn't get 'swallowed' inside.
      final topY = 0.0;
      // Lower limit sits significantly lower so its own bottom aligns roughly
      // with the integral's bottom.
      final botY = opSize;

      double minY = 0.0;
      double maxY = opSize;

      if (node.upper != null) {
        final supBox = _layout(node.upper!, fs * _scriptScale, color);
        // Sup runs from topY - supBox.height, ensuring it's mostly ABOVE the
        // integral's visual body.
        final supY = topY - supBox.height * 0.60;
        _offsetCommands(supBox.commandStart, supBox.commandEnd, limX, supY);
        totalWidth = limX + supBox.width;
        if (supY < minY) minY = supY;
      }

      if (node.lower != null) {
        final subBox = _layout(node.lower!, fs * _scriptScale, color);
        // Sub top sits near the lower part of the integral, pushing it further down.
        final subY = botY - subBox.height * 0.40;
        _offsetCommands(subBox.commandStart, subBox.commandEnd, limX, subY);
        final scriptW = node.upper != null ? (totalWidth - limX) : subBox.width;
        totalWidth = limX + (scriptW > subBox.width ? scriptW : subBox.width);
        if (subY + subBox.height > maxY) maxY = subY + subBox.height;
      }

      // If upper limit extended above the integral, shift everything down
      if (minY < 0) {
        _offsetCommands(cmdStart, _commands.length, 0, -minY);
        maxY -= minY;
      }

      final totalHeight = maxY;
      final baseline = (minY < 0 ? -minY : 0) + opSize * _baselineFraction;

      return _LayoutBox(
        width: totalWidth + fs * _thickSpace,
        height: totalHeight,
        baseline: baseline,
        commandStart: cmdStart,
        commandEnd: _commands.length,
      );
    }

    // Display style (∑, ∏ …): limits centered above/below.
    double maxWidth = opWidth;
    // TeX BigOpSpacing: tight gap between operator and limits.
    final gap = fs * 0.06;

    _LayoutBox? upperBox;
    _LayoutBox? lowerBox;

    if (node.upper != null) {
      upperBox = _layout(node.upper!, fs * _scriptScale, color);
      if (upperBox.width > maxWidth) maxWidth = upperBox.width;
    }

    if (node.lower != null) {
      lowerBox = _layout(node.lower!, fs * _scriptScale, color);
      if (lowerBox.width > maxWidth) maxWidth = lowerBox.width;
    }

    // 🚀 CRITICAL SPACING FIX:
    // A LayoutBox for text (like '∞') has internal whitespace (descent space)
    // BELOW its visible baseline. If we just add gap to height, it floats too far up.
    // Instead, we reserve space relative to the VISIBLE gap.
    final upperDescent =
        upperBox != null ? (upperBox.height - upperBox.baseline) : 0.0;

    // total physical Y-space reserved for upper limit box:
    final upperHeight =
        upperBox != null ? (upperBox.height - upperDescent + gap) : 0.0;
    final lowerHeight = lowerBox != null ? (lowerBox.height + gap) : 0.0;

    final totalHeight = upperHeight + opSize + lowerHeight;
    final baseline = upperHeight + opSize * _baselineFraction;

    // Center operator horizontally
    final opX = (maxWidth - opWidth) / 2;
    _offsetCommands(cmdStart, cmdStart + 1, opX, upperHeight);

    if (upperBox != null) {
      final ux = (maxWidth - upperBox.width) / 2;
      // Position upper limit physically. Because upperHeight excludes the descent,
      // we offset the upper box such that its BASELINE aligns directly with upperHeight - gap.
      // E.g. gap = 5, upperBox has 20 height, 15 baseline.
      // upperHeight = 15 + 5 = 20.
      // uy = upperHeight - gap - upperBox.baseline => 20 - 5 - 15 = 0.
      // This means the visual bottom of ∞ touches exactly 'gap' pixels above the Sigma.
      final uy = upperHeight - gap - upperBox.baseline;
      _offsetCommands(upperBox.commandStart, upperBox.commandEnd, ux, uy);
    }

    if (lowerBox != null) {
      final lx = (maxWidth - lowerBox.width) / 2;
      // Lower limit sits gap distance below the operator bottom edge.
      final ly = upperHeight + opSize + gap;
      _offsetCommands(lowerBox.commandStart, lowerBox.commandEnd, lx, ly);
    }

    return _LayoutBox(
      width: maxWidth + fs * _thickSpace,
      height: totalHeight,
      baseline: baseline,
      commandStart: cmdStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutMatrix(LatexMatrix node, double fs, Color color) {
    if (node.rows.isEmpty) {
      return _LayoutBox(width: 0, height: fs, baseline: fs * _baselineFraction);
    }

    final cmdStart = _commands.length;
    final cellFs = fs * _scriptScale;
    final cellGap = fs * 0.32;
    final rowGap = fs * 0.22;
    final delimPadding = fs * 0.15;

    final cellBoxes = <List<_LayoutBox>>[];
    for (final row in node.rows) {
      final rowBoxes = <_LayoutBox>[];
      for (final cell in row) {
        rowBoxes.add(_layout(cell, cellFs, color));
      }
      cellBoxes.add(rowBoxes);
    }

    int maxCols = 0;
    for (final row in cellBoxes) {
      if (row.length > maxCols) maxCols = row.length;
    }

    final colWidths = List.filled(maxCols, 0.0);
    for (final row in cellBoxes) {
      for (int c = 0; c < row.length; c++) {
        if (row[c].width > colWidths[c]) colWidths[c] = row[c].width;
      }
    }

    final rowHeights =
        cellBoxes.map((row) {
          double maxH = cellFs;
          for (final box in row) {
            if (box.height > maxH) maxH = box.height;
          }
          return maxH;
        }).toList();

    final hasDelims = node.style != MatrixStyle.plain;
    final delimW = hasDelims ? fs * 0.25 : 0.0;
    final contentOffsetX = delimW + delimPadding;

    double y = 0;
    for (int r = 0; r < cellBoxes.length; r++) {
      double x = 0;
      for (int c = 0; c < cellBoxes[r].length; c++) {
        final box = cellBoxes[r][c];
        final dx = contentOffsetX + x + (colWidths[c] - box.width) / 2;
        final dy = y + (rowHeights[r] - box.height) / 2;
        _offsetCommands(box.commandStart, box.commandEnd, dx, dy);
        x += colWidths[c] + cellGap;
      }
      y += rowHeights[r] + rowGap;
    }

    final contentWidth =
        colWidths.fold(0.0, (s, w) => s + w) + cellGap * (maxCols - 1);
    final totalHeight =
        rowHeights.fold(0.0, (s, h) => s + h) + rowGap * (cellBoxes.length - 1);
    final totalWidth = contentWidth + (contentOffsetX + delimW + delimPadding);

    if (hasDelims) {
      final String openDelim;
      final String closeDelim;
      switch (node.style) {
        case MatrixStyle.parenthesized:
          openDelim = '(';
          closeDelim = ')';
        case MatrixStyle.bracketed:
          openDelim = '[';
          closeDelim = ']';
        case MatrixStyle.braced:
          openDelim = '{';
          closeDelim = '}';
        case MatrixStyle.verticalBar:
          openDelim = '|';
          closeDelim = '|';
        case MatrixStyle.doubleVerticalBar:
          openDelim = '‖';
          closeDelim = '‖';
        case MatrixStyle.plain:
          openDelim = '';
          closeDelim = '';
      }

      if (openDelim.isNotEmpty) {
        _commands.add(
          GlyphDrawCommand(
            text: openDelim,
            x: 0,
            y: 0,
            fontSize: totalHeight,
            color: color,
            fontFamily: _mathFontFamily,
          ),
        );
      }
      if (closeDelim.isNotEmpty) {
        _commands.add(
          GlyphDrawCommand(
            text: closeDelim,
            x: totalWidth - delimW,
            y: 0,
            fontSize: totalHeight,
            color: color,
            fontFamily: _mathFontFamily,
          ),
        );
      }
    }

    return _LayoutBox(
      width: totalWidth,
      height: totalHeight,
      baseline: totalHeight / 2,
      commandStart: cmdStart,
      commandEnd: _commands.length,
    );
  }

  /// Draw a tall delimiter as a B\u00e9zier path instead of a scaled glyph.
  ///
  /// For tall expressions, scaling a glyph character produces thick, distorted
  /// strokes. This method draws each delimiter type (parens, brackets, braces)
  /// as proportional B\u00e9zier curves that look correct at any height.
  void _addPathDelimiter(
    String delim,
    double x,
    double y,
    double width,
    double height,
    double fontSize,
    Color color,
  ) {
    final strokeW = fontSize * _fractionBarThickness * 1.5;
    final h = height;
    final w = width;

    switch (delim) {
      case '(':
        // Left parenthesis: smooth arc from top to bottom.
        _commands.add(
          PathDrawCommand(
            points: [
              Offset(x + w * 0.85, y),
              Offset(x + w * 0.55, y + h * 0.15),
              Offset(x + w * 0.30, y + h * 0.35),
              Offset(x + w * 0.25, y + h * 0.50),
              Offset(x + w * 0.30, y + h * 0.65),
              Offset(x + w * 0.55, y + h * 0.85),
              Offset(x + w * 0.85, y + h),
            ],
            strokeWidth: strokeW,
            color: color,
            smooth: true,
          ),
        );
      case ')':
        // Right parenthesis: mirror of left.
        _commands.add(
          PathDrawCommand(
            points: [
              Offset(x + w * 0.15, y),
              Offset(x + w * 0.45, y + h * 0.15),
              Offset(x + w * 0.70, y + h * 0.35),
              Offset(x + w * 0.75, y + h * 0.50),
              Offset(x + w * 0.70, y + h * 0.65),
              Offset(x + w * 0.45, y + h * 0.85),
              Offset(x + w * 0.15, y + h),
            ],
            strokeWidth: strokeW,
            color: color,
            smooth: true,
          ),
        );
      case '[':
        // Left bracket: three straight lines (top, vertical, bottom).
        _commands.add(
          PathDrawCommand(
            points: [
              Offset(x + w * 0.75, y),
              Offset(x + w * 0.30, y),
              Offset(x + w * 0.30, y + h),
              Offset(x + w * 0.75, y + h),
            ],
            strokeWidth: strokeW,
            color: color,
          ),
        );
      case ']':
        // Right bracket: mirror.
        _commands.add(
          PathDrawCommand(
            points: [
              Offset(x + w * 0.25, y),
              Offset(x + w * 0.70, y),
              Offset(x + w * 0.70, y + h),
              Offset(x + w * 0.25, y + h),
            ],
            strokeWidth: strokeW,
            color: color,
          ),
        );
      case '{':
        // Left brace: smooth S-shape with center point.
        _commands.add(
          PathDrawCommand(
            points: [
              Offset(x + w * 0.80, y),
              Offset(x + w * 0.55, y + h * 0.05),
              Offset(x + w * 0.50, y + h * 0.20),
              Offset(x + w * 0.50, y + h * 0.40),
              Offset(x + w * 0.25, y + h * 0.50), // center cusp
              Offset(x + w * 0.50, y + h * 0.60),
              Offset(x + w * 0.50, y + h * 0.80),
              Offset(x + w * 0.55, y + h * 0.95),
              Offset(x + w * 0.80, y + h),
            ],
            strokeWidth: strokeW,
            color: color,
            smooth: true,
          ),
        );
      case '}':
        // Right brace: mirror of left.
        _commands.add(
          PathDrawCommand(
            points: [
              Offset(x + w * 0.20, y),
              Offset(x + w * 0.45, y + h * 0.05),
              Offset(x + w * 0.50, y + h * 0.20),
              Offset(x + w * 0.50, y + h * 0.40),
              Offset(x + w * 0.75, y + h * 0.50), // center cusp
              Offset(x + w * 0.50, y + h * 0.60),
              Offset(x + w * 0.50, y + h * 0.80),
              Offset(x + w * 0.45, y + h * 0.95),
              Offset(x + w * 0.20, y + h),
            ],
            strokeWidth: strokeW,
            color: color,
            smooth: true,
          ),
        );
      case '|':
        // Vertical bar: single line.
        _commands.add(
          PathDrawCommand(
            points: [Offset(x + w * 0.50, y), Offset(x + w * 0.50, y + h)],
            strokeWidth: strokeW,
            color: color,
          ),
        );
      case '‖':
        // Double vertical bar.
        _commands.add(
          PathDrawCommand(
            points: [Offset(x + w * 0.35, y), Offset(x + w * 0.35, y + h)],
            strokeWidth: strokeW,
            color: color,
          ),
        );
        _commands.add(
          PathDrawCommand(
            points: [Offset(x + w * 0.65, y), Offset(x + w * 0.65, y + h)],
            strokeWidth: strokeW,
            color: color,
          ),
        );
      default:
        // Unsupported delimiter — fall back to glyph.
        _commands.add(
          GlyphDrawCommand(
            text: delim,
            x: x,
            y: y,
            fontSize: height,
            color: color,
            fontFamily: _mathFontFamily,
          ),
        );
    }
  }

  _LayoutBox _layoutDelimited(LatexDelimited node, double fs, Color color) {
    final bodyBox = _layout(node.body, fs, color);

    // Scale delimiters to at least 1 em tall and add 10 % vertical clearance.
    final minDelimHeight = fs;
    final rawHeight = bodyBox.height * 1.10;
    final delimHeight = rawHeight > minDelimHeight ? rawHeight : minDelimHeight;
    final delimWidth = fs * 0.30;

    // Vertical offset so delimiters are centered around the body.
    final vertOffset = (delimHeight - bodyBox.height) / 2;

    // C: For tall delimiters (> 1.5× font), draw with Bézier paths to
    //    avoid thick/distorted glyph scaling.
    final usePathDelim = delimHeight > fs * 1.5;

    if (node.open.isNotEmpty) {
      if (usePathDelim) {
        _addPathDelimiter(
          node.open,
          0,
          vertOffset,
          delimWidth,
          delimHeight,
          fs,
          color,
        );
      } else {
        _commands.add(
          GlyphDrawCommand(
            text: node.open,
            x: 0,
            y: vertOffset,
            fontSize: delimHeight,
            color: color,
            fontFamily: _mathFontFamily,
          ),
        );
      }
    }

    _offsetCommands(
      bodyBox.commandStart,
      bodyBox.commandEnd,
      delimWidth,
      vertOffset,
    );

    if (node.close.isNotEmpty) {
      if (usePathDelim) {
        _addPathDelimiter(
          node.close,
          delimWidth + bodyBox.width,
          vertOffset,
          delimWidth,
          delimHeight,
          fs,
          color,
        );
      } else {
        _commands.add(
          GlyphDrawCommand(
            text: node.close,
            x: delimWidth + bodyBox.width,
            y: vertOffset,
            fontSize: delimHeight,
            color: color,
            fontFamily: _mathFontFamily,
          ),
        );
      }
    }

    final openWidth = node.open.isNotEmpty ? delimWidth : 0.0;
    final closeWidth = node.close.isNotEmpty ? delimWidth : 0.0;

    return _LayoutBox(
      width: openWidth + bodyBox.width + closeWidth,
      height: delimHeight,
      // Baseline rises by the same vertOffset applied to the body.
      baseline: bodyBox.baseline + vertOffset,
      commandStart:
          _commands.length -
          (bodyBox.commandEnd - bodyBox.commandStart) -
          (node.open.isNotEmpty ? 1 : 0) -
          (node.close.isNotEmpty ? 1 : 0),
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutText(LatexText node, double fs, Color color) {
    // I: Use null fontFamily so \text{} renders in the system sans-serif
    // font, matching TeX convention where \text uses the document font.
    final width = _measureTextWidth(node.text, fs, italic: false);

    _commands.add(
      GlyphDrawCommand(
        text: node.text,
        x: 0,
        y: 0,
        fontSize: fs,
        color: color,
        fontFamily: null, // I: system font, not math font
        italic: false,
      ),
    );

    // G: Add trailing thin space after operator names (sin, cos, log, etc.)
    // so that e.g. "\sin x" renders as "sin x" not "sinx".
    final trailingSpace = fs * _thinSpace;

    return _LayoutBox(
      width: width + trailingSpace,
      height: fs,
      baseline: fs * _baselineFraction,
      commandStart: _commands.length - 1,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutSpace(LatexSpace node, double fs) {
    final width = fs * node.emWidth;
    return _LayoutBox(
      width: width,
      height: fs,
      baseline: fs * _baselineFraction,
    );
  }

  _LayoutBox _layoutLimit(LatexLimit node, double fs, Color color) {
    final cmdStart = _commands.length;
    final limWidth = _measureTextWidth('lim', fs, italic: false);

    _commands.add(
      GlyphDrawCommand(
        text: 'lim',
        x: 0,
        y: 0,
        fontSize: fs,
        color: color,
        fontFamily: _mathFontFamily,
        italic: false,
      ),
    );

    if (node.subscript == null) {
      return _LayoutBox(
        width: limWidth + fs * _thickSpace,
        height: fs,
        baseline: fs * _baselineFraction,
        commandStart: cmdStart,
        commandEnd: _commands.length,
      );
    }

    final subBox = _layout(node.subscript!, fs * _scriptScale, color);
    final gap = fs * 0.08;
    final maxWidth = limWidth > subBox.width ? limWidth : subBox.width;

    final limX = (maxWidth - limWidth) / 2;
    _offsetCommands(cmdStart, cmdStart + 1, limX, 0);

    final subX = (maxWidth - subBox.width) / 2;
    final subY = fs + gap;
    _offsetCommands(subBox.commandStart, subBox.commandEnd, subX, subY);

    final totalHeight = fs + gap + subBox.height;

    return _LayoutBox(
      width: maxWidth + fs * _thickSpace,
      height: totalHeight,
      baseline: fs * _baselineFraction,
      commandStart: cmdStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutAccent(LatexAccent node, double fs, Color color) {
    final baseBox = _layout(node.base, fs, color);

    // Special handling for \underline — draw line below base.
    if (node.accentType == 'underline') {
      final lineGap = fs * 0.06;
      final lineThickness = fs * _fractionBarThickness;
      final lineY = baseBox.height + lineGap;

      _commands.add(
        LineDrawCommand(
          x1: 0,
          y1: lineY,
          x2: baseBox.width,
          y2: lineY,
          thickness: lineThickness,
          color: color,
        ),
      );

      return _LayoutBox(
        width: baseBox.width,
        height: lineY + lineThickness,
        baseline: baseBox.baseline,
        commandStart: baseBox.commandStart,
        commandEnd: _commands.length,
      );
    }

    final accentChar = _accentSymbol(node.accentType);
    final accentFs = fs * 0.80;
    final accentWidth = _measureTextWidth(accentChar, accentFs);
    final accentHeight = fs * 0.26;

    // Center accent above base, with italic correction if applicable.
    final italicShift =
        (node.base is LatexSymbol && (node.base as LatexSymbol).italic)
            ? fs * 0.05
            : 0.0;
    final accentX = ((baseBox.width - accentWidth) / 2 + italicShift).clamp(
      0.0,
      double.infinity,
    );

    _commands.add(
      GlyphDrawCommand(
        text: accentChar,
        x: accentX,
        y: -accentHeight,
        fontSize: accentFs,
        color: color,
        fontFamily: _mathFontFamily,
      ),
    );

    _offsetCommands(baseBox.commandStart, baseBox.commandEnd, 0, accentHeight);

    final totalWidth =
        baseBox.width > accentWidth ? baseBox.width : accentWidth;

    return _LayoutBox(
      width: totalWidth,
      height: baseBox.height + accentHeight,
      baseline: baseBox.baseline + accentHeight,
      commandStart: baseBox.commandStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutError(LatexErrorNode node, double fs, Color color) {
    const errorColor = Color(0xFFFF4444);
    final text = node.rawText.isNotEmpty ? node.rawText : '?';
    final width = _measureTextWidth(text, fs, italic: true);

    _commands.add(
      GlyphDrawCommand(
        text: text,
        x: 0,
        y: 0,
        fontSize: fs,
        color: errorColor,
        italic: true,
      ),
    );

    // H: Draw a red underline to visually distinguish parse errors.
    final barY = fs * 0.95;
    _commands.add(
      LineDrawCommand(
        x1: 0,
        y1: barY,
        x2: width,
        y2: barY,
        thickness: fs * 0.04,
        color: errorColor,
      ),
    );

    return _LayoutBox(
      width: width,
      height: fs,
      baseline: fs * _baselineFraction,
      commandStart: _commands.length - 2,
      commandEnd: _commands.length,
    );
  }

  // ---------------------------------------------------------------------------
  // New Construct Layouts
  // ---------------------------------------------------------------------------

  /// Color name → ARGB color mapping.
  static Color _parseColorName(String name) {
    return switch (name.toLowerCase()) {
      'red' => const Color(0xFFFF0000),
      'blue' => const Color(0xFF0000FF),
      'green' => const Color(0xFF00AA00),
      'orange' => const Color(0xFFFF8800),
      'purple' => const Color(0xFF8800FF),
      'cyan' => const Color(0xFF00CCCC),
      'magenta' => const Color(0xFFFF00FF),
      'yellow' => const Color(0xFFCCCC00),
      'white' => const Color(0xFFFFFFFF),
      'black' => const Color(0xFF000000),
      'gray' || 'grey' => const Color(0xFF888888),
      'brown' => const Color(0xFF884400),
      'pink' => const Color(0xFFFF88AA),
      'lime' => const Color(0xFF88FF00),
      'teal' => const Color(0xFF008888),
      'violet' => const Color(0xFF8800CC),
      _ =>
        name.startsWith('#') && name.length == 7
            ? Color(int.parse('FF${name.substring(1)}', radix: 16))
            : const Color(0xFFFF4444), // fallback red for unknown
    };
  }

  _LayoutBox _layoutColored(LatexColored node, double fs, Color color) {
    final resolvedColor = _parseColorName(node.colorName);
    return _layout(node.body, fs, resolvedColor);
  }

  _LayoutBox _layoutBoxed(LatexBoxed node, double fs, Color color) {
    final bodyBox = _layout(node.body, fs, color);
    final padding = fs * 0.12;
    final borderThickness = fs * _fractionBarThickness;
    final cmdStart = bodyBox.commandStart;

    // Offset body for padding.
    _offsetCommands(bodyBox.commandStart, bodyBox.commandEnd, padding, padding);

    final totalWidth = bodyBox.width + padding * 2;
    final totalHeight = bodyBox.height + padding * 2;

    // Draw rectangle border.
    // Top
    _commands.add(
      LineDrawCommand(
        x1: 0,
        y1: 0,
        x2: totalWidth,
        y2: 0,
        thickness: borderThickness,
        color: color,
      ),
    );
    // Bottom
    _commands.add(
      LineDrawCommand(
        x1: 0,
        y1: totalHeight,
        x2: totalWidth,
        y2: totalHeight,
        thickness: borderThickness,
        color: color,
      ),
    );
    // Left
    _commands.add(
      LineDrawCommand(
        x1: 0,
        y1: 0,
        x2: 0,
        y2: totalHeight,
        thickness: borderThickness,
        color: color,
      ),
    );
    // Right
    _commands.add(
      LineDrawCommand(
        x1: totalWidth,
        y1: 0,
        x2: totalWidth,
        y2: totalHeight,
        thickness: borderThickness,
        color: color,
      ),
    );

    return _LayoutBox(
      width: totalWidth,
      height: totalHeight,
      baseline: bodyBox.baseline + padding,
      commandStart: cmdStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutUnderOver(LatexUnderOver node, double fs, Color color) {
    final bodyBox = _layout(node.body, fs, color);
    final annoBox = _layout(node.annotation, fs * _scriptScale, color);
    final gap = fs * 0.10;
    final braceHeight = node.braceStyle == 'brace' ? fs * 0.18 : 0.0;

    final maxWidth =
        bodyBox.width > annoBox.width ? bodyBox.width : annoBox.width;

    if (node.above) {
      // Annotation above: annotation → (brace) → body
      final annoX = (maxWidth - annoBox.width) / 2;
      final bodyX = (maxWidth - bodyBox.width) / 2;

      _offsetCommands(annoBox.commandStart, annoBox.commandEnd, annoX, 0);

      if (node.braceStyle == 'brace') {
        // Draw a horizontal overbrace between annotation and body
        final braceY = annoBox.height + gap;
        _commands.add(
          PathDrawCommand(
            points: [
              Offset(bodyX, braceY + braceHeight),
              Offset(bodyX, braceY),
              Offset(bodyX + bodyBox.width / 2, braceY - braceHeight * 0.3),
              Offset(bodyX + bodyBox.width, braceY),
              Offset(bodyX + bodyBox.width, braceY + braceHeight),
            ],
            strokeWidth: fs * _fractionBarThickness,
            color: color,
            smooth: true,
          ),
        );
      }

      final bodyY = annoBox.height + gap + braceHeight + gap;
      _offsetCommands(bodyBox.commandStart, bodyBox.commandEnd, bodyX, bodyY);

      final totalHeight = bodyY + bodyBox.height;
      return _LayoutBox(
        width: maxWidth,
        height: totalHeight,
        baseline: bodyY + bodyBox.baseline,
        commandStart: annoBox.commandStart,
        commandEnd: _commands.length,
      );
    } else {
      // Annotation below: body → (brace) → annotation
      final bodyX = (maxWidth - bodyBox.width) / 2;
      final annoX = (maxWidth - annoBox.width) / 2;

      _offsetCommands(bodyBox.commandStart, bodyBox.commandEnd, bodyX, 0);

      final braceY = bodyBox.height + gap;
      if (node.braceStyle == 'brace') {
        _commands.add(
          PathDrawCommand(
            points: [
              Offset(bodyX, braceY),
              Offset(bodyX, braceY + braceHeight),
              Offset(bodyX + bodyBox.width / 2, braceY + braceHeight * 1.3),
              Offset(bodyX + bodyBox.width, braceY + braceHeight),
              Offset(bodyX + bodyBox.width, braceY),
            ],
            strokeWidth: fs * _fractionBarThickness,
            color: color,
            smooth: true,
          ),
        );
      }

      final annoY = braceY + braceHeight + gap;
      _offsetCommands(annoBox.commandStart, annoBox.commandEnd, annoX, annoY);

      final totalHeight = annoY + annoBox.height;
      return _LayoutBox(
        width: maxWidth,
        height: totalHeight,
        baseline: bodyBox.baseline,
        commandStart: bodyBox.commandStart,
        commandEnd: _commands.length,
      );
    }
  }

  _LayoutBox _layoutCancel(LatexCancel node, double fs, Color color) {
    final bodyBox = _layout(node.body, fs, color);
    final strokeW = fs * _fractionBarThickness * 1.2;

    switch (node.direction) {
      case 'forward': // diagonal /
        _commands.add(
          LineDrawCommand(
            x1: 0,
            y1: bodyBox.height,
            x2: bodyBox.width,
            y2: 0,
            thickness: strokeW,
            color: const Color(0xFFFF4444),
          ),
        );
      case 'back': // diagonal \
        _commands.add(
          LineDrawCommand(
            x1: 0,
            y1: 0,
            x2: bodyBox.width,
            y2: bodyBox.height,
            thickness: strokeW,
            color: const Color(0xFFFF4444),
          ),
        );
      case 'cross': // X
        _commands.add(
          LineDrawCommand(
            x1: 0,
            y1: bodyBox.height,
            x2: bodyBox.width,
            y2: 0,
            thickness: strokeW,
            color: const Color(0xFFFF4444),
          ),
        );
        _commands.add(
          LineDrawCommand(
            x1: 0,
            y1: 0,
            x2: bodyBox.width,
            y2: bodyBox.height,
            thickness: strokeW,
            color: const Color(0xFFFF4444),
          ),
        );
    }

    return _LayoutBox(
      width: bodyBox.width,
      height: bodyBox.height,
      baseline: bodyBox.baseline,
      commandStart: bodyBox.commandStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutPhantom(LatexPhantom node, double fs, Color color) {
    // Layout the body to get dimensions, then discard its commands.
    final cmdStart = _commands.length;
    final bodyBox = _layout(node.body, fs, color);
    // Remove all commands generated by body — phantom is invisible.
    _commands.removeRange(cmdStart, _commands.length);

    return _LayoutBox(
      width: bodyBox.width,
      height: bodyBox.height,
      baseline: bodyBox.baseline,
    );
  }

  _LayoutBox _layoutCases(LatexCases node, double fs, Color color) {
    final braceWidth = fs * 0.30;
    final rowGap = fs * 0.15;
    final colGap = fs * 0.60;

    // Layout each cell.
    final cellBoxes = <List<_LayoutBox>>[];
    for (final row in node.rows) {
      final rowBoxes = <_LayoutBox>[];
      for (final cell in row) {
        rowBoxes.add(_layout(cell, fs, color));
      }
      cellBoxes.add(rowBoxes);
    }

    // Compute column widths.
    final numCols = cellBoxes.fold<int>(
      0,
      (mx, r) => r.length > mx ? r.length : mx,
    );
    final colWidths = List<double>.filled(numCols, 0);
    for (final row in cellBoxes) {
      for (var c = 0; c < row.length; c++) {
        if (row[c].width > colWidths[c]) colWidths[c] = row[c].width;
      }
    }

    // Compute row heights.
    final rowHeights = <double>[];
    for (final row in cellBoxes) {
      var maxH = fs;
      for (final cell in row) {
        if (cell.height > maxH) maxH = cell.height;
      }
      rowHeights.add(maxH);
    }

    // Total content dimensions.
    final contentWidth =
        colWidths.fold<double>(0, (s, w) => s + w) +
        (numCols > 1 ? (numCols - 1) * colGap : 0);
    final contentHeight =
        rowHeights.fold<double>(0, (s, h) => s + h) +
        (rowHeights.length > 1 ? (rowHeights.length - 1) * rowGap : 0);

    // Position cells.
    var currentY = 0.0;
    for (var r = 0; r < cellBoxes.length; r++) {
      var currentX = braceWidth;
      for (var c = 0; c < cellBoxes[r].length; c++) {
        final cell = cellBoxes[r][c];
        final cellY = currentY + (rowHeights[r] - cell.height) / 2;
        _offsetCommands(cell.commandStart, cell.commandEnd, currentX, cellY);
        currentX += colWidths[c] + colGap;
      }
      currentY += rowHeights[r] + rowGap;
    }

    // Draw left brace using path delimiter.
    _addPathDelimiter('{', 0, 0, braceWidth, contentHeight, fs, color);

    final totalWidth = braceWidth + contentWidth;
    return _LayoutBox(
      width: totalWidth,
      height: contentHeight,
      baseline: contentHeight / 2 + fs * _mathAxisOffset,
      commandStart:
          cellBoxes.isNotEmpty && cellBoxes.first.isNotEmpty
              ? cellBoxes.first.first.commandStart
              : _commands.length - 1,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutExtensibleArrow(
    LatexExtensibleArrow node,
    double fs,
    Color color,
  ) {
    final cmdStart = _commands.length;
    final minWidth = fs * 2.0;
    final strokeW = fs * _fractionBarThickness;

    // Layout optional text above/below.
    _LayoutBox? aboveBox;
    _LayoutBox? belowBox;
    if (node.above != null) {
      aboveBox = _layout(node.above!, fs * _scriptScale, color);
    }
    if (node.below != null) {
      belowBox = _layout(node.below!, fs * _scriptScale, color);
    }

    final textWidth = [
      minWidth,
      if (aboveBox != null) aboveBox.width + fs * 0.4,
      if (belowBox != null) belowBox.width + fs * 0.4,
    ].fold<double>(0, (a, b) => a > b ? a : b);

    final arrowY =
        (aboveBox != null ? aboveBox.height + fs * 0.08 : 0) + fs * 0.1;

    // Draw arrow line.
    _commands.add(
      LineDrawCommand(
        x1: 0,
        y1: arrowY,
        x2: textWidth,
        y2: arrowY,
        thickness: strokeW,
        color: color,
      ),
    );

    // Draw arrowhead.
    final headSize = fs * 0.12;
    if (node.direction == 'right' || node.direction == 'both') {
      _commands.add(
        PathDrawCommand(
          points: [
            Offset(textWidth - headSize, arrowY - headSize),
            Offset(textWidth, arrowY),
            Offset(textWidth - headSize, arrowY + headSize),
          ],
          strokeWidth: strokeW,
          color: color,
        ),
      );
    }
    if (node.direction == 'left' || node.direction == 'both') {
      _commands.add(
        PathDrawCommand(
          points: [
            Offset(headSize, arrowY - headSize),
            Offset(0, arrowY),
            Offset(headSize, arrowY + headSize),
          ],
          strokeWidth: strokeW,
          color: color,
        ),
      );
    }

    // Position text above/below arrow.
    if (aboveBox != null) {
      final ax = (textWidth - aboveBox.width) / 2;
      _offsetCommands(aboveBox.commandStart, aboveBox.commandEnd, ax, 0);
    }
    if (belowBox != null) {
      final bx = (textWidth - belowBox.width) / 2;
      final by = arrowY + fs * 0.15;
      _offsetCommands(belowBox.commandStart, belowBox.commandEnd, bx, by);
    }

    final totalHeight =
        arrowY +
        fs * 0.1 +
        (belowBox != null ? belowBox.height + fs * 0.08 : 0);

    return _LayoutBox(
      width: textWidth,
      height: totalHeight,
      baseline: arrowY,
      commandStart: cmdStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutAlign(LatexAlign node, double fs, Color color) {
    if (node.rows.isEmpty) {
      return _LayoutBox(width: 0, height: fs, baseline: fs * _baselineFraction);
    }

    final rowGap = fs * 0.25;
    final colGap = fs * 0.15;

    // Layout each cell.
    final cellBoxes = <List<_LayoutBox>>[];
    for (final row in node.rows) {
      final rowBoxes = <_LayoutBox>[];
      for (final cell in row) {
        rowBoxes.add(_layout(cell, fs, color));
      }
      cellBoxes.add(rowBoxes);
    }

    // Determine max columns (typically 2: left & right of &).
    final numCols = cellBoxes.fold<int>(
      0,
      (mx, r) => r.length > mx ? r.length : mx,
    );

    // Compute column widths.
    final colWidths = List<double>.filled(numCols, 0);
    for (final row in cellBoxes) {
      for (var c = 0; c < row.length; c++) {
        if (row[c].width > colWidths[c]) colWidths[c] = row[c].width;
      }
    }

    // Compute row heights.
    final rowHeights = <double>[];
    for (final row in cellBoxes) {
      var maxH = fs;
      for (final cell in row) {
        if (cell.height > maxH) maxH = cell.height;
      }
      rowHeights.add(maxH);
    }

    // Total width.
    final totalWidth =
        colWidths.fold<double>(0, (s, w) => s + w) +
        (numCols > 1 ? (numCols - 1) * colGap : 0);

    // Position cells — right-align col 0 (before &), left-align col 1+ (after &).
    var currentY = 0.0;
    for (var r = 0; r < cellBoxes.length; r++) {
      var currentX = 0.0;
      for (var c = 0; c < cellBoxes[r].length; c++) {
        final cell = cellBoxes[r][c];
        double cellX;
        if (c == 0) {
          // Right-align the left column.
          cellX = colWidths[0] - cell.width;
        } else {
          cellX = currentX;
        }
        final cellY = currentY + (rowHeights[r] - cell.height) / 2;
        _offsetCommands(cell.commandStart, cell.commandEnd, cellX, cellY);
        currentX = colWidths[0] + colGap + (c > 0 ? colWidths[c] + colGap : 0);
      }
      currentY += rowHeights[r] + rowGap;
    }

    final totalHeight = currentY - rowGap; // remove trailing gap

    return _LayoutBox(
      width: totalWidth,
      height: totalHeight,
      baseline:
          rowHeights.isNotEmpty
              ? rowHeights.first * _baselineFraction
              : totalHeight / 2,
      commandStart:
          cellBoxes.first.isNotEmpty
              ? cellBoxes.first.first.commandStart
              : _commands.length,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutColorBox(LatexColorBox node, double fs, Color color) {
    final bgColor = _parseColorName(node.colorName);
    final bodyBox = _layout(node.body, fs, color);
    final padding = fs * 0.08;
    final cmdStart = bodyBox.commandStart;

    // Offset body for padding.
    _offsetCommands(bodyBox.commandStart, bodyBox.commandEnd, padding, padding);

    final totalWidth = bodyBox.width + padding * 2;
    final totalHeight = bodyBox.height + padding * 2;

    // Draw filled background rectangle.
    _commands.add(
      RectDrawCommand(
        x: 0,
        y: 0,
        width: totalWidth,
        height: totalHeight,
        color: bgColor,
        filled: true,
      ),
    );

    return _LayoutBox(
      width: totalWidth,
      height: totalHeight,
      baseline: bodyBox.baseline + padding,
      commandStart: cmdStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutRule(LatexRule node, double fs, Color color) {
    final w = fs * node.widthEm;
    final h = fs * node.heightEm;

    _commands.add(
      RectDrawCommand(
        x: 0,
        y: 0,
        width: w,
        height: h,
        color: color,
        filled: true,
      ),
    );

    return _LayoutBox(
      width: w,
      height: h,
      baseline: h,
      commandStart: _commands.length - 1,
      commandEnd: _commands.length,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Offset all draw commands in [start, end) by (dx, dy).
  void _offsetCommands(int start, int end, double dx, double dy) {
    if (dx == 0 && dy == 0) return;
    for (int i = start; i < end && i < _commands.length; i++) {
      final cmd = _commands[i];
      switch (cmd) {
        case GlyphDrawCommand():
          _commands[i] = GlyphDrawCommand(
            text: cmd.text,
            x: cmd.x + dx,
            y: cmd.y + dy,
            fontSize: cmd.fontSize,
            color: cmd.color,
            fontFamily: cmd.fontFamily,
            italic: cmd.italic,
            bold: cmd.bold,
          );
        case LineDrawCommand():
          _commands[i] = LineDrawCommand(
            x1: cmd.x1 + dx,
            y1: cmd.y1 + dy,
            x2: cmd.x2 + dx,
            y2: cmd.y2 + dy,
            thickness: cmd.thickness,
            color: cmd.color,
          );
        case PathDrawCommand():
          _commands[i] = PathDrawCommand(
            points:
                cmd.points.map((p) => Offset(p.dx + dx, p.dy + dy)).toList(),
            closed: cmd.closed,
            strokeWidth: cmd.strokeWidth,
            color: cmd.color,
            filled: cmd.filled,
          );
        case RectDrawCommand():
          _commands[i] = RectDrawCommand(
            x: cmd.x + dx,
            y: cmd.y + dy,
            width: cmd.width,
            height: cmd.height,
            color: cmd.color,
            filled: cmd.filled,
          );
      }
    }
  }

  /// Measure text width using TextPainter. Results cached by (text, size, italic, font).
  double _measureTextWidth(
    String text,
    double fontSize, {
    bool italic = false,
  }) {
    final key = '$text|$fontSize|$italic|${_mathFontFamily ?? ""}';
    final cached = _widthCache[key];
    if (cached != null) return cached;

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: _mathFontFamily,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final width = tp.width;
    _widthCache[key] = width;
    return width;
  }

  /// Measure character width using TextPainter for accurate glyph metrics.
  ///
  /// All characters — including single ASCII — are measured against the
  /// actual font to ensure correct alignment with the bundled math font.
  double _measureCharWidth(
    String char,
    double fontSize, {
    bool italic = false,
  }) {
    return _measureTextWidth(char, fontSize, italic: italic);
  }

  /// Returns true if [s] is a binary operator (thin-space spacing).
  static bool _isBinaryOperator(String s) {
    return '+-×÷·±∓∗∘∙⊕⊗⊖⊙'.contains(s);
  }

  /// Returns true if [s] is a relational operator (thick-space spacing).
  static bool _isRelationalOperator(String s) {
    return '=≠≤≥<>≈≡∼∝∈∉⊂⊃⊆⊇∪∩→←↔⇒⇐⇔'.contains(s);
  }

  static double _cos(double x) => math.cos(x);
  static double _sin(double x) => math.sin(x);

  static String _accentSymbol(String type) {
    return switch (type) {
      'hat' || 'widehat' => '^',
      'bar' || 'overline' => '‾',
      'vec' => '→',
      'dot' => '˙',
      'ddot' => '¨',
      'tilde' || 'widetilde' => '~',
      'breve' => '˘',
      'check' => 'ˇ',
      'acute' => '´',
      'grave' => '`',
      _ => '^',
    };
  }
}

/// Internal bounding box for layout computation.
class _LayoutBox {
  final double width;
  final double height;
  final double baseline;
  final int commandStart;
  final int commandEnd;

  _LayoutBox({
    required this.width,
    required this.height,
    required this.baseline,
    this.commandStart = 0,
    this.commandEnd = 0,
  });
}
