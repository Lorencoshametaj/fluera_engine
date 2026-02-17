/// 🚀 PREDICTIVE STROKE RENDERER (ANTI-LAG)
///
/// Simula l'anticipo of the stroke come Apple Pencil:
/// - Prevede i prossimi 2-3 punti based on direzione e speed
/// - Draw a light "ghost trail" which is then replaced by the real stroke
/// - Eliminates lag sensation even on medium devices
///
/// Features:
/// - Velocity-based prediction
/// - Direction smoothing
/// - Opacity fade for ghost trail
library;

import 'dart:ui';
import 'dart:math' as math;

class PredictiveRenderer {
  /// Number of punti da predire
  final int predictedPointsCount;

  /// Opacity of the stroke predetto
  final double ghostOpacity;

  /// Decay factor per velocity prediction
  final double velocityDecay;

  /// Storia of points recenti to calculate speed
  final List<_PointWithTime> _recentPoints = [];
  static const int _maxRecentPoints = 5;

  PredictiveRenderer({
    this.predictedPointsCount = 3,
    this.ghostOpacity = 0.3,
    this.velocityDecay = 0.85,
  });

  // 🚀 CACHED objects for rendering (avoids allocation every frame)
  final Paint _ghostPaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
  final Path _ghostPath = Path();

  /// Adds a point to history
  void addPoint(Offset point, DateTime timestamp) {
    _recentPoints.add(_PointWithTime(point, timestamp));
    if (_recentPoints.length > _maxRecentPoints) {
      _recentPoints.removeAt(0);
    }
  }

  /// Predici i prossimi punti based on speed e direzione
  List<Offset> predictNextPoints() {
    if (_recentPoints.length < 2) {
      return [];
    }

    // Calculate average speed and direction
    final velocity = _calculateVelocity();
    if (velocity.distance < 0.1) {
      // Troppo lento, non serve predizione
      return [];
    }

    final lastPoint = _recentPoints.last.point;
    final predicted = <Offset>[];

    // Genera punti predetti con velocity decay
    Offset currentVelocity = velocity;
    Offset currentPoint = lastPoint;

    for (int i = 0; i < predictedPointsCount; i++) {
      // Applica velocity decay (rallenta progressivamente)
      currentVelocity = currentVelocity * velocityDecay;
      currentPoint = currentPoint + currentVelocity;
      predicted.add(currentPoint);
    }

    return predicted;
  }

  /// Draws il ghost trail (tratto predetto)
  void drawGhostTrail(
    Canvas canvas,
    Paint basePaint,
    List<Offset> predictedPoints,
  ) {
    if (predictedPoints.isEmpty) return;

    final lastActualPoint = _recentPoints.last.point;

    // 🚀 USE CACHED PAINT and PATH (reset and reuse)
    _ghostPaint
      ..color = basePaint.color.withValues(alpha: ghostOpacity)
      ..strokeWidth = basePaint.strokeWidth;

    _ghostPath.reset();
    _ghostPath.moveTo(lastActualPoint.dx, lastActualPoint.dy);

    for (int i = 0; i < predictedPoints.length; i++) {
      final point = predictedPoints[i];

      // Fade progressivo (more distante = more trasparente)
      final fade = 1.0 - (i / predictedPoints.length) * 0.5;
      _ghostPaint.color = basePaint.color.withValues(
        alpha: ghostOpacity * fade,
      );

      // Linea verso punto predetto
      _ghostPath.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(_ghostPath, _ghostPaint);
  }

  /// Calculates speed media dai punti recenti
  Offset _calculateVelocity() {
    if (_recentPoints.length < 2) return Offset.zero;

    // Use last 2-3 points to calculate speed
    final recent = _recentPoints.sublist(math.max(0, _recentPoints.length - 3));

    double totalVelX = 0.0;
    double totalVelY = 0.0;
    int count = 0;

    for (int i = 1; i < recent.length; i++) {
      final dt =
          recent[i].timestamp
              .difference(recent[i - 1].timestamp)
              .inMicroseconds /
          1000000.0;
      if (dt > 0) {
        final dx = (recent[i].point.dx - recent[i - 1].point.dx) / dt;
        final dy = (recent[i].point.dy - recent[i - 1].point.dy) / dt;

        // Speed in px/s
        totalVelX += dx;
        totalVelY += dy;
        count++;
      }
    }

    if (count == 0) return Offset.zero;

    // Speed media (in px/frame assumendo 60fps)
    final avgVelX = (totalVelX / count) / 60.0;
    final avgVelY = (totalVelY / count) / 60.0;

    return Offset(avgVelX, avgVelY);
  }

  /// Calculates la speed attuale in px/s
  double getCurrentSpeed() {
    final velocity = _calculateVelocity();
    // Convert da px/frame a px/s
    return velocity.distance * 60.0;
  }

  /// Get la direzione attuale del movimento
  Offset getDirection() {
    if (_recentPoints.length < 2) return Offset.zero;

    final last = _recentPoints.last.point;
    final prev = _recentPoints[_recentPoints.length - 2].point;
    final direction = last - prev;

    if (direction.distance < 0.1) return Offset.zero;
    return direction / direction.distance; // Normalize
  }

  /// Resets la storia
  void reset() {
    _recentPoints.clear();
  }
}

/// Punto con timestamp
class _PointWithTime {
  final Offset point;
  final DateTime timestamp;

  _PointWithTime(this.point, this.timestamp);
}
