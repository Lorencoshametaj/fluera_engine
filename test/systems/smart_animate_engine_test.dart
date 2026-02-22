import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:nebula_engine/src/core/nodes/frame_node.dart';
import 'package:nebula_engine/src/systems/smart_animate_engine.dart';
import 'package:nebula_engine/src/systems/smart_animate_snapshot.dart';

// =============================================================================
// Test helpers
// =============================================================================

FrameNode _frame(
  String id,
  String name, {
  double x = 0,
  double y = 0,
  Color? fillColor,
  double opacity = 1.0,
  double borderRadius = 0,
  List<FrameNode>? children,
}) {
  final frame = FrameNode(
    id: NodeId(id),
    name: name,
    fillColor: fillColor,
    opacity: opacity,
    borderRadius: borderRadius,
  );
  frame.setPosition(x, y);
  if (children != null) {
    for (final child in children) {
      frame.add(child);
    }
  }
  return frame;
}

void main() {
  group('SmartAnimateEngine', () {
    late SmartAnimateEngine engine;

    setUp(() {
      engine = const SmartAnimateEngine();
    });

    // =========================================================================
    // 1. Name-based matching
    // =========================================================================
    test('matches layers by name between frames', () {
      final source = _frame(
        'src',
        'Screen A',
        children: [
          _frame('s1', 'avatar', x: 10, y: 10),
          _frame('s2', 'title', x: 70, y: 10),
          _frame('s3', 'only-in-source', x: 0, y: 80),
        ],
      );

      final target = _frame(
        'tgt',
        'Screen B',
        children: [
          _frame('t1', 'avatar', x: 50, y: 50),
          _frame('t2', 'title', x: 70, y: 60),
          _frame('t3', 'only-in-target', x: 0, y: 100),
        ],
      );

      final plan = engine.createTransitionPlan(
        sourceFrame: source,
        targetFrame: target,
      );

      expect(plan.matchedCount, 2);
      expect(plan.exitingLayers.length, 1);
      expect(plan.enteringLayers.length, 1);
      expect(plan.exitingLayers.first.node.name, 'only-in-source');
      expect(plan.enteringLayers.first.node.name, 'only-in-target');
    });

    // =========================================================================
    // 2. Unmatched nodes sorted correctly
    // =========================================================================
    test('unmatched source nodes are exiting, target nodes are entering', () {
      final source = _frame(
        's',
        'A',
        children: [_frame('s1', 'alpha'), _frame('s2', 'beta')],
      );
      final target = _frame(
        't',
        'B',
        children: [_frame('t1', 'gamma'), _frame('t2', 'delta')],
      );

      final plan = engine.createTransitionPlan(
        sourceFrame: source,
        targetFrame: target,
      );

      expect(plan.matchedCount, 0);
      expect(plan.exitingLayers.length, 2);
      expect(plan.enteringLayers.length, 2);
      expect(plan.exitingLayers.every((l) => !l.isEntering), isTrue);
      expect(plan.enteringLayers.every((l) => l.isEntering), isTrue);
    });

    // =========================================================================
    // 3. No matches — completely different frames
    // =========================================================================
    test('no matches produces all entering/exiting', () {
      final source = _frame('s', 'A', children: [_frame('s1', 'foo')]);
      final target = _frame('t', 'B', children: [_frame('t1', 'bar')]);

      final plan = engine.createTransitionPlan(
        sourceFrame: source,
        targetFrame: target,
      );

      expect(plan.matchedCount, 0);
      expect(plan.exitingLayers.length, 1);
      expect(plan.enteringLayers.length, 1);
    });

    // =========================================================================
    // 4. Property snapshot captures position/opacity
    // =========================================================================
    test('snapshot captures key properties', () {
      final node = _frame(
        'n1',
        'test',
        x: 25,
        y: 30,
        opacity: 0.7,
        fillColor: const Color(0xFFFF0000),
      );

      final snap = SmartAnimateSnapshot.capture(node);

      expect(snap.nodeName, 'test');
      expect(snap.properties[AnimatableProperty.positionX], 25);
      expect(snap.properties[AnimatableProperty.positionY], 30);
      expect(snap.properties[AnimatableProperty.opacity], 0.7);
      expect(
        snap.properties.containsKey(AnimatableProperty.fillColorR),
        isTrue,
      );
    });

    // =========================================================================
    // 5. Interpolation at t=0 returns source, t=1 returns target
    // =========================================================================
    test('interpolation boundary conditions', () {
      final from = SmartAnimateSnapshot(
        nodeName: 'test',
        nodeType: 'FrameNode',
        properties: {
          AnimatableProperty.positionX: 0,
          AnimatableProperty.opacity: 0.2,
        },
      );
      final to = SmartAnimateSnapshot(
        nodeName: 'test',
        nodeType: 'FrameNode',
        properties: {
          AnimatableProperty.positionX: 100,
          AnimatableProperty.opacity: 1.0,
        },
      );

      final atZero = SmartAnimateSnapshot.interpolate(from, to, 0.0);
      final atOne = SmartAnimateSnapshot.interpolate(from, to, 1.0);

      expect(atZero.properties[AnimatableProperty.positionX], 0);
      expect(atZero.properties[AnimatableProperty.opacity], 0.2);
      expect(atOne.properties[AnimatableProperty.positionX], 100);
      expect(atOne.properties[AnimatableProperty.opacity], 1.0);
    });

    // =========================================================================
    // 6. Interpolation at t=0.5 returns midpoint
    // =========================================================================
    test('interpolation midpoint is correct', () {
      final from = SmartAnimateSnapshot(
        nodeName: 'test',
        nodeType: 'FrameNode',
        properties: {
          AnimatableProperty.positionX: 0,
          AnimatableProperty.opacity: 0.0,
        },
      );
      final to = SmartAnimateSnapshot(
        nodeName: 'test',
        nodeType: 'FrameNode',
        properties: {
          AnimatableProperty.positionX: 100,
          AnimatableProperty.opacity: 1.0,
        },
      );

      final mid = SmartAnimateSnapshot.interpolate(from, to, 0.5);

      expect(mid.properties[AnimatableProperty.positionX], closeTo(50, 0.01));
      expect(mid.properties[AnimatableProperty.opacity], closeTo(0.5, 0.01));
    });

    // =========================================================================
    // 7. Entering nodes fade in during transition
    // =========================================================================
    test('entering nodes fade in', () {
      final source = _frame('s', 'A');
      final target = _frame(
        't',
        'B',
        children: [_frame('t1', 'newElement', opacity: 1.0)],
      );

      final plan = engine.createTransitionPlan(
        sourceFrame: source,
        targetFrame: target,
      );

      // At t=0, entering node should fade to 0.
      engine.applyTransitionFrame(plan, 0.0);
      expect(plan.enteringLayers.first.node.opacity, closeTo(0.0, 0.01));

      // At t=1, entering node should be at full opacity.
      engine.applyTransitionFrame(plan, 1.0);
      expect(plan.enteringLayers.first.node.opacity, closeTo(1.0, 0.01));
    });

    // =========================================================================
    // 8. Exiting nodes fade out during transition
    // =========================================================================
    test('exiting nodes fade out', () {
      final source = _frame(
        's',
        'A',
        children: [_frame('s1', 'oldElement', opacity: 1.0)],
      );
      final target = _frame('t', 'B');

      final plan = engine.createTransitionPlan(
        sourceFrame: source,
        targetFrame: target,
      );

      // At t=0, exiting node should be at full opacity.
      engine.applyTransitionFrame(plan, 0.0);
      expect(plan.exitingLayers.first.node.opacity, closeTo(1.0, 0.01));

      // At t=1, exiting node should be faded out.
      engine.applyTransitionFrame(plan, 1.0);
      expect(plan.exitingLayers.first.node.opacity, closeTo(0.0, 0.01));
    });

    // =========================================================================
    // 9. Transition plan serialization
    // =========================================================================
    test('transition plan serializes to JSON', () {
      final source = _frame(
        's',
        'A',
        children: [_frame('s1', 'shared'), _frame('s2', 'removed')],
      );
      final target = _frame(
        't',
        'B',
        children: [_frame('t1', 'shared'), _frame('t2', 'added')],
      );

      final plan = engine.createTransitionPlan(
        sourceFrame: source,
        targetFrame: target,
      );

      final json = plan.toJson();
      expect(json['matchedCount'], 1);
      expect(json['exitingCount'], 1);
      expect(json['enteringCount'], 1);
      expect((json['matchedNames'] as List).contains('shared'), isTrue);
    });

    // =========================================================================
    // 10. Reset after transition restores final state
    // =========================================================================
    test('resetAfterTransition applies final target state', () {
      final source = _frame(
        's',
        'A',
        children: [_frame('s1', 'hero', x: 0, y: 0, opacity: 1.0)],
      );
      final target = _frame(
        't',
        'B',
        children: [_frame('t1', 'hero', x: 100, y: 50, opacity: 0.8)],
      );

      final plan = engine.createTransitionPlan(
        sourceFrame: source,
        targetFrame: target,
      );

      // Apply mid-transition.
      engine.applyTransitionFrame(plan, 0.5);

      // Reset to final state.
      engine.resetAfterTransition(plan);

      final hero = plan.matchedLayers.first.targetNode;
      expect(hero.opacity, closeTo(0.8, 0.01));
    });
  });

  group('SmartAnimateSnapshot', () {
    // =========================================================================
    // 11. JSON roundtrip
    // =========================================================================
    test('serializes and deserializes correctly', () {
      final snap = SmartAnimateSnapshot(
        nodeName: 'button',
        nodeType: 'FrameNode',
        properties: {
          AnimatableProperty.positionX: 42.5,
          AnimatableProperty.opacity: 0.75,
        },
      );

      final json = snap.toJson();
      final restored = SmartAnimateSnapshot.fromJson(json);

      expect(restored.nodeName, 'button');
      expect(restored.nodeType, 'FrameNode');
      expect(restored.properties[AnimatableProperty.positionX], 42.5);
      expect(restored.properties[AnimatableProperty.opacity], 0.75);
    });
  });
}
