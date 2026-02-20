import '../engine_event_bus.dart';
import '../engine_telemetry.dart';
import '../nodes/layer_node.dart';
import './canvas_node.dart';
import './scene_graph.dart';
import './scene_graph_savepoint.dart';
import './scene_graph_snapshot.dart';

// ---------------------------------------------------------------------------
// Scene Graph Transaction
// ---------------------------------------------------------------------------

/// Atomic transaction boundary for scene graph mutations.
///
/// Captures a structural snapshot on begin, defers all observer
/// notifications until commit, and restores from inverse-ops log on rollback.
/// A full JSON backup is kept as a safety fallback.
///
/// Usage:
/// ```dart
/// final txn = graph.beginTransaction();
/// try {
///   graph.addLayer(layerA);
///   graph.addLayer(layerB);
///   txn.commit();
/// } catch (e) {
///   txn.rollback();
///   rethrow;
/// }
/// ```
///
/// During the transaction:
/// - Observer notifications are **deferred** (buffered, not dispatched)
/// - The [EngineEventBus] is **paused** (if connected)
/// - Re-entrant `beginTransaction()` calls are rejected
/// - Mutations are logged as inverse operations for efficient rollback
///
/// After commit:
/// - All deferred notifications are flushed in order
/// - The EventBus is resumed
/// - Inverse ops log is discarded
///
/// After rollback:
/// - Inverse ops execute in reverse order (primary strategy)
/// - If inverse replay fails, JSON backup is used (safety fallback)
/// - Deferred notifications are discarded
/// - The EventBus is resumed
class SceneGraphTransaction {
  /// The owning scene graph.
  final SceneGraph graph;

  final SceneGraphSnapshot _snapshot;
  final EngineEventBus? _eventBus;

  /// Lazy JSON backup provider — only evaluated if rollback needs it.
  final Map<String, dynamic> Function() _jsonBackupProvider;
  Map<String, dynamic>? _jsonBackupCache;

  /// JSON backup of the full graph for rollback safety fallback.
  ///
  /// Lazily computed — the full serialization only runs if rollback()
  /// is called and inverse-ops replay fails.
  Map<String, dynamic> get jsonBackup =>
      _jsonBackupCache ??= _jsonBackupProvider();

  bool _committed = false;
  bool _rolledBack = false;

  /// Inverse operations log — recorded during the transaction.
  ///
  /// On rollback, these are replayed in reverse to undo each mutation
  /// without the cost of full JSON deserialization.
  final List<TransactionInverseOp> _inverseOps = [];

  /// Version of the scene graph at transaction start.
  ///
  /// On rollback, this is restored so that `assertUnchanged()` works
  /// correctly after a rollback returns the graph to its pre-transaction state.
  final int versionAtStart;

  /// Creates a transaction. Use [SceneGraph.beginTransaction] instead.
  SceneGraphTransaction({
    required this.graph,
    required SceneGraphSnapshot snapshot,
    required Map<String, dynamic> Function() jsonBackupProvider,
    required this.versionAtStart,
    EngineEventBus? eventBus,
    EngineTelemetry? telemetry,
  }) : _snapshot = snapshot,
       _jsonBackupProvider = jsonBackupProvider,
       _eventBus = eventBus {
    // Start telemetry span for the transaction
    if (telemetry != null) {
      _span = telemetry.startSpan(
        'scene_graph.transaction',
        scope: TelemetryScope.sceneGraph,
      );
    }
  }

  /// Telemetry span tracking this transaction's duration.
  TelemetrySpan? _span;

  /// Whether this transaction has been committed or rolled back.
  bool get isFinished => _committed || _rolledBack;

  /// The snapshot captured at the start of the transaction.
  SceneGraphSnapshot get snapshot => _snapshot;

  /// Number of inverse operations recorded.
  int get inverseOpCount => _inverseOps.length;

  /// Record an inverse operation (called by SceneGraph mutation methods).
  void recordInverse(TransactionInverseOp op) {
    if (isFinished) return;
    _inverseOps.add(op);
  }

  /// Commit the transaction — flush all deferred notifications.
  ///
  /// Throws [StateError] if already finished.
  void commit() {
    _assertNotFinished('commit');
    _committed = true;
    _span?.end();
    _inverseOps.clear(); // No longer needed
    graph.finishTransaction(flush: true);
    _eventBus?.resume();
  }

