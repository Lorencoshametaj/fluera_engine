import 'package:flutter/material.dart';

import '../../core/nodes/tabular_node.dart';
import '../../core/tabular/cell_address.dart';
import '../../core/tabular/cell_node.dart';
import '../../core/tabular/cell_value.dart';
import '../../core/tabular/cell_number_formatter.dart';
import '../../core/tabular/conditional_format.dart';
import '../../core/tabular/spreadsheet_model.dart';
import '../../core/tabular/tabular_hit_test_utils.dart';

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

  // ── Pre-allocated Paint Objects (Zero-Allocation Rendering) ──────
  static final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _headerPaint =
      Paint()
        ..color = const Color(0xFF2A2A2A)
        ..style = PaintingStyle.fill;
  static final Paint _gridLinePaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..isAntiAlias = false;
  static final Paint _cellBgPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _validationPaint =
      Paint()
        ..color = const Color(0xFFFF4444)
        ..style = PaintingStyle.fill;
  static final Paint _frozenSeparatorPaint =
      Paint()
        ..color = const Color(0xFF4A90D9)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

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

    // Early bail: table is entirely off-viewport.
    if (visibleRect != null && !visibleRect.overlaps(bounds)) return;

    final effectiveVisibleRect = visibleRect ?? bounds;

    // Offsets for headers.
    final xOffset = node.showRowHeaders ? node.headerWidth : 0.0;
    final yOffset = node.showColumnHeaders ? node.headerHeight : 0.0;

    // ── LOD: compute effective screen-space cell height ───────────────
    // When the visible rect is much larger than the table bounds, the
    // table is zoomed out and each cell is tiny on screen.
    //
    // Tiers:
    //   screenCellH >= 8  → full render (text, formatting, validation)
    //   4 <= screenCellH < 8 → backgrounds only (skip text)
    //   screenCellH < 4  → grid only (skip cells, merges, frozen panes)
    final avgCellH = rows > 0 ? model.rowOffset(rows) / rows : 24.0;
    final viewportScale = bounds.height / effectiveVisibleRect.height;
    final screenCellH = avgCellH * viewportScale;
    final skipText = screenCellH < 8.0;
    final gridOnly = screenCellH < 4.0;

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

    // 3. Draw headers (skip at low LOD — too small to read).
    if (!skipText) {
      if (node.showColumnHeaders) {
        _drawColumnHeaders(canvas, model, node, firstCol, lastCol, xOffset);
      }
      if (node.showRowHeaders) {
        _drawRowHeaders(canvas, model, node, firstRow, lastRow, yOffset);
      }
    }

    // 4. Draw grid lines (always visible — gives shape at any zoom).
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

    // LOD: grid-only mode — skip everything below.
    if (gridOnly) return;

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

    // 6. Draw cell contents (skip text at mid-LOD).
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
      skipText: skipText,
    );

    // 7. Draw frozen panes overlay (skip at low LOD).
    if (!skipText) {
      _drawFrozenPanes(canvas, model, node, xOffset, yOffset, bounds);
    }
  }

  /// Clear the text painter cache (call on node disposal or scene change).
  static void clearCache() {
    _cellPainterCache.clear();
  }

  // =========================================================================
  // Background
  // =========================================================================

  static void _drawBackground(Canvas canvas, Rect bounds, TabularNode node) {
    _bgPaint.color = node.backgroundColor;
    canvas.drawRect(bounds, _bgPaint);
  }

  // =========================================================================
  // Column / Row finding (viewport culling)
  // =========================================================================

  /// Binary search for the first column whose right edge is past [x].
  static int _findFirstColumn(SpreadsheetModel model, int cols, double x) {
    if (cols <= 0) return 0;
    int lo = 0, hi = cols - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final rightEdge = model.columnOffset(mid) + model.getColumnWidth(mid);
      if (rightEdge <= x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Binary search for the last column whose left edge is before [x].
  static int _findLastColumn(SpreadsheetModel model, int cols, double x) {
    if (cols <= 0) return 0;
    int lo = 0, hi = cols - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (model.columnOffset(mid) < x) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Binary search for the first row whose bottom edge is past [y].
  static int _findFirstRow(SpreadsheetModel model, int rows, double y) {
    if (rows <= 0) return 0;
    int lo = 0, hi = rows - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final bottomEdge = model.rowOffset(mid) + model.getRowHeight(mid);
      if (bottomEdge <= y) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Binary search for the last row whose top edge is before [y].
  static int _findLastRow(SpreadsheetModel model, int rows, double y) {
    if (rows <= 0) return 0;
    int lo = 0, hi = rows - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (model.rowOffset(mid) < y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  // =========================================================================
  // Headers
  // =========================================================================

  static void _drawColumnHeaders(
    Canvas canvas,
    SpreadsheetModel model,
    TabularNode node,
    int firstCol,
    int lastCol,
    double xOffset,
  ) {
    double x = xOffset + model.columnOffset(firstCol);

    for (int c = firstCol; c <= lastCol; c++) {
      final w = model.getColumnWidth(c);
      final rect = Rect.fromLTWH(x, 0, w, node.headerHeight);

      // Background.
      canvas.drawRect(rect, _headerPaint);

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
    SpreadsheetModel model,
    TabularNode node,
    int firstRow,
    int lastRow,
    double yOffset,
  ) {
    double y = yOffset + model.rowOffset(firstRow);

    for (int r = firstRow; r <= lastRow; r++) {
      final h = model.getRowHeight(r);
      final rect = Rect.fromLTWH(0, y, node.headerWidth, h);

      // Background.
      canvas.drawRect(rect, _headerPaint);

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
    SpreadsheetModel model,
    TabularNode node,
    int firstCol,
    int lastCol,
    int firstRow,
    int lastRow,
    double xOffset,
    double yOffset,
    Rect bounds,
  ) {
    _gridLinePaint
      ..color = node.gridLineColor
      ..strokeWidth = node.gridLineWidth;

    // Pre-compute column X positions via O(1) offsets.
    final colX = <double>[];
    for (int c = firstCol; c <= lastCol + 1; c++) {
      colX.add(xOffset + model.columnOffset(c));
    }

    // Pre-compute row Y positions via O(1) offsets.
    final rowY = <double>[];
    for (int r = firstRow; r <= lastRow + 1; r++) {
      rowY.add(yOffset + model.rowOffset(r));
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
            canvas.drawLine(Offset(x, y1), Offset(x, y2), _gridLinePaint);
          }
        } else if (c == lastCol + 1) {
          // Right edge of table: draw if edge cell has .right border.
          if (_getBorders(c - 1, r).right) {
            canvas.drawLine(Offset(x, y1), Offset(x, y2), _gridLinePaint);
          }
        } else {
          // Between col c-1 and col c: draw if c-1.right or c.left is true.
          final leftBorders = _getBorders(c - 1, r);
          final rightBorders = _getBorders(c, r);
          if (leftBorders.right || rightBorders.left) {
            canvas.drawLine(Offset(x, y1), Offset(x, y2), _gridLinePaint);
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
            canvas.drawLine(Offset(x1, y), Offset(x2, y), _gridLinePaint);
          }
        } else if (r == lastRow + 1) {
          // Bottom edge of table: draw if edge cell has .bottom border.
          if (_getBorders(c, r - 1).bottom) {
            canvas.drawLine(Offset(x1, y), Offset(x2, y), _gridLinePaint);
          }
        } else {
          // Between row r-1 and row r: draw if r-1.bottom or r.top is true.
          final topBorders = _getBorders(c, r - 1);
          final bottomBorders = _getBorders(c, r);
          if (topBorders.bottom || bottomBorders.top) {
            canvas.drawLine(Offset(x1, y), Offset(x2, y), _gridLinePaint);
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
    SpreadsheetModel model,
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

    // Pre-compute column X positions via O(1) offsets.
    final colXMap = <int, double>{};
    for (int c = firstCol; c <= lastCol; c++) {
      colXMap[c] = xOffset + model.columnOffset(c);
    }

    // Pre-compute row Y positions via O(1) offsets.
    final rowYMap = <int, double>{};
    for (int r = firstRow; r <= lastRow; r++) {
      rowYMap[r] = yOffset + model.rowOffset(r);
    }

    _bgPaint.color = node.backgroundColor;
    _gridLinePaint
      ..color = node.gridLineColor
      ..strokeWidth = node.gridLineWidth;

    for (final region in regions) {
      // Skip regions fully outside the visible range.
      if (region.endColumn < firstCol || region.startColumn > lastCol) continue;
      if (region.endRow < firstRow || region.startRow > lastRow) continue;

      // Compute the pixel rect for this region.
      final startCol = region.startColumn;
      final startRow = region.startRow;

      // Use O(1) offset lookups for region bounds.
      final regionX = xOffset + model.columnOffset(startCol);
      final regionY = yOffset + model.rowOffset(startRow);
      final regionW =
          model.columnOffset(region.endColumn + 1) -
          model.columnOffset(region.startColumn);
      final regionH =
          model.rowOffset(region.endRow + 1) - model.rowOffset(region.startRow);

      final rect = Rect.fromLTWH(regionX, regionY, regionW, regionH);

      // Fill with background to cover internal grid lines.
      canvas.drawRect(rect, _bgPaint);

      // Check if the master cell has a custom background color.
      final masterAddr = CellAddress(region.startColumn, region.startRow);
      final masterCell = model.getCell(masterAddr);
      if (masterCell != null && masterCell.format?.backgroundColor != null) {
        _cellBgPaint.color = masterCell.format!.backgroundColor!;
        canvas.drawRect(rect, _cellBgPaint);
      }

      // Draw border around the merged region.
      canvas.drawRect(rect, _gridLinePaint);
    }
  }

  // =========================================================================
  // Cell contents
  // =========================================================================

  static void _drawCells(
    Canvas canvas,
    SpreadsheetModel model,
    TabularNode node,
    int firstCol,
    int lastCol,
    int firstRow,
    int lastRow,
    double xOffset,
    double yOffset, {
    bool skipText = false,
  }) {
    // Pre-compute row Y offsets via O(1) lookups.
    final rowYs = <double>[];
    for (int r = firstRow; r <= lastRow; r++) {
      rowYs.add(yOffset + model.rowOffset(r));
    }

    // Pre-compute column X offsets via O(1) lookups.
    final colXs = <double>[];
    for (int c = firstCol; c <= lastCol; c++) {
      colXs.add(xOffset + model.columnOffset(c));
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
          // O(1) via offset subtraction instead of summing each width/height.
          cellW =
              model.columnOffset(mergeRegion.endColumn + 1) -
              model.columnOffset(mergeRegion.startColumn);
          cellH =
              model.rowOffset(mergeRegion.endRow + 1) -
              model.rowOffset(mergeRegion.startRow);
        } else {
          cellW = model.getColumnWidth(c);
          cellH = model.getRowHeight(r);
        }

        // Resolve effective format: static cell format + conditional overrides.
        final staticFormat = cell.format;
        final condFormat = node.model.conditionalFormats.getEffectiveFormat(
          addr,
          displayValue,
        );
        final effectiveFormat = CellFormat.merge(staticFormat, condFormat);

        // Cell background (if format specifies one).
        if (effectiveFormat?.backgroundColor != null) {
          _cellBgPaint.color = effectiveFormat!.backgroundColor!;
          canvas.drawRect(
            Rect.fromLTWH(cellX, cellY, cellW, cellH),
            _cellBgPaint,
          );
        }

        // LOD: skip text rendering at mid-zoom — cells are too small to read.
        if (skipText) continue;

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
          canvas.drawPath(path, _validationPaint);
        }
      }
    }
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
    SpreadsheetModel model,
    TabularNode node,
    double xOffset,
    double yOffset,
    Rect bounds,
  ) {
    final frozenCols = model.frozenColumns;
    final frozenRows = model.frozenRows;

    if (frozenCols <= 0 && frozenRows <= 0) return;

    // Draw frozen columns (left panel).
    if (frozenCols > 0) {
      // O(1) via prefix-sum offset.
      final frozenWidth = model.columnOffset(frozenCols);

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
      _bgPaint.color = node.backgroundColor;
      canvas.drawRect(frozenRect, _bgPaint);

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
        _frozenSeparatorPaint,
      );
    }

    // Draw frozen rows (top panel).
    if (frozenRows > 0) {
      // O(1) via prefix-sum offset.
      final frozenHeight = model.rowOffset(frozenRows);

      final frozenRect = Rect.fromLTWH(
        xOffset,
        yOffset,
        bounds.width - xOffset,
        frozenHeight,
      );
      canvas.save();
      canvas.clipRect(frozenRect);

      _bgPaint.color = node.backgroundColor;
      canvas.drawRect(frozenRect, _bgPaint);

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
        _frozenSeparatorPaint,
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
