import 'dart:ui';
import 'latex_ast.dart';
import 'latex_draw_command.dart';

/// 🧮 LaTeX Layout Engine — converts an AST into positioned draw commands.
///
/// Implements TeX-inspired math typesetting rules to compute the position,
/// size, and style of every glyph and line in the expression.
///
/// The layout is deterministic and side-effect-free: given the same AST,
/// fontSize, and color, it always produces identical output.
///
/// Example:
/// ```dart
/// final ast = LatexParser.parse(r'\frac{a}{b}');
/// final result = LatexLayoutEngine.layout(ast, fontSize: 24, color: Colors.white);
/// // result.commands → [GlyphDrawCommand, LineDrawCommand, GlyphDrawCommand]
/// // result.size → Size(width, height)
/// ```
class LatexLayoutEngine {
  /// Layout an AST tree into positioned draw commands.
  static LatexLayoutResult layout(
    LatexAstNode node, {
    required double fontSize,
    required Color color,
  }) {
    final engine = LatexLayoutEngine._();
    final box = engine._layout(node, fontSize, color);
    return LatexLayoutResult(
      commands: engine._commands,
      size: Size(box.width, box.height),
      baseline: box.baseline,
    );
  }

  LatexLayoutEngine._();

  final List<LatexDrawCommand> _commands = [];

  // ---------------------------------------------------------------------------
  // TeX-Inspired Constants (proportional to fontSize)
  // ---------------------------------------------------------------------------

  /// Scale factor for sub/superscripts relative to base font size.
  static const double _scriptScale = 0.7;

  /// Scale factor for sub-sub-scripts.
  static const double _scriptScriptScale = 0.5;

  /// Superscript vertical offset (upward) as fraction of fontSize.
  static const double _superscriptShift = 0.45;

  /// Subscript vertical offset (downward) as fraction of fontSize.
  static const double _subscriptShift = 0.25;

  /// Fraction bar thickness as fraction of fontSize.
  static const double _fractionBarThickness = 0.04;

  /// Gap between fraction bar and numerator/denominator.
  static const double _fractionGap = 0.15;

  /// Horizontal padding for fraction numerator/denominator.
  static const double _fractionPadding = 0.1;

  /// Radical symbol vertical overhang above radicand.
  static const double _radicalOverhang = 0.1;

  /// Baseline fraction (how far down from top the baseline sits).
  static const double _baselineFraction = 0.7;

  /// Math axis position relative to baseline (fraction of fontSize).
  ///
  /// In TeX, the math axis is the vertical center of operators and fraction
  /// bars. It sits slightly above the geometric midline of the x-height.
  /// Operators like =, +, - and fraction bars must align to this axis,
  /// NOT to the text baseline.
  static const double _mathAxisOffset = 0.25;

  /// Approximate character width as fraction of fontSize.
  static const double _charWidthFraction = 0.55;

  /// Spacing between atoms as fraction of fontSize.
  static const double _atomSpacing = 0.05;

  /// Operator spacing (around +, -, =, etc.) as fraction of fontSize.
  static const double _operatorSpacing = 0.15;

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
    final isOperator = _isOperatorSymbol(node.value);
    final charWidth = _measureCharWidth(node.value, fs);
    final height = fs;
    final baseline = fs * _baselineFraction;

    // R3: For binary/relational operators, shift Y so the glyph center
    // aligns with the math axis rather than sitting on the text baseline.
    final yShift = isOperator ? fs * _mathAxisOffset * 0.5 : 0.0;

    _commands.add(
      GlyphDrawCommand(
        text: node.value,
        x: 0, // will be offset by parent
        y: -yShift,
        fontSize: fs,
        color: color,
        italic: node.italic,
      ),
    );

    final totalWidth =
        isOperator ? charWidth + fs * _operatorSpacing * 2 : charWidth;

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

    // Compute total width and max ascent/descent
    double totalWidth = 0;
    double maxAscent = 0; // baseline distance from top
    double maxDescent = 0; // distance from baseline to bottom

    for (final box in childBoxes) {
      maxAscent = maxAscent > box.baseline ? maxAscent : box.baseline;
      final descent = box.height - box.baseline;
      maxDescent = maxDescent > descent ? maxDescent : descent;
    }

