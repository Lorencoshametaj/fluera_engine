import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// 🧠 Enterprise-grade image memory manager with:
///
/// 1. **LRU eviction** — off-viewport images evicted after cooldown
/// 2. **Compressed byte cache** — evicted images keep JPEG/PNG bytes in RAM
/// 3. **Staggered thumbnail queue** — serial processing prevents CPU spikes
/// 4. **Memory pressure** — aggressive eviction on OS low-memory signal
/// 5. **Adaptive budget** — maxImages adjusts based on device RSS
/// 6. **Multi-level LOD** — 3 resolution tiers for zoom levels
/// 7. **Image deduplication** — reference counting for shared textures
/// 8. **Predictive viewport** — preload images in scroll direction
/// 9. **Double-buffer swap** — decode new LOD before disposing old
class ImageMemoryManager {
  /// Base maximum number of decoded images to keep in memory.
  int maxImages;

  /// Cooldown in milliseconds: images off-viewport for this long → evict.
  final int cooldownMs;

  /// Last access timestamp per image path (ms since epoch).
  final Map<String, int> _accessTimestamps = {};

  /// Last time each image was confirmed visible in the viewport.
  final Map<String, int> _lastVisibleTimestamps = {};

  // ======================== COMPRESSED BYTE CACHE ========================

  /// Compressed byte cache: JPEG/PNG bytes for evicted images.
  final Map<String, Uint8List> _compressedCache = {};
  static const int _maxCompressedCacheEntries = 50;

  // ======================== STAGGERED THUMBNAIL ========================

  /// Serial thumbnail generation queue (prevents CPU spike).
  final Queue<_ThumbnailRequest> _thumbnailQueue = Queue();
  bool _isProcessingThumbnails = false;

  /// Callback for thumbnail completion (set by canvas lifecycle).
  void Function(String path, ui.Image thumbnail)? onThumbnailReady;

  // ======================== MULTI-LEVEL LOD ========================

  static const List<_LodTier> lodTiers = [
    _LodTier(zoomThreshold: 0.15, maxDimension: 256, name: 'micro'),
    _LodTier(zoomThreshold: 0.3, maxDimension: 512, name: 'thumb'),
    _LodTier(zoomThreshold: 0.5, maxDimension: 1024, name: 'medium'),
  ];

  /// Current LOD level per image path (null = full res).
  final Map<String, String> _currentLodLevel = {};

  // ======================== IMAGE DEDUPLICATION ========================

  /// Reference count for each loaded image path.
  /// Multiple ImageElements can reference the same file path.
  /// We only dispose when refCount drops to 0.
  final Map<String, int> _refCounts = {};

  // ======================== PREDICTIVE VIEWPORT ========================

  /// Previous viewport offset for velocity calculation.
  ui.Offset _previousOffset = ui.Offset.zero;
  int _previousOffsetTimestamp = 0;

  /// Calculated scroll velocity (canvas units per second).
  ui.Offset _scrollVelocity = ui.Offset.zero;

  // ======================== DOUBLE BUFFER ========================

  /// Paths currently being decoded for LOD swap (prevents duplicate requests).
  final Set<String> _pendingLodSwaps = {};

  ImageMemoryManager({this.maxImages = 20, this.cooldownMs = 5000});

  // ======================= CORE ACCESS TRACKING =======================

  void markAccessed(String path) {
    _accessTimestamps[path] = DateTime.now().millisecondsSinceEpoch;
  }

