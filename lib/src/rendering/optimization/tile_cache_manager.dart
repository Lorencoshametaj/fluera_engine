import 'dart:collection';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 🧩 TILE CACHE MANAGER — Regional cache for O(1) stroke addition
///
/// Divides the canvas into fixed-size tiles (4096×4096 canvas units).
/// Each tile stores a pre-rendered `ui.Picture` of the strokes within it.
///
/// PERFORMANCE:
/// - Adding a stroke invalidates only the 1-2 tiles it overlaps
/// - Drawing replays only tiles visible in the current viewport
/// - Full cache rebuild cost: O(strokes_per_tile) instead of O(all_strokes)
///
/// TILE COORDINATE SYSTEM:
/// Canvas point (x, y) → tile (x ~/ tileSize, y ~/ tileSize)
/// Tile (tx, ty) covers canvas area [tx*4096, ty*4096, (tx+1)*4096, (ty+1)*4096]
class TileCacheManager {
  /// Size of each tile in canvas units.
  /// 4096 is a good balance: large enough to contain many strokes per tile
  /// (reducing overhead), small enough that rebuilding one tile is fast.
  static const double tileSize = 4096.0;

  /// Maximum cached tiles to prevent OOM on large canvases.
  /// 128 tiles × display lists = very memory-efficient (Pictures are
  /// GPU command lists, not raw bitmaps).
  static const int maxTiles = 48;

  /// Cached pictures keyed by tile coordinates.
  /// LinkedHashMap preserves insertion order for LRU eviction.
  final LinkedHashMap<TileKey, ui.Picture> _tiles =
      LinkedHashMap<TileKey, ui.Picture>();

  /// 🚀 STALE TILES: old-LOD tiles kept as GPU-scaled fallback during
  /// progressive rebuild. Disposed lazily as new tiles replace them.
  final Map<TileKey, ui.Picture> _staleTiles = {};

  /// Scene graph version when each tile was last built.
  final Map<TileKey, int> _tileVersions = {};

  /// Total stroke count when the tile cache was last fully valid.
  int _cachedStrokeCount = 0;

  /// Scene graph version for the overall cache.
  int _cachedVersion = -1;

  /// Public access to cached scene version for external invalidation checks.
  int get cachedVersion => _cachedVersion;

  /// Number of cached tiles.
  int get tileCount => _tiles.length;

  /// Total stroke count in the cache.
  int get cachedStrokeCount => _cachedStrokeCount;

  /// Whether the cache has any tiles.
  bool get hasCachedTiles => _tiles.isNotEmpty;

  // =========================================================================
  // CACHE STATS (for debug overlay)
  // =========================================================================

  int _cacheHits = 0;
  int _cacheMisses = 0;

  /// Cache hit count since last reset.
  int get cacheHits => _cacheHits;

  /// Cache miss count since last reset.
  int get cacheMisses => _cacheMisses;

  /// Hit rate as a percentage (0-100). Returns 100 if no requests.
  double get hitRate {
    final total = _cacheHits + _cacheMisses;
    return total > 0 ? (_cacheHits / total * 100) : 100;
  }

  /// Reset hit/miss counters (call periodically from monitor).
  void resetStats() {
    _cacheHits = 0;
    _cacheMisses = 0;
  }

  // =========================================================================
  // TILE KEY COMPUTATION
  // =========================================================================

  /// Compute the tile key for a canvas point.
  static TileKey tileKeyForPoint(double x, double y) {
    return TileKey(x ~/ tileSize, y ~/ tileSize);
  }

  /// Compute all tile keys that overlap a given rect.
  static List<TileKey> tileKeysForRect(Rect rect) {
    if (rect.isEmpty) return const [];

    final minTx = rect.left ~/ tileSize - (rect.left < 0 ? 1 : 0);
    final minTy = rect.top ~/ tileSize - (rect.top < 0 ? 1 : 0);
    final maxTx = rect.right ~/ tileSize;
    final maxTy = rect.bottom ~/ tileSize;

    final keys = <TileKey>[];
    for (int tx = minTx; tx <= maxTx; tx++) {
      for (int ty = minTy; ty <= maxTy; ty++) {
        keys.add(TileKey(tx, ty));
      }
    }
    return keys;
  }

