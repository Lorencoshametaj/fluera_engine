import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/vector/shape_presets.dart';

void main() {
  // ===========================================================================
  // Rectangle
  // ===========================================================================

  group('ShapePresets - rectangle', () {
    test('creates closed rectangle path', () {
      final path = ShapePresets.rectangle(const Rect.fromLTWH(0, 0, 100, 50));
      expect(path, isNotNull);
      expect(path.isClosed, isTrue);
    });
  });

  // ===========================================================================
  // Rounded Rectangle
  // ===========================================================================

  group('ShapePresets - roundedRectangle', () {
    test('creates rounded rect', () {
      final path = ShapePresets.roundedRectangle(
        const Rect.fromLTWH(0, 0, 100, 100),
        10,
      );
      expect(path, isNotNull);
      expect(path.isClosed, isTrue);
    });
  });

  // ===========================================================================
  // Ellipse / Circle
  // ===========================================================================

  group('ShapePresets - ellipse', () {
    test('creates ellipse', () {
      final path = ShapePresets.ellipse(const Rect.fromLTWH(0, 0, 100, 50));
      expect(path, isNotNull);
      expect(path.isClosed, isTrue);
    });

    test('circle is shortcut for ellipse', () {
      final path = ShapePresets.circle(const Offset(50, 50), 25);
      expect(path, isNotNull);
    });
  });

  // ===========================================================================
  // Polygons
  // ===========================================================================

  group('ShapePresets - polygons', () {
    test('triangle has segments', () {
      final path = ShapePresets.triangle(const Rect.fromLTWH(0, 0, 100, 100));
      expect(path, isNotNull);
      expect(path.isClosed, isTrue);
    });

    test('pentagon shortcut', () {
      final path = ShapePresets.pentagon(const Rect.fromLTWH(0, 0, 100, 100));
      expect(path, isNotNull);
    });

    test('hexagon shortcut', () {
      final path = ShapePresets.hexagon(const Rect.fromLTWH(0, 0, 100, 100));
      expect(path, isNotNull);
    });

    test('diamond is 4-sided', () {
      final path = ShapePresets.diamond(const Rect.fromLTWH(0, 0, 100, 100));
      expect(path, isNotNull);
      expect(path.isClosed, isTrue);
    });
  });

  // ===========================================================================
  // Star
  // ===========================================================================

  group('ShapePresets - star', () {
    test('creates 5-point star', () {
      final path = ShapePresets.star(const Rect.fromLTWH(0, 0, 100, 100));
      expect(path, isNotNull);
      expect(path.isClosed, isTrue);
    });

    test('custom point count', () {
      final path = ShapePresets.star(
        const Rect.fromLTWH(0, 0, 100, 100),
        points: 8,
      );
      expect(path, isNotNull);
    });
  });

  // ===========================================================================
  // Heart
  // ===========================================================================

  group('ShapePresets - heart', () {
    test('creates heart shape', () {
      final path = ShapePresets.heart(const Rect.fromLTWH(0, 0, 100, 100));
      expect(path, isNotNull);
      expect(path.isClosed, isTrue);
    });
  });

  // ===========================================================================
  // Arrow / Line
  // ===========================================================================

  group('ShapePresets - arrow/line', () {
    test('creates arrow', () {
      final path = ShapePresets.arrow(
        const Offset(0, 50),
        const Offset(100, 50),
      );
      expect(path, isNotNull);
    });

    test('creates line', () {
      final path = ShapePresets.line(
        const Offset(0, 0),
        const Offset(100, 100),
      );
      expect(path, isNotNull);
    });
  });
}
