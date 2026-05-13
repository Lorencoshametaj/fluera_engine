// V3.4 ω — streaming + per-stage failure isolation tests.
//
// Verifies that the new per-stage parallel streaming pipeline:
//   1. Parses cleanly when the stream emits valid JSON (chunked or whole)
//   2. Falls back to template when a stream errors or returns empty
//   3. Isolates failures: 1 stage failing does NOT contaminate the
//      other 2 stages in the same session (queue still has the others
//      as real questions)

import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_controller.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';
import 'package:fluera_engine/src/utils/ai_language_preference.dart';

import '../_fakes.dart';

ContentCluster _cluster(String id, {Offset centroid = Offset.zero}) {
  return ContentCluster(
    id: id,
    strokeIds: const [],
    bounds: Rect.fromCenter(center: centroid, width: 100, height: 100),
    centroid: centroid,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    installTempPathProvider();
    AiLanguagePreference.setForTests('it');
  });
  tearDown(AiLanguagePreference.resetForTests);

  group('V3.4 ω — per-stage stream parsing', () {
    test('Single-chunk valid JSON → question parsed cleanly', () async {
      final fake = FakeGeminiProvider()
        ..streamPerStageOverride = {
          'anchor': jsonEncode({
            'q': 'Cosa ti viene in mente per primo su forze e moto?',
            'h': ['Pensa a F=ma', 'Quale legge?', 'Newton prima legge'],
          }),
        };
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'forze e moto'},
      );

      expect(ctrl.session, isNotNull);
      expect(ctrl.session!.queue.length, greaterThanOrEqualTo(1));
      final firstQ = ctrl.session!.queue.first.text;
      expect(firstQ.toLowerCase(), contains('forze'),
          reason: 'Streamed question must include cluster concept word');
    });

    test('Empty stream → falls back to template (no crash)', () async {
      // No streamPerStageOverride + empty socraticBatchResponse → fake
      // yields empty `{q:"",h:[]}` → controller filters it → fallback.
      final fake = FakeGeminiProvider()..socraticBatchResponse = '{"clusters":[]}';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'topic-1'},
      );

      // Fallback path produces N questions where N = batchPlan size.
      expect(ctrl.session, isNotNull);
      expect(ctrl.session!.queue.length, greaterThan(0));
      expect(ctrl.usedFallback, isTrue,
          reason: 'Empty AI response must trip the fallback flag');
    });
  });

  group('V3.4 ω — per-stage failure isolation', () {
    test('1 stage succeeds, others fail → succeeded stage still in queue',
        () async {
      // anchor returns valid JSON; other stages fall through to legacy
      // dispatch which yields empty (since socraticBatchResponse is
      // empty clusters by default).
      final fake = FakeGeminiProvider()
        ..streamPerStageOverride = {
          'anchor': jsonEncode({
            'q': 'Cosa ricordi della prima legge di Newton?',
            'h': ['hint1', 'hint2', 'hint3'],
          }),
        };
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 2},
        provider: fake,
        clusterTexts: const {'c1': 'prima legge di Newton'},
      );

      // The anchor question must be present in the queue (failure
      // isolation: succeeded stages survive even when peers fail).
      final queueTexts =
          ctrl.session!.queue.map((q) => q.text.toLowerCase()).toList();
      expect(queueTexts.any((t) => t.contains('prima legge')), isTrue,
          reason: 'Anchor success must survive in queue regardless of '
              'other stages failing → failure isolation');
    });

    test('streamForStageCalls records each stage invocation', () async {
      final fake = FakeGeminiProvider()
        ..streamPerStageOverride = {
          'anchor': '{"q":"Anchor Q topic-1","h":["a","b","c"]}',
          'elaboration': '{"q":"Elaboration Q topic-1","h":["a","b","c"]}',
          'counterfactual': '{"q":"Counterfactual Q topic-1","h":["a","b","c"]}',
        };
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'topic-1'},
      );

      // At least one streamForStage call fired.
      expect(fake.streamForStageCalls, isNotEmpty);
      // The langCode in every call must be the active preference.
      for (final c in fake.streamForStageCalls) {
        expect(c.langCode, 'it');
      }
    });
  });

  group('V3.4 ω — stream payload contract', () {
    test('payload contains DISCIPLINA block when IT', () async {
      final fake = FakeGeminiProvider()
        ..streamPerStageOverride = {
          'anchor': '{"q":"Cosa intendi per moto rettilineo uniforme?","h":["a","b","c"]}',
        };
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'forza accelerazione massa F=ma'},
      );

      expect(fake.streamForStageCalls, isNotEmpty);
      final firstPayload = fake.streamForStageCalls.first.payload;
      expect(firstPayload, contains('DISCIPLINA:'),
          reason: 'IT payload must inject discipline hints block');
      expect(firstPayload, contains('CLUSTER'),
          reason: 'Payload must include CLUSTER section');
    });
  });
}