  /// Get the canvas-space bounds of a tile.
  static Rect tileBounds(TileKey key) {
    return Rect.fromLTWH(
      key.tx * tileSize,
      key.ty * tileSize,
      tileSize,
      tileSize,
    );
  }

  /// 🚀 Sort tile keys by distance to viewport center (center-first priority).
  /// Tiles closest to where the user is looking are rebuilt first.
  static void sortByDistanceToCenter(List<TileKey> tiles, Rect viewport) {
    final cx = viewport.center.dx / tileSize;
    final cy = viewport.center.dy / tileSize;
    tiles.sort((a, b) {
      final da = (a.tx - cx) * (a.tx - cx) + (a.ty - cy) * (a.ty - cy);
      final db = (b.tx - cx) * (b.tx - cx) + (b.ty - cy) * (b.ty - cy);
      return da.compareTo(db);
    });
  }

  /// 🚀 Sort tiles biased toward pan direction (viewport prediction).
  /// Tiles in the pan direction get negative distance bias → built first.
  /// `panDir` should be a normalized direction vector (dx, dy).
  static void sortByPanPrediction(
    List<TileKey> tiles,
    Rect viewport,
    Offset panDir,
  ) {
    if (panDir == Offset.zero) {
      sortByDistanceToCenter(tiles, viewport);
      return;
    }
    final cx = viewport.center.dx / tileSize;
    final cy = viewport.center.dy / tileSize;
    final pdx = panDir.dx;
    final pdy = panDir.dy;
    tiles.sort((a, b) {
      // Dot product with pan direction: higher = more aligned
      final dotA = (a.tx - cx) * pdx + (a.ty - cy) * pdy;
      final dotB = (b.tx - cx) * pdx + (b.ty - cy) * pdy;
      // Prefer tiles aligned with pan direction (negative = behind)
      // Strongly bias: subtract 2× dot product from distance
      final da =
          (a.tx - cx) * (a.tx - cx) + (a.ty - cy) * (a.ty - cy) - dotA * 3.0;
      final db =
          (b.tx - cx) * (b.tx - cx) + (b.ty - cy) * (b.ty - cy) - dotB * 3.0;
      return da.compareTo(db);
    });
  }

  /// 🚀 Collect missing tiles in a 2-ring surrounding the viewport (pre-warm).
  /// Returns tiles OUTSIDE the viewport that aren't cached yet.
  List<TileKey> collectMissingPreWarm(Rect viewport) {
    // Inflate viewport by 2 tiles in each direction for aggressive pre-warm
    final inflated = viewport.inflate(tileSize * 2);
    final allKeys = tileKeysForRect(inflated);
    final visibleKeys = tileKeysForRect(viewport).toSet();
    final missing = <TileKey>[];
    for (final key in allKeys) {
      if (!visibleKeys.contains(key) && !_tiles.containsKey(key)) {
        missing.add(key);
      }
    }
    return missing;
  }

  // =========================================================================
  // CACHE OPERATIONS
  // =========================================================================

  /// Check if the tile cache is valid for the given stroke count and version.
  bool isValid(int strokeCount, int sceneVersion) {
    return _cachedStrokeCount == strokeCount &&
        _cachedVersion == sceneVersion &&
        _tiles.isNotEmpty;
  }

  /// Invalidate tiles that overlap the given bounds (e.g. a new stroke).
  void invalidateForBounds(Rect bounds) {
    final keys = tileKeysForRect(bounds);
    for (final key in keys) {
      _tiles.remove(key)?.dispose();
      _tileVersions.remove(key);
    }
  }

  /// Invalidate ALL tiles (e.g. on undo or full scene change).
  void invalidateAll() {
    for (final picture in _tiles.values) {
      picture.dispose();
    }
    _tiles.clear();
    _tileVersions.clear();
    _cachedStrokeCount = 0;
    _cachedVersion = -1;
    // Also dispose stale tiles
    for (final p in _staleTiles.values) {
      p.dispose();
    }
    _staleTiles.clear();
  }

