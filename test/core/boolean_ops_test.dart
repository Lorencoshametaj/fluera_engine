import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/vector/boolean_ops.dart';
import 'package:fluera_engine/src/core/vector/vector_path.dart';
import 'package:fluera_engine/src/core/vector/shape_presets.dart';
import 'package:fluera_engine/src/core/nodes/boolean_group_node.dart';
import 'package:fluera_engine/src/core/nodes/path_node.dart';
import 'package:fluera_engine/src/core/nodes/shape_node.dart';
import 'package:fluera_engine/src/core/models/shape_type.dart';

// =============================================================================
// Helpers
// =============================================================================

/// Create a closed rectangle VectorPath at given origin + size.
VectorPath _rect(double x, double y, double w, double h) {
  return ShapePresets.rectangle(Rect.fromLTWH(x, y, w, h));
}

/// Compute bounding area of a VectorPath.
double _area(VectorPath path) {
  final bounds = path.computeBounds();
  return bounds.width * bounds.height;
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  // ===========================================================================
  // 1. Union of two overlapping rectangles
  // ===========================================================================
  test('union merges two overlapping rects', () {
    //  A: 0,0 100x100
    //  B: 50,0 100x100
    //  Result bounding box should be 0,0 → 150,100
    final a = _rect(0, 0, 100, 100);
    final b = _rect(50, 0, 100, 100);

    final result = BooleanOps.union(a, b, sourceAId: 'a', sourceBId: 'b');

    expect(result.operation, BooleanOpType.union);
    final bounds = result.resultPath.computeBounds();
    expect(bounds.left, closeTo(0, 1));
    expect(bounds.top, closeTo(0, 1));
    expect(bounds.right, closeTo(150, 1));
    expect(bounds.bottom, closeTo(100, 1));
  });

  // ===========================================================================
  // 2. Subtract (hole punch)
  // ===========================================================================
  test('subtract removes B from A', () {
    //  A: 0,0 100x100
    //  B: 25,25 50x50  (entirely inside A)
    //  Result should have A's bounding box but smaller area.
    final a = _rect(0, 0, 100, 100);
    final b = _rect(25, 25, 50, 50);

    final result = BooleanOps.subtract(a, b, sourceAId: 'a', sourceBId: 'b');

    expect(result.operation, BooleanOpType.subtract);
    // Bounding box stays the same as A.
    final bounds = result.resultPath.computeBounds();
    expect(bounds.left, closeTo(0, 1));
    expect(bounds.top, closeTo(0, 1));
    expect(bounds.right, closeTo(100, 1));
    expect(bounds.bottom, closeTo(100, 1));
    // Result should have segments (not empty).
    expect(result.resultPath.segments, isNotEmpty);
  });

  // ===========================================================================
  // 3. Intersect
  // ===========================================================================
  test('intersect keeps only overlap', () {
    //  A: 0,0 100x100
    //  B: 50,50 100x100
    //  Intersection: 50,50 → 100,100 (50x50)
    final a = _rect(0, 0, 100, 100);
    final b = _rect(50, 50, 100, 100);

    final result = BooleanOps.intersect(a, b, sourceAId: 'a', sourceBId: 'b');

    expect(result.operation, BooleanOpType.intersect);
    final bounds = result.resultPath.computeBounds();
    expect(bounds.left, closeTo(50, 1));
    expect(bounds.top, closeTo(50, 1));
    expect(bounds.width, closeTo(50, 2));
    expect(bounds.height, closeTo(50, 2));
  });

  // ===========================================================================
  // 4. Exclude (XOR)
  // ===========================================================================
  test('exclude removes the overlapping area', () {
    final a = _rect(0, 0, 100, 100);
    final b = _rect(50, 0, 100, 100);

    final result = BooleanOps.exclude(a, b, sourceAId: 'a', sourceBId: 'b');

    expect(result.operation, BooleanOpType.exclude);
    // Bounding box spans both rects: 0 → 150.
    final bounds = result.resultPath.computeBounds();
    expect(bounds.left, closeTo(0, 1));
    expect(bounds.right, closeTo(150, 1));
    expect(result.resultPath.segments, isNotEmpty);
  });

  // ===========================================================================
  // 5. Multi-path union (flattenUnion)
  // ===========================================================================
  test('flattenUnion merges 3+ shapes', () {
    final paths = [
      _rect(0, 0, 50, 50),
      _rect(25, 0, 50, 50),
      _rect(50, 0, 50, 50),
    ];

    final result = BooleanOps.flattenUnion(paths);
    final bounds = result.computeBounds();

    // Should span 0 → 100 in X, 0 → 50 in Y.
    expect(bounds.left, closeTo(0, 1));
    expect(bounds.right, closeTo(100, 1));
    expect(bounds.top, closeTo(0, 1));
    expect(bounds.bottom, closeTo(50, 1));
  });

  // ===========================================================================
  // 6. multiExecute with subtract
  // ===========================================================================
  test('multiExecute chains operations across N paths', () {
    final paths = [
      _rect(0, 0, 100, 100),
      _rect(10, 10, 20, 20),
      _rect(50, 50, 20, 20),
    ];

    // Subtract both holes from the first shape.
    final result = BooleanOps.multiExecute(BooleanOpType.subtract, paths);

    // Result still has A's bounding box but with two holes.
    final bounds = result.computeBounds();
    expect(bounds.left, closeTo(0, 1));
    expect(bounds.right, closeTo(100, 1));
    expect(result.segments, isNotEmpty);
  });

  // ===========================================================================
  // 7. pathsOverlap true / false
  // ===========================================================================
  group('pathsOverlap', () {
    test('returns true for overlapping rects', () {
      final a = _rect(0, 0, 100, 100);
      final b = _rect(50, 50, 100, 100);
      expect(BooleanOps.pathsOverlap(a, b), isTrue);
    });

    test('returns false for non-overlapping rects', () {
      final a = _rect(0, 0, 50, 50);
      final b = _rect(200, 200, 50, 50);
      expect(BooleanOps.pathsOverlap(a, b), isFalse);
    });
  });

  // ===========================================================================
  // 8. BooleanGroupNode JSON roundtrip
  // ===========================================================================
  test('BooleanGroupNode JSON roundtrip preserves all fields', () {
    final group = BooleanGroupNode(
      id: NodeId('bg1'),
      operation: BooleanOpType.subtract,
      fillColor: const Color(0xFFFF0000),
      strokeColor: const Color(0xFF0000FF),
      strokeWidth: 3.0,
    );

    final json = group.toJson();
    final restored = BooleanGroupNode.fromJson(json);

    expect(restored.id, 'bg1');
    expect(restored.operation, BooleanOpType.subtract);
    expect(restored.fillColor, const Color(0xFFFF0000));
    expect(restored.strokeColor, const Color(0xFF0000FF));
    expect(restored.strokeWidth, 3.0);
  });

  // ===========================================================================
  // 9. BooleanGroupNode dirty caching
  // ===========================================================================
  test('BooleanGroupNode caches computed path until invalidated', () {
    final group = BooleanGroupNode(id: NodeId('bg2'), operation: BooleanOpType.union);

    final childA = PathNode(id: NodeId('pa'), path: _rect(0, 0, 50, 50));
    final childB = PathNode(id: NodeId('pb'), path: _rect(25, 0, 50, 50));

    group.add(childA);
    group.add(childB);

    // First access: computes the path.
    expect(group.needsRecompute, isTrue);
    final path1 = group.computedPath;
    expect(group.needsRecompute, isFalse);
    expect(path1.segments, isNotEmpty);

    // Second access: returns cached (same instance).
    final path2 = group.computedPath;
    expect(identical(path1, path2), isTrue);

    // Invalidate and verify it recomputes.
    group.invalidate();
    expect(group.needsRecompute, isTrue);
    final path3 = group.computedPath;
    expect(group.needsRecompute, isFalse);
    expect(identical(path1, path3), isFalse);
  });

  // ===========================================================================
  // 10. nodeToVectorPath converts ShapeNode correctly
  // ===========================================================================
  test('nodeToVectorPath converts a ShapeNode rectangle', () {
    final shape = GeometricShape(
      id: NodeId('s1'),
      type: ShapeType.rectangle,
      startPoint: const Offset(0, 0),
      endPoint: const Offset(80, 60),
      color: const Color(0xFF000000),
      strokeWidth: 1,
      createdAt: DateTime.now(),
    );

    final node = ShapeNode(id: NodeId('s1'), shape: shape);
    final vp = BooleanOps.nodeToVectorPath(node);

    expect(vp, isNotNull);
    final bounds = vp!.computeBounds();
    expect(bounds.width, closeTo(80, 1));
    expect(bounds.height, closeTo(60, 1));
  });

  // ===========================================================================
  // 11. BooleanResult toJson
  // ===========================================================================
  test('BooleanResult.toJson includes all fields', () {
    final result = BooleanOps.union(
      _rect(0, 0, 50, 50),
      _rect(25, 25, 50, 50),
      sourceAId: 'shapeA',
      sourceBId: 'shapeB',
    );

    final json = result.toJson();
    expect(json['operation'], 'union');
    expect(json['sourceA'], 'shapeA');
    expect(json['sourceB'], 'shapeB');
    expect(json['resultPath'], isA<Map>());
  });

  // ===========================================================================
  // 12. Empty paths edge case
  // ===========================================================================
  test('multiExecute handles empty list gracefully', () {
    final result = BooleanOps.multiExecute(BooleanOpType.union, []);
    expect(result.segments, isEmpty);
  });

  test('multiExecute with single path returns it unchanged', () {
    final rect = _rect(10, 20, 30, 40);
    final result = BooleanOps.multiExecute(BooleanOpType.union, [rect]);
    expect(result.computeBounds().width, closeTo(30, 1));
    expect(result.computeBounds().height, closeTo(40, 1));
  });
}
