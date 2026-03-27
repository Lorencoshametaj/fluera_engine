import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/history/undo_redo_manager.dart';
import 'package:fluera_engine/src/history/canvas_delta_tracker.dart';

void main() {
  late UndoRedoManager manager;

  setUp(() {
    manager = UndoRedoManager.instance;
    manager.resetForTesting();
  });

  tearDown(() {
    manager.resetForTesting();
  });

  CanvasDelta _makeDelta(
    CanvasDeltaType type, {
    String id = 'delta-1',
    String layerId = 'layer-1',
  }) {
    return CanvasDelta(
      id: id,
      type: type,
      layerId: layerId,
      timestamp: DateTime.now(),
      elementId: 'elem-$id',
      elementData: {'key': 'value'},
    );
  }

  group('UndoRedoManager — basic operations', () {
    test('starts with empty stacks', () {
      expect(manager.canUndo, isFalse);
      expect(manager.canRedo, isFalse);
      expect(manager.undoLabel, isNull);
      expect(manager.redoLabel, isNull);
    });

    test('pushDelta enables undo', () {
      manager.pushDelta(_makeDelta(CanvasDeltaType.strokeAdded));
      expect(manager.canUndo, isTrue);
      expect(manager.canRedo, isFalse);
    });

    test('undo moves delta to redo stack', () {
      final delta = _makeDelta(CanvasDeltaType.strokeAdded);
      manager.pushDelta(delta);

      final undone = manager.undo();
      expect(undone, isNotNull);
      expect(undone!.id, delta.id);
      expect(manager.canUndo, isFalse);
      expect(manager.canRedo, isTrue);
    });

    test('redo moves delta back to undo stack', () {
      manager.pushDelta(_makeDelta(CanvasDeltaType.strokeAdded));
      manager.undo();

      final redone = manager.redo();
      expect(redone, isNotNull);
      expect(manager.canUndo, isTrue);
      expect(manager.canRedo, isFalse);
    });

    test('undo returns null when stack is empty', () {
      expect(manager.undo(), isNull);
    });

    test('redo returns null when stack is empty', () {
      expect(manager.redo(), isNull);
    });

    test('pushing new delta clears redo stack', () {
      manager.pushDelta(_makeDelta(CanvasDeltaType.strokeAdded, id: NodeId('a')));
      manager.undo();
      expect(manager.canRedo, isTrue);

      manager.pushDelta(_makeDelta(CanvasDeltaType.strokeAdded, id: NodeId('b')));
      expect(manager.canRedo, isFalse);
    });

    test('multiple undo/redo maintain LIFO order', () {
      manager.pushDelta(_makeDelta(CanvasDeltaType.strokeAdded, id: NodeId('first')));
      manager.pushDelta(_makeDelta(CanvasDeltaType.shapeAdded, id: NodeId('second')));
      manager.pushDelta(_makeDelta(CanvasDeltaType.textAdded, id: NodeId('third')));

      expect(manager.undo()!.id, 'third');
      expect(manager.undo()!.id, 'second');
      expect(manager.undo()!.id, 'first');

      expect(manager.redo()!.id, 'first');
      expect(manager.redo()!.id, 'second');
      expect(manager.redo()!.id, 'third');
    });
  });

  group('UndoRedoManager — batching', () {
    test('beginBatch/endBatch pushes deltas contiguously to undo stack', () {
      manager.beginBatch();
      manager.pushDelta(_makeDelta(CanvasDeltaType.strokeAdded, id: NodeId('b1')));
      manager.pushDelta(_makeDelta(CanvasDeltaType.strokeAdded, id: NodeId('b2')));
      manager.pushDelta(_makeDelta(CanvasDeltaType.strokeAdded, id: NodeId('b3')));
      manager.endBatch();

      // Each batched delta is pushed individually to the stack
      expect(manager.canUndo, isTrue);
      expect(manager.undo()!.id, 'b3');
      expect(manager.undo()!.id, 'b2');
      expect(manager.undo()!.id, 'b1');
      expect(manager.canUndo, isFalse);
    });

    test('empty batch pushes nothing', () {
      manager.beginBatch();
      manager.endBatch();

      expect(manager.canUndo, isFalse);
    });

    test('label getters return delta type names', () {
      manager.pushDelta(_makeDelta(CanvasDeltaType.strokeAdded));
      expect(manager.undoLabel, isNotNull);
    });
  });

  group('UndoRedoManager — stack limit', () {
    test('respects max stack size', () {
      // Push more than the limit (default 100)
      for (int i = 0; i < 120; i++) {
        manager.pushDelta(
          _makeDelta(CanvasDeltaType.strokeAdded, id: NodeId('delta-$i')),
        );
      }

      // Should not have more than 100 items on the undo stack
      int undoCount = 0;
      while (manager.canUndo) {
        manager.undo();
        undoCount++;
      }
      expect(undoCount, lessThanOrEqualTo(100));
    });
  });

  group('UndoRedoManager — clear', () {
    test('clear empties both stacks', () {
      manager.pushDelta(_makeDelta(CanvasDeltaType.strokeAdded));
      manager.pushDelta(_makeDelta(CanvasDeltaType.shapeAdded));
      manager.undo();

      manager.clear();

      expect(manager.canUndo, isFalse);
      expect(manager.canRedo, isFalse);
    });
  });
}
