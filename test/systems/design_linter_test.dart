import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/design_linter.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:nebula_engine/src/core/nodes/group_node.dart';

import '../helpers/test_helpers.dart';

void main() {
  // ===========================================================================
  // LintViolation
  // ===========================================================================

  group('LintViolation', () {
    test('toString formats correctly', () {
      final v = LintViolation(
        ruleId: 'test/rule',
        severity: LintSeverity.error,
        message: 'Something bad',
        nodeId: 'n1',
      );
      final s = v.toString();
      expect(s, contains('ERROR'));
      expect(s, contains('test/rule'));
      expect(s, contains('Something bad'));
      expect(s, contains('n1'));
    });

    test('toJson includes all fields', () {
      final v = LintViolation(
        ruleId: 'test/rule',
        severity: LintSeverity.warning,
        message: 'Warn',
        nodeId: 'n1',
        nodeName: 'Node 1',
        suggestion: 'Fix it',
      );
      final json = v.toJson();
      expect(json['ruleId'], 'test/rule');
      expect(json['severity'], 'warning');
      expect(json['message'], 'Warn');
      expect(json['nodeId'], 'n1');
      expect(json['nodeName'], 'Node 1');
      expect(json['suggestion'], 'Fix it');
    });

    test('toJson omits null fields', () {
      final v = LintViolation(
        ruleId: 'r',
        severity: LintSeverity.info,
        message: 'msg',
      );
      final json = v.toJson();
      expect(json.containsKey('nodeId'), false);
      expect(json.containsKey('suggestion'), false);
    });
  });

  // ===========================================================================
  // UnnamedNodeRule — Simple built-in rule
  // ===========================================================================

  group('UnnamedNodeRule', () {
    test('detects nodes with empty names', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));
      // Nodes from test helpers have empty names by default
      final node = testStrokeNode(id: 'unnamed');
      layer.add(node);
      sg.addLayer(layer);

      final rule = UnnamedNodeRule();
      final violations = rule.check(sg);

      // All nodes without names should be flagged
      expect(violations.any((v) => v.ruleId == 'naming/unnamed-node'), true);
    });

    test('does not flag nodes with names', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));
      final node = testStrokeNode(id: 'named');
      node.name = 'My Nice Stroke';
      layer.add(node);
      sg.addLayer(layer);

      final rule = UnnamedNodeRule();
      final violations = rule.check(sg);

      // 'named' node should NOT be in violations
      final namedViolations = violations.where((v) => v.nodeId == 'named');
      expect(namedViolations, isEmpty);
    });

    test('rule has correct metadata', () {
      final rule = UnnamedNodeRule();
      expect(rule.id, 'naming/unnamed-node');
      expect(rule.name, 'Unnamed Node');
      expect(rule.defaultSeverity, LintSeverity.info);
      expect(rule.enabled, true);
    });
  });

  // ===========================================================================
  // DeepNestingRule
  // ===========================================================================

  group('DeepNestingRule', () {
    test('allows nesting up to maxDepth', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));
      sg.addLayer(layer);

      // Only one level of nesting — should be fine with default maxDepth=10
      final rule = DeepNestingRule();
      final violations = rule.check(sg);
      final nestingViolations = violations.where(
        (v) => v.ruleId == 'structure/deep-nesting',
      );
      expect(nestingViolations, isEmpty);
    });

    test('detects excessive nesting', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));

      // Build a chain of 5 nested groups
      var current = testGroupNode(id: 'g0');
      layer.add(current);
      for (int i = 1; i <= 4; i++) {
        final child = testGroupNode(id: 'g$i');
        current.add(child);
        current = child;
      }
      sg.addLayer(layer);

      // With maxDepth=2, should detect violations
      final rule = DeepNestingRule(maxDepth: 2);
      final violations = rule.check(sg);
      final nestingViolations = violations.where(
        (v) => v.ruleId == 'structure/deep-nesting',
      );
      expect(nestingViolations, isNotEmpty);
    });
  });

  // ===========================================================================
  // DesignLinter
  // ===========================================================================

  group('DesignLinter', () {
    test('addRule and rules', () {
      final linter = DesignLinter();
      linter.addRule(UnnamedNodeRule());
      linter.addRule(DeepNestingRule());

      expect(linter.rules, hasLength(2));
    });

    test('removeRule by id', () {
      final linter =
          DesignLinter()
            ..addRule(UnnamedNodeRule())
            ..addRule(DeepNestingRule());

      linter.removeRule('naming/unnamed-node');
      expect(linter.rules, hasLength(1));
      expect(linter.rules.first.id, 'structure/deep-nesting');
    });

    test('disabled rules are skipped', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));
      layer.add(testStrokeNode(id: 'unnamed'));
      sg.addLayer(layer);

      final rule = UnnamedNodeRule()..enabled = false;
      final linter = DesignLinter()..addRule(rule);
      final violations = linter.lint(sg);

      expect(
        violations.where((v) => v.ruleId == 'naming/unnamed-node'),
        isEmpty,
      );
    });

    test('lintGrouped groups by severity', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));
      layer.add(testStrokeNode(id: 'unnamed'));
      sg.addLayer(layer);

      final linter = DesignLinter()..addRule(UnnamedNodeRule());
      final grouped = linter.lintGrouped(sg);

      expect(grouped[LintSeverity.info], isA<List>());
      expect(grouped[LintSeverity.warning], isA<List>());
      expect(grouped[LintSeverity.error], isA<List>());
    });

    test('hasErrors returns false for info-only violations', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));
      layer.add(testStrokeNode(id: 'unnamed'));
      sg.addLayer(layer);

      final linter =
          DesignLinter()..addRule(UnnamedNodeRule()); // info severity
      expect(linter.hasErrors(sg), false);
    });

    test('report returns clean message for no violations', () {
      final sg = SceneGraph();
      final linter = DesignLinter(); // No rules
      final reportStr = linter.report(sg);
      expect(reportStr, contains('✅'));
    });

    test('report includes violation details', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));
      layer.add(testStrokeNode(id: 'unnamed'));
      sg.addLayer(layer);

      final linter = DesignLinter()..addRule(UnnamedNodeRule());
      final reportStr = linter.report(sg);
      expect(reportStr, contains('Design Lint Report'));
    });

    test('withDefaults includes all built-in rules', () {
      final linter = DesignLinter.withDefaults();
      expect(linter.rules.length, greaterThanOrEqualTo(5));
      final ids = linter.rules.map((r) => r.id).toSet();
      expect(ids, contains('a11y/missing-label'));
      expect(ids, contains('constraint/conflict'));
      expect(ids, contains('structure/deep-nesting'));
      expect(ids, contains('binding/orphaned'));
      expect(ids, contains('naming/unnamed-node'));
    });
  });
}
