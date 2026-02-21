import 'dart:async';

import '../engine_event.dart';
import '../engine_event_bus.dart';
import 'audit_entry.dart';
import 'audit_log_service.dart';

/// 🔌 AUDIT EVENT BRIDGE — Automatic EngineEventBus → AuditLogService mapping.
///
/// Subscribes to the [EngineEventBus] and translates engine events into
/// structured [AuditEntry] records, automatically recording them in the
/// [AuditLogService].
///
/// Each [EngineEvent] subtype is mapped to the appropriate [AuditAction]
/// and [AuditSeverity]:
///
/// | Engine Event | Audit Action | Severity |
/// |---|---|---|
/// | `NodeAddedEngineEvent` | `create` | `info` |
/// | `NodeRemovedEngineEvent` | `delete` | `info` |
/// | `NodePropertyChangedEngineEvent` | `update` | `info` |
/// | `NodeReorderedEngineEvent` | `reorder` | `info` |
/// | `VariableChangedEngineEvent` | `update` | `info` |
/// | `ErrorReportedEngineEvent` | `error` | `critical` |
/// | `CustomPluginEngineEvent` | `pluginEvent` | `info` |
/// | `MemoryPressureEngineEvent` | `custom` | `warning` |
///
/// Selection events and batch-complete events are filtered out as noise.
///
/// ```dart
/// final bridge = AuditEventBridge(
///   eventBus: scope.eventBus,
///   auditLog: scope.auditLog,
///   actor: 'user-42',
/// );
/// bridge.start();
///
/// // All engine events are now automatically audited.
/// // Call bridge.stop() to pause, bridge.dispose() to cleanup.
/// ```
class AuditEventBridge {
  /// The event bus to listen to.
  final EngineEventBus eventBus;

  /// The audit log to record entries in.
  final AuditLogService auditLog;

  /// Default actor ID for entries created by this bridge.
  ///
  /// Can be overridden per-event for events that carry actor information.
  final String actor;

  /// Active subscription to the event bus.
  StreamSubscription<EngineEvent>? _subscription;

  /// Whether the bridge is currently listening.
  bool get isActive => _subscription != null;

  /// Create an audit event bridge.
  ///
  /// Does NOT start listening automatically — call [start] to begin.
  AuditEventBridge({
    required this.eventBus,
    required this.auditLog,
    this.actor = 'system',
  });

  /// Start listening to the event bus and recording audit entries.
  ///
  /// If already active, this is a no-op.
  void start() {
    if (_subscription != null) return;

    _subscription = eventBus.stream.listen(_onEvent);
  }

  /// Stop listening to the event bus.
  ///
  /// Can be restarted with [start]. Does not dispose resources.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Dispose the bridge, cancelling any active subscription.
  ///
  /// After disposal, [start] should not be called again.
  void dispose() {
    stop();
  }

  // ===========================================================================
  // EVENT MAPPING
  // ===========================================================================

  /// Map an engine event to an audit entry and record it.
  void _onEvent(EngineEvent event) {
    final entry = _mapEvent(event);
    if (entry != null) {
      auditLog.record(entry);
    }
  }

  /// Convert an [EngineEvent] to an [AuditEntry], or `null` to skip.
  AuditEntry? _mapEvent(EngineEvent event) {
    // -- Scene graph structural events --
    if (event is NodeAddedEngineEvent) {
      return AuditEntry(
        action: AuditAction.create,
        actor: actor,
        source: event.source,
        targetId: event.node.id,
        targetType: event.node.runtimeType.toString(),
        description: 'Node added to scene graph',
        metadata: {'parentId': event.parentId},
      );
    }

    if (event is NodeRemovedEngineEvent) {
      return AuditEntry(
        action: AuditAction.delete,
        actor: actor,
        source: event.source,
        targetId: event.node.id,
        targetType: event.node.runtimeType.toString(),
        description: 'Node removed from scene graph',
        metadata: {'parentId': event.parentId},
      );
    }

    if (event is NodePropertyChangedEngineEvent) {
      return AuditEntry(
        action: AuditAction.update,
        actor: actor,
        source: event.source,
        targetId: event.node.id,
        targetType: event.node.runtimeType.toString(),
        description: 'Node property changed: ${event.property}',
        metadata: {'property': event.property},
      );
    }

    if (event is NodeReorderedEngineEvent) {
      return AuditEntry(
        action: AuditAction.reorder,
        actor: actor,
        source: event.source,
        targetId: event.parentId,
        description: 'Children reordered',
        metadata: {'oldIndex': event.oldIndex, 'newIndex': event.newIndex},
      );
    }

    // -- Design variable events --
    if (event is VariableChangedEngineEvent) {
      return AuditEntry(
        action: AuditAction.update,
        actor: actor,
        source: event.source,
        targetId: event.variableId,
        targetType: 'DesignVariable',
        description: 'Variable "${event.variableId}" ${event.property} changed',
        before:
            event.oldValue != null
                ? {'value': event.oldValue.toString()}
                : null,
        after:
            event.newValue != null
                ? {'value': event.newValue.toString()}
                : null,
        metadata: {'property': event.property},
      );
    }

    // -- Error events --
    if (event is ErrorReportedEngineEvent) {
      return AuditEntry(
        action: AuditAction.error,
        severity: AuditSeverity.critical,
        actor: actor,
        source: event.source,
        description: 'Error: ${event.error.original}',
        metadata: {
          'errorDomain': event.error.domain.name,
          'errorSeverity': event.error.severity.name,
          'errorSource': event.error.source,
        },
      );
    }

    // -- Plugin events --
    if (event is CustomPluginEngineEvent) {
      return AuditEntry(
        action: AuditAction.pluginEvent,
        actor: event.pluginId,
        source: event.source,
        description: 'Plugin event: ${event.name}',
        metadata: event.data,
      );
    }

    // -- Memory pressure events --
    if (event is MemoryPressureEngineEvent) {
      return AuditEntry(
        action: AuditAction.custom,
        severity: AuditSeverity.warning,
        actor: 'system',
        source: event.source,
        description: 'Memory pressure: ${event.level}',
        metadata: {
          'level': event.level,
          'totalEstimatedMB': event.totalEstimatedMB,
          'budgetCapMB': event.budgetCapMB,
        },
      );
    }

    // -- Command events --
    if (event is CommandExecutedEngineEvent) {
      return AuditEntry(
        action: AuditAction.custom,
        actor: actor,
        source: event.source,
        description: 'Command executed: ${event.commandLabel}',
        metadata: {
          'commandType': event.commandType,
          'commandLabel': event.commandLabel,
        },
      );
    }

    if (event is CommandUndoneEngineEvent) {
      return AuditEntry(
        action: AuditAction.undo,
        actor: actor,
        source: event.source,
        description: 'Command undone: ${event.commandLabel}',
        metadata: {
          'commandType': event.commandType,
          'commandLabel': event.commandLabel,
        },
      );
    }

    // -- Filtered out (noise) --
    // SelectionChangedEngineEvent — too frequent, no compliance value
    // BatchCompleteEngineEvent — internal bus mechanics
    // AnimationFrameEvent — per-frame noise
    // AccessibilityTreeChangedEvent — internal rebuild
    return null;
  }
}
