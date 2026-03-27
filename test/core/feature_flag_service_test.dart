import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/analytics/feature_flag_service.dart';

void main() {
  late FeatureFlagService service;

  setUp(() {
    service = FeatureFlagService();
  });

  tearDown(() {
    service.dispose();
  });

  // ===========================================================================
  // Define and get flags
  // ===========================================================================

  group('FeatureFlagService - define', () {
    test('defines and retrieves a flag', () {
      service.define(
        const FeatureFlag(
          id: 'dark_mode',
          type: FlagType.boolean,
          defaultValue: true,
        ),
      );
      expect(service.getFlag('dark_mode'), isNotNull);
    });

    test('unknown flag returns null', () {
      expect(service.getFlag('unknown'), isNull);
    });

    test('remove removes flag', () {
      service.define(
        const FeatureFlag(
          id: 'test',
          type: FlagType.boolean,
          defaultValue: false,
        ),
      );
      service.remove('test');
      expect(service.getFlag('test'), isNull);
    });
  });

  // ===========================================================================
  // Evaluate
  // ===========================================================================

  group('FeatureFlagService - evaluate', () {
    test('evaluates to default value', () {
      service.define(
        const FeatureFlag(id: 'f1', type: FlagType.boolean, defaultValue: true),
      );
      expect(service.evaluate('f1'), isTrue);
    });

    test('isEnabled convenience', () {
      service.define(
        const FeatureFlag(id: 'f1', type: FlagType.boolean, defaultValue: true),
      );
      expect(service.isEnabled('f1'), isTrue);
    });

    test('stringValue returns default', () {
      service.define(
        const FeatureFlag(
          id: 's1',
          type: FlagType.string,
          defaultValue: 'hello',
        ),
      );
      expect(service.stringValue('s1'), 'hello');
    });

    test('numberValue returns default', () {
      service.define(
        const FeatureFlag(id: 'n1', type: FlagType.number, defaultValue: 42.0),
      );
      expect(service.numberValue('n1'), 42.0);
    });
  });

  // ===========================================================================
  // Overrides
  // ===========================================================================

  group('FeatureFlagService - overrides', () {
    test('override replaces default', () {
      service.define(
        const FeatureFlag(
          id: 'f1',
          type: FlagType.boolean,
          defaultValue: false,
        ),
      );
      service.setOverride('f1', true);
      expect(service.evaluate('f1'), isTrue);
    });

    test('removeOverride restores default', () {
      service.define(
        const FeatureFlag(
          id: 'f1',
          type: FlagType.boolean,
          defaultValue: false,
        ),
      );
      service.setOverride('f1', true);
      service.removeOverride('f1');
      expect(service.evaluate('f1'), isFalse);
    });
  });

  // ===========================================================================
  // Serialization
  // ===========================================================================

  group('FeatureFlagService - toJson', () {
    test('exports flags as JSON', () {
      service.define(
        const FeatureFlag(id: 'f1', type: FlagType.boolean, defaultValue: true),
      );
      final json = service.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });
  });

  // ===========================================================================
  // Reset
  // ===========================================================================

  group('FeatureFlagService - reset', () {
    test('clears all flags', () {
      service.define(
        const FeatureFlag(id: 'f1', type: FlagType.boolean, defaultValue: true),
      );
      service.reset();
      expect(service.getFlag('f1'), isNull);
    });
  });

  // ===========================================================================
  // FeatureFlag model
  // ===========================================================================

  group('FeatureFlag', () {
    test('toJson serializes', () {
      const flag = FeatureFlag(
        id: 'f1',
        type: FlagType.boolean,
        defaultValue: true,
      );
      final json = flag.toJson();
      expect(json['id'], 'f1');
    });

    test('toString is readable', () {
      const flag = FeatureFlag(
        id: 'f1',
        type: FlagType.boolean,
        defaultValue: false,
      );
      expect(flag.toString(), contains('f1'));
    });
  });
}
