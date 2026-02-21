/// 🗂️ FORMAT REGISTRY — Extensible file format registration.
///
/// Manages format descriptors with capability metadata, MIME types,
/// and file extensions. Includes 10 built-in presets.
///
/// ```dart
/// final registry = FormatRegistry.withDefaults();
/// final pngFormat = registry.byExtension('png');
/// final exportFormats = registry.withCapability(FormatCapability.export);
/// ```
library;

// =============================================================================
// FORMAT CAPABILITY
// =============================================================================

/// Capabilities a file format can support.
enum FormatCapability {
  /// Can import/read this format.
  import_,

  /// Can export/write this format.
  export_,

  /// Supports multiple layers.
  layers,

  /// Supports vector graphics.
  vectors,

  /// Supports raster/bitmap data.
  raster,

  /// Supports metadata (EXIF, XMP, etc.).
  metadata,

  /// Supports transparency (alpha channel).
  transparency,

  /// Supports animation.
  animation,

  /// Supports CMYK color space.
  cmyk,

  /// Supports 16-bit or higher color depth.
  highBitDepth,
}

// =============================================================================
// FILE FORMAT DESCRIPTOR
// =============================================================================

/// Describes a supported file format.
class FileFormatDescriptor {
  /// Unique format identifier (e.g. "png", "figma", "psd").
  final String id;

  /// Display name.
  final String name;

  /// File extensions (e.g. [".png", ".PNG"]).
  final List<String> extensions;

  /// MIME types (e.g. ["image/png"]).
  final List<String> mimeTypes;

  /// Supported capabilities.
  final Set<FormatCapability> capabilities;

  /// Maximum file size in bytes (0 = unlimited).
  final int maxFileSizeBytes;

  /// Format category.
  final FormatCategory category;

  /// Description.
  final String description;

  const FileFormatDescriptor({
    required this.id,
    required this.name,
    required this.extensions,
    this.mimeTypes = const [],
    this.capabilities = const {},
    this.maxFileSizeBytes = 0,
    this.category = FormatCategory.raster,
    this.description = '',
  });

  /// Whether this format supports a specific capability.
  bool hasCapability(FormatCapability cap) => capabilities.contains(cap);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'extensions': extensions,
    'mimeTypes': mimeTypes,
    'capabilities': capabilities.map((c) => c.name).toList(),
    'category': category.name,
    'description': description,
  };

  @override
  String toString() => 'FileFormat($id, ${extensions.join("/")})';
}

/// Format category for grouping.
enum FormatCategory { raster, vector, design, document, cad, animation }

// =============================================================================
// FORMAT REGISTRY
// =============================================================================

/// Registry of supported file formats.
class FormatRegistry {
  final Map<String, FileFormatDescriptor> _formats = {};

  FormatRegistry();

  /// Create a registry with built-in format presets.
  factory FormatRegistry.withDefaults() {
    final registry = FormatRegistry();
    for (final fmt in _builtInFormats) {
      registry.register(fmt);
    }
    return registry;
  }

  /// Register a format.
  void register(FileFormatDescriptor format) {
    _formats[format.id] = format;
  }

  /// Unregister a format.
  void unregister(String formatId) => _formats.remove(formatId);

  /// Get a format by ID.
  FileFormatDescriptor? byId(String id) => _formats[id];

  /// Find a format by file extension (with or without dot).
  FileFormatDescriptor? byExtension(String ext) {
    final normalized =
        ext.startsWith('.') ? ext.toLowerCase() : '.$ext'.toLowerCase();
    for (final fmt in _formats.values) {
      if (fmt.extensions.any((e) => e.toLowerCase() == normalized)) {
        return fmt;
      }
    }
    return null;
  }

  /// Find a format by MIME type.
  FileFormatDescriptor? byMimeType(String mime) {
    for (final fmt in _formats.values) {
      if (fmt.mimeTypes.contains(mime)) return fmt;
    }
    return null;
  }

  /// Get all formats with a specific capability.
  List<FileFormatDescriptor> withCapability(FormatCapability cap) =>
      _formats.values.where((f) => f.hasCapability(cap)).toList();

  /// Get all formats in a category.
  List<FileFormatDescriptor> inCategory(FormatCategory cat) =>
      _formats.values.where((f) => f.category == cat).toList();

