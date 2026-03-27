import 'package:flutter/material.dart';
import '../../core/engine_scope.dart';
import '../../core/nodes/latex_node.dart';
import '../../core/nodes/tabular_node.dart';
import '../../core/tabular/cell_address.dart';
import '../../layers/layer_controller.dart';
import '../../tools/tabular_interaction_tool.dart';
import '../../canvas/infinite_canvas_controller.dart';

/// Painter for the Bidirectional Traceability logic.
/// Highlights cells referenced by a selected LatexNode.
/// Highlights LatexNodes that reference a selected Tabular cell.
class LatexProvenanceOverlayPainter extends CustomPainter {
  final LayerController layerController;
  final TabularInteractionTool tabularTool;
  final Set<String> selectedNodeIds;
  final Offset canvasOffset;
  final double canvasScale;

  /// Cached painted rects for tap hit-testing (populated during paint).
  final List<_HighlightTarget> _paintedTargets = [];

  LatexProvenanceOverlayPainter({
    required this.layerController,
    required this.tabularTool,
    required this.selectedNodeIds,
    required this.canvasOffset,
    required this.canvasScale,
  }) : super(repaint: layerController);

  /// Hit-test a screen-space tap position and return the target node/cell
  /// bounds in canvas space, or null if nothing was tapped.
  Offset? hitTestTarget(Offset tapPosition) {
    for (final target in _paintedTargets) {
      if (target.screenRect.contains(tapPosition)) {
        return target.canvasCenter;
      }
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintedTargets.clear();
    if (!EngineScope.hasScope) return;
    final bridge = EngineScope.current.tabularModule?.tabularLatexBridge;
    if (bridge == null) return;

    // CASE 1: A LatexNode is selected -> Highlight the cells it references
    if (selectedNodeIds.length == 1) {
      final firstNode = layerController.findNodeById(selectedNodeIds.first);
      if (firstNode is LatexNode) {
        final referencedCells = bridge.getCellsReferencedBy(
          firstNode.id.toString(),
        );

        if (referencedCells.isNotEmpty) {
          _drawReferencedCells(canvas, referencedCells);
        }
      }
    }

    // CASE 2: A TabularNode cell is selected -> Highlight the LatexNodes depending on it
    if (tabularTool.hasCellSelection) {
      final range = tabularTool.selectedRange;
      if (range != null) {
        final latexNodeIds = <String>{};
        for (final addr in range.addresses) {
          latexNodeIds.addAll(bridge.getLatexNodesReferencingCell(addr));
        }

        if (latexNodeIds.isNotEmpty) {
          _drawDependentLatexNodes(canvas, latexNodeIds);
        }
      }
    }
  }

  void _drawReferencedCells(Canvas canvas, Set<CellAddress> addresses) {
    final tabularNodes =
        layerController.sceneGraph.nodeIndexIds
            .map((id) => layerController.findNodeById(id))
            .whereType<TabularNode>()
            .toList();
    if (tabularNodes.isEmpty) return;

    final paint =
        Paint()
          ..color = Colors.amber.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill;

    final borderPaint =
        Paint()
          ..color = Colors.amber
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

    // We use the first tabular node or the active one
    final tabularNode = tabularTool.selectedTabular ?? tabularNodes.first;

    for (final addr in addresses) {
      final cellRect = _getCellScreenRect(tabularNode, addr.column, addr.row);
      if (cellRect != null) {
        canvas.drawRect(cellRect, paint);
        canvas.drawRect(cellRect, borderPaint);

        // Cache for hit-testing — store canvas-space center for navigation
        final localTx = tabularNode.localTransform.getTranslation();
        double left =
            tabularNode.showRowHeaders ? tabularNode.headerWidth : 0.0;
        for (int c = 0; c < addr.column; c++)
          left += tabularNode.model.getColumnWidth(c);
        double top =
            tabularNode.showColumnHeaders ? tabularNode.headerHeight : 0.0;
        for (int r = 0; r < addr.row; r++)
          top += tabularNode.model.getRowHeight(r);
        final cw = tabularNode.model.getColumnWidth(addr.column);
        final ch = tabularNode.model.getRowHeight(addr.row);
        _paintedTargets.add(
          _HighlightTarget(
            screenRect: cellRect,
            canvasCenter: Offset(
              left + localTx.x + cw / 2,
              top + localTx.y + ch / 2,
            ),
          ),
        );
      }
    }
  }

  void _drawDependentLatexNodes(Canvas canvas, Set<String> latexNodeIds) {
    final latexNodes = layerController.sceneGraph.nodeIndexIds
        .map((id) => layerController.findNodeById(id))
        .whereType<LatexNode>()
        .where((n) => latexNodeIds.contains(n.id.toString()));

    final paint =
        Paint()
          ..color = Colors.purpleAccent.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill;

    final borderPaint =
        Paint()
          ..color = Colors.purpleAccent
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

    for (final node in latexNodes) {
      final bounds = node.localBounds;

      final localTx = node.localTransform.getTranslation();
      final localLeft = bounds.left + localTx.x;
      final localTop = bounds.top + localTx.y;

      // Transform bounds to screen space using canvasOffset and canvasScale
      final screenLeft = (localLeft + canvasOffset.dx) * canvasScale;
      final screenTop = (localTop + canvasOffset.dy) * canvasScale;
      final screenWidth = bounds.width * canvasScale;
      final screenHeight = bounds.height * canvasScale;

      final rect = Rect.fromLTWH(
        screenLeft,
        screenTop,
        screenWidth,
        screenHeight,
      ).inflate(4.0);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        borderPaint,
      );

      // Cache for hit-testing
      _paintedTargets.add(
        _HighlightTarget(
          screenRect: rect,
          canvasCenter: Offset(
            localLeft + bounds.width / 2,
            localTop + bounds.height / 2,
          ),
        ),
      );
    }
  }

