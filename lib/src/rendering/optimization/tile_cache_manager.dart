import 'dart:collection';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../drawing/brushes/brushes.dart';

import './stroke_data_manager.dart';
import './advanced_tile_optimizer.dart';
import '../../core/engine_scope.dart';

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
class TileCacheManager {
  // ═══════════════════════════════════════════════════════════════════════════
  // 📐 CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Tile size in logical pixels
  /// 512px: With devicePixelRatio 2.75 = 1408px real
  /// Memory per tile: 1408² × 4 bytes = ~8MB (was ~127MB with 2048)
  static const double tileSize = 512.0;

  /// Maximum number of cached tiles (LRU eviction)
  /// 32 tiles × ~8MB = ~256MB max (was 8×127MB = ~1GB)
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

  /// Generates unique key for tile
  String _tileKey(int x, int y) => '$x:$y';

  /// Calculates tile bounds in canvas coordinates
  Rect getTileBounds(int tileX, int tileY) {
    return Rect.fromLTWH(
      tileX * tileSize,
      tileY * tileSize,
      tileSize,
      tileSize,
    );
  }

  /// Calculates which tiles are visible in the viewport (with preload margin)
  /// Supports negative coordinates for infinite canvas
  List<(int, int)> getVisibleTiles(Rect viewport) {
    // Expand viewport for preload
    final expandedViewport = viewport.inflate(tileSize * preloadMargin);

    final startX = (expandedViewport.left / tileSize).floor();
    final startY = (expandedViewport.top / tileSize).floor();
    final endX = (expandedViewport.right / tileSize).ceil();
    final endY = (expandedViewport.bottom / tileSize).ceil();

    return [
      for (int x = startX; x <= endX; x++)
        for (int y = startY; y <= endY; y++) (x, y),
    ];
  }

  /// Calculates which tiles are touched by bounds (stroke, shape)
  /// Supports negative coordinates for infinite canvas
  List<(int, int)> getTilesForBounds(Rect bounds) {
    final startX = (bounds.left / tileSize).floor();
    final startY = (bounds.top / tileSize).floor();
    final endX = (bounds.right / tileSize).ceil();
    final endY = (bounds.bottom / tileSize).ceil();

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
    canvas.translate(-tileX * tileSize, -tileY * tileSize);

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
    final pixelWidth = (tileSize * devicePixelRatio).ceil();
    final pixelHeight = (tileSize * devicePixelRatio).ceil();

    // toImageSync is synchronous - no lag!
    final image = picture.toImageSync(pixelWidth, pixelHeight);
    _totalImagesCreated++;

    // 🗑️ CRITICAL: Dispose picture after rasterization to avoid memory leak
    picture.dispose();
    _totalPicturesDisposed++;

    // Add to cache (now space is guaranteed)
    _tileCache[key] = image;
    _tileStrokeCounts[key] = strokesInTile.length;
    _dirtyTiles.remove(key);

    _logMemoryStats('rasterizeTile-end');
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
    final pixelWidth = (tileSize * devicePixelRatio).ceil();
    final pixelHeight = (tileSize * devicePixelRatio).ceil();

    // Create recorder and draw existing bitmap + new stroke
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Draw existing bitmap (without scaling — already at HiDPI size)
    canvas.drawImage(existingImage, Offset.zero, Paint());

    // 2. Overlay the new stroke (with HiDPI scaling + tile translation)
    canvas.scale(devicePixelRatio);
    canvas.translate(-tileX * tileSize, -tileY * tileSize);
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
  void paintVisibleTiles(Canvas canvas, Rect viewport, double scale) {
    final visibleTiles = getVisibleTiles(viewport);

    for (final (tileX, tileY) in visibleTiles) {
      final key = _tileKey(tileX, tileY);
      final image = _tileCache[key];

      if (image != null) {
        // Update access for LRU
        _touchTile(key);

        // Calculate destination position
        final destRect = Rect.fromLTWH(
          tileX * tileSize,
          tileY * tileSize,
          tileSize,
          tileSize,
        );

        // Draw correctly scaled tile
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          destRect,
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    }
  }

  /// 🚀 Draw ALL cached tiles on the canvas
  ///
  /// Used when paint() is called only on stroke changes (not on pan/zoom).
  /// The Transform widget composites the canvas layer → ALL tiles are needed
  /// because the GPU will show them when user pans.
  /// Cost: 1 drawImageRect per cached tile (max 32) — negligible.
  void paintAllCachedTiles(Canvas canvas) {
    final tilePaint = Paint()..filterQuality = FilterQuality.medium;

    for (final entry in _tileCache.entries) {
      final key = entry.key;
      final image = entry.value;

      // Parse tile coordinates from key "x:y"
      final parts = key.split(':');
      if (parts.length != 2) continue;
      final tileX = int.tryParse(parts[0]);
      final tileY = int.tryParse(parts[1]);
      if (tileX == null || tileY == null) continue;

      final destRect = Rect.fromLTWH(
        tileX * tileSize,
        tileY * tileSize,
        tileSize,
        tileSize,
      );

      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        destRect,
        tilePaint,
      );
    }
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

  /// Invalidate un singolo tile (will come ri-rasterizzato al prossimo paint)
  void invalidateTile(int tileX, int tileY) {
    final key = _tileKey(tileX, tileY);
    _dirtyTiles.add(key);

    // 🗑️ CRITICAL FIX: Dispose image when we invalidate tile
    // The old image is no longer needed, will be re-rasterized
    final oldImage = _tileCache[key];
    if (oldImage != null) {
      _tileCache.remove(key);
      _tileStrokeCounts.remove(key);

      // 🐛 FIX: IMMEDIATE Dispose (not Future.microtask) to avoid leak
      oldImage.dispose();
      _totalImagesDisposed++;
    }
    _logMemoryStats('invalidateTile');
  }

  /// Invalidate tutti i tile che contengono un certo stroke
  void invalidateTilesForStroke(ProStroke stroke) {
    final bounds = stroke.bounds;
    if (bounds == Rect.zero) return;

    for (final (tileX, tileY) in getTilesForBounds(bounds)) {
      invalidateTile(tileX, tileY);
    }
  }

  /// Invalidate tutti i tile che intersecano un bounds
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
  void evictDistantTiles(Rect viewport) {
    final visibleTiles =
        getVisibleTiles(viewport).map((t) => _tileKey(t.$1, t.$2)).toSet();

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

  /// Invalidate tutti i tile (ricostruzione completa)
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
