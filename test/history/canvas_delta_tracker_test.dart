import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/history/canvas_delta_tracker.dart';
import 'package:nebula_engine/src/core/models/canvas_layer.dart';
import 'package:nebula_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:nebula_engine/src/core/models/shape_type.dart';
import 'dart:ui';

import '../helpers/test_helpers.dart';

void main() {
  late CanvasDeltaTracker tracker;

  setUp(() {
    tracker = CanvasDeltaTracker.instance;
    tracker.resetForTesting();
  });

  tearDown(() {
    tracker.resetForTesting();
  });

  group('CanvasDeltaTracker — initialization', () {
    test('starts with no pending deltas', () {
      expect(tracker.deltaCount, 0);
      expect(tracker.hasPendingDeltas, isFalse);
    });

    test('initForCanvas sets canvas ID', () {
      tracker.initForCanvas('canvas-1');
      expect(tracker.currentCanvasId, 'canvas-1');
    });

    test('initForCanvas clears deltas when switching canvas', () {
      tracker.initForCanvas('canvas-1');
      tracker.recordStrokeAdded('layer-1', testStroke());
      expect(tracker.deltaCount, 1);

      tracker.initForCanvas('canvas-2');
      expect(tracker.deltaCount, 0);
      expect(tracker.currentCanvasId, 'canvas-2');
    });

    test('initForCanvas preserves deltas for same canvas', () {
      tracker.initForCanvas('canvas-1');
      tracker.recordStrokeAdded('layer-1', testStroke());

      tracker.initForCanvas('canvas-1');
      expect(tracker.deltaCount, 1);
    });
  });

  group('CanvasDeltaTracker — record operations', () {
    test('recordStrokeAdded creates pending delta', () {
      tracker.recordStrokeAdded('layer-1', testStroke());
      expect(tracker.deltaCount, 1);
      expect(tracker.hasPendingDeltas, isTrue);

      final deltas = tracker.peekDeltas();
      expect(deltas.first.type, CanvasDeltaType.strokeAdded);
      expect(deltas.first.layerId, 'layer-1');
    });

    test('recordStrokeRemoved creates pending delta', () {
      tracker.recordStrokeRemoved('layer-1', 'stroke-1');
      expect(tracker.deltaCount, 1);

      final deltas = tracker.peekDeltas();
      expect(deltas.first.type, CanvasDeltaType.strokeRemoved);
      expect(deltas.first.elementId, 'stroke-1');
    });

    test('recordShapeAdded creates pending delta', () {
      tracker.recordShapeAdded('layer-1', testShape());
      expect(tracker.deltaCount, 1);
      expect(tracker.peekDeltas().first.type, CanvasDeltaType.shapeAdded);
    });

    test('recordShapeRemoved creates pending delta', () {
      tracker.recordShapeRemoved('layer-1', 'shape-1');
      expect(tracker.deltaCount, 1);
      expect(tracker.peekDeltas().first.type, CanvasDeltaType.shapeRemoved);
    });

    test('recordLayerModified creates delta with previous values', () {
      tracker.recordLayerModified(
        'layer-1',
        {'opacity': 0.5},
        previousValues: {'opacity': 1.0},
      );
      expect(tracker.deltaCount, 1);

      final delta = tracker.peekDeltas().first;
      expect(delta.type, CanvasDeltaType.layerModified);
      expect(delta.elementData!['opacity'], 0.5);
      expect(delta.previousData!['opacity'], 1.0);
    });

    test('recordLayerAdded creates pending delta', () {
      final layer = CanvasLayer(id: 'new-layer', name: 'Test Layer');
      tracker.recordLayerAdded(layer);
      expect(tracker.deltaCount, 1);
      expect(tracker.peekDeltas().first.type, CanvasDeltaType.layerAdded);
    });

    test('recordLayerRemoved creates pending delta', () {
      tracker.recordLayerRemoved('layer-1');
      expect(tracker.deltaCount, 1);
      expect(tracker.peekDeltas().first.type, CanvasDeltaType.layerRemoved);
    });

    test('multiple records accumulate deltas', () {
      tracker.recordStrokeAdded('l', testStroke(id: 's1'));
      tracker.recordStrokeAdded('l', testStroke(id: 's2'));
      tracker.recordStrokeRemoved('l', 's1');
      expect(tracker.deltaCount, 3);
    });
  });

  group('CanvasDeltaTracker — consume deltas', () {
    test('peekDeltas returns unmodifiable copy', () {
      tracker.recordStrokeAdded('l', testStroke());
      final peeked = tracker.peekDeltas();
      expect(peeked.length, 1);
      expect(() => (peeked as List).add(null), throwsA(anything));
    });

    test('removeDeltas removes only the first N', () {
      tracker.recordStrokeAdded('l', testStroke(id: 's1'));
      tracker.recordStrokeAdded('l', testStroke(id: 's2'));
      tracker.recordStrokeAdded('l', testStroke(id: 's3'));

      tracker.removeDeltas(count: 2);
      expect(tracker.deltaCount, 1);
      expect(tracker.peekDeltas().first.elementId, 's3');
    });

    test('removeDeltas with invalid count does nothing', () {
      tracker.recordStrokeAdded('l', testStroke());
      tracker.removeDeltas(count: 0);
      expect(tracker.deltaCount, 1);

      tracker.removeDeltas(count: 5);
      expect(tracker.deltaCount, 1);
    });

    test('markCheckpointCompleted clears all deltas', () {
      tracker.recordStrokeAdded('l', testStroke(id: 's1'));
      tracker.recordStrokeAdded('l', testStroke(id: 's2'));
      tracker.markCheckpointCompleted();

      expect(tracker.deltaCount, 0);
      expect(tracker.hasPendingDeltas, isFalse);
    });
  });

  group('CanvasDeltaTracker — checkpoint threshold', () {
    test('needsFullCheckpoint false when under threshold', () {
      tracker.recordStrokeAdded('l', testStroke());
      expect(tracker.needsFullCheckpoint, isFalse);
    });

    test('needsFullCheckpoint true at threshold', () {
      for (int i = 0; i < CanvasDeltaTracker.checkpointThreshold; i++) {
        tracker.recordStrokeAdded('l', testStroke(id: 'stroke-$i'));
      }
      expect(tracker.needsFullCheckpoint, isTrue);
    });
  });

  group('CanvasDeltaTracker — serialization', () {
    test('CanvasDelta roundtrip via JSON', () {
      final original = CanvasDelta(
        id: 'delta-1',
        type: CanvasDeltaType.strokeAdded,
        layerId: 'layer-1',
        pageIndex: 2,
        timestamp: DateTime(2025, 1, 1),
        elementData: {'color': '#FF0000', 'width': 2.5},
        elementId: 'stroke-1',
        previousData: {'color': '#00FF00'},
      );

      final json = original.toJson();
      final restored = CanvasDelta.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.type, original.type);
      expect(restored.layerId, original.layerId);
      expect(restored.pageIndex, original.pageIndex);
      expect(restored.elementId, original.elementId);
      expect(restored.elementData!['color'], '#FF0000');
      expect(restored.previousData!['color'], '#00FF00');
    });

    test('serializeDeltasToJsonl produces one line per delta', () {
      tracker.recordStrokeAdded('l', testStroke(id: 's1'));
      tracker.recordStrokeAdded('l', testStroke(id: 's2'));

      final jsonl = tracker.serializeDeltasToJsonl();
      final lines =
          jsonl.split('\n').where((l) => l.trim().isNotEmpty).toList();
      expect(lines.length, 2);
    });

    test('deserializeDeltasFromJsonl restores deltas', () {
      tracker.recordStrokeAdded('l', testStroke(id: 's1'));
      tracker.recordShapeAdded('l', testShape(id: 'sh1'));

      final jsonl = tracker.serializeDeltasToJsonl();
      final restored = CanvasDeltaTracker.deserializeDeltasFromJsonl(jsonl);

      expect(restored.length, 2);
      expect(restored[0].type, CanvasDeltaType.strokeAdded);
      expect(restored[1].type, CanvasDeltaType.shapeAdded);
    });

    test('empty JSONL returns empty list', () {
      final restored = CanvasDeltaTracker.deserializeDeltasFromJsonl('');
      expect(restored, isEmpty);
    });
  });

  group('CanvasDeltaTracker — applyDeltas', () {
    test('strokeAdded adds stroke to layer', () {
      final layer = CanvasLayer(id: 'l1', name: 'Layer 1');
      final stroke = testStroke(id: 's1');

      final delta = CanvasDelta(
        id: 'd1',
        type: CanvasDeltaType.strokeAdded,
        layerId: 'l1',
        timestamp: DateTime.now(),
        elementData: stroke.toJson(),
        elementId: 's1',
      );

      final result = CanvasDeltaTracker.applyDeltas([layer], [delta]);
      expect(result.first.strokes.length, 1);
      expect(result.first.strokes.first.id, 's1');
    });

    test('strokeRemoved removes stroke from layer', () {
      final stroke = testStroke(id: 's1');
      final layer = CanvasLayer(id: 'l1', name: 'Layer 1', strokes: [stroke]);

      final delta = CanvasDelta(
        id: 'd1',
        type: CanvasDeltaType.strokeRemoved,
        layerId: 'l1',
        timestamp: DateTime.now(),
        elementId: 's1',
      );

      final result = CanvasDeltaTracker.applyDeltas([layer], [delta]);
      expect(result.first.strokes, isEmpty);
    });

    test('layerModified updates layer properties', () {
      final layer = CanvasLayer(id: 'l1', name: 'Old', opacity: 1.0);

      final delta = CanvasDelta(
        id: 'd1',
        type: CanvasDeltaType.layerModified,
        layerId: 'l1',
        timestamp: DateTime.now(),
        elementData: {'name': 'New', 'opacity': 0.5},
      );

      final result = CanvasDeltaTracker.applyDeltas([layer], [delta]);
      expect(result.first.name, 'New');
      expect(result.first.opacity, 0.5);
    });

    test('layerAdded creates new layer', () {
      final newLayer = CanvasLayer(id: 'l2', name: 'Added');

      final delta = CanvasDelta(
        id: 'd1',
        type: CanvasDeltaType.layerAdded,
        layerId: 'l2',
        timestamp: DateTime.now(),
        elementData: newLayer.toJson(),
      );

      final result = CanvasDeltaTracker.applyDeltas([], [delta]);
      expect(result.length, 1);
      expect(result.first.id, 'l2');
    });

    test('layerRemoved removes layer', () {
      final layer = CanvasLayer(id: 'l1', name: 'Layer 1');

      final delta = CanvasDelta(
        id: 'd1',
        type: CanvasDeltaType.layerRemoved,
        layerId: 'l1',
        timestamp: DateTime.now(),
      );

      final result = CanvasDeltaTracker.applyDeltas([layer], [delta]);
      expect(result, isEmpty);
    });

    test('layerCleared removes all elements from layer', () {
      final layer = CanvasLayer(
        id: 'l1',
        name: 'Layer 1',
        strokes: [testStroke()],
        shapes: [testShape()],
      );

      final delta = CanvasDelta(
        id: 'd1',
        type: CanvasDeltaType.layerCleared,
        layerId: 'l1',
        timestamp: DateTime.now(),
      );

      final result = CanvasDeltaTracker.applyDeltas([layer], [delta]);
      expect(result.first.strokes, isEmpty);
      expect(result.first.shapes, isEmpty);
    });

    test('delta for missing layer auto-creates it', () {
      final stroke = testStroke(id: 's1');

      final delta = CanvasDelta(
        id: 'd1',
        type: CanvasDeltaType.strokeAdded,
        layerId: 'auto-created',
        timestamp: DateTime.now(),
        elementData: stroke.toJson(),
        elementId: 's1',
      );

      final result = CanvasDeltaTracker.applyDeltas([], [delta]);
      expect(result.length, 1);
      expect(result.first.id, 'auto-created');
      expect(result.first.strokes.length, 1);
    });

    test('preserves original layer order', () {
      final l1 = CanvasLayer(id: 'l1', name: 'First');
      final l2 = CanvasLayer(id: 'l2', name: 'Second');

      final delta = CanvasDelta(
        id: 'd1',
        type: CanvasDeltaType.layerModified,
        layerId: 'l2',
        timestamp: DateTime.now(),
        elementData: {'name': 'Modified'},
      );

      final result = CanvasDeltaTracker.applyDeltas([l1, l2], [delta]);
      expect(result[0].id, 'l1');
      expect(result[1].id, 'l2');
      expect(result[1].name, 'Modified');
    });
  });

  group('CanvasDeltaTracker — reset', () {
    test('reset clears everything', () {
      tracker.initForCanvas('c1');
      tracker.recordStrokeAdded('l', testStroke());

      tracker.reset();
      expect(tracker.deltaCount, 0);
      expect(tracker.currentCanvasId, isNull);
    });
  });
}
