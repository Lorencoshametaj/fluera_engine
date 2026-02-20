import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/spatial_index.dart';
import 'package:nebula_engine/src/core/nodes/stroke_node.dart';
import 'package:nebula_engine/src/core/nodes/shape_node.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('SpatialIndex (R-tree) insert and query', () {
    test('insert and queryRange returns the node', () {
      final index = SpatialIndex();
      final node = testShapeNode(id: NodeId('si-1'));
      index.insert(node);

      final results = index.queryRange(const Rect.fromLTWH(0, 0, 200, 200));
      expect(results.any((n) => n.id == 'si-1'), isTrue);
    });

    test('queryRange misses nodes outside range', () {
      final index = SpatialIndex();
      final node = testShapeNode(id: NodeId('si-far'));
      // Shape is at (0,0)-(100,100)
      index.insert(node);

      final results = index.queryRange(const Rect.fromLTWH(500, 500, 100, 100));
      expect(results, isEmpty);
    });
  });

  group('SpatialIndex remove', () {
    test('remove by id returns node no longer in results', () {
      final index = SpatialIndex();
      final node = testShapeNode(id: NodeId('si-rem'));
      index.insert(node);
      index.remove('si-rem');

      final results = index.queryRange(const Rect.fromLTWH(0, 0, 200, 200));
      expect(results.any((n) => n.id == 'si-rem'), isFalse);
    });
  });

  group('SpatialIndex queryPoint', () {
    test('queryPoint finds nodes containing the point', () {
      final index = SpatialIndex();
      final node = testShapeNode(id: NodeId('si-pt'));
      index.insert(node);

      final results = index.queryPoint(const Offset(50, 50));
      expect(results.any((n) => n.id == 'si-pt'), isTrue);
    });

    test('queryPoint misses nodes not containing the point', () {
      final index = SpatialIndex();
      final node = testShapeNode(id: NodeId('si-miss'));
      index.insert(node);

      final results = index.queryPoint(const Offset(500, 500));
      expect(results, isEmpty);
    });
  });

  group('SpatialIndex queryNearest', () {
    test('queryNearest returns closest node', () {
      final index = SpatialIndex();
      final near = testShapeNode(id: NodeId('near'));
      index.insert(near);

      final results = index.queryNearest(const Offset(50, 50), k: 1);
      expect(results.length, 1);
      expect(results.first.id, 'near');
    });
  });

  group('SpatialIndex rebuild and contains', () {
    test('contains returns true for inserted node', () {
      final index = SpatialIndex();
      final node = testShapeNode(id: NodeId('exists'));
      index.insert(node);

      expect(index.contains('exists'), isTrue);
      expect(index.contains('nope'), isFalse);
    });

    test('rebuild replaces all nodes', () {
      final index = SpatialIndex();
      index.insert(testShapeNode(id: NodeId('old')));

      index.rebuild([testShapeNode(id: NodeId('new-1')), testShapeNode(id: NodeId('new-2'))]);

      expect(index.contains('old'), isFalse);
      expect(index.contains('new-1'), isTrue);
      expect(index.contains('new-2'), isTrue);
    });

    test('clear removes everything', () {
      final index = SpatialIndex();
      index.insert(testShapeNode(id: NodeId('cl')));
      index.clear();

      expect(index.contains('cl'), isFalse);
      expect(index.queryRange(const Rect.fromLTWH(0, 0, 9999, 9999)), isEmpty);
    });
  });
}
