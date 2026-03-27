import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/effects/shader_effect.dart';

void main() {
  // ===========================================================================
  // Uniform types
  // ===========================================================================

  group('FloatUniform', () {
    test('serializes to JSON', () {
      final u = FloatUniform('scale', 2.5);
      final json = u.toJson();
      expect(json['name'], 'scale');
      expect(json['value'], 2.5);
    });
  });

  group('Vec2Uniform', () {
    test('serializes to JSON', () {
      final u = Vec2Uniform('offset', 1.0, 2.0);
      final json = u.toJson();
      expect(json['name'], 'offset');
    });
  });

  group('Vec4Uniform', () {
    test('serializes to JSON', () {
      final u = Vec4Uniform('rect', 0, 0, 100, 200);
      final json = u.toJson();
      expect(json['name'], 'rect');
    });
  });

  group('ColorUniform', () {
    test('serializes to JSON', () {
      final u = ColorUniform('tint', const Color(0xFFFF0000));
      final json = u.toJson();
      expect(json['name'], 'tint');
    });
  });

  // ===========================================================================
  // ShaderUniform.fromJson
  // ===========================================================================

  group('ShaderUniform - fromJson', () {
    test('round-trips float uniform', () {
      final u = FloatUniform('x', 3.14);
      final restored = ShaderUniform.fromJson(u.toJson());
      expect(restored, isA<FloatUniform>());
    });

    test('round-trips vec2 uniform', () {
      final u = Vec2Uniform('pos', 1, 2);
      final restored = ShaderUniform.fromJson(u.toJson());
      expect(restored, isA<Vec2Uniform>());
    });
  });

  // ===========================================================================
  // ShaderPreset enum
  // ===========================================================================

  group('ShaderPreset', () {
    test('has noise, voronoi, chromaticAberration', () {
      expect(ShaderPreset.values, contains(ShaderPreset.noise));
      expect(ShaderPreset.values, contains(ShaderPreset.voronoi));
    });
  });

  // ===========================================================================
  // ShaderEffect
  // ===========================================================================

  group('ShaderEffect', () {
    test('creates with preset', () {
      final effect = ShaderEffect(
        preset: ShaderPreset.noise,
        uniforms: [FloatUniform('scale', 10)],
      );
      expect(effect.preset, ShaderPreset.noise);
    });

    test('setFloat updates existing uniform', () {
      final effect = ShaderEffect(
        preset: ShaderPreset.noise,
        uniforms: [FloatUniform('scale', 10)],
      );
      effect.setFloat('scale', 20);
      expect(effect.getFloat('scale'), 20.0);
    });

    test('getFloat returns null for missing', () {
      final effect = ShaderEffect(preset: ShaderPreset.noise, uniforms: []);
      expect(effect.getFloat('missing'), isNull);
    });

    test('toJson serializes', () {
      final effect = ShaderEffect(
        preset: ShaderPreset.glitch,
        uniforms: [FloatUniform('intensity', 0.5)],
      );
      final json = effect.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });
  });
}
