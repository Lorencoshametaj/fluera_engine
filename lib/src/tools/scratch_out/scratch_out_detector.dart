import 'dart:math' as math;
import 'dart:ui';

import '../../drawing/models/pro_drawing_point.dart';

/// Result of scratch-out gesture analysis.
class ScratchOutResult {
  /// Whether the gesture was recognized as a scratch-out.
  final bool recognized;

  /// Bounding box of the scratch gesture (for finding overlapping strokes).
  final Rect scratchBounds;

  /// Number of direction reversals detected.
  final int reversalCount;

  /// Confidence score (0.0–1.0).
  final double confidence;

  const ScratchOutResult({
    required this.recognized,
    required this.scratchBounds,
    required this.reversalCount,
    required this.confidence,
  });

  static const notRecognized = ScratchOutResult(
    recognized: false,
    scratchBounds: Rect.zero,
    reversalCount: 0,
    confidence: 0.0,
  );
}

/// 🚀 Incremental PCA accumulator for O(1) partial analysis.
///
/// Maintains running sums (sumX, sumY, sumXX, sumXY, sumYY) and bbox
/// so that `analyzePartial()` during drawing doesn't need to re-scan
/// all N points — just uses the accumulated statistics.
///
/// Usage:
/// ```dart
/// final acc = ScratchOutAccumulator();
/// // In _onDrawStart:
/// acc.reset();
/// // In _onDrawUpdate:
/// acc.addPoint(point);
/// if (acc.pointCount >= 15 && acc.shouldCheck()) {
///   final result = acc.analyzePartial();
/// }
/// // In _onDrawEnd:
/// final result = ScratchOutDetector.analyze(allPoints);
/// ```
class ScratchOutAccumulator {
  // Running sums for PCA (O(1) update)
  double _sumX = 0, _sumY = 0;
  double _sumXX = 0, _sumXY = 0, _sumYY = 0;

  // Bbox tracking
  double _minX = double.infinity, _minY = double.infinity;
  double _maxX = double.negativeInfinity, _maxY = double.negativeInfinity;

  // Point tracking
  int _pointCount = 0;
  int _firstTs = 0;

  // Reversal tracking (incremental)
  int _reversals = 0;
  int _lastDirection = 0;
  double _accumDistance = 0.0;
  double _totalPathLength = 0.0;
  Offset? _lastPosition;

  // PCA cache (recomputed only when dirty)
  double _perpDx = 0, _perpDy = 1;
  bool _pcaDirty = true;
  int _pcaComputedAt = 0; // point count when PCA was last computed

  // Debounce: timestamp of last partial check
  int _lastCheckMs = 0;
  static const int _debounceMs = 50;

  int get pointCount => _pointCount;

  /// Reset for a new stroke.
  void reset() {
    _sumX = _sumY = 0;
    _sumXX = _sumXY = _sumYY = 0;
    _minX = _minY = double.infinity;
    _maxX = _maxY = double.negativeInfinity;
    _pointCount = 0;
    _firstTs = 0;
    _reversals = 0;
    _lastDirection = 0;
    _accumDistance = 0.0;
    _totalPathLength = 0.0;
    _lastPosition = null;
    _perpDx = 0;
    _perpDy = 1;
    _pcaDirty = true;
    _pcaComputedAt = 0;
    _lastCheckMs = 0;
  }

  /// Add a single point (O(1)).
  void addPoint(ProDrawingPoint p) {
    final x = p.position.dx;
    final y = p.position.dy;

    // Update running sums
    _sumX += x;
    _sumY += y;
    _sumXX += x * x;
    _sumXY += x * y;
    _sumYY += y * y;

    // Update bbox
    if (x < _minX) _minX = x;
    if (y < _minY) _minY = y;
    if (x > _maxX) _maxX = x;
    if (y > _maxY) _maxY = y;

    // Track first timestamp
    if (_pointCount == 0) _firstTs = p.timestamp;

    _pointCount++;
    _pcaDirty = true;

    // Incremental path length + reversal counting
    // (requires PCA direction — use cached if available)
    if (_lastPosition != null) {
      final dx = x - _lastPosition!.dx;
      final dy = y - _lastPosition!.dy;
      _totalPathLength += math.sqrt(dx * dx + dy * dy);

      // Project onto perpendicular axis (use cached PCA direction)
      if (_pcaComputedAt > 0) {
        final movement = dx * _perpDx + dy * _perpDy;
        _accumDistance += movement;

        if (_accumDistance.abs() >= ScratchOutDetector.minSegmentLength) {
          final direction = _accumDistance > 0 ? 1 : -1;
          if (_lastDirection != 0 && direction != _lastDirection) {
            _reversals++;
          }
          _lastDirection = direction;
          _accumDistance = 0.0;
        }
      }
    }
    _lastPosition = p.position;
  }

