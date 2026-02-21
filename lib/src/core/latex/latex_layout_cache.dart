import 'dart:ui' as ui;
import 'latex_draw_command.dart';

/// 🧮 LaTeX Layout Cache — LRU cache for computed layout results.
///
/// Avoids re-computing the layout every frame for static expressions.
/// The cache key is the combination of (latexSource, fontSize, color).
///
/// ## R6: Picture Caching
///
/// For static (non-editing) formulas on an infinite canvas, this cache
/// stores pre-recorded [ui.Picture] objects alongside layout results.
/// Rendering a cached Picture is a single `canvas.drawPicture(picture)`
/// call — **drastically** faster than re-executing the full draw
/// command loop (drawTextRun, drawPath, drawLine × N).
///
/// The Picture is lazily recorded on first render via [getOrRecordPicture]
/// and invalidated whenever the layout result changes.
///
/// Max capacity is [maxEntries] (default 64). When full, the least
/// recently used entry is evicted.
class LatexLayoutCache {
  /// Maximum number of cached entries.
  final int maxEntries;

  /// Ordered map: most recently used entries are at the end.
  final Map<String, _CacheEntry> _cache = {};

  LatexLayoutCache({this.maxEntries = 64});

  /// Build a cache key from the layout parameters.
  static String _key(String source, double fontSize, ui.Color color) {
    return '$source|$fontSize|${color.toARGB32()}';
  }

  /// Look up a cached layout result.
  ///
  /// Returns `null` if not cached. Moves the entry to most-recently-used
  /// position on hit.
  LatexLayoutResult? get(String source, double fontSize, ui.Color color) {
    final key = _key(source, fontSize, color);
    final entry = _cache.remove(key);
    if (entry != null) {
      _cache[key] = entry;
      return entry.result;
    }
    return null;
  }

  /// Store a layout result in the cache.
  ///
  /// Evicts the least recently used entry if at capacity.
  /// Any previously cached [ui.Picture] for this key is disposed.
  void put(
    String source,
    double fontSize,
    ui.Color color,
    LatexLayoutResult result,
  ) {
    final key = _key(source, fontSize, color);

    // Dispose old Picture if exists
    final oldEntry = _cache.remove(key);
    oldEntry?.picture?.dispose();

    // Evict LRU if at capacity
    while (_cache.length >= maxEntries) {
      final evictKey = _cache.keys.first;
      _cache.remove(evictKey)?.picture?.dispose();
    }

    _cache[key] = _CacheEntry(result: result);
  }

  /// Get or lazily record a [ui.Picture] for a cached layout result.
  ///
  /// On first call, records all draw commands into a Picture via
  /// [ui.PictureRecorder]. On subsequent calls, returns the cached Picture.
  ///
  /// Returns `null` if no layout result is cached for this key.
  ///
  /// The caller renders with:
  /// ```dart
  /// final picture = cache.getOrRecordPicture(src, fs, color, renderer);
  /// if (picture != null) canvas.drawPicture(picture);
  /// ```
  ui.Picture? getOrRecordPicture(
    String source,
    double fontSize,
    ui.Color color,
    void Function(ui.Canvas canvas, LatexLayoutResult result) renderFn,
  ) {
    final key = _key(source, fontSize, color);
    final entry = _cache.remove(key);
    if (entry == null) return null;

    // Re-insert at end (MRU)
    _cache[key] = entry;

    // Return cached Picture if available
    if (entry.picture != null) return entry.picture;

    // Record a new Picture
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    renderFn(canvas, entry.result);
    final picture = recorder.endRecording();
    entry.picture = picture;

    return picture;
  }

  /// Invalidate a specific entry (disposes its Picture).
  void invalidate(String source, double fontSize, ui.Color color) {
    final key = _key(source, fontSize, color);
    _cache.remove(key)?.picture?.dispose();
  }

  /// Clear all cached entries (disposes all Pictures).
  void clear() {
    for (final entry in _cache.values) {
      entry.picture?.dispose();
    }
    _cache.clear();
  }

  /// Current number of cached entries.
  int get length => _cache.length;

  /// Whether the cache is empty.
  bool get isEmpty => _cache.isEmpty;
}

/// Internal cache entry holding both the layout result and optional Picture.
class _CacheEntry {
  final LatexLayoutResult result;
  ui.Picture? picture;

  _CacheEntry({required this.result, this.picture});
}
