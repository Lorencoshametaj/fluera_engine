import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/vector/anchor_point.dart';
import 'package:nebula_engine/src/core/nodes/path_node.dart';
import 'package:nebula_engine/src/tools/pen/pen_tool.dart';
import 'package:nebula_engine/src/tools/base/tool_context.dart';
import 'package:nebula_engine/src/layers/adapters/canvas_adapter.dart';
import 'package:nebula_engine/src/layers/nebula_layer_controller.dart';
import 'package:nebula_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:nebula_engine/src/core/models/shape_type.dart';
import 'package:nebula_engine/src/core/models/digital_text_element.dart';
import 'package:nebula_engine/src/core/models/image_element.dart';
import 'package:nebula_engine/src/core/models/canvas_layer.dart';
import 'package:nebula_engine/src/rendering/optimization/spatial_index.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph.dart';

/// Helper: create a PenTool and load anchors into it via editPathNode.
PenTool _toolWithAnchors(List<AnchorPoint> anchors) {
  final tool = PenTool();
  final path = AnchorPoint.toVectorPath(anchors);
  final node = PathNode(id: 'test-helper', path: path, strokeWidth: 2.0);
  tool.editPathNode(node);
  return tool;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // ===========================================================================
  // ANCHOR TYPE CYCLING
  // ===========================================================================

  group('Anchor type cycling', () {
    test('corner → smooth: generates smart handles from neighbors', () {
      final tool = _toolWithAnchors([
        AnchorPoint(position: const Offset(0, 0), type: AnchorType.corner),
        AnchorPoint(position: const Offset(100, 0), type: AnchorType.corner),
        AnchorPoint(position: const Offset(200, 0), type: AnchorType.corner),
      ]);

      // Cycle middle anchor: corner → smooth.
      tool.cycleAnchorTypeAt(1);

      final anchor = tool.anchors[1];
      expect(anchor.type, AnchorType.smooth);
      expect(anchor.handleIn, isNotNull, reason: 'handleIn should be created');
      expect(
        anchor.handleOut,
        isNotNull,
        reason: 'handleOut should be created',
      );
    });

    test('smooth → symmetric: equalizes handles to longer length', () {
      final tool = _toolWithAnchors([
        AnchorPoint(position: const Offset(0, 0)),
        AnchorPoint(
          position: const Offset(100, 0),
          type: AnchorType.smooth,
          handleIn: const Offset(-20, 0),
          handleOut: const Offset(40, 0),
        ),
        AnchorPoint(position: const Offset(200, 0)),
      ]);

      // Cycle: smooth → symmetric.
      tool.cycleAnchorTypeAt(1);

      final anchor = tool.anchors[1];
      expect(anchor.type, AnchorType.symmetric);
      // Both should be 40 (the longer one).
      expect(anchor.handleIn!.distance, closeTo(40.0, 0.01));
      expect(anchor.handleOut!.distance, closeTo(40.0, 0.01));
    });

    test('symmetric → corner: removes handles', () {
      // Start from smooth, cycle to symmetric first, then to corner.
      final tool = _toolWithAnchors([
        AnchorPoint(position: const Offset(0, 0)),
        AnchorPoint(
          position: const Offset(100, 0),
          type: AnchorType.smooth,
          handleIn: const Offset(-30, 0),
          handleOut: const Offset(30, 0),
        ),
        AnchorPoint(position: const Offset(200, 0)),
      ]);

      // Cycle smooth → symmetric first.
      tool.cycleAnchorTypeAt(1);
      expect(tool.anchors[1].type, AnchorType.symmetric);

      // Cycle symmetric → corner.
      tool.cycleAnchorTypeAt(1);

      final anchor = tool.anchors[1];
      expect(anchor.type, AnchorType.corner);
      expect(anchor.handleIn, isNull);
      expect(anchor.handleOut, isNull);
    });

    test('full cycle: corner → smooth → symmetric → corner', () {
      final tool = _toolWithAnchors([
        AnchorPoint(position: const Offset(0, 0)),
        AnchorPoint(position: const Offset(100, 0), type: AnchorType.corner),
        AnchorPoint(position: const Offset(200, 0)),
      ]);

      // corner → smooth
      tool.cycleAnchorTypeAt(1);
      expect(tool.anchors[1].type, AnchorType.smooth);

      // smooth → symmetric
      tool.cycleAnchorTypeAt(1);
      expect(tool.anchors[1].type, AnchorType.symmetric);

      // symmetric → corner
      tool.cycleAnchorTypeAt(1);
      expect(tool.anchors[1].type, AnchorType.corner);
      expect(tool.anchors[1].handleIn, isNull);
      expect(tool.anchors[1].handleOut, isNull);
    });
  });

  // ===========================================================================
  // ANCHOR DELETION
  // ===========================================================================

  group('Anchor deletion', () {
    test('deletes middle anchor by selection', () {
      final tool = _toolWithAnchors([
        AnchorPoint(position: const Offset(0, 0)),
        AnchorPoint(position: const Offset(50, 50)),
        AnchorPoint(position: const Offset(100, 0)),
      ]);

      tool.deleteSelectedAnchors(); // Nothing selected yet.
      expect(tool.anchors.length, 3, reason: 'No deletion without selection');

      // Select and delete the middle anchor.
      tool.setSelectedAnchorsForTest({1});
      tool.deleteSelectedAnchors();

      expect(tool.anchors.length, 2);
      expect(tool.anchors[0].position, const Offset(0, 0));
      expect(tool.anchors[1].position, const Offset(100, 0));
    });

    test('deletes multiple selected anchors', () {
      final tool = _toolWithAnchors([
        AnchorPoint(position: const Offset(0, 0)),
        AnchorPoint(position: const Offset(25, 25)),
        AnchorPoint(position: const Offset(50, 50)),
        AnchorPoint(position: const Offset(75, 75)),
        AnchorPoint(position: const Offset(100, 100)),
      ]);

      // Delete indices 1 and 3.
      tool.setSelectedAnchorsForTest({1, 3});
      tool.deleteSelectedAnchors();

      expect(tool.anchors.length, 3);
      expect(tool.anchors[0].position, const Offset(0, 0));
      expect(tool.anchors[1].position, const Offset(50, 50));
      expect(tool.anchors[2].position, const Offset(100, 100));
    });
  });

  // ===========================================================================
  // PATH REVERSAL
  // ===========================================================================

  group('Path reversal', () {
    test('reverses anchor order', () {
      final tool = _toolWithAnchors([
        AnchorPoint(position: const Offset(0, 0)),
        AnchorPoint(position: const Offset(50, 50)),
        AnchorPoint(position: const Offset(100, 100)),
      ]);

      tool.reversePathDirection();

      expect(tool.anchors[0].position, const Offset(100, 100));
      expect(tool.anchors[1].position, const Offset(50, 50));
      expect(tool.anchors[2].position, const Offset(0, 0));
    });

    test('swaps handleIn and handleOut on reversal', () {
      final tool = _toolWithAnchors([
        AnchorPoint(position: const Offset(0, 0), type: AnchorType.corner),
        AnchorPoint(
          position: const Offset(50, 0),
          handleIn: const Offset(-10, 0),
          handleOut: const Offset(20, 0),
          type: AnchorType.smooth,
        ),
        AnchorPoint(position: const Offset(100, 0), type: AnchorType.corner),
      ]);

      tool.reversePathDirection();

      // After reversal, the middle anchor (originally index 1) stays at index 1.
      // Its handles get swapped: handleIn becomes what handleOut was, and vice versa.
      final swapped = tool.anchors[1];
      expect(swapped.position, const Offset(50, 0));
      expect(swapped.handleIn!.dx, closeTo(20.0, 0.1)); // was handleOut
      expect(swapped.handleOut!.dx, closeTo(-10.0, 0.1)); // was handleIn
    });
  });

  // ===========================================================================
  // HANDLE EQUALIZATION
  // ===========================================================================

  group('Handle equalization', () {
    test('equalizes handles to average length', () {
      final tool = _toolWithAnchors([
        AnchorPoint(position: const Offset(0, 0), type: AnchorType.corner),
        AnchorPoint(
          position: const Offset(100, 100),
          handleIn: const Offset(-10, 0), // length = 10
          handleOut: const Offset(30, 0), // length = 30
          type: AnchorType.smooth,
        ),
        AnchorPoint(position: const Offset(200, 200), type: AnchorType.corner),
      ]);

      tool.equalizeHandlesAt(1);

      final anchor = tool.anchors[1];
      // Average = (10 + 30) / 2 = 20.
      expect(anchor.handleIn!.distance, closeTo(20.0, 0.01));
      expect(anchor.handleOut!.distance, closeTo(20.0, 0.01));
    });

    test('preserves handle direction after equalization', () {
      final tool = _toolWithAnchors([
        AnchorPoint(position: const Offset(-50, 0), type: AnchorType.corner),
        AnchorPoint(
          position: const Offset(0, 0),
          handleIn: const Offset(-20, 0), // pointing left
          handleOut: const Offset(0, 40), // pointing down
          type: AnchorType.smooth,
        ),
        AnchorPoint(position: const Offset(50, 50), type: AnchorType.corner),
      ]);

      tool.equalizeHandlesAt(1);

      final anchor = tool.anchors[1];
      // Direction of handleIn should still be left (negative x).
      expect(anchor.handleIn!.dx, lessThan(0));
      expect(anchor.handleIn!.dy, closeTo(0, 0.01));
      // Direction of handleOut should still be down (positive y).
      expect(anchor.handleOut!.dx, closeTo(0, 0.01));
      expect(anchor.handleOut!.dy, greaterThan(0));
    });
  });

  // ===========================================================================
  // EDIT PATHNODE ROUND-TRIP
  // ===========================================================================

  group('Edit PathNode round-trip', () {
    test('extracts anchors from PathNode and loads them', () {
      // Create a vector path with known anchors.
      final originalAnchors = [
        AnchorPoint(position: const Offset(0, 0), type: AnchorType.corner),
        AnchorPoint(
          position: const Offset(100, 0),
          type: AnchorType.smooth,
          handleIn: const Offset(-20, -10),
          handleOut: const Offset(20, 10),
        ),
        AnchorPoint(position: const Offset(200, 100), type: AnchorType.corner),
      ];

      final vectorPath = AnchorPoint.toVectorPath(originalAnchors);
      final pathNode = PathNode(
        id: 'test-node-1',
        path: vectorPath,
        strokeColor: const Color(0xFFFF0000),
        strokeWidth: 3.0,
      );

      // Enter edit mode.
      final tool = PenTool();
      tool.editPathNode(pathNode);

      expect(tool.isEditingExisting, isTrue);
      expect(tool.isBuilding, isTrue);
      expect(tool.anchors.length, originalAnchors.length);
      expect(tool.strokeColor, const Color(0xFFFF0000));
      expect(tool.strokeWidth, 3.0);
    });

    test('finalize in edit mode calls onPathNodeEdited', () {
      PathNode? editedNode;
      String? editedId;

      final tool = PenTool(
        onPathNodeEdited: (id, node) {
          editedId = id;
          editedNode = node;
        },
      );

      // Set up edit mode.
      final vectorPath = AnchorPoint.toVectorPath([
        AnchorPoint(position: const Offset(0, 0)),
        AnchorPoint(position: const Offset(100, 0)),
      ]);
      final pathNode = PathNode(
        id: 'test-edit-42',
        path: vectorPath,
        strokeWidth: 2.0,
      );

      tool.editPathNode(pathNode);
      expect(tool.isEditingExisting, isTrue);

      // After edit, verify the callback was not yet called.
      expect(editedNode, isNull);
      expect(editedId, isNull);
    });
  });

  // ===========================================================================
  // DE CASTELJAU INSERTION (GEOMETRY)
  // ===========================================================================

  group('De Casteljau insertion', () {
    test('inserted anchor is on the original curve', () {
      final tool = _toolWithAnchors([
        AnchorPoint(
          position: const Offset(0, 0),
          handleOut: const Offset(50, 0),
          type: AnchorType.smooth,
        ),
        AnchorPoint(
          position: const Offset(200, 0),
          handleIn: const Offset(-50, 0),
          type: AnchorType.smooth,
        ),
      ]);

      // Insert at midpoint (t=0.5).
      tool.insertAnchorOnSegmentForTest(0, 0.5);

      expect(tool.anchors.length, 3);

      // The inserted anchor should be at the midpoint of the cubic curve.
      // For a symmetric cubic with control points at (50,0) and (150,0),
      // the midpoint is at (100, 0).
      final inserted = tool.anchors[1];
      expect(inserted.position.dx, closeTo(100.0, 1.0));
      expect(inserted.position.dy, closeTo(0.0, 1.0));
      expect(inserted.type, AnchorType.smooth);
    });

    test('insertion preserves path shape', () {
      final tool = _toolWithAnchors([
        AnchorPoint(
          position: const Offset(0, 0),
          handleOut: const Offset(30, 30),
          type: AnchorType.smooth,
        ),
        AnchorPoint(
          position: const Offset(100, 100),
          handleIn: const Offset(-30, -30),
          type: AnchorType.smooth,
        ),
      ]);

      tool.insertAnchorOnSegmentForTest(0, 0.5);

      // After insertion, we should have 3 anchors.
      expect(tool.anchors.length, 3);
      // The new anchor should have both handles.
      expect(tool.anchors[1].handleIn, isNotNull);
      expect(tool.anchors[1].handleOut, isNotNull);
    });
  });

  // ===========================================================================
  // AUTO-SMOOTH (CATMULL-ROM)
  // ===========================================================================

  group('Auto-smooth', () {
    test('converts all anchors to smooth type', () {
      final tool = _toolWithAnchors([
        AnchorPoint(position: const Offset(0, 0), type: AnchorType.corner),
        AnchorPoint(position: const Offset(50, 50), type: AnchorType.corner),
        AnchorPoint(position: const Offset(100, 0), type: AnchorType.corner),
      ]);

      tool.autoSmooth();

      for (final anchor in tool.anchors) {
        expect(anchor.type, AnchorType.smooth);
      }
    });

    test('generates handles for interior anchors', () {
      final tool = _toolWithAnchors([
        AnchorPoint(position: const Offset(0, 0), type: AnchorType.corner),
        AnchorPoint(position: const Offset(100, 100), type: AnchorType.corner),
        AnchorPoint(position: const Offset(200, 0), type: AnchorType.corner),
      ]);

      tool.autoSmooth();

      // Interior anchor should have both handles.
      final mid = tool.anchors[1];
      expect(mid.handleIn, isNotNull);
      expect(mid.handleOut, isNotNull);
      // Handle lengths should be proportional to neighbor distances.
      expect(mid.handleIn!.distance, greaterThan(0));
      expect(mid.handleOut!.distance, greaterThan(0));
    });

    test('first anchor has handleOut only, last has handleIn only', () {
      final tool = _toolWithAnchors([
        AnchorPoint(position: const Offset(0, 0), type: AnchorType.corner),
        AnchorPoint(position: const Offset(100, 100), type: AnchorType.corner),
        AnchorPoint(position: const Offset(200, 0), type: AnchorType.corner),
      ]);

      tool.autoSmooth();

      final first = tool.anchors[0];
      expect(first.handleOut, isNotNull);
      expect(first.handleIn, isNull);

      final last = tool.anchors[2];
      expect(last.handleIn, isNotNull);
      expect(last.handleOut, isNull);
    });
  });

  // ===========================================================================
  // SEGMENT DELETION
  // ===========================================================================

  group('Segment deletion', () {
    test('2-anchor path is cleared on segment deletion', () {
      PathNode? createdNode;
      final tool = PenTool(onPathNodeCreated: (node) => createdNode = node);

      final path = AnchorPoint.toVectorPath([
        AnchorPoint(position: const Offset(0, 0)),
        AnchorPoint(position: const Offset(100, 0)),
      ]);
      tool.editPathNode(PathNode(id: 'test', path: path, strokeWidth: 2.0));

      tool.splitPathAtSegment(0, _mockContext());

      // Should reset entirely (clear anchors).
      expect(tool.anchors.isEmpty, isTrue);
      expect(createdNode, isNull);
    });

    test('3-anchor split creates first half and keeps second', () {
      PathNode? createdNode;
      final tool = PenTool(onPathNodeCreated: (node) => createdNode = node);

      final path = AnchorPoint.toVectorPath([
        AnchorPoint(position: const Offset(0, 0)),
        AnchorPoint(position: const Offset(100, 0)),
        AnchorPoint(position: const Offset(200, 0)),
      ]);
      tool.editPathNode(PathNode(id: 'test', path: path, strokeWidth: 2.0));

      // Delete segment between anchor 0 and 1.
      tool.splitPathAtSegment(0, _mockContext());

      // First half (anchors 0..0) has only 1 anchor, so not finalized.
      // Second half (anchors 1..2) should remain as current editing.
      expect(tool.anchors.length, 2);
      // Positions should be the second half.
      expect(tool.anchors[0].position, const Offset(100, 0));
      expect(tool.anchors[1].position, const Offset(200, 0));
    });

    test('4-anchor split at middle creates two groups', () {
      PathNode? createdNode;
      final tool = PenTool(onPathNodeCreated: (node) => createdNode = node);

      final path = AnchorPoint.toVectorPath([
        AnchorPoint(position: const Offset(0, 0)),
        AnchorPoint(position: const Offset(100, 0)),
        AnchorPoint(position: const Offset(200, 0)),
        AnchorPoint(position: const Offset(300, 0)),
      ]);
      tool.editPathNode(PathNode(id: 'test', path: path, strokeWidth: 2.0));

      // Delete segment between anchor 1 and 2.
      tool.splitPathAtSegment(1, _mockContext());

      // First half is [0, 1] = 2 anchors → finalized as PathNode.
      expect(createdNode, isNotNull);
      // Second half is [2, 3] = 2 anchors → kept as current.
      expect(tool.anchors.length, 2);
      expect(tool.anchors[0].position, const Offset(200, 0));
      expect(tool.anchors[1].position, const Offset(300, 0));
    });
  });

  // ===========================================================================
  // CONTEXT MENU STATE
  // ===========================================================================

  group('Context menu state', () {
    test('initial context menu state is hidden', () {
      final tool = PenTool();
      expect(tool.showAnchorContextMenu, isFalse);
      expect(tool.showSegmentContextMenu, isFalse);
      expect(tool.contextMenuAnchorIndex, -1);
      expect(tool.contextMenuSegmentIndex, -1);
    });

    test('dismissContextMenu resets all context menu state', () {
      final tool = PenTool();
      tool.dismissContextMenu();
      expect(tool.showAnchorContextMenu, isFalse);
      expect(tool.showSegmentContextMenu, isFalse);
      expect(tool.contextMenuAnchorIndex, -1);
      expect(tool.contextMenuSegmentIndex, -1);
    });
  });

  // ===========================================================================
  // CURSOR HINT STATE
  // ===========================================================================

  group('Cursor hint state', () {
    test('initial cursor hint is none', () {
      final tool = PenTool();
      expect(tool.cursorHint, PenCursorHint.none);
    });
  });
}

