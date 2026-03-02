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

  /// Cached pictures keyed by tile coordinates.
  final Map<TileKey, ui.Picture> _tiles = {};

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
      } else {
        missing.add(key);
      }
    }

    return missing;
  }

  /// Cache a rebuilt tile picture.
  void cacheTile(TileKey key, ui.Picture picture, int sceneVersion) {
    _tiles[key]?.dispose();
    _tiles[key] = picture;
    _tileVersions[key] = sceneVersion;
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
