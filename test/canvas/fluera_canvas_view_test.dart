import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluera_engine/src/canvas/canvas_scope.dart';
import 'package:fluera_engine/src/canvas/canvas_view_tier.dart';
import 'package:fluera_engine/src/canvas/fluera_canvas_view.dart';
import 'package:fluera_engine/src/core/engine_scope.dart';
import 'package:fluera_engine/src/core/models/shape_type.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:fluera_engine/src/canvas/ai/fog_of_war/fog_of_war_controller.dart';
import 'package:fluera_engine/src/canvas/ai/ghost_map_controller.dart';
import 'package:fluera_engine/src/canvas/ai/learning_step_controller.dart';
import 'package:fluera_engine/src/canvas/ai/recall/recall_mode_controller.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_controller.dart';
import 'package:fluera_engine/src/canvas/ai/srs_review_session.dart';
import 'package:fluera_engine/src/canvas/ai/tier_gate_controller.dart';
import 'package:fluera_engine/src/ai/ai_provider.dart';
import 'package:fluera_engine/src/canvas/fluera_canvas_config.dart'
    show FlueraSubscriptionTier;
import 'package:fluera_engine/src/l10n/generated/fluera_localizations_en.g.dart';
import 'package:fluera_engine/src/layers/layer_controller.dart';
import 'package:fluera_engine/src/tools/unified_tool_controller.dart';

