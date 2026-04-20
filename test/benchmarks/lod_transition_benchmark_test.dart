// ignore_for_file: avoid_print
/// LOD TRANSITION BENCHMARK + TILE PYRAMID UNIT TESTS
///
/// The renderer treats LOD transitions Google Maps-style: each LOD tier
/// has its own per-tile LRU map inside [TileCacheManager], and a missing
/// tile at the active tier falls back to the closest available tile from
/// any other tier (parent fallback). There is no snapshot, no cross-fade
/// and no progressive rebuild loop — the visible swap happens per tile,
/// at the moment each new tile becomes available.
///
/// This file covers two orthogonal concerns:
///
/// 1) BENCHMARK — how cheap a steady-state cross-tier replay actually is
///    on the CPU thread (drawWithParentFallback over a viewport-sized set
///    of tiles). The raster-thread cost is GPU-bound and must be measured
///    separately via CanvasPerformanceMonitor.rasterP99Ms.
///
/// 2) UNIT TESTS — the lifecycle invariants the painter relies on:
///    parent fallback resolution order, tier isolation, idle eviction,
///    cross-tier invalidation by bounds.
///
/// Run:
///   flutter test test/benchmarks/lod_transition_benchmark_test.dart \
///                --reporter expanded

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/rendering/optimization/tile_cache_manager.dart';

const int _frames = 30;
const double _viewportWidth = 1920;
const double _viewportHeight = 1080;

/// Build a representative tile picture: [strokeCount] short colored
/// polylines distributed inside a single tile bounds. Roughly mirrors the
/// CPU shape of a tier-1 (simplified) tile.
ui.Picture _buildTilePicture(int strokeCount, Rect bounds) {
  final rng = math.Random(42);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..isAntiAlias = true;
  for (int i = 0; i < strokeCount; i++) {
    paint.color = Color.fromARGB(
      255,
      rng.nextInt(256),
      rng.nextInt(256),
      rng.nextInt(256),
    );
    final path = ui.Path();
    final startX = bounds.left + rng.nextDouble() * bounds.width;
    final startY = bounds.top + rng.nextDouble() * bounds.height;
    path.moveTo(startX, startY);
    for (int j = 0; j < 6; j++) {
      path.lineTo(
        startX + rng.nextDouble() * 80 - 40,
        startY + rng.nextDouble() * 80 - 40,
      );
    }
    canvas.drawPath(path, paint);
  }
  return recorder.endRecording();
}

