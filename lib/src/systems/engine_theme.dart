import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart' show FontWeight;

import '../core/engine_event.dart';
import '../core/engine_event_bus.dart';
import '../core/scene_graph/canvas_node.dart';
import 'style_system.dart';

// =============================================================================
// Color Palette
// =============================================================================

/// A complete color palette for theming.
///
/// Contains semantic color slots used across the entire canvas:
///
/// ```dart
/// final palette = ColorPalette(
///   primary: Color(0xFF6750A4),
///   onPrimary: Color(0xFFFFFFFF),
///   // ...
/// );
/// ```
class ColorPalette {
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color onSurface;
  final Color error;
  final Color onError;

  const ColorPalette({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.error,
    required this.onError,
  });

  /// Linearly interpolate between two palettes.
  static ColorPalette lerp(ColorPalette a, ColorPalette b, double t) {
    return ColorPalette(
      primary: Color.lerp(a.primary, b.primary, t)!,
      onPrimary: Color.lerp(a.onPrimary, b.onPrimary, t)!,
      secondary: Color.lerp(a.secondary, b.secondary, t)!,
      onSecondary: Color.lerp(a.onSecondary, b.onSecondary, t)!,
      accent: Color.lerp(a.accent, b.accent, t)!,
      background: Color.lerp(a.background, b.background, t)!,
      surface: Color.lerp(a.surface, b.surface, t)!,
      onSurface: Color.lerp(a.onSurface, b.onSurface, t)!,
      error: Color.lerp(a.error, b.error, t)!,
      onError: Color.lerp(a.onError, b.onError, t)!,
    );
  }

  ColorPalette copyWith({
    Color? primary,
    Color? onPrimary,
    Color? secondary,
    Color? onSecondary,
    Color? accent,
    Color? background,
    Color? surface,
    Color? onSurface,
    Color? error,
    Color? onError,
  }) {
    return ColorPalette(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      accent: accent ?? this.accent,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      onSurface: onSurface ?? this.onSurface,
      error: error ?? this.error,
      onError: onError ?? this.onError,
    );
  }

  Map<String, int> toJson() => {
    'primary': primary.toARGB32(),
    'onPrimary': onPrimary.toARGB32(),
    'secondary': secondary.toARGB32(),
    'onSecondary': onSecondary.toARGB32(),
    'accent': accent.toARGB32(),
    'background': background.toARGB32(),
    'surface': surface.toARGB32(),
    'onSurface': onSurface.toARGB32(),
    'error': error.toARGB32(),
    'onError': onError.toARGB32(),
  };
}

// =============================================================================
// Typography Scale
// =============================================================================

/// A complete typography scale for the design system.
class TypographyScale {
  final TypographyToken heading1;
  final TypographyToken heading2;
  final TypographyToken heading3;
  final TypographyToken heading4;
  final TypographyToken body;
  final TypographyToken caption;
  final TypographyToken overline;

  const TypographyScale({
    required this.heading1,
    required this.heading2,
    required this.heading3,
    required this.heading4,
    required this.body,
    required this.caption,
    required this.overline,
  });

  /// Default typography scale using Inter.
  factory TypographyScale.defaults() => TypographyScale(
    heading1: TypographyToken(
      name: 'heading1',
      fontFamily: 'Inter',
      fontSize: 48,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      lineHeight: 1.2,
    ),
    heading2: TypographyToken(
      name: 'heading2',
      fontFamily: 'Inter',
      fontSize: 36,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.25,
      lineHeight: 1.25,
    ),
    heading3: TypographyToken(
      name: 'heading3',
      fontFamily: 'Inter',
      fontSize: 28,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      lineHeight: 1.3,
    ),
    heading4: TypographyToken(
      name: 'heading4',
      fontFamily: 'Inter',
      fontSize: 22,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
      lineHeight: 1.35,
    ),
    body: TypographyToken(
      name: 'body',
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.15,
      lineHeight: 1.5,
    ),
    caption: TypographyToken(
      name: 'caption',
      fontFamily: 'Inter',
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
      lineHeight: 1.4,
    ),
    overline: TypographyToken(
      name: 'overline',
      fontFamily: 'Inter',
      fontSize: 10,
      fontWeight: FontWeight.w500,
      letterSpacing: 1.5,
      lineHeight: 1.6,
    ),
  );

