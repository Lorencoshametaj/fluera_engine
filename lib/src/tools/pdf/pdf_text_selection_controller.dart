import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/models/pdf_text_rect.dart';
import '../../core/nodes/pdf_page_node.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../canvas/fluera_canvas_config.dart';

// =============================================================================
// 📝 PDF TEXT SELECTION — Controller & model for text selection on PDF pages
// =============================================================================

/// Immutable snapshot of a text selection on a single PDF page.
class PdfTextSelection {
  /// The page this selection belongs to (0-based index).
  final int pageIndex;

  /// Ordered list of selected text rects (word-level granularity).
  final List<PdfTextRect> spans;

  /// Start index in the page's textRects list.
  final int startIndex;

  /// End index (inclusive) in the page's textRects list.
  final int endIndex;

  const PdfTextSelection({
    required this.pageIndex,
    required this.spans,
    required this.startIndex,
    required this.endIndex,
  });

  /// Combined selected text (smart join: no space within same line).
  String get selectedText {
    if (spans.isEmpty) return '';
    final buf = StringBuffer();
    for (int i = 0; i < spans.length; i++) {
      if (i > 0) {
        // Same line: no separator. Different line: space.
        final prevBottom = spans[i - 1].rect.bottom;
        final currTop = spans[i].rect.top;
        final lineHeight = spans[i - 1].rect.height;
        // If vertical gap < 50% of line height → same line
        if ((currTop - prevBottom).abs() < lineHeight * 0.5) {
          // same line, no separator
        } else {
          buf.write('\n');
        }
      }
      buf.write(spans[i].text);
    }
    return buf.toString();
  }

  /// Whether any text is selected.
  bool get isEmpty => spans.isEmpty;
  bool get isNotEmpty => spans.isNotEmpty;

  /// Union bounding rect of all selected spans.
  Rect get bounds {
    if (spans.isEmpty) return Rect.zero;
    Rect b = spans.first.rect;
    for (int i = 1; i < spans.length; i++) {
      b = b.expandToInclude(spans[i].rect);
    }
    return b;
  }

  static const empty = PdfTextSelection(
    pageIndex: -1,
    spans: [],
    startIndex: -1,
    endIndex: -1,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfTextSelection &&
          pageIndex == other.pageIndex &&
          startIndex == other.startIndex &&
          endIndex == other.endIndex &&
          listEquals(spans, other.spans);

  @override
  int get hashCode =>
      Object.hash(pageIndex, startIndex, endIndex, spans.length);
}

/// ✂️ Controller for PDF text selection on rasterized pages.
///
/// Layer 5 of the PDF architecture: an invisible overlay of [PdfTextRect]
/// objects enables text selection/copying on pages that are rendered as
/// raster images.
///
/// Supports:
/// - Tap → select word at position
/// - Long-press + drag → extend selection across spans
/// - Activate / deactivate selection mode
/// - Copy selected text to clipboard
/// - Lazy text geometry loading via [FlueraPdfProvider]
///
/// DESIGN: Works in page-local coordinates. The canvas converts screen
/// coordinates to page-local before calling methods here.
class PdfTextSelectionController extends ChangeNotifier {
  final FlueraPdfProvider? _provider;

  /// Whether text selection mode is active.
  bool _isActive = false;
  bool get isActive => _isActive;

  /// Current selection (may be empty).
  PdfTextSelection _selection = PdfTextSelection.empty;
  PdfTextSelection get selection => _selection;

  /// The page node currently being selected on.
  PdfPageNode? _activePage;
  PdfPageNode? get activePage => _activePage;

  /// Drag anchor index (for extending selection).
  int _dragAnchorIndex = -1;

  /// Pages currently loading text geometry (prevents concurrent dups).
  final Set<int> _loadingPages = {};

  PdfTextSelectionController({FlueraPdfProvider? provider})
    : _provider = provider;

  // ---------------------------------------------------------------------------
  // Mode management
  // ---------------------------------------------------------------------------

  /// Enter text selection mode.
  void activate() {
    _isActive = true;
    notifyListeners();
  }

  /// Exit text selection mode and clear any selection.
  void deactivate() {
    _isActive = false;
    clearSelection();
  }

  /// Dispose loaded text geometry from all pages the controller has touched.
  ///
  /// Call this to free memory when text selection is no longer needed.
  void disposeTextGeometry(PdfDocumentNode doc) {
    for (final page in doc.pageNodes) {
      page.textRects = null;
    }
  }

  /// Toggle text selection mode.
  void toggle() {
    if (_isActive) {
      deactivate();
    } else {
      activate();
    }
  }

  // ---------------------------------------------------------------------------
  // Text geometry loading
  // ---------------------------------------------------------------------------

  /// Ensure text geometry is loaded for [page].
  ///
  /// If already loaded or a load is in-flight, this is a no-op.
  Future<void> ensureTextGeometry(PdfPageNode page) async {
    if (page.hasTextGeometry) return;
    if (_provider == null) return;

    final pageIndex = page.pageModel.pageIndex;

    // Guard: prevent concurrent loads for the same page
    if (_loadingPages.contains(pageIndex)) return;
    _loadingPages.add(pageIndex);

    try {
      final rects = await _provider.extractTextGeometry(pageIndex);
      page.textRects = rects;
    } catch (e) {
    } finally {
      _loadingPages.remove(pageIndex);
    }
  }

