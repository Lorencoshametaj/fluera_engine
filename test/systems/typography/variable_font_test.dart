import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/variable_font.dart';
import 'dart:ui' show FontVariation;

void main() {
  group('VariableFontConfig Tests', () {
    test('FontAxis presets return correct tags and bounds', () {
      final weight = FontAxis.weight(600);
      expect(weight.tag, 'wght');
      expect(weight.value, 600);
      expect(weight.min, 100);
      expect(weight.max, 900);

      final italic = FontAxis.italic(1);
      expect(italic.tag, 'ital');
      expect(italic.value, 1);

      final slant = FontAxis.slant(-15);
      expect(slant.tag, 'slnt');
      expect(slant.value, -15);
    });

    test('clampToRange restricts values', () {
      final w =
          FontAxis(tag: 'wght', value: 1200, min: 100, max: 900).clampToRange();
      expect(w.value, 900);

      final w2 =
          FontAxis(tag: 'wght', value: -50, min: 100, max: 900).clampToRange();
      expect(w2.value, 100);
    });

    test('toFontVariations converts config to Flutter format', () {
      final config = VariableFontConfig(
        axes: [FontAxis.weight(700), FontAxis.width(110)],
      );

      final variations = config.toFontVariations();
      expect(variations.length, 2);
      expect(variations[0].axis, 'wght');
      expect(variations[0].value, 700);
      expect(variations[1].axis, 'wdth');
      expect(variations[1].value, 110);
    });

    test('withAxis and withoutAxis modify config immutably', () {
      var config = VariableFontConfig(
        axes: [FontAxis.weight(400), FontAxis.italic(0)],
      );

      // Add/Update
      config = config.withAxis(FontAxis.weight(700)); // Update existing
      config = config.withAxis(FontAxis.opticalSize(14)); // Add new

      expect(config.axes.length, 3);
      expect(config.axis('wght')?.value, 700);
      expect(config.axis('opsz')?.value, 14);

      // Remove
      config = config.withoutAxis('ital');
      expect(config.axes.length, 2);
      expect(config.axis('ital'), isNull);
    });

    test('serialization roundtrip', () {
      final config = VariableFontConfig(
        axes: [FontAxis.weight(800), FontAxis.grade(-50)],
      );

      final json = config.toJson();
      final restored = VariableFontConfig.fromJson(json);

      expect(restored.axes.length, 2);
      expect(restored.axis('wght')?.value, 800);
      expect(restored.axis('GRAD')?.value, -50);
    });
  });
}
