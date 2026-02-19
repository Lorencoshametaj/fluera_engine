import 'dart:ui';
import './canvas_node.dart';
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
class SceneGraph with SceneGraphObservable {
  /// The root node of the scene graph. Direct children are layers.
  final GroupNode rootNode;

  /// Spatial index for O(log n) viewport culling and hit testing.
  final SpatialIndex spatialIndex = SpatialIndex();

  /// Dirty tracker for incremental repaint.
  final DirtyTracker dirtyTracker = DirtyTracker();

  /// Animation timeline for keyframe-based property animation.
  AnimationTimeline timeline = AnimationTimeline();

  /// Prototype flows for interactive prototyping links.
  final List<PrototypeFlow> prototypeFlows = [];

  /// Design variable collections (themes, breakpoints, etc.).
  final List<VariableCollection> variableCollections = [];

  /// Registry of variable-to-node property bindings.
  final VariableBindingRegistry variableBindings = VariableBindingRegistry();

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

  /// Monotonically-incrementing version stamp. Bumped on every mutation.
  int _version = 0;

  /// Current version of the scene graph (for change detection).
  int get version => _version;

  /// Increment the version stamp without structural changes.
  ///
  /// Use when a node is mutated in-place (e.g. stroke added directly to
  /// an existing [LayerNode]) and a full rebuild is not needed.
  void bumpVersion() => _version++;

  SceneGraph() : rootNode = GroupNode(id: '_root', name: 'Root') {
    addObserver(_bindingObserver);
  }

  // ---------------------------------------------------------------------------
  // Layer access
  // ---------------------------------------------------------------------------

  /// All layers in the scene graph (direct children of root).
  List<LayerNode> get layers => rootNode.childrenOfType<LayerNode>();

  /// Number of layers.
  int get layerCount => rootNode.children.whereType<LayerNode>().length;

  /// Add a layer to the scene graph.
  void addLayer(LayerNode layer) {
    _assertNotDisposed();
    rootNode.add(layer);
    _registerSubtree(layer);
    _version++;
    notifyNodeAdded(layer, rootNode.id);
  }

  /// Insert a layer at a specific index.
  void insertLayer(int index, LayerNode layer) {
    _assertNotDisposed();
    rootNode.insertAt(index, layer);
    _registerSubtree(layer);
    _version++;
    notifyNodeAdded(layer, rootNode.id);
  }

  /// Remove a layer by ID. Returns the removed layer, or null.
  LayerNode? removeLayer(String layerId) {
    _assertNotDisposed();
    final node = rootNode.removeById(layerId);
    if (node is LayerNode) {
      _unregisterSubtree(node);
      _version++;
      notifyNodeRemoved(node, rootNode.id);
      return node;
    }
    return null;
  }

  /// Find a layer by ID.
  LayerNode? findLayer(String layerId) {
    final node = rootNode.findChild(layerId);
    return node is LayerNode ? node : null;
  }

  /// Reorder layers.
  void reorderLayers(int oldIndex, int newIndex) {
    rootNode.reorder(oldIndex, newIndex);
    _version++;
  }

  // ---------------------------------------------------------------------------
  // Global queries
  // ---------------------------------------------------------------------------

  /// Find any node by ID anywhere in the tree.
  CanvasNode? findNodeById(String nodeId) => rootNode.findDescendant(nodeId);

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
    return {
      'version': 1,
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
    };
  }

  factory SceneGraph.fromJson(Map<String, dynamic> json) {
    final graph = SceneGraph();
    // Version field reserved for future migration logic.
    final sgData = json['sceneGraph'] as Map<String, dynamic>?;
    if (sgData == null) return graph;

    final layersJson = sgData['layers'] as List<dynamic>? ?? [];
    for (final layerJson in layersJson) {
      final layer = CanvasNodeFactory.layerFromJson(
        layerJson as Map<String, dynamic>,
      );
      graph.addLayer(layer);
    }

    // Restore timeline.
    if (json['timeline'] != null) {
      graph.timeline = AnimationTimeline.fromJson(
        json['timeline'] as Map<String, dynamic>,
      );
    }

    // Restore prototype flows.
    if (json['prototypeFlows'] != null) {
      for (final flowJson in json['prototypeFlows'] as List<dynamic>) {
        graph.prototypeFlows.add(
          PrototypeFlow.fromJson(flowJson as Map<String, dynamic>),
        );
      }
    }

    // Restore variable collections.
    if (json['variableCollections'] != null) {
      for (final cJson in json['variableCollections'] as List<dynamic>) {
        graph.variableCollections.add(
          VariableCollection.fromJson(cJson as Map<String, dynamic>),
        );
      }
    }

    // Restore variable bindings.
    if (json['variableBindings'] != null) {
      graph.variableBindings.loadFromJson(
        json['variableBindings'] as Map<String, dynamic>,
      );
    }

    // Restore active modes.
    if (json['variableActiveModes'] != null) {
      graph.variableResolver.loadActiveModes(
        json['variableActiveModes'] as Map<String, dynamic>,
      );
    }

    return graph;
  }

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

  /// Register a node subtree with the spatial index and dirty tracker.
  void _registerSubtree(CanvasNode node) {
    spatialIndex.insert(node);
    dirtyTracker.registerNode(node);
    if (node is GroupNode) {
      for (final child in node.children) {
        _registerSubtree(child);
      }
    }
  }

  /// Unregister a node subtree from the spatial index and dirty tracker.
  void _unregisterSubtree(CanvasNode node) {
    spatialIndex.remove(node.id);
    dirtyTracker.unregisterNode(node.id);
    if (node is GroupNode) {
      for (final child in node.children) {
        _unregisterSubtree(child);
      }
    }
  }

  /// Throw if this scene graph has been disposed.
  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('SceneGraph has been disposed and cannot be used.');
    }
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
    removeObserver(_bindingObserver);
    variableResolver.dispose();
    dirtyTracker.dispose();
    rootNode.clear();
    prototypeFlows.clear();
    variableCollections.clear();
    variableBindings.clear();
    disposeObservable();
  }
}
