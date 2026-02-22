/// 🗂️ COMPONENT SET — Figma-style grouping of related component variants.
///
/// Groups [SymbolDefinition]s that share the same variant axes into a set.
/// Supports auto-grouping by name prefix (e.g., "Button/Primary" → set "Button").
///
/// ```dart
/// final set = ComponentSet(
///   id: 'set-btn',
///   name: 'Button',
///   definitionIds: ['btn-primary', 'btn-secondary', 'btn-ghost'],
///   variantAxes: ['Style', 'Size'],
/// );
/// ```
library;

import '../core/nodes/symbol_system.dart';

// =============================================================================
// COMPONENT SET
// =============================================================================

/// A group of related [SymbolDefinition]s that form a component set.
///
/// In Figma, a component set is a collection of variants — e.g.,
/// "Button" with variants "Primary/Small", "Primary/Large", "Ghost/Small".
class ComponentSet {
  /// Unique set ID.
  final String id;

  /// Display name of the component set.
  String name;

  /// Description of the set.
  String description;

  /// IDs of the [SymbolDefinition]s that belong to this set.
  final List<String> _definitionIds;

  /// Shared variant axes (e.g., ["Style", "Size", "State"]).
  ///
  /// These are the variant properties that all definitions in the set share.
  final List<String> variantAxes;

  ComponentSet({
    required this.id,
    required this.name,
    this.description = '',
    List<String> definitionIds = const [],
    this.variantAxes = const [],
  }) : _definitionIds = List<String>.from(definitionIds);

  /// Unmodifiable view of definition IDs.
  List<String> get definitionIds => List.unmodifiable(_definitionIds);

  /// Number of variants in this set.
  int get variantCount => _definitionIds.length;

  /// Add a definition to this set.
  void addDefinition(String definitionId) {
    if (!_definitionIds.contains(definitionId)) {
      _definitionIds.add(definitionId);
    }
  }

  /// Remove a definition from this set.
  bool removeDefinition(String definitionId) =>
      _definitionIds.remove(definitionId);

  /// Check if a definition belongs to this set.
  bool contains(String definitionId) => _definitionIds.contains(definitionId);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'definitionIds': _definitionIds,
    'variantAxes': variantAxes,
  };

  factory ComponentSet.fromJson(Map<String, dynamic> json) => ComponentSet(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    definitionIds:
        (json['definitionIds'] as List<dynamic>?)?.cast<String>() ?? [],
    variantAxes: (json['variantAxes'] as List<dynamic>?)?.cast<String>() ?? [],
  );
}

// =============================================================================
// COMPONENT SET REGISTRY
// =============================================================================

/// Manages all component sets.
class ComponentSetRegistry {
  final Map<String, ComponentSet> _sets = {};

  /// All registered sets (unmodifiable).
  Map<String, ComponentSet> get sets => Map.unmodifiable(_sets);

  /// Number of sets.
  int get length => _sets.length;

  /// Register a component set.
  void register(ComponentSet set) => _sets[set.id] = set;

  /// Remove a set by ID.
  bool unregister(String setId) => _sets.remove(setId) != null;

  /// Get a set by ID.
  ComponentSet? get(String setId) => _sets[setId];

  /// Find which set a definition belongs to.
  ComponentSet? findSetForDefinition(String definitionId) {
    for (final set in _sets.values) {
      if (set.contains(definitionId)) return set;
    }
    return null;
  }

  /// Auto-group definitions by name prefix.
  ///
  /// Definitions with names like "Button/Primary", "Button/Secondary"
  /// are grouped into a set named "Button".
  ///
  /// [separator] is the delimiter used in names (default: "/").
  List<ComponentSet> autoGroup(
    SymbolRegistry registry, {
    String separator = '/',
    String idPrefix = 'auto-set-',
  }) {
    final groups = <String, List<String>>{};

    for (final def in registry.definitions) {
      final parts = def.name.split(separator);
      if (parts.length >= 2) {
        final prefix = parts.first.trim();
        groups.putIfAbsent(prefix, () => []).add(def.id);
      }
    }

    final result = <ComponentSet>[];
    int counter = 0;
    for (final entry in groups.entries) {
      if (entry.value.length < 2) continue; // Need 2+ to form a set.
      final set = ComponentSet(
        id: '$idPrefix${++counter}',
        name: entry.key,
        definitionIds: entry.value,
      );
      _sets[set.id] = set;
      result.add(set);
    }
    return result;
  }

  /// Get all definitions in a set, resolved from a [SymbolRegistry].
  List<SymbolDefinition> resolveDefinitions(
    String setId,
    SymbolRegistry registry,
  ) {
    final set = _sets[setId];
    if (set == null) return [];
    return set.definitionIds
        .map((id) => registry.lookup(id))
        .whereType<SymbolDefinition>()
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'sets': _sets.values.map((s) => s.toJson()).toList(),
  };

  static ComponentSetRegistry fromJson(Map<String, dynamic> json) {
    final reg = ComponentSetRegistry();
    for (final s in (json['sets'] as List<dynamic>? ?? [])) {
      final set = ComponentSet.fromJson(s as Map<String, dynamic>);
      reg._sets[set.id] = set;
    }
    return reg;
  }
}
