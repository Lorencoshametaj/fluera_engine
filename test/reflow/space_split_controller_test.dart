import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/reflow/space_split_controller.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';

// =============================================================================
// ✂️ SPACE-SPLIT CONTROLLER v3 — UNIT TESTS
// =============================================================================

ContentCluster _c(String id, double cx, double cy) {
  return ContentCluster(
    id: id,
    strokeIds: ['stroke_$id'],
    bounds: Rect.fromCenter(center: Offset(cx, cy), width: 100, height: 50),
    centroid: Offset(cx, cy),
  );
}

void main() {
  group('SpaceSplitController v3', () {
    // ─────────────────────────────────────────────────────────────────────
    // VERTICAL (original behavior)
    // ─────────────────────────────────────────────────────────────────────

    test('vertical: below pushed down, above pushed up', () {
      final c = SpaceSplitController();
      c.clusters = [_c('a', 50, 100), _c('b', 50, 300)];
      c.startSplit(200.0);
      final ghosts = c.updateSplit(100.0);

      expect(ghosts['a']!.dy, lessThan(0));
      expect(ghosts['b']!.dy, greaterThan(0));
    });

    test('vertical: squeeze reverses direction', () {
      final c = SpaceSplitController();
      c.clusters = [_c('a', 50, 100), _c('b', 50, 300)];
      c.startSplit(200.0);
      final ghosts = c.updateSplit(-100.0);

      expect(ghosts['a']!.dy, greaterThan(0));
      expect(ghosts['b']!.dy, lessThan(0));
    });

    test('vertical: gradient falloff near > far', () {
      final c = SpaceSplitController();
      c.clusters = [_c('near', 50, 250), _c('far', 50, 1200)];
      c.startSplit(200.0);
      final ghosts = c.updateSplit(200.0);

      expect(ghosts['near']!.dy, greaterThan(ghosts['far']!.dy));
    });

    // ─────────────────────────────────────────────────────────────────────
    // HORIZONTAL SPLIT (#3)
    // ─────────────────────────────────────────────────────────────────────

    test('horizontal: left pushed left, right pushed right', () {
      final c = SpaceSplitController();
      c.clusters = [_c('left', 100, 50), _c('right', 300, 50)];
      c.startSplit(200.0, axis: SplitAxis.horizontal);
      final ghosts = c.updateSplit(100.0);

      expect(ghosts['left']!.dx, lessThan(0));   // Pushed left
      expect(ghosts['right']!.dx, greaterThan(0)); // Pushed right
      // Y should be 0 for horizontal split
      expect(ghosts['left']!.dy, equals(0.0));
      expect(ghosts['right']!.dy, equals(0.0));
    });

    test('horizontal: squeeze reverses', () {
      final c = SpaceSplitController();
      c.clusters = [_c('left', 100, 50), _c('right', 300, 50)];
      c.startSplit(200.0, axis: SplitAxis.horizontal);
      final ghosts = c.updateSplit(-100.0);

      expect(ghosts['left']!.dx, greaterThan(0)); // Squeezed right
      expect(ghosts['right']!.dx, lessThan(0));    // Squeezed left
    });

    // ─────────────────────────────────────────────────────────────────────
    // AUTO-DETECT DIRECTION (#7)
    // ─────────────────────────────────────────────────────────────────────

    test('auto-detect: all below → unidirectional down, full spread', () {
      final c = SpaceSplitController();
      c.clusters = [
        _c('c1', 50, 300),
        _c('c2', 50, 400),
        _c('c3', 50, 500),
      ];
      c.startSplit(100.0); // All 3 are below split line

      expect(c.isUnidirectional, isTrue);
      expect(c.unidirectionalSign, equals(1)); // Push down

      final ghosts = c.updateSplit(100.0);
      // All should be pushed down
      for (final offset in ghosts.values) {
        expect(offset.dy, greaterThan(0));
      }
    });

    test('auto-detect: all above → unidirectional up', () {
      final c = SpaceSplitController();
      c.clusters = [
        _c('c1', 50, 100),
        _c('c2', 50, 200),
        _c('c3', 50, 300),
      ];
      c.startSplit(900.0); // All 3 are above split line

      expect(c.isUnidirectional, isTrue);
      expect(c.unidirectionalSign, equals(-1)); // Push up
    });

    test('auto-detect: mixed clusters → bidirectional', () {
      final c = SpaceSplitController();
      c.clusters = [
        _c('a1', 50, 100),
        _c('a2', 50, 150),
        _c('b1', 50, 250),
        _c('b2', 50, 300),
      ];
      c.startSplit(200.0); // 2 above, 2 below → not 85%

      expect(c.isUnidirectional, isFalse);
    });

    test('auto-detect unidirectional: full spread vs half spread', () {
      final c = SpaceSplitController();
      // All below at same distance
      c.clusters = [_c('c1', 50, 200.5)];
      c.startSplit(200.0);

      final unidirGhosts = c.updateSplit(200.0);
      // Unidirectional: gets full spread × falloff ≈ 200 × 1.0

      final c2 = SpaceSplitController();
      // Mix: one above, one below
      c2.clusters = [_c('a', 50, 199.5), _c('b', 50, 200.5)];
      c2.startSplit(200.0);
      final bidirGhosts = c2.updateSplit(200.0);
      // Bidirectional: gets half spread × falloff ≈ 100 × 1.0

      // Unidirectional should move more than bidirectional
      expect(unidirGhosts['c1']!.dy.abs(), greaterThan(bidirGhosts['b']!.dy.abs()));
    });

    // ─────────────────────────────────────────────────────────────────────
    // ELEMENT-LEVEL GHOSTS
    // ─────────────────────────────────────────────────────────────────────

    test('element ghosts expanded correctly', () {
      final c = SpaceSplitController();
      c.clusters = [
        ContentCluster(
          id: 'c1',
          strokeIds: ['s1', 's2'],
          shapeIds: ['sh1'],
          bounds: const Rect.fromLTWH(0, 250, 100, 50),
          centroid: const Offset(50, 275),
        ),
      ];
      c.startSplit(200.0);
      c.updateSplit(100.0);

      expect(c.elementGhostDisplacements.containsKey('s1'), isTrue);
      expect(c.elementGhostDisplacements.containsKey('s2'), isTrue);
      expect(c.elementGhostDisplacements.containsKey('sh1'), isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────
    // LIFECYCLE
    // ─────────────────────────────────────────────────────────────────────

    test('endSplit returns results', () {
      final c = SpaceSplitController();
      c.clusters = [_c('c1', 50, 300)];
      c.startSplit(200.0);
      c.updateSplit(100.0);
      final result = c.endSplit();

      expect(result.isNotEmpty, isTrue);
      expect(result.clusterDisplacements.containsKey('c1'), isTrue);
    });

    test('cancelSplit resets all state', () {
      final c = SpaceSplitController();
      c.clusters = [_c('c1', 50, 300)];
      c.startSplit(200.0);
      c.updateSplit(100.0);
      c.cancelSplit();

      expect(c.isActive, isFalse);
      expect(c.ghostDisplacements, isEmpty);
      expect(c.elementGhostDisplacements, isEmpty);
    });

    test('empty clusters → no crash', () {
      final c = SpaceSplitController();
      c.clusters = [];
      c.startSplit(200.0);
      final ghosts = c.updateSplit(100.0);
      expect(ghosts, isEmpty);
    });

    test('axis getter returns correct value', () {
      final c = SpaceSplitController();
      c.startSplit(200.0, axis: SplitAxis.horizontal);
      expect(c.axis, equals(SplitAxis.horizontal));
    });
  });
}
