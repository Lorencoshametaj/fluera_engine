// ============================================================================
// 🎙️ VOICE QUOTA — Unit tests for the engine-side primitives
//
// Covers:
//   • VoiceQuotaSnapshot: derived getters (isUnlimited, canRecord, etc.)
//   • VoiceQuotaExhaustedException: payload fields
//   • NoopVoiceQuotaTracker: every operation succeeds without blocking
//   • VoiceRecordButtonPhase: enum sanity (full value set)
//
// The Supabase-backed impl is integration-tested in the Fluera app suite.
// ============================================================================

import 'package:fluera_engine/fluera_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceQuotaSnapshot', () {
    VoiceQuotaSnapshot snap({
      int used = 0,
      int limit = 60,
      String tier = 'plus',
    }) =>
        VoiceQuotaSnapshot(
          minutesUsed: used,
          minutesLimit: limit,
          tier: tier,
          monthlyResetAt: DateTime.utc(2030, 1, 1),
        );

    test('isUnlimited fires only on the -1 sentinel', () {
      expect(snap(limit: voiceMinutesUnlimited).isUnlimited, isTrue);
      expect(snap(limit: 0).isUnlimited, isFalse);
      expect(snap(limit: 60).isUnlimited, isFalse);
    });

    test('minutesRemaining clamps at 0 (never negative)', () {
      expect(snap(used: 30, limit: 60).minutesRemaining, 30);
      expect(snap(used: 80, limit: 60).minutesRemaining, 0);
      expect(snap(used: 60, limit: 60).minutesRemaining, 0);
    });

    test('minutesRemaining returns -1 sentinel for unlimited', () {
      expect(snap(limit: voiceMinutesUnlimited).minutesRemaining,
          voiceMinutesUnlimited);
    });

    test('isExhausted only at full burn (not on overdraft)', () {
      expect(snap(used: 0, limit: 60).isExhausted, isFalse);
      expect(snap(used: 60, limit: 60).isExhausted, isTrue);
      expect(snap(used: 61, limit: 60).isExhausted, isTrue);
      expect(snap(used: 60, limit: voiceMinutesUnlimited).isExhausted, isFalse,
          reason: 'Unlimited tier is never exhausted');
    });

    test('usedFraction reports consumed share', () {
      expect(snap(used: 30, limit: 60).usedFraction, closeTo(0.5, 0.0001));
      expect(snap(used: 100, limit: 60).usedFraction, 1.0);
    });

    test('usedFraction is 0 for unlimited (no progress bar)', () {
      expect(snap(limit: voiceMinutesUnlimited).usedFraction, 0.0);
    });

    test('canRecord returns true while there is enough headroom', () {
      final s = snap(used: 55, limit: 60);
      expect(s.canRecord(requestedMinutes: 1), isTrue);
      expect(s.canRecord(requestedMinutes: 5), isTrue);
      expect(s.canRecord(requestedMinutes: 6), isFalse);
    });

    test('canRecord is always true for unlimited tier', () {
      final s = snap(used: 9999, limit: voiceMinutesUnlimited);
      expect(s.canRecord(requestedMinutes: 1000000), isTrue);
    });
  });

  group('VoiceQuotaExhaustedException', () {
    test('carries all the payload fields for UI rendering', () {
      final exc = VoiceQuotaExhaustedException(
        requestedMinutes: 5,
        minutesRemaining: 2,
        resetAt: DateTime.utc(2030, 1, 1),
        tier: 'plus',
      );
      expect(exc.requestedMinutes, 5);
      expect(exc.minutesRemaining, 2);
      expect(exc.resetAt, DateTime.utc(2030, 1, 1));
      expect(exc.tier, 'plus');
    });
  });

  group('NoopVoiceQuotaTracker', () {
    test('reserve always succeeds and returns a token', () async {
      final tracker = NoopVoiceQuotaTracker();
      final token = await tracker.reserve(estimateMinutes: 30);
      expect(token, startsWith('noop-'));
      tracker.dispose();
    });

    test('commit / refund do not throw', () async {
      final tracker = NoopVoiceQuotaTracker();
      await tracker.commit(reservationToken: 'noop-x', actualMinutes: 12);
      await tracker.refund('noop-x');
      tracker.dispose();
    });

    test('default snapshot carries an unlimited limit so happy paths run',
        () {
      final tracker = NoopVoiceQuotaTracker();
      final s = tracker.quota.value;
      expect(s, isNotNull);
      expect(s!.isUnlimited, isTrue);
      tracker.dispose();
    });

    test('updateTier mutates the snapshot tier field', () async {
      final tracker = NoopVoiceQuotaTracker();
      await tracker.updateTier('pro');
      expect(tracker.quota.value?.tier, 'pro');
      tracker.dispose();
    });
  });

  group('VoiceRecordButtonPhase enum', () {
    test('contains every phase the widget can reach', () {
      expect(
        VoiceRecordButtonPhase.values.toSet(),
        {
          VoiceRecordButtonPhase.idle,
          VoiceRecordButtonPhase.reserving,
          VoiceRecordButtonPhase.recording,
          VoiceRecordButtonPhase.stopping,
          VoiceRecordButtonPhase.exhausted,
        },
      );
    });
  });
}