  /// Rollback the transaction — replay inverse ops, fallback to JSON backup.
  ///
  /// Throws [StateError] if already finished.
  void rollback() {
    _assertNotFinished('rollback');
    _rolledBack = true;
    _span?.end();

    if (_inverseOps.isNotEmpty) {
      try {
        // Replay inverse ops in reverse order.
        for (int i = _inverseOps.length - 1; i >= 0; i--) {
          _inverseOps[i].apply(graph);
        }
        _inverseOps.clear();
        graph.restoreVersion(versionAtStart);
        graph.finishTransaction(flush: false);
        _eventBus?.resume();
        return;
      } catch (_) {
        // Inverse replay failed — fall through to JSON restore.
      }
    }

    // Fallback: full JSON restore.
    graph.restoreFromBackup(jsonBackup);
    graph.restoreVersion(versionAtStart);
    _eventBus?.resume();
  }

  // -------------------------------------------------------------------------
  // Savepoints
  // -------------------------------------------------------------------------

  /// Create a named savepoint at the current point in the transaction.
  ///
  /// The savepoint captures the current inverse-ops log offset so that
  /// [rollbackToSavepoint] can undo only the mutations recorded **after**
  /// this point.
  SceneGraphSavepoint createSavepoint(String name) {
    _assertNotFinished('createSavepoint');
    return SceneGraphSavepoint(
      name: name,
      inverseOpsOffset: _inverseOps.length,
      versionAtSavepoint: graph.version,
    );
  }

  /// Rollback to a previously created savepoint.
  ///
  /// Replays inverse ops recorded **after** the savepoint in reverse,
  /// preserving all mutations made before it.
  ///
  /// Throws [ArgumentError] if the savepoint offset is invalid.
  void rollbackToSavepoint(SceneGraphSavepoint savepoint) {
    _assertNotFinished('rollbackToSavepoint');
    if (savepoint.inverseOpsOffset > _inverseOps.length) {
      throw ArgumentError(
        'Invalid savepoint offset ${savepoint.inverseOpsOffset} '
        '(current log size: ${_inverseOps.length})',
      );
    }

    // Replay inverse ops from most recent back to savepoint offset.
    for (int i = _inverseOps.length - 1; i >= savepoint.inverseOpsOffset; i--) {
      _inverseOps[i].apply(graph);
    }
    // Trim the log back to the savepoint.
    _inverseOps.removeRange(savepoint.inverseOpsOffset, _inverseOps.length);
    // Restore the version at the savepoint.
    graph.restoreVersion(savepoint.versionAtSavepoint);
  }

  void _assertNotFinished(String action) {
    if (_committed) {
      throw StateError('Cannot $action: transaction already committed.');
    }
    if (_rolledBack) {
      throw StateError('Cannot $action: transaction already rolled back.');
    }
  }
}

// ---------------------------------------------------------------------------
// Inverse Operations
// ---------------------------------------------------------------------------

/// An inverse operation that can undo a single scene graph mutation.
///
/// Recorded during a [SceneGraphTransaction] and replayed on rollback.
sealed class TransactionInverseOp {
  const TransactionInverseOp();

  /// Apply this inverse operation to undo the original mutation.
  void apply(SceneGraph graph);
}

/// Inverse of `addLayer` — removes the layer.
class RemoveLayerInverseOp extends TransactionInverseOp {
  final String layerId;
  const RemoveLayerInverseOp(this.layerId);

  @override
  void apply(SceneGraph graph) {
    final node = graph.rootNode.removeById(layerId);
    if (node != null) {
      graph.unregisterSubtreeForRollback(node);
    }
  }
}

/// Inverse of `removeLayer` — re-inserts the layer at its original position.
class InsertLayerInverseOp extends TransactionInverseOp {
  final LayerNode layer;
  final int index;
  const InsertLayerInverseOp(this.layer, this.index);

  @override
  void apply(SceneGraph graph) {
    graph.rootNode.insertAt(index, layer);
    graph.registerSubtreeForRollback(layer);
  }
}

/// Inverse of `reorderLayers` — reverses the reorder.
class ReorderLayersInverseOp extends TransactionInverseOp {
  final int oldIndex;
  final int newIndex;
  const ReorderLayersInverseOp(this.oldIndex, this.newIndex);

  @override
  void apply(SceneGraph graph) {
    // Reverse: move from newIndex back to oldIndex
    graph.rootNode.reorder(newIndex, oldIndex);
  }
}
