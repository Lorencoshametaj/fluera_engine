import 'dart:math' as math;
import 'dart:ui';

// ============================================================================
// 📊 ERASER ANALYTICS — Session tracking, heatmap, and dissolve effects
// ============================================================================

/// Tracks eraser usage analytics: stroke counts, area coverage,
/// session timing, heatmap density, and dissolve effect positions.
class EraserAnalytics {
  static const double _heatmapCellSize = 30.0;
  static const int _maxSnapshots = 50;
  static const int _maxDissolvePoints = 50;

  // ── Counters ───────────────────────────────────────────────────────

  int totalStrokesErased = 0;
  double totalAreaCovered = 0.0;
  Duration totalEraseTime = Duration.zero;
  DateTime? _eraseSessionStart;

  // ── Heatmap ────────────────────────────────────────────────────────

  final Map<int, int> _heatmapGrid = {};

  // ── Dissolve points (for particle effects) ─────────────────────────

  final List<Offset> dissolvePoints = [];

  // ── History snapshots ──────────────────────────────────────────────

  final List<(DateTime, int)> historySnapshots = [];

  // ── Session Tracking ───────────────────────────────────────────────

  /// Start tracking erase session time.
  void startSession() {
    _eraseSessionStart = DateTime.now();
  }

  /// End tracking erase session time.
  void endSession() {
    if (_eraseSessionStart != null) {
      totalEraseTime += DateTime.now().difference(_eraseSessionStart!);
      _eraseSessionStart = null;
    }
  }

  // ── Recording ──────────────────────────────────────────────────────

  /// Record analytics for a single erase action.
  void recordErase(Offset position, double eraserRadius) {
    totalStrokesErased++;
    totalAreaCovered += math.pi * eraserRadius * eraserRadius;

    // Dissolve point for particle effect
    dissolvePoints.add(position);
    if (dissolvePoints.length > _maxDissolvePoints) {
      dissolvePoints.removeAt(0);
    }

    // Heatmap touch
    final hx = (position.dx / _heatmapCellSize).floor();
    final hy = (position.dy / _heatmapCellSize).floor();
    final hkey = hx * 100003 + hy;
    _heatmapGrid[hkey] = (_heatmapGrid[hkey] ?? 0) + 1;
  }

  /// Take a lightweight history snapshot.
  void takeSnapshot(int currentStrokeCount) {
    historySnapshots.add((DateTime.now(), currentStrokeCount));
    if (historySnapshots.length > _maxSnapshots) {
      historySnapshots.removeAt(0);
    }
  }

  // ── Queries ────────────────────────────────────────────────────────

  /// Get heatmap intensity at a position [0..1].
  double getHeatmapIntensity(Offset position) {
    final hx = (position.dx / _heatmapCellSize).floor();
    final hy = (position.dy / _heatmapCellSize).floor();
    final hkey = hx * 100003 + hy;
    final count = _heatmapGrid[hkey] ?? 0;
    return (count / 10.0).clamp(0.0, 1.0);
  }

  /// Get analytics summary string.
  String get summary {
    final secs = totalEraseTime.inSeconds;
    return '$totalStrokesErased strokes · '
        '${(totalAreaCovered / 1000).toStringAsFixed(1)}k px² · ${secs}s';
  }

  // ── Reset ──────────────────────────────────────────────────────────

  /// Reset all analytics counters and data.
  void reset() {
    totalStrokesErased = 0;
    totalAreaCovered = 0.0;
    totalEraseTime = Duration.zero;
    _heatmapGrid.clear();
    dissolvePoints.clear();
    historySnapshots.clear();
  }
}
