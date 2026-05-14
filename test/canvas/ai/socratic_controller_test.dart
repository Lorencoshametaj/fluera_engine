// ============================================================================
// 🔶 SOCRATIC CONTROLLER — Lifecycle + ZPD + breadcrumb + history tests.
//
// Locks the contract before refactoring towards Atlas-Exam parity (history
// persistence, checkpoint, avoid-list). The controller has a non-trivial
// state machine — without these tests, any refactor downstream silently
// breaks ZPD adaptation, hypercorrection detection, and breadcrumb gating.
// ============================================================================

import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/telemetry_recorder.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_controller.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_model.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';
import 'package:fluera_engine/src/utils/ai_language_preference.dart';
import '_fakes.dart';

ContentCluster _cluster(String id, {Offset centroid = Offset.zero}) {
  return ContentCluster(
    id: id,
    strokeIds: const [],
    bounds: Rect.fromCenter(center: centroid, width: 100, height: 100),
    centroid: centroid,
  );
}

/// JSON that yields N questions with a deterministic prefix + 3 breadcrumbs.
/// The "topic-N" suffix in the question text matches the cluster topic
/// passed to `activate()` so the B4 specificity validator (added in the
/// 2026-05-10 quality sprint) doesn't reject the question for lacking
/// a concept-word overlap with the cluster. The "Cosa" opener ensures
/// the question passes the G4 chain-of-verification (S3.A 2026-05-12)
/// which requires an interrogative word.
String _socraticJson(int n) {
  final clusters = List.generate(
    n,
    (i) => '{"q":"Cosa collega la domanda ${i + 1} a topic-${i} relazione?",'
        '"h":["Indizio A","Indizio B","Indizio C"]}',
  ).join(',');
  return '{"clusters":[$clusters]}';
}

