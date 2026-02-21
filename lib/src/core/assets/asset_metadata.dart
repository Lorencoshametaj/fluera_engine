/// 📦 ASSET METADATA — Rich cataloging for managed assets.
///
/// Provides enterprise-grade metadata for assets registered in the
/// [AssetRegistry], including tags, license tracking, dimensions,
/// MIME type, import provenance, and version history.
///
/// ```dart
/// final meta = AssetMetadata(
///   tags: {'icon', 'ui', 'brand'},
///   license: AssetLicense.royaltyFree,
///   description: 'Primary logo icon',
///   mimeType: 'image/png',
///   widthPx: 512,
///   heightPx: 512,
/// );
/// ```
library;

// =============================================================================
// ASSET LICENSE
// =============================================================================

/// License classification for a managed asset.
enum AssetLicense {
  /// Free to use without restrictions.
  royaltyFree,

  /// Licensed — usage may require attribution or fees.
  licensed,

  /// Proprietary — internal use only, no redistribution.
  proprietary,

  /// License status not yet determined.
  unknown,
}

// =============================================================================
// ASSET METADATA
// =============================================================================

/// Rich metadata for a cataloged asset.
///
/// Attached to [AssetEntry] to provide searchable, auditable information
/// about each asset in the registry.
class AssetMetadata {
  /// User-defined tags for categorization and search.
  final Set<String> tags;

  /// Human-readable description.
  final String? description;

  /// License classification.
  final AssetLicense license;

  /// Image/SVG width in pixels (null for non-visual assets).
  final int? widthPx;

  /// Image/SVG height in pixels (null for non-visual assets).
  final int? heightPx;

  /// Original file size in bytes.
  final int? fileSizeBytes;

  /// MIME type string (e.g. `'image/png'`, `'font/ttf'`).
  final String? mimeType;

  /// When this asset was first imported into the registry.
  final DateTime importedAt;

  /// Actor who imported this asset (user ID or `'system'`).
  final String importedBy;

  /// Optional custom key-value metadata.
  final Map<String, dynamic>? custom;

  AssetMetadata({
    Set<String>? tags,
    this.description,
    this.license = AssetLicense.unknown,
    this.widthPx,
    this.heightPx,
    this.fileSizeBytes,
    this.mimeType,
    DateTime? importedAt,
    this.importedBy = 'system',
    this.custom,
  }) : tags = tags ?? {},
       importedAt = importedAt ?? DateTime.now().toUtc();

  /// Create a copy with updated fields.
  AssetMetadata copyWith({
    Set<String>? tags,
    String? description,
    AssetLicense? license,
    int? widthPx,
    int? heightPx,
    int? fileSizeBytes,
    String? mimeType,
    DateTime? importedAt,
    String? importedBy,
    Map<String, dynamic>? custom,
  }) => AssetMetadata(
    tags: tags ?? this.tags,
    description: description ?? this.description,
    license: license ?? this.license,
    widthPx: widthPx ?? this.widthPx,
    heightPx: heightPx ?? this.heightPx,
    fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    mimeType: mimeType ?? this.mimeType,
    importedAt: importedAt ?? this.importedAt,
    importedBy: importedBy ?? this.importedBy,
    custom: custom ?? this.custom,
  );

  /// Add tags (returns new metadata).
  AssetMetadata addTags(Set<String> newTags) =>
      copyWith(tags: {...tags, ...newTags});

  /// Remove tags (returns new metadata).
  AssetMetadata removeTags(Set<String> removedTags) =>
      copyWith(tags: tags.difference(removedTags));

  /// Check if any tag matches a search query (case-insensitive).
  bool matchesTags(String query) {
    final q = query.toLowerCase();
    return tags.any((t) => t.toLowerCase().contains(q));
  }

  /// Full-text search across tags, description, and MIME type.
  bool matchesSearch(String query) {
    final q = query.toLowerCase();
    if (tags.any((t) => t.toLowerCase().contains(q))) return true;
    if (description?.toLowerCase().contains(q) ?? false) return true;
    if (mimeType?.toLowerCase().contains(q) ?? false) return true;
    return false;
  }

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'tags': tags.toList(),
    'license': license.name,
    'importedAt': importedAt.toIso8601String(),
    'importedBy': importedBy,
    if (description != null) 'description': description,
    if (widthPx != null) 'widthPx': widthPx,
    if (heightPx != null) 'heightPx': heightPx,
    if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
    if (mimeType != null) 'mimeType': mimeType,
    if (custom != null) 'custom': custom,
  };

  /// Deserialize from JSON.
  factory AssetMetadata.fromJson(Map<String, dynamic> json) => AssetMetadata(
    tags: (json['tags'] as List?)?.cast<String>().toSet(),
    description: json['description'] as String?,
    license: AssetLicense.values.firstWhere(
      (l) => l.name == json['license'],
      orElse: () => AssetLicense.unknown,
    ),
    widthPx: json['widthPx'] as int?,
    heightPx: json['heightPx'] as int?,
    fileSizeBytes: json['fileSizeBytes'] as int?,
    mimeType: json['mimeType'] as String?,
    importedAt:
        json['importedAt'] != null
            ? DateTime.parse(json['importedAt'] as String)
            : null,
    importedBy: json['importedBy'] as String? ?? 'system',
    custom: json['custom'] as Map<String, dynamic>?,
  );

  @override
  String toString() =>
      'AssetMetadata(tags=$tags, license=${license.name}, '
      '${mimeType ?? "unknown type"})';
}

// =============================================================================
// ASSET VERSION
// =============================================================================

/// A single version entry in an asset's history.
///
/// When an asset is updated (e.g. re-uploaded with different content),
/// a new version is recorded while preserving the previous content hash.
class AssetVersion {
  /// Sequential version number (1-based).
  final int version;

  /// Content hash (SHA-256) of this version.
  final String contentHash;

  /// When this version was created.
  final DateTime createdAt;

  /// Optional comment describing the change.
  final String? comment;

  /// Actor who created this version.
  final String createdBy;

  const AssetVersion({
    required this.version,
    required this.contentHash,
    required this.createdAt,
    this.comment,
    this.createdBy = 'system',
  });

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'version': version,
    'contentHash': contentHash,
    'createdAt': createdAt.toIso8601String(),
    'createdBy': createdBy,
    if (comment != null) 'comment': comment,
  };

  /// Deserialize from JSON.
  factory AssetVersion.fromJson(Map<String, dynamic> json) => AssetVersion(
    version: json['version'] as int,
    contentHash: json['contentHash'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    comment: json['comment'] as String?,
    createdBy: json['createdBy'] as String? ?? 'system',
  );

  @override
  String toString() => 'AssetVersion(v$version, $contentHash)';
}
