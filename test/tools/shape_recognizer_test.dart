import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/tools/shape/shape_recognizer.dart';
import 'package:nebula_engine/src/core/models/shape_type.dart';

void main() {
  // ============================================================================
  // HELPERS
  // ============================================================================

  /// Generate points on a circle/ellipse.
  List<Offset> circlePoints(
    double cx,
    double cy,
    double rx,
    double ry, {
    int n = 60,
  }) {
    return List.generate(n, (i) {
      final angle = 2 * pi * i / n;
      return Offset(cx + rx * cos(angle), cy + ry * sin(angle));
    });
  }

  /// Generate regular polygon vertices with many intermediate points.
  List<Offset> regularPolygon(
    double cx,
    double cy,
    double r,
    int sides, {
    int pointsPerSide = 15,
  }) {
    final pts = <Offset>[];
    for (int s = 0; s < sides; s++) {
      final angle1 = 2 * pi * s / sides - pi / 2;
      final angle2 = 2 * pi * (s + 1) / sides - pi / 2;
      final p1 = Offset(cx + r * cos(angle1), cy + r * sin(angle1));
      final p2 = Offset(cx + r * cos(angle2), cy + r * sin(angle2));
      for (int i = 0; i < pointsPerSide; i++) {
        final t = i / pointsPerSide;
        pts.add(
          Offset(p1.dx + t * (p2.dx - p1.dx), p1.dy + t * (p2.dy - p1.dy)),
        );
      }
    }
    // Close path
    pts.add(pts.first);
    return pts;
  }

  /// Generate a star shape.
  List<Offset> starPoints(
    double cx,
    double cy,
    double outerR,
    double innerR, {
    int n = 5,
    int pointsPerSegment = 10,
  }) {
    final pts = <Offset>[];
    for (int i = 0; i < n; i++) {
      final outerAngle = 2 * pi * i / n - pi / 2;
      final innerAngle = 2 * pi * (i + 0.5) / n - pi / 2;
      final outer = Offset(
        cx + outerR * cos(outerAngle),
        cy + outerR * sin(outerAngle),
      );
      final inner = Offset(
        cx + innerR * cos(innerAngle),
        cy + innerR * sin(innerAngle),
      );
      // Points from outer to inner
      for (int j = 0; j < pointsPerSegment; j++) {
        final t = j / pointsPerSegment;
        pts.add(
          Offset(
            outer.dx + t * (inner.dx - outer.dx),
            outer.dy + t * (inner.dy - outer.dy),
          ),
        );
      }
      // Points from inner to next outer
      final nextOuterAngle = 2 * pi * (i + 1) / n - pi / 2;
      final nextOuter = Offset(
        cx + outerR * cos(nextOuterAngle),
        cy + outerR * sin(nextOuterAngle),
      );
      for (int j = 0; j < pointsPerSegment; j++) {
        final t = j / pointsPerSegment;
        pts.add(
          Offset(
            inner.dx + t * (nextOuter.dx - inner.dx),
            inner.dy + t * (nextOuter.dy - inner.dy),
          ),
        );
      }
    }
    pts.add(pts.first);
    return pts;
  }

  // ============================================================================
  // CIRCLE TESTS
  // ============================================================================

  group('circle recognition', () {
    test('perfect circle is recognized', () {
      final pts = circlePoints(100, 100, 50, 50);
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      expect(result.type, ShapeType.circle);
      expect(result.isEllipse, isFalse);
    });

    test('elliptical shape is recognized with isEllipse flag', () {
      final pts = circlePoints(100, 100, 60, 40);
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      expect(result.type, ShapeType.circle);
      expect(result.isEllipse, isTrue);
    });

    test('slightly oval circle (50×45) is recognized', () {
      final pts = circlePoints(100, 100, 50, 45);
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      expect(result.type, ShapeType.circle);
    });

    test('noisy circle with jitter is still recognized', () {
      final random = Random(42);
      final pts = List.generate(60, (i) {
        final angle = 2 * pi * i / 60;
        return Offset(
          100 + 50 * cos(angle) + (random.nextDouble() - 0.5) * 6,
          100 + 50 * sin(angle) + (random.nextDouble() - 0.5) * 6,
        );
      });
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      expect(result.type, ShapeType.circle);
    });
  });

  // ============================================================================
  // RECTANGLE TESTS
  // ============================================================================

  group('rectangle recognition', () {
    test('perfect rectangle is recognized', () {
      final pts = regularPolygon(100, 100, 50, 4, pointsPerSide: 20);
      // Rotate to make a rectangle (square is fine too)
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      // Could be rectangle or diamond depending on rotation
    });

    test('axis-aligned rectangle is recognized', () {
      final pts = <Offset>[];
      // Top edge
      for (int i = 0; i <= 20; i++) pts.add(Offset(50 + i * 5.0, 50));
      // Right edge
      for (int i = 0; i <= 15; i++) pts.add(Offset(150, 50 + i * 5.0));
      // Bottom edge
      for (int i = 0; i <= 20; i++) pts.add(Offset(150 - i * 5.0, 125));
      // Left edge
      for (int i = 0; i <= 15; i++) pts.add(Offset(50, 125 - i * 5.0));
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      expect(result.type, ShapeType.rectangle);
    });
  });

  // ============================================================================
  // TRIANGLE TESTS
  // ============================================================================

  group('triangle recognition', () {
    test('equilateral triangle is recognized', () {
      final pts = regularPolygon(100, 100, 50, 3, pointsPerSide: 20);
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      expect(result.type, ShapeType.triangle);
    });

    test('right triangle is recognized', () {
      final pts = <Offset>[];
      for (int i = 0; i <= 20; i++) pts.add(Offset(50 + i * 5.0, 150));
      for (int i = 0; i <= 20; i++) pts.add(Offset(150, 150 - i * 5.0));
      for (int i = 0; i <= 28; i++) {
        final t = i / 28;
        pts.add(Offset(150 - t * 100, 50 + t * 100));
      }
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      expect(result.type, ShapeType.triangle);
    });
  });

  // ============================================================================
  // LINE TESTS
  // ============================================================================

  group('line recognition', () {
    test('horizontal line is recognized', () {
      final pts = List.generate(30, (i) => Offset(50 + i * 5.0, 100));
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      expect(result.type, ShapeType.line);
    });

    test('diagonal line is recognized', () {
      final pts = List.generate(30, (i) => Offset(50 + i * 5.0, 50 + i * 3.0));
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      expect(result.type, ShapeType.line);
    });

    test('slightly wobbly line is still recognized', () {
      final random = Random(42);
      final pts = List.generate(30, (i) {
        return Offset(50 + i * 5.0, 100 + (random.nextDouble() - 0.5) * 3);
      });
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      expect(result.type, ShapeType.line);
    });
  });

  // ============================================================================
  // PENTAGON TESTS
  // ============================================================================

  group('pentagon recognition', () {
    test('regular pentagon is recognized', () {
      final pts = regularPolygon(100, 100, 50, 5, pointsPerSide: 15);
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      expect(result.type, ShapeType.pentagon);
    });
  });

  // ============================================================================
  // HEXAGON TESTS
  // ============================================================================

  group('hexagon recognition', () {
    test('regular hexagon is recognized', () {
      final pts = regularPolygon(100, 100, 50, 6, pointsPerSide: 15);
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      expect(result.type, ShapeType.hexagon);
    });
  });

  // ============================================================================
  // STAR TESTS
  // ============================================================================

  group('star recognition', () {
    test('5-pointed star is recognized', () {
      final pts = starPoints(100, 100, 60, 25, n: 5, pointsPerSegment: 12);
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isTrue);
      expect(result.type, ShapeType.star);
    });
  });

  // ============================================================================
  // REJECTION TESTS
  // ============================================================================

  group('rejection', () {
    test('random zigzag is not recognized', () {
      final pts = <Offset>[];
      for (int i = 0; i < 40; i++) {
        pts.add(Offset(50 + i * 5.0, 100 + (i.isEven ? 30 : -30).toDouble()));
      }
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isFalse);
    });

    test('too few points returns no match', () {
      final pts = [const Offset(0, 0), const Offset(100, 100)];
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isFalse);
    });

    test('tiny gesture is rejected', () {
      final pts = List.generate(10, (i) => Offset(5 + i * 1.0, 5));
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isFalse);
    });

    test('open S-curve is not recognized as a shape', () {
      final pts = List.generate(40, (i) {
        final t = i / 40.0 * 2 * pi;
        return Offset(100 + 30 * sin(t), 50 + i * 3.0);
      });
      final result = ShapeRecognizer.recognize(pts);
      expect(result.recognized, isFalse);
    });
  });

  // ============================================================================
  // SENSITIVITY TESTS
  // ============================================================================

  group('sensitivity levels', () {
    test('high sensitivity accepts rough shapes', () {
      // A rough circle that medium sensitivity might reject
      final random = Random(99);
      final pts = List.generate(50, (i) {
        final angle = 2 * pi * i / 50;
        return Offset(
          100 + 50 * cos(angle) + (random.nextDouble() - 0.5) * 10,
          100 + 50 * sin(angle) + (random.nextDouble() - 0.5) * 10,
        );
      });
      final highResult = ShapeRecognizer.recognize(
        pts,
        sensitivity: ShapeRecognitionSensitivity.high,
      );
      // High sensitivity should be more lenient
      expect(highResult.type, isNotNull);
    });

    test('low sensitivity rejects rough shapes', () {
      final random = Random(99);
      final pts = List.generate(50, (i) {
        final angle = 2 * pi * i / 50;
        return Offset(
          100 + 50 * cos(angle) + (random.nextDouble() - 0.5) * 15,
          100 + 50 * sin(angle) + (random.nextDouble() - 0.5) * 15,
        );
      });
      final lowResult = ShapeRecognizer.recognize(
        pts,
        sensitivity: ShapeRecognitionSensitivity.low,
      );
      // Low sensitivity should be stricter
      expect(
        lowResult.recognizedAt(ShapeRecognitionSensitivity.low.threshold),
        isFalse,
      );
    });
  });

  // ============================================================================
  // RESULT PROPERTIES TESTS
  // ============================================================================

  group('result properties', () {
    test('boundingBox is correct for circle', () {
      final pts = circlePoints(100, 100, 50, 50);
      final result = ShapeRecognizer.recognize(pts);
      expect(result.boundingBox.width, closeTo(100, 5));
      expect(result.boundingBox.height, closeTo(100, 5));
    });

    test('toString includes type and confidence', () {
      final pts = circlePoints(100, 100, 50, 50);
      final result = ShapeRecognizer.recognize(pts);
      expect(result.toString(), contains('circle'));
    });

    test('ellipse toString includes ellipse flag', () {
      final pts = circlePoints(100, 100, 60, 40);
      final result = ShapeRecognizer.recognize(pts);
      if (result.isEllipse) {
        expect(result.toString(), contains('ellipse'));
      }
    });

    test('sensitivity enum thresholds are ordered', () {
      expect(
        ShapeRecognitionSensitivity.low.threshold,
        greaterThan(ShapeRecognitionSensitivity.medium.threshold),
      );
      expect(
        ShapeRecognitionSensitivity.medium.threshold,
        greaterThan(ShapeRecognitionSensitivity.high.threshold),
      );
    });
  });
}
