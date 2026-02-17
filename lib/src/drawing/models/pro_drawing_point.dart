import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import './pro_brush_settings.dart';

/// Punto di disegno professionale con metadati completi
class ProDrawingPoint {
  final Offset position;
  final double pressure;
  final double tiltX;
  final double tiltY;
  final double orientation;
  final int timestamp;

  const ProDrawingPoint({
    required this.position,
    required this.pressure,
    this.tiltX = 0.0,
    this.tiltY = 0.0,
    this.orientation = 0.0,
    required this.timestamp,
  });

  /// Getter per compatibility con OptimizedPathBuilder
  Offset get offset => position;

  /// Serialize con precisione ottimizzata per storage
  ///
  /// 🚀 OTTIMIZZAZIONE v2: 4 decimali per coordinate (era 2)
  /// - Coordinate: 0.0001px → preserva curve Catmull-Rom smooth
  /// - Pressione: 0.01 (2 decimali sufficienti per 100 livelli)
  /// - Tilt/Orientation: 2 decimals (adequate angular precision)
  ///
  /// 🎯 FIX: 2 decimali causavano curve grezze dopo load because
  /// le piccole differenze tra punti adiacenti venivano quantizzate,
  /// corrompendo i control points del Catmull-Rom spline.
  Map<String, dynamic> toJson() => {
    'x': _round4(position.dx),
    'y': _round4(position.dy),
    'pressure': _round2(pressure),
    // Ometti tilt/orientation se sono 0 (default) per risparmiare spazio
    if (tiltX != 0.0) 'tiltX': _round2(tiltX),
    if (tiltY != 0.0) 'tiltY': _round2(tiltY),
    if (orientation != 0.0) 'orientation': _round2(orientation),
    'timestamp': timestamp,
  };

  /// Arrotonda a 4 decimali (per coordinate — preserva smoothness)
  static double _round4(double value) =>
      (value * 10000).roundToDouble() / 10000;

  /// Arrotonda a 2 decimali (per pressione, tilt, orientation)
  static double _round2(double value) => (value * 100).roundToDouble() / 100;

  factory ProDrawingPoint.fromJson(Map<String, dynamic> json) =>
      ProDrawingPoint(
        position: Offset(
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
        ),
        pressure: (json['pressure'] as num).toDouble(),
        tiltX: (json['tiltX'] as num?)?.toDouble() ?? 0.0,
        tiltY: (json['tiltY'] as num?)?.toDouble() ?? 0.0,
        orientation: (json['orientation'] as num?)?.toDouble() ?? 0.0,
        timestamp: json['timestamp'] as int,
      );

