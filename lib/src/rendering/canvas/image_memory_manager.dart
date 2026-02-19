import 'dart:ui' as ui;

/// 🧠 Enterprise-grade LRU memory manager for loaded `ui.Image` objects.
///
/// Tracks access patterns and evicts least-recently-used images that are
/// off-viewport when memory budget is exceeded. Prevents OOM with many
/// large images on the canvas.
///
/// Usage:
/// ```dart
/// final manager = ImageMemoryManager(maxImages: 20);
/// manager.markAccessed('path/to/image.png');
/// final toEvict = manager.getEvictionCandidates(viewportPaths);
/// ```
class ImageMemoryManager {
  /// Maximum number of images to keep in memory simultaneously.
  final int maxImages;

  /// Last access timestamp per image path (microseconds since epoch).
  final Map<String, int> _accessTimestamps = {};

  ImageMemoryManager({this.maxImages = 20});

  /// 📌 Mark an image as recently accessed (called during paint).
  void markAccessed(String path) {
    _accessTimestamps[path] = DateTime.now().microsecondsSinceEpoch;
  }

  /// 📌 Mark multiple images as recently accessed.
  void markAllAccessed(Iterable<String> paths) {
    final now = DateTime.now().microsecondsSinceEpoch;
    for (final path in paths) {
      _accessTimestamps[path] = now;
    }
  }

  /// 🗑️ Remove tracking for an image (when deleted from canvas).
  void remove(String path) {
    _accessTimestamps.remove(path);
  }

  /// 🧹 Clear all tracking data.
  void clear() {
    _accessTimestamps.clear();
  }

  /// 🔍 Get paths that should be evicted from memory.
  ///
  /// Returns paths sorted by oldest access time, excluding any paths
  /// currently visible in the viewport.
  ///
  /// [loadedPaths] — all paths currently loaded in memory.
  /// [viewportPaths] — paths of images currently in the viewport (protected).
  List<String> getEvictionCandidates(
    Set<String> loadedPaths,
    Set<String> viewportPaths,
  ) {
    if (loadedPaths.length <= maxImages) return const [];

    // Evictable = loaded but NOT in viewport
    final evictable = loadedPaths.difference(viewportPaths).toList();

    // Sort by oldest access time first
    evictable.sort((a, b) {
      final timeA = _accessTimestamps[a] ?? 0;
      final timeB = _accessTimestamps[b] ?? 0;
      return timeA.compareTo(timeB);
    });

    // How many to evict to get back to budget
    final excess = loadedPaths.length - maxImages;
    if (excess <= 0) return const [];

    return evictable.take(excess).toList();
  }

  /// ⚡ Perform eviction: dispose and remove images beyond the budget.
  ///
  /// Returns the number of images evicted.
  int scheduleEviction(
    Map<String, ui.Image> loadedImages,
    Set<String> viewportPaths,
  ) {
    final candidates = getEvictionCandidates(
      loadedImages.keys.toSet(),
      viewportPaths,
    );

    for (final path in candidates) {
      final image = loadedImages.remove(path);
      image?.dispose();
      _accessTimestamps.remove(path);
    }

    return candidates.length;
  }

  /// 📊 Stats for debugging.
  Map<String, dynamic> get stats => {
    'trackedImages': _accessTimestamps.length,
    'maxImages': maxImages,
  };
}
