import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/ai_provider.dart';
import 'package:fluera_engine/src/ai/atlas_action.dart';
import 'package:fluera_engine/src/canvas/ai/chat_session_controller.dart';

/// Minimal AiProvider that never hits the network. Used so the controller
/// can be constructed in tests without exploding the askChatStream path.
class _NoopAiProvider extends AiProvider {
  @override
  String get name => 'noop';

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<AtlasResponse> askAtlas(
    String userPrompt,
    List<Map<String, dynamic>> canvasContext,
  ) async =>
      const AtlasResponse(actions: [], explanation: '');

  @override
  void dispose() {}
}

void main() {
  // The controller's constructor calls `_loadHistory()` which touches
  // path_provider. That code is wrapped in try/catch so failures are
  // silent in tests — we don't need to mock the channel for these
  // router-focused tests.

  group('ChatSessionController quick actions = router', () {
    test('findGaps() returns false when no router handler is wired', () {
      final controller = ChatSessionController(
        provider: _NoopAiProvider(),
      );
      addTearDown(controller.dispose);

      expect(controller.findGaps(), isFalse);
    });

    test('findGaps() invokes onTriggerGhostMap when wired', () {
      var triggered = 0;
      final controller = ChatSessionController(
        provider: _NoopAiProvider(),
        router: ChatActionRouter(
          onTriggerGhostMap: () => triggered++,
        ),
      );
      addTearDown(controller.dispose);

      expect(controller.findGaps(), isTrue);
      expect(triggered, 1);
    });

    test('startQuiz() invokes onTriggerExam', () {
      var triggered = 0;
      final controller = ChatSessionController(
        provider: _NoopAiProvider(),
        router: ChatActionRouter(
          onTriggerExam: () => triggered++,
        ),
      );
      addTearDown(controller.dispose);

      expect(controller.startQuiz(), isTrue);
      expect(triggered, 1);
    });

    test(
      'startSocratic() forwards the selected cluster id when exactly one is selected',
      () {
        String? receivedId = 'sentinel';
        final controller = ChatSessionController(
          provider: _NoopAiProvider(),
          router: ChatActionRouter(
            onTriggerSocraticOnCluster: (id) => receivedId = id,
          ),
        );
        addTearDown(controller.dispose);

        controller.selectedClusterIds = {'cluster_42'};
        expect(controller.startSocratic(), isTrue);
        expect(receivedId, 'cluster_42');
      },
    );

    test(
      'startSocratic() forwards null when zero or multiple clusters selected',
      () {
        String? receivedId = 'sentinel';
        final controller = ChatSessionController(
          provider: _NoopAiProvider(),
          router: ChatActionRouter(
            onTriggerSocraticOnCluster: (id) => receivedId = id,
          ),
        );
        addTearDown(controller.dispose);

        // Zero selected → null
        receivedId = 'sentinel';
        controller.selectedClusterIds = {};
        expect(controller.startSocratic(), isTrue);
        expect(receivedId, isNull);

        // Multiple selected → null (canvas decides UX)
        receivedId = 'sentinel';
        controller.selectedClusterIds = {'a', 'b'};
        expect(controller.startSocratic(), isTrue);
        expect(receivedId, isNull);
      },
    );

    test('compareWithSource() invokes onTriggerSourceCompare', () {
      var triggered = 0;
      final controller = ChatSessionController(
        provider: _NoopAiProvider(),
        router: ChatActionRouter(
          onTriggerSourceCompare: (_) => triggered++,
        ),
      );
      addTearDown(controller.dispose);

      expect(controller.compareWithSource(), isTrue);
      expect(triggered, 1);
    });

    test('no router action sends a user message (no LLM prompt leakage)', () {
      // The whole point of the router refactor: clicking a chip must NOT
      // append a hard-coded prompt to the conversation — that's what the
      // old summarize/generateFlashcards/explainConcept did.
      final controller = ChatSessionController(
        provider: _NoopAiProvider(),
        router: ChatActionRouter(
          onTriggerGhostMap: () {},
          onTriggerExam: () {},
          onTriggerSocraticOnCluster: (_) {},
          onTriggerSourceCompare: (_) {},
        ),
      );
      addTearDown(controller.dispose);

      controller.startSession();

      controller.findGaps();
      controller.startQuiz();
      controller.startSocratic();
      controller.compareWithSource();

      expect(controller.session?.messages, isEmpty);
    });
  });
}
