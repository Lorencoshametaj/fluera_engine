import 'dart:math' as math;
import 'package:flutter/material.dart'; // For Colors
import '../models/pro_drawing_point.dart';
import '../models/pro_brush_settings.dart'; // For ProBrushSettings

/// 🧪 DEBUG TOOL - Generatore automatico di strokes per testing scalabilità
///
/// USO:
/// ```dart
/// final strokes = StrokeGenerator.generateRandomStrokes(10000);
/// for (final stroke in strokes) {
///   _layerController.addStroke(stroke);
///   await StrokePersistenceService.instance.saveStroke(stroke);
/// }
/// ```
class StrokeGenerator {
  static final _random = math.Random();

  /// Genera N strokes casuali distribuiti on the canvas
  ///
  /// [count]: Number of strokes da generare (es. 10000 per TIER 4)
  /// [canvasSize]: Size canvas (default 5000x5000)
  /// [avgPointsPerStroke]: Punti medi per stroke (default 50)
  /// [enableDeltaTracking]: Se false, tutti i punti avranno timestamp identico
  ///                        per disabilitare delta tracking (default: false for performance test)
  static List<ProStroke> generateRandomStrokes(
    int count, {
    Size canvasSize = const Size(5000, 5000),
    int avgPointsPerStroke = 50,
    bool enableDeltaTracking = false,
  }) {
    final strokes = <ProStroke>[];

    for (int i = 0; i < count; i++) {
      // Position iniziale casuale
      final startX = _random.nextDouble() * canvasSize.width;
      final startY = _random.nextDouble() * canvasSize.height;

      // Numero punti variabile (30-70)
      final pointCount = avgPointsPerStroke + _random.nextInt(40) - 20;

      // Genera stroke casuale (linea curva)
      final points = _generateStrokePath(
        Offset(startX, startY),
        pointCount,
        maxLength: 200.0,
        enableDeltaTracking: enableDeltaTracking,
      );

      // Color casuale
      final color = Color.fromARGB(
        255,
        _random.nextInt(256),
        _random.nextInt(256),
        _random.nextInt(256),
      );

      // Create stroke
      final stroke = ProStroke(
        id: 'generated_$i',
        points: points,
        color: color,
        baseWidth: 2.0 + _random.nextDouble() * 3.0,
        penType: ProPenType.ballpoint, // Fixed: use enum
        createdAt: DateTime.now(),
        settings: ProBrushSettings(), // Fixed: added required settings
      );

      strokes.add(stroke);

      // Log progress every 1000 strokes
      if ((i + 1) % 1000 == 0) {
      }
    }

    return strokes;
  }

  /// Genera un percorso curvo casuale
  ///
  /// [enableDeltaTracking]: If false, all points will have the same timestamp
  static List<ProDrawingPoint> _generateStrokePath(
    Offset start,
    int pointCount, {
    double maxLength = 200.0,
    bool enableDeltaTracking = false,
  }) {
    final points = <ProDrawingPoint>[];
    var currentPos = start;

    // Direzione iniziale casuale
    var angle = _random.nextDouble() * 2 * math.pi;

    // 🧪 Base timestamp: if delta tracking is disabled, always use the same
    final baseTimestamp = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < pointCount; i++) {
      // Pressione variabile (simula tocco naturale)
      final pressure = 0.3 + _random.nextDouble() * 0.7;

      // Add punto
      points.add(
        ProDrawingPoint(
          position: currentPos,
          pressure: pressure,
          // If delta tracking is disabled, always use baseTimestamp
          // Altrimenti incrementa per ogni punto
          timestamp: enableDeltaTracking ? baseTimestamp + i : baseTimestamp,
        ),
      );

      // Movimento verso prossimo punto
      final stepLength = maxLength / pointCount;

      // Slightly vary the direction (natural curve)
      angle += (_random.nextDouble() - 0.5) * 0.3;

      currentPos = Offset(
        currentPos.dx + math.cos(angle) * stepLength,
        currentPos.dy + math.sin(angle) * stepLength,
      );
    }

    return points;
  }

  /// Genera strokes in un pattern specifico (per test visuale)
  static List<ProStroke> generateGridPattern(
    int rows,
    int cols, {
    Size canvasSize = const Size(5000, 5000),
  }) {
    final strokes = <ProStroke>[];
    final cellWidth = canvasSize.width / cols;
    final cellHeight = canvasSize.height / rows;

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final centerX = (col + 0.5) * cellWidth;
        final centerY = (row + 0.5) * cellHeight;

        // Create una piccola spirale in ogni cella
        final points = _generateSpiral(
          Offset(centerX, centerY),
          radius: math.min(cellWidth, cellHeight) * 0.4,
        );

        final stroke = ProStroke(
          id: 'grid_${row}_$col',
          points: points,
          color: Colors.blue,
          baseWidth: 2.0,
          penType: ProPenType.ballpoint, // Fixed: use enum
          createdAt: DateTime.now(),
          settings: ProBrushSettings(), // Fixed: added required settings
        );

        strokes.add(stroke);
      }
    }

    return strokes;
  }

  /// Genera una spirale
  static List<ProDrawingPoint> _generateSpiral(
    Offset center, {
    double radius = 50.0,
    int turns = 3,
  }) {
    final points = <ProDrawingPoint>[];
    final pointsPerTurn = 20;
    final totalPoints = turns * pointsPerTurn;

    for (int i = 0; i < totalPoints; i++) {
      final progress = i / totalPoints;
      final angle = progress * turns * 2 * math.pi;
      final currentRadius = radius * progress;

      final x = center.dx + math.cos(angle) * currentRadius;
      final y = center.dy + math.sin(angle) * currentRadius;

      points.add(
        ProDrawingPoint(
          position: Offset(x, y),
          pressure: 0.5,
          timestamp: DateTime.now().millisecondsSinceEpoch + i,
        ),
      );
    }

    return points;
  }
}
