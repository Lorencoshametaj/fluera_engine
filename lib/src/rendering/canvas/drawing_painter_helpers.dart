part of 'drawing_painter.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 🎨 DrawingPainter — Static Paint Objects & Helper Functions
// ═══════════════════════════════════════════════════════════════════════════

// ---------------------------------------------------------------------------
// 📄 REUSABLE PAINT OBJECTS (zero per-frame allocation)
// ---------------------------------------------------------------------------

  // 📄 Reusable Paint objects for PDF rendering (zero per-frame allocation)
final Paint _pdfShadowPaint =
      Paint()
        ..color = const Color(0x30000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
final Paint _pdfPageBgPaint = Paint()..color = const Color(0xFFFFFFFF);
final Paint _pdfBorderPaint =
      Paint()
        ..color = const Color(0xFFE0E0E0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;

  // 🚀 PERF: Pre-allocated Paint objects for hot path (zero GC pressure)
final Paint _pdfDragFillPaint =
      Paint()
        ..color = const Color(0x30000000)
        ..style = PaintingStyle.fill;
final Paint _pdfDragBorderPaint =
      Paint()
        ..color = const Color(0xFF1976D2)
        ..style = PaintingStyle.stroke;
  // Reusable paints for LOD thumbnail/batch rendering (color set per-use)
final Paint _lodThumbFillPaint = Paint()..style = PaintingStyle.fill;
final Paint _lodThumbStrokePaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
final Paint _lodBatchPaint =
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round;

  // 🚀 PDF LOD rectangle paints (color set per-use)
final Paint _pdfLodRectFill = Paint()..style = PaintingStyle.fill;
final Paint _pdfLodRectStroke =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
final Paint _layerCompositePaint = Paint();
final Paint _debugLayerPaint =
      Paint()..color = const Color(0x66FFFFFF);
final Paint _debugBoundsPaint =
      Paint()..color = const Color(0x40FF0000);
final Paint _tilePaint = Paint()..filterQuality = FilterQuality.low;

// 🚀 P99 FIX: Static Stopwatch for paint() timing — avoids per-frame allocation.
final Stopwatch _paintStopwatch = Stopwatch();

// 🚀 P99 FIX: Static Paint for background fill — avoids per-frame allocation.
final Paint _bgFillPaint = Paint();

  // 🏷️ Structured annotation render paints
final Paint _annotHighlightPaint = Paint(); // I6: reuse for highlights
final Paint _underlinePaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
final Paint _stickyIconBgPaint =
      Paint()..color = const Color(0xFFFFF176);
final Paint _stickyFoldPaint =
      Paint()..color = const Color(0x40000000); // I7: static fold paint
final Path _stickyFoldPath = Path(); // I7: reusable fold path

final TextPainter _wmTextPainter = TextPainter(
    textDirection: TextDirection.ltr,
  );

// ---------------------------------------------------------------------------
// 🔧 STATIC HELPER FUNCTIONS
// ---------------------------------------------------------------------------

/// Collect strokes from a node, skipping the first [skip] strokes.
/// Only adds strokes after the skip count to [result].
void _collectStrokesSkipping(
    CanvasNode node,
    List<ProStroke> result,
    int skip,
    int alreadySkipped,
  ) {
    if (node is StrokeNode) {
      if (alreadySkipped >= skip) {
        result.add(node.stroke);
      }
    } else if (node is GroupNode) {
      int localSkipped = alreadySkipped;
      for (final child in node.children) {
        if (!child.isVisible) continue;
        _collectStrokesSkipping(child, result, skip, localSkipped);
        localSkipped += (child is StrokeNode) ? 1 : 0;
      }
    }
  }

/// Recursively collect LOADED (non-stub) ProStroke instances from a node subtree.
/// Adds loaded stroke IDs to _loadedStrokeIds for O(K) fast lookup.
/// At 10M strokes, stubs are skipped → cache holds only ~1000-5000 loaded.
void _collectStrokes(CanvasNode node, List<ProStroke> result) {
    if (node is StrokeNode) {
      if (!node.stroke.isStub) {
        result.add(node.stroke);
        DrawingPainter._loadedStrokeIds.add(node.stroke.id);
      }
    } else if (node is GroupNode) {
      for (final child in node.children) {
        if (child.isVisible) _collectStrokes(child, result);
      }
    }
  }

/// Find the CanvasNode that wraps a given ProStroke.
CanvasNode? _findStrokeNode(CanvasNode node, ProStroke stroke) {
    if (node is StrokeNode && identical(node.stroke, stroke)) {
      return node;
    }
    if (node is GroupNode) {
      // Search in reverse — new strokes are typically at the end
      for (int i = node.children.length - 1; i >= 0; i--) {
        final child = node.children[i];
        final found = _findStrokeNode(child, stroke);
        if (found != null) return found;
      }
    }
    return null;
  }

/// Recursively collect leaf CanvasNodes for R-Tree indexing.
void _collectLeafNodes(CanvasNode node, List<CanvasNode> result) {
    if (node is GroupNode) {
      // SectionNode is BOTH a container AND a renderable node —
      // add it to the index so tile cache renders its background/border/label.
      if (node is SectionNode && node.isVisible) {
        result.add(node);
      }
      for (final child in node.children) {
        if (child.isVisible) _collectLeafNodes(child, result);
      }
    } else if (node.isVisible) {
      // Leaf node (StrokeNode, ShapeNode, TextNode, ImageNode, etc.)
      result.add(node);
    }
  }

/// Recursively collect annotation IDs from PDF nodes in a subtree.
void _collectPdfAnnotationIdsFromNode(
    CanvasNode node,
    Set<String> ids,
  ) {
    if (node is PdfDocumentNode) {
      for (final page in node.pageNodes) {
        final annotations = page.pageModel.annotations;
        if (annotations.isNotEmpty) {
          ids.addAll(annotations);
        }
      }
    } else if (node is GroupNode) {
      for (final child in node.children) {
        if (child.isVisible) {
          _collectPdfAnnotationIdsFromNode(child, ids);
        }
      }
    }
  }

// ---------------------------------------------------------------------------
// 📦 HELPER CLASSES
// ---------------------------------------------------------------------------


/// 🚀 PERF: Cache entry for the incremental annotation Picture cache.
class _AnnotCacheEntry {
  final int count;
  final ui.Picture picture;
  const _AnnotCacheEntry({required this.count, required this.picture});
}

/// 🚀 LOD: batch strokes by color for low-zoom rendering.
class _ColorBatch {
  final ui.Path path;
  final Color color;
  double maxWidth;
  _ColorBatch(this.path, this.color, this.maxWidth);
}

