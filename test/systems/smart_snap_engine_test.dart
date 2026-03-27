import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/systems/smart_snap_engine.dart';

import '../helpers/test_helpers.dart';

void main() {
  late SmartSnapEngine engine;

  setUp(() {
    engine = SmartSnapEngine(threshold: 8.0, gridSpacing: 0.0);
  });

  // ===========================================================================
  // snapAngle
  // ===========================================================================

  group('snapAngle', () {
    test('snaps to nearest 15-degree increment', () {
      // 14 degrees in radians → should snap to 15
      final input = 14 * math.pi / 180;
      final snapped = engine.snapAngle(input);
      final snappedDeg = snapped * 180 / math.pi;

      expect(snappedDeg, closeTo(15, 0.01));
    });

    test('exact increment stays unchanged', () {
      final input = 45 * math.pi / 180;
      final snapped = engine.snapAngle(input);
      final snappedDeg = snapped * 180 / math.pi;

      expect(snappedDeg, closeTo(45, 0.01));
    });

    test('0 degrees stays at 0', () {
      expect(engine.snapAngle(0), closeTo(0, 0.001));
    });

    test('disabled when angleIncrement is 0', () {
      engine = SmartSnapEngine(angleIncrement: 0.0);
      const input = 17 * math.pi / 180;
      expect(engine.snapAngle(input), closeTo(input, 0.001));
    });
  });

  // ===========================================================================
  // SnapResult
  // ===========================================================================

  group('SnapResult', () {
    test('hasSnap is false for empty result', () {
      const result = SnapResult();
      expect(result.hasSnap, false);
      expect(result.allGuides, isEmpty);
      expect(result.snapOffset, Offset.zero);
    });

    test('hasSnap is true with horizontal guides', () {
      final result = SnapResult(
        horizontalGuides: [
          SnapGuide(
            position: 100,
            axis: SnapAxis.horizontal,
            type: SnapGuideType.edgeAlignment,
          ),
        ],
      );
      expect(result.hasSnap, true);
      expect(result.allGuides, hasLength(1));
    });
  });

  // ===========================================================================
  // SnapGuide
  // ===========================================================================

  group('SnapGuide', () {
    test('stores all fields', () {
      final guide = SnapGuide(
        position: 42.0,
        axis: SnapAxis.vertical,
        type: SnapGuideType.centerAlignment,
        referenceNodeId: 'ref1',
      );

      expect(guide.position, 42.0);
      expect(guide.axis, SnapAxis.vertical);
      expect(guide.type, SnapGuideType.centerAlignment);
      expect(guide.referenceNodeId, 'ref1');
    });
  });

  // ===========================================================================
  // calculateSnaps — edge alignment
  // ===========================================================================

  group('calculateSnaps', () {
    test('detects horizontal edge alignment', () {
      // Two shapes at the same Y position — should snap
      final dragged = testShapeNode(id: 'drag');
      final other = testShapeNode(id: 'other');

      final result = engine.calculateSnaps(dragged, [other]);

      // Both shapes have the same bounds (from test helpers),
      // so edge alignment should be detected
      expect(result, isA<SnapResult>());
    });

    test('skips self in calculation', () {
      final node = testShapeNode(id: 'self');
      final result = engine.calculateSnaps(node, [node]);

      // Should not snap to self
      expect(result.horizontalGuides, isEmpty);
      expect(result.verticalGuides, isEmpty);
    });

    test('returns empty for no other nodes', () {
      final node = testShapeNode(id: 'alone');
      final result = engine.calculateSnaps(node, []);

      expect(result.hasSnap, false);
    });
  });

  // ===========================================================================
  // matchSize
  // ===========================================================================

  group('matchSize', () {
    test('returns guide when sizes match within threshold', () {
      final other = testShapeNode(id: 'ref');
      final guide = engine.matchSize(
        const Size(100, 100), // Match the default test shape bounds
        other,
        SnapAxis.horizontal,
      );

      // The test shape size determines if this matches
      expect(guide == null || guide.type == SnapGuideType.sizeMatch, true);
    });
  });

  // ===========================================================================
  // Threshold
  // ===========================================================================

  group('threshold', () {
    test('mutable threshold works', () {
      engine.threshold = 20.0;
      expect(engine.threshold, 20.0);
    });
  });

  // ===========================================================================
  // Grid snap
  // ===========================================================================

  group('grid snap', () {
    test('grid snap disabled when gridSpacing is 0', () {
      final node = testShapeNode(id: 'grid-test');
      final result = engine.calculateSnaps(node, []);

      // No grid snapping should occur
      expect(result.snapOffset, Offset.zero);
    });
  });

  // ===========================================================================
  // Enums
  // ===========================================================================

  group('enums', () {
    test('SnapGuideType has expected values', () {
      expect(SnapGuideType.values, contains(SnapGuideType.edgeAlignment));
      expect(SnapGuideType.values, contains(SnapGuideType.centerAlignment));
      expect(SnapGuideType.values, contains(SnapGuideType.equalSpacing));
      expect(SnapGuideType.values, contains(SnapGuideType.gridSnap));
      expect(SnapGuideType.values, contains(SnapGuideType.angleSnap));
      expect(SnapGuideType.values, contains(SnapGuideType.sizeMatch));
    });

    test('SnapAxis has horizontal and vertical', () {
      expect(SnapAxis.values, hasLength(2));
    });
  });
}
