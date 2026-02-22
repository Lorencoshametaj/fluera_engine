import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/preferred_values.dart';

void main() {
  group('PreferredValueSet', () {
    final spacingSet = PreferredValueSet(
      id: 'spacing',
      name: 'Spacing Scale',
      property: 'spacing',
      values: [
        PreferredValue(label: 'xs', value: 4),
        PreferredValue(label: 'sm', value: 8),
        PreferredValue(label: 'md', value: 16),
        PreferredValue(label: 'lg', value: 24),
        PreferredValue(label: 'xl', value: 32),
      ],
    );

    test('snapToNearest finds closest', () {
      expect(spacingSet.snapToNearest(15)?.value, 16);
      expect(spacingSet.snapToNearest(0)?.value, 4);
      expect(spacingSet.snapToNearest(100)?.value, 32);
    });

    test('contains checks exact match', () {
      expect(spacingSet.contains(8), isTrue);
      expect(spacingSet.contains(10), isFalse);
    });

    test('labelFor returns label', () {
      expect(spacingSet.labelFor(16), 'md');
      expect(spacingSet.labelFor(10), isNull);
    });

    test('nudgeUp to next value', () {
      expect(spacingSet.nudgeUp(8)?.value, 16);
      expect(spacingSet.nudgeUp(32)?.value, 32); // stays at last
    });

    test('nudgeDown to previous value', () {
      expect(spacingSet.nudgeDown(16)?.value, 8);
      expect(spacingSet.nudgeDown(4)?.value, 4); // stays at first
    });

    test('JSON roundtrip', () {
      final json = spacingSet.toJson();
      final restored = PreferredValueSet.fromJson(json);
      expect(restored.values.length, 5);
      expect(restored.values[2].label, 'md');
    });
  });

  group('PreferredValueRegistry', () {
    late PreferredValueRegistry registry;

    setUp(() {
      registry = PreferredValueRegistry();
      registry.register(
        PreferredValueSet(
          id: 'spacing',
          name: 'Spacing',
          property: 'spacing',
          values: [
            PreferredValue(label: 'sm', value: 8),
            PreferredValue(label: 'md', value: 16),
          ],
        ),
      );
    });

    test('snapToNearest via registry', () {
      expect(registry.snapToNearest('spacing', 13), 16);
    });

    test('nudge up/down via registry', () {
      expect(registry.nudgeUp('spacing', 8), 16);
      expect(registry.nudgeDown('spacing', 16), 8);
    });

    test('isPreferred checks', () {
      expect(registry.isPreferred('spacing', 8), isTrue);
      expect(registry.isPreferred('spacing', 10), isFalse);
      expect(registry.isPreferred('unknown', 8), isFalse);
    });

    test('unregister removes set', () {
      expect(registry.unregister('spacing'), isTrue);
      expect(registry.forProperty('spacing'), isNull);
    });

    test('JSON roundtrip', () {
      final json = registry.toJson();
      final restored = PreferredValueRegistry.fromJson(json);
      expect(restored.forProperty('spacing'), isNotNull);
    });
  });
}
