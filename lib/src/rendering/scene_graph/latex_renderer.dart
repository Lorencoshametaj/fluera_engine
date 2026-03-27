import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/nodes/latex_node.dart';
import '../../core/latex/latex_draw_command.dart';
import 'latex_chart_renderer.dart';

/// 🧮 LatexRenderer — renders a [LatexNode] onto a Flutter [Canvas].
///
/// Consumes the pre-computed [LatexDrawCommand] list from the layout engine
/// and executes the corresponding Canvas operations:
/// - [GlyphDrawCommand] → `canvas.drawParagraph()` / `TextPainter.paint()`
/// - [LineDrawCommand]  → `canvas.drawLine()`
/// - [PathDrawCommand]  → `canvas.drawPath()`
///
/// When no cached layout is available, draws a placeholder.
class LatexRenderer {
  /// Draw the LaTeX node onto the canvas.
  ///
  /// When a `ui.Picture` cache exists on the node, replays it directly
  /// (zero per-frame allocation). Otherwise renders from draw commands and
  /// records the result for next time.
  static void drawLatexNode(Canvas canvas, LatexNode node) {
    final commands = node.cachedDrawCommands;
    if (commands != null && commands.isNotEmpty) {
      // --- Picture cache fast path ----------------------------------------
      final cached = node.cachedPicture;
      if (cached != null) {
        canvas.drawPicture(cached);
        return;
      }

      // --- Record into Picture for future re-use --------------------------
      final recorder = ui.PictureRecorder();
      final recCanvas = Canvas(recorder);
      for (final cmd in commands) {
        switch (cmd) {
          case GlyphDrawCommand():
            _drawGlyph(recCanvas, cmd);
          case LineDrawCommand():
            _drawLine(recCanvas, cmd);
          case PathDrawCommand():
            _drawPathCmd(recCanvas, cmd);
          case RectDrawCommand():
            _drawRect(recCanvas, cmd);
        }
      }
      final picture = recorder.endRecording();
      node.cachedPicture = picture;
      canvas.drawPicture(picture);
      return;
    }

    // Route to the appropriate visual renderer.
    if (node.chartType != null) {
      LatexChartRenderer.drawChartPreview(canvas, node);
    } else if (node.latexSource.contains(r'\begin{tabular}')) {
      _drawTabularPreview(canvas, node);
    } else {
      drawPlaceholder(canvas, node);
    }
  }

