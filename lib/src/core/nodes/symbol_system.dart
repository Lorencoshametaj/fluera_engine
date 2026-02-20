import 'dart:ui' as ui;
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import './group_node.dart';
import './variant_property.dart';

// ---------------------------------------------------------------------------
// Symbol Definition
// ---------------------------------------------------------------------------

/// Master definition of a reusable symbol/component.
///
/// A symbol packages a [GroupNode] subtree as a reusable component.
/// Instances ([SymbolInstanceNode]) reference this definition and can
/// override specific properties.
///
/// ```
/// SymbolDefinition("button")
///   content: GroupNode [
///     PathNode (rectangle bg),
///     RichTextNode ("Click me"),
///   ]
///   overridableProps: ["text", "fillColor"]
/// ```
class SymbolDefinition {
  /// Unique identifier.
  final String id;

  /// Human-readable name (shown in component library).
  String name;

  /// The master geometry tree — this is the source of truth.
  /// When variant properties are defined, this serves as the default
  /// variant content. When no variants exist, this is the only content.
  GroupNode content;

  /// Property paths that instances are allowed to override.
  /// e.g. `["children.0.fillColor", "children.1.text"]`
  List<String> overridableProps;

  /// Optional description for the component library.
  String description;

  /// Tags for search/filtering in the component library.
  List<String> tags;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Last modification timestamp.
  DateTime modifiedAt;

  // ---------------------------------------------------------------------------
  // Variant Properties
  // ---------------------------------------------------------------------------

  /// Declared variant property axes (e.g. "Size", "State").
  ///
  /// Each property defines an axis in the variant matrix. Instances
  /// select a value for each axis to resolve the visual content.
  List<VariantProperty> variantProperties;

  /// The variant matrix: maps canonical variant keys to content subtrees.
  ///
  /// Keys are built via [VariantContent.buildVariantKey] from sorted
  /// property-value pairs. The default content is stored under
  /// [defaultVariantKey].
  final Map<String, VariantContent> variants;

  /// Canonical key for the default variant combination.
  ///
  /// Built from each property's [VariantProperty.defaultValue].
  /// Empty string if no variant properties are defined.
  String get defaultVariantKey {
    if (variantProperties.isEmpty) return '';
    final defaults = <String, String>{};
    for (final prop in variantProperties) {
      defaults[prop.name] = prop.defaultValue;
    }
    return VariantContent.buildVariantKey(defaults);
  }

