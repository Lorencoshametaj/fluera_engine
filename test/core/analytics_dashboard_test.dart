import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/analytics/usage_analytics.dart';
import 'package:nebula_engine/src/core/analytics/metric_exporter.dart';
import 'package:nebula_engine/src/core/analytics/dashboard_endpoint.dart';
import 'package:nebula_engine/src/core/analytics/feature_flag_service.dart';

void main() {
  // ===========================================================================
  // USAGE ANALYTICS
  // ===========================================================================

  group('UsageAnalytics', () {
    test('session lifecycle', () {
      final analytics = UsageAnalytics();
      final session = analytics.startSession(userId: 'u-1');
      expect(session.isActive, isTrue);
      expect(analytics.currentSession, isNotNull);

      analytics.endSession();
      expect(session.isActive, isFalse);
      expect(analytics.currentSession, isNull);
      expect(analytics.sessions.length, 1);
    });

    test('tool usage tracking', () {
      final analytics = UsageAnalytics();
      analytics.startSession(userId: 'u-1');
      analytics.trackToolUse('pen');
      analytics.trackToolUse('pen');
      analytics.trackToolUse('eraser');
      analytics.stopToolUse();

      final heatMap = analytics.toolHeatMap;
      expect(heatMap.length, 2);
      expect(heatMap[0].toolId, 'pen');
      expect(heatMap[0].useCount, 2);
      expect(heatMap[1].toolId, 'eraser');
    });

    test('event funnel', () {
      final analytics = UsageAnalytics();
      final funnel = analytics.funnel('signup', ['visit', 'click', 'submit']);

      funnel.recordStep('visit');
      funnel.recordStep('visit');
      funnel.recordStep('click');
      funnel.recordStep('submit');

      expect(funnel.countFor('visit'), 2);
      expect(funnel.conversionRate('visit', 'click'), 0.5);
    });

    test('funnel drop-off analysis', () {
      final analytics = UsageAnalytics();
      final funnel = analytics.funnel('flow', ['a', 'b', 'c']);
      funnel.recordStep('a');
      funnel.recordStep('a');
      funnel.recordStep('b');

      final analysis = funnel.dropOffAnalysis();
      expect(analysis.length, 3);
      expect(analysis[1]['dropOff'], closeTo(0.5, 0.01));
    });

    test('generate report', () {
      final analytics = UsageAnalytics();
      analytics.startSession(userId: 'u-1');
      analytics.trackToolUse('pen');
      analytics.endSession();

      final report = analytics.generateReport();
      expect(report['totalSessions'], 1);
      expect(report['toolUsage'], isNotEmpty);
    });

    test('reset clears everything', () {
      final analytics = UsageAnalytics();
      analytics.startSession(userId: 'u-1');
      analytics.trackToolUse('pen');
      analytics.reset();

      expect(analytics.sessions, isEmpty);
      expect(analytics.toolHeatMap, isEmpty);
    });
  });

  // ===========================================================================
  // METRIC EXPORTER
  // ===========================================================================

  group('MetricExporter', () {
    final snapshot = <String, dynamic>{
      'counters': {'repairs': 42, 'errors': 3},
      'gauges': {'memory_mb': 280.5},
      'histograms': {
        'frame_ms': {
          'count': 100,
          'sum': 1400.0,
          'min': 8.0,
          'max': 32.0,
          'p50': 14.0,
          'p95': 28.0,
        },
      },
    };

    test('Prometheus format contains metric lines', () {
      final output = PrometheusExporter.format(snapshot);
      expect(output, contains('nebula_counter_repairs 42'));
      expect(output, contains('# TYPE nebula_gauge_memory_mb gauge'));
      expect(output, contains('nebula_histogram_frame_ms_count'));
    });

    test('Prometheus with labels', () {
      final output = PrometheusExporter.format(
        snapshot,
        globalLabels: {'instance': 'engine-01'},
      );
      expect(output, contains('instance="engine-01"'));
    });

    test('Prometheus sanitizes names', () {
      final dirty = <String, dynamic>{
        'counters': {'my.weird-name': 1},
      };
      final output = PrometheusExporter.format(dirty);
      expect(output, contains('nebula_counter_my_weird_name'));
    });

    test('JSON Lines format generates lines', () {
      final output = JsonLinesExporter.format(snapshot, source: 'engine-01');
      final lines = output.trim().split('\n');
      expect(lines.length, greaterThan(2));
      expect(lines[0], contains('"type":"counter"'));
      expect(lines[0], contains('"source":"engine-01"'));
    });

    test('metricLine helper', () {
      final line = PrometheusExporter.metricLine(
        'test_metric',
        42,
        labels: {'env': 'prod'},
      );
      expect(line, contains('test_metric'));
      expect(line, contains('env="prod"'));
    });
  });

  // ===========================================================================
  // DASHBOARD ENDPOINT
  // ===========================================================================

  group('DashboardEndpoint', () {
    test('register subsystem and check health', () {
      final dashboard = DashboardEndpoint();
      dashboard.registerSubsystem(
        'rendering',
        () => SubsystemHealth(
          name: 'rendering',
          level: HealthLevel.healthy,
          message: 'All good',
        ),
      );
      expect(dashboard.overallHealth, HealthLevel.healthy);
    });

    test('overall health is worst of all', () {
      final dashboard = DashboardEndpoint();
      dashboard.registerSubsystem(
        'a',
        () => SubsystemHealth(name: 'a', level: HealthLevel.healthy),
      );
      dashboard.registerSubsystem(
        'b',
        () => SubsystemHealth(name: 'b', level: HealthLevel.degraded),
      );
      expect(dashboard.overallHealth, HealthLevel.degraded);
    });

    test('raise and acknowledge alerts', () {
      final dashboard = DashboardEndpoint();
      final alert = dashboard.raiseAlert(
        severity: AlertSeverity.warning,
        message: 'Memory high',
        source: 'memory',
      );
      expect(dashboard.activeAlerts.length, 1);

      dashboard.acknowledgeAlert(alert.id);
      expect(dashboard.activeAlerts.length, 0);
      expect(dashboard.allAlerts.length, 1);
    });

    test('metric cards CRUD', () {
      final dashboard = DashboardEndpoint();
      dashboard.addMetricCard(
        const MetricCard(label: 'FPS', value: 60, unit: 'fps'),
      );
      final snap = dashboard.snapshot();
      final metrics = snap['metrics'] as List;
      expect(metrics.length, 1);
    });

    test('snapshot contains all sections', () {
      final dashboard = DashboardEndpoint();
      dashboard.registerSubsystem(
        'test',
        () => SubsystemHealth(name: 'test', level: HealthLevel.healthy),
      );
      final snap = dashboard.snapshot();
      expect(snap.containsKey('overallHealth'), isTrue);
      expect(snap.containsKey('subsystems'), isTrue);
      expect(snap.containsKey('metrics'), isTrue);
      expect(snap.containsKey('alerts'), isTrue);
    });
  });

  // ===========================================================================
  // FEATURE FLAG SERVICE
  // ===========================================================================

  group('FeatureFlagService', () {
    test('define and evaluate boolean flag', () {
      final flags = FeatureFlagService();
      flags.define(FeatureFlag.boolean('dark_mode', defaultValue: true));
      expect(flags.isEnabled('dark_mode'), isTrue);
      flags.dispose();
    });

    test('string flag', () {
      final flags = FeatureFlagService();
      flags.define(FeatureFlag.string('theme', defaultValue: 'ocean'));
      expect(flags.stringValue('theme'), 'ocean');
      flags.dispose();
    });

    test('number flag', () {
      final flags = FeatureFlagService();
      flags.define(FeatureFlag.number('max_layers', defaultValue: 100));
      expect(flags.numberValue('max_layers'), 100.0);
      flags.dispose();
    });

    test('override takes precedence', () {
      final flags = FeatureFlagService();
      flags.define(FeatureFlag.boolean('feature_x', defaultValue: false));
      flags.setOverride('feature_x', true);
      expect(flags.isEnabled('feature_x'), isTrue);
      flags.dispose();
    });

    test('scoped override with active scopes', () {
      final flags = FeatureFlagService(activeScopes: ['user:u-123']);
      flags.define(FeatureFlag.boolean('beta', defaultValue: false));
      flags.setOverride('beta', true, scope: 'user:u-123');
      expect(flags.isEnabled('beta'), isTrue);

      // Different scope shouldn't match
      flags.activeScopes = ['user:u-456'];
      expect(flags.isEnabled('beta'), isFalse);
      flags.dispose();
    });

    test('override priority', () {
      final flags = FeatureFlagService(activeScopes: ['user:u-1', 'env:prod']);
      flags.define(FeatureFlag.string('label', defaultValue: 'default'));
      flags.setOverride('label', 'user-level', scope: 'user:u-1', priority: 1);
      flags.setOverride('label', 'env-level', scope: 'env:prod', priority: 10);
      expect(flags.stringValue('label'), 'env-level'); // higher priority
      flags.dispose();
    });

    test('rollout percentage', () {
      // Use fixed seed for determinism
      final flags = FeatureFlagService(random: math.Random(42));
      flags.define(
        FeatureFlag.boolean(
          'experiment',
          defaultValue: true,
          rolloutPercent: 50,
        ),
      );
      // Should return a boolean (either true or false based on random)
      final result = flags.evaluate('experiment');
      expect(result, isA<bool>());
      flags.dispose();
    });

    test('change stream fires on define', () async {
      final flags = FeatureFlagService();
      final changes = <String>[];
      flags.changes.listen(changes.add);

      flags.define(FeatureFlag.boolean('a'));
      await Future.delayed(Duration.zero);

      expect(changes, contains('a'));
      flags.dispose();
    });

    test('serialization round-trip', () {
      final flags = FeatureFlagService();
      flags.define(FeatureFlag.boolean('a', defaultValue: true));
      flags.setOverride('a', false, scope: 'env:test');

      final json = flags.toJson();
      final restored = FeatureFlagService();
      restored.loadFromJson(json);

      expect(restored.getFlag('a'), isNotNull);
      expect(restored.getFlag('a')!.defaultValue, true);
      restored.dispose();
      flags.dispose();
    });

    test('remove flag', () {
      final flags = FeatureFlagService();
      flags.define(FeatureFlag.boolean('x'));
      flags.remove('x');
      expect(flags.getFlag('x'), isNull);
      flags.dispose();
    });

    test('undefined flag returns null', () {
      final flags = FeatureFlagService();
      expect(flags.evaluate('nonexistent'), isNull);
      flags.dispose();
    });
  });
}
