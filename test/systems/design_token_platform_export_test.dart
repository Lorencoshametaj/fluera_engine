import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/design_token_exporter.dart';
import 'package:nebula_engine/src/systems/design_variables.dart';

void main() {
  /// Create a test collection with various token types.
  VariableCollection makeTestCollection() {
    return VariableCollection(
      id: 'test-collection',
      name: 'Brand Tokens',
      modes: [VariableMode(id: 'light', name: 'Light')],
      variables: [
        DesignVariable(
          id: 'primary-color',
          name: 'primary',
          type: DesignVariableType.color,
          group: 'colors',
          description: 'Primary brand color',
          values: {'light': 0xFF3366FF}, // ARGB opaque blue
        ),
        DesignVariable(
          id: 'font-size',
          name: 'fontSize',
          type: DesignVariableType.number,
          group: 'typography',
          values: {'light': 16.0},
        ),
        DesignVariable(
          id: 'dark-mode',
          name: 'darkMode',
          type: DesignVariableType.boolean,
          values: {'light': false},
        ),
        DesignVariable(
          id: 'font-family',
          name: 'fontFamily',
          type: DesignVariableType.string,
          group: 'typography',
          values: {'light': 'Inter'},
        ),
        DesignVariable(
          id: 'semi-color',
          name: 'semiTransparent',
          type: DesignVariableType.color,
          group: 'colors',
          description: 'Semi-transparent overlay',
          values: {'light': 0x803366FF}, // 50% alpha
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // CSS Custom Properties
  // ───────────────────────────────────────────────────────────────────────────

  group('CSS Custom Properties export', () {
    test('generates valid CSS :root block', () {
      final collection = makeTestCollection();
      final css = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.cssCustomProperties,
      );

      expect(css, contains(':root {'));
      expect(css, contains('}'));
    });

    test('opaque color renders as hex', () {
      final collection = makeTestCollection();
      final css = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.cssCustomProperties,
      );

      expect(css, contains('--colors-primary: #3366ff;'));
    });

    test('semi-transparent color renders as rgba', () {
      final collection = makeTestCollection();
      final css = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.cssCustomProperties,
      );

      expect(css, contains('rgba('));
    });

    test('number value rendered correctly', () {
      final collection = makeTestCollection();
      final css = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.cssCustomProperties,
      );

      expect(css, contains('--typography-fontsize: 16.0;'));
    });

    test('boolean renders as 0 or 1', () {
      final collection = makeTestCollection();
      final css = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.cssCustomProperties,
      );

      expect(css, contains('--darkmode: 0;'));
    });

    test('includes comments for described tokens', () {
      final collection = makeTestCollection();
      final css = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.cssCustomProperties,
      );

      expect(css, contains('/* Primary brand color */'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Kotlin Object
  // ───────────────────────────────────────────────────────────────────────────

  group('Kotlin Object export', () {
    test('generates valid Kotlin object', () {
      final collection = makeTestCollection();
      final kotlin = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.kotlinObject,
      );

      expect(kotlin, contains('object BrandTokens {'));
      expect(kotlin, contains('}'));
    });

    test('color renders as Long hex', () {
      final collection = makeTestCollection();
      final kotlin = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.kotlinObject,
      );

      expect(kotlin, contains('Long'));
      expect(kotlin, contains('0x'));
      expect(kotlin, contains('L'));
    });

    test('number renders as Double', () {
      final collection = makeTestCollection();
      final kotlin = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.kotlinObject,
      );

      expect(kotlin, contains('Double'));
      expect(kotlin, contains('16.0'));
    });

    test('boolean renders correctly', () {
      final collection = makeTestCollection();
      final kotlin = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.kotlinObject,
      );

      expect(kotlin, contains('Boolean'));
      expect(kotlin, contains('false'));
    });

    test('string renders with quotes', () {
      final collection = makeTestCollection();
      final kotlin = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.kotlinObject,
      );

      expect(kotlin, contains('"Inter"'));
    });

    test('includes KDoc comments', () {
      final collection = makeTestCollection();
      final kotlin = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.kotlinObject,
      );

      expect(kotlin, contains('/** Primary brand color */'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Swift Struct
  // ───────────────────────────────────────────────────────────────────────────

  group('Swift Struct export', () {
    test('generates valid Swift struct', () {
      final collection = makeTestCollection();
      final swift = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.swiftStruct,
      );

      expect(swift, contains('struct BrandTokens {'));
      expect(swift, contains('}'));
    });

    test('color renders as UInt32 hex', () {
      final collection = makeTestCollection();
      final swift = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.swiftStruct,
      );

      expect(swift, contains('UInt32'));
      expect(swift, contains('0x'));
    });

    test('uses static let declarations', () {
      final collection = makeTestCollection();
      final swift = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.swiftStruct,
      );

      expect(swift, contains('static let'));
    });

    test('boolean uses Bool type', () {
      final collection = makeTestCollection();
      final swift = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.swiftStruct,
      );

      expect(swift, contains('Bool'));
    });

    test('includes Swift doc comments', () {
      final collection = makeTestCollection();
      final swift = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.swiftStruct,
      );

      expect(swift, contains('/// Primary brand color'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // exportToString fallback for JSON-based formats
  // ───────────────────────────────────────────────────────────────────────────

  group('exportToString JSON fallback', () {
    test('w3c format returns valid JSON string', () {
      final collection = makeTestCollection();
      final json = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.w3c,
      );

      expect(json, contains(r'"$value"'));
      expect(json, contains(r'"$type"'));
    });

    test('styleDictionary format returns valid JSON string', () {
      final collection = makeTestCollection();
      final json = DesignTokenExporter.exportToString(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.styleDictionary,
      );

      expect(json, contains('"value"'));
      expect(json, contains('"type"'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // exportCollection for platform formats
  // ───────────────────────────────────────────────────────────────────────────

  group('exportCollection platform formats', () {
    test('CSS format returns map with _output key', () {
      final collection = makeTestCollection();
      final result = DesignTokenExporter.exportCollection(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.cssCustomProperties,
      );

      expect(result.containsKey('_output'), isTrue);
      expect(result['_output'], isA<String>());
      expect(result['_output'] as String, contains(':root'));
    });

    test('Kotlin format returns map with _output key', () {
      final collection = makeTestCollection();
      final result = DesignTokenExporter.exportCollection(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.kotlinObject,
      );

      expect(result['_output'], isA<String>());
      expect(result['_output'] as String, contains('object'));
    });

    test('Swift format returns map with _output key', () {
      final collection = makeTestCollection();
      final result = DesignTokenExporter.exportCollection(
        collection: collection,
        modeId: 'light',
        format: DesignTokenFormat.swiftStruct,
      );

      expect(result['_output'], isA<String>());
      expect(result['_output'] as String, contains('struct'));
    });
  });
}
