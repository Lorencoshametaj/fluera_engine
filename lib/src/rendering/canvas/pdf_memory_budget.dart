import '../../../src/platform/native_performance_monitor.dart';

/// 🧠 Adaptive memory budget for PDF raster tile cache.
///
/// Queries device capabilities via [NativePerformanceMonitor] to determine
/// how much memory the PDF system should use — no hardcoded cap.
///
/// The budget reacts to memory pressure events, dynamically adjusting
/// the LOD strategy and cache size.
///
/// | Device class       | Available RAM | Budget  | LOD strategy                          |
/// |--------------------|---------------|---------|---------------------------------------|
/// | iPad Pro / flagship | > 2 GB        | 400 MB  | All visible at 2x, prefetch ±2       |
/// | Mid-range          | 1–2 GB        | 200 MB  | Visible at 1x, adjacent at 0.5x      |
/// | Budget Android     | < 1 GB        | 80 MB   | Visible only at 0.5x, placeholders   |
/// | Memory pressure    | critical       | 30 MB   | Aggressively evict, drop to 0.25x    |
class PdfMemoryBudget {
  /// Singleton-ish: one budget per PDF rendering pipeline.
  int _currentBudgetMB = 100;

  /// Compute the maximum allowed cache size in megabytes.
  ///
  /// Call at startup and whenever [PerformanceMetrics] changes.
  int computeBudgetMB(PerformanceMetrics metrics) {
    final availMB = metrics.memoryAvailableMB ?? 500.0;
    final pressure = metrics.memoryPressureLevel;

    int budget;

    if (pressure == 'critical') {
      budget = 30;
    } else if (pressure == 'warning') {
      budget = 60;
    } else if (availMB > 2000) {
      budget = 400; // flagship: go all-in
    } else if (availMB > 1000) {
      budget = 200; // mid-range: comfortable
    } else if (availMB > 500) {
      budget = 100; // modest
    } else {
      budget = 80; // budget device
    }

    _currentBudgetMB = budget;
    return budget;
  }

  /// The most recently computed budget in megabytes.
  int get currentBudgetMB => _currentBudgetMB;

  /// Number of active PDF documents sharing this device's budget.
  int activeDocumentCount = 1;

  /// Current budget in bytes, divided by active document count.
  int get currentBudgetBytes =>
      (_currentBudgetMB * 1024 * 1024) ~/ activeDocumentCount.clamp(1, 100);

  /// Target LOD scale based on current device capabilities.
  ///
  /// [baseScale] is the zoom-based scale (0.25, 0.5, 1.0, 2.0).
  /// This method clamps it based on memory constraints.
  double clampScale(double baseScale) {
    if (_currentBudgetMB <= 30) {
      return baseScale.clamp(0.25, 0.5);
    } else if (_currentBudgetMB <= 80) {
      return baseScale.clamp(0.25, 1.0);
    } else if (_currentBudgetMB <= 200) {
      return baseScale.clamp(0.25, 2.0);
    } else {
      return baseScale.clamp(0.25, 4.0);
    }
  }

  /// Number of off-screen pages to prefetch, based on budget.
  int get prefetchCount {
    if (_currentBudgetMB >= 400) return 6;
    if (_currentBudgetMB >= 200) return 4;
    if (_currentBudgetMB >= 100) return 3;
    return 1;
  }

  /// Whether we should downgrade existing caches due to pressure.
  bool get shouldEvictAgressively => _currentBudgetMB <= 60;

  /// Compute zoom-based LOD scale.
  ///
  /// Maps the current canvas zoom level to a raster scale factor.
  static double lodScaleForZoom(double zoom) {
    if (zoom < 0.15) return 0.25;
    if (zoom < 0.4) return 0.5;
    if (zoom < 1.0) return 1.0;
    if (zoom < 2.0) return 2.0;
    return 4.0;
  }

  @override
  String toString() =>
      'PdfMemoryBudget(${_currentBudgetMB}MB, '
      'prefetch: $prefetchCount, '
      'evict: $shouldEvictAgressively)';
}
