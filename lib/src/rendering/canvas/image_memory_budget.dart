import 'dart:io' show ProcessInfo;
import '../../../src/platform/native_performance_monitor.dart';

/// 🧠 Adaptive memory budget for image raster cache.
///
/// Queries device capabilities via [NativePerformanceMonitor] to determine
/// how much memory the image system should use — no hardcoded cap.
///
/// The budget reacts to memory pressure events, dynamically adjusting
/// the LOD strategy and cache size.
///
/// | Device class       | Available RAM | Budget  | Strategy                              |
/// |--------------------|---------------|---------|---------------------------------------|
/// | iPad Pro / flagship| > 2 GB        | 400 MB  | All visible at full-res, prefetch     |
/// | Mid-range          | 1–2 GB        | 200 MB  | Visible at full-res, LOD off-viewport |
/// | Budget Android     | < 1 GB        | 80 MB   | Visible at LOD, aggressive stubbing   |
/// | Memory pressure    | critical      | 30 MB   | Aggressively evict, micro thumbnails  |
class ImageMemoryBudget {
  /// Current budget in megabytes.
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

  /// Current budget in bytes.
  int get currentBudgetBytes => _currentBudgetMB * 1024 * 1024;

  /// Compute budget from current process RSS (synchronous).
  ///
  /// Uses the inverse heuristic: lower RSS = more headroom → higher budget.
  /// This replaces the old `adjustBudgetFromMemory()` approach.
  int computeBudgetFromRSS() {
    final rssMB = ProcessInfo.currentRss ~/ (1024 * 1024);

    int budget;
    if (rssMB < 300) {
      budget = 400; // Very low usage → flagship-like headroom
    } else if (rssMB < 500) {
      budget = 200; // Moderate usage
    } else if (rssMB < 700) {
      budget = 100; // Getting full
    } else {
      budget = 80; // Heavy usage → budget mode
    }

    _currentBudgetMB = budget;
    return budget;
  }

  /// Compute `maxImages` from the budget.
  ///
  /// Assumes an average decoded image is [avgImageSizeMB] MB.
  /// A 2048×1536 RGBA image ≈ 12 MB. A 4K image ≈ 33 MB.
  /// Default uses 12 MB (capped at 2048px by `_decodeImageCapped`).
  int computeMaxImages({double avgImageSizeMB = 12.0}) {
    return (_currentBudgetMB / avgImageSizeMB).floor().clamp(3, 100);
  }

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

  /// Number of off-screen images to prefetch, based on budget.
  int get prefetchCount {
    if (_currentBudgetMB >= 400) return 6;
    if (_currentBudgetMB >= 200) return 4;
    if (_currentBudgetMB >= 100) return 3;
    return 1;
  }

  /// Whether we should downgrade existing caches due to pressure.
  bool get shouldEvictAggressively => _currentBudgetMB <= 60;

  /// Compute zoom-based LOD scale for images.
  ///
  /// Maps the current canvas zoom level to a raster scale factor.
  /// At low zoom many small images → blurriness invisible.
  /// Full quality at zoom ≥ 0.8 where images fill the screen.
  static double lodScaleForZoom(double zoom) {
    if (zoom < 0.15) return 0.20; // tiny thumbnails → 80% savings
    if (zoom < 0.4) return 0.35; // multiple images → 30% savings
    if (zoom < 1.0) return 1.0; // image visible → full quality
    if (zoom < 2.0) return 2.0; // zoomed in → crisp
    return 4.0; // deep zoom → max quality
  }

  @override
  String toString() =>
      'ImageMemoryBudget(${_currentBudgetMB}MB, '
      'prefetch: $prefetchCount, '
      'evict: $shouldEvictAggressively)';
}
