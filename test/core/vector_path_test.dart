import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/vector/vector_path.dart';

void main() {
  // ===========================================================================
  // Segments
  // ===========================================================================

  group('PathSegment - MoveSegment', () {
    test('creates with endpoint', () {
      final seg = MoveSegment(endPoint: const Offset(10, 20));
      expect(seg.endPoint, const Offset(10, 20));
    });

    test('toJson serializes', () {
      final seg = MoveSegment(endPoint: const Offset(0, 0));
      final json = seg.toJson();
      expect(json['segmentType'], 'move');
    });
  });

  group('PathSegment - LineSegment', () {
    test('creates with endpoint', () {
      final seg = LineSegment(endPoint: const Offset(100, 200));
      expect(seg.endPoint, const Offset(100, 200));
    });

    test('toJson serializes', () {
      final seg = LineSegment(endPoint: const Offset(50, 50));
      final json = seg.toJson();
      expect(json['segmentType'], 'line');
    });
  });

  group('PathSegment - CubicSegment', () {
    test('creates with control points', () {
      final seg = CubicSegment(
        controlPoint1: const Offset(10, 10),
        controlPoint2: const Offset(90, 90),
        endPoint: const Offset(100, 100),
      );
      expect(seg.endPoint, const Offset(100, 100));
      expect(seg.controlPoint1, const Offset(10, 10));
    });
  });

  group('PathSegment - fromJson', () {
    test('deserializes move segment', () {
      final seg = PathSegment.fromJson({
        'segmentType': 'move',
        'x': 5,
        'y': 10,
      });
      expect(seg, isA<MoveSegment>());
    });

    test('deserializes line segment', () {
      final seg = PathSegment.fromJson({
        'segmentType': 'line',
        'x': 50,
        'y': 50,
      });
      expect(seg, isA<LineSegment>());
    });
  });

  // ===========================================================================
  // VectorPath
  // ===========================================================================

  group('VectorPath - construction', () {
    test('creates path with segments', () {
      final path = VectorPath(
        segments: [
          MoveSegment(endPoint: const Offset(0, 0)),
          LineSegment(endPoint: const Offset(100, 0)),
          LineSegment(endPoint: const Offset(100, 100)),
        ],
      );
      expect(path.segments.length, 3);
    });

    test('close makes path closed', () {
      final path = VectorPath(
        segments: [
          MoveSegment(endPoint: const Offset(0, 0)),
          LineSegment(endPoint: const Offset(100, 0)),
          LineSegment(endPoint: const Offset(100, 100)),
        ],
      );
      path.close();
      expect(path.isClosed, isTrue);
    });

    test('lineTo adds line segment', () {
      final path = VectorPath(
        segments: [MoveSegment(endPoint: const Offset(0, 0))],
      );
      path.lineTo(100, 0);
      expect(path.segments.last, isA<LineSegment>());
    });

    test('cubicTo adds cubic segment', () {
      final path = VectorPath(
        segments: [MoveSegment(endPoint: const Offset(0, 0))],
      );
      path.cubicTo(10, 10, 90, 90, 100, 100);
      expect(path.segments.last, isA<CubicSegment>());
    });
  });

  // ===========================================================================
  // Conversion
  // ===========================================================================

  group('VectorPath - toFlutterPath', () {
    test('converts to Flutter Path', () {
      final vp = VectorPath(
        segments: [
          MoveSegment(endPoint: const Offset(0, 0)),
          LineSegment(endPoint: const Offset(100, 0)),
        ],
      );
      final flutterPath = vp.toFlutterPath();
      expect(flutterPath, isA<Path>());
    });
  });

  group('VectorPath - computeBounds', () {
    test('computes bounding box', () {
      final vp = VectorPath(
        segments: [
          MoveSegment(endPoint: const Offset(0, 0)),
          LineSegment(endPoint: const Offset(100, 50)),
        ],
      );
      final bounds = vp.computeBounds();
      expect(bounds.width, greaterThan(0));
    });
  });

  group('VectorPath - toSvgPathData', () {
    test('generates SVG d attribute', () {
      final vp = VectorPath(
        segments: [
          MoveSegment(endPoint: const Offset(0, 0)),
          LineSegment(endPoint: const Offset(100, 0)),
        ],
      );
      final svg = vp.toSvgPathData();
      expect(svg, contains('M'));
      expect(svg, contains('L'));
    });
  });

  // ===========================================================================
  // Serialization
  // ===========================================================================

  group('VectorPath - toJson', () {
    test('serializes to map', () {
      final vp = VectorPath(
        segments: [
          MoveSegment(endPoint: const Offset(10, 20)),
          LineSegment(endPoint: const Offset(50, 50)),
        ],
      );
      final json = vp.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });
  });
}
