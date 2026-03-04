import 'dart:ui' as ui;

import 'frame_budget_manager.dart';

/// 🗂️ IMAGE STUB MANAGER — Memory-bounded image storage
///
/// At 100+ images, keeping all [ui.Image] textures decoded consumes
/// significant GPU memory:
/// - A 2048×1536 RGBA image ≈ 12 MB
/// - A 4K image (3840×2160) ≈ 33 MB
/// - 100 images at 2048px ≈ 1.2 GB RAM
///
/// This manager stubs out images far from the viewport:
/// - Disposes `ui.Image` from `loadedImages` (GPU memory)
/// - The `ImageElement` metadata remains in RAM (~200 bytes/image)
///   for R-Tree spatial queries and placeholder rendering.
/// - `ImageMemoryManager._imageDimensions` stays cached so placeholders
///   render at the correct aspect ratio.
///
/// PAGING STRATEGY:
/// - Page-out margin: 3× longest viewport side (1× under pressure)
/// - Page-in margin: 1.5× longest viewport side (hysteresis)
/// - Throttled to run every N eviction cycles (not every frame)
///
/// MEMORY SAVINGS:
/// At 200 images of 2048px:
/// - Before:  200 × ~12MB = ~2.4 GB RAM
/// - After:   ~20 viewport images = ~240 MB
///            180 stubs × ~16KB micro-thumb = ~2.8 MB
class ImageStubManager {
  /// Image IDs that have been stubbed out (texture disposed).
  final Set<String> _stubbedImageIds = {};

  /// 🖼️ Micro-thumbnails (64px) for stubbed images — ~16KB each.
  /// Shown instead of generic placeholder so the canvas feels populated.
  final Map<String, ui.Image> _microThumbnails = {};

  /// Eviction cycles between stub-out passes.
  /// The eviction timer runs every 5s, so interval=2 means every 10s.
  static const int _kStubInterval = 2;

  /// Page-out margin multiplier (relative to viewport longest side).
  /// ⚡ Improvement 3: Dynamic — shrinks under memory pressure.
  double _pageOutMarginMultiplier = 3.0;

  /// Page-in margin multiplier (hysteresis — smaller than page-out).
  static const double _kPageInMarginMultiplier = 1.5;

  /// Maximum images to stub per pass (budget-cap to avoid frame spike).
  static const int _kMaxStubsPerPass = 30;

  /// ⚡ Improvement 1: Maximum images to hydrate per pass (staggered).
  /// Prevents CPU/IO spike when navigating to a cluster of stubs.
  static const int _kMaxHydratesPerPass = 3;

  /// Cycle counter for throttling.
  int _cycleCounter = 0;

  /// Whether the manager is active (only needed for many images).
  bool _isActive = false;

  /// ⚡ Improvement 6: Dynamic activation threshold based on device.
  /// Defaults to 30, dynamically adjusted by [updateFromDeviceClass].
  int _activationThreshold = 30;

  // ═══════════════════════════════════════════════════════════════════════════
  // ⚡ Improvement 7: Telemetry
  // ═══════════════════════════════════════════════════════════════════════════

  int _totalStubbedCount = 0;
  int _totalHydratedCount = 0;
  int _compressedCacheHits = 0;
  int _compressedCacheMisses = 0;

  /// Number of images currently stubbed.
  int get stubbedCount => _stubbedImageIds.length;

  /// Whether an image is currently stubbed.
  bool isStubbed(String imageId) => _stubbedImageIds.contains(imageId);

  /// Total images stubbed since creation (diagnostic).
  int get totalStubbedCount => _totalStubbedCount;

  /// Total images hydrated since creation (diagnostic).
  int get totalHydratedCount => _totalHydratedCount;

  // ---------------------------------------------------------------------------
  // ⚡ Improvement 3: Memory pressure — dynamic margin
  // ---------------------------------------------------------------------------

  /// Adjust margins based on memory pressure level.
  ///
  /// Under pressure, shrink the page-out margin to free more memory.
  void onMemoryPressure(MemoryPressureLevel level) {
    switch (level) {
      case MemoryPressureLevel.normal:
        _pageOutMarginMultiplier = 3.0;
      case MemoryPressureLevel.warning:
        _pageOutMarginMultiplier = 1.5;
      case MemoryPressureLevel.critical:
        _pageOutMarginMultiplier = 0.5;
    }
  }

  // ---------------------------------------------------------------------------
  // ⚡ Improvement 6: Dynamic activation threshold
  // ---------------------------------------------------------------------------

  /// Update activation threshold based on device capabilities.
  ///
  /// [budgetMB] is the dynamic budget from [ImageMemoryBudget].
  /// Higher budgets → higher threshold (more images before stubbing kicks in).
  void updateFromBudget(int budgetMB) {
    if (budgetMB >= 400) {
      _activationThreshold = 60; // flagship
    } else if (budgetMB >= 200) {
      _activationThreshold = 40; // mid-range
    } else if (budgetMB >= 100) {
      _activationThreshold = 30; // modest
    } else {
      _activationThreshold = 15; // budget — activate early
    }
  }