  Map<String, dynamic> toJson() => {
    'heading1': heading1.toJson(),
    'heading2': heading2.toJson(),
    'heading3': heading3.toJson(),
    'heading4': heading4.toJson(),
    'body': body.toJson(),
    'caption': caption.toJson(),
    'overline': overline.toJson(),
  };
}

// =============================================================================
// Spacing Scale & Corner Radii
// =============================================================================

/// Spacing scale for consistent whitespace.
class SpacingScale {
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;

  const SpacingScale({
    this.xs = 4,
    this.sm = 8,
    this.md = 16,
    this.lg = 24,
    this.xl = 40,
  });

  static SpacingScale lerp(SpacingScale a, SpacingScale b, double t) {
    return SpacingScale(
      xs: a.xs + (b.xs - a.xs) * t,
      sm: a.sm + (b.sm - a.sm) * t,
      md: a.md + (b.md - a.md) * t,
      lg: a.lg + (b.lg - a.lg) * t,
      xl: a.xl + (b.xl - a.xl) * t,
    );
  }
}

/// Corner radii for consistent rounding.
class CornerRadii {
  final double sm;
  final double md;
  final double lg;

  const CornerRadii({this.sm = 4, this.md = 8, this.lg = 16});

  static CornerRadii lerp(CornerRadii a, CornerRadii b, double t) {
    return CornerRadii(
      sm: a.sm + (b.sm - a.sm) * t,
      md: a.md + (b.md - a.md) * t,
      lg: a.lg + (b.lg - a.lg) * t,
    );
  }
}

/// Shadow definition for the design system.
class ShadowToken {
  final double offsetX;
  final double offsetY;
  final double blurRadius;
  final double spreadRadius;
  final Color color;

  const ShadowToken({
    this.offsetX = 0,
    this.offsetY = 2,
    this.blurRadius = 4,
    this.spreadRadius = 0,
    this.color = const Color(0x33000000),
  });

  Map<String, dynamic> toJson() => {
    'offsetX': offsetX,
    'offsetY': offsetY,
    'blurRadius': blurRadius,
    'spreadRadius': spreadRadius,
    'color': color.toARGB32(),
  };
}

/// Shadow scale (small, medium, large).
class ShadowScale {
  final ShadowToken sm;
  final ShadowToken md;
  final ShadowToken lg;

  const ShadowScale({
    this.sm = const ShadowToken(offsetY: 1, blurRadius: 2),
    this.md = const ShadowToken(offsetY: 4, blurRadius: 8),
    this.lg = const ShadowToken(offsetY: 8, blurRadius: 24, spreadRadius: 2),
  });
}

// =============================================================================
// Theme Brightness
// =============================================================================

/// Whether the theme is light or dark.
enum ThemeBrightness { light, dark }

// =============================================================================
// Engine Theme Data
// =============================================================================

/// Immutable theme definition for the entire engine.
///
/// ```dart
/// final theme = EngineThemeData.light();
/// final dark = EngineThemeData.dark();
/// final custom = theme.copyWith(
///   colors: theme.colors.copyWith(primary: Color(0xFFFF5722)),
/// );
/// ```
class EngineThemeData {
  final String id;
  final String name;
  final ThemeBrightness brightness;
  final ColorPalette colors;
  final TypographyScale typography;
  final SpacingScale spacing;
  final CornerRadii corners;
  final ShadowScale shadows;

  const EngineThemeData({
    required this.id,
    required this.name,
    this.brightness = ThemeBrightness.light,
    required this.colors,
    required this.typography,
    required this.spacing,
    required this.corners,
    required this.shadows,
  });

  /// Material Design 3 inspired light theme.
  factory EngineThemeData.light() => EngineThemeData(
    id: 'nebula_light',
    name: 'Nebula Light',
    brightness: ThemeBrightness.light,
    colors: const ColorPalette(
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
    ),
    typography: TypographyScale.defaults(),
    spacing: const SpacingScale(),
    corners: const CornerRadii(),
    shadows: const ShadowScale(),
  );

