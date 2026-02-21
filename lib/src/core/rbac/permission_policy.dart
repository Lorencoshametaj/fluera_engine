/// 🔐 PERMISSION POLICY — ABAC rules with attribute-based overrides.
///
/// A [PermissionPolicy] is a composable set of [PermissionRule]s that
/// can override standard RBAC decisions based on runtime attributes
/// (e.g. node type, node ownership, time of day, etc.).
///
/// Rules are evaluated in priority order (highest first). The first
/// matching rule wins. If no rule matches, the decision falls through
/// to standard RBAC (role-based check).
///
/// ```dart
/// final policy = PermissionPolicy(rules: [
///   // Block deleting PDF pages even for editors
///   PermissionRule(
///     permission: EnginePermission.removeNodes,
///     allow: false,
///     conditions: [
///       AttributeCondition('node.type', 'PdfPageNode'),
///     ],
///     priority: 100,
///   ),
///   // Allow viewers to export if canvas is public
///   PermissionRule(
///     permission: EnginePermission.exportCanvas,
///     allow: true,
///     conditions: [
///       AttributeCondition('canvas.isPublic', true),
///     ],
///     priority: 50,
///   ),
/// ]);
/// ```
library;

import 'engine_permission.dart';

// =============================================================================
// ATTRIBUTE CONDITION
// =============================================================================

/// A single attribute-based condition for ABAC policy evaluation.
///
/// Conditions test runtime attributes against expected values.
/// Multiple conditions in a rule are ANDed together.
class AttributeCondition {
  /// Dot-separated attribute path (e.g. `'node.type'`, `'actor.role'`).
  final String attribute;

  /// Expected value to match against.
  ///
  /// Comparison is performed via `==` for simple types.
  /// For `Set` or `List` values, checks if the attribute value is contained.
  final dynamic expectedValue;

  const AttributeCondition(this.attribute, this.expectedValue);

  /// Evaluate this condition against a map of runtime attributes.
  ///
  /// Returns `true` if the attribute exists and matches the expected value.
  bool evaluate(Map<String, dynamic> attributes) {
    final actual = attributes[attribute];
    if (actual == null) return false;

    if (expectedValue is Set) {
      return (expectedValue as Set).contains(actual);
    }
    if (expectedValue is List) {
      return (expectedValue as List).contains(actual);
    }
    return actual == expectedValue;
  }

  @override
  String toString() => 'AttributeCondition($attribute == $expectedValue)';
}

// =============================================================================
// PERMISSION RULE
// =============================================================================

/// A single ABAC rule that can override RBAC decisions.
///
/// Rules have a [priority] (higher = evaluated first) and a set of
/// [conditions] that must ALL match for the rule to apply.
class PermissionRule {
  /// Which permission this rule applies to.
  final EnginePermission permission;

  /// Whether this rule grants (`true`) or denies (`false`) the permission.
  final bool allow;

  /// Conditions that must ALL be true for this rule to match.
  ///
  /// An empty conditions list means the rule always matches.
  final List<AttributeCondition> conditions;

  /// Priority (higher = evaluated first).
  final int priority;

  /// Optional human-readable description.
  final String? description;

  const PermissionRule({
    required this.permission,
    required this.allow,
    this.conditions = const [],
    this.priority = 0,
    this.description,
  });

  /// Check if all conditions match the given attributes.
  bool matches(Map<String, dynamic> attributes) {
    if (conditions.isEmpty) return true;
    return conditions.every((c) => c.evaluate(attributes));
  }

  @override
  String toString() =>
      'PermissionRule(${permission.name}, '
      '${allow ? "ALLOW" : "DENY"}, '
      'priority=$priority, '
      'conditions=${conditions.length})';
}

// =============================================================================
// PERMISSION POLICY
// =============================================================================

/// Composable ABAC policy that overlays standard RBAC.
///
/// Contains a sorted list of [PermissionRule]s. When [evaluate] is called,
/// rules are checked in priority order (highest first) until a match is found.
class PermissionPolicy {
  /// The rules in this policy, sorted by priority (highest first).
  final List<PermissionRule> _rules;

  /// Create a policy with explicit rules.
  PermissionPolicy({required List<PermissionRule> rules})
    : _rules = List.of(rules)..sort((a, b) => b.priority.compareTo(a.priority));

  /// Empty policy — all decisions fall through to RBAC.
  const PermissionPolicy.empty() : _rules = const [];

  /// Standard policy — no ABAC overrides, pure RBAC.
  factory PermissionPolicy.standard() => const PermissionPolicy.empty();

  /// Read-only policy — explicitly deny all write operations.
  factory PermissionPolicy.readOnly() => PermissionPolicy(
    rules: [
      for (final perm in [
        EnginePermission.editContent,
        EnginePermission.addNodes,
        EnginePermission.removeNodes,
        EnginePermission.reorderNodes,
        EnginePermission.lockNodes,
        EnginePermission.manageVariables,
        EnginePermission.managePlugins,
        EnginePermission.manageRoles,
        EnginePermission.configureEngine,
      ])
        PermissionRule(
          permission: perm,
          allow: false,
          priority: 1000, // highest priority — overrides everything
          description: 'Read-only policy: deny ${perm.name}',
        ),
    ],
  );

  /// All rules in this policy (read-only).
  List<PermissionRule> get rules => List.unmodifiable(_rules);

  /// Evaluate the policy for a given [permission] and [attributes].
  ///
  /// Returns `true` if a matching rule allows the permission,
  /// `false` if a matching rule denies it, or `null` if no rule matches
  /// (fall through to RBAC).
  bool? evaluate(EnginePermission permission, Map<String, dynamic> attributes) {
    for (final rule in _rules) {
      if (rule.permission != permission) continue;
      if (rule.matches(attributes)) {
        return rule.allow;
      }
    }
    return null; // No matching rule — defer to RBAC
  }

  @override
  String toString() => 'PermissionPolicy(rules=${_rules.length})';
}
