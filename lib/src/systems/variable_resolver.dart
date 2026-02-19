import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../core/scene_graph/canvas_node.dart';
import './design_variables.dart';
import './variable_binding.dart';

// =============================================================================
// 🎯 VARIABLE RESOLVER
//
// Runtime engine for resolving variable values against the active mode and
// applying them to bound canvas nodes. Extends ChangeNotifier for reactive
// UI updates when modes change.
// =============================================================================

/// Callback for applying variable values to node properties that are
/// subclass-specific or not part of the base [CanvasNode] API.
///
/// The consumer app can register custom property setters for properties
/// like `fillColor`, `strokeWidth`, etc. that live on node subclasses.
///
/// Returns `true` if the property was handled, `false` to fall back to
/// the default [NodePropertySetter].
typedef CustomPropertyApplier =
    bool Function(CanvasNode node, String property, dynamic value);

/// Resolves variable values for the active mode and applies them to bound nodes.
///
/// Owns the active mode per collection and provides reactive updates via
/// [ChangeNotifier] when modes change.
///
/// ```dart
/// final resolver = VariableResolver(
///   collections: [themeCollection],
///   bindings: bindingRegistry,
/// );
///
/// // Switch to dark mode
/// resolver.setActiveMode('themes', 'dark');
///
/// // Apply all bindings
/// resolver.resolveAndApply((nodeId) => sceneGraph.findNodeById(nodeId));
/// ```
///
/// DESIGN PRINCIPLES:
/// - Reactive: extends ChangeNotifier for widget rebuilds on mode change
/// - Pluggable: custom property appliers for subclass-specific properties
/// - Safe: gracefully handles missing variables, modes, or nodes
class VariableResolver extends ChangeNotifier {
  /// Variable collections.
  final List<VariableCollection> _collections;

  /// Binding registry.
  final VariableBindingRegistry _bindings;

  /// Active mode ID per collection (collectionId → modeId).
  final Map<String, String> _activeModes = {};

  /// Batch update depth counter. Notifications are suppressed while > 0.
  int _batchDepth = 0;

  /// Whether a notification is pending from a batched update.
  bool _batchDirty = false;

  /// Resolution cache — maps variableId → resolved value.
  ///
  /// Automatically invalidated on mode change. Avoids re-traversing
  /// collections on repeated [resolveVariable] calls.
  final Map<String, dynamic> _resolveCache = {};

  /// Optional custom property applier for subclass-specific node properties.
  CustomPropertyApplier? customPropertyApplier;

  /// Optional callback fired after [resolveAndApply] completes.
  ///
  /// Use this to trigger repaint or other side-effects after variables
  /// are applied to the scene graph.
  VoidCallback? onVariablesApplied;

  /// Read-only access to collections.
  List<VariableCollection> get collections => List.unmodifiable(_collections);

  /// Read-only access to bindings.
  VariableBindingRegistry get bindings => _bindings;

  /// Active mode map (collectionId → modeId).
  Map<String, String> get activeModes => Map.unmodifiable(_activeModes);

  VariableResolver({
    List<VariableCollection>? collections,
    VariableBindingRegistry? bindings,
    this.customPropertyApplier,
  }) : _collections = collections ?? [],
       _bindings = bindings ?? VariableBindingRegistry() {
    // Initialize active modes to default for each collection.
    for (final c in _collections) {
      _activeModes.putIfAbsent(c.id, () => c.defaultModeId);
    }
  }

  // ---------------------------------------------------------------------------
  // Collection management
  // ---------------------------------------------------------------------------

  /// Add a collection and initialize its active mode.
  void addCollection(VariableCollection collection) {
    if (_collections.any((c) => c.id == collection.id)) return;
    _collections.add(collection);
    _activeModes.putIfAbsent(collection.id, () => collection.defaultModeId);
  }

  /// Remove a collection and its active mode.
  void removeCollection(String collectionId) {
    _collections.removeWhere((c) => c.id == collectionId);
    _activeModes.remove(collectionId);
  }

