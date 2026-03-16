import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/digital_text_element.dart';
import '../../services/handwriting_index_service.dart';

// =============================================================================
// 🔍 Handwriting Search Overlay — iOS-style floating search bar
//
// Premium glassmorphism search overlay with live search-as-you-type,
// ranked results list, and tap-to-navigate. Integrates with the
// HandwritingIndexService for FTS5-powered search.
// =============================================================================

/// Callback to scroll canvas to a specific bounds.
typedef OnNavigateToResult = void Function(
  HandwritingSearchResult result,
);

/// Floating search overlay for handwritten content.
///
/// Shows a glassmorphic search bar at the top of the canvas with
/// live results as the user types. Tapping a result scrolls the
/// canvas to the matched stroke and highlights it.
class HandwritingSearchOverlay extends StatefulWidget {
  final String? canvasId;
  final OnNavigateToResult onNavigate;
  final VoidCallback onDismiss;
  final ValueChanged<List<HandwritingSearchResult>> onResultsChanged;
  final List<DigitalTextElement> textElements;

  /// Callback for Find & Replace: updates a DigitalTextElement's text.
  final void Function(String elementId, String oldText, String newText)?
      onReplaceText;

  /// Returns the current visible viewport rect in canvas coordinates.
  /// Used for "search visible area only" toggle.
  final ui.Rect Function()? getViewportRect;

  const HandwritingSearchOverlay({
    super.key,
    this.canvasId,
    required this.onNavigate,
    required this.onDismiss,
    required this.onResultsChanged,
    this.textElements = const [],
    this.onReplaceText,
    this.getViewportRect,
  });

  @override
  State<HandwritingSearchOverlay> createState() =>
      _HandwritingSearchOverlayState();
}