void main() {
  // 🛡️ Sprint 2: most fixtures use IT cluster text + IT questions.
  // Force AI target='it' so the consolidated validator doesn't flag
  // them as language drift on the default-EN test locale.
  setUp(() {
    AiLanguagePreference.setForTests('it');
  });
  tearDown(() {
    AiLanguagePreference.resetForTests();
  });

  group('SocraticController.activate', () {
    test('Happy path — creates session with N questions for N clusters', () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = _socraticJson(3);
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1'), _cluster('c2'), _cluster('c3')],
        recallData: const {'c1': 2, 'c2': 3, 'c3': 4},
        provider: fake,
        clusterTexts: const {'c1': 'topic-1', 'c2': 'topic-2', 'c3': 'topic-3'},
      );

      expect(ctrl.isActive, isTrue);
      expect(ctrl.session, isNotNull);
      expect(ctrl.session!.queue.length, 3);
      expect(ctrl.usedFallback, isFalse);
    });

    test('Device 2026-05-10: strips meta-preamble from generated question',
        () async {
      // The model occasionally emits q="Il comando chiede di generare
      // una domanda sulla prima legge di Newton. Cosa manca per
      // collegare la prima legge al concetto di 'corpo a riposo'?"
      // The first sentence is task-echo. The sanitizer must strip it.
      final polluted =
          '{"clusters":[{"q":"Il comando chiede di generare una domanda '
          'sulla prima legge di Newton. Cosa manca per collegare la prima '
          'legge al concetto di corpo a riposo e all\\u0027assenza di '
          'forza netta?","h":["Indizio A","Indizio B","Indizio C"]}]}';
      final fake = FakeGeminiProvider()..socraticBatchResponse = polluted;
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 1},
        provider: fake,
        clusterTexts: const {'c1': 'prima legge Newton corpo riposo'},
      );

      final q = ctrl.session!.queue[0].text;
      expect(q, contains('Cosa manca'),
          reason: 'real question must survive');
      expect(q.toLowerCase(), isNot(contains('il comando chiede')),
          reason: 'meta-preamble must be stripped');
      expect(q.toLowerCase(), isNot(contains('generare una domanda')),
          reason: 'task-echo must be stripped');
    });

    test('Empty clusters → no-op (controller stays inactive)', () async {
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: const [],
        recallData: const {},
        provider: FakeGeminiProvider(),
      );

      expect(ctrl.isActive, isFalse);
      expect(ctrl.session, isNull);
    });

    test('AI failure → falls back to built-in fallback questions', () async {
      // Empty JSON → controller's fallback path activates. 2026-05-12
      // pedagogical redesign: session size = ceil(N*1.5) clamped [3,8].
      // 2 clusters → 3 stages (anchor / elaboration / counterfactual).
      // Each cluster topic appears in at least one question.
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1'), _cluster('c2')],
        recallData: const {'c1': 1, 'c2': 5},
        provider: fake,
        clusterTexts: const {'c1': 'lacuna-topic', 'c2': 'transfer-topic'},
      );

      expect(ctrl.isActive, isTrue);
      expect(ctrl.usedFallback, isTrue);
      expect(ctrl.session!.queue.length, 3);
      // Each cluster topic must appear in at least one question text.
      final allText = ctrl.session!.queue.map((q) => q.text).join(' ');
      expect(allText, contains('lacuna-topic'));
      expect(allText, contains('transfer-topic'));
    });

    test('Recall level maps to question type (lacuna / challenge / depth / transfer)', () async {
      // 2026-05-12 pedagogical redesign: 4 clusters → ceil(4*1.5)=6 questions.
      // Each cluster's TYPE is still derived from its recall (legacy FSRS
      // mapping preserved), but slot allocation is stage-based.
      final fake = FakeGeminiProvider()..socraticBatchResponse = _socraticJson(6);
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1'), _cluster('c2'), _cluster('c3'), _cluster('c4')],
        recallData: const {'c1': 1, 'c2': 3, 'c3': 4, 'c4': 5},
        provider: fake,
        clusterTexts: const {'c1': 'a', 'c2': 'b', 'c3': 'c', 'c4': 'd'},
      );

      expect(ctrl.session!.queue.length, 6);
      // Each question's type matches the recall of its assigned cluster.
      for (final q in ctrl.session!.queue) {
        final expectedType = switch (q.clusterId) {
          'c1' => SocraticQuestionType.lacuna,
          'c2' => SocraticQuestionType.challenge,
          'c3' => SocraticQuestionType.depth,
          'c4' => SocraticQuestionType.transfer,
          _ => SocraticQuestionType.challenge,
        };
        expect(q.type, expectedType,
            reason: 'cluster ${q.clusterId} should map to ${expectedType.name}');
      }
    });

    test('V2 multi-turn: setConfidence(autoChooseAnswer:false) → awaitingTurnMode',
        () async {
      final ctrl = await _activatedController(qCount: 1);
      addTearDown(ctrl.dispose);

      ctrl.setConfidence(3, autoChooseAnswer: false);

      expect(ctrl.session!.activeQuestion!.status,
          SocraticBubbleStatus.awaitingTurnMode);
    });

    test('V2 multi-turn: chooseTurnMode(sketch: false) → awaitingAnswer (legacy path)',
        () async {
      final ctrl = await _activatedController(qCount: 1);
      addTearDown(ctrl.dispose);

      ctrl.setConfidence(3, autoChooseAnswer: false);
      ctrl.chooseTurnMode(sketch: false);

      expect(ctrl.session!.activeQuestion!.status,
          SocraticBubbleStatus.awaitingAnswer);
      // Legacy recordResult still works.
      ctrl.recordResult(recalled: true);
      expect(ctrl.session!.queue[0].status,
          SocraticBubbleStatus.correctLowConf);
    });

    test('V2 multi-turn: chooseTurnMode(sketch: true) → awaitingSketch + seeds initial turn',
        () async {
      final ctrl = await _activatedController(qCount: 1);
      addTearDown(ctrl.dispose);

      ctrl.setConfidence(3, autoChooseAnswer: false);
      ctrl.chooseTurnMode(sketch: true);

      expect(ctrl.session!.activeQuestion!.status,
          SocraticBubbleStatus.awaitingSketch);
      expect(ctrl.session!.activeQuestion!.turns, hasLength(1));
      expect(ctrl.session!.activeQuestion!.turns[0].role,
          SocraticTurnRole.initial);
    });

    test('V2 multi-turn: submitSketch fires follow-up and emits next turn',
        () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = _socraticJson(1);
      fake.socraticFollowUpOverride = (role, prior, sketch) => (
            question: 'Hai accennato a inerzia. E se la massa varia nel tempo?',
            isAporetic: false,
          );
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);
      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'inerzia'},
      );

      ctrl.setConfidence(3, autoChooseAnswer: false);
      ctrl.chooseTurnMode(sketch: true);
      await ctrl.submitSketch(
        sketchOcr: 'inerzia forza esterna',
        provider: fake,
        clusterText: 'inerzia',
      );

      final q = ctrl.session!.activeQuestion!;
      expect(q.turns, hasLength(2));
      expect(q.turns[0].sketchOcr, 'inerzia forza esterna');
      expect(q.turns[1].role, SocraticTurnRole.followUp);
      expect(q.turns[1].question, contains('inerzia'));
      expect(q.status, SocraticBubbleStatus.awaitingTurnMode);
      expect(fake.socraticFollowUpCalls, 1);
    });

    test('V2 multi-turn: 2nd submitSketch emits aporetic turn + awaitingReflection',
        () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = _socraticJson(1);
      var callCount = 0;
      fake.socraticFollowUpOverride = (role, prior, sketch) {
        callCount++;
        return (
          question: callCount == 1 ? 'Follow-up question' : 'Aporetic close. Tienila in testa.',
          isAporetic: callCount == 2,
        );
      };
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);
      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'inerzia'},
      );

      ctrl.setConfidence(3, autoChooseAnswer: false);
      ctrl.chooseTurnMode(sketch: true);
      await ctrl.submitSketch(
        sketchOcr: 'sketch 1',
        provider: fake,
        clusterText: 'inerzia',
      );
      // After first follow-up, status is awaitingTurnMode again.
      ctrl.chooseTurnMode(sketch: true);
      await ctrl.submitSketch(
        sketchOcr: 'sketch 2',
        provider: fake,
        clusterText: 'inerzia',
      );

      final q = ctrl.session!.activeQuestion!;
      expect(q.turns, hasLength(3));
      expect(q.turns[2].role, SocraticTurnRole.aporetic);
      expect(q.isAporeticClosed, isTrue);
      expect(q.status, SocraticBubbleStatus.awaitingReflection);
      expect(fake.socraticFollowUpCalls, 2);
    });

    test('V2 multi-turn: recordReflection sets finalReflection + resolves',
        () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = _socraticJson(1);
      fake.socraticFollowUpOverride = (role, prior, sketch) => (
            question: 'Aporetic. Tienila in testa.',
            isAporetic: true,
          );
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);
      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'inerzia'},
      );

      ctrl.setConfidence(3, autoChooseAnswer: false);
      ctrl.chooseTurnMode(sketch: true);
      await ctrl.submitSketch(
        sketchOcr: 'sketch 1',
        provider: fake,
        clusterText: 'inerzia',
      );
      ctrl.chooseTurnMode(sketch: true);
      await ctrl.submitSketch(
        sketchOcr: 'sketch 2',
        provider: fake,
        clusterText: 'inerzia',
      );

      ctrl.recordReflection(SocraticReflectionOutcome.uncertain);

      final q = ctrl.session!.queue[0];
      expect(q.finalReflection, SocraticReflectionOutcome.uncertain);
      expect(q.isResolved, isTrue);
    });

    test(
        'V2 multi-turn: low-quality sketch OCR skips AI call, uses cluster fallback',
        () async {
      // Device 2026-05-10: MyScript on sparse sketch returned "CA" /
      // "forever" — AI cited them verbatim ("Hai menzionato 'CA'…").
      // The quality gate must intercept and use the type-aware fallback.
      final fake = FakeGeminiProvider()..socraticBatchResponse = _socraticJson(1);
      // Override would be CALLED if quality gate didn't fire — we
      // verify it does NOT fire (callCount stays 0).
      fake.socraticFollowUpOverride = (role, prior, sketch) => (
            question: 'AI MUST NOT be called for "CA"',
            isAporetic: false,
          );
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);
      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'prima legge Newton inerzia'},
      );

      ctrl.setConfidence(3, autoChooseAnswer: false);
      ctrl.chooseTurnMode(sketch: true);
      // Garbled OCR: single short token (the device case "CA").
      await ctrl.submitSketch(
        sketchOcr: 'CA',
        provider: fake,
        clusterText: 'prima legge Newton inerzia',
      );

      // Quality gate fired → no AI call.
      expect(fake.socraticFollowUpCalls, 0,
          reason: 'low-quality OCR must not reach the AI provider');
      // Question generated from cluster-anchored fallback (does not
      // cite "CA" as a standalone word). Use word-boundary regex —
      // 'ca' as substring is fine ("mancano" etc.).
      final lastTurn = ctrl.session!.activeQuestion!.turns.last;
      expect(
        RegExp(r'\bCA\b').hasMatch(lastTurn.question),
        isFalse,
        reason: 'fallback must NOT cite the garbled "CA" token as a word',
      );
      expect(lastTurn.question, isNot(contains("'CA'")),
          reason: 'fallback must NOT quote the garbled token');
    });

    test('V2 multi-turn: cancelSketch rolls back to awaitingTurnMode', () async {
      final ctrl = await _activatedController(qCount: 1);
      addTearDown(ctrl.dispose);

      ctrl.setConfidence(3, autoChooseAnswer: false);
      ctrl.chooseTurnMode(sketch: true);
      expect(ctrl.session!.activeQuestion!.status,
          SocraticBubbleStatus.awaitingSketch);

      ctrl.cancelSketch();
      expect(ctrl.session!.activeQuestion!.status,
          SocraticBubbleStatus.awaitingTurnMode);
    });

    test('V2 multi-turn: SocraticTurn JSON round-trip', () {
      final turn = SocraticTurn(
        index: 1,
        role: SocraticTurnRole.followUp,
        question: 'E se la massa varia nel tempo?',
        sketchOcr: 'inerzia forza',
        timestamp: DateTime(2026, 5, 10, 12, 0),
      );
      final restored = SocraticTurn.fromJson(turn.toJson());
      expect(restored.index, 1);
      expect(restored.role, SocraticTurnRole.followUp);
      expect(restored.question, 'E se la massa varia nel tempo?');
      expect(restored.sketchOcr, 'inerzia forza');
    });

    test(
        'FSRS-naive canvas (all recall=3) → round-robin types instead of all challenge',
        () async {
      // Device session 2026-05-10: 3 clusters with no SRS history all
      // collapsed to "challenge, challenge, challenge". After the fix
      // (typeMap round-robin assignment preserved through _buildBatchPlan)
      // the batch distributes types round-robin so the student sees
      // lacuna / challenge / depth phrasings even on a fresh canvas.
      // 2026-05-12 redesign: 3 clusters → ceil(3*1.5)=5 questions.
      final fake = FakeGeminiProvider()..socraticBatchResponse = _socraticJson(5);
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1'), _cluster('c2'), _cluster('c3')],
        recallData: const {'c1': 3, 'c2': 3, 'c3': 3},
        provider: fake,
        clusterTexts: const {'c1': 'a', 'c2': 'b', 'c3': 'c'},
      );

      final types = ctrl.session!.queue.map((q) => q.type).toSet();
      // At least three types should be distinct — no collapse to all-one.
      expect(types.length, greaterThanOrEqualTo(3),
          reason: 'FSRS-naive batches must spread types via round-robin');
    });
  });

  group('SocraticController.setConfidence', () {
    test('Transitions active → awaitingAnswer', () async {
      final ctrl = await _activatedController(qCount: 2);
      addTearDown(ctrl.dispose);

      ctrl.setConfidence(4);

      expect(ctrl.session!.activeQuestion!.confidence, 4);
      expect(ctrl.session!.activeQuestion!.status,
          SocraticBubbleStatus.awaitingAnswer);
    });

    test('Clamps level to [1..5]', () async {
      final ctrl = await _activatedController(qCount: 1);
      addTearDown(ctrl.dispose);

      ctrl.setConfidence(99);

      expect(ctrl.session!.activeQuestion!.confidence, 5);
    });

    test('Ignored when active question is already resolved', () async {
      final ctrl = await _activatedController(qCount: 2);
      addTearDown(ctrl.dispose);
      ctrl.setConfidence(3);
      ctrl.recordResult(recalled: true); // status → correctLowConf (resolved)

      ctrl.setConfidence(5); // should be ignored

      // Confidence stays at 3 from the recorded answer.
      expect(ctrl.session!.queue[0].confidence, 3);
    });
  });

  group('SocraticController.recordResult', () {
    test('Correct + confidence>=4 → status=correct (high)', () async {
      final ctrl = await _activatedController(qCount: 1);
      addTearDown(ctrl.dispose);
      ctrl.setConfidence(5);

      ctrl.recordResult(recalled: true);

      expect(ctrl.session!.queue[0].status, SocraticBubbleStatus.correct);
      expect(ctrl.session!.queue[0].isHypercorrection, isFalse);
      expect(ctrl.session!.totalCorrect, 1);
    });

    test('Correct + confidence<4 → status=correctLowConf', () async {
      final ctrl = await _activatedController(qCount: 1);
      addTearDown(ctrl.dispose);
      ctrl.setConfidence(2);

      ctrl.recordResult(recalled: true);

      expect(ctrl.session!.queue[0].status,
          SocraticBubbleStatus.correctLowConf);
    });

    test('Wrong + confidence>=4 → wrongHighConf + isHypercorrection=true', () async {
      final ctrl = await _activatedController(qCount: 1);
      addTearDown(ctrl.dispose);
      ctrl.setConfidence(5);

      ctrl.recordResult(recalled: false);

      expect(ctrl.session!.queue[0].status,
          SocraticBubbleStatus.wrongHighConf);
      expect(ctrl.session!.queue[0].isHypercorrection, isTrue);
      expect(ctrl.session!.totalHypercorrections, 1);
    });

    test('Wrong + confidence<4 → wrongLowConf, no hypercorrection', () async {
      final ctrl = await _activatedController(qCount: 1);
      addTearDown(ctrl.dispose);
      ctrl.setConfidence(2);

      ctrl.recordResult(recalled: false);

      expect(ctrl.session!.queue[0].status,
          SocraticBubbleStatus.wrongLowConf);
      expect(ctrl.session!.queue[0].isHypercorrection, isFalse);
    });
  });

  group('SocraticController — ZPD adaptation', () {
    test('3 consecutive correct → upgrades next question type', () async {
      // Build a session where every question starts as `lacuna` so we can
      // observe the upgrade. Recall=1 maps to lacuna for all 4 clusters.
      final ctrl = await _activatedController(qCount: 4, recall: 1);
      addTearDown(ctrl.dispose);

      // Three correct in a row.
      for (int i = 0; i < 3; i++) {
        ctrl.setConfidence(3);
        ctrl.recordResult(recalled: true);
        ctrl.next();
      }

      // The 4th question's type should now be upgraded from lacuna →
      // challenge (and the adapt fires after each result, so by the
      // 3rd correct, the 4th is upgraded).
      expect(ctrl.session!.queue[3].type,
          isNot(SocraticQuestionType.lacuna));
    });

    test('2 consecutive wrong → downgrades next question type', () async {
      // Start with all `transfer` questions (recall=5 maps to transfer)
      // so the downgrade is observable.
      final ctrl = await _activatedController(qCount: 4, recall: 5);
      addTearDown(ctrl.dispose);

      ctrl.setConfidence(2);
      ctrl.recordResult(recalled: false);
      ctrl.next();
      ctrl.setConfidence(2);
      ctrl.recordResult(recalled: false);

      // The 3rd question (next) should be downgraded from transfer → depth.
      expect(ctrl.session!.queue[2].type,
          isNot(SocraticQuestionType.transfer));
    });
  });

  group('SocraticController.requestBreadcrumb', () {
    test('Increments breadcrumbsUsed and returns text', () async {
      final ctrl = await _activatedController(qCount: 1);
      addTearDown(ctrl.dispose);

      final first = ctrl.requestBreadcrumb();
      expect(first, 'Indizio A');
      expect(ctrl.session!.activeQuestion!.breadcrumbsUsed, 1);

      final second = ctrl.requestBreadcrumb();
      expect(second, 'Indizio B');
      expect(ctrl.session!.activeQuestion!.breadcrumbsUsed, 2);
    });

    test('Returns null after 3 calls (cap)', () async {
      final ctrl = await _activatedController(qCount: 1);
      addTearDown(ctrl.dispose);

      ctrl.requestBreadcrumb();
      ctrl.requestBreadcrumb();
      ctrl.requestBreadcrumb();
      final fourth = ctrl.requestBreadcrumb();

      expect(fourth, isNull);
      expect(ctrl.session!.activeQuestion!.breadcrumbsUsed, 3);
    });

    test('canRequestBreadcrumb returns false when breadcrumbs empty', () async {
      // Fallback path produces empty breadcrumbs.
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);
      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 't'},
      );

      expect(ctrl.canRequestBreadcrumb, isFalse);
    });
  });

  group('SocraticController — navigation', () {
    test('skip → status=skipped, advances activeIndex', () async {
      final ctrl = await _activatedController(qCount: 2);
      addTearDown(ctrl.dispose);
      final firstId = ctrl.session!.queue[0].id;

      ctrl.skip();

      expect(ctrl.session!.queue[0].status, SocraticBubbleStatus.skipped);
      expect(ctrl.session!.totalSkipped, 1);
      // skip() calls next() internally — active should now be queue[1].
      expect(ctrl.session!.activeQuestion!.id, isNot(firstId));
    });

    test('next() skips already-resolved questions', () async {
      final ctrl = await _activatedController(qCount: 3);
      addTearDown(ctrl.dispose);

      // Manually mark q[1] as resolved (simulating a back-nav scenario).
      ctrl.session!.replaceQuestion(
        1,
        ctrl.session!.queue[1].copyWith(status: SocraticBubbleStatus.skipped),
      );

      // Resolve current (q[0]) and call next.
      ctrl.setConfidence(3);
      ctrl.recordResult(recalled: true);
      ctrl.next();

      // We jumped from q[0] over q[1] (already resolved) to q[2].
      expect(ctrl.session!.activeIndex, 2);
    });

    test('markBelowZPD → counter incremented, status set', () async {
      final ctrl = await _activatedController(qCount: 1);
      addTearDown(ctrl.dispose);

      ctrl.markBelowZPD();

      expect(ctrl.session!.queue[0].status, SocraticBubbleStatus.belowZPD);
      expect(ctrl.session!.totalBelowZPD, 1);
    });
  });

  group('SocraticController — session lifecycle', () {
    test('endSession marks all unresolved questions skipped', () async {
      final ctrl = await _activatedController(qCount: 3);
      addTearDown(ctrl.dispose);

      ctrl.endSession();

      for (final q in ctrl.session!.queue) {
        expect(q.status, SocraticBubbleStatus.skipped);
      }
    });

    test('dismiss resets state to inactive', () async {
      final ctrl = await _activatedController(qCount: 2);
      addTearDown(ctrl.dispose);

      ctrl.dismiss();

      expect(ctrl.isActive, isFalse);
      expect(ctrl.session, isNull);
    });

    test('hypercorrectionClusterIds returns only flagged clusters', () async {
      final ctrl = await _activatedController(qCount: 2);
      addTearDown(ctrl.dispose);
      final c0Id = ctrl.session!.queue[0].clusterId;

      // Q1: hypercorrection (high conf + wrong).
      ctrl.setConfidence(5);
      ctrl.recordResult(recalled: false);
      ctrl.next();
      // Q2: correct (no flag).
      ctrl.setConfidence(3);
      ctrl.recordResult(recalled: true);

      expect(ctrl.hypercorrectionClusterIds, {c0Id});
    });
  });

  group('SocraticController — history persistence', () {
    late Directory tempDir;

    setUp(() {
      tempDir = installTempPathProvider();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('dismiss writes a history record with one entry', () async {
      final ctrl = await _activatedController(qCount: 2);
      // Resolve at least one question so dismiss persists.
      ctrl.setConfidence(3);
      ctrl.recordResult(recalled: true);

      ctrl.dismiss();
      // Dismiss persists asynchronously — let the unawaited write settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final file = File('${tempDir.path}/fluera_socratic_history.json');
      expect(file.existsSync(), isTrue);
      final loaded = await SocraticController.loadHistoryStandalone();
      expect(loaded, hasLength(1));
      expect(loaded.first.totalQuestions, 2);
      expect(loaded.first.correctCount, 1);
    });

    test('dismiss does NOT write when no question was resolved', () async {
      final ctrl = await _activatedController(qCount: 2);
      // Don't resolve anything — dismiss as soon as session starts.
      ctrl.dismiss();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final file = File('${tempDir.path}/fluera_socratic_history.json');
      expect(file.existsSync(), isFalse);
    });

    test('History caps at 50 records', () async {
      // Pre-seed 50 records, then complete a session → expect oldest dropped.
      final ctrl = await _activatedController(qCount: 1);
      // Use _saveHistory indirectly via dismiss in a loop — fastest path
      // is to just dismiss-then-reactivate 51 times. To keep the test
      // fast, we simulate by writing 50 valid records to disk before
      // running the controller flow.
      final priorRecords = List.generate(50, (i) {
        return {
          'sessionId': 'pre_$i',
          'startedAt': DateTime(2024, 1, 1).toIso8601String(),
          'completedAt': DateTime(2024, 1, 1, 0, 5).toIso8601String(),
          'totalQuestions': 1,
          'correctCount': 1,
          'wrongCount': 0,
          'skippedCount': 0,
          'hypercorrectionCount': 0,
          'clusterIds': const ['c0'],
          'hypercorrectionClusterIds': const [],
          'breadcrumbsUsed': 0,
          'avgConfidence': 3.0,
          'questions': const [],
          'schemaVersion': 1,
        };
      });
      final file = File('${tempDir.path}/fluera_socratic_history.json');
      file.writeAsStringSync(
        '[${priorRecords.map((r) => '''{"sessionId":"${r['sessionId']}","startedAt":"${r['startedAt']}","completedAt":"${r['completedAt']}","totalQuestions":1,"correctCount":1,"wrongCount":0,"skippedCount":0,"hypercorrectionCount":0,"clusterIds":["c0"],"hypercorrectionClusterIds":[],"breadcrumbsUsed":0,"avgConfidence":3.0,"questions":[],"schemaVersion":1}''').join(',')}]',
      );

      // Reload + dismiss the live session.
      final ctrl2 = await _activatedController(qCount: 1);
      // Wait for _loadHistory to finish.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      ctrl2.setConfidence(3);
      ctrl2.recordResult(recalled: true);
      ctrl2.dismiss();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final loaded = await SocraticController.loadHistoryStandalone();
      expect(loaded, hasLength(50)); // cap respected
      // Newest record must be the just-dismissed live session.
      expect(loaded.first.sessionId, isNot(startsWith('pre_')));

      // Cleanup the original ctrl too.
      ctrl.dismiss();
    });

    test('loadHistoryStandalone reads the file written by an earlier session',
        () async {
      final ctrl = await _activatedController(qCount: 1);
      ctrl.setConfidence(4);
      ctrl.recordResult(recalled: true);
      ctrl.dismiss();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final loaded = await SocraticController.loadHistoryStandalone();
      expect(loaded, hasLength(1));
      expect(loaded.first.correctCount, 1);
      expect(loaded.first.avgConfidence, 4.0);
    });
  });

  group('SocraticController — checkpoint (crash recovery)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = installTempPathProvider();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('mutation triggers a checkpoint file write', () async {
      final ctrl = await _activatedController(qCount: 2);
      addTearDown(ctrl.dispose);

      ctrl.setConfidence(3); // unawaited(_persistCheckpoint())
      // Allow the unawaited write to settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final file = File('${tempDir.path}/fluera_socratic_checkpoint.json');
      expect(file.existsSync(), isTrue);
    });

    test('peekCheckpoint returns null when no checkpoint exists', () async {
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);
      // _loadHistory async call needs a beat to settle.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final preview = await ctrl.peekCheckpoint();
      expect(preview, isNull);
    });

    test('Mid-session crash → fresh controller resumes', () async {
      // 1. First controller: start, answer Q1, abandon (no dispose call →
      //    simulates the OS killing the app mid-flight).
      final ctrlA = await _activatedController(qCount: 3);
      ctrlA.setConfidence(4);
      ctrlA.recordResult(recalled: true);
      ctrlA.next();
      // Wait for the unawaited checkpoint writes to flush.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // No dispose() — checkpoint stays on disk.

      // 2. Second controller: peek + resume.
      final ctrlB = SocraticController();
      addTearDown(ctrlB.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final preview = await ctrlB.peekCheckpoint();
      expect(preview, isNotNull);
      expect(preview!.totalQuestions, 3);
      expect(preview.resolvedCount, 1);

      final ok = await ctrlB.resumeFromCheckpoint();
      expect(ok, isTrue);
      expect(ctrlB.session, isNotNull);
      expect(ctrlB.session!.queue.length, 3);
      // The resolved question id matches Q1 (first in queue) — and its
      // confidence + status survived the round-trip.
      final resolved =
          ctrlB.session!.queue.firstWhere((q) => q.isResolved);
      expect(resolved.confidence, 4);
      expect(resolved.status, SocraticBubbleStatus.correct);
    });

    test('discardCheckpoint deletes the file', () async {
      final ctrl = await _activatedController(qCount: 1);
      ctrl.setConfidence(3);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final file = File('${tempDir.path}/fluera_socratic_checkpoint.json');
      expect(file.existsSync(), isTrue);

      await ctrl.discardCheckpoint();

      expect(file.existsSync(), isFalse);
      ctrl.dispose();
    });

    test('dismiss deletes the checkpoint after persisting history', () async {
      final ctrl = await _activatedController(qCount: 1);
      ctrl.setConfidence(3);
      ctrl.recordResult(recalled: true);
      // Checkpoint exists at this point.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final file = File('${tempDir.path}/fluera_socratic_checkpoint.json');
      expect(file.existsSync(), isTrue);

      ctrl.dismiss();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // dismiss → save history + delete checkpoint.
      expect(file.existsSync(), isFalse);
      final hist = await SocraticController.loadHistoryStandalone();
      expect(hist, hasLength(1));
    });
  });

  group('SocraticController — avoid-list ring buffer', () {
    test('Second activation on same cluster passes recent questions to AI',
        () async {
      installTempPathProvider();
      final fake = FakeGeminiProvider()..socraticBatchResponse = _socraticJson(1);
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      // First session — no avoid list yet, run + dismiss.
      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'topic-1'},
      );
      // The 1st AI call must have been with no AVOID block in payload.
      // V3.4 ω: avoid list lives INSIDE the per-stage payload string
      // (was a separate `avoidPrompts` arg in V3.3 batch). Check the
      // payload doesn't contain the AVOID marker.
      final firstPayload = fake.streamForStageCalls.last.payload;
      expect(firstPayload, isNot(contains('AVOID THESE RECENTLY-ASKED')));
      ctrl.setConfidence(3);
      ctrl.recordResult(recalled: true);
      ctrl.dismiss();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Second session — same cluster. Avoid list should now contain
      // the question text from the first session, embedded in the
      // per-stage payload.
      fake.resetStreamDispatchCursor();
      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'topic-1'},
      );

      final secondPayload = fake.streamForStageCalls.last.payload;
      expect(secondPayload, contains('AVOID THESE RECENTLY-ASKED'));
      expect(secondPayload, contains('topic-0'));
    });
  });

  group('SocraticController — B4 specificity validator', () {
    test('Generic question (no concept overlap) → swapped for type-aware fallback',
        () async {
      // The model returns a question that doesn't mention the cluster
      // topic at all — the B4 validator must reject + fall back.
      // Force target=IT so B4 runs (cross-lang skip would otherwise
      // bypass it for IT source on default-EN test locale).
      AiLanguagePreference.setForTests('it');
      addTearDown(AiLanguagePreference.resetForTests);
      final fake = FakeGeminiProvider()
        ..socraticBatchResponse =
            '{"clusters":[{"q":"Cosa puoi spiegare con le tue parole?","h":["A","B","C"]}]}';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 5}, // → transfer
        provider: fake,
        clusterTexts: const {'c1': 'leve di Archimede'},
      );

      final q = ctrl.session!.queue.first.text;
      // Original generic question must NOT survive — it had no overlap
      // with "leve di Archimede". The transfer-flavored fallback names
      // "Archimede" or pushes to another discipline.
      expect(q, isNot(contains('cosa puoi spiegare')));
      expect(q.toLowerCase(), contains('archimede'));
    });

    test('Specific question mentioning cluster concept → preserved as-is',
        () async {
      final fake = FakeGeminiProvider()
        ..socraticBatchResponse =
            '{"clusters":[{"q":"Cosa connette il principio di inerzia all\'assenza di forza netta?","h":["A","B","C"]}]}';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 1}, // → lacuna
        provider: fake,
        clusterTexts: const {'c1': 'Prima legge di Newton inerzia'},
      );

      // "inerzia" overlaps between question and cluster → kept verbatim.
      final q = ctrl.session!.queue.first.text;
      expect(q, contains('inerzia'));
    });

    test('Device 2026-05-12: IT question with EN label → accepted via OCR pool',
        () async {
      // Repro of device log: Atlas generated label "Newton's Laws" (EN) on
      // Italian OCR. The Italian question mentions "newton" + "legge" +
      // "corpo" — overlaps with the raw OCR pool. Pre-fix this was
      // rejected for "no concept overlap with 'Newtons Laws'" (label-only).
      final fake = FakeGeminiProvider()
        ..socraticBatchResponse =
            '{"clusters":[{"q":"Cosa intendi quando dici che un corpo a riposo rimane a riposo secondo la prima legge di Newton?","h":["A","B","C"]}]}';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 1},
        provider: fake,
        clusterTexts: const {
          // Raw OCR (Italian) — what _displayLabelForCluster falls back to
          // when no AI title is cached. Contains "legge", "newton", "corpo",
          // "riposo" — all overlap with the question.
          'c1': 'Leggi di Newton prima corpo a riposo seconda legge',
        },
      );

      final q = ctrl.session!.queue.first.text;
      // Question must survive B4 — it mentions cluster concepts via OCR.
      expect(q, contains('Newton'));
      expect(q, contains('legge'));
      expect(q, isNot(contains('"Newtons Laws"')),
          reason: 'fallback-for-cluster template would substitute the EN label '
              'in — the original IT question must survive B4 instead.');
    });

    test('Cross-language session: IT source + EN device locale → '
        'EN question is LEGITIMATE (no drift, no B4 reject)', () async {
      // Override the file-level setUp (which forces 'it') so this
      // test can verify the cross-language path.
      AiLanguagePreference.setForTests('en');
      // 2026-05-12 architectural change: drift detection now compares
      // against the device target language, NOT the source language.
      // When student notes are in language A but device locale targets
      // language B, the model legitimately generates in language B —
      // this is NOT drift. B4 specificity is also skipped in this
      // cross-language mode (lexical overlap is zero by design).
      //
      // The Fake provider's `validateSocraticQuestion` returns 1.0 so
      // G4 is bypassed in unit tests. The behavior under test here is
      // that the EN question survives unchanged through B4 (cross-lang
      // skip) and is NOT replaced by fallback.
      final fake = FakeGeminiProvider()
        ..socraticBatchResponse =
            '{"clusters":[{"q":"Imagine an astronaut in deep space gives a small object a push. If it were true that motion requires a continuous force, what would happen?","h":["A","B","C"]}]}';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 1},
        provider: fake,
        clusterTexts: const {
          'c1': 'Leggi di Newton prima corpo a riposo seconda legge',
        },
      );

      final q = ctrl.session!.queue.first.text;
      // EN question must survive — cross-language session is legitimate
      // (device locale default in tests is 'en', source is IT).
      expect(q.toLowerCase(), contains('imagine'),
          reason: 'Cross-lang IT-source + EN-target session lets EN '
              'question through (B4 skipped, G4 stubbed by fake).');
    });
  });

  // ── Sprint F.3 (2026-05-13 PM) — Quiz-me auto-recycle regression ─────────
  // Bug: after `session.isComplete=true`, pressing "Quiz me" again was a
  // silent no-op because `_isActive=true` lingered (dismiss is explicit).
  // Fix: showSocraticSetup auto-dismisses complete-but-active sessions
  // before starting fresh. This test locks the contract: simulating that
  // flow (manual dismiss-then-activate when session is complete) produces
  // a new session.
  group('SocraticController — Quiz-me auto-recycle (Sprint F.3)', () {
    test('Activating twice after session complete → 2 distinct sessions',
        () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = _socraticJson(3);
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      // Session 1: activate + resolve every question to mark complete.
      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'topic-1'},
      );
      final firstSessionStart = ctrl.session?.queue.first.id;
      // Resolve all questions in the queue (batch plan may inflate 1 cluster
      // to 3 stages — application/elaboration/counterfactual).
      while (!ctrl.isComplete && ctrl.session != null) {
        ctrl.setConfidence(3);
        ctrl.recordResult(recalled: true);
      }
      expect(ctrl.isComplete, isTrue,
          reason: 'Session must be complete after resolving every question');
      expect(ctrl.isActive, isTrue,
          reason: 'isActive lingers until dismiss() is called');

      // Simulate the showSocraticSetup auto-recycle: if isActive AND
      // isComplete, dismiss before reactivating.
      if (ctrl.isActive && ctrl.isComplete) {
        ctrl.dismiss();
      }
      expect(ctrl.isActive, isFalse,
          reason: 'dismiss() must transition isActive to false');

      // Session 2: activate again.
      fake.resetStreamDispatchCursor();
      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'topic-1'},
      );
      expect(ctrl.session, isNotNull);
      expect(ctrl.isActive, isTrue,
          reason: 'New session must be active');
      expect(ctrl.session!.queue, isNotEmpty);
      // The new session must have a different question id (timestamp-based)
      // than the first session's question.
      final secondSessionStart = ctrl.session?.queue.first.id;
      expect(secondSessionStart, isNotNull);
      expect(secondSessionStart, isNot(equals(firstSessionStart)),
          reason: 'Quiz-me cycle must produce a NEW session, not reuse the old');
    });
  });

  // ── Sprint F.3 (2026-05-13 PM) — Retry-on-truncated stream ───────────────
  // Bug device 2026-05-13 PM: stream returned 226 chars then cut mid-string
  // (no closing `}`, finishReason=null). Original retry-on-tiny threshold
  // was `< 80 chars` only — 226 chars passed but JSON was incomplete. Fix:
  // retry trigger now uses (buffer < 80 OR buffer doesn't end with `}`).
  group('SocraticController — Retry-on-unclosed JSON (Sprint F.3)', () {
    test('First call returns unclosed JSON, retry returns valid → recovered',
        () async {
      // FakeGeminiProvider streamForStage cycles through clusters in
      // socraticBatchResponse. We provide 2 entries: first is unclosed,
      // second is complete. Cycle: call 1 → unclosed, call 2 → recovered.
      const unclosed =
          '{"q":"Consider the hypothesis that a body in motion requires a '
          'continuous force to stay in motion. If a satellite of 100 kg, '
          'after engines off, moves at 7 km/s in a straight line through';
      const complete =
          '{"q":"Recovered question for cluster Newton","h":["a","b","c"]}';
      final fake = FakeGeminiProvider()
        ..socraticBatchResponse =
            '{"clusters":[$unclosed,$complete]}';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'topic-1'},
      );

      // The retry path should have fired (unclosed JSON triggers it),
      // and the recovered question should now be in the queue. We can
      // also verify multiple streamForStage calls were made.
      expect(fake.streamForStageCalls.length, greaterThanOrEqualTo(2),
          reason: 'streamForStage must be called twice: original + retry');
    });
  });

  // 🚩 Sprint F.5 (2026-05-13 PM): native-validation report path.
  // Pure telemetry, no state mutation. Verifies the event emits with
  // the expected properties so the aggregation dashboard stays stable.
  group('SocraticController — reportQuestion telemetry (Sprint F.5)', () {
    test('emits socratic_question_reported with lang/stage/type/reason',
        () {
      final telemetry = _ReportTelemetry();
      final ctrl = SocraticController(telemetry: telemetry);
      addTearDown(ctrl.dispose);
      const q = SocraticQuestion(
        id: 'q-test-1',
        clusterId: 'c1',
        anchorPosition: Offset(0, 0),
        type: SocraticQuestionType.lacuna,
        text: 'Quale legge governa il moto rettilineo uniforme?',
        stage: SocraticStage.anchor,
      );
      ctrl.reportQuestion(q, 'ko', reason: 'sounds machine-translated');
      expect(telemetry.events, hasLength(1));
      final e = telemetry.events.single;
      expect(e.event, 'socratic_question_reported');
      expect(e.props['lang_code'], 'ko');
      expect(e.props['stage'], 'anchor');
      expect(e.props['type'], 'lacuna');
      expect(e.props['cluster_id'], 'c1');
      expect(e.props['question_id'], 'q-test-1');
      expect(e.props['reason'], 'sounds machine-translated');
    });

    test('null/empty reason → recorded as "unspecified"', () {
      final telemetry = _ReportTelemetry();
      final ctrl = SocraticController(telemetry: telemetry);
      addTearDown(ctrl.dispose);
      const q = SocraticQuestion(
        id: 'q-test-2',
        clusterId: 'c2',
        anchorPosition: Offset(0, 0),
        type: SocraticQuestionType.challenge,
        text: 'short',
        stage: SocraticStage.elaboration,
      );
      ctrl.reportQuestion(q, 'ja');
      expect(telemetry.events.single.props['reason'], 'unspecified');
    });

    test('question_text + reason both capped at 500 chars', () {
      final telemetry = _ReportTelemetry();
      final ctrl = SocraticController(telemetry: telemetry);
      addTearDown(ctrl.dispose);
      final q = SocraticQuestion(
        id: 'q-long',
        clusterId: 'c3',
        anchorPosition: const Offset(0, 0),
        type: SocraticQuestionType.depth,
        text: 'x' * 800,
        stage: SocraticStage.counterfactual,
      );
      ctrl.reportQuestion(q, 'ar', reason: 'y' * 800);
      final p = telemetry.events.single.props;
      expect((p['question_text'] as String).length, 500);
      expect((p['reason'] as String).length, 500);
    });
  });
}

class _ReportTelemetry implements TelemetryRecorder {
  final List<({String event, Map<String, dynamic> props})> events = [];

  @override
  void logEvent(String eventType, {Map<String, dynamic>? properties}) {
    events.add((event: eventType, props: properties ?? const {}));
  }
}

// ─── helpers ─────────────────────────────────────────────────────────────────

/// Build a controller with [qCount] questions already activated. Each
/// cluster gets the same [recall] level (default 3 → challenge).
Future<SocraticController> _activatedController({
  required int qCount,
  int recall = 3,
}) async {
  final fake = FakeGeminiProvider()
    ..socraticBatchResponse = _socraticJson(qCount);
  final ctrl = SocraticController();
  await ctrl.activate(
    clusters: [for (int i = 0; i < qCount; i++) _cluster('c$i')],
    recallData: {for (int i = 0; i < qCount; i++) 'c$i': recall},
    provider: fake,
    clusterTexts: {for (int i = 0; i < qCount; i++) 'c$i': 'topic-$i'},
  );
  return ctrl;
}
