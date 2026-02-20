import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/models/digital_text_element.dart';
import 'package:nebula_engine/src/layers/layer_controller.dart';
import 'package:nebula_engine/src/layers/adapters/infinite_canvas_adapter.dart';
import 'package:nebula_engine/src/tools/base/tool_context.dart';
import 'package:nebula_engine/src/tools/text/digital_text_tool.dart';

void main() {
  late DigitalTextTool tool;
  late LayerController layerController;
  late List<DigitalTextElement> elements;
  late List<DigitalTextElement> updatedElements;
  late int operationCompleteCount;

  DigitalTextElement _makeElement({
    String id = 'e1',
    String text = 'Hello',
    Offset position = const Offset(100, 100),
    double fontSize = 24.0,
    double scale = 1.0,
  }) {
    return DigitalTextElement(
      id: id,
      text: text,
      position: position,
      color: Colors.black,
      fontSize: fontSize,
      scale: scale,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  ToolContext _makeContext() {
    final adapter = InfiniteCanvasAdapter(
      canvasId: 'test-canvas',
      onOperationComplete: () => operationCompleteCount++,
      onGetTextElements: () => elements,
      onUpdateTextElement: (e) {
        final idx = updatedElements.indexWhere((u) => u.id == e.id);
        if (idx != -1) {
          updatedElements[idx] = e;
        } else {
          updatedElements.add(e);
        }
        // Also sync in the live list
        final liveIdx = elements.indexWhere((u) => u.id == e.id);
        if (liveIdx != -1) elements[liveIdx] = e;
      },
      onRemoveTextElement: (id) {
        elements.removeWhere((e) => e.id == id);
      },
    );

    return ToolContext(
      adapter: adapter,
      layerController: layerController,
      scale: 1.0,
      viewOffset: Offset.zero,
      viewportSize: const Size(800, 600),
      settings: const ToolSettings(),
    );
  }

  PointerDownEvent _downAt(Offset pos) {
    return PointerDownEvent(position: pos);
  }

  PointerMoveEvent _moveAt(Offset pos) {
    return PointerMoveEvent(position: pos);
  }

  PointerUpEvent _upAt(Offset pos) {
    return PointerUpEvent(position: pos);
  }

  setUp(() {
    tool = DigitalTextTool();
    layerController = LayerController();
    elements = [];
    updatedElements = [];
    operationCompleteCount = 0;
  });

  group('DigitalTextTool.onPointerDown', () {
    test('hit-test selects element when tapped on text', () {
      final element = _makeElement(position: const Offset(100, 100));
      elements.add(element);
      final ctx = _makeContext();

      // Tap inside the text bounding box
      final bounds = element.getBounds();
      final center = bounds.center;
      tool.onPointerDown(ctx, _downAt(center));

      expect(tool.hasSelection, isTrue);
      expect(tool.selectedElement?.id, 'e1');
      expect(tool.isDragging, isTrue);
    });

    test('miss deselects when tapping empty area', () {
      final element = _makeElement(position: const Offset(100, 100));
      elements.add(element);
      final ctx = _makeContext();

      // First select
      tool.selectElement(element);
      expect(tool.hasSelection, isTrue);

      // Tap far away
      tool.onPointerDown(ctx, _downAt(const Offset(5000, 5000)));

      expect(tool.hasSelection, isFalse);
    });

    test('hit-test returns topmost element when overlapping', () {
      final bottom = _makeElement(
        id: NodeId('bottom'),
        position: const Offset(100, 100),
      );
      final top = _makeElement(id: NodeId('top'), position: const Offset(100, 100));
      elements.addAll([bottom, top]);
      final ctx = _makeContext();

      final bounds = top.getBounds();
      tool.onPointerDown(ctx, _downAt(bounds.center));

      // Should select the topmost (last in list)
      expect(tool.selectedElement?.id, 'top');
    });
  });

  group('DigitalTextTool.onPointerMove', () {
    test('drag updates element position via ToolContext', () {
      final element = _makeElement(position: const Offset(100, 100));
      elements.add(element);
      final ctx = _makeContext();

      // Select and start drag
      final bounds = element.getBounds();
      tool.onPointerDown(ctx, _downAt(bounds.center));
      expect(tool.isDragging, isTrue);

      // Move 50px right
      tool.onPointerMove(ctx, _moveAt(bounds.center + const Offset(50, 0)));

      // Should have called updateTextElement
      expect(updatedElements.isNotEmpty, isTrue);

      // Element position should have shifted
      final movedElement = updatedElements.last;
      expect(movedElement.position.dx, greaterThan(100));
    });
  });

  group('DigitalTextTool.onPointerUp', () {
    test('endDrag notifies operation complete', () {
      final element = _makeElement(position: const Offset(100, 100));
      elements.add(element);
      final ctx = _makeContext();

      // Full drag cycle: down → move → up
      final bounds = element.getBounds();
      tool.onPointerDown(ctx, _downAt(bounds.center));
      tool.onPointerMove(ctx, _moveAt(bounds.center + const Offset(50, 0)));
      tool.onPointerUp(ctx, _upAt(bounds.center + const Offset(50, 0)));

      expect(tool.isDragging, isFalse);
      expect(operationCompleteCount, 1);
    });

    test('no-op when no drag/resize is active', () {
      final ctx = _makeContext();
      tool.onPointerUp(ctx, _upAt(const Offset(100, 100)));

      // Should not crash or notify
      expect(operationCompleteCount, 0);
    });
  });

  group('DigitalTextTool.onPointerCancel', () {
    test('cancels active drag cleanly', () {
      final element = _makeElement(position: const Offset(100, 100));
      elements.add(element);
      final ctx = _makeContext();

      // Start drag
      final bounds = element.getBounds();
      tool.onPointerDown(ctx, _downAt(bounds.center));
      expect(tool.isDragging, isTrue);

      // Cancel
      tool.onPointerCancel(ctx);
      expect(tool.isDragging, isFalse);
    });
  });

  group('DigitalTextTool lifecycle', () {
    test('onDeactivate clears selection', () {
      final element = _makeElement();
      elements.add(element);
      final ctx = _makeContext();

      tool.selectElement(element);
      expect(tool.hasSelection, isTrue);

      tool.onDeactivate(ctx);
      expect(tool.hasSelection, isFalse);
    });

    test('identity properties are correct', () {
      expect(tool.toolId, 'digital_text');
      expect(tool.label, 'Text');
      expect(tool.icon, Icons.text_fields);
      expect(tool.hasOverlay, isTrue);
      expect(tool.supportsUndo, isTrue);
      expect(tool.requiresExclusiveGesture, isFalse);
    });
  });
}
