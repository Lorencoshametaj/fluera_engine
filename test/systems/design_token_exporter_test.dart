import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/design_variables.dart';
import 'package:nebula_engine/src/systems/design_token_exporter.dart';

void main() {
  // =========================================================================
  // Multi-Mode Export
  // =========================================================================

  group('exportAllModes', () {
    test('exports all modes in one document', () {
      final collection = VariableCollection(
        id: 'themes',
        name: 'Themes',
        modes: [
          VariableMode(id: 'light', name: 'Light'),
          VariableMode(id: 'dark', name: 'Dark'),
        ],
        variables: [
          DesignVariable(
            id: 'bg',
            name: 'BG',
            type: DesignVariableType.color,
            values: {'light': 0xFFFFFFFF, 'dark': 0xFF000000},
          ),
        ],
      );

      final result = DesignTokenExporter.exportAllModes(collection: collection);

      expect(result.containsKey('light'), isTrue);
      expect(result.containsKey('dark'), isTrue);

      // Light mode should have white bg.
      final lightTokens = result['light'] as Map<String, dynamic>;
      expect(lightTokens['bg'][r'$value'], '#ffffff');

      // Dark mode should have black bg.
      final darkTokens = result['dark'] as Map<String, dynamic>;
      expect(darkTokens['bg'][r'$value'], '#000000');
    });

    test('exportAllModesToJson returns valid JSON string', () {
      final collection = VariableCollection(
        id: 'c1',
        name: 'Test',
        modes: [VariableMode(id: 'default', name: 'Default')],
        variables: [
          DesignVariable(
            id: 'v1',
            name: 'V1',
            type: DesignVariableType.number,
            values: {'default': 42.0},
          ),
        ],
      );

      final jsonStr = DesignTokenExporter.exportAllModesToJson(
        collection: collection,
      );

      // Should be valid JSON.
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(parsed.containsKey('default'), isTrue);
    });
  });

  // =========================================================================
  // Import with Validation
  // =========================================================================

  group('importW3CWithValidation', () {
    test('imports valid tokens without errors', () {
      final tokenDoc = <String, dynamic>{
        'primary': {r'$value': '#ff0000', r'$type': 'color'},
        'spacing': {r'$value': 16.0, r'$type': 'number'},
      };

      final result = DesignTokenExporter.importW3CWithValidation(
        collectionId: 'imported',
        collectionName: 'Imported',
        modeId: 'default',
        tokenDocument: tokenDoc,
      );

      expect(result.errors, isEmpty);
      expect(result.collection.variableCount, 2);
    });

    test('reports errors for invalid token entries', () {
      final tokenDoc = <String, dynamic>{
        'valid-token': {r'$value': 'hello', r'$type': 'string'},
        'invalid-token': 'not a map', // invalid
      };

      final result = DesignTokenExporter.importW3CWithValidation(
        collectionId: 'imported',
        collectionName: 'Imported',
        modeId: 'default',
        tokenDocument: tokenDoc,
      );

      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('invalid-token'));
      expect(result.collection.variableCount, 1);
    });

    test('collects errors without breaking valid tokens', () {
      final tokenDoc = <String, dynamic>{
        'good': {r'$value': true, r'$type': 'boolean'},
        'bad': 42, // not a map
        'also-good': {r'$value': 'text', r'$type': 'string'},
      };

      final result = DesignTokenExporter.importW3CWithValidation(
        collectionId: 'test',
        collectionName: 'Test',
        modeId: 'default',
        tokenDocument: tokenDoc,
      );

      expect(result.errors, hasLength(1));
      expect(result.collection.variableCount, 2);
    });
  });
}
