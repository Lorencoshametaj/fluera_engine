import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/layers/layer_controller.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('LayerController.deleteNodes (F10)', () {
    late LayerController lc;

    setUp(() {
      lc = LayerController();
    });

    test('removes every stroke in the list', () async {
      for (var i = 0; i < 5; i++) {
        lc.addStroke(testStroke(id: 'stk_$i'));
      }
      final strokeNodes = lc.activeLayer!.node.children
          .where((c) => c.id.toString().startsWith('stk_'))
          .toList();
      expect(strokeNodes, hasLength(5));

      final removed = await lc.deleteNodes(strokeNodes);

      expect(removed, 5);
      expect(lc.activeLayer!.strokes, isEmpty);
    });

    test('returns 0 and is a no-op for empty input', () async {
      lc.addStroke(testStroke(id: 'survivor'));
      final removed = await lc.deleteNodes(const []);
      expect(removed, 0);
      expect(lc.activeLayer!.strokes, hasLength(1));
    });

    test('bulk delete lands as a single composite undo entry', () async {
      for (var i = 0; i < 4; i++) {
        lc.addStroke(testStroke(id: 'bulk_$i'));
      }
      final nodes = lc.activeLayer!.node.children
          .where((c) => c.id.toString().startsWith('bulk_'))
          .toList();
      expect(nodes, hasLength(4));

      await lc.deleteNodes(nodes);
      expect(lc.activeLayer!.strokes.where(
          (s) => s.id.startsWith('bulk_')), isEmpty);

      // One undo restores ALL four strokes — not just one.
      lc.undo();
      final remaining = lc.activeLayer!.strokes
          .where((s) => s.id.startsWith('bulk_'))
          .toList();
      expect(remaining, hasLength(4),
          reason: 'single Ctrl+Z reverts the entire bulk delete');
    });

    test('redo after composite undo reapplies all children', () async {
      for (var i = 0; i < 3; i++) {
        lc.addStroke(testStroke(id: 'redo_$i'));
      }
      final nodes = lc.activeLayer!.node.children
          .where((c) => c.id.toString().startsWith('redo_'))
          .toList();
      expect(nodes, hasLength(3));

      await lc.deleteNodes(nodes);
      // After delete: none of the redo_* strokes remain.
      expect(
        lc.activeLayer!.strokes.where((s) => s.id.startsWith('redo_')),
        isEmpty,
      );

      lc.undo();
      // After undo: all 3 back.
      expect(
        lc.activeLayer!.strokes.where((s) => s.id.startsWith('redo_')),
        hasLength(3),
      );

      lc.redo();
      // After redo: all 3 gone again — proves `reapplyDelta` unwinds the
      // composite forward instead of skipping it (pre-fix bug surfaced
      // from the eraser-pixel device test).
      expect(
        lc.activeLayer!.strokes.where((s) => s.id.startsWith('redo_')),
        isEmpty,
        reason: 'redo of a composite must reapply every child in forward order',
      );
    });

    test('survives orphan nodes without a parent (skips silently)', () async {
      // testStrokeNode produces a StrokeNode but does not attach it to a
      // LayerNode parent — so deleteNodes hits the "no typed API + no
      // GroupNode parent" branch.
      final orphan = testStrokeNode(id: 'orphan_1');
      // testStrokeNode's stroke is not in any layer, so even the typed
      // removeStroke path is a no-op. The point: no crash.
      final removed = await lc.deleteNodes([orphan]);
      // The orphan IS a StrokeNode so it routes through removeStroke
      // (no-op because not present); removed counter increments.
      expect(removed, anyOf(0, 1));
    });
  });
}
