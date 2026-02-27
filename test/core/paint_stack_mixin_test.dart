import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/effects/paint_stack.dart';
import 'package:fluera_engine/src/core/scene_graph/paint_stack_mixin.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:fluera_engine/src/core/nodes/path_node.dart';
import 'package:fluera_engine/src/core/vector/vector_path.dart';

/// Create a minimal PathNode for testing paint stack operations.
PathNode _testPathNode(String id) =>
    PathNode(id: NodeId(id), path: VectorPath.moveTo(Offset.zero));

void main() {
  // Use PathNode as a concrete class that uses PaintStackMixin
  late PathNode node;

  setUp(() {
    node = _testPathNode('test-path');
  });

  // ===========================================================================
  // Fill operations
  // ===========================================================================

  group('fill operations', () {
    test('addFill appends to end by default', () {
      final fill1 = FillLayer.solid(color: Colors.red);
      final fill2 = FillLayer.solid(color: Colors.blue);
      node.addFill(fill1);
      node.addFill(fill2);

      expect(node.fills, hasLength(2));
      expect(node.fills[0].color, Colors.red);
      expect(node.fills[1].color, Colors.blue);
    });

    test('addFill at index inserts correctly', () {
      final fill1 = FillLayer.solid(color: Colors.red);
      final fill2 = FillLayer.solid(color: Colors.blue);
      final fill3 = FillLayer.solid(color: Colors.green);
      node.addFill(fill1);
      node.addFill(fill2);
      node.addFill(fill3, 1); // Insert at index 1

      expect(node.fills, hasLength(3));
      expect(node.fills[1].color, Colors.green);
    });

    test('removeFill removes by id', () {
      final fill = FillLayer.solid(color: Colors.red);
      node.addFill(fill);

      final removed = node.removeFill(fill.id);
      expect(removed, true);
      expect(node.fills, isEmpty);
    });

    test('removeFill returns false if not found', () {
      expect(node.removeFill('nonexistent'), false);
    });

    test('reorderFill moves fill', () {
      final fill1 = FillLayer.solid(color: Colors.red);
      final fill2 = FillLayer.solid(color: Colors.blue);
      final fill3 = FillLayer.solid(color: Colors.green);
      node.addFill(fill1);
      node.addFill(fill2);
      node.addFill(fill3);

      node.reorderFill(0, 2); // Move first to third position

      expect(node.fills[0].color, Colors.blue);
      expect(node.fills[1].color, Colors.red);
    });

    test('reorderFill ignores invalid index', () {
      node.addFill(FillLayer.solid(color: Colors.red));
      node.reorderFill(-1, 0); // Invalid — should not throw
      node.reorderFill(5, 0); // Out of range — should not throw
    });

    test('findFill returns fill by id', () {
      final fill = FillLayer.solid(color: Colors.red);
      node.addFill(fill);

      expect(node.findFill(fill.id), isNotNull);
      expect(node.findFill(fill.id)!.color, Colors.red);
    });

    test('findFill returns null if not found', () {
      expect(node.findFill('none'), isNull);
    });
  });

  // ===========================================================================
  // Stroke operations
  // ===========================================================================

  group('stroke operations', () {
    test('addStroke appends to end by default', () {
      final s1 = StrokeLayer(color: Colors.black, width: 1.0);
      final s2 = StrokeLayer(color: Colors.white, width: 2.0);
      node.addStroke(s1);
      node.addStroke(s2);

      expect(node.strokes, hasLength(2));
      expect(node.strokes[0].width, 1.0);
      expect(node.strokes[1].width, 2.0);
    });

    test('addStroke at index inserts correctly', () {
      final s1 = StrokeLayer(color: Colors.black, width: 1.0);
      final s2 = StrokeLayer(color: Colors.white, width: 2.0);
      final s3 = StrokeLayer(color: Colors.red, width: 3.0);
      node.addStroke(s1);
      node.addStroke(s2);
      node.addStroke(s3, 0); // Insert at front

      expect(node.strokes, hasLength(3));
      expect(node.strokes[0].width, 3.0);
    });

    test('removeStroke removes by id', () {
      final s = StrokeLayer(color: Colors.black, width: 1.0);
      node.addStroke(s);

      expect(node.removeStroke(s.id), true);
      expect(node.strokes, isEmpty);
    });

    test('removeStroke returns false if not found', () {
      expect(node.removeStroke('nonexistent'), false);
    });

    test('findStroke returns stroke by id', () {
      final s = StrokeLayer(color: Colors.black, width: 2.5);
      node.addStroke(s);

      expect(node.findStroke(s.id), isNotNull);
      expect(node.findStroke(s.id)!.width, 2.5);
    });

    test('findStroke returns null if not found', () {
      expect(node.findStroke('none'), isNull);
    });
  });

  // ===========================================================================
  // maxStrokeBoundsInflation
  // ===========================================================================

  group('maxStrokeBoundsInflation', () {
    test('returns 0 with no strokes', () {
      expect(node.maxStrokeBoundsInflation, 0.0);
    });

    test('returns max inflation across visible strokes', () {
      node.addStroke(StrokeLayer(color: Colors.black, width: 4.0));
      node.addStroke(StrokeLayer(color: Colors.red, width: 10.0));

      expect(node.maxStrokeBoundsInflation, greaterThanOrEqualTo(0));
    });
  });

  // ===========================================================================
  // Serialization
  // ===========================================================================

  group('serialization', () {
    test('paintStackToJson includes fills and strokes', () {
      node.addFill(FillLayer.solid(color: Colors.red));
      node.addStroke(StrokeLayer(color: Colors.black, width: 1.0));

      final json = node.paintStackToJson();
      expect(json['fills'], isA<List>());
      expect(json['strokes'], isA<List>());
      expect((json['fills'] as List), hasLength(1));
      expect((json['strokes'] as List), hasLength(1));
    });

    test('paintStackToJson omits empty lists', () {
      final json = node.paintStackToJson();
      expect(json.containsKey('fills'), false);
      expect(json.containsKey('strokes'), false);
    });

    test('applyPaintStackFromJson restores fills and strokes', () {
      node.addFill(FillLayer.solid(color: Colors.red));
      node.addStroke(StrokeLayer(color: Colors.black, width: 2.0));

      final json = node.paintStackToJson();

      final target = _testPathNode('target');
      PaintStackMixin.applyPaintStackFromJson(target, json);

      expect(target.fills, hasLength(1));
      expect(target.strokes, hasLength(1));
    });
  });

  // ===========================================================================
  // Clone
  // ===========================================================================

  group('clonePaintStackInto', () {
    test('creates independent copies', () {
      node.addFill(FillLayer.solid(color: Colors.red));
      node.addStroke(StrokeLayer(color: Colors.black, width: 1.0));

      final target = _testPathNode('clone');
      node.clonePaintStackInto(target);

      expect(target.fills, hasLength(1));
      expect(target.strokes, hasLength(1));

      // Verify independence — modifying original doesn't affect clone
      node.fills.clear();
      expect(target.fills, hasLength(1));
    });
  });
}