    final totalHeight = maxAscent + maxDescent;

    // Position children horizontally, aligned by baseline
    for (int i = 0; i < childBoxes.length; i++) {
      final box = childBoxes[i];
      final dx = totalWidth;
      final dy = maxAscent - box.baseline;

      // Offset all commands in this child
      _offsetCommands(box.commandStart, box.commandEnd, dx, dy);

      totalWidth += box.width + fs * _atomSpacing;
    }

    // Remove trailing atom spacing
    totalWidth -= fs * _atomSpacing;

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

    // R3: Math axis alignment — the fraction bar sits at the math axis,
    // which is offset above the baseline center. This ensures that in
    // expressions like `a + \frac{b}{c} = d`, the = sign aligns with
    // the fraction bar, not with the top or bottom of the fraction.
    final mathAxis = fs * _baselineFraction - fs * _mathAxisOffset;
    final barY = numBox.height + gap + barThickness / 2;
    final baseline = mathAxis + (barY - mathAxis);

    // Position numerator (centered)
    final numX = (contentWidth - numBox.width) / 2;
    _offsetCommands(numBox.commandStart, numBox.commandEnd, numX, 0);

    // Fraction bar
    _commands.add(
      LineDrawCommand(
        x1: 0,
        y1: numBox.height + gap + barThickness / 2,
        x2: contentWidth,
        y2: numBox.height + gap + barThickness / 2,
        thickness: barThickness,
        color: color,
      ),
    );

    // Position denominator (centered)
    final denX = (contentWidth - denBox.width) / 2;
    final denY = numBox.height + gap + barThickness + gap;
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

    final supY = -(fs * _superscriptShift);
    _offsetCommands(
      supBox.commandStart,
      supBox.commandEnd,
      baseBox.width,
      supY,
    );

    final ascent = baseBox.baseline + (-supY > 0 ? -supY : 0);
    final descent =
        (baseBox.height - baseBox.baseline) >
                (supBox.height + supY - baseBox.baseline)
            ? (baseBox.height - baseBox.baseline)
            : 0.0;

