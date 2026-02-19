import 'package:flutter/material.dart';
import '../../core/nodes/pdf_page_node.dart';
import '../../core/nodes/pdf_document_node.dart';

/// 📐 Controller for PDF grid layout and page lock/unlock operations.
///
/// Sits between the UI layer and the [PdfDocumentNode], managing:
/// - Grid recalculation when pages are added/removed/reordered
/// - Lock/unlock toggling with undo-friendly change tracking
/// - Bulk operations (lock all, unlock all, reset layout)
///
/// This controller does NOT own the document node — it operates on it
/// via references passed to each method.
class PdfGridController {
  /// Change notifier so consumers can react to layout updates.
  final ValueNotifier<int> layoutVersion = ValueNotifier<int>(0);

  // ---------------------------------------------------------------------------
  // Grid layout
  // ---------------------------------------------------------------------------

  /// Recalculate grid positions for all locked pages.
  ///
  /// Delegates to [PdfDocumentNode.performGridLayout] and bumps
  /// the layout version so listeners rebuild.
  void relayout(PdfDocumentNode doc) {
    doc.performGridLayout();
    layoutVersion.value++;
  }

  /// Change the grid column count and re-layout.
  void setGridColumns(PdfDocumentNode doc, int columns) {
    if (columns < 1) return;
    doc.documentModel = doc.documentModel.copyWith(
      gridColumns: columns,
      lastModifiedAt: DateTime.now().millisecondsSinceEpoch,
    );
    relayout(doc);
  }

  /// Change the grid spacing and re-layout.
  void setGridSpacing(PdfDocumentNode doc, double spacing) {
    if (spacing < 0) return;
    doc.documentModel = doc.documentModel.copyWith(
      gridSpacing: spacing,
      lastModifiedAt: DateTime.now().millisecondsSinceEpoch,
    );
    relayout(doc);
  }

  /// Change the grid origin and re-layout.
  void setGridOrigin(PdfDocumentNode doc, Offset origin) {
    doc.documentModel = doc.documentModel.copyWith(
      gridOrigin: origin,
      lastModifiedAt: DateTime.now().millisecondsSinceEpoch,
    );
    relayout(doc);
  }

  // ---------------------------------------------------------------------------
  // Lock/unlock
  // ---------------------------------------------------------------------------

  /// Toggle the lock state of a single page.
  ///
  /// When unlocking, the page's current grid position is stored as
  /// [PdfPageModel.customOffset] so it stays in place.
  /// When re-locking, the custom offset is cleared and the page
  /// returns to the grid.
  ///
  /// Returns `true` if the page was found and toggled.
  bool togglePageLock(PdfDocumentNode doc, int pageIndex) {
    if (pageIndex < 0 || pageIndex >= doc.pageNodes.length) return false;
    doc.togglePageLock(pageIndex);
    layoutVersion.value++;
    return true;
  }

  /// Lock all pages (return them all to the grid).
  void lockAll(PdfDocumentNode doc) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final page in doc.pageNodes) {
      if (!page.pageModel.isLocked) {
        page.pageModel = page.pageModel.copyWith(
          isLocked: true,
          clearCustomOffset: true,
          lastModifiedAt: now,
        );
      }
    }
    doc.documentModel = doc.documentModel.copyWith(lastModifiedAt: now);
    relayout(doc);
  }

  /// Unlock all pages (freeze each at its current grid position).
  void unlockAll(PdfDocumentNode doc) {
    final now = DateTime.now().millisecondsSinceEpoch;
    // First compute the grid so positions are fresh
    doc.performGridLayout();

    for (final page in doc.pageNodes) {
      if (page.pageModel.isLocked) {
        page.pageModel = page.pageModel.copyWith(
          isLocked: false,
          customOffset: page.position,
          lastModifiedAt: now,
        );
      }
    }
    doc.documentModel = doc.documentModel.copyWith(lastModifiedAt: now);
    layoutVersion.value++;
  }

  // ---------------------------------------------------------------------------
  // Bulk operations
  // ---------------------------------------------------------------------------

  /// Reset all pages to locked state with a fresh grid layout.
  void resetLayout(PdfDocumentNode doc) {
    lockAll(doc);
  }

  /// Auto-fit grid columns to best match a target viewport width.
  ///
  /// Calculates the optimal column count so pages fit within [viewportWidth]
  /// without horizontal scrolling.
  void autoFitColumns(PdfDocumentNode doc, double viewportWidth) {
    if (doc.pageNodes.isEmpty) return;

    // Use the widest page to determine column fit
    double maxPageWidth = 0;
    for (final page in doc.pageNodes) {
      final w = page.pageModel.originalSize.width;
      if (w > maxPageWidth) maxPageWidth = w;
    }

    if (maxPageWidth <= 0) return;

    final spacing = doc.documentModel.gridSpacing;
    // How many columns fit: viewport = cols * pageWidth + (cols-1) * spacing
    // cols = (viewport + spacing) / (pageWidth + spacing)
    final cols = ((viewportWidth + spacing) / (maxPageWidth + spacing))
        .floor()
        .clamp(1, doc.pageNodes.length);

    setGridColumns(doc, cols);
  }

  /// Dispose the controller's resources.
  void dispose() {
    layoutVersion.dispose();
  }
}