  /// Material Design 3 inspired dark theme.
  factory EngineThemeData.dark() => EngineThemeData(
    id: 'nebula_dark',
    name: 'Nebula Dark',
    brightness: ThemeBrightness.dark,
    colors: const ColorPalette(
      primary: Color(0xFFD0BCFF),
      onPrimary: Color(0xFF381E72),
      secondary: Color(0xFFCCC2DC),
      onSecondary: Color(0xFF332D41),
      accent: Color(0xFFEFB8C8),
      background: Color(0xFF1C1B1F),
      surface: Color(0xFF1C1B1F),
      onSurface: Color(0xFFE6E1E5),
      error: Color(0xFFF2B8B5),
      onError: Color(0xFF601410),
    ),
    typography: TypographyScale.defaults(),
    spacing: const SpacingScale(),
    corners: const CornerRadii(),
    shadows: const ShadowScale(
      sm: ShadowToken(offsetY: 1, blurRadius: 3, color: Color(0x66000000)),
      md: ShadowToken(offsetY: 4, blurRadius: 10, color: Color(0x66000000)),
      lg: ShadowToken(
        offsetY: 8,
        blurRadius: 28,
        spreadRadius: 4,
        color: Color(0x80000000),
      ),
    ),
  );

  /// Linearly interpolate between two themes (for animated transitions).
  static EngineThemeData lerp(EngineThemeData a, EngineThemeData b, double t) {
    return EngineThemeData(
      id: t < 0.5 ? a.id : b.id,
      name: t < 0.5 ? a.name : b.name,
      brightness: t < 0.5 ? a.brightness : b.brightness,
      colors: ColorPalette.lerp(a.colors, b.colors, t),
      typography: t < 0.5 ? a.typography : b.typography,
      spacing: SpacingScale.lerp(a.spacing, b.spacing, t),
      corners: CornerRadii.lerp(a.corners, b.corners, t),
      shadows: t < 0.5 ? a.shadows : b.shadows,
    );
  }

  EngineThemeData copyWith({
    String? id,
    String? name,
    ThemeBrightness? brightness,
    ColorPalette? colors,
    TypographyScale? typography,
    SpacingScale? spacing,
    CornerRadii? corners,
    ShadowScale? shadows,
  }) {
    return EngineThemeData(
      id: id ?? this.id,
      name: name ?? this.name,
      brightness: brightness ?? this.brightness,
      colors: colors ?? this.colors,
      typography: typography ?? this.typography,
      spacing: spacing ?? this.spacing,
      corners: corners ?? this.corners,
      shadows: shadows ?? this.shadows,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'brightness': brightness.name,
    'colors': colors.toJson(),
    'typography': typography.toJson(),
  };
}

// =============================================================================
// Theme Override (per-node or per-group)
// =============================================================================

/// A partial theme override attached to a node or group.
///
/// Only non-null fields replace the parent theme — everything else
/// falls through to the inherited theme.
class ThemeOverride {
  /// Override color palette (partial — use [ColorPalette.copyWith]).
  final ColorPalette? colors;

  /// Override corner radii.
  final CornerRadii? corners;

  /// Override spacing scale.
  final SpacingScale? spacing;

  /// ID of a registered theme to use instead of inheriting.
  final String? themeId;

  const ThemeOverride({this.colors, this.corners, this.spacing, this.themeId});
}

// =============================================================================
// Theme Resolver
// =============================================================================

/// Resolves the effective theme for a given node by walking up the scene tree.
///
/// Resolution order:
/// 1. Node-level [ThemeOverride] (if set via [EngineThemeManager.setOverride])
/// 2. Nearest ancestor [GroupNode] with a [ThemeOverride]
/// 3. Global active theme from [EngineThemeManager]
class ThemeResolver {
  final EngineThemeManager _manager;

  ThemeResolver(this._manager);

  /// Resolve the effective theme for [node].
  EngineThemeData resolve(CanvasNode node) {
    // Check node-level override.
    final nodeOverride = _manager.getOverride(node.id);
    if (nodeOverride?.themeId != null) {
      final explicit = _manager.getTheme(nodeOverride!.themeId!);
      if (explicit != null) return explicit;
    }

    // Walk up to parent groups.
    CanvasNode? current = node.parent;
    while (current != null) {
      final override = _manager.getOverride(current.id);
      if (override?.themeId != null) {
        final explicit = _manager.getTheme(override!.themeId!);
        if (explicit != null) return _applyOverrides(explicit, nodeOverride);
      }
      current = current.parent;
    }

    // Fall back to active global theme.
    return _applyOverrides(_manager.activeTheme, nodeOverride);
  }

