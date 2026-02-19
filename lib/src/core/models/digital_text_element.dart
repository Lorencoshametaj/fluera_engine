import 'package:flutter/material.dart';

/// 📝 Digital text element on the canvas
///
/// Represents text inserted via keyboard with support for:
/// - Free positioning on canvas (absolute coordinates)
/// - Scaling (resize via handles)
/// - Selection and dragging
/// - JSON persistence and serialization
/// - OCR mode (text recognized from handwriting)
///
/// 🚀 PERFORMANCE: Layout is cached via [layoutPainter]. The TextPainter is
/// created lazily on first access and reused for subsequent calls to
/// [getBounds], [containsPoint], and by [DigitalTextPainter.paint].
/// Since [copyWith] returns a new instance, the cache is automatically
/// invalidated (new instance = null cache fields).
class DigitalTextElement {
  final String id;
  final String text;
  final Offset position;
  final Color color;
  final double fontSize;
  final FontWeight fontWeight;
  final String fontFamily;
  final double scale;
  final bool isOCR;
  final int? pageIndex;
  final DateTime createdAt;
  final DateTime? modifiedAt;

  // ── Layout cache (lazily initialized) ────────────────────────────────────
  TextPainter? _cachedPainter;
  Rect? _cachedBounds;

  DigitalTextElement({
    required this.id,
    required this.text,
    required this.position,
    required this.color,
    this.fontSize = 24.0,
    this.fontWeight = FontWeight.normal,
    this.fontFamily = 'Roboto',
    this.scale = 1.0,
    this.isOCR = false,
    this.pageIndex,
    required this.createdAt,
    this.modifiedAt,
  });

  DigitalTextElement copyWith({
    String? id,
    String? text,
    Offset? position,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    String? fontFamily,
    double? scale,
    bool? isOCR,
    int? pageIndex,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return DigitalTextElement(
      id: id ?? this.id,
      text: text ?? this.text,
      position: position ?? this.position,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      fontFamily: fontFamily ?? this.fontFamily,
      scale: scale ?? this.scale,
      isOCR: isOCR ?? this.isOCR,
      pageIndex: pageIndex ?? this.pageIndex,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  // ── Layout caching ───────────────────────────────────────────────────────

  /// 🚀 Ensure [_cachedPainter] is valid. Creates a TextPainter on first call,
  /// reuses it on subsequent calls for the same instance.
  void _ensureLayout() {
    if (_cachedPainter != null) return;

    _cachedPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize * scale,
          fontWeight: fontWeight,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    )..layout();
  }

  /// 🚀 Cached TextPainter — reused by [DigitalTextPainter.paint] to avoid
  /// per-frame allocation. Lazily created on first access.
  TextPainter get layoutPainter {
    _ensureLayout();
    return _cachedPainter!;
  }

  /// Calculates bounds of the text element (for hit testing and rendering).
  /// Result is cached per instance.
  Rect getBounds() {
    if (_cachedBounds != null) return _cachedBounds!;

    _ensureLayout();
    _cachedBounds = Rect.fromLTWH(
      position.dx,
      position.dy,
      _cachedPainter!.width,
      _cachedPainter!.height,
    );
    return _cachedBounds!;
  }

  /// Checks if a point touches this text element
  bool containsPoint(Offset point) {
    return getBounds().contains(point);
  }

  // ── Serialization ────────────────────────────────────────────────────────

  /// JSON serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'position': {'x': position.dx, 'y': position.dy},
      'color': color.toARGB32(),
      'fontSize': fontSize,
      'fontWeight': fontWeight.index,
      'fontFamily': fontFamily,
      'scale': scale,
      'isOCR': isOCR,
      'pageIndex': pageIndex,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt?.toIso8601String(),
    };
  }

  /// JSON deserialization
  factory DigitalTextElement.fromJson(Map<String, dynamic> json) {
    return DigitalTextElement(
      id: json['id'] as String,
      text: json['text'] as String,
      position: Offset(
        (json['position']['x'] as num).toDouble(),
        (json['position']['y'] as num).toDouble(),
      ),
      color: Color(json['color'] as int),
      fontSize: (json['fontSize'] as num).toDouble(),
      fontWeight: FontWeight.values[json['fontWeight'] as int],
      fontFamily: json['fontFamily'] as String,
      scale: (json['scale'] as num).toDouble(),
      isOCR: json['isOCR'] as bool? ?? false,
      pageIndex: json['pageIndex'] as int?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt:
          json['modifiedAt'] != null
              ? DateTime.parse(json['modifiedAt'] as String)
              : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DigitalTextElement &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'DigitalTextElement(id: $id, text: "$text", pos: $position, scale: $scale)';
}
