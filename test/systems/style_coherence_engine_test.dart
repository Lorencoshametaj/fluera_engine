import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/conscious_architecture.dart';
import 'package:fluera_engine/src/core/engine_event.dart';
import 'package:fluera_engine/src/core/engine_event_bus.dart';
import 'package:fluera_engine/src/systems/style_coherence_engine.dart';

void main() {
  group('StyleCoherenceEngine', () {
    late StyleCoherenceEngine engine;

    setUp(() => engine = StyleCoherenceEngine());
    tearDown(() => engine.dispose());

    test('belongs to generative layer', () {
      expect(engine.layer, IntelligenceLayer.generative);
      expect(engine.name, 'StyleCoherence');
      expect(engine.isActive, isTrue);
    });

    test('no recommendations when empty', () {
      expect(engine.recommendedColor('pen'), isNull);
      expect(engine.recommendedStrokeWidth('pen'), isNull);
      expect(engine.recommendedOpacity('pen'), isNull);
      expect(engine.documentPalette, isEmpty);
      expect(engine.recentColors, isEmpty);
      expect(engine.trackedTools, isEmpty);
    });

    test('recommends most-used color for tool', () {
      const blue = Color(0xFF2D5BFF);
      const red = Color(0xFFE94560);

      engine.recordStyleUsage('pen', color: blue);
      engine.recordStyleUsage('pen', color: blue);
      engine.recordStyleUsage('pen', color: blue);
      engine.recordStyleUsage('pen', color: red);

      expect(engine.recommendedColor('pen'), blue);
    });

    test('recommends average stroke width for tool', () {
      engine.recordStyleUsage('pen', strokeWidth: 2.0);
      engine.recordStyleUsage('pen', strokeWidth: 4.0);
      engine.recordStyleUsage('pen', strokeWidth: 6.0);

      expect(engine.recommendedStrokeWidth('pen'), 4.0);
    });

    test('recommends average opacity for tool', () {
      engine.recordStyleUsage('pen', opacity: 0.5);
      engine.recordStyleUsage('pen', opacity: 1.0);
      engine.recordStyleUsage('pen', opacity: 0.8);

      expect(engine.recommendedOpacity('pen'), closeTo(0.7667, 0.001));
    });

    test('ignores out-of-range opacity', () {
      engine.recordStyleUsage('pen', opacity: 0.0);
      engine.recordStyleUsage('pen', opacity: 1.5);
      expect(engine.recommendedOpacity('pen'), isNull);
    });

    test('maintains separate profiles per tool', () {
      const blue = Color(0xFF2D5BFF);
      const green = Color(0xFF00FF88);

      engine.recordStyleUsage(
        'pen',
        color: blue,
        strokeWidth: 2.0,
        opacity: 0.9,
      );
      engine.recordStyleUsage(
        'shape',
        color: green,
        strokeWidth: 4.0,
        opacity: 0.5,
      );

      expect(engine.recommendedColor('pen'), blue);
      expect(engine.recommendedColor('shape'), green);
      expect(engine.recommendedStrokeWidth('pen'), 2.0);
      expect(engine.recommendedStrokeWidth('shape'), 4.0);
      expect(engine.recommendedOpacity('pen'), 0.9);
      expect(engine.recommendedOpacity('shape'), 0.5);
      expect(engine.trackedTools, containsAll(['pen', 'shape']));
    });

    test('builds document palette on idle', () {
      const c1 = Color(0xFF111111);
      const c2 = Color(0xFF222222);
      const c3 = Color(0xFF333333);

      for (int i = 0; i < 5; i++) {
        engine.recordStyleUsage('pen', color: c1);
      }
      for (int i = 0; i < 3; i++) {
        engine.recordStyleUsage('shape', color: c2);
      }
      engine.recordStyleUsage('pen', color: c3);

      engine.onIdle(const Duration(milliseconds: 300));

      final palette = engine.documentPalette;
      expect(palette, hasLength(3));
      expect(palette[0], c1);
      expect(palette[1], c2);
      expect(palette[2], c3);
    });

    test('palette caps at maxPaletteSize', () {
      for (int i = 0; i < 7; i++) {
        engine.recordStyleUsage('pen', color: Color(0xFF000000 + i));
      }

      engine.onIdle(const Duration(milliseconds: 300));

      expect(
        engine.documentPalette.length,
        lessThanOrEqualTo(StyleCoherenceEngine.maxPaletteSize),
      );
    });

    test('palette merges colors across tools', () {
      const blue = Color(0xFF0000FF);

      engine.recordStyleUsage('pen', color: blue);
      engine.recordStyleUsage('pen', color: blue);
      engine.recordStyleUsage('shape', color: blue);

      engine.onIdle(const Duration(milliseconds: 300));

      expect(engine.documentPalette, contains(blue));
    });

    test('ignores zero stroke width', () {
      engine.recordStyleUsage('pen', strokeWidth: 0);
      expect(engine.recommendedStrokeWidth('pen'), isNull);
    });

    // ─── Recent Colors ───

    test('tracks recent colors in chronological order', () {
      const c1 = Color(0xFFAA0000);
      const c2 = Color(0xFF00BB00);
      const c3 = Color(0xFF0000CC);

      engine.recordStyleUsage('pen', color: c1);
      engine.recordStyleUsage('pen', color: c2);
      engine.recordStyleUsage('pen', color: c3);

      final recent = engine.recentColors;
      expect(recent, hasLength(3));
      expect(recent[0], c3);
      expect(recent[1], c2);
      expect(recent[2], c1);
    });

    test('recent colors deduplicates', () {
      const c1 = Color(0xFFAA0000);
      const c2 = Color(0xFF00BB00);

      engine.recordStyleUsage('pen', color: c1);
      engine.recordStyleUsage('pen', color: c2);
      engine.recordStyleUsage('pen', color: c1);

      final recent = engine.recentColors;
      expect(recent, hasLength(2));
      expect(recent[0], c1);
      expect(recent[1], c2);
    });

    test('recent colors caps at maxRecentColors', () {
      for (int i = 0; i < 12; i++) {
        engine.recordStyleUsage('pen', color: Color(0xFF000000 + i));
      }

      expect(
        engine.recentColors.length,
        lessThanOrEqualTo(StyleCoherenceEngine.maxRecentColors),
      );
    });

    // ─── Tool Switch Callback ───

    test('fires onToolSwitchRecommendation on tool change', () {
      const blue = Color(0xFF2D5BFF);
      engine.recordStyleUsage(
        'pen',
        color: blue,
        strokeWidth: 3.0,
        opacity: 0.8,
      );

      Color? receivedColor;
      double? receivedWidth;
      double? receivedOpacity;
      engine.onToolSwitchRecommendation = (c, w, o) {
        receivedColor = c;
        receivedWidth = w;
        receivedOpacity = o;
      };

      engine.onContextChanged(const EngineContext(activeTool: 'pen'));

      expect(receivedColor, blue);
      expect(receivedWidth, 3.0);
      expect(receivedOpacity, 0.8);
    });

    test('does not fire recommendation for tool without data', () {
      bool called = false;
      engine.onToolSwitchRecommendation = (_, __, ___) => called = true;

      engine.onContextChanged(const EngineContext(activeTool: 'unknown'));
      expect(called, isFalse);
    });

    test('does not fire on same tool', () {
      engine.recordStyleUsage('pen', color: const Color(0xFF000000));
      int callCount = 0;
      engine.onToolSwitchRecommendation = (_, __, ___) => callCount++;

      engine.onContextChanged(const EngineContext(activeTool: 'pen'));
      engine.onContextChanged(const EngineContext(activeTool: 'pen'));

      expect(callCount, 1);
    });

    // ─── Manual-Change Guard ───

    test('manual override suppresses auto-apply', () {
      const blue = Color(0xFF2D5BFF);
      engine.recordStyleUsage('pen', color: blue, strokeWidth: 3.0);

      engine.markManualOverride('pen');

      bool called = false;
      engine.onToolSwitchRecommendation = (_, __, ___) => called = true;

      engine.onContextChanged(const EngineContext(activeTool: 'pen'));

      expect(called, isFalse);
      expect(engine.hasManualOverride('pen'), isTrue);
    });

    test('clearManualOverride re-enables auto-apply', () {
      engine.recordStyleUsage('pen', color: const Color(0xFF000000));
      engine.markManualOverride('pen');
      engine.clearManualOverride('pen');

      bool called = false;
      engine.onToolSwitchRecommendation = (_, __, ___) => called = true;
      engine.onContextChanged(const EngineContext(activeTool: 'pen'));

      expect(called, isTrue);
    });

    test('clearAllManualOverrides clears all', () {
      engine.markManualOverride('pen');
      engine.markManualOverride('shape');
      engine.clearAllManualOverrides();

      expect(engine.hasManualOverride('pen'), isFalse);
      expect(engine.hasManualOverride('shape'), isFalse);
    });

    // ─── Temporal Decay ───

    test('decay reduces color frequency', () {
      const blue = Color(0xFF2D5BFF);
      // Record 10 usages
      for (int i = 0; i < 10; i++) {
        engine.recordStyleUsage('pen', color: blue);
      }

      // Run 5 idle cycles to trigger decay
      for (int i = 0; i < 5; i++) {
        engine.onIdle(const Duration(milliseconds: 300));
      }

      // After decay (0.9×), frequency should be ~9.0 (10 * 0.9)
      // dominantColor should still be blue (it's the only color)
      expect(engine.recommendedColor('pen'), blue);
    });

    test('decay prunes low-frequency colors', () {
      // Record a color just once → freq = 1
      engine.recordStyleUsage('pen', color: const Color(0xFFAAAAAA));

      // Run many decay cycles: 1 * 0.9^n → eventually < 0.5
      // (0.9^7 = 0.478 → pruned after ~7 decay rounds = 35 idle calls)
      for (int i = 0; i < 50; i++) {
        engine.onIdle(const Duration(milliseconds: 300));
      }

      // The single-use color should have been pruned
      expect(engine.recommendedColor('pen'), isNull);
    });

    // ─── Per-Document Identity ───

    test('setCanvasId and canvasId accessors', () {
      expect(engine.canvasId, isNull);
      engine.setCanvasId('doc_123');
      expect(engine.canvasId, 'doc_123');
    });

    // ─── EventBus Integration ───

    test('emits StyleRecommendationEvent on tool switch', () async {
      const blue = Color(0xFF2D5BFF);
      engine.recordStyleUsage('pen', color: blue);

      final bus = EngineEventBus();
      engine.eventBus = bus;

      final future = expectLater(
        bus.on<StyleRecommendationEvent>(),
        emits(
          isA<StyleRecommendationEvent>()
              .having((e) => e.tool, 'tool', 'pen')
              .having((e) => e.color, 'color', blue)
              .having((e) => e.domain, 'domain', EventDomain.intelligence),
        ),
      );

      engine.onContextChanged(const EngineContext(activeTool: 'pen'));

      await future;
      bus.dispose();
    });

    test('does not emit event when manual override is active', () async {
      engine.recordStyleUsage('pen', color: const Color(0xFF000000));
      engine.markManualOverride('pen');

      final bus = EngineEventBus();
      engine.eventBus = bus;

      final events = <StyleRecommendationEvent>[];
      final sub = bus.on<StyleRecommendationEvent>().listen(
        (e) => events.add(e),
      );

      engine.onContextChanged(const EngineContext(activeTool: 'pen'));

      // Give async stream time to deliver (if there were an event).
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);

      await sub.cancel();
      bus.dispose();
    });

    // ─── Lifecycle ───

    test('idle with short duration does not recompute', () {
      engine.recordStyleUsage('pen', color: const Color(0xFFFF0000));

      engine.onIdle(const Duration(milliseconds: 50));
      expect(engine.documentPalette, isEmpty);

      engine.onIdle(const Duration(milliseconds: 300));
      expect(engine.documentPalette, hasLength(1));
    });

    test('dispose clears state', () {
      engine.recordStyleUsage('pen', color: const Color(0xFFFF0000));
      engine.markManualOverride('pen');
      engine.setCanvasId('doc_1');
      engine.onIdle(const Duration(milliseconds: 300));
      expect(engine.documentPalette, isNotEmpty);
      expect(engine.recentColors, isNotEmpty);

      engine.dispose();
      expect(engine.isActive, isFalse);
      expect(engine.documentPalette, isEmpty);
      expect(engine.recentColors, isEmpty);
      expect(engine.trackedTools, isEmpty);
      expect(engine.onToolSwitchRecommendation, isNull);
      expect(engine.eventBus, isNull);
      expect(engine.canvasId, isNull);
      expect(engine.hasManualOverride('pen'), isFalse);
    });

    test('toJson returns diagnostic summary', () {
      engine.recordStyleUsage(
        'pen',
        color: const Color(0xFF2D5BFF),
        strokeWidth: 2.0,
        opacity: 0.9,
      );
      engine.setCanvasId('my_doc');
      engine.markManualOverride('pen');
      engine.onIdle(const Duration(milliseconds: 300));

      final json = engine.toJson();
      expect(json['canvasId'], 'my_doc');
      expect(json['trackedTools'], contains('pen'));
      expect(json['paletteSize'], 1);
      expect(json['recentColorCount'], 1);
      expect(json['manualOverrides'], contains('pen'));
      expect(json['documentPalette'], isA<List>());
      expect(json['profiles'], isA<Map>());
      expect(json['profiles']['pen'], isA<Map>());
      expect(json['profiles']['pen']['averageOpacity'], closeTo(0.9, 0.001));
    });
  });

  group('ConsciousArchitecture integration', () {
    test('registers and queries correctly', () {
      final arch = ConsciousArchitecture();
      final engine = StyleCoherenceEngine();

      arch.register(engine);

      expect(arch.byLayer(IntelligenceLayer.generative), hasLength(1));
      expect(arch.find<StyleCoherenceEngine>(), same(engine));

      arch.notifyContextChanged(const EngineContext(activeTool: 'pen'));
      arch.notifyIdle(const Duration(milliseconds: 300));

      arch.dispose();
    });
  });
}
