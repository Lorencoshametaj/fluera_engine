import 'package:flutter/material.dart';

/// 📝 ELEMENTO TESTO DIGITALE
/// Rappresenta un testo inserito tramite tastiera on the canvas
/// With support for:
/// - Positionmento libero
/// - Ridimensionamento (scale)
/// - Selezione e trascinamento
/// - Persistenza e serializzazione
/// - Modalità OCR (testo riconosciuto da handwriting)
class DigitalTextElement {
  final String id;
  final String text;
  final Offset position; // Position on the canvas (coordinate assolute)
  final Color color;
  final double fontSize;
  final FontWeight fontWeight;
  final String fontFamily;
  final double scale; // Fattore di scala per resize (1.0 = normale)
  final bool isOCR; // True if the testo proviene da riconoscimento OCR
  final int?
  pageIndex; // 📄 Indice della pagina PDF a cui appartiene (null per canvas normale)
  final DateTime createdAt;
  final DateTime? modifiedAt;

  const DigitalTextElement({
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

  /// Calculatates bounds del testo (per hit testing)
  Rect getBounds(BuildContext context) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize * scale,
          fontWeight: fontWeight,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    return Rect.fromLTWH(
      position.dx,
      position.dy,
      textPainter.width,
      textPainter.height,
    );
  }

  /// Checks if a point touches this text
  bool containsPoint(Offset point, BuildContext context) {
    return getBounds(context).contains(point);
  }

  /// Serializezione JSON
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

  /// Deserializzazione JSON
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