class _HandwritingSearchOverlayState extends State<HandwritingSearchOverlay>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _replaceController = TextEditingController();
  final _focusNode = FocusNode();
  List<HandwritingSearchResult> _results = [];
  int _activeResultIndex = -1;
  bool _isSearching = false;
  bool _searchAllCanvases = false;
  bool _showReplace = false;
  bool _caseSensitive = false;
  bool _wholeWord = false;
  bool _fuzzy = false;
  bool _visibleAreaOnly = false;
  bool _useRegex = false;
  List<String> _suggestions = [];
  Timer? _debounce;
  StreamSubscription? _indexSub;
  int _shownCount = 8; // Pagination: how many results to show
  int _indexedCount = 0; // Number of indexed strokes

  /// Recent search history (persistent via SQLite).
  static List<String> _recentSearches = [];

  late final AnimationController _animController;
  late final Animation<double> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnim = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );

    _animController.forward();
    _focusNode.requestFocus();
    _controller.addListener(_onQueryChanged);

    // 🔍 Fix 5: Live refresh when index changes (new strokes indexed)
    _indexSub = HandwritingIndexService.instance.onIndexChanged.listen((_) {
      if (_controller.text.trim().isNotEmpty) _performSearch();
      _loadIndexedCount();
    });
    _loadIndexedCount();
    _loadHistory();
  }

  Future<void> _loadIndexedCount() async {
    final count = await HandwritingIndexService.instance
        .getIndexedStrokeCount(canvasId: widget.canvasId);
    if (mounted) setState(() => _indexedCount = count);
  }

  Future<void> _loadHistory() async {
    final history = await HandwritingIndexService.instance.loadSearchHistory(limit: 5);
    if (mounted) setState(() => _recentSearches = history);
  }

  @override
  void dispose() {
    _indexSub?.cancel();
    _debounce?.cancel();
    _controller.dispose();
    _replaceController.dispose();
    _focusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    // Adaptive debounce: short queries (noisy) → longer delay
    final len = _controller.text.trim().length;
    final delay = len <= 2 ? 500 : 200;
    _debounce = Timer(Duration(milliseconds: delay), _performSearch);

    // Fetch suggestions immediately (lightweight query)
    final text = _controller.text.trim();
    if (text.isNotEmpty && text.length >= 2) {
      HandwritingIndexService.instance
          .getSuggestions(
            text,
            canvasId: _searchAllCanvases ? null : widget.canvasId,
          )
          .then((suggestions) {
        if (mounted) setState(() => _suggestions = suggestions);
      });
    } else {
      setState(() => _suggestions = []);
    }
  }

  Future<void> _performSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _activeResultIndex = -1;
        _isSearching = false;
      });
      widget.onResultsChanged([]);
      return;
    }

    setState(() => _isSearching = true);

    final results = await HandwritingIndexService.instance.searchUnified(
      query,
      canvasId: _searchAllCanvases ? null : widget.canvasId,
      textElements: _searchAllCanvases ? const [] : widget.textElements,
      limit: 50,
      caseSensitive: _caseSensitive,
      wholeWord: _wholeWord,
      fuzzy: _fuzzy,
    );

    if (!mounted) return;

    // Sort by canvas position: top→bottom, then left→right
    results.sort((a, b) {
      final dy = a.bounds.top.compareTo(b.bounds.top);
      return dy != 0 ? dy : a.bounds.left.compareTo(b.bounds.left);
    });

    setState(() {
      _results = results;
      _activeResultIndex = results.isNotEmpty ? 0 : -1;
      _isSearching = false;
      _suggestions = []; // Clear suggestions when results arrive
      _shownCount = 8; // Reset pagination on new search
    });

    // Post-filter: visible area only
    if (_visibleAreaOnly && widget.getViewportRect != null) {
      final vp = widget.getViewportRect!();
      final filtered = _results.where((r) => vp.overlaps(r.bounds)).toList();
      setState(() {
        _results = filtered;
        _activeResultIndex = filtered.isNotEmpty ? 0 : -1;
      });
    }

    // Post-filter: regex mode
    if (_useRegex && _controller.text.trim().isNotEmpty) {
      try {
        final re = RegExp(_controller.text.trim(),
            caseSensitive: _caseSensitive);
        final filtered = _results.where((r) => re.hasMatch(r.recognizedText)).toList();
        setState(() {
          _results = filtered;
          _activeResultIndex = filtered.isNotEmpty ? 0 : -1;
        });
      } catch (_) {
        // Invalid regex — ignore filter
      }
    }
    widget.onResultsChanged(results);

    // Auto-navigate to first result
    if (results.isNotEmpty) {
      widget.onNavigate(results.first);
      // Add to search history
      final q = _controller.text.trim();
      if (q.isNotEmpty) {
        _recentSearches.remove(q);
        _recentSearches.insert(0, q);
        if (_recentSearches.length > 5) _recentSearches.removeLast();
        // Persist to SQLite
        HandwritingIndexService.instance.saveSearchHistory(q);
      }
    }
  }

  void _navigateToResult(int index) {
    if (index < 0 || index >= _results.length) return;
    setState(() => _activeResultIndex = index);
    widget.onNavigate(_results[index]);
    HapticFeedback.selectionClick();
  }

  void _nextResult() {
    if (_results.isEmpty) return;
    _navigateToResult((_activeResultIndex + 1) % _results.length);
  }

  void _previousResult() {
    if (_results.isEmpty) return;
    _navigateToResult(
      (_activeResultIndex - 1 + _results.length) % _results.length,
    );
  }

  Future<void> _dismiss() async {
    await _animController.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnim.value,
          child: Transform.translate(
            offset: Offset(0, _slideAnim.value * 60),
            child: child,
          ),
        );
      },
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _dismiss();
            } else if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _nextResult();
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _previousResult();
            } else if (event.logicalKey == LogicalKeyboardKey.keyH &&
                (HardwareKeyboard.instance.isControlPressed ||
                    HardwareKeyboard.instance.isMetaPressed)) {
              // Ctrl+H / Cmd+H → toggle Replace row
              setState(() => _showReplace = !_showReplace);
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Search Bar ──
              _buildSearchBar(isDark),

              // ── Replace Row (Find & Replace) ──
              if (_showReplace && widget.onReplaceText != null) ...[
                const SizedBox(height: 4),
                _buildReplaceRow(isDark),
              ],

              // ── Suggestion Chips ──
              if (_suggestions.isNotEmpty && _results.isEmpty) ...[
                const SizedBox(height: 6),
                _buildSuggestionChips(isDark),
              ],

              // ── Recent Search History ──
              if (_controller.text.isEmpty &&
                  _recentSearches.isNotEmpty &&
                  _results.isEmpty) ...[
                const SizedBox(height: 6),
                _buildHistoryChips(isDark),
              ],

              // ── Results or Empty State ── (animated expand/collapse)
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_results.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildResultsList(isDark)),
                          // ── Search Minimap ──
                          if (_results.length > 1)
                            _buildMinimap(isDark),
                        ],
                      ),
                    ] else if (_controller.text.trim().isNotEmpty && !_isSearching) ...[
                      const SizedBox(height: 6),
                      _buildEmptyState(isDark),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            // Use a tinted off-white so the bar stands out on any canvas bg
            color: isDark
                ? const Color(0xFF2A2535) // dark purple-gray
                : const Color(0xFFF5F3F8), // warm lavender-tinted gray
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.deepPurple.withValues(alpha: 0.15),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                Icons.search_rounded,
                size: 20,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              const SizedBox(width: 6),
              // 🔍 Toggle chips row — scrollable to fit all toggles
              Flexible(
                flex: 0,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildToggleChip(
                        label: _searchAllCanvases ? 'All pages' : 'This page',
                        icon: _searchAllCanvases
                            ? Icons.language_rounded
                            : Icons.description_outlined,
                        isActive: _searchAllCanvases,
                        isDark: isDark,
                        onTap: () {
                          setState(() => _searchAllCanvases = !_searchAllCanvases);
                          if (_controller.text.trim().isNotEmpty) _performSearch();
                        },
                      ),
                      const SizedBox(width: 3),
                      _buildToggleChip(
                        label: 'Aa',
                        isActive: _caseSensitive,
                        isDark: isDark,
                        tooltip: _caseSensitive ? 'Case sensitive' : 'Case insensitive',
                        onTap: () {
                          setState(() => _caseSensitive = !_caseSensitive);
                          if (_controller.text.trim().isNotEmpty) _performSearch();
                        },
                      ),
                      const SizedBox(width: 3),
                      _buildToggleChip(
                        label: 'Word',
                        isActive: _wholeWord,
                        isDark: isDark,
                        tooltip: _wholeWord ? 'Whole word' : 'Substring match',
                        onTap: () {
                          setState(() => _wholeWord = !_wholeWord);
                          if (_controller.text.trim().isNotEmpty) _performSearch();
                        },
                      ),
                      const SizedBox(width: 3),
                      _buildToggleChip(
                        label: 'Fuzzy',
                        icon: null,
                        isActive: _fuzzy,
                        isDark: isDark,
                        tooltip: _fuzzy
                            ? 'Fuzzy match (≤2 typos)'
                            : 'Exact match only',
                        onTap: () {
                          setState(() => _fuzzy = !_fuzzy);
                          if (_controller.text.trim().isNotEmpty) _performSearch();
                        },
                      ),
                      const SizedBox(width: 3),
                      _buildToggleChip(
                        label: 'Regex',
                        icon: null,
                        isActive: _useRegex,
                        isDark: isDark,
                        tooltip: _useRegex
                            ? 'Regex mode active'
                            : 'Enable regex patterns',
                        onTap: () {
                          setState(() => _useRegex = !_useRegex);
                          if (_controller.text.trim().isNotEmpty) _performSearch();
                        },
                      ),
                      if (widget.getViewportRect != null) ...[
                        const SizedBox(width: 3),
                        _buildToggleChip(
                          label: 'Visible',
                          icon: Icons.visibility_rounded,
                          isActive: _visibleAreaOnly,
                          isDark: isDark,
                          tooltip: _visibleAreaOnly
                              ? 'Visible area only'
                              : 'Search entire canvas',
                          onTap: () {
                            setState(() => _visibleAreaOnly = !_visibleAreaOnly);
                            if (_controller.text.trim().isNotEmpty) _performSearch();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Search handwriting...',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white30 : Colors.black26,
                      fontSize: 15,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),

              // Match count badge
              if (_results.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_activeResultIndex + 1}/${_results.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ),

              if (_isSearching)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark ? Colors.white38 : Colors.black26,
                    ),
                  ),
                ),

              // Navigation arrows
              if (_results.length > 1) ...[
                _NavButton(
                  icon: Icons.keyboard_arrow_up_rounded,
                  onTap: _previousResult,
                  isDark: isDark,
                ),
                _NavButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  onTap: _nextResult,
                  isDark: isDark,
                ),
              ],

              // Replace toggle
              if (widget.onReplaceText != null)
                _NavButton(
                  icon: _showReplace
                      ? Icons.find_replace_rounded
                      : Icons.find_replace_rounded,
                  onTap: () => setState(() => _showReplace = !_showReplace),
                  isDark: isDark,
                ),

              // Close button
              _NavButton(
                icon: Icons.close_rounded,
                onTap: _dismiss,
                isDark: isDark,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList(bool isDark) {
    final queryText = _controller.text.trim();

    // Split results into handwriting and typed text groups
    final hwResults = <MapEntry<int, HandwritingSearchResult>>[];
    final txtResults = <MapEntry<int, HandwritingSearchResult>>[];
    final shown = _results.take(_shownCount).toList();
    for (int i = 0; i < shown.length; i++) {
      if (shown[i].isTextElement) {
        txtResults.add(MapEntry(i, shown[i]));
      } else {
        hwResults.add(MapEntry(i, shown[i]));
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 320),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF2A2535)
                : const Color(0xFFF5F3F8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.deepPurple.withValues(alpha: 0.10),
            ),
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              // ── Handwriting section ──
              if (hwResults.isNotEmpty) ...[
                _buildSectionHeader('✍️ Handwriting', hwResults.length, isDark),
                ...hwResults.map((e) =>
                    _buildSearchResultItem(e.value, e.key, queryText, isDark)),
              ],
              // ── Typed text section ──
              if (txtResults.isNotEmpty) ...[
                if (hwResults.isNotEmpty)
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                  ),
                _buildSectionHeader('📝 Typed text', txtResults.length, isDark),
                ...txtResults.map((e) =>
                    _buildSearchResultItem(e.value, e.key, queryText, isDark)),
              ],
              // ── "Show more" button ──
              if (_results.length > _shownCount)
                InkWell(
                  onTap: () => setState(() => _shownCount += 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    child: Text(
                      'Show ${(_results.length - _shownCount).clamp(0, 8)} more…',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.deepPurple.shade300,
                      ),
                    ),
                  ),
                ),
              // ── Footer with hints + copy + index count ──
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_results.length} results · $_indexedCount indexed · ↑↓ Esc',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                    ),
                    // Copy all results button
                    GestureDetector(
                      onTap: () {
                        final allText = _results
                            .map((r) => r.recognizedText)
                            .toSet()
                            .join('\n');
                        Clipboard.setData(ClipboardData(text: allText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied ${_results.length} results'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a compact labeled toggle chip for the search bar.
  Widget _buildToggleChip({
    required String label,
    IconData? icon,
    required bool isActive,
    required bool isDark,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final color = isActive
        ? Colors.deepPurple
        : (isDark ? Colors.white30 : Colors.black26);

    final chip = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.deepPurple.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );

    return tooltip != null
        ? Tooltip(message: tooltip, child: chip)
        : chip;
  }

  Widget _buildSectionHeader(String title, int count, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white30 : Colors.black26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultItem(
    HandwritingSearchResult result,
    int index,
    String queryText,
    bool isDark,
  ) {
    final isActive = index == _activeResultIndex;
    return InkWell(
      onTap: () => _navigateToResult(index),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark
                  ? Colors.deepPurple.withValues(alpha: 0.2)
                  : Colors.deepPurple.withValues(alpha: 0.08))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.deepPurple.withValues(alpha: 0.15)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04)),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Icon(
                result.isTextElement
                    ? Icons.text_fields_rounded
                    : Icons.draw_rounded,
                size: 14,
                color: isActive
                    ? Colors.deepPurple
                    : (isDark ? Colors.white30 : Colors.black26),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHighlightedText(
                    _extractContext(result.recognizedText, queryText),
                    queryText,
                    isDark: isDark,
                    isActive: isActive,
                  ),
                  // Multi-canvas label
                  if (_searchAllCanvases && result.canvasId.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '📄 ${result.canvasId.length > 12 ? '${result.canvasId.substring(0, 12)}…' : result.canvasId}',
                        style: TextStyle(
                          fontSize: 9,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (isActive)
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: Colors.deepPurple.withValues(alpha: 0.6),
              ),
          ],
        ),
      ),
    );
  }

  /// Extract a context window around the query match in long text.
  ///
  /// For short text (<= 25 chars), returns as-is.
  /// For long text, extracts ~15 chars before and after the first match
  /// with ellipsis for context.
  String _extractContext(String text, String query) {
    if (text.length <= 25 || query.isEmpty) return text;

    final idx = text.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) return text;

    const windowSize = 15;
    final start = (idx - windowSize).clamp(0, text.length);
    final end = (idx + query.length + windowSize).clamp(0, text.length);

    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return '$prefix${text.substring(start, end)}$suffix';
  }

  /// Builds a text widget with the matching query highlighted.
  Widget _buildHighlightedText(
    String text,
    String query, {
    required bool isDark,
    required bool isActive,
  }) {
    if (query.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          color: isDark ? Colors.white : Colors.black87,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    int start = 0;

    while (start < text.length) {
      final matchIdx = lowerText.indexOf(lowerQuery, start);
      if (matchIdx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      // Text before match
      if (matchIdx > start) {
        spans.add(TextSpan(text: text.substring(start, matchIdx)));
      }
      // Matched portion — highlighted with background
      spans.add(TextSpan(
        text: text.substring(matchIdx, matchIdx + query.length),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.deepPurple.shade300,
          backgroundColor: Colors.deepPurple.withValues(alpha: 0.12),
        ),
      ));
      start = matchIdx + query.length;
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 14,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          color: isDark ? Colors.white : Colors.black87,
        ),
        children: spans,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Empty state when query has no matches.
  /// Builds a thin vertical minimap showing result positions on the canvas.
  Widget _buildMinimap(bool isDark) {
    // Compute the bounding box of all results
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final r in _results) {
      if (r.bounds.top < minY) minY = r.bounds.top;
      if (r.bounds.bottom > maxY) maxY = r.bounds.bottom;
    }
    final range = (maxY - minY).clamp(1, double.infinity);

    return Container(
      width: 20,
      constraints: const BoxConstraints(maxHeight: 320),
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(4),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          return Stack(
            children: [
              for (int i = 0; i < _results.length; i++)
                Positioned(
                  top: (((_results[i].bounds.center.dy - minY) / range) *
                          (height - 8))
                      .clamp(0, height - 8),
                  left: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => _navigateToResult(i),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _activeResultIndex
                            ? Colors.deepPurple
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.deepPurple.withValues(alpha: 0.25)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF2A2535)
                : const Color(0xFFF5F3F8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.deepPurple.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 20,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No results found',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white30 : Colors.black38,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Replace Row ──────────────────────────────────────────────────────────

  Widget _buildReplaceRow(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF2A2535)
                : const Color(0xFFF5F3F8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.deepPurple.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                Icons.swap_horiz_rounded,
                size: 18,
                color: isDark ? Colors.white38 : Colors.black26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _replaceController,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Replace with...',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white24 : Colors.black26,
                      fontSize: 14,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              // Replace button
              if (_activeResultIndex >= 0 &&
                  _activeResultIndex < _results.length &&
                  _results[_activeResultIndex].isTextElement)
                GestureDetector(
                  onTap: _replaceActive,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Replace',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.deepPurple.shade300,
                      ),
                    ),
                  ),
                ),
              // Replace All button
              if (_results.any((r) => r.isTextElement))
                GestureDetector(
                  onTap: _replaceAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'All',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.deepPurple.shade200,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _replaceActive() {
    if (_activeResultIndex < 0 || _activeResultIndex >= _results.length) return;
    final result = _results[_activeResultIndex];
    if (!result.isTextElement || widget.onReplaceText == null) return;
    widget.onReplaceText!(
      result.strokeId,
      _controller.text.trim(),
      _replaceController.text,
    );
    HapticFeedback.lightImpact();
    _performSearch(); // Refresh results
  }

  void _replaceAll() {
    if (widget.onReplaceText == null) return;
    final textResults = _results.where((r) => r.isTextElement).toList();
    for (final result in textResults) {
      widget.onReplaceText!(
        result.strokeId,
        _controller.text.trim(),
        _replaceController.text,
      );
    }
    HapticFeedback.mediumImpact();
    _performSearch(); // Refresh results
  }

  // ── Suggestion Chips ────────────────────────────────────────────────────

  Widget _buildSuggestionChips(bool isDark) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () {
              _controller.text = _suggestions[index];
              _controller.selection = TextSelection.collapsed(
                offset: _suggestions[index].length,
              );
              _performSearch();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.deepPurple.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.deepPurple.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                _suggestions[index],
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.deepPurple.shade300,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── History Chips ────────────────────────────────────────────────────────

  Widget _buildHistoryChips(bool isDark) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: _recentSearches.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () {
              _controller.text = _recentSearches[index];
              _controller.selection = TextSelection.collapsed(
                offset: _recentSearches[index].length,
              );
              _performSearch();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 12,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _recentSearches[index],
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  const _NavButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        child: Icon(
          icon,
          size: 22,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
      ),
    );
  }
}
