import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/drawing/services/brush_settings_service.dart';
import 'package:nebula_engine/src/drawing/models/pro_brush_settings.dart';
import 'package:nebula_engine/src/core/engine_scope.dart';

void main() {
  late BrushSettingsService service;

  setUp(() {
    EngineScope.reset();
    service = BrushSettingsService.create();
  });

  tearDown(() {
    service.dispose();
    EngineScope.reset();
  });

  // =========================================================================
  // Initial State
  // =========================================================================

  group('initial state', () {
    test('starts with default settings', () {
      expect(service.settings, isNotNull);
      expect(service.settings, equals(const ProBrushSettings()));
    });

    test('starts not initialized', () {
      expect(service.isInitialized, isFalse);
    });
  });

  // =========================================================================
  // Settings Update (without SharedPreferences — testing in-memory behavior)
  // =========================================================================

  group('settings update', () {
    test('updateSettings changes the current settings', () async {
      const newSettings = ProBrushSettings(
        fountainMinPressure: 0.5,
        fountainMaxPressure: 1.5,
      );
      await service.updateSettings(newSettings);
      expect(service.settings.fountainMinPressure, 0.5);
      expect(service.settings.fountainMaxPressure, 1.5);
    });

    test('updateSettings notifies listeners', () async {
      int notifyCount = 0;
      service.addListener(() => notifyCount++);

      const newSettings = ProBrushSettings(fountainMinPressure: 0.8);
      await service.updateSettings(newSettings);
      expect(notifyCount, 1);
    });

    test('updateSettings with same value does not notify', () async {
      int notifyCount = 0;
      service.addListener(() => notifyCount++);

      // Set to default (same as initial)
      await service.updateSettings(const ProBrushSettings());
      expect(notifyCount, 0);
    });

    test('resetToDefaults restores default settings', () async {
      const custom = ProBrushSettings(fountainMinPressure: 0.9);
      await service.updateSettings(custom);
      expect(service.settings.fountainMinPressure, 0.9);

      await service.resetToDefaults();
      expect(service.settings, equals(const ProBrushSettings()));
    });
  });

  // =========================================================================
  // Conversion
  // =========================================================================

  group('conversion to BrushSettings', () {
    test('toBrushSettings creates matching object', () async {
      const custom = ProBrushSettings(
        fountainMinPressure: 0.3,
        fountainMaxPressure: 1.8,
        fountainTaperEntry: 3,
        highlighterOpacity: 0.6,
      );
      await service.updateSettings(custom);

      final brushSettings = service.toBrushSettings();
      expect(brushSettings.fountainMinPressure, 0.3);
      expect(brushSettings.fountainMaxPressure, 1.8);
      expect(brushSettings.fountainTaperEntry, 3);
      expect(brushSettings.highlighterOpacity, 0.6);
    });
  });

  // =========================================================================
  // ChangeNotifier
  // =========================================================================

  group('ChangeNotifier behavior', () {
    test('multiple listeners receive updates', () async {
      int count1 = 0, count2 = 0;
      service.addListener(() => count1++);
      service.addListener(() => count2++);

      await service.updateSettings(
        const ProBrushSettings(fountainMinPressure: 0.1),
      );
      expect(count1, 1);
      expect(count2, 1);
    });

    test('removed listener does not receive updates', () async {
      int count = 0;
      void listener() => count++;
      service.addListener(listener);
      service.removeListener(listener);

      await service.updateSettings(
        const ProBrushSettings(fountainMinPressure: 0.2),
      );
      expect(count, 0);
    });
  });

  // =========================================================================
  // EngineScope Integration
  // =========================================================================

  group('EngineScope integration', () {
    test('accessible via EngineScope.current', () {
      final scopeService = EngineScope.current.brushSettingsService;
      expect(scopeService, isNotNull);
      expect(scopeService, isA<BrushSettingsService>());
    });
  });
}