  /// Whether enough time has passed since last check (debounce).
  bool shouldCheck() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCheckMs < _debounceMs) return false;
    _lastCheckMs = now;
    return true;
  }

  /// O(1) partial analysis using accumulated statistics.
  ScratchOutResult analyzePartial() {
    if (_pointCount < ScratchOutDetector.minPointCount) {
      return ScratchOutResult.notRecognized;
    }

    final bboxW = _maxX - _minX;
    final bboxH = _maxY - _minY;
    if (bboxW < 10.0 || bboxH < 10.0) return ScratchOutResult.notRecognized;

    // Recompute PCA direction if dirty (every ~20 points, amortized O(1))
    if (_pcaDirty && _pointCount - _pcaComputedAt >= 20) {
      _recomputePCA();
    }

    // Use incremental reversal count
    if (_reversals < ScratchOutDetector.minReversalsPartial) {
      return ScratchOutResult.notRecognized;
    }

    final scratchBounds =
        Rect.fromLTRB(_minX, _minY, _maxX, _maxY).inflate(5.0);

    return ScratchOutResult(
      recognized: true,
      scratchBounds: scratchBounds,
      reversalCount: _reversals,
      confidence: 0.5, // Partial — no full confidence scoring
    );
  }

  /// Recompute PCA direction from running sums (O(1)).
  void _recomputePCA() {
    final n = _pointCount.toDouble();
    if (n < 2) return;

    final meanX = _sumX / n;
    final meanY = _sumY / n;

    // Covariance from running sums: cov(X,Y) = E[XY] - E[X]E[Y]
    final cxx = _sumXX / n - meanX * meanX;
    final cxy = _sumXY / n - meanX * meanY;
    final cyy = _sumYY / n - meanY * meanY;

    final trace = cxx + cyy;
    final det = cxx * cyy - cxy * cxy;
    final disc = math.sqrt(math.max(0, trace * trace / 4 - det));
    final lambda1 = trace / 2 + disc;

    if (cxy.abs() > 1e-6) {
      final evx = lambda1 - cyy;
      final evy = cxy;
      final evLen = math.sqrt(evx * evx + evy * evy);
      if (evLen > 1e-8) {
        _perpDx = -evy / evLen;
        _perpDy = evx / evLen;
      }
    } else {
      _perpDx = cxx >= cyy ? 0 : 1;
      _perpDy = cxx >= cyy ? 1 : 0;
    }

    _pcaComputedAt = _pointCount;
    _pcaDirty = false;

    // Re-count reversals from scratch with new direction
    // (only needed when PCA direction changes significantly)
    // For efficiency, we skip this — the incremental count with
    // the previous direction is close enough for partial preview.
  }
}

/// 🧹 Scratch-Out Gesture Detector (v2 — PCA-based)
///
/// Detects rapid zigzag scribbles by:
/// 1. Computing PCA to find the dominant direction (any angle).
/// 2. Projecting onto perpendicular axis and counting reversals.
///
/// O(n) for full analysis; O(1) partial via [ScratchOutAccumulator].
class ScratchOutDetector {
  ScratchOutDetector._();

  // ── Thresholds (v3 — tightened to avoid false triggers on zoom) ──
  static const int minReversals = 6;
  static const int minReversalsPartial = 4;
  static const int minPointCount = 25;
  static const int maxDurationMs = 1500;
  static const double minElongation = 3.0;
  static const double minSegmentLength = 15.0;
  static const double minConfidence = 0.5;
  /// Minimum bounding box area (px²) — rejects tiny/tight gestures.
  static const double minBboxArea = 2000.0;
  /// Minimum perpendicular amplitude (px) — rejects jitter-level oscillation.
  static const double minAmplitude = 20.0;

  /// Full analysis: recognize scratch-out gesture.
  static ScratchOutResult analyze(List<ProDrawingPoint> points) {
    return _analyze(points, partial: false);
  }

  /// Partial analysis for real-time preview (lower thresholds).
  static ScratchOutResult analyzePartial(List<ProDrawingPoint> points) {
    return _analyze(points, partial: true);
  }

