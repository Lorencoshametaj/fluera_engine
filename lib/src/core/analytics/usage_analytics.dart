/// 📊 USAGE ANALYTICS — Session tracking and tool usage analytics.
///
/// Tracks user sessions, tool usage heat maps, and event funnels
/// for enterprise analytics dashboards.
///
/// ```dart
/// final analytics = UsageAnalytics();
/// analytics.startSession(userId: 'u-123');
/// analytics.trackToolUse('pen');
/// analytics.trackToolUse('eraser');
/// final report = analytics.generateReport();
/// ```
library;

// =============================================================================
// SESSION
// =============================================================================

/// A single user session with timing and metadata.
class AnalyticsSession {
  /// Session identifier.
  final String id;

  /// User identifier.
  final String userId;

  /// Session start time (epoch ms).
  final int startTimeMs;

  /// Session end time (epoch ms), null if active.
  int? endTimeMs;

  /// Custom metadata.
  final Map<String, dynamic> metadata;

  AnalyticsSession({
    required this.id,
    required this.userId,
    required this.startTimeMs,
    this.endTimeMs,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? {};

  /// Session duration in milliseconds (0 if still active).
  int get durationMs => endTimeMs != null ? endTimeMs! - startTimeMs : 0;

  /// Whether the session is still active.
  bool get isActive => endTimeMs == null;

  /// End the session.
  void end() {
    endTimeMs ??= DateTime.now().millisecondsSinceEpoch;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'startTimeMs': startTimeMs,
    if (endTimeMs != null) 'endTimeMs': endTimeMs,
    'durationMs': durationMs,
    'metadata': metadata,
  };
}

// =============================================================================
// TOOL USAGE ENTRY
// =============================================================================

/// Tracks usage of a specific tool.
class ToolUsageEntry {
  /// Tool identifier.
  final String toolId;

  /// Number of times used.
  int useCount;

  /// Total time spent using tool (ms).
  int totalTimeMs;

  /// Last used timestamp (epoch ms).
  int lastUsedMs;

  ToolUsageEntry({
    required this.toolId,
    this.useCount = 0,
    this.totalTimeMs = 0,
    this.lastUsedMs = 0,
  });

  /// Average time per use (ms).
  double get avgTimeMs => useCount > 0 ? totalTimeMs / useCount : 0;

  Map<String, dynamic> toJson() => {
    'toolId': toolId,
    'useCount': useCount,
    'totalTimeMs': totalTimeMs,
    'avgTimeMs': avgTimeMs,
    'lastUsedMs': lastUsedMs,
  };
}

// =============================================================================
// EVENT FUNNEL
// =============================================================================

/// Tracks a multi-step user flow for drop-off analysis.
class EventFunnel {
  /// Funnel identifier.
  final String id;

  /// Ordered step names.
  final List<String> steps;

  /// Count per step.
  final Map<String, int> _stepCounts = {};

  EventFunnel({required this.id, required this.steps}) {
    for (final step in steps) {
      _stepCounts[step] = 0;
    }
  }

  /// Record that a user reached a step.
  void recordStep(String step) {
    if (_stepCounts.containsKey(step)) {
      _stepCounts[step] = _stepCounts[step]! + 1;
    }
  }

  /// Get count for a step.
  int countFor(String step) => _stepCounts[step] ?? 0;

  /// Get conversion rate between two sequential steps (0–1).
  double conversionRate(String fromStep, String toStep) {
    final from = _stepCounts[fromStep] ?? 0;
    final to = _stepCounts[toStep] ?? 0;
    return from > 0 ? to / from : 0;
  }

  /// Get drop-off analysis for all steps.
  List<Map<String, dynamic>> dropOffAnalysis() {
    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < steps.length; i++) {
      final count = _stepCounts[steps[i]] ?? 0;
      final prevCount = i > 0 ? _stepCounts[steps[i - 1]] ?? 0 : count;
      result.add({
        'step': steps[i],
        'count': count,
        'dropOff': prevCount > 0 ? 1.0 - (count / prevCount) : 0.0,
      });
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'steps': steps,
    'counts': Map<String, int>.from(_stepCounts),
    'dropOff': dropOffAnalysis(),
  };
}

// =============================================================================
// USAGE ANALYTICS
// =============================================================================

/// Central usage analytics service.
class UsageAnalytics {
  final List<AnalyticsSession> _sessions = [];
  final Map<String, ToolUsageEntry> _toolUsage = {};
  final Map<String, EventFunnel> _funnels = {};

  AnalyticsSession? _currentSession;
  String? _activeToolId;
  int _activeToolStartMs = 0;
  int _sessionIdCounter = 0;

  /// Start a new session.
  AnalyticsSession startSession({
    required String userId,
    Map<String, dynamic>? metadata,
  }) {
    // End current session if active
    _currentSession?.end();
    _flushActiveTool();

    final session = AnalyticsSession(
      id: 'session-${++_sessionIdCounter}',
      userId: userId,
      startTimeMs: DateTime.now().millisecondsSinceEpoch,
      metadata: metadata,
    );
    _sessions.add(session);
    _currentSession = session;
    return session;
  }

  /// End the current session.
  void endSession() {
    _flushActiveTool();
    _currentSession?.end();
    _currentSession = null;
  }

  /// Current active session.
  AnalyticsSession? get currentSession => _currentSession;

  /// All recorded sessions.
  List<AnalyticsSession> get sessions => List.unmodifiable(_sessions);

  /// Track a tool use event.
  void trackToolUse(String toolId) {
    _flushActiveTool();
    final entry = _toolUsage.putIfAbsent(
      toolId,
      () => ToolUsageEntry(toolId: toolId),
    );
    entry.useCount++;
    entry.lastUsedMs = DateTime.now().millisecondsSinceEpoch;
    _activeToolId = toolId;
    _activeToolStartMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// Stop tracking the current tool.
  void stopToolUse() => _flushActiveTool();

  void _flushActiveTool() {
    if (_activeToolId != null) {
      final entry = _toolUsage[_activeToolId];
      if (entry != null) {
        final elapsed =
            DateTime.now().millisecondsSinceEpoch - _activeToolStartMs;
        entry.totalTimeMs += elapsed;
      }
      _activeToolId = null;
    }
  }

  /// Get tool usage heat map sorted by use count (descending).
  List<ToolUsageEntry> get toolHeatMap {
    final entries = _toolUsage.values.toList();
    entries.sort((a, b) => b.useCount.compareTo(a.useCount));
    return entries;
  }

  /// Get usage for a specific tool.
  ToolUsageEntry? getToolUsage(String toolId) => _toolUsage[toolId];

  /// Create or get an event funnel.
  EventFunnel funnel(String id, List<String> steps) {
    return _funnels.putIfAbsent(id, () => EventFunnel(id: id, steps: steps));
  }

  /// Get a funnel by id.
  EventFunnel? getFunnel(String id) => _funnels[id];

  /// Generate a comprehensive usage report.
  Map<String, dynamic> generateReport() {
    return {
      'totalSessions': _sessions.length,
      'activeSessions': _sessions.where((s) => s.isActive).length,
      'avgSessionDurationMs':
          _sessions.isEmpty
              ? 0
              : _sessions
                      .where((s) => !s.isActive)
                      .fold<int>(0, (sum, s) => sum + s.durationMs) /
                  _sessions.where((s) => !s.isActive).length.clamp(1, 999999),
      'toolUsage': {
        for (final entry in toolHeatMap) entry.toolId: entry.toJson(),
      },
      'funnels': {for (final f in _funnels.values) f.id: f.toJson()},
    };
  }

  /// Reset all analytics data.
  void reset() {
    _sessions.clear();
    _toolUsage.clear();
    _funnels.clear();
    _currentSession = null;
    _activeToolId = null;
  }
}
