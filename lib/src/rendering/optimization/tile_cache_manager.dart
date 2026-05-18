import 'dart:collection';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 🧩 TILE CACHE MANAGER — Pyramidal regional cache (Google Maps-style)
///
/// ARCHITECTURE
/// ────────────
/// The canvas is divided into a fixed grid of tiles ([tileSize]×[tileSize]
/// canvas units). For each tile, multiple `ui.Picture` representations may
/// coexist — one per LOD tier — forming a tile pyramid.
///
/// Three LOD tiers are supported:
///   tier 0 = full quality   (high zoom, scale ≥ 0.50)
///   tier 1 = simplified     (mid zoom, 0.25 ≤ scale < 0.50)
///   tier 2 = thumbnails     (low zoom, scale < 0.25)
///
/// Each tier owns an independent LRU map ([maxTilesPerTier]) so a transition
/// between tiers does NOT discard the previous tier's tiles.
///
/// PARENT FALLBACK (the trick behind Google Maps' smooth zoom)
/// ───────────────────────────────────────────────────────────
/// When the renderer asks for a tile at the active tier and that tile is
/// not yet cached, [drawWithParentFallback] looks across other tiers for
/// the closest available tile and draws THAT picture instead. The result
/// is identical in canvas coordinates (the canvas transform handles any
/// scale mismatch) — the only visible difference is the level of detail,
/// which the user accepts as "the new zoom is loading".
///
/// As soon as the active-tier tile is built and cached, subsequent frames
/// stop falling back. There is no global cross-fade: the swap happens per
/// tile, exactly when each new tile becomes available, just like Google
/// Maps swaps individual map tiles in a viewport.
///
/// IDLE TIER EVICTION
/// ──────────────────
/// Each tier remembers when it was last drawn ([_lastVisitFrame]). Call
/// [evictIdleTiers] periodically (the painter does this on every frame at
/// negligible cost) to drop tiers untouched for [evictAfterFrames] frames.
/// The currently active tier is never evicted.
///
/// MEMORY BUDGET
/// ─────────────
/// Worst case: [maxTilesPerTier] × [_numTiers] = 96 × 3 = 288 cached
/// pictures. Pictures are vector command lists (typically < 1 MB each),
/// not bitmaps, so the realistic ceiling is ~50–100 MB even on dense
/// scenes. Bitmap rasterization is left to Skia / Impeller on the raster
/// thread, where the GPU caches the resulting textures with its own LRU.
///
/// 🔧 2026-05-18: bumped from 48 → 96 to accommodate bucketed [TileKey]
/// variants. Each `(tx, ty)` can have up to 4 ink-bucket variants × 4
/// god-bucket variants during a pinch through the semantic-morph band.
/// In practice only 2-3 buckets are active per visible tile during a
/// single gesture; the ×2 bump leaves headroom without ballooning.
///
/// TILE COORDINATE SYSTEM
/// ──────────────────────
/// Canvas point (x, y) → tile (x ~/ tileSize, y ~/ tileSize). The same
/// (tx, ty) refers to the same canvas region across all tiers; only the
/// rendering inside the picture differs (full quality vs simplified vs
/// thumbnail).
class TileCacheManager {
  /// Edge length of each tile in canvas units.
  ///
  /// 🎚️ D: 2048 (was 4096). Halving the tile dimension means a single
  /// rebuild touches ~4× fewer strokes (R-tree query smaller, BrushEngine
  /// stamp count smaller), so the per-tile rebuild fits in ~1 ms instead
  /// of 3-5 ms. With the 4 ms per-frame budget we now bake ~4 tiles per
  /// frame instead of 1, so the cache populates 4× faster on first entry
  /// into a fresh region. Per-tier memory is unchanged: the 4× tile-count
  /// inflation is offset by 4× smaller Picture command lists.
  static const double tileSize = 2048.0;

  /// Maximum cached tiles per LOD tier (LRU-evicted).
  ///
  /// 🔧 2026-05-18: 48 → 96 to host bucketed [TileKey] variants without
  /// thrashing during a pinch through the semantic-morph band. Steady
  /// state (no morph active) still occupies < 30 entries because tiles
  /// outside the morph band share a single bucket key.
  static const int maxTilesPerTier = 96;