  // ---------------------------------------------------------------------------
  // Stub-out: dispose textures for images far from viewport
  // ---------------------------------------------------------------------------

  /// 🚀 SPATIAL-ONLY stub-out pass — O(loaded) instead of O(n).
  ///
  /// [safeImageIds] is the set of image IDs near the viewport (from R-tree
  /// query). Any loaded image NOT in this set is a candidate for stubbing.
  ///
  /// [loadedImages] maps imagePath → ui.Image (the live texture map).
  /// [imageIdToPath] maps image ID → image path for disposal.
  /// [totalImageCount] is the total number of images on canvas (for activation).
  ///
  /// Returns a list of image paths that were stubbed (for cache invalidation).
  ///
  /// [onBeforeStub] is called before disposing each image, giving the caller
  /// a chance to cache compressed bytes for instant re-hydration.
  List<String> maybeStubOut({
    required Set<String> safeImageIds,
    required Map<String, ui.Image> loadedImages,
    required Map<String, String> imageIdToPath,
    required int totalImageCount,
    void Function(String imagePath, ui.Image image)? onBeforeStub,
  }) {
    // Activation check: only stub when image count warrants it
    if (!_isActive) {
      if (totalImageCount >= _activationThreshold) {
        _isActive = true;
      } else {
        return const [];
      }
    }

    // Throttle: run every _kStubInterval cycles
    _cycleCounter++;
    if (_cycleCounter % _kStubInterval != 0) return const [];

    final stubbedPaths = <String>[];
    int stubbed = 0;

    // 🚀 Iterate only LOADED images (typically ~20), NOT all N images.
    // Any loaded image whose ID is NOT in the safe set → stub it.
    for (final entry in imageIdToPath.entries) {
      if (stubbed >= _kMaxStubsPerPass) break;

      final imageId = entry.key;
      final imagePath = entry.value;

      // Skip already-stubbed images
      if (_stubbedImageIds.contains(imageId)) continue;

      // Skip images without a loaded texture (nothing to dispose)
      if (!loadedImages.containsKey(imagePath)) continue;

      // Skip images that are near the viewport (safe set from R-tree)
      if (safeImageIds.contains(imageId)) continue;

      // 🧠 Let caller cache compressed bytes before dispose
      final image = loadedImages[imagePath];
      if (image != null) {
        onBeforeStub?.call(imagePath, image);
      }

      // Dispose the decoded texture — frees GPU memory
      loadedImages.remove(imagePath);
      image?.dispose();

      _stubbedImageIds.add(imageId);
      stubbedPaths.add(imagePath);
      _totalStubbedCount++;
      stubbed++;
    }

    return stubbedPaths;
  }

  /// 🚀 SPATIAL-ONLY hydration — O(k) instead of O(n).
  ///
  /// [nearbyImageIds] is the list of (id, path, center) tuples from R-tree
  /// query for images near the viewport. Only stubbed images in this list
  /// are candidates for hydration.
  ///
  /// Capped at [_kMaxHydratesPerPass] per call (staggered).
  /// Sorted by distance to viewport center (closest first).
  /// Includes [lodScale] for LOD-aware loading.
  ///
  /// Does NOT perform the actual loading — the caller should invoke
  /// `_preloadImage` for each returned path.
  List<ImageHydrateRequest> maybeHydrate({
    required List<NearbyImage> nearbyImages,
    required Map<String, ui.Image> loadedImages,
    required ui.Rect viewport,
    double canvasScale = 1.0,
  }) {
    if (_stubbedImageIds.isEmpty) return const [];

    final requests = <ImageHydrateRequest>[];
    final toHydrate = <String>[];

    // 🚀 Only iterate R-tree results (k nearby), NOT all N images
    for (final nearby in nearbyImages) {
      if (!_stubbedImageIds.contains(nearby.imageId)) continue;
      if (loadedImages.containsKey(nearby.imagePath)) continue;

      final lodScale = _lodScaleForZoom(canvasScale);
      requests.add(
        ImageHydrateRequest(
          imageId: nearby.imageId,
          imagePath: nearby.imagePath,
          lodScale: lodScale,
        ),
      );
      toHydrate.add(nearby.imageId);
    }

    // Remove from stubbed set
    for (final id in toHydrate) {
      _stubbedImageIds.remove(id);
      _microThumbnails[id]?.dispose();
      _microThumbnails.remove(id);
      _totalHydratedCount++;
    }

    // 🎯 Sort by distance to viewport center (closest first)
    if (requests.length > 1) {
      final center = viewport.center;
      // Build center lookup for O(1) access
      final centerMap = <String, ui.Offset>{};
      for (final n in nearbyImages) {
        centerMap[n.imageId] = n.center;
      }
      requests.sort((a, b) {
        final ca = centerMap[a.imageId] ?? center;
        final cb = centerMap[b.imageId] ?? center;
        final distA = (ca - center).distanceSquared;
        final distB = (cb - center).distanceSquared;
        return distA.compareTo(distB);
      });
    }

    // ⚡ Staggered hydration — cap at N per pass
    if (requests.length > _kMaxHydratesPerPass) {
      return requests.sublist(0, _kMaxHydratesPerPass);
    }

    return requests;
  }

