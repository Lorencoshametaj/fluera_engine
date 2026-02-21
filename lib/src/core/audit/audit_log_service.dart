import 'dart:async';
import 'dart:collection';

import 'audit_entry.dart';

/// Configuration for the [AuditLogService].
///
/// Controls buffer size, retention, and noise filtering.
///
/// ```dart
/// final config = AuditLogConfig(
///   maxEntries: 50000,
///   retentionPeriod: Duration(days: 365),
///   ignoredActions: {AuditAction.custom},
/// );
/// final auditLog = AuditLogService(config: config);
/// ```
class AuditLogConfig {
  /// Maximum number of entries kept in the ring buffer.
  ///
  /// When exceeded, oldest entries are evicted first.
  /// Default: 10,000.
  final int maxEntries;

  /// How long entries are kept before automatic purge.
  ///
  /// `null` means entries are never purged by age (only by [maxEntries]).
  /// Default: 90 days.
  final Duration? retentionPeriod;

  /// Whether to capture before/after snapshots for diff-based auditing.
  ///
  /// Disable for reduced memory usage in high-throughput scenarios.
  /// Default: `true`.
  final bool enableBeforeAfter;

  /// Actions to silently ignore (e.g. noisy selection changes).
  ///
  /// Entries with these actions are dropped before storage.
  final Set<AuditAction> ignoredActions;

  const AuditLogConfig({
    this.maxEntries = 10000,
    this.retentionPeriod = const Duration(days: 90),
    this.enableBeforeAfter = true,
    this.ignoredActions = const {},
  });
}

/// Aggregate statistics for the audit log.
class AuditLogStats {
  /// Total number of entries currently stored.
  final int totalEntries;

  /// Timestamp of the oldest entry, or `null` if empty.
  final DateTime? oldestTimestamp;

  /// Timestamp of the newest entry, or `null` if empty.
  final DateTime? newestTimestamp;

  /// Breakdown of entries by action type.
  final Map<AuditAction, int> actionCounts;

  /// Breakdown of entries by severity.
  final Map<AuditSeverity, int> severityCounts;

  const AuditLogStats({
    required this.totalEntries,
    this.oldestTimestamp,
    this.newestTimestamp,
    required this.actionCounts,
    required this.severityCounts,
  });

  @override
  String toString() =>
      'AuditLogStats(entries=$totalEntries, '
      'oldest=${oldestTimestamp?.toIso8601String() ?? "n/a"}, '
      'newest=${newestTimestamp?.toIso8601String() ?? "n/a"})';
}

/// Filtering criteria for [AuditLogService.query].
///
/// All fields are optional — `null` means "match any".
/// Multiple non-null fields are ANDed together.
///
/// ```dart
/// final errors = auditLog.query(AuditQuery(
///   actions: {AuditAction.error},
///   minSeverity: AuditSeverity.warning,
///   limit: 50,
/// ));
/// ```
class AuditQuery {
  /// Only include entries within this time range.
  final ({DateTime start, DateTime end})? timeRange;

  /// Only include entries with one of these actions.
  final Set<AuditAction>? actions;

  /// Only include entries from this actor.
  final String? actor;

  /// Only include entries targeting this entity.
  final String? targetId;

  /// Only include entries from this source subsystem.
  final String? source;

  /// Only include entries at or above this severity.
  final AuditSeverity? minSeverity;

  /// Maximum number of entries to return. Default: 100.
  final int limit;

  /// Number of entries to skip (for pagination). Default: 0.
  final int offset;

  const AuditQuery({
    this.timeRange,
    this.actions,
    this.actor,
    this.targetId,
    this.source,
    this.minSeverity,
    this.limit = 100,
    this.offset = 0,
  });
}

// =============================================================================
// AUDIT LOG SERVICE
// =============================================================================

/// 🔒 AUDIT LOG SERVICE — Append-only, queryable compliance trail.
///
/// Provides an in-memory ring buffer for audit entries with:
/// - **O(1) append** via [record]
/// - **Filtered query** via [query] with composable [AuditQuery]
/// - **Retention policies** via [applyRetention]
/// - **Real-time streaming** via [stream]
/// - **Statistics** via [stats]
///
/// Integrates with [EngineScope] for lifecycle management and
/// [AuditEventBridge] for automatic event-bus subscription.
///
/// ```dart
/// final auditLog = AuditLogService();
///
/// auditLog.record(AuditEntry(
///   action: AuditAction.create,
///   source: 'SceneGraph',
///   targetId: 'node-123',
/// ));
///
/// final recent = auditLog.query(AuditQuery(
///   actions: {AuditAction.create, AuditAction.delete},
///   limit: 20,
/// ));
///
/// // Real-time listener
/// auditLog.stream.listen((entry) => print(entry));
///
/// // Compliance export
/// final stats = auditLog.stats;
/// print('Total entries: ${stats.totalEntries}');
/// ```
class AuditLogService {
  /// Service configuration.
  final AuditLogConfig config;

  /// Bounded ring buffer of audit entries.
  final Queue<AuditEntry> _entries = Queue<AuditEntry>();

  /// Index by entry ID for O(1) lookup.
  final Map<String, AuditEntry> _idIndex = {};

  /// Real-time entry stream.
  final StreamController<AuditEntry> _controller =
      StreamController<AuditEntry>.broadcast(sync: false);

  /// Total entries ever recorded (including evicted ones).
  int _totalRecorded = 0;

  /// Whether the service has been disposed.
  bool _disposed = false;

