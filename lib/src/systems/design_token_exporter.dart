import 'dart:convert';
import './design_variables.dart';

// =============================================================================
// 🌐 W3C DESIGN TOKEN EXPORTER
//
// Exports VariableCollections to the W3C Design Token Community Group format
// (https://tr.designtokens.org/format/) and Style Dictionary compatible JSON.
//
// Supports:
// - W3C DTCG format (draft spec)
// - Style Dictionary flat format
// - Import from both formats
// =============================================================================

/// Output format for design token export.
enum DesignTokenFormat {
  /// W3C Design Token Community Group format (nested, with $value/$type).
  w3c,

  /// Style Dictionary flat format (with value/type at leaf level).
  styleDictionary,
}

/// Exports [VariableCollection]s to standard design token formats.
///
/// ```dart
/// final json = DesignTokenExporter.exportCollection(
///   collection: myThemes,
///   modeId: 'dark',
///   format: DesignTokenFormat.w3c,
/// );
/// print(jsonEncode(json)); // W3C DTCG JSON
/// ```
class DesignTokenExporter {
  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// Export a single collection for a specific mode.
  ///
  /// Returns a JSON-serializable map in the specified [format].
  static Map<String, dynamic> exportCollection({
    required VariableCollection collection,
    required String modeId,
    DesignTokenFormat format = DesignTokenFormat.w3c,
  }) {
    switch (format) {
      case DesignTokenFormat.w3c:
        return _exportW3C(collection, modeId);
      case DesignTokenFormat.styleDictionary:
        return _exportStyleDictionary(collection, modeId);
    }
  }

  /// Export multiple collections into a single token document.
  static Map<String, dynamic> exportAll({
    required List<VariableCollection> collections,
    required Map<String, String> activeModes,
    DesignTokenFormat format = DesignTokenFormat.w3c,
  }) {
    final result = <String, dynamic>{};
    for (final collection in collections) {
      final modeId = activeModes[collection.id] ?? collection.defaultModeId;
      result[_sanitizeKey(collection.name)] = exportCollection(
        collection: collection,
        modeId: modeId,
        format: format,
      );
    }
    return result;
  }

  /// Export to a JSON string.
  static String exportToJson({
    required List<VariableCollection> collections,
    required Map<String, String> activeModes,
    DesignTokenFormat format = DesignTokenFormat.w3c,
  }) {
    return const JsonEncoder.withIndent('  ').convert(
      exportAll(
        collections: collections,
        activeModes: activeModes,
        format: format,
      ),
    );
  }

  /// Export a single collection with ALL modes in one document.
  ///
  /// The output nests each mode under a mode key:
  /// ```json
  /// { "light": { ... tokens ... }, "dark": { ... tokens ... } }
  /// ```
  static Map<String, dynamic> exportAllModes({
    required VariableCollection collection,
    DesignTokenFormat format = DesignTokenFormat.w3c,
  }) {
    final result = <String, dynamic>{};
    for (final mode in collection.modes) {
      result[_sanitizeKey(mode.name)] = exportCollection(
        collection: collection,
        modeId: mode.id,
        format: format,
      );
    }
    return result;
  }

  /// Export all modes to a JSON string.
  static String exportAllModesToJson({
    required VariableCollection collection,
    DesignTokenFormat format = DesignTokenFormat.w3c,
  }) {
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(exportAllModes(collection: collection, format: format));
  }

  /// Import result containing both the collection and any validation errors.
  static ({VariableCollection collection, List<String> errors})
  importW3CWithValidation({
    required String collectionId,
    required String collectionName,
    required String modeId,
    required Map<String, dynamic> tokenDocument,
  }) {
    final errors = <String>[];
    final variables = <DesignVariable>[];

    _walkW3CTokensValidated(
      tokenDocument,
      <String>[],
      modeId,
      variables,
      errors,
    );

    final collection = VariableCollection(
      id: collectionId,
      name: collectionName,
      modes: [VariableMode(id: modeId, name: modeId)],
      variables: variables,
    );

    return (collection: collection, errors: errors);
  }

