import '../scene_graph/canvas_node.dart';
import './group_node.dart';
import '../../utils/uid.dart';

// =============================================================================
// 🎯 COMPONENT VARIANT PROPERTIES
//
// Typed property axes for Figma-style component variants.
// A SymbolDefinition declares a list of VariantPropertys (axes) and stores
// a VariantContent for each combination in the Cartesian product.
// =============================================================================

// ---------------------------------------------------------------------------
// Property type enum
// ---------------------------------------------------------------------------

/// The kind of variant property exposed by a component.
///
/// - [variant]: Enum-like axis with discrete options (e.g. size: small/medium/large).
/// - [boolean]: Toggle property (e.g. hasIcon: true/false).
/// - [text]: Exposed text override (e.g. label: "Click me").
/// - [instanceSwap]: Swap a child instance for another symbol definition.
enum VariantPropertyType { variant, boolean, text, instanceSwap }

// ---------------------------------------------------------------------------
// VariantProperty
// ---------------------------------------------------------------------------

/// A typed property axis on a component definition.
///
/// Each property declares a name, a type, and (for enum-like axes) a list
/// of allowed options. Properties are identified by [id] so they survive
/// rename operations.
///
/// ```dart
/// VariantProperty(
///   name: 'Size',
///   type: VariantPropertyType.variant,
///   options: ['small', 'medium', 'large'],
///   defaultValue: 'medium',
/// );
/// ```
class VariantProperty {
  /// Unique, stable identifier.
  final String id;

  /// Human-readable name (displayed in the property panel).
  String name;

  /// What kind of property this is.
  VariantPropertyType type;

  /// Allowed values for [VariantPropertyType.variant].
  ///
  /// For [VariantPropertyType.boolean] this is always `['true', 'false']`.
  /// For [VariantPropertyType.text] / [VariantPropertyType.instanceSwap]
  /// this list is typically empty (free-form values).
  List<String> options;

  /// Default value when an instance does not specify this property.
  String defaultValue;

  VariantProperty({
    String? id,
    required this.name,
    required this.type,
    this.options = const [],
    required this.defaultValue,
  }) : id = id ?? generateUid();

  // -- Convenience constructors ---------------------------------------------

  /// Create a boolean variant property.
  factory VariantProperty.boolean({
    String? id,
    required String name,
    bool defaultValue = false,
  }) => VariantProperty(
    id: id,
    name: name,
    type: VariantPropertyType.boolean,
    options: const ['true', 'false'],
    defaultValue: defaultValue.toString(),
  );

  /// Create an enum-like variant property.
  factory VariantProperty.variant({
    String? id,
    required String name,
    required List<String> options,
    String? defaultValue,
  }) {
    if (options.isEmpty) {
      throw ArgumentError('Variant property must have at least one option');
    }
    return VariantProperty(
      id: id,
      name: name,
      type: VariantPropertyType.variant,
      options: List.of(options),
      defaultValue: defaultValue ?? options.first,
    );
  }

  /// Create a text variant property.
  factory VariantProperty.text({
    String? id,
    required String name,
    String defaultValue = '',
  }) => VariantProperty(
    id: id,
    name: name,
    type: VariantPropertyType.text,
    defaultValue: defaultValue,
  );

  /// Create an instance-swap variant property.
  factory VariantProperty.instanceSwap({
    String? id,
    required String name,
    required String defaultSymbolId,
  }) => VariantProperty(
    id: id,
    name: name,
    type: VariantPropertyType.instanceSwap,
    defaultValue: defaultSymbolId,
  );

  // -- Mutations ------------------------------------------------------------

  /// Create a copy with optional field overrides.
  ///
  /// Uses the sentinel [_absent] pattern so callers can explicitly pass `null`
  /// for nullable fields (currently none are nullable, but this is
  /// future-proof).
  VariantProperty copyWith({
    String? name,
    VariantPropertyType? type,
    List<String>? options,
    String? defaultValue,
  }) {
    return VariantProperty(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      options: options ?? List.of(this.options),
      defaultValue: defaultValue ?? this.defaultValue,
    );
  }

  /// Add a new option to a [VariantPropertyType.variant] property.
  ///
  /// No-op if the option already exists.
  void addOption(String value) {
    if (options.contains(value)) return;
    options = [...options, value];
  }

  /// Remove an option from a [VariantPropertyType.variant] property.
  ///
  /// If the removed option was the [defaultValue], the default is reset
  /// to the first remaining option (or empty string if none remain).
  ///
  /// Returns `true` if the option was found and removed.
  bool removeOption(String value) {
    if (!options.contains(value)) return false;
    options = options.where((o) => o != value).toList();
    if (defaultValue == value) {
      defaultValue = options.isNotEmpty ? options.first : '';
    }
    return true;
  }

