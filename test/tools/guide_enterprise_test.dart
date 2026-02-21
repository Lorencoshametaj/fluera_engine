import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/history/command_history.dart';
import 'package:nebula_engine/src/history/guide_commands.dart';
import 'package:nebula_engine/src/tools/ruler/ruler_guide_system.dart';

void main() {
  // -----------------------------------------------------------------------
  // A. Guide Commands — CommandHistory integration
  // -----------------------------------------------------------------------
  group('Guide Commands', () {
    late RulerGuideSystem sys;
    late CommandHistory history;

    setUp(() {
      sys = RulerGuideSystem();
      history = CommandHistory();
    });

    test('AddGuideCommand adds guide and undo removes it', () {
      history.execute(
        AddGuideCommand(guideSystem: sys, position: 100, isHorizontal: true),
      );
      expect(sys.horizontalGuides, contains(100));

      history.undo();
      expect(sys.horizontalGuides, isEmpty);
    });

    test('AddGuideCommand vertical adds and undoes', () {
      history.execute(
        AddGuideCommand(
          guideSystem: sys,
          position: 200,
          isHorizontal: false,
          color: const Color(0xFFFF0000),
        ),
      );
      expect(sys.verticalGuides, contains(200));

      history.undo();
      expect(sys.verticalGuides, isEmpty);
    });

    test('RemoveGuideCommand removes and restores on undo', () {
      sys.addHorizontalGuide(50, color: const Color(0xFF00FF00));
      sys.setGuideLabel(true, 0, 'margin');
      expect(sys.horizontalGuides.length, 1);

      history.execute(
        RemoveGuideCommand(guideSystem: sys, isHorizontal: true, index: 0),
      );
      expect(sys.horizontalGuides, isEmpty);

      history.undo();
      expect(sys.horizontalGuides, contains(50));
      // Color and label restored
      expect(sys.horizontalColors[0], const Color(0xFF00FF00));
      expect(sys.getGuideLabel(true, 0), 'margin');
    });

    test('MoveGuideCommand moves and supports drag coalescing', () {
      sys.addHorizontalGuide(100);

      final cmd1 = MoveGuideCommand(
        guideSystem: sys,
        isHorizontal: true,
        index: 0,
        newPosition: 110,
      );
      history.execute(cmd1);
      expect(sys.horizontalGuides[0], 110);

      // Second move merges
      final cmd2 = MoveGuideCommand(
        guideSystem: sys,
        isHorizontal: true,
        index: 0,
        newPosition: 150,
      );
      history.execute(cmd2);
      expect(sys.horizontalGuides[0], 150);
      expect(history.undoCount, 1); // merged into one

      // Single undo restores original
      history.undo();
      expect(sys.horizontalGuides[0], 100);
    });

    test('SetGuidePropertyCommand.color sets and undoes', () {
      sys.addVerticalGuide(200);

      history.execute(
        SetGuidePropertyCommand.color(
          guideSystem: sys,
          isHorizontal: false,
          index: 0,
          newColor: const Color(0xFFABCDEF),
        ),
      );
      expect(sys.verticalColors[0], const Color(0xFFABCDEF));

      history.undo();
      expect(sys.verticalColors[0], isNull);
    });

    test('SetGuidePropertyCommand.locked toggles and undoes', () {
      sys.addHorizontalGuide(100);
      expect(sys.isLocked(true, 0), isFalse);

      history.execute(
        SetGuidePropertyCommand.locked(
          guideSystem: sys,
          isHorizontal: true,
          index: 0,
        ),
      );
      expect(sys.isLocked(true, 0), isTrue);

      history.undo();
      expect(sys.isLocked(true, 0), isFalse);
    });

    test('ClearAllGuidesCommand clears and undo restores', () {
      sys.addHorizontalGuide(10);
      sys.addHorizontalGuide(20);
      sys.addVerticalGuide(30);

      history.execute(ClearAllGuidesCommand(guideSystem: sys));
      expect(sys.horizontalGuides, isEmpty);
      expect(sys.verticalGuides, isEmpty);

      history.undo();
      expect(sys.horizontalGuides.length, 2);
      expect(sys.verticalGuides.length, 1);
    });

    test('AddAngularGuideCommand adds and undoes', () {
      history.execute(
        AddAngularGuideCommand(
          guideSystem: sys,
          origin: const Offset(100, 100),
          angleDeg: 45,
        ),
      );
      expect(sys.angularGuides.length, 1);

      history.undo();
      expect(sys.angularGuides, isEmpty);
    });

    test('redo re-applies command', () {
      history.execute(
        AddGuideCommand(guideSystem: sys, position: 75, isHorizontal: true),
      );
      history.undo();
      expect(sys.horizontalGuides, isEmpty);

      history.redo();
      expect(sys.horizontalGuides, contains(75));
    });
  });

  // -----------------------------------------------------------------------
  // B. Frame-Scoped Guides
  // -----------------------------------------------------------------------
  group('Frame-Scoped Guides', () {
    late RulerGuideSystem sys;

    setUp(() {
      sys = RulerGuideSystem();
    });

    test('addFrameGuide adds to frameGuides', () {
      final guide = CanvasGuide(
        position: 100,
        isHorizontal: true,
        frameId: 'frame-1',
      );
      sys.addFrameGuide(guide);
      expect(sys.frameGuides.length, 1);
      expect(sys.frameGuides.first.frameId, 'frame-1');
    });

    test('guidesForFrame filters by frameId', () {
      sys.addFrameGuide(
        CanvasGuide(position: 50, isHorizontal: true, frameId: 'frame-1'),
      );
      sys.addFrameGuide(
        CanvasGuide(position: 150, isHorizontal: false, frameId: 'frame-2'),
      );
      sys.addFrameGuide(
        CanvasGuide(position: 200, isHorizontal: true, frameId: 'frame-1'),
      );

      final f1 = sys.guidesForFrame('frame-1');
      expect(f1.length, 2);

      final f2 = sys.guidesForFrame('frame-2');
      expect(f2.length, 1);
    });

    test('removeFrameGuide removes by ID', () {
      final guide = CanvasGuide(
        position: 100,
        isHorizontal: true,
        frameId: 'frame-1',
      );
      sys.addFrameGuide(guide);
      expect(sys.frameGuides.length, 1);

      sys.removeFrameGuide(guide.id);
      expect(sys.frameGuides, isEmpty);
    });

    test('globalFrameGuides returns null-frameId guides', () {
      sys.addFrameGuide(
        CanvasGuide(position: 100, isHorizontal: true),
      ); // global
      sys.addFrameGuide(
        CanvasGuide(position: 200, isHorizontal: false, frameId: 'frame-1'),
      );

      expect(sys.globalFrameGuides.length, 1);
    });

    test('snapPoint snaps to frame guides', () {
      sys.addFrameGuide(CanvasGuide(position: 100, isHorizontal: true));
      sys.snapEnabled = true;

      // Close to 100 on Y axis
      final snapped = sys.snapPoint(const Offset(50, 103), 1.0);
      expect(snapped.dy, 100);
    });

    test('frame guides are serialized', () {
      sys.addFrameGuide(
        CanvasGuide(
          position: 100,
          isHorizontal: true,
          frameId: 'f1',
          label: 'header',
        ),
      );
      final json = sys.toJson();
      final sys2 = RulerGuideSystem();
      sys2.loadFromJson(json);

      expect(sys2.frameGuides.length, 1);
      expect(sys2.frameGuides.first.position, 100);
      expect(sys2.frameGuides.first.frameId, 'f1');
      expect(sys2.frameGuides.first.label, 'header');
    });

    test('frame guides included in snapshot undo/redo', () {
      sys.addFrameGuide(
        CanvasGuide(position: 100, isHorizontal: true, frameId: 'f1'),
      );
      sys.saveSnapshot();
      sys.frameGuides.clear();
      expect(sys.frameGuides, isEmpty);

      sys.undo();
      expect(sys.frameGuides.length, 1);
      expect(sys.frameGuides.first.position, 100);
    });

    test('onChanged fires for frame guide operations', () {
      int callCount = 0;
      sys.onChanged = () => callCount++;

      sys.addFrameGuide(CanvasGuide(position: 50, isHorizontal: true));
      expect(callCount, 1);

      sys.removeFrameGuide(sys.frameGuides.first.id);
      expect(callCount, 2);
    });
  });

  // -----------------------------------------------------------------------
  // B2. CanvasGuide model
  // -----------------------------------------------------------------------
  group('CanvasGuide', () {
    test('toJson/fromJson round trip', () {
      final guide = CanvasGuide(
        position: 200,
        isHorizontal: false,
        frameId: 'artboard-3',
        locked: true,
        color: const Color(0xFFFF0000),
        label: 'right margin',
      );
      final json = guide.toJson();
      final restored = CanvasGuide.fromJson(json);

      expect(restored.position, 200);
      expect(restored.isHorizontal, false);
      expect(restored.frameId, 'artboard-3');
      expect(restored.locked, true);
      expect(restored.color, const Color(0xFFFF0000));
      expect(restored.label, 'right margin');
    });

    test('copyWith creates independent copy', () {
      final guide = CanvasGuide(position: 100, isHorizontal: true);
      final copy = guide.copyWith(position: 200);
      expect(copy.id, guide.id);
      expect(copy.position, 200);
      expect(guide.position, 100);
    });

    test('equality by id', () {
      final g1 = CanvasGuide(
        id: NodeId('test-1'),
        position: 100,
        isHorizontal: true,
      );
      final g2 = CanvasGuide(
        id: NodeId('test-1'),
        position: 200,
        isHorizontal: false,
      );
      expect(g1, equals(g2));
    });
  });

  // -----------------------------------------------------------------------
  // E. Constraint Guides
  // -----------------------------------------------------------------------
  group('Constraint Guides', () {
    late RulerGuideSystem sys;

    setUp(() {
      sys = RulerGuideSystem();
    });

    test('ConstraintGuide resolve computes edge positions', () {
      final bounds = const Rect.fromLTWH(100, 50, 300, 200);

      expect(
        ConstraintGuide(
          frameId: 'f',
          edge: ConstraintEdge.left,
        ).resolve(bounds),
        100,
      );
      expect(
        ConstraintGuide(
          frameId: 'f',
          edge: ConstraintEdge.right,
        ).resolve(bounds),
        400,
      );
      expect(
        ConstraintGuide(frameId: 'f', edge: ConstraintEdge.top).resolve(bounds),
        50,
      );
      expect(
        ConstraintGuide(
          frameId: 'f',
          edge: ConstraintEdge.bottom,
        ).resolve(bounds),
        250,
      );
      expect(
        ConstraintGuide(
          frameId: 'f',
          edge: ConstraintEdge.centerX,
        ).resolve(bounds),
        250,
      );
      expect(
        ConstraintGuide(
          frameId: 'f',
          edge: ConstraintEdge.centerY,
        ).resolve(bounds),
        150,
      );
    });

    test('ConstraintGuide offset works', () {
      final bounds = const Rect.fromLTWH(0, 0, 400, 300);

      final cg = ConstraintGuide(
        frameId: 'f',
        edge: ConstraintEdge.left,
        offset: 16,
      );
      expect(cg.resolve(bounds), 16); // 0 + 16

      final cgR = ConstraintGuide(
        frameId: 'f',
        edge: ConstraintEdge.right,
        offset: 16,
      );
      expect(cgR.resolve(bounds), 384); // 400 - 16
    });

    test('ConstraintGuide isHorizontal classification', () {
      expect(
        ConstraintGuide(frameId: 'f', edge: ConstraintEdge.top).isHorizontal,
        true,
      );
      expect(
        ConstraintGuide(frameId: 'f', edge: ConstraintEdge.left).isHorizontal,
        false,
      );
      expect(
        ConstraintGuide(
          frameId: 'f',
          edge: ConstraintEdge.centerY,
        ).isHorizontal,
        true,
      );
      expect(
        ConstraintGuide(
          frameId: 'f',
          edge: ConstraintEdge.centerX,
        ).isHorizontal,
        false,
      );
    });

    test('addConstraintGuide and resolveConstraintGuides', () {
      final cg = ConstraintGuide(
        frameId: 'frame-1',
        edge: ConstraintEdge.left,
        offset: 16,
      );
      sys.addConstraintGuide(cg);
      expect(sys.constraintGuides.length, 1);

      sys.resolveConstraintGuides({
        'frame-1': const Rect.fromLTWH(100, 50, 400, 300),
      });
      expect(sys.resolvedConstraintPositions[cg.id], 116); // 100 + 16
    });

    test('removeConstraintGuide', () {
      final cg = ConstraintGuide(frameId: 'f', edge: ConstraintEdge.top);
      sys.addConstraintGuide(cg);
      sys.removeConstraintGuide(cg.id);
      expect(sys.constraintGuides, isEmpty);
    });

    test('constraint guides snap in snapPoint', () {
      sys.snapEnabled = true;
      final cg = ConstraintGuide(frameId: 'f1', edge: ConstraintEdge.left);
      sys.addConstraintGuide(cg);
      sys.resolveConstraintGuides({
        'f1': const Rect.fromLTWH(200, 0, 400, 300),
      });

      // Snap X to 200 (left edge)
      final snapped = sys.snapPoint(const Offset(203, 100), 1.0);
      expect(snapped.dx, 200);
    });

    test('constraint guides are serialized', () {
      sys.addConstraintGuide(
        ConstraintGuide(
          frameId: 'f1',
          edge: ConstraintEdge.right,
          offset: 10,
          label: 'gutter',
        ),
      );

      final json = sys.toJson();
      final sys2 = RulerGuideSystem();
      sys2.loadFromJson(json);

      expect(sys2.constraintGuides.length, 1);
      expect(sys2.constraintGuides.first.edge, ConstraintEdge.right);
      expect(sys2.constraintGuides.first.offset, 10);
      expect(sys2.constraintGuides.first.label, 'gutter');
    });

    test('ConstraintGuide toJson/fromJson round trip', () {
      final cg = ConstraintGuide(
        frameId: 'f2',
        edge: ConstraintEdge.centerX,
        offset: 5,
        color: const Color(0xFF00FF00),
        label: 'center axis',
      );
      final json = cg.toJson();
      final restored = ConstraintGuide.fromJson(json);

      expect(restored.frameId, 'f2');
      expect(restored.edge, ConstraintEdge.centerX);
      expect(restored.offset, 5);
      expect(restored.color, const Color(0xFF00FF00));
      expect(restored.label, 'center axis');
    });
  });

  // -----------------------------------------------------------------------
  // C. Grid Overlay Opacity
  // -----------------------------------------------------------------------
  group('Grid Overlay Opacity', () {
    test('gridOpacity defaults to 1.0', () {
      final sys = RulerGuideSystem();
      expect(sys.gridOpacity, 1.0);
    });

    test('gridOpacity serialized and restored', () {
      final sys = RulerGuideSystem()..gridOpacity = 0.5;
      final json = sys.toJson();
      final sys2 = RulerGuideSystem();
      sys2.loadFromJson(json);
      expect(sys2.gridOpacity, 0.5);
    });
  });

  // -----------------------------------------------------------------------
  // D. Sub-Pixel Grid
  // -----------------------------------------------------------------------
  group('Sub-Pixel Grid', () {
    test('gridStep returns sub-pixel step at high zoom', () {
      final sys = RulerGuideSystem();
      // At zoom 10, target spacing = 40, step 5 * 10 = 50 >= 40 ✓
      // But sub-pixel: 0.125 * 10 = 1.25 < 40, 0.25 * 10 = 2.5 < 40,
      // 0.5 * 10 = 5 < 40, 1.0 * 10 = 10 < 40, 2.0 * 10 = 20 < 40,
      // 5.0 * 10 = 50 >= 40 ✓ -> step = 5
      final step = sys.gridStep(10.0);
      expect(step, 5.0);
    });

    test('gridStep returns fractional step at very high zoom', () {
      final sys = RulerGuideSystem();
      // At zoom 100: 0.125 * 100 = 12.5 < 40, 0.25 * 100 = 25 < 40
      // 0.5 * 100 = 50 >= 40 ✓ -> step = 0.5
      final step = sys.gridStep(100.0);
      expect(step, 0.5);
    });

    test('gridStep returns 0.25 at zoom 200', () {
      final sys = RulerGuideSystem();
      // 0.125 * 200 = 25 < 40, 0.25 * 200 = 50 >= 40 ✓
      final step = sys.gridStep(200.0);
      expect(step, 0.25);
    });

    test('gridStep at normal zoom uses standard steps', () {
      final sys = RulerGuideSystem();
      // At zoom 1.0 (< 4.0), no sub-pixel.
      // 1.0 * 1.0 = 1 < 40, ..., 50.0 * 1.0 = 50 >= 40 ✓ -> step = 50
      final step = sys.gridStep(1.0);
      expect(step, 50.0);
    });
  });

  // -----------------------------------------------------------------------
  // Integration: mixed global + frame + constraint
  // -----------------------------------------------------------------------
  group('Integration', () {
    test('snap priority: global guide > frame guide > constraint guide', () {
      final sys = RulerGuideSystem()..snapEnabled = true;

      // Global guide at y=100
      sys.addHorizontalGuide(100);

      // Frame guide at y=103
      sys.addFrameGuide(CanvasGuide(position: 103, isHorizontal: true));

      // Constraint guide at y=106
      final cg = ConstraintGuide(frameId: 'f', edge: ConstraintEdge.top);
      sys.addConstraintGuide(cg);
      sys.resolveConstraintGuides({'f': const Rect.fromLTWH(0, 106, 100, 100)});

      // Point at (50, 102) → should snap to global guide at 100
      final snapped = sys.snapPoint(const Offset(50, 102), 1.0);
      expect(snapped.dy, 100);
    });

    test('full toJson/loadFromJson round-trip with all new fields', () {
      final sys = RulerGuideSystem();
      sys.gridOpacity = 0.7;
      sys.addFrameGuide(
        CanvasGuide(position: 200, isHorizontal: false, frameId: 'artboard-1'),
      );
      sys.addConstraintGuide(
        ConstraintGuide(
          frameId: 'artboard-1',
          edge: ConstraintEdge.bottom,
          offset: 32,
        ),
      );

      final json = sys.toJson();
      final sys2 = RulerGuideSystem();
      sys2.loadFromJson(json);

      expect(sys2.gridOpacity, 0.7);
      expect(sys2.frameGuides.length, 1);
      expect(sys2.frameGuides.first.position, 200);
      expect(sys2.constraintGuides.length, 1);
      expect(sys2.constraintGuides.first.edge, ConstraintEdge.bottom);
      expect(sys2.constraintGuides.first.offset, 32);
    });
  });
}
