import 'dart:ui' as ui;
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_visitor.dart';
import './group_node.dart';

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
  /// Instances render from this content.
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

  SymbolDefinition({
    required this.id,
    required this.name,
    required this.content,
    this.overridableProps = const [],
    this.description = '',
    this.tags = const [],
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       modifiedAt = modifiedAt ?? DateTime.now();

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
  };

  factory SymbolDefinition.fromJson(
    Map<String, dynamic> json,
    CanvasNode Function(Map<String, dynamic>) nodeFactory,
  ) {
    final contentNode = nodeFactory(json['content'] as Map<String, dynamic>);
    if (contentNode is! GroupNode) {
      throw ArgumentError('Symbol content must be a GroupNode');
    }

    return SymbolDefinition(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      content: contentNode,
      overridableProps:
          (json['overridableProps'] as List<dynamic>?)?.cast<String>() ?? [],
      description: json['description'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
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

  SymbolInstanceNode({
    required super.id,
    required this.symbolDefinitionId,
    this.overrides = const {},
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  });

  @override
  ui.Rect get localBounds {
    // Bounds are determined by the definition content.
    // Without access to the registry here, use a default.
    // The renderer resolves actual bounds via the registry.
    return ui.Rect.fromLTWH(0, 0, 100, 100);
  }

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
    return json;
  }

  factory SymbolInstanceNode.fromJson(Map<String, dynamic> json) {
    final node = SymbolInstanceNode(
      id: json['id'] as String,
      symbolDefinitionId: json['symbolDefinitionId'] as String,
      overrides: (json['overrides'] as Map<String, dynamic>?) ?? {},
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitSymbolInstance(this);
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
  void remove(String id) {
    _definitions.remove(id);
  }

  /// Look up a definition by ID. Returns null if not found.
  SymbolDefinition? lookup(String id) => _definitions[id];

  /// Check if a definition exists.
  bool contains(String id) => _definitions.containsKey(id);

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
