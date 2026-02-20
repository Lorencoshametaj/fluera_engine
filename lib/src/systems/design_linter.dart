import '../core/scene_graph/canvas_node.dart';
import '../core/scene_graph/node_constraint.dart';
import '../core/scene_graph/scene_graph.dart';
import '../core/nodes/group_node.dart';
import 'accessibility_tree.dart';
import 'variable_binding.dart';

// ---------------------------------------------------------------------------
// LintSeverity
// ---------------------------------------------------------------------------

/// Severity level of a lint violation.
enum LintSeverity {
  /// Informational — suggestion for improvement.
  info,

  /// Warning — may cause issues under certain conditions.
  warning,

  /// Error — definite bug or critical quality issue.
  error,
}

// ---------------------------------------------------------------------------
// LintViolation
// ---------------------------------------------------------------------------

/// A single violation detected by a [DesignLintRule].
class LintViolation {
  /// Which rule detected this violation.
  final String ruleId;

  /// Severity level.
  final LintSeverity severity;

  /// Human-readable description.
  final String message;

  /// Node ID related to this violation (if applicable).
  final String? nodeId;

  /// Node name (for display).
  final String? nodeName;

  /// Suggested fix description.
  final String? suggestion;

  const LintViolation({
    required this.ruleId,
    required this.severity,
    required this.message,
    this.nodeId,
    this.nodeName,
    this.suggestion,
  });

  @override
  String toString() {
    final loc = nodeId != null ? ' ($nodeId)' : '';
    return '[${severity.name.toUpperCase()}] $ruleId$loc: $message';
  }

  Map<String, dynamic> toJson() => {
    'ruleId': ruleId,
    'severity': severity.name,
    'message': message,
    if (nodeId != null) 'nodeId': nodeId,
    if (nodeName != null) 'nodeName': nodeName,
    if (suggestion != null) 'suggestion': suggestion,
  };
}

// ---------------------------------------------------------------------------
// DesignLintRule
// ---------------------------------------------------------------------------

/// Abstract base for a design quality check.
///
/// Implement [check] to scan the scene graph and return violations.
abstract class DesignLintRule {
  /// Unique rule identifier (e.g., `a11y/missing-label`).
  String get id;

  /// Human-readable name.
  String get name;

  /// Default severity.
  LintSeverity get defaultSeverity;

  /// Whether this rule is enabled.
  bool enabled = true;

  /// Run the rule against a scene graph.
  List<LintViolation> check(SceneGraph graph);
}

// ---------------------------------------------------------------------------
// Built-in rules
// ---------------------------------------------------------------------------

/// Flags nodes missing accessibility labels.
class MissingA11yLabelRule extends DesignLintRule {
  @override
  String get id => 'a11y/missing-label';

  @override
  String get name => 'Missing Accessibility Label';

  @override
  LintSeverity get defaultSeverity => LintSeverity.warning;

  @override
  List<LintViolation> check(SceneGraph graph) {
    final violations = <LintViolation>[];
    for (final node in graph.allNodes) {
      final info = node.accessibilityInfo;
      // Skip decorative nodes and groups without a11y info.
      if (info == null) continue;
      if (info.role == AccessibilityRole.decorative) continue;
      if (!info.isAccessible) continue;

      if (info.label == null || info.label!.isEmpty) {
        violations.add(
          LintViolation(
            ruleId: id,
            severity: defaultSeverity,
            message: 'Accessible node is missing a label',
            nodeId: node.id,
            nodeName: node.name,
            suggestion: 'Set accessibilityInfo.label to a descriptive string',
          ),
        );
      }
    }
    return violations;
  }
}

/// Flags constraint conflicts (two constraints that oppose each other
/// on the same target node).
class ConstraintConflictRule extends DesignLintRule {
  @override
  String get id => 'constraint/conflict';

  @override
  String get name => 'Constraint Conflict';

