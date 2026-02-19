import 'dart:ui';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_visitor.dart';
import './group_node.dart';
import './pdf_page_node.dart';
import '../models/pdf_document_model.dart';
import '../models/pdf_page_model.dart';

/// 📄 Scene graph container node for an entire PDF document.
///
/// Extends [GroupNode] to hold [PdfPageNode] children. Manages the
/// automatic grid layout and lock/unlock semantics. When a page is
/// locked, it is positioned by [performGridLayout]; when unlocked,
/// it keeps its [PdfPageModel.customOffset].
///
/// DESIGN PRINCIPLES:
/// - One PdfDocumentNode per imported PDF
/// - Grid layout is recalculated on lock/unlock or config change
/// - Children are always PdfPageNodes (enforced by add helpers)
/// - Serialization includes all page metadata + grid config
class PdfDocumentNode extends GroupNode {
  /// Document-level metadata (hash, grid config, timestamps).
  PdfDocumentModel documentModel;

  PdfDocumentNode({
    required super.id,
    required this.documentModel,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  });

  // ---------------------------------------------------------------------------
  // Page access helpers
  // ---------------------------------------------------------------------------

  /// All child PdfPageNodes in order.
  List<PdfPageNode> get pageNodes => childrenOfType<PdfPageNode>().toList();

  /// Get a specific page node by page index.
  PdfPageNode? pageAt(int pageIndex) {
    try {
      return pageNodes.firstWhere((n) => n.pageModel.pageIndex == pageIndex);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Grid layout
  // ---------------------------------------------------------------------------

  /// Position all locked pages in a grid layout.
  ///
  /// Unlocked pages retain their [PdfPageModel.customOffset].
  /// After layout, the document's [localBounds] will encompass all pages.
  void performGridLayout() {
    final cols = documentModel.gridColumns;
    final spacing = documentModel.gridSpacing;
    final origin = documentModel.gridOrigin;

    int row = 0;
    int col = 0;

    for (final pageNode in pageNodes) {
      if (pageNode.pageModel.isLocked) {
        // Calculate grid position
        final pageWidth = pageNode.pageModel.originalSize.width;
        final pageHeight = pageNode.pageModel.originalSize.height;

        final x = origin.dx + col * (pageWidth + spacing);
        final y = origin.dy + row * (pageHeight + spacing);

        pageNode.setPosition(x, y);
        pageNode.invalidateTransformCache();

        // Update grid position in page model
        pageNode.pageModel = pageNode.pageModel.copyWith(
          gridRow: row,
          gridCol: col,
        );

        col++;
        if (col >= cols) {
          col = 0;
          row++;
        }
      } else {
        // Unlocked pages use their custom offset
        final offset = pageNode.pageModel.customOffset ?? Offset.zero;
        pageNode.setPosition(offset.dx, offset.dy);
        pageNode.invalidateTransformCache();
      }
    }
  }

  /// Toggle lock state for a specific page and re-layout.
  void togglePageLock(int pageIndex) {
    final pageNode = pageAt(pageIndex);
    if (pageNode == null) return;

    final now = DateTime.now().microsecondsSinceEpoch;

    if (pageNode.pageModel.isLocked) {
      // Unlock: capture current position as custom offset
      pageNode.pageModel = pageNode.pageModel.copyWith(
        isLocked: false,
        customOffset: pageNode.position,
        lastModifiedAt: now,
      );
    } else {
      // Lock: clear custom offset, will be positioned by grid
      pageNode.pageModel = pageNode.pageModel.copyWith(
        isLocked: true,
        clearCustomOffset: true,
        lastModifiedAt: now,
      );
    }

    // Update document timestamp
    documentModel = documentModel.copyWith(lastModifiedAt: now);

    // Re-layout grid
    performGridLayout();
  }

  // ---------------------------------------------------------------------------
  // Memory management
  // ---------------------------------------------------------------------------

  /// Total estimated memory usage of all cached page images (bytes).
  int get totalCachedMemoryBytes {
    int total = 0;
    for (final page in pageNodes) {
      total += page.estimatedMemoryBytes;
    }
    return total;
  }

  /// Dispose all cached images (call during memory pressure or cleanup).
  void disposeAllCachedImages() {
    for (final page in pageNodes) {
      page.disposeCachedImage();
    }
  }

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds {
    if (children.isEmpty) return Rect.zero;
    Rect bounds = children.first.localBounds;
    for (int i = 1; i < children.length; i++) {
      bounds = bounds.expandToInclude(children[i].localBounds);
    }
    return bounds;
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'pdfDocument';
    json['documentModel'] = documentModel.toJson();
    json['children'] = children.map((c) => c.toJson()).toList();
    return json;
  }

  factory PdfDocumentNode.fromJson(Map<String, dynamic> json) {
    final node = PdfDocumentNode(
      id: json['id'] as String,
      documentModel: PdfDocumentModel.fromJson(
        json['documentModel'] as Map<String, dynamic>,
      ),
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  // ---------------------------------------------------------------------------
  // Visitor
  // ---------------------------------------------------------------------------

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitPdfDocument(this);

  @override
  String toString() =>
      'PdfDocumentNode(id: $id, '
      '${documentModel.totalPages} pages, '
      '${pageNodes.where((p) => p.pageModel.isLocked).length} locked)';
}
