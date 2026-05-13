import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/history/canvas_delta_tracker.dart';
import 'package:fluera_engine/src/history/undo_redo_manager.dart';

void main() {
  group('UndoRedoManager.endBatchAsComposite', () {
    late UndoRedoManager mgr;

    setUp(() {
      mgr = UndoRedoManager.create();
    });

    CanvasDelta _strokeAdded(String id, {String layer = 'layer_0'}) => CanvasDelta(
          id: 'd_$id',
          type: CanvasDeltaType.strokeAdded,
          layerId: layer,
          timestamp: DateTime.now(),
          elementId: id,
          elementData: {'id': id},
        );

    test('aggregates N pushed deltas into a single composite entry', () {
      mgr.beginBatch();
      for (var i = 0; i < 50; i++) {
        mgr.pushDelta(_strokeAdded('s$i'));
      }
      mgr.endBatchAsComposite('Sposta cluster');

      // One entry on the stack — not 50.
      expect(mgr.undoCount, 1);
    });

    test('an empty batch pushes nothing', () {
      mgr.beginBatch();
      mgr.endBatchAsComposite('noop');
      expect(mgr.undoCount, 0);
    });

    test('a single-delta batch is unwrapped (no composite indirection)', () {
      mgr.beginBatch();
      mgr.pushDelta(_strokeAdded('only'));
      mgr.endBatchAsComposite('Sposta cluster');

      expect(mgr.undoCount, 1);
      // The entry should NOT be wrapped in composite — it's the original.
      // (Verified indirectly: undo() returns a strokeAdded delta, not
      //  a composite one.)
      final popped = mgr.undo();
      expect(popped, isNotNull);
      expect(popped!.type, CanvasDeltaType.strokeAdded);
      expect(popped.elementId, 'only');
    });

    test('composite delta carries the label and child deltas', () {
      mgr.beginBatch();
      mgr.pushDelta(_strokeAdded('a'));
      mgr.pushDelta(_strokeAdded('b'));
      mgr.pushDelta(_strokeAdded('c'));
      mgr.endBatchAsComposite('Allinea cluster');

      final popped = mgr.undo();
      expect(popped, isNotNull);
      expect(popped!.type, CanvasDeltaType.composite);
      expect(popped.compositeLabel, 'Allinea cluster');
      expect(popped.childDeltas, hasLength(3));
      expect(
        popped.childDeltas!.map((d) => d.elementId).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('undo returns the composite, redo re-pushes it intact', () {
      mgr.beginBatch();
      mgr.pushDelta(_strokeAdded('x'));
      mgr.pushDelta(_strokeAdded('y'));
      mgr.endBatchAsComposite('Colora cluster');

      expect(mgr.undoCount, 1);
      expect(mgr.redoCount, 0);

      mgr.undo();
      expect(mgr.undoCount, 0);
      expect(mgr.redoCount, 1);

      mgr.redo();
      expect(mgr.undoCount, 1);
      expect(mgr.redoCount, 0);
    });

    test('eraser-style remove+add fragments collapse into one entry', () {
      // Reproduces the pixel-eraser pattern: for each affected stroke,
      // the tool removes the original and pushes N replacement fragments.
      // Without the gesture-level batch wrapper, Ctrl+Z would pop just
      // one fragment at a time. With it, one undo reverts the whole pass.
      mgr.beginBatch();
      // First stroke split into 2 fragments.
      mgr.pushDelta(CanvasDelta(
        id: 'd_rm1',
        type: CanvasDeltaType.strokeRemoved,
        layerId: 'layer_0',
        timestamp: DateTime.now(),
        elementId: 's1',
        elementData: const {'id': 's1'},
      ));
      mgr.pushDelta(_strokeAdded('s1_a'));
      mgr.pushDelta(_strokeAdded('s1_b'));
      // Second stroke split into 1 fragment.
      mgr.pushDelta(CanvasDelta(
        id: 'd_rm2',
        type: CanvasDeltaType.strokeRemoved,
        layerId: 'layer_0',
        timestamp: DateTime.now(),
        elementId: 's2',
        elementData: const {'id': 's2'},
      ));
      mgr.pushDelta(_strokeAdded('s2_a'));
      mgr.endBatchAsComposite('Cancella');

      expect(mgr.undoCount, 1);
      final popped = mgr.undo();
      expect(popped, isNotNull);
      expect(popped!.type, CanvasDeltaType.composite);
      expect(popped.compositeLabel, 'Cancella');
      // 2 removed + 3 added = 5 child deltas.
      expect(popped.childDeltas, hasLength(5));
    });
  });
}