  Rect? _getCellScreenRect(TabularNode node, int col, int row) {
    if (col < 0 || row < 0) return null;

    double left = node.showRowHeaders ? node.headerWidth : 0.0;
    for (int c = 0; c < col; c++) left += node.model.getColumnWidth(c);

    double top = node.showColumnHeaders ? node.headerHeight : 0.0;
    for (int r = 0; r < row; r++) top += node.model.getRowHeight(r);

    double width = node.model.getColumnWidth(col);
    double height = node.model.getRowHeight(row);

    // Consider merged regions
    if (node.mergeManager.isMasterCell(CellAddress(col, row))) {
      final region = node.mergeManager.getRegion(CellAddress(col, row))!;
      width = 0;
      for (int c = region.startColumn; c <= region.endColumn; c++) {
        width += node.model.getColumnWidth(c);
      }
      height = 0;
      for (int r = region.startRow; r <= region.endRow; r++) {
        height += node.model.getRowHeight(r);
      }
    } else if (node.mergeManager.isHiddenByMerge(CellAddress(col, row))) {
      return null;
    }

    final localRect = Rect.fromLTWH(left, top, width, height);

    // Apply node transform
    final localTx = node.localTransform.getTranslation();

    final globalTLX = localRect.left + localTx.x;
    final globalTLY = localRect.top + localTx.y;
    final globalBRX = localRect.right + localTx.x;
    final globalBRY = localRect.bottom + localTx.y;

    // Apply canvas transform
    final screenLeft = (globalTLX + canvasOffset.dx) * canvasScale;
    final screenTop = (globalTLY + canvasOffset.dy) * canvasScale;
    final screenRight = (globalBRX + canvasOffset.dx) * canvasScale;
    final screenBottom = (globalBRY + canvasOffset.dy) * canvasScale;

    return Rect.fromLTRB(screenLeft, screenTop, screenRight, screenBottom);
  }

  @override
  bool shouldRepaint(covariant LatexProvenanceOverlayPainter oldDelegate) {
    return oldDelegate.canvasOffset != canvasOffset ||
        oldDelegate.canvasScale != canvasScale ||
        oldDelegate.selectedNodeIds != selectedNodeIds;
  }
}

/// Internal hit-test target storing the screen rect and canvas-space center.
class _HighlightTarget {
  final Rect screenRect;
  final Offset canvasCenter;

  const _HighlightTarget({
    required this.screenRect,
    required this.canvasCenter,
  });
}
