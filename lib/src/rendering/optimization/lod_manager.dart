import 'dart:isolate';
import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';

/// 🚀 LOD MANAGER - Level of Detail per stroke simplification
///
/// PROBLEMA:
/// At low zoom (e.g. 10%), no need to draw all 1000 points of a stroke.
/// L'occhio non can distinguere dettagli so piccoli.
///
/// SOLUZIONE:
/// - Use Douglas-Peucker algorithm to simplify points
/// - At low zoom: fewer points = faster rendering
/// - At high zoom: all points for maximum detail
///
/// LOD LEVELS:
/// - LOD 0 (zoom > 50%): All points
/// - LOD 1 (zoom 20-50%): ~50% of points
/// - LOD 2 (zoom 5-20%): ~20% of points
/// - LOD 3 (zoom < 5%): ~5% of points
///
/// PERFORMANCE:
/// - 1000 points → ~50 points at LOD 3 = 20x less work
/// - Maintains the general shape of the stroke
class LODManager {
  // ═══════════════════════════════════════════════════════════════════════════
  // 📐 CONFIGURATION LOD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Soglie di zoom per ogni LOD level
  static const double lod0Threshold = 0.5; // > 50% = full detail
  static const double lod1Threshold = 0.2; // 20-50% = medium detail
  static const double lod2Threshold = 0.05; // 5-20% = low detail
  // < 5% = very low detail (LOD 3)

  /// Tolleranze per Douglas-Peucker (in pixel canvas)
  /// Più alto = more semplificazione
  static const double lod1Tolerance = 2.0;
  static const double lod2Tolerance = 5.0;
  static const double lod3Tolerance = 15.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎯 CACHE LOD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Cache per punti semplificati: strokeId -> {lodLevel -> points}
  static final Map<String, Map<int, List<ProDrawingPoint>>> _lodCache = {};

  /// Maximum number di stroke in cache LOD
  /// 🆕 Aumentato da 500 a 5000 per supportare canvas grandi without thrashing
  static const int maxCachedStrokes = 5000;

  // ═══════════════════════════════════════════════════════════════════════════
  // 📊 LOD LEVEL CALCULATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calculates il LOD level appropriato for ao zoom
  static int getLODLevel(double zoom) {
    if (zoom > lod0Threshold) return 0; // Full detail
    if (zoom > lod1Threshold) return 1; // Medium
    if (zoom > lod2Threshold) return 2; // Low
    return 3; // Very low
  }

