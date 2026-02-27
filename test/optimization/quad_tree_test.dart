import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/rendering/optimization/spatial_index.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:fluera_engine/src/core/models/shape_type.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('RTree<ProStroke> insert and query', () {
    late RTree<ProStroke> tree;

    setUp(() {
      tree = RTree<ProStroke>((s) => s.bounds);
    });

    test('insert and query returns the stroke', () {
      final stroke = testStroke(id: NodeId('r1'));
      tree.insert(stroke);

      final results = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(results, contains(stroke));
    });

    test('query misses strokes outside viewport', () {
      final stroke = testStroke(id: NodeId('far'));
      tree.insert(stroke);

      final results = tree.queryVisible(
        const Rect.fromLTWH(500, 500, 100, 100),
        margin: 0,
      );
      expect(results, isEmpty);
    });

    test('insert with empty bounds is ignored', () {
      final emptyStroke = ProStroke(
        id: NodeId('empty'),
        points: [],
        color: Colors.black,
        baseWidth: 2.0,
        penType: ProPenType.ballpoint,
        createdAt: DateTime(2025),
      );
      tree.insert(emptyStroke);
      expect(tree.count, 0);
    });

    test('count tracks inserted items', () {
      tree.insert(testStroke(id: NodeId('a')));
      tree.insert(testStroke(id: NodeId('b')));
      tree.insert(testStroke(id: NodeId('c')));
      expect(tree.count, 3);
    });
  });

  group('RTree<ProStroke> remove', () {
    test('remove returns true for existing item', () {
      final tree = RTree<ProStroke>((s) => s.bounds);
      final stroke = testStroke(id: NodeId('rem'));
      tree.insert(stroke);

      expect(tree.remove(stroke), isTrue);
      expect(tree.count, 0);
    });

    test('after removal, query no longer returns item', () {
      final tree = RTree<ProStroke>((s) => s.bounds);
      final stroke = testStroke(id: NodeId('rem2'));
      tree.insert(stroke);
      tree.remove(stroke);

      final results = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(results, isEmpty);
    });

    test('remove non-existent item returns false', () {
      final tree = RTree<ProStroke>((s) => s.bounds);
      final stroke = testStroke(id: NodeId('ghost'));
      expect(tree.remove(stroke), isFalse);
    });
  });

  group('RTree node splitting', () {
    test('handles many inserts without errors', () {
      final tree = RTree<ProStroke>((s) => s.bounds, maxEntries: 4);

      // Insert more than maxEntries to trigger splits
      for (int i = 0; i < 50; i++) {
        tree.insert(testStroke(id: NodeId('split-$i')));
      }

      expect(tree.count, 50);

      final stats = tree.stats;
      // After splits, total nodes should be > 1
      expect(stats['totalNodes']!, greaterThan(1));
      expect(stats['totalItems']!, 50);
    });

    test('all items remain queryable after splits', () {
      final tree = RTree<ProStroke>((s) => s.bounds, maxEntries: 4);
      final strokes = List.generate(30, (i) => testStroke(id: NodeId('q-$i')));

      for (final s in strokes) {
        tree.insert(s);
      }

      // All strokes are near origin, so a large viewport should find all
      final results = tree.queryVisible(
        const Rect.fromLTWH(-100, -100, 1000, 1000),
        margin: 0,
      );
      expect(results.length, 30);
    });
  });

  group('RTree clear', () {
    test('clear empties the tree', () {
      final tree = RTree<ProStroke>((s) => s.bounds);
      tree.insert(testStroke(id: NodeId('cl')));
      tree.clear();

      expect(tree.count, 0);
      expect(tree.isEmpty, isTrue);

      final results = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 1000, 1000),
        margin: 0,
      );
      expect(results, isEmpty);
    });
  });

  group('RTree.fromItems bulk load', () {
    test('builds tree from list of items', () {
      final strokes = List.generate(5, (i) => testStroke(id: NodeId('fi-$i')));
      final tree = RTree<ProStroke>.fromItems(strokes, (s) => s.bounds);

      expect(tree.count, 5);

      final results = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(results.length, 5);
    });

    test('bulk load with many items produces balanced tree', () {
      final strokes = List.generate(100, (i) => testStroke(id: NodeId('bulk-$i')));
      final tree = RTree<ProStroke>.fromItems(strokes, (s) => s.bounds);

      expect(tree.count, 100);

      final stats = tree.stats;
      expect(stats['totalItems']!, 100);
      // Height should be reasonable (< 5 for 100 items with default fanout)
      expect(stats['height']!, lessThanOrEqualTo(5));
    });

    test('bulk load empty list returns empty tree', () {
      final tree = RTree<ProStroke>.fromItems([], (s) => s.bounds);

      expect(tree.isEmpty, isTrue);
    });
  });

  group('RTree with margin', () {
    test('margin expands viewport for query', () {
      final tree = RTree<ProStroke>((s) => s.bounds);
      final stroke = testStroke(id: NodeId('margin'));
      tree.insert(stroke);

      // Stroke is at origin area, query far away but with large margin
      final results = tree.queryVisible(
        const Rect.fromLTWH(200, 200, 100, 100),
        margin: 500.0,
      );
      expect(results, isNotEmpty);
    });
  });

  group('SpatialIndexManager', () {
    test('build and query strokes', () {
      final manager = SpatialIndexManager();
      manager.build(
        strokes: [testStroke(id: NodeId('sm-1')), testStroke(id: NodeId('sm-2'))],
        shapes: [],
      );

      expect(manager.isBuilt, isTrue);

      final visible = manager.queryVisibleStrokes(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(visible.length, 2);
    });

    test('build and query shapes', () {
      final manager = SpatialIndexManager();
      manager.build(strokes: [], shapes: [testShape(id: NodeId('sm-sh'))]);

      final visible = manager.queryVisibleShapes(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(visible.length, 1);
    });

    test('clear resets index', () {
      final manager = SpatialIndexManager();
      manager.build(strokes: [testStroke()], shapes: []);
      manager.clear();

      expect(manager.isBuilt, isFalse);
    });

    test('addStroke adds to existing index', () {
      final manager = SpatialIndexManager();
      manager.build(strokes: [], shapes: []);
      manager.addStroke(testStroke(id: NodeId('added')));

      final visible = manager.queryVisibleStrokes(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(visible.length, 1);
    });

    test('removeStroke removes from index', () {
      final manager = SpatialIndexManager();
      final stroke = testStroke(id: NodeId('to-remove'));
      manager.build(strokes: [stroke], shapes: []);
      manager.removeStroke(stroke);

      final visible = manager.queryVisibleStrokes(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(visible, isEmpty);
    });
  });
}
