import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/prototype_flow.dart';

void main() {
  // ===========================================================================
  // PrototypeLink
  // ===========================================================================

  group('PrototypeLink', () {
    test('stores all fields with defaults', () {
      final link = PrototypeLink(
        id: 'link1',
        sourceNodeId: 'btn',
        targetFrameId: 'screen2',
      );

      expect(link.id, 'link1');
      expect(link.sourceNodeId, 'btn');
      expect(link.targetFrameId, 'screen2');
      expect(link.trigger, PrototypeTrigger.click);
      expect(link.transition, PrototypeTransition.dissolve);
      expect(link.isEnabled, true);
    });

    test('JSON roundtrip', () {
      final link = PrototypeLink(
        id: 'link1',
        sourceNodeId: 'btn',
        targetFrameId: 'screen2',
        trigger: PrototypeTrigger.hover,
        transition: PrototypeTransition.slideLeft,
        duration: const Duration(milliseconds: 500),
        easing: PrototypeEasing.spring,
        delay: const Duration(milliseconds: 100),
        preserveScrollPosition: true,
        isEnabled: false,
      );

      final json = link.toJson();
      final restored = PrototypeLink.fromJson(json);

      expect(restored.id, 'link1');
      expect(restored.sourceNodeId, 'btn');
      expect(restored.targetFrameId, 'screen2');
      expect(restored.trigger, PrototypeTrigger.hover);
      expect(restored.transition, PrototypeTransition.slideLeft);
      expect(restored.duration.inMilliseconds, 500);
      expect(restored.easing, PrototypeEasing.spring);
      expect(restored.delay.inMilliseconds, 100);
      expect(restored.preserveScrollPosition, true);
      expect(restored.isEnabled, false);
    });
  });

  // ===========================================================================
  // PrototypeScreen
  // ===========================================================================

  group('PrototypeScreen', () {
    test('stores fields', () {
      final screen = PrototypeScreen(
        frameId: 'home',
        name: 'Home Screen',
        isStartScreen: true,
      );

      expect(screen.frameId, 'home');
      expect(screen.name, 'Home Screen');
      expect(screen.isStartScreen, true);
    });

    test('JSON roundtrip', () {
      final screen = PrototypeScreen(frameId: 'settings', name: 'Settings');

      final json = screen.toJson();
      final restored = PrototypeScreen.fromJson(json);

      expect(restored.frameId, 'settings');
      expect(restored.name, 'Settings');
      expect(restored.isStartScreen, false);
    });
  });

  // ===========================================================================
  // PrototypeFlow
  // ===========================================================================

  group('PrototypeFlow', () {
    late PrototypeFlow flow;

    setUp(() {
      flow = PrototypeFlow(id: 'onboarding', name: 'Onboarding');
    });

    // --- Screens ---

    test('addScreen and getScreen', () {
      final screen = PrototypeScreen(frameId: 'splash', isStartScreen: true);
      flow.addScreen(screen);

      expect(flow.screens, hasLength(1));
      expect(flow.getScreen('splash'), isNotNull);
      expect(flow.getScreen('splash')!.isStartScreen, true);
    });

    test('getScreen returns null for missing', () {
      expect(flow.getScreen('missing'), isNull);
    });

    test('removeScreen removes screen and related links', () {
      flow.addScreen(PrototypeScreen(frameId: 'a'));
      flow.addScreen(PrototypeScreen(frameId: 'b'));
      flow.addLink(
        PrototypeLink(id: 'link1', sourceNodeId: 'a', targetFrameId: 'b'),
      );

      flow.removeScreen('a');

      expect(flow.screens, hasLength(1));
      expect(flow.links, isEmpty); // Link from 'a' removed
    });

    test('startScreen returns first isStartScreen', () {
      flow.addScreen(PrototypeScreen(frameId: 'a'));
      flow.addScreen(PrototypeScreen(frameId: 'b', isStartScreen: true));

      expect(flow.startScreen!.frameId, 'b');
    });

    test('startScreen falls back to first screen', () {
      flow.addScreen(PrototypeScreen(frameId: 'a'));
      flow.addScreen(PrototypeScreen(frameId: 'b'));

      expect(flow.startScreen!.frameId, 'a');
    });

    test('startScreen returns null for empty flow', () {
      expect(flow.startScreen, isNull);
    });

    // --- Links ---

    test('addLink and linksFromNode', () {
      flow.addLink(
        PrototypeLink(id: 'l1', sourceNodeId: 'btn', targetFrameId: 's2'),
      );
      flow.addLink(
        PrototypeLink(id: 'l2', sourceNodeId: 'btn', targetFrameId: 's3'),
      );
      flow.addLink(
        PrototypeLink(id: 'l3', sourceNodeId: 'other', targetFrameId: 's2'),
      );

      expect(flow.linksFromNode('btn'), hasLength(2));
      expect(flow.linksFromNode('other'), hasLength(1));
    });

    test('linksToFrame', () {
      flow.addLink(
        PrototypeLink(id: 'l1', sourceNodeId: 'a', targetFrameId: 'target'),
      );
      flow.addLink(
        PrototypeLink(id: 'l2', sourceNodeId: 'b', targetFrameId: 'target'),
      );

      expect(flow.linksToFrame('target'), hasLength(2));
    });

    test('removeLink removes by id', () {
      flow.addLink(
        PrototypeLink(id: 'l1', sourceNodeId: 'a', targetFrameId: 'b'),
      );
      flow.removeLink('l1');

      expect(flow.links, isEmpty);
    });

    // --- resolveNavigation ---

    test('resolveNavigation finds matching link', () {
      flow.addLink(
        PrototypeLink(
          id: 'l1',
          sourceNodeId: 'btn',
          targetFrameId: 'next',
          trigger: PrototypeTrigger.click,
        ),
      );

      final result = flow.resolveNavigation('btn', PrototypeTrigger.click);
      expect(result, isNotNull);
      expect(result!.targetFrameId, 'next');
    });

    test('resolveNavigation returns null for wrong trigger', () {
      flow.addLink(
        PrototypeLink(
          id: 'l1',
          sourceNodeId: 'btn',
          targetFrameId: 'next',
          trigger: PrototypeTrigger.click,
        ),
      );

      expect(flow.resolveNavigation('btn', PrototypeTrigger.hover), isNull);
    });

    test('resolveNavigation skips disabled links', () {
      flow.addLink(
        PrototypeLink(
          id: 'l1',
          sourceNodeId: 'btn',
          targetFrameId: 'next',
          trigger: PrototypeTrigger.click,
          isEnabled: false,
        ),
      );

      expect(flow.resolveNavigation('btn', PrototypeTrigger.click), isNull);
    });

    // --- Serialization ---

    test('JSON roundtrip preserves full flow', () {
      flow.addScreen(
        PrototypeScreen(frameId: 's1', isStartScreen: true, name: 'Splash'),
      );
      flow.addScreen(PrototypeScreen(frameId: 's2', name: 'Login'));
      flow.addLink(
        PrototypeLink(id: 'l1', sourceNodeId: 'btn', targetFrameId: 's2'),
      );

      final json = flow.toJson();
      final restored = PrototypeFlow.fromJson(json);

      expect(restored.id, 'onboarding');
      expect(restored.name, 'Onboarding');
      expect(restored.screens, hasLength(2));
      expect(restored.links, hasLength(1));
      expect(restored.startScreen!.frameId, 's1');
    });

    // --- Immutability of returned lists ---

    test('screens list is unmodifiable', () {
      flow.addScreen(PrototypeScreen(frameId: 's1'));
      expect(
        () => flow.screens.add(PrototypeScreen(frameId: 's2')),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('links list is unmodifiable', () {
      flow.addLink(
        PrototypeLink(id: 'l1', sourceNodeId: 'a', targetFrameId: 'b'),
      );
      expect(
        () => flow.links.add(
          PrototypeLink(id: 'l2', sourceNodeId: 'c', targetFrameId: 'd'),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
