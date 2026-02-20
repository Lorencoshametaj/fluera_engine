import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/tools/ruler/ruler_guide_system.dart';

void main() {
  late RulerGuideSystem sys;

  setUp(() {
    sys = RulerGuideSystem();
  });

  // ─── Guide CRUD ────────────────────────────────────────────────────

  group('Guide CRUD', () {
    test('adds horizontal guide with correct parallel lists', () {
      sys.addHorizontalGuide(100);
      expect(sys.horizontalGuides, [100.0]);
      expect(sys.horizontalLocked, [false]);
      expect(sys.horizontalColors, [null]);
      expect(sys.horizontalLabels, [null]);
    });

    test('adds vertical guide with custom color', () {
      sys.addVerticalGuide(200, color: const Color(0xFFFF0000));
      expect(sys.verticalGuides, [200.0]);
      expect(sys.verticalColors, [const Color(0xFFFF0000)]);
    });

    test('rejects duplicate guide within 0.5px', () {
      sys.addHorizontalGuide(100);
      sys.addHorizontalGuide(100.3);
      expect(sys.horizontalGuides.length, 1);
    });

    test('respects maxGuidesPerAxis', () {
      for (int i = 0; i < RulerGuideSystem.maxGuidesPerAxis + 5; i++) {
        sys.addHorizontalGuide(i * 10.0);
      }
      expect(sys.horizontalGuides.length, RulerGuideSystem.maxGuidesPerAxis);
    });

    test('removeHorizontalGuideAt shifts selection indices', () {
      sys.addHorizontalGuide(10);
      sys.addHorizontalGuide(20);
      sys.addHorizontalGuide(30);
      sys.selectedHorizontalGuides.addAll({1, 2});
      sys.removeHorizontalGuideAt(0);
      // indices should shift down by 1
      expect(sys.selectedHorizontalGuides, {0, 1});
    });

    test('removeVerticalGuideAt cleans up symmetry axis', () {
      sys.addVerticalGuide(50);
      sys.addVerticalGuide(100);
      sys.setSymmetryAxis(false, 0);
      sys.removeVerticalGuideAt(0);
      expect(sys.symmetryEnabled, false);
      expect(sys.symmetryAxisIndex, null);
    });

    test('clearAllGuides empties all lists', () {
      sys.addHorizontalGuide(10);
      sys.addVerticalGuide(20);
      sys.setGuideLabel(true, 0, 'Label');
      sys.clearAllGuides();
      expect(sys.horizontalGuides, isEmpty);
      expect(sys.verticalGuides, isEmpty);
      expect(sys.horizontalLabels, isEmpty);
      expect(sys.verticalLabels, isEmpty);
    });

    test('guide labels persist through add/remove', () {
      sys.addHorizontalGuide(10);
      sys.setGuideLabel(true, 0, 'MyLabel');
      expect(sys.getGuideLabel(true, 0), 'MyLabel');
    });
  });

  // ─── Snap Priority Cascade ─────────────────────────────────────────

  group('Snap Priority Cascade', () {
    test('snaps to vertical guide (highest priority)', () {
      sys.snapEnabled = true;
      sys.addVerticalGuide(100);
      final result = sys.snapPoint(const Offset(103, 200), 1.0);
      expect(result.dx, 100.0);
      expect(sys.lastSnapType, 'guide');
    });

    test('snaps to horizontal guide', () {
      sys.snapEnabled = true;
      sys.addHorizontalGuide(200);
      final result = sys.snapPoint(const Offset(50, 203), 1.0);
      expect(result.dy, 200.0);
      expect(sys.lastSnapType, 'guide');
    });

    test('snaps to angular guide when no linear guide nearby', () {
      sys.snapEnabled = true;
      // Angular guide at (0,0), 45° → direction (cos45, sin45)
      sys.addAngularGuide(Offset.zero, 45.0);
      final point = const Offset(100, 105); // slightly off y=x line
      final result = sys.snapPoint(point, 1.0);
      // Should snap to the 45° line through origin
      expect((result.dx - result.dy).abs(), lessThan(1.0));
      expect(sys.lastSnapType, 'angular');
    });

    test('snaps to grid when no guide nearby', () {
      sys.snapEnabled = true;
      sys.gridVisible = true;
      sys.gridSnapEnabled = true;
      sys.customGridStep = 50;
      final result = sys.snapPoint(const Offset(103, 198), 1.0);
      expect(result.dx, 100.0);
      expect(result.dy, 200.0);
      expect(sys.lastSnapType, 'grid');
    });

    test('returns unsnapped when snapEnabled is false', () {
      sys.snapEnabled = false;
      sys.addVerticalGuide(100);
      final result = sys.snapPoint(const Offset(103, 200), 1.0);
      expect(result.dx, 103.0);
      expect(result.dy, 200.0);
    });

    test('snap adjusts to zoom level', () {
      sys.snapEnabled = true;
      sys.addVerticalGuide(100);
      // At zoom 0.5, snap distance doubles in canvas coords
      final result = sys.snapPoint(const Offset(114, 200), 0.5);
      expect(result.dx, 100.0);
    });
  });

  // ─── Isometric & Radial Snap ───────────────────────────────────────

  group('Isometric & Radial Snap', () {
    test('snaps to isometric grid intersection', () {
      sys.snapEnabled = true;
      sys.isometricGridVisible = true;
      sys.customGridStep = 50;
      final result = sys.snapPoint(const Offset(52, 3), 1.0);
      expect(result.dx, 50.0);
      expect(sys.lastSnapType, 'isometric');
    });

    test('snaps to radial grid intersection', () {
      sys.snapEnabled = true;
      sys.radialGridVisible = true;
      sys.radialCenter = const Offset(200, 200);
      sys.radialMaxRadius = 300;
      sys.radialRings = 6;
      sys.radialDivisions = 12;
      // Point near (200 + 50, 200) = ring 1 at 0°
      final ringSpacing = 300.0 / 6; // 50
      final result = sys.snapPoint(const Offset(252, 203), 1.0);
      expect(result.dx, closeTo(200 + ringSpacing, 1.0));
      expect(result.dy, closeTo(200, 1.0));
      expect(sys.lastSnapType, 'radial');
    });
  });

  // ─── Grid Step Calculation ─────────────────────────────────────────

  group('Grid Step', () {
    test('custom step overrides auto-calculation', () {
      sys.customGridStep = 25;
      expect(sys.gridStep(1.0), 25.0);
    });

    test('null custom step uses nice-step algorithm', () {
      sys.customGridStep = null;
      final step = sys.gridStep(1.0);
      expect(step, greaterThan(0));
      // At zoom 1.0, target spacing 40px → step should be ≥ 40
      expect(step, greaterThanOrEqualTo(40));
    });

    test('higher zoom produces smaller step', () {
      sys.customGridStep = null;
      final stepLow = sys.gridStep(0.5);
      final stepHigh = sys.gridStep(5.0);
      expect(stepHigh, lessThanOrEqualTo(stepLow));
    });

    test('very low zoom falls back to 100', () {
      sys.customGridStep = null;
      final step = sys.gridStep(0.01);
      expect(step, 100.0);
    });
  });

  // ─── Symmetry ──────────────────────────────────────────────────────

  group('Symmetry', () {
    test('mirrorPoint reflects across horizontal guide', () {
      sys.addHorizontalGuide(100);
      sys.setSymmetryAxis(true, 0);
      final mirrored = sys.mirrorPoint(const Offset(50, 80));
      expect(mirrored!.dy, 120.0);
      expect(mirrored.dx, 50.0);
    });

    test('mirrorPoint reflects across vertical guide', () {
      sys.addVerticalGuide(200);
      sys.setSymmetryAxis(false, 0);
      final mirrored = sys.mirrorPoint(const Offset(180, 50));
      expect(mirrored!.dx, 220.0);
    });

    test('mirrorPointMulti generates N-1 copies for kaleidoscope', () {
      sys.addHorizontalGuide(100);
      sys.setSymmetryAxis(true, 0);
      sys.symmetrySegments = 6;
      final copies = sys.mirrorPointMulti(const Offset(50, 80));
      expect(copies.length, 5); // 6 segments - 1
    });

    test('clearSymmetry resets all symmetry state', () {
      sys.addHorizontalGuide(100);
      sys.setSymmetryAxis(true, 0);
      sys.symmetrySegments = 8;
      sys.clearSymmetry();
      expect(sys.symmetryEnabled, false);
      expect(sys.symmetryAxisIndex, null);
      expect(sys.symmetrySegments, 2);
    });
  });

  // ─── toJson ↔ loadFromJson Round-Trip ──────────────────────────────

  group('toJson ↔ loadFromJson round-trip', () {
    test('round-trips guides with colors and labels', () {
      sys.addHorizontalGuide(100, color: const Color(0xFFFF0000));
      sys.addVerticalGuide(200);
      sys.setGuideLabel(true, 0, 'HLabel');
      sys.verticalLabels.add(null); // ensure alignment

      final json = sys.toJson();
      final restored = RulerGuideSystem();
      restored.loadFromJson(json);

      expect(restored.horizontalGuides, [100.0]);
      expect(restored.verticalGuides, [200.0]);
      expect(restored.horizontalColors.first, const Color(0xFFFF0000));
      expect(restored.horizontalLabels.first, 'HLabel');
    });

    test('round-trips grid settings', () {
      sys.gridVisible = true;
      sys.gridSnapEnabled = true;
      sys.gridStyle = GridStyle.dots;
      sys.customGridStep = 25;

      final json = sys.toJson();
      final restored = RulerGuideSystem();
      restored.loadFromJson(json);

      expect(restored.gridVisible, true);
      expect(restored.gridSnapEnabled, true);
      expect(restored.gridStyle, GridStyle.dots);
      expect(restored.customGridStep, 25);
    });

    test('round-trips angular guides', () {
      sys.addAngularGuide(
        const Offset(10, 20),
        45.0,
        color: const Color(0xFF00FF00),
      );

      final json = sys.toJson();
      final restored = RulerGuideSystem();
      restored.loadFromJson(json);

      expect(restored.angularGuides.length, 1);
      expect(restored.angularGuides.first.origin, const Offset(10, 20));
      expect(restored.angularGuides.first.angleDeg, 45.0);
    });

    test('round-trips perspective grid', () {
      sys.perspectiveType = PerspectiveType.twoPoint;
      sys.vp1 = const Offset(100, 200);
      sys.vp2 = const Offset(400, 200);

      final json = sys.toJson();
      final restored = RulerGuideSystem();
      restored.loadFromJson(json);

      expect(restored.perspectiveType, PerspectiveType.twoPoint);
      expect(restored.vp1, const Offset(100, 200));
      expect(restored.vp2, const Offset(400, 200));
    });

    test('round-trips radial grid', () {
      sys.radialGridVisible = true;
      sys.radialCenter = const Offset(150, 250);
      sys.radialDivisions = 8;
      sys.radialRings = 4;
      sys.radialMaxRadius = 500;

      final json = sys.toJson();
      final restored = RulerGuideSystem();
      restored.loadFromJson(json);

      expect(restored.radialGridVisible, true);
      expect(restored.radialCenter, const Offset(150, 250));
      expect(restored.radialDivisions, 8);
      expect(restored.radialRings, 4);
      expect(restored.radialMaxRadius, 500);
    });

    test('round-trips enterprise v2 fields (opacity, theme, etc.)', () {
      sys.guideOpacity = 0.7;
      sys.snapStrength = 0.9;
      sys.guideColorTheme = GuideColorTheme.neon;
      sys.showGoldenSpiral = true;
      sys.protractorSnapStep = 30;
      sys.crosshairEnabled = true;
      sys.rulersVisible = false;
      sys.guidesVisible = false;

      final json = sys.toJson();
      final restored = RulerGuideSystem();
      restored.loadFromJson(json);

      expect(restored.guideOpacity, 0.7);
      expect(restored.snapStrength, 0.9);
      expect(restored.guideColorTheme, GuideColorTheme.neon);
      expect(restored.showGoldenSpiral, true);
      expect(restored.protractorSnapStep, 30);
      expect(restored.crosshairEnabled, true);
      expect(restored.rulersVisible, false);
      expect(restored.guidesVisible, false);
    });

    test('round-trips bookmarks', () {
      sys.addBookmark(50, true, const Color(0xFFABCDEF));

      final json = sys.toJson();
      final restored = RulerGuideSystem();
      restored.loadFromJson(json);

      expect(restored.bookmarkMarks.length, 1);
      expect(restored.bookmarkMarks.first.position, 50.0);
      expect(restored.bookmarkMarks.first.isHorizontal, true);
    });

    test('round-trips spacing locks', () {
      sys.addHorizontalGuide(10);
      sys.addHorizontalGuide(60);
      sys.addSpacingLock(true, 0, 1);

      final json = sys.toJson();
      final restored = RulerGuideSystem();
      restored.loadFromJson(json);

      expect(restored.spacingLocks.length, 1);
      expect(restored.spacingLocks.first.distance, 50.0);
    });

    test('round-trips named guide groups', () {
      sys.addHorizontalGuide(10);
      sys.addVerticalGuide(20);
      sys.createGroup('MyGroup', {0}, {0});

      final json = sys.toJson();
      final restored = RulerGuideSystem();
      restored.loadFromJson(json);

      expect(restored.namedGuideGroups.length, 1);
      expect(restored.namedGuideGroups.first.name, 'MyGroup');
    });

    test('round-trips percent guides', () {
      sys.addPercentGuide(true, 50.0, 1000);
      sys.addPercentGuide(false, 33.0, 800);

      final json = sys.toJson();
      final restored = RulerGuideSystem();
      restored.loadFromJson(json);

      expect(restored.horizontalPercentGuides[0], 50.0);
      expect(restored.verticalPercentGuides[0], 33.0);
    });

    test('loadFromJson with null is a no-op', () {
      sys.addHorizontalGuide(42);
      sys.loadFromJson(null);
      // Should not clear existing state
      expect(sys.horizontalGuides, [42.0]);
    });
  });

  // ─── Undo/Redo Snapshots ───────────────────────────────────────────

  group('Undo/Redo', () {
    test('basic undo restores previous guide state', () {
      sys.saveSnapshot();
      sys.addHorizontalGuide(100);
      sys.undo();
      expect(sys.horizontalGuides, isEmpty);
    });

    test('redo re-applies undone state', () {
      sys.addHorizontalGuide(50);
      sys.saveSnapshot();
      sys.clearAllGuides();
      expect(sys.horizontalGuides, isEmpty);
      sys.undo();
      expect(sys.horizontalGuides, [50.0]);
      sys.redo();
      expect(sys.horizontalGuides, isEmpty);
    });

    test('snapshot captures labels', () {
      sys.addHorizontalGuide(100);
      sys.setGuideLabel(true, 0, 'Before');
      sys.saveSnapshot();
      sys.setGuideLabel(true, 0, 'After');
      expect(sys.getGuideLabel(true, 0), 'After');
      sys.undo();
      expect(sys.getGuideLabel(true, 0), 'Before');
    });

    test('snapshot captures guide opacity', () {
      sys.guideOpacity = 0.5;
      sys.saveSnapshot();
      sys.guideOpacity = 1.0;
      sys.undo();
      expect(sys.guideOpacity, 0.5);
    });
  });

  // ─── onChanged Callback ────────────────────────────────────────────

  group('onChanged callback', () {
    test('fires on addHorizontalGuide', () {
      int count = 0;
      sys.onChanged = () => count++;
      sys.addHorizontalGuide(100);
      expect(count, 1);
    });

    test('fires on addVerticalGuide', () {
      int count = 0;
      sys.onChanged = () => count++;
      sys.addVerticalGuide(200);
      expect(count, 1);
    });

    test('fires on removeHorizontalGuideAt', () {
      sys.addHorizontalGuide(100);
      int count = 0;
      sys.onChanged = () => count++;
      sys.removeHorizontalGuideAt(0);
      expect(count, 1);
    });

    test('fires on removeVerticalGuideAt', () {
      sys.addVerticalGuide(100);
      int count = 0;
      sys.onChanged = () => count++;
      sys.removeVerticalGuideAt(0);
      expect(count, 1);
    });

    test('fires on undo', () {
      sys.saveSnapshot();
      sys.addHorizontalGuide(100);
      int count = 0;
      sys.onChanged = () => count++;
      sys.undo();
      expect(count, 1);
    });

    test('fires on redo', () {
      sys.addHorizontalGuide(100);
      sys.saveSnapshot();
      sys.addHorizontalGuide(200);
      sys.undo();
      int count = 0;
      sys.onChanged = () => count++;
      sys.redo();
      expect(count, 1);
    });

    test('fires on clearAllGuides', () {
      sys.addHorizontalGuide(100);
      int count = 0;
      sys.onChanged = () => count++;
      sys.clearAllGuides();
      expect(count, greaterThanOrEqualTo(1));
    });
  });

  // ─── Unit Conversion ───────────────────────────────────────────────

  group('Unit conversion', () {
    test('px returns identity', () {
      sys.currentUnit = RulerUnit.px;
      expect(sys.convertToUnit(72), 72);
    });

    test('cm conversion at 72 ppi', () {
      sys.currentUnit = RulerUnit.cm;
      sys.ppi = 72;
      // 72 px at 72 ppi = 1 inch = 2.54 cm
      expect(sys.convertToUnit(72), closeTo(2.54, 0.01));
    });

    test('mm conversion at 72 ppi', () {
      sys.currentUnit = RulerUnit.mm;
      sys.ppi = 72;
      expect(sys.convertToUnit(72), closeTo(25.4, 0.1));
    });

    test('inches conversion at 72 ppi', () {
      sys.currentUnit = RulerUnit.inches;
      sys.ppi = 72;
      expect(sys.convertToUnit(72), 1.0);
    });
  });

  // ─── Guide Operations ─────────────────────────────────────────────

  group('Guide operations', () {
    test('duplicateGuide creates offset copy', () {
      sys.addHorizontalGuide(100);
      sys.duplicateGuide(true, 0);
      expect(sys.horizontalGuides.length, 2);
      expect(sys.horizontalGuides[1], 120); // offset by 20
    });

    test('lockAllGuides locks everything', () {
      sys.addHorizontalGuide(10);
      sys.addVerticalGuide(20);
      sys.lockAllGuides();
      expect(sys.horizontalLocked, [true]);
      expect(sys.verticalLocked, [true]);
    });

    test('distributeGuides creates evenly spaced guides', () {
      sys.distributeGuides(true, 5, 0, 200);
      expect(sys.horizontalGuides.length, 5);
      expect(sys.horizontalGuides[0], 0);
      expect(sys.horizontalGuides[2], 100);
      expect(sys.horizontalGuides[4], 200);
    });

    test('spacing lock enforcement', () {
      sys.addHorizontalGuide(0);
      sys.addHorizontalGuide(50);
      sys.addSpacingLock(true, 0, 1);
      // Move guide 0 → enforce should adjust guide 1
      sys.horizontalGuides[0] = 10;
      sys.enforceSpacingLocks(true, 0);
      expect(
        (sys.horizontalGuides[1] - sys.horizontalGuides[0]).abs(),
        closeTo(50, 0.01),
      );
    });
  });
}
