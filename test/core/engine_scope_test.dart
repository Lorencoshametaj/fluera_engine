import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/engine_scope.dart';

void main() {
  tearDown(() {
    // Always clean up the global scope after each test
    EngineScope.reset();
  });

  // =========================================================================
  // Lazy Initialization
  // =========================================================================

  group('lazy initialization', () {
    test('no scope active initially after reset', () {
      expect(EngineScope.hasScope, isFalse);
    });

    test('current creates a default scope on first access', () {
      final scope = EngineScope.current;
      expect(scope, isNotNull);
      expect(EngineScope.hasScope, isTrue);
    });

    test('current returns same instance on repeated access', () {
      final a = EngineScope.current;
      final b = EngineScope.current;
      expect(identical(a, b), isTrue);
    });
  });

  // =========================================================================
  // Bind / Reset
  // =========================================================================

  group('bind and reset', () {
    test('bind replaces active scope', () {
      final scope1 = EngineScope.current;
      final scope2 = EngineScope();
      EngineScope.push(scope2);
      expect(identical(EngineScope.current, scope2), isTrue);
      expect(identical(EngineScope.current, scope1), isFalse);
    });

    test('reset clears scope', () {
      EngineScope.current; // trigger creation
      EngineScope.reset();
      expect(EngineScope.hasScope, isFalse);
    });

    test('reset then current creates fresh scope', () {
      final first = EngineScope.current;
      EngineScope.reset();
      final second = EngineScope.current;
      expect(identical(first, second), isFalse);
    });
  });

  // =========================================================================
  // Service Lazy Access
  // =========================================================================

  group('service lazy access', () {
    test('deltaTracker is available', () {
      expect(EngineScope.current.deltaTracker, isNotNull);
    });

    test('undoRedoManager is available', () {
      expect(EngineScope.current.undoRedoManager, isNotNull);
    });

    test('brushSettingsService is available', () {
      expect(EngineScope.current.brushSettingsService, isNotNull);
    });

    test('toolRegistry is available', () {
      expect(EngineScope.current.toolRegistry, isNotNull);
    });

    test('pathPool is available', () {
      expect(EngineScope.current.pathPool, isNotNull);
    });

    test('strokePointPool is available', () {
      expect(EngineScope.current.strokePointPool, isNotNull);
    });

    test('displayLinkService is available', () {
      expect(EngineScope.current.displayLinkService, isNotNull);
    });

    test('predictedTouchService is available', () {
      expect(EngineScope.current.predictedTouchService, isNotNull);
    });

    test('audioPlayerChannel is available', () {
      expect(EngineScope.current.audioPlayerChannel, isNotNull);
    });

    test('audioRecorderChannel is available', () {
      expect(EngineScope.current.audioRecorderChannel, isNotNull);
    });

    test('imageCacheService is available', () {
      expect(EngineScope.current.imageCacheService, isNotNull);
    });

    test('frameBudgetManager is available', () {
      expect(EngineScope.current.frameBudgetManager, isNotNull);
    });

    test('memoryPressureHandler is available', () {
      expect(EngineScope.current.memoryPressureHandler, isNotNull);
    });

    test('adaptiveDebouncerService is available', () {
      expect(EngineScope.current.adaptiveDebouncerService, isNotNull);
    });
  });

  // =========================================================================
  // Scope Isolation
  // =========================================================================

  group('scope isolation', () {
    test('different scopes have independent services', () {
      final scope1 = EngineScope();
      final scope2 = EngineScope();

      expect(identical(scope1.deltaTracker, scope2.deltaTracker), isFalse);
      expect(
        identical(scope1.undoRedoManager, scope2.undoRedoManager),
        isFalse,
      );
    });

    test('same scope returns same service instance', () {
      final scope = EngineScope();
      expect(identical(scope.deltaTracker, scope.deltaTracker), isTrue);
      expect(identical(scope.pathPool, scope.pathPool), isTrue);
    });
  });

  // =========================================================================
  // Dispose
  // =========================================================================

  group('dispose', () {
    test('dispose does not throw', () {
      final scope = EngineScope();
      // Access some services to trigger lazy init
      scope.undoRedoManager;
      scope.brushSettingsService;
      scope.toolRegistry;
      expect(() => scope.dispose(), returnsNormally);
    });
  });
}