  /// Find a collection by ID.
  VariableCollection? findCollection(String collectionId) {
    for (final c in _collections) {
      if (c.id == collectionId) return c;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Mode switching
  // ---------------------------------------------------------------------------

  /// Get the active mode for a collection.
  String? getActiveMode(String collectionId) => _activeModes[collectionId];

  /// Switch the active mode for a collection.
  ///
  /// Fires [notifyListeners] so that widgets can rebuild.
  /// Call [resolveAndApply] after this to update bound nodes.
  void setActiveMode(String collectionId, String modeId) {
    final collection = findCollection(collectionId);
    if (collection == null) return;

    // Validate mode exists.
    if (collection.findMode(modeId) == null) return;

    final oldMode = _activeModes[collectionId];
    if (oldMode == modeId) return;

    _activeModes[collectionId] = modeId;
    _resolveCache.clear(); // invalidate cache on mode change
    _notifyOrDefer();
  }

  /// Manually invalidate the resolution cache.
  ///
  /// Call this after external mutations (e.g. setting a variable value)
  /// that the resolver doesn't observe directly.
  void invalidateCache() => _resolveCache.clear();

  // ---------------------------------------------------------------------------
  // Batch updates
  // ---------------------------------------------------------------------------

  /// Begin a batch update. Notifications are suppressed until [endBatch].
  ///
  /// Use this when switching multiple modes at once to avoid N rebuilds.
  /// Calls can be nested.
  ///
  /// ```dart
  /// resolver.beginBatch();
  /// resolver.setActiveMode('themes', 'dark');
  /// resolver.setActiveMode('breakpoints', 'mobile');
  /// resolver.endBatch(); // single notification
  /// ```
  void beginBatch() => _batchDepth++;

  /// End a batch update. Fires a single notification if any modes changed.
  void endBatch() {
    if (_batchDepth <= 0) return;
    _batchDepth--;
    if (_batchDepth == 0 && _batchDirty) {
      _batchDirty = false;
      notifyListeners();
    }
  }

  /// Notify listeners or defer if inside a batch.
  void _notifyOrDefer() {
    if (_batchDepth > 0) {
      _batchDirty = true;
    } else {
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Resolution
  // ---------------------------------------------------------------------------

  /// Resolve a variable's current value given the active modes.
  ///
  /// Results are cached until the next mode change or [invalidateCache].
  /// Searches all collections for the variable, resolves against the
  /// active mode, and follows alias chains (up to depth 8) with cycle detection.
  dynamic resolveVariable(String variableId) {
    if (_resolveCache.containsKey(variableId)) {
      return _resolveCache[variableId];
    }
    final value = _resolveWithAlias(variableId, 8, <String>{});
    _resolveCache[variableId] = value;
    return value;
  }

  /// Type-safe resolution. Returns `null` if the resolved value is not
  /// of type [T].
  ///
  /// ```dart
  /// final opacity = resolver.resolveAs<double>('bg-opacity');
  /// final color   = resolver.resolveAs<int>('primary-color');
  /// ```
  T? resolveAs<T>(String variableId) {
    final value = resolveVariable(variableId);
    return value is T ? value : null;
  }

  /// Recursively resolve a variable, following alias chains.
  dynamic _resolveWithAlias(
    String variableId,
    int remainingDepth,
    Set<String> visited,
  ) {
    if (remainingDepth <= 0 || visited.contains(variableId)) return null;
    visited.add(variableId);

    for (final collection in _collections) {
      final variable = collection.findVariable(variableId);
      if (variable == null) continue;

      // If it's an alias, follow the chain.
      if (variable.isAlias) {
        return _resolveWithAlias(
          variable.aliasVariableId!,
          remainingDepth - 1,
          visited,
        );
      }

      // Resolve with mode inheritance chain.
      final activeModeId =
          _activeModes[collection.id] ?? collection.defaultModeId;
      final chain = collection.modeInheritanceChain(activeModeId);
      for (final modeId in chain) {
        if (variable.hasValueForMode(modeId)) {
          return variable.getValue(modeId);
        }
      }
      // Fall back to first available value.
      return variable.resolve(activeModeId);
    }
    return null;
  }

  /// Resolve all bindings and apply values to bound nodes.
  ///
  /// Uses [nodeResolver] to look up nodes by ID (typically
  /// `sceneGraph.findNodeById`).
  ///
  /// If [ancestorChecker] is provided, scope-restricted variables
  /// will only apply when the bound node is a descendant of
  /// the variable's [scopeNodeId].
  void resolveAndApply(
    CanvasNode? Function(String nodeId) nodeResolver, {
    bool Function(String nodeId, String ancestorId)? ancestorChecker,
  }) {
    for (final binding in _bindings.allBindings) {
      final value = resolveVariable(binding.variableId);
      if (value == null) continue;

      // Scope check.
      if (ancestorChecker != null) {
        final scopeId = _findScopeNodeId(binding.variableId);
        if (scopeId != null && !ancestorChecker(binding.nodeId, scopeId)) {
          continue; // node is not in scope
        }
      }

      final node = nodeResolver(binding.nodeId);
      if (node == null) continue;

      _applyToNode(node, binding.nodeProperty, value);
    }
    onVariablesApplied?.call();
  }

  /// Resolve and apply only bindings affected by a specific collection.
  ///
  /// More efficient than [resolveAndApply] when switching a single mode.
  void resolveAndApplyForCollection(
    String collectionId,
    CanvasNode? Function(String nodeId) nodeResolver,
  ) {
    final collection = findCollection(collectionId);
    if (collection == null) return;

    // Gather variable IDs from this collection.
    final varIds = <String>{};
    for (final v in collection.variables) {
      varIds.add(v.id);
    }

    // Apply only bindings for these variables.
    for (final varId in varIds) {
      final bindings = _bindings.bindingsForVariable(varId);
      if (bindings.isEmpty) continue;

      final value = resolveVariable(varId);
      if (value == null) continue;

      for (final binding in bindings) {
        final node = nodeResolver(binding.nodeId);
        if (node == null) continue;
        _applyToNode(node, binding.nodeProperty, value);
      }
    }
    onVariablesApplied?.call();
  }

  // ---------------------------------------------------------------------------
  // Property application
  // ---------------------------------------------------------------------------

  /// Apply a resolved value to a node property.
  void _applyToNode(CanvasNode node, String property, dynamic value) {
    // Try custom applier first.
    if (customPropertyApplier != null &&
        customPropertyApplier!(node, property, value)) {
      return;
    }

    // Fall back to built-in property setters.
    NodePropertySetter.apply(node, property, value);
  }

  /// Find the scopeNodeId for a variable across all collections.
  String? _findScopeNodeId(String variableId) {
    for (final collection in _collections) {
      final variable = collection.findVariable(variableId);
      if (variable != null) return variable.scopeNodeId;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Serialization (active modes only — collections and bindings serialized
  // separately by SceneGraph)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> activeModesToJson() =>
      Map<String, dynamic>.from(_activeModes);

  void loadActiveModes(Map<String, dynamic> json) {
    _activeModes.clear();
    for (final entry in json.entries) {
      _activeModes[entry.key] = entry.value as String;
    }
    // Ensure all collections have an active mode.
    for (final c in _collections) {
      _activeModes.putIfAbsent(c.id, () => c.defaultModeId);
    }
  }
}

// ---------------------------------------------------------------------------
// Node Property Setter
// ---------------------------------------------------------------------------

/// Static utility for applying resolved variable values to [CanvasNode]
/// base properties.
///
/// Handles the common properties shared by all node types.
/// For subclass-specific properties, use [CustomPropertyApplier].
class NodePropertySetter {
  /// Apply a value to a named property on a node.
  ///
  /// Returns `true` if the property was recognized and set.
  static bool apply(CanvasNode node, String property, dynamic value) {
    switch (property) {
      case 'opacity':
        if (value is num) {
          node.opacity = value.toDouble();
          return true;
        }

      case 'isVisible':
        if (value is bool) {
          node.isVisible = value;
          return true;
        }

      case 'isLocked':
        if (value is bool) {
          node.isLocked = value;
          return true;
        }

      case 'blendMode':
        if (value is String) {
          final mode = ui.BlendMode.values.where((m) => m.name == value);
          if (mode.isNotEmpty) {
            node.blendMode = mode.first;
            return true;
          }
        }

      case 'name':
        if (value is String) {
          node.name = value;
          return true;
        }
    }

    // Property not recognized — caller should use custom applier.
    return false;
  }
}