  /// Number of LOD tiers managed by this cache.
  static const int _numTiers = 3;

  /// Per-tier LRU maps. `_tilesByTier[t][key]` is the picture cached for
  /// tier `t`, or null if not built yet at that tier.
  final List<LinkedHashMap<TileKey, ui.Picture>> _tilesByTier = List.generate(
    _numTiers,
    (_) => LinkedHashMap<TileKey, ui.Picture>(),
  );

  /// Per-tier scene-graph version map. Used by future fine-grained version
  /// checks; today the cache is invalidated as a whole on scene change.
  final List<Map<TileKey, int>> _versionsByTier = List.generate(
    _numTiers,
    (_) => <TileKey, int>{},
  );

  // 🎚️ A: BITMAP CACHE FOR TIER 2 (thumbnails)
  // At tier 2 the picture is just colored RRect batches covering the
  // whole viewport; replaying that command list each frame burns GPU
  // fillrate redundantly. Bake to a 1024² bitmap (1.7× downscale max
  // versus the 614 px screen-coverage worst-case at scale=0.30 with
  // 2048-unit tiles → no perceptible blur) and replay via drawImageRect
  // (~0.2 ms/tile vs 2-4 ms picture replay). Worst-case heap: 4 MB ×
  // 48 = 192 MB GPU. The Picture is kept alongside the Image so cross-
  // tier parent fallback (returning Picture) keeps working unchanged.
  static const int _bakedThumbSizePx = 1024;
  final LinkedHashMap<TileKey, _BakedThumb> _bakedThumbsTier2 =
      LinkedHashMap<TileKey, _BakedThumb>();

  // 🎚️ F1: ASYNC BAKE QUEUE for tier 2.
  // Synchronous toImageSync(1024×1024) costs 1-3 ms per tile on Adreno
  // 660. With the 4 ms per-frame budget after D (tile size 2048), 3-4
  // tiles can be rebuilt per frame, multiplying the bake cost by 3-4×
  // and producing a 35 ms spike during fast multi-tier zoom. Deferring
  // the bake to a post-frame callback keeps the rebuild loop fast: the
  // tile is drawn as Picture for the current frame, then becomes a
  // baked image from the next frame onward — invisible to the user.
  final List<MapEntry<TileKey, ui.Picture>> _pendingBakeQueue = [];

  // 🌫️ B.1: per-tier fade-in spawn frame. When a tile is first cached
  // (key NEW to its tier map), record _frameCounter. drawWithParentFallback
  // uses this to overlay the new render with an alpha ramp 0→1 over
  // kTileFadeFrames frames so a cold-cache fill doesn't visibly "pop":
  // the previous parent-fallback render stays on screen and the new tile
  // fades in over the top. See plan: quando-si-muove-tra-structured-puzzle.md.
  static const int kTileFadeFrames = 5;
  final List<Map<TileKey, int>> _fadeSpawnByTier = List.generate(
    _numTiers,
    (_) => <TileKey, int>{},
  );
  // Separate fade tracker for tier-2 baked thumbnails, which land on a
  // different code path (flushPendingBakes, not cacheTile).
  final Map<TileKey, int> _bakedThumbFadeSpawn = <TileKey, int>{};
  // Reusable paint for fading composites; mutated alpha each draw.
  final Paint _fadePicturePaint = Paint();
  final Paint _fadeBakedPaint = Paint()
    ..filterQuality = FilterQuality.low
    ..isAntiAlias = false;

  /// Frame index at which each tier was last drawn from. Used by
  /// [evictIdleTiers] to drop pictures the user has not visited recently.
  final List<int> _lastVisitFrame = List.filled(_numTiers, 0);

  /// Monotonic frame counter, advanced once per [drawWithParentFallback] call.
  int _frameCounter = 0;

  /// Tier most recently drawn from. Never evicted by [evictIdleTiers].
  int _activeTier = 0;

  /// Total stroke count when the cache was last marked valid.
  int _cachedStrokeCount = 0;

