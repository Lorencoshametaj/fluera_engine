import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../storage/fluera_storage_adapter.dart';
import '../../storage/pin_this_view.dart' as storage;
import '../../storage/spatial_bookmark.dart';

/// 📌 SPATIAL BOOKMARK CONTROLLER — per-canvas bookmark list backed by the
/// engine's [FlueraStorageAdapter] (schema v16+).
///
/// Lifecycle:
///   1. [loadFromStorage] on canvas open (reads [CanvasMetadata.bookmarks]).
///   2. [add] / [remove] / [rename] / [recordVisit] from UI. Every mutation
///      fires a fire-and-forget save to the adapter.
///   3. The widget listening to this controller rebuilds on [notifyListeners].
///
/// Cap: [maxBookmarksPerCanvas] = 50. When exceeded, LRU eviction:
///   - first, never-visited entries (lastVisitedAt == null), oldest first
///   - then visited entries by oldest lastVisitedAt
class SpatialBookmarkController extends ChangeNotifier {
  static const int maxBookmarksPerCanvas = 50;

  /// Adapter used for persistence. May be null — controllers without an
  /// adapter behave like an in-memory list and never persist (useful for
  /// tests or preview screens where the canvas isn't backed by storage).
  final FlueraStorageAdapter? adapter;

  SpatialBookmarkController({this.adapter});

  final List<SpatialBookmark> _bookmarks = [];

  /// Unmodifiable view sorted by createdAt descending (most recent first).
  List<SpatialBookmark> get bookmarks => List.unmodifiable(_bookmarks);

  bool contains(String id) => _bookmarks.any((b) => b.id == id);

  SpatialBookmark? byId(String id) {
    for (final b in _bookmarks) {
      if (b.id == id) return b;
    }
    return null;
  }

  // ── Persistence ──────────────────────────────────────────────────────

  /// Hydrate from the storage adapter. Safe on canvases with no bookmarks
  /// or on controllers without an adapter (both no-op).
  Future<void> loadFromStorage(String canvasId) async {
    final a = adapter;
    if (a == null) return;
    try {
      final all = await a.listCanvases();
      for (final meta in all) {
        if (meta.canvasId != canvasId) continue;
        _bookmarks
          ..clear()
          ..addAll(meta.bookmarks);
        _sortInPlace();
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('📌 Bookmark load failed for $canvasId: $e');
    }
  }

  /// Seed the controller from an in-memory list (e.g. the metadata already
  /// held by the canvas screen). Avoids a round-trip to storage.
  void seedFromMetadata(List<SpatialBookmark> fromMetadata) {
    _bookmarks
      ..clear()
      ..addAll(fromMetadata);
    _sortInPlace();
    notifyListeners();
  }

  Future<void> _persist(String canvasId) async {
    final a = adapter;
    if (a == null) return;
    try {
      await a.saveBookmarks(canvasId, bookmarks: _bookmarks);
    } catch (e) {
      debugPrint('📌 Bookmark save failed for $canvasId: $e');
    }
  }

  // ── CRUD ─────────────────────────────────────────────────────────────

  /// Create + insert a new bookmark, then persist.
  ///
  /// [canvasPosition] is the world-space point to recentre on; [scale] is
  /// the zoom level the user had when pinning.
  Future<SpatialBookmark> add({
    required String canvasId,
    required String label,
    required Offset canvasPosition,
    required double scale,
    int? color,
  }) async {
    if (_bookmarks.length >= maxBookmarksPerCanvas) {
      _evictLeastRelevant();
    }
    final bm = SpatialBookmark(
      id: _generateId(),
      name: label.trim().isEmpty ? 'Bookmark' : label.trim(),
      cx: canvasPosition.dx,
      cy: canvasPosition.dy,
      zoom: scale,
      color: color,
      createdAt: DateTime.now(),
    );
    _bookmarks.add(bm);
    _sortInPlace();
    notifyListeners();
    await _persist(canvasId);
    return bm;
  }

  Future<bool> remove(String canvasId, String id) async {
    final beforeLen = _bookmarks.length;
    _bookmarks.removeWhere((b) => b.id == id);
    final removed = _bookmarks.length != beforeLen;
    if (removed) {
      notifyListeners();
      await _persist(canvasId);
    }
    return removed;
  }

  Future<bool> rename(String canvasId, String id, String newLabel) async {
    final trimmed = newLabel.trim();
    if (trimmed.isEmpty) return false;
    final idx = _bookmarks.indexWhere((b) => b.id == id);
    if (idx < 0) return false;
    _bookmarks[idx] = _bookmarks[idx].copyWith(name: trimmed);
    notifyListeners();
    await _persist(canvasId);
    return true;
  }

  /// Mark the bookmark as visited *now* (for LRU + UX hints).
  Future<void> recordVisit(String canvasId, String id) async {
    final idx = _bookmarks.indexWhere((b) => b.id == id);
    if (idx < 0) return;
    _bookmarks[idx] =
        _bookmarks[idx].copyWith(lastVisitedAt: DateTime.now());
    notifyListeners();
    await _persist(canvasId);
  }

  void clear() {
    if (_bookmarks.isEmpty) return;
    _bookmarks.clear();
    notifyListeners();
  }

  // ── Internals ────────────────────────────────────────────────────────

  void _sortInPlace() {
    _bookmarks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _evictLeastRelevant() {
    if (_bookmarks.isEmpty) return;
    int? targetIdx;
    int targetScore = -1 << 62;
    for (var i = 0; i < _bookmarks.length; i++) {
      final b = _bookmarks[i];
      final score = b.lastVisitedAt == null
          ? -b.createdAt.millisecondsSinceEpoch
          : -b.lastVisitedAt!.millisecondsSinceEpoch;
      if (targetIdx == null || score > targetScore) {
        targetIdx = i;
        targetScore = score;
      }
    }
    if (targetIdx != null) _bookmarks.removeAt(targetIdx);
  }

  static String _generateId() => storage.generateBookmarkId();
}
