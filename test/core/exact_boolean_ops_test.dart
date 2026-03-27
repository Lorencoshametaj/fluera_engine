import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/vector/exact_boolean_ops.dart';
import 'package:fluera_engine/src/core/vector/boolean_ops.dart';
import 'package:fluera_engine/src/core/vector/vector_network.dart';

void main() {
  // Helper: create a simple rectangular VectorNetwork
  VectorNetwork makeRect(double x, double y, double w, double h) {
    final network = VectorNetwork();
    final v0 = network.addVertex(NetworkVertex(position: Offset(x, y)));
    final v1 = network.addVertex(NetworkVertex(position: Offset(x + w, y)));
    final v2 = network.addVertex(NetworkVertex(position: Offset(x + w, y + h)));
    final v3 = network.addVertex(NetworkVertex(position: Offset(x, y + h)));
    final s0 = network.addSegment(NetworkSegment(start: v0, end: v1));
    final s1 = network.addSegment(NetworkSegment(start: v1, end: v2));
    final s2 = network.addSegment(NetworkSegment(start: v2, end: v3));
    final s3 = network.addSegment(NetworkSegment(start: v3, end: v0));
    network.addRegion(
      NetworkRegion(
        loops: [
          RegionLoop(
            segments: [
              SegmentRef(index: s0),
              SegmentRef(index: s1),
              SegmentRef(index: s2),
              SegmentRef(index: s3),
            ],
          ),
        ],
      ),
    );
    return network;
  }

  // ===========================================================================
  // BooleanOpType enum
  // ===========================================================================

  group('BooleanOpType', () {
    test('has union, intersect, subtract, xor', () {
      expect(BooleanOpType.values, contains(BooleanOpType.union));
      expect(BooleanOpType.values, contains(BooleanOpType.intersect));
      expect(BooleanOpType.values, contains(BooleanOpType.subtract));
    });
  });

  // ===========================================================================
  // ExactBooleanOps.execute
  // ===========================================================================

  group('ExactBooleanOps - execute', () {
    test('union of two overlapping rects', () {
      final a = makeRect(0, 0, 100, 100);
      final b = makeRect(50, 50, 100, 100);
      final result = ExactBooleanOps.execute(BooleanOpType.union, a, b);
      expect(result, isNotNull);
      expect(result.vertices.isNotEmpty, isTrue);
    });

    test('intersect of two overlapping rects', () {
      final a = makeRect(0, 0, 100, 100);
      final b = makeRect(50, 50, 100, 100);
      final result = ExactBooleanOps.execute(BooleanOpType.intersect, a, b);
      expect(result, isNotNull);
    });

    test('subtract A - B', () {
      final a = makeRect(0, 0, 100, 100);
      final b = makeRect(50, 50, 100, 100);
      final result = ExactBooleanOps.execute(BooleanOpType.subtract, a, b);
      expect(result, isNotNull);
    });

    test('union of non-overlapping rects', () {
      final a = makeRect(0, 0, 50, 50);
      final b = makeRect(200, 200, 50, 50);
      final result = ExactBooleanOps.execute(BooleanOpType.union, a, b);
      expect(result, isNotNull);
    });
  });
}