  /// Rename an option value in-place.
  ///
  /// Updates the options list and, if the renamed option was the default,
  /// updates [defaultValue] as well.
  ///
  /// Returns `true` if the option was found and renamed.
  bool renameOption(String oldValue, String newValue) {
    final index = options.indexOf(oldValue);
    if (index == -1) return false;
    if (options.contains(newValue)) return false; // Target already exists.

    final mutable = List<String>.of(options);
    mutable[index] = newValue;
    options = mutable;

    if (defaultValue == oldValue) {
      defaultValue = newValue;
    }
    return true;
  }

  // -- Validation -----------------------------------------------------------

  /// Whether a given [value] is valid for this property.
  bool isValidValue(String value) {
    switch (type) {
      case VariantPropertyType.variant:
        return options.contains(value);
      case VariantPropertyType.boolean:
        return value == 'true' || value == 'false';
      case VariantPropertyType.text:
        return true; // Any string is valid.
      case VariantPropertyType.instanceSwap:
        return value.isNotEmpty; // Must be a symbol ID.
    }
  }

  // -- Serialization --------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    if (options.isNotEmpty) 'options': options,
    'defaultValue': defaultValue,
  };

  factory VariantProperty.fromJson(Map<String, dynamic> json) {
    return VariantProperty(
      id: json['id'] as String? ?? generateUid(),
      name: json['name'] as String,
      type: VariantPropertyType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => VariantPropertyType.variant,
      ),
      options: (json['options'] as List<dynamic>?)?.cast<String>() ?? const [],
      defaultValue: json['defaultValue'] as String? ?? '',
    );
  }

  // -- Equality (by id) -----------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VariantProperty &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VariantProperty($name: $type)';
}

// ---------------------------------------------------------------------------
// VariantContent
// ---------------------------------------------------------------------------

/// A single variant entry in the variant matrix.
///
/// Maps a specific combination of property values to a [GroupNode] subtree
/// that represents the visual state for that combination.
///
/// The [variantKey] is a canonical string built from sorted property values:
/// ```
/// "size=medium,state=hover"
/// ```
class VariantContent {
  /// Canonical key for this variant combination.
  ///
  /// Built from [propertyValues] via [buildVariantKey].
  final String variantKey;

  /// The property name→value pairs for this variant.
  ///
  /// e.g. `{"size": "medium", "state": "hover"}`
  final Map<String, String> propertyValues;

  /// The visual subtree for this variant combination.
  GroupNode content;

  VariantContent({
    required this.propertyValues,
    required this.content,
    String? variantKey,
  }) : variantKey = variantKey ?? buildVariantKey(propertyValues);

  /// Build a canonical variant key from property-value pairs.
  ///
  /// Properties are sorted alphabetically by name, then joined with commas:
  /// ```
  /// buildVariantKey({"state": "hover", "size": "medium"})
  /// // => "size=medium,state=hover"
  /// ```
  static String buildVariantKey(Map<String, String> propertyValues) {
    if (propertyValues.isEmpty) return '';
    final sorted =
        propertyValues.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return sorted
        .map((e) => '${_escapeKeyPart(e.key)}=${_escapeKeyPart(e.value)}')
        .join(',');
  }

  /// Escape `=` and `,` in key parts to prevent ambiguous variant keys.
  static String _escapeKeyPart(String s) =>
      s.replaceAll('%', '%25').replaceAll('=', '%3D').replaceAll(',', '%2C');

  /// Unescape a variant key part.
  static String unescapeKeyPart(String s) =>
      s.replaceAll('%2C', ',').replaceAll('%3D', '=').replaceAll('%25', '%');

  // -- Serialization --------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'variantKey': variantKey,
    'propertyValues': propertyValues,
    'content': content.toJson(),
  };

  factory VariantContent.fromJson(
    Map<String, dynamic> json,
    CanvasNode Function(Map<String, dynamic>) nodeFactory,
  ) {
    final contentNode = nodeFactory(json['content'] as Map<String, dynamic>);
    if (contentNode is! GroupNode) {
      throw ArgumentError('VariantContent.content must be a GroupNode');
    }

    final pvMap =
        (json['propertyValues'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as String),
        ) ??
        {};

    // Always recompute the key from propertyValues to prevent desync.
    final computedKey = buildVariantKey(pvMap);

    return VariantContent(
      variantKey: computedKey,
      propertyValues: pvMap,
      content: contentNode,
    );
  }

  @override
  String toString() => 'VariantContent($variantKey)';
}
