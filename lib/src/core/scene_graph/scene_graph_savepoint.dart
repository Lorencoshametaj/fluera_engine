import './scene_graph_transaction.dart';

// ---------------------------------------------------------------------------
// Scene Graph Savepoint
// ---------------------------------------------------------------------------

/// A lightweight savepoint within a [SceneGraphTransaction].
///
/// Captures the offset into the transaction's inverse-ops log at creation
/// time. Rolling back to a savepoint replays only the inverse ops recorded
/// **after** the savepoint, preserving mutations made before it.
///
/// This enables partial rollback within a single transaction, useful for
/// compound operations like "try to apply constraint A, if it fails,
/// undo A but keep the rest".
///
/// ```dart
/// final txn = graph.beginTransaction();
/// graph.addLayer(layerA);
/// final sp = txn.createSavepoint('before-constraint');
/// try {
///   applyConstraint(graph);
/// } catch (e) {
///   txn.rollbackToSavepoint(sp); // undo only the constraint
/// }
/// txn.commit(); // layerA is still committed
/// ```
class SceneGraphSavepoint {
  /// Human-readable name for debugging.
  final String name;

  /// Offset into the inverse-ops log at the moment this savepoint was created.
  final int inverseOpsOffset;

  /// Graph version at the moment this savepoint was created.
  final int versionAtSavepoint;

  const SceneGraphSavepoint({
    required this.name,
    required this.inverseOpsOffset,
    required this.versionAtSavepoint,
  });

  @override
  String toString() =>
      'SceneGraphSavepoint("$name", offset: $inverseOpsOffset)';
}