  /// Scene-graph version when the cache was last marked valid.
  int _cachedVersion = -1;

  /// Public access to cached scene version for external invalidation checks.
  int get cachedVersion => _cachedVersion;

  /// Total stroke count in the cache.
  int get cachedStrokeCount => _cachedStrokeCount;

  /// Sum of cached pictures across every tier.
  int get tileCount {
    var total = 0;
    for (final tier in _tilesByTier) {
      total += tier.length;
    }
    return total;
  }

  /// Cached picture count for a specific tier.
  int tileCountForTier(int tier) => _tilesByTier[tier].length;

  /// Tier that received the most recent [drawWithParentFallback] call.
  int get activeTier => _activeTier;

  /// True when at least one tier holds at least one tile.
  bool get hasCachedTiles {
    for (final tier in _tilesByTier) {
      if (tier.isNotEmpty) return true;
    }
    return false;
  }

  // =========================================================================
  // CACHE STATS (for debug overlay)
  // =========================================================================

  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _parentFallbackHits = 0;

  /// Cache hit count since last reset. A "hit" means the tile was found at
  /// the requested tier (parent fallback does NOT count as a hit).
  int get cacheHits => _cacheHits;

  /// Cache miss count since last reset. Includes parent-fallback fills.
  int get cacheMisses => _cacheMisses;

  /// Misses where another tier's picture was drawn as fallback. Subset of
  /// [cacheMisses]. High counts during zoom-out indicate the painter is
  /// rasterizing wrong-tier pictures (often more expensive than the target).
  int get parentFallbackHits => _parentFallbackHits;

  /// Hit rate as a percentage (0–100). Returns 100 when no requests yet.
  double get hitRate {
    final total = _cacheHits + _cacheMisses;
    return total > 0 ? (_cacheHits / total * 100) : 100;
  }

  /// Reset hit/miss counters. Called periodically by the performance monitor.
  void resetStats() {
    _cacheHits = 0;
    _cacheMisses = 0;
    _parentFallbackHits = 0;
  }

  // =========================================================================
  // TILE KEY COMPUTATION
  // =========================================================================

  /// Compute the tile key containing canvas point (x, y).
  static TileKey tileKeyForPoint(double x, double y) {
    return TileKey(x ~/ tileSize, y ~/ tileSize);
  }

  /// Compute every tile key overlapping [rect] in canvas coordinates.
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

  /// Canvas-space bounds of the tile identified by [key].
  static Rect tileBounds(TileKey key) {
    return Rect.fromLTWH(
      key.tx * tileSize,
      key.ty * tileSize,
      tileSize,
      tileSize,
    );
  }

  /// Sort [tiles] in-place by squared distance to viewport center.
  /// Used to schedule center-first tile rebuilds during progressive load.
  static void sortByDistanceToCenter(List<TileKey> tiles, Rect viewport) {
    final cx = viewport.center.dx / tileSize;
    final cy = viewport.center.dy / tileSize;
    tiles.sort((a, b) {
      final da = (a.tx - cx) * (a.tx - cx) + (a.ty - cy) * (a.ty - cy);
      final db = (b.tx - cx) * (b.tx - cx) + (b.ty - cy) * (b.ty - cy);
      return da.compareTo(db);
    });
  }

