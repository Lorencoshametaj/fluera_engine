import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/rendering/optimization/spatial_index.dart';

// =============================================================================
// Helpers
// =============================================================================

/// Wrapper for test items with a known bounding box.
class _TestItem {
  final String id;
  final Rect bounds;
  _TestItem(this.id, this.bounds);

  @override
  String toString() => '_TestItem($id)';
}

RTree<_TestItem> _makeTree() => RTree<_TestItem>((item) => item.bounds);

_TestItem _item(String id, double x, double y, double w, double h) =>
    _TestItem(id, Rect.fromLTWH(x, y, w, h));

void main() {
  // ===========================================================================
  // RTree — basic insert/remove
  // ===========================================================================

  group('RTree - insert/remove', () {
    test('starts empty', () {
      final tree = _makeTree();
      expect(tree.count, 0);
    });

    test('insert increases count', () {
      final tree = _makeTree();
      tree.insert(_item('a', 0, 0, 10, 10));
      expect(tree.count, 1);
      tree.insert(_item('b', 20, 20, 10, 10));
      expect(tree.count, 2);
    });

    test('remove decreases count', () {
      final tree = _makeTree();
      final item = _item('a', 0, 0, 10, 10);
      tree.insert(item);
      tree.remove(item);
      expect(tree.count, 0);
    });

    test('remove non-existent item is safe', () {
      final tree = _makeTree();
      tree.insert(_item('a', 0, 0, 10, 10));
      tree.remove(_item('non_existent', 0, 0, 10, 10));
      expect(tree.count, 1);
    });
  });

  // ===========================================================================
  // RTree — queryVisible
  // ===========================================================================

  group('RTree - queryVisible', () {
    test('returns items in viewport', () {
      final tree = _makeTree();
      final inView = _item('in', 50, 50, 10, 10);
      final outOfView = _item('out', 5000, 5000, 10, 10);
      tree.insert(inView);
      tree.insert(outOfView);

      final results = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(results.length, 1);
      expect(results.first.id, 'in');
    });

    test('returns all items when viewport covers everything', () {
      final tree = _makeTree();
      for (int i = 0; i < 10; i++) {
        tree.insert(_item('item$i', i * 100.0, 0, 50, 50));
      }
      final results = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 10000, 10000),
        margin: 0,
      );
      expect(results.length, 10);
    });

    test('returns empty for viewport with no items', () {
      final tree = _makeTree();
      tree.insert(_item('a', 0, 0, 10, 10));
      final results = tree.queryVisible(
        const Rect.fromLTWH(1000, 1000, 100, 100),
        margin: 0,
      );
      expect(results, isEmpty);
    });

    test('margin expands the query area', () {
      final tree = _makeTree();
      final nearby = _item('near', 250, 250, 10, 10);
      tree.insert(nearby);

      // Without margin, 250,250 is outside [0..200]
      final noMargin = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(noMargin, isEmpty);

      // With margin, 250 is within 200+100=300
      final withMargin = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 100,
      );
      expect(withMargin.length, 1);
    });
  });

  // ===========================================================================
  // RTree — bulk load
  // ===========================================================================

  group('RTree - bulk load', () {
    test('handles many insertions', () {
      final tree = _makeTree();
      for (int i = 0; i < 500; i++) {
        tree.insert(_item('item$i', i * 10.0, (i % 50) * 10.0, 5, 5));
      }
      expect(tree.count, 500);

      // Query should return only items in viewport
      final results = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 100, 100),
        margin: 0,
      );
      expect(results.length, greaterThan(0));
      expect(results.length, lessThan(500));
    });
  });

  // ===========================================================================
  // RTree — clear
  // ===========================================================================

  group('RTree - clear', () {
    test('clear resets tree', () {
      final tree = _makeTree();
      for (int i = 0; i < 20; i++) {
        tree.insert(_item('item$i', i * 10.0, 0, 5, 5));
      }
      expect(tree.count, 20);
      tree.clear();
      expect(tree.count, 0);
      expect(
        tree.queryVisible(const Rect.fromLTWH(0, 0, 10000, 10000)),
        isEmpty,
      );
    });
  });

  // ===========================================================================
  // RTree — edge cases
  // ===========================================================================

  group('RTree - edge cases', () {
    test('overlapping items are all returned', () {
      final tree = _makeTree();
      tree.insert(_item('a', 0, 0, 100, 100));
      tree.insert(_item('b', 50, 50, 100, 100));
      tree.insert(_item('c', 0, 0, 100, 100));

      final results = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(results.length, 3);
    });

    test('insert after remove works correctly', () {
      final tree = _makeTree();
      final item = _item('a', 0, 0, 10, 10);
      tree.insert(item);
      tree.remove(item);
      tree.insert(_item('b', 0, 0, 10, 10));
      expect(tree.count, 1);
    });
  });
}
