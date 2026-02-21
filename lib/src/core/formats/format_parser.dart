/// 🗂️ FORMAT PARSER — Multi-format import with intermediate representation.
///
/// Defines a structured IR (ParsedDocument/ParsedLayer) and abstract
/// parser base for implementing format-specific importers.
///
/// ```dart
/// final doc = ParsedDocument(
///   name: 'my-design',
///   width: 1920, height: 1080,
///   layers: [ParsedLayer(...)],
/// );
/// ```
library;

// =============================================================================
// PARSED LAYER TYPE
// =============================================================================

/// Type of a parsed layer.
enum ParsedLayerType { raster, vector, text, group, adjustment, mask }

// =============================================================================
// PARSED LAYER
// =============================================================================

/// A single layer in the intermediate representation.
class ParsedLayer {
  /// Layer identifier.
  final String id;

  /// Layer name.
  final String name;

  /// Layer type.
  final ParsedLayerType type;

  /// Position (x, y).
  final double x, y;

  /// Dimensions.
  final double width, height;

  /// Opacity (0–1).
  final double opacity;

  /// Whether the layer is visible.
  final bool visible;

  /// Whether the layer is locked.
  final bool locked;

  /// Blend mode name.
  final String blendMode;

  /// Child layers (for groups).
  final List<ParsedLayer> children;

  /// Custom properties.
  final Map<String, dynamic> properties;

  const ParsedLayer({
    required this.id,
    this.name = '',
    this.type = ParsedLayerType.raster,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.opacity = 1.0,
    this.visible = true,
    this.locked = false,
    this.blendMode = 'normal',
    this.children = const [],
    this.properties = const {},
  });

  /// Total number of layers (including nested).
  int get totalLayerCount {
    int count = 1;
    for (final child in children) {
      count += child.totalLayerCount;
    }
    return count;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'opacity': opacity,
    'visible': visible,
    'locked': locked,
    'blendMode': blendMode,
    if (children.isNotEmpty)
      'children': children.map((c) => c.toJson()).toList(),
    if (properties.isNotEmpty) 'properties': properties,
  };

  @override
  String toString() => 'ParsedLayer($name, ${type.name}, ${width}x$height)';
}

// =============================================================================
// PARSED DOCUMENT
// =============================================================================

/// Intermediate representation of an imported document.
class ParsedDocument {
  /// Document name.
  final String name;

  /// Canvas width.
  final double width;

  /// Canvas height.
  final double height;

  /// Top-level layers.
  final List<ParsedLayer> layers;

  /// Document metadata.
  final Map<String, dynamic> metadata;

  /// Source format ID.
  final String sourceFormat;

  /// Color profile name.
  final String? colorProfile;

  /// DPI resolution.
  final double dpi;

  const ParsedDocument({
    required this.name,
    this.width = 0,
    this.height = 0,
    this.layers = const [],
    this.metadata = const {},
    this.sourceFormat = 'unknown',
    this.colorProfile,
    this.dpi = 72,
  });

  /// Total layers in the document (including nested).
  int get totalLayers {
    int count = 0;
    for (final layer in layers) {
      count += layer.totalLayerCount;
    }
    return count;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'width': width,
    'height': height,
    'layers': layers.map((l) => l.toJson()).toList(),
    'metadata': metadata,
    'sourceFormat': sourceFormat,
    if (colorProfile != null) 'colorProfile': colorProfile,
    'dpi': dpi,
    'totalLayers': totalLayers,
  };

  @override
  String toString() =>
      'ParsedDocument($name, ${width}x$height, $totalLayers layers)';
}

// =============================================================================
// IMPORT RESULT
// =============================================================================

/// Result of a format import operation.
class ImportResult {
  /// The parsed document (null if failed).
  final ParsedDocument? document;

  /// Whether the import succeeded.
  final bool success;

  /// Error messages.
  final List<String> errors;

  /// Warning messages.
  final List<String> warnings;

  /// Import duration in milliseconds.
  final int durationMs;

  const ImportResult({
    this.document,
    this.success = true,
    this.errors = const [],
    this.warnings = const [],
    this.durationMs = 0,
  });

  /// Create a success result.
  factory ImportResult.ok(
    ParsedDocument doc, {
    int durationMs = 0,
    List<String> warnings = const [],
  }) => ImportResult(
    document: doc,
    success: true,
    durationMs: durationMs,
    warnings: warnings,
  );

  /// Create a failure result.
  factory ImportResult.fail(String error) =>
      ImportResult(success: false, errors: [error]);

  @override
  String toString() =>
      success
          ? 'ImportResult(OK, ${document?.totalLayers} layers, ${durationMs}ms)'
          : 'ImportResult(FAIL: ${errors.join(", ")})';
}

// =============================================================================
// FORMAT PARSER BASE
// =============================================================================

/// Abstract base for format-specific parsers.
abstract class FormatParserBase {
  /// Format ID this parser handles.
  String get formatId;

  /// Format display name.
  String get formatName;

  /// Supported file extensions.
  List<String> get supportedExtensions;

  /// Check if a filename is supported by this parser.
  bool canParse(String filename) {
    final lower = filename.toLowerCase();
    return supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  /// Parse raw data into a ParsedDocument.
  ///
  /// Subclasses implement the actual parsing logic.
  ImportResult parse(List<int> data, {String? filename});
}
