import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/tools/eraser/eraser_spatial_index.dart';
import 'package:fluera_engine/src/tools/eraser/eraser_hit_tester.dart';
import '../helpers/test_helpers.dart';

void main() {
  late EraserSpatialIndex index;

  setUp(() {
    index = EraserSpatialIndex();
  });

  // =========================================================================
  // Initial State
  // =========================================================================

  group('initial state', () {
    test('starts dirty', () {
      expect(index.isDirty, isTrue);
    });

    test('returns empty set when dirty', () {
      final result = index.getNearbyStrokeIds(
        const Offset(50, 50),
        eraserRadius: 20.0,
        eraserShape: EraserShape.circle,
      );
      expect(result, isEmpty);
    });
  });

  // =========================================================================
  // Rebuild
  // =========================================================================

  group('rebuild', () {
    test('clears dirty flag after rebuild', () {
      index.rebuild([testStroke()]);
      expect(index.isDirty, isFalse);
    });

    test('finds stroke after rebuild', () {
      final stroke = testStroke(id: NodeId('nearby'), pointCount: 5); // (0,0)→(40,40)
      index.rebuild([stroke]);

      final result = index.getNearbyStrokeIds(
        const Offset(20, 20),
        eraserRadius: 30.0,
        eraserShape: EraserShape.circle,
      );
      expect(result, contains('nearby'));
    });

    test('does not find distant stroke', () {
      final stroke = testStroke(id: NodeId('far'), pointCount: 3);
      index.rebuild([stroke]);

      final result = index.getNearbyStrokeIds(
        const Offset(500, 500),
        eraserRadius: 10.0,
        eraserShape: EraserShape.circle,
      );
      expect(result, isNot(contains('far')));
    });

    test('multiple strokes in same area', () {
      final s1 = testStroke(id: NodeId('s1'), pointCount: 3);
      final s2 = testStroke(id: NodeId('s2'), pointCount: 3);
      index.rebuild([s1, s2]);

      final result = index.getNearbyStrokeIds(
        const Offset(10, 10),
        eraserRadius: 30.0,
        eraserShape: EraserShape.circle,
      );
      expect(result, containsAll(['s1', 's2']));
    });
  });

  // =========================================================================
  // Incremental Operations
  // =========================================================================

  group('incrementalAdd', () {
    test('adds stroke to existing index', () {
      index.rebuild([]); // clean index
      final stroke = testStroke(id: NodeId('added'), pointCount: 3);
      index.incrementalAdd(stroke);

      final result = index.getNearbyStrokeIds(
        const Offset(10, 10),
        eraserRadius: 30.0,
        eraserShape: EraserShape.circle,
      );
      expect(result, contains('added'));
    });

    test('no-op when index is dirty', () {
      // Don't rebuild → stays dirty
      final stroke = testStroke(id: NodeId('ignored'), pointCount: 3);
      index.incrementalAdd(stroke); // should be no-op

      // After rebuild with empty list, stroke should not be there
      index.rebuild([]);
      final result = index.getNearbyStrokeIds(
        const Offset(10, 10),
        eraserRadius: 30.0,
        eraserShape: EraserShape.circle,
      );
      expect(result, isNot(contains('ignored')));
    });
  });

  group('incrementalRemove', () {
    test('removes stroke from index', () {
      final stroke = testStroke(id: NodeId('removable'), pointCount: 3);
      index.rebuild([stroke]);
      index.incrementalRemove(stroke);

      final result = index.getNearbyStrokeIds(
        const Offset(10, 10),
        eraserRadius: 30.0,
        eraserShape: EraserShape.circle,
      );
      expect(result, isNot(contains('removable')));
    });
  });

  // =========================================================================
  // Dirty Flag
  // =========================================================================

  group('markDirty', () {
    test('sets dirty flag', () {
      index.rebuild([]);
      expect(index.isDirty, isFalse);
      index.markDirty();
      expect(index.isDirty, isTrue);
    });
  });

  // =========================================================================
  // Clear
  // =========================================================================

  group('clear', () {
    test('removes all entries and sets dirty', () {
      final stroke = testStroke(id: NodeId('cleared'), pointCount: 3);
      index.rebuild([stroke]);
      expect(index.isDirty, isFalse);

      index.clear();
      expect(index.isDirty, isTrue);

      // After rebuild, stroke should be gone
      index.rebuild([]);
      final result = index.getNearbyStrokeIds(
        const Offset(10, 10),
        eraserRadius: 30.0,
        eraserShape: EraserShape.circle,
      );
      expect(result, isEmpty);
    });
  });

  // =========================================================================
  // Shape-Aware Queries
  // =========================================================================

  group('shape-aware queries', () {
    test('rectangle query finds strokes', () {
      final stroke = testStroke(id: NodeId('rect-q'), pointCount: 5);
      index.rebuild([stroke]);

      final result = index.getNearbyStrokeIds(
        const Offset(20, 20),
        eraserRadius: 30.0,
        eraserShape: EraserShape.rectangle,
        eraserShapeWidth: 40.0,
        eraserShapeAngle: 0.0,
      );
      expect(result, contains('rect-q'));
    });

    test('line query finds strokes along line direction', () {
      final stroke = testStroke(id: NodeId('line-q'), pointCount: 5);
      index.rebuild([stroke]);

      final result = index.getNearbyStrokeIds(
        const Offset(20, 20),
        eraserRadius: 30.0,
        eraserShape: EraserShape.line,
        eraserShapeAngle: 0.0,
      );
      expect(result, contains('line-q'));
    });
  });
}
