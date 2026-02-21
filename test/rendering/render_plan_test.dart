import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:nebula_engine/src/rendering/scene_graph/render_plan.dart';
import 'package:nebula_engine/src/rendering/scene_graph/scene_graph_renderer.dart';
import 'package:nebula_engine/src/rendering/scene_graph/render_interceptor.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:nebula_engine/src/core/scene_graph/invalidation_graph.dart';
import 'package:nebula_engine/src/core/nodes/layer_node.dart';
import 'package:nebula_engine/src/core/nodes/shape_node.dart';
import 'package:nebula_engine/src/core/models/shape_type.dart';

// =============================================================================
// Helpers
// =============================================================================

GeometricShape _makeRect(double x, double y, double w, double h) {
  return GeometricShape(
    id: 'gs-${x.toInt()}-${y.toInt()}',
    type: ShapeType.rectangle,
    startPoint: Offset(x, y),
    endPoint: Offset(x + w, y + h),
    color: const Color(0xFF000000),
    strokeWidth: 1.0,
    createdAt: DateTime(2026),
  );
}

SceneGraph _simpleScene() {
  final graph = SceneGraph();
  final layer = LayerNode(id: NodeId('layer-1'), name: 'Layer 1');
  final shape = ShapeNode(
    id: NodeId('shape-1'),
    shape: _makeRect(10, 10, 100, 100),
  );
  layer.add(shape);
  graph.addLayer(layer);
  return graph;
}

SceneGraph _multiLayerScene() {
  final graph = SceneGraph();
  for (int i = 0; i < 5; i++) {
    final layer = LayerNode(id: NodeId('layer-$i'), name: 'Layer $i');
    for (int j = 0; j < 3; j++) {
      layer.add(
        ShapeNode(
          id: NodeId('shape-$i-$j'),
          shape: _makeRect(j * 120.0, i * 120.0, 100, 100),
        ),
      );
    }
    graph.addLayer(layer);
  }
  return graph;
}

