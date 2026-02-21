/// 🧪 PERFORMANCE BASELINE — Frame time and memory regression tracking.
///
/// Records performance metrics as baselines and checks current measurements
/// against them with configurable regression thresholds.
///
/// ```dart
/// final baseline = PerformanceBaseline();
/// baseline.record('scene_render_ms', 8.5);
/// baseline.record('scene_render_ms', 9.0);
/// baseline.record('scene_render_ms', 8.2);
///
/// final check = baseline.check('scene_render_ms', 12.0);
/// if (check.isRegression) {
///   print('Performance regression: ${check.summary}');
/// }
/// ```
library;

// =============================================================================
// PERFORMANCE METRIC
// =============================================================================

/// A single recorded performance measurement.
class PerformanceMetric {
  /// Metric name (e.g. `'scene_render_ms'`, `'memory_mb'`).
  final String name;

  /// Measured value.
  final double value;

  /// When this measurement was taken.
  final DateTime measuredAt;

  PerformanceMetric({
    required this.name,
    required this.value,
    DateTime? measuredAt,
  }) : measuredAt = measuredAt ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'measuredAt': measuredAt.toIso8601String(),
  };

  factory PerformanceMetric.fromJson(Map<String, dynamic> json) =>
      PerformanceMetric(
        name: json['name'] as String,
        value: (json['value'] as num).toDouble(),
        measuredAt: DateTime.parse(json['measuredAt'] as String),
      );
}

// =============================================================================
// METRIC STATS
// =============================================================================

/// Aggregated statistics for a named metric.
class MetricStats {
  /// Metric name.
  final String name;

  /// All recorded values.
  final List<double> values;

  const MetricStats({required this.name, required this.values});

  /// Number of recorded samples.
  int get count => values.length;

  /// Mean (average) value.
  double get mean {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Minimum value.
  double get min {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a < b ? a : b);
  }

  /// Maximum value.
  double get max {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a > b ? a : b);
  }

  /// Standard deviation.
  double get stddev {
    if (values.length < 2) return 0.0;
    final m = mean;
    final variance =
        values.map((v) => (v - m) * (v - m)).reduce((a, b) => a + b) /
        values.length;
    return _sqrt(variance);
  }

  /// P95 percentile.
  double get p95 {
    if (values.isEmpty) return 0.0;
    final sorted = List<double>.from(values)..sort();
    final index = ((sorted.length - 1) * 0.95).round();
    return sorted[index];
  }

  /// Simple sqrt implementation to avoid dart:math import.
  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'count': count,
    'mean': mean,
    'min': min,
    'max': max,
    'stddev': stddev,
    'p95': p95,
  };

  @override
  String toString() =>
      'MetricStats($name, n=$count, mean=${mean.toStringAsFixed(2)}, '
      'p95=${p95.toStringAsFixed(2)})';
}

// =============================================================================
// PERFORMANCE CHECK RESULT
// =============================================================================

/// Result of checking a metric against its baseline.
class PerformanceCheckResult {
  /// Whether a regression was detected.
  final bool isRegression;

  /// Current measured value.
  final double currentValue;

  /// Baseline mean value.
  final double baselineMean;

  /// Percentage change from baseline.
  final double changePercent;

  /// The configured threshold that was used.
  final double threshold;

  /// Human-readable summary.
  final String summary;

  const PerformanceCheckResult({
    required this.isRegression,
    required this.currentValue,
    required this.baselineMean,
    required this.changePercent,
    required this.threshold,
    required this.summary,
  });

  Map<String, dynamic> toJson() => {
    'isRegression': isRegression,
    'currentValue': currentValue,
    'baselineMean': baselineMean,
    'changePercent': changePercent,
    'threshold': threshold,
    'summary': summary,
  };

  @override
  String toString() => summary;
}

// =============================================================================
// PERFORMANCE BASELINE
// =============================================================================

