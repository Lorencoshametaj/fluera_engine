import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/analytics/usage_analytics.dart';

void main() {
  late UsageAnalytics analytics;

  setUp(() {
    analytics = UsageAnalytics();
  });

  // ===========================================================================
  // Sessions
  // ===========================================================================

  group('UsageAnalytics - sessions', () {
    test('starts a session', () {
      final session = analytics.startSession(userId: 'u1');
      expect(session.userId, 'u1');
      expect(session.isActive, isTrue);
    });

    test('ends a session', () {
      analytics.startSession(userId: 'u1');
      analytics.endSession();
      expect(analytics.currentSession, isNull);
    });

    test('tracks multiple sessions', () {
      analytics.startSession(userId: 'u1');
      analytics.endSession();
      analytics.startSession(userId: 'u2');
      analytics.endSession();
      expect(analytics.sessions.length, 2);
    });
  });

  // ===========================================================================
  // Tool Usage
  // ===========================================================================

  group('UsageAnalytics - tools', () {
    test('tracks tool usage', () {
      analytics.trackToolUse('pen');
      final entry = analytics.getToolUsage('pen');
      expect(entry, isNotNull);
      expect(entry!.useCount, 1);
    });

    test('increments use count', () {
      analytics.trackToolUse('pen');
      analytics.trackToolUse('pen');
      expect(analytics.getToolUsage('pen')!.useCount, 2);
    });

    test('heat map is sorted by count', () {
      analytics.trackToolUse('pen');
      analytics.trackToolUse('eraser');
      analytics.trackToolUse('eraser');
      final heatMap = analytics.toolHeatMap;
      expect(heatMap.first.toolId, 'eraser');
    });
  });

  // ===========================================================================
  // Event Funnels
  // ===========================================================================

  group('UsageAnalytics - funnels', () {
    test('creates funnel', () {
      final f = analytics.funnel('signup', ['view', 'click', 'submit']);
      expect(f.steps.length, 3);
    });

    test('records funnel steps', () {
      final f = analytics.funnel('signup', ['view', 'click', 'submit']);
      f.recordStep('view');
      f.recordStep('view');
      f.recordStep('click');
      expect(f.countFor('view'), 2);
      expect(f.countFor('click'), 1);
    });

    test('conversion rate computed', () {
      final f = analytics.funnel('test', ['a', 'b']);
      f.recordStep('a');
      f.recordStep('a');
      f.recordStep('b');
      expect(f.conversionRate('a', 'b'), closeTo(0.5, 0.01));
    });

    test('drop-off analysis', () {
      final f = analytics.funnel('test', ['a', 'b', 'c']);
      f.recordStep('a');
      f.recordStep('a');
      f.recordStep('b');
      final analysis = f.dropOffAnalysis();
      expect(analysis.length, 3);
    });

    test('getFunnel returns existing', () {
      analytics.funnel('f1', ['a']);
      expect(analytics.getFunnel('f1'), isNotNull);
    });
  });

  // ===========================================================================
  // Report
  // ===========================================================================

  group('UsageAnalytics - report', () {
    test('generates report', () {
      analytics.startSession(userId: 'u1');
      analytics.trackToolUse('pen');
      analytics.endSession();
      final report = analytics.generateReport();
      expect(report['totalSessions'], 1);
    });
  });

  // ===========================================================================
  // Reset
  // ===========================================================================

  group('UsageAnalytics - reset', () {
    test('clears all data', () {
      analytics.startSession(userId: 'u1');
      analytics.trackToolUse('pen');
      analytics.reset();
      expect(analytics.sessions, isEmpty);
      expect(analytics.getToolUsage('pen'), isNull);
    });
  });

  // ===========================================================================
  // Models
  // ===========================================================================

  group('ToolUsageEntry', () {
    test('toJson serializes', () {
      final entry = ToolUsageEntry(toolId: 'pen', useCount: 5);
      final json = entry.toJson();
      expect(json['toolId'], 'pen');
    });
  });

  group('AnalyticsSession', () {
    test('toJson serializes', () {
      final session = AnalyticsSession(
        id: 's1',
        userId: 'u1',
        startTimeMs: 1000,
      );
      final json = session.toJson();
      expect(json['id'], 's1');
    });
  });
}
