import 'package:flutter/material.dart';

import '../../core/nodes/tabular_node.dart';
import '../../core/tabular/cell_address.dart';
import '../../core/tabular/cell_node.dart';
import '../../core/tabular/cell_value.dart';
import '../../core/tabular/cell_number_formatter.dart';
import '../../core/tabular/conditional_format.dart';

/// 📊 TabularRenderer — renders a [TabularNode] onto a Flutter [Canvas].
///
/// Implements viewport culling: only visible rows and columns are drawn.
/// Cell text is rendered via cached [TextPainter] instances to avoid
/// expensive re-layout on every frame.
///
/// ## Rendering Pipeline
///
/// 1. Compute visible row/column range from viewport
/// 2. Draw grid background
/// 3. Draw column/row headers (if enabled)
/// 4. Draw grid lines
/// 5. Draw cell contents (text only for visible cells)
/// 6. Draw selection overlay
class TabularRenderer {
  /// Cached text painters, keyed by `"col:row"` string.
  ///
  /// Re-used across frames to avoid [TextPainter.layout()] every frame.
  static final Map<String, _CachedCellPainter> _cellPainterCache = {};

  /// Maximum cache size to prevent memory bloat.
  static const int _maxCacheSize = 2000;

  /// Draw the tabular node onto the canvas.
  ///
  /// [visibleRect] is the viewport in the node's local coordinate space
  /// (after inverse-transforming the world viewport).
  static void drawTabularNode(
    Canvas canvas,
    TabularNode node, {
    Rect? visibleRect,
  }) {
    final model = node.model;
    final cols = node.effectiveColumns;
    final rows = node.effectiveRows;

    if (cols <= 0 || rows <= 0) return;

    final bounds = node.localBounds;
    final effectiveVisibleRect = visibleRect ?? bounds;

    // Offsets for headers.
    final xOffset = node.showRowHeaders ? node.headerWidth : 0.0;
    final yOffset = node.showColumnHeaders ? node.headerHeight : 0.0;

    // 1. Background.
    _drawBackground(canvas, bounds, node);

    // 2. Compute visible range.
    final firstCol = _findFirstColumn(
      model,
      cols,
      effectiveVisibleRect.left - xOffset,
    );
    final lastCol = _findLastColumn(
      model,
      cols,
      effectiveVisibleRect.right - xOffset,
    );
    final firstRow = _findFirstRow(
      model,
      rows,
      effectiveVisibleRect.top - yOffset,
    );
    final lastRow = _findLastRow(
      model,
      rows,
      effectiveVisibleRect.bottom - yOffset,
    );

    // 3. Draw headers.
    if (node.showColumnHeaders) {
      _drawColumnHeaders(canvas, model, node, firstCol, lastCol, xOffset);
    }
    if (node.showRowHeaders) {
      _drawRowHeaders(canvas, model, node, firstRow, lastRow, yOffset);
    }

    // 4. Draw grid lines.
    _drawGridLines(
      canvas,
      model,
      node,
      firstCol,
      lastCol,
      firstRow,
      lastRow,
      xOffset,
      yOffset,
      bounds,
    );

    // 5. Draw merge region overlays (covers internal grid lines).
    _drawMergeOverlays(
      canvas,
      model,
      node,
      firstCol,
      lastCol,
      firstRow,
      lastRow,
      xOffset,
      yOffset,
    );

    // 6. Draw cell contents.
    _drawCells(
      canvas,
      model,
      node,
      firstCol,
      lastCol,
      firstRow,
      lastRow,
      xOffset,
      yOffset,
    );

    // 6. Draw frozen panes overlay.
    _drawFrozenPanes(canvas, model, node, xOffset, yOffset, bounds);
  }

  /// Clear the text painter cache (call on node disposal or scene change).
  static void clearCache() {
    _cellPainterCache.clear();
  }

  // =========================================================================
  // Background
  // =========================================================================

  static void _drawBackground(Canvas canvas, Rect bounds, TabularNode node) {
    final paint =
        Paint()
          ..color = node.backgroundColor
          ..style = PaintingStyle.fill;
    canvas.drawRect(bounds, paint);
  }

