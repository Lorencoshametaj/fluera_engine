import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import 'ai_usage_tracker.dart';

/// Default no-op [AiUsageTracker] used when the host app doesn't wire one in.
///
/// Never enforces a quota, never throws, never records anywhere. Keeps the
/// engine fully functional without a backing Supabase (or equivalent) layer —
/// e.g. in unit tests, the web demo, and the landing page previews.
class NoopAiUsageTracker implements AiUsageTracker {
  final ValueNotifier<AiQuotaSnapshot?> _quota = ValueNotifier<AiQuotaSnapshot?>(null);

  @override
  ValueListenable<AiQuotaSnapshot?> get quota => _quota;

  @override
  Stream<AiQuotaExceededException> get exceededEvents =>
      const Stream<AiQuotaExceededException>.empty();

  @override
  Future<AiQuotaSnapshot?> refresh() async => null;

  @override
  Future<void> ensureBalance({int estimate = 500}) async {}

  @override
  Future<void> recordUsage(int tokens, String feature) async {}

  @override
  void dispose() {
    _quota.dispose();
  }
}
