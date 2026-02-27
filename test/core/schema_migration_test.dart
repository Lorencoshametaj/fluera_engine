import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/schema_version.dart';
import 'package:fluera_engine/src/core/scene_graph/scene_graph.dart';

void main() {
  group('Schema Version', () {
    // =========================================================================
    // migrateDocument
    // =========================================================================

    test('current version returns JSON unchanged', () {
      final json = <String, dynamic>{
        'version': kCurrentSchemaVersion,
        'sceneGraph': {'layers': []},
      };
      final result = migrateDocument(json);
      expect(result['version'], kCurrentSchemaVersion);
      expect(result['sceneGraph'], json['sceneGraph']);
    });

    test('missing version defaults to 1 (legacy)', () {
      final json = <String, dynamic>{
        'sceneGraph': {'layers': []},
      };
      // Since kCurrentSchemaVersion == 1 and missing defaults to 1,
      // it should pass through without error.
      final result = migrateDocument(json);
      expect(result, isNotNull);
    });

    test('future version throws SchemaVersionException', () {
      final json = <String, dynamic>{
        'version': kCurrentSchemaVersion + 1,
        'sceneGraph': {'layers': []},
      };
      expect(
        () => migrateDocument(json),
        throwsA(isA<SchemaVersionException>()),
      );
    });

    test('SchemaVersionException has correct fields', () {
      final json = <String, dynamic>{
        'version': 999,
        'sceneGraph': {'layers': []},
      };
      try {
        migrateDocument(json);
        fail('Should have thrown');
      } on SchemaVersionException catch (e) {
        expect(e.documentVersion, 999);
        expect(e.currentVersion, kCurrentSchemaVersion);
        expect(e.message, contains('newer version'));
        expect(e.toString(), contains('SchemaVersionException'));
      }
    });

    // =========================================================================
    // validateDocumentVersion
    // =========================================================================

    test('validateDocumentVersion returns null for valid version', () {
      final json = <String, dynamic>{'version': kCurrentSchemaVersion};
      expect(validateDocumentVersion(json), isNull);
    });

    test('validateDocumentVersion returns error for future version', () {
      final json = <String, dynamic>{'version': kCurrentSchemaVersion + 5};
      expect(validateDocumentVersion(json), isNotNull);
      expect(
        validateDocumentVersion(json),
        contains('v${kCurrentSchemaVersion + 5}'),
      );
    });

    test('validateDocumentVersion returns null for legacy (no version)', () {
      final json = <String, dynamic>{'sceneGraph': {}};
      // defaults to 1, which == kCurrentSchemaVersion
      expect(validateDocumentVersion(json), isNull);
    });

    // =========================================================================
    // documentVersion
    // =========================================================================

    test('documentVersion reads version field', () {
      expect(documentVersion({'version': 3}), 3);
    });

    test('documentVersion defaults to 1 when missing', () {
      expect(documentVersion({}), 1);
    });

    // =========================================================================
    // walkNodes
    // =========================================================================

    test('walkNodes visits all nodes in layer tree', () {
      final json = <String, dynamic>{
        'version': 1,
        'sceneGraph': {
          'layers': [
            {
              'nodeType': 'layer',
              'id': 'layer1',
              'children': [
                {'nodeType': 'stroke', 'id': 's1'},
                {
                  'nodeType': 'group',
                  'id': 'g1',
                  'children': [
                    {'nodeType': 'shape', 'id': 'sh1'},
                    {'nodeType': 'text', 'id': 't1'},
                  ],
                },
              ],
            },
          ],
        },
      };

      final visited = <String>[];
      walkNodes(json, (node) {
        visited.add(node['id'] as String);
      });

      expect(visited, ['layer1', 's1', 'g1', 'sh1', 't1']);
    });

    test('walkNodes handles empty scene graph', () {
      final json = <String, dynamic>{
        'version': 1,
        'sceneGraph': {'layers': []},
      };

      final visited = <String>[];
      walkNodes(json, (node) => visited.add(node['id'] as String));
      expect(visited, isEmpty);
    });

    test('walkNodes handles null sceneGraph', () {
      final json = <String, dynamic>{'version': 1};
      // Should not throw
      walkNodes(json, (_) {});
    });

    // =========================================================================
    // SceneGraph round-trip with versioning
    // =========================================================================

    test('SceneGraph.toJson writes kCurrentSchemaVersion', () {
      final graph = SceneGraph();
      final json = graph.toJson();
      expect(json['version'], kCurrentSchemaVersion);
    });

    test('SceneGraph round-trip preserves version', () {
      final graph = SceneGraph();
      final json = graph.toJson();
      final restored = SceneGraph.fromJson(json);
      final json2 = restored.toJson();
      expect(json2['version'], json['version']);
    });

    test('SceneGraph.fromJson rejects future version', () {
      final json = <String, dynamic>{
        'version': kCurrentSchemaVersion + 1,
        'sceneGraph': {'layers': []},
      };
      expect(
        () => SceneGraph.fromJson(json),
        throwsA(isA<SchemaVersionException>()),
      );
    });
  });
}
