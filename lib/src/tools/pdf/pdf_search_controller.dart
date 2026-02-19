import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../core/nodes/pdf_page_node.dart';
import '../../core/models/pdf_text_rect.dart';
import '../../canvas/nebula_canvas_config.dart';
import 'pdf_text_extractor.dart';

// =============================================================================
// 🔍 PDF FULL-TEXT SEARCH — Controller for searching text across PDF pages
// =============================================================================

/// A single search match within a PDF page.
class PdfSearchMatch {
  /// Page index (0-based) where this match was found.
  final int pageIndex;

  /// Start character offset within the page text.
  final int startOffset;

  /// End character offset (exclusive) within the page text.
  final int endOffset;

  /// Short snippet of context around the match.
  final String snippet;

  const PdfSearchMatch({
    required this.pageIndex,
    required this.startOffset,
    required this.endOffset,
    required this.snippet,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfSearchMatch &&
          pageIndex == other.pageIndex &&
          startOffset == other.startOffset &&
          endOffset == other.endOffset;

  @override
  int get hashCode => Object.hash(pageIndex, startOffset, endOffset);

  @override
  String toString() =>
      'PdfSearchMatch(page: $pageIndex, $startOffset..$endOffset, "$snippet")';
}

/// 🔍 Controller for full-text search across PDF pages.
///
/// Uses [NebulaPdfProvider.getPageText] to lazily load and cache text content,
/// then performs case-insensitive substring search. Results are navigable
/// via [nextMatch] / [previousMatch].
///
/// DESIGN PRINCIPLES:
/// - Lazy text loading — only loads pages not yet cached
/// - Case-insensitive search by default
/// - Snippet extraction with configurable context size
/// - Match navigation with wrap-around
/// - Highlight rects resolved from [PdfTextRect] geometry
class PdfSearchController extends ChangeNotifier {
  final NebulaPdfProvider? _provider;

  /// Cached full text per page index.
  final Map<int, String> _pageTextCache = {};

  /// Monotonic version counter — guards against stale async results.
  int _searchVersion = 0;

  /// Current search query (lowercase).
  String _query = '';
  String get query => _query;

  /// All matches found.
  List<PdfSearchMatch> _matches = const [];
  List<PdfSearchMatch> get matches => _matches;

  /// Index of the currently focused match (-1 if none).
  int _currentIndex = -1;
  int get currentIndex => _currentIndex;

  /// The currently focused match, or null.
  PdfSearchMatch? get currentMatch =>
      _currentIndex >= 0 && _currentIndex < _matches.length
          ? _matches[_currentIndex]
          : null;

  /// Whether a search is in progress.
  bool _isSearching = false;
  bool get isSearching => _isSearching;

  /// Total match count.
  int get matchCount => _matches.length;

  /// Whether there are any results.
  bool get hasMatches => _matches.isNotEmpty;

  PdfSearchController({NebulaPdfProvider? provider}) : _provider = provider;

  /// Raw PDF bytes for Dart-side text extraction fallback.
  Uint8List? _documentBytes;
  PdfTextExtractor? _dartExtractor;
  List<String>? _dartExtractedPages;
  int _totalPageCount = 0;

  /// Set the raw PDF bytes so the controller can extract text in pure Dart
  /// when the native provider doesn't support text extraction.
  void setDocumentBytes(Uint8List bytes) {
    _documentBytes = bytes;
    _dartExtractor = PdfTextExtractor(bytes);
    _dartExtractedPages = null; // lazy
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  /// Search all pages of [doc] for [query].
  ///
  /// Loads text content lazily from [NebulaPdfProvider] and caches it.
  /// Search is case-insensitive.
  Future<void> search(PdfDocumentNode doc, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clearSearch();
      return;
    }

    // I2: Skip if query is unchanged
    if (trimmed == _query && _matches.isNotEmpty) return;

    // I1: Bump version to cancel any in-flight search
    final version = ++_searchVersion;

    _query = trimmed;
    _isSearching = true;
    notifyListeners();

    debugPrint(
      '[PDF Search] Searching for "$trimmed" across ${doc.pageNodes.length} pages '
      '(hasBytes=${_dartExtractor != null}, hasProvider=${_provider != null})',
    );

    _totalPageCount = doc.pageNodes.length;

    final lowerQuery = trimmed.toLowerCase();
    final results = <PdfSearchMatch>[];
    final pages = doc.pageNodes;
    int pagesWithText = 0;

    for (int i = 0; i < pages.length; i++) {
      // I1: Bail if a newer search was triggered
      if (_searchVersion != version) return;

      final pageIndex = pages[i].pageModel.pageIndex;
      final text = await _getPageText(pageIndex);
      if (text.isEmpty) continue;

      pagesWithText++;
      _collectMatches(text, lowerQuery, trimmed.length, pageIndex, results);
    }

    // I1: Final guard — don't apply stale results
    if (_searchVersion != version) return;

    debugPrint(
      '[PDF Search] Done: $pagesWithText pages had text, ${results.length} matches found',
    );

    _matches = results;
    _currentIndex = results.isNotEmpty ? 0 : -1;
    _isSearching = false;
    notifyListeners();
  }

  /// Collect matches of [lowerQuery] in [text] for [pageIndex].
  void _collectMatches(
    String text,
    String lowerQuery,
    int originalLength,
    int pageIndex,
    List<PdfSearchMatch> results,
  ) {
    final lowerText = text.toLowerCase();
    int searchFrom = 0;

    while (true) {
      final idx = lowerText.indexOf(lowerQuery, searchFrom);
      if (idx < 0) break;

      results.add(
        PdfSearchMatch(
          pageIndex: pageIndex,
          startOffset: idx,
          endOffset: idx + originalLength,
          snippet: _extractSnippet(text, idx, originalLength),
        ),
      );

      searchFrom = idx + 1;
    }
  }

  /// Navigate to the next match (wraps around).
  void nextMatch() {
    if (_matches.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _matches.length;
    notifyListeners();
  }

  /// Navigate to the previous match (wraps around).
  void previousMatch() {
    if (_matches.isEmpty) return;
    _currentIndex = (_currentIndex - 1 + _matches.length) % _matches.length;
    notifyListeners();
  }

  /// I3: Jump directly to match at [index].
  void jumpToMatch(int index) {
    if (index < 0 || index >= _matches.length) return;
    _currentIndex = index;
    notifyListeners();
  }

  /// Clear all search state.
  void clearSearch() {
    _query = '';
    _matches = const [];
    _currentIndex = -1;
    _isSearching = false;
    _searchVersion++; // Cancel any in-flight search
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Highlight rects for rendering
  // ---------------------------------------------------------------------------

  /// Get highlight rects for all matches on [pageIndex].
  ///
  /// Resolves character offsets to [Rect] positions using the page's
  /// [PdfTextRect] geometry. Returns empty if geometry is not loaded.
  List<Rect> highlightRectsForPage(
    PdfPageNode page, {
    bool currentOnly = false,
  }) {
    if (page.textRects == null || page.textRects!.isEmpty) return const [];

    final pageIndex = page.pageModel.pageIndex;
    final pageMatches =
        currentOnly
            ? (currentMatch != null && currentMatch!.pageIndex == pageIndex
                ? [currentMatch!]
                : const <PdfSearchMatch>[])
            : _matches.where((m) => m.pageIndex == pageIndex);

    if (pageMatches.isEmpty) return const [];

    final rects = <Rect>[];
    final textRects = page.textRects!;

    for (final match in pageMatches) {
      // Find text rects whose character range overlaps the match
      for (final tr in textRects) {
        final trEnd = tr.charOffset + tr.text.length;
        if (trEnd > match.startOffset && tr.charOffset < match.endOffset) {
          rects.add(tr.rect);
        }
      }
    }

    return rects;
  }

  /// Get the highlight rect for only the current match on [pageIndex].
  Rect? currentMatchRectForPage(PdfPageNode page) {
    if (currentMatch == null) return null;
    if (currentMatch!.pageIndex != page.pageModel.pageIndex) return null;

    final rects = highlightRectsForPage(page, currentOnly: true);
    if (rects.isEmpty) return null;

    // Union all rects for the current match
    Rect union = rects.first;
    for (int i = 1; i < rects.length; i++) {
      union = union.expandToInclude(rects[i]);
    }
    return union;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Get or load page text (cached).
  ///
  /// First tries the native provider. If it returns empty text, falls back
  /// to the pure-Dart [PdfTextExtractor].
  Future<String> _getPageText(int pageIndex) async {
    if (_pageTextCache.containsKey(pageIndex)) {
      return _pageTextCache[pageIndex]!;
    }

    // Try native provider first
    if (_provider != null) {
      try {
        final text = await _provider.getPageText(pageIndex);
        if (text.isNotEmpty) {
          _pageTextCache[pageIndex] = text;
          return text;
        }
      } catch (e) {
        debugPrint(
          '[PDF Search] Native getPageText error for page $pageIndex: $e',
        );
      }
    }

    // Fallback: pure-Dart text extraction
    if (_dartExtractor != null) {
      try {
        _dartExtractedPages ??= _dartExtractor!.extractAllPages(
          pageCount: _totalPageCount,
        );
        debugPrint(
          '[PDF Search] Dart extracted ${_dartExtractedPages!.where((t) => t.isNotEmpty).length} '
          'text blocks across ${_dartExtractedPages!.length} pages',
        );
        if (pageIndex >= 0 && pageIndex < _dartExtractedPages!.length) {
          final text = _dartExtractedPages![pageIndex];
          _pageTextCache[pageIndex] = text;
          return text;
        }
      } catch (e) {
        debugPrint(
          '[PDF Search] Dart extraction error for page $pageIndex: $e',
        );
      }
    }

    return '';
  }

  /// Extract a snippet around [matchStart] with context.
  String _extractSnippet(String text, int matchStart, int matchLength) {
    const contextChars = 30;
    final snippetStart = (matchStart - contextChars).clamp(0, text.length);
    final snippetEnd = (matchStart + matchLength + contextChars).clamp(
      0,
      text.length,
    );

    final prefix = snippetStart > 0 ? '…' : '';
    final suffix = snippetEnd < text.length ? '…' : '';
    return '$prefix${text.substring(snippetStart, snippetEnd)}$suffix';
  }

  /// Invalidate text cache (call when document changes).
  void invalidateCache() => _pageTextCache.clear();

  @override
  void dispose() {
    _pageTextCache.clear();
    _matches = const [];
    super.dispose();
  }
}