  // =========================================================================
  // Column / Row finding (viewport culling)
  // =========================================================================

  static int _findFirstColumn(dynamic model, int cols, double x) {
    double offset = 0;
    for (int c = 0; c < cols; c++) {
      final w = model.getColumnWidth(c) as double;
      if (offset + w > x) return c;
      offset += w;
    }
    return 0;
  }

  static int _findLastColumn(dynamic model, int cols, double x) {
    double offset = 0;
    for (int c = 0; c < cols; c++) {
      offset += model.getColumnWidth(c) as double;
      if (offset >= x) return c;
    }
    return cols - 1;
  }

  static int _findFirstRow(dynamic model, int rows, double y) {
    double offset = 0;
    for (int r = 0; r < rows; r++) {
      final h = model.getRowHeight(r) as double;
      if (offset + h > y) return r;
      offset += h;
    }
    return 0;
  }

  static int _findLastRow(dynamic model, int rows, double y) {
    double offset = 0;
    for (int r = 0; r < rows; r++) {
      offset += model.getRowHeight(r) as double;
      if (offset >= y) return r;
    }
    return rows - 1;
  }

  // =========================================================================
  // Headers
  // =========================================================================

  static void _drawColumnHeaders(
    Canvas canvas,
    dynamic model,
    TabularNode node,
    int firstCol,
    int lastCol,
    double xOffset,
  ) {
    final headerPaint =
        Paint()
          ..color = const Color(0xFF2A2A2A)
          ..style = PaintingStyle.fill;

    double x = xOffset;
    for (int c = 0; c < firstCol; c++) {
      x += model.getColumnWidth(c) as double;
    }

    for (int c = firstCol; c <= lastCol; c++) {
      final w = model.getColumnWidth(c) as double;
      final rect = Rect.fromLTWH(x, 0, w, node.headerHeight);

      // Background.
      canvas.drawRect(rect, headerPaint);

      // Label.
      final addr = CellAddress(c, 0);
      final label = addr.columnLabel;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFFAAAAAA),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset(x + (w - tp.width) / 2, (node.headerHeight - tp.height) / 2),
      );

