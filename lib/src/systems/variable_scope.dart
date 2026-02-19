import './design_variables.dart';

// =============================================================================
// 🎯 VARIABLE SCOPE
//
// Per-node (typically per-frame) variable overrides. Allows a FrameNode to
// declare "within me, this collection uses mode X" — enabling sections of
// a document to have different themes, breakpoints, or locales.
//
// Modeled after Figma's "explicit variable mode" per frame.
// =============================================================================

/// A scoped variable mode override for a specific collection.
///
/// When attached to a node (typically a [FrameNode]), it tells the resolver:
/// "within this node's subtree, use mode [modeId] for collection [collectionId]."
///
/// ```dart
/// final darkSection = VariableScope(
///   collectionId: 'themes',
///   modeId: 'dark',
/// );
/// frame.variableScopes.add(darkSection);
/// ```
class VariableScope {
  /// The collection this scope applies to.
  final String collectionId;

  /// The mode to use within this scope.
  final String modeId;

  const VariableScope({required this.collectionId, required this.modeId});

  Map<String, dynamic> toJson() => {
    'collectionId': collectionId,
    'modeId': modeId,
  };

  factory VariableScope.fromJson(Map<String, dynamic> json) => VariableScope(
    collectionId: json['collectionId'] as String? ?? '',
    modeId: json['modeId'] as String? ?? '',
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VariableScope &&
          collectionId == other.collectionId &&
          modeId == other.modeId;

  @override
  int get hashCode => Object.hash(collectionId, modeId);

  @override
  String toString() => 'VariableScope($collectionId → $modeId)';
}

// ---------------------------------------------------------------------------
// Scoped Variable Resolver
// ---------------------------------------------------------------------------

/// Resolves the effective mode for a collection by walking up the node tree,
/// looking for [VariableScope] overrides.
///
/// Usage:
/// ```dart
/// // Given a node deep in a frame hierarchy:
/// final effectiveMode = ScopedVariableResolver.resolveMode(
///   collectionId: 'themes',
///   scopes: node.ancestorScopes, // collected from parent frames
///   fallbackModeId: resolver.getActiveMode('themes')!,
/// );
/// ```
///
/// The innermost scope wins (last in the list = closest ancestor).
class ScopedVariableResolver {
  /// Resolve the effective mode ID for a collection.
  ///
  /// [scopes] should be ordered from outermost to innermost ancestor.
  /// The last matching scope wins.
  /// Returns [fallbackModeId] if no scope overrides the collection.
  static String resolveMode({
    required String collectionId,
    required List<VariableScope> scopes,
    required String fallbackModeId,
  }) {
    // Walk from innermost to outermost — first match wins.
    for (int i = scopes.length - 1; i >= 0; i--) {
      if (scopes[i].collectionId == collectionId) {
        return scopes[i].modeId;
      }
    }
    return fallbackModeId;
  }

  /// Resolve effective modes for ALL collections at once.
  ///
  /// Returns a map of `collectionId → effectiveModeId`.
  static Map<String, String> resolveAllModes({
    required List<VariableScope> scopes,
    required Map<String, String> fallbackModes,
  }) {
    final result = Map<String, String>.from(fallbackModes);
    // Walk from outermost to innermost — innermost overrides.
    for (final scope in scopes) {
      result[scope.collectionId] = scope.modeId;
    }
    return result;
  }

  /// Resolve a variable value considering scope overrides.
  ///
  /// Resolves the effective mode for the variable's collection, then
  /// resolves the variable using that mode.
  static dynamic resolveVariable({
    required String variableId,
    required VariableCollection collection,
    required List<VariableScope> scopes,
    required String fallbackModeId,
  }) {
    final effectiveMode = resolveMode(
      collectionId: collection.id,
      scopes: scopes,
      fallbackModeId: fallbackModeId,
    );
    return collection.resolveVariable(variableId, effectiveMode);
  }
}

/// Mixin for nodes that support variable scoping (typically frames).
///
/// ```dart
/// class FrameNode extends GroupNode with VariableScopeMixin { ... }
/// ```
mixin VariableScopeMixin {
  /// Scoped variable mode overrides for this node's subtree.
  final List<VariableScope> variableScopes = [];

  /// Set the mode for a collection within this scope.
  void setScopeMode(String collectionId, String modeId) {
    variableScopes.removeWhere((s) => s.collectionId == collectionId);
    variableScopes.add(
      VariableScope(collectionId: collectionId, modeId: modeId),
    );
  }

  /// Remove the scope override for a collection.
  void removeScopeMode(String collectionId) {
    variableScopes.removeWhere((s) => s.collectionId == collectionId);
  }

  /// Get the scoped mode for a collection, or `null` if unscoped.
  String? getScopeMode(String collectionId) {
    for (int i = variableScopes.length - 1; i >= 0; i--) {
      if (variableScopes[i].collectionId == collectionId) {
        return variableScopes[i].modeId;
      }
    }
    return null;
  }

  /// Serialize scopes to JSON.
  List<Map<String, dynamic>> scopesToJson() =>
      variableScopes.map((s) => s.toJson()).toList();

  /// Load scopes from JSON.
  void loadScopesFromJson(List<dynamic>? json) {
    variableScopes.clear();
    if (json == null) return;
    for (final item in json) {
      try {
        variableScopes.add(
          VariableScope.fromJson(item as Map<String, dynamic>),
        );
      } catch (_) {
        // Resilient loading — skip malformed scope entries.
      }
    }
  }
}
