// ============================================================================
// 📊 PEDAGOGICAL TELEMETRY SERVICE — Opt-in anonymous metrics (A19)
//
// Specifica: A19-01 → A19-10
//
// Tracks 10 anonymous pedagogical metrics to measure and improve
// learning effectiveness. All telemetry is:
//   - OPT-IN (requires GdprConsentManager.analytics)
//   - ANONYMOUS (no user ID, no PII)
//   - LOCAL-FIRST (buffered, batched, host app decides when to send)
//   - GDPR-COMPLIANT (Art. 6(1)(a) — explicit consent)
//
// ARCHITECTURE:
//   Pure model — no network calls, no platform dependencies.
//   Host app is responsible for transmitting buffered events.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'package:flutter/foundation.dart';

/// 📊 Telemetry event categories.
enum TelemetryMetric {
  /// Average time spent per zone (seconds).
  zoneTime,

  /// Recall success rate per step (0.0–1.0).
  recallRate,

  /// Cross-domain bridges created per session.
  bridgesCreated,

  /// Red Wall activations (crisis events).
  redWallActivations,

  /// Fog of War completion rate.
  fowCompletionRate,

  /// Writing vs reading time ratio.
  writeReadRatio,

  /// Socratic question skip rate.
  socraticSkipRate,

  /// Session duration (seconds).
  sessionDuration,

  /// FSRS prediction accuracy (0.0–1.0).
  fsrsAccuracy,

  /// Step progression sequence.
  stepProgression,
}

/// 📊 A single telemetry event.
class PedagogicalTelemetryEvent {
  /// The metric category.
  final TelemetryMetric metric;

  /// Numeric value.
  final double value;

  /// Optional string payload (e.g., step sequence).
  final String? label;

  /// Timestamp.
  final DateTime timestamp;

  /// Session ID (anonymous, random per session).
  final String sessionId;

  PedagogicalTelemetryEvent({
    required this.metric,
    required this.value,
    this.label,
    required this.sessionId,
  }) : timestamp = DateTime.now();

  Map<String, dynamic> toJson() => {
        'metric': metric.name,
        'value': value,
        if (label != null) 'label': label,
        'timestamp': timestamp.toIso8601String(),
        'sessionId': sessionId,
      };

  factory PedagogicalTelemetryEvent.fromJson(Map<String, dynamic> json) => PedagogicalTelemetryEvent(
        metric: TelemetryMetric.values
                .where((m) => m.name == (json['metric'] as String? ?? ''))
                .firstOrNull ??
            TelemetryMetric.sessionDuration,
        value: (json['value'] as num?)?.toDouble() ?? 0,
        label: json['label'] as String?,
        sessionId: json['sessionId'] as String? ?? '',
      );
}

/// 📊 Session summary for batch upload.
class TelemetrySessionSummary {
  final String sessionId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int eventCount;
  final Map<TelemetryMetric, double> aggregates;

  TelemetrySessionSummary({
    required this.sessionId,
    required this.startedAt,
    required this.endedAt,
    required this.eventCount,
    required this.aggregates,
  });

  /// Duration in seconds.
  int get durationSeconds => endedAt.difference(startedAt).inSeconds;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'durationSeconds': durationSeconds,
        'eventCount': eventCount,
        'aggregates': aggregates.map((k, v) => MapEntry(k.name, v)),
      };
}

/// 📊 Pedagogical Telemetry Service (A19).
///
/// Buffers anonymous pedagogical events locally.
/// The host app flushes the buffer when appropriate.
///
/// Usage:
/// ```dart
/// final telemetry = PedagogicalTelemetryService();
///
/// // Check consent before recording
/// if (consentManager.isGranted(ConsentCategory.analytics)) {
///   telemetry.record(TelemetryMetric.recallRate, 0.85);
///   telemetry.record(TelemetryMetric.sessionDuration, 1800);
/// }
///
/// // Flush buffer (host app sends to backend)
/// final events = telemetry.flush();
/// await api.sendTelemetry(events);
/// ```
class PedagogicalTelemetryService extends ChangeNotifier {
  /// Whether telemetry is enabled (linked to consent).
  bool _enabled = false;
  bool get isEnabled => _enabled;

  /// Current session ID (random, anonymous).
  String _sessionId = '';
  String get sessionId => _sessionId;

  /// Buffered events (not yet flushed).
  final List<PedagogicalTelemetryEvent> _buffer = [];

  /// Number of buffered events.
  int get bufferSize => _buffer.length;

  /// Maximum buffer size before auto-flush warning.
  static const int maxBufferSize = 500;

  /// Session start time.
  DateTime? _sessionStart;

  /// Enable telemetry (call when user grants consent).
  void enable() {
    _enabled = true;
    notifyListeners();
  }

  /// Disable telemetry (call when user revokes consent).
  /// Clears all buffered data.
  void disable() {
    _enabled = false;
    _buffer.clear();
    notifyListeners();
  }

  /// Start a new telemetry session.
  void startSession(String sessionId) {
    _sessionId = sessionId;
    _sessionStart = DateTime.now();
  }

  /// Record a telemetry event.
  ///
  /// No-op if telemetry is disabled or no session is active.
  void record(TelemetryMetric metric, double value, {String? label}) {
    if (!_enabled || _sessionId.isEmpty) return;

    _buffer.add(PedagogicalTelemetryEvent(
      metric: metric,
      value: value,
      label: label,
      sessionId: _sessionId,
    ));

    // Hard cap: drop oldest events to prevent memory growth.
    if (_buffer.length > maxBufferSize) {
      _buffer.removeRange(0, _buffer.length - maxBufferSize);
      debugPrint('📊 [Telemetry] Buffer exceeded cap — oldest events dropped.');
    }
  }

  /// Flush the buffer and return all events.
  ///
  /// The caller (host app) is responsible for transmitting these.
  /// Buffer is cleared after flush.
  List<PedagogicalTelemetryEvent> flush() {
    final events = List<PedagogicalTelemetryEvent>.from(_buffer);
    _buffer.clear();
    return events;
  }

  /// Generate a session summary from buffered events.
  TelemetrySessionSummary? generateSummary() {
    if (_sessionId.isEmpty || _sessionStart == null) return null;

    // Aggregate: average per metric.
    final sums = <TelemetryMetric, double>{};
    final counts = <TelemetryMetric, int>{};

    for (final event in _buffer) {
      sums[event.metric] = (sums[event.metric] ?? 0) + event.value;
      counts[event.metric] = (counts[event.metric] ?? 0) + 1;
    }

    final aggregates = <TelemetryMetric, double>{};
    for (final metric in sums.keys) {
      aggregates[metric] = sums[metric]! / counts[metric]!;
    }

    return TelemetrySessionSummary(
      sessionId: _sessionId,
      startedAt: _sessionStart!,
      endedAt: DateTime.now(),
      eventCount: _buffer.length,
      aggregates: aggregates,
    );
  }
}
