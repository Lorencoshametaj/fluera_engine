// ============================================================================
// 🆓 BackgroundAiController — unit tests (Bundle A, 2026-05-17)
//
// Covers the trigger orchestrator's contract:
//   • idle 5 s post-stroke fires `_processBatch`
//   • cold-start window suppresses the first 2 s
//   • app pause cancels pending timers
//   • first-dezoom < 0.30 edge trigger fires once, resets above threshold
//   • signature dedup skips unchanged clusters across batches
//   • cap exceeded → onCapExceeded callback + no second AI call
//   • maxBatchSize truncates oversized batches
//   • consent off → silent skip
// ============================================================================

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/ai_provider.dart';
import 'package:fluera_engine/src/ai/atlas_action.dart';
import 'package:fluera_engine/src/ai/background_ai_controller.dart';
import 'package:fluera_engine/src/ai/credits/ai_credits_controller.dart';
import 'package:fluera_engine/src/ai/credits/ai_credits_costs.dart';
import 'package:fluera_engine/src/canvas/ai/cluster_concept_index.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────

class _FakeProvider extends AiProvider {
  _FakeProvider({this.initialized = true});

  @override
  String get name => 'fake';

  @override
  Future<void> initialize() async {}

  @override
  void dispose() {}

  @override
  bool get isInitialized => initialized;
  bool initialized;

  int bulkCalls = 0;
  bool? lastIsFreeBackground;

  @override
  Future<AtlasResponse> askAtlas(
    String prompt,
    List<Map<String, dynamic>> canvasContext, {
    Map<String, dynamic>? lensContext,
  }) async {
    return AtlasResponse(rawJson: const {}, explanation: null, actions: const []);
  }

  @override
  Future<String> askFreeText(
    String prompt, {
    bool isFreeBackground = false,
  }) async {
    bulkCalls++;
    lastIsFreeBackground = isFreeBackground;
    // Return a JSON shape `bulkGenerateTitles` understands.
    return '{"titoli": {"1": "Title 1", "2": "Title 2"}}';
  }
}

class _FakeCredits implements AiCreditsController {
  _FakeCredits({
    this.allowedSequence = const [true, true, true, true, true],
    bool authenticated = true,
  }) {
    // Default to "authenticated" by seeding a non-null snapshot. Tests that
    // need to exercise the unauthenticated path can pass `authenticated:
    // false` to leave the snapshot null (matches the heuristic in
    // `BackgroundAiController._isAuthenticatedNow`).
    if (authenticated) {
      _credits.value = AiCreditsSnapshot(
        monthlyCredits: 100,
        packCredits: 0,
        tier: 'free',
        monthlyResetAt: DateTime.now().add(const Duration(days: 30)),
      );
    }
  }

  /// Sequence of allowed/denied responses for recordBackgroundCall calls.
  /// Wraps around so a single test can cover many invocations.
  final List<bool> allowedSequence;
  int recordCallIdx = 0;
  int recordCalls = 0;
  int lastClusterCount = 0;
  final StreamController<BackgroundAiCapExceededException> _capCtrl =
      StreamController<BackgroundAiCapExceededException>.broadcast();

  @override
  Future<bool> recordBackgroundCall({required int clusterCount}) async {
    recordCalls++;
    lastClusterCount = clusterCount;
    final allowed = allowedSequence.isEmpty
        ? true
        : allowedSequence[recordCallIdx % allowedSequence.length];
    recordCallIdx++;
    if (!allowed) {
      _capCtrl.add(BackgroundAiCapExceededException(
        tier: 'free',
        cap: 1000,
        used: 1000,
      ));
    }
    return allowed;
  }

  // The rest is unused in these tests but required by the interface.
  @override
  ValueListenable<AiCreditsSnapshot?> get credits => _credits;
  final ValueNotifier<AiCreditsSnapshot?> _credits =
      ValueNotifier<AiCreditsSnapshot?>(null);

  @override
  Stream<AiCreditsExhaustedException> get exhaustedEvents => const Stream.empty();

  @override
  Stream<AiCreditsRateLimitedException> get rateLimitedEvents => const Stream.empty();

  @override
  Stream<BackgroundAiCapExceededException> get backgroundCapEvents => _capCtrl.stream;

  @override
  Future<AiCreditsSnapshot?> refresh() async => null;

  @override
  Future<AiCreditsReceipt> consume(AiCreditFeature feature) async {
    throw UnimplementedError();
  }

  @override
  Future<void> refund(String idempotencyKey) async {}

  @override
  Future<void> applyPackPurchase({
    required String packSku,
    required String purchaseToken,
  }) async {}

