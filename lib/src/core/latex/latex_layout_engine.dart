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
  static LatexLayoutResult layout(
    LatexAstNode node, {
    required double fontSize,
    required Color color,
    String? fontFamily,
  }) {
    final engine = LatexLayoutEngine._(mathFontFamily: fontFamily);
    final box = engine._layout(node, fontSize, color);
    return LatexLayoutResult(
      commands: engine._commands,
      size: Size(box.width, box.height),
      baseline: box.baseline,
    );
  }

  LatexLayoutEngine._({String? mathFontFamily}) : _mathFontFamily = mathFontFamily;

  final List<LatexDrawCommand> _commands = [];

  /// Math font family applied to every glyph. Setting this to a dedicated
  /// math font (e.g. 'STIX Two Math') is the single biggest visual upgrade.
  final String? _mathFontFamily;

  // Measurement cache — avoids redundant TextPainter.layout() calls.
  final Map<String, double> _widthCache = {};

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

  /// Spacing between ordinary atoms (thin inter-atom kern).
  /// Keeps default spacing tight; operators add their own spacing.
  static const double _atomSpacing = 0.04;

  /// TeX thin space (3 mu = 3/18 em ≈ 0.167 em).
  /// Used on both sides of binary operators: +, −, ×, ÷, ·, ±, ∓.
  static const double _thinSpace = 3.0 / 18.0;

  /// TeX thick space (5 mu = 5/18 em ≈ 0.278 em).
  /// Used on both sides of relational operators: =, ≠, <, >, ≤, ≥, ≈, ≡, ∼.
  static const double _thickSpace = 5.0 / 18.0;

  /// Space between big-operator glyph and inline limits (sub/superscript).
  static const double _bigOpLimitKern = 0.04;

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
      // Add inter-atom spacing between children (not after the last).
      if (i < childBoxes.length - 1) {
        totalWidth += fs * _atomSpacing;
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

    // The fraction bar is centered on the math axis. The baseline of the
    // entire fraction equals the bar's vertical center, so that operators
    // like = and fraction bars align in compound expressions.
    final barTopY = numBox.height + gap;
    final barMidY = barTopY + barThickness / 2;

    // Baseline is the bar mid-line (math axis alignment).
    final baseline = barMidY;

    // Position numerator centered above bar.
    final numX = (contentWidth - numBox.width) / 2;
    _offsetCommands(numBox.commandStart, numBox.commandEnd, numX, 0);

    // Draw fraction bar (vinculum).
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
    final supBox = _layout(node.exponent, fs * _scriptScale, color);

    // Italic correction: if the base is italic, shift superscript right by a
    // small kern so it clears the slanted stroke (TeX: italcorr).
    final italicCorrection =
        (node.base is LatexSymbol && (node.base as LatexSymbol).italic)
            ? fs * 0.10
            : 0.0;

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

    final subY = baseBox.baseline - subBox.baseline + fs * _subscriptShift;
    _offsetCommands(
      subBox.commandStart,
      subBox.commandEnd,
      baseBox.width,
      subY,
    );

    final subBottom = subY + subBox.height;
    final totalHeight = subBottom > baseBox.height ? subBottom : baseBox.height;

    return _LayoutBox(
      width: baseBox.width + subBox.width,
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
    _commands.add(
      PathDrawCommand(
        points: [
          Offset(0, symHeight * 0.62), // P0: serif left
          Offset(tailWidth, symHeight * 0.57), // P1: serif right / kink
          Offset(tailWidth + veeWidth, symHeight), // P2: V bottom
          Offset(symbolWidth, barThickness / 2), // P3: top of upstroke
        ],
        strokeWidth: strokeWidth,
        color: color,
      ),
    );

    // Vinculum (horizontal bar over radicand).
    _commands.add(
      LineDrawCommand(
        x1: symbolWidth - strokeWidth * 0.25,
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

    double opWidth;

    if (isIntegral) {
      opWidth = opSize * 0.32;
      final strokeW = fs * _fractionBarThickness * 2.2;
      final h = opSize;
      final w = opWidth;

      final count = switch (node.operator) {
        '∬' => 2,
        '∭' => 3,
        _ => 1,
      };
      final spacing = count > 1 ? w * 0.6 : 0.0;

      for (int n = 0; n < count; n++) {
        final dx = n * spacing;
        _commands.add(
          PathDrawCommand(
            points: [
              Offset(dx + w * 0.70, h * 0.02),
              Offset(dx + w * 0.55, 0),
              Offset(dx + w * 0.45, h * 0.05),
              Offset(dx + w * 0.48, h * 0.25),
              Offset(dx + w * 0.48, h * 0.45),
              Offset(dx + w * 0.50, h * 0.50),
              Offset(dx + w * 0.52, h * 0.55),
              Offset(dx + w * 0.52, h * 0.75),
              Offset(dx + w * 0.55, h * 0.95),
              Offset(dx + w * 0.45, h),
              Offset(dx + w * 0.30, h * 0.98),
            ],
            strokeWidth: strokeW,
            color: color,
          ),
        );
      }

      if (node.operator == '∮') {
        final cx = w * 0.50;
        final cy = h * 0.50;
        final r = fs * 0.08;
        final circlePoints = <Offset>[];
        for (int i = 0; i <= 8; i++) {
          final angle = i * math.pi * 2.0 / 8;
          circlePoints.add(Offset(cx + r * _cos(angle), cy + r * _sin(angle)));
        }
        _commands.add(
          PathDrawCommand(
            points: circlePoints,
            strokeWidth: strokeW * 0.7,
            color: color,
            closed: true,
          ),
        );
      }

      if (count > 1) opWidth = w + spacing * (count - 1);
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
      // Inline style (∫, ∬ …): limits as sub/superscript.
      final opBaseline = opSize * _baselineFraction;
      final limX = opWidth + fs * _bigOpLimitKern;
      double totalWidth = limX;
      double ascent = opBaseline;
      double descent = opSize - opBaseline;

      if (node.upper != null) {
        final supBox = _layout(node.upper!, fs * _scriptScale, color);
        final supShift = fs * _superscriptShift;
        final supY = opBaseline - supShift - supBox.height;
        _offsetCommands(supBox.commandStart, supBox.commandEnd, limX, supY);
        totalWidth = limX + supBox.width;
        if (-supY > ascent) ascent = -supY;
      }

      if (node.lower != null) {
        final subBox = _layout(node.lower!, fs * _scriptScale, color);
        final subY = opBaseline + fs * _subscriptShift - subBox.baseline;
        _offsetCommands(subBox.commandStart, subBox.commandEnd, limX, subY);
        final scriptW = node.upper != null ? (totalWidth - limX) : subBox.width;
        totalWidth = limX + (scriptW > subBox.width ? scriptW : subBox.width);
        final subBottom = subY + subBox.height - opBaseline;
        if (subBottom > descent) descent = subBottom;
      }

      return _LayoutBox(
        width: totalWidth + fs * _thickSpace,
        height: ascent + descent,
        baseline: ascent,
        commandStart: cmdStart,
        commandEnd: _commands.length,
      );
    }

    // Display style (∑, ∏ …): limits centered above/below.
    double upperHeight = 0;
    double lowerHeight = 0;
    double maxWidth = opWidth;
    final gap = fs * 0.12;

    _LayoutBox? upperBox;
    _LayoutBox? lowerBox;

    if (node.upper != null) {
      upperBox = _layout(node.upper!, fs * _scriptScale, color);
      upperHeight = upperBox.height + gap;
      if (upperBox.width > maxWidth) maxWidth = upperBox.width;
    }

    if (node.lower != null) {
      lowerBox = _layout(node.lower!, fs * _scriptScale, color);
      lowerHeight = lowerBox.height + gap;
      if (lowerBox.width > maxWidth) maxWidth = lowerBox.width;
    }

    final totalHeight = upperHeight + opSize + lowerHeight;
    final baseline = upperHeight + opSize * _baselineFraction;

    final opX = (maxWidth - opWidth) / 2;
    _offsetCommands(cmdStart, cmdStart + 1, opX, upperHeight);

    if (upperBox != null) {
      final ux = (maxWidth - upperBox.width) / 2;
      _offsetCommands(upperBox.commandStart, upperBox.commandEnd, ux, 0);
    }

    if (lowerBox != null) {
      final lx = (maxWidth - lowerBox.width) / 2;
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

  _LayoutBox _layoutDelimited(LatexDelimited node, double fs, Color color) {
    final bodyBox = _layout(node.body, fs, color);

    // Scale delimiters to at least 1 em tall and add 10 % vertical clearance.
    final minDelimHeight = fs;
    final rawHeight = bodyBox.height * 1.10;
    final delimHeight = rawHeight > minDelimHeight ? rawHeight : minDelimHeight;
    final delimWidth = fs * 0.30;

    // Vertical offset so delimiters are centered around the body.
    final vertOffset = (delimHeight - bodyBox.height) / 2;

    if (node.open.isNotEmpty) {
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

    _offsetCommands(
      bodyBox.commandStart,
      bodyBox.commandEnd,
      delimWidth,
      vertOffset,
    );

    if (node.close.isNotEmpty) {
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
    final width = _measureTextWidth(node.text, fs, italic: false);

    _commands.add(
      GlyphDrawCommand(
        text: node.text,
        x: 0,
        y: 0,
        fontSize: fs,
        color: color,
        fontFamily: _mathFontFamily,
        italic: false,
      ),
    );

    return _LayoutBox(
      width: width,
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

    return _LayoutBox(
      width: fs * _charWidthFraction * text.length,
      height: fs,
      baseline: fs * _baselineFraction,
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

  /// Approximate character width — fast path for single ASCII characters.
  /// Falls back to TextPainter for multi-char strings and Unicode math symbols.
  double _measureCharWidth(
    String char,
    double fontSize, {
    bool italic = false,
  }) {
    if (char.length > 1)
      return _measureTextWidth(char, fontSize, italic: italic);
    if (char.codeUnitAt(0) > 127)
      return _measureTextWidth(char, fontSize, italic: italic);

    // Letter-specific heuristics — uppercase and lowercase grouped by width class.
    if ('WM'.contains(char)) return fontSize * 0.76;
    if ('wm'.contains(char)) return fontSize * 0.68;
    if ('ABCDEFGHKLNOPQRSTUVXYZbdghknopquy'.contains(char))
      return fontSize * 0.58;
    if ('aecrsxz'.contains(char)) return fontSize * 0.52;
    if ('iIlj1|!.,;:'.contains(char)) return fontSize * 0.30;
    if ('ft'.contains(char)) return fontSize * 0.36;
    if ('r'.contains(char)) return fontSize * 0.38;
    if ('0123456789'.contains(char)) return fontSize * 0.54;
    return fontSize * _charWidthFraction;
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
