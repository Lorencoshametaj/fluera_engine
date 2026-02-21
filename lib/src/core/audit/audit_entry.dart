/// 🔒 AUDIT ENTRY — Immutable audit trail record for compliance & forensics.
///
/// Every auditable operation in the engine produces an [AuditEntry] with:
/// - **who** ([actor]) — user ID, `'system'`, or plugin identifier
/// - **what** ([action]) — classified operation type
/// - **when** ([timestamp]) — UTC timestamp
/// - **where** ([source]) — originating subsystem
/// - **target** ([targetId], [targetType]) — affected entity
/// - **diff** ([before], [after]) — pre/post-change snapshots
///
/// Entries are immutable after creation. Use [AuditLogService] to persist
/// and query them.
///
/// ```dart
/// final entry = AuditEntry(
///   action: AuditAction.create,
///   actor: 'user-42',
///   source: 'SceneGraph',
///   targetId: 'node-abc',
///   targetType: 'GroupNode',
/// );
/// auditLog.record(entry);
/// ```
library;

/// Classification of auditable operations.
enum AuditAction {
  /// A new entity was created (node, layer, variable, etc.).
  create,

  /// An existing entity was modified (property change, transform, etc.).
  update,

  /// An entity was removed from the document.
  delete,

  /// An entity was moved to a different parent or position.
  move,

  /// Children were reordered within a container.
  reorder,

  /// Data was imported into the document.
  import_,

  /// Data was exported from the document.
  export_,

  /// An undo operation was performed.
  undo,

  /// A redo operation was performed.
  redo,

  /// User session started.
  login,

  /// User session ended.
  logout,

  /// Engine or canvas configuration was changed.
  configChange,

  /// A plugin emitted a custom event.
  pluginEvent,

  /// An error was reported through the recovery system.
  error,

  /// Custom action not covered by the above.
  custom,
}

/// Severity level of an audit entry.
enum AuditSeverity {
  /// Informational — routine operations.
  info,

  /// Warning — unusual but non-critical events.
  warning,

  /// Critical — errors, integrity violations, security events.
  critical,
}

/// Immutable audit trail record.
///
/// Each entry captures a single auditable operation with full context
/// for compliance reporting, forensic analysis, and operational monitoring.
class AuditEntry {
  /// Unique identifier (UUID v4 format).
  final String id;

  /// When the event occurred (always UTC).
  final DateTime timestamp;

  /// What type of operation was performed.
  final AuditAction action;

  /// Severity classification.
  final AuditSeverity severity;

  /// Who performed the action — user ID, `'system'`, or plugin identifier.
  final String actor;

  /// Which subsystem originated the event (e.g. `'SceneGraph'`, `'History'`).
  final String source;

  /// ID of the affected entity (node ID, variable name, etc.), if applicable.
  final String? targetId;

  /// Type of the affected entity (`'GroupNode'`, `'Layer'`, etc.), if applicable.
  final String? targetType;

  /// Pre-change snapshot of the target, for diff-based auditing.
  final Map<String, dynamic>? before;

  /// Post-change snapshot of the target, for diff-based auditing.
  final Map<String, dynamic>? after;

  /// Freeform metadata for additional forensic context.
  final Map<String, dynamic>? metadata;

  /// Human-readable description of the operation, if provided.
  final String? description;

  /// Create a new audit entry.
  ///
  /// [id] defaults to a timestamp-based pseudo-UUID if not provided.
  /// [timestamp] defaults to `DateTime.now().toUtc()`.
  /// [severity] defaults to [AuditSeverity.info].
  /// [actor] defaults to `'system'`.
  AuditEntry({
    String? id,
    DateTime? timestamp,
    required this.action,
    this.severity = AuditSeverity.info,
    this.actor = 'system',
    required this.source,
    this.targetId,
    this.targetType,
    this.before,
    this.after,
    this.metadata,
    this.description,
  }) : id = id ?? _generateId(),
       timestamp = timestamp ?? DateTime.now().toUtc();

  /// Generate a pseudo-unique ID based on microsecond timestamp + hash.
  static int _idCounter = 0;
  static String _generateId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final seq = ++_idCounter;
    return '${ts.toRadixString(36)}-${seq.toRadixString(36)}';
  }

  /// Serialize to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'action': action.name,
    'severity': severity.name,
    'actor': actor,
    'source': source,
    if (targetId != null) 'targetId': targetId,
    if (targetType != null) 'targetType': targetType,
    if (before != null) 'before': before,
    if (after != null) 'after': after,
    if (metadata != null) 'metadata': metadata,
    if (description != null) 'description': description,
  };

  /// Deserialize from a JSON map.
  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    action: AuditAction.values.firstWhere(
      (a) => a.name == json['action'],
      orElse: () => AuditAction.custom,
    ),
    severity: AuditSeverity.values.firstWhere(
      (s) => s.name == json['severity'],
      orElse: () => AuditSeverity.info,
    ),
    actor: json['actor'] as String? ?? 'system',
    source: json['source'] as String,
    targetId: json['targetId'] as String?,
    targetType: json['targetType'] as String?,
    before: json['before'] as Map<String, dynamic>?,
    after: json['after'] as Map<String, dynamic>?,
    metadata: json['metadata'] as Map<String, dynamic>?,
    description: json['description'] as String?,
  );

  @override
  String toString() =>
      'AuditEntry($id, ${action.name}, actor=$actor, source=$source'
      '${targetId != null ? ', target=$targetId' : ''})';
}
