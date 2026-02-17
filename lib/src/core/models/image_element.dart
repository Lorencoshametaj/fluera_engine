import 'dart:ui';
import '../../drawing/models/pro_drawing_point.dart';
import './shape_type.dart';

/// 🖼️ MODELLO ELEMENTO IMMAGINE
/// Represents an image positioned on the canvas with all modifications
class ImageElement {
  final String id;
  final String imagePath; // Path locale of the image
  final String? storageUrl; // URL Cloud Storage (per immagini grandi)
  final String? thumbnailUrl; // URL thumbnail per preview rapida
  final Offset position; // Position on the canvas
  final double scale; // Scala (1.0 = size originale)
  final double rotation; // Rotazione in radianti
  final DateTime createdAt;
  final int pageIndex; // Pagina del PDF a cui appartiene l'immagine

  // ✨ Filtri colore
  final double brightness; // -0.5 a +0.5
  final double contrast; // -0.5 a +0.5
  final double saturation; // -0.5 a +0.5
  final double opacity; // 0.0 a 1.0

  // 🔄 Transformations
  final bool flipHorizontal;
  final bool flipVertical;

  // ✂️ Crop (cropped area, relativa all'immagine originale 0.0-1.0)
  final Rect? cropRect; // null = nessun crop

  // 🎨 Strokes and shapes drawn on top of the image (in editing mode)
  final List<ProStroke> drawingStrokes;
  final List<GeometricShape> drawingShapes;

  const ImageElement({
    required this.id,
    required this.imagePath,
    this.storageUrl,
    this.thumbnailUrl,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
    required this.createdAt,
    required this.pageIndex,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.opacity = 1.0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.cropRect,
    this.drawingStrokes = const [],
    this.drawingShapes = const [],
  });

  /// Creates una copia con modifiche
  ImageElement copyWith({
    String? id,
    String? imagePath,
    String? storageUrl,
    String? thumbnailUrl,
    Offset? position,
    double? scale,
    double? rotation,
    DateTime? createdAt,
    int? pageIndex,
    double? brightness,
    double? contrast,
    double? saturation,
    double? opacity,
    bool? flipHorizontal,
    bool? flipVertical,
    Rect? cropRect,
    bool clearCrop = false,
    List<ProStroke>? drawingStrokes,
    List<GeometricShape>? drawingShapes,
  }) {
    return ImageElement(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      storageUrl: storageUrl ?? this.storageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      createdAt: createdAt ?? this.createdAt,
      pageIndex: pageIndex ?? this.pageIndex,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      opacity: opacity ?? this.opacity,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      cropRect: clearCrop ? null : (cropRect ?? this.cropRect),
      drawingStrokes: drawingStrokes ?? this.drawingStrokes,
      drawingShapes: drawingShapes ?? this.drawingShapes,
    );
  }

  /// Serialize in JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      if (storageUrl != null) 'storageUrl': storageUrl,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      'position': {'dx': position.dx, 'dy': position.dy},
      'scale': scale,
      'rotation': rotation,
      'createdAt': createdAt.toIso8601String(),
      'pageIndex': pageIndex,
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'opacity': opacity,
      'flipHorizontal': flipHorizontal,
      'flipVertical': flipVertical,
      'cropRect':
          cropRect != null
              ? {
                'left': cropRect!.left,
                'top': cropRect!.top,
                'right': cropRect!.right,
                'bottom': cropRect!.bottom,
              }
              : null,
      'drawingStrokes': drawingStrokes.map((s) => s.toJson()).toList(),
      'drawingShapes': drawingShapes.map((s) => s.toJson()).toList(),
    };
  }

  /// Deserializza da JSON
  factory ImageElement.fromJson(Map<String, dynamic> json) {
    Rect? cropRect;
    if (json['cropRect'] != null) {
      final crop = json['cropRect'] as Map<String, dynamic>;
      cropRect = Rect.fromLTRB(
        (crop['left'] as num).toDouble(),
        (crop['top'] as num).toDouble(),
        (crop['right'] as num).toDouble(),
        (crop['bottom'] as num).toDouble(),
      );
    }

    final strokesJson = json['drawingStrokes'] as List<dynamic>? ?? [];
    final strokes = strokesJson.map((s) => ProStroke.fromJson(s)).toList();

    final shapesJson = json['drawingShapes'] as List<dynamic>? ?? [];
    final shapes = shapesJson.map((s) => GeometricShape.fromJson(s)).toList();

    return ImageElement(
      id: json['id'] as String,
      imagePath: json['imagePath'] as String,
      storageUrl: json['storageUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      position: Offset(
        (json['position']['dx'] as num).toDouble(),
        (json['position']['dy'] as num).toDouble(),
      ),
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      flipHorizontal: json['flipHorizontal'] as bool? ?? false,
      flipVertical: json['flipVertical'] as bool? ?? false,
      cropRect: cropRect,
      drawingStrokes: strokes,
      drawingShapes: shapes,
    );
  }

  @override
  String toString() =>
      'ImageElement(id: $id, path: $imagePath, pos: $position, scale: $scale)';
}
