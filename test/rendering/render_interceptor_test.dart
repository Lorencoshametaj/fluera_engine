import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/rendering/scene_graph/render_interceptor.dart';
import 'package:nebula_engine/src/rendering/scene_graph/scene_graph_renderer.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph.dart';
import 'package:nebula_engine/src/core/nodes/layer_node.dart';
import 'package:nebula_engine/src/core/nodes/shape_node.dart';
import 'package:nebula_engine/src/core/engine_scope.dart';

// =============================================================================
// Test helpers
// =============================================================================

/// Records calls for verification.
class _RecordingInterceptor extends RenderInterceptor {
  final List<String> log = [];
  final bool callNext;

  _RecordingInterceptor({this.callNext = true});

  @override
  void intercept(
    Canvas canvas,
    CanvasNode node,
    Rect viewport,
    RenderNext next,
  ) {
    log.add('intercept:${node.id}');
    if (callNext) next(canvas, node, viewport);
  }

  @override
  void onFrameStart() => log.add('frameStart');

  @override
  void onFrameEnd() => log.add('frameEnd');
}

/// Helper to build a simple scene for testing.
SceneGraph _simpleScene() {
  final graph = SceneGraph();
  final layer = LayerNode(id: NodeId('layer-1'), name: 'Layer 1');
  layer.isVisible = true;
  graph.addLayer(layer);
  return graph;
}

void main() {
  late SceneGraphRenderer renderer;

  setUp(() {
    renderer = SceneGraphRenderer();
  });

  group('Interceptor management', () {
    test('starts with no interceptors', () {
      expect(renderer.interceptors, isEmpty);
    });

    test('addInterceptor registers interceptor', () {
      final i = _RecordingInterceptor();
      renderer.addInterceptor(i);
      expect(renderer.interceptors, hasLength(1));
      expect(renderer.interceptors.first, same(i));
    });

    test('removeInterceptor unregisters interceptor', () {
      final i = _RecordingInterceptor();
      renderer.addInterceptor(i);
      renderer.removeInterceptor(i);
      expect(renderer.interceptors, isEmpty);
    });

    test('clearInterceptors removes all', () {
      renderer.addInterceptor(_RecordingInterceptor());
      renderer.addInterceptor(_RecordingInterceptor());
      renderer.clearInterceptors();
      expect(renderer.interceptors, isEmpty);
    });

    test('interceptors list is unmodifiable', () {
      expect(
        () => renderer.interceptors.add(_RecordingInterceptor()),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('Interceptor chain execution', () {
    testWidgets('interceptors called in order', (tester) async {
      final i1 = _RecordingInterceptor();
      final i2 = _RecordingInterceptor();
      renderer.addInterceptor(i1);
      renderer.addInterceptor(i2);

      final scene = _simpleScene();

      await tester.pumpWidget(
        CustomPaint(
          painter: _TestPainter((canvas) {
            renderer.render(
              canvas,
              scene,
              const Rect.fromLTWH(0, 0, 1000, 1000),
            );
          }),
        ),
      );

      // Both interceptors should see frameStart, the layer node, frameEnd
      expect(i1.log, ['frameStart', 'intercept:layer-1', 'frameEnd']);
      expect(i2.log, ['frameStart', 'intercept:layer-1', 'frameEnd']);
    });

    testWidgets('interceptor can skip node by not calling next', (
      tester,
    ) async {
      final skipper = _RecordingInterceptor(callNext: false);
      final after = _RecordingInterceptor();
      renderer.addInterceptor(skipper);
      renderer.addInterceptor(after);

      final scene = _simpleScene();

      await tester.pumpWidget(
        CustomPaint(
          painter: _TestPainter((canvas) {
            renderer.render(
              canvas,
              scene,
              const Rect.fromLTWH(0, 0, 1000, 1000),
            );
          }),
        ),
      );

      // Skipper intercepts but doesn't pass to next
      expect(skipper.log, contains('intercept:layer-1'));
      // After never sees the node (but still gets frame lifecycle)
      expect(after.log.where((l) => l.startsWith('intercept')), isEmpty);
    });

    testWidgets('onFrameStart and onFrameEnd called exactly once', (
      tester,
    ) async {
      final i = _RecordingInterceptor();
      renderer.addInterceptor(i);

      final scene = _simpleScene();

      await tester.pumpWidget(
        CustomPaint(
          painter: _TestPainter((canvas) {
            renderer.render(
              canvas,
              scene,
              const Rect.fromLTWH(0, 0, 1000, 1000),
            );
          }),
        ),
      );

      expect(i.log.where((l) => l == 'frameStart'), hasLength(1));
      expect(i.log.where((l) => l == 'frameEnd'), hasLength(1));
    });

    testWidgets('zero overhead when no interceptors', (tester) async {
      // Just verify no errors when rendering without interceptors
      final scene = _simpleScene();

      await tester.pumpWidget(
        CustomPaint(
          painter: _TestPainter((canvas) {
            renderer.render(
              canvas,
              scene,
              const Rect.fromLTWH(0, 0, 1000, 1000),
            );
          }),
        ),
      );

      // No crash = success
    });
  });

  group('NodeFilterInterceptor', () {
    testWidgets('filters nodes by predicate', (tester) async {
      final recorder = _RecordingInterceptor();
      renderer.addInterceptor(
        NodeFilterInterceptor((node) => node.id != 'layer-1'),
      );
      renderer.addInterceptor(recorder);

      final scene = _simpleScene();

      await tester.pumpWidget(
        CustomPaint(
          painter: _TestPainter((canvas) {
            renderer.render(
              canvas,
              scene,
              const Rect.fromLTWH(0, 0, 1000, 1000),
            );
          }),
        ),
      );

      // layer-1 is filtered out, so recorder never sees it
      expect(recorder.log.where((l) => l.startsWith('intercept')), isEmpty);
    });
  });

  group('RenderProfilingInterceptor', () {
    testWidgets('counts rendered nodes', (tester) async {
      EngineScope.reset();
      EngineScope.push(EngineScope());

      final profiler = RenderProfilingInterceptor();
      renderer.addInterceptor(profiler);

      final scene = _simpleScene();

      await tester.pumpWidget(
        CustomPaint(
          painter: _TestPainter((canvas) {
            renderer.render(
              canvas,
              scene,
              const Rect.fromLTWH(0, 0, 1000, 1000),
            );
          }),
        ),
      );

      final t = EngineScope.current.telemetry;
      expect(t.counter('render.nodes').value, greaterThan(0));

      EngineScope.reset();
    });
  });
}

/// Simple CustomPainter that runs a callback for testing.
class _TestPainter extends CustomPainter {
  final void Function(Canvas canvas) _paintCallback;

  _TestPainter(this._paintCallback);

  @override
  void paint(Canvas canvas, Size size) => _paintCallback(canvas);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
