import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../schema_version.dart';
import './scene_graph_integrity.dart';
import './canvas_node.dart';
import './node_id.dart';
import '../nodes/group_node.dart';
import '../nodes/layer_node.dart';
import './canvas_node_factory.dart';
import '../../systems/spatial_index.dart';
import '../../systems/dirty_tracker.dart';
import '../../systems/animation_timeline.dart';
import '../../systems/prototype_flow.dart';
import '../../systems/design_variables.dart';
import '../../systems/variable_binding.dart';
import '../../systems/variable_resolver.dart';
import './scene_graph_observer.dart';
import './scene_graph_interceptor.dart';
import './scene_graph_snapshot.dart';
import './scene_graph_transaction.dart';
import './node_constraint.dart';
import './invalidation_graph.dart';
import './transform_bridge.dart';
import './read_only_scene_graph.dart';
import '../engine_scope.dart';
import '../nodes/tabular_node.dart';
import '../nodes/latex_node.dart';

/// Top-level container for the canvas scene graph.
///
/// The [SceneGraph] owns a [rootNode] whose direct children are [LayerNode]s.
/// It provides convenience methods for querying, traversing, and hit-testing
/// the entire tree.
///
/// ```
/// SceneGraph
/// └── rootNode (GroupNode)
///     ├── LayerNode "Background"
///     │   ├── ImageNode
///     │   └── ShapeNode
///     ├── LayerNode "Drawing"
///     │   ├── StrokeNode
///     │   ├── GroupNode "Logo"
///     │   │   ├── ShapeNode
///     │   │   └── TextNode
///     │   └── StrokeNode
///     └── LayerNode "Annotations"
///         └── TextNode
/// ```
class SceneGraph with SceneGraphObservable implements TransformBridge {
  /// The root node of the scene graph. Direct children are layers.
  final GroupNode rootNode;

  /// O(1) node lookup index — maintained in sync with tree mutations.
  ///
  /// Every node registered via [_registerSubtree] is indexed here.
  /// This replaces the O(n) DFS in [findNodeById].
  final Map<String, CanvasNode> _nodeIndex = {};

  /// Read-only view of node IDs in the index (for integrity checking).
  Set<String> get nodeIndexIds => _nodeIndex.keys.toSet();

  /// Captures a read-consistent view of the graph.
  /// Any read on a stale epoch throws automatically.
  ReadConsistentView get readView => ReadConsistentView(this);

  /// Spatial index for O(log n) viewport culling and hit testing.
  final SpatialIndex spatialIndex = SpatialIndex();

  /// Dirty tracker for incremental repaint.
  final DirtyTracker dirtyTracker = DirtyTracker();

  /// Reactive invalidation graph for incremental scene graph updates.
  ///
  /// Tracks dirty flags ({@link DirtyFlag}) across nodes and propagates
  /// changes through registered dependency edges.
  final InvalidationGraph invalidationGraph = InvalidationGraph();

  /// Animation timeline for keyframe-based property animation.
  AnimationTimeline timeline = AnimationTimeline();

  /// Prototype flows for interactive prototyping links.
  final List<PrototypeFlow> prototypeFlows = [];

  /// Design variable collections (themes, breakpoints, etc.).
  final List<VariableCollection> variableCollections = [];

  /// Registry of variable-to-node property bindings.
  final VariableBindingRegistry variableBindings = VariableBindingRegistry();

  /// Scene-graph level constraints between nodes.
  final List<NodeConstraint> nodeConstraints = [];

  /// Pre-mutation interceptor chain.
  ///
  /// Register interceptors here to validate, reject, or transform
  /// mutations before they are applied.
  final InterceptorChain interceptorChain = InterceptorChain();

  /// Runtime resolver for variable values and mode switching.
  late final VariableResolver variableResolver = VariableResolver(
    collections: variableCollections,
    bindings: variableBindings,
  );

  /// Observer that auto-removes bindings when nodes are deleted.
  late final VariableBindingObserver _bindingObserver = VariableBindingObserver(
    variableBindings,
  );

  /// Whether this scene graph has been disposed.
  bool _disposed = false;

  /// Re-entrancy guard — true while a mutation is in progress.
  bool _mutating = false;

  /// Whether a mutation is currently in progress (for diagnostics).
  bool get isMutating => _mutating;

  /// Active transaction, if any.
  SceneGraphTransaction? _transaction;

  /// Whether a transaction is currently active.
  bool get isTransacting => _transaction != null;