  /// 🚀 Mark all current tiles as STALE (wrong LOD) instead of disposing.
  /// Stale tiles are drawn as fallback during progressive rebuild,
  /// then disposed lazily as new tiles replace them.
  void markAllStale() {
    // Move current tiles → stale, dispose any existing stale
    for (final entry in _staleTiles.entries) {
      entry.value.dispose();
    }
    _staleTiles.clear();
    _staleTiles.addAll(_tiles);
    _tiles.clear();
    _tileVersions.clear();
    _cachedStrokeCount = 0;
    _cachedVersion = -1;
  }

  /// Draw all cached tiles that overlap the viewport.
  ///
  /// Returns the list of tile keys that are MISSING (need rebuilding).
  /// The caller should rebuild those tiles and call [cacheTile] for each.
  List<TileKey> drawAndCollectMissing(Canvas canvas, Rect viewport) {
    final visibleKeys = tileKeysForRect(viewport);
    final missing = <TileKey>[];

    for (final key in visibleKeys) {
      final picture = _tiles[key];
      if (picture != null) {
        canvas.drawPicture(picture);
        _cacheHits++;
      } else {
        // 🚀 STALE FALLBACK: draw old-LOD tile if available (GPU-scaled)
        final stale = _staleTiles[key];
        if (stale != null) {
          canvas.drawPicture(stale);
        }
        _cacheMisses++;
        missing.add(key);
      }
    }

    return missing;
  }

  /// 🚀 Collect missing tile keys WITHOUT drawing cached tiles.
  /// Used during progressive LOD transition: we draw the old snapshot
  /// and only need to know which tiles still need rebuilding.
  List<TileKey> collectMissing(Rect viewport) {
    final visibleKeys = tileKeysForRect(viewport);
    final missing = <TileKey>[];
    for (final key in visibleKeys) {
      if (!_tiles.containsKey(key)) {
        missing.add(key);
      }
    }
    return missing;
  }

  /// 🚀 Draw ONLY cached tiles (skip missing). Used for global cache adoption
  /// where we just need to replay already-rendered tiles into a PictureRecorder.
  /// No tile rebuilding — O(1) per tile via drawPicture.
  void drawCachedOnly(Canvas canvas, Rect viewport) {
    final visibleKeys = tileKeysForRect(viewport);
    for (final key in visibleKeys) {
      final picture = _tiles[key];
      if (picture != null) {
        canvas.drawPicture(picture);
      }
    }
  }

  /// Cache a rebuilt tile picture.
  /// Evicts oldest tiles if the cache exceeds [maxTiles].
  void cacheTile(TileKey key, ui.Picture picture, int sceneVersion) {
    _tiles.remove(key)?.dispose();
    _tiles[key] = picture; // Insert at end (newest)
    _tileVersions[key] = sceneVersion;

    // 🚀 Dispose stale tile for this key (no longer needed)
    _staleTiles.remove(key)?.dispose();

    // 🛡️ LRU EVICTION: remove oldest tiles if over cap
    while (_tiles.length > maxTiles) {
      final oldest = _tiles.keys.first;
      _tiles.remove(oldest)?.dispose();
      _tileVersions.remove(oldest);
    }
  }

  /// Mark the cache as fully valid for the given counts.
  void markValid(int strokeCount, int sceneVersion) {
    _cachedStrokeCount = strokeCount;
    _cachedVersion = sceneVersion;
  }

  /// Dispose all cached tiles.
  void dispose() {
    for (final picture in _tiles.values) {
      picture.dispose();
    }
    _tiles.clear();
    _tileVersions.clear();
    for (final p in _staleTiles.values) {
      p.dispose();
    }
    _staleTiles.clear();
  }
}

// ===========================================================================
// TILE KEY
// ===========================================================================

/// Immutable tile coordinate key for cache lookups.
@immutable
class TileKey {
  final int tx;
  final int ty;

  const TileKey(this.tx, this.ty);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileKey && other.tx == tx && other.ty == ty;

  @override
  int get hashCode => tx.hashCode ^ (ty.hashCode * 31);

  @override
  String toString() => 'TileKey($tx, $ty)';
}
