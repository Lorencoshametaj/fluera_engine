// ============================================================================
// 🎯 SocraticScopePicker — Search-first cluster scope picker.
//
// SCALE: the canvas can hold 10k-50k+ clusters (see `project_canvas_scale`).
// A chip-wall picker that renders every cluster as a button would freeze
// the UI and exhaust the GPU. This picker therefore:
//
//   1. Defaults to showing the viewport-visible clusters (typically ≤50).
//   2. Exposes a search box that ranks results across the full canvas.
//   3. Renders at most ~20 results at a time as a virtualized list.
//   4. Resolves titles / OCR text LAZILY via the host-provided callbacks —
//      no eager iteration of `_clusterCache`.
//   5. Caps selection at 10 to keep the downstream Socratic batch bounded.
//
// Returns the selected cluster IDs (or null when dismissed) via Navigator.pop.
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';

import '../../l10n/fluera_localizations.dart';
import '../../reflow/content_cluster.dart';

/// Lazy resolver — returns a cached title/text for the cluster id, or
/// null when not yet computed. Picker must NEVER trigger an expensive
/// network/OCR call from inside these — they are peek-only.
typedef ClusterStringResolver = String? Function(String clusterId);

/// Lazy resolution callback — picker fires this for clusters it intends
/// to display whose title/text isn't yet cached. Implementation must
/// kick off OCR + cleanedOcr + title generation off-thread and return
/// when DONE so the picker can re-render with the resolved labels.
/// The picker dedupes by cluster id so the callback is invoked at most
/// once per id per picker lifetime — safe to be expensive (Gemini call).
typedef ClusterLazyResolver = Future<void> Function(List<String> clusterIds);

class SocraticScopePicker extends StatefulWidget {
  /// Full list of clusters on the canvas. The picker iterates this only
  /// for ranking (cheap string compare) and never builds a widget per
  /// cluster — only the top-N ranked results render.
  final List<ContentCluster> allClusters;

  /// IDs of clusters that overlap the current viewport. These rank highest
  /// when the search field is empty.
  final Set<String> viewportClusterIds;

  /// Returns the AI-generated title for the cluster if already cached, else
  /// null. The picker uses this for display and search matching.
  final ClusterStringResolver titleResolver;

  /// Returns the OCR text for the cluster if already cached, else null.
  /// Used as the fallback display when no title is set, and as a secondary
  /// search target.
  final ClusterStringResolver textResolver;

  /// Initially-checked cluster IDs (typically the viewport set).
  final Set<String> initialSelectedClusterIds;

  /// Maximum number of clusters the user can select. Downstream Socratic
  /// batch caps at 8 slots anyway — 10 keeps a small margin for picker UX.
  final int selectionCap;

  /// Optional lazy resolver — when provided, the picker calls this for
  /// clusters it wants to display whose title/text isn't yet cached.
  /// Typical use: off-viewport clusters whose OCR + title generation
  /// was skipped on activation for scale safety. The resolver is invoked
  /// at most once per cluster id per picker session.
  final ClusterLazyResolver? lazyResolve;

  const SocraticScopePicker({
    super.key,
    required this.allClusters,
    required this.viewportClusterIds,
    required this.titleResolver,
    required this.textResolver,
    this.initialSelectedClusterIds = const {},
    this.selectionCap = 10,
    this.lazyResolve,
  });

  @override
  State<SocraticScopePicker> createState() => _SocraticScopePickerState();

  /// Convenience launcher — opens as a modal bottom sheet themed to match
  /// the Socratic summary. Returns the selected ids (or null on dismiss).
  static Future<Set<String>?> show({
    required BuildContext context,
    required List<ContentCluster> allClusters,
    required Set<String> viewportClusterIds,
    required ClusterStringResolver titleResolver,
    required ClusterStringResolver textResolver,
    Set<String> initialSelectedClusterIds = const {},
    int selectionCap = 10,
    ClusterLazyResolver? lazyResolve,
  }) {
    return showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SocraticScopePicker(
        allClusters: allClusters,
        viewportClusterIds: viewportClusterIds,
        titleResolver: titleResolver,
        textResolver: textResolver,
        initialSelectedClusterIds: initialSelectedClusterIds,
        selectionCap: selectionCap,
        lazyResolve: lazyResolve,
      ),
    );
  }
}

class _ScopeResult {
  final String id;
  final String title;
  final bool inViewport;
  _ScopeResult(this.id, this.title, this.inViewport);
}

class _SocraticScopePickerState extends State<SocraticScopePicker> {
  static const _accent = Color(0xFFFFD54F);
  static const _bgTop = Color(0xFF0F1028);
  static const _bgBottom = Color(0xFF060612);
  // Max results rendered in the list. The full canvas can have 10k+
  // clusters; we never paint more than this regardless of search.
  static const _maxResults = 20;

