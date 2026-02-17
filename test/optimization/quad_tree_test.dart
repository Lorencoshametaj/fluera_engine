import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/rendering/optimization/spatial_index.dart';
import 'package:nebula_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:nebula_engine/src/core/models/shape_type.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('QuadTree<ProStroke> insert and query', () {
    late QuadTree<ProStroke> tree;
    final canvasBounds = const Rect.fromLTWH(0, 0, 1000, 1000);

    setUp(() {
      tree = QuadTree<ProStroke>(canvasBounds, (s) => s.bounds);
    });

    test('insert and query returns the stroke', () {
      final stroke = testStroke(id: 'q1');
      tree.insert(stroke);

      final results = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(results, contains(stroke));
    });

    test('query misses strokes outside viewport', () {
      final stroke = testStroke(id: 'far');
      // Stroke points are near origin (0-40, 0-40)
      tree.insert(stroke);

      final results = tree.queryVisible(
        const Rect.fromLTWH(500, 500, 100, 100),
        margin: 0,
      );
      expect(results, isEmpty);
    });

    test('insert outside bounds is ignored', () {
      // Create stroke way outside canvas
      final farStroke = ProStroke(
        id: 'outside',
        points: [
          ProDrawingPoint(
            position: const Offset(5000, 5000),
            pressure: 0.5,
            timestamp: 0,
          ),
        ],
        color: Colors.black,
        baseWidth: 2.0,
        penType: ProPenType.ballpoint,
        createdAt: DateTime(2025),
      );
      tree.insert(farStroke);

      // Should not appear in query within bounds
      final results = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 100, 100),
        margin: 0,
      );
      expect(results, isEmpty);
    });
  });

  group('QuadTree<ProStroke> remove', () {
    test('remove returns true for existing item', () {
      final tree = QuadTree<ProStroke>(
        const Rect.fromLTWH(0, 0, 1000, 1000),
        (s) => s.bounds,
      );
      final stroke = testStroke(id: 'rem');
      tree.insert(stroke);

      expect(tree.remove(stroke), isTrue);
    });

    test('after removal, query no longer returns item', () {
      final tree = QuadTree<ProStroke>(
        const Rect.fromLTWH(0, 0, 1000, 1000),
        (s) => s.bounds,
      );
      final stroke = testStroke(id: 'rem2');
      tree.insert(stroke);
      tree.remove(stroke);

      final results = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(results, isEmpty);
    });
  });

  group('QuadTree subdivision', () {
    test('subdivides when exceeding maxItemsPerNode', () {
      final tree = QuadTree<ProStroke>(
        const Rect.fromLTWH(0, 0, 1000, 1000),
        (s) => s.bounds,
      );

      // Insert more than maxItemsPerNode (16) strokes
      for (int i = 0; i < 20; i++) {
        tree.insert(testStroke(id: 'sub-$i'));
      }

      final stats = tree.stats;
      // After subdivision, total nodes should be > 1
      expect(stats['totalNodes']!, greaterThan(1));
    });
  });

  group('QuadTree clear', () {
    test('clear empties the tree', () {
      final tree = QuadTree<ProStroke>(
        const Rect.fromLTWH(0, 0, 1000, 1000),
        (s) => s.bounds,
      );
      tree.insert(testStroke(id: 'cl'));
      tree.clear();

      final results = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 1000, 1000),
        margin: 0,
      );
      expect(results, isEmpty);
    });
  });

  group('QuadTree.fromItems factory', () {
    test('builds tree from list of items', () {
      final strokes = List.generate(5, (i) => testStroke(id: 'fi-$i'));
      final tree = QuadTree<ProStroke>.fromItems(
        strokes,
        const Rect.fromLTWH(0, 0, 1000, 1000),
        (s) => s.bounds,
      );

      final results = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(results.length, 5);
    });
  });

  group('QuadTree with margin', () {
    test('margin expands viewport for query', () {
      final tree = QuadTree<ProStroke>(
        const Rect.fromLTWH(0, 0, 10000, 10000),
        (s) => s.bounds,
      );
      final stroke = testStroke(id: 'margin');
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
        strokes: [testStroke(id: 'sm-1'), testStroke(id: 'sm-2')],
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
      manager.build(strokes: [], shapes: [testShape(id: 'sm-sh')]);

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
      manager.addStroke(testStroke(id: 'added'));

      final visible = manager.queryVisibleStrokes(
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 0,
      );
      expect(visible.length, 1);
    });
  });
}