  /// Gets la tolleranza for a LOD level
  /// 🆕 LOD 3 aggiunto per estrema semplificazione ai bordi viewport
  static double getToleranceForLevel(int lodLevel) {
    switch (lodLevel) {
      case 0:
        return 0.0; // No simplification
      case 1:
        return lod1Tolerance; // 2.0px
      case 2:
        return lod2Tolerance; // 5.0px
      case 3:
        return lod3Tolerance; // 15.0px - aggressivo per 60 FPS
      default:
        return 0.0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎨 GET POINTS FOR LOD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets i punti di uno stroke al LOD level appropriato
  ///
  /// [stroke]: Lo stroke da semplificare
  /// [zoom]: Current zoom level (0.0 - 1.0+)
  ///
  /// Returns: Lista di punti (originali o semplificati)
  static List<ProDrawingPoint> getPointsForZoom(ProStroke stroke, double zoom) {
    final lodLevel = getLODLevel(zoom);

    // LOD 0 = nessuna semplificazione
    if (lodLevel == 0) {
      return stroke.points;
    }

    // Check cache
    final cached = _getCachedPoints(stroke.id, lodLevel);
    if (cached != null) {
      return cached;
    }

    // Calculate punti semplificati
    final tolerance = getToleranceForLevel(lodLevel);
    final simplified = simplifyPoints(stroke.points, tolerance);

    // Save in cache
    _cachePoints(stroke.id, lodLevel, simplified);

    return simplified;
  }

  /// Gets punti cached for ao stroke/lod
  static List<ProDrawingPoint>? _getCachedPoints(
    String strokeId,
    int lodLevel,
  ) {
    return _lodCache[strokeId]?[lodLevel];
  }

  /// Saves punti semplificati in cache
  static void _cachePoints(
    String strokeId,
    int lodLevel,
    List<ProDrawingPoint> points,
  ) {
    // Evict vecchi stroke se cache troppo grande
    if (_lodCache.length >= maxCachedStrokes) {
      final oldestKey = _lodCache.keys.first;
      _lodCache.remove(oldestKey);
    }

    _lodCache.putIfAbsent(strokeId, () => {});
    _lodCache[strokeId]![lodLevel] = points;
  }

  /// Invalidate cache for a stroke (call after modification)
  static void invalidateStroke(String strokeId) {
    _lodCache.remove(strokeId);
  }

  /// Clears the entire cache LOD
  static void clearCache() {
    _lodCache.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 DOUGLAS-PEUCKER SIMPLIFICATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Semplifica una list of punti usando Douglas-Peucker algorithm
  ///
  /// [points]: Lista di punti originali
  /// [tolerance]: Maximum distance from segment (higher = more simplification)
  ///
  /// Returns: Lista di punti semplificati che mantiene la forma generale
  static List<ProDrawingPoint> simplifyPoints(
    List<ProDrawingPoint> points,
    double tolerance,
  ) {
    if (points.length <= 2) {
      return points;
    }

    // Find il punto more distante from the linea tra primo e ultimo
    double maxDistance = 0;
    int maxIndex = 0;

    final first = points.first.position;
    final last = points.last.position;

    for (int i = 1; i < points.length - 1; i++) {
      final distance = _perpendicularDistance(points[i].position, first, last);

      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    // If the maximum distance is greater than the tolerance, recursively simplify
    if (maxDistance > tolerance) {
      // Ricorsivamente semplifica le due mage
      final left = simplifyPoints(points.sublist(0, maxIndex + 1), tolerance);
      final right = simplifyPoints(points.sublist(maxIndex), tolerance);

      // Combine results (avoid midpoint duplication)
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      // All i punti intermedi possono essere rimossi
      return [points.first, points.last];
    }
  }

  /// Calculates la distanza perpendicolare di un punto da una linea
  static double _perpendicularDistance(
    Offset point,
    Offset lineStart,
    Offset lineEnd,
  ) {
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;

    // If la linea is un punto, ritorna distanza dat the point
    final lineLengthSq = dx * dx + dy * dy;
    if (lineLengthSq == 0) {
      return (point - lineStart).distance;
    }

    // Proietta il punto sulla linea
    final t =
        ((point.dx - lineStart.dx) * dx + (point.dy - lineStart.dy) * dy) /
        lineLengthSq;

    // Clamp t to [0, 1] to stay on the segment
    final clampedT = t.clamp(0.0, 1.0);

    // Punto more vicino sulla linea
    final closest = Offset(
      lineStart.dx + clampedT * dx,
      lineStart.dy + clampedT * dy,
    );

    return (point - closest).distance;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📊 STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calculates il fattore di riduzione for a LOD level
  static double getReductionFactor(
    List<ProDrawingPoint> original,
    int lodLevel,
  ) {
    if (lodLevel == 0) return 1.0;

    final tolerance = getToleranceForLevel(lodLevel);
    final simplified = simplifyPoints(original, tolerance);

    return simplified.length / original.length;
  }

  /// Statistiche cache
  static Map<String, dynamic> get stats => {
    'cachedStrokes': _lodCache.length,
    'maxCachedStrokes': maxCachedStrokes,
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧵 ASYNC SIMPLIFICATION (Compute Isolate)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Simplify points on a background isolate.
  /// Use for non-urgent tile rasterization prep.
  /// Falls back to synchronous if isolate fails.
  static Future<List<ProDrawingPoint>> simplifyAsync(
    List<ProDrawingPoint> points,
    double tolerance,
  ) async {
    if (points.length <= 2 || tolerance <= 0) return points;

    // For small point counts (<200), synchronous is faster (no isolate overhead)
    if (points.length < 200) {
      return simplifyPoints(points, tolerance);
    }

    try {
      // Serialize to transferable data (positions + metadata)
      final data = _SimplifyRequest(
        positions: points.map((p) => [p.position.dx, p.position.dy]).toList(),
        pressures: points.map((p) => p.pressure).toList(),
        timestamps: points.map((p) => p.timestamp).toList(),
        tiltXs: points.map((p) => p.tiltX).toList(),
        tiltYs: points.map((p) => p.tiltY).toList(),
        orientations: points.map((p) => p.orientation).toList(),
        tolerance: tolerance,
      );

      final resultIndices = await Isolate.run(() {
        return _simplifyOnIsolate(data);
      });

      // Reconstruct points using the kept indices
      return resultIndices.map((i) => points[i]).toList();
    } catch (_) {
      // Fallback to synchronous on isolate failure
      return simplifyPoints(points, tolerance);
    }
  }

  /// Pre-compute LOD for a batch of strokes asynchronously.
  /// Call when idle (e.g., after zoom settles, or on canvas load).
  static Future<void> precomputeLODBatch(
    List<ProStroke> strokes,
    double zoom,
  ) async {
    final lodLevel = getLODLevel(zoom);
    if (lodLevel == 0) return; // No simplification needed at full zoom

    final tolerance = getToleranceForLevel(lodLevel);

    for (final stroke in strokes) {
      // Skip if already cached
      if (_getCachedPoints(stroke.id, lodLevel) != null) continue;

      // Skip very short strokes
      if (stroke.points.length <= 2) continue;

      final simplified = await simplifyAsync(stroke.points, tolerance);
      _cachePoints(stroke.id, lodLevel, simplified);
    }
  }

  /// Pure function for isolate execution — works only with primitive data.
  static List<int> _simplifyOnIsolate(_SimplifyRequest req) {
    // Reconstruct positions as offsets
    final positions = req.positions.map((p) => Offset(p[0], p[1])).toList();
    return _douglasPeuckerIndices(
      positions,
      0,
      positions.length - 1,
      req.tolerance,
    );
  }

  /// Douglas-Peucker that returns kept indices instead of points.
  /// Pure function safe for isolate execution.
  static List<int> _douglasPeuckerIndices(
    List<Offset> positions,
    int start,
    int end,
    double tolerance,
  ) {
    if (end - start < 2) {
      final result = <int>[start];
      if (end != start) result.add(end);
      return result;
    }

    double maxDistance = 0;
    int maxIndex = start;

    final first = positions[start];
    final last = positions[end];

    for (int i = start + 1; i < end; i++) {
      final distance = _perpendicularDistance(positions[i], first, last);
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    if (maxDistance > tolerance) {
      final left = _douglasPeuckerIndices(
        positions,
        start,
        maxIndex,
        tolerance,
      );
      final right = _douglasPeuckerIndices(positions, maxIndex, end, tolerance);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [start, end];
    }
  }
}

/// Serializable request for isolate-based simplification.
class _SimplifyRequest {
  final List<List<double>> positions;
  final List<double> pressures;
  final List<int> timestamps;
  final List<double> tiltXs;
  final List<double> tiltYs;
  final List<double> orientations;
  final double tolerance;

  const _SimplifyRequest({
    required this.positions,
    required this.pressures,
    required this.timestamps,
    required this.tiltXs,
    required this.tiltYs,
    required this.orientations,
    required this.tolerance,
  });
}