  /// Sort [tiles] in-place biased toward [panDir] (normalized direction
  /// vector). Tiles in the predicted pan direction get rebuilt first so
  /// they land in cache by the time the user pans into them.
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
      final dotA = (a.tx - cx) * pdx + (a.ty - cy) * pdy;
      final dotB = (b.tx - cx) * pdx + (b.ty - cy) * pdy;
      final da =
          (a.tx - cx) * (a.tx - cx) + (a.ty - cy) * (a.ty - cy) - dotA * 3.0;
      final db =
          (b.tx - cx) * (b.tx - cx) + (b.ty - cy) * (b.ty - cy) - dotB * 3.0;
      return da.compareTo(db);
    });
  }

  // =========================================================================
  // CACHE OPERATIONS — TIER-AWARE
  // =========================================================================

  /// Whether the cache has every visible tile of [tier] for [strokeCount]
  /// strokes at scene [sceneVersion]. Cheap viewport-aware check used by
  /// the painter to short-circuit the rebuild loop.
  bool isValidForTier(int tier, int strokeCount, int sceneVersion) {
    return _cachedStrokeCount == strokeCount &&
        _cachedVersion == sceneVersion &&
        _tilesByTier[tier].isNotEmpty;
  }

  /// Look up the cached picture for ([tier], [key]). Returns null when no
  /// picture has been built yet at that tier. Does NOT count toward stats.
  ui.Picture? getTile(int tier, TileKey key) => _tilesByTier[tier][key];

  /// Find the closest available tile for [key] across tiers OTHER than
  /// [currentTier]. Prefers the tier nearest to [currentTier] (smallest
  /// |delta|) so the visual mismatch is minimized. Returns null when no
  /// tier holds a picture for [key].
  ///
  /// This is the Google Maps "parent fallback": a tile from another zoom
  /// level renders in the same canvas region, only at a different level
  /// of detail.
  ui.Picture? getParentFallback(int currentTier, TileKey key) {
    for (int delta = 1; delta < _numTiers; delta++) {
      // Prefer the tier just BELOW (more detailed) before going coarser.
      // For currentTier=2 the order is: tier 1, then tier 0.
      // For currentTier=0 the order is: tier 1, then tier 2.
      for (final candidate in [currentTier - delta, currentTier + delta]) {
        if (candidate < 0 || candidate >= _numTiers) continue;
        // 🔧 2026-05-18: bucket-agnostic lookup. During a pinch the
        // requested `key.inkBucket` / `key.godBucket` may not yet be
        // baked at the parent tier — accept any sibling bucket at the
        // same `(tx, ty)` as a 1-2 frame stand-in. The proper-bucket
        // bake lands within `kTileFadeFrames` and the fade-in math in
        // `drawWithParentFallback` blends it on top.
        final tier = _tilesByTier[candidate];
        final exact = tier[key];
        if (exact != null) return exact;
        for (final entry in tier.entries) {
          if (entry.key.tx == key.tx && entry.key.ty == key.ty) {
            return entry.value;
          }
        }
      }
    }
    return null;
  }

  /// Draw every tile visible in [viewport] at [currentTier]; for each
  /// missing tile, fall back to a picture from another tier (see
  /// [getParentFallback]). Returns the keys still missing AT [currentTier]
  /// — the caller is expected to rebuild and [cacheTile] them, ideally
  /// progressively across frames.
  ///
  /// Side effects:
  ///   • marks [currentTier] as the active tier;
  ///   • advances the internal frame counter (drives [evictIdleTiers]);
  ///   • updates hit / miss counters.
  List<TileKey> drawWithParentFallback(
    Canvas canvas,
    Rect viewport,
    int currentTier, {
    int inkBucket = 3,
    int godBucket = 0,
  }) {
    _activeTier = currentTier;
    _frameCounter++;
    _lastVisitFrame[currentTier] = _frameCounter;

    // 🔧 2026-05-18: re-key visible tiles with the caller's current morph
    // buckets so we look up the variant that matches the live alpha state,
    // not whatever was previously baked at the same `(tx, ty)`. Without
    // this rebuild a stroke baked at `inkCrossfade = 1.0` would still
    // appear at scale 0.14 where `inkCrossfade = 0` → ghost ink inside
    // the semantic node.
    final coordKeys = tileKeysForRect(viewport);
    final visibleKeys = (inkBucket == 3 && godBucket == 0)
        ? coordKeys
        : [
            for (final k in coordKeys)
              TileKey(k.tx, k.ty,
                  inkBucket: inkBucket, godBucket: godBucket),
          ];
    final missing = <TileKey>[];
    final tier = _tilesByTier[currentTier];
    final fadeSpawnMap = _fadeSpawnByTier[currentTier];

    final bool isTier2 = currentTier == 2;
    for (final key in visibleKeys) {
      // 🎚️ A: at tier 2, prefer the baked bitmap if present.
      if (isTier2) {
        final baked = _bakedThumbsTier2[key];
        if (baked != null) {
          final fadeSpawn = _bakedThumbFadeSpawn[key];
          if (fadeSpawn != null) {
            final age = _frameCounter - fadeSpawn;
            if (age >= kTileFadeFrames) {
              _bakedThumbFadeSpawn.remove(key);
              _drawBakedThumb(canvas, key, baked);
            } else {
              // 🌫️ B.1: keep parent fallback visible while the new baked
              // thumb fades in. Alpha climbs 0 → 1 over kTileFadeFrames.
              final alpha = (age + 1) / (kTileFadeFrames + 1);
              final fb = getParentFallback(currentTier, key);
              if (fb != null) canvas.drawPicture(fb);
              _drawBakedThumbWithAlpha(canvas, key, baked, alpha);
            }
          } else {
            _drawBakedThumb(canvas, key, baked);
          }
          _cacheHits++;
          continue;
        }
      }
      final picture = tier[key];
      if (picture != null) {
        final fadeSpawn = fadeSpawnMap[key];
        if (fadeSpawn != null) {
          final age = _frameCounter - fadeSpawn;
          if (age >= kTileFadeFrames) {
            fadeSpawnMap.remove(key);
            canvas.drawPicture(picture);
          } else {
            final alpha = (age + 1) / (kTileFadeFrames + 1);
            final fb = getParentFallback(currentTier, key);
            if (fb != null) canvas.drawPicture(fb);
            _drawPictureWithAlpha(canvas, picture, key, alpha);
          }
        } else {
          canvas.drawPicture(picture);
        }
        _cacheHits++;
      } else {
        final fallback = getParentFallback(currentTier, key);
        if (fallback != null) {
          canvas.drawPicture(fallback);
          _parentFallbackHits++;
        }
        _cacheMisses++;
        missing.add(key);
      }
    }
    return missing;
  }

  /// 🌫️ B.1: replay a Picture into [canvas] inside a saveLayer that
  /// applies `alpha`. saveLayer cost is ~0.2-0.4ms per call but bounded
  /// to the few tiles in fade band (~5 frames × ~12 visible tiles max).
  void _drawPictureWithAlpha(
    Canvas canvas,
    ui.Picture picture,
    TileKey key,
    double alpha,
  ) {
    if (alpha >= 1.0) {
      canvas.drawPicture(picture);
      return;
    }
    _fadePicturePaint.color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0));
    canvas.saveLayer(tileBounds(key), _fadePicturePaint);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  /// 🌫️ B.1: alpha-blended variant of [_drawBakedThumb] for fade-in.
  void _drawBakedThumbWithAlpha(
    Canvas canvas,
    TileKey key,
    _BakedThumb baked,
    double alpha,
  ) {
    final size = baked.image.width.toDouble();
    _fadeBakedPaint.color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0));
    canvas.drawImageRect(
      baked.image,
      Rect.fromLTWH(0, 0, size, size),
      tileBounds(key),
      _fadeBakedPaint,
    );
  }

  /// Replay a tier-2 baked thumbnail at [key] onto [canvas] in canvas
  /// coordinates. Texture sample is O(pixel coverage) without the AA
  /// edge work of replaying the original RRect batches.
  static final Paint _bakedThumbPaint = Paint()
    ..filterQuality = FilterQuality.low
    ..isAntiAlias = false;
  void _drawBakedThumb(Canvas canvas, TileKey key, _BakedThumb baked) {
    final size = baked.image.width.toDouble();
    canvas.drawImageRect(
      baked.image,
      Rect.fromLTWH(0, 0, size, size),
      tileBounds(key),
      _bakedThumbPaint,
    );
  }

  /// Collect missing tile keys at [tier] without drawing anything.
  List<TileKey> collectMissing(int tier, Rect viewport) {
    final visibleKeys = tileKeysForRect(viewport);
    final missing = <TileKey>[];
    final map = _tilesByTier[tier];
    for (final key in visibleKeys) {
      if (!map.containsKey(key)) missing.add(key);
    }
    return missing;
  }

  /// Collect missing tiles in a 2-ring around [viewport] at [tier],
  /// EXCLUDING the visible viewport itself. Used for predictive pre-warm
  /// during idle frames.
  ///
  /// 🔧 2026-05-18: bucket-aware. Pre-warm targets the SAME bucket the
  /// painter will look up next frame; otherwise idle pre-bakes would
  /// be wasted against the live morph state.
  List<TileKey> collectMissingPreWarm(
    int tier,
    Rect viewport, {
    int inkBucket = 3,
    int godBucket = 0,
  }) {
    final inflated = viewport.inflate(tileSize * 2);
    final coordAll = tileKeysForRect(inflated);
    final coordVisible = tileKeysForRect(viewport).toSet();
    final missing = <TileKey>[];
    final map = _tilesByTier[tier];
    for (final coord in coordAll) {
      if (coordVisible.contains(coord)) continue;
      final key = (inkBucket == 3 && godBucket == 0)
          ? coord
          : TileKey(coord.tx, coord.ty,
              inkBucket: inkBucket, godBucket: godBucket);
      if (!map.containsKey(key)) missing.add(key);
    }
    return missing;
  }

  /// Replay only tiles cached at [tier] that are visible in [viewport],
  /// without falling back to other tiers. Used when adopting tiles into a
  /// global stroke-cache picture (we want a clean, single-tier render).
  ///
  /// 🔧 2026-05-18: bucket-aware to match `drawWithParentFallback`.
  void drawCachedOnlyForTier(
    int tier,
    Canvas canvas,
    Rect viewport, {
    int inkBucket = 3,
    int godBucket = 0,
  }) {
    final coordKeys = tileKeysForRect(viewport);
    final map = _tilesByTier[tier];
    for (final coord in coordKeys) {
      final key = (inkBucket == 3 && godBucket == 0)
          ? coord
          : TileKey(coord.tx, coord.ty,
              inkBucket: inkBucket, godBucket: godBucket);
      final picture = map[key];
      if (picture != null) canvas.drawPicture(picture);
    }
  }

  /// Cache a freshly-rebuilt tile picture for ([tier], [key]). LRU-evicts
  /// the oldest tile of [tier] when the per-tier cap is exceeded.
  ///
  /// 🎚️ A: at tier 2 the picture is also baked to a 1024² bitmap and
  /// stored separately. Subsequent replays use the bitmap (cheap GPU
  /// texture sample) while the picture stays around for cross-tier
  /// parent fallback queries.
  void cacheTile(int tier, TileKey key, ui.Picture picture, int sceneVersion) {
    final map = _tilesByTier[tier];
    final versions = _versionsByTier[tier];
    // 🌫️ B.1: register fade spawn when this key is genuinely new (not a
    // re-cache of an already-visible tile — the user has already seen it).
    final wasPresent = map.containsKey(key);
    map.remove(key)?.dispose();
    map[key] = picture; // Insert at end (newest)
    versions[key] = sceneVersion;
    if (!wasPresent) _fadeSpawnByTier[tier][key] = _frameCounter;

    while (map.length > maxTilesPerTier) {
      final oldest = map.keys.first;
      map.remove(oldest)?.dispose();
      versions.remove(oldest);
      _fadeSpawnByTier[tier].remove(oldest);
      // Also evict the baked thumb if this tile was at tier 2.
      _bakedThumbsTier2.remove(oldest)?.dispose();
      _bakedThumbFadeSpawn.remove(oldest);
    }

    // 🎚️ A+F1: enqueue bake for tier 2; the actual toImageSync is
    // performed by [flushPendingBakes] in a post-frame callback so the
    // 1-3 ms-per-tile bake cost doesn't pile up inside the rebuild
    // loop's 4 ms budget. Until the bake lands, drawWithParentFallback
    // falls back to the Picture command list (already in `_tilesByTier`)
    // for this key — slightly more expensive than the bitmap, but only
    // for one or two frames.
    if (tier == 2) {
      _pendingBakeQueue.add(MapEntry(key, picture));
    }
  }

  /// 🎚️ F1: drain up to [maxBakes] entries from the pending bake queue
  /// and convert their pictures to baked thumbnails. Call from a post-
  /// frame callback so the synchronous toImageSync cost is paid AFTER
  /// the rebuild loop's deadline, never inside it. Returns true if more
  /// entries remain queued (caller may schedule another flush).
  bool flushPendingBakes({int maxBakes = 2}) {
    if (_pendingBakeQueue.isEmpty) return false;
    final scale = _bakedThumbSizePx / tileSize;
    int processed = 0;
    while (_pendingBakeQueue.isNotEmpty && processed < maxBakes) {
      final entry = _pendingBakeQueue.removeAt(0);
      final key = entry.key;
      final picture = entry.value;
      // Skip stale entries: if the picture was evicted from the tier-2
      // cache between enqueue and now, don't bake it.
      if (_tilesByTier[2][key] != picture) {
        processed++;
        continue;
      }
      final bounds = tileBounds(key);
      final wrapRec = ui.PictureRecorder();
      final wrapCanvas = Canvas(wrapRec);
      wrapCanvas.scale(scale);
      wrapCanvas.translate(-bounds.left, -bounds.top);
      wrapCanvas.drawPicture(picture);
      final bakedPic = wrapRec.endRecording();
      final image = bakedPic.toImageSync(_bakedThumbSizePx, _bakedThumbSizePx);
      bakedPic.dispose();
      final hadBaked = _bakedThumbsTier2.containsKey(key);
      _bakedThumbsTier2.remove(key)?.dispose();
      _bakedThumbsTier2[key] =
          _BakedThumb(image, _versionsByTier[2][key] ?? -1);
      // 🌫️ B.1: fade-in the new baked thumb only if it's the first one
      // for this key. A re-bake of an already-visible thumb shouldn't
      // re-fade — the user has already seen it.
      if (!hadBaked) _bakedThumbFadeSpawn[key] = _frameCounter;
      processed++;
    }
    return _pendingBakeQueue.isNotEmpty;
  }

  /// Mark the cache as fully valid for the given counts. Called once per
  /// frame after a successful tile rebuild pass.
  void markValid(int strokeCount, int sceneVersion) {
    _cachedStrokeCount = strokeCount;
    _cachedVersion = sceneVersion;
  }

  // =========================================================================
  // INVALIDATION
  // =========================================================================

  /// Invalidate every tile across every tier whose canvas footprint
  /// overlaps [bounds]. Stroke mutations affect all LODs, so all tiers
  /// must be invalidated together.
  void invalidateForBounds(Rect bounds) {
    final keys = tileKeysForRect(bounds);
    for (int t = 0; t < _numTiers; t++) {
      final map = _tilesByTier[t];
      final versions = _versionsByTier[t];
      final fadeMap = _fadeSpawnByTier[t];
      for (final key in keys) {
        map.remove(key)?.dispose();
        versions.remove(key);
        fadeMap.remove(key);
      }
    }
    // 🎚️ A: also drop tier-2 baked thumbs for these keys.
    for (final key in keys) {
      _bakedThumbsTier2.remove(key)?.dispose();
      _bakedThumbFadeSpawn.remove(key);
    }
  }

  /// Invalidate every tile across every tier (e.g. on undo or full
  /// scene change).
  void invalidateAll() {
    for (final map in _tilesByTier) {
      for (final p in map.values) {
        p.dispose();
      }
      map.clear();
    }
    for (final v in _versionsByTier) {
      v.clear();
    }
    for (final fade in _fadeSpawnByTier) {
      fade.clear();
    }
    // 🎚️ A: drop all tier-2 baked thumbs.
    for (final t in _bakedThumbsTier2.values) {
      t.dispose();
    }
    _bakedThumbsTier2.clear();
    _bakedThumbFadeSpawn.clear();
    _cachedStrokeCount = 0;
    _cachedVersion = -1;
  }

  /// Drop every tile of a specific [tier]. Use sparingly — the value of
  /// the pyramid is in keeping other-tier tiles around as parent fallback.
  void evictTier(int tier) {
    final map = _tilesByTier[tier];
    for (final p in map.values) {
      p.dispose();
    }
    map.clear();
    _versionsByTier[tier].clear();
    _fadeSpawnByTier[tier].clear();
    // 🎚️ A: if evicting tier 2, also drop the baked thumbs.
    if (tier == 2) {
      for (final t in _bakedThumbsTier2.values) {
        t.dispose();
      }
      _bakedThumbsTier2.clear();
      _bakedThumbFadeSpawn.clear();
    }
  }

  /// Drop tiles of any tier untouched for more than [evictAfterFrames]
  /// frames. The currently active tier is always preserved.
  ///
  /// Cheap to call every frame: walks 3 integers and only allocates work
  /// when a tier actually exceeds the threshold.
  void evictIdleTiers({int evictAfterFrames = 600}) {
    for (int t = 0; t < _numTiers; t++) {
      if (t == _activeTier) continue;
      if (_tilesByTier[t].isEmpty) continue;
      if (_frameCounter - _lastVisitFrame[t] > evictAfterFrames) {
        evictTier(t);
      }
    }
  }

  /// Dispose every cached tile across every tier. Call when the canvas
  /// is destroyed or the engine is torn down.
  void dispose() {
    for (final map in _tilesByTier) {
      for (final p in map.values) {
        p.dispose();
      }
      map.clear();
    }
    for (final v in _versionsByTier) {
      v.clear();
    }
    for (final fade in _fadeSpawnByTier) {
      fade.clear();
    }
    // 🎚️ A: dispose tier-2 baked thumbs.
    for (final t in _bakedThumbsTier2.values) {
      t.dispose();
    }
    _bakedThumbsTier2.clear();
    _bakedThumbFadeSpawn.clear();
  }
}

