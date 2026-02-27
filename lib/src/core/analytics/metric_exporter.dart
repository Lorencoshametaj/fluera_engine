/// 📊 METRIC EXPORTER — Prometheus/OpenMetrics and JSON Lines export.
///
/// Converts telemetry snapshots to standard monitoring formats
/// for integration with Prometheus, Grafana, ELK, Splunk, DataDog.
///
/// ```dart
/// final snapshot = telemetry.snapshot();
/// final prometheus = PrometheusExporter.format(snapshot);
/// final jsonLines = JsonLinesExporter.format(snapshot);
/// ```
library;

// =============================================================================
// METRIC TYPE (for Prometheus)
// =============================================================================

/// Prometheus metric type annotations.
enum PrometheusMetricType { counter, gauge, histogram, summary, untyped }

// =============================================================================
// PROMETHEUS EXPORTER
// =============================================================================

/// Exports telemetry data in Prometheus/OpenMetrics text exposition format.
class PrometheusExporter {
  const PrometheusExporter._();

  /// Format a telemetry snapshot as Prometheus text.
  ///
  /// ```
  /// # HELP fluera_counter_integrity_repairs Total repairs
  /// # TYPE fluera_counter_integrity_repairs counter
  /// fluera_counter_integrity_repairs 42
  /// ```
  static String format(
    Map<String, dynamic> snapshot, {
    String prefix = 'fluera',
    Map<String, String>? globalLabels,
  }) {
    final buffer = StringBuffer();
    final labels = _formatLabels(globalLabels);

    // Counters
    final counters = snapshot['counters'] as Map<String, dynamic>? ?? {};
    for (final entry in counters.entries) {
      final name = _sanitizeName('${prefix}_counter_${entry.key}');
      buffer.writeln('# HELP $name Total count of ${entry.key}');
      buffer.writeln('# TYPE $name counter');
      buffer.writeln('$name$labels ${entry.value}');
      buffer.writeln();
    }

    // Gauges
    final gauges = snapshot['gauges'] as Map<String, dynamic>? ?? {};
    for (final entry in gauges.entries) {
      final name = _sanitizeName('${prefix}_gauge_${entry.key}');
      buffer.writeln('# HELP $name Current value of ${entry.key}');
      buffer.writeln('# TYPE $name gauge');
      buffer.writeln('$name$labels ${entry.value}');
      buffer.writeln();
    }

    // Histograms
    final histograms = snapshot['histograms'] as Map<String, dynamic>? ?? {};
    for (final entry in histograms.entries) {
      final name = _sanitizeName('${prefix}_histogram_${entry.key}');
      final data = entry.value as Map<String, dynamic>? ?? {};
      buffer.writeln('# HELP $name Distribution of ${entry.key}');
      buffer.writeln('# TYPE $name summary');
      final count = data['count'] ?? 0;
      final sum = data['sum'] ?? 0;
      buffer.writeln('${name}_count$labels $count');
      buffer.writeln('${name}_sum$labels $sum');
      if (data.containsKey('min')) {
        buffer.writeln('${name}{quantile="0"$labels} ${data['min']}');
      }
      if (data.containsKey('p50')) {
        buffer.writeln('${name}{quantile="0.5"$labels} ${data['p50']}');
      }
      if (data.containsKey('p95')) {
        buffer.writeln('${name}{quantile="0.95"$labels} ${data['p95']}');
      }
      if (data.containsKey('p99')) {
        buffer.writeln('${name}{quantile="0.99"$labels} ${data['p99']}');
      }
      if (data.containsKey('max')) {
        buffer.writeln('${name}{quantile="1"$labels} ${data['max']}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Sanitize a metric name for Prometheus (a-z, A-Z, 0-9, _).
  static String _sanitizeName(String name) =>
      name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

  static String _formatLabels(Map<String, String>? labels) {
    if (labels == null || labels.isEmpty) return '';
    final pairs = labels.entries.map((e) => '${e.key}="${e.value}"').join(',');
    return '{$pairs}';
  }

  /// Format a single metric line.
  static String metricLine(
    String name,
    dynamic value, {
    Map<String, String>? labels,
    int? timestampMs,
  }) {
    final labelStr = _formatLabels(labels);
    final ts = timestampMs != null ? ' $timestampMs' : '';
    return '${_sanitizeName(name)}$labelStr $value$ts';
  }
}

// =============================================================================
// JSON LINES EXPORTER
// =============================================================================

/// Exports telemetry data as JSON Lines (one JSON object per line).
///
/// Compatible with ELK (Elasticsearch), Splunk, DataDog log intake, etc.
class JsonLinesExporter {
  const JsonLinesExporter._();

  /// Format a telemetry snapshot as JSON Lines.
  static String format(
    Map<String, dynamic> snapshot, {
    String? source,
    Map<String, dynamic>? extraFields,
  }) {
    final buffer = StringBuffer();
    final now = DateTime.now().toUtc().toIso8601String();

    // Counters
    final counters = snapshot['counters'] as Map<String, dynamic>? ?? {};
    for (final entry in counters.entries) {
      buffer.writeln(
        _jsonLine({
          'timestamp': now,
          'type': 'counter',
          'metric': entry.key,
          'value': entry.value,
          if (source != null) 'source': source,
          ...?extraFields,
        }),
      );
    }

    // Gauges
    final gauges = snapshot['gauges'] as Map<String, dynamic>? ?? {};
    for (final entry in gauges.entries) {
      buffer.writeln(
        _jsonLine({
          'timestamp': now,
          'type': 'gauge',
          'metric': entry.key,
          'value': entry.value,
          if (source != null) 'source': source,
          ...?extraFields,
        }),
      );
    }

    // Histograms
    final histograms = snapshot['histograms'] as Map<String, dynamic>? ?? {};
    for (final entry in histograms.entries) {
      buffer.writeln(
        _jsonLine({
          'timestamp': now,
          'type': 'histogram',
          'metric': entry.key,
          'stats': entry.value,
          if (source != null) 'source': source,
          ...?extraFields,
        }),
      );
    }

    // Events
    final events = snapshot['events'] as List<dynamic>? ?? [];
    for (final event in events) {
      buffer.writeln(
        _jsonLine({
          'timestamp': now,
          'type': 'event',
          'event': event,
          if (source != null) 'source': source,
          ...?extraFields,
        }),
      );
    }

    return buffer.toString();
  }

  /// Simple JSON serialization (no dependency on dart:convert in signature).
  static String _jsonLine(Map<String, dynamic> data) {
    final pairs = data.entries
        .map((e) {
          final v = e.value;
          final vStr = v is String ? '"$v"' : '$v';
          return '"${e.key}":$vStr';
        })
        .join(',');
    return '{$pairs}';
  }
}
