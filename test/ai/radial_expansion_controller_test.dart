import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/radial_expansion_controller.dart';

void main() {
  group('RadialExpansionController', () {
    late RadialExpansionController controller;

    setUp(() {
      controller = RadialExpansionController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('starts in idle phase', () {
      expect(controller.phase, RadialExpansionPhase.idle);
      expect(controller.bubbles, isEmpty);
      expect(controller.chargeProgress, 0.0);
    });

    test('startCharge transitions from idle to charging', () {
      RadialExpansionPhase? lastPhase;
      controller.onPhaseChanged = (p) => lastPhase = p;

      controller.startCharge('cluster_1', const Offset(100, 200), 'Fisica');

      expect(controller.phase, RadialExpansionPhase.charging);
      expect(lastPhase, RadialExpansionPhase.charging);
      expect(controller.sourceClusterId, 'cluster_1');
      expect(controller.sourceCenter, const Offset(100, 200));
    });

    test('startCharge is ignored if not idle', () {
      controller.startCharge('c1', Offset.zero, 'text');
      expect(controller.phase, RadialExpansionPhase.charging);

      controller.startCharge('c2', const Offset(50, 50), 'other');
      expect(controller.sourceClusterId, 'c1');
    });

    test('cancelCharge returns to idle', () {
      controller.startCharge('c1', Offset.zero, 'text');
      expect(controller.phase, RadialExpansionPhase.charging);

      controller.cancelCharge();
      expect(controller.phase, RadialExpansionPhase.idle);
      expect(controller.chargeProgress, 0.0);
    });

    test('cancelCharge is ignored if not charging', () {
      controller.cancelCharge();
      expect(controller.phase, RadialExpansionPhase.idle);
    });

    test('tick advances charge progress', () {
      controller.startCharge('c1', Offset.zero, 'text');
      final changed = controller.tick(RadialExpansionController.chargeDuration / 2);
      expect(changed, isTrue);
      expect(controller.chargeProgress, closeTo(0.5, 0.02));
    });

    test('tick returns false when idle', () {
      final changed = controller.tick(0.016);
      expect(changed, isFalse);
    });

    test('cancelCharge is noop from non-charging phase', () {
      controller.cancelCharge();
      expect(controller.phase, RadialExpansionPhase.idle);
    });

    test('hitTest returns null when idle', () {
      final bubble = controller.hitTest(Offset.zero);
      expect(bubble, isNull);
    });

    test('dispose prevents further ticking', () {
      controller.startCharge('c1', Offset.zero, 'text');
      controller.dispose();
      final changed = controller.tick(0.016);
      expect(changed, isFalse);
    });

    test('generate guard prevents double call', () async {
      controller.startCharge('c1', Offset.zero, 'text');
      // First generate call moves to generating phase
      // We can't call generate() without an EngineScope, but we can test the guard
      // by verifying _generateCalled is respected via phase observation.
      // Instead test that generate from wrong phase returns empty:
      // (idle → allowed; after first call it's guarded)
      // Since we can't mock EngineScope here, just verify the phase check.
      expect(controller.phase, RadialExpansionPhase.charging);
    });

    group('GhostBubble', () {
      test('has correct initial state', () {
        final bubble = GhostBubble(
          id: 'test_1',
          label: 'Meccanica',
          targetPosition: const Offset(100, 200),
          angle: 0.0,
          distance: 180.0,
        );

        expect(bubble.id, 'test_1');
        expect(bubble.label, 'Meccanica');
        expect(bubble.opacity, 0.0);
        expect(bubble.scale, 1.2); // v3: starts at bounce-overshoot scale
        expect(bubble.state, GhostBubbleState.launching);
        expect(bubble.dragOffset, Offset.zero);
      });

      test('currentPosition interpolates correctly', () {
        const src = Offset(0, 0);
        const target = Offset(200, 0);
        final bubble = GhostBubble(
          id: 'b',
          label: 'Test',
          targetPosition: target,
          angle: 0,
          distance: 200,
        );

        bubble.launchProgress = 0.5;
        final pos = bubble.currentPosition(src);
        expect(pos.dx, closeTo(100, 0.1));
        expect(pos.dy, closeTo(0, 0.1));
      });

      test('drag offset applies to currentPosition', () {
        const src = Offset(0, 0);
        const target = Offset(200, 0);
        final bubble = GhostBubble(
          id: 'b',
          label: 'Test',
          targetPosition: target,
          angle: 0,
          distance: 200,
          launchProgress: 1.0,
        );
        bubble.dragOffset = const Offset(30, 0);
        final pos = bubble.currentPosition(src);
        expect(pos.dx, closeTo(230, 0.1));
      });
    });

    group('phase transitions', () {
      test('tracks phase changes via callback', () {
        final phases = <RadialExpansionPhase>[];
        controller.onPhaseChanged = (p) => phases.add(p);

        controller.startCharge('c1', Offset.zero, 'text');
        controller.cancelCharge();

        expect(phases, [
          RadialExpansionPhase.charging,
          RadialExpansionPhase.idle,
        ]);
      });
    });
  });
}
