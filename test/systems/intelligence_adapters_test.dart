import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/conscious_architecture.dart';
import 'package:fluera_engine/src/systems/intelligence_adapters.dart';

void main() {
  group('SmartSnapAdapter', () {
    late SmartSnapAdapter adapter;

    setUp(() => adapter = SmartSnapAdapter());
    tearDown(() => adapter.dispose());

    test('belongs to invisible layer', () {
      expect(adapter.layer, IntelligenceLayer.invisible);
      expect(adapter.name, 'SmartSnap');
    });

    test('default threshold is 8px', () {
      expect(adapter.snapThreshold, 8.0);
    });

    test('reduces threshold at high zoom', () {
      adapter.onContextChanged(const EngineContext(zoom: 5.0));
      expect(adapter.snapThreshold, 4.0);
    });

    test('increases threshold at low zoom', () {
      adapter.onContextChanged(const EngineContext(zoom: 0.1));
      expect(adapter.snapThreshold, 16.0);
    });

    test('normal threshold at normal zoom', () {
      adapter.onContextChanged(const EngineContext(zoom: 1.0));
      expect(adapter.snapThreshold, 8.0);
    });

    test('dispose deactivates', () {
      expect(adapter.isActive, isTrue);
      adapter.dispose();
      expect(adapter.isActive, isFalse);
    });
  });

  group('SmartAnimateAdapter', () {
    late SmartAnimateAdapter adapter;

    setUp(() => adapter = SmartAnimateAdapter());
    tearDown(() => adapter.dispose());

    test('belongs to invisible layer', () {
      expect(adapter.layer, IntelligenceLayer.invisible);
      expect(adapter.name, 'SmartAnimate');
    });

    test('lifecycle works without errors', () {
      adapter.onContextChanged(const EngineContext(activeTool: 'prototype'));
      adapter.onIdle(const Duration(seconds: 1));
      adapter.dispose();
      expect(adapter.isActive, isFalse);
    });
  });

  group('AccessibilityAdapter', () {
    late AccessibilityAdapter adapter;
    late List<String> announcements;
    late int rebuildCount;

    setUp(() {
      adapter = AccessibilityAdapter();
      announcements = [];
      rebuildCount = 0;
      adapter.onAnnounce = (msg) => announcements.add(msg);
      adapter.onNeedsRebuild = () => rebuildCount++;
    });

    tearDown(() => adapter.dispose());

    test('belongs to invisible layer', () {
      expect(adapter.layer, IntelligenceLayer.invisible);
      expect(adapter.name, 'Accessibility');
    });

    test('announces tool changes', () {
      adapter.onContextChanged(const EngineContext(activeTool: 'pen'));
      expect(announcements, ['Tool: pen']);

      adapter.onContextChanged(const EngineContext(activeTool: 'lasso'));
      expect(announcements, ['Tool: pen', 'Tool: lasso']);
    });

    test('does not announce same tool twice', () {
      adapter.onContextChanged(const EngineContext(activeTool: 'pen'));
      adapter.onContextChanged(const EngineContext(activeTool: 'pen'));
      expect(announcements, hasLength(1));
    });

    test('skips announcements when null tool', () {
      adapter.onContextChanged(const EngineContext());
      expect(announcements, isEmpty);
    });

    test('triggers rebuild on idle > 300ms', () {
      adapter.onIdle(const Duration(milliseconds: 100));
      expect(rebuildCount, 0);

      adapter.onIdle(const Duration(milliseconds: 400));
      expect(rebuildCount, 1);
    });

    test('dispose clears callbacks', () {
      adapter.dispose();
      expect(adapter.isActive, isFalse);
      expect(adapter.onAnnounce, isNull);
      expect(adapter.onNeedsRebuild, isNull);
    });
  });

  group('DesignLinterAdapter', () {
    late DesignLinterAdapter adapter;
    late int lintCallCount;

    setUp(() {
      adapter = DesignLinterAdapter();
      lintCallCount = 0;
      adapter.onLintRequested = () {
        lintCallCount++;
        return 3; // Simulate 3 violations
      };
    });

    tearDown(() => adapter.dispose());

    test('belongs to generative layer', () {
      expect(adapter.layer, IntelligenceLayer.generative);
      expect(adapter.name, 'DesignLinter');
    });

    test('marks lint as pending on context change', () {
      expect(adapter.lintPending, isFalse);
      adapter.onContextChanged(const EngineContext());
      expect(adapter.lintPending, isTrue);
    });

    test('runs lint on idle > 1000ms when pending', () {
      adapter.onContextChanged(const EngineContext());

      // Not enough idle time
      adapter.onIdle(const Duration(milliseconds: 500));
      expect(lintCallCount, 0);

      // Enough idle time
      adapter.onIdle(const Duration(milliseconds: 1100));
      expect(lintCallCount, 1);
      expect(adapter.lastViolationCount, 3);
      expect(adapter.lintPending, isFalse);
    });

    test('does not lint when not pending', () {
      adapter.onIdle(const Duration(seconds: 5));
      expect(lintCallCount, 0);
    });

    test('dispose clears callback', () {
      adapter.dispose();
      expect(adapter.isActive, isFalse);
      expect(adapter.onLintRequested, isNull);
    });
  });

  group('Full architecture registration', () {
    test('all adapters register and query correctly', () {
      final arch = ConsciousArchitecture();

      arch.register(SmartSnapAdapter());
      arch.register(SmartAnimateAdapter());
      arch.register(AccessibilityAdapter());
      arch.register(DesignLinterAdapter());

      expect(arch.byLayer(IntelligenceLayer.invisible), hasLength(3));
      expect(arch.byLayer(IntelligenceLayer.generative), hasLength(1));
      expect(arch.find<SmartSnapAdapter>(), isNotNull);
      expect(arch.find<DesignLinterAdapter>(), isNotNull);

      arch.dispose();
    });
  });
}