    return _LayoutBox(
      width: baseBox.width + supBox.width,
      height:
          ascent + descent > baseBox.height ? ascent + descent : baseBox.height,
      baseline: ascent,
      commandStart: baseBox.commandStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutSubscript(LatexSubscript node, double fs, Color color) {
    final baseBox = _layout(node.base, fs, color);
    final subBox = _layout(node.subscript, fs * _scriptScale, color);

    final subY = fs * _subscriptShift;
    _offsetCommands(
      subBox.commandStart,
      subBox.commandEnd,
      baseBox.width,
      subY,
    );

    final totalHeight =
        baseBox.height + subY > baseBox.height + subBox.height
            ? baseBox.height
            : subY + subBox.height;

    return _LayoutBox(
      width: baseBox.width + subBox.width,
      height: totalHeight > baseBox.height ? totalHeight : baseBox.height,
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

    final supY = -(fs * _superscriptShift);
    _offsetCommands(
      supBox.commandStart,
      supBox.commandEnd,
      baseBox.width,
      supY,
    );

    final subY = fs * _subscriptShift;
    _offsetCommands(
      subBox.commandStart,
      subBox.commandEnd,
      baseBox.width,
      subY,
    );

    final scriptWidth =
        supBox.width > subBox.width ? supBox.width : subBox.width;
    final ascent = baseBox.baseline + (-supY > 0 ? -supY : 0);
    final descent = subY + subBox.height - baseBox.baseline;
    final totalHeight = ascent + (descent > 0 ? descent : 0);

    return _LayoutBox(
      width: baseBox.width + scriptWidth,
      height: totalHeight > baseBox.height ? totalHeight : baseBox.height,
      baseline: ascent,
      commandStart: baseBox.commandStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutSqrt(LatexSqrt node, double fs, Color color) {
    final radBox = _layout(node.radicand, fs, color);
    final overhang = fs * _radicalOverhang;
    final barThickness = fs * _fractionBarThickness;
    final symbolWidth = fs * 0.5;

    // Radical symbol path (simplified √ shape)
    final symHeight = radBox.height + overhang + barThickness;
    _commands.add(
      PathDrawCommand(
        points: [
          Offset(0, symHeight * 0.6),
          Offset(symbolWidth * 0.3, symHeight * 0.6),
          Offset(symbolWidth * 0.5, symHeight),
          Offset(symbolWidth, 0),
        ],
        strokeWidth: barThickness * 1.5,
        color: color,
      ),
    );

    // Horizontal bar over radicand
    _commands.add(
      LineDrawCommand(
        x1: symbolWidth,
        y1: barThickness / 2,
        x2: symbolWidth + radBox.width + overhang,
        y2: barThickness / 2,
        thickness: barThickness,
        color: color,
      ),
    );

    // Offset radicand content
    _offsetCommands(
      radBox.commandStart,
      radBox.commandEnd,
      symbolWidth,
      barThickness + overhang,
    );

    final totalWidth = symbolWidth + radBox.width + overhang;
    final totalHeight = symHeight;

    // Layout optional degree
    if (node.degree != null) {
      final degBox = _layout(node.degree!, fs * _scriptScriptScale, color);
      _offsetCommands(degBox.commandStart, degBox.commandEnd, 0, 0);
    }

    return _LayoutBox(
      width: totalWidth,
      height: totalHeight,
      baseline: totalHeight * _baselineFraction,
      commandStart:
          _commands.length -
          2 -
          (radBox.commandEnd - radBox.commandStart) -
          (node.degree != null ? 1 : 0),
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutBigOperator(LatexBigOperator node, double fs, Color color) {
    final opSize = fs * 1.5;
    final charWidth = _measureCharWidth(node.operator, opSize);

    _commands.add(
      GlyphDrawCommand(
        text: node.operator,
        x: 0,
        y: 0,
        fontSize: opSize,
        color: color,
      ),
    );

    return _LayoutBox(
      width: charWidth + fs * _operatorSpacing,
      height: opSize,
      baseline: opSize * _baselineFraction,
      commandStart: _commands.length - 1,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutMatrix(LatexMatrix node, double fs, Color color) {
    if (node.rows.isEmpty) {
      return _LayoutBox(width: 0, height: fs, baseline: fs * _baselineFraction);
    }

    final cellFs = fs * _scriptScale;
    final cellGap = fs * 0.3;
    final rowGap = fs * 0.2;

    // Layout all cells
    final cellBoxes = <List<_LayoutBox>>[];
    for (final row in node.rows) {
      final rowBoxes = <_LayoutBox>[];
      for (final cell in row) {
        rowBoxes.add(_layout(cell, cellFs, color));
      }
      cellBoxes.add(rowBoxes);
    }

    // Compute column widths
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

    // Compute row heights
    final rowHeights =
        cellBoxes.map((row) {
          double maxH = cellFs;
          for (final box in row) {
            if (box.height > maxH) maxH = box.height;
          }
          return maxH;
        }).toList();

    // Position all cells
    double y = 0;
    for (int r = 0; r < cellBoxes.length; r++) {
      double x = 0;
      for (int c = 0; c < cellBoxes[r].length; c++) {
        final box = cellBoxes[r][c];
        final dx = x + (colWidths[c] - box.width) / 2;
        final dy = y + (rowHeights[r] - box.height) / 2;
        _offsetCommands(box.commandStart, box.commandEnd, dx, dy);
        x += colWidths[c] + cellGap;
      }
      y += rowHeights[r] + rowGap;
    }

    final totalWidth =
        colWidths.fold(0.0, (s, w) => s + w) + cellGap * (maxCols - 1);
    final totalHeight =
        rowHeights.fold(0.0, (s, h) => s + h) + rowGap * (cellBoxes.length - 1);

    return _LayoutBox(
      width: totalWidth,
      height: totalHeight,
      baseline: totalHeight / 2,
      commandStart:
          cellBoxes.first.isNotEmpty ? cellBoxes.first.first.commandStart : 0,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutDelimited(LatexDelimited node, double fs, Color color) {
    final bodyBox = _layout(node.body, fs, color);
    final delimWidth = fs * 0.3;
    final delimHeight = bodyBox.height * 1.1;

    // Draw opening delimiter
    if (node.open.isNotEmpty) {
      _commands.add(
        GlyphDrawCommand(
          text: node.open,
          x: 0,
          y: (delimHeight - bodyBox.height) / 2,
          fontSize: delimHeight,
          color: color,
        ),
      );
    }

    // Offset body
    _offsetCommands(
      bodyBox.commandStart,
      bodyBox.commandEnd,
      delimWidth,
      (delimHeight - bodyBox.height) / 2,
    );

    // Draw closing delimiter
    if (node.close.isNotEmpty) {
      _commands.add(
        GlyphDrawCommand(
          text: node.close,
          x: delimWidth + bodyBox.width,
          y: (delimHeight - bodyBox.height) / 2,
          fontSize: delimHeight,
          color: color,
        ),
      );
    }

    final closeWidth = node.close.isNotEmpty ? delimWidth : 0;
    final openWidth = node.open.isNotEmpty ? delimWidth : 0;

    return _LayoutBox(
      width: openWidth + bodyBox.width + closeWidth,
      height: delimHeight,
      baseline: delimHeight * _baselineFraction,
      commandStart:
          _commands.length -
          (bodyBox.commandEnd - bodyBox.commandStart) -
          (node.open.isNotEmpty ? 1 : 0) -
          (node.close.isNotEmpty ? 1 : 0),
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutText(LatexText node, double fs, Color color) {
    final charWidth = fs * _charWidthFraction;
    final width = node.text.length * charWidth;

    _commands.add(
      GlyphDrawCommand(
        text: node.text,
        x: 0,
        y: 0,
        fontSize: fs,
        color: color,
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
    _commands.add(
      GlyphDrawCommand(
        text: 'lim',
        x: 0,
        y: 0,
        fontSize: fs,
        color: color,
        italic: false,
      ),
    );

    final width = fs * _charWidthFraction * 3;
    return _LayoutBox(
      width: width + fs * _operatorSpacing,
      height: fs,
      baseline: fs * _baselineFraction,
      commandStart: _commands.length - 1,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutAccent(LatexAccent node, double fs, Color color) {
    final baseBox = _layout(node.base, fs, color);
    final accentChar = _accentSymbol(node.accentType);
    final accentHeight = fs * 0.25;

    // Draw accent above base
    _commands.add(
      GlyphDrawCommand(
        text: accentChar,
        x: baseBox.width * 0.3,
        y: -accentHeight,
        fontSize: fs * 0.8,
        color: color,
      ),
    );

    // Offset base down to make room for accent
    _offsetCommands(baseBox.commandStart, baseBox.commandEnd, 0, accentHeight);

    return _LayoutBox(
      width: baseBox.width,
      height: baseBox.height + accentHeight,
      baseline: baseBox.baseline + accentHeight,
      commandStart: baseBox.commandStart,
      commandEnd: _commands.length,
    );
  }

  _LayoutBox _layoutError(LatexErrorNode node, double fs, Color color) {
    // Render error text in red
    final errorColor = const Color(0xFFFF4444);
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

  /// Approximate character width measurement.
  double _measureCharWidth(String char, double fontSize) {
    // Wide characters
    if ('∫∑∏∬∭∮'.contains(char)) return fontSize * 0.7;
    if ('WMwm'.contains(char)) return fontSize * 0.75;
    // Narrow characters
    if ('iIlj1|!.,;:'.contains(char)) return fontSize * 0.3;
    if ('ft'.contains(char)) return fontSize * 0.35;
    // Standard
    return fontSize * _charWidthFraction;
  }

  static bool _isOperatorSymbol(String s) {
    return '+-=≠≤≥≈≡∼±∓×÷·→←↔⇒⇐⇔∈∉⊂⊃∪∩∝'.contains(s);
  }

  static String _accentSymbol(String type) {
    switch (type) {
      case 'hat':
        return '^';
      case 'bar':
      case 'overline':
        return '‾';
      case 'vec':
        return '→';
      case 'dot':
        return '˙';
      case 'ddot':
        return '¨';
      case 'tilde':
      case 'widetilde':
        return '~';
      case 'widehat':
        return '^';
      default:
        return '^';
    }
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