  static ScratchOutResult _analyze(
    List<ProDrawingPoint> points, {
    required bool partial,
  }) {
    if (points.length < minPointCount) return ScratchOutResult.notRecognized;

    // ── Duration check ──
    if (!partial) {
      final firstTs = points.first.timestamp;
      final lastTs = points.last.timestamp;
      if (firstTs > 0 && lastTs > 0) {
        if (lastTs - firstTs > maxDurationMs) {
          return ScratchOutResult.notRecognized;
        }
      }
    }

    // ── Single-pass: bbox + PCA sums ──
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    double sumX = 0, sumY = 0;
    double sumXX = 0, sumXY = 0, sumYY = 0;

    for (final p in points) {
      final x = p.position.dx;
      final y = p.position.dy;
      sumX += x;
      sumY += y;
      sumXX += x * x;
      sumXY += x * y;
      sumYY += y * y;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    final bboxW = maxX - minX;
    final bboxH = maxY - minY;
    if (bboxW < 10.0 || bboxH < 10.0) return ScratchOutResult.notRecognized;

    // ── Minimum area check ──
    if (bboxW * bboxH < minBboxArea) return ScratchOutResult.notRecognized;

    // ── PCA from running sums (no second pass) ──
    final n = points.length.toDouble();
    final meanX = sumX / n;
    final meanY = sumY / n;
    final cxx = sumXX / n - meanX * meanX;
    final cxy = sumXY / n - meanX * meanY;
    final cyy = sumYY / n - meanY * meanY;

    final trace = cxx + cyy;
    final det = cxx * cyy - cxy * cxy;
    final disc = math.sqrt(math.max(0, trace * trace / 4 - det));
    final lambda1 = trace / 2 + disc;
    final lambda2 = trace / 2 - disc;

    if (lambda2 <= 0 || lambda1 / lambda2 < minElongation) {
      return ScratchOutResult.notRecognized;
    }

    // ── Perpendicular direction ──
    double perpDx, perpDy;
    if (cxy.abs() > 1e-6) {
      final evx = lambda1 - cyy;
      final evy = cxy;
      final evLen = math.sqrt(evx * evx + evy * evy);
      perpDx = -evy / evLen;
      perpDy = evx / evLen;
    } else {
      perpDx = cxx >= cyy ? 0 : 1;
      perpDy = cxx >= cyy ? 1 : 0;
    }

    // ── Reversal counting ──
    int reversals = 0;
    int lastDirection = 0;
    double accumDistance = 0.0;
    double totalPathLength = 0.0;

    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1].position;
      final curr = points[i].position;
      final dx = curr.dx - prev.dx;
      final dy = curr.dy - prev.dy;
      totalPathLength += math.sqrt(dx * dx + dy * dy);

      final movement = dx * perpDx + dy * perpDy;
      accumDistance += movement;

      if (accumDistance.abs() >= minSegmentLength) {
        final direction = accumDistance > 0 ? 1 : -1;
        if (lastDirection != 0 && direction != lastDirection) {
          reversals++;
        }
        lastDirection = direction;
        accumDistance = 0.0;
      }
    }

    final requiredReversals = partial ? minReversalsPartial : minReversals;
    if (reversals < requiredReversals) return ScratchOutResult.notRecognized;

    // ── Perpendicular amplitude check ──
    // Ensure the oscillation spans at least minAmplitude px on the perp axis.
    final perpMin = bboxW < bboxH ? bboxW : bboxH;
    if (perpMin < minAmplitude) return ScratchOutResult.notRecognized;

    // ── Confidence ──
    final bboxArea = bboxW * bboxH;
    final pathLenSq = totalPathLength * totalPathLength;
    final density =
        pathLenSq > 0 ? (bboxArea / pathLenSq).clamp(0.0, 1.0) : 0.0;
    final reversalScore =
        ((reversals - requiredReversals) / 6.0).clamp(0.0, 1.0);
    final confidence =
        (reversalScore * 0.6 + (1.0 - density) * 0.4).clamp(0.0, 1.0);

    if (!partial && confidence < minConfidence) {
      return ScratchOutResult.notRecognized;
    }

    final scratchBounds = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(5.0);

    return ScratchOutResult(
      recognized: true,
      scratchBounds: scratchBounds,
      reversalCount: reversals,
      confidence: confidence,
    );
  }
}
