/// 🔤 OPENTYPE FEATURES — OpenType feature flag configuration.
///
/// Maps OpenType feature tags (liga, smcp, tnum, etc.) to Flutter's
/// [FontFeature] API for advanced typographic control.
///
/// ```dart
/// final config = OpenTypeConfig.withPreset(OpenTypePreset.smallCaps);
/// final features = config.toFontFeatures();
/// ```
library;

import 'dart:ui' show FontFeature;

/// A single OpenType feature toggle.
class FeatureTag {
  /// 4-character OpenType tag (e.g. 'liga', 'smcp', 'tnum').
  final String tag;

  /// Whether this feature is enabled.
  final bool enabled;

  /// Human-readable name.
  final String? name;

  const FeatureTag({required this.tag, this.enabled = true, this.name});

  FontFeature toFontFeature() => FontFeature(tag, enabled ? 1 : 0);

  Map<String, dynamic> toJson() => {
    'tag': tag,
    'enabled': enabled,
    if (name != null) 'name': name,
  };

  factory FeatureTag.fromJson(Map<String, dynamic> json) => FeatureTag(
    tag: json['tag'] as String,
    enabled: json['enabled'] as bool? ?? true,
    name: json['name'] as String?,
  );

  @override
  String toString() => 'FeatureTag($tag: ${enabled ? 'on' : 'off'})';
}

/// Preset groups of OpenType features.
enum OpenTypePreset {
  /// Standard ligatures (fi, fl, etc.).
  ligatures,

  /// Small capitals.
  smallCaps,

  /// Tabular (monospaced) figures.
  tabularFigures,

  /// Old-style (text) figures.
  oldStyleFigures,

  /// Stylistic alternates set 1.
  stylisticAlternates,

  /// Fractions.
  fractions,

  /// Ordinals (1st, 2nd).
  ordinals,

  /// Swash variants.
  swash,

  /// All off — disable everything.
  allOff,
}

/// Configuration for OpenType feature flags.
class OpenTypeConfig {
  final List<FeatureTag> features;

  const OpenTypeConfig({this.features = const []});

  /// Create from a preset.
  factory OpenTypeConfig.withPreset(OpenTypePreset preset) {
    switch (preset) {
      case OpenTypePreset.ligatures:
        return const OpenTypeConfig(
          features: [
            FeatureTag(tag: 'liga', name: 'Standard Ligatures'),
            FeatureTag(tag: 'clig', name: 'Contextual Ligatures'),
          ],
        );
      case OpenTypePreset.smallCaps:
        return const OpenTypeConfig(
          features: [FeatureTag(tag: 'smcp', name: 'Small Capitals')],
        );
      case OpenTypePreset.tabularFigures:
        return const OpenTypeConfig(
          features: [FeatureTag(tag: 'tnum', name: 'Tabular Figures')],
        );
      case OpenTypePreset.oldStyleFigures:
        return const OpenTypeConfig(
          features: [FeatureTag(tag: 'onum', name: 'Old-Style Figures')],
        );
      case OpenTypePreset.stylisticAlternates:
        return const OpenTypeConfig(
          features: [
            FeatureTag(tag: 'salt', name: 'Stylistic Alternates'),
            FeatureTag(tag: 'ss01', name: 'Stylistic Set 1'),
          ],
        );
      case OpenTypePreset.fractions:
        return const OpenTypeConfig(
          features: [FeatureTag(tag: 'frac', name: 'Fractions')],
        );
      case OpenTypePreset.ordinals:
        return const OpenTypeConfig(
          features: [FeatureTag(tag: 'ordn', name: 'Ordinals')],
        );
      case OpenTypePreset.swash:
        return const OpenTypeConfig(
          features: [FeatureTag(tag: 'swsh', name: 'Swash')],
        );
      case OpenTypePreset.allOff:
        return const OpenTypeConfig(
          features: [
            FeatureTag(tag: 'liga', enabled: false),
            FeatureTag(tag: 'clig', enabled: false),
            FeatureTag(tag: 'kern', enabled: false),
          ],
        );
    }
  }

  /// Convert to Flutter's font feature list.
  List<FontFeature> toFontFeatures() =>
      features.map((f) => f.toFontFeature()).toList();

  /// Get a feature by tag.
  FeatureTag? feature(String tag) {
    for (final f in features) {
      if (f.tag == tag) return f;
    }
    return null;
  }

  /// Enable or add a feature.
  OpenTypeConfig withFeature(FeatureTag feature) {
    final updated = features.where((f) => f.tag != feature.tag).toList();
    updated.add(feature);
    return OpenTypeConfig(features: updated);
  }

  /// Remove a feature.
  OpenTypeConfig withoutFeature(String tag) =>
      OpenTypeConfig(features: features.where((f) => f.tag != tag).toList());

  /// Merge with another config (other takes priority).
  OpenTypeConfig merge(OpenTypeConfig other) {
    final merged = Map.fromEntries(features.map((f) => MapEntry(f.tag, f)));
    for (final f in other.features) {
      merged[f.tag] = f;
    }
    return OpenTypeConfig(features: merged.values.toList());
  }

  Map<String, dynamic> toJson() => {
    'features': features.map((f) => f.toJson()).toList(),
  };

  factory OpenTypeConfig.fromJson(Map<String, dynamic> json) => OpenTypeConfig(
    features:
        (json['features'] as List<dynamic>? ?? [])
            .map((f) => FeatureTag.fromJson(f as Map<String, dynamic>))
            .toList(),
  );

  @override
  String toString() => 'OpenTypeConfig(${features.length} features)';
}
