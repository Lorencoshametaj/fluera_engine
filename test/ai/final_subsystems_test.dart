// ============================================================================
// 🧪 UNIT TESTS — Final 3 subsystems: A19, A20.6, A20.7
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/pedagogical_telemetry_service.dart';
import 'package:fluera_engine/src/canvas/ai/knowledge_type_controller.dart';
import 'package:fluera_engine/src/canvas/ai/degraded_mode_controller.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // PEDAGOGICAL TELEMETRY (A19)
  // ═══════════════════════════════════════════════════════════════════════════

  group('PedagogicalTelemetryService', () {
    late PedagogicalTelemetryService service;

    setUp(() => service = PedagogicalTelemetryService());
    tearDown(() => service.dispose());

    test('disabled by default', () {
      expect(service.isEnabled, isFalse);
      expect(service.bufferSize, 0);
    });

    test('record is no-op when disabled', () {
      service.startSession('s1');
      service.record(TelemetryMetric.recallRate, 0.8);
      expect(service.bufferSize, 0);
    });

    test('record works when enabled + session active', () {
      service.enable();
      service.startSession('s1');
      service.record(TelemetryMetric.recallRate, 0.9);
      service.record(TelemetryMetric.sessionDuration, 1800);
      expect(service.bufferSize, 2);
    });

    test('record is no-op without session', () {
      service.enable();
      service.record(TelemetryMetric.recallRate, 0.5);
      expect(service.bufferSize, 0);
    });

    test('flush returns and clears buffer', () {
      service.enable();
      service.startSession('s1');
      service.record(TelemetryMetric.recallRate, 0.8);
      service.record(TelemetryMetric.fowCompletionRate, 0.6);

      final events = service.flush();
      expect(events.length, 2);
      expect(service.bufferSize, 0);
    });

    test('disable clears buffer', () {
      service.enable();
      service.startSession('s1');
      service.record(TelemetryMetric.recallRate, 0.8);
      service.disable();
      expect(service.bufferSize, 0);
      expect(service.isEnabled, isFalse);
    });

    test('event serialization', () {
      service.enable();
      service.startSession('test-session');
      service.record(TelemetryMetric.bridgesCreated, 3, label: 'bio→chem');

      final events = service.flush();
      final json = events.first.toJson();
      expect(json['metric'], 'bridgesCreated');
      expect(json['value'], 3.0);
      expect(json['label'], 'bio→chem');
      expect(json['sessionId'], 'test-session');
    });

    test('event deserialization', () {
      final event = PedagogicalTelemetryEvent.fromJson({
        'metric': 'recallRate',
        'value': 0.75,
        'sessionId': 'abc',
      });
      expect(event.metric, TelemetryMetric.recallRate);
      expect(event.value, 0.75);
    });

    test('session summary aggregates averages', () {
      service.enable();
      service.startSession('s1');
      service.record(TelemetryMetric.recallRate, 0.8);
      service.record(TelemetryMetric.recallRate, 0.6);
      service.record(TelemetryMetric.sessionDuration, 1200);

      final summary = service.generateSummary();
      expect(summary, isNotNull);
      expect(summary!.sessionId, 's1');
      expect(summary.eventCount, 3);
      expect(summary.aggregates[TelemetryMetric.recallRate], closeTo(0.7, 0.01));
      expect(summary.aggregates[TelemetryMetric.sessionDuration], 1200);
    });

    test('summary serialization', () {
      service.enable();
      service.startSession('s1');
      service.record(TelemetryMetric.recallRate, 0.9);

      final summary = service.generateSummary();
      final json = summary!.toJson();
      expect(json['sessionId'], 's1');
      expect(json['eventCount'], 1);
    });

    test('all 10 metrics defined', () {
      expect(TelemetryMetric.values.length, 10);
    });

    test('buffer hard cap drops oldest events', () {
      service.enable();
      service.startSession('overflow-test');

      // Fill beyond maxBufferSize
      for (int i = 0; i < PedagogicalTelemetryService.maxBufferSize + 50; i++) {
        service.record(TelemetryMetric.recallRate, i.toDouble());
      }

      // Buffer should be capped at maxBufferSize
      expect(service.bufferSize, PedagogicalTelemetryService.maxBufferSize);

      // Oldest events should have been dropped — flush should contain latest
      final events = service.flush();
      expect(events.last.value,
          (PedagogicalTelemetryService.maxBufferSize + 49).toDouble());
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // KNOWLEDGE TYPE CONTROLLER (A20.6)
  // ═══════════════════════════════════════════════════════════════════════════

  group('KnowledgeTypeController', () {
    late KnowledgeTypeController controller;

    setUp(() => controller = KnowledgeTypeController());

    test('untagged zone defaults to declarative', () {
      expect(controller.getType('any_zone'), KnowledgeType.declarative);
    });

    test('setType tags a zone', () {
      controller.setType('bio_zone', KnowledgeType.visual);
      expect(controller.getType('bio_zone'), KnowledgeType.visual);
      expect(controller.taggedCount, 1);
    });

    test('all 5 types have modifiers', () {
      for (final type in KnowledgeType.values) {
        expect(KnowledgeTypeController.modifiers[type], isNotNull);
      }
    });

    test('linguistic has shortest interval', () {
      final ling = KnowledgeTypeController.modifiers[KnowledgeType.linguistic]!;
      final decl = KnowledgeTypeController.modifiers[KnowledgeType.declarative]!;
      expect(ling.intervalMultiplier, lessThan(decl.intervalMultiplier));
    });

    test('visual has highest ghost map weight', () {
      final vis = KnowledgeTypeController.modifiers[KnowledgeType.visual]!;
      expect(vis.ghostMapWeight, 0.9);
    });

    test('mathematical prefers practice + variation', () {
      final math = KnowledgeTypeController.modifiers[KnowledgeType.mathematical]!;
      expect(math.preferPractice, isTrue);
      expect(math.variateProblems, isTrue);
    });

    test('linguistic has most daily reviews', () {
      final ling = KnowledgeTypeController.modifiers[KnowledgeType.linguistic]!;
      expect(ling.minDailyReviews, 20);
    });

    test('getModifiers uses zone type', () {
      controller.setType('z1', KnowledgeType.procedural);
      final mods = controller.getModifiers('z1');
      expect(mods.preferPractice, isTrue);
      expect(mods.intervalMultiplier, 0.8);
    });

    test('auto-detect mathematical', () {
      final type = KnowledgeTypeController.detectFromContent(
        'Studiare la formula del teorema di Pitagora e la derivata',
      );
      expect(type, KnowledgeType.mathematical);
    });

    test('auto-detect linguistic', () {
      final type = KnowledgeTypeController.detectFromContent(
        'Vocabolario inglese: traduzione e grammatica avanzata',
      );
      expect(type, KnowledgeType.linguistic);
    });

    test('auto-detect visual', () {
      final type = KnowledgeTypeController.detectFromContent(
        'Anatomia del cuore: diagramma ventricolare e mappa del sistema',
      );
      expect(type, KnowledgeType.visual);
    });

    test('auto-detect procedural', () {
      final type = KnowledgeTypeController.detectFromContent(
        'Passo 1: procedura di calibrazione. Passo 2: algoritmo di verifica.',
      );
      expect(type, KnowledgeType.procedural);
    });

    test('ambiguous text defaults to declarative', () {
      final type = KnowledgeTypeController.detectFromContent(
        'Il rinascimento fu un periodo storico importante',
      );
      expect(type, KnowledgeType.declarative);
    });

    test('serialization round-trip', () {
      controller.setType('z1', KnowledgeType.visual);
      controller.setType('z2', KnowledgeType.mathematical);

      final json = controller.toJson();
      final restored = KnowledgeTypeController.fromJson(json);

      expect(restored.getType('z1'), KnowledgeType.visual);
      expect(restored.getType('z2'), KnowledgeType.mathematical);
      expect(restored.taggedCount, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DEGRADED MODE CONTROLLER (A20.7)
  // ═══════════════════════════════════════════════════════════════════════════

  group('DegradedModeController', () {
    late DegradedModeController controller;

    setUp(() => controller = DegradedModeController());
    tearDown(() => controller.dispose());

    test('defaults to full + online', () {
      expect(controller.device, DeviceCapability.full);
      expect(controller.network, NetworkCapability.online);
      expect(controller.isDegraded, isFalse);
      expect(controller.isAiAvailable, isTrue);
    });

    test('smartphone mode enables compact toolbar', () {
      controller.configure(device: DeviceCapability.smartphone);
      expect(controller.config.compactToolbar, isTrue);
      expect(controller.config.autoZoomToWrite, isTrue);
      expect(controller.config.showMinimap, isFalse);
    });

    test('smartphone has larger touch target (WCAG)', () {
      controller.configure(device: DeviceCapability.smartphone);
      expect(controller.config.minTouchTarget, greaterThanOrEqualTo(56));
    });

    test('desktop has smallest touch target (mouse precision)', () {
      controller.configure(device: DeviceCapability.desktop);
      expect(controller.config.minTouchTarget, 32);
      expect(controller.config.palmRejection, isFalse);
    });

    test('tablet no stylus disables palm rejection', () {
      controller.configure(device: DeviceCapability.tabletNoStylus);
      expect(controller.config.palmRejection, isFalse);
      expect(controller.config.touchSlop, greaterThan(8));
    });

    test('offline disables AI features', () {
      controller.configure(network: NetworkCapability.offline);
      expect(controller.isAiAvailable, isFalse);
      expect(controller.config.socraticEnabled, isFalse);
      expect(controller.config.ghostMapEnabled, isFalse);
      expect(controller.config.showOfflineBadge, isTrue);
    });

    test('online enables AI features', () {
      controller.configure(network: NetworkCapability.online);
      expect(controller.config.socraticEnabled, isTrue);
      expect(controller.config.ghostMapEnabled, isTrue);
      expect(controller.config.showOfflineBadge, isFalse);
    });

    test('isDegraded detects any limitation', () {
      controller.configure(device: DeviceCapability.smartphone);
      expect(controller.isDegraded, isTrue);

      controller.configure(
          device: DeviceCapability.full,
          network: NetworkCapability.offline);
      expect(controller.isDegraded, isTrue);
    });

    test('auto-detect smartphone from screen width', () {
      final device = DegradedModeController.detectDevice(
        screenWidth: 375,
        hasStylus: false,
        isDesktop: false,
      );
      expect(device, DeviceCapability.smartphone);
    });

    test('auto-detect desktop', () {
      final device = DegradedModeController.detectDevice(
        screenWidth: 1920,
        hasStylus: false,
        isDesktop: true,
      );
      expect(device, DeviceCapability.desktop);
    });

    test('auto-detect tablet without stylus', () {
      final device = DegradedModeController.detectDevice(
        screenWidth: 1024,
        hasStylus: false,
        isDesktop: false,
      );
      expect(device, DeviceCapability.tabletNoStylus);
    });

    test('auto-detect full (tablet + stylus)', () {
      final device = DegradedModeController.detectDevice(
        screenWidth: 1024,
        hasStylus: true,
        isDesktop: false,
      );
      expect(device, DeviceCapability.full);
    });

    test('manual override persists', () {
      controller.setManualOverride(DeviceCapability.smartphone);
      expect(controller.device, DeviceCapability.smartphone);
      expect(controller.config.compactToolbar, isTrue);
    });

    test('clear manual override returns to auto', () {
      controller.setManualOverride(DeviceCapability.smartphone);
      controller.clearManualOverride();
      // Still smartphone until re-configured
      expect(controller.device, DeviceCapability.smartphone);
    });

    test('smartphone limits toolbar buttons to 5', () {
      controller.configure(device: DeviceCapability.smartphone);
      expect(controller.config.toolbarButtonLimit, 5);
    });

    test('full mode has 12 toolbar buttons', () {
      controller.configure(device: DeviceCapability.full);
      expect(controller.config.toolbarButtonLimit, 12);
    });

    test('each mode has Italian label', () {
      for (final device in DeviceCapability.values) {
        controller.configure(device: device);
        expect(controller.config.labelIt, isNotEmpty);
      }
    });

    test('network changes apply even during manual device override', () {
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.setManualOverride(DeviceCapability.smartphone);
      notifyCount = 0; // Reset after setup

      // Network change should still fire even under manual override
      controller.configure(network: NetworkCapability.offline);
      expect(notifyCount, 1);
      expect(controller.config.showOfflineBadge, isTrue);
      expect(controller.config.socraticEnabled, isFalse);

      // Device stays overridden (smartphone)
      expect(controller.device, DeviceCapability.smartphone);
    });

    test('device changes ignored during manual override', () {
      controller.setManualOverride(DeviceCapability.smartphone);
      controller.configure(device: DeviceCapability.full);
      // Manual override should prevent device change
      expect(controller.device, DeviceCapability.smartphone);
    });
  });
}