  /// Create an audit log service with optional [config].
  AuditLogService({this.config = const AuditLogConfig()});

  // ═══════════════════════════════════════════════════════════════════════════
  // WRITE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Append an audit entry to the log.
  ///
  /// - Entries matching [AuditLogConfig.ignoredActions] are silently dropped.
  /// - If [AuditLogConfig.enableBeforeAfter] is `false`, the entry's
  ///   `before`/`after` fields are ignored (the entry is stored without them).
  /// - When the ring buffer exceeds [AuditLogConfig.maxEntries], the oldest
  ///   entry is evicted.
  void record(AuditEntry entry) {
    if (_disposed) return;
    if (config.ignoredActions.contains(entry.action)) return;

    // Strip before/after if disabled
    final stored =
        !config.enableBeforeAfter &&
                (entry.before != null || entry.after != null)
            ? AuditEntry(
              id: entry.id,
              timestamp: entry.timestamp,
              action: entry.action,
              severity: entry.severity,
              actor: entry.actor,
              source: entry.source,
              targetId: entry.targetId,
              targetType: entry.targetType,
              metadata: entry.metadata,
              description: entry.description,
            )
            : entry;

    // Evict oldest if at capacity
    while (_entries.length >= config.maxEntries) {
      final evicted = _entries.removeFirst();
      _idIndex.remove(evicted.id);
    }

    _entries.addLast(stored);
    _idIndex[stored.id] = stored;
    _totalRecorded++;

    if (!_controller.isClosed) {
      _controller.add(stored);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUERY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Query the audit log with composable filters.
  ///
  /// Returns entries matching ALL non-null criteria in [query],
  /// respecting [AuditQuery.limit] and [AuditQuery.offset].
  List<AuditEntry> query(AuditQuery query) {
    Iterable<AuditEntry> results = _entries;

    // Time range filter
    if (query.timeRange != null) {
      final start = query.timeRange!.start;
      final end = query.timeRange!.end;
      results = results.where(
        (e) => !e.timestamp.isBefore(start) && !e.timestamp.isAfter(end),
      );
    }

    // Action filter
    if (query.actions != null && query.actions!.isNotEmpty) {
      results = results.where((e) => query.actions!.contains(e.action));
    }

    // Actor filter
    if (query.actor != null) {
      results = results.where((e) => e.actor == query.actor);
    }

    // Target filter
    if (query.targetId != null) {
      results = results.where((e) => e.targetId == query.targetId);
    }

    // Source filter
    if (query.source != null) {
      results = results.where((e) => e.source == query.source);
    }

    // Severity filter
    if (query.minSeverity != null) {
      final minIndex = query.minSeverity!.index;
      results = results.where((e) => e.severity.index >= minIndex);
    }

    // Pagination
    return results.skip(query.offset).take(query.limit).toList();
  }

  /// Get the most recent [count] entries (newest first).
  List<AuditEntry> recentEntries([int count = 20]) {
    final list = _entries.toList();
    final start = list.length > count ? list.length - count : 0;
    return list.sublist(start).reversed.toList();
  }

  /// Look up a single entry by its unique [id].
  ///
  /// Returns `null` if not found (may have been evicted or never recorded).
  AuditEntry? getById(String id) => _idIndex[id];

  /// All entries currently in the buffer (oldest first).
  List<AuditEntry> get entries => _entries.toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // RETENTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Apply retention policy, purging entries older than
  /// [AuditLogConfig.retentionPeriod].
  ///
  /// Returns the number of entries purged.
  /// Returns 0 if [retentionPeriod] is `null`.
  int applyRetention() {
    if (config.retentionPeriod == null) return 0;

    final cutoff = DateTime.now().toUtc().subtract(config.retentionPeriod!);
    int purged = 0;

    while (_entries.isNotEmpty && _entries.first.timestamp.isBefore(cutoff)) {
      final removed = _entries.removeFirst();
      _idIndex.remove(removed.id);
      purged++;
    }

    return purged;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STREAM
  // ═══════════════════════════════════════════════════════════════════════════

  /// Real-time stream of newly recorded audit entries.
  ///
  /// Only entries recorded after subscribing are emitted.
  Stream<AuditEntry> get stream => _controller.stream;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Aggregate statistics of the current audit log state.
  AuditLogStats get stats {
    final actionCounts = <AuditAction, int>{};
    final severityCounts = <AuditSeverity, int>{};

    for (final entry in _entries) {
      actionCounts[entry.action] = (actionCounts[entry.action] ?? 0) + 1;
      severityCounts[entry.severity] =
          (severityCounts[entry.severity] ?? 0) + 1;
    }

    return AuditLogStats(
      totalEntries: _entries.length,
      oldestTimestamp: _entries.isNotEmpty ? _entries.first.timestamp : null,
      newestTimestamp: _entries.isNotEmpty ? _entries.last.timestamp : null,
      actionCounts: actionCounts,
      severityCounts: severityCounts,
    );
  }

  /// Total entries ever recorded (including evicted ones).
  int get totalRecorded => _totalRecorded;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Clear all entries from the buffer.
  void clear() {
    _entries.clear();
    _idIndex.clear();
  }

  /// Dispose the audit log service.
  ///
  /// After disposal, [record] calls are silently ignored and [stream]
  /// is closed.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.close();
    _entries.clear();
    _idIndex.clear();
  }

  /// Whether this service has been disposed.
  bool get isDisposed => _disposed;
}
