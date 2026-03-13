import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  const HandwritingSearchOverlay({
    super.key,
    this.canvasId,
    required this.onNavigate,
    required this.onDismiss,
    required this.onResultsChanged,
  });

  @override
  State<HandwritingSearchOverlay> createState() =>
      _HandwritingSearchOverlayState();
}

class _HandwritingSearchOverlayState extends State<HandwritingSearchOverlay>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<HandwritingSearchResult> _results = [];
  int _activeResultIndex = -1;
  bool _isSearching = false;
  Timer? _debounce;

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
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _performSearch);
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

    final results = await HandwritingIndexService.instance.search(
      query,
      canvasId: widget.canvasId,
      limit: 50,
    );

    if (!mounted) return;
    setState(() {
      _results = results;
      _activeResultIndex = results.isNotEmpty ? 0 : -1;
      _isSearching = false;
    });
    widget.onResultsChanged(results);

    // Auto-navigate to first result
    if (results.isNotEmpty) {
      widget.onNavigate(results.first);
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
            }
          }
        },
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, topPadding + 8, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Search Bar ──
              _buildSearchBar(isDark),

              // ── Results ──
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildResultsList(isDark),
              ],
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
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
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
              const SizedBox(width: 10),
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
    final shown = _results.take(8).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 280),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: shown.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 44,
              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
            ),
            itemBuilder: (context, index) {
              final result = shown[index];
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
                          Icons.draw_rounded,
                          size: 14,
                          color: isActive
                              ? Colors.deepPurple
                              : (isDark ? Colors.white30 : Colors.black26),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          result.recognizedText,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.w400,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
            },
          ),
        ),
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