  // ---------------------------------------------------------------------------
  // ⚡ Improvement 4: LOD scale for zoom
  // ---------------------------------------------------------------------------

  /// Compute optimal LOD scale based on current canvas zoom.
  ///
  /// At low zoom, images are tiny → load at reduced resolution.
  /// Saves ~80% RAM when zoomed out.
  static double _lodScaleForZoom(double zoom) {
    if (zoom < 0.15) return 0.20;
    if (zoom < 0.4) return 0.35;
    if (zoom < 0.8) return 0.50;
    return 1.0; // full quality when image is large on screen
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Clear all stub tracking (e.g., on canvas reset).
  void clear() {
    _stubbedImageIds.clear();
    for (final thumb in _microThumbnails.values) {
      thumb.dispose();
    }
    _microThumbnails.clear();
    _totalStubbedCount = 0;
    _totalHydratedCount = 0;
    _compressedCacheHits = 0;
    _compressedCacheMisses = 0;
    _cycleCounter = 0;
    _isActive = false;
    _pageOutMarginMultiplier = 3.0;
  }

  /// Remove tracking for images that no longer exist.
  void removeStaleEntries(Set<String> currentImageIds) {
    _stubbedImageIds.retainAll(currentImageIds);
  }

  /// Remove a specific image from stub tracking (e.g., on delete).
  void removeEntry(String imageId) {
    _stubbedImageIds.remove(imageId);
    _microThumbnails[imageId]?.dispose();
    _microThumbnails.remove(imageId);
  }

  // ---------------------------------------------------------------------------
  // ⚡ Improvement 7: Telemetry
  // ---------------------------------------------------------------------------

  /// Record a compressed cache hit (for telemetry).
  void recordCacheHit() => _compressedCacheHits++;

  /// Record a compressed cache miss (for telemetry).
  void recordCacheMiss() => _compressedCacheMisses++;

  /// Cache hit rate (0.0–1.0). Returns 0 if no lookups yet.
  double get cacheHitRate {
    final total = _compressedCacheHits + _compressedCacheMisses;
    if (total == 0) return 0.0;
    return _compressedCacheHits / total;
  }

  // ---------------------------------------------------------------------------
  // Micro-thumbnails (Improvement 2)
  // ---------------------------------------------------------------------------

  /// Get the micro-thumbnail for a stubbed image (64px, ~16KB).
  /// Returns null if no thumbnail is cached.
  ui.Image? getMicroThumbnail(String imageId) => _microThumbnails[imageId];

  /// Store a micro-thumbnail for a stubbed image.
  /// Called from the lifecycle after generating a 64px thumbnail.
  void setMicroThumbnail(String imageId, ui.Image thumbnail) {
    _microThumbnails[imageId]?.dispose();
    _microThumbnails[imageId] = thumbnail;
  }

  /// Number of micro-thumbnails cached (diagnostic).
  int get microThumbnailCount => _microThumbnails.length;

  /// Unmodifiable view of all micro-thumbnails (for ImagePainter).
  Map<String, ui.Image> get microThumbnails =>
      Map.unmodifiable(_microThumbnails);

  /// Diagnostic stats.
  Map<String, dynamic> get stats => {
    'isActive': _isActive,
    'stubbedCount': _stubbedImageIds.length,
    'totalStubbedCount': _totalStubbedCount,
    'totalHydratedCount': _totalHydratedCount,
    'microThumbnailCount': _microThumbnails.length,
    'cycleCounter': _cycleCounter,
    'pageOutMargin': _pageOutMarginMultiplier,
    'activationThreshold': _activationThreshold,
    'cacheHitRate': cacheHitRate,
  };
}

/// Request to hydrate (re-load) a stubbed image.
class ImageHydrateRequest {
  final String imageId;
  final String imagePath;

  /// ⚡ Improvement 4: LOD scale for zoom-aware loading.
  /// 1.0 = full resolution, 0.5 = half, 0.25 = quarter.
  final double lodScale;

  const ImageHydrateRequest({
    required this.imageId,
    required this.imagePath,
    this.lodScale = 1.0,
  });
}

/// Lightweight data from R-tree query result for hydration.
class NearbyImage {
  final String imageId;
  final String imagePath;
  final ui.Offset center;

  const NearbyImage({
    required this.imageId,
    required this.imagePath,
    required this.center,
  });
}