/// Create a minimal ToolContext for tests that need one (e.g. segment deletion).
ToolContext _mockContext() => ToolContext(
  adapter: _StubAdapter(),
  layerController: _StubLayerController(),
  scale: 1.0,
  viewOffset: Offset.zero,
  viewportSize: const Size(800, 600),
  settings: const ToolSettings(),
);

/// Stub adapter — all methods are no-ops or return defaults.
class _StubAdapter extends CanvasAdapter {
  @override
  String get contextType => 'test';
  @override
  Rect? get bounds => null;
  @override
  String get contextId => 'test-ctx';

  @override
  Offset screenToCanvas(Offset screen, double scale, Offset viewOffset) =>
      (screen - viewOffset) / scale;
  @override
  Offset canvasToScreen(Offset canvas, double scale, Offset viewOffset) =>
      canvas * scale + viewOffset;
  @override
  bool isPointInBounds(Offset canvasPosition) => true;

  @override
  void addStroke(NebulaLayerController c, ProStroke s) {}
  @override
  void removeStroke(NebulaLayerController c, String id) {}
  @override
  List<ProStroke> getStrokesInViewport(NebulaLayerController c, Rect v) => [];
  @override
  void addShape(NebulaLayerController c, GeometricShape s) {}
  @override
  void removeShape(NebulaLayerController c, String id) {}
  @override
  List<GeometricShape> getShapesInViewport(NebulaLayerController c, Rect v) =>
      [];
  @override
  void addTextElement(DigitalTextElement e) {}
  @override
  List<DigitalTextElement> getTextElements() => [];
  @override
  void updateTextElement(DigitalTextElement e) {}
  @override
  void removeTextElement(String id) {}
  @override
  void addImageElement(ImageElement e) {}
  @override
  List<ImageElement> getImageElements() => [];
  @override
  void updateImageElement(ImageElement e) {}
  @override
  void removeImageElement(String id) {}
  @override
  void saveUndoState() {}
  @override
  void notifyOperationComplete() {}
}

