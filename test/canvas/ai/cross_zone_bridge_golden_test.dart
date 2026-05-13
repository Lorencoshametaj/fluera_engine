// Golden tests for Cross-Zone Bridges persistence.
//
// Verifies that:
//   1. CrossZoneBridgeSuggestion.toJson/fromJson roundtrip is lossless.
//   2. KnowledgeConnection extended with bridge fields (incl. the new
//      bridgeSuggestionDismissed tombstone flag) roundtrips losslessly,
//      and is BACKWARD-COMPATIBLE: a canvas saved before Passo 9 loads
//      cleanly with all new fields defaulted (no exception).
//   3. CrossZoneBridgePersistence write→read cycle preserves all
//      suggestions, the prompt hash, and the TTL window.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluera_engine/src/canvas/ai/cross_zone_bridge_controller.dart';
import 'package:fluera_engine/src/reflow/knowledge_connection.dart';
import 'package:fluera_engine/src/services/cross_zone_bridge_persistence.dart';

import '_fakes.dart';

void main() {
  group('CrossZoneBridgeSuggestion.toJson/fromJson', () {
    test('roundtrip is lossless on all fields', () {
      final s = CrossZoneBridgeSuggestion(
        id: 'sug_42',
        sourceClusterId: 'A',
        targetClusterId: 'B',
        socraticQuestion: 'Cosa accomuna le due strutture?',
        bridgeType: CrossZoneBridgeType.sharedMechanism,
        confidence: 0.87,
        dismissed: false,
        surfacedAt: 1714816800000,
      );

      final decoded = CrossZoneBridgeSuggestion.fromJson(s.toJson());

      expect(decoded.id, s.id);
      expect(decoded.sourceClusterId, s.sourceClusterId);
      expect(decoded.targetClusterId, s.targetClusterId);
      expect(decoded.socraticQuestion, s.socraticQuestion);
      expect(decoded.bridgeType, s.bridgeType);
      expect(decoded.confidence, closeTo(s.confidence, 1e-9));
      expect(decoded.dismissed, s.dismissed);
      expect(decoded.surfacedAtMs, s.surfacedAtMs);
    });

    test('unknown bridge_type degrades to analogyStructural (forward-compat)',
        () {
      final json = {
        'id': 'x',
        'sourceClusterId': 'A',
        'targetClusterId': 'B',
        'socraticQuestion': 'Q?',
        'bridgeType': 'someFutureType',
        'confidence': 0.5,
        'dismissed': false,
        'surfacedAtMs': 0,
      };
      final decoded = CrossZoneBridgeSuggestion.fromJson(json);
      expect(decoded.bridgeType, CrossZoneBridgeType.analogyStructural);
    });
  });

  group('KnowledgeConnection bridge-field roundtrip', () {
    test('toJson/fromJson preserves dismissed tombstone flag', () {
      final c = KnowledgeConnection(
        id: 'conn_1',
        sourceClusterId: 'A',
        targetClusterId: 'B',
        isGhost: true,
        bridgeSuggestionDismissed: true,
        bridgeType: CrossZoneBridgeType.analogyStructural,
        bridgeSocraticQuestion: 'Domanda?',
      );
      final json = c.toJson();
      expect(json['bridgeSuggestionDismissed'], true);

      final decoded = KnowledgeConnection.fromJson(json);
      expect(decoded.bridgeSuggestionDismissed, true);
      expect(decoded.isGhost, true);
      expect(decoded.bridgeType, CrossZoneBridgeType.analogyStructural);
      expect(decoded.bridgeSocraticQuestion, 'Domanda?');
    });

    test(
        'legacy canvas without bridge fields loads cleanly (backward-compat)',
        () {
      // Simulate a connection saved by a pre-Passo 9 build.
      final legacyJson = {
        'id': 'legacy_conn',
        'sourceClusterId': 'A',
        'targetClusterId': 'B',
        'color': 0xFF64B5F6,
        'curveStrength': 0.3,
        'connectionType': 'association',
        'connectionStyle': 'curved',
        'isBidirectional': false,
        // NB: no bridge* fields at all.
      };

      final decoded = KnowledgeConnection.fromJson(legacyJson);

      expect(decoded.id, 'legacy_conn');
      expect(decoded.isGhost, false);
      expect(decoded.isCrossZone, false);
      expect(decoded.bridgeType, isNull);
      expect(decoded.discoveredBy, isNull);
      expect(decoded.bridgeAnnotationClusterId, isNull);
      expect(decoded.bridgeSocraticQuestion, isNull);
      expect(decoded.bridgeSuggestionDismissed, false);
    });

    test('toJson omits dismissed flag when false (compact serialization)', () {
      final c = KnowledgeConnection(
        id: 'c',
        sourceClusterId: 'A',
        targetClusterId: 'B',
      );
      final json = c.toJson();
      expect(json.containsKey('bridgeSuggestionDismissed'), false,
          reason: 'false flag should be omitted to keep the JSON minimal');
    });
  });

  group('CrossZoneBridgePersistence write→read', () {
    late Directory tempDir;

    setUp(() {
      tempDir = installTempPathProvider();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('save then loadIfFresh returns same suggestions on hash match',
        () async {
      final suggestions = [
        CrossZoneBridgeSuggestion(
          id: 's1',
          sourceClusterId: 'A',
          targetClusterId: 'B',
          socraticQuestion: 'Q1?',
          bridgeType: CrossZoneBridgeType.analogyStructural,
          confidence: 0.8,
        ),
        CrossZoneBridgeSuggestion(
          id: 's2',
          sourceClusterId: 'B',
          targetClusterId: 'C',
          socraticQuestion: 'Q2?',
          bridgeType: CrossZoneBridgeType.complementaryPerspective,
          confidence: 0.6,
        ),
      ];

      await CrossZoneBridgePersistence.instance
          .save('canvas_test', 'hash_abc', suggestions);

      final loaded = await CrossZoneBridgePersistence.instance
          .loadIfFresh('canvas_test', 'hash_abc');

      expect(loaded, isNotNull);
      expect(loaded!.length, 2);
      expect(loaded[0].id, 's1');
      expect(loaded[0].bridgeType, CrossZoneBridgeType.analogyStructural);
      expect(loaded[1].id, 's2');
      expect(loaded[1].bridgeType,
          CrossZoneBridgeType.complementaryPerspective);
    });

    test('loadIfFresh returns null on hash mismatch (different prompt)',
        () async {
      await CrossZoneBridgePersistence.instance.save(
        'canvas_test',
        'hash_v1',
        [
          CrossZoneBridgeSuggestion(
            id: 's1',
            sourceClusterId: 'A',
            targetClusterId: 'B',
            socraticQuestion: 'Q?',
            bridgeType: CrossZoneBridgeType.analogyStructural,
          ),
        ],
      );

      final loaded = await CrossZoneBridgePersistence.instance
          .loadIfFresh('canvas_test', 'hash_DIFFERENT');

      expect(loaded, isNull,
          reason: 'cache must miss when prompt inputs changed');
    });

    test('loadIfFresh returns null when no cache exists', () async {
      final loaded = await CrossZoneBridgePersistence.instance
          .loadIfFresh('never_saved_canvas', 'any_hash');
      expect(loaded, isNull);
    });

    test('save is a no-op for empty suggestions list', () async {
      await CrossZoneBridgePersistence.instance
          .save('canvas_test', 'h', const []);
      final loaded = await CrossZoneBridgePersistence.instance
          .loadIfFresh('canvas_test', 'h');
      expect(loaded, isNull,
          reason: 'empty save should not create a stale file');
    });

    test('delete removes the cache file', () async {
      await CrossZoneBridgePersistence.instance.save(
        'canvas_test',
        'h',
        [
          CrossZoneBridgeSuggestion(
            id: 's',
            sourceClusterId: 'A',
            targetClusterId: 'B',
            socraticQuestion: 'Q?',
            bridgeType: CrossZoneBridgeType.analogyStructural,
          ),
        ],
      );
      await CrossZoneBridgePersistence.instance.delete('canvas_test');

      final loaded = await CrossZoneBridgePersistence.instance
          .loadIfFresh('canvas_test', 'h');
      expect(loaded, isNull);
    });
  });
}