  void markAllAccessed(Iterable<String> paths) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final path in paths) {
      _accessTimestamps[path] = now;
      _lastVisibleTimestamps[path] = now;
    }
  }

  void remove(String path) {
    _accessTimestamps.remove(path);
    _lastVisibleTimestamps.remove(path);
    _compressedCache.remove(path);
    _currentLodLevel.remove(path);
    _refCounts.remove(path);
    _pendingLodSwaps.remove(path);
  }

  void clear() {
    _accessTimestamps.clear();
    _lastVisibleTimestamps.clear();
    _compressedCache.clear();
    _currentLodLevel.clear();
    _thumbnailQueue.clear();
    _refCounts.clear();
    _pendingLodSwaps.clear();
  }

  // ======================= IMAGE DEDUPLICATION =======================

  /// 📎 Increment reference count for an image path.
  /// Returns true if this is the first reference (needs loading).
  bool addRef(String path) {
    _refCounts[path] = (_refCounts[path] ?? 0) + 1;
    return _refCounts[path] == 1;
  }

  /// 📎 Decrement reference count. Returns true if refCount reached 0
  /// (image can be disposed).
  bool releaseRef(String path) {
    final current = _refCounts[path] ?? 0;
    if (current <= 1) {
      _refCounts.remove(path);
      return true;
    }
    _refCounts[path] = current - 1;
    return false;
  }

  /// Get current reference count for a path.
  int getRefCount(String path) => _refCounts[path] ?? 0;

  /// Build deduplication map from image elements.
  /// Returns paths that have multiple references.
  Set<String> findDuplicateRefs(Iterable<String> allPaths) {
    final counts = <String, int>{};
    for (final path in allPaths) {
      counts[path] = (counts[path] ?? 0) + 1;
    }
    return counts.entries.where((e) => e.value > 1).map((e) => e.key).toSet();
  }

  // ======================= PREDICTIVE VIEWPORT =======================

  /// 🔮 Update scroll velocity tracking (call before computing viewport).
  void updateScrollVelocity(ui.Offset currentOffset) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _previousOffsetTimestamp;

    if (elapsed > 0 && elapsed < 10000 && _previousOffsetTimestamp > 0) {
      final dt = elapsed / 1000.0; // seconds
      _scrollVelocity = ui.Offset(
        (currentOffset.dx - _previousOffset.dx) / dt,
        (currentOffset.dy - _previousOffset.dy) / dt,
      );
    } else {
      _scrollVelocity = ui.Offset.zero;
    }

    _previousOffset = currentOffset;
    _previousOffsetTimestamp = now;
  }

  /// 🔮 Get the predictive viewport: expands in the direction of movement.
  ///
  /// [baseViewport] — the current viewport rect in canvas coordinates.
  /// Returns an expanded rect that includes the predicted area the user
  /// will be scrolling into (1x lookahead based on velocity).
  ui.Rect getPredictiveViewport(ui.Rect baseViewport) {
    // Prediction window: where will the viewport be in ~1 second?
    const lookAheadSeconds = 1.0;
    final predictedDx = _scrollVelocity.dx * lookAheadSeconds;
    final predictedDy = _scrollVelocity.dy * lookAheadSeconds;

    if (predictedDx.abs() < 10 && predictedDy.abs() < 10) {
      return baseViewport; // Not scrolling significantly
    }

    // Expand in the scroll direction only
    final left =
        predictedDx < 0 ? baseViewport.left + predictedDx : baseViewport.left;
    final top =
        predictedDy < 0 ? baseViewport.top + predictedDy : baseViewport.top;
    final right =
        predictedDx > 0 ? baseViewport.right + predictedDx : baseViewport.right;
    final bottom =
        predictedDy > 0
            ? baseViewport.bottom + predictedDy
            : baseViewport.bottom;

    return ui.Rect.fromLTRB(left, top, right, bottom);
  }

  // ======================= BUDGET EVICTION =======================

  List<String> getEvictionCandidates(
    Set<String> loadedPaths,
    Set<String> viewportPaths,
  ) {
    if (loadedPaths.length <= maxImages) return const [];
    final evictable = loadedPaths.difference(viewportPaths).toList();
    evictable.sort((a, b) {
      final timeA = _accessTimestamps[a] ?? 0;
      final timeB = _accessTimestamps[b] ?? 0;
      return timeA.compareTo(timeB);
    });
    final excess = loadedPaths.length - maxImages;
    if (excess <= 0) return const [];
    return evictable.take(excess).toList();
  }

  int scheduleEviction(
    Map<String, ui.Image> loadedImages,
    Set<String> viewportPaths,
  ) {
    final candidates = getEvictionCandidates(
      loadedImages.keys.toSet(),
      viewportPaths,
    );
    for (final path in candidates) {
      _evictImage(loadedImages, path);
    }
    return candidates.length;
  }

  // ======================= PROACTIVE EVICTION =======================

  List<String> proactiveEviction(
    Map<String, ui.Image> loadedImages,
    Set<String> viewportPaths,
  ) {
    if (loadedImages.isEmpty) return const [];

    // 🚀 Skip eviction when under budget — no memory pressure, avoids
    // useless evict→dispose→decode→reload cycles.
    if (loadedImages.length <= maxImages) return const [];

    final now = DateTime.now().millisecondsSinceEpoch;
    final evicted = <String>[];

    for (final path in viewportPaths) {
      _lastVisibleTimestamps[path] = now;
    }

    final offViewport = loadedImages.keys.toSet().difference(viewportPaths);
    for (final path in offViewport) {
      final lastVisible = _lastVisibleTimestamps[path];
      if (lastVisible == null) {
        // 🛡️ First encounter: image was just added. Give it a cooldown
        // grace period before it can be evicted. Without this, newly
        // added images get immediately evicted (lastVisible=0 → instant eviction).
        _lastVisibleTimestamps[path] = now;
        continue;
      }
      if (now - lastVisible > cooldownMs) {
        _evictImage(loadedImages, path);
        evicted.add(path);
      }
    }

    return evicted;
  }

  void _evictImage(Map<String, ui.Image> loadedImages, String path) {
    final image = loadedImages.remove(path);
    image?.dispose();
    _accessTimestamps.remove(path);
    _lastVisibleTimestamps.remove(path);
    _currentLodLevel.remove(path);
    _pendingLodSwaps.remove(path);
  }

  // ======================= COMPRESSED BYTE CACHE =======================

  /// Max total bytes for compressed cache (200MB).
  /// 50 entries × 5MB avg = 250MB → capped at 200MB.
  static const int _maxCompressedCacheBytes = 200 * 1024 * 1024;
  int _compressedCacheBytes = 0;

  void cacheCompressedBytes(String path, Uint8List bytes) {
    // Remove old entry if replacing
    final old = _compressedCache[path];
    if (old != null) _compressedCacheBytes -= old.length;

    _compressedCache[path] = bytes;
    _compressedCacheBytes += bytes.length;

    // Entry count limit
    while (_compressedCache.length > _maxCompressedCacheEntries) {
      final oldest = _compressedCache.keys.first;
      _compressedCacheBytes -= _compressedCache[oldest]!.length;
      _compressedCache.remove(oldest);
    }

    // 🧠 #6: Byte-size limit (prevents OOM with large images)
    while (_compressedCacheBytes > _maxCompressedCacheBytes &&
        _compressedCache.isNotEmpty) {
      final oldest = _compressedCache.keys.first;
      _compressedCacheBytes -= _compressedCache[oldest]!.length;
      _compressedCache.remove(oldest);
    }
  }

  Uint8List? getCompressedBytes(String path) => _compressedCache[path];
  bool hasCompressedBytes(String path) => _compressedCache.containsKey(path);

  // ======================= MEMORY PRESSURE =======================

  int onMemoryPressure(
    Map<String, ui.Image> loadedImages,
    Set<String> viewportPaths,
  ) {
    final offViewport = loadedImages.keys.toSet().difference(viewportPaths);
    int evictedCount = 0;
    for (final path in offViewport) {
      final image = loadedImages.remove(path);
      image?.dispose();
      _accessTimestamps.remove(path);
      _lastVisibleTimestamps.remove(path);
      _currentLodLevel.remove(path);
      evictedCount++;
    }
    _compressedCache.clear();
    return evictedCount;
  }

  // ======================= STAGGERED THUMBNAILS =======================

  void enqueueThumbnail(String path, Uint8List bytes, int maxDimension) {
    if (_thumbnailQueue.any(
      (r) => r.path == path && r.maxDimension == maxDimension,
    )) {
      return;
    }
    _thumbnailQueue.add(_ThumbnailRequest(path, bytes, maxDimension));
    _processNextThumbnail();
  }

  Future<void> _processNextThumbnail() async {
    if (_isProcessingThumbnails || _thumbnailQueue.isEmpty) return;
    _isProcessingThumbnails = true;

    while (_thumbnailQueue.isNotEmpty) {
      final request = _thumbnailQueue.removeFirst();
      try {
        final codec = await ui.instantiateImageCodec(request.bytes);
        final frame = await codec.getNextFrame();
        final origW = frame.image.width;
        final origH = frame.image.height;
        frame.image.dispose();
        codec.dispose();

        if (origW <= request.maxDimension && origH <= request.maxDimension) {
          continue;
        }

        int targetW, targetH;
        if (origW >= origH) {
          targetW = request.maxDimension;
          targetH = (origH * request.maxDimension / origW).round();
        } else {
          targetH = request.maxDimension;
          targetW = (origW * request.maxDimension / origH).round();
        }

        final thumbCodec = await ui.instantiateImageCodec(
          request.bytes,
          targetWidth: targetW,
          targetHeight: targetH,
        );
        final thumbFrame = await thumbCodec.getNextFrame();
        thumbCodec.dispose();

        onThumbnailReady?.call(request.path, thumbFrame.image);
      } catch (_) {
        // Skip failed thumbnails silently
      }
    }

    _isProcessingThumbnails = false;
  }

  // ======================= DOUBLE-BUFFER LOD SWAP =======================

  /// 🔄 Whether a LOD swap is already pending for this path.
  bool isLodSwapPending(String path) => _pendingLodSwaps.contains(path);

  /// 🔄 Mark a LOD swap as pending (prevents duplicate work).
  void markLodSwapPending(String path) => _pendingLodSwaps.add(path);

  /// 🔄 Mark a LOD swap as complete.
  void markLodSwapComplete(String path) => _pendingLodSwaps.remove(path);

  // ======================= MULTI-LEVEL LOD =======================

  _LodTier? getOptimalLodTier(double canvasScale) {
    for (final tier in lodTiers) {
      if (canvasScale < tier.zoomThreshold) return tier;
    }
    return null;
  }

  String? getCurrentLodLevel(String path) => _currentLodLevel[path];

  void setLodLevel(String path, String? level) {
    if (level == null) {
      _currentLodLevel.remove(path);
    } else {
      _currentLodLevel[path] = level;
    }
  }

  // ======================= ADAPTIVE BUDGET =======================

  void adjustBudgetFromMemory() {
    final rss = ProcessInfo.currentRss;
    final rssMB = rss ~/ (1024 * 1024);

    if (rssMB < 300) {
      maxImages = 30;
    } else if (rssMB < 500) {
      maxImages = 20;
    } else if (rssMB < 700) {
      maxImages = 10;
    } else {
      maxImages = 5;
    }
  }

  // ======================= ISOLATE FILE I/O =======================

  /// 🚀 Read file bytes on a background isolate (zero UI thread I/O).
  static Future<Uint8List?> readFileOnIsolate(String path) {
    return compute(_readFileBytes, path);
  }

  /// Top-level function for isolate (must be static/top-level).
  static Uint8List? _readFileBytes(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return file.readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  // ======================= MIME TYPE DETECTION =======================

  /// 🔍 Detect MIME type from file magic bytes (first 12 bytes).
  ///
  /// Returns correct MIME instead of hardcoding 'image/png'.
  /// JPEG files are ~5-10x smaller than PNG for photos.
  static String detectMimeType(Uint8List bytes) {
    if (bytes.length < 4) return 'application/octet-stream';

    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    // WebP: RIFF....WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    // GIF: GIF87a or GIF89a
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return 'image/gif';
    }
    // BMP: BM
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'image/bmp';
    }
    return 'image/png'; // Default fallback
  }

  // ======================= RESIZE FOR UPLOAD =======================

  /// 📐 Resize image bytes for cloud upload (max 4096px, re-encode as PNG).
  ///
  /// Photos from modern phones can be 20MP+ (5000x4000). Uploading at full
  /// resolution wastes bandwidth and storage. This caps at [maxDimension]
  /// while preserving aspect ratio.
  ///
  /// Returns original bytes if image is already small enough.
  static Future<Uint8List> resizeForUpload(
    Uint8List bytes, {
    int maxDimension = 4096,
  }) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      codec.dispose();

      // Already small enough (codec already disposed above)
      if (w <= maxDimension && h <= maxDimension) return bytes;

      // Calculate target dimensions preserving aspect ratio
      int targetW, targetH;
      if (w >= h) {
        targetW = maxDimension;
        targetH = (h * maxDimension / w).round();
      } else {
        targetH = maxDimension;
        targetW = (w * maxDimension / h).round();
      }

      // Re-decode at target size
      final resizedCodec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetW,
        targetHeight: targetH,
      );
      final resizedFrame = await resizedCodec.getNextFrame();
      resizedCodec.dispose();

      // Re-encode as PNG
      final byteData = await resizedFrame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      resizedFrame.image.dispose();

      if (byteData == null) return bytes;

      final resized = byteData.buffer.asUint8List();
      return resized;
    } catch (e) {
      return bytes;
    }
  }

  // ======================= IMAGE DIMENSION CACHE =======================

  /// 📏 Last-known image dimensions per path.
  /// Used by the loading placeholder to render at correct aspect ratio
  /// instead of the hardcoded 200x150px.
  final Map<String, ui.Size> _imageDimensions = {};

  /// Store dimensions when an image is decoded.
  void cacheImageDimensions(String path, int width, int height) {
    _imageDimensions[path] = ui.Size(width.toDouble(), height.toDouble());
  }

  /// Get cached dimensions (null if never loaded).
  ui.Size? getImageDimensions(String path) => _imageDimensions[path];

  /// 📊 Stats for debugging.
  Map<String, dynamic> get stats => {
    'trackedImages': _accessTimestamps.length,
    'maxImages': maxImages,
    'cooldownMs': cooldownMs,
    'compressedCacheEntries': _compressedCache.length,
    'compressedCacheBytes': _compressedCache.values.fold<int>(
      0,
      (s, b) => s + b.length,
    ),
    'thumbnailQueueLength': _thumbnailQueue.length,
    'lodLevels': _currentLodLevel.length,
    'refCounts': _refCounts.length,
    'pendingLodSwaps': _pendingLodSwaps.length,
    'scrollVelocity':
        '${_scrollVelocity.dx.toStringAsFixed(0)},${_scrollVelocity.dy.toStringAsFixed(0)}',
    'cachedDimensions': _imageDimensions.length,
  };
}

class _LodTier {
  final double zoomThreshold;
  final int maxDimension;
  final String name;
  const _LodTier({
    required this.zoomThreshold,
    required this.maxDimension,
    required this.name,
  });
}

class _ThumbnailRequest {
  final String path;
  final Uint8List bytes;
  final int maxDimension;
  _ThumbnailRequest(this.path, this.bytes, this.maxDimension);
}
