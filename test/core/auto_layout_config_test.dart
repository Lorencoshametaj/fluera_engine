import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/layout/auto_layout_config.dart';

void main() {
  // ===========================================================================
  // Enums
  // ===========================================================================

  group('Layout enums', () {
    test('LayoutDirection has horizontal and vertical', () {
      expect(LayoutDirection.values, contains(LayoutDirection.horizontal));
      expect(LayoutDirection.values, contains(LayoutDirection.vertical));
    });

    test('MainAxisAlignment has spaceBetween', () {
      expect(
        MainAxisAlignment.values,
        contains(MainAxisAlignment.spaceBetween),
      );
    });

    test('CrossAxisAlignment has stretch', () {
      expect(CrossAxisAlignment.values, contains(CrossAxisAlignment.stretch));
    });
  });

  // ===========================================================================
  // LayoutEdgeInsets
  // ===========================================================================

  group('LayoutEdgeInsets', () {
    test('all creates uniform insets', () {
      const insets = LayoutEdgeInsets.all(16);
      expect(insets.top, 16);
      expect(insets.right, 16);
      expect(insets.bottom, 16);
      expect(insets.left, 16);
    });

    test('zero creates zero insets', () {
      const insets = LayoutEdgeInsets.zero;
      expect(insets.top, 0);
    });

    test('toJson serializes', () {
      const insets = LayoutEdgeInsets.symmetric(horizontal: 20, vertical: 10);
      final json = insets.toJson();
      expect(json['top'], 10);
      expect(json['left'], 20);
    });

    test('toString is readable', () {
      const insets = LayoutEdgeInsets.all(8);
      expect(insets.toString(), isNotEmpty);
    });
  });

  // ===========================================================================
  // ChildOverride
  // ===========================================================================

  group('ChildOverride', () {
    test('creates with defaults', () {
      const o = ChildOverride();
      expect(o.flexGrow, 0);
    });

    test('toJson serializes', () {
      const o = ChildOverride(flexGrow: 2);
      final json = o.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });
  });

  // ===========================================================================
  // AutoLayoutConfig
  // ===========================================================================

  group('AutoLayoutConfig', () {
    test('default creates vertical layout', () {
      const config = AutoLayoutConfig();
      expect(config.direction, LayoutDirection.vertical);
    });

    test('copyWith overrides direction', () {
      const config = AutoLayoutConfig();
      final vertical = config.copyWith(direction: LayoutDirection.vertical);
      expect(vertical.direction, LayoutDirection.vertical);
    });

    test('copyWith preserves unchanged fields', () {
      const config = AutoLayoutConfig(spacing: 8);
      final copy = config.copyWith(direction: LayoutDirection.vertical);
      expect(copy.spacing, 8);
    });

    test('toJson serializes', () {
      const config = AutoLayoutConfig(spacing: 12);
      final json = config.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });

    test('toString is readable', () {
      const config = AutoLayoutConfig();
      expect(config.toString(), isNotEmpty);
    });
  });
}