  ProDrawingPoint copyWith({
    Offset? position,
    double? pressure,
    double? tiltX,
    double? tiltY,
    double? orientation,
    int? timestamp,
  }) {
    return ProDrawingPoint(
      position: position ?? this.position,
      pressure: pressure ?? this.pressure,
      tiltX: tiltX ?? this.tiltX,
      tiltY: tiltY ?? this.tiltY,
      orientation: orientation ?? this.orientation,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Complete professional stroke
class ProStroke {
  final String id;
  final List<ProDrawingPoint> points;
  final Color color;
  final double baseWidth;
  final ProPenType penType;
  final DateTime createdAt;
  final ProBrushSettings settings; // 🎛️ Parametri pennello personalizzati

  /// 🛡️ Engine version che ha prodotto questo stroke.
  /// Permette migration/fallback se l'algoritmo di un brush cambia.
  /// - v1: strokes without tag (pre-versioning, backward compatible)
  /// - v2: first tagged version (current)
  /// Incrementare when modifica il comportamento di un brush.
  final int engineVersion;

  /// Current rendering engine version
  static const int currentEngineVersion = 2;

  /// 🪣 Fill overlay — transient raster image (not serialized)
  /// Stored in canvas-space coordinates; rendered at fillBounds position
  ui.Image? fillOverlay;
  Rect? fillBounds;

  /// True if this stroke is a fill operation (has raster overlay)
  bool get isFill => fillOverlay != null && fillBounds != null;

  /// Dispose fill overlay image to free GPU memory
  void disposeFillOverlay() {
    fillOverlay?.dispose();
    fillOverlay = null;
    fillBounds = null;
  }

  /// 🚀 CACHED BOUNDS - Calculateto una sola volta for performance O(1)
  /// Evita ricalcolo O(n) ad every frame durante viewport culling
  Rect? _cachedBounds;

  ProStroke({
    required this.id,
    required List<ProDrawingPoint> points,
    required this.color,
    required this.baseWidth,
    required this.penType,
    required this.createdAt,
    ProBrushSettings? settings,
    int? engineVersion,
    this.fillOverlay,
    this.fillBounds,
  }) : points = List.unmodifiable(points),
       settings = settings ?? const ProBrushSettings(),
       engineVersion = engineVersion ?? currentEngineVersion;

  /// 🚀 Bounds cachato - calcola una volta e riusa
  /// Performance: da O(n) every frame a O(1) dopo primo calcolo
  Rect get bounds {
    _cachedBounds ??= _calculateBounds();
    return _cachedBounds!;
  }

  /// Calculatates bounds of the stroke (chiamato una sola volta)
  Rect _calculateBounds() {
    if (points.isEmpty) {
      return Rect.zero;
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final point in points) {
      if (point.position.dx < minX) minX = point.position.dx;
      if (point.position.dy < minY) minY = point.position.dy;
      if (point.position.dx > maxX) maxX = point.position.dx;
      if (point.position.dy > maxY) maxY = point.position.dy;
    }

    // Add padding for the stroke width
    final padding = baseWidth * 2;

    return Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ev': engineVersion, // 🛡️ Engine version tag
    'points': points.map((p) => p.toJson()).toList(),
    'color': color.toARGB32(),
    'baseWidth': baseWidth,
    'penType': penType.toString(),
    'createdAt': createdAt.toIso8601String(),
    // 🎛️ Save settings only thef not sono i default (ottimizza storage)
    if (!settings.isDefault) 'settings': settings.toJson(),
  };

  factory ProStroke.fromJson(Map<String, dynamic> json) => ProStroke(
    id: json['id'] as String,
    // 🛡️ Old strokes without 'ev' are version 1 (pre-versioning)
    engineVersion: (json['ev'] as int?) ?? 1,
    points:
        (json['points'] as List)
            .map(
              (p) => ProDrawingPoint.fromJson(
                p is Map<String, dynamic>
                    ? p
                    : Map<String, dynamic>.from(p as Map),
              ),
            )
            .toList(),
    color: Color(json['color'] as int),
    baseWidth: (json['baseWidth'] as num).toDouble(),
    penType: ProPenType.values.firstWhere(
      (e) => e.toString() == json['penType'],
      orElse: () => ProPenType.ballpoint,
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
    settings: ProBrushSettings.fromJson(
      json['settings'] is Map
          ? Map<String, dynamic>.from(json['settings'] as Map)
          : null,
    ),
  );

  ProStroke copyWith({
    String? id,
    List<ProDrawingPoint>? points,
    Color? color,
    double? baseWidth,
    ProPenType? penType,
    DateTime? createdAt,
    ProBrushSettings? settings,
    int? engineVersion,
  }) {
    return ProStroke(
      id: id ?? this.id,
      points: points ?? this.points,
      color: color ?? this.color,
      baseWidth: baseWidth ?? this.baseWidth,
      penType: penType ?? this.penType,
      createdAt: createdAt ?? this.createdAt,
      settings: settings ?? this.settings,
      engineVersion: engineVersion ?? this.engineVersion,
    );
  }
}

/// Tipi di penna professionale
enum ProPenType {
  ballpoint, // Penna a sfera
  fountain, // Stilografica
  pencil, // Matita
  highlighter, // Evidenziatore
}
