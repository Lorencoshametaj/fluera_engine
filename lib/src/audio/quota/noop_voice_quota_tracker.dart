// ============================================================================
// 🎙️ NO-OP VOICE QUOTA TRACKER — Engine default when no host is injected
//
// Treats every tier as unlimited so SDK builds run without a backend.
// Tests that need quota assertions should swap in a fake implementation.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_quota_tracker.dart';

class NoopVoiceQuotaTracker implements VoiceQuotaTracker {
  NoopVoiceQuotaTracker();

  final ValueNotifier<VoiceQuotaSnapshot?> _quota =
      ValueNotifier<VoiceQuotaSnapshot?>(
    VoiceQuotaSnapshot(
      minutesUsed: 0,
      minutesLimit: voiceMinutesUnlimited,
      tier: 'free',
      monthlyResetAt: DateTime.utc(2100, 1, 1),
    ),
  );

  final StreamController<VoiceQuotaExhaustedException> _exhaustedCtrl =
      StreamController<VoiceQuotaExhaustedException>.broadcast();

  @override
  ValueListenable<VoiceQuotaSnapshot?> get quota => _quota;

  @override
  Stream<VoiceQuotaExhaustedException> get exhaustedEvents =>
      _exhaustedCtrl.stream;

  @override
  Future<VoiceQuotaSnapshot?> refresh() async => _quota.value;

  @override
  Future<String> reserve({int estimateMinutes = 1}) async {
    return 'noop-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  Future<void> commit({
    required String reservationToken,
    required int actualMinutes,
  }) async {}

  @override
  Future<void> refund(String reservationToken) async {}

  @override
  Future<void> updateTier(String tier) async {
    final current = _quota.value;
    if (current != null) {
      _quota.value = current.copyWith(tier: tier);
    }
  }

  @override
  void dispose() {
    _quota.dispose();
    _exhaustedCtrl.close();
  }
}