  SymbolDefinition({
    required this.id,
    required this.name,
    required this.content,
    this.overridableProps = const [],
    this.description = '',
    this.tags = const [],
    this.variantProperties = const [],
    Map<String, VariantContent>? variants,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) : variants = variants ?? {},
       createdAt = createdAt ?? DateTime.now(),
       modifiedAt = modifiedAt ?? DateTime.now();

  // ---------------------------------------------------------------------------
  // Variant resolution
  // ---------------------------------------------------------------------------

  /// Whether this component has variant properties defined.
  bool get hasVariants => variantProperties.isNotEmpty;

  /// Resolve the [GroupNode] content for a given set of property selections.
  ///
  /// Missing selections are filled with each property's [defaultValue].
  /// If no matching variant is found, falls back to the default variant,
  /// then to the base [content].
  GroupNode resolveContent(Map<String, String> selections) {
    if (!hasVariants) return content;

    // Fill missing selections with defaults.
    final resolved = <String, String>{};
    for (final prop in variantProperties) {
      resolved[prop.name] = selections[prop.name] ?? prop.defaultValue;
    }

    final key = VariantContent.buildVariantKey(resolved);

    // Exact match.
    if (variants.containsKey(key)) {
      return variants[key]!.content;
    }

    // Fallback to default variant.
    final defKey = defaultVariantKey;
    if (variants.containsKey(defKey)) {
      return variants[defKey]!.content;
    }

    // Ultimate fallback: base content.
    return content;
  }

  /// Add or update a variant content entry.
  ///
  /// Builds the canonical key from [propertyValues] and stores the
  /// [content] subtree in the variant matrix.
  void setVariant(
    Map<String, String> propertyValues,
    GroupNode variantContent,
  ) {
    final key = VariantContent.buildVariantKey(propertyValues);
    variants[key] = VariantContent(
      propertyValues: Map.unmodifiable(propertyValues),
      content: variantContent,
      variantKey: key,
    );
    modifiedAt = DateTime.now();
  }

  /// Remove a variant content entry by its property values.
  bool removeVariant(Map<String, String> propertyValues) {
    final key = VariantContent.buildVariantKey(propertyValues);
    final removed = variants.remove(key) != null;
    if (removed) modifiedAt = DateTime.now();
    return removed;
  }

  /// Add a new variant property axis.
  ///
  /// Does **not** auto-populate the variant matrix — callers should
  /// add variant content entries for the new combinations.
  ///
  /// Rejects properties with duplicate IDs **or** duplicate names.
  void addVariantProperty(VariantProperty property) {
    if (variantProperties.any((p) => p.id == property.id)) return;
    if (variantProperties.any((p) => p.name == property.name)) return;
    variantProperties = [...variantProperties, property];
    modifiedAt = DateTime.now();
  }

  /// Remove a variant property axis by ID.
  ///
  /// Also removes all variant content entries that reference this property.
  /// Returns `false` if the property was not found.
  bool removeVariantProperty(String propertyId) {
    final prop = variantProperties.where((p) => p.id == propertyId).firstOrNull;
    if (prop == null) return false;

    variantProperties =
        variantProperties.where((p) => p.id != propertyId).toList();

    // Remove variants that reference this property.
    variants.removeWhere((key, vc) => vc.propertyValues.containsKey(prop.name));
    modifiedAt = DateTime.now();
    return true;
  }

  /// Get all variant keys currently in the matrix.
  Iterable<String> get variantKeys => variants.keys;

  /// Look up a variant by its canonical key.
  VariantContent? lookupVariant(String key) => variants[key];

  // ---------------------------------------------------------------------------
  // Matrix completeness
  // ---------------------------------------------------------------------------

  /// Variant property axes that participate in the Cartesian product.
  ///
  /// Only [VariantPropertyType.variant] and [VariantPropertyType.boolean]
  /// axes contribute to the matrix. Text and instanceSwap are free-form
  /// and do not create combinatorial entries.
  List<VariantProperty> get _matrixProperties =>
      variantProperties
          .where(
            (p) =>
                p.type == VariantPropertyType.variant ||
                p.type == VariantPropertyType.boolean,
          )
          .toList();

  /// Compute the full Cartesian product of all enum/boolean property options.
  ///
  /// Returns a list of property-value maps, one for each possible combination.
  /// Text and instanceSwap axes are excluded (they are free-form).
  List<Map<String, String>> get allCombinations {
    final props = _matrixProperties;
    if (props.isEmpty) return [{}];

    List<Map<String, String>> result = [{}];
    for (final prop in props) {
      final expanded = <Map<String, String>>[];
      final values =
          prop.type == VariantPropertyType.boolean
              ? ['true', 'false']
              : prop.options;
      for (final existing in result) {
        for (final value in values) {
          expanded.add({...existing, prop.name: value});
        }
      }
      result = expanded;
    }
    return result;
  }

  /// Returns the variant keys that are NOT yet in the matrix.
  ///
  /// Useful for UI to show incomplete variant coverage.
  List<String> get missingVariantKeys {
    final all = allCombinations;
    final missing = <String>[];
    for (final combo in all) {
      final key = VariantContent.buildVariantKey(combo);
      if (!variants.containsKey(key)) {
        missing.add(key);
      }
    }
    return missing;
  }

  /// Whether every combination in the Cartesian product has content.
  bool get isMatrixComplete => missingVariantKeys.isEmpty;

  // ---------------------------------------------------------------------------
  // Rename propagation
  // ---------------------------------------------------------------------------

  /// Rename a variant option across the entire definition.
  ///
  /// Updates the property's options list, the default value,
  /// and all variant matrix keys that reference the old value.
  ///
  /// Returns `true` if the rename was applied.
  bool renameVariantOption(
    String propertyId,
    String oldValue,
    String newValue,
  ) {
    final propIndex = variantProperties.indexWhere((p) => p.id == propertyId);
    if (propIndex == -1) return false;

    final prop = variantProperties[propIndex];
    if (!prop.renameOption(oldValue, newValue)) return false;

    // Rebuild affected variant keys.
    final propName = prop.name;
    final keysToRebuild =
        variants.entries
            .where((e) => e.value.propertyValues[propName] == oldValue)
            .toList();

    for (final entry in keysToRebuild) {
      final vc = entry.value;
      variants.remove(entry.key);

      final newProps = Map<String, String>.from(vc.propertyValues);
      newProps[propName] = newValue;
      final newKey = VariantContent.buildVariantKey(newProps);

      variants[newKey] = VariantContent(
        propertyValues: Map.unmodifiable(newProps),
        content: vc.content,
        variantKey: newKey,
      );
    }

    modifiedAt = DateTime.now();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Reorder
  // ---------------------------------------------------------------------------

  /// Move a variant property axis to a new position.
  ///
  /// Does not affect variant keys (they are sorted alphabetically).
  void reorderVariantProperty(String propertyId, int newIndex) {
    final current = variantProperties.indexWhere((p) => p.id == propertyId);
    if (current == -1) return;
    if (newIndex < 0 || newIndex >= variantProperties.length) return;
    if (current == newIndex) return;

    final prop = variantProperties[current];
    final mutable = List<VariantProperty>.of(variantProperties);
    mutable.removeAt(current);
    mutable.insert(newIndex, prop);
    variantProperties = mutable;
    modifiedAt = DateTime.now();
  }

  // ---------------------------------------------------------------------------
  // Rename property axis
  // ---------------------------------------------------------------------------

  /// Rename a variant property axis (not an option, but the axis itself).
  ///
  /// Propagates the name change through all variant matrix keys and
  /// property values. Returns `true` if the rename was applied.
  bool renameVariantPropertyAxis(String propertyId, String newName) {
    final propIndex = variantProperties.indexWhere((p) => p.id == propertyId);
    if (propIndex == -1) return false;

    final prop = variantProperties[propIndex];
    final oldName = prop.name;
    if (oldName == newName) return false;

    // Guard: no other property should already have this name.
    if (variantProperties.any((p) => p.name == newName && p.id != propertyId)) {
      return false;
    }

    prop.name = newName;

    // Rebuild all variant keys that reference the old property name.
    final keysToRebuild =
        variants.entries
            .where((e) => e.value.propertyValues.containsKey(oldName))
            .toList();

    for (final entry in keysToRebuild) {
      final vc = entry.value;
      variants.remove(entry.key);

      final newProps = <String, String>{};
      for (final pv in vc.propertyValues.entries) {
        newProps[pv.key == oldName ? newName : pv.key] = pv.value;
      }
      final newKey = VariantContent.buildVariantKey(newProps);

      variants[newKey] = VariantContent(
        propertyValues: Map.unmodifiable(newProps),
        content: vc.content,
        variantKey: newKey,
      );
    }

    modifiedAt = DateTime.now();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Duplication
  // ---------------------------------------------------------------------------

  /// Create a copy of this definition with a new ID and optional name.
  ///
  /// Deep-copies variant properties and variant content map (but shares
  /// the GroupNode subtrees — callers should clone those separately if
  /// independent mutation is needed).
  SymbolDefinition copyWith({String? id, String? name}) {
    return SymbolDefinition(
      id: id ?? '${this.id}-copy',
      name: name ?? '${this.name} (Copy)',
      content: content,
      overridableProps: List.of(overridableProps),
      description: description,
      tags: List.of(tags),
      variantProperties: variantProperties.map((p) => p.copyWith()).toList(),
      variants: Map.fromEntries(
        variants.entries.map(
          (e) => MapEntry(
            e.key,
            VariantContent(
              propertyValues: Map.of(e.value.propertyValues),
              content: e.value.content,
              variantKey: e.key,
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'content': content.toJson(),
    'overridableProps': overridableProps,
    'description': description,
    'tags': tags,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    if (variantProperties.isNotEmpty)
      'variantProperties': variantProperties.map((p) => p.toJson()).toList(),
    if (variants.isNotEmpty)
      'variants': variants.values.map((v) => v.toJson()).toList(),
  };

  factory SymbolDefinition.fromJson(
    Map<String, dynamic> json,
    CanvasNode Function(Map<String, dynamic>) nodeFactory,
  ) {
    final contentNode = nodeFactory(json['content'] as Map<String, dynamic>);
    if (contentNode is! GroupNode) {
      throw ArgumentError('Symbol content must be a GroupNode');
    }

    // Parse variant properties.
    final variantProps =
        (json['variantProperties'] as List<dynamic>?)
            ?.map((p) => VariantProperty.fromJson(p as Map<String, dynamic>))
            .toList() ??
        [];

    // Parse variant content entries.
    final variantsMap = <String, VariantContent>{};
    final variantsList = json['variants'] as List<dynamic>?;
    if (variantsList != null) {
      for (final vJson in variantsList) {
        final vc = VariantContent.fromJson(
          vJson as Map<String, dynamic>,
          nodeFactory,
        );
        variantsMap[vc.variantKey] = vc;
      }
    }

    return SymbolDefinition(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      content: contentNode,
      overridableProps:
          (json['overridableProps'] as List<dynamic>?)?.cast<String>() ?? [],
      description: json['description'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      variantProperties: variantProps,
      variants: variantsMap,
      createdAt:
          json['createdAt'] != null
              ? DateTime.parse(json['createdAt'] as String)
              : null,
      modifiedAt:
          json['modifiedAt'] != null
              ? DateTime.parse(json['modifiedAt'] as String)
              : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Symbol Instance Node
// ---------------------------------------------------------------------------

/// A scene graph node that references a [SymbolDefinition].
///
/// Instead of containing its own geometry, instances point to a
/// definition and can override specific properties (e.g. text, color).
/// This enables:
/// - **Single source of truth**: edit the definition, all instances update
/// - **Per-instance customization**: override allowed properties
/// - **Memory efficiency**: geometry is shared, not duplicated
class SymbolInstanceNode extends CanvasNode {
  /// ID of the referenced [SymbolDefinition].
  final String symbolDefinitionId;

  /// Per-instance property overrides.
  ///
  /// Keys are property paths (matching [SymbolDefinition.overridableProps]),
  /// values are the overridden values.
  /// e.g. `{"children.1.text": "Buy Now", "children.0.fillColor": 0xFF00FF00}`
  Map<String, dynamic> overrides;

  /// Selected variant property values for this instance.
  ///
  /// Keys are property names (matching [VariantProperty.name]),
  /// values are the chosen option.
  /// e.g. `{"Size": "medium", "State": "hover"}`
  ///
  /// Properties not listed here fall back to their
  /// [VariantProperty.defaultValue].
  Map<String, String> variantSelections;

  /// Cached bounds from the resolved variant content.
  ///
  /// Updated by the renderer after resolving the definition content.
  /// Falls back to a default 100×100 rect when not yet resolved.
  ui.Rect? resolvedBounds;

  SymbolInstanceNode({
    required super.id,
    required this.symbolDefinitionId,
    Map<String, dynamic> overrides = const {},
    Map<String, String> variantSelections = const {},
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  }) : overrides = Map<String, dynamic>.of(overrides),
       variantSelections = Map<String, String>.of(variantSelections);

  @override
  ui.Rect get localBounds =>
      resolvedBounds ?? const ui.Rect.fromLTWH(0, 0, 100, 100);

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'symbolInstance';
    json['symbolDefinitionId'] = symbolDefinitionId;
    if (overrides.isNotEmpty) {
      json['overrides'] = overrides;
    }
    if (variantSelections.isNotEmpty) {
      json['variantSelections'] = variantSelections;
    }
    return json;
  }

  factory SymbolInstanceNode.fromJson(Map<String, dynamic> json) {
    final node = SymbolInstanceNode(
      id: NodeId(json['id'] as String),
      symbolDefinitionId: json['symbolDefinitionId'] as String,
      overrides: (json['overrides'] as Map<String, dynamic>?) ?? {},
      variantSelections:
          (json['variantSelections'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as String),
          ) ??
          {},
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitSymbolInstance(this);

  // -------------------------------------------------------------------------
  // Clone
  // -------------------------------------------------------------------------

  /// Create an independent copy of this instance with a new ID.
  SymbolInstanceNode clone({String? id}) {
    return SymbolInstanceNode(
      id: NodeId(id ?? '${this.id}-clone'),
      symbolDefinitionId: symbolDefinitionId,
      overrides: Map<String, dynamic>.from(overrides),
      variantSelections: Map<String, String>.from(variantSelections),
      name: name,
      localTransform: localTransform.clone(),
      opacity: opacity,
      blendMode: blendMode,
      isVisible: isVisible,
      isLocked: isLocked,
    );
  }

  // -------------------------------------------------------------------------
  // Variant validation
  // -------------------------------------------------------------------------

  /// Validate current [variantSelections] against a [SymbolDefinition].
  ///
  /// Returns a list of property names whose selected values are invalid
  /// (not in the property's options for enum/boolean types).
  List<String> validateSelections(SymbolDefinition definition) {
    final invalid = <String>[];
    for (final entry in variantSelections.entries) {
      final prop =
          definition.variantProperties
              .where((p) => p.name == entry.key)
              .firstOrNull;
      if (prop == null) {
        invalid.add(entry.key); // Property doesn't exist on definition.
      } else if (!prop.isValidValue(entry.value)) {
        invalid.add(entry.key); // Value is not valid for this property.
      }
    }
    return invalid;
  }

  /// Replace invalid or stale selections with their default values.
  ///
  /// Returns the number of selections that were corrected.
  int sanitizeSelections(SymbolDefinition definition) {
    int corrected = 0;
    final clean = Map<String, String>.from(variantSelections);

    // Remove selections for properties that no longer exist.
    final propNames = definition.variantProperties.map((p) => p.name).toSet();
    final staleKeys = clean.keys.where((k) => !propNames.contains(k)).toList();
    for (final key in staleKeys) {
      clean.remove(key);
      corrected++;
    }

    // Fix invalid values.
    for (final prop in definition.variantProperties) {
      final current = clean[prop.name];
      if (current != null && !prop.isValidValue(current)) {
        clean[prop.name] = prop.defaultValue;
        corrected++;
      }
    }

    if (corrected > 0) {
      variantSelections = clean;
    }
    return corrected;
  }
}

// ---------------------------------------------------------------------------
// Symbol Registry
// ---------------------------------------------------------------------------

/// Central registry that manages all [SymbolDefinition]s.
///
/// The registry is stored alongside the [SceneGraph] and provides
/// lookup by ID for the renderer and editor.
class SymbolRegistry {
  final Map<String, SymbolDefinition> _definitions = {};

  /// Creates an empty symbol registry.
  SymbolRegistry();

  /// All registered definitions.
  Iterable<SymbolDefinition> get definitions => _definitions.values;

  /// Number of registered symbols.
  int get count => _definitions.length;

  /// Register a new symbol definition.
  void register(SymbolDefinition definition) {
    _definitions[definition.id] = definition;
  }

  /// Remove a symbol definition by ID.
  ///
  /// Returns `true` if the definition was found and removed.
  bool remove(String id) {
    return _definitions.remove(id) != null;
  }

  /// Whether a symbol instance references a definition that is not in
  /// the registry (orphaned).
  bool isOrphan(SymbolInstanceNode instance) =>
      !_definitions.containsKey(instance.symbolDefinitionId);

  /// Look up a definition by ID. Returns null if not found.
  SymbolDefinition? lookup(String id) => _definitions[id];

  /// Check if a definition exists.
  bool contains(String id) => _definitions.containsKey(id);

  // -------------------------------------------------------------------------
  // Variant resolution
  // -------------------------------------------------------------------------

  /// Resolve a [SymbolInstanceNode] to its rendered [GroupNode] content.
  ///
  /// Looks up the definition, applies variant selections, and returns
  /// the resolved content subtree. Returns `null` if the definition
  /// is not registered.
  GroupNode? resolveInstance(SymbolInstanceNode instance) {
    final def = lookup(instance.symbolDefinitionId);
    if (def == null) return null;
    return def.resolveContent(instance.variantSelections);
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'definitions': _definitions.values.map((d) => d.toJson()).toList(),
  };

  factory SymbolRegistry.fromJson(
    Map<String, dynamic> json,
    CanvasNode Function(Map<String, dynamic>) nodeFactory,
  ) {
    final registry = SymbolRegistry();
    final defList = json['definitions'] as List<dynamic>? ?? [];
    for (final defJson in defList) {
      registry.register(
        SymbolDefinition.fromJson(defJson as Map<String, dynamic>, nodeFactory),
      );
    }
    return registry;
  }
}
