import 'dart:ui';

import '../../core/nodes/pdf_page_node.dart';

/// 🗂️ PDF PAGE STUB MANAGER — Memory-bounded PDF page storage
///
/// At 100K+ PDF pages, keeping all [PdfPageNode] fields populated consumes
/// significant memory:
/// - `cachedImage`: ~4MB RGBA per page (already LRU-evicted by PdfPagePainter)
/// - `textRects`: ~50KB per page (loaded lazily, but never freed)
/// - `structuredAnnotations`: variable, grows with user markups
///
/// This manager stubs out pages far from the viewport:
/// - Disposes `cachedImage` (GPU memory)
/// - Nulls `textRects` (text geometry — reloaded on demand)
/// - The `pageModel` and `bounds` remain in RAM (~200 bytes/page)
///   for R-Tree spatial queries and placeholder rendering.
///
/// PAGING STRATEGY:
/// - Page-out margin: 3× longest viewport side
/// - Page-in margin: 1.5× longest viewport side (hysteresis)
/// - Throttled to run every N frames (not every paint call)
///
/// MEMORY SAVINGS:
/// At 100K pages with text rects loaded:
/// - Before:  100K × ~50KB text = ~5GB RAM
/// - After:   ~200 pages with text in RAM = ~10MB
///            100K stubs × ~200B = ~20MB
class PdfPageStubManager {
  /// Pages that have been stubbed out (text rects freed).
  final Set<String> _stubbedPageIds = {};

  /// Frames between stub-out passes.
  static const int _kStubInterval = 60;

  /// Page-out margin multiplier (relative to viewport longest side).
  static const double _kPageOutMarginMultiplier = 3.0;

  /// Page-in margin multiplier (hysteresis — smaller than page-out).
  static const double _kPageInMarginMultiplier = 1.5;

  /// Maximum pages to stub per pass (budget-cap to avoid frame spike).
  static const int _kMaxStubsPerPass = 50;

  /// Frame counter for throttling.
  int _frameCounter = 0;

  /// Total text rects freed by stubbing (diagnostic).
  int _totalTextRectsFreed = 0;

  /// Whether the manager is active (only needed for large page counts).
  bool _isActive = false;

  /// Minimum page count to activate stubbing.
  static const int _kActivationThreshold = 200;

  /// Number of pages currently stubbed.
  int get stubbedCount => _stubbedPageIds.length;

  /// Whether a page is currently stubbed.
  bool isStubbed(String pageId) => _stubbedPageIds.contains(pageId);

  /// Total text rects freed (diagnostic).
  int get totalTextRectsFreed => _totalTextRectsFreed;

  // ---------------------------------------------------------------------------
  // Stub-out: free heavy fields on far-from-viewport pages
  // ---------------------------------------------------------------------------

  /// Run a stub-out pass on the given pages.
  ///
  /// Call once per paint cycle (throttled internally).
  /// Returns the number of pages newly stubbed.
  int maybeStubOut(List<PdfPageNode> allPages, Rect viewport) {
    // Activation check: only stub when page count warrants it
    if (!_isActive) {
      if (allPages.length >= _kActivationThreshold) {
        _isActive = true;
      } else {
        return 0;
      }
    }

    // Throttle: run every _kStubInterval frames
    _frameCounter++;
    if (_frameCounter % _kStubInterval != 0) return 0;

    final margin = viewport.longestSide * _kPageOutMarginMultiplier;
    final inflatedViewport = viewport.inflate(margin);

    int stubbed = 0;

    for (final page in allPages) {
      if (stubbed >= _kMaxStubsPerPass) break;
      if (_stubbedPageIds.contains(page.id)) continue;

      // Check if page is far from viewport
      final pos = page.position;
      final sz = page.pageModel.originalSize;
      final pageRect = Rect.fromLTWH(pos.dx, pos.dy, sz.width, sz.height);

      if (!pageRect.overlaps(inflatedViewport)) {
        _stubPage(page);
        stubbed++;
      }
    }

    return stubbed;
  }

  /// Hydrate stubbed pages that are now within the viewport margin.
  ///
  /// Call before painting visible pages.
  /// Returns the number of pages hydrated (text rects will be re-loaded
  /// on demand by the text selection controller).
  int maybeHydrate(List<PdfPageNode> visiblePages, Rect viewport) {
    if (_stubbedPageIds.isEmpty) return 0;

    final margin = viewport.longestSide * _kPageInMarginMultiplier;
    final inflatedViewport = viewport.inflate(margin);

    int hydrated = 0;

    for (final page in visiblePages) {
      if (!_stubbedPageIds.contains(page.id)) continue;

      final pos = page.position;
      final sz = page.pageModel.originalSize;
      final pageRect = Rect.fromLTWH(pos.dx, pos.dy, sz.width, sz.height);

      if (pageRect.overlaps(inflatedViewport)) {
        _hydratePage(page);
        hydrated++;
      }
    }

    return hydrated;
  }

  // ---------------------------------------------------------------------------
  // Internal operations
  // ---------------------------------------------------------------------------

  void _stubPage(PdfPageNode page) {
    // 1. Dispose cached raster image (GPU memory)
    if (page.cachedImage != null) {
      page.disposeCachedImage();
    }

    // 2. Free text geometry (re-loaded on demand by text selection)
    if (page.textRects != null) {
      _totalTextRectsFreed += page.textRects!.length;
      page.textRects = null;
    }

    _stubbedPageIds.add(page.id);
  }

  void _hydratePage(PdfPageNode page) {
    // Mark as no longer stubbed.
    // - cachedImage: PdfPagePainter will re-render it when it becomes visible
    // - textRects: text selection controller will re-load on demand
    _stubbedPageIds.remove(page.id);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Clear all stub tracking (e.g., on canvas reset).
  void clear() {
    _stubbedPageIds.clear();
    _totalTextRectsFreed = 0;
    _frameCounter = 0;
    _isActive = false;
  }

  /// Remove tracking for pages that no longer exist.
  void removeStaleEntries(Set<String> currentPageIds) {
    _stubbedPageIds.retainAll(currentPageIds);
  }
}
