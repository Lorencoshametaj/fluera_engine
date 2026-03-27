import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/layout/grid_layout_solver.dart';

void main() {
  // ===========================================================================
  // TrackDefinition
  // ===========================================================================

  group('TrackDefinition', () {
    test('fixed track has correct properties', () {
      const track = TrackDefinition.fixed(120);
      expect(track.isFixed, isTrue);
      expect(track.isFr, isFalse);
      expect(track.fixedSize, 120);
      expect(track.minSize, 120);
      expect(track.maxSize, 120);
    });

    test('fr track has correct properties', () {
      const track = TrackDefinition.fr(2);
      expect(track.isFr, isTrue);
      expect(track.isFixed, isFalse);
      expect(track.frFraction, 2);
      expect(track.minSize, 0);
    });

    test('minmax track has correct properties', () {
      const track = TrackDefinition.minmax(50, 200);
      expect(track.isFixed, isFalse);
      expect(track.isFr, isFalse);
      expect(track.minSize, 50);
      expect(track.maxSize, 200);
    });

    test('toJson serializes correctly', () {
      const track = TrackDefinition.fixed(100);
      final json = track.toJson();
      expect(json['fixedSize'], 100);
      expect(json['minSize'], 100);
    });

    test('toString for fixed', () {
      const track = TrackDefinition.fixed(60);
      expect(track.toString(), contains('60'));
    });

    test('toString for fr', () {
      const track = TrackDefinition.fr(1);
      expect(track.toString(), contains('fr'));
    });
  });

  // ===========================================================================
  // GridLayoutConfig
  // ===========================================================================

  group('GridLayoutConfig', () {
    test('cellCount is cols x rows', () {
      const config = GridLayoutConfig(
        columns: [TrackDefinition.fr(1), TrackDefinition.fr(1)],
        rows: [
          TrackDefinition.fixed(50),
          TrackDefinition.fixed(50),
          TrackDefinition.fixed(50),
        ],
      );
      expect(config.cellCount, 6);
    });

    test('defaults', () {
      const config = GridLayoutConfig(
        columns: [TrackDefinition.fr(1)],
        rows: [TrackDefinition.fr(1)],
      );
      expect(config.columnGap, 0);
      expect(config.rowGap, 0);
      expect(config.autoFlow, GridAutoFlow.rowFirst);
    });

    test('toJson serializes correctly', () {
      const config = GridLayoutConfig(
        columns: [TrackDefinition.fixed(100)],
        rows: [TrackDefinition.fr(1)],
        columnGap: 8,
        rowGap: 12,
        autoFlow: GridAutoFlow.columnFirst,
      );
      final json = config.toJson();
      expect(json['columnGap'], 8);
      expect(json['rowGap'], 12);
      expect(json['autoFlow'], 'columnFirst');
      expect((json['columns'] as List).length, 1);
    });
  });

  // ===========================================================================
  // GridLayoutSolver — empty / edge cases
  // ===========================================================================

  group('GridLayoutSolver - edge cases', () {
    test('empty grid returns zero rects', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(columns: [], rows: []),
        containerSize: const Size(400, 300),
        children: [const GridChild()],
      );
      expect(result.childRects.length, 1);
      expect(result.childRects.first, Rect.zero);
      expect(result.contentSize, Size.zero);
    });

    test('no children returns empty rects list', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fr(1)],
          rows: [TrackDefinition.fr(1)],
        ),
        containerSize: const Size(400, 300),
        children: [],
      );
      expect(result.childRects, isEmpty);
      expect(result.columnWidths.length, 1);
      expect(result.rowHeights.length, 1);
    });
  });

  // ===========================================================================
  // GridLayoutSolver — fixed tracks
  // ===========================================================================

  group('GridLayoutSolver - fixed tracks', () {
    test('2x2 fixed grid positions children correctly', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fixed(100), TrackDefinition.fixed(150)],
          rows: [TrackDefinition.fixed(50), TrackDefinition.fixed(75)],
          columnGap: 0,
          rowGap: 0,
        ),
        containerSize: const Size(400, 300),
        children: [
          const GridChild(column: 0, row: 0),
          const GridChild(column: 1, row: 0),
          const GridChild(column: 0, row: 1),
          const GridChild(column: 1, row: 1),
        ],
      );

      expect(result.childRects[0], const Rect.fromLTWH(0, 0, 100, 50));
      expect(result.childRects[1], const Rect.fromLTWH(100, 0, 150, 50));
      expect(result.childRects[2], const Rect.fromLTWH(0, 50, 100, 75));
      expect(result.childRects[3], const Rect.fromLTWH(100, 50, 150, 75));
    });

    test('column widths and row heights are correct', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fixed(80), TrackDefinition.fixed(120)],
          rows: [TrackDefinition.fixed(40)],
        ),
        containerSize: const Size(400, 300),
        children: [],
      );

      expect(result.columnWidths, [80, 120]);
      expect(result.rowHeights, [40]);
      expect(result.contentSize, const Size(200, 40));
    });
  });

  // ===========================================================================
  // GridLayoutSolver — fractional tracks
  // ===========================================================================

  group('GridLayoutSolver - fractional tracks', () {
    test('equal fr distribute space equally', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fr(1), TrackDefinition.fr(1)],
          rows: [TrackDefinition.fr(1)],
          columnGap: 0,
        ),
        containerSize: const Size(400, 200),
        children: [
          const GridChild(column: 0, row: 0),
          const GridChild(column: 1, row: 0),
        ],
      );

      expect(result.columnWidths[0], closeTo(200, 0.1));
      expect(result.columnWidths[1], closeTo(200, 0.1));
      expect(result.childRects[0].left, closeTo(0, 0.1));
      expect(result.childRects[1].left, closeTo(200, 0.1));
    });

    test('unequal fr distribute proportionally', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fr(1), TrackDefinition.fr(2)],
          rows: [TrackDefinition.fr(1)],
          columnGap: 0,
        ),
        containerSize: const Size(300, 100),
        children: [const GridChild(column: 0, row: 0)],
      );

      // 1/3 * 300 = 100, 2/3 * 300 = 200
      expect(result.columnWidths[0], closeTo(100, 0.1));
      expect(result.columnWidths[1], closeTo(200, 0.1));
    });

    test('mixed fixed and fr tracks', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [
            TrackDefinition.fixed(100),
            TrackDefinition.fr(1),
            TrackDefinition.fr(1),
          ],
          rows: [TrackDefinition.fr(1)],
          columnGap: 0,
        ),
        containerSize: const Size(500, 100),
        children: [],
      );

      // Fixed: 100, remaining: 400, each fr: 200
      expect(result.columnWidths[0], 100);
      expect(result.columnWidths[1], closeTo(200, 0.1));
      expect(result.columnWidths[2], closeTo(200, 0.1));
    });
  });

  // ===========================================================================
  // GridLayoutSolver — gaps
  // ===========================================================================

  group('GridLayoutSolver - gaps', () {
    test('column gaps offset children correctly', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fixed(100), TrackDefinition.fixed(100)],
          rows: [TrackDefinition.fixed(50)],
          columnGap: 20,
        ),
        containerSize: const Size(400, 200),
        children: [
          const GridChild(column: 0, row: 0),
          const GridChild(column: 1, row: 0),
        ],
      );

      expect(result.childRects[0].left, 0);
      expect(result.childRects[0].width, 100);
      expect(result.childRects[1].left, 120); // 100 + 20 gap
      expect(result.childRects[1].width, 100);
    });

    test('row gaps offset children correctly', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fixed(100)],
          rows: [TrackDefinition.fixed(50), TrackDefinition.fixed(50)],
          rowGap: 10,
        ),
        containerSize: const Size(200, 200),
        children: [
          const GridChild(column: 0, row: 0),
          const GridChild(column: 0, row: 1),
        ],
      );

      expect(result.childRects[0].top, 0);
      expect(result.childRects[1].top, 60); // 50 + 10 gap
    });

    test('gaps reduce fr available space', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fr(1), TrackDefinition.fr(1)],
          rows: [TrackDefinition.fr(1)],
          columnGap: 100,
        ),
        containerSize: const Size(500, 100),
        children: [],
      );

      // Available = 500 - 100 gap = 400, each fr = 200
      expect(result.columnWidths[0], closeTo(200, 0.1));
      expect(result.columnWidths[1], closeTo(200, 0.1));
    });
  });

  // ===========================================================================
  // GridLayoutSolver — auto-placement
  // ===========================================================================

  group('GridLayoutSolver - auto-placement', () {
    test('row-first auto-placement fills left to right', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fixed(100), TrackDefinition.fixed(100)],
          rows: [TrackDefinition.fixed(50), TrackDefinition.fixed(50)],
          autoFlow: GridAutoFlow.rowFirst,
        ),
        containerSize: const Size(400, 200),
        children: [
          const GridChild(), // auto → (0,0)
          const GridChild(), // auto → (1,0)
          const GridChild(), // auto → (0,1)
          const GridChild(), // auto → (1,1)
        ],
      );

      // Row 0
      expect(result.childRects[0].left, 0);
      expect(result.childRects[0].top, 0);
      expect(result.childRects[1].left, 100);
      expect(result.childRects[1].top, 0);
      // Row 1
      expect(result.childRects[2].left, 0);
      expect(result.childRects[2].top, 50);
      expect(result.childRects[3].left, 100);
      expect(result.childRects[3].top, 50);
    });

    test('column-first auto-placement fills top to bottom', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fixed(100), TrackDefinition.fixed(100)],
          rows: [TrackDefinition.fixed(50), TrackDefinition.fixed(50)],
          autoFlow: GridAutoFlow.columnFirst,
        ),
        containerSize: const Size(400, 200),
        children: [
          const GridChild(), // auto → (0,0)
          const GridChild(), // auto → (0,1)
          const GridChild(), // auto → (1,0)
          const GridChild(), // auto → (1,1)
        ],
      );

      // Column 0
      expect(result.childRects[0].left, 0);
      expect(result.childRects[0].top, 0);
      expect(result.childRects[1].left, 0);
      expect(result.childRects[1].top, 50);
      // Column 1
      expect(result.childRects[2].left, 100);
      expect(result.childRects[2].top, 0);
      expect(result.childRects[3].left, 100);
      expect(result.childRects[3].top, 50);
    });
  });

  // ===========================================================================
  // GridLayoutSolver — spanning
  // ===========================================================================

  group('GridLayoutSolver - spanning', () {
    test('column span merges cells horizontally', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [
            TrackDefinition.fixed(100),
            TrackDefinition.fixed(100),
            TrackDefinition.fixed(100),
          ],
          rows: [TrackDefinition.fixed(50)],
          columnGap: 0,
        ),
        containerSize: const Size(400, 100),
        children: [
          const GridChild(column: 0, row: 0, columnSpan: 2), // spans 2 cols
        ],
      );

      // Width should be col0 + col1 = 200
      expect(result.childRects[0].width, 200);
      expect(result.childRects[0].left, 0);
    });

    test('row span merges cells vertically', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fixed(100)],
          rows: [
            TrackDefinition.fixed(50),
            TrackDefinition.fixed(50),
            TrackDefinition.fixed(50),
          ],
          rowGap: 0,
        ),
        containerSize: const Size(200, 200),
        children: [
          const GridChild(column: 0, row: 0, rowSpan: 2), // spans 2 rows
        ],
      );

      expect(result.childRects[0].height, 100);
      expect(result.childRects[0].top, 0);
    });

    test('spanning with gaps includes intermediate gaps', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fixed(100), TrackDefinition.fixed(100)],
          rows: [TrackDefinition.fixed(50)],
          columnGap: 10,
        ),
        containerSize: const Size(400, 100),
        children: [const GridChild(column: 0, row: 0, columnSpan: 2)],
      );

      // Width = col0 + gap + col1 = 100 + 10 + 100 = 210
      expect(result.childRects[0].width, closeTo(210, 0.1));
    });
  });

  // ===========================================================================
  // GridLayoutSolver — content size
  // ===========================================================================

  group('GridLayoutSolver - content size', () {
    test('contentSize is sum of tracks plus gaps', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fixed(100), TrackDefinition.fixed(100)],
          rows: [TrackDefinition.fixed(50), TrackDefinition.fixed(50)],
          columnGap: 10,
          rowGap: 5,
        ),
        containerSize: const Size(400, 200),
        children: [],
      );

      // Width = 100 + 10 + 100 = 210
      // Height = 50 + 5 + 50 = 105
      expect(result.contentSize.width, closeTo(210, 0.1));
      expect(result.contentSize.height, closeTo(105, 0.1));
    });
  });
}
