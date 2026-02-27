import 'package:flutter_test/flutter_test.dart';
import 'dart:ui';
import 'package:fluera_engine/src/rendering/optimization/advanced_tile_optimizer.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';

ProStroke _makeStroke(String id) {
  return ProStroke(
    id: id,
    points: [
      ProDrawingPoint(
        position: const Offset(0, 0),
        pressure: 0.5,
        timestamp: 0,
      ),
    ],
    color: const Color(0xFF000000),
    baseWidth: 2.0,
    penType: ProPenType.ballpoint,
    createdAt: DateTime(2024),
  );
}

void main() {
  late AdvancedTileOptimizer optimizer;

  setUp(() {
    optimizer = AdvancedTileOptimizer.create();
  });

  tearDown(() {
    optimizer.clearAll();
  });

  group('AdvancedTileOptimizer', () {
    group('incremental tile updates', () {
      test('getNewStrokesForTile returns all for fresh tile', () {
        final strokes = [_makeStroke('s1'), _makeStroke('s2')];
        final newStrokes = optimizer.getNewStrokesForTile('tile_0_0', strokes);
        expect(newStrokes.length, 2);
      });

      test('getNewStrokesForTile excludes already rasterized', () {
        final strokes = [
          _makeStroke('s1'),
          _makeStroke('s2'),
          _makeStroke('s3'),
        ];
        optimizer.markStrokesAsRasterized('tile_0_0', ['s1', 's2']);
        final newStrokes = optimizer.getNewStrokesForTile('tile_0_0', strokes);
        expect(newStrokes.length, 1);
        expect(newStrokes[0].id, 's3');
      });

      test('markStrokesAsRasterized accumulates', () {
        optimizer.markStrokesAsRasterized('tile_0_0', ['s1']);
        optimizer.markStrokesAsRasterized('tile_0_0', ['s2']);
        final strokes = [
          _makeStroke('s1'),
          _makeStroke('s2'),
          _makeStroke('s3'),
        ];
        final newStrokes = optimizer.getNewStrokesForTile('tile_0_0', strokes);
        expect(newStrokes.length, 1);
      });

      test('canDoIncrementalUpdate returns false for fresh tile', () {
        final strokes = [_makeStroke('s1')];
        expect(optimizer.canDoIncrementalUpdate('tile_0_0', strokes), isFalse);
      });

      test('canDoIncrementalUpdate returns true when few new strokes', () {
        optimizer.markStrokesAsRasterized('tile_0_0', ['s1', 's2', 's3']);
        final strokes = [
          _makeStroke('s1'),
          _makeStroke('s2'),
          _makeStroke('s3'),
          _makeStroke('s4'), // 1 new stroke
        ];
        expect(optimizer.canDoIncrementalUpdate('tile_0_0', strokes), isTrue);
      });

      test(
        'canDoIncrementalUpdate returns false when too many new strokes',
        () {
          optimizer.markStrokesAsRasterized('tile_0_0', ['s1']);
          // Create 15 new strokes (> threshold of 10)
          final strokes = [_makeStroke('s1')];
          for (int i = 2; i <= 16; i++) {
            strokes.add(_makeStroke('s$i'));
          }
          expect(
            optimizer.canDoIncrementalUpdate('tile_0_0', strokes),
            isFalse,
          );
        },
      );
    });

    group('invalidation', () {
      test('invalidateTile clears rasterized strokes for tile', () {
        optimizer.markStrokesAsRasterized('tile_0_0', ['s1', 's2']);
        optimizer.invalidateTile('tile_0_0');
        final strokes = [_makeStroke('s1')];
        final newStrokes = optimizer.getNewStrokesForTile('tile_0_0', strokes);
        expect(newStrokes.length, 1); // All are "new" again
      });

      test('invalidateStrokes removes specific strokes from all tiles', () {
        optimizer.markStrokesAsRasterized('tile_0_0', ['s1', 's2', 's3']);
        optimizer.markStrokesAsRasterized('tile_1_0', ['s2', 's3', 's4']);

        optimizer.invalidateStrokes(['s2', 's3']);

        final strokes1 = [
          _makeStroke('s1'),
          _makeStroke('s2'),
          _makeStroke('s3'),
        ];
        final new1 = optimizer.getNewStrokesForTile('tile_0_0', strokes1);
        expect(new1.length, 2); // s2, s3 are "new" again

        final strokes2 = [
          _makeStroke('s2'),
          _makeStroke('s3'),
          _makeStroke('s4'),
        ];
        final new2 = optimizer.getNewStrokesForTile('tile_1_0', strokes2);
        expect(new2.length, 2); // s2, s3 are "new" again
      });
    });

    group('stroke batching', () {
      test('groups strokes by pen type, color, and width', () {
        final strokes = [
          ProStroke(
            id: 's1',
            points: [
              ProDrawingPoint(
                position: Offset.zero,
                pressure: 0.5,
                timestamp: 0,
              ),
            ],
            color: const Color(0xFF000000),
            baseWidth: 2.0,
            penType: ProPenType.ballpoint,
            createdAt: DateTime(2024),
          ),
          ProStroke(
            id: 's2',
            points: [
              ProDrawingPoint(
                position: Offset.zero,
                pressure: 0.5,
                timestamp: 0,
              ),
            ],
            color: const Color(0xFF000000),
            baseWidth: 2.0,
            penType: ProPenType.ballpoint,
            createdAt: DateTime(2024),
          ),
          ProStroke(
            id: 's3',
            points: [
              ProDrawingPoint(
                position: Offset.zero,
                pressure: 0.5,
                timestamp: 0,
              ),
            ],
            color: const Color(0xFFFF0000), // Different color
            baseWidth: 2.0,
            penType: ProPenType.ballpoint,
            createdAt: DateTime(2024),
          ),
        ];
        final batches = optimizer.batchStrokes(strokes);
        expect(batches.length, 2); // Two different colors
        // One batch has 2 strokes, the other has 1
        final counts = batches.values.map((l) => l.length).toList()..sort();
        expect(counts, [1, 2]);
      });

      test('empty strokes produces empty batches', () {
        final batches = optimizer.batchStrokes([]);
        expect(batches, isEmpty);
      });
    });

    group('tile priority queue', () {
      test('queueTileForRasterization adds tasks', () {
        optimizer.queueTileForRasterization(
          TileRasterTask(
            tileKey: 'tile_0_0',
            tileX: 0,
            tileY: 0,
            priority: 50,
            isIncremental: false,
            strokes: [],
          ),
        );
        expect(optimizer.stats['queuedTiles'], 1);
      });

      test('getNextTileToRasterize returns highest priority first', () {
        optimizer.queueTileForRasterization(
          TileRasterTask(
            tileKey: 'tile_low',
            tileX: 0,
            tileY: 0,
            priority: 10,
            isIncremental: false,
            strokes: [],
          ),
        );
        optimizer.queueTileForRasterization(
          TileRasterTask(
            tileKey: 'tile_high',
            tileX: 1,
            tileY: 1,
            priority: 90,
            isIncremental: false,
            strokes: [],
          ),
        );
        optimizer.queueTileForRasterization(
          TileRasterTask(
            tileKey: 'tile_mid',
            tileX: 0,
            tileY: 1,
            priority: 50,
            isIncremental: false,
            strokes: [],
          ),
        );

        final first = optimizer.getNextTileToRasterize();
        expect(first!.tileKey, 'tile_high');
        final second = optimizer.getNextTileToRasterize();
        expect(second!.tileKey, 'tile_mid');
        final third = optimizer.getNextTileToRasterize();
        expect(third!.tileKey, 'tile_low');
      });

      test('getNextTileToRasterize returns null when empty', () {
        expect(optimizer.getNextTileToRasterize(), isNull);
      });

      test(
        'queueTileForRasterization replaces existing task for same tile',
        () {
          optimizer.queueTileForRasterization(
            TileRasterTask(
              tileKey: 'tile_0_0',
              tileX: 0,
              tileY: 0,
              priority: 10,
              isIncremental: false,
              strokes: [],
            ),
          );
          optimizer.queueTileForRasterization(
            TileRasterTask(
              tileKey: 'tile_0_0',
              tileX: 0,
              tileY: 0,
              priority: 90, // Updated priority
              isIncremental: true, // Updated
              strokes: [],
            ),
          );
          expect(optimizer.stats['queuedTiles'], 1);
          final task = optimizer.getNextTileToRasterize();
          expect(task!.priority, 90);
          expect(task.isIncremental, isTrue);
        },
      );
    });

    group('calculateTilePriority', () {
      test('center tile has highest priority', () {
        final viewport = const Rect.fromLTWH(0, 0, 500, 500);
        final centerPriority = optimizer.calculateTilePriority(
          2,
          2,
          viewport,
          100,
        );
        final edgePriority = optimizer.calculateTilePriority(
          0,
          0,
          viewport,
          100,
        );
        expect(centerPriority, greaterThan(edgePriority));
      });

      test('farther tiles have lower priority', () {
        final viewport = const Rect.fromLTWH(0, 0, 400, 400);
        final p1 = optimizer.calculateTilePriority(1, 1, viewport, 100);
        final p2 = optimizer.calculateTilePriority(5, 5, viewport, 100);
        expect(p1, greaterThan(p2));
      });

      test('priority is always positive', () {
        final viewport = const Rect.fromLTWH(0, 0, 100, 100);
        final p = optimizer.calculateTilePriority(100, 100, viewport, 100);
        expect(p, greaterThan(0));
      });
    });

    group('stats', () {
      test('reports initial state', () {
        final s = optimizer.stats;
        expect(s['tilesWithRasterizedStrokes'], 0);
        expect(s['totalRasterizedStrokes'], 0);
        expect(s['queuedTiles'], 0);
      });

      test('reports correct after operations', () {
        optimizer.markStrokesAsRasterized('t1', ['s1', 's2']);
        optimizer.markStrokesAsRasterized('t2', ['s3']);
        final s = optimizer.stats;
        expect(s['tilesWithRasterizedStrokes'], 2);
        expect(s['totalRasterizedStrokes'], 3);
      });
    });

    group('clearAll', () {
      test('resets everything', () {
        optimizer.markStrokesAsRasterized('tile_0_0', ['s1']);
        optimizer.queueTileForRasterization(
          TileRasterTask(
            tileKey: 'tile_0_0',
            tileX: 0,
            tileY: 0,
            priority: 50,
            isIncremental: false,
            strokes: [],
          ),
        );
        optimizer.clearAll();
        expect(optimizer.stats['tilesWithRasterizedStrokes'], 0);
        expect(optimizer.stats['queuedTiles'], 0);
      });
    });
  });

  group('StrokeBatchKey', () {
    test('equality works', () {
      const k1 = StrokeBatchKey(
        penType: ProPenType.ballpoint,
        color: Color(0xFF000000),
        baseWidth: 2.0,
      );
      const k2 = StrokeBatchKey(
        penType: ProPenType.ballpoint,
        color: Color(0xFF000000),
        baseWidth: 2.0,
      );
      expect(k1, equals(k2));
      expect(k1.hashCode, equals(k2.hashCode));
    });

    test('differs by pen type', () {
      const k1 = StrokeBatchKey(
        penType: ProPenType.ballpoint,
        color: Color(0xFF000000),
        baseWidth: 2.0,
      );
      const k2 = StrokeBatchKey(
        penType: ProPenType.fountain,
        color: Color(0xFF000000),
        baseWidth: 2.0,
      );
      expect(k1, isNot(equals(k2)));
    });

    test('differs by color', () {
      const k1 = StrokeBatchKey(
        penType: ProPenType.ballpoint,
        color: Color(0xFF000000),
        baseWidth: 2.0,
      );
      const k2 = StrokeBatchKey(
        penType: ProPenType.ballpoint,
        color: Color(0xFFFF0000),
        baseWidth: 2.0,
      );
      expect(k1, isNot(equals(k2)));
    });
  });

  group('TileRasterTask', () {
    test('stores fields correctly', () {
      const task = TileRasterTask(
        tileKey: 'tile_3_4',
        tileX: 3,
        tileY: 4,
        priority: 85.5,
        isIncremental: true,
        strokes: [],
      );
      expect(task.tileKey, 'tile_3_4');
      expect(task.tileX, 3);
      expect(task.tileY, 4);
      expect(task.priority, 85.5);
      expect(task.isIncremental, isTrue);
    });
  });
}
