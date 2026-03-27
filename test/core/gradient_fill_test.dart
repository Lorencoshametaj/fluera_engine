import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/effects/gradient_fill.dart';

void main() {
  // ===========================================================================
  // GradientType enum
  // ===========================================================================

  group('GradientType', () {
    test('has linear, radial, conic', () {
      expect(GradientType.values.length, 3);
    });
  });

  // ===========================================================================
  // LinearGradientFill
  // ===========================================================================

  group('LinearGradientFill', () {
    test('creates with colors and stops', () {
      final g = LinearGradientFill(
        colors: [const Color(0xFFFF0000), const Color(0xFF0000FF)],
        stops: [0.0, 1.0],
      );
      expect(g.colors.length, 2);
    });

    test('toShader returns shader', () {
      final g = LinearGradientFill(
        colors: [const Color(0xFFFF0000), const Color(0xFF0000FF)],
        stops: [0.0, 1.0],
      );
      final shader = g.toShader(const Rect.fromLTWH(0, 0, 100, 100));
      expect(shader, isNotNull);
    });

    test('toJson serializes', () {
      final g = LinearGradientFill(
        colors: [const Color(0xFFFF0000), const Color(0xFF00FF00)],
        stops: [0.0, 1.0],
      );
      final json = g.toJson();
      expect(json['type'], 'linear');
    });

    test('copyWith preserves unchanged', () {
      final g = LinearGradientFill(
        colors: [const Color(0xFFFF0000), const Color(0xFF0000FF)],
        stops: [0.0, 1.0],
        begin: const Offset(0, 0),
        end: const Offset(1, 1),
      );
      final copy = g.copyWith(begin: const Offset(0.5, 0));
      expect(copy.end, const Offset(1, 1));
    });
  });

  // ===========================================================================
  // RadialGradientFill
  // ===========================================================================

  group('RadialGradientFill', () {
    test('creates with center and radius', () {
      final g = RadialGradientFill(
        colors: [const Color(0xFFFF0000), const Color(0xFF0000FF)],
        stops: [0.0, 1.0],
        center: const Offset(0.5, 0.5),
        radius: 0.5,
      );
      expect(g.radius, 0.5);
    });

    test('toShader returns shader', () {
      final g = RadialGradientFill(
        colors: [const Color(0xFFFFFFFF), const Color(0xFF000000)],
        stops: [0.0, 1.0],
      );
      final shader = g.toShader(const Rect.fromLTWH(0, 0, 100, 100));
      expect(shader, isNotNull);
    });

    test('toJson serializes', () {
      final g = RadialGradientFill(
        colors: [const Color(0xFFFF0000), const Color(0xFF000000)],
        stops: [0.0, 1.0],
      );
      final json = g.toJson();
      expect(json['type'], 'radial');
    });
  });

  // ===========================================================================
  // ConicGradientFill
  // ===========================================================================

  group('ConicGradientFill', () {
    test('creates with start angle', () {
      final g = ConicGradientFill(
        colors: [const Color(0xFFFF0000), const Color(0xFF00FF00)],
        stops: [0.0, 1.0],
        startAngle: 0.0,
      );
      expect(g.startAngle, 0.0);
    });

    test('toShader returns shader', () {
      final g = ConicGradientFill(
        colors: [const Color(0xFFFF0000), const Color(0xFF0000FF)],
        stops: [0.0, 1.0],
      );
      final shader = g.toShader(const Rect.fromLTWH(0, 0, 100, 100));
      expect(shader, isNotNull);
    });

    test('toJson serializes', () {
      final g = ConicGradientFill(
        colors: [const Color(0xFFFF0000), const Color(0xFF000000)],
        stops: [0.0, 1.0],
      );
      final json = g.toJson();
      expect(json['type'], 'conic');
    });
  });

  // ===========================================================================
  // GradientFill.fromJson
  // ===========================================================================

  group('GradientFill - fromJson', () {
    test('round-trips linear gradient', () {
      final g = LinearGradientFill(
        colors: [const Color(0xFFFF0000), const Color(0xFF0000FF)],
        stops: [0.0, 1.0],
      );
      final json = g.toJson();
      final restored = GradientFill.fromJson(json);
      expect(restored, isA<LinearGradientFill>());
    });
  });
}
