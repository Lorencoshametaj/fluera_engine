import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/nodes/stroke_node.dart';
import 'package:fluera_engine/src/history/undo_redo_manager.dart';
import 'package:fluera_engine/src/layers/layer_controller.dart';
import 'package:fluera_engine/src/tools/lasso/lasso_tool.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('LassoTool.endDrag composite bake (F12)', () {
    late LayerController lc;
    late LassoTool lasso;

    setUp(() {
      lc = LayerController();
      lasso = LassoTool(layerController: lc);
    });

    StrokeNode _seedStrokeNode(String id, {Offset offset = Offset.zero}) {
      lc.addStroke(testStroke(id: id));
      final layer = lc.activeLayer!;
      final node = layer.node.children.firstWhere(
        (c) => c.id.toString() == id,
      ) as StrokeNode;
      if (offset != Offset.zero) {
        node.translate(offset.dx, offset.dy);
      }
      return node;
    }

    test('drag-end produces a single composite undo entry', () {
      final n1 = _seedStrokeNode('drag_1');
      final n2 = _seedStrokeNode('drag_2');
      final n3 = _seedStrokeNode('drag_3');

      // Simulate a drag: translate all three by the same offset.
      lasso.selectionManager.selectAll([n1, n2, n3]);
      lasso.startDrag(Offset.zero);
      n1.translate(50, 0);
      n2.translate(50, 0);
      n3.translate(50, 0);

      // Sanity baseline: capture undo stack size before endDrag bake.
      final beforeUndoCount = UndoRedoManager.instance.undoCount;

      lasso.endDrag();

      // Exactly ONE new undo entry — the composite "Sposta selezione",
      // regardless of how many strokes were translated.
      final afterUndoCount = UndoRedoManager.instance.undoCount;
      expect(afterUndoCount, beforeUndoCount + 1);

      // All three strokes are now baked at the new position.
      for (final id in ['drag_1', 'drag_2', 'drag_3']) {
        final s = lc.activeLayer!.strokes.firstWhere((s) => s.id == id);
        // testStroke puts the first point at (0,0); after the +50 bake it
        // should be at (50, 0).
        expect(s.points.first.position.dx, 50);
        expect(s.points.first.position.dy, 0);
      }
    });

    test('undo of the composite restores every stroke to its original points',
        () {
      final n1 = _seedStrokeNode('rev_1');
      final n2 = _seedStrokeNode('rev_2');

      lasso.selectionManager.selectAll([n1, n2]);
      lasso.startDrag(Offset.zero);
      n1.translate(80, 30);
      n2.translate(80, 30);
      lasso.endDrag();

      // After bake: both at offset.
      expect(
        lc.activeLayer!.strokes.firstWhere((s) => s.id == 'rev_1').points.first.position,
        const Offset(80, 30),
      );

      lc.undo();

      // After undo: both back at origin.
      for (final id in ['rev_1', 'rev_2']) {
        final s = lc.activeLayer!.strokes.firstWhere((s) => s.id == id);
        expect(s.points.first.position, Offset.zero,
            reason: 'one Ctrl+Z must restore $id to its pre-drag points');
      }
    });

    test('redo after composite undo reapplies the bake', () {
      final n = _seedStrokeNode('rdo_1');
      lasso.selectionManager.selectAll([n]);
      lasso.startDrag(Offset.zero);
      n.translate(120, 0);
      lasso.endDrag();

      lc.undo();
      lc.redo();

      final s = lc.activeLayer!.strokes.firstWhere((s) => s.id == 'rdo_1');
      expect(s.points.first.position.dx, 120);
    });

    test('drag-end with no actual movement does not create an undo entry', () {
      final n = _seedStrokeNode('noop_1');
      lasso.selectionManager.selectAll([n]);
      lasso.startDrag(Offset.zero);
      // No translate — drag was cancelled.
      final before = UndoRedoManager.instance.undoCount;
      lasso.endDrag();
      final after = UndoRedoManager.instance.undoCount;
      expect(after, before, reason: 'empty bake must not push an undo entry');
    });
  });
}
