import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../core/nodes/pdf_page_node.dart';
import '../../core/models/ocr_result.dart';
import '../../core/models/pdf_text_rect.dart';
import '../../canvas/nebula_canvas_config.dart';
import '../../core/engine_scope.dart';
import '../../core/engine_error.dart';
import '../../core/engine_telemetry.dart';
import 'pdf_text_extractor.dart';

// =============================================================================
// 🔍 PDF FULL-TEXT SEARCH — Enterprise multi-document search controller
// =============================================================================

/// A single search match within a PDF page.
class PdfSearchMatch {
  /// Document ID that this match belongs to.
  final String documentId;

  /// Page index (0-based) where this match was found.
  final int pageIndex;

  /// Start character offset within the page text.
  final int startOffset;

  /// End character offset (exclusive) within the page text.
  final int endOffset;

  /// Short snippet of context around the match.
  final String snippet;

  const PdfSearchMatch({
    required this.documentId,
    required this.pageIndex,
    required this.startOffset,
    required this.endOffset,
    required this.snippet,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfSearchMatch &&
          documentId == other.documentId &&
          pageIndex == other.pageIndex &&
          startOffset == other.startOffset &&
          endOffset == other.endOffset;

  @override
  int get hashCode =>
      Object.hash(documentId, pageIndex, startOffset, endOffset);

  @override
  String toString() =>
      'PdfSearchMatch(doc: $documentId, page: $pageIndex, '
      '$startOffset..$endOffset, "$snippet")';
}

/// Per-document extraction state.
class _DocState {
  final Uint8List bytes;
  final NebulaPdfProvider? provider;
  List<ExtractedPageText>? extractedPages;
  final Map<int, String> textCache = {};

  /// Cached OCR results per page — avoids re-running expensive native OCR.
  final Map<int, OcrPageResult> ocrCache = {};

  _DocState({required this.bytes, this.provider});
}

/// 🔍 Enterprise multi-document PDF search controller.
///
/// Supports searching across one or multiple PDF documents simultaneously.
/// Each document is registered with [registerDocument] and can be
/// unregistered with [unregisterDocument].
///
/// DESIGN PRINCIPLES:
/// - Multi-document aware — per-document extraction state keyed by ID
/// - Lazy text loading — only loads pages not yet cached
/// - Case-insensitive search by default + whole-word mode
/// - Match navigation with wrap-around
/// - Highlight rects resolved from [PdfTextRect] geometry with caching
/// - Search progress reporting for large PDFs
class PdfSearchController extends ChangeNotifier {
  /// Per-document state (bytes, cache, provider, extracted pages).
  final Map<String, _DocState> _documents = {};

  /// Per-page OCR status tracking — prevents duplicate work and enables
  /// UI status reporting.
  /// Key: 'documentId:pageIndex'.
  final Map<String, OcrPageStatus> _ocrStatus = {};

  /// Minimum OCR confidence threshold — blocks below this are filtered.
  ///
  /// Default 0.3 is intentionally low to preserve recall; the Dart-side
  /// search will further validate via exact string matching.
  static const double ocrConfidenceThreshold = 0.3;

  /// DEBUG: When true, skip native text extraction and Dart parsing —
  /// always use OCR for every page. Set to `true` to test the full
  /// OCR pipeline on Android/iOS.
  static const bool forceOcr = true;

  /// Monotonic version counter — guards against stale async results.
  int _searchVersion = 0;

  /// Current search query.
  String _query = '';
  String get query => _query;

  /// Whether whole-word matching is enabled.
  bool _wholeWord = false;
  bool get wholeWord => _wholeWord;
  set wholeWord(bool value) {
    if (_wholeWord == value) return;
    _wholeWord = value;
    notifyListeners();
  }

  /// All matches found (across all documents).
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

  /// Search progress: pages searched so far.
  int _pagesSearched = 0;
  int get pagesSearched => _pagesSearched;

  /// Search progress: total pages to search.
  int _totalPagesToSearch = 0;
  int get totalPagesToSearch => _totalPagesToSearch;

  /// Progress fraction 0.0–1.0 (0 if not searching).
  double get searchProgress =>
      _totalPagesToSearch > 0
          ? (_pagesSearched / _totalPagesToSearch).clamp(0.0, 1.0)
          : 0.0;

  /// Total match count.
  int get matchCount => _matches.length;

  /// Match count for a specific document.
  int matchCountForDocument(String documentId) =>
      _matches.where((m) => m.documentId == documentId).length;

  /// Whether there are any results.
  bool get hasMatches => _matches.isNotEmpty;

  PdfSearchController();

  // ---------------------------------------------------------------------------
  // Highlight rect cache (D)
  // ---------------------------------------------------------------------------
  //
  // Cache keyed by (documentId, pageIndex) → List<Rect>.
  // Invalidated when _matches change (new search, clear, unregister).

  final Map<String, List<Rect>> _highlightRectCache = {};

  String _hlCacheKey(String? docId, int pageIndex) =>
      '${docId ?? '*'}:$pageIndex';

  void _invalidateHighlightCache() => _highlightRectCache.clear();

  // ---------------------------------------------------------------------------
  // Document registration
  // ---------------------------------------------------------------------------

  /// Register a PDF document for searching.
  void registerDocument(
    String documentId,
    Uint8List bytes, {
    NebulaPdfProvider? provider,
  }) {
    _documents[documentId] = _DocState(bytes: bytes, provider: provider);
  }

  /// Unregister a PDF document (e.g. when removed from canvas).
  void unregisterDocument(String documentId) {
    _documents.remove(documentId);
    if (_matches.any((m) => m.documentId == documentId)) {
      _matches = _matches.where((m) => m.documentId != documentId).toList();
      if (_currentIndex >= _matches.length) {
        _currentIndex = _matches.isEmpty ? -1 : 0;
      }
      _invalidateHighlightCache();
      notifyListeners();
    }
  }

  /// Whether a document is registered.
  bool hasDocument(String documentId) => _documents.containsKey(documentId);

  /// Number of registered documents.
  int get documentCount => _documents.length;

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  /// Search a single document for [query].
  Future<void> search(PdfDocumentNode doc, String query) async {
    return searchDocuments([doc], query);
  }

  /// Search across multiple PDF documents for [query].
  ///
  /// Results from all documents are merged and sorted by document order,
  /// then page order within each document.
  Future<void> searchDocuments(
    List<PdfDocumentNode> docs,
    String query, {
    bool? wholeWord,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clearSearch();
      return;
    }

    final useWholeWord = wholeWord ?? _wholeWord;

    // Skip if query + mode unchanged and we already have results
    if (trimmed == _query &&
        useWholeWord == _wholeWord &&
        _matches.isNotEmpty) {
      return;
    }

    // Bump version to cancel any in-flight search
    final version = ++_searchVersion;

    _query = trimmed;
    _wholeWord = useWholeWord;
    _isSearching = true;

    // Count total pages for progress
    _totalPagesToSearch = docs.fold<int>(0, (s, d) => s + d.pageNodes.length);
    _pagesSearched = 0;
    notifyListeners();

    final lowerQuery = trimmed.toLowerCase();
    // Build regex for whole-word mode
    final RegExp? wordPattern =
        useWholeWord
            ? RegExp('\\b${RegExp.escape(lowerQuery)}\\b', caseSensitive: false)
            : null;

    final results = <PdfSearchMatch>[];
    int totalPagesWithText = 0;

    for (final doc in docs) {
      final documentId = doc.id;
      final pages = doc.pageNodes;
      final totalPageCount = pages.length;

      for (int i = 0; i < pages.length; i++) {
        if (_searchVersion != version) return; // bail on newer search

        final pageNode = pages[i];
        final pageIndex = pageNode.pageModel.pageIndex;
        final text = await _getPageText(
          documentId,
          pageIndex,
          totalPageCount,
          pageNode: pageNode,
        );

        _pagesSearched++;
        // Notify progress every 5 pages to avoid excessive rebuilds
        if (_pagesSearched % 5 == 0 || _pagesSearched == _totalPagesToSearch) {
          notifyListeners();
        }

        if (text.isEmpty) continue;
        totalPagesWithText++;

        if (wordPattern != null) {
          _collectMatchesRegex(
            text,
            wordPattern,
            trimmed.length,
            documentId,
            pageIndex,
            results,
          );
        } else {
          _collectMatches(
            text,
            lowerQuery,
            trimmed.length,
            documentId,
            pageIndex,
            results,
          );
        }
      }
    }

    if (_searchVersion != version) return;

    debugPrint(
      '[PDF Search] Done: $totalPagesWithText pages had text, '
      '${results.length} matches across ${docs.length} document(s)',
    );

    _matches = results;
    _currentIndex = results.isNotEmpty ? 0 : -1;
    _isSearching = false;
    _invalidateHighlightCache();

    // ── ONE-SHOT DIAGNOSTIC ──
    if (results.isNotEmpty) {
      for (final doc in docs) {
        final firstMatch = results.first;
        final matchPage = doc.pageNodes.firstWhere(
          (p) => p.pageModel.pageIndex == firstMatch.pageIndex,
          orElse: () => doc.pageNodes.first,
        );
        final trs = matchPage.textRects;
        if (trs != null && trs.isNotEmpty) {
          final f = trs.first;
          final l = trs.last;
          debugPrint(
            '[PDF DBG] viewerSize=${matchPage.pageModel.originalSize}',
          );
          // Show extractor dims for comparison
          final docState = _documents[doc.id];
          final ext = docState?.extractedPages;
          if (ext != null && firstMatch.pageIndex < ext.length) {
            final ep = ext[firstMatch.pageIndex];
            debugPrint(
              '[PDF DBG] extractorSize=${ep.pageWidth}x${ep.pageHeight}',
            );
          }
          debugPrint(
            '[PDF DBG] first textRect: rect=${f.rect}, '
            'charOffset=${f.charOffset}, text="${f.text}"',
          );
          debugPrint(
            '[PDF DBG] last textRect: rect=${l.rect}, '
            'charOffset=${l.charOffset}',
          );
          debugPrint(
            '[PDF DBG] match: page=${firstMatch.pageIndex}, '
            'start=${firstMatch.startOffset}, end=${firstMatch.endOffset}, '
            'docId=${firstMatch.documentId}',
          );
          // Detect normalization state
          final isNorm = f.rect.right <= 1.5 && f.rect.bottom <= 1.5;
          debugPrint('[PDF DBG] rects normalized=$isNorm');
          // Compute highlight with current logic
          final hlRects = _computeHighlightRects(
            matchPage,
            firstMatch.pageIndex,
            doc.id,
            false,
          );
          if (hlRects.isNotEmpty) {
            debugPrint('[PDF DBG] highlight[0]=${hlRects.first}');
          } else {
            debugPrint('[PDF DBG] highlight: 0 rects!');
          }

          // Y-position map of page 0: group by Y-band
          final yBands = <int, StringBuffer>{};
          for (final tr in trs) {
            final band = (tr.rect.top * 10).floor(); // 0-9 for 0%-100%
            yBands.putIfAbsent(band, () => StringBuffer());
            if (yBands[band]!.length < 80) {
              yBands[band]!.write('${tr.text} ');
            }
          }
          for (final band in yBands.keys.toList()..sort()) {
            debugPrint(
              '[Y-MAP] band=${band * 10}%-${(band + 1) * 10}%: '
              '${yBands[band].toString().trim()}',
            );
          }

          // Show what textRect is at the match's charOffset
          int overlapCount = 0;
          for (final tr in trs) {
            final trEnd = tr.charOffset + tr.text.length;
            if (trEnd > firstMatch.startOffset &&
                tr.charOffset < firstMatch.endOffset) {
              overlapCount++;
              if (overlapCount <= 10) {
                debugPrint(
                  '[PDF DBG] overlap[$overlapCount]: '
                  'charOffset=${tr.charOffset}..${trEnd - 1}, '
                  'rect=${tr.rect}, '
                  'text="${tr.text.substring(0, tr.text.length.clamp(0, 40))}"',
                );
              }
            }
          }
          debugPrint(
            '[PDF DBG] Total overlapping rects=$overlapCount, '
            'highlight rects=${hlRects.length}',
          );

          // Show what the search text has at offset 152
          final cached =
              _documents[firstMatch.documentId]?.textCache[firstMatch
                  .pageIndex] ??
              '';
          if (cached.isNotEmpty && firstMatch.endOffset <= cached.length) {
            final matchSnippet = cached.substring(
              firstMatch.startOffset,
              firstMatch.endOffset,
            );
            debugPrint(
              '[PDF DBG] search text at offset ${firstMatch.startOffset}: "$matchSnippet"',
            );
          }
        } else {
          debugPrint(
            '[PDF DBG] NO textRects on match page '
            '${firstMatch.pageIndex}!',
          );
        }
      }
    }
    // ── END DIAGNOSTIC ──

    notifyListeners();
  }

  /// Collect substring matches.
  void _collectMatches(
    String text,
    String lowerQuery,
    int originalLength,
    String documentId,
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
          documentId: documentId,
          pageIndex: pageIndex,
          startOffset: idx,
          endOffset: idx + originalLength,
          snippet: _extractSnippet(text, idx, originalLength),
        ),
      );
      searchFrom = idx + 1;
    }
  }

  /// Collect whole-word matches via regex.
  void _collectMatchesRegex(
    String text,
    RegExp pattern,
    int originalLength,
    String documentId,
    int pageIndex,
    List<PdfSearchMatch> results,
  ) {
    for (final m in pattern.allMatches(text)) {
      results.add(
        PdfSearchMatch(
          documentId: documentId,
          pageIndex: pageIndex,
          startOffset: m.start,
          endOffset: m.end,
          snippet: _extractSnippet(text, m.start, m.end - m.start),
        ),
      );
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

  /// Jump directly to match at [index].
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
    _pagesSearched = 0;
    _totalPagesToSearch = 0;
    _searchVersion++;
    _invalidateHighlightCache();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Highlight rects for rendering (with caching)
  // ---------------------------------------------------------------------------

  /// Get highlight rects for all matches on [page].
  ///
  /// Results are cached per (documentId, pageIndex) and invalidated when
  /// matches change. This avoids O(matches × textRects) per paint frame.
  List<Rect> highlightRectsForPage(
    PdfPageNode page, {
    bool currentOnly = false,
    String? documentId,
  }) {
    if (page.textRects == null || page.textRects!.isEmpty) return const [];

    final pageIndex = page.pageModel.pageIndex;

    // Current-only is never cached (changes on every navigation)
    if (currentOnly) {
      return _computeHighlightRects(page, pageIndex, documentId, true);
    }

    // Check cache
    final key = _hlCacheKey(documentId, pageIndex);
    final cached = _highlightRectCache[key];
    if (cached != null) return cached;

    // Compute and cache
    final rects = _computeHighlightRects(page, pageIndex, documentId, false);
    _highlightRectCache[key] = rects;
    return rects;
  }

  List<Rect> _computeHighlightRects(
    PdfPageNode page,
    int pageIndex,
    String? documentId,
    bool currentOnly,
  ) {
    final Iterable<PdfSearchMatch> pageMatches;

    if (currentOnly) {
      pageMatches =
          currentMatch != null &&
                  currentMatch!.pageIndex == pageIndex &&
                  (documentId == null || currentMatch!.documentId == documentId)
              ? [currentMatch!]
              : const <PdfSearchMatch>[];
    } else {
      pageMatches = _matches.where(
        (m) =>
            m.pageIndex == pageIndex &&
            (documentId == null || m.documentId == documentId),
      );
    }

    if (pageMatches.isEmpty) return const [];

    final rects = <Rect>[];
    final textRects = page.textRects!;
    final pgW = page.pageModel.originalSize.width;
    final pgH = page.pageModel.originalSize.height;

    // Minimum dimensions for visible highlights (in normalized 0-1 coords).
    // ~1.5% of page ≈ 12pt on a typical 792pt page — approximately one
    // standard text line height.
    const double minNormalizedHeight = 0.015;
    const double minNormalizedWidth = 0.003;

    // Y is always top-down after _normalizeRects (which flips bottom-up to
    // top-down during normalization). No Y-flip needed here.
    for (final match in pageMatches) {
      for (final tr in textRects) {
        final trEnd = tr.charOffset + tr.text.length;
        if (trEnd > match.startOffset && tr.charOffset < match.endOffset) {
          final trLen = tr.text.length;
          double left = tr.rect.left;
          double right = tr.rect.right;

          // Clip to match boundaries within the text rect
          if (trLen > 1) {
            final trWidth = tr.rect.width;
            final clipStart = (match.startOffset - tr.charOffset).clamp(
              0,
              trLen,
            );
            final clipEnd = (match.endOffset - tr.charOffset).clamp(0, trLen);

            // Use run-boundary charPositions when available for precision;
            // fall back to uniform subdivision otherwise.
            final cp = tr.charPositions;
            if (cp != null && clipEnd < cp.length) {
              left = tr.rect.left + cp[clipStart] * trWidth;
              right = tr.rect.left + cp[clipEnd] * trWidth;
            } else {
              left = tr.rect.left + (clipStart / trLen) * trWidth;
              right = tr.rect.left + (clipEnd / trLen) * trWidth;
            }
          }

          // Enforce minimum dimensions on degenerate rects (e.g. rects
          // whose height collapsed during CTM transform or normalization).
          double top = tr.rect.top;
          double bottom = tr.rect.bottom;
          if ((bottom - top) < minNormalizedHeight) {
            final midY = (top + bottom) / 2;
            top = (midY - minNormalizedHeight / 2).clamp(0.0, 1.0);
            bottom = (midY + minNormalizedHeight / 2).clamp(0.0, 1.0);
          }
          if ((right - left) < minNormalizedWidth) {
            right = (left + minNormalizedWidth).clamp(0.0, 1.0);
          }

          rects.add(
            Rect.fromLTRB(left * pgW, top * pgH, right * pgW, bottom * pgH),
          );
        }
      }
    }

    return rects;
  }

  /// Get the highlight rect for only the current match on [page].
  Rect? currentMatchRectForPage(PdfPageNode page, {String? documentId}) {
    if (currentMatch == null) return null;
    if (currentMatch!.pageIndex != page.pageModel.pageIndex) return null;
    if (documentId != null && currentMatch!.documentId != documentId) {
      return null;
    }

    final rects = highlightRectsForPage(
      page,
      currentOnly: true,
      documentId: documentId,
    );
    if (rects.isEmpty) return null;

    Rect union = rects.first;
    for (int i = 1; i < rects.length; i++) {
      union = union.expandToInclude(rects[i]);
    }
    return union;
  }

  /// Ensures [rects] are in normalized 0.0–1.0 coordinates with Y=0 at top.
  ///
  /// 1. Detects if rects are already normalized (values ≤ 1.5).
  /// 2. If not normalized, divides by the extractor's page dimensions.
  /// 3. Uses the extractor's [isYFlipped] flag (from CTM d-component):
  ///    - `isYFlipped = true` → CTM already made Y top-down, no flip needed.
  ///    - `isYFlipped = false` → standard bottom-up PDF, flip Y to top-down.
  static List<PdfTextRect> _normalizeRects(
    List<PdfTextRect> rects,
    double extractorWidth,
    double extractorHeight, {
    bool isYFlipped = false,
    double originX = 0,
    double originY = 0,
  }) {
    if (rects.isEmpty) return rects;

    // Standard bottom-up PDF needs Y-flip; CTM-flipped PDF does not.
    final needsYFlip = !isYFlipped;

    // Detect if already normalized: check a few rects for values > 1.5
    bool alreadyNormalized = true;
    for (final r in rects) {
      if (r.rect.right > 1.5 || r.rect.bottom > 1.5) {
        alreadyNormalized = false;
        break;
      }
    }

    if (alreadyNormalized) {
      if (!needsYFlip) return rects;
      // Flip Y on already-normalized rects
      return rects.map((r) {
        return PdfTextRect(
          rect: Rect.fromLTRB(
            r.rect.left,
            1.0 - r.rect.bottom,
            r.rect.right,
            1.0 - r.rect.top,
          ),
          text: r.text,
          charOffset: r.charOffset,
          charPositions: r.charPositions,
        );
      }).toList();
    }

    // Normalize using the extractor's page dimensions
    final pgW = extractorWidth;
    final pgH = extractorHeight;
    if (pgW <= 0 || pgH <= 0) return rects;

    return rects.map((r) {
      double nTop = ((r.rect.top - originY) / pgH).clamp(0.0, 1.0);
      double nBot = ((r.rect.bottom - originY) / pgH).clamp(0.0, 1.0);

      if (needsYFlip) {
        // Flip Y: bottom-up → top-down
        final flippedTop = 1.0 - nBot;
        final flippedBot = 1.0 - nTop;
        nTop = flippedTop;
        nBot = flippedBot;
      }

      return PdfTextRect(
        rect: Rect.fromLTRB(
          ((r.rect.left - originX) / pgW).clamp(0.0, 1.0),
          nTop,
          ((r.rect.right - originX) / pgW).clamp(0.0, 1.0),
          nBot,
        ),
        text: r.text,
        charOffset: r.charOffset,
        charPositions: r.charPositions,
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Get or load page text for a specific document (cached per-document).
  ///
  /// FIX (E): Always ensures textRects are populated on the pageNode, even
  /// when text was cached from a previous search. Re-extracts via Dart
  /// extractor if needed when native provider was used for text only.
  Future<String> _getPageText(
    String documentId,
    int pageIndex,
    int totalPageCount, {
    PdfPageNode? pageNode,
  }) async {
    final docState = _documents[documentId];
    if (docState == null) return '';

    // DEBUG: Force OCR path — skip all text extraction
    if (forceOcr && docState.provider != null) {
      if (docState.textCache.containsKey(pageIndex)) {
        // Repopulate textRects from OCR cache if needed
        if (pageNode != null && pageNode.textRects == null) {
          final cached = docState.ocrCache[pageIndex];
          if (cached != null) pageNode.textRects = cached.toTextRects();
        }
        return docState.textCache[pageIndex]!;
      }
      return _tryOcrFallback(documentId, pageIndex, pageNode: pageNode);
    }

    // Check text cache
    if (docState.textCache.containsKey(pageIndex)) {
      // (E) Repopulate textRects if missing on the node
      if (pageNode != null && pageNode.textRects == null) {
        // Try from Dart extraction cache first
        if (docState.extractedPages != null &&
            pageIndex < docState.extractedPages!.length) {
          final extracted = docState.extractedPages![pageIndex];
          if (extracted.rects.isNotEmpty) {
            // Use viewer's page dimensions (authoritative) for normalization
            // — extractor may report different dimensions (e.g. MediaBox
            //   612×792 vs CropBox 595×842).
            final viewW = pageNode.pageModel.originalSize.width;
            final viewH = pageNode.pageModel.originalSize.height;
            pageNode.textRects = _normalizeRects(
              extracted.rects,
              viewW > 0 ? viewW : extracted.pageWidth,
              viewH > 0 ? viewH : extracted.pageHeight,
              isYFlipped: extracted.isYFlipped,
              originX: extracted.originX,
              originY: extracted.originY,
            );
            // Sync text cache with Dart extractor text for charOffset alignment
            if (extracted.text.isNotEmpty) {
              docState.textCache[pageIndex] = extracted.text;
            }
          }
        }
        // If still missing (native provider path), trigger Dart extraction
        // just for rects
        if (pageNode.textRects == null) {
          try {
            docState.extractedPages ??= await PdfTextExtractor.extractInIsolate(
              docState.bytes,
              pageCount: totalPageCount,
            );
            if (pageIndex < docState.extractedPages!.length) {
              final extracted = docState.extractedPages![pageIndex];
              if (extracted.rects.isNotEmpty) {
                final viewW = pageNode.pageModel.originalSize.width;
                final viewH = pageNode.pageModel.originalSize.height;
                pageNode.textRects = _normalizeRects(
                  extracted.rects,
                  viewW > 0 ? viewW : extracted.pageWidth,
                  viewH > 0 ? viewH : extracted.pageHeight,
                  isYFlipped: extracted.isYFlipped,
                  originX: extracted.originX,
                  originY: extracted.originY,
                );
                if (extracted.text.isNotEmpty) {
                  docState.textCache[pageIndex] = extracted.text;
                }
              }
            }
          } catch (e, stack) {
            EngineScope.current.errorRecovery.reportError(
              EngineError(
                severity: ErrorSeverity.degraded,
                domain: ErrorDomain.rendering,
                source: 'PdfSearchController._getPageText.dartExtraction',
                original: e,
                stack: stack,
              ),
            );
          }
        }
      }
      return docState.textCache[pageIndex]!;
    }

    // Try native provider first
    if (docState.provider != null) {
      try {
        final text = await docState.provider!.getPageText(pageIndex);
        if (text.isNotEmpty) {
          // (E) Still need rects from Dart extraction for highlighting
          if (pageNode != null && pageNode.textRects == null) {
            try {
              docState
                  .extractedPages ??= await PdfTextExtractor.extractInIsolate(
                docState.bytes,
                pageCount: totalPageCount,
              );
              if (pageIndex < docState.extractedPages!.length) {
                final extracted = docState.extractedPages![pageIndex];
                final rects = extracted.rects;

                if (rects.isNotEmpty) {
                  final viewW = pageNode.pageModel.originalSize.width;
                  final viewH = pageNode.pageModel.originalSize.height;
                  pageNode.textRects = _normalizeRects(
                    rects,
                    viewW > 0 ? viewW : extracted.pageWidth,
                    viewH > 0 ? viewH : extracted.pageHeight,
                    isYFlipped: extracted.isYFlipped,
                    originX: extracted.originX,
                    originY: extracted.originY,
                  );
                  // CRITICAL: Use Dart extractor text so match offsets align
                  // with rect charOffsets (native text may differ in spacing)
                  if (extracted.text.isNotEmpty) {
                    // Diagnostic: compare native vs Dart text for first page
                    if (pageIndex == 0) {
                      final nativeSnip = text.substring(
                        0,
                        text.length.clamp(0, 50),
                      );
                      final dartSnip = extracted.text.substring(
                        0,
                        extracted.text.length.clamp(0, 50),
                      );
                      debugPrint('[PDF DBG] Native text p0: "$nativeSnip"');
                      debugPrint('[PDF DBG] Dart text p0:   "$dartSnip"');
                      debugPrint(
                        '[PDF DBG] Native len=${text.length}, '
                        'Dart len=${extracted.text.length}',
                      );
                    }
                    docState.textCache[pageIndex] = extracted.text;
                    return extracted.text;
                  }
                }
              } else {}
            } catch (e, stack) {
              EngineScope.current.errorRecovery.reportError(
                EngineError(
                  severity: ErrorSeverity.degraded,
                  domain: ErrorDomain.rendering,
                  source: 'PdfSearchController._getPageText.rectExtraction',
                  original: e,
                  stack: stack,
                ),
              );
            }
          }
          // Fallback: use native text if no Dart extraction available

          docState.textCache[pageIndex] = text;
          return text;
        }
      } catch (_) {
        // Native provider error — fall through to Dart extraction
      }
    }

    // Fallback: pure-Dart text extraction (isolate, non-blocking)
    try {
      docState.extractedPages ??= await PdfTextExtractor.extractInIsolate(
        docState.bytes,
        pageCount: totalPageCount,
      );
      if (pageIndex >= 0 && pageIndex < docState.extractedPages!.length) {
        final extracted = docState.extractedPages![pageIndex];
        docState.textCache[pageIndex] = extracted.text;
        if (pageNode != null && extracted.rects.isNotEmpty) {
          final viewW = pageNode.pageModel.originalSize.width;
          final viewH = pageNode.pageModel.originalSize.height;
          pageNode.textRects = _normalizeRects(
            extracted.rects,
            viewW > 0 ? viewW : extracted.pageWidth,
            viewH > 0 ? viewH : extracted.pageHeight,
            isYFlipped: extracted.isYFlipped,
          );
        }
        // If Dart extraction returned text, use it; otherwise try OCR
        if (extracted.text.isNotEmpty) {
          return extracted.text;
        }
      }
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.degraded,
          domain: ErrorDomain.rendering,
          source: 'PdfSearchController._getPageText.fallbackExtraction',
          original: e,
          stack: stack,
        ),
      );
    }

    // Fallback 3: OCR for scanned / image-based pages
    return _tryOcrFallback(documentId, pageIndex, pageNode: pageNode);
  }

  /// OCR fallback: runs native OCR on a scanned page and caches results.
  ///
  /// Called only when both native text extraction and Dart parsing return
  /// empty — indicating the page is likely image-based / scanned.
  ///
  /// ENTERPRISE FEATURES:
  /// - Telemetry span for performance monitoring
  /// - OCR result caching in _DocState to avoid re-processing
  /// - Per-page status tracking via OcrPageStatus
  /// - Confidence-based filtering to discard noise
  /// - Duration measurement attached to OcrPageResult
  Future<String> _tryOcrFallback(
    String documentId,
    int pageIndex, {
    PdfPageNode? pageNode,
  }) async {
    final docState = _documents[documentId];
    if (docState == null) return '';

    final ocrKey = '$documentId:$pageIndex';

    // Check per-page status — skip if already processed or in progress
    final status = _ocrStatus[ocrKey];
    if (status != null && status != OcrPageStatus.notAttempted) {
      // Return cached result if available
      if (status == OcrPageStatus.completed) {
        final cached = docState.ocrCache[pageIndex];
        if (cached != null && cached.isNotEmpty) {
          return cached.text;
        }
      }
      return '';
    }

    // No provider → mark as skipped
    if (docState.provider == null) {
      _ocrStatus[ocrKey] = OcrPageStatus.skipped;
      return '';
    }

    // Mark as in-progress
    _ocrStatus[ocrKey] = OcrPageStatus.inProgress;

    // Start telemetry span
    final span = EngineScope.current.telemetry.startSpan(
      'pdf.ocr.page',
      scope: TelemetryScope.io,
    );

    final stopwatch = Stopwatch()..start();

    try {
      final ocrResult = await docState.provider!.ocrPage(pageIndex);
      stopwatch.stop();
      span.end();

      if (ocrResult == null || ocrResult.isEmpty) {
        _ocrStatus[ocrKey] = OcrPageStatus.empty;
        EngineScope.current.telemetry.event('pdf.ocr.empty', {
          'documentId': documentId,
          'pageIndex': pageIndex,
          'durationMs': stopwatch.elapsedMilliseconds,
        });
        return '';
      }

      // Apply confidence filtering
      final filtered = ocrResult.filterByConfidence(ocrConfidenceThreshold);

      // Attach processing metadata
      final enriched = filtered.copyWith(
        processingDuration: stopwatch.elapsed,
        pageIndex: pageIndex,
      );

      // Record telemetry
      EngineScope.current.telemetry
          .histogram('pdf.ocr.durationMs')
          .record(stopwatch.elapsedMilliseconds.toDouble());
      EngineScope.current.telemetry.counter('pdf.ocr.pages').increment();
      EngineScope.current.telemetry.event('pdf.ocr.completed', {
        'documentId': documentId,
        'pageIndex': pageIndex,
        'blocks': enriched.blocks.length,
        'chars': enriched.text.length,
        'avgConfidence': enriched.averageConfidence,
        'durationMs': stopwatch.elapsedMilliseconds,
        'estimatedBytes': enriched.estimatedBytes,
      });

      debugPrint(
        '[PDF OCR] Page $pageIndex: ${enriched.blocks.length} blocks, '
        '${enriched.text.length} chars, '
        'avgConf=${enriched.averageConfidence?.toStringAsFixed(2) ?? "n/a"}, '
        '${stopwatch.elapsedMilliseconds}ms',
      );

      // Cache results
      _ocrStatus[ocrKey] = OcrPageStatus.completed;
      docState.ocrCache[pageIndex] = enriched;
      docState.textCache[pageIndex] = enriched.text;

      // Generate synthetic textRects from OCR blocks for highlighting
      if (pageNode != null) {
        pageNode.textRects = enriched.toTextRects();
      }

      return enriched.text;
    } catch (e, stack) {
      stopwatch.stop();
      span.end();

      _ocrStatus[ocrKey] = OcrPageStatus.failed;
      EngineScope.current.telemetry.counter('pdf.ocr.errors').increment();
      EngineScope.current.telemetry.event('pdf.ocr.failed', {
        'documentId': documentId,
        'pageIndex': pageIndex,
        'error': e.toString(),
        'durationMs': stopwatch.elapsedMilliseconds,
      });

      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.degraded,
          domain: ErrorDomain.rendering,
          source: 'PdfSearchController._tryOcrFallback',
          original: e,
          stack: stack,
        ),
      );
      return '';
    }
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

  /// Invalidate text cache for all documents.
  void invalidateCache() {
    for (final doc in _documents.values) {
      doc.textCache.clear();
      doc.extractedPages = null;
      doc.ocrCache.clear();
    }
    _ocrStatus.clear();
    _invalidateHighlightCache();
  }

  /// Invalidate cache for a specific document.
  void invalidateCacheFor(String documentId) {
    final doc = _documents[documentId];
    if (doc != null) {
      doc.textCache.clear();
      doc.extractedPages = null;
      doc.ocrCache.clear();
    }
    _ocrStatus.removeWhere((k, _) => k.startsWith('$documentId:'));
    _invalidateHighlightCache();
  }

  /// Get the OCR status for a specific page.
  OcrPageStatus getOcrStatus(String documentId, int pageIndex) =>
      _ocrStatus['$documentId:$pageIndex'] ?? OcrPageStatus.notAttempted;

  /// Get all cached OCR results for a document.
  Map<int, OcrPageResult> getOcrCache(String documentId) =>
      Map.unmodifiable(_documents[documentId]?.ocrCache ?? {});

  @override
  void dispose() {
    _documents.clear();
    _highlightRectCache.clear();
    _matches = const [];
    super.dispose();
  }
}
