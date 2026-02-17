import 'dart:ui' as ui;

/// 🎨 Snapshot Cache Manager for Incremental Rendering
///
/// **Phase 3 Feature**: Caches rendered canvas regions to avoid redundant repaints.
///
/// **Benefits**:
/// - Reuse previously rendered regions → 10x-100x faster
/// - Only repaint dirty areas
/// - LRU eviction with memory limits
///
/// **Usage**:
/// ```dart
/// // Cache a rendered region
/// await cacheManager.cacheSnapshot(region, renderedImage);
///
/// // Retrieve cached snapshot
/// final cached = cacheManager.getSnapshot(region);
/// if (cached != null) {
///   canvas.drawImage(cached, offset, paint);
/// }
///
/// // Invalidatete on modification
/// cacheManager.invalidate(dirtyRect);
/// ```
class SnapshotCacheManager {
  /// Cache storage: region key → rendered image
  final Map<String, _CacheEntry> _cache = {};

  /// Maximum cache size in bytes (default: 50MB)
  int maxCacheSize = 50 * 1024 * 1024;

  /// Current cache size in bytes
  int _currentCacheSize = 0;

  /// Cache hit/miss statistics
  int _cacheHits = 0;
  int _cacheMisses = 0;

  /// Get cache statistics
  Map<String, dynamic> get stats => {
    'entries': _cache.length,
    'sizeBytes': _currentCacheSize,
    'sizeMB': (_currentCacheSize / (1024 * 1024)).toStringAsFixed(2),
    'hits': _cacheHits,
    'misses': _cacheMisses,
    'hitRate':
        _cacheHits + _cacheMisses > 0
            ? ((_cacheHits / (_cacheHits + _cacheMisses)) * 100)
                .toStringAsFixed(1)
            : '0.0',
  };

  /// Cache a rendered region
  Future<void> cacheSnapshot(ui.Rect region, ui.Image image) async {
    final key = _regionKey(region);
    final imageSize = _estimateImageSize(image);

    // Check if adding this would exceed limit
    if (_currentCacheSize + imageSize > maxCacheSize) {
      _evictLRU(imageSize);
    }

    // Store in cache
    _cache[key] = _CacheEntry(
      image: image,
      region: region,
      lastAccessed: DateTime.now(),
      sizeBytes: imageSize,
    );

    _currentCacheSize += imageSize;

  }

  /// Get cached snapshot for region (exact match)
  ui.Image? getSnapshot(ui.Rect region) {
    final key = _regionKey(region);
    final entry = _cache[key];

    if (entry != null) {
      entry.lastAccessed = DateTime.now();
      _cacheHits++;
      return entry.image;
    }

    _cacheMisses++;
    return null;
  }

  /// Find cached snapshot that contains the region
  ui.Image? findContainingSnapshot(ui.Rect region) {
    for (final entry in _cache.values) {
      if (_containsRegion(entry.region, region)) {
        entry.lastAccessed = DateTime.now();
        _cacheHits++;
        return entry.image;
      }
    }

    _cacheMisses++;
    return null;
  }

  /// Invalidatete all cached snapshots that overlap with dirty rect
  void invalidate(ui.Rect dirtyRect) {
    final keysToRemove = <String>[];

    for (final entry in _cache.entries) {
      if (entry.value.region.overlaps(dirtyRect)) {
        keysToRemove.add(entry.key);
        _currentCacheSize -= entry.value.sizeBytes;
      }
    }

    for (final key in keysToRemove) {
      _cache[key]?.image.dispose();
      _cache.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
    }
  }

  /// Invalidatete all cached snapshots
  void invalidateAll() {
    for (final entry in _cache.values) {
      entry.image.dispose();
    }
    _cache.clear();
    _currentCacheSize = 0;
  }

  /// Evict least recently used entries to make room
  void _evictLRU(int requiredSpace) {
    if (_cache.isEmpty) return;

    // Sort by last accessed (oldest first)
    final entries =
        _cache.entries.toList()..sort(
          (a, b) => a.value.lastAccessed.compareTo(b.value.lastAccessed),
        );

    int freedSpace = 0;
    final keysToRemove = <String>[];

    for (final entry in entries) {
      if (_currentCacheSize - freedSpace + requiredSpace <= maxCacheSize) {
        break;
      }

      keysToRemove.add(entry.key);
      freedSpace += entry.value.sizeBytes;
    }

    for (final key in keysToRemove) {
      _cache[key]?.image.dispose();
      _cache.remove(key);
    }

    _currentCacheSize -= freedSpace;

  }

  /// Generate cache key from region
  String _regionKey(ui.Rect region) {
    return '${region.left.toInt()}_${region.top.toInt()}_'
        '${region.width.toInt()}_${region.height.toInt()}';
  }

  /// Check if region A contains region B
  bool _containsRegion(ui.Rect a, ui.Rect b) {
    return a.left <= b.left &&
        a.top <= b.top &&
        a.right >= b.right &&
        a.bottom >= b.bottom;
  }

  /// Estimate image size in bytes
  int _estimateImageSize(ui.Image image) {
    // RGBA = 4 bytes per pixel
    return image.width * image.height * 4;
  }

  /// Dispose all cached images
  void dispose() {
    for (final entry in _cache.values) {
      entry.image.dispose();
    }
    _cache.clear();
    _currentCacheSize = 0;
  }

  /// Debug info
  void printStatus() {
    if (_cacheHits + _cacheMisses > 0) {
      final hitRate = (_cacheHits / (_cacheHits + _cacheMisses)) * 100;
    }
  }
}

/// Internal cache entry
class _CacheEntry {
  final ui.Image image;
  final ui.Rect region;
  DateTime lastAccessed;
  final int sizeBytes;

  _CacheEntry({
    required this.image,
    required this.region,
    required this.lastAccessed,
    required this.sizeBytes,
  });
}