  /// All registered formats.
  List<FileFormatDescriptor> get all => _formats.values.toList();

  /// Number of registered formats.
  int get count => _formats.length;

  // ── Built-in format presets ──

  static const _builtInFormats = <FileFormatDescriptor>[
    FileFormatDescriptor(
      id: 'png',
      name: 'PNG',
      extensions: ['.png'],
      mimeTypes: ['image/png'],
      category: FormatCategory.raster,
      capabilities: {
        FormatCapability.import_,
        FormatCapability.export_,
        FormatCapability.raster,
        FormatCapability.transparency,
      },
    ),
    FileFormatDescriptor(
      id: 'jpg',
      name: 'JPEG',
      extensions: ['.jpg', '.jpeg'],
      mimeTypes: ['image/jpeg'],
      category: FormatCategory.raster,
      capabilities: {
        FormatCapability.import_,
        FormatCapability.export_,
        FormatCapability.raster,
        FormatCapability.metadata,
      },
    ),
    FileFormatDescriptor(
      id: 'webp',
      name: 'WebP',
      extensions: ['.webp'],
      mimeTypes: ['image/webp'],
      category: FormatCategory.raster,
      capabilities: {
        FormatCapability.import_,
        FormatCapability.export_,
        FormatCapability.raster,
        FormatCapability.transparency,
        FormatCapability.animation,
      },
    ),
    FileFormatDescriptor(
      id: 'avif',
      name: 'AVIF',
      extensions: ['.avif'],
      mimeTypes: ['image/avif'],
      category: FormatCategory.raster,
      capabilities: {
        FormatCapability.export_,
        FormatCapability.raster,
        FormatCapability.transparency,
        FormatCapability.highBitDepth,
      },
    ),
    FileFormatDescriptor(
      id: 'tiff',
      name: 'TIFF',
      extensions: ['.tiff', '.tif'],
      mimeTypes: ['image/tiff'],
      category: FormatCategory.raster,
      capabilities: {
        FormatCapability.import_,
        FormatCapability.export_,
        FormatCapability.raster,
        FormatCapability.layers,
        FormatCapability.cmyk,
        FormatCapability.highBitDepth,
        FormatCapability.metadata,
      },
    ),
    FileFormatDescriptor(
      id: 'svg',
      name: 'SVG',
      extensions: ['.svg'],
      mimeTypes: ['image/svg+xml'],
      category: FormatCategory.vector,
      capabilities: {
        FormatCapability.import_,
        FormatCapability.export_,
        FormatCapability.vectors,
        FormatCapability.transparency,
      },
    ),
    FileFormatDescriptor(
      id: 'pdf',
      name: 'PDF',
      extensions: ['.pdf'],
      mimeTypes: ['application/pdf'],
      category: FormatCategory.document,
      capabilities: {
        FormatCapability.import_,
        FormatCapability.export_,
        FormatCapability.vectors,
        FormatCapability.raster,
        FormatCapability.layers,
        FormatCapability.metadata,
      },
    ),
    FileFormatDescriptor(
      id: 'psd',
      name: 'Photoshop',
      extensions: ['.psd'],
      mimeTypes: ['image/vnd.adobe.photoshop'],
      category: FormatCategory.design,
      capabilities: {
        FormatCapability.import_,
        FormatCapability.raster,
        FormatCapability.layers,
        FormatCapability.cmyk,
        FormatCapability.highBitDepth,
        FormatCapability.metadata,
      },
    ),
    FileFormatDescriptor(
      id: 'figma',
      name: 'Figma',
      extensions: ['.fig'],
      mimeTypes: ['application/x-figma'],
      category: FormatCategory.design,
      capabilities: {
        FormatCapability.import_,
        FormatCapability.vectors,
        FormatCapability.layers,
      },
    ),
    FileFormatDescriptor(
      id: 'sketch',
      name: 'Sketch',
      extensions: ['.sketch'],
      mimeTypes: ['application/x-sketch'],
      category: FormatCategory.design,
      capabilities: {
        FormatCapability.import_,
        FormatCapability.vectors,
        FormatCapability.layers,
      },
    ),
  ];
}