  /// Draw a text glyph at its computed position.
  ///
  /// Uses subpixel-accurate rendering via `letterSpacing: 0` (forces
  /// per-glyph positioning) and enables OpenType font features for
  /// proper kerning and ligatures.
  static void _drawGlyph(Canvas canvas, GlyphDrawCommand cmd) {
    final style = TextStyle(
      fontFamily: (cmd.fontFamily != null && cmd.fontFamily!.isNotEmpty) ? cmd.fontFamily : null,
      fontSize: cmd.fontSize,
      color: cmd.color,
      fontStyle: cmd.italic ? FontStyle.italic : FontStyle.normal,
      fontWeight: cmd.bold ? FontWeight.bold : FontWeight.normal,
      letterSpacing: 0, // forces subpixel glyph positioning
      fontFeatures: const [
        FontFeature.enable('kern'), // pair kerning
        FontFeature.enable('liga'), // standard ligatures
      ],
    );

    final painter = TextPainter(
      text: TextSpan(text: cmd.text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(canvas, Offset(cmd.x, cmd.y));
  }

  /// Draw a line segment (fraction bar, radical bar, etc.).
  static void _drawLine(Canvas canvas, LineDrawCommand cmd) {
    final paint =
        Paint()
          ..color = cmd.color
          ..strokeWidth = cmd.thickness
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.butt
          ..isAntiAlias = true;

    canvas.drawLine(Offset(cmd.x1, cmd.y1), Offset(cmd.x2, cmd.y2), paint);
  }

  /// Draw a path (integral sign, radical symbol, brackets, etc.).
  ///
  /// When [PathDrawCommand.smooth] is true, the points are rendered as a
  /// smooth cubic Bézier spline using Catmull-Rom interpolation, producing
  /// fluid curves for integrals and radical symbols.
  static void _drawPathCmd(Canvas canvas, PathDrawCommand cmd) {
    if (cmd.points.isEmpty) return;

    final path = Path();
    path.moveTo(cmd.points.first.dx, cmd.points.first.dy);

    if (cmd.smooth && cmd.points.length >= 3) {
      // Catmull-Rom to cubic Bézier conversion.
      // For n points, generates smooth curves through interior points.
      final pts = cmd.points;
      for (int i = 0; i < pts.length - 1; i++) {
        final p0 = i > 0 ? pts[i - 1] : pts[i];
        final p1 = pts[i];
        final p2 = pts[i + 1];
        final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];

        // Convert Catmull-Rom segment [p1..p2] to cubic Bézier control points.
        final cp1 = Offset(
          p1.dx + (p2.dx - p0.dx) / 6.0,
          p1.dy + (p2.dy - p0.dy) / 6.0,
        );
        final cp2 = Offset(
          p2.dx - (p3.dx - p1.dx) / 6.0,
          p2.dy - (p3.dy - p1.dy) / 6.0,
        );
        path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
      }
    } else {
      for (int i = 1; i < cmd.points.length; i++) {
        path.lineTo(cmd.points[i].dx, cmd.points[i].dy);
      }
    }
    if (cmd.closed) path.close();

    final paint =
        Paint()
          ..color = cmd.color
          ..isAntiAlias = true;

    if (cmd.filled) {
      paint.style = PaintingStyle.fill;
    } else {
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = cmd.strokeWidth;
      paint.strokeCap = StrokeCap.round;
      paint.strokeJoin = StrokeJoin.round;
    }

    canvas.drawPath(path, paint);
  }

  /// Draw a placeholder when the layout is not yet computed.
  ///
  /// For tabular environments, renders a visual mini-table with cells.
  /// For other LaTeX, shows a clean label with the node name.
  static void drawPlaceholder(Canvas canvas, LatexNode node) {
    // Try to render as a visual table if it contains \begin{tabular}.
    if (node.latexSource.contains(r'\begin{tabular}')) {
      _drawTabularPreview(canvas, node);
      return;
    }

    // Fallback: clean label for non-tabular LaTeX.
    final bounds = node.localBounds;

    final bgPaint =
        Paint()
          ..color = const Color(0xE6252530)
          ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(8)),
      bgPaint,
    );

