/// 📊 DASHBOARD ENDPOINT — Health, metrics, and alerts API model.
///
/// Provides a structured snapshot of engine state for monitoring
/// dashboards, health checks, and alerting systems.
///
/// ```dart
/// final endpoint = DashboardEndpoint();
/// endpoint.registerSubsystem('rendering', () => SubsystemHealth(...));
/// final snapshot = endpoint.snapshot();
/// ```
library;

// =============================================================================
// HEALTH STATUS
// =============================================================================

/// Overall health status.
enum HealthLevel {
  /// All systems nominal.
  healthy,

  /// Some degradation, still functional.
  degraded,

  /// Critical issues, may be non-functional.
  unhealthy,
}

/// Health status of a single subsystem.
class SubsystemHealth {
  /// Subsystem name.
  final String name;

  /// Health level.
  final HealthLevel level;

  /// Human-readable status message.
  final String message;

  /// Key metrics for this subsystem.
  final Map<String, dynamic> metrics;

  /// Timestamp (epoch ms).
  final int timestampMs;

  const SubsystemHealth({
    required this.name,
    required this.level,
    this.message = 'OK',
    this.metrics = const {},
    this.timestampMs = 0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'level': level.name,
    'message': message,
    'metrics': metrics,
    'timestampMs': timestampMs,
  };
}

// =============================================================================
// METRIC SUMMARY
// =============================================================================

/// Aggregated metric for dashboard display.
class MetricCard {
  /// Metric label (e.g. "Frame Time").
  final String label;

  /// Current value.
  final double value;

  /// Unit (e.g. "ms", "%", "MB").
  final String unit;

  /// Trend direction.
  final MetricTrend trend;

  /// Change from previous period.
  final double? changePercent;

  const MetricCard({
    required this.label,
    required this.value,
    this.unit = '',
    this.trend = MetricTrend.stable,
    this.changePercent,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'value': value,
    'unit': unit,
    'trend': trend.name,
    if (changePercent != null) 'changePercent': changePercent,
  };
}

/// Metric trend direction.
enum MetricTrend { up, down, stable }

// =============================================================================
// ALERT SUMMARY
// =============================================================================

/// A dashboard alert entry.
class DashboardAlert {
  /// Alert identifier.
  final String id;

  /// Severity level.
  final AlertSeverity severity;

  /// Alert message.
  final String message;

  /// Source metric/subsystem.
  final String source;

  /// When the alert was triggered (epoch ms).
  final int triggeredMs;

  /// Whether the alert has been acknowledged.
  bool acknowledged;

  DashboardAlert({
    required this.id,
    required this.severity,
    required this.message,
    required this.source,
    required this.triggeredMs,
    this.acknowledged = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'severity': severity.name,
    'message': message,
    'source': source,
    'triggeredMs': triggeredMs,
    'acknowledged': acknowledged,
  };
}

/// Alert severity.
enum AlertSeverity { info, warning, critical }

// =============================================================================
// DASHBOARD ENDPOINT
// =============================================================================

/// Central dashboard API providing health + metrics + alerts snapshot.
class DashboardEndpoint {
  final Map<String, SubsystemHealth Function()> _subsystems = {};
  final List<MetricCard> _metricCards = [];
  final List<DashboardAlert> _alerts = [];
  int _alertIdCounter = 0;

  /// Register a subsystem health provider.
  void registerSubsystem(String name, SubsystemHealth Function() provider) {
    _subsystems[name] = provider;
  }

  /// Unregister a subsystem.
  void unregisterSubsystem(String name) => _subsystems.remove(name);

  /// Add a metric card to the dashboard.
  void addMetricCard(MetricCard card) => _metricCards.add(card);

  /// Clear all metric cards.
  void clearMetricCards() => _metricCards.clear();

  /// Update metric cards (replace all).
  void updateMetricCards(List<MetricCard> cards) {
    _metricCards
      ..clear()
      ..addAll(cards);
  }

  /// Raise an alert.
  DashboardAlert raiseAlert({
    required AlertSeverity severity,
    required String message,
    required String source,
  }) {
    final alert = DashboardAlert(
      id: 'alert-${++_alertIdCounter}',
      severity: severity,
      message: message,
      source: source,
      triggeredMs: DateTime.now().millisecondsSinceEpoch,
    );
    _alerts.add(alert);
    return alert;
  }

  /// Acknowledge an alert by ID.
  void acknowledgeAlert(String id) {
    for (final alert in _alerts) {
      if (alert.id == id) {
        alert.acknowledged = true;
        break;
      }
    }
  }

  /// Get active (unacknowledged) alerts.
  List<DashboardAlert> get activeAlerts =>
      _alerts.where((a) => !a.acknowledged).toList();

  /// Get all alerts.
  List<DashboardAlert> get allAlerts => List.unmodifiable(_alerts);

  /// Overall engine health (worst of all subsystems).
  HealthLevel get overallHealth {
    if (_subsystems.isEmpty) return HealthLevel.healthy;

    var worst = HealthLevel.healthy;
    for (final provider in _subsystems.values) {
      final health = provider();
      if (health.level.index > worst.index) {
        worst = health.level;
      }
    }
    return worst;
  }

  /// Generate a complete dashboard snapshot.
  Map<String, dynamic> snapshot() {
    final subsystemHealths = <String, Map<String, dynamic>>{};
    for (final entry in _subsystems.entries) {
      subsystemHealths[entry.key] = entry.value().toJson();
    }

    return {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'overallHealth': overallHealth.name,
      'subsystems': subsystemHealths,
      'metrics': _metricCards.map((c) => c.toJson()).toList(),
      'alerts': {
        'active': activeAlerts.map((a) => a.toJson()).toList(),
        'total': _alerts.length,
        'acknowledged': _alerts.where((a) => a.acknowledged).length,
      },
    };
  }

  /// Clear all alerts.
  void clearAlerts() => _alerts.clear();

  /// Reset everything.
  void reset() {
    _subsystems.clear();
    _metricCards.clear();
    _alerts.clear();
  }
}