  late final Set<String> _selected;
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<_ScopeResult> _results = const [];
  /// Cluster ids for which `lazyResolve` has already been kicked off
  /// in this picker session. Prevents duplicate Gemini calls when the
  /// build/scoring loop re-renders the same off-viewport clusters.
  final Set<String> _lazyRequestedIds = {};
  /// Cluster ids for which the lazy resolver has FINISHED (success OR
  /// skip — e.g. cluster has no strokes to OCR). Used to differentiate
  /// "still loading" from "resolved-but-no-content" in the display, so
  /// empty clusters don't render as "caricamento…" forever.
  final Set<String> _resolvedClusterIds = {};

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelectedClusterIds};
    _recomputeResults();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Kick off lazy resolution for displayed clusters that don't yet have
  /// title or text resolved. Dedupes via [_lazyRequestedIds] so each id
  /// fires at most once. When the resolver completes we recompute results
  /// so the freshly-resolved labels become visible.
  void _maybeLazyResolve() {
    final resolver = widget.lazyResolve;
    if (resolver == null) return;
    final needed = <String>[];
    for (final r in _results) {
      if (_lazyRequestedIds.contains(r.id)) continue;
      // Already resolved? Skip.
      if (widget.titleResolver(r.id) != null) continue;
      if ((widget.textResolver(r.id) ?? '').trim().isNotEmpty) continue;
      needed.add(r.id);
      _lazyRequestedIds.add(r.id);
    }
    if (needed.isEmpty) return;
    // Fire-and-forget; recompute when done. Don't await inside build —
    // schedule the callback for the next microtask.
    unawaited(() async {
      await resolver(needed);
      if (!mounted) return;
      // Mark FINISHED — success or skip. The display below uses this to
      // distinguish "loading" from "no content".
      _resolvedClusterIds.addAll(needed);
      setState(_recomputeResults);
    }());
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _query = raw.trim().toLowerCase();
        _recomputeResults();
      });
    });
  }

  /// Score-and-sort the cluster list, capping at [_maxResults]. Runs on
  /// every keystroke (debounced 200ms). The scoring is pure string contains
  /// + viewport boost — O(N) per call where N = total canvas clusters.
  /// At N=10k this is ~few ms on a modern CPU; the search is the only
  /// linear pass over the full canvas, and it's behind a debounce.
  void _recomputeResults() {
    final q = _query;
    final scored = <({_ScopeResult result, double score})>[];
    int offViewportCounter = 0;
    for (final c in widget.allClusters) {
      final title = widget.titleResolver(c.id);
      final text = widget.textResolver(c.id);
      final inViewport = widget.viewportClusterIds.contains(c.id);
      final isSelected = _selected.contains(c.id);

      double score = 0;
      if (q.isEmpty) {
        // Default order: viewport clusters first (score 100), then
        // off-viewport clusters in canvas-order with a small descending
        // tiebreaker so the first ones in `allClusters` rank above the
        // rest. This shows a representative slice of the canvas without
        // requiring the student to type. Capped to `_maxResults` total.
        if (inViewport) {
          score = 100;
        } else {
          // Descending tiebreaker so first-encountered off-viewport
          // clusters win the top spots. With clusters detected in
          // spatial order, this tends to put nearby off-viewport
          // clusters first.
          score = 10 - (offViewportCounter * 0.001);
          offViewportCounter++;
        }
      } else {
        if (title != null && title.toLowerCase().contains(q)) score += 10;
        if (text != null && text.toLowerCase().contains(q)) score += 5;
        if (inViewport) score += 2;
      }
      // Selected items always remain reachable so the user can deselect.
      if (isSelected) score += 1;

      if (score == 0) continue;

      final hasTitle = title != null && title.trim().isNotEmpty;
      final hasText = text != null && text.trim().isNotEmpty;
      final wasResolved = _resolvedClusterIds.contains(c.id);

      // 🚫 Hide clusters that resolved with no extractable text
      // (doodles, scribbles, sparse strokes MyScript couldn't parse,
      // shapes-only clusters). They take a precious top-20 slot but
      // can't be sensibly interrogated — the Socratic batch needs OCR
      // text to anchor the question. Keep them visible ONLY when the
      // student has already selected them (so deselect remains possible).
      if (!hasTitle && !hasText && wasResolved && !isSelected) {
        continue;
      }

      final display = hasTitle
          ? title.trim()
          : hasText
              ? (text.length > 36 ? '${text.substring(0, 36)}…' : text)
              : (widget.lazyResolve != null && !wasResolved)
                  // Off-viewport cluster whose lazy resolve hasn't fired
                  // yet OR is still in flight.
                  ? 'Argomento (caricamento…)'
                  // Reaches here only when a currently-selected cluster
                  // resolved to empty (kept visible so the student can
                  // deselect it).
                  : 'Argomento senza testo';

      scored.add((
        result: _ScopeResult(c.id, display, inViewport),
        score: score,
      ));
      // Early exit when the score is high enough to guarantee a top slot
      // and we already have many candidates — keeps worst-case O(N) but
      // memory bounded.
      if (scored.length > _maxResults * 4) {
        scored.sort((a, b) => b.score.compareTo(a.score));
        scored.removeRange(_maxResults * 2, scored.length);
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    _results = scored.take(_maxResults).map((s) => s.result).toList();
    // Kick off lazy OCR/title for displayed clusters that don't yet have
    // a label. Deduped — each id fires at most once per picker session.
    _maybeLazyResolve();
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (_selected.length < widget.selectionCap) {
        _selected.add(id);
      }
    });
  }

  void _selectAllViewport() {
    setState(() {
      _selected.clear();
      for (final id in widget.viewportClusterIds) {
        if (_selected.length >= widget.selectionCap) break;
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canvasTotal = widget.allClusters.length;
    final viewportCount = widget.viewportClusterIds.length;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Su cosa vuoi essere interrogato?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$viewportCount nel viewport · $canvasTotal totali nel canvas',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            _buildSearchField(),
            const SizedBox(height: 10),
            if (_selected.isNotEmpty) ...[
              _buildSelectedStrip(),
              const SizedBox(height: 10),
            ],
            _buildActionRow(viewportCount),
            const SizedBox(height: 6),
            _buildResultsList(),
            const SizedBox(height: 12),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      autofocus: false,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: _accent,
      onChanged: _onQueryChanged,
      decoration: InputDecoration(
        hintText: FlueraLocalizations.of(context)!.socraticScope_searchHint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        prefixIcon: Icon(Icons.search,
            size: 18, color: Colors.white.withValues(alpha: 0.5)),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close,
                    size: 18, color: Colors.white.withValues(alpha: 0.5)),
                onPressed: () {
                  _searchCtrl.clear();
                  _onQueryChanged('');
                },
              ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _accent.withValues(alpha: 0.7)),
        ),
      ),
    );
  }

  /// Horizontal strip of currently-selected chips (always rendered, so
  /// the user can deselect items that have scrolled out of the result
  /// list because the query no longer matches them).
  Widget _buildSelectedStrip() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selected.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final id = _selected.elementAt(i);
          final title = widget.titleResolver(id) ??
              widget.textResolver(id) ??
              'Cluster ${id.substring(0, id.length.clamp(0, 6))}';
          final display =
              title.length > 24 ? '${title.substring(0, 24)}…' : title;
          return InkWell(
            onTap: () => _toggle(id),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _accent, width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    display,
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.close, size: 14, color: _accent),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionRow(int viewportCount) {
    final canTakeAll =
        viewportCount > 0 && viewportCount <= widget.selectionCap;
    return Row(
      children: [
        TextButton.icon(
          onPressed: viewportCount == 0 ? null : _selectAllViewport,
          icon: const Icon(Icons.center_focus_strong, size: 14),
          label: Text(
            canTakeAll
                ? 'Tutti i visibili ($viewportCount)'
                : 'Visibili (cap ${widget.selectionCap})',
            style: const TextStyle(fontSize: 12),
          ),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.7),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const Spacer(),
        Text(
          '${_selected.length}/${widget.selectionCap}',
          style: TextStyle(
            color: _selected.length >= widget.selectionCap
                ? _accent
                : Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Virtualized result list — capped at [_maxResults] entries so the
  /// widget count is bounded regardless of canvas size.
  Widget _buildResultsList() {
    if (_results.isEmpty) {
      final message = _query.isEmpty
          ? 'Nessun argomento nel viewport. Scrivi qualcosa nel canvas o usa la ricerca per trovare argomenti fuori area.'
          : 'Nessun argomento corrisponde a "$_query".\nProva un titolo o una parola degli appunti.';
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 120, maxHeight: 200),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _results.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: Colors.white.withValues(alpha: 0.06),
        ),
        itemBuilder: (_, i) {
          final r = _results[i];
          final selected = _selected.contains(r.id);
          final atCap = _selected.length >= widget.selectionCap;
          return InkWell(
            onTap: (!selected && atCap) ? null : () => _toggle(r.id),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 18,
                    color: selected
                        ? _accent
                        : Colors.white.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.title,
                      style: TextStyle(
                        color: selected
                            ? _accent
                            : (!selected && atCap)
                                ? Colors.white.withValues(alpha: 0.25)
                                : Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (r.inViewport)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _accent.withValues(alpha: 0.3),
                            width: 0.5),
                      ),
                      child: Text(
                        'viewport',
                        style: TextStyle(
                          color: _accent.withValues(alpha: 0.8),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
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

  Widget _buildBottomBar() {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white60,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              'Annulla',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: const Color(0xFF0A0A1A),
              disabledBackgroundColor:
                  Colors.white.withValues(alpha: 0.08),
              disabledForegroundColor: Colors.white24,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _selected.isEmpty
                  ? 'Scegli almeno un argomento'
                  : 'Inizia (${_selected.length})',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