  @override
  LintSeverity get defaultSeverity => LintSeverity.error;

  @override
  List<LintViolation> check(SceneGraph graph) {
    final violations = <LintViolation>[];

    // Group constraints by target node.
    final byTarget = <String, List<NodeConstraint>>{};
    for (final c in graph.nodeConstraints) {
      byTarget.putIfAbsent(c.targetNodeId, () => []).add(c);
    }

    for (final entry in byTarget.entries) {
      final constraints = entry.value;
      final types = constraints.map((c) => c.type).toSet();

      // Check for opposing alignment constraints.
      if (types.contains(NodeConstraintType.alignLeft) &&
          types.contains(NodeConstraintType.alignRight)) {
        violations.add(
          LintViolation(
            ruleId: id,
            severity: defaultSeverity,
            message: 'Conflicting alignLeft + alignRight on same target',
            nodeId: entry.key,
            suggestion: 'Remove one of the opposing alignment constraints',
          ),
        );
      }
      if (types.contains(NodeConstraintType.alignTop) &&
          types.contains(NodeConstraintType.alignBottom)) {
        violations.add(
          LintViolation(
            ruleId: id,
            severity: defaultSeverity,
            message: 'Conflicting alignTop + alignBottom on same target',
            nodeId: entry.key,
            suggestion: 'Remove one of the opposing alignment constraints',
          ),
        );
      }
    }

    return violations;
  }
}

/// Flags excessive group nesting depth.
class DeepNestingRule extends DesignLintRule {
  /// Maximum allowed nesting depth.
  final int maxDepth;

  DeepNestingRule({this.maxDepth = 10});

  @override
  String get id => 'structure/deep-nesting';

  @override
  String get name => 'Deep Nesting';

  @override
  LintSeverity get defaultSeverity => LintSeverity.warning;

  @override
  List<LintViolation> check(SceneGraph graph) {
    final violations = <LintViolation>[];
    _checkDepth(graph.rootNode, 0, violations);
    return violations;
  }

  void _checkDepth(CanvasNode node, int depth, List<LintViolation> violations) {
    if (depth > maxDepth) {
      violations.add(
        LintViolation(
          ruleId: id,
          severity: defaultSeverity,
          message: 'Nesting depth $depth exceeds maximum $maxDepth',
          nodeId: node.id,
          nodeName: node.name,
          suggestion: 'Flatten the group hierarchy or extract into a component',
        ),
      );
      return; // Don't recurse further to avoid duplicate warnings.
    }
    if (node is GroupNode) {
      for (final child in node.children) {
        _checkDepth(child, depth + 1, violations);
      }
    }
  }
}

/// Flags variable bindings that reference non-existent nodes.
class OrphanedBindingRule extends DesignLintRule {
  @override
  String get id => 'binding/orphaned';

  @override
  String get name => 'Orphaned Variable Binding';

  @override
  LintSeverity get defaultSeverity => LintSeverity.error;

  @override
  List<LintViolation> check(SceneGraph graph) {
    final violations = <LintViolation>[];

    // Collect all node IDs.
    final nodeIds = <String>{};
    for (final node in graph.allNodes) {
      nodeIds.add(node.id);
    }

    // Check each binding's target node.
    for (final binding in graph.variableBindings.allBindings) {
      if (!nodeIds.contains(binding.nodeId)) {
        violations.add(
          LintViolation(
            ruleId: id,
            severity: defaultSeverity,
            message:
                'Binding references node "${binding.nodeId}" which no longer exists',
            nodeId: binding.nodeId,
            suggestion: 'Remove the orphaned binding',
          ),
        );
      }
    }

    return violations;
  }
}

/// Flags nodes with empty names (unnamed).
class UnnamedNodeRule extends DesignLintRule {
  @override
  String get id => 'naming/unnamed-node';

  @override
  String get name => 'Unnamed Node';

  @override
  LintSeverity get defaultSeverity => LintSeverity.info;

