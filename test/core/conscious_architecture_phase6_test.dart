import 'package:flutter_test/flutter_test.dart';

import 'package:fluera_engine/src/core/conscious_architecture.dart';
import 'package:fluera_engine/src/core/adaptive_profile.dart';
import 'package:fluera_engine/src/core/engine_event.dart';
import 'package:fluera_engine/src/systems/smart_snap_engine.dart';

import 'package:fluera_engine/src/systems/intelligence_adapters.dart';

void main() {
  group('SmartSnapEngine mutable threshold (Fix 1)', () {
    test('threshold can be mutated without recreating engine', () {
      final engine = SmartSnapEngine(threshold: 8.0);
      expect(engine.threshold, 8.0);
      engine.threshold = 4.0;
      expect(engine.threshold, 4.0);
      expect(engine.gridSpacing, 0.0); // Other fields unchanged
    });

    test('gridSpacing and angleIncrement remain final', () {
      final engine = SmartSnapEngine(gridSpacing: 10.0, angleIncrement: 45.0);
      expect(engine.gridSpacing, 10.0);
      expect(engine.angleIncrement, 45.0);
    });
  });

  group('AdaptiveProfile persistence (Fix 5)', () {
    test('toJson returns expected structure', () {
      final profile = AdaptiveProfile();
      // Push some context
      profile.onContextChanged(
        EngineContext(
          activeTool: 'pen',
          zoom: 1.5,
          panVelocity: Offset.zero,
          isDrawing: true,
          strokeCount: 42,
          isPdfDocument: false,
        ),
      );
      final json = profile.toJson();
      expect(json['drawingRatio'], isA<double>());
      expect(json['zoomChangeRate'], isA<double>());
      expect(json['dominantTool'], 'pen');
      expect(json['recommendations'], isA<Map>());
    });

    test('counters serialize and deserialize correctly', () {
      final p1 = AdaptiveProfile();
      // Simulate 10 context changes with drawing
      for (int i = 0; i < 10; i++) {
        p1.onContextChanged(
          EngineContext(
            activeTool: i < 7 ? 'pen' : 'eraser',
            zoom: 1.0 + i * 0.1,
            panVelocity: Offset.zero,
            isDrawing: i < 7,
            strokeCount: 10,
            isPdfDocument: false,
          ),
        );
      }

      expect(p1.drawingRatio, greaterThan(0.5));
      expect(p1.dominantTool, 'pen');
      expect(p1.toolUsage['pen'], 7);
      expect(p1.toolUsage['eraser'], 3);
    });
  });

  // TODO: AnticipatoryTilePrefetch tests — class not yet implemented

  group('Intelligence events (Fix 3)', () {
    test('ProfileRecommendationsChangedEvent has expected fields', () {
      final event = ProfileRecommendationsChangedEvent(
        stabilizerLevel: 2,
        prefetchBias: 1.5,
      );
      expect(event.stabilizerLevel, 2);
      expect(event.prefetchBias, 1.5);
      expect(event.domain, EventDomain.intelligence);
      expect(event.source, 'ConsciousArchitecture');
    });

    test('LintCompletedEvent has expected fields', () {
      final event = LintCompletedEvent(violationCount: 3);
      expect(event.violationCount, 3);
      expect(event.domain, EventDomain.intelligence);
    });

    test('SnapThresholdChangedEvent has expected fields', () {
      final event = SnapThresholdChangedEvent(threshold: 4.5);
      expect(event.threshold, 4.5);
      expect(event.domain, EventDomain.intelligence);
    });
  });

  group('ConsciousArchitecture registration', () {
    test('find returns null for unregistered subsystem', () {
      final arch = ConsciousArchitecture();
      expect(arch.find<AdaptiveProfile>(), isNull);
    });

    test('find returns registered subsystem', () {
      final arch = ConsciousArchitecture();
      final profile = AdaptiveProfile();
      arch.register(profile);
      expect(arch.find<AdaptiveProfile>(), same(profile));
    });

    test('subsystems list contains all registered', () {
      final arch = ConsciousArchitecture();
      final profile = AdaptiveProfile();
      arch.register(profile);
      expect(arch.subsystems.length, 1);
    });

    test('notifyContextChanged propagates to all subsystems', () {
      final arch = ConsciousArchitecture();
      final profile = AdaptiveProfile();
      arch.register(profile);

      arch.notifyContextChanged(
        EngineContext(
          activeTool: 'pen',
          zoom: 2.0,
          panVelocity: Offset.zero,
          isDrawing: true,
          strokeCount: 5,
          isPdfDocument: false,
        ),
      );

      expect(profile.dominantTool, 'pen');
    });
  });

  group('SmartSnapAdapter threshold adaptation', () {
    test('snapThreshold adapts to zoom context', () {
      final adapter = SmartSnapAdapter();

      // High zoom → smaller threshold
      adapter.onContextChanged(
        EngineContext(
          activeTool: 'pen',
          zoom: 4.0,
          panVelocity: Offset.zero,
          isDrawing: false,
          strokeCount: 0,
          isPdfDocument: false,
        ),
      );
      final highZoomThreshold = adapter.snapThreshold;

      // Low zoom → larger threshold
      adapter.onContextChanged(
        EngineContext(
          activeTool: 'pen',
          zoom: 0.2,
          panVelocity: Offset.zero,
          isDrawing: false,
          strokeCount: 0,
          isPdfDocument: false,
        ),
      );
      final lowZoomThreshold = adapter.snapThreshold;

      expect(lowZoomThreshold, greaterThan(highZoomThreshold));
    });
  });
}