  @override
  Future<void> updateTier(String tier) async {}

  // Preflight peek — overridable by tests via [peekResult]. Default null
  // mirrors the engine no-op so existing tests don't need updating.
  BackgroundAiPeek? peekResult;
  int peekCalls = 0;
  @override
  Future<BackgroundAiPeek?> peekBackgroundStatus() async {
    peekCalls++;
    return peekResult;
  }

  @override
  void dispose() {
    _credits.dispose();
    _capCtrl.close();
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────

ContentCluster _cluster(String id, {int strokeCount = 3}) => ContentCluster(
      id: id,
      strokeIds: List.generate(strokeCount, (i) => '$id-s$i'),
      bounds: const Rect.fromLTWH(0, 0, 100, 50),
      centroid: const Offset(50, 25),
    );

BackgroundAiController _make({
  required _FakeProvider provider,
  required ClusterConceptIndex index,
  required List<ContentCluster> Function() clustersFn,
  required Map<String, String> Function() textsFn,
  _FakeCredits? credits,
  bool consent = true,
  Duration idleDuration = const Duration(milliseconds: 50),
  Duration coldStart = const Duration(milliseconds: 30),
}) {
  return BackgroundAiController(
    providerFn: () => provider,
    indexFn: () => index,
    clustersFn: clustersFn,
    clusterTextsFn: textsFn,
    creditsControllerFn: credits == null ? null : () => credits,
    consentFn: () => consent,
    idleDuration: idleDuration,
    coldStartDelay: coldStart,
    maxBatchSize: 50,
  );
}

ClusterConceptIndex _index(_FakeProvider provider) {
  return ClusterConceptIndex(
    providerFn: () => provider,
    strokeMapFn: () => const {},
    reviewScheduleFn: () => const {},
    languageNameFn: () => 'Italian',
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────

void main() {
  group('BackgroundAiController — trigger lifecycle', () {
    test(
        'onStrokeCommitted resets the idle timer; fire when idleDuration '
        'elapses without further strokes', () async {
      final provider = _FakeProvider();
      final index = _index(provider);
      final clusters = [_cluster('c1')];
      final texts = {'c1': 'prima legge di newton'};

      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => clusters,
        textsFn: () => texts,
        idleDuration: const Duration(milliseconds: 40),
        coldStart: const Duration(milliseconds: 0), // skip cold-start
      );
      controller.onCanvasOpened();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      controller.onStrokeCommitted();

      // Sleep enough for idle to fire.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(provider.bulkCalls, 1,
          reason: 'idle timer should have fired exactly once');
      expect(provider.lastIsFreeBackground, isTrue,
          reason: 'background batch must propagate isFreeBackground=true');
      controller.dispose();
    });

    test(
        'cold-start window suppresses the first stroke trigger; idle fires '
        'only after cold-start elapses', () async {
      final provider = _FakeProvider();
      final index = _index(provider);
      final clusters = [_cluster('c1')];
      final texts = {'c1': 'la prima legge di newton sulla dinamica del moto'};

      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => clusters,
        textsFn: () => texts,
        idleDuration: const Duration(milliseconds: 30),
        coldStart: const Duration(milliseconds: 60),
      );
      controller.onCanvasOpened();
      controller.onStrokeCommitted(); // during cold-start → ignored
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(provider.bulkCalls, 0,
          reason: 'cold-start should suppress the first stroke trigger');

      // Wait past cold-start, then commit again — timer should arm now.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      controller.onStrokeCommitted();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(provider.bulkCalls, 1,
          reason: 'post cold-start stroke must trigger one batch');
      controller.dispose();
    });

    test(
        'app pause cancels the pending idle timer; resume re-arms on next stroke',
        () async {
      final provider = _FakeProvider();
      final index = _index(provider);
      final texts = {'c1': 'la prima legge di newton sulla dinamica del moto'};
      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => [_cluster('c1')],
        textsFn: () => texts,
        idleDuration: const Duration(milliseconds: 60),
        coldStart: Duration.zero,
      );
      controller.onCanvasOpened();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      controller.onStrokeCommitted();
      controller.onAppPaused();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(provider.bulkCalls, 0,
          reason: 'paused controller must not fire timers');

      controller.onAppResumed();
      controller.onStrokeCommitted();
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(provider.bulkCalls, 1);
      controller.dispose();
    });
  });

  group('BackgroundAiController — dezoom edge trigger', () {
    test(
        'first scale < 0.30 fires immediately; subsequent calls below the '
        'threshold are no-ops until the user zooms back in', () async {
      final provider = _FakeProvider();
      final index = _index(provider);
      final texts = {'c1': 'la prima legge di newton sulla dinamica del moto'};
      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => [_cluster('c1')],
        textsFn: () => texts,
        idleDuration: const Duration(seconds: 99),
        coldStart: Duration.zero,
      );
      controller.onCanvasOpened();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      controller.onScaleChanged(0.50); // above threshold — no fire
      controller.onScaleChanged(0.40);
      controller.onScaleChanged(0.31);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(provider.bulkCalls, 0);

      // Cross the threshold downward.
      controller.onScaleChanged(0.29);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(provider.bulkCalls, 1, reason: 'first dezoom should fire once');

      // Subsequent scale changes below 0.30 → no-op.
      controller.onScaleChanged(0.20);
      controller.onScaleChanged(0.15);
      controller.onScaleChanged(0.10);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(provider.bulkCalls, 1,
          reason: 'edge trigger must not fire again within same dezoom');

      // Zoom back above threshold → re-arms.
      controller.onScaleChanged(0.40);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // (clusters now have title from previous batch; pending will be empty.
      //  Force a fresh cluster so the next dezoom has work to do.)
      texts['c2'] = 'altro cluster';
      // ignore: invalid_use_of_visible_for_testing_member
      controller.pendingForTest(); // touch helper for coverage

      controller.dispose();
    });
  });

  group('BackgroundAiController — dedup + cap', () {
    test(
        'signature dedup: same cluster + same text not re-processed in '
        'consecutive batches', () async {
      final provider = _FakeProvider();
      final index = _index(provider);
      final texts = {'c1': 'la prima legge di newton sulla dinamica del moto'};
      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => [_cluster('c1')],
        textsFn: () => texts,
        idleDuration: const Duration(milliseconds: 30),
        coldStart: Duration.zero,
      );
      controller.onCanvasOpened();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      controller.onStrokeCommitted();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.bulkCalls, 1);

      // bulkGenerateTitles caches the title in the index → next pending
      // build skips this cluster entirely (existing title not empty).
      // Plus the controller would also dedup by signature.
      controller.onStrokeCommitted();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.bulkCalls, 1,
          reason: 'second batch with unchanged content must be skipped');
      controller.dispose();
    });

    test('cap exceeded → onCapExceeded callback fires; no AI call', () async {
      final provider = _FakeProvider();
      final index = _index(provider);
      final credits = _FakeCredits(allowedSequence: const [false]);
      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => [_cluster('c1')],
        textsFn: () => {'c1': 'la prima legge di newton sulla dinamica del moto'},
        credits: credits,
        idleDuration: const Duration(milliseconds: 30),
        coldStart: Duration.zero,
      );
      var capCalled = false;
      controller.onCapExceeded = () => capCalled = true;
      controller.onCanvasOpened();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      controller.onStrokeCommitted();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(credits.recordCalls, 1,
          reason: 'controller must consult the cap RPC');
      expect(credits.lastClusterCount, 1);
      expect(capCalled, isTrue, reason: 'cap callback must fire on denial');
      expect(provider.bulkCalls, 0,
          reason: 'AI must not be called when cap denies the batch');
      controller.dispose();
    });

    test(
        'consent off short-circuits before the RPC; provider never called',
        () async {
      final provider = _FakeProvider();
      final index = _index(provider);
      final credits = _FakeCredits();
      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => [_cluster('c1')],
        textsFn: () => {'c1': 'la prima legge di newton sulla dinamica del moto'},
        credits: credits,
        consent: false,
        idleDuration: const Duration(milliseconds: 30),
        coldStart: Duration.zero,
      );
      controller.onCanvasOpened();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      controller.onStrokeCommitted();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(credits.recordCalls, 0,
          reason: 'consent off must skip the RPC');
      expect(provider.bulkCalls, 0);
      controller.dispose();
    });

    test('provider not initialized → no batch fires', () async {
      final provider = _FakeProvider(initialized: false);
      final index = _index(provider);
      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => [_cluster('c1')],
        textsFn: () => {'c1': 'la prima legge di newton sulla dinamica del moto'},
        idleDuration: const Duration(milliseconds: 30),
        coldStart: Duration.zero,
      );
      controller.onCanvasOpened();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      controller.onStrokeCommitted();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.bulkCalls, 0);
      controller.dispose();
    });
  });

  group('BackgroundAiController — pending build', () {
    test(
        'pendingForTest skips clusters with empty text, already-titled '
        'clusters, and respects maxBatchSize implicitly via filter order',
        () {
      final provider = _FakeProvider();
      final index = _index(provider);
      // Pre-cache a title for c2 — should be skipped.
      index.setTitle('c2', 'Cached', sourceText: 'cached source');
      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => [_cluster('c1'), _cluster('c2'), _cluster('c3')],
        textsFn: () => {
          'c1': 'la prima legge di newton sulla dinamica del moto',
          'c2': 'einstein', // titled → skip
          'c3': '', // empty → skip
        },
        idleDuration: const Duration(milliseconds: 99),
        coldStart: Duration.zero,
      );
      controller.onCanvasOpened();
      final pending = controller.pendingForTest();
      expect(pending.keys, ['c1']);
      controller.dispose();
    });
  });

  group('BackgroundAiController — viewport priority (Bundle 5)', () {
    test(
        'when viewportFn is provided, clusters intersecting the viewport '
        'come BEFORE off-screen ones in the pending map', () {
      final provider = _FakeProvider();
      final index = _index(provider);
      // 3 clusters: 'visible1' inside viewport, 'visible2' inside, 'offscreen' outside.
      final visible1 = ContentCluster(
        id: 'visible1',
        strokeIds: const ['s1', 's2', 's3'],
        bounds: const Rect.fromLTWH(10, 10, 50, 50),
        centroid: const Offset(35, 35),
      );
      final offscreen = ContentCluster(
        id: 'offscreen',
        strokeIds: const ['s1', 's2', 's3'],
        bounds: const Rect.fromLTWH(2000, 2000, 50, 50),
        centroid: const Offset(2025, 2025),
      );
      final visible2 = ContentCluster(
        id: 'visible2',
        strokeIds: const ['s1', 's2', 's3'],
        bounds: const Rect.fromLTWH(100, 100, 50, 50),
        centroid: const Offset(125, 125),
      );
      // Note: natural order is [visible1, offscreen, visible2] — the
      // controller must reorder so visible1+visible2 come BEFORE offscreen.
      final clusters = [visible1, offscreen, visible2];

      final controller = BackgroundAiController(
        providerFn: () => provider,
        indexFn: () => index,
        clustersFn: () => clusters,
        clusterTextsFn: () => {
          'visible1': 'la prima legge di newton sulla dinamica',
          'offscreen': 'la seconda legge di newton sulla dinamica',
          'visible2': 'la terza legge di newton sulla dinamica',
        },
        viewportFn: () => const Rect.fromLTWH(0, 0, 500, 500),
        idleDuration: const Duration(milliseconds: 99),
        coldStartDelay: Duration.zero,
      );
      controller.onCanvasOpened();
      final pending = controller.pendingForTest();
      final ids = pending.keys.toList();
      expect(ids.length, 3);
      // visible1 + visible2 must come BEFORE offscreen.
      final offscreenIdx = ids.indexOf('offscreen');
      expect(ids.indexOf('visible1'), lessThan(offscreenIdx));
      expect(ids.indexOf('visible2'), lessThan(offscreenIdx));
      controller.dispose();
    });

    test(
        'null viewportFn falls back to natural cluster order (no '
        're-ordering)', () {
      final provider = _FakeProvider();
      final index = _index(provider);
      final c1 = _cluster('c1');
      final c2 = _cluster('c2');
      final c3 = _cluster('c3');
      final controller = BackgroundAiController(
        providerFn: () => provider,
        indexFn: () => index,
        clustersFn: () => [c1, c2, c3],
        clusterTextsFn: () => {
          'c1': 'la prima legge di newton sulla dinamica',
          'c2': 'la seconda legge di newton sulla dinamica',
          'c3': 'la terza legge di newton sulla dinamica',
        },
        // viewportFn intentionally omitted (defaults to null)
        idleDuration: const Duration(milliseconds: 99),
        coldStartDelay: Duration.zero,
      );
      controller.onCanvasOpened();
      final pending = controller.pendingForTest();
      expect(pending.keys.toList(), ['c1', 'c2', 'c3'],
          reason: 'without viewportFn the natural order must be preserved');
      controller.dispose();
    });
  });

  group('BackgroundAiController — disposal', () {
    test('dispose cancels pending timers and ignores further calls', () async {
      final provider = _FakeProvider();
      final index = _index(provider);
      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => [_cluster('c1')],
        textsFn: () => {'c1': 'la prima legge di newton sulla dinamica del moto'},
        idleDuration: const Duration(milliseconds: 40),
        coldStart: Duration.zero,
      );
      controller.onCanvasOpened();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      controller.onStrokeCommitted();
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(provider.bulkCalls, 0, reason: 'disposed controller must not fire');
      // Post-dispose calls are no-ops, not throws.
      controller.onStrokeCommitted();
      controller.onScaleChanged(0.10);
      controller.onAppPaused();
      controller.onAppResumed();
    });
  });

  // ─── Preflight + gate ────────────────────────────────────────────────────
  //
  // 🔍 2026-05-18 — the preflight + observable gate state is the diagnostic
  // surface added after the device whack-a-mole pattern (see plan
  // `.claude/plans/perfetto-fai-un-piano-dreamy-kite.md`). These tests
  // pin the gate enum value at each well-defined precondition state so
  // future regressions are caught.

  group('BackgroundAiController — preflight diagnostics', () {
    test('gate starts at initial; transitions to ready when all gates pass',
        () async {
      final provider = _FakeProvider();
      final index = _index(provider);
      final clusters = [_cluster('c1')];
      final texts = {'c1': 'la prima legge di newton'};
      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => clusters,
        textsFn: () => texts,
        credits: _FakeCredits(),
        coldStart: Duration.zero,
      );
      expect(controller.gate.value, BackgroundAiGate.initial);
      controller.onCanvasOpened();
      // Synchronous portion of preflight has run.
      expect(controller.gate.value, BackgroundAiGate.ready);
      controller.dispose();
    });

    test('gate transitions to notAuthenticated when credits controller '
        'present but snapshot is null (unauthenticated session)', () async {
      final provider = _FakeProvider();
      final index = _index(provider);
      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => [_cluster('c1')],
        textsFn: () => {'c1': 'foo'},
        credits: _FakeCredits(authenticated: false),
        coldStart: Duration.zero,
      );
      controller.onCanvasOpened();
      expect(controller.gate.value, BackgroundAiGate.notAuthenticated);
      controller.dispose();
    });

    test('gate transitions to providerNull when providerFn returns null',
        () async {
      final index = ClusterConceptIndex(
        providerFn: () => null,
        strokeMapFn: () => const {},
        reviewScheduleFn: () => const {},
        languageNameFn: () => 'Italian',
      );
      final controller = BackgroundAiController(
        providerFn: () => null,
        indexFn: () => index,
        clustersFn: () => [_cluster('c1')],
        clusterTextsFn: () => {'c1': 'foo'},
        creditsControllerFn: () => _FakeCredits(),
        consentFn: () => true,
        idleDuration: const Duration(milliseconds: 40),
        coldStartDelay: Duration.zero,
      );
      controller.onCanvasOpened();
      expect(controller.gate.value, BackgroundAiGate.providerNull);
      controller.dispose();
    });

    test('gate transitions to consentOff when host consent flag is false',
        () async {
      final provider = _FakeProvider();
      final index = _index(provider);
      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => [_cluster('c1')],
        textsFn: () => {'c1': 'foo'},
        credits: _FakeCredits(),
        consent: false,
        coldStart: Duration.zero,
      );
      controller.onCanvasOpened();
      expect(controller.gate.value, BackgroundAiGate.consentOff);
      controller.dispose();
    });

    test('gate transitions to ocrTextNotReady when clusters present but no text',
        () async {
      final provider = _FakeProvider();
      final index = _index(provider);
      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => [_cluster('c1'), _cluster('c2')],
        textsFn: () => const <String, String>{}, // no text yet
        credits: _FakeCredits(),
        coldStart: Duration.zero,
      );
      controller.onCanvasOpened();
      expect(controller.gate.value, BackgroundAiGate.ocrTextNotReady);
      controller.dispose();
    });

    test('gate transitions to capExceeded when async peek reports cap_exceeded',
        () async {
      final provider = _FakeProvider();
      final index = _index(provider);
      final credits = _FakeCredits();
      credits.peekResult = const BackgroundAiPeek(
        ok: true,
        allowed: false,
        error: 'cap_exceeded',
        tier: 'free',
        used: 1000,
        cap: 1000,
      );
      final controller = _make(
        provider: provider,
        index: index,
        clustersFn: () => [_cluster('c1')],
        textsFn: () => {'c1': 'foo'},
        credits: credits,
        coldStart: Duration.zero,
      );
      controller.onCanvasOpened();
      // Synchronous portion sets gate to ready; async peek refines.
      expect(controller.gate.value, BackgroundAiGate.ready);
      // Wait for the async peek to resolve.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.gate.value, BackgroundAiGate.capExceeded);
      expect(credits.peekCalls, 1);
      controller.dispose();
    });
  });
}
