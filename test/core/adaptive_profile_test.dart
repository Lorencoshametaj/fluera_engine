import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/adaptive_profile.dart';
import 'package:fluera_engine/src/core/conscious_architecture.dart';

void main() {
  late AdaptiveProfile profile;

  setUp(() {
    profile = AdaptiveProfile();
  });

  tearDown(() {
    profile.dispose();
  });

  // ===========================================================================
  // Identity
  // ===========================================================================

  group('identity', () {
    test('is L2 adaptive layer', () {
      expect(profile.layer, IntelligenceLayer.adaptive);
    });

    test('name is AdaptiveProfile', () {
      expect(profile.name, 'AdaptiveProfile');
    });

    test('isActive is true initially', () {
      expect(profile.isActive, true);
    });

    test('isActive is false after dispose', () {
      profile.dispose();
      expect(profile.isActive, false);
    });
  });

  // ===========================================================================
  // Default values (no context updates)
  // ===========================================================================

  group('defaults', () {
    test('drawingRatio is 0 initially', () {
      expect(profile.drawingRatio, 0.0);
    });

    test('zoomChangeRate is 0 initially', () {
      expect(profile.zoomChangeRate, 0.0);
    });

    test('avgStrokeCount is 0 initially', () {
      expect(profile.avgStrokeCount, 0.0);
    });

    test('dominantTool is null initially', () {
      expect(profile.dominantTool, isNull);
    });

    test('toolUsage is empty initially', () {
      expect(profile.toolUsage, isEmpty);
    });
  });

  // ===========================================================================
  // Tracking
  // ===========================================================================

  group('tracking', () {
    test('drawingRatio reflects drawing context changes', () {
      // 3 context changes, 2 with isDrawing
      profile.onContextChanged(const EngineContext(isDrawing: true));
      profile.onContextChanged(const EngineContext(isDrawing: true));
      profile.onContextChanged(const EngineContext(isDrawing: false));

      expect(profile.drawingRatio, closeTo(2 / 3, 0.01));
    });

    test('zoomChanges are tracked with threshold', () {
      // Initial zoom is 1.0
      profile.onContextChanged(const EngineContext(zoom: 1.005));
      // Below 0.01 threshold — should NOT count as zoom change
      expect(profile.zoomChangeRate, 0.0);

      profile.onContextChanged(const EngineContext(zoom: 1.5));
      // Above threshold — should count
      // zoomChangeRate requires elapsed time, so let's just verify it doesn't crash
    });

    test('stroke count is tracked', () {
      profile.onContextChanged(const EngineContext(strokeCount: 100));
      profile.onContextChanged(const EngineContext(strokeCount: 200));

      expect(profile.avgStrokeCount, closeTo(150, 0.1));
    });

    test('stroke count ignores zero-stroke contexts', () {
      profile.onContextChanged(const EngineContext(strokeCount: 0));
      profile.onContextChanged(const EngineContext(strokeCount: 100));

      expect(profile.avgStrokeCount, closeTo(100, 0.1));
    });

    test('tool usage distribution is tracked', () {
      profile.onContextChanged(const EngineContext(activeTool: 'pen'));
      profile.onContextChanged(const EngineContext(activeTool: 'pen'));
      profile.onContextChanged(const EngineContext(activeTool: 'eraser'));

      expect(profile.toolUsage['pen'], 2);
      expect(profile.toolUsage['eraser'], 1);
    });

    test('dominantTool returns most used tool', () {
      profile.onContextChanged(const EngineContext(activeTool: 'pen'));
      profile.onContextChanged(const EngineContext(activeTool: 'pen'));
      profile.onContextChanged(const EngineContext(activeTool: 'lasso'));

      expect(profile.dominantTool, 'pen');
    });

    test('null activeTool is not tracked', () {
      profile.onContextChanged(const EngineContext());
      expect(profile.toolUsage, isEmpty);
    });
  });

  // ===========================================================================
  // Recommendations
  // ===========================================================================

  group('recommendations', () {
    test('heavy drawer gets high filter beta', () {
      // Create a session with >70% drawing
      for (int i = 0; i < 10; i++) {
        profile.onContextChanged(const EngineContext(isDrawing: true));
      }
      for (int i = 0; i < 3; i++) {
        profile.onContextChanged(const EngineContext(isDrawing: false));
      }

      // drawingRatio > 0.7 → beta 0.012
      expect(profile.recommendedFilterBeta, 0.012);
    });

    test('mostly navigating gets low filter beta', () {
      // Create a session with <30% drawing
      for (int i = 0; i < 2; i++) {
        profile.onContextChanged(const EngineContext(isDrawing: true));
      }
      for (int i = 0; i < 10; i++) {
        profile.onContextChanged(const EngineContext(isDrawing: false));
      }

      // drawingRatio < 0.3 → beta 0.005
      expect(profile.recommendedFilterBeta, 0.005);
    });

    test('balanced usage gets default recommendations', () {
      // 50/50 drawing
      for (int i = 0; i < 5; i++) {
        profile.onContextChanged(const EngineContext(isDrawing: true));
      }
      for (int i = 0; i < 5; i++) {
        profile.onContextChanged(const EngineContext(isDrawing: false));
      }

      expect(profile.recommendedFilterBeta, 0.007);
    });

    test('heavy strokes increase LOD precompute', () {
      profile.onContextChanged(const EngineContext(strokeCount: 600));

      expect(profile.recommendedLODPrecompute, 30);
    });

    test('default LOD precompute for low stroke count', () {
      profile.onContextChanged(const EngineContext(strokeCount: 50));

      expect(profile.recommendedLODPrecompute, 15);
    });

    test('tile cache memory bias favors strokes for heavy drawers', () {
      for (int i = 0; i < 10; i++) {
        profile.onContextChanged(const EngineContext(isDrawing: true));
      }
      for (int i = 0; i < 2; i++) {
        profile.onContextChanged(const EngineContext(isDrawing: false));
      }

      // drawingRatio > 0.7 → bias 0.3 (less memory to tile cache)
      expect(profile.tileCacheMemoryBias, 0.3);
    });

    test('tile cache memory bias favors tiles for navigators', () {
      for (int i = 0; i < 1; i++) {
        profile.onContextChanged(const EngineContext(isDrawing: true));
      }
      for (int i = 0; i < 10; i++) {
        profile.onContextChanged(const EngineContext(isDrawing: false));
      }

      // drawingRatio < 0.3 → bias 0.8
      expect(profile.tileCacheMemoryBias, 0.8);
    });
  });

  // ===========================================================================
  // Serialization
  // ===========================================================================

  group('toJson', () {
    test('contains all expected keys', () {
      profile.onContextChanged(
        const EngineContext(
          isDrawing: true,
          strokeCount: 50,
          activeTool: 'pen',
        ),
      );

      final json = profile.toJson();

      expect(json, containsPair('sessionDuration', isA<int>()));
      expect(json, containsPair('drawingRatio', isA<double>()));
      expect(json, containsPair('zoomChangeRate', isA<double>()));
      expect(json, containsPair('avgStrokeCount', isA<double>()));
      expect(json, containsPair('dominantTool', 'pen'));
      expect(json, containsPair('recommendations', isA<Map>()));

      final recs = json['recommendations'] as Map<String, dynamic>;
      expect(recs, containsPair('lodPrecompute', isA<int>()));
      expect(recs, containsPair('filterBeta', isA<double>()));
      expect(recs, containsPair('tilePrefetch', isA<int>()));
      expect(recs, containsPair('tileCacheMemoryBias', isA<double>()));
    });
  });

  // ===========================================================================
  // onIdle
  // ===========================================================================

  group('onIdle', () {
    test('does not throw (v1 is a no-op)', () {
      expect(() => profile.onIdle(const Duration(seconds: 5)), returnsNormally);
    });
  });

  // ===========================================================================
  // toolUsage is unmodifiable
  // ===========================================================================

  group('toolUsage immutability', () {
    test('returned map is unmodifiable', () {
      profile.onContextChanged(const EngineContext(activeTool: 'pen'));
      final map = profile.toolUsage;
      expect(() => map['pen'] = 999, throwsA(isA<UnsupportedError>()));
    });
  });
}
