import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/schema_version.dart';

void main() {
  // ===========================================================================
  // migrateDocument
  // ===========================================================================

  group('migrateDocument', () {
    test('returns unchanged for current version', () {
      final json = {'version': kCurrentSchemaVersion, 'data': 'hello'};
      final result = migrateDocument(json);

      expect(result['version'], kCurrentSchemaVersion);
      expect(result['data'], 'hello');
    });

    test('defaults to version 1 when version field is missing', () {
      final json = <String, dynamic>{'data': 'legacy'};
      // Since kCurrentSchemaVersion is 1, this should return unchanged
      final result = migrateDocument(json);
      expect(result['data'], 'legacy');
    });

    test('throws SchemaVersionException for future version', () {
      final json = {'version': kCurrentSchemaVersion + 1};

      expect(
        () => migrateDocument(json),
        throwsA(
          isA<SchemaVersionException>().having(
            (e) => e.documentVersion,
            'documentVersion',
            kCurrentSchemaVersion + 1,
          ),
        ),
      );
    });

    test('SchemaVersionException has correct fields', () {
      try {
        migrateDocument({'version': kCurrentSchemaVersion + 5});
        fail('Should have thrown');
      } on SchemaVersionException catch (e) {
        expect(e.documentVersion, kCurrentSchemaVersion + 5);
        expect(e.currentVersion, kCurrentSchemaVersion);
        expect(e.message, isNotEmpty);
        expect(e.toString(), contains('SchemaVersionException'));
        expect(e.toString(), contains(e.message));
      }
    });
  });

  // ===========================================================================
  // validateDocumentVersion
  // ===========================================================================

  group('validateDocumentVersion', () {
    test('returns null for current version', () {
      final json = {'version': kCurrentSchemaVersion};
      expect(validateDocumentVersion(json), isNull);
    });

    test('returns null for missing version (defaults to 1)', () {
      final json = <String, dynamic>{'data': 'legacy'};
      // kMinSupportedSchemaVersion is 1, so missing version (treated as 1)
      // should be within range
      expect(validateDocumentVersion(json), isNull);
    });

    test('returns error string for future version', () {
      final json = {'version': kCurrentSchemaVersion + 1};
      final result = validateDocumentVersion(json);
      expect(result, isNotNull);
      expect(result, contains('v${kCurrentSchemaVersion + 1}'));
    });
  });

  // ===========================================================================
  // documentVersion
  // ===========================================================================

  group('documentVersion', () {
    test('returns version field value', () {
      expect(documentVersion({'version': 3}), 3);
    });

    test('defaults to 1 when field is missing', () {
      expect(documentVersion(<String, dynamic>{}), 1);
    });

    test('defaults to 1 when field is null', () {
      expect(documentVersion({'version': null}), 1);
    });
  });

  // ===========================================================================
  // walkNodes
  // ===========================================================================

  group('walkNodes', () {
    test('visits all nodes in layer tree depth-first', () {
      final json = {
        'sceneGraph': {
          'layers': [
            {
              'nodeType': 'layer',
              'id': 'L1',
              'children': [
                {'nodeType': 'stroke', 'id': 'S1'},
                {
                  'nodeType': 'group',
                  'id': 'G1',
                  'children': [
                    {'nodeType': 'shape', 'id': 'SH1'},
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

      expect(visited, ['L1', 'S1', 'G1', 'SH1']);
    });

    test('handles empty scene graph gracefully', () {
      final json = <String, dynamic>{'sceneGraph': <String, dynamic>{}};
      final visited = <String>[];
      walkNodes(json, (node) => visited.add(node['id'] as String));
      expect(visited, isEmpty);
    });

    test('handles missing sceneGraph key', () {
      final json = <String, dynamic>{'data': 'no scene graph'};
      final visited = <String>[];
      walkNodes(json, (node) => visited.add(node['id'] as String));
      expect(visited, isEmpty);
    });

    test('handles nodes without children', () {
      final json = {
        'sceneGraph': {
          'layers': [
            {'nodeType': 'layer', 'id': 'L1'},
          ],
        },
      };
      final visited = <String>[];
      walkNodes(json, (node) => visited.add(node['id'] as String));
      expect(visited, ['L1']);
    });
  });

  // ===========================================================================
  // Constants
  // ===========================================================================

  group('constants', () {
    test('kCurrentSchemaVersion is positive', () {
      expect(kCurrentSchemaVersion, greaterThan(0));
    });

    test('kMinSupportedSchemaVersion <= kCurrentSchemaVersion', () {
      expect(
        kMinSupportedSchemaVersion,
        lessThanOrEqualTo(kCurrentSchemaVersion),
      );
    });
  });
}
