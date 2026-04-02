// ============================================================================
// 📐 SECTION SUMMARY — Lightweight section metadata for gallery display
//
// Extracted from SectionNode scene graph data during auto-save.
// Does NOT depend on the scene graph — pure data class for the gallery layer.
// ============================================================================

import 'dart:ui';

/// Lightweight summary of a [SectionNode] for gallery/hub display.
///
/// Created by the storage layer when saving a canvas, by extracting
/// section data from the serialized scene graph JSON. This avoids
/// requiring the gallery to parse the full canvas data.
///
/// ```dart
/// // Typical usage in gallery/hub:
/// final metadata = await storage.listCanvasesWithSections();
/// for (final section in metadata.sections) {
///   print('${section.name}: ${section.width}×${section.height}');
/// }
/// ```
class SectionSummary {
  /// Node ID (from SectionNode.id).
  final String id;

  /// Display name (from SectionNode.sectionName).
  final String name;

  /// World-space position (from SectionNode.worldTransform translation).
  final double x;
  final double y;

  /// Section dimensions in canvas units.
  final double width;
  final double height;

  /// Background color (ARGB int), or null if transparent.
  final int? bgColor;

  /// Background color as a [Color], or transparent if null.
  Color get backgroundColor =>
      bgColor != null ? Color(bgColor!) : const Color(0x00000000);

  /// Preset name (e.g. 'iphone16', 'a4Portrait'), or null for custom sizes.
  final String? preset;

  const SectionSummary({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.bgColor,
    this.preset,
  });

  /// Bounding rectangle in canvas world space.
  Rect get bounds => Rect.fromLTWH(x, y, width, height);

  /// Center point of the section.
  Offset get center => Offset(x + width / 2, y + height / 2);

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    if (bgColor != null) 'bgColor': bgColor,
    if (preset != null) 'preset': preset,
  };

  /// Deserialize from JSON.
  factory SectionSummary.fromJson(Map<String, dynamic> json) {
    return SectionSummary(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Section',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 800,
      height: (json['height'] as num?)?.toDouble() ?? 600,
      bgColor: json['bgColor'] as int?,
      preset: json['preset'] as String?,
    );
  }

  @override
  String toString() => 'SectionSummary($name, ${width.round()}×${height.round()} @ ($x, $y))';
}
