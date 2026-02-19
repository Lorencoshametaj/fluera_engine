import 'package:flutter/material.dart';
import '../../core/nodes/pdf_page_node.dart';
import '../../core/models/pdf_text_rect.dart';
import '../../canvas/nebula_canvas_config.dart';

/// ✂️ Controller for PDF text selection on rasterized pages.
///
/// Layer 5 of the PDF architecture: an invisible overlay of [PdfTextRect]
/// objects enables text selection/copying on pages that are rendered as
/// raster images.
///
/// WORKFLOW:
/// 1. User long-presses or double-taps on a PDF page
/// 2. Text geometry is loaded lazily via [NebulaPdfProvider.extractTextGeometry]
/// 3. Selection handles appear over the page
/// 4. User adjusts selection → [selectedText] updates
/// 5. Copy action copies [selectedText] to clipboard
class PdfTextSelectionController {
  final NebulaPdfProvider? _provider;

  /// Currently selected text rects.
  final ValueNotifier<List<PdfTextRect>> selection =
      ValueNotifier<List<PdfTextRect>>([]);

  PdfTextSelectionController({NebulaPdfProvider? provider})
    : _provider = provider;

  // ---------------------------------------------------------------------------
  // Text geometry loading
  // ---------------------------------------------------------------------------

  /// Ensure text geometry is loaded for [page].
  ///
  /// If already loaded, this is a no-op. Otherwise, calls the provider
  /// to extract text rects and stores them on the node.
  Future<void> ensureTextGeometry(PdfPageNode page) async {
    if (page.hasTextGeometry) return;
    if (_provider == null) return;

    final rects = await _provider.extractTextGeometry(page.pageModel.pageIndex);
    page.textRects = rects;
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  /// Start a new selection at [localPoint] on [page].
  ///
  /// Loads text geometry if needed, then finds the rect at the point.
  Future<void> beginSelection(PdfPageNode page, Offset localPoint) async {
    await ensureTextGeometry(page);

    final hit = page.hitTestText(localPoint);
    if (hit != null) {
      selection.value = [hit];
    } else {
      selection.value = [];
    }
  }

  /// Extend the selection to include [localPoint].
  ///
  /// Selects all text rects between the first selected rect
  /// and the rect at [localPoint] (by charOffset order).
  void extendSelection(PdfPageNode page, Offset localPoint) {
    if (selection.value.isEmpty) return;
    if (!page.hasTextGeometry) return;

    final hit = page.hitTestText(localPoint);
    if (hit == null) return;

    final anchor = selection.value.first;
    final startOffset =
        anchor.charOffset < hit.charOffset ? anchor.charOffset : hit.charOffset;
    final endOffset =
        anchor.charOffset < hit.charOffset ? hit.charOffset : anchor.charOffset;

    // Select all rects within the char offset range
    final rects =
        page.textRects!
            .where(
              (r) => r.charOffset >= startOffset && r.charOffset <= endOffset,
            )
            .toList();

    selection.value = rects;
  }

  /// Get the combined selected text.
  String get selectedText {
    if (selection.value.isEmpty) return '';
    final sorted = List<PdfTextRect>.from(selection.value)
      ..sort((a, b) => a.charOffset.compareTo(b.charOffset));
    return sorted.map((r) => r.text).join('');
  }

  /// Get the bounding rect of the current selection.
  Rect? get selectionBounds {
    if (selection.value.isEmpty) return null;
    Rect combined = selection.value.first.rect;
    for (final r in selection.value.skip(1)) {
      combined = combined.expandToInclude(r.rect);
    }
    return combined;
  }

  /// Clear the selection.
  void clearSelection() {
    selection.value = [];
  }

  /// Dispose resources.
  void dispose() {
    selection.dispose();
  }
}