  /// Monotonically-incrementing version stamp. Bumped on every mutation.
  int _version = 0;

  /// Current version of the scene graph (for change detection).
  int get version => _version;

  /// Increment the version stamp without structural changes.
  ///
  /// Use when a node is mutated in-place (e.g. stroke added directly to
  /// an existing [LayerNode]) and a full rebuild is not needed.
  void bumpVersion() {
    _guardedMutation(() {
      _version++;
    });
  }

  SceneGraph() : rootNode = GroupNode(id: NodeId('_root'), name: 'Root') {
    addObserver(_bindingObserver);
  }

  // ---------------------------------------------------------------------------
  // Concurrency safety
  // ---------------------------------------------------------------------------

  /// Execute [fn] within a mutation guard.
  ///
  /// Prevents re-entrant mutations (e.g. an observer modifying the graph
  /// inside its callback), which would leave the graph in an inconsistent
  /// intermediate state.
  void _guardedMutation(void Function() fn) {
    if (_mutating) {
      throw StateError(
        'Re-entrant SceneGraph mutation detected. '
        'Do not mutate the graph inside an observer callback.',
      );
    }
    _mutating = true;
    try {
      fn();
    } finally {
      _mutating = false;
    }
  }

  /// Capture the current version stamp.
  ///
  /// Use before async operations to detect if the graph was mutated
  /// during the async gap:
  /// ```dart
  /// final v = graph.snapshotVersion();
  /// await heavyWork();
  /// graph.assertUnchanged(v, context: 'heavyWork');
  /// ```
  int snapshotVersion() => _version;

