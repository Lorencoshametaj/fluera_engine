import 'dart:ui' show Color, Rect;
import 'package:flutter/material.dart' show FontWeight;
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:nebula_engine/src/core/scene_graph/node_visitor.dart';
import 'package:nebula_engine/src/systems/engine_theme.dart';

// =============================================================================
// Helpers
// =============================================================================

/// Simple test node with configurable bounds.
class _TestNode extends CanvasNode {
  _TestNode({required super.id});

  @override
  get localBounds => const Rect.fromLTWH(0, 0, 10, 10);

  @override
  Map<String, dynamic> toJson() => {'id': id, 'nodeType': 'test'};

  @override
  R accept<R>(NodeVisitor<R> visitor) =>
      throw UnimplementedError('not needed for tests');
}

void main() {
  // ===========================================================================
  // ColorPalette
  // ===========================================================================

  group('ColorPalette', () {
    test('construction with all fields', () {
      const palette = ColorPalette(
        primary: Color(0xFF0000FF),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFF00FF00),
        onSecondary: Color(0xFF000000),
        accent: Color(0xFFFF0000),
        background: Color(0xFFEEEEEE),
        surface: Color(0xFFDDDDDD),
        onSurface: Color(0xFF111111),
        error: Color(0xFFFF0000),
        onError: Color(0xFFFFFFFF),
      );
      expect(palette.primary, const Color(0xFF0000FF));
      expect(palette.surface, const Color(0xFFDDDDDD));
    });

    test('copyWith overrides specific fields', () {
      const original = ColorPalette(
        primary: Color(0xFF0000FF),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFF00FF00),
        onSecondary: Color(0xFF000000),
        accent: Color(0xFFFF0000),
        background: Color(0xFFEEEEEE),
        surface: Color(0xFFDDDDDD),
        onSurface: Color(0xFF111111),
        error: Color(0xFFFF0000),
        onError: Color(0xFFFFFFFF),
      );
      final modified = original.copyWith(primary: const Color(0xFFAA0000));
      expect(modified.primary, const Color(0xFFAA0000));
      expect(modified.onPrimary, original.onPrimary); // unchanged
    });

    test('lerp interpolates colors at t=0.5', () {
      const a = ColorPalette(
        primary: Color(0xFF000000),
        onPrimary: Color(0xFF000000),
        secondary: Color(0xFF000000),
        onSecondary: Color(0xFF000000),
        accent: Color(0xFF000000),
        background: Color(0xFF000000),
        surface: Color(0xFF000000),
        onSurface: Color(0xFF000000),
        error: Color(0xFF000000),
        onError: Color(0xFF000000),
      );
      const b = ColorPalette(
        primary: Color(0xFFFFFFFF),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFFFFFFFF),
        accent: Color(0xFFFFFFFF),
        background: Color(0xFFFFFFFF),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFFFFFFFF),
        error: Color(0xFFFFFFFF),
        onError: Color(0xFFFFFFFF),
      );
      final result = ColorPalette.lerp(a, b, 0.5);
      // Mid-point between black and white → each channel (R, G, B) should be ~128
      final r = result.primary.red;
      expect(r, closeTo(128, 2));
    });

    test('toJson returns all keys', () {
      const palette = ColorPalette(
        primary: Color(0xFF6750A4),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFF625B71),
        onSecondary: Color(0xFFFFFFFF),
        accent: Color(0xFF7D5260),
        background: Color(0xFFFFFBFE),
        surface: Color(0xFFFFFBFE),
        onSurface: Color(0xFF1C1B1F),
        error: Color(0xFFB3261E),
        onError: Color(0xFFFFFFFF),
      );
      final json = palette.toJson();
      expect(json.keys.length, 10);
      expect(json.containsKey('primary'), isTrue);
      expect(json.containsKey('error'), isTrue);
    });
  });

  // ===========================================================================
  // SpacingScale
  // ===========================================================================

  group('SpacingScale', () {
    test('defaults', () {
      const s = SpacingScale();
      expect(s.xs, 4);
      expect(s.sm, 8);
      expect(s.md, 16);
      expect(s.lg, 24);
      expect(s.xl, 40);
    });

    test('lerp interpolates at t=0.5', () {
      const a = SpacingScale(xs: 0, sm: 0, md: 0, lg: 0, xl: 0);
      const b = SpacingScale(xs: 10, sm: 20, md: 30, lg: 40, xl: 50);
      final result = SpacingScale.lerp(a, b, 0.5);
      expect(result.xs, closeTo(5, 0.1));
      expect(result.md, closeTo(15, 0.1));
      expect(result.xl, closeTo(25, 0.1));
    });
  });

  // ===========================================================================
  // CornerRadii
  // ===========================================================================

  group('CornerRadii', () {
    test('defaults', () {
      const c = CornerRadii();
      expect(c.sm, 4);
      expect(c.md, 8);
      expect(c.lg, 16);
    });

    test('lerp interpolates at t=0', () {
      const a = CornerRadii(sm: 4, md: 8, lg: 16);
      const b = CornerRadii(sm: 12, md: 24, lg: 48);
      final result = CornerRadii.lerp(a, b, 0);
      expect(result.sm, closeTo(4, 0.1));
      expect(result.lg, closeTo(16, 0.1));
    });

    test('lerp interpolates at t=1', () {
      const a = CornerRadii(sm: 4, md: 8, lg: 16);
      const b = CornerRadii(sm: 12, md: 24, lg: 48);
      final result = CornerRadii.lerp(a, b, 1);
      expect(result.sm, closeTo(12, 0.1));
      expect(result.lg, closeTo(48, 0.1));
    });
  });

  // ===========================================================================
  // TypographyScale
  // ===========================================================================

  group('TypographyScale', () {
    test('defaults creates valid scale', () {
      final scale = TypographyScale.defaults();
      expect(scale.heading1.fontSize, 48);
      expect(scale.body.fontSize, 16);
      expect(scale.caption.fontSize, 12);
      expect(scale.heading1.fontFamily, 'Inter');
    });

    test('toJson has all tokens', () {
      final json = TypographyScale.defaults().toJson();
      expect(json.keys.length, 7);
      expect(json.containsKey('heading1'), isTrue);
      expect(json.containsKey('overline'), isTrue);
    });
  });

  // ===========================================================================
  // ShadowToken / ShadowScale
  // ===========================================================================

  group('ShadowToken', () {
    test('toJson serializes all fields', () {
      const shadow = ShadowToken(
        offsetX: 2,
        offsetY: 4,
        blurRadius: 8,
        spreadRadius: 1,
        color: Color(0x33000000),
      );
      final json = shadow.toJson();
      expect(json['offsetX'], 2);
      expect(json['offsetY'], 4);
      expect(json['blurRadius'], 8);
      expect(json['spreadRadius'], 1);
    });
  });

  // ===========================================================================
  // EngineThemeData
  // ===========================================================================

  group('EngineThemeData', () {
    test('light factory creates valid theme', () {
      final theme = EngineThemeData.light();
      expect(theme.id, 'nebula_light');
      expect(theme.name, 'Nebula Light');
      expect(theme.brightness, ThemeBrightness.light);
      expect(theme.colors.primary, const Color(0xFF6750A4));
    });

    test('dark factory creates valid theme', () {
      final theme = EngineThemeData.dark();
      expect(theme.id, 'nebula_dark');
      expect(theme.brightness, ThemeBrightness.dark);
      expect(theme.colors.primary, const Color(0xFFD0BCFF));
    });

    test('copyWith overrides specific fields', () {
      final theme = EngineThemeData.light();
      final modified = theme.copyWith(name: 'Custom');
      expect(modified.name, 'Custom');
      expect(modified.id, theme.id); // unchanged
      expect(modified.colors.primary, theme.colors.primary); // unchanged
    });

    test('lerp at t=0 returns first theme', () {
      final a = EngineThemeData.light();
      final b = EngineThemeData.dark();
      final result = EngineThemeData.lerp(a, b, 0);
      expect(result.id, a.id);
      expect(result.brightness, ThemeBrightness.light);
    });

    test('lerp at t=1 returns second theme', () {
      final a = EngineThemeData.light();
      final b = EngineThemeData.dark();
      final result = EngineThemeData.lerp(a, b, 1);
      expect(result.id, b.id);
      expect(result.brightness, ThemeBrightness.dark);
    });

    test('toJson includes all top-level fields', () {
      final json = EngineThemeData.light().toJson();
      expect(json['id'], 'nebula_light');
      expect(json['name'], 'Nebula Light');
      expect(json['brightness'], 'light');
      expect(json.containsKey('colors'), isTrue);
      expect(json.containsKey('typography'), isTrue);
    });
  });

  // ===========================================================================
  // EngineThemeManager
  // ===========================================================================

  group('EngineThemeManager', () {
    test('is initialized with light theme active', () {
      final manager = EngineThemeManager();
      expect(manager.activeTheme.id, 'nebula_light');
      expect(manager.themeIds, contains('nebula_light'));
      expect(manager.themeIds, contains('nebula_dark'));
    });

    test('setActiveTheme switches theme', () {
      final manager = EngineThemeManager();
      final ok = manager.setActiveTheme('nebula_dark');
      expect(ok, isTrue);
      expect(manager.activeTheme.id, 'nebula_dark');
      expect(manager.activeTheme.brightness, ThemeBrightness.dark);
    });

    test('setActiveTheme returns false for unknown ID', () {
      final manager = EngineThemeManager();
      final ok = manager.setActiveTheme('non_existent');
      expect(ok, isFalse);
      expect(manager.activeTheme.id, 'nebula_light'); // unchanged
    });

    test('registerTheme and getTheme', () {
      final manager = EngineThemeManager();
      final custom = EngineThemeData.light().copyWith(
        id: 'custom1',
        name: 'Custom',
      );
      manager.registerTheme(custom);
      expect(manager.getTheme('custom1'), isNotNull);
      expect(manager.getTheme('custom1')!.name, 'Custom');
    });

    test('removeTheme cannot remove active theme', () {
      final manager = EngineThemeManager();
      expect(manager.removeTheme('nebula_light'), isFalse);
    });

    test('removeTheme removes non-active theme', () {
      final manager = EngineThemeManager();
      final custom = EngineThemeData.light().copyWith(
        id: 'removable',
        name: 'R',
      );
      manager.registerTheme(custom);
      expect(manager.removeTheme('removable'), isTrue);
      expect(manager.getTheme('removable'), isNull);
    });

    test('toggleBrightness switches between light and dark', () {
      final manager = EngineThemeManager();
      expect(manager.activeTheme.brightness, ThemeBrightness.light);
      manager.toggleBrightness();
      expect(manager.activeTheme.brightness, ThemeBrightness.dark);
      manager.toggleBrightness();
      expect(manager.activeTheme.brightness, ThemeBrightness.light);
    });

    test('setOverride and getOverride', () {
      final manager = EngineThemeManager();
      const override = ThemeOverride(corners: CornerRadii(sm: 0, md: 0, lg: 0));
      manager.setOverride('node1', override);
      expect(manager.getOverride('node1'), isNotNull);
      expect(manager.getOverride('node1')!.corners!.sm, 0);
    });

    test('removeOverride', () {
      final manager = EngineThemeManager();
      manager.setOverride('node1', const ThemeOverride());
      manager.removeOverride('node1');
      expect(manager.getOverride('node1'), isNull);
    });

    test('notifies listeners on theme change', () {
      final manager = EngineThemeManager();
      int notifyCount = 0;
      manager.addListener(() => notifyCount++);
      manager.setActiveTheme('nebula_dark');
      expect(notifyCount, 1);
    });
  });

  // ===========================================================================
  // ThemeOverride
  // ===========================================================================

  group('ThemeOverride', () {
    test('default override has all null fields', () {
      const override = ThemeOverride();
      expect(override.colors, isNull);
      expect(override.corners, isNull);
      expect(override.spacing, isNull);
      expect(override.themeId, isNull);
    });
  });

  // ===========================================================================
  // ThemeResolver
  // ===========================================================================

  group('ThemeResolver', () {
    test('resolve returns active theme when no overrides', () {
      final manager = EngineThemeManager();
      final node = _TestNode(id: NodeId('n1'));
      final resolved = manager.resolver.resolve(node);
      expect(resolved.id, 'nebula_light');
    });

    test('resolve applies node-level themeId override', () {
      final manager = EngineThemeManager();
      final node = _TestNode(id: NodeId('n1'));
      manager.setOverride('n1', const ThemeOverride(themeId: 'nebula_dark'));
      final resolved = manager.resolver.resolve(node);
      expect(resolved.id, 'nebula_dark');
    });

    test('resolve applies partial color override', () {
      final manager = EngineThemeManager();
      final node = _TestNode(id: NodeId('n1'));
      final customColors = manager.activeTheme.colors.copyWith(
        primary: const Color(0xFFFF0000),
      );
      manager.setOverride('n1', ThemeOverride(colors: customColors));
      final resolved = manager.resolver.resolve(node);
      expect(resolved.colors.primary, const Color(0xFFFF0000));
    });
  });
}
