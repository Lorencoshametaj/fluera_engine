import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/vector/anchor_point.dart';
import 'package:fluera_engine/src/core/vector/vector_path.dart';

void main() {
  // ===========================================================================
  // AnchorType enum
  // ===========================================================================

  group('AnchorType', () {
    test('has corner, smooth, symmetric', () {
      expect(AnchorType.values.length, 3);
      expect(AnchorType.values, contains(AnchorType.corner));
      expect(AnchorType.values, contains(AnchorType.smooth));
      expect(AnchorType.values, contains(AnchorType.symmetric));
    });
  });

  // ===========================================================================
  // AnchorPoint construction
  // ===========================================================================

  group('AnchorPoint - construction', () {
    test('creates with position', () {
      final a = AnchorPoint(position: const Offset(10, 20));
      expect(a.position, const Offset(10, 20));
      expect(a.type, AnchorType.corner);
    });

    test('hasCurve false without handles', () {
      final a = AnchorPoint(position: Offset.zero);
      expect(a.hasCurve, isFalse);
    });

    test('hasCurve true with handle', () {
      final a = AnchorPoint(
        position: Offset.zero,
        handleOut: const Offset(10, 0),
      );
      expect(a.hasCurve, isTrue);
    });

    test('handleInAbsolute computes correctly', () {
      final a = AnchorPoint(
        position: const Offset(50, 50),
        handleIn: const Offset(-10, 0),
      );
      expect(a.handleInAbsolute, const Offset(40, 50));
    });

    test('handleOutAbsolute computes correctly', () {
      final a = AnchorPoint(
        position: const Offset(50, 50),
        handleOut: const Offset(10, 0),
      );
      expect(a.handleOutAbsolute, const Offset(60, 50));
    });
  });

  // ===========================================================================
  // Equality
  // ===========================================================================

  group('AnchorPoint - equality', () {
    test('equal anchors', () {
      final a = AnchorPoint(position: const Offset(1, 2));
      final b = AnchorPoint(position: const Offset(1, 2));
      expect(a, b);
    });

    test('different positions not equal', () {
      final a = AnchorPoint(position: const Offset(1, 2));
      final b = AnchorPoint(position: const Offset(3, 4));
      expect(a, isNot(b));
    });
  });

  // ===========================================================================
  // Serialization
  // ===========================================================================

  group('AnchorPoint - toJson/fromJson', () {
    test('round-trips corner anchor', () {
      final anchor = AnchorPoint(position: const Offset(10, 20));
      final json = anchor.toJson();
      final restored = AnchorPoint.fromJson(json);
      expect(restored.position, const Offset(10, 20));
      expect(restored.type, AnchorType.corner);
    });

    test('round-trips smooth anchor with handles', () {
      final anchor = AnchorPoint(
        position: const Offset(50, 50),
        handleIn: const Offset(-10, 0),
        handleOut: const Offset(10, 0),
        type: AnchorType.smooth,
      );
      final json = anchor.toJson();
      final restored = AnchorPoint.fromJson(json);
      expect(restored.handleIn, const Offset(-10, 0));
      expect(restored.handleOut, const Offset(10, 0));
      expect(restored.type, AnchorType.smooth);
    });
  });

  // ===========================================================================
  // toVectorPath / fromVectorPath
  // ===========================================================================

  group('AnchorPoint - toVectorPath', () {
    test('empty list returns empty path', () {
      final path = AnchorPoint.toVectorPath([]);
      expect(path.segments, isEmpty);
    });

    test('straight line anchors produce line path', () {
      final anchors = [
        AnchorPoint(position: const Offset(0, 0)),
        AnchorPoint(position: const Offset(100, 0)),
        AnchorPoint(position: const Offset(100, 100)),
      ];
      final path = AnchorPoint.toVectorPath(anchors);
      expect(path.segments.length, 3); // move + 2 lines
    });

    test('closed path', () {
      final anchors = [
        AnchorPoint(position: const Offset(0, 0)),
        AnchorPoint(position: const Offset(100, 0)),
        AnchorPoint(position: const Offset(50, 100)),
      ];
      final path = AnchorPoint.toVectorPath(anchors, closed: true);
      expect(path.isClosed, isTrue);
    });

    test('anchors with handles produce cubics', () {
      final anchors = [
        AnchorPoint(
          position: const Offset(0, 0),
          handleOut: const Offset(30, 0),
        ),
        AnchorPoint(
          position: const Offset(100, 0),
          handleIn: const Offset(-30, 0),
        ),
      ];
      final path = AnchorPoint.toVectorPath(anchors);
      expect(path.segments.last, isA<CubicSegment>());
    });
  });

  group('AnchorPoint - fromVectorPath', () {
    test('extracts anchors from line path', () {
      final path = VectorPath(
        segments: [
          MoveSegment(endPoint: const Offset(0, 0)),
          LineSegment(endPoint: const Offset(100, 0)),
        ],
      );
      final anchors = AnchorPoint.fromVectorPath(path);
      expect(anchors.length, 2);
      expect(anchors[0].position, const Offset(0, 0));
      expect(anchors[1].position, const Offset(100, 0));
    });

    test('extracts anchors from cubic path', () {
      final path = VectorPath(
        segments: [
          MoveSegment(endPoint: const Offset(0, 0)),
          CubicSegment(
            controlPoint1: const Offset(30, 0),
            controlPoint2: const Offset(70, 0),
            endPoint: const Offset(100, 0),
          ),
        ],
      );
      final anchors = AnchorPoint.fromVectorPath(path);
      expect(anchors.length, 2);
      expect(anchors[0].handleOut, isNotNull);
      expect(anchors[1].handleIn, isNotNull);
    });
  });
}
