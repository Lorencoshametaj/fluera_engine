import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/infinite_canvas_controller.dart';

void main() {
  // Required because _checkLodTier fires HapticFeedback through MethodChannel.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InfiniteCanvasController — LOD callbacks (A.1 + A.2)', () {
    late InfiniteCanvasController c;
    late List<String> events;

    setUp(() {
      c = InfiniteCanvasController();
      events = <String>[];
      c.onLodTierChanged = (oldTier, newTier) =>
          events.add('tier:$oldTier->$newTier');
      c.onLodTierApproaching = (next) => events.add('approach:$next');
    });

    tearDown(() {
      c.dispose();
    });

    test('crossing 0.5 boundary fires onLodTierChanged once with old+new', () {
      // Start at 1.0 (tier 0)
      c.setScale(1.0);
      events.clear();
      // Zoom out across the 0.45 hysteresis edge → tier 1
      c.setScale(0.40);
      expect(
        events.where((e) => e.startsWith('tier:')).length,
        1,
        reason: 'tier change should fire exactly once per crossing',
      );
      expect(events.contains('tier:0->1'), isTrue,
          reason: 'callback must receive oldTier=0 and newTier=1');
    });

    test('lingering inside approach band fires onLodTierApproaching once '
        '(throttled)', () {
      c.setScale(1.0); // tier 0
      events.clear();
      // 0.58 is inside [0.55, 0.60] approach band → tier 1
      c.setScale(0.58);
      // Re-enter same band immediately — must be throttled.
      c.setScale(0.57);
      c.setScale(0.56);
      final approachFires = events.where((e) => e.startsWith('approach:')).length;
      expect(
        approachFires,
        1,
        reason: 'approach should be throttled to 1 fire per ~150ms per tier',
      );
      expect(events.first, 'approach:1');
    });

    test('approach for tier 2 fires when entering [0.30, 0.35] from tier 1',
        () {
      c.setScale(0.40); // tier 1 (passes through 0.45 boundary first)
      events.clear();
      c.setScale(0.32);
      expect(events, contains('approach:2'));
    });

    test('approach lock resets after a real tier crossing', () {
      c.setScale(1.0);
      events.clear();
      c.setScale(0.58); // approach tier 1
      c.setScale(0.40); // cross into tier 1
      // Now we're in tier 1; re-entering [0.45, 0.50] should fire approach 0
      c.setScale(0.48);
      final hasApproach0 = events.contains('approach:0');
      expect(hasApproach0, isTrue,
          reason: 'approach lock should be reset on real tier switch');
    });

    test('worldViewportAABB returns canvas-space rect inverse of scale', () {
      c.setScale(1.0);
      final r = c.worldViewportAABB(const Size(400, 300));
      // At scale 1, offset 0, rect is exactly the screen size.
      expect(r.left, 0);
      expect(r.top, 0);
      expect(r.width, 400);
      expect(r.height, 300);
    });

    test('worldViewportAABB inflates when zooming out', () {
      c.setScale(0.5);
      final r = c.worldViewportAABB(const Size(400, 300));
      // At scale 0.5, viewport in world units doubles.
      expect(r.width, closeTo(800, 0.001));
      expect(r.height, closeTo(600, 0.001));
    });

    test('worldViewportAABB returns Rect.zero for empty size', () {
      c.setScale(1.0);
      expect(c.worldViewportAABB(Size.zero), Rect.zero);
    });
  });
}
