/// 🔤 VARIABLE FONT — Variable font axis configuration.
///
/// Maps font variation axes (weight, width, italic, optical size, etc.)
/// to Flutter's [FontVariation] API for dynamic font rendering.
///
/// ```dart
/// final config = VariableFontConfig(axes: [
///   FontAxis.weight(600),
///   FontAxis.width(75),
/// ]);
/// final variations = config.toFontVariations();
/// ```
library;

import 'dart:ui' show FontVariation;

/// A single font variation axis.
class FontAxis {
  /// The 4-character OpenType tag (e.g. 'wght', 'wdth', 'ital').
  final String tag;

  /// Current value on this axis.
  final double value;

  /// Minimum allowed value.
  final double min;

  /// Maximum allowed value.
  final double max;

  /// Human-readable name for this axis.
  final String? name;

  const FontAxis({
    required this.tag,
    required this.value,
    this.min = 0,
    this.max = 1000,
    this.name,
  });

  // -- Common presets ---------------------------------------------------------

  /// Weight axis (100=thin → 900=black).
  factory FontAxis.weight(double value) =>
      FontAxis(tag: 'wght', value: value, min: 100, max: 900, name: 'Weight');

  /// Width axis (50=ultra-condensed → 200=ultra-expanded).
  factory FontAxis.width(double value) =>
      FontAxis(tag: 'wdth', value: value, min: 50, max: 200, name: 'Width');

  /// Italic axis (0=upright, 1=italic).
  factory FontAxis.italic(double value) =>
      FontAxis(tag: 'ital', value: value, min: 0, max: 1, name: 'Italic');

  /// Optical size axis (auto-adjusts to text size).
  factory FontAxis.opticalSize(double value) => FontAxis(
    tag: 'opsz',
    value: value,
    min: 6,
    max: 144,
    name: 'Optical Size',
  );

  /// Slant axis (degrees, 0=upright, negative=backslant).
  factory FontAxis.slant(double value) =>
      FontAxis(tag: 'slnt', value: value, min: -90, max: 90, name: 'Slant');

  /// Grade axis (affects stroke weight without changing width).
  factory FontAxis.grade(double value) =>
      FontAxis(tag: 'GRAD', value: value, min: -200, max: 150, name: 'Grade');

  /// Convert to Flutter's [FontVariation].
  FontVariation toFontVariation() => FontVariation(tag, value);

  /// Clamp value to valid range.
  FontAxis clampToRange() => FontAxis(
    tag: tag,
    value: value.clamp(min, max),
    min: min,
    max: max,
    name: name,
  );

  Map<String, dynamic> toJson() => {
    'tag': tag,
    'value': value,
    'min': min,
    'max': max,
    if (name != null) 'name': name,
  };

  factory FontAxis.fromJson(Map<String, dynamic> json) => FontAxis(
    tag: json['tag'] as String,
    value: (json['value'] as num).toDouble(),
    min: (json['min'] as num?)?.toDouble() ?? 0,
    max: (json['max'] as num?)?.toDouble() ?? 1000,
    name: json['name'] as String?,
  );

  @override
  String toString() => 'FontAxis($tag: $value [$min–$max])';
}

/// Configuration for variable font rendering.
class VariableFontConfig {
  final List<FontAxis> axes;

  const VariableFontConfig({this.axes = const []});

  /// Convert to Flutter's font variation list.
  List<FontVariation> toFontVariations() =>
      axes.map((a) => a.toFontVariation()).toList();

  /// Get a specific axis by tag.
  FontAxis? axis(String tag) {
    for (final a in axes) {
      if (a.tag == tag) return a;
    }
    return null;
  }

  /// Set or update an axis value.
  VariableFontConfig withAxis(FontAxis axis) {
    final updated = axes.where((a) => a.tag != axis.tag).toList();
    updated.add(axis);
    return VariableFontConfig(axes: updated);
  }

  /// Remove an axis by tag.
  VariableFontConfig withoutAxis(String tag) =>
      VariableFontConfig(axes: axes.where((a) => a.tag != tag).toList());

  Map<String, dynamic> toJson() => {
    'axes': axes.map((a) => a.toJson()).toList(),
  };

  factory VariableFontConfig.fromJson(Map<String, dynamic> json) =>
      VariableFontConfig(
        axes:
            (json['axes'] as List<dynamic>? ?? [])
                .map((a) => FontAxis.fromJson(a as Map<String, dynamic>))
                .toList(),
      );

  @override
  String toString() => 'VariableFontConfig(${axes.length} axes)';
}
