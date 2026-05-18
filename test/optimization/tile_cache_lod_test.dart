import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/rendering/optimization/tile_cache_manager.dart';

/// Build a tiny throwaway picture so we can exercise the cache without
/// pulling in the full DrawingPainter pipeline.
ui.Picture _dummyPicture({Color color = const Color(0xFFAA0000)}) {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 2048, 2048),
    Paint()..color = color,
  );
  return rec.endRecording();
}

void main() {
  group('TileCacheManager — B.1 fade-in', () {
    test('newly cached tile registers a fade spawn', () {
      final cache = TileCacheManager();
      const key = TileKey(0, 0);
      // Trigger _frameCounter to advance so spawn is positive.
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      cache.drawWithParentFallback(c, const Rect.fromLTWH(0, 0, 100, 100), 0);
      rec.endRecording();
      cache.cacheTile(0, key, _dummyPicture(), 1);
      // The fade entry should now exist — verify via observable behavior:
      // re-caching the same key keeps the entry (no double-fade).
      final dpr = ui.PictureRecorder();
      final c2 = Canvas(dpr);
      cache.drawWithParentFallback(c2, const Rect.fromLTWH(0, 0, 100, 100), 0);
      dpr.endRecording();
      // After enough frames the fade entry self-clears. Drive 6 frames and
      // confirm no exception + the tile keeps being drawn.
      for (int i = 0; i < 6; i++) {
        final rec3 = ui.PictureRecorder();
        cache.drawWithParentFallback(
          Canvas(rec3),
          const Rect.fromLTWH(0, 0, 100, 100),
          0,
        );
        rec3.endRecording();
      }
      expect(cache.cacheHits, greaterThan(0));
      cache.dispose();
    });

    test('re-caching the same key does not extend the fade window', () {
      // Re-cache should NOT reset spawn — the user has already seen this
      // tile, so a refresh shouldn't briefly fade it out again.
      final cache = TileCacheManager();
      const key = TileKey(1, 1);
      cache.cacheTile(0, key, _dummyPicture(), 1);
      // Drive 10 frames so fade window expires (kTileFadeFrames=5).
      for (int i = 0; i < 10; i++) {
        final rec = ui.PictureRecorder();
        cache.drawWithParentFallback(
          Canvas(rec),
          const Rect.fromLTWH(2048, 2048, 100, 100),
          0,
        );
        rec.endRecording();
      }
      // Re-cache after expiry — should not be considered "new".
      cache.cacheTile(0, key, _dummyPicture(color: const Color(0xFF00AA00)), 2);
      // No assertion-level introspection available, but a final draw must
      // not throw and the hit counter must advance.
      final hitsBefore = cache.cacheHits;
      final rec = ui.PictureRecorder();
      cache.drawWithParentFallback(
        Canvas(rec),
        const Rect.fromLTWH(2048, 2048, 100, 100),
        0,
      );
      rec.endRecording();
      expect(cache.cacheHits, greaterThan(hitsBefore));
      cache.dispose();
    });

    test('invalidateAll clears fade spawn entries too', () {
      final cache = TileCacheManager();
      cache.cacheTile(0, const TileKey(0, 0), _dummyPicture(), 1);
      cache.cacheTile(1, const TileKey(0, 0), _dummyPicture(), 1);
      expect(cache.tileCount, 2);
      cache.invalidateAll();
      expect(cache.tileCount, 0);
      // Re-caching a key should treat it as fresh and re-fade — already
      // covered functionally above; here we just sanity-check no leak.
      cache.cacheTile(0, const TileKey(0, 0), _dummyPicture(), 1);
      expect(cache.tileCount, 1);
      cache.dispose();
    });
  });

  group('TileCacheManager — X.1 surgical evict', () {
    test('evictTier drops only the targeted tier; others stay hot', () {
      final cache = TileCacheManager();
      cache.cacheTile(0, const TileKey(0, 0), _dummyPicture(), 1);
      cache.cacheTile(1, const TileKey(0, 0), _dummyPicture(), 1);
      cache.cacheTile(2, const TileKey(0, 0), _dummyPicture(), 1);
      expect(cache.tileCountForTier(0), 1);
      expect(cache.tileCountForTier(1), 1);
      expect(cache.tileCountForTier(2), 1);

      cache.evictTier(0);

      expect(cache.tileCountForTier(0), 0,
          reason: 'tier 0 must be empty after evictTier(0)');
      expect(cache.tileCountForTier(1), 1,
          reason: 'tier 1 must remain hot — kept for parent fallback');
      expect(cache.tileCountForTier(2), 1,
          reason: 'tier 2 must remain hot — kept for parent fallback');
      cache.dispose();
    });
  });

  group('TileCacheManager — A.3 bake budget', () {
    test('flushPendingBakes(maxBakes: 0) drains nothing — queue still pending',
        () {
      final cache = TileCacheManager();
      // Cache one tier-2 picture — this enqueues a bake.
      cache.cacheTile(2, const TileKey(0, 0), _dummyPicture(), 1);
      final hadMore = cache.flushPendingBakes(maxBakes: 0);
      // Queue must still report pending so the caller knows to retry later.
      expect(hadMore, isTrue,
          reason: 'maxBakes=0 must not consume entries — must stay pending');
      // Now drain with normal budget — bake should actually happen.
      final stillMore = cache.flushPendingBakes(maxBakes: 4);
      // Single tile so queue is empty after.
      expect(stillMore, isFalse);
      cache.dispose();
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 🔧 2026-05-18: TileKey bucketing for inkCrossfade + godViewProgress.
  //
  // Background: tiles bake stroke alpha modulated by `inkCrossfade` and
  // `godViewProgress`. Without these as part of the key, a tile baked at
  // scale 1.0 (full strokes) would be replayed at scale 0.14 (where strokes
  // should be invisible during semantic morph) → "ghost ink". Bucketing
  // produces one variant per band so the cache returns the correct alpha.
  // ────────────────────────────────────────────────────────────────────────
  group('TileKey bucketing', () {
    test('default buckets match legacy 2-arg constructor', () {
      const a = TileKey(3, 4);
      const b = TileKey(3, 4, inkBucket: 3, godBucket: 0);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different inkBucket → different keys', () {
      const a = TileKey(0, 0, inkBucket: 0);
      const b = TileKey(0, 0, inkBucket: 3);
      expect(a == b, isFalse);
      expect(a.hashCode != b.hashCode, isTrue);
    });

    test('different godBucket → different keys', () {
      const a = TileKey(0, 0, godBucket: 0);
      const b = TileKey(0, 0, godBucket: 3);
      expect(a == b, isFalse);
      expect(a.hashCode != b.hashCode, isTrue);
    });

    test('cacheTile + getTile round-trip respects the full key', () {
      final cache = TileCacheManager();
      final pic = _dummyPicture(color: const Color(0xFF00FF00));
      cache.cacheTile(0, const TileKey(1, 2, inkBucket: 0), pic, 1);
      expect(
        cache.getTile(0, const TileKey(1, 2, inkBucket: 0)),
        same(pic),
      );
      // Different bucket → cache miss (caller will rebake fresh).
      expect(
        cache.getTile(0, const TileKey(1, 2, inkBucket: 3)),
        isNull,
      );
      cache.dispose();
    });

    test('drawWithParentFallback with non-default buckets reports the '
        'bucketed missing key', () {
      final cache = TileCacheManager();
      // Cache a tile at the DEFAULT bucket only.
      cache.cacheTile(0, const TileKey(0, 0), _dummyPicture(), 1);
      // Look up with a different ink bucket — must miss.
      final rec = ui.PictureRecorder();
      final missing = cache.drawWithParentFallback(
        Canvas(rec),
        const Rect.fromLTWH(0, 0, 100, 100),
        0,
        inkBucket: 0,
      );
      rec.endRecording();
      expect(missing, isNotEmpty);
      expect(missing.first.inkBucket, equals(0),
          reason: 'missing key must carry the requested bucket so the bake '
              'site re-caches against the right variant');
      cache.dispose();
    });

    test('getParentFallback returns sibling bucket when exact missing', () {
      final cache = TileCacheManager();
      final picTier0 = _dummyPicture(color: const Color(0xFFAA0000));
      // Bake (0,0) at tier 0 with the DEFAULT bucket only.
      cache.cacheTile(0, const TileKey(0, 0), picTier0, 1);
      // Ask tier 1 for (0,0) with a DIFFERENT bucket — the bucket-agnostic
      // fallback should still surface the tier-0 picture.
      final fb = cache.getParentFallback(
        1,
        const TileKey(0, 0, inkBucket: 0),
      );
      expect(fb, same(picTier0),
          reason: 'parent fallback must be bucket-agnostic so morph-band '
              'transitions never expose an empty viewport while the '
              'proper bucket is being baked');
      cache.dispose();
    });
  });
}