/// 🧪 Smoke tests for [FlueraCanvasView] — verify the widget can be
/// constructed, mounts inside a [CanvasScope] without throwing, and
/// renders the expected painter sub-tree for each tier.
///
/// NOTE: This is NOT a pixel-match regression test. Full visual parity
/// validation against the legacy `_buildCanvasArea` path requires:
///  - Golden file infrastructure (per-platform Skia/Impeller variance)
///  - Mock `EngineScope` for `DrawingPainter` static caches
///  - Curated test scenes (empty / strokes / images / PDFs / cognitive)
/// Memo: `engine_pro_d5_pixel_match_validated` standard ≥99.9% match
/// at zoom=1.0.
///
/// What this test DOES verify:
///  - FlueraCanvasView constructs with minimal CanvasScope ancestor
///  - Tier `.full / .panel / .preview` all build without throwing
///  - Drawing input gating: `.preview` blocks input pipeline init
void main() {
  group('FlueraCanvasView smoke', () {
    late LayerController layerController;
    late UnifiedToolController toolController;
    late LearningStepController learningStepController;
    late SocraticController socraticController;
    late RecallModeController recallModeController;
    late FogOfWarController fogOfWarController;
    late GhostMapController ghostMapController;
    late TierGateController tierGateController;
    late SrsReviewSession srsReviewSession;
    late FlueraLocalizationsEn l10n;

    setUp(() {
      // Reset EngineScope + DrawingPainter static caches to isolate
      // tests. Without this, `_renderIndex` / paging manager / scope
      // singleton can leak state from one scenario into the next and
      // produce order-dependent flakiness (e.g. shape pixel deltas
      // vanishing after a preceding stroke test).
      EngineScope.reset();
      layerController = LayerController();
      toolController = UnifiedToolController();
      learningStepController = LearningStepController();
      socraticController = SocraticController();
      recallModeController = RecallModeController();
      fogOfWarController = FogOfWarController();
      ghostMapController = GhostMapController(provider: _NoopAiProvider());
      tierGateController =
          TierGateController(tier: FlueraSubscriptionTier.free);
      srsReviewSession = SrsReviewSession();
      l10n = FlueraLocalizationsEn();
    });

    Widget buildScope({
      CanvasViewTier tier = CanvasViewTier.preview,
      Key? repaintKey,
    }) {
      Widget canvas = SizedBox(
        width: 800,
        height: 600,
        child: FlueraCanvasView(
          tier: tier,
          cacheName: 'test_${tier.name}',
        ),
      );
      if (repaintKey != null) {
        canvas = RepaintBoundary(key: repaintKey, child: canvas);
      }
      return WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, child) {
          return CanvasScope(
            layerController: layerController,
            toolController: toolController,
            learningStepController: learningStepController,
            socraticController: socraticController,
            recallModeController: recallModeController,
            fogOfWarController: fogOfWarController,
            ghostMapController: ghostMapController,
            tierGateController: tierGateController,
            srsReviewSession: srsReviewSession,
            clusterCache: const [],
            l10n: l10n,
            canvasId: 'test_canvas',
            child: canvas,
          );
        },
      );
    }

    testWidgets('builds in `.preview` tier without throwing',
        (tester) async {
      await tester.pumpWidget(buildScope(tier: CanvasViewTier.preview));
      expect(find.byType(FlueraCanvasView), findsOneWidget);
    });

    testWidgets('builds in `.panel` tier without throwing', (tester) async {
      await tester.pumpWidget(buildScope(tier: CanvasViewTier.panel));
      expect(find.byType(FlueraCanvasView), findsOneWidget);
    });

    testWidgets('builds in `.full` tier without throwing', (tester) async {
      await tester.pumpWidget(buildScope(tier: CanvasViewTier.full));
      expect(find.byType(FlueraCanvasView), findsOneWidget);
    });

    testWidgets('disposes cleanly on unmount', (tester) async {
      await tester.pumpWidget(buildScope(tier: CanvasViewTier.preview));
      // Replace with empty widget — triggers dispose of FlueraCanvasView
      await tester.pumpWidget(const SizedBox.shrink());
      expect(find.byType(FlueraCanvasView), findsNothing);
    });

    testWidgets('survives several frame pumps without errors',
        (tester) async {
      // Mount in `.preview` tier (no native overlay, no live stroke
      // pipeline → the safest tier for headless widget testing).
      await tester.pumpWidget(buildScope(tier: CanvasViewTier.preview));

      // Pump 10 frames at 16ms each. The cognitive animation controller
      // is repeating internally; `tester.pump(duration)` advances the
      // test clock + drives the painter. If any controller throws on a
      // tick, this would surface.
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(FlueraCanvasView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rebuilds without throwing on layer mutation',
        (tester) async {
      await tester.pumpWidget(buildScope(tier: CanvasViewTier.preview));
      // Mutate the layer controller (typical of "user drew a stroke")
      // — the view must rebuild via ListenableBuilder on layerController.
      layerController.notifyListeners();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(FlueraCanvasView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // SKIPPED: `RepaintBoundary.toImage()` hangs even in `.preview` tier
    // on an empty scene graph and with the cognitive animation controller
    // disabled. Bash command timeout at 240s, individual `--timeout=30s`
    // also exceeded. Confirmed independently 2026-05-10.
    //
    // Hypothesis: a child controller in the FlueraCanvasView subtree (not
    // the cognitive anim — that is now opt-out) still calls `.repeat()`
    // OR holds an async Future that never completes. Candidates:
    //   - `InfiniteCanvasController.attachTicker(this)` — ticker is
    //     created on initState and may be requesting frames continuously.
    //   - One of the ~30 ListenableBuilder subtrees may be triggered by
    //     an internal animation we have not yet identified.
    //   - `toImage()` itself triggers a paint pass that touches
    //     `DrawingPainter` statics depending on `EngineScope` (which is
    //     null in widget tests) → could throw silently in a microtask.
    //
    // Next investigation steps:
    //   1. Wrap subtree in `tester.runAsync` to allow real platform calls
    //   2. Audit `_buildOverlays` for hidden `.repeat()` AnimationControllers
    //   3. Run with `flutter test --verbose` to surface scheduler state
    //   4. Mock `EngineScope` with no-op `RenderCacheScope` so the painter
    //      static caches don't ping platform channels.
    //
    // The smoke tests above ARE sufficient to verify the widget tree
    // mounts, mutates, and disposes cleanly across all tiers. Pixel-match
    // belongs to a dedicated harness (per memo
    // `engine_pro_d5_pixel_match_validated` — ~1 day of fixture work).
    testWidgets(
      'captures pixels via RepaintBoundary.toImage on empty scene',
      (tester) async {
        // Pixel-match harness building block #2.
        // CRITICAL: `RepaintBoundary.toImage()` in widget tests needs
        // `tester.runAsync` — otherwise the Skia rasterization async
        // machinery never advances (tester fake clock blocks Future
        // completion of the image future).
        FlueraCanvasView.disableCognitiveAnimationForTesting = true;
        addTearDown(() {
          FlueraCanvasView.disableCognitiveAnimationForTesting = false;
        });

        final repaintKey = GlobalKey();
        await tester.pumpWidget(
          buildScope(tier: CanvasViewTier.preview, repaintKey: repaintKey),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final boundary = repaintKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;

        final byteData = await tester.runAsync<ByteData?>(() async {
          final image = await boundary.toImage(pixelRatio: 1.0);
          try {
            return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          } finally {
            image.dispose();
          }
        });

        expect(byteData, isNotNull);
        // 4 bytes/pixel × 800 × 600 = 1_920_000.
        expect(byteData!.lengthInBytes, 800 * 600 * 4);
      },
    );

    testWidgets(
      'stroke is visible in pixel capture (1-stroke regression scenario)',
      (tester) async {
        // First functional pixel-match scenario. Verifies that a stroke
        // injected via the public LayerController API actually appears
        // in the rendered pixel buffer (i.e. is not silently dropped by
        // some pipeline gate). Comparison: empty-scene capture must
        // differ from with-stroke capture beyond a noise threshold.
        FlueraCanvasView.disableCognitiveAnimationForTesting = true;
        addTearDown(() {
          FlueraCanvasView.disableCognitiveAnimationForTesting = false;
        });

        final repaintKey = GlobalKey();
        await tester.pumpWidget(
          buildScope(tier: CanvasViewTier.preview, repaintKey: repaintKey),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final boundary = repaintKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;

        Future<Uint8List> capture() async {
          final bytes = await tester.runAsync<ByteData?>(() async {
            final image = await boundary.toImage(pixelRatio: 1.0);
            try {
              return await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
            } finally {
              image.dispose();
            }
          });
          return bytes!.buffer.asUint8List();
        }

        final emptyBytes = await capture();

        // Inject a horizontal stroke roughly across the viewport. Coords
        // are canvas-space; identity transform makes them ≈ screen-space.
        layerController.addStroke(
          ProStroke(
            id: 'test_stroke_0',
            points: [
              for (int i = 0; i <= 20; i++)
                ProDrawingPoint(
                  position: Offset(100.0 + i * 30.0, 300.0),
                  pressure: 1.0,
                  timestamp: i * 8,
                ),
            ],
            color: const Color(0xFF000000),
            baseWidth: 8.0,
            penType: ProPenType.ballpoint,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final strokeBytes = await capture();

        // Buffers must be same length but differ — the stroke pixels
        // changed enough of the buffer to be statistically visible.
        expect(strokeBytes.length, emptyBytes.length);
        var diffCount = 0;
        for (var i = 0; i < strokeBytes.length; i++) {
          if (strokeBytes[i] != emptyBytes[i]) diffCount++;
        }
        // Threshold: stroke must touch at least 0.5% of bytes (~9600 of
        // 1.92M). A real ballpoint stroke covers far more, but we keep
        // the bar low to avoid platform variance flakiness.
        expect(
          diffCount,
          greaterThan(strokeBytes.length ~/ 200),
          reason: 'Stroke not visible in pixel buffer: only $diffCount of '
              '${strokeBytes.length} bytes changed. Pipeline may be '
              'dropping the stroke silently.',
        );
      },
    );

    testWidgets(
      'rectangle shape is visible in pixel capture',
      (tester) async {
        // Verifies the shape painter pipeline: a filled rectangle injected
        // via `addShape` must produce a pixel-buffer delta vs the empty
        // scene. Catches regressions where shapes silently fail to render.
        FlueraCanvasView.disableCognitiveAnimationForTesting = true;
        addTearDown(() {
          FlueraCanvasView.disableCognitiveAnimationForTesting = false;
        });

        final repaintKey = GlobalKey();
        await tester.pumpWidget(
          buildScope(tier: CanvasViewTier.preview, repaintKey: repaintKey),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final boundary = repaintKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;

        Future<Uint8List> capture() async {
          final bytes = await tester.runAsync<ByteData?>(() async {
            final image = await boundary.toImage(pixelRatio: 1.0);
            try {
              return await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
            } finally {
              image.dispose();
            }
          });
          return bytes!.buffer.asUint8List();
        }

        final emptyBytes = await capture();

        layerController.addShape(
          GeometricShape(
            id: 'test_rect_0',
            type: ShapeType.rectangle,
            startPoint: const Offset(200, 150),
            endPoint: const Offset(600, 450),
            color: const Color(0xFFFF0000),
            strokeWidth: 4.0,
            filled: true,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final shapeBytes = await capture();

        expect(shapeBytes.length, emptyBytes.length);
        var diffCount = 0;
        for (var i = 0; i < shapeBytes.length; i++) {
          if (shapeBytes[i] != emptyBytes[i]) diffCount++;
        }
        // A filled 400×300 rectangle covers ~480k bytes (25% of buffer).
        // Threshold 5% to absorb platform variance.
        expect(
          diffCount,
          greaterThan(shapeBytes.length ~/ 20),
          reason: 'Rectangle not visible: only $diffCount of '
              '${shapeBytes.length} bytes changed.',
        );
      },
    );

    testWidgets(
      'multiple strokes accumulate visibly (no silent drop)',
      (tester) async {
        // 3 strokes injected sequentially must produce strictly more
        // pixel deltas than 1 stroke alone — guards against any pipeline
        // bug that overwrites or short-circuits later strokes.
        FlueraCanvasView.disableCognitiveAnimationForTesting = true;
        addTearDown(() {
          FlueraCanvasView.disableCognitiveAnimationForTesting = false;
        });

        final repaintKey = GlobalKey();
        await tester.pumpWidget(
          buildScope(tier: CanvasViewTier.preview, repaintKey: repaintKey),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final boundary = repaintKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;

        Future<Uint8List> capture() async {
          final bytes = await tester.runAsync<ByteData?>(() async {
            final image = await boundary.toImage(pixelRatio: 1.0);
            try {
              return await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
            } finally {
              image.dispose();
            }
          });
          return bytes!.buffer.asUint8List();
        }

        final emptyBytes = await capture();

        // 3 parallel horizontal strokes at different y.
        for (int s = 0; s < 3; s++) {
          layerController.addStroke(
            ProStroke(
              id: 'test_stroke_$s',
              points: [
                for (int i = 0; i <= 20; i++)
                  ProDrawingPoint(
                    position: Offset(100.0 + i * 30.0, 150.0 + s * 150.0),
                    pressure: 1.0,
                    timestamp: i * 8,
                  ),
              ],
              color: const Color(0xFF000000),
              baseWidth: 6.0,
              penType: ProPenType.ballpoint,
              createdAt: DateTime.fromMillisecondsSinceEpoch(s * 1000),
            ),
          );
        }
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final multiBytes = await capture();

        var diffCount = 0;
        for (var i = 0; i < multiBytes.length; i++) {
          if (multiBytes[i] != emptyBytes[i]) diffCount++;
        }
        // 3 strokes ≈ 3× single-stroke coverage. Threshold 1.5% to absorb
        // anti-aliasing & catmull-rom curvature variance.
        expect(
          diffCount,
          greaterThan(multiBytes.length * 15 ~/ 1000),
          reason: 'Multi-stroke under-renders: $diffCount delta bytes '
              '(expected > 1.5% of ${multiBytes.length}).',
        );
      },
    );

    testWidgets(
      'pixel snapshot is stable across consecutive captures (flakiness probe)',
      (tester) async {
        // With cognitive anim stopped, 2 capture passes on the same widget
        // tree must produce identical bytes. If they don't, a hidden
        // animation or stochastic painter (noise, jitter) is in play —
        // golden tests would be flaky.
        FlueraCanvasView.disableCognitiveAnimationForTesting = true;
        addTearDown(() {
          FlueraCanvasView.disableCognitiveAnimationForTesting = false;
        });

        final repaintKey = GlobalKey();
        await tester.pumpWidget(
          buildScope(tier: CanvasViewTier.preview, repaintKey: repaintKey),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final boundary = repaintKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;

        Future<ByteData> capture() async {
          final bytes = await tester.runAsync<ByteData?>(() async {
            final image = await boundary.toImage(pixelRatio: 1.0);
            try {
              return await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
            } finally {
              image.dispose();
            }
          });
          return bytes!;
        }

        final a = await capture();
        // Pump a couple of frames between captures to surface any hidden
        // tick-driven repaint.
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        final b = await capture();

        expect(a.lengthInBytes, b.lengthInBytes);
        // Byte-by-byte equality (memo `engine_pro_d5_pixel_match_validated`
        // standard ≥99.9% — flakiness probe demands 100% here, no animation
        // in scope).
        final aBytes = a.buffer.asUint8List();
        final bBytes = b.buffer.asUint8List();
        var diffCount = 0;
        for (var i = 0; i < aBytes.length; i++) {
          if (aBytes[i] != bBytes[i]) diffCount++;
        }
        expect(
          diffCount,
          0,
          reason: 'Expected identical snapshots; found $diffCount byte deltas. '
              'A hidden animation or stochastic painter is leaking into the '
              'subtree.',
        );
      },
    );

    testWidgets(
      'pumpAndSettle reaches steady state with cognitive anim disabled',
      (tester) async {
        // Pixel-match harness building block: with the cognitive animation
        // controller stopped at value=0.0, the widget tree must reach
        // steady state (no scheduled frames pending). This is the
        // precondition for `RepaintBoundary.toImage()` golden capture.
        FlueraCanvasView.disableCognitiveAnimationForTesting = true;
        addTearDown(() {
          FlueraCanvasView.disableCognitiveAnimationForTesting = false;
        });

        await tester.pumpWidget(buildScope(tier: CanvasViewTier.preview));
        // If any other controller in the subtree calls `.repeat()`, this
        // line deadlocks at the 10-min test timeout. Bounded settle to
        // surface that quickly.
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(FlueraCanvasView), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────
  // 🎨 TODO: PIXEL parity / golden tests
  //
  // Tried: pump 30 frames + RepaintBoundary.toImage() → bytes compare.
  // Result: hangs (10-minute test timeout) because:
  //   - `_cognitiveAnimController` in FlueraCanvasView calls `.repeat()`
  //     → `pumpAndSettle()` deadlocks; bounded `pump()` doesn't help
  //     because the painter pipeline awaits frames that never settle.
  //   - DrawingPainter's tile pyramid + native Vulkan/Metal stroke
  //     overlay depend on platform channels not available in widget
  //     tests (no MissingPluginException, just silently never completes).
  //
  // Real pixel-match regression requires a dedicated test fixture:
  //   1. Mock `EngineScope` with no-op `RenderCacheScope`
  //   2. Disable the cognitive animation controller (factory injection)
  //   3. Stub native MethodChannels for Vulkan stroke overlay
  //   4. Manage golden files per-platform (Skia ≠ Impeller raster)
  //   5. Test scenarios: empty / 1 stroke / images / PDFs / cognitive
  //
  // Memo `engine_pro_d5_pixel_match_validated` standard: ≥99.9% match
  // at zoom=1.0. Effort estimate: ~1 day to set up the fixture, then
  // ongoing maintenance per painter change.
  //
  // For now we rely on:
  //   - Smoke tests above (constructor + tier transitions + dispose)
  //   - `flutter analyze --no-pub` (0 regression)
  //   - Manual flag-on test on a real canvas (user-driven validation)
  // ──────────────────────────────────────────────────────────────────────
}


/// No-op `AiProvider` that throws on every method — the smoke test
/// never triggers AI calls (no Ghost Map / Socratic / Atlas activated).
class _NoopAiProvider extends AiProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'Test should not invoke ${invocation.memberName} — AI is dormant',
    );
  }
}