    final borderPaint =
        Paint()
          ..color = const Color(0xFF7C4DFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(8)),
      borderPaint,
    );

    // Show node name or "LaTeX" label.
    final label = node.name.isNotEmpty ? node.name : 'LaTeX Expression';

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFFBBBBCC),
          fontSize: node.fontSize * 0.7,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: bounds.width.clamp(100, 2000));

    tp.paint(
      canvas,
      Offset(
        bounds.left + (bounds.width - tp.width) / 2,
        bounds.top + (bounds.height - tp.height) / 2,
      ),
    );
  }

  /// Parse and draw a visual table from a \begin{tabular}...\end{tabular} source.
  static void _drawTabularPreview(Canvas canvas, LatexNode node) {
    // ── Parse rows from the LaTeX source ──
    final source = node.latexSource;
    final tabStart = source.indexOf(r'\begin{tabular}');
    final tabEnd = source.indexOf(r'\end{tabular}');
    if (tabStart < 0 || tabEnd < 0) return;

    // Extract the content between \begin{tabular}{...} and \end{tabular}
    var body = source.substring(tabStart, tabEnd);
    // Remove \begin{tabular}{...}
    final bodyStart = body.indexOf('}');
    if (bodyStart < 0) return;
    body = body.substring(bodyStart + 1);

    // Remove \hline, \cline{...}, \toprule, \midrule, \bottomrule directives
    body = body.replaceAll(r'\hline', '');
    body = body.replaceAll(RegExp(r'\\cline\{[^}]*\}'), '');
    body = body.replaceAll(r'\toprule', '');
    body = body.replaceAll(r'\midrule', '');
    body = body.replaceAll(r'\bottomrule', '');

    // Split rows by \\ (LaTeX row separator)
    final rawRows = body.split(r'\\');

    // ── Parse each cell, extracting text + merge spans ──
    // Cell data: text, colSpan, rowSpan
    final parsedRows = <List<({String text, int colSpan, int rowSpan})>>[];

    for (final row in rawRows) {
      final trimmed = row.trim();
      if (trimmed.isEmpty) continue;
      // Split cells by &
      final rawCells = trimmed.split('&');
      final cells = <({String text, int colSpan, int rowSpan})>[];

      for (var rawCell in rawCells) {
        rawCell = rawCell.trim();
        int colSpan = 1;
        int rowSpan = 1;
        String text = rawCell;

        // Parse \multicolumn{N}{align}{content}
        final mcMatch = RegExp(
          r'\\multicolumn\{(\d+)\}\{[^}]*\}\{(.*)\}$',
        ).firstMatch(text);
        if (mcMatch != null) {
          colSpan = int.tryParse(mcMatch.group(1)!) ?? 1;
          text = mcMatch.group(2)!;
        }

        // Parse \multirow{N}{*}{content} — may be nested inside multicolumn
        final mrMatch = RegExp(
          r'\\multirow\{(\d+)\}\{[^}]*\}\{(.*)\}$',
        ).firstMatch(text);
        if (mrMatch != null) {
          rowSpan = int.tryParse(mrMatch.group(1)!) ?? 1;
          text = mrMatch.group(2)!;
        }

        // Strip \textbf{...}
        final boldMatch = RegExp(r'\\textbf\{([^}]*)\}').firstMatch(text);
        if (boldMatch != null) {
          text = boldMatch.group(1)!;
        }

        cells.add((text: text.trim(), colSpan: colSpan, rowSpan: rowSpan));
      }

      parsedRows.add(cells);
    }

    if (parsedRows.isEmpty) return;

    // ── Detect header row ──
    final firstRowRaw = rawRows.firstWhere(
      (r) => r.trim().isNotEmpty,
      orElse: () => '',
    );
    final hasHeaders = firstRowRaw.contains(r'\textbf');

    // ── Build a grid occupied-map for merge spans ──
    final rowCount = parsedRows.length;
    final colCount = parsedRows
        .map((r) => r.fold<int>(0, (sum, c) => sum + c.colSpan))
        .reduce((a, b) => a > b ? a : b);

    // Grid: each cell stores (text, colSpan, rowSpan) or null if occupied.
    final grid = List.generate(
      rowCount,
      (_) => List<({String text, int colSpan, int rowSpan})?>.filled(
        colCount,
        null,
      ),
    );

    for (int r = 0; r < parsedRows.length; r++) {
      int gc = 0; // grid column pointer
      for (final cell in parsedRows[r]) {
        // Skip occupied cells (from previous rowSpan merges above).
        while (gc < colCount && grid[r][gc] != null) {
          gc++;
        }
        if (gc >= colCount) break;

        grid[r][gc] = cell;

        // Mark occupied cells for colSpan/rowSpan.
        for (int dr = 0; dr < cell.rowSpan; dr++) {
          for (int dc = 0; dc < cell.colSpan; dc++) {
            if (dr == 0 && dc == 0) continue; // master cell already set
            final tr = r + dr;
            final tc = gc + dc;
            if (tr < rowCount && tc < colCount) {
              // Mark as occupied (empty placeholder).
              grid[tr][tc] = (text: '', colSpan: 0, rowSpan: 0);
            }
          }
        }
        gc += cell.colSpan;
      }
    }

    // ── Layout constants ──
    final fontSize = (node.fontSize * 0.55).clamp(10.0, 18.0);
    const cellPadH = 10.0;
    const cellPadV = 6.0;
    final cellHeight = fontSize + cellPadV * 2;

    // Measure max column widths.
    final colWidths = List<double>.filled(colCount, 40.0);
    for (int r = 0; r < rowCount; r++) {
      for (int c = 0; c < colCount; c++) {
        final cell = grid[r][c];
        if (cell == null || cell.colSpan == 0) continue; // skip occupied
        if (cell.colSpan > 1) continue; // skip multi-column for width calc
        final tp = TextPainter(
          text: TextSpan(text: cell.text, style: TextStyle(fontSize: fontSize)),
          textDirection: TextDirection.ltr,
        )..layout();
        final needed = tp.width + cellPadH * 2;
        if (needed > colWidths[c]) colWidths[c] = needed;
      }
    }

    final tableWidth = colWidths.reduce((a, b) => a + b);
    final tableHeight = cellHeight * rowCount;

    // ── Update node bounds ──
    node.cachedLayout = LatexLayoutResult(
      commands: const [],
      size: Size(tableWidth, tableHeight),
    );

    const ox = 0.0;
    const oy = 0.0;

    // ── Draw background ──
    final tableRect = Rect.fromLTWH(ox, oy, tableWidth, tableHeight);
    final bgPaint =
        Paint()
          ..color = const Color(0xF0202028)
          ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(tableRect, const Radius.circular(6)),
      bgPaint,
    );

    // ── Draw cells ──
    final gridPaint =
        Paint()
          ..color = const Color(0x40FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;

    final headerBgPaint =
        Paint()
          ..color = const Color(0xFF3A3A50)
          ..style = PaintingStyle.fill;

    // Compute column X offsets.
    final colX = List<double>.filled(colCount + 1, 0);
    for (int c = 0; c < colCount; c++) {
      colX[c + 1] = colX[c] + colWidths[c];
    }

    for (int r = 0; r < rowCount; r++) {
      final y = oy + r * cellHeight;
      final isHeader = hasHeaders && r == 0;

      // Draw header background.
      if (isHeader) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(ox, y, tableWidth, cellHeight),
            topLeft: const Radius.circular(6),
            topRight: const Radius.circular(6),
          ),
          headerBgPaint,
        );
      }

      for (int c = 0; c < colCount; c++) {
        final cell = grid[r][c];
        if (cell == null) {
          // Empty unset cell — draw border.
          final cellRect = Rect.fromLTWH(
            ox + colX[c],
            y,
            colWidths[c],
            cellHeight,
          );
          canvas.drawRect(cellRect, gridPaint);
          continue;
        }

        if (cell.colSpan == 0 && cell.rowSpan == 0) {
          // Occupied by merge — don't draw border or text.
          continue;
        }

        // Master cell — compute merged rect.
        final mergedWidth = colX[c + cell.colSpan] - colX[c];
        final mergedHeight = cellHeight * cell.rowSpan;
        final cellRect = Rect.fromLTWH(
          ox + colX[c],
          y,
          mergedWidth,
          mergedHeight,
        );

        // Cell border.
        canvas.drawRect(cellRect, gridPaint);

        // Cell text — centered in merged area.
        if (cell.text.isNotEmpty) {
          final tp = TextPainter(
            text: TextSpan(
              text: cell.text,
              style: TextStyle(
                color:
                    isHeader
                        ? const Color(0xFFE0E0F0)
                        : const Color(0xFFBBBBCC),
                fontSize: fontSize,
                fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: mergedWidth - cellPadH);

          tp.paint(
            canvas,
            Offset(
              ox + colX[c] + (mergedWidth - tp.width) / 2,
              y + (mergedHeight - tp.height) / 2,
            ),
          );
        }
      }
    }

    // ── Outer border ──
    final outerPaint =
        Paint()
          ..color = const Color(0xFF7C4DFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(tableRect, const Radius.circular(6)),
      outerPaint,
    );
  }

  /// Draw a filled or stroked rectangle.
  static void _drawRect(Canvas canvas, RectDrawCommand cmd) {
    canvas.drawRect(
      Rect.fromLTWH(cmd.x, cmd.y, cmd.width, cmd.height),
      Paint()
        ..color = cmd.color
        ..style = cmd.filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..isAntiAlias = true,
    );
  }
}
