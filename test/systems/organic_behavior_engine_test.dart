import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/systems/organic_behavior_engine.dart';
import 'package:fluera_engine/src/core/conscious_architecture.dart';

void main() {
  group('OrganicBehaviorEngine', () {
    late OrganicBehaviorEngine engine;

    setUp(() {
      engine = OrganicBehaviorEngine();
    });

    tearDown(() {
      engine.dispose();
    });

    test('registers as L2 Adaptive subsystem', () {
      expect(engine.layer, IntelligenceLayer.adaptive);
      expect(engine.name, 'OrganicBehaviorEngine');
      expect(engine.isActive, isTrue);
    });

    test('static intensity returns 0 by default', () {
      // No context change yet
      expect(OrganicBehaviorEngine.intensity, 0.0);
    });

    test('drawing tool context enables organicity', () {
      engine.onContextChanged(
        const EngineContext(activeTool: 'pen', isDrawing: true, zoom: 1.0),
      );
      expect(OrganicBehaviorEngine.intensity, 1.0);
    });

    test('non-drawing tool disables organicity', () {
      engine.onContextChanged(
        const EngineContext(activeTool: 'lasso', isDrawing: false, zoom: 1.0),
      );
      expect(OrganicBehaviorEngine.intensity, 0.0);
    });

    test('PDF document disables organicity', () {
      engine.onContextChanged(
        const EngineContext(
          activeTool: 'pen',
          isDrawing: true,
          isPdfDocument: true,
        ),
      );
      expect(OrganicBehaviorEngine.intensity, 0.0);
    });

    test('low zoom reduces intensity when not drawing', () {
      engine.onContextChanged(
        const EngineContext(activeTool: 'pencil', isDrawing: false, zoom: 0.2),
      );
      expect(OrganicBehaviorEngine.intensity, 0.0);
    });

    test('active drawing overrides zoom factor', () {
      engine.onContextChanged(
        const EngineContext(activeTool: 'pencil', isDrawing: true, zoom: 0.1),
      );
      // While drawing, intensity is always 1.0 regardless of zoom
      expect(OrganicBehaviorEngine.intensity, 1.0);
    });

    test('mid zoom gives partial intensity when not drawing', () {
      engine.onContextChanged(
        const EngineContext(
          activeTool: 'fountain',
          isDrawing: false,
          zoom: 0.65,
        ),
      );
      expect(OrganicBehaviorEngine.intensity, greaterThan(0.0));
      expect(OrganicBehaviorEngine.intensity, lessThan(1.0));
    });

    test('dispose clears static reference', () {
      engine.onContextChanged(
        const EngineContext(activeTool: 'pen', isDrawing: true),
      );
      expect(OrganicBehaviorEngine.intensity, 1.0);
      engine.dispose();
      expect(OrganicBehaviorEngine.intensity, 0.0);
    });

    test('configure toggles individual behaviors', () {
      engine.onContextChanged(
        const EngineContext(activeTool: 'pen', isDrawing: true),
      );
      expect(OrganicBehaviorEngine.tremorEnabled, isTrue);
      expect(OrganicBehaviorEngine.physicsInkEnabled, isTrue);

      engine.configure(tremor: false);
      expect(OrganicBehaviorEngine.tremorEnabled, isFalse);
      expect(OrganicBehaviorEngine.physicsInkEnabled, isTrue);

      engine.configure(physicsInk: false, elasticStabilizer: false);
      expect(OrganicBehaviorEngine.physicsInkEnabled, isFalse);
      expect(OrganicBehaviorEngine.elasticStabilizerEnabled, isFalse);
    });

    test('registers in ConsciousArchitecture', () {
      final arch = ConsciousArchitecture();
      arch.register(engine);
      expect(arch.find<OrganicBehaviorEngine>(), isNotNull);
      expect(arch.byLayer(IntelligenceLayer.adaptive), contains(engine));
    });
  });
}