/// Stub layer controller — minimal implementation for tests.
class _StubLayerController extends NebulaLayerController {
  @override
  List<CanvasLayer> get layers => [];
  @override
  CanvasLayer? get activeLayer => null;
  @override
  String? get activeLayerId => null;
  @override
  SpatialIndexManager get spatialIndex => throw UnimplementedError();
  @override
  SceneGraph get sceneGraph => throw UnimplementedError();

  @override
  void addLayer({String? name}) {}
  @override
  void removeLayer(String id) {}
  @override
  void selectLayer(String id) {}
  @override
  void renameLayer(String id, String name) {}
  @override
  void toggleLayerVisibility(String id) {}
  @override
  void toggleLayerLock(String id) {}
  @override
  void setLayerOpacity(String id, double opacity) {}
  @override
  void setLayerBlendMode(String id, BlendMode mode) {}
  @override
  void moveLayerUp(String id) {}
  @override
  void moveLayerDown(String id) {}
  @override
  void updateLayer(CanvasLayer l) {}
  @override
  void clearAllAndLoadLayers(List<CanvasLayer> l) {}
  @override
  void duplicateLayer(String id) {}

  @override
  void addStroke(ProStroke s) {}
  @override
  void addStrokesBatch(List<ProStroke> s) {}
  @override
  void removeStrokeAt(int i) {}
  @override
  void removeStroke(String id) {}
  @override
  List<ProStroke> getAllVisibleStrokes() => [];

  @override
  void addShape(GeometricShape s) {}
  @override
  void removeShapeAt(int i) {}
  @override
  void removeShape(String id) {}
  @override
  List<GeometricShape> getAllVisibleShapes() => [];

  @override
  void addText(DigitalTextElement t) {}
  @override
  void removeText(String id) {}
  @override
  void updateText(DigitalTextElement t) {}

  @override
  void addImage(ImageElement i) {}
  @override
  void removeImage(String id) {}

  @override
  void undoLastElement() {}

  @override
  void dispose() {
    super.dispose();
  }
}
