import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/drawing/models/brush_preset.dart';
import 'package:fluera_engine/src/drawing/models/pro_brush_settings.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';

void main() {
  // ===========================================================================
  // BrushPreset — construction
  // ===========================================================================

  group('BrushPreset - construction', () {
    test('creates with required fields', () {
      final preset = BrushPreset(
        id: 'test_1',
        name: 'Test Brush',
        icon: '✏️',
        penType: ProPenType.fountain,
        baseWidth: 3.0,
        color: const Color(0xFF000000),
        settings: const ProBrushSettings(),
        category: BrushCategory.writing,
      );
      expect(preset.id, 'test_1');
      expect(preset.name, 'Test Brush');
      expect(preset.penType, ProPenType.fountain);
      expect(preset.baseWidth, 3.0);
      expect(preset.category, BrushCategory.writing);
      expect(preset.isBuiltIn, isFalse);
    });
  });

  // ===========================================================================
  // BrushPreset — copyWith
  // ===========================================================================

  group('BrushPreset - copyWith', () {
    test('copies with changed name', () {
      final original = BrushPreset(
        id: 'p1',
        name: 'Original',
        icon: '🖊️',
        penType: ProPenType.pencil,
        baseWidth: 2.0,
        color: const Color(0xFF0000FF),
        settings: const ProBrushSettings(),
        category: BrushCategory.artistic,
      );
      final copy = original.copyWith(name: 'Copied');
      expect(copy.name, 'Copied');
      expect(copy.id, 'p1');
      expect(copy.penType, ProPenType.pencil);
      expect(copy.baseWidth, 2.0);
    });

    test('copies with changed baseWidth and color', () {
      final original = BrushPreset(
        id: 'p2',
        name: 'Thick',
        icon: '🖌️',
        penType: ProPenType.marker,
        baseWidth: 5.0,
        color: const Color(0xFFFF0000),
        settings: const ProBrushSettings(),
      );
      final copy = original.copyWith(
        baseWidth: 10.0,
        color: const Color(0xFF00FF00),
      );
      expect(copy.baseWidth, 10.0);
      expect(copy.color, const Color(0xFF00FF00));
      expect(copy.name, 'Thick');
    });

    test('copies with changed category', () {
      final original = BrushPreset(
        id: 'p3',
        name: 'Switch',
        icon: '💧',
        penType: ProPenType.watercolor,
        baseWidth: 12.0,
        color: const Color(0xFF2196F3),
        settings: const ProBrushSettings(),
        category: BrushCategory.writing,
      );
      final copy = original.copyWith(category: BrushCategory.artistic);
      expect(copy.category, BrushCategory.artistic);
    });
  });

  // ===========================================================================
  // BrushPreset — serialization
  // ===========================================================================

  group('BrushPreset - serialization', () {
    test('toJson produces expected keys', () {
      final preset = BrushPreset(
        id: 'serial_1',
        name: 'Serializable',
        icon: '🖋️',
        penType: ProPenType.fountain,
        baseWidth: 4.0,
        color: const Color(0xFF800080),
        settings: const ProBrushSettings(fountainThinning: 0.7),
      );
      final json = preset.toJson();
      expect(json['id'], 'serial_1');
      expect(json['name'], 'Serializable');
      expect(json['penType'], ProPenType.fountain.index);
      expect(json['baseWidth'], 4.0);
    });

    test('fromJson round-trips correctly', () {
      final original = BrushPreset(
        id: 'rt_1',
        name: 'Round Trip',
        icon: '✏️',
        penType: ProPenType.pencil,
        baseWidth: 2.5,
        color: const Color(0xFF112233),
        settings: const ProBrushSettings(),
      );
      final json = original.toJson();
      final restored = BrushPreset.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.penType, original.penType);
      expect(restored.baseWidth, original.baseWidth);
    });
  });

  // ===========================================================================
  // BrushPreset — built-in presets
  // ===========================================================================

  group('BrushPreset - builtInPresets', () {
    test('has 13 built-in presets', () {
      expect(BrushPreset.builtInPresets.length, 13);
    });

    test('all built-in presets have isBuiltIn = true', () {
      for (final preset in BrushPreset.builtInPresets) {
        expect(
          preset.isBuiltIn,
          isTrue,
          reason: '${preset.name} should be built-in',
        );
      }
    });

    test('writingPresets filters to writing category', () {
      final writing = BrushPreset.writingPresets;
      expect(writing, isNotEmpty);
      for (final p in writing) {
        expect(p.category, BrushCategory.writing);
      }
    });

    test('artisticPresets filters to artistic category', () {
      final artistic = BrushPreset.artisticPresets;
      expect(artistic, isNotEmpty);
      for (final p in artistic) {
        expect(p.category, BrushCategory.artistic);
      }
    });

    test('writing + artistic cover all presets', () {
      final total =
          BrushPreset.writingPresets.length +
          BrushPreset.artisticPresets.length;
      expect(total, BrushPreset.builtInPresets.length);
    });
  });

  // ===========================================================================
  // BrushPreset — equality
  // ===========================================================================

  group('BrushPreset - equality', () {
    test('equal by id, name, icon', () {
      final a = BrushPreset(
        id: 'eq1',
        name: 'Same',
        icon: '✏️',
        penType: ProPenType.fountain,
        baseWidth: 3.0,
        color: const Color(0xFF000000),
        settings: const ProBrushSettings(),
      );
      final b = BrushPreset(
        id: 'eq1',
        name: 'Same',
        icon: '✏️',
        penType: ProPenType.ballpoint, // Different pen type
        baseWidth: 10.0,
        color: const Color(0xFFFF0000),
        settings: const ProBrushSettings(),
      );
      expect(a, equals(b)); // Equality only checks id, name, icon
    });

    test('different id → not equal', () {
      final a = BrushPreset(
        id: 'a',
        name: 'Same',
        icon: '✏️',
        penType: ProPenType.fountain,
        baseWidth: 3.0,
        color: const Color(0xFF000000),
        settings: const ProBrushSettings(),
      );
      final b = BrushPreset(
        id: 'b',
        name: 'Same',
        icon: '✏️',
        penType: ProPenType.fountain,
        baseWidth: 3.0,
        color: const Color(0xFF000000),
        settings: const ProBrushSettings(),
      );
      expect(a, isNot(equals(b)));
    });
  });
}