  /// Assert the graph hasn't changed since [snapshot].
  ///
  /// Throws [StateError] if it was mutated during an async gap.
  void assertUnchanged(int snapshot, {String? context}) {
    if (_version != snapshot) {
      throw StateError(
        'SceneGraph was mutated during async operation '
        '(version $snapshot → $_version)'
        '${context != null ? ". Context: $context" : ""}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Layer access
  // ---------------------------------------------------------------------------

  /// All layers in the scene graph (direct children of root).
  ///
  /// Cached and invalidated by version stamp to avoid allocating
  /// a new filtered list on every access during rendering.
  List<LayerNode>? _cachedLayers;
  int _layerCacheVersion = -1;

  List<LayerNode> get layers {
    if (_layerCacheVersion == _version && _cachedLayers != null) {
      return _cachedLayers!;
    }
    _cachedLayers = rootNode.childrenOfType<LayerNode>();
    _layerCacheVersion = _version;
    return _cachedLayers!;
  }

  /// Number of layers.
  int get layerCount => rootNode.children.whereType<LayerNode>().length;

  /// Add a layer to the scene graph.
  ///
  /// Runs interceptor chain before mutation. Throws [MutationRejectedError]
  /// if any interceptor rejects the addition.
  void addLayer(LayerNode layer) {
    _assertNotDisposed();
    final intercepted = interceptorChain.runBeforeAdd(layer, rootNode.id);
    final target = intercepted is LayerNode ? intercepted : layer;
    _guardedMutation(() {
      rootNode.add(target);
      _registerSubtree(target);
      _version++;
      // Record inverse for transaction rollback.
      _transaction?.recordInverse(RemoveLayerInverseOp(target.id));
      notifyNodeAdded(target, rootNode.id);
    });
  }

  /// Insert a layer at a specific index.
  ///
  /// Runs interceptor chain before mutation.
  void insertLayer(int index, LayerNode layer) {
    _assertNotDisposed();
    final intercepted = interceptorChain.runBeforeAdd(layer, rootNode.id);
    final target = intercepted is LayerNode ? intercepted : layer;
    _guardedMutation(() {
      rootNode.insertAt(index, target);
      _registerSubtree(target);
      _version++;
      _transaction?.recordInverse(RemoveLayerInverseOp(target.id));
      notifyNodeAdded(target, rootNode.id);
    });
  }

  /// Remove a layer by ID. Returns the removed layer, or null.
  ///
  /// Runs interceptor chain before mutation.
  LayerNode? removeLayer(String layerId) {
    _assertNotDisposed();
    LayerNode? result;
    // Find the layer first for interceptor validation.
    final existing =
        rootNode.children
            .whereType<LayerNode>()
            .where((l) => l.id == layerId)
            .firstOrNull;
    if (existing != null) {
      interceptorChain.runBeforeRemove(existing, rootNode.id);
    }
    _guardedMutation(() {
      // Capture index BEFORE removal for inverse op.
      final layerIndex = rootNode.indexOfById(layerId);
      final node = rootNode.removeById(layerId);
      if (node is LayerNode) {
        _unregisterSubtree(node);
        _version++;
        _transaction?.recordInverse(
          InsertLayerInverseOp(node, layerIndex >= 0 ? layerIndex : 0),
        );
        notifyNodeRemoved(node, rootNode.id);
        result = node;
      }
    });
    return result;
  }

  /// Find a layer by ID.
  LayerNode? findLayer(String layerId) {
    final node = rootNode.findChild(layerId);
    return node is LayerNode ? node : null;
  }

  /// Reorder layers.
  void reorderLayers(int oldIndex, int newIndex) {
    _assertNotDisposed();
    _guardedMutation(() {
      rootNode.reorder(oldIndex, newIndex);
      _version++;
      _transaction?.recordInverse(ReorderLayersInverseOp(oldIndex, newIndex));
    });
  }

  // ---------------------------------------------------------------------------
  // Global queries
  // ---------------------------------------------------------------------------

  /// Find any node by ID anywhere in the tree — O(1).
  CanvasNode? findNodeById(String nodeId) => _nodeIndex[nodeId];

  /// Whether the tree contains a node with [nodeId] — O(1).
  bool containsNode(String nodeId) => _nodeIndex.containsKey(nodeId);

  /// All nodes in the tree (depth-first traversal).
  Iterable<CanvasNode> get allNodes => rootNode.allDescendants;

  /// All nodes whose world bounds intersect [viewport].
  ///
  /// Uses the spatial index for O(log n) performance when populated,
  /// falls back to linear scan otherwise.
  List<CanvasNode> nodesInBounds(Rect viewport) {
    if (spatialIndex.nodeCount > 0) {
      return spatialIndex.queryRange(viewport);
    }
    // Fallback to linear scan.
    final result = <CanvasNode>[];
    _collectNodesInBounds(rootNode, viewport, result);
    return result;
  }

  /// Hit test at a world-space point. Returns the topmost hit node.
  CanvasNode? hitTestAt(Offset worldPoint) {
    // Use spatial index for candidate narrowing if available.
    if (spatialIndex.nodeCount > 0) {
      final candidates = spatialIndex.queryPoint(worldPoint);
      // Return topmost (last added) hit.
      for (int i = candidates.length - 1; i >= 0; i--) {
        if (candidates[i].isVisible && candidates[i].hitTest(worldPoint)) {
          return candidates[i];
        }
      }
      return null;
    }

    // Fallback: traverse layers in reverse (top layer first)
    final layerList = layers;
    for (int i = layerList.length - 1; i >= 0; i--) {
      final layer = layerList[i];
      if (!layer.isVisible) continue;

      final hit = layer.hitTestChildren(worldPoint);
      if (hit != null) return hit;
    }
    return null;
  }

  /// Total number of leaf nodes (non-group nodes).
  int get totalElementCount {
    int count = 0;
    for (final node in allNodes) {
      if (node is! GroupNode) count++;
    }
    return count;
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() {
    if (_mutating) {
      throw StateError(
        'Cannot serialize SceneGraph while a mutation is in progress.',
      );
    }
    return {
      'version': kCurrentSchemaVersion,
      'sceneGraph': {'layers': layers.map((l) => l.toJson()).toList()},
      if (timeline.tracks.isNotEmpty) 'timeline': timeline.toJson(),
      if (prototypeFlows.isNotEmpty)
        'prototypeFlows': prototypeFlows.map((f) => f.toJson()).toList(),
      if (variableCollections.isNotEmpty)
        'variableCollections':
            variableCollections.map((c) => c.toJson()).toList(),
      if (variableBindings.bindingCount > 0)
        'variableBindings': variableBindings.toJson(),
      if (variableResolver.activeModes.isNotEmpty)
        'variableActiveModes': variableResolver.activeModesToJson(),
      if (nodeConstraints.isNotEmpty)
        'nodeConstraints': nodeConstraints.map((c) => c.toJson()).toList(),
    };
  }

  factory SceneGraph.fromJson(Map<String, dynamic> json) {
    // Run migration pipeline: v_old → v_current
    final migrated = migrateDocument(json);
    final graph = SceneGraph();
    final sgData = migrated['sceneGraph'] as Map<String, dynamic>?;
    if (sgData == null) return graph;

    final layersJson = sgData['layers'] as List<dynamic>? ?? [];
    for (final layerJson in layersJson) {
      final layer = CanvasNodeFactory.layerFromJson(
        layerJson as Map<String, dynamic>,
      );
      graph.addLayer(layer);
    }

    // Restore timeline.
    if (migrated['timeline'] != null) {
      graph.timeline = AnimationTimeline.fromJson(
        migrated['timeline'] as Map<String, dynamic>,
      );
    }

    // Restore prototype flows.
    if (migrated['prototypeFlows'] != null) {
      for (final flowJson in migrated['prototypeFlows'] as List<dynamic>) {
        graph.prototypeFlows.add(
          PrototypeFlow.fromJson(flowJson as Map<String, dynamic>),
        );
      }
    }

    // Restore variable collections.
    if (migrated['variableCollections'] != null) {
      for (final cJson in migrated['variableCollections'] as List<dynamic>) {
        graph.variableCollections.add(
          VariableCollection.fromJson(cJson as Map<String, dynamic>),
        );
      }
    }

    // Restore variable bindings.
    if (migrated['variableBindings'] != null) {
      graph.variableBindings.loadFromJson(
        migrated['variableBindings'] as Map<String, dynamic>,
      );
    }

    // Restore active modes.
    if (migrated['variableActiveModes'] != null) {
      graph.variableResolver.loadActiveModes(
        migrated['variableActiveModes'] as Map<String, dynamic>,
      );
    }

    // Restore node constraints.
    if (migrated['nodeConstraints'] != null) {
      for (final cJson in migrated['nodeConstraints'] as List<dynamic>) {
        graph.nodeConstraints.add(
          NodeConstraint.fromJson(cJson as Map<String, dynamic>),
        );
      }
    }

    assert(() {
      final violations = SceneGraphIntegrity.validate(graph);
      if (violations.isNotEmpty) {
        for (final v in violations) {
        }
      }
      return violations.isEmpty;
    }());

    return graph;
  }

  // ---------------------------------------------------------------------------
  // Integrity
  // ---------------------------------------------------------------------------

  /// Validate all structural invariants. Returns list of violations.
  ///
  /// Empty list = healthy graph.
  List<IntegrityViolation> validate() => SceneGraphIntegrity.validate(this);

  /// Validate and auto-repair fixable violations.
  IntegrityReport validateAndRepair() =>
      SceneGraphIntegrity.validateAndRepair(this);

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _collectNodesInBounds(
    CanvasNode node,
    Rect viewport,
    List<CanvasNode> result,
  ) {
    if (!node.isVisible) return;

    if (node is GroupNode) {
      // Check if group's bounds intersect at all (early exit)
      final groupBounds = node.worldBounds;
      if (!groupBounds.isEmpty && !viewport.overlaps(groupBounds)) return;

      for (final child in node.children) {
        _collectNodesInBounds(child, viewport, result);
      }
    } else {
      if (viewport.overlaps(node.worldBounds)) {
        result.add(node);
      }
    }
  }

  /// Warning threshold for `_nodeIndex` size — emits a telemetry warning once.
  static const int _nodeIndexWarningThreshold = 50000;

  /// Whether the node-index warning has already been emitted.
  bool _nodeIndexWarningEmitted = false;

  /// Register a node subtree with the node index, spatial index,
  /// dirty tracker, and owner graph reference.
  void _registerSubtree(CanvasNode node) {
    _nodeIndex[node.id] = node;
    node.ownerGraph = this;
    // Only insert leaf nodes into the spatial index — GroupNodes are
    // containers and their bounds are derived from children.
    if (node is! GroupNode) {
      spatialIndex.insert(node);
    }
    dirtyTracker.registerNode(node);
    if (node is GroupNode) {
      for (final child in node.children) {
        _registerSubtree(child);
      }
    }
    // Emit a telemetry warning when the index exceeds the threshold.
    if (!_nodeIndexWarningEmitted &&
        _nodeIndex.length > _nodeIndexWarningThreshold) {
      _nodeIndexWarningEmitted = true;
      telemetryBus?.counter('scene_graph.node_index_large').increment();
    }

    // --- Module-based Tabular/LaTeX Bridge Integration ---
    if (EngineScope.hasScope) {
      if (node is LatexNode) {
        EngineScope.current.tabularModule?.tabularLatexBridge.registerLatexNode(
          node,
          node.id.toString(),
        );
      }
    }
  }

  /// Unregister a node subtree from all indices and dispose.
  void _unregisterSubtree(CanvasNode node) {
    _nodeIndex.remove(node.id);
    spatialIndex.remove(node.id);
    dirtyTracker.unregisterNode(node.id);
    if (node is GroupNode) {
      for (final child in node.children) {
        _unregisterSubtree(child);
      }
    }

    // --- Module-based Tabular/LaTeX Bridge Integration ---
    if (EngineScope.hasScope) {
      if (node is LatexNode) {
        EngineScope.current.tabularModule?.tabularLatexBridge
            .unregisterLatexNode(node.id.toString());
      }
    }

    node.dispose();
  }

  /// Called by [CanvasNode.invalidateTransformCache] to bridge
  /// transform changes into the invalidation graph and spatial index.
  ///
  /// This ensures the spatial index AABB stays in sync with node transforms
  /// and the invalidation graph knows to re-compute dependent properties.
  @override
  void onNodeTransformInvalidated(CanvasNode node) {
    // NOTE: marking transform automatically cascades to bounds
    // via InvalidationGraph cascade rules.
    invalidationGraph.markDirty(node.id, DirtyFlag.transform);
    if (spatialIndex.contains(node.id)) {
      spatialIndex.update(node);
    }
    // Bump version so shouldRepaint detects the change and triggers
    // a cache rebuild (e.g., section moved/resized during drag).
    _version++;
  }

  /// Public helper for [TransactionInverseOp] rollback — registers a subtree.
  ///
  /// **Do not call directly** — used exclusively by inverse operations.
  void registerSubtreeForRollback(CanvasNode node) => _registerSubtree(node);

  /// Public helper for [TransactionInverseOp] rollback — unregisters a subtree.
  ///
  /// **Do not call directly** — used exclusively by inverse operations.
  void unregisterSubtreeForRollback(CanvasNode node) =>
      _unregisterSubtree(node);

  /// Rebuild the node index from the tree.
  ///
  /// Clears the existing index and re-walks the entire tree,
  /// re-registering every node. Used by integrity auto-repair.
  void rebuildNodeIndex() {
    _nodeIndex.clear();
    void walk(CanvasNode node) {
      _nodeIndex[node.id] = node;
      node.ownerGraph = this;
      if (node is GroupNode) {
        for (final child in node.children) {
          walk(child);
        }
      }
    }

    walk(rootNode);
  }

  /// Throw if this scene graph has been disposed.
  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('SceneGraph has been disposed and cannot be used.');
    }
  }

  /// Restore the version stamp to a previous value.
  ///
  /// **Package-internal** — used by [SceneGraphTransaction.rollback]
  /// to undo version increments that occurred during the transaction.
  void restoreVersion(int v) => _version = v;

  // ---------------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------------

  /// Begin an atomic transaction on this scene graph.
  ///
  /// During a transaction:
  /// - Observer notifications are **deferred** until commit
  /// - The [EngineEventBus] is **paused** (if connected)
  ///
  /// On commit, deferred notifications are flushed. On rollback,
  /// the graph is restored to its pre-transaction state.
  ///
  /// Throws [StateError] if a transaction is already active.
  SceneGraphTransaction beginTransaction() {
    _assertNotDisposed();
    if (_transaction != null) {
      throw StateError(
        'Cannot begin a new transaction: one is already active.',
      );
    }
    final snap = snapshot();
    beginDeferNotifications();
    final bus = engineEventBus;
    bus?.pause();
    _transaction = SceneGraphTransaction(
      graph: this,
      snapshot: snap,
      jsonBackupProvider: () => toJson(),
      versionAtStart: _version,
      eventBus: bus,
      telemetry: telemetryBus,
    );
    return _transaction!;
  }

  /// Commit the active transaction — flush deferred notifications.
  ///
  /// Throws [StateError] if no transaction is active.
  void commitTransaction() {
    if (_transaction == null) {
      throw StateError('No active transaction to commit.');
    }
    _transaction!.commit();
  }

  /// Rollback the active transaction — restore graph to pre-transaction state.
  ///
  /// Throws [StateError] if no transaction is active.
  @Deprecated('Use the SceneGraphTransaction.rollback() directly')
  void rollbackActiveTransaction() {
    if (_transaction == null) {
      throw StateError('No active transaction to rollback.');
    }
    _transaction!.rollback();
  }

  /// Called by [SceneGraphTransaction.commit] to flush deferred notifications.
  ///
  /// **Do not call directly** — use [commitTransaction] or
  /// [SceneGraphTransaction.commit] instead.
  ///
  /// This method is public only because [SceneGraphTransaction] lives in
  /// a separate file. Calling it outside the transaction contract will
  /// corrupt state.
  void finishTransaction({required bool flush}) {
    _transaction = null;
    if (flush) {
      flushDeferredNotifications();
    } else {
      clearDeferredNotifications();
    }
  }

  /// Called by [SceneGraphTransaction.rollback] to restore graph state.
  ///
  /// **Do not call directly** — use [SceneGraphTransaction.rollback] instead.
  ///
  /// This method is public only because [SceneGraphTransaction] lives in
  /// a separate file. Calling it outside the transaction contract will
  /// corrupt state.
  void restoreFromBackup(Map<String, dynamic> jsonBackup) {
    // Clear current state
    for (final layer in List.of(layers)) {
      _unregisterSubtree(layer);
    }
    _nodeIndex.clear();
    rootNode.clear();
    prototypeFlows.clear();
    variableCollections.clear();
    variableBindings.clear();
    nodeConstraints.clear();

    // Restore from backup
    final sgData = jsonBackup['sceneGraph'] as Map<String, dynamic>?;
    if (sgData != null) {
      final layersJson = sgData['layers'] as List<dynamic>? ?? [];
      for (final layerJson in layersJson) {
        final layer = CanvasNodeFactory.layerFromJson(
          layerJson as Map<String, dynamic>,
        );
        rootNode.add(layer);
        _registerSubtree(layer);
      }
    }

    // Restore timeline
    if (jsonBackup['timeline'] != null) {
      timeline = AnimationTimeline.fromJson(
        jsonBackup['timeline'] as Map<String, dynamic>,
      );
    }

    // Restore prototype flows
    if (jsonBackup['prototypeFlows'] != null) {
      for (final flowJson in jsonBackup['prototypeFlows'] as List<dynamic>) {
        prototypeFlows.add(
          PrototypeFlow.fromJson(flowJson as Map<String, dynamic>),
        );
      }
    }

    // Restore variable collections
    if (jsonBackup['variableCollections'] != null) {
      for (final cJson in jsonBackup['variableCollections'] as List<dynamic>) {
        variableCollections.add(
          VariableCollection.fromJson(cJson as Map<String, dynamic>),
        );
      }
    }

    // Restore variable bindings
    if (jsonBackup['variableBindings'] != null) {
      variableBindings.loadFromJson(
        jsonBackup['variableBindings'] as Map<String, dynamic>,
      );
    }

    // Restore active modes
    if (jsonBackup['variableActiveModes'] != null) {
      variableResolver.loadActiveModes(
        jsonBackup['variableActiveModes'] as Map<String, dynamic>,
      );
    }

    // Restore node constraints
    if (jsonBackup['nodeConstraints'] != null) {
      for (final cJson in jsonBackup['nodeConstraints'] as List<dynamic>) {
        nodeConstraints.add(
          NodeConstraint.fromJson(cJson as Map<String, dynamic>),
        );
      }
    }

    // Discard deferred notifications and finalize
    _transaction = null;
    clearDeferredNotifications();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Release all resources held by this scene graph.
  ///
  /// After calling dispose, the scene graph must not be used.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _transaction = null;
    removeObserver(_bindingObserver);
    variableResolver.dispose();
    dirtyTracker.dispose();
    _nodeIndex.clear();
    rootNode.clear();
    prototypeFlows.clear();
    variableCollections.clear();
    variableBindings.clear();
    nodeConstraints.clear();
    interceptorChain.clear();
    disposeObservable();
  }

  // ---------------------------------------------------------------------------
  // Snapshots & Diffing
  // ---------------------------------------------------------------------------

  /// Capture a lightweight structural snapshot of the current state.
  ///
  /// Snapshots are cheap (node IDs + hashes only) and can be compared
  /// via [diffFrom] for collaboration, change history, or smart merge.
  SceneGraphSnapshot snapshot() => SceneGraphSnapshot.capture(this);

  /// Compute the structural diff from [oldSnapshot] to the current state.
  SceneGraphDiff diffFrom(SceneGraphSnapshot oldSnapshot) =>
      oldSnapshot.diff(snapshot());
}
