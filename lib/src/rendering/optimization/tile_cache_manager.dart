import 'dart:collection';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../drawing/brushes/brushes.dart';

import './stroke_data_manager.dart';
import './advanced_tile_optimizer.dart';
import './memory_managed_cache.dart';
import './isolate_geometry_worker.dart';
import '../../core/engine_scope.dart';
import '../../core/conscious_architecture.dart';
import './anticipatory_tile_prefetch.dart';

/// 🚀 TILE CACHE MANAGER - Scalable tile caching for 100k+ strokes
///
/// STRATEGY:
/// - Canvas divided into 4096x4096 px tiles
/// - Only visible tiles are rasterized
/// - Every tile has a cached ui.Image (HiDPI)
/// - LRU eviction to limit memory
/// - Invalidatezione granulare (1 tile invece di tutto)
///
/// PERFORMANCE WITH 100k+ STROKES:
/// - Memory: O(viewport) instead of O(n)
/// - Rendering: O(1) - draws only cached images
/// - Invalidatezione: O(k) dove k = tile coinvolti (typically 1-2)
///
/// ARCHITECTURE PREPARED FOR:
/// - Phase 2: LOD (Level of Detail) for zoom
/// - Phase 3: Disk-backed tiles for 10M+ strokes
class TileCacheManager
    with MemoryManagedCacheMixin
    implements MemoryManagedCache {
  // ═══════════════════════════════════════════════════════════════════════════
  // 📐 CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Base tile size in logical pixels (adapted by scale)
  /// Memory per tile at 3x DPI: (256×3)² × 4 bytes = ~2.4MB
  /// 🚀 PERF: Reduced from 512 (9.4MB/tile) to 256 (2.4MB/tile)
  /// to cut GC pressure by ~75% — was causing 168ms P99 pauses.
  static const double baseTileSize = 256.0;

  /// Get adaptive tile size based on zoom level
  static double getTileSize(double scale) {
    return baseTileSize / scale.clamp(0.25, 4.0).ceil();
  }

  /// Maximum number of cached tiles (LRU eviction)
  /// 32 tiles × ~2.4MB = ~76MB max (acceptable on modern 6-12GB phones)
  /// 🚀 PERF: Raised from 16 (38MB) to 32 (76MB) to prevent constant
  /// LRU thrashing — a 3×3 visible grid + prefetch + LOD fallback easily
  /// exceeds 16 tiles, causing re-rasterization every frame.
  static const int maxCachedTiles = 32;

  /// Extra margin to pre-load adjacent tiles
  static const double preloadMargin = 0.5; // 50% of the tile

  // 🐛 DEBUG: Counters to track Image/Picture lifecycle
  static int _totalImagesCreated = 0;
  static int _totalImagesDisposed = 0;
  static int _totalPicturesCreated = 0;
  static int _totalPicturesDisposed = 0;

  static void _logMemoryStats(String context) {
    // No-op: logging removed with singleton migration
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🗂️ CACHE STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// LRU Cache: tileKey -> rasterized image
  /// LinkedHashMap maintains access order for LRU
  final LinkedHashMap<String, ui.Image> _tileCache = LinkedHashMap();

  /// Tiles that need to be re-rasterized
  final Set<String> _dirtyTiles = {};

  /// Stroke count per tile to detect changes
  final Map<String, int> _tileStrokeCounts = {};

  /// Current device pixel ratio
  double _devicePixelRatio = 1.0;

  /// Current scale bucket for grid alignment (flushes when changed)
  int _currentScaleBucket = 1;

  /// Update the internal scale bucket.
  ///
  /// Unlike the previous implementation, this does NOT clear the cache
  /// on bucket change. Tiles from the old LOD level stay in the LRU
  /// cache and are evicted naturally by the LRU policy. This eliminates
  /// the full-cache flush jank on pinch-zoom transitions.
  void updateScale(double scale) {
    _currentScaleBucket = scale.clamp(0.25, 4.0).ceil();
  }

  /// Get the active tile size for the current bucket
  double get currentTileSize => baseTileSize / _currentScaleBucket;

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 SINGLETON (optional, can be instance)
  // ═══════════════════════════════════════════════════════════════════════════
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static TileCacheManager get instance => EngineScope.current.tileCacheManager;

  /// Creates a new instance (used by [EngineScope]).
  TileCacheManager.create();

  // ═══════════════════════════════════════════════════════════════════════════
  // 📐 TILE GEOMETRY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generates unique key for tile, including LOD level.
  ///
  /// Format: `lod:x:y` — tiles from different zoom levels coexist
  /// in the same LRU cache without colliding.
  String _tileKey(int x, int y) => '$_currentScaleBucket:$x:$y';

  /// Generates tile key for a specific LOD level.
  String _tileKeyForLod(int lod, int x, int y) => '$lod:$x:$y';

  /// Returns all LOD levels that currently have cached tiles.
  Set<int> get _allCachedLodLevels {
    final lods = <int>{};
    for (final key in _tileCache.keys) {
      final colonIdx = key.indexOf(':');
      if (colonIdx > 0) {
        final lod = int.tryParse(key.substring(0, colonIdx));
        if (lod != null) lods.add(lod);
      }
    }
    return lods;
  }

  /// Calculates tile bounds in canvas coordinates
  Rect getTileBounds(int tileX, int tileY, double scale) {
    updateScale(scale);
    final ts = getTileSize(scale);
    return Rect.fromLTWH(tileX * ts, tileY * ts, ts, ts);
  }

  /// Calculates which tiles are visible in the viewport (with preload margin)
  /// Supports negative coordinates for infinite canvas
  List<(int, int)> getVisibleTiles(Rect viewport, double scale) {
    updateScale(scale);
    final ts = getTileSize(scale);

    // 🧠 CONSCIOUS ARCHITECTURE: Use directional margins from
    // AnticipatoryTilePrefetch if available, otherwise fall back
    // to the static uniform preloadMargin.
    Rect expandedViewport;
    try {
      final arch = EngineScope.current.consciousArchitecture;
      final prefetch = arch.find<AnticipatoryTilePrefetch>();
      if (prefetch != null && prefetch.isActive) {
        final m = prefetch.margins; // [left, top, right, bottom] in tiles
        expandedViewport = Rect.fromLTRB(
          viewport.left - m[0] * ts,
          viewport.top - m[1] * ts,
          viewport.right + m[2] * ts,
          viewport.bottom + m[3] * ts,
        );
      } else {
        expandedViewport = viewport.inflate(ts * preloadMargin);
      }
    } catch (_) {
      // EngineScope not initialized yet — use uniform margin.
      expandedViewport = viewport.inflate(ts * preloadMargin);
    }

    final startX = (expandedViewport.left / ts).floor();
    final startY = (expandedViewport.top / ts).floor();
    final endX = (expandedViewport.right / ts).ceil();
    final endY = (expandedViewport.bottom / ts).ceil();

    return [
      for (int x = startX; x <= endX; x++)
        for (int y = startY; y <= endY; y++) (x, y),
    ];
  }

  /// Calculates which tiles are touched by bounds (stroke, shape)
  /// Uses internally cached scale bucket to not require scale parameter
  List<(int, int)> getTilesForBounds(Rect bounds) {
    final ts = currentTileSize;
    final startX = (bounds.left / ts).floor();
    final startY = (bounds.top / ts).floor();
    final endX = (bounds.right / ts).ceil();
    final endY = (bounds.bottom / ts).ceil();

    return [
      for (int x = startX; x <= endX; x++)
        for (int y = startY; y <= endY; y++) (x, y),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎨 TILE RASTERIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Rasterize a single tile with its strokes at max quality
  ///
  /// [tileX], [tileY]: Tile coordinates
  /// [strokesInTile]: Strokes intersecting this tile
  /// [devicePixelRatio]: For HiDPI rendering
  void rasterizeTile(
    int tileX,
    int tileY,
    List<ProStroke> strokesInTile,
    double devicePixelRatio,
  ) {
    final key = _tileKey(tileX, tileY);
    _devicePixelRatio = devicePixelRatio;

    // 🗑️ CRITICAL FIX: Dispose previous image BEFORE creating new one
    final oldImage = _tileCache[key];
    if (oldImage != null) {
      // Remove from cache BEFORE dispose to avoid race conditions
      _tileCache.remove(key);
      _tileStrokeCounts.remove(key);
      // 🐛 DEBUG: IMMEDIATE Dispose instead of Future.microtask
      oldImage.dispose();
      _totalImagesDisposed++;
    }

    if (strokesInTile.isEmpty) {
      _dirtyTiles.remove(key);
      _logMemoryStats('rasterizeTile-empty');
      return;
    }

    // 🗑️ LRU eviction BEFORE adding new tile
    _evictOldestTilesBeforeAdd();

    // Create recorder to record drawing
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Scale for HiDPI
    canvas.scale(devicePixelRatio);

    // Translate to position tile at origin
    final ts = currentTileSize;
    canvas.translate(-tileX * ts, -tileY * ts);

    // 📦 BATCH RENDERING: group strokes by penType/color/width,
    // then draw each batch in a single pass (ballpoint combined into 1 path).
    final optimizer = AdvancedTileOptimizer.instance;
    final batches = optimizer.batchStrokes(strokesInTile);
    for (final entry in batches.entries) {
      optimizer.drawStrokeBatch(canvas, entry.key, entry.value);
    }

    final picture = recorder.endRecording();
    _totalPicturesCreated++;

    // Rasterize at HiDPI size
    final pixelWidth = (ts * devicePixelRatio).ceil();
    final pixelHeight = (ts * devicePixelRatio).ceil();

    // toImageSync is synchronous - no lag!
    final image = picture.toImageSync(pixelWidth, pixelHeight);
    _totalImagesCreated++;

    // 🗑️ CRITICAL: Dispose picture after rasterization to avoid memory leak
    picture.dispose();
    _totalPicturesDisposed++;

    // Add to cache (skip if hysteresis refill-lock is active)
    if (isRefillAllowed) {
      _tileCache[key] = image;
      _tileStrokeCounts[key] = strokesInTile.length;
      _dirtyTiles.remove(key);
    } else {
      // Draw direct without caching — image will be GC'd
      _totalImagesDisposed++;
    }

    _logMemoryStats('rasterizeTile-end');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚀 CHUNKED RASTERIZATION (Gap 5)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Maximum strokes per chunk to stay within frame budget (~4ms per chunk).
  static const int maxStrokesPerChunk = 80;

  /// Tracks in-progress chunked rasterizations: tileKey → strokesProcessedSoFar.
  final Map<String, int> _chunkProgress = {};

  /// 🚀 Rasterize a tile in chunks to avoid exceeding the frame budget.
  ///
  /// Each call processes at most [maxStrokesPerChunk] strokes. Returns
  /// the number of remaining strokes. Call repeatedly (e.g., from
  /// FrameBudgetManager) until 0 is returned.
  ///
  /// **Progressive LOD**: The first chunk produces a visible (partial) tile
  /// immediately, so the viewport never shows blank space during rasterization.
  /// Subsequent chunks composite additional strokes on top.
  ///
  /// Returns: number of strokes remaining (0 = complete).
  int rasterizeTileChunked(
    int tileX,
    int tileY,
    List<ProStroke> allStrokesInTile,
    double devicePixelRatio,
  ) {
    if (allStrokesInTile.isEmpty) {
      return 0;
    }

    // If total strokes fit in one chunk, use the fast full-rasterize path
    if (allStrokesInTile.length <= maxStrokesPerChunk) {
      rasterizeTile(tileX, tileY, allStrokesInTile, devicePixelRatio);
      _chunkProgress.remove(_tileKey(tileX, tileY));
      return 0;
    }

    final key = _tileKey(tileX, tileY);
    _devicePixelRatio = devicePixelRatio;
    final ts = currentTileSize;
    final pixelWidth = (ts * devicePixelRatio).ceil();
    final pixelHeight = (ts * devicePixelRatio).ceil();

    // Determine chunk range
    final processedSoFar = _chunkProgress[key] ?? 0;
    final chunkEnd = (processedSoFar + maxStrokesPerChunk).clamp(
      0,
      allStrokesInTile.length,
    );
    final chunkStrokes = allStrokesInTile.sublist(processedSoFar, chunkEnd);

    // Create recorder
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Draw existing tile (if any) as the base layer
    final existingImage = _tileCache[key];
    if (existingImage != null) {
      canvas.drawImage(existingImage, Offset.zero, Paint());
    }

    // 2. Overlay this chunk's strokes
    canvas.scale(devicePixelRatio);
    canvas.translate(-tileX * ts, -tileY * ts);

    final optimizer = AdvancedTileOptimizer.instance;
    final batches = optimizer.batchStrokes(chunkStrokes);
    for (final entry in batches.entries) {
      optimizer.drawStrokeBatch(canvas, entry.key, entry.value);
    }

    final picture = recorder.endRecording();
    _totalPicturesCreated++;

    final newImage = picture.toImageSync(pixelWidth, pixelHeight);
    _totalImagesCreated++;

    picture.dispose();
    _totalPicturesDisposed++;

    // Replace old image
    if (existingImage != null) {
      _tileCache.remove(key);
      existingImage.dispose();
      _totalImagesDisposed++;
    } else {
      _evictOldestTilesBeforeAdd();
    }

    if (isRefillAllowed) {
      _tileCache[key] = newImage;
      _tileStrokeCounts[key] = chunkEnd;
      _dirtyTiles.remove(key);
    }

    // Update progress
    final remaining = allStrokesInTile.length - chunkEnd;
    if (remaining > 0) {
      _chunkProgress[key] = chunkEnd;
    } else {
      _chunkProgress.remove(key);
    }

    return remaining;
  }

  /// Whether a tile has pending chunked rasterization work.
  bool hasPendingChunks(int tileX, int tileY) {
    return _chunkProgress.containsKey(_tileKey(tileX, tileY));
  }

  /// Clear all chunk progress tracking.
  void clearChunkProgress() {
    _chunkProgress.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ⚡ ISOLATE-BASED ASYNC RASTERIZATION (Gap 8)
  // ═══════════════════════════════════════════════════════════════════════════

  /// 🚀 Rasterize a tile asynchronously, offloading geometry computation
  /// to a background isolate.
  ///
  /// For tiles with [minStrokesForIsolate]+ strokes, the CPU-heavy path
  /// building runs on a background isolate. The main thread only does
  /// the final `canvas.drawPath()` calls (GPU-bound, fast).
  ///
  /// Falls back to synchronous [rasterizeTile] for small tiles where
  /// the isolate spawn overhead exceeds computation cost.
  Future<void> rasterizeTileAsync(
    int tileX,
    int tileY,
    List<ProStroke> strokesInTile,
    double devicePixelRatio,
  ) async {
    // Small tiles: sync is faster (no isolate overhead)
    if (strokesInTile.length < minStrokesForIsolate) {
      rasterizeTile(tileX, tileY, strokesInTile, devicePixelRatio);
      return;
    }

    final key = _tileKey(tileX, tileY);
    _devicePixelRatio = devicePixelRatio;
    final ts = currentTileSize;
    final pixelWidth = (ts * devicePixelRatio).ceil();
    final pixelHeight = (ts * devicePixelRatio).ceil();

    // 1. Serialize stroke data (fast, main thread)
    final inputs = serializeStrokes(strokesInTile);

    // 2. Compute geometry on background isolate (CPU-heavy)
    final result = await computeGeometryOnIsolate(inputs);

    // 3. Check if tile was invalidated while we were computing
    if (_dirtyTiles.contains(key) || !isRefillAllowed) {
      return; // Tile was invalidated — discard stale result
    }

    // 4. Dispose previous image
    final oldImage = _tileCache[key];
    if (oldImage != null) {
      _tileCache.remove(key);
      _tileStrokeCounts.remove(key);
      oldImage.dispose();
      _totalImagesDisposed++;
    } else {
      _evictOldestTilesBeforeAdd();
    }

    // 5. Record drawing using pre-computed geometry (fast, main thread)
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(devicePixelRatio);
    canvas.translate(-tileX * ts, -tileY * ts);

    // Draw batched ballpoint paths (from isolate-computed Float32List)
    drawBatchedPaths(canvas, result);

    // Draw complex brush strokes (BrushEngine, main thread)
    drawComplexSegments(canvas, result, strokesInTile);

    final picture = recorder.endRecording();
    _totalPicturesCreated++;

    final image = picture.toImageSync(pixelWidth, pixelHeight);
    _totalImagesCreated++;

    picture.dispose();
    _totalPicturesDisposed++;

    // 6. Cache the result
    if (isRefillAllowed) {
      _tileCache[key] = image;
      _tileStrokeCounts[key] = strokesInTile.length;
      _dirtyTiles.remove(key);
    }
  }

  /// 🚀 INCREMENTAL UPDATE: Overlays a single stroke on an existing tile
  ///
  /// Instead of re-rasterizing ALL strokes in the tile, draws only
  /// the new stroke over the cached bitmap. O(1) per stroke vs O(N) full.
  ///
  /// Returns true if incremental update succeeded, false if full is needed.
  bool incrementalUpdateTile(
    int tileX,
    int tileY,
    ProStroke newStroke,
    double devicePixelRatio,
  ) {
    final key = _tileKey(tileX, tileY);
    final existingImage = _tileCache[key];

    // If there is no cached tile, full rasterization is needed
    if (existingImage == null) return false;

    _devicePixelRatio = devicePixelRatio;
    final ts = currentTileSize;
    final pixelWidth = (ts * devicePixelRatio).ceil();
    final pixelHeight = (ts * devicePixelRatio).ceil();

    // Create recorder and draw existing bitmap + new stroke
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Draw existing bitmap (without scaling — already at HiDPI size)
    canvas.drawImage(existingImage, Offset.zero, Paint());

    // 2. Overlay the new stroke (with HiDPI scaling + tile translation)
    canvas.scale(devicePixelRatio);
    canvas.translate(-tileX * ts, -tileY * ts);
    _drawStroke(canvas, newStroke);

    final picture = recorder.endRecording();
    _totalPicturesCreated++;

    // Composite rasterization
    final newImage = picture.toImageSync(pixelWidth, pixelHeight);
    _totalImagesCreated++;

    picture.dispose();
    _totalPicturesDisposed++;

    // Dispose old image and replace
    _tileCache.remove(key);
    existingImage.dispose();
    _totalImagesDisposed++;

    _tileCache[key] = newImage;
    _tileStrokeCounts[key] = (_tileStrokeCounts[key] ?? 0) + 1;
    _dirtyTiles.remove(key);

    return true;
  }

  /// Draws a stroke on the canvas at max quality (zero LOD)
  void _drawStroke(Canvas canvas, ProStroke stroke) {
    // Get points (lazy loading if configured)
    final points = StrokeDataManager.getPoints(
      stroke.id,
      fallbackPoints: stroke.points,
    );
    if (points.isEmpty) return;

    BrushEngine.renderStroke(
      canvas,
      points,
      stroke.color,
      stroke.baseWidth,
      stroke.penType,
      stroke.settings,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🖼️ RENDERING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Draws all visible tiles on the canvas
  ///
  /// [canvas]: Canvas to draw on
  /// [viewport]: Current viewport in canvas coordinates
  /// [scale]: Current scale of the canvas
  ///
  /// 🚀 LOD CROSS-FADE: When a tile is missing at the current LOD level,
  /// attempts to draw a fallback tile from an adjacent LOD level to prevent
  /// visible "popping". The fallback tile is drawn at full opacity since
  /// it will be naturally replaced when the correct LOD tile is rasterized.
  void paintVisibleTiles(Canvas canvas, Rect viewport, double scale) {
    final visibleTiles = getVisibleTiles(viewport, scale);
    final ts = currentTileSize;
    final tilePaint = Paint()..filterQuality = FilterQuality.medium;

    for (final (tileX, tileY) in visibleTiles) {
      final key = _tileKey(tileX, tileY);
      final image = _tileCache[key];

      if (image != null) {
        // Current LOD tile exists — draw normally
        _touchTile(key);
        final destRect = Rect.fromLTWH(tileX * ts, tileY * ts, ts, ts);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          destRect,
          tilePaint,
        );
      } else {
        // 🚀 LOD CROSS-FADE: No tile at current LOD — search other levels
        _drawFallbackTile(canvas, tileX, tileY, ts, tilePaint);
      }
    }
  }

  /// 🚀 LOD CROSS-FADE: Draw a fallback tile from an adjacent LOD level.
  ///
  /// When the current LOD tile hasn't been rasterized yet, this looks
  /// through cached tiles at other LOD levels to find one that covers
  /// the same spatial region. The fallback is slightly blurrier but
  /// eliminates the "pop" visual artifact during zoom transitions.
  void _drawFallbackTile(
    Canvas canvas,
    int tileX,
    int tileY,
    double ts,
    Paint tilePaint,
  ) {
    // Spatial bounds of the missing tile in canvas coordinates
    final missingBounds = Rect.fromLTWH(tileX * ts, tileY * ts, ts, ts);

    // Search adjacent LOD levels (prefer closest)
    for (final lod in _allCachedLodLevels) {
      if (lod == _currentScaleBucket) continue;

      final otherTs = baseTileSize / lod;
      // Find which tile at this LOD level covers the center of our missing tile
      final centerX = missingBounds.center.dx;
      final centerY = missingBounds.center.dy;
      final fallbackTileX = (centerX / otherTs).floor();
      final fallbackTileY = (centerY / otherTs).floor();

      final fallbackKey = _tileKeyForLod(lod, fallbackTileX, fallbackTileY);
      final fallbackImage = _tileCache[fallbackKey];

      if (fallbackImage != null) {
        _touchTile(fallbackKey);

        // The fallback tile covers a different area (different tile size).
        // We need to draw only the portion that overlaps our missing tile.
        final fallbackBounds = Rect.fromLTWH(
          fallbackTileX * otherTs,
          fallbackTileY * otherTs,
          otherTs,
          otherTs,
        );

        // Source rect: portion of the fallback image that overlaps
        final overlap = missingBounds.intersect(fallbackBounds);
        if (overlap.isEmpty) continue;

        // Map overlap from canvas-space to fallback-image pixel-space
        final imgW = fallbackImage.width.toDouble();
        final imgH = fallbackImage.height.toDouble();
        final srcRect = Rect.fromLTWH(
          (overlap.left - fallbackBounds.left) / otherTs * imgW,
          (overlap.top - fallbackBounds.top) / otherTs * imgH,
          overlap.width / otherTs * imgW,
          overlap.height / otherTs * imgH,
        );

        canvas.drawImageRect(fallbackImage, srcRect, overlap, tilePaint);
        return; // Found a fallback — stop searching
      }
    }
  }

  /// 🚀 Draw ALL cached tiles for the CURRENT LOD level on the canvas.
  ///
  /// Only draws tiles matching `_currentScaleBucket` — tiles from other
  /// LOD levels stay in cache but are not rendered.
  void paintAllCachedTiles(Canvas canvas) {
    final tilePaint = Paint()..filterQuality = FilterQuality.medium;
    final lodPrefix = '$_currentScaleBucket:';

    for (final entry in _tileCache.entries) {
      final key = entry.key;
      if (!key.startsWith(lodPrefix)) continue; // Skip other LOD levels

      final image = entry.value;

      // Parse tile coordinates from key "lod:x:y"
      final parts = key.split(':');
      if (parts.length != 3) continue;
      final tileX = int.tryParse(parts[1]);
      final tileY = int.tryParse(parts[2]);
      if (tileX == null || tileY == null) continue;

      final ts = currentTileSize;
      final destRect = Rect.fromLTWH(tileX * ts, tileY * ts, ts, ts);

      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        destRect,
        tilePaint,
      );
    }
  }

  /// 🚀 Paint a single cached tile by coordinates.
  ///
  /// Used during hybrid rendering (eraser) to composite individual clean
  /// tiles while dirty tiles are rendered inline.
  void paintSingleTile(Canvas canvas, int tileX, int tileY) {
    final key = _tileKey(tileX, tileY);
    final image = _tileCache[key];
    if (image == null) return;

    _touchTile(key);
    final ts = currentTileSize;
    final destRect = Rect.fromLTWH(tileX * ts, tileY * ts, ts, ts);
    final tilePaint = Paint()..filterQuality = FilterQuality.medium;

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      destRect,
      tilePaint,
    );
  }

  /// Updates LRU order for a tile
  void _touchTile(String key) {
    if (_tileCache.containsKey(key)) {
      final image = _tileCache.remove(key);
      if (image != null) {
        _tileCache[key] = image;
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔄 INVALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Invalidate a tile at ALL LOD levels.
  ///
  /// When content changes (stroke add/remove), the affected spatial region
  /// must be invalidated at every cached LOD level, not just the active one.
  /// Otherwise, switching zoom levels would show stale tiles.
  void invalidateTile(int tileX, int tileY) {
    // Invalidate at current LOD level
    _invalidateSingleTile(_tileKey(tileX, tileY));

    // Also invalidate tiles at other cached LOD levels that overlap
    // the same spatial region. Different LOD levels have different tile
    // sizes, so the tile coordinates differ per level.
    for (final lod in _allCachedLodLevels) {
      if (lod == _currentScaleBucket) continue;
      // Compute the spatial bounds of this tile at current LOD
      final ts = currentTileSize;
      final bounds = Rect.fromLTWH(tileX * ts, tileY * ts, ts, ts);
      // Map to tile coordinates at the other LOD level
      final otherTs = baseTileSize / lod;
      final startX = (bounds.left / otherTs).floor();
      final startY = (bounds.top / otherTs).floor();
      final endX = (bounds.right / otherTs).ceil();
      final endY = (bounds.bottom / otherTs).ceil();
      for (int x = startX; x <= endX; x++) {
        for (int y = startY; y <= endY; y++) {
          _invalidateSingleTile(_tileKeyForLod(lod, x, y));
        }
      }
    }
    _logMemoryStats('invalidateTile');
  }

  /// Invalidate a single tile by key (internal helper).
  void _invalidateSingleTile(String key) {
    _dirtyTiles.add(key);
    final oldImage = _tileCache[key];
    if (oldImage != null) {
      _tileCache.remove(key);
      _tileStrokeCounts.remove(key);
      oldImage.dispose();
      _totalImagesDisposed++;
    }
  }

  /// Invalidate all tiles that contain a certain stroke
  void invalidateTilesForStroke(ProStroke stroke) {
    final bounds = stroke.bounds;
    if (bounds == Rect.zero) return;

    for (final (tileX, tileY) in getTilesForBounds(bounds)) {
      invalidateTile(tileX, tileY);
    }
  }

  /// Invalidate all tiles that intersect a bounds
  void invalidateTilesInBounds(Rect bounds) {
    for (final (tileX, tileY) in getTilesForBounds(bounds)) {
      invalidateTile(tileX, tileY);
    }
  }

  /// Gets tiles that need to be updated
  Set<String> get dirtyTiles => Set.unmodifiable(_dirtyTiles);

  /// Checks if a specific tile is dirty
  bool isTileDirty(int tileX, int tileY) {
    return _dirtyTiles.contains(_tileKey(tileX, tileY));
  }

  /// Checks if a tile is in cache
  bool hasTileCached(int tileX, int tileY) {
    return _tileCache.containsKey(_tileKey(tileX, tileY));
  }

  /// Gets the number of strokes cached for a tile (0 if not in cache)
  int getTileStrokeCount(int tileX, int tileY) {
    return _tileStrokeCounts[_tileKey(tileX, tileY)] ?? 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🗑️ LRU EVICTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// 🗑️ Removes tile to make space BEFORE adding a new one
  void _evictOldestTilesBeforeAdd() {
    if (_tileCache.length < maxCachedTiles) return;

    int evicted = 0;

    // Evict if we are already at the limit (to make space for new one)
    while (_tileCache.length >= maxCachedTiles) {
      final oldestKey = _tileCache.keys.first;
      final oldImage = _tileCache[oldestKey];
      if (oldImage != null) {
        // 🐛 DEBUG: IMMEDIATE Dispose instead of Future.microtask
        oldImage.dispose();
        _totalImagesDisposed++;
        evicted++;
      }
      _tileCache.remove(oldestKey);
      _tileStrokeCounts.remove(oldestKey);

      _dirtyTiles.remove(oldestKey);
    }

    _logMemoryStats('evictOldest');
  }

  /// Forces eviction of tiles far from viewport
  void evictDistantTiles(Rect viewport, double scale) {
    final visibleTiles = getVisibleTiles(
      viewport,
      scale,
    ).map((t) => _tileKey(t.$1, t.$2)).toSet();

    final keysToRemove = <String>[];
    for (final key in _tileCache.keys) {
      if (!visibleTiles.contains(key)) {
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      final oldImage = _tileCache[key];
      if (oldImage != null) {
        // 🐛 DEBUG: Dispose IMMEDIATO
        oldImage.dispose();
        _totalImagesDisposed++;
      }
      _tileCache.remove(key);
      _tileStrokeCounts.remove(key);

      _dirtyTiles.remove(key);
    }

    _logMemoryStats('evictDistant');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📊 STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Number of tiles currently in cache
  int get cachedTileCount => _tileCache.length;

  /// Number of dirty tiles
  int get dirtyTileCount => _dirtyTiles.length;

  /// Estimated memory used from cache (in bytes)
  int get estimatedMemoryUsage {
    int total = 0;
    for (final image in _tileCache.values) {
      total += image.width * image.height * 4; // 4 bytes per pixel (RGBA)
    }
    return total;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧠 MEMORY MANAGED CACHE INTERFACE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  String get cacheName => 'TileCache';

  @override
  int get estimatedMemoryBytes => estimatedMemoryUsage;

  @override
  int get cacheEntryCount => cachedTileCount;

  /// Expensive: full GPU re-rasterization needed to rebuild.
  @override
  int get evictionPriority => 70;

  @override
  void evictFraction(double fraction) {
    if (_tileCache.isEmpty || fraction <= 0) return;

    final toEvict = (cachedTileCount * fraction).ceil().clamp(
      1,
      cachedTileCount,
    );
    int evicted = 0;

    while (evicted < toEvict && _tileCache.isNotEmpty) {
      final oldestKey = _tileCache.keys.first;
      final oldImage = _tileCache[oldestKey];
      if (oldImage != null) {
        oldImage.dispose();
        _totalImagesDisposed++;
      }
      _tileCache.remove(oldestKey);
      _tileStrokeCounts.remove(oldestKey);
      _dirtyTiles.remove(oldestKey);
      evicted++;
    }
  }

  @override
  void evictAll() => clear();

  /// Statistics for debugging
  Map<String, dynamic> get stats => {
    'cachedTiles': cachedTileCount,
    'dirtyTiles': dirtyTileCount,
    'memoryMB': (estimatedMemoryUsage / 1024 / 1024).toStringAsFixed(1),
    'devicePixelRatio': _devicePixelRatio,
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧹 CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Invalidate all tiles (complete reconstruction)
  void invalidateAll() {
    _dirtyTiles.addAll(_tileCache.keys);
  }

  /// Clears the entire cache
  void clear() {
    // Dispose all Images IMMEDIATELY
    for (final image in _tileCache.values) {
      image.dispose();
      _totalImagesDisposed++;
    }
    _tileCache.clear();
    _dirtyTiles.clear();
    _tileStrokeCounts.clear();

    _logMemoryStats('clear');
  }

  /// Dispose manager
  void dispose() {
    clear();
  }
}
