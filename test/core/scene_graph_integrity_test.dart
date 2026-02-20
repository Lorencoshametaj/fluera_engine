import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph_integrity.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node_factory.dart';
import 'package:nebula_engine/src/core/nodes/group_node.dart';
import 'package:nebula_engine/src/core/nodes/layer_node.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_visitor.dart';

/// Test-only node with concrete bounds for spatial index testing.
class _BoundsNode extends CanvasNode {
  final Rect _bounds;
  _BoundsNode({required super.id, Rect? bounds})
    : _bounds = bounds ?? const Rect.fromLTWH(0, 0, 100, 100);

  @override
  Rect get localBounds => _bounds;

  @override
  Map<String, dynamic> toJson() => {'nodeType': 'test', 'id': id};

  @override
  R accept<R>(NodeVisitor<R> visitor) => throw UnimplementedError();
}

void main() {
  group('SceneGraphIntegrity', () {
    // =========================================================================
    // Healthy graph
    // =========================================================================

    test('healthy graph has zero violations', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);

      final violations = SceneGraphIntegrity.validate(graph);
      expect(violations, isEmpty);
      expect(graph.validate(), isEmpty);
    });

    test('empty graph is healthy', () {
      final graph = SceneGraph();
      expect(SceneGraphIntegrity.isHealthy(graph), isTrue);
    });

    // =========================================================================
    // Check 1: Duplicate IDs
    // =========================================================================

    test('detects duplicate IDs in tree', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);

      // Force a child with same ID via loadChildrenFromJson (bypasses assert)
      layer.loadChildrenFromJson([
        {'nodeType': 'group', 'id': 'layer1', 'children': []},
      ], CanvasNodeFactory.fromJson);

      final violations = SceneGraphIntegrity.validate(graph);
      final dupes = violations.where(
        (v) => v.type == ViolationType.duplicateId,
      );
      expect(dupes, isNotEmpty);
      expect(dupes.first.nodeId, 'layer1');
      expect(dupes.first.autoRepairable, isFalse);
    });

    // =========================================================================
    // Check 2: Parent pointer mismatch
    // =========================================================================

    test('detects parent pointer mismatch', () {
      final graph = SceneGraph();
      final layer1 = LayerNode(id: NodeId('layer1'));
      final layer2 = LayerNode(id: NodeId('layer2'));
      graph.addLayer(layer1);
      graph.addLayer(layer2);

      // Corrupt: make layer1's parent point to layer2 instead of root
      layer1.parent = layer2;

      final violations = SceneGraphIntegrity.validate(graph);
      final mismatches = violations.where(
        (v) => v.type == ViolationType.parentPointerMismatch,
      );
      expect(mismatches, isNotEmpty);
      expect(mismatches.first.nodeId, 'layer1');
      expect(mismatches.first.autoRepairable, isTrue);
    });

    test('repairs parent pointer mismatch', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);

      // Corrupt the parent pointer
      layer.parent = null;

      final report = SceneGraphIntegrity.validateAndRepair(graph);
      expect(report.violations, isNotEmpty);
      expect(report.repaired, isNotEmpty);

      // After repair, parent should be correct
      expect(layer.parent, graph.rootNode);

      // Re-validate should be clean
      expect(SceneGraphIntegrity.validate(graph), isEmpty);
    });

    // =========================================================================
    // Check 3: Root child types
    // =========================================================================

    test('detects non-LayerNode as root child', () {
      final graph = SceneGraph();
      // Force a GroupNode (not LayerNode) as root child
      graph.rootNode.loadChildrenFromJson([
        {'nodeType': 'group', 'id': 'not_a_layer', 'children': []},
      ], CanvasNodeFactory.fromJson);

      final violations = SceneGraphIntegrity.validate(graph);
      final rootChildViolations = violations.where(
        (v) => v.type == ViolationType.invalidRootChild,
      );
      expect(rootChildViolations, isNotEmpty);
      expect(rootChildViolations.first.nodeId, 'not_a_layer');
    });

    // =========================================================================
    // Check 4: Spatial index sync
    // =========================================================================

    test('detects spatial index desync', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);

      // Add a node with real bounds so it gets indexed
      final node = _BoundsNode(id: NodeId('bounded1'));
      layer.add(node);
      graph.spatialIndex.insert(node);
      graph.dirtyTracker.registerNode(node);

      // Verify it's indexed first...
      expect(graph.spatialIndex.contains('bounded1'), isTrue);

      // Now clear the spatial index to simulate desync
      graph.spatialIndex.clear();

      final violations = SceneGraphIntegrity.validate(graph);
      final desync = violations.where(
        (v) => v.type == ViolationType.spatialIndexDesync,
      );
      expect(desync, isNotEmpty);
      expect(desync.first.autoRepairable, isTrue);
    });

    test('repairs spatial index desync', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);

      // Add node with real bounds
      final node = _BoundsNode(id: NodeId('bounded2'));
      layer.add(node);
      graph.spatialIndex.insert(node);
      graph.dirtyTracker.registerNode(node);

      // Desync
      graph.spatialIndex.clear();

      final report = graph.validateAndRepair();
      expect(
        report.repaired.any((v) => v.type == ViolationType.spatialIndexDesync),
        isTrue,
      );

      // After repair, the node should be back in the index
      expect(graph.spatialIndex.contains('bounded2'), isTrue);
    });

    // =========================================================================
    // Check 5: Dirty tracker sync
    // =========================================================================

    test('detects dirty tracker desync', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);

      // Manually unregister from dirty tracker
      graph.dirtyTracker.unregisterNode('layer1');

      final violations = SceneGraphIntegrity.validate(graph);
      final desync = violations.where(
        (v) => v.type == ViolationType.dirtyTrackerDesync,
      );
      expect(desync, isNotEmpty);
    });

    test('repairs dirty tracker desync', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);

      graph.dirtyTracker.unregisterNode('layer1');

      final report = graph.validateAndRepair();
      expect(
        report.repaired.any((v) => v.type == ViolationType.dirtyTrackerDesync),
        isTrue,
      );

      // After repair, marking dirty should work
      graph.dirtyTracker.markDirtyById('layer1');
      expect(graph.dirtyTracker.isDirty('layer1'), isTrue);
    });

    // =========================================================================
    // Check 6: Depth overflow
    // =========================================================================

    test('detects excessive tree depth', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);

      // Build a deeply nested chain > kMaxTreeDepth
      GroupNode current = layer;
      for (int i = 0; i < kMaxTreeDepth + 5; i++) {
        final child = GroupNode(id: NodeId('deep_$i'));
        current.add(child);
        current = child;
      }

      final violations = SceneGraphIntegrity.validate(graph);
      final depthViolations = violations.where(
        (v) => v.type == ViolationType.depthOverflow,
      );
      expect(depthViolations, isNotEmpty);
      expect(depthViolations.first.autoRepairable, isFalse);
    });

    // =========================================================================
    // IntegrityReport
    // =========================================================================

    test('IntegrityReport.isHealthy is true for clean graph', () {
      final graph = SceneGraph();
      final report = graph.validateAndRepair();
      expect(report.isHealthy, isTrue);
      expect(report.isFullyRepaired, isTrue);
      expect(report.violations, isEmpty);
      expect(report.repaired, isEmpty);
    });

    test('IntegrityReport.unresolved filters correctly', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);

      // Corrupt parent (repairable) AND add non-layer root child (not repairable)
      layer.parent = null;
      graph.rootNode.loadChildrenFromJson([
        {'nodeType': 'group', 'id': 'bad_root_child', 'children': []},
      ], CanvasNodeFactory.fromJson);

      final report = graph.validateAndRepair();
      expect(report.violations, isNotEmpty);
      // Should have some unresolved violations
      expect(report.unresolved, isNotEmpty);
    });

    // =========================================================================
    // Convenience methods
    // =========================================================================

    test('SceneGraph.validate() delegates to SceneGraphIntegrity', () {
      final graph = SceneGraph();
      graph.addLayer(LayerNode(id: NodeId('l1')));

      final direct = SceneGraphIntegrity.validate(graph);
      final convenience = graph.validate();
      expect(convenience.length, direct.length);
    });

    test('SceneGraphIntegrity.isHealthy shortcut works', () {
      final graph = SceneGraph();
      graph.addLayer(LayerNode(id: NodeId('l1')));
      expect(SceneGraphIntegrity.isHealthy(graph), isTrue);
    });

    // =========================================================================
    // IntegrityMetrics
    // =========================================================================

    test('IntegrityMetrics tracks validateAndRepair calls', () {
      IntegrityMetrics.instance.reset();

      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);

      // Break something repairable
      layer.parent = null;
      graph.validateAndRepair();

      expect(IntegrityMetrics.instance.totalChecks, 1);
      expect(IntegrityMetrics.instance.totalViolationsDetected, greaterThan(0));
      expect(IntegrityMetrics.instance.totalRepairsApplied, greaterThan(0));
      expect(IntegrityMetrics.instance.lastCheckAt, isNotNull);
    });

    test('IntegrityMetrics.toJson returns valid map', () {
      IntegrityMetrics.instance.reset();

      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);
      // Trigger a repairable violation so metrics are recorded
      layer.parent = null;
      graph.validateAndRepair();

      final json = IntegrityMetrics.instance.toJson();
      expect(json['totalChecks'], 1);
      expect(json.containsKey('lastCheckAt'), isTrue);
    });

    test('IntegrityMetrics.reset clears all counters', () {
      IntegrityMetrics.instance.reset();
      expect(IntegrityMetrics.instance.totalChecks, 0);
      expect(IntegrityMetrics.instance.totalViolationsDetected, 0);
      expect(IntegrityMetrics.instance.totalRepairsApplied, 0);
      expect(IntegrityMetrics.instance.lastCheckAt, isNull);
    });

    // =========================================================================
    // IntegrityWatchdog
    // =========================================================================

    test('IntegrityWatchdog starts and disposes correctly', () {
      final graph = SceneGraph();
      final watchdog = IntegrityWatchdog(
        graph,
        interval: const Duration(seconds: 60),
      );

      expect(watchdog.isActive, isTrue);

      watchdog.dispose();
      expect(watchdog.isActive, isFalse);
    });

    // =========================================================================
    // Check 7: Cycle detection
    // =========================================================================

    test('detects cycle in parent chain', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);

      final g1 = GroupNode(id: NodeId('g1'));
      final g2 = GroupNode(id: NodeId('g2'));
      layer.add(g1);
      g1.add(g2);

      // Corrupt: create a cycle by pointing g2's parent back to g2 itself
      g2.parent = g2;

      final violations = SceneGraphIntegrity.validate(graph);
      final cycles = violations.where((v) => v.type == ViolationType.cycle);
      expect(cycles, isNotEmpty);
      expect(cycles.first.autoRepairable, isFalse);
    });

    // =========================================================================
    // Cumulative metrics
    // =========================================================================

    test('IntegrityMetrics accumulates across multiple runs', () {
      IntegrityMetrics.instance.reset();

      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);

      // Run 1: trigger a violation
      layer.parent = null;
      graph.validateAndRepair();

      // Run 2: trigger another violation
      graph.dirtyTracker.unregisterNode('layer1');
      graph.validateAndRepair();

      expect(IntegrityMetrics.instance.totalChecks, 2);
      expect(IntegrityMetrics.instance.totalViolationsDetected, greaterThan(1));
      expect(IntegrityMetrics.instance.totalRepairsApplied, greaterThan(1));
    });

    test('IntegrityMetrics tracks clean runs too', () {
      IntegrityMetrics.instance.reset();

      final graph = SceneGraph();
      graph.validateAndRepair(); // No violations

      expect(IntegrityMetrics.instance.totalChecks, 1);
      expect(IntegrityMetrics.instance.totalViolationsDetected, 0);
      expect(IntegrityMetrics.instance.totalRepairsApplied, 0);
      expect(IntegrityMetrics.instance.lastCheckAt, isNotNull);
    });

    // =========================================================================
    // validate() is pure (no side effects)
    // =========================================================================

    test('validate does not mutate dirty tracker state', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer1'));
      graph.addLayer(layer);

      // Ensure nothing is dirty before validate
      graph.dirtyTracker.clearAll();
      expect(graph.dirtyTracker.hasDirty, isFalse);

      // Run validate — should NOT make anything dirty
      SceneGraphIntegrity.validate(graph);

      expect(graph.dirtyTracker.hasDirty, isFalse);
    });
  });
}