  // ---------------------------------------------------------------------------
  // Selection operations
  // ---------------------------------------------------------------------------

  /// Select a single word at [localPoint] on [page].
  ///
  /// Loads text geometry if needed, then finds the rect at the point.
  Future<void> selectWordAt(PdfPageNode page, Offset localPoint) async {
    if (!_isActive) return;
    await ensureTextGeometry(page);

    if (page.textRects == null) return;

    final idx = _indexAtPoint(page, localPoint);
    if (idx < 0) {
      clearSelection();
      return;
    }

    _activePage = page;
    _dragAnchorIndex = idx;
    _selection = PdfTextSelection(
      pageIndex: page.pageModel.pageIndex,
      spans: [page.textRects![idx]],
      startIndex: idx,
      endIndex: idx,
    );
    notifyListeners();
  }

  /// Begin a drag selection at [localPoint].
  Future<void> beginDragSelection(PdfPageNode page, Offset localPoint) async {
    if (!_isActive) return;
    await ensureTextGeometry(page);

    if (page.textRects == null) return;

    final idx = _indexAtPoint(page, localPoint);
    if (idx < 0) return;

    _activePage = page;
    _dragAnchorIndex = idx;
    _selection = PdfTextSelection(
      pageIndex: page.pageModel.pageIndex,
      spans: [page.textRects![idx]],
      startIndex: idx,
      endIndex: idx,
    );
    notifyListeners();
  }

  /// Extend the current drag selection to [localPoint].
  void extendDragSelection(Offset localPoint) {
    if (!_isActive || _activePage == null || _dragAnchorIndex < 0) return;

    final page = _activePage!;
    if (page.textRects == null) return;

    final idx = _indexAtPoint(page, localPoint);
    if (idx < 0) return;

    final startIdx = idx < _dragAnchorIndex ? idx : _dragAnchorIndex;
    final endIdx = idx < _dragAnchorIndex ? _dragAnchorIndex : idx;

    _selection = PdfTextSelection(
      pageIndex: page.pageModel.pageIndex,
      spans: page.textRects!.sublist(startIdx, endIdx + 1),
      startIndex: startIdx,
      endIndex: endIdx,
    );
    notifyListeners();
  }

  /// Select all text on the active page.
  void selectAll() {
    if (_activePage == null || _activePage!.textRects == null) return;

    final rects = _activePage!.textRects!;
    if (rects.isEmpty) return;

    _selection = PdfTextSelection(
      pageIndex: _activePage!.pageModel.pageIndex,
      spans: rects,
      startIndex: 0,
      endIndex: rects.length - 1,
    );
    notifyListeners();
  }

  /// Get the combined selected text.
  String get selectedText => _selection.selectedText;

  /// Get the bounding rect of the current selection.
  Rect? get selectionBounds {
    if (_selection.isEmpty) return null;
    return _selection.bounds;
  }

  /// Clear the current selection.
  void clearSelection() {
    _selection = PdfTextSelection.empty;
    _activePage = null;
    _dragAnchorIndex = -1;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Clipboard
  // ---------------------------------------------------------------------------

  /// Copy selected text to clipboard.
  ///
  /// Returns true on success, false on empty selection or platform error.
  Future<bool> copyToClipboard() async {
    if (_selection.isEmpty) return false;

    final text = _selection.selectedText;
    if (text.isEmpty) return false;

    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (e) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Hit testing (private)
  // ---------------------------------------------------------------------------

  /// Find the textRects index at [localPoint], or -1 if none.
  int _indexAtPoint(PdfPageNode page, Offset localPoint) {
    final rects = page.textRects;
    if (rects == null || rects.isEmpty) return -1;

    for (int i = 0; i < rects.length; i++) {
      if (rects[i].containsPoint(localPoint)) return i;
    }

    // Fallback: find closest rect within tolerance (10 pts)
    const tolerance = 10.0;
    double closestDist = double.infinity;
    int closestIdx = -1;

    for (int i = 0; i < rects.length; i++) {
      final center = rects[i].rect.center;
      final dist = (center - localPoint).distance;
      if (dist < closestDist && dist < tolerance) {
        closestDist = dist;
        closestIdx = i;
      }
    }

    return closestIdx;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Find which PdfPageNode (if any) contains [canvasPoint].
  ///
  /// Converts to page-local coordinates and returns the page + local offset.
  static (PdfPageNode?, Offset) hitTestPage(
    PdfDocumentNode doc,
    Offset canvasPoint,
  ) {
    for (final page in doc.pageNodes) {
      final pageRect = doc.pageRectFor(page);
      if (pageRect.contains(canvasPoint)) {
        // Convert to page-local coordinates
        final localPoint = canvasPoint - Offset(pageRect.left, pageRect.top);
        return (page, localPoint);
      }
    }
    return (null, Offset.zero);
  }

  @override
  void dispose() {
    clearSelection();
    _loadingPages.clear(); // F5: hygiene — clear stale entries
    super.dispose();
  }
}