  /// Like [_walkW3CTokens] but collects errors instead of silently skipping.
  static void _walkW3CTokensValidated(
    Map<String, dynamic> node,
    List<String> path,
    String modeId,
    List<DesignVariable> out,
    List<String> errors,
  ) {
    for (final entry in node.entries) {
      final key = entry.key;
      if (key.startsWith(r'$')) continue;
      final child = entry.value;
      if (child is! Map<String, dynamic>) {
        errors.add(
          'Invalid token at ${[...path, key].join("/")}: expected map',
        );
        continue;
      }

      if (child.containsKey(r'$value')) {
        try {
          final type = _parseW3CType(child[r'$type'] as String?);
          final value = _deserializeValue(type, child[r'$value']);
          final groupPath = path.isNotEmpty ? path.join('/') : null;
          final id = [...path, key].join('-');

          out.add(
            DesignVariable(
              id: id,
              name: key,
              type: type,
              group: groupPath,
              description: child[r'$description'] as String?,
              values: {modeId: value},
            ),
          );
        } catch (e) {
          errors.add('Error parsing token ${[...path, key].join("/")}: $e');
        }
      } else {
        _walkW3CTokensValidated(child, [...path, key], modeId, out, errors);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // W3C DTCG Format
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _exportW3C(
    VariableCollection collection,
    String modeId,
  ) {
    final root = <String, dynamic>{};
    final resolved = collection.resolveAll(modeId);

    for (final variable in collection.variables) {
      final value = resolved[variable.id];
      if (value == null) continue;

      final token = <String, dynamic>{
        r'$value': _serializeValue(variable.type, value),
        r'$type': _w3cTypeName(variable.type),
      };
      if (variable.description != null) {
        token[r'$description'] = variable.description;
      }

      // Nest by group path (e.g. "colors/primary" → {"colors": {"primary": ...}}).
      _setNested(root, _tokenPath(variable), token);
    }

    return root;
  }

  // ---------------------------------------------------------------------------
  // Style Dictionary Format
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _exportStyleDictionary(
    VariableCollection collection,
    String modeId,
  ) {
    final root = <String, dynamic>{};
    final resolved = collection.resolveAll(modeId);

    for (final variable in collection.variables) {
      final value = resolved[variable.id];
      if (value == null) continue;

      final token = <String, dynamic>{
        'value': _serializeValue(variable.type, value),
        'type': _sdTypeName(variable.type),
      };
      if (variable.description != null) {
        token['comment'] = variable.description;
      }
      if (variable.group != null) {
        token['attributes'] = {'category': variable.group};
      }

      _setNested(root, _tokenPath(variable), token);
    }

    return root;
  }

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------

  /// Import a W3C DTCG token document into a [VariableCollection].
  ///
  /// Creates variables from the nested token structure, mapping W3C types
  /// back to [DesignVariableType].
  static VariableCollection importW3C({
    required String collectionId,
    required String collectionName,
    required String modeId,
    required Map<String, dynamic> tokenDocument,
  }) {
    final variables = <DesignVariable>[];
    _walkW3CTokens(tokenDocument, <String>[], modeId, variables);

    return VariableCollection(
      id: collectionId,
      name: collectionName,
      modes: [VariableMode(id: modeId, name: modeId)],
      variables: variables,
    );
  }

  static void _walkW3CTokens(
    Map<String, dynamic> node,
    List<String> path,
    String modeId,
    List<DesignVariable> out,
  ) {
    for (final entry in node.entries) {
      final key = entry.key;
      if (key.startsWith(r'$')) continue; // skip meta keys
      final child = entry.value;
      if (child is! Map<String, dynamic>) continue;

      if (child.containsKey(r'$value')) {
        // Leaf token.
        final type = _parseW3CType(child[r'$type'] as String?);
        final value = _deserializeValue(type, child[r'$value']);
        final groupPath = path.isNotEmpty ? path.join('/') : null;
        final id = [...path, key].join('-');

        out.add(
          DesignVariable(
            id: id,
            name: key,
            type: type,
            group: groupPath,
            description: child[r'$description'] as String?,
            values: {modeId: value},
          ),
        );
      } else {
        // Group node — recurse.
        _walkW3CTokens(child, [...path, key], modeId, out);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Convert a variable's group + name into a token path.
  static List<String> _tokenPath(DesignVariable variable) {
    if (variable.group != null && variable.group!.isNotEmpty) {
      return [...variable.group!.split('/'), _sanitizeKey(variable.name)];
    }
    return [_sanitizeKey(variable.name)];
  }

  /// Set a value in a nested map using a path.
  static void _setNested(
    Map<String, dynamic> root,
    List<String> path,
    dynamic value,
  ) {
    var current = root;
    for (var i = 0; i < path.length - 1; i++) {
      current =
          current.putIfAbsent(path[i], () => <String, dynamic>{})
              as Map<String, dynamic>;
    }
    current[path.last] = value;
  }

  /// Sanitize a key for use in JSON (lowercase, replace spaces with hyphens).
  static String _sanitizeKey(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'\s+'), '-');

  /// Map [DesignVariableType] to W3C DTCG $type values.
  static String _w3cTypeName(DesignVariableType type) {
    switch (type) {
      case DesignVariableType.color:
        return 'color';
      case DesignVariableType.number:
        return 'number';
      case DesignVariableType.string:
        return 'string';
      case DesignVariableType.boolean:
        return 'boolean';
    }
  }

  /// Map [DesignVariableType] to Style Dictionary type values.
  static String _sdTypeName(DesignVariableType type) {
    switch (type) {
      case DesignVariableType.color:
        return 'color';
      case DesignVariableType.number:
        return 'sizing'; // SD convention
      case DesignVariableType.string:
        return 'other';
      case DesignVariableType.boolean:
        return 'other';
    }
  }

  /// Parse a W3C $type string back to [DesignVariableType].
  static DesignVariableType _parseW3CType(String? type) {
    switch (type) {
      case 'color':
        return DesignVariableType.color;
      case 'number':
      case 'dimension':
        return DesignVariableType.number;
      case 'boolean':
        return DesignVariableType.boolean;
      default:
        return DesignVariableType.string;
    }
  }

  /// Serialize a value for token output.
  static dynamic _serializeValue(DesignVariableType type, dynamic value) {
    if (type == DesignVariableType.color && value is int) {
      // Convert ARGB32 int to CSS hex color (#RRGGBBAA).
      final a = (value >> 24) & 0xFF;
      final r = (value >> 16) & 0xFF;
      final g = (value >> 8) & 0xFF;
      final b = value & 0xFF;
      if (a == 0xFF) {
        return '#${r.toRadixString(16).padLeft(2, '0')}'
            '${g.toRadixString(16).padLeft(2, '0')}'
            '${b.toRadixString(16).padLeft(2, '0')}';
      }
      return '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}'
          '${a.toRadixString(16).padLeft(2, '0')}';
    }
    return value;
  }

  /// Deserialize a token value back to the Dart runtime type.
  static dynamic _deserializeValue(DesignVariableType type, dynamic value) {
    if (type == DesignVariableType.color && value is String) {
      return _parseHexColor(value);
    }
    if (type == DesignVariableType.number && value is num) {
      return value.toDouble();
    }
    return value;
  }

  /// Parse a CSS hex color (#RGB, #RRGGBB, #RRGGBBAA) to ARGB32 int.
  static int _parseHexColor(String hex) {
    var clean = hex.replaceAll('#', '');
    if (clean.length == 3) {
      // #RGB → #RRGGBB
      clean = clean.split('').map((c) => '$c$c').join();
    }
    if (clean.length == 6) {
      return int.parse('FF$clean', radix: 16);
    }
    if (clean.length == 8) {
      // #RRGGBBAA → AARRGGBB
      final rr = clean.substring(0, 2);
      final gg = clean.substring(2, 4);
      final bb = clean.substring(4, 6);
      final aa = clean.substring(6, 8);
      return int.parse('$aa$rr$gg$bb', radix: 16);
    }
    return 0xFF000000; // fallback: black
  }
}
