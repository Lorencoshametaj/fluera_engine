// ============================================================================
// 💰 AiBudgetMonitor — Unit tests
//
// Verifies:
//   - Threshold crossings emit telemetry (70%/90%/100%)
//   - Single emission per threshold (no spam on near-threshold updates)
//   - Per-feature breakdown accumulates correctly
//   - Top spender reflects largest contributor
//   - resetPeriod() clears state and re-arms threshold emission
//   - Decorator does NOT modify the wrapped tracker's contract
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/ai_usage_tracker.dart';
import 'package:fluera_engine/src/ai/billing/budget_monitor.dart';
import 'package:fluera_engine/src/ai/telemetry_recorder.dart';

void main() {
  late _FakeTracker tracker;
  late _CapturingTelemetry telemetry;
  late AiBudgetMonitor monitor;

  setUp(() {
    tracker = _FakeTracker();
    telemetry = _CapturingTelemetry();
    monitor = AiBudgetMonitor(tracker: tracker, telemetry: telemetry);
  });

  tearDown(() => monitor.dispose());

  group('Threshold emission on quota changes', () {
    test('No threshold event when usage < 70%', () {
      tracker.setQuota(used: 600, limit: 1000); // 60%
      expect(telemetry.events, isEmpty);
    });

    test('70% threshold emits warning70', () {
      tracker.setQuota(used: 700, limit: 1000);
      expect(telemetry.events, hasLength(1));
      expect(telemetry.events.single.props['threshold'], 'warning70');
      expect(telemetry.events.single.props['fraction'], 0.7);
    });

    test('90% threshold emits warning90 (after 70%)', () {
      tracker.setQuota(used: 700, limit: 1000); // emits warning70
      tracker.setQuota(used: 900, limit: 1000); // emits warning90
      expect(telemetry.events, hasLength(2));
      expect(telemetry.events.last.props['threshold'], 'warning90');
    });

    test('100% threshold emits exhausted', () {
      tracker.setQuota(used: 1000, limit: 1000);
      // 70 → 90 → 100 all crossed at once; only the highest emits per
      // the "crossing" semantics (we don't backfill).
      expect(telemetry.events, hasLength(1));
      expect(telemetry.events.single.props['threshold'], 'exhausted');
    });

    test('Crossings only emit ONCE — no spam on subsequent updates', () {
      tracker.setQuota(used: 700, limit: 1000); // warning70
      tracker.setQuota(used: 750, limit: 1000); // still 75%, no event
      tracker.setQuota(used: 800, limit: 1000); // still 80%, no event
      expect(telemetry.events, hasLength(1));
    });

    test('Going BACKWARDS (e.g. period reset) does NOT re-emit', () {
      tracker.setQuota(used: 950, limit: 1000); // warning90
      tracker.setQuota(used: 100, limit: 1000); // back to 10%, no event
      expect(telemetry.events, hasLength(1));
    });
  });

  group('Per-feature breakdown', () {
    test('recordSpend accumulates per feature', () {
      monitor.recordSpend('chat', 100);
      monitor.recordSpend('exam', 250);
      monitor.recordSpend('chat', 50);
      final s = monitor.snapshot.value;
      expect(s.featureBreakdown, {'chat': 150, 'exam': 250});
      expect(s.totalTokens, 400);
    });

    test('Zero/negative tokens are ignored', () {
      monitor.recordSpend('chat', 100);
      monitor.recordSpend('chat', 0);
      monitor.recordSpend('chat', -50);
      expect(monitor.snapshot.value.featureBreakdown['chat'], 100);
    });

    test('topSpender returns largest contributor', () {
      monitor.recordSpend('chat', 100);
      monitor.recordSpend('exam', 500);
      monitor.recordSpend('socratic', 300);
      expect(monitor.snapshot.value.topSpender, 'exam');
    });

    test('topSpender is null with no recorded spend', () {
      expect(monitor.snapshot.value.topSpender, isNull);
    });

    test('Threshold event payload carries top_spender', () {
      monitor.recordSpend('chat', 500);
      monitor.recordSpend('exam', 100);
      tracker.setQuota(used: 800, limit: 1000); // warning70 crossed
      expect(telemetry.events.single.props['top_spender'], 'chat');
    });
  });

  group('resetPeriod — period rollover semantics', () {
    test('Clears breakdown + re-arms threshold emission', () {
      monitor.recordSpend('chat', 100);
      tracker.setQuota(used: 950, limit: 1000); // warning90 emits
      expect(telemetry.events, hasLength(1));

      monitor.resetPeriod();
      expect(monitor.snapshot.value.featureBreakdown, isEmpty);
      expect(monitor.snapshot.value.thresholdReached, isNull);

      // After reset, crossing 70% again emits a fresh event.
      tracker.setQuota(used: 100, limit: 1000); // back to 10%
      tracker.setQuota(used: 700, limit: 1000); // 70% again
      expect(telemetry.events, hasLength(2));
      expect(telemetry.events.last.props['threshold'], 'warning70');
    });
  });

  group('Snapshot reactivity', () {
    test('snapshot updates on tracker quota change', () {
      var notifications = 0;
      monitor.snapshot.addListener(() => notifications++);
      tracker.setQuota(used: 100, limit: 1000);
      tracker.setQuota(used: 200, limit: 1000);
      expect(notifications, 2);
    });

    test('snapshot updates on recordSpend', () {
      var notifications = 0;
      monitor.snapshot.addListener(() => notifications++);
      monitor.recordSpend('chat', 50);
      monitor.recordSpend('exam', 100);
      expect(notifications, 2);
    });
  });
}

// ─── Test helpers ───────────────────────────────────────────────────────────

class _FakeTracker implements AiUsageTracker {
  final ValueNotifier<AiQuotaSnapshot?> _quota =
      ValueNotifier<AiQuotaSnapshot?>(null);

  void setQuota({required int used, required int limit, String tier = 'free'}) {
    _quota.value = AiQuotaSnapshot(
      tokensUsed: used,
      tokensLimit: limit,
      tier: tier,
      periodEnd: DateTime.now().add(const Duration(days: 30)),
    );
  }

  @override
  ValueListenable<AiQuotaSnapshot?> get quota => _quota;

  @override
  Stream<AiQuotaExceededException> get exceededEvents => const Stream.empty();

  @override
  Stream<AiRateLimitedException> get rateLimitedEvents => const Stream.empty();

  @override
  Stream<GhostMapCapExceededException> get ghostMapCapEvents =>
      const Stream.empty();

  @override
  Future<AiQuotaSnapshot?> refresh() async => _quota.value;

  @override
  Future<void> ensureBalance({int estimate = 500, String? feature}) async {}

  @override
  Future<void> recordUsage(
    int tokens,
    String feature, {
    int? inputTokens,
    int? outputTokens,
    String? model,
  }) async {}

  @override
  void dispose() {
    _quota.dispose();
  }
}

class _CapturingTelemetry implements TelemetryRecorder {
  final List<({String event, Map<String, dynamic> props})> events = [];

  @override
  void logEvent(String eventType, {Map<String, dynamic>? properties}) {
    events.add((event: eventType, props: properties ?? const {}));
  }
}
