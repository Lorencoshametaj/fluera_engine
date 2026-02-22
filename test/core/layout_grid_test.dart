import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/layout/layout_grid.dart';

void main() {
  group('LayoutGrid', () {
    test('computes 12-column grid cells', () {
      final grid = LayoutGrid(
        id: 'g1',
        type: LayoutGridType.columns,
        count: 12,
        gutterSize: 20,
        margin: 40,
      );
      final cells = grid.computeCells(1440);
      expect(cells.length, 12);
      // First cell starts at margin.
      expect(cells.first.offset, closeTo(40, 0.01));
      // All cells have same width.
      final widths = cells.map((c) => c.size).toSet();
      expect(widths.length, 1);
    });

    test('computes uniform grid', () {
      final grid = LayoutGrid(id: 'g2', type: LayoutGridType.grid, cellSize: 8);
      final cells = grid.computeCells(100);
      expect(cells.length, 13); // 0,8,16,...,96
      expect(cells.first.offset, 0);
      expect(cells.first.size, 8);
    });

    test('handles zero count gracefully', () {
      final grid = LayoutGrid(id: 'g3', count: 0);
      expect(grid.computeCells(500), isEmpty);
    });

    test('JSON roundtrip', () {
      final grid = LayoutGrid(
        id: 'g4',
        type: LayoutGridType.rows,
        count: 4,
        gutterSize: 10,
        margin: 20,
        alignment: LayoutGridAlignment.center,
        color: const Color(0x3300FF00),
        isVisible: false,
      );
      final restored = LayoutGrid.fromJson(grid.toJson());
      expect(restored.id, 'g4');
      expect(restored.type, LayoutGridType.rows);
      expect(restored.count, 4);
      expect(restored.alignment, LayoutGridAlignment.center);
      expect(restored.isVisible, false);
    });

    test('copyWith preserves unchanged values', () {
      final grid = LayoutGrid(id: 'g5', count: 6, gutterSize: 10);
      final copy = grid.copyWith(count: 8);
      expect(copy.count, 8);
      expect(copy.gutterSize, 10);
      expect(copy.id, 'g5');
    });
  });

  group('LayoutGridSet', () {
    test('add, find, remove', () {
      final set = LayoutGridSet();
      set.add(LayoutGrid(id: 'a'));
      set.add(LayoutGrid(id: 'b'));
      expect(set.length, 2);
      expect(set.find('a'), isNotNull);
      expect(set.remove('a'), isTrue);
      expect(set.length, 1);
    });

    test('toggleAll visibility', () {
      final set = LayoutGridSet();
      set.add(LayoutGrid(id: 'a', isVisible: true));
      set.add(LayoutGrid(id: 'b', isVisible: true));
      set.toggleAll(false);
      expect(set.grids.every((g) => !g.isVisible), isTrue);
    });

    test('JSON roundtrip', () {
      final set = LayoutGridSet();
      set.add(LayoutGrid(id: 'x', count: 4));
      final restored = LayoutGridSet.fromJson(set.toJson());
      expect(restored.length, 1);
      expect(restored.grids.first.count, 4);
    });
  });
}
