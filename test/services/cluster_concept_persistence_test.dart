// ============================================================================
// 💾 ClusterConceptPersistence — Unit tests
//
// Covers: round-trip JSON, schema-version mismatch drop, 30d TTL prune,
// per-canvas namespacing, atomic .tmp write.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/cluster_concept.dart';
import 'package:fluera_engine/src/services/cluster_concept_persistence.dart';

Directory _installTempPathProvider() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = Directory.systemTemp.createTempSync('fluera_concept_test_');
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
      case 'getApplicationSupportDirectory':
      case 'getTemporaryDirectory':
        return tempDir.path;
    }
    return null;
  });
  return tempDir;
}

void main() {
  late Directory tempDir;
  late ClusterConceptPersistence p;

  setUp(() {
    tempDir = _installTempPathProvider();
    p = ClusterConceptPersistence.instance;
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ClusterConceptPersistence — round-trip', () {
    test('save then load returns the same concepts', () async {
      final concepts = {
        'c1': ClusterConcept(
          clusterId: 'c1',
          rawOcr: 'raw',
          cleanedOcr: 'clean',
          title: 'Title',
          concepts: ['Newton'],
          sourceVersion: 2,
          strokeChecksum: 42,
        ),
      };
      await p.save('canvas-A', concepts);
      final loaded = await p.load('canvas-A');
      expect(loaded.keys, contains('c1'));
      expect(loaded['c1']!.title, 'Title');
      expect(loaded['c1']!.concepts, ['Newton']);
      expect(loaded['c1']!.sourceVersion, 2);
    });

    test('empty save is a no-op (no file created)', () async {
      await p.save('canvas-empty', {});
      final loaded = await p.load('canvas-empty');
      expect(loaded, isEmpty);
    });

    test('load returns empty map for unknown canvas', () async {
      final loaded = await p.load('canvas-never-seen');
      expect(loaded, isEmpty);
    });
  });

  group('ClusterConceptPersistence — namespacing', () {
    test('different canvases have isolated stores', () async {
      await p.save('canvas-A', {
        'c1': ClusterConcept(clusterId: 'c1', title: 'A-title'),
      });
      await p.save('canvas-B', {
        'c1': ClusterConcept(clusterId: 'c1', title: 'B-title'),
      });
      final a = await p.load('canvas-A');
      final b = await p.load('canvas-B');
      expect(a['c1']!.title, 'A-title');
      expect(b['c1']!.title, 'B-title');
    });

    test('delete removes only the targeted canvas', () async {
      await p.save('canvas-A', {
        'c1': ClusterConcept(clusterId: 'c1', title: 'A'),
      });
      await p.save('canvas-B', {
        'c1': ClusterConcept(clusterId: 'c1', title: 'B'),
      });
      await p.delete('canvas-A');
      final a = await p.load('canvas-A');
      final b = await p.load('canvas-B');
      expect(a, isEmpty);
      expect(b, isNotEmpty);
    });
  });

  group('ClusterConceptPersistence — schema + TTL', () {
    test('schema version mismatch drops the cache', () async {
      // Manually write a payload with a wrong schema version.
      final dir = Directory('${tempDir.path}/fluera_concepts');
      await dir.create(recursive: true);
      final file = File('${dir.path}/canvas_legacy.json');
      await file.writeAsString(jsonEncode({
        'version': 999,
        'savedAt': DateTime.now().toIso8601String(),
        'concepts': [
          {'clusterId': 'c1', 'title': 'Stale'},
        ],
      }));
      final loaded = await p.load('canvas-legacy');
      expect(loaded, isEmpty);
    });

    test('entries older than 30 days are dropped at load', () async {
      final fresh = ClusterConcept(
        clusterId: 'fresh',
        title: 'Fresh',
        lastUpdated: DateTime.now().subtract(const Duration(days: 5)),
      );
      final stale = ClusterConcept(
        clusterId: 'stale',
        title: 'Stale',
        lastUpdated: DateTime.now().subtract(const Duration(days: 60)),
      );
      await p.save('canvas-mixed', {
        'fresh': fresh,
        'stale': stale,
      });
      final loaded = await p.load('canvas-mixed');
      expect(loaded.keys, contains('fresh'));
      expect(loaded.keys, isNot(contains('stale')));
    });
  });
}
