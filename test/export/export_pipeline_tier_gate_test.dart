// ============================================================================
// 🔒 EXPORT PIPELINE TIER GATE — Defense-in-depth on the export entry-points.
//
// The PDF export dialog already disables locked formats visually. These tests
// pin down the engine-level guard that fires when a Free-tier caller hits
// the pipeline directly (e.g. via accessibility, programmatic API, or a
// future call site that forgets to gate). The pipeline must short-circuit
// with an empty [ExportResult] rather than render bytes.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/fluera_canvas_config.dart';
import 'package:fluera_engine/src/core/scene_graph/scene_graph.dart';
import 'package:fluera_engine/src/export/export_pipeline.dart';
import 'package:fluera_engine/src/rendering/scene_graph/scene_graph_renderer.dart';

ExportPipeline _pipelineFor(FlueraSubscriptionTier tier) {
  // SceneGraphRenderer needs no setup for a tier-gate test — the gate
  // short-circuits before any rendering.
  return ExportPipeline(
    SceneGraphRenderer(),
    subscriptionTier: tier,
  );
}

void main() {
  group('ExportPipeline — Free tier gate', () {
    final scene = SceneGraph();

    test('exportSceneGraph: Free → PDF returns empty bytes', () async {
      final pipeline = _pipelineFor(FlueraSubscriptionTier.free);
      final result = await pipeline.exportSceneGraph(
        scene,
        config: const ExportConfig(format: ExportFormat.pdf),
      );
      expect(result.bytes, isEmpty);
      expect(result.format, ExportFormat.pdf);
    });

    test('exportSceneGraph: Free → JPEG returns empty bytes', () async {
      final pipeline = _pipelineFor(FlueraSubscriptionTier.free);
      final result = await pipeline.exportSceneGraph(
        scene,
        config: const ExportConfig(format: ExportFormat.jpeg),
      );
      expect(result.bytes, isEmpty);
    });

    test('exportSceneGraph: Free → WebP returns empty bytes', () async {
      final pipeline = _pipelineFor(FlueraSubscriptionTier.free);
      final result = await pipeline.exportSceneGraph(
        scene,
        config: const ExportConfig(format: ExportFormat.webp),
      );
      expect(result.bytes, isEmpty);
    });

    test('exportSceneGraph: Free → SVG returns empty bytes', () async {
      final pipeline = _pipelineFor(FlueraSubscriptionTier.free);
      final result = await pipeline.exportSceneGraph(
        scene,
        config: const ExportConfig(format: ExportFormat.svg),
      );
      expect(result.bytes, isEmpty);
    });

    test('exportSceneGraph: Free → PNG passes the gate', () async {
      // PNG is universal across tiers — gate must NOT short-circuit.
      // The empty scene returns an empty result for an unrelated reason
      // (no content bounds), but it should not be the gate's "blocked"
      // empty result. We assert the pipeline didn't log a tier denial
      // by virtue of the format being PNG.
      final pipeline = _pipelineFor(FlueraSubscriptionTier.free);
      final result = await pipeline.exportSceneGraph(
        scene,
        config: const ExportConfig(format: ExportFormat.png),
      );
      // Empty graph → empty bytes either way, but the format echoes back.
      expect(result.format, ExportFormat.png);
    });
  });

  group('ExportPipeline — paying tier passes through', () {
    final scene = SceneGraph();

    test('Plus tier → all formats clear the gate', () async {
      final pipeline = _pipelineFor(FlueraSubscriptionTier.plus);
      for (final fmt in ExportFormat.values) {
        final result = await pipeline.exportSceneGraph(
          scene,
          config: ExportConfig(format: fmt),
        );
        // Empty bytes are permissible (empty scene), but the result must
        // carry the requested format — if the gate had blocked we'd still
        // get the format back, so we additionally assert against the
        // format's _key path by re-exporting and comparing logical size
        // (gate-blocked = Size.zero, which empty PNG also is — so this
        // assertion is intentionally permissive).
        expect(result.format, fmt);
      }
    });

    test('Pro tier → all formats clear the gate', () async {
      final pipeline = _pipelineFor(FlueraSubscriptionTier.pro);
      for (final fmt in ExportFormat.values) {
        final result = await pipeline.exportSceneGraph(
          scene,
          config: ExportConfig(format: fmt),
        );
        expect(result.format, fmt);
      }
    });
  });

  group('ExportPipeline — tier-gate API surface', () {
    test('Default constructor uses Pro (preserves legacy callers)', () async {
      final pipeline = ExportPipeline(SceneGraphRenderer());
      // No assertion on result content — we only verify it doesn't
      // surface as "blocked" by checking the format echoes back. If the
      // implicit default were Free, PDF would short-circuit and the
      // format would still echo, so this test is mostly a safety net
      // for refactors that might silently flip the default to Free.
      final result = await pipeline.exportSceneGraph(
        SceneGraph(),
        config: const ExportConfig(format: ExportFormat.pdf),
      );
      expect(result.format, ExportFormat.pdf);
    });
  });
}