/// Tracks performance baselines and detects regressions.
///
/// Records named metrics over time and compares new measurements
/// against the baseline mean with configurable thresholds.
class PerformanceBaseline {
  /// Recorded metrics grouped by name.
  final Map<String, List<PerformanceMetric>> _metrics = {};

  /// Create an empty performance baseline.
  PerformanceBaseline();

  /// Record a new measurement.
  void record(String name, double value) {
    (_metrics[name] ??= []).add(PerformanceMetric(name: name, value: value));
  }

  /// Record multiple values at once.
  void recordAll(String name, List<double> values) {
    for (final v in values) {
      record(name, v);
    }
  }

  /// Get aggregated statistics for a metric.
  MetricStats? stats(String name) {
    final list = _metrics[name];
    if (list == null || list.isEmpty) return null;
    return MetricStats(name: name, values: list.map((m) => m.value).toList());
  }

  /// All recorded metric names.
  List<String> get metricNames => _metrics.keys.toList();

  /// Check if [currentValue] represents a regression for [name].
  ///
  /// [threshold] is the fractional change allowed (e.g. 0.1 = 10%).
  /// A metric is considered regressed if `currentValue > baselineMean * (1 + threshold)`.
  PerformanceCheckResult check(
    String name,
    double currentValue, {
    double threshold = 0.1,
  }) {
    final s = stats(name);

    if (s == null || s.count == 0) {
      return PerformanceCheckResult(
        isRegression: false,
        currentValue: currentValue,
        baselineMean: 0,
        changePercent: 0,
        threshold: threshold,
        summary: 'No baseline for "$name" — recording as first measurement',
      );
    }

    final baselineMean = s.mean;
    final changePercent =
        baselineMean > 0
            ? ((currentValue - baselineMean) / baselineMean) * 100.0
            : 0.0;
    final regressionLimit = baselineMean * (1 + threshold);
    final isRegression = currentValue > regressionLimit;

    return PerformanceCheckResult(
      isRegression: isRegression,
      currentValue: currentValue,
      baselineMean: baselineMean,
      changePercent: changePercent,
      threshold: threshold,
      summary:
          isRegression
              ? 'REGRESSION: "$name" is ${changePercent.toStringAsFixed(1)}% '
                  'above baseline (${currentValue.toStringAsFixed(2)} vs '
                  '${baselineMean.toStringAsFixed(2)}, limit: '
                  '${regressionLimit.toStringAsFixed(2)})'
              : 'OK: "$name" within ${(threshold * 100).toStringAsFixed(0)}% '
                  'threshold (${currentValue.toStringAsFixed(2)} vs '
                  '${baselineMean.toStringAsFixed(2)})',
    );
  }

  /// Check all metrics against new values.
  Map<String, PerformanceCheckResult> checkAll(
    Map<String, double> currentValues, {
    double threshold = 0.1,
  }) {
    return {
      for (final entry in currentValues.entries)
        entry.key: check(entry.key, entry.value, threshold: threshold),
    };
  }

  /// Clear all recorded metrics.
  void clear() => _metrics.clear();

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'metrics': {
      for (final entry in _metrics.entries)
        entry.key: entry.value.map((m) => m.toJson()).toList(),
    },
  };

  /// Deserialize from JSON.
  factory PerformanceBaseline.fromJson(Map<String, dynamic> json) {
    final baseline = PerformanceBaseline();
    final metrics = json['metrics'] as Map<String, dynamic>?;
    if (metrics != null) {
      for (final entry in metrics.entries) {
        final list = entry.value as List;
        for (final item in list) {
          final metric = PerformanceMetric.fromJson(
            item as Map<String, dynamic>,
          );
          (baseline._metrics[entry.key] ??= []).add(metric);
        }
      }
    }
    return baseline;
  }

  @override
  String toString() =>
      'PerformanceBaseline(metrics=${_metrics.length}, '
      'samples=${_metrics.values.fold<int>(0, (s, l) => s + l.length)})';
}