      x += w;
    }
  }

  static void _drawRowHeaders(
    Canvas canvas,
    dynamic model,
    TabularNode node,
    int firstRow,
    int lastRow,
    double yOffset,
  ) {
    final headerPaint =
        Paint()
          ..color = const Color(0xFF2A2A2A)
          ..style = PaintingStyle.fill;

    double y = yOffset;
    for (int r = 0; r < firstRow; r++) {
      y += model.getRowHeight(r) as double;
    }

    for (int r = firstRow; r <= lastRow; r++) {
      final h = model.getRowHeight(r) as double;
      final rect = Rect.fromLTWH(0, y, node.headerWidth, h);

      // Background.
      canvas.drawRect(rect, headerPaint);

      // Label (1-indexed row number).
      final label = '${r + 1}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFFAAAAAA),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset((node.headerWidth - tp.width) / 2, y + (h - tp.height) / 2),
      );

      y += h;
    }
  }

  // =========================================================================
  // Grid lines
  // =========================================================================

  static void _drawGridLines(
    Canvas canvas,
    dynamic model,
    TabularNode node,
    int firstCol,
    int lastCol,
    int firstRow,
    int lastRow,
    double xOffset,
    double yOffset,
    Rect bounds,
  ) {
    final linePaint =
        Paint()
          ..color = node.gridLineColor
          ..strokeWidth = node.gridLineWidth
          ..style = PaintingStyle.stroke
          ..isAntiAlias = false;

    // Pre-compute column X positions.
    final colX = <double>[];
    double cx = xOffset;
    for (int c = 0; c < firstCol; c++) {
      cx += model.getColumnWidth(c) as double;
    }
    for (int c = firstCol; c <= lastCol + 1; c++) {
      colX.add(cx);
      if (c <= lastCol) cx += model.getColumnWidth(c) as double;
    }

    // Pre-compute row Y positions.
    final rowY = <double>[];
    double ry = yOffset;
    for (int r = 0; r < firstRow; r++) {
      ry += model.getRowHeight(r) as double;
    }
    for (int r = firstRow; r <= lastRow + 1; r++) {
      rowY.add(ry);
      if (r <= lastRow) ry += model.getRowHeight(r) as double;
    }

    // Helper to get cell borders (null format = default = all borders).
    CellBorders _getBorders(int col, int row) {
      final cell = model.getCell(CellAddress(col, row));
      return cell?.format?.borders ?? CellBorders.all;
    }

    // Draw vertical line segments (between columns).
    for (int ci = 0; ci < colX.length; ci++) {
      final c = firstCol + ci;
      final x = colX[ci];

      for (int ri = 0; ri < rowY.length - 1; ri++) {
        final r = firstRow + ri;
        final y1 = rowY[ri];
        final y2 = rowY[ri + 1];

        if (c == firstCol) {
          // Left edge of table: draw if edge cell has .left border.
          if (_getBorders(c, r).left) {
            canvas.drawLine(Offset(x, y1), Offset(x, y2), linePaint);
          }
        } else if (c == lastCol + 1) {
          // Right edge of table: draw if edge cell has .right border.
          if (_getBorders(c - 1, r).right) {
            canvas.drawLine(Offset(x, y1), Offset(x, y2), linePaint);
          }
        } else {
          // Between col c-1 and col c: draw if c-1.right or c.left is true.
          final leftBorders = _getBorders(c - 1, r);
          final rightBorders = _getBorders(c, r);
          if (leftBorders.right || rightBorders.left) {
            canvas.drawLine(Offset(x, y1), Offset(x, y2), linePaint);
          }
        }
      }
    }

    // Draw horizontal line segments (between rows).
    for (int ri = 0; ri < rowY.length; ri++) {
      final r = firstRow + ri;
      final y = rowY[ri];

      for (int ci = 0; ci < colX.length - 1; ci++) {
        final c = firstCol + ci;
        final x1 = colX[ci];
        final x2 = colX[ci + 1];

        if (r == firstRow) {
          // Top edge of table: draw if edge cell has .top border.
          if (_getBorders(c, r).top) {
            canvas.drawLine(Offset(x1, y), Offset(x2, y), linePaint);
          }
        } else if (r == lastRow + 1) {
          // Bottom edge of table: draw if edge cell has .bottom border.
          if (_getBorders(c, r - 1).bottom) {
            canvas.drawLine(Offset(x1, y), Offset(x2, y), linePaint);
          }
        } else {
          // Between row r-1 and row r: draw if r-1.bottom or r.top is true.
          final topBorders = _getBorders(c, r - 1);
          final bottomBorders = _getBorders(c, r);
          if (topBorders.bottom || bottomBorders.top) {
            canvas.drawLine(Offset(x1, y), Offset(x2, y), linePaint);
          }
        }
      }
    }
  }

  // =========================================================================
  // Merge region overlays — fills merged areas to hide internal grid lines
  // =========================================================================

  static void _drawMergeOverlays(
    Canvas canvas,
    dynamic model,
    TabularNode node,
    int firstCol,
    int lastCol,
    int firstRow,
    int lastRow,
    double xOffset,
    double yOffset,
  ) {
    final regions = node.mergeManager.regions;
    if (regions.isEmpty) return;

    // Pre-compute column X positions.
    final colXMap = <int, double>{};
    double cx = xOffset;
    for (int c = 0; c <= lastCol; c++) {
      if (c >= firstCol) colXMap[c] = cx;
      cx += model.getColumnWidth(c) as double;
    }

    // Pre-compute row Y positions.
    final rowYMap = <int, double>{};
    double ry = yOffset;
    for (int r = 0; r <= lastRow; r++) {
      if (r >= firstRow) rowYMap[r] = ry;
      ry += model.getRowHeight(r) as double;
    }

    final bgPaint =
        Paint()
          ..color = node.backgroundColor
          ..style = PaintingStyle.fill;

    final borderPaint =
        Paint()
          ..color = node.gridLineColor
          ..strokeWidth = node.gridLineWidth
          ..style = PaintingStyle.stroke
          ..isAntiAlias = false;

    for (final region in regions) {
      // Skip regions fully outside the visible range.
      if (region.endColumn < firstCol || region.startColumn > lastCol) continue;
      if (region.endRow < firstRow || region.startRow > lastRow) continue;

      // Compute the pixel rect for this region.
      final startCol = region.startColumn;
      final startRow = region.startRow;

      // X position of the region start.
      double regionX = xOffset;
      for (int c = 0; c < startCol; c++) {
        regionX += model.getColumnWidth(c) as double;
      }
      // Y position of the region start.
      double regionY = yOffset;
      for (int r = 0; r < startRow; r++) {
        regionY += model.getRowHeight(r) as double;
      }
      // Width = sum of column widths in region.
      double regionW = 0;
      for (int c = region.startColumn; c <= region.endColumn; c++) {
        regionW += model.getColumnWidth(c) as double;
      }
      // Height = sum of row heights in region.
      double regionH = 0;
      for (int r = region.startRow; r <= region.endRow; r++) {
        regionH += model.getRowHeight(r) as double;
      }

      final rect = Rect.fromLTWH(regionX, regionY, regionW, regionH);

      // Fill with background to cover internal grid lines.
      canvas.drawRect(rect, bgPaint);

      // Check if the master cell has a custom background color.
      final masterAddr = CellAddress(region.startColumn, region.startRow);
      final masterCell = model.getCell(masterAddr);
      if (masterCell != null && masterCell.format?.backgroundColor != null) {
        final cellBgPaint =
            Paint()
              ..color = masterCell.format!.backgroundColor!
              ..style = PaintingStyle.fill;
        canvas.drawRect(rect, cellBgPaint);
      }

      // Draw border around the merged region.
      canvas.drawRect(rect, borderPaint);
    }
  }

  // =========================================================================
  // Cell contents
  // =========================================================================

  static void _drawCells(
    Canvas canvas,
    dynamic model,
    TabularNode node,
    int firstCol,
    int lastCol,
    int firstRow,
    int lastRow,
    double xOffset,
    double yOffset,
  ) {
    // Pre-compute row Y offsets.
    final rowYs = <double>[];
    double y = yOffset;
    for (int r = 0; r < firstRow; r++) {
      y += model.getRowHeight(r) as double;
    }
    for (int r = firstRow; r <= lastRow; r++) {
      rowYs.add(y);
      y += model.getRowHeight(r) as double;
    }

    // Pre-compute column X offsets.
    final colXs = <double>[];
    double x = xOffset;
    for (int c = 0; c < firstCol; c++) {
      x += model.getColumnWidth(c) as double;
    }
    for (int c = firstCol; c <= lastCol; c++) {
      colXs.add(x);
      x += model.getColumnWidth(c) as double;
    }

    final cellPadding = 4.0;

    for (int ri = 0; ri < rowYs.length; ri++) {
      final r = firstRow + ri;
      for (int ci = 0; ci < colXs.length; ci++) {
        final c = firstCol + ci;
        final addr = CellAddress(c, r);
        final cell = model.getCell(addr);
        if (cell == null) continue;

        final displayValue = cell.displayValue;
        if (displayValue is EmptyValue) continue;

        // Skip cells hidden by merge regions.
        if (node.mergeManager.isHiddenByMerge(addr)) continue;

        final cellX = colXs[ci];
        final cellY = rowYs[ri];

        // For merged cells, compute expanded bounds.
        double cellW;
        double cellH;
        final mergeRegion = node.mergeManager.getRegion(addr);
        if (mergeRegion != null && node.mergeManager.isMasterCell(addr)) {
          // Sum widths and heights of the merged region.
          cellW = 0;
          for (
            int mc = mergeRegion.startColumn;
            mc <= mergeRegion.endColumn;
            mc++
          ) {
            cellW += model.getColumnWidth(mc) as double;
          }
          cellH = 0;
          for (int mr = mergeRegion.startRow; mr <= mergeRegion.endRow; mr++) {
            cellH += model.getRowHeight(mr) as double;
          }
        } else {
          cellW = model.getColumnWidth(c) as double;
          cellH = model.getRowHeight(r) as double;
        }

        // Resolve effective format: static cell format + conditional overrides.
        final staticFormat = cell.format;
        final condFormat = node.model.conditionalFormats.getEffectiveFormat(
          addr,
          displayValue,
        );
        final effectiveFormat = _mergeFormats(staticFormat, condFormat);

        // Cell background (if format specifies one).
        if (effectiveFormat?.backgroundColor != null) {
          final bgPaint =
              Paint()
                ..color = effectiveFormat!.backgroundColor!
                ..style = PaintingStyle.fill;
          canvas.drawRect(Rect.fromLTWH(cellX, cellY, cellW, cellH), bgPaint);
        }

        // Cell text.
        String text;
        if (displayValue is NumberValue &&
            effectiveFormat?.numberFormat != null) {
          text = CellNumberFormatter.format(
            displayValue.value,
            effectiveFormat!.numberFormat,
          );
        } else {
          text = displayValue.displayString;
        }
        if (text.isEmpty) continue;

        final cacheKey = '${node.id.value}:$c:$r';
        final contentHash = Object.hash(
          text,
          effectiveFormat?.fontSize,
          effectiveFormat?.bold,
          effectiveFormat?.italic,
          effectiveFormat?.textColor,
          effectiveFormat?.backgroundColor,
        );

        _CachedCellPainter? cached = _cellPainterCache[cacheKey];
        TextPainter tp;
        if (cached != null && cached.contentHash == contentHash) {
          tp = cached.painter;
        } else {
          // Evict oldest entries if cache is too large.
          if (_cellPainterCache.length >= _maxCacheSize) {
            final keysToRemove = _cellPainterCache.keys.take(100).toList();
            for (final k in keysToRemove) {
              _cellPainterCache.remove(k);
            }
          }

          final isError = displayValue is ErrorValue;
          final textColor =
              isError
                  ? const Color(0xFFFF4444)
                  : (effectiveFormat?.textColor ?? const Color(0xFFE0E0E0));
          final fontSize = effectiveFormat?.fontSize ?? 13.0;

          tp = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                color: textColor,
                fontSize: fontSize,
                fontWeight:
                    (effectiveFormat?.bold ?? false)
                        ? FontWeight.bold
                        : FontWeight.normal,
                fontStyle:
                    (effectiveFormat?.italic ?? false)
                        ? FontStyle.italic
                        : FontStyle.normal,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: cellW - cellPadding * 2);

          _cellPainterCache[cacheKey] = _CachedCellPainter(tp, contentHash);
        }

        // Position based on alignment (explicit or smart default).
        final explicitAlign = effectiveFormat?.horizontalAlign;
        final effectiveAlign =
            explicitAlign ??
            (displayValue is NumberValue
                ? CellAlignment.right
                : CellAlignment.left);

        double textX = cellX + cellPadding; // default left
        switch (effectiveAlign) {
          case CellAlignment.right:
            textX = cellX + cellW - cellPadding - tp.width;
          case CellAlignment.center:
            textX = cellX + (cellW - tp.width) / 2;
          case CellAlignment.left:
            textX = cellX + cellPadding;
        }
        final textY = cellY + (cellH - tp.height) / 2;

        // Clip to cell bounds.
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(cellX, cellY, cellW, cellH));
        tp.paint(canvas, Offset(textX, textY));
        canvas.restore();

        // Validation error indicator — red triangle in top-right corner.
        if (node.model.hasValidation(addr) &&
            !node.model.validateCell(addr, displayValue)) {
          final triangleSize = 6.0;
          final path =
              Path()
                ..moveTo(cellX + cellW - triangleSize, cellY)
                ..lineTo(cellX + cellW, cellY)
                ..lineTo(cellX + cellW, cellY + triangleSize)
                ..close();
          canvas.drawPath(
            path,
            Paint()
              ..color = const Color(0xFFFF4444)
              ..style = PaintingStyle.fill,
          );
        }
      }
    }
  }

  /// Merge a static cell format with a conditional format overlay.
  ///
  /// Returns the effective [CellFormat] to use for rendering.
  /// If both are null, returns null. Conditional format properties
  /// override static format properties.
  static CellFormat? _mergeFormats(CellFormat? staticFmt, CellFormat? condFmt) {
    if (staticFmt == null && condFmt == null) return null;
    if (condFmt == null) return staticFmt;
    if (staticFmt == null) return condFmt;

    return CellFormat(
      numberFormat: condFmt.numberFormat ?? staticFmt.numberFormat,
      horizontalAlign: condFmt.horizontalAlign ?? staticFmt.horizontalAlign,
      verticalAlign: condFmt.verticalAlign ?? staticFmt.verticalAlign,
      fontSize: condFmt.fontSize ?? staticFmt.fontSize,
      textColor: condFmt.textColor ?? staticFmt.textColor,
      backgroundColor: condFmt.backgroundColor ?? staticFmt.backgroundColor,
      bold: condFmt.bold ?? staticFmt.bold,
      italic: condFmt.italic ?? staticFmt.italic,
    );
  }

  // =========================================================================
  // Frozen panes
  // =========================================================================

  /// Draw frozen row/column panes on top of the scrollable grid.
  ///
  /// Frozen rows/columns are re-drawn over the scrolled content,
  /// providing the "pinned header" effect common in spreadsheet apps.
  static void _drawFrozenPanes(
    Canvas canvas,
    dynamic model,
    TabularNode node,
    double xOffset,
    double yOffset,
    Rect bounds,
  ) {
    final frozenCols = model.frozenColumns as int;
    final frozenRows = model.frozenRows as int;

    if (frozenCols <= 0 && frozenRows <= 0) return;

    final separatorPaint =
        Paint()
          ..color = const Color(0xFF4A90D9)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

    // Draw frozen columns (left panel).
    if (frozenCols > 0) {
      double frozenWidth = 0;
      for (int c = 0; c < frozenCols; c++) {
        frozenWidth += model.getColumnWidth(c) as double;
      }

      // Background to cover scrolled content.
      final frozenRect = Rect.fromLTWH(
        xOffset,
        yOffset,
        frozenWidth,
        bounds.height - yOffset,
      );
      canvas.save();
      canvas.clipRect(frozenRect);

      // Fill background.
      final bgPaint =
          Paint()
            ..color = node.backgroundColor
            ..style = PaintingStyle.fill;
      canvas.drawRect(frozenRect, bgPaint);

      // Draw cells in frozen columns.
      _drawCells(
        canvas,
        model,
        node,
        0,
        frozenCols - 1,
        0,
        node.effectiveRows - 1,
        xOffset,
        yOffset,
      );
      canvas.restore();

      // Separator line.
      final sepX = xOffset + frozenWidth;
      canvas.drawLine(
        Offset(sepX, yOffset),
        Offset(sepX, bounds.bottom),
        separatorPaint,
      );
    }

    // Draw frozen rows (top panel).
    if (frozenRows > 0) {
      double frozenHeight = 0;
      for (int r = 0; r < frozenRows; r++) {
        frozenHeight += model.getRowHeight(r) as double;
      }

      final frozenRect = Rect.fromLTWH(
        xOffset,
        yOffset,
        bounds.width - xOffset,
        frozenHeight,
      );
      canvas.save();
      canvas.clipRect(frozenRect);

      final bgPaint =
          Paint()
            ..color = node.backgroundColor
            ..style = PaintingStyle.fill;
      canvas.drawRect(frozenRect, bgPaint);

      _drawCells(
        canvas,
        model,
        node,
        0,
        node.effectiveColumns - 1,
        0,
        frozenRows - 1,
        xOffset,
        yOffset,
      );
      canvas.restore();

      // Separator line.
      final sepY = yOffset + frozenHeight;
      canvas.drawLine(
        Offset(xOffset, sepY),
        Offset(bounds.right, sepY),
        separatorPaint,
      );
    }
  }
}

/// Cached [TextPainter] for a cell, with content hash for invalidation.
class _CachedCellPainter {
  final TextPainter painter;
  final int contentHash;
  const _CachedCellPainter(this.painter, this.contentHash);
}