// ===========================================================================
// TILE KEY
// ===========================================================================

/// Immutable tile coordinate key. The same `(tx, ty)` refers to the same
/// canvas region across every LOD tier.
///
/// 🔧 2026-05-18: extended with [inkBucket] / [godBucket] so the cache
/// stores one variant per `(crossfade, godViewProgress)` band. A tile
/// baked while `inkCrossfade ≈ 1.0` keeps stroke alpha at its baked
/// value forever — even after the user dezooms into the morph band
/// where `inkCrossfade = 0` and strokes should disappear. Without
/// bucketing the painter would replay the stale tile and show "ghost
/// ink" (e.g. visible stroke fragments inside the semantic node at
/// scale 0.14). Encoding the morph state into the key produces a
/// fresh bake per band and lets the LRU keep both variants for the
/// duration of a pinch gesture.
///
/// 4 discrete steps per axis (`round(value * 3)`) — `Δalpha < 25%`
/// per bucket is under the perceptual threshold during a normal pinch.
@immutable
class TileKey {
  final int tx;
  final int ty;

  /// `round(inkCrossfade * 3)`. Range 0..3. Default 3 == strokes
  /// opaque (no semantic morph active) so any pre-2026-05-18 call site
  /// constructing `TileKey(tx, ty)` lands in the same bucket as before.
  final int inkBucket;

  /// `round(godViewProgress * 3)`. Range 0..3. Default 0 == not in
  /// god view. Same backward-compat reasoning as [inkBucket].
  final int godBucket;

  const TileKey(this.tx, this.ty, {this.inkBucket = 3, this.godBucket = 0});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileKey &&
          other.tx == tx &&
          other.ty == ty &&
          other.inkBucket == inkBucket &&
          other.godBucket == godBucket;

  @override
  int get hashCode => Object.hash(tx, ty, inkBucket, godBucket);

  @override
  String toString() =>
      'TileKey($tx, $ty, ink=$inkBucket, god=$godBucket)';
}

// ===========================================================================
// BAKED THUMB (tier 2 only)
// ===========================================================================

/// Rasterized 1024×1024 bitmap of a tier-2 tile, plus the scene version
/// it was baked at. Used by the bake-tier-2 fast path: the Picture is
/// still kept by the cache for cross-tier parent-fallback, but normal
/// drawing replays this image instead of the picture command list.
class _BakedThumb {
  final ui.Image image;
  final int sceneVersion;
  const _BakedThumb(this.image, this.sceneVersion);
  void dispose() => image.dispose();
}
