import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/systems/opentype_features.dart';
import 'dart:ui' show FontFeature;

void main() {
  group('OpenTypeFeatures Tests', () {
    test('FeatureTag parses and exports correctly', () {
      const tag = FeatureTag(tag: 'smcp', enabled: true);
      expect(tag.toFontFeature().feature, 'smcp');
      expect(tag.toFontFeature().value, 1);

      const offTag = FeatureTag(tag: 'liga', enabled: false);
      expect(offTag.toFontFeature().value, 0);
    });

    test('OpenTypeConfig presets generate correct tags', () {
      final lig = OpenTypeConfig.withPreset(OpenTypePreset.ligatures);
      expect(lig.feature('liga')?.enabled, true);
      expect(lig.feature('clig')?.enabled, true);

      final sc = OpenTypeConfig.withPreset(OpenTypePreset.smallCaps);
      expect(sc.feature('smcp')?.enabled, true);

      final off = OpenTypeConfig.withPreset(OpenTypePreset.allOff);
      expect(off.feature('liga')?.enabled, false);
      expect(off.feature('clig')?.enabled, false);
      expect(off.feature('kern')?.enabled, false);
    });

    test('merge combines configs with priority', () {
      final base = OpenTypeConfig(
        features: [
          const FeatureTag(tag: 'liga', enabled: true),
          const FeatureTag(tag: 'smcp', enabled: false),
        ],
      );

      final override = OpenTypeConfig(
        features: [
          const FeatureTag(tag: 'smcp', enabled: true), // Override
          const FeatureTag(tag: 'tnum', enabled: true), // New
        ],
      );

      final merged = base.merge(override);
      expect(merged.features.length, 3);
      expect(merged.feature('liga')?.enabled, true);
      expect(merged.feature('smcp')?.enabled, true); // Overridden to true
      expect(merged.feature('tnum')?.enabled, true);
    });

    test('withFeature and withoutFeature modify config', () {
      var config = OpenTypeConfig(
        features: [const FeatureTag(tag: 'liga', enabled: true)],
      );

      config = config.withFeature(const FeatureTag(tag: 'smcp', enabled: true));
      expect(config.features.length, 2);

      config = config.withoutFeature('liga');
      expect(config.features.length, 1);
      expect(config.feature('smcp'), isNotNull);
      expect(config.feature('liga'), isNull);
    });

    test('serialization roundtrip', () {
      final config = OpenTypeConfig.withPreset(
        OpenTypePreset.fractions,
      ).withFeature(const FeatureTag(tag: 'tnum', enabled: true));

      final json = config.toJson();
      final restored = OpenTypeConfig.fromJson(json);

      expect(restored.features.length, 2);
      expect(restored.feature('frac')?.enabled, true);
      expect(restored.feature('tnum')?.enabled, true);
    });
  });
}