  @override
  List<LintViolation> check(SceneGraph graph) {
    final violations = <LintViolation>[];
    for (final node in graph.allNodes) {
      if (node.name.isEmpty) {
        violations.add(
          LintViolation(
            ruleId: id,
            severity: defaultSeverity,
            message:
                'Node has no name — may be hard to identify in layer panel',
            nodeId: node.id,
            suggestion: 'Give the node a descriptive name',
          ),
        );
      }
    }
    return violations;
  }
}

// ---------------------------------------------------------------------------
// DesignLinter
// ---------------------------------------------------------------------------

/// Runs a set of [DesignLintRule]s against a [SceneGraph].
///
/// ```dart
/// final linter = DesignLinter()
///   ..addRule(MissingA11yLabelRule())
///   ..addRule(ConstraintConflictRule())
///   ..addRule(DeepNestingRule())
///   ..addRule(OrphanedBindingRule())
///   ..addRule(UnnamedNodeRule());
///
/// final violations = linter.lint(sceneGraph);
/// for (final v in violations) {
///   print(v);
/// }
/// ```
class DesignLinter {
  final List<DesignLintRule> _rules;

  /// Create an empty linter. Add rules via [addRule].
  DesignLinter() : _rules = [];

  DesignLinter._(this._rules);

  /// Add a lint rule.
  void addRule(DesignLintRule rule) => _rules.add(rule);

  /// Remove a lint rule by ID.
  void removeRule(String ruleId) => _rules.removeWhere((r) => r.id == ruleId);

  /// All registered rules (read-only).
  List<DesignLintRule> get rules => List.unmodifiable(_rules);

  /// Create a linter pre-loaded with all built-in rules.
  factory DesignLinter.withDefaults() {
    return DesignLinter()
      ..addRule(MissingA11yLabelRule())
      ..addRule(ConstraintConflictRule())
      ..addRule(DeepNestingRule())
      ..addRule(OrphanedBindingRule())
      ..addRule(UnnamedNodeRule());
  }

  /// Run all enabled rules against the scene graph.
  List<LintViolation> lint(SceneGraph graph) {
    final violations = <LintViolation>[];
    for (final rule in _rules) {
      if (!rule.enabled) continue;
      violations.addAll(rule.check(graph));
    }
    return violations;
  }

  /// Run lint and group results by severity.
  Map<LintSeverity, List<LintViolation>> lintGrouped(SceneGraph graph) {
    final all = lint(graph);
    return {
      LintSeverity.error:
          all.where((v) => v.severity == LintSeverity.error).toList(),
      LintSeverity.warning:
          all.where((v) => v.severity == LintSeverity.warning).toList(),
      LintSeverity.info:
          all.where((v) => v.severity == LintSeverity.info).toList(),
    };
  }

  /// Quick check: does the scene graph have any errors?
  bool hasErrors(SceneGraph graph) =>
      lint(graph).any((v) => v.severity == LintSeverity.error);

  /// Generate a human-readable lint report.
  String report(SceneGraph graph) {
    final violations = lint(graph);
    if (violations.isEmpty) return '✅ No design lint violations found.';

    final buffer = StringBuffer();
    final errors = violations.where((v) => v.severity == LintSeverity.error);
    final warnings = violations.where(
      (v) => v.severity == LintSeverity.warning,
    );
    final infos = violations.where((v) => v.severity == LintSeverity.info);

    buffer.writeln('Design Lint Report');
    buffer.writeln('${'=' * 40}');
    buffer.writeln(
      '${errors.length} error(s), ${warnings.length} warning(s), '
      '${infos.length} info(s)',
    );
    buffer.writeln();

    for (final v in violations) {
      buffer.writeln(v);
      if (v.suggestion != null) {
        buffer.writeln('  💡 ${v.suggestion}');
      }
    }

    return buffer.toString();
  }
}
