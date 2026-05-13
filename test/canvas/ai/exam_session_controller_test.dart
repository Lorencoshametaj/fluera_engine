import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/exam_session_controller.dart';
import 'package:fluera_engine/src/canvas/ai/exam_session_model.dart';
import 'package:fluera_engine/src/config/v1_feature_gate.dart';
import '_fakes.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = installTempPathProvider();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // Sanity: every test in this file assumes the gate is open. If the gate
  // ever flips back to false we want the failure to be loud, not silent.
  test('Sprint 3 prerequisite — V1FeatureGate.examSession is enabled', () {
    expect(V1FeatureGate.examSession, isTrue,
        reason: 'examSession gate must be true for the controller tests to exercise the real path');
  });

  group('ExamSessionController.startExam', () {
    test('Creates a session when provider returns questions', () async {
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1'),
        buildTestQuestion(id: 'q2'),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);

      await ctrl.startExam({'c1': 'sample text'}, count: 2);

      expect(ctrl.session, isNotNull);
      expect(ctrl.session!.questions.length, 2);
      expect(ctrl.error, isNull);
    });

    test('Sets an error when provider returns no questions', () async {
      final fake = FakeGeminiProvider(questionsToReturn: const []);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);

      await ctrl.startExam({'c1': 'text'}, count: 5);

      expect(ctrl.session, isNull);
      expect(ctrl.error, isNotNull);
    });

    test('Catches provider errors and reports them', () async {
      final fake = FakeGeminiProvider()
        ..throwOnNextGenerate = StateError('network down');
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);

      await ctrl.startExam({'c1': 'text'});

      expect(ctrl.session, isNull);
      expect(ctrl.error, isNotNull);
      expect(ctrl.error, contains('Errore'));
    });
  });

  group('ExamSessionController.submitChoiceAnswer', () {
    test('Correct answer marks result + tracks consecutive correct', () async {
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1', correctIndex: 1),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);
      await ctrl.startExam({'c1': 'x'});

      ctrl.submitChoiceAnswer(1);
      expect(ctrl.session!.questions[0].result, ExamAnswerResult.correct);
      expect(ctrl.session!.consecutiveCorrect, 1);
    });

    test('Wrong answer resets the consecutive-correct counter', () async {
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1', correctIndex: 0),
        buildTestQuestion(id: 'q2', correctIndex: 0),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);
      await ctrl.startExam({'c1': 'x'}, count: 2);

      ctrl.submitChoiceAnswer(0); // correct
      expect(ctrl.session!.consecutiveCorrect, 1);

      ctrl.nextQuestion();
      ctrl.submitChoiceAnswer(2); // wrong
      expect(ctrl.session!.consecutiveCorrect, 0);
      expect(ctrl.session!.questions[1].result, ExamAnswerResult.incorrect);
    });

    test('Cannot submit twice on the same question', () async {
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1', correctIndex: 1),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);
      await ctrl.startExam({'c1': 'x'});

      ctrl.submitChoiceAnswer(1); // correct
      ctrl.submitChoiceAnswer(0); // ignored — already answered
      expect(ctrl.session!.questions[0].result, ExamAnswerResult.correct);
    });
  });

  group('ExamSessionController.skipQuestion + setConfidence + saveElaboration', () {
    test('skipQuestion marks skipped + populates eval text', () async {
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1', correctIndex: 0),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);
      await ctrl.startExam({'c1': 'x'});

      ctrl.skipQuestion();
      expect(ctrl.session!.questions[0].result, ExamAnswerResult.skipped);
      expect(ctrl.currentEvalText, isNotEmpty);
    });

    test('setConfidence persists to the current question', () async {
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1'),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);
      await ctrl.startExam({'c1': 'x'});

      ctrl.setConfidence(4);
      expect(ctrl.session!.questions[0].confidenceLevel, 4);
    });

    test('saveElaboration persists to the current question', () async {
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1'),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);
      await ctrl.startExam({'c1': 'x'});

      ctrl.saveElaboration('La risposta giusta era X perché Y.');
      expect(ctrl.session!.questions[0].elaboration,
          'La risposta giusta era X perché Y.');
    });
  });

  group('ExamSessionController.nextQuestion + completion', () {
    test('Returns false when the session ends', () async {
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1', correctIndex: 0),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);
      await ctrl.startExam({'c1': 'x'});

      ctrl.submitChoiceAnswer(0);
      expect(ctrl.nextQuestion(), isFalse);
      expect(ctrl.session!.isComplete, isTrue);
    });

    test('Completion writes a history record + clears the checkpoint', () async {
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1', correctIndex: 0),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);
      await ctrl.startExam({'c1': 'x'});

      ctrl.submitChoiceAnswer(0);
      ctrl.nextQuestion();
      // history is written async via _saveHistory().
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final historyFile = File('${tempDir.path}/fluera_exam_history.json');
      final checkpointFile =
          File('${tempDir.path}/fluera_exam_checkpoint.json');
      expect(historyFile.existsSync(), isTrue);
      expect(checkpointFile.existsSync(), isFalse,
          reason: 'completion must remove the checkpoint');
    });
  });

  group('ExamSessionController — checkpoint resume', () {
    test('peekCheckpoint returns null when nothing is in flight', () async {
      final ctrl = ExamSessionController(provider: FakeGeminiProvider());
      addTearDown(ctrl.dispose);
      // Allow the constructor's _loadHistory / _loadLastExamMap to settle.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final preview = await ctrl.peekCheckpoint();
      expect(preview, isNull);
    });

    test('Mid-session crash → checkpoint can be restored on a fresh controller',
        () async {
      // 1. First controller: start an exam, answer the first question
      //    (whichever it is post-shuffle), drop without dispose.
      final fakeA = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1', correctIndex: 0),
        buildTestQuestion(id: 'q2', correctIndex: 1),
        buildTestQuestion(id: 'q3', correctIndex: 2),
      ]);
      final ctrlA = ExamSessionController(provider: fakeA);
      ctrlA.selectedTopicTitles = ['Anatomia'];
      await ctrlA.startExam({'c1': 'first cluster'}, count: 3);
      // Capture the post-shuffle Q at position 0 — that's what the
      // user is answering. ExamSession.ctor runs `_interleaveShuffle`
      // so position 0 isn't deterministic w.r.t. input order.
      final firstQ = ctrlA.session!.questions[0];
      ctrlA.submitChoiceAnswer(firstQ.correctChoiceIndex!); // always correct
      ctrlA.setConfidence(4);
      ctrlA.nextQuestion(); // advance to next — checkpoint should now exist
      // Wait a beat for the unawaited checkpoint write.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      ctrlA.dispose();

      // 2. Fresh controller: peek + resume.
      final fakeB = FakeGeminiProvider();
      final ctrlB = ExamSessionController(provider: fakeB);
      addTearDown(ctrlB.dispose);

      final preview = await ctrlB.peekCheckpoint();
      expect(preview, isNotNull);
      expect(preview!.totalQuestions, 3);
      expect(preview.currentIndex, 1);
      expect(preview.topicTitles, contains('Anatomia'));

      final ok = await ctrlB.resumeFromCheckpoint();
      expect(ok, isTrue);
      expect(ctrlB.session, isNotNull);
      expect(ctrlB.session!.currentIndex, 1);
      // The resumed session preserves the answered question's ID and
      // result regardless of which one the shuffle put first.
      final answered =
          ctrlB.session!.questions.firstWhere((q) => q.result != null);
      expect(answered.id, firstQ.id);
      expect(answered.result, ExamAnswerResult.correct);
      expect(answered.confidenceLevel, 4);
    });

    test('discardCheckpoint deletes the file', () async {
      // Write a sentinel checkpoint by simulating mid-session.
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1', correctIndex: 0),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      await ctrl.startExam({'c1': 'x'});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      ctrl.dispose();

      final cp = File('${tempDir.path}/fluera_exam_checkpoint.json');
      expect(cp.existsSync(), isTrue);

      final ctrl2 = ExamSessionController(provider: FakeGeminiProvider());
      addTearDown(ctrl2.dispose);
      await ctrl2.discardCheckpoint();

      expect(cp.existsSync(), isFalse);
    });

    test('Corrupted checkpoint is silently discarded on read', () async {
      final cp = File('${tempDir.path}/fluera_exam_checkpoint.json');
      cp.writeAsStringSync('{ this is not valid json');

      final ctrl = ExamSessionController(provider: FakeGeminiProvider());
      addTearDown(ctrl.dispose);
      final preview = await ctrl.peekCheckpoint();
      expect(preview, isNull);
      expect(cp.existsSync(), isFalse,
          reason: 'corrupted checkpoint must be cleaned up');
    });
  });

  group('ExamSessionController — anti-cramming', () {
    test('No prior exam → no warning', () async {
      final ctrl = ExamSessionController(provider: FakeGeminiProvider());
      addTearDown(ctrl.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final w = ctrl.recentExamFor(['c1', 'c2']);
      expect(w, isNull);
    });

    test('Recent exam on a cluster (< 4h) → returns warning', () async {
      // Pre-seed the per-cluster timestamp file with "30 minutes ago".
      final f = File('${tempDir.path}/fluera_exam_last_per_cluster.json');
      final recent =
          DateTime.now().subtract(const Duration(minutes: 30)).toIso8601String();
      f.writeAsStringSync(jsonEncode({'c1': recent}));

      final ctrl = ExamSessionController(provider: FakeGeminiProvider());
      addTearDown(ctrl.dispose);
      // Wait for the loader to finish.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final w = ctrl.recentExamFor(['c1']);
      expect(w, isNotNull);
      expect(w!.clusterId, 'c1');
      expect(w.sinceLastExam.inMinutes, inInclusiveRange(29, 31));
    });

    test('Old exam (> 4h) → no warning', () async {
      final f = File('${tempDir.path}/fluera_exam_last_per_cluster.json');
      final old =
          DateTime.now().subtract(const Duration(hours: 6)).toIso8601String();
      f.writeAsStringSync(jsonEncode({'c1': old}));

      final ctrl = ExamSessionController(provider: FakeGeminiProvider());
      addTearDown(ctrl.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(ctrl.recentExamFor(['c1']), isNull);
    });

    test('Completing an exam stamps every cluster + persists', () async {
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1', correctIndex: 0, clusterId: 'A'),
        buildTestQuestion(id: 'q2', correctIndex: 0, clusterId: 'B'),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);
      await ctrl.startExam({'A': 'a-text', 'B': 'b-text'}, count: 2);

      ctrl.submitChoiceAnswer(0); ctrl.nextQuestion();
      ctrl.submitChoiceAnswer(0); ctrl.nextQuestion();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // The map file must exist + contain both clusters.
      final mapFile =
          File('${tempDir.path}/fluera_exam_last_per_cluster.json');
      expect(mapFile.existsSync(), isTrue);
      final map = jsonDecode(mapFile.readAsStringSync()) as Map<String, dynamic>;
      expect(map.keys, containsAll(['A', 'B']));

      // And the in-memory check returns warnings now (just completed).
      expect(ctrl.recentExamFor(['A']), isNotNull);
      expect(ctrl.recentExamFor(['B']), isNotNull);
    });
  });

  group('ExamSessionController — atomic history', () {
    test('Writes happen atomically (.tmp → rename, never partial)', () async {
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1', correctIndex: 0),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);
      await ctrl.startExam({'c1': 'x'});
      ctrl.submitChoiceAnswer(0);
      ctrl.nextQuestion();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final hist = File('${tempDir.path}/fluera_exam_history.json');
      expect(hist.existsSync(), isTrue);
      final raw = hist.readAsStringSync();
      // Must be valid JSON — never partial.
      final parsed = jsonDecode(raw) as List<dynamic>;
      expect(parsed.length, 1);

      // No leftover .tmp file.
      expect(File('${hist.path}.tmp').existsSync(), isFalse);
    });

    test('Falls back to .bak when primary history file is corrupted', () async {
      // Pre-seed: a corrupted primary + a valid .bak.
      final hist = File('${tempDir.path}/fluera_exam_history.json');
      final bak = File('${hist.path}.bak');

      hist.writeAsStringSync('{this is not json[');
      final goodRecord = ExamHistoryRecord(
        sessionId: 'old',
        date: DateTime(2026, 5, 4),
        score: 0.7,
        totalQuestions: 5,
        correctCount: 3,
        durationSeconds: 200,
        topicTitles: const ['Backup topic'],
      );
      bak.writeAsStringSync(jsonEncode([goodRecord.toJson()]));

      final ctrl = ExamSessionController(provider: FakeGeminiProvider());
      addTearDown(ctrl.dispose);
      // Wait for _loadHistory to run.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(ctrl.history.length, 1);
      expect(ctrl.history.first.sessionId, 'old');
      expect(ctrl.history.first.topicTitles.first, 'Backup topic');
    });
  });

  group('ExamSessionController — review schedule (FSRS bridge)', () {
    test('partial → 1 day, incorrect → 3 days, skipped → 3 days, correct excluded',
        () async {
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1', correctIndex: 0, clusterId: 'A'),
        buildTestQuestion(id: 'q2', correctIndex: 0, clusterId: 'B'),
        buildTestQuestion(id: 'q3', correctIndex: 0, clusterId: 'C'),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);
      await ctrl.startExam(
        {'A': 'aaa concept-a', 'B': 'bbb concept-b', 'C': 'ccc concept-c'},
        count: 3,
      );
      // Force results without going through evaluator.
      ctrl.session!.questions[0].result = ExamAnswerResult.partial;
      ctrl.session!.questions[1].result = ExamAnswerResult.incorrect;
      ctrl.session!.questions[2].result = ExamAnswerResult.correct;

      final schedule = ctrl.reviewSchedule;
      // Correct cluster is excluded.
      expect(schedule.length, 2);
      // Partial → 1 day.
      expect(
        schedule.values.where((d) => d == const Duration(days: 1)).length,
        1,
      );
      // Incorrect → 3 days.
      expect(
        schedule.values.where((d) => d == const Duration(days: 3)).length,
        1,
      );
    });
  });

  group('ExamSessionController — error replay', () {
    test('Returns the wrong + skipped questions only', () async {
      final fake = FakeGeminiProvider(questionsToReturn: [
        buildTestQuestion(id: 'q1', correctIndex: 0),
        buildTestQuestion(id: 'q2', correctIndex: 0),
        buildTestQuestion(id: 'q3', correctIndex: 0),
      ]);
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);
      await ctrl.startExam({'c1': 'x'}, count: 3);

      // Capture the shuffled order — interleaving randomises which q@id
      // sits at which index, so we can't assume q1/q2/q3 by position.
      final ordered = ctrl.session!.questions.map((q) => q.id).toList();
      final firstId = ordered[0];
      final secondId = ordered[1];
      final thirdId = ordered[2];

      ctrl.submitChoiceAnswer(0); ctrl.nextQuestion(); // correct → firstId
      ctrl.submitChoiceAnswer(2); ctrl.nextQuestion(); // wrong   → secondId
      ctrl.skipQuestion();                              // skipped → thirdId

      final wrong = ctrl.incorrectQuestions;
      expect(wrong.length, 2);
      final ids = wrong.map((q) => q.id).toSet();
      // The two wrong/skipped should be the second and third in shuffle order.
      expect(ids, contains(secondId));
      expect(ids, contains(thirdId));
      // And NOT the first (which was correct).
      expect(ids, isNot(contains(firstId)));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 🌉 Passo 9 → Passo 11: cross-domain bridge validation in the exam
  // ─────────────────────────────────────────────────────────────────────────

  group('ExamSessionController.appendCrossDomainQuestions', () {
    test('appends generated questions and marks them isCrossDomain', () async {
      final fake = FakeGeminiProvider(
        questionsToReturn: [buildTestQuestion(id: 'q1')],
      )..crossDomainQuestionsToReturn = [
          ExamQuestion(
            id: 'crossdomain_1',
            questionText: 'Applica X al contesto Y.',
            type: ExamQuestionType.openEnded,
            correctAnswer: 'A',
            explanation: 'spiegazione',
            sourceClusterId: 'cA',
            sourceText: 'src',
            isCrossDomain: true,
          ),
        ];
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);

      await ctrl.startExam({'cA': 'long enough source text for cluster A', 'cB': 'long enough source text for cluster B'});
      expect(ctrl.session!.questions.length, 1);

      final added = await ctrl.appendCrossDomainQuestions(
        bridges: [
          (
            sourceLabel: 'Bio',
            targetLabel: 'Eco',
            socraticQuestion: 'Cosa hanno in comune?',
            sourceClusterId: 'cA',
            targetClusterId: 'cB',
          ),
        ],
        clusterTexts: const {
          'cA': 'long enough source text for cluster A',
          'cB': 'long enough source text for cluster B',
        },
      );

      expect(added, 1);
      expect(ctrl.session!.questions.length, 2);
      expect(ctrl.session!.questions.last.isCrossDomain, true);
      expect(fake.crossDomainCalls, hasLength(1));
      expect(fake.crossDomainCalls.single.bridgeCount, 1);
    });

    test('no-op when no session is active', () async {
      final fake = FakeGeminiProvider()
        ..crossDomainQuestionsToReturn = [
          ExamQuestion(
            id: 'cd_should_not_appear',
            questionText: 'Q?',
            type: ExamQuestionType.openEnded,
            correctAnswer: 'A',
            explanation: '',
            sourceClusterId: 'c',
            sourceText: 's',
            isCrossDomain: true,
          ),
        ];
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);

      // No startExam call → no session.
      final added = await ctrl.appendCrossDomainQuestions(
        bridges: [
          (
            sourceLabel: 'A',
            targetLabel: 'B',
            socraticQuestion: 'q?',
            sourceClusterId: 'cA',
            targetClusterId: 'cB',
          ),
        ],
        clusterTexts: const {'cA': 'x', 'cB': 'y'},
      );

      expect(added, 0);
      expect(ctrl.session, isNull);
      expect(fake.crossDomainCalls, isEmpty,
          reason: 'must short-circuit before hitting the provider');
    });

    test('no-op when bridges list is empty', () async {
      final fake = FakeGeminiProvider(
        questionsToReturn: [buildTestQuestion(id: 'q1')],
      );
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);
      await ctrl.startExam({'c1': 'text'});

      final added = await ctrl.appendCrossDomainQuestions(
        bridges: const [],
        clusterTexts: const {'c1': 'text'},
      );

      expect(added, 0);
      expect(fake.crossDomainCalls, isEmpty);
    });

    test('crossDomainCorrectRate returns ratio over answered cross-domain Qs',
        () async {
      final fake = FakeGeminiProvider(
        questionsToReturn: [buildTestQuestion(id: 'q1')],
      )..crossDomainQuestionsToReturn = [
          ExamQuestion(
            id: 'cd_q1',
            questionText: 'Q1?',
            type: ExamQuestionType.openEnded,
            correctAnswer: 'A',
            explanation: '',
            sourceClusterId: 'c',
            sourceText: 's',
            isCrossDomain: true,
          ),
          ExamQuestion(
            id: 'cd_q2',
            questionText: 'Q2?',
            type: ExamQuestionType.openEnded,
            correctAnswer: 'B',
            explanation: '',
            sourceClusterId: 'c',
            sourceText: 's',
            isCrossDomain: true,
          ),
        ];
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);

      await ctrl.startExam({'c': 'text'});
      await ctrl.appendCrossDomainQuestions(
        bridges: [
          (
            sourceLabel: 'A',
            targetLabel: 'B',
            socraticQuestion: 'q?',
            sourceClusterId: 'c',
            targetClusterId: 'c',
          ),
        ],
        clusterTexts: const {'c': 'text'},
      );

      expect(ctrl.crossDomainCorrectRate, isNull,
          reason: 'no cross-domain Q answered yet → null (not 0.0)');

      // Manually mark one cross-domain question as correct and one as wrong.
      final cdQuestions =
          ctrl.session!.questions.where((q) => q.isCrossDomain).toList();
      cdQuestions[0].result = ExamAnswerResult.correct;
      cdQuestions[1].result = ExamAnswerResult.incorrect;

      expect(ctrl.crossDomainCorrectRate, closeTo(0.5, 1e-9));
    });
  });
}