void main() {
  group('RenderCommand', () {
    test('save/restore/skip are const singletons', () {
      const save1 = RenderCommand.save();
      const save2 = RenderCommand.save();
      expect(identical(save1, save2), isTrue);

      const restore1 = RenderCommand.restore();
      const restore2 = RenderCommand.restore();
      expect(identical(restore1, restore2), isTrue);

      const skip1 = RenderCommand.skip();
      const skip2 = RenderCommand.skip();
      expect(identical(skip1, skip2), isTrue);
    });

    test('drawNode carries node reference', () {
      final shape = ShapeNode(id: NodeId('s1'), shape: _makeRect(0, 0, 10, 10));
      final cmd = RenderCommand.drawNode(shape);
      expect(cmd.type, RenderCommandType.drawNode);
      expect(cmd.node, same(shape));
    });

    test('transform carries matrix', () {
      final m = Matrix4.translationValues(10, 20, 0);
      final cmd = RenderCommand.transform(m);
      expect(cmd.type, RenderCommandType.transform);
      expect(cmd.matrix, same(m));
    });
  });

  group('RenderPlanCompiler', () {
    test('compiles empty scene into empty plan', () {
      final graph = SceneGraph();
      final compiler = RenderPlanCompiler();
      final plan = compiler.compile(
        graph,
        const Rect.fromLTWH(0, 0, 1000, 1000),
      );
      expect(plan.commands, isEmpty);
      expect(plan.drawCount, 0);
    });

    test('compiles simple scene with save/transform/draw/restore', () {
      final graph = _simpleScene();
      final compiler = RenderPlanCompiler();
      final plan = compiler.compile(
        graph,
        const Rect.fromLTWH(0, 0, 1000, 1000),
      );

      expect(plan.commands, isNotEmpty);
      expect(plan.drawCount, greaterThan(0));

      final drawCmds =
          plan.commands
              .where((c) => c.type == RenderCommandType.drawNode)
              .toList();
      expect(drawCmds, isNotEmpty);
    });

    test('culls nodes outside viewport', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer-1'), name: 'Layer 1');
      layer.add(
        ShapeNode(
          id: NodeId('far-shape'),
          shape: _makeRect(5000, 5000, 100, 100),
        ),
      );
      graph.addLayer(layer);

      final compiler = RenderPlanCompiler();
      final plan = compiler.compile(graph, const Rect.fromLTWH(0, 0, 100, 100));

      final drawCmds =
          plan.commands
              .where((c) => c.type == RenderCommandType.drawNode)
              .toList();
      expect(drawCmds, isEmpty);
      expect(plan.culledCount, greaterThan(0));
    });

    test('multi-layer scene produces correct draw count', () {
      final graph = _multiLayerScene();
      final compiler = RenderPlanCompiler();
      final plan = compiler.compile(
        graph,
        const Rect.fromLTWH(0, 0, 2000, 2000),
      );

      // 5 layers × 3 shapes = 15 leaf nodes.
      expect(plan.drawCount, 15);
    });

    test('hidden layers are skipped', () {
      final graph = _simpleScene();
      graph.layers.first.isVisible = false;

      final compiler = RenderPlanCompiler();
      final plan = compiler.compile(
        graph,
        const Rect.fromLTWH(0, 0, 1000, 1000),
      );
      expect(plan.drawCount, 0);
    });
  });

  group('RenderPlan validity', () {
    test('valid when nothing changes', () {
      final graph = _simpleScene();
      final compiler = RenderPlanCompiler();
      final viewport = const Rect.fromLTWH(0, 0, 1000, 1000);
      final plan = compiler.compile(graph, viewport, scale: 1.0);

      expect(
        plan.isValid(
          currentGraphVersion: graph.version,
          currentViewport: viewport,
          currentScale: 1.0,
        ),
        isTrue,
      );
    });

    test('invalid when graph version changes', () {
      final graph = _simpleScene();
      final compiler = RenderPlanCompiler();
      final viewport = const Rect.fromLTWH(0, 0, 1000, 1000);
      final plan = compiler.compile(graph, viewport, scale: 1.0);

      expect(
        plan.isValid(
          currentGraphVersion: graph.version + 1,
          currentViewport: viewport,
          currentScale: 1.0,
        ),
        isFalse,
      );
    });

    test('invalid when viewport changes significantly', () {
      final graph = _simpleScene();
      final compiler = RenderPlanCompiler();
      final plan = compiler.compile(
        graph,
        const Rect.fromLTWH(0, 0, 1000, 1000),
        scale: 1.0,
      );

      expect(
        plan.isValid(
          currentGraphVersion: graph.version,
          currentViewport: const Rect.fromLTWH(500, 500, 1000, 1000),
          currentScale: 1.0,
        ),
        isFalse,
      );
    });

    test('invalid when scale changes >10%', () {
      final graph = _simpleScene();
      final compiler = RenderPlanCompiler();
      final viewport = const Rect.fromLTWH(0, 0, 1000, 1000);
      final plan = compiler.compile(graph, viewport, scale: 1.0);

      expect(
        plan.isValid(
          currentGraphVersion: graph.version,
          currentViewport: viewport,
          currentScale: 1.5,
        ),
        isFalse,
      );
    });

    test('invalid when markDirty() called', () {
      final graph = _simpleScene();
      final compiler = RenderPlanCompiler();
      final viewport = const Rect.fromLTWH(0, 0, 1000, 1000);
      final plan = compiler.compile(graph, viewport, scale: 1.0);

      plan.markDirty();

      expect(
        plan.isValid(
          currentGraphVersion: graph.version,
          currentViewport: viewport,
          currentScale: 1.0,
        ),
        isFalse,
      );
    });

    test('invalid when invalidation graph has dirty nodes', () {
      final graph = _simpleScene();
      final invGraph = InvalidationGraph();
      final compiler = RenderPlanCompiler();
      final viewport = const Rect.fromLTWH(0, 0, 1000, 1000);
      final plan = compiler.compile(graph, viewport, scale: 1.0);

      invGraph.markDirty('shape-1', DirtyFlag.paint);

      expect(
        plan.isValid(
          currentGraphVersion: graph.version,
          currentViewport: viewport,
          currentScale: 1.0,
          invalidationGraph: invGraph,
        ),
        isFalse,
      );
    });
  });

  group('RenderPlan execution', () {
    testWidgets('plan executes without errors', (tester) async {
      final graph = _simpleScene();
      final compiler = RenderPlanCompiler();
      final renderer = SceneGraphRenderer();
      final viewport = const Rect.fromLTWH(0, 0, 1000, 1000);
      final plan = compiler.compile(graph, viewport);

      await tester.pumpWidget(
        CustomPaint(
          painter: _TestPainter((canvas) {
            plan.execute(canvas, renderer);
          }),
        ),
      );
    });
  });

  group('SceneGraphRenderer with RenderPlan', () {
    testWidgets('uses cached plan when scene unchanged', (tester) async {
      final graph = _simpleScene();
      final renderer = SceneGraphRenderer();
      renderer.useRenderPlan = true;
      final viewport = const Rect.fromLTWH(0, 0, 1000, 1000);

      await tester.pumpWidget(
        CustomPaint(
          painter: _TestPainter((canvas) {
            renderer.render(canvas, graph, viewport);
          }),
        ),
      );
    });

    testWidgets('falls back to recursive path with interceptors', (
      tester,
    ) async {
      final graph = _simpleScene();
      final renderer = SceneGraphRenderer();
      renderer.useRenderPlan = true;
      renderer.addInterceptor(_NoOpInterceptor());

      await tester.pumpWidget(
        CustomPaint(
          painter: _TestPainter((canvas) {
            renderer.render(
              canvas,
              graph,
              const Rect.fromLTWH(0, 0, 1000, 1000),
            );
          }),
        ),
      );
    });

    testWidgets('invalidatePlan forces recompilation', (tester) async {
      final graph = _simpleScene();
      final renderer = SceneGraphRenderer();
      renderer.useRenderPlan = true;

      await tester.pumpWidget(
        CustomPaint(
          painter: _TestPainter((canvas) {
            renderer.render(
              canvas,
              graph,
              const Rect.fromLTWH(0, 0, 1000, 1000),
            );
            renderer.invalidatePlan();
            renderer.render(
              canvas,
              graph,
              const Rect.fromLTWH(0, 0, 1000, 1000),
            );
          }),
        ),
      );
    });

    testWidgets('invalidation graph integration clears dirty after render', (
      tester,
    ) async {
      final graph = _simpleScene();
      final invGraph = InvalidationGraph();
      final renderer = SceneGraphRenderer();
      renderer.useRenderPlan = true;
      renderer.invalidationGraph = invGraph;

      invGraph.markDirty('shape-1', DirtyFlag.paint);
      expect(invGraph.hasDirty, isTrue);

      await tester.pumpWidget(
        CustomPaint(
          painter: _TestPainter((canvas) {
            renderer.render(
              canvas,
              graph,
              const Rect.fromLTWH(0, 0, 1000, 1000),
            );
          }),
        ),
      );

      expect(invGraph.hasDirty, isFalse);
    });
  });
}

// =============================================================================
// Test helpers
// =============================================================================

class _TestPainter extends CustomPainter {
  final void Function(Canvas canvas) _paintCallback;
  _TestPainter(this._paintCallback);

  @override
  void paint(Canvas canvas, Size size) => _paintCallback(canvas);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _NoOpInterceptor extends RenderInterceptor {
  @override
  void intercept(
    Canvas canvas,
    CanvasNode node,
    Rect viewport,
    RenderNext next,
  ) {
    next(canvas, node, viewport);
  }
}
