/// 🏷️ SEMANTIC TOKEN — Token aliasing and reference chains.
///
/// Semantic tokens reference other design variables, enabling
/// an abstraction layer: `color.primary` → `blue.500`.
library;

import 'design_variables.dart';

/// An alias from a semantic name to a concrete design variable.
class SemanticTokenAlias {
  final String name;
  final String targetCollectionId;
  final String targetVariableId;
  final String? description;

  const SemanticTokenAlias({
    required this.name,
    required this.targetCollectionId,
    required this.targetVariableId,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'targetCollectionId': targetCollectionId,
    'targetVariableId': targetVariableId,
    if (description != null) 'description': description,
  };

  factory SemanticTokenAlias.fromJson(Map<String, dynamic> json) =>
      SemanticTokenAlias(
        name: json['name'] as String,
        targetCollectionId: json['targetCollectionId'] as String,
        targetVariableId: json['targetVariableId'] as String,
        description: json['description'] as String?,
      );

  @override
  String toString() =>
      'SemanticTokenAlias($name → $targetCollectionId/$targetVariableId)';
}

/// Resolved token value with its resolution chain.
class ResolvedToken {
  final String aliasName;
  final dynamic value;
  final DesignVariableType type;
  final List<String> resolutionChain;

  const ResolvedToken({
    required this.aliasName,
    required this.value,
    required this.type,
    required this.resolutionChain,
  });
}

/// Registry for semantic token aliases with circular reference detection.
class SemanticTokenRegistry {
  SemanticTokenRegistry();
  final Map<String, SemanticTokenAlias> _aliases = {};

  Map<String, SemanticTokenAlias> get aliases => Map.unmodifiable(_aliases);

  int get length => _aliases.length;

  void addAlias(SemanticTokenAlias alias) {
    _aliases[alias.name] = alias;
  }

  bool removeAlias(String name) => _aliases.remove(name) != null;

  SemanticTokenAlias? getAlias(String name) => _aliases[name];

  bool hasAlias(String name) => _aliases.containsKey(name);

  /// Resolve an alias to its concrete value.
  ///
  /// Follows alias chains (alias → alias → concrete) with
  /// circular reference detection (max depth 10).
  ResolvedToken? resolve(
    String aliasName,
    List<VariableCollection> collections,
    Map<String, String> activeModes,
  ) {
    final chain = <String>[];
    return _resolveRecursive(aliasName, collections, activeModes, chain, 0);
  }

  ResolvedToken? _resolveRecursive(
    String name,
    List<VariableCollection> collections,
    Map<String, String> activeModes,
    List<String> chain,
    int depth,
  ) {
    if (depth > 10) return null; // Circular reference protection.
    if (chain.contains(name)) return null; // Direct cycle detected.
    chain.add(name);

    final alias = _aliases[name];
    if (alias == null) return null;

    // Check if target is another alias.
    final targetKey = '${alias.targetCollectionId}/${alias.targetVariableId}';
    final chained = _aliases[targetKey];
    if (chained != null) {
      return _resolveRecursive(
        targetKey,
        collections,
        activeModes,
        chain,
        depth + 1,
      );
    }

    // Resolve to concrete value.
    for (final collection in collections) {
      if (collection.id != alias.targetCollectionId) continue;
      for (final variable in collection.variables) {
        if (variable.id != alias.targetVariableId &&
            variable.name != alias.targetVariableId) {
          continue;
        }
        final modeId =
            activeModes[collection.id] ??
            (collection.modes.isNotEmpty ? collection.modes.first.id : null);
        if (modeId == null) continue;
        final value = variable.values[modeId];
        if (value != null) {
          return ResolvedToken(
            aliasName: chain.first,
            value: value,
            type: variable.type,
            resolutionChain: chain,
          );
        }
      }
    }
    return null;
  }

  /// Validate all aliases — returns names with broken references.
  List<String> validate(List<VariableCollection> collections) {
    final broken = <String>[];
    for (final alias in _aliases.values) {
      bool found = false;
      for (final c in collections) {
        if (c.id != alias.targetCollectionId) continue;
        for (final v in c.variables) {
          if (v.id == alias.targetVariableId ||
              v.name == alias.targetVariableId) {
            found = true;
            break;
          }
        }
        if (found) break;
      }
      // Also check if it points to another alias.
      if (!found &&
          !_aliases.containsKey(
            '${alias.targetCollectionId}/${alias.targetVariableId}',
          )) {
        broken.add(alias.name);
      }
    }
    return broken;
  }

  /// Detect circular references. Returns the alias names involved.
  List<String> detectCircles() {
    final circles = <String>[];
    for (final name in _aliases.keys) {
      final visited = <String>{};
      var current = name;
      while (true) {
        if (visited.contains(current)) {
          circles.add(name);
          break;
        }
        visited.add(current);
        final alias = _aliases[current];
        if (alias == null) break;
        final next = '${alias.targetCollectionId}/${alias.targetVariableId}';
        if (!_aliases.containsKey(next)) break;
        current = next;
      }
    }
    return circles;
  }

  Map<String, dynamic> toJson() => {
    'aliases': _aliases.values.map((a) => a.toJson()).toList(),
  };

  factory SemanticTokenRegistry.fromJson(Map<String, dynamic> json) {
    final registry = SemanticTokenRegistry();
    final list = json['aliases'] as List<dynamic>? ?? [];
    for (final raw in list) {
      final alias = SemanticTokenAlias.fromJson(raw as Map<String, dynamic>);
      registry._aliases[alias.name] = alias;
    }
    return registry;
  }
}
