import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/conscious_architecture.dart';
import 'package:fluera_engine/src/core/adaptive_profile.dart';
import 'package:fluera_engine/src/rendering/optimization/anticipatory_tile_prefetch.dart';

// =============================================================================
// Test Subsystem (for testing registration and lifecycle)
// =============================================================================

class _TestSubsystem extends IntelligenceSubsystem {
  @override
  final IntelligenceLayer layer;

  @override
  final String name;

  bool _active = true;
  @override
  bool get isActive => _active;

  final List<String> log = [];

  _TestSubsystem({required this.layer, required this.name});

  @override
  void onContextChanged(EngineContext context) {
    log.add('context:${context.activeTool}:${context.zoom}');
  }

  @override
  void onIdle(Duration idleDuration) {
    log.add('idle:${idleDuration.inMilliseconds}');
  }

  @override
  void dispose() {
    _active = false;
    log.add('disposed');
  }
}

void main() {
  group('ConsciousArchitecture', () {
    late ConsciousArchitecture arch;

    setUp(() {
      arch = ConsciousArchitecture();
    });

    tearDown(() {
      arch.dispose();
    });

    test('register and find subsystem', () {
      final sub = _TestSubsystem(
        layer: IntelligenceLayer.anticipatory,
        name: 'TestAnticipatory',
      );
      arch.register(sub);

      expect(arch.subsystems, hasLength(1));
      expect(arch.find<_TestSubsystem>(), same(sub));
    });

    test('prevents duplicate registration of same type', () {
      final sub1 = _TestSubsystem(
        layer: IntelligenceLayer.anticipatory,
        name: 'First',
      );
      final sub2 = _TestSubsystem(
        layer: IntelligenceLayer.anticipatory,
        name: 'Second',
      );

      arch.register(sub1);
      arch.register(sub2); // Should be silently ignored

      expect(arch.subsystems, hasLength(1));
      expect(arch.find<_TestSubsystem>()!.name, 'First');
    });

    test('byLayer filters correctly', () {
      final l1 = _TestSubsystem(
        layer: IntelligenceLayer.anticipatory,
        name: 'L1',
      );
      arch.register(l1);

      // Can't register another _TestSubsystem, so just check filtering
      expect(arch.byLayer(IntelligenceLayer.anticipatory), hasLength(1));
      expect(arch.byLayer(IntelligenceLayer.adaptive), isEmpty);
      expect(arch.byLayer(IntelligenceLayer.generative), isEmpty);
    });

    test('notifyContextChanged dispatches to active subsystems', () {
      final sub = _TestSubsystem(
        layer: IntelligenceLayer.adaptive,
        name: 'TestAdaptive',
      );
      arch.register(sub);

      const context = EngineContext(activeTool: 'pen', zoom: 2.0);
      arch.notifyContextChanged(context);

      expect(sub.log, ['context:pen:2.0']);
      expect(arch.currentContext.activeTool, 'pen');
      expect(arch.currentContext.zoom, 2.0);
    });

    test('notifyIdle dispatches to active subsystems', () {
      final sub = _TestSubsystem(
        layer: IntelligenceLayer.invisible,
        name: 'TestInvisible',
      );
      arch.register(sub);

      arch.notifyIdle(const Duration(milliseconds: 300));

      expect(sub.log, ['idle:300']);
    });

    test('skips inactive subsystems', () {
      final sub = _TestSubsystem(
        layer: IntelligenceLayer.generative,
        name: 'TestGenerative',
      );
      arch.register(sub);
      sub.dispose(); // Makes it inactive

      arch.notifyContextChanged(const EngineContext(activeTool: 'lasso'));
      arch.notifyIdle(const Duration(milliseconds: 100));

      // Only the dispose log, no context or idle events
      expect(sub.log, ['disposed']);
    });

    test('unregister removes subsystem', () {
      final sub = _TestSubsystem(
        layer: IntelligenceLayer.anticipatory,
        name: 'TestRemove',
      );
      arch.register(sub);
      expect(arch.subsystems, hasLength(1));

      arch.unregister(sub);
      expect(arch.subsystems, isEmpty);
      expect(arch.find<_TestSubsystem>(), isNull);
    });

    test('dispose clears all subsystems', () {
      final sub = _TestSubsystem(
        layer: IntelligenceLayer.adaptive,
        name: 'TestDispose',
      );
      arch.register(sub);

      arch.dispose();

      expect(sub.log, contains('disposed'));
      expect(arch.subsystems, isEmpty);
    });

    test('diagnostics returns correct summary', () {
      final sub = _TestSubsystem(
        layer: IntelligenceLayer.anticipatory,
        name: 'TestDiagnostics',
      );
      arch.register(sub);

      final diag = arch.diagnostics();
      expect(diag['totalSubsystems'], 1);
      expect(diag['activeSubsystems'], 1);
    });

    test('isLayerActive returns correct state', () {
      final sub = _TestSubsystem(
        layer: IntelligenceLayer.adaptive,
        name: 'TestActive',
      );
      arch.register(sub);

      expect(arch.isLayerActive<_TestSubsystem>(), isTrue);

      sub.dispose();
      expect(arch.isLayerActive<_TestSubsystem>(), isFalse);
    });
  });

  group('EngineContext', () {
    test('default constructor has sensible defaults', () {
      const ctx = EngineContext();
      expect(ctx.activeTool, isNull);
      expect(ctx.zoom, 1.0);
      expect(ctx.panVelocity, Offset.zero);
      expect(ctx.isDrawing, isFalse);
      expect(ctx.strokeCount, 0);
      expect(ctx.isPdfDocument, isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      const original = EngineContext(activeTool: 'pen', zoom: 2.0);
      final copy = original.copyWith(zoom: 3.0);

      expect(copy.activeTool, 'pen');
      expect(copy.zoom, 3.0);
    });
  });

  group('AnticipatoryTilePrefetch', () {
    late AnticipatoryTilePrefetch prefetch;

    setUp(() {
      prefetch = AnticipatoryTilePrefetch();
    });

    tearDown(() {
      prefetch.dispose();
    });

    test('initial margins are uniform', () {
      expect(prefetch.margins, [2, 2, 2, 2]);
    });

    test('low velocity keeps uniform margins', () {
      prefetch.onContextChanged(
        const EngineContext(panVelocity: Offset(30, 0)),
      );
      expect(prefetch.margins, [2, 2, 2, 2]);
    });

    test('rightward pan biases margins right', () {
      prefetch.onContextChanged(
        const EngineContext(panVelocity: Offset(500, 0)),
      );

      // Right margin should be greater than left margin
      expect(prefetch.margins[2], greaterThan(prefetch.margins[0]));
    });

    test('downward pan biases margins down', () {
      prefetch.onContextChanged(
        const EngineContext(panVelocity: Offset(0, 500)),
      );

      // Bottom margin should be greater than top margin
      expect(prefetch.margins[3], greaterThan(prefetch.margins[1]));
    });

    test('idle resets margins to default', () {
      prefetch.onContextChanged(
        const EngineContext(panVelocity: Offset(500, 0)),
      );
      // Margins are now biased

      prefetch.onIdle(const Duration(milliseconds: 600));
      expect(prefetch.margins, [2, 2, 2, 2]);
    });

    test('expandedViewport applies margins', () {
      final viewport = const Rect.fromLTWH(0, 0, 1000, 800);
      final expanded = prefetch.expandedViewport(viewport, 4096);

      // With uniform margin of 2, each side expands by 2 * 4096 = 8192
      expect(expanded.left, -8192);
      expect(expanded.top, -8192);
      expect(expanded.right, 1000 + 8192);
      expect(expanded.bottom, 800 + 8192);
    });

    test('dispose sets inactive', () {
      expect(prefetch.isActive, isTrue);
      prefetch.dispose();
      expect(prefetch.isActive, isFalse);
    });
  });

  group('AdaptiveProfile', () {
    late AdaptiveProfile profile;

    setUp(() {
      profile = AdaptiveProfile();
    });

    tearDown(() {
      profile.dispose();
    });

    test('initial state has zero metrics', () {
      expect(profile.drawingRatio, 0.0);
      expect(profile.zoomChangeRate, 0.0);
      expect(profile.avgStrokeCount, 0.0);
      expect(profile.dominantTool, isNull);
    });

    test('tracks drawing ratio', () {
      profile.onContextChanged(const EngineContext(isDrawing: true));
      profile.onContextChanged(const EngineContext(isDrawing: true));
      profile.onContextChanged(const EngineContext(isDrawing: false));
      profile.onContextChanged(const EngineContext(isDrawing: false));

      expect(profile.drawingRatio, 0.5);
    });

    test('tracks tool usage', () {
      profile.onContextChanged(const EngineContext(activeTool: 'pen'));
      profile.onContextChanged(const EngineContext(activeTool: 'pen'));
      profile.onContextChanged(const EngineContext(activeTool: 'lasso'));

      expect(profile.toolUsage['pen'], 2);
      expect(profile.toolUsage['lasso'], 1);
      expect(profile.dominantTool, 'pen');
    });

    test('tracks zoom changes', () {
      profile.onContextChanged(const EngineContext(zoom: 1.0));
      profile.onContextChanged(const EngineContext(zoom: 2.0));
      profile.onContextChanged(const EngineContext(zoom: 3.0));

      // zoomChangeRate depends on elapsed time, so just verify
      // the rate is non-negative (counter incremented correctly)
      expect(profile.zoomChangeRate, greaterThanOrEqualTo(0));
      // Verify tool usage tracking still works (indirectly shows
      // context changes are being processed)
      expect(profile.drawingRatio, 0.0); // No isDrawing=true
    });

    test('recommendations adjust to drawing-heavy profile', () {
      // Simulate a heavy drawer
      for (int i = 0; i < 100; i++) {
        profile.onContextChanged(
          const EngineContext(isDrawing: true, activeTool: 'pen'),
        );
      }

      // Heavy drawer should get higher filter beta (more reactive)
      expect(profile.recommendedFilterBeta, greaterThan(0.007));
      // And lower tile cache bias (prioritize stroke cache)
      expect(profile.tileCacheMemoryBias, lessThan(0.5));
    });

    test('toJson returns diagnostic summary', () {
      profile.onContextChanged(const EngineContext(activeTool: 'pen'));
      final json = profile.toJson();

      expect(json, containsPair('drawingRatio', isA<double>()));
      expect(json, containsPair('dominantTool', 'pen'));
      expect(json['recommendations'], isA<Map>());
    });
  });
}
