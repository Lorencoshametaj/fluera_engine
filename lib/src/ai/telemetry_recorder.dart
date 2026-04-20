/// 📊 Abstract sink for fire-and-forget product telemetry events.
///
/// The engine doesn't know (and shouldn't know) how events are transported —
/// Supabase, PostHog, Firebase, a local log file, /dev/null. The host app
/// supplies a concrete implementation via [FlueraCanvasConfig.telemetry].
///
/// Contract:
///   - Never throws. Failures are the implementation's problem.
///   - Non-blocking. [logEvent] must return synchronously; any network I/O
///     happens in the background.
///   - Host-side consent gating. Implementations are expected to check
///     GDPR consent before transmitting; the engine emits events
///     unconditionally.
///   - PII-free payloads. Callers must not pass note content, email,
///     personal names, etc. Enforced by convention + code review.
abstract class TelemetryRecorder {
  void logEvent(String eventType, {Map<String, dynamic>? properties});

  /// Singleton no-op recorder. Use when telemetry is disabled or not wired,
  /// so callers can emit events unconditionally without null checks.
  static const TelemetryRecorder noop = _NoopTelemetryRecorder();
}

class _NoopTelemetryRecorder implements TelemetryRecorder {
  const _NoopTelemetryRecorder();

  @override
  void logEvent(String eventType, {Map<String, dynamic>? properties}) {}
}
