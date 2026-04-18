import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../utils/key_value_store.dart';
import 'spatial_bookmark.dart';

/// 📌 SPATIAL BOOKMARK CONTROLLER — manages the per-canvas bookmark list.
///
/// Lifecycle:
///   1. `loadFromKVStore(canvasId)` on canvas open
///   2. `add` / `remove` / `rename` / `recordVisit` from UI
///   3. `saveToKVStore(canvasId)` after every mutation (auto, fire-and-forget)
///
/// Persistence:
///   Key `bookmarks_$canvasId` → JSON-encoded list of [SpatialBookmark.toJson].
///   Same scoping convention as `srs_return_count_$canvasId` and
///   `proactive_sr_$canvasId` used elsewhere in the engine.
///
/// Cap: [maxBookmarksPerCanvas] = 50. When exceeded, LRU eviction:
///   - first, never-visited entries (lastVisitedAtMs == null), oldest first
///   - then visited entries by oldest lastVisitedAtMs
class SpatialBookmarkController extends ChangeNotifier {
  static const int maxBookmarksPerCanvas = 50;

  final List<SpatialBookmark> _bookmarks = [];

  /// Unmodifiable view sorted by createdAtMs descending (most recent first).
  List<SpatialBookmark> get bookmarks => List.unmodifiable(_bookmarks);

  /// True if the given id corresponds to a stored bookmark.
  bool contains(String id) => _bookmarks.any((b) => b.id == id);

  // ── Persistence ──────────────────────────────────────────────────────

  String _key(String canvasId) => 'bookmarks_$canvasId';

  /// Pure JSON serialization of the current bookmark list. Exposed as a
  /// public hook for unit testing + alternative persistence backends
  /// (tests don't need to mock path_provider to exercise the round-trip).
  String serializeToJson() =>
      jsonEncode(_bookmarks.map((b) => b.toJson()).toList());

  /// Replace the current list with the contents of [json]. Malformed or
  /// non-list payloads are ignored (list stays empty, no throw). Sorts
  /// + notifies on success.
  ///
  /// Returns true if the payload was parsed successfully (even if empty).
  /// False is reserved for catastrophic parse failures.
  bool loadFromJson(String json) {
    if (json.isEmpty) return true;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return false;
      final parsed = <SpatialBookmark>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        // Per-entry try/catch so one corrupt row doesn't poison the load.
        // Critical for long-lived canvases where a partial write (power
        // loss, force quit mid-save) could leave a dangling row.
        try {
          parsed.add(SpatialBookmark.fromJson(entry));
        } catch (e) {
          debugPrint('📌 Skipping malformed bookmark entry: $e');
        }
      }
      _bookmarks
        ..clear()
        ..addAll(parsed);
      _sortInPlace();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('📌 Bookmark parse failed: $e');
      return false;
    }
  }

  /// Load bookmarks from the KV store. Safe to call on canvases that
  /// have never had bookmarks (key absent → no-op, list stays empty).
  /// Malformed JSON is logged and ignored — the controller stays usable.
  Future<void> loadFromKVStore(String canvasId) async {
    try {
      final store = await KeyValueStore.getInstance();
      final raw = store.getString(_key(canvasId));
      if (raw == null || raw.isEmpty) return;
      loadFromJson(raw);
    } catch (e) {
      debugPrint('📌 Bookmark load failed for $canvasId: $e');
    }
  }

  /// Persist current state. Fire-and-forget from caller's perspective.
  Future<void> saveToKVStore(String canvasId) async {
    try {
      final store = await KeyValueStore.getInstance();
      await store.setString(_key(canvasId), serializeToJson());
    } catch (e) {
      debugPrint('📌 Bookmark save failed for $canvasId: $e');
    }
  }

  // ── CRUD ─────────────────────────────────────────────────────────────

  /// Create + insert a new bookmark. Caller is responsible for the
  /// follow-up [saveToKVStore] call (or rely on auto-save in their flow).
  /// If the cap is hit, evicts the LRU entry before inserting.
  SpatialBookmark add({
    required String label,
    required Offset canvasPosition,
    required double scale,
  }) {
    if (_bookmarks.length >= maxBookmarksPerCanvas) {
      _evictLeastRelevant();
    }
    final bm = SpatialBookmark(
      id: _generateId(),
      label: label.trim().isEmpty ? 'Bookmark' : label.trim(),
      canvasPosition: canvasPosition,
      scale: scale,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _bookmarks.add(bm);
    _sortInPlace();
    notifyListeners();
    return bm;
  }

  /// Remove by id. Returns true if a bookmark was removed.
  bool remove(String id) {
    final beforeLen = _bookmarks.length;
    _bookmarks.removeWhere((b) => b.id == id);
    final removed = _bookmarks.length != beforeLen;
    if (removed) notifyListeners();
    return removed;
  }

  /// Rename by id. Returns true on success.
  bool rename(String id, String newLabel) {
    final trimmed = newLabel.trim();
    if (trimmed.isEmpty) return false;
    final idx = _bookmarks.indexWhere((b) => b.id == id);
    if (idx < 0) return false;
    _bookmarks[idx] = _bookmarks[idx].copyWith(label: trimmed);
    notifyListeners();
    return true;
  }

  /// Mark the bookmark as visited *now* (for LRU + UX hints).
  /// No-op if the id doesn't exist.
  void recordVisit(String id) {
    final idx = _bookmarks.indexWhere((b) => b.id == id);
    if (idx < 0) return;
    _bookmarks[idx] = _bookmarks[idx]
        .copyWith(lastVisitedAtMs: DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
  }

  /// Lookup by id; null if absent.
  SpatialBookmark? byId(String id) {
    for (final b in _bookmarks) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Clear all bookmarks (used by tests + canvas reset flows).
  void clear() {
    if (_bookmarks.isEmpty) return;
    _bookmarks.clear();
    notifyListeners();
  }

  // ── Internals ────────────────────────────────────────────────────────

  void _sortInPlace() {
    _bookmarks.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
  }

  /// LRU eviction strategy:
  ///   1. Drop a never-visited entry (lastVisitedAtMs == null) — oldest first
  ///   2. Otherwise, drop the visited entry with the oldest lastVisitedAtMs
  void _evictLeastRelevant() {
    if (_bookmarks.isEmpty) return;
    int? targetIdx;
    int targetScore = -1;
    for (var i = 0; i < _bookmarks.length; i++) {
      final b = _bookmarks[i];
      // Score: never-visited beats all visited; among never-visited, oldest
      // createdAt wins. Among visited, oldest lastVisitedAt wins.
      final score = b.lastVisitedAtMs == null
          ? -b.createdAtMs // negative so older = higher score
          : (-b.lastVisitedAtMs!);
      if (targetIdx == null || score > targetScore) {
        targetIdx = i;
        targetScore = score;
      }
    }
    if (targetIdx != null) _bookmarks.removeAt(targetIdx);
  }

  static String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = math.Random().nextInt(0xFFFF);
    return 'bm_${now.toRadixString(36)}_${rand.toRadixString(36)}';
  }
}
