import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/exam_session_controller.dart';
import 'package:fluera_engine/src/canvas/ai/exam_session_model.dart';
import 'package:fluera_engine/src/canvas/overlays/exam_overlay.dart';
import 'package:fluera_engine/src/l10n/generated/fluera_localizations.g.dart';
import '../ai/_fakes.dart';

/// Wraps [child] in the bare-minimum Material + Localizations scaffolding so
/// the overlay can resolve [FlueraLocalizations] and read theme defaults.
Widget _harness(Widget child) {
  return MaterialApp(
    home: child,
    localizationsDelegates: FlueraLocalizations.localizationsDelegates,
    supportedLocales: FlueraLocalizations.supportedLocales,
    locale: const Locale('it'),
  );
}

void main() {
  setUp(() {
    installTempPathProvider();
  });

  group('ExamOverlay — scope picker (fresh exam)', () {
    testWidgets('Renders the scope picker when no session is loaded',
        (tester) async {
      final ctrl = ExamSessionController(provider: FakeGeminiProvider());
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_harness(ExamOverlay(
        availableClusters: const {'c1': 'Anatomia', 'c2': 'Patologia'},
        clusterTexts: const {'c1': 'aaa', 'c2': 'bbb'},
        controller: ctrl,
        onClose: () {},
        onComplete: (_, __) {},
      )));
      await tester.pump(const Duration(milliseconds: 600));

      // Scope picker title is the localized "select topics" prompt.
      expect(find.text('Anatomia'), findsOneWidget);
      expect(find.text('Patologia'), findsOneWidget);
    });
  });

  group('ExamOverlay — resume mode (session pre-loaded)', () {
    testWidgets('Skips the scope picker when a session is already on the controller',
        (tester) async {
      // Manually inject a session so the overlay sees it on initState.
      final ctrl = _RehydratedController(provider: FakeGeminiProvider())
        ..injectSession(ExamSession.fromCheckpoint(
          sessionId: 'resumed',
          questions: [
            buildTestQuestion(id: 'q1', text: 'Domanda di prova A'),
            buildTestQuestion(id: 'q2', text: 'Domanda di prova B'),
          ],
          currentIndex: 1,
          startedAt: DateTime.now(),
        ));
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_harness(ExamOverlay(
        // Empty topic map — the resume flow does not use it.
        availableClusters: const {},
        clusterTexts: const {},
        controller: ctrl,
        onClose: () {},
        onComplete: (_, __) {},
      )));
      await tester.pump(const Duration(milliseconds: 600));

      // The current Q is "B" (index 1), which means the overlay went straight
      // to the question screen instead of the topic picker.
      expect(find.textContaining('Domanda di prova B'), findsOneWidget);
    });
  });

  group('ExamOverlay — confidence slider labels', () {
    testWidgets('Shows the explicit Italian confidence labels',
        (tester) async {
      final ctrl = _RehydratedController(provider: FakeGeminiProvider())
        ..injectSession(ExamSession.fromCheckpoint(
          sessionId: 's',
          questions: [buildTestQuestion(id: 'q1', text: 'Domanda?')],
          currentIndex: 0,
          startedAt: DateTime.now(),
        ));
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_harness(ExamOverlay(
        availableClusters: const {},
        clusterTexts: const {},
        controller: ctrl,
        onClose: () {},
        onComplete: (_, __) {},
      )));
      await tester.pump(const Duration(milliseconds: 600));

      // All five level labels must render.
      expect(find.text('Indovino'), findsOneWidget);
      expect(find.text('Poco sicuro'), findsOneWidget);
      expect(find.text('Più o meno'), findsOneWidget);
      expect(find.text('Quasi certo'), findsOneWidget);
      expect(find.text('Sicurissimo'), findsOneWidget);
    });

    testWidgets('Tapping the (?) icon opens the explainer bottom-sheet',
        (tester) async {
      final ctrl = _RehydratedController(provider: FakeGeminiProvider())
        ..injectSession(ExamSession.fromCheckpoint(
          sessionId: 's',
          questions: [buildTestQuestion(id: 'q1', text: 'Domanda di prova')],
          currentIndex: 0,
          startedAt: DateTime.now(),
        ));
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_harness(ExamOverlay(
        availableClusters: const {},
        clusterTexts: const {},
        controller: ctrl,
        onClose: () {},
        onComplete: (_, __) {},
      )));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.byIcon(Icons.help_outline_rounded));
      await tester.pump(const Duration(milliseconds: 400));

      // The explainer sheet headline.
      expect(find.text('Perché la tua fiducia conta'), findsOneWidget);
      // And the dismiss button.
      expect(find.text('Capito'), findsOneWidget);
    });
  });

  group('ExamOverlay — completed session results', () {
    testWidgets('Renders the calibration card per-level breakdown',
        (tester) async {
      final qs = [
        buildTestQuestion(id: 'q1')
          ..result = ExamAnswerResult.correct
          ..confidenceLevel = 5,
        buildTestQuestion(id: 'q2')
          ..result = ExamAnswerResult.incorrect
          ..confidenceLevel = 5,
        buildTestQuestion(id: 'q3')
          ..result = ExamAnswerResult.correct
          ..confidenceLevel = 3,
      ];
      final session = ExamSession.fromCheckpoint(
        sessionId: 's',
        questions: qs,
        currentIndex: qs.length, // complete
        startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        completedAt: DateTime.now(),
      );

      final ctrl = _RehydratedController(provider: FakeGeminiProvider())
        ..injectSession(session);
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_harness(ExamOverlay(
        availableClusters: const {},
        clusterTexts: const {},
        controller: ctrl,
        onClose: () {},
        onComplete: (_, __) {},
      )));
      await tester.pump(const Duration(milliseconds: 600));

      // The calibration breakdown row for confidence=5 must show "1/2"
      // (one correct out of two confident attempts).
      expect(find.textContaining('1/2'), findsOneWidget);
      // Confidence labels appear in the breakdown rows too.
      expect(find.textContaining('Sicurissimo'), findsOneWidget);
      expect(find.textContaining('Più o meno'), findsOneWidget);
    });
  });
}

/// Tiny extension that exposes a test-only setter so widget tests can pre-load
/// a session without going through the real Gemini-backed [startExam] flow.
class _RehydratedController extends ExamSessionController {
  _RehydratedController({required super.provider});

  /// Replace the in-memory session. Mirrors what `resumeFromCheckpoint`
  /// would do without writing/reading the disk.
  void injectSession(ExamSession s) {
    // The base class keeps `_session` private, but `resumeFromCheckpoint`
    // is the canonical setter. We inject by writing a checkpoint to the temp
    // path provider, then asking the controller to resume from it. That
    // exercises the same code path the production resume dialog uses.
    //
    // For simplicity in widget tests we re-implement the rehydration
    // inline — peek/resume would otherwise require async + a real disk
    // round-trip we don't want in widget land.
    _injectedSession = s;
    notifyListenersForTest();
  }

  ExamSession? _injectedSession;

  @override
  ExamSession? get session => _injectedSession ?? super.session;
}

/// Tiny extension shim — `notifyListeners` is `protected` on `ChangeNotifier`,
/// but the analyzer's `invalid_use_of_protected_member` warning is
/// already silenced at the package level. We expose a public hook here for
/// clarity (it's only used by the widget tests above).
extension _NotifyForTest on ExamSessionController {
  void notifyListenersForTest() {
    // ignore: invalid_use_of_protected_member
    notifyListeners();
  }
}