  /// Apply node-level overrides on top of a base theme.
  EngineThemeData _applyOverrides(
    EngineThemeData base,
    ThemeOverride? override,
  ) {
    if (override == null) return base;
    return base.copyWith(
      colors: override.colors ?? base.colors,
      corners: override.corners ?? base.corners,
      spacing: override.spacing ?? base.spacing,
    );
  }
}

// =============================================================================
// Engine Theme Manager
// =============================================================================

/// Manages registered themes, active theme selection, and change notifications.
///
/// ```dart
/// final manager = EngineThemeManager(eventBus: scope.eventBus);
/// manager.registerTheme(EngineThemeData.light());
/// manager.registerTheme(EngineThemeData.dark());
/// manager.setActiveTheme('nebula_dark'); // fires theme changed event
/// ```
class EngineThemeManager extends ChangeNotifier {
  final EngineEventBus? _eventBus;

  /// Registered themes by ID.
  final Map<String, EngineThemeData> _themes = {};

  /// Per-node theme overrides, keyed by node ID.
  final Map<String, ThemeOverride> _overrides = {};

  /// The currently active theme.
  EngineThemeData _active;

  /// Theme resolver for node-level resolution.
  late final ThemeResolver resolver = ThemeResolver(this);

  EngineThemeManager({EngineEventBus? eventBus})
    : _eventBus = eventBus,
      _active = EngineThemeData.light() {
    // Pre-register default themes.
    _themes[_active.id] = _active;
    _themes['nebula_dark'] = EngineThemeData.dark();
  }

  /// The currently active theme.
  EngineThemeData get activeTheme => _active;

  /// All registered theme IDs.
  Iterable<String> get themeIds => _themes.keys;

  /// Get a theme by ID, or null if not registered.
  EngineThemeData? getTheme(String id) => _themes[id];

  /// Register a theme (or replace an existing one).
  void registerTheme(EngineThemeData theme) {
    _themes[theme.id] = theme;
  }

  /// Remove a registered theme. Cannot remove the active theme.
  bool removeTheme(String id) {
    if (id == _active.id) return false;
    return _themes.remove(id) != null;
  }

  // ---------------------------------------------------------------------------
  // Per-node overrides
  // ---------------------------------------------------------------------------

  /// Set a theme override for a specific node.
  void setOverride(String nodeId, ThemeOverride override) {
    _overrides[nodeId] = override;
  }

  /// Get the theme override for a node, or null.
  ThemeOverride? getOverride(String nodeId) => _overrides[nodeId];

  /// Remove a node's theme override.
  void removeOverride(String nodeId) => _overrides.remove(nodeId);

  /// Switch the active theme.
  ///
  /// Fires [ThemeChangedEngineEvent] and notifies listeners.
  /// Returns `false` if the theme ID is not registered.
  bool setActiveTheme(String themeId) {
    final theme = _themes[themeId];
    if (theme == null) return false;
    if (theme.id == _active.id) return true; // already active

    final old = _active;
    _active = theme;

    _eventBus?.emit(ThemeChangedEngineEvent(oldTheme: old, newTheme: theme));

    notifyListeners();
    return true;
  }

  /// Toggle between light and dark themes.
  void toggleBrightness() {
    if (_active.brightness == ThemeBrightness.light) {
      setActiveTheme('nebula_dark');
    } else {
      setActiveTheme('nebula_light');
    }
  }
}

// =============================================================================
// Theme Engine Event
// =============================================================================

/// Emitted when the active theme changes.
class ThemeChangedEngineEvent extends EngineEvent {
  final EngineThemeData oldTheme;
  final EngineThemeData newTheme;

  ThemeChangedEngineEvent({required this.oldTheme, required this.newTheme})
    : super(source: 'EngineThemeManager', domain: EventDomain.custom);
}