/// Populate [cache] at [tier] with one picture for every tile overlapping
/// [viewport].
void _seedTierForViewport(
  TileCacheManager cache,
  int tier,
  Rect viewport,
  int strokesPerTile,
) {
  for (final key in TileCacheManager.tileKeysForRect(viewport)) {
    cache.cacheTile(
      tier,
      key,
      _buildTilePicture(strokesPerTile, TileCacheManager.tileBounds(key)),
      1,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tile pyramid: drawWithParentFallback CPU cost', () {
    for (final strokesPerTile in [10, 100, 1000]) {
      test('$strokesPerTile strokes/tile — full-tier replay', () {
        final viewport = Rect.fromLTWH(0, 0, _viewportWidth, _viewportHeight);
        final cache = TileCacheManager();
        _seedTierForViewport(cache, 2, viewport, strokesPerTile);

        // Steady-state replay: the active tier (2) holds every visible tile,
        // so drawWithParentFallback never touches the parent slot.
        final times = <int>[];
        for (int i = 0; i < _frames; i++) {
          final recorder = ui.PictureRecorder();
          final c = Canvas(recorder);
          final sw = Stopwatch()..start();
          final missing = cache.drawWithParentFallback(c, viewport, 2);
          sw.stop();
          recorder.endRecording().dispose();
          expect(missing, isEmpty);
          times.add(sw.elapsedMicroseconds);
        }

        times.sort();
        final p50Us = times[times.length ~/ 2];
        final p99Us = times[(times.length * 0.99).floor().clamp(0, times.length - 1)];
        print('  $strokesPerTile strokes/tile: '
            'p50=${(p50Us / 1000).toStringAsFixed(3)}ms '
            'p99=${(p99Us / 1000).toStringAsFixed(3)}ms '
            '(${cache.tileCountForTier(2)} tiles)');

        cache.dispose();
      });
    }

    test('cross-tier transition — parent fallback fills until tier built', () {
      final viewport = Rect.fromLTWH(0, 0, _viewportWidth, _viewportHeight);
      final cache = TileCacheManager();
      _seedTierForViewport(cache, 1, viewport, 100);

      // Frame 0: active tier flips to 2 with NO tier-2 tiles built yet.
      // Every visible key should fall back to tier 1 transparently and
      // come back as "missing at tier 2".
      final r0 = ui.PictureRecorder();
      final missingAtFrame0 = cache.drawWithParentFallback(
        Canvas(r0),
        viewport,
        2,
      );
      r0.endRecording().dispose();
      expect(missingAtFrame0, isNotEmpty);
      expect(cache.cacheMisses, missingAtFrame0.length);

      // Build the missing tier-2 tiles incrementally over a few frames and
      // verify that the missing list shrinks monotonically.
      final order = List<TileKey>.from(missingAtFrame0);
      var prevMissing = missingAtFrame0.length;
      for (int i = 0; i < order.length; i++) {
        cache.cacheTile(
          2,
          order[i],
          _buildTilePicture(100, TileCacheManager.tileBounds(order[i])),
          1,
        );
        final r = ui.PictureRecorder();
        final missing = cache.drawWithParentFallback(
          Canvas(r),
          viewport,
          2,
        );
        r.endRecording().dispose();
        expect(missing.length, lessThan(prevMissing));
        prevMissing = missing.length;
      }
      expect(prevMissing, 0);
      cache.dispose();
    });
  });

  group('Tile pyramid: invariants', () {
    test('tier isolation — caching at one tier does not affect others', () {
      final cache = TileCacheManager();
      final pic = _buildTilePicture(10, TileCacheManager.tileBounds(const TileKey(0, 0)));
      cache.cacheTile(0, const TileKey(0, 0), pic, 1);

      expect(cache.tileCountForTier(0), 1);
      expect(cache.tileCountForTier(1), 0);
      expect(cache.tileCountForTier(2), 0);
      expect(cache.getTile(0, const TileKey(0, 0)), isNotNull);
      expect(cache.getTile(1, const TileKey(0, 0)), isNull);
      expect(cache.getTile(2, const TileKey(0, 0)), isNull);

      cache.dispose();
    });

    test('parent fallback prefers nearest tier (|delta| ascending)', () {
      final cache = TileCacheManager();
      const key = TileKey(0, 0);
      final pic0 = _buildTilePicture(1, TileCacheManager.tileBounds(key));
      final pic2 = _buildTilePicture(2, TileCacheManager.tileBounds(key));
      cache.cacheTile(0, key, pic0, 1);
      cache.cacheTile(2, key, pic2, 1);

      // Active tier 1: tier 0 and tier 2 are both at |delta|=1; the
      // implementation tries currentTier - delta FIRST, so tier 0 wins.
      expect(identical(cache.getParentFallback(1, key), pic0), isTrue);

      // Active tier 0: only tier 2 is available → |delta|=2.
      cache.evictTier(0);
      cache.cacheTile(1, key, _buildTilePicture(1, TileCacheManager.tileBounds(key)), 1);
      expect(identical(cache.getParentFallback(0, key), cache.getTile(1, key)), isTrue);

      cache.dispose();
    });

    test('parent fallback returns null when no tier holds the key', () {
      final cache = TileCacheManager();
      expect(cache.getParentFallback(0, const TileKey(99, 99)), isNull);
      expect(cache.getParentFallback(2, const TileKey(99, 99)), isNull);
      cache.dispose();
    });

    test('invalidateForBounds invalidates ACROSS every tier', () {
      final cache = TileCacheManager();
      const key = TileKey(0, 0);
      final bounds = TileCacheManager.tileBounds(key);
      cache.cacheTile(0, key, _buildTilePicture(1, bounds), 1);
      cache.cacheTile(1, key, _buildTilePicture(1, bounds), 1);
      cache.cacheTile(2, key, _buildTilePicture(1, bounds), 1);
      expect(cache.tileCount, 3);

      cache.invalidateForBounds(bounds);
      expect(cache.tileCountForTier(0), 0);
      expect(cache.tileCountForTier(1), 0);
      expect(cache.tileCountForTier(2), 0);

      cache.dispose();
    });

    test('evictIdleTiers preserves the active tier and drops the rest', () {
      final cache = TileCacheManager();
      final viewport = Rect.fromLTWH(0, 0, _viewportWidth, _viewportHeight);
      _seedTierForViewport(cache, 0, viewport, 5);
      _seedTierForViewport(cache, 1, viewport, 5);
      _seedTierForViewport(cache, 2, viewport, 5);

      // Drive the frame counter: a single drawWithParentFallback at tier 1
      // marks tier 1 active.
      final r = ui.PictureRecorder();
      cache.drawWithParentFallback(Canvas(r), viewport, 1);
      r.endRecording().dispose();

      // With a 0-frame threshold every non-active tier is idle by definition.
      cache.evictIdleTiers(evictAfterFrames: 0);
      expect(cache.tileCountForTier(0), 0);
      expect(cache.tileCountForTier(2), 0);
      expect(cache.tileCountForTier(1), greaterThan(0));

      cache.dispose();
    });

    test('per-tier LRU caps at maxTilesPerTier', () {
      final cache = TileCacheManager();
      // Insert maxTilesPerTier + 5 tiles into tier 0; expect LRU eviction
      // to keep the size at exactly the cap.
      for (int i = 0; i < TileCacheManager.maxTilesPerTier + 5; i++) {
        cache.cacheTile(
          0,
          TileKey(i, 0),
          _buildTilePicture(1, TileCacheManager.tileBounds(TileKey(i, 0))),
          1,
        );
      }
      expect(cache.tileCountForTier(0), TileCacheManager.maxTilesPerTier);
      cache.dispose();
    });
  });
}
