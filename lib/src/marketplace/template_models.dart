import 'dart:typed_data';

// =============================================================================
// 📦 FLUERA TEMPLATE MODELS — Data models for Marketplace & Templates
//
// Defines the complete data model layer for the template ecosystem:
// - TemplateCategory: enum of template types
// - TemplatePackage: full metadata for a marketplace template
// - TemplateSearchQuery: search/filter/sort parameters
// - TemplateSearchResult: paginated search results
// - InstalledTemplate: locally cached template with file path
// =============================================================================

/// Categories for organizing templates in the marketplace.
///
/// Each category has a display label and an emoji icon for UI rendering.
enum TemplateCategory {
  /// Study notes, lecture templates, Cornell notes
  study('Study', '📚'),

  /// Daily/weekly/monthly planners, habit trackers
  planner('Planner', '📅'),

  /// Bullet journals, gratitude journals, diaries
  journal('Journal', '📓'),

  /// Calligraphy practice sheets, lettering guides
  calligraphy('Calligraphy', '✒️'),

  /// Music staff paper, chord charts, tablature
  music('Music', '🎵'),

  /// Storyboard frames, animation planning
  storyboard('Storyboard', '🎬'),

  /// Meeting notes, project planning, wireframes
  business('Business', '💼'),

  /// Mind maps, brainstorming, concept maps
  mindMap('Mind Map', '🧠'),

  /// Math/science grid paper, lab notebooks
  science('Science', '🔬'),

  /// Language learning, vocabulary, grammar
  language('Language', '🌐'),

  /// User-created custom category
  custom('Custom', '🎨');

  /// Human-readable label for UI display.
  final String label;

  /// Emoji icon for compact UI rendering.
  final String icon;

  const TemplateCategory(this.label, this.icon);

  /// Look up a category by name (case-insensitive).
  /// Returns [custom] if not found.
  static TemplateCategory fromName(String name) {
    final lower = name.toLowerCase();
    return TemplateCategory.values.firstWhere(
      (c) => c.name.toLowerCase() == lower,
      orElse: () => TemplateCategory.custom,
    );
  }
}

/// Sort ordering for marketplace search results.
enum TemplateSortOrder {
  /// Most popular first (by download count).
  popular,

  /// Newest first (by creation date).
  newest,

  /// Highest rated first (by average rating).
  topRated,

  /// Alphabetical by title.
  alphabetical,
}

// =============================================================================
// 📋 TEMPLATE PACKAGE — Full metadata for a marketplace template
// =============================================================================

/// Complete metadata for a template in the marketplace.
///
/// Represents both remote (marketplace-hosted) and local (installed) templates.
/// All fields are serializable to/from JSON for API transport and local caching.
///
/// ```dart
/// final template = TemplatePackage(
///   id: 'tmpl_cornell_notes_v2',
///   title: 'Cornell Notes Pro',
///   description: 'Professional Cornell note-taking template...',
///   authorId: 'user_12345',
///   authorName: 'StudyMaster',
///   category: TemplateCategory.study,
///   tags: ['cornell', 'notes', 'lecture', 'study'],
///   paperType: 'cornell',
///   backgroundColorValue: 0xFFFFFBF0,
///   version: 2,
/// );
/// ```
class TemplatePackage {
  /// Unique template identifier (marketplace-assigned).
  final String id;

  /// Human-readable template title.
  final String title;

  /// Detailed description with usage instructions.
  final String description;

  /// Author's user ID on the marketplace.
  final String authorId;

  /// Author's display name.
  final String authorName;

  /// Primary category.
  final TemplateCategory category;

  /// Searchable tags (lowercase, no spaces).
  final List<String> tags;

  /// URL or storage key for the thumbnail preview image.
  final String? thumbnailUrl;

  /// Number of pages in the template.
  final int pageCount;

  /// Average user rating (0.0 – 5.0).
  final double rating;

  /// Total number of ratings received.
  final int ratingCount;

  /// Total number of downloads.
  final int downloadCount;

  /// Paper type key (matches [CanvasPaperType.storageKey]).
  final String paperType;

  /// Background color as ARGB int.
  final int backgroundColorValue;

  /// Template format version (incremented on updates).
  final int version;

  /// File size in bytes (of the .fluera template file).
  final int fileSizeBytes;

  /// Whether this template is free or requires purchase.
  final bool isFree;

  /// Price in cents (0 if free). Currency determined by marketplace.
  final int priceInCents;

  /// Whether this template is featured/promoted.
  final bool isFeatured;

  /// ISO 8601 creation timestamp.
  final DateTime createdAt;

  /// ISO 8601 last update timestamp.
  final DateTime updatedAt;

  /// Optional preview image URLs (carousel in marketplace UI).
  final List<String> previewImageUrls;

  const TemplatePackage({
    required this.id,
    required this.title,
    this.description = '',
    required this.authorId,
    required this.authorName,
    this.category = TemplateCategory.custom,
    this.tags = const [],
    this.thumbnailUrl,
    this.pageCount = 1,
    this.rating = 0.0,
    this.ratingCount = 0,
    this.downloadCount = 0,
    this.paperType = 'blank',
    this.backgroundColorValue = 0xFFFFFFFF,
    this.version = 1,
    this.fileSizeBytes = 0,
    this.isFree = true,
    this.priceInCents = 0,
    this.isFeatured = false,
    required this.createdAt,
    required this.updatedAt,
    this.previewImageUrls = const [],
  });

  /// Create a copy with updated fields.
  TemplatePackage copyWith({
    String? id,
    String? title,
    String? description,
    String? authorId,
    String? authorName,
    TemplateCategory? category,
    List<String>? tags,
    String? thumbnailUrl,
    int? pageCount,
    double? rating,
    int? ratingCount,
    int? downloadCount,
    String? paperType,
    int? backgroundColorValue,
    int? version,
    int? fileSizeBytes,
    bool? isFree,
    int? priceInCents,
    bool? isFeatured,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? previewImageUrls,
  }) {
    return TemplatePackage(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      pageCount: pageCount ?? this.pageCount,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      downloadCount: downloadCount ?? this.downloadCount,
      paperType: paperType ?? this.paperType,
      backgroundColorValue: backgroundColorValue ?? this.backgroundColorValue,
      version: version ?? this.version,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      isFree: isFree ?? this.isFree,
      priceInCents: priceInCents ?? this.priceInCents,
      isFeatured: isFeatured ?? this.isFeatured,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      previewImageUrls: previewImageUrls ?? this.previewImageUrls,
    );
  }

  /// Serialize to JSON map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'authorId': authorId,
    'authorName': authorName,
    'category': category.name,
    'tags': tags,
    if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
    'pageCount': pageCount,
    'rating': rating,
    'ratingCount': ratingCount,
    'downloadCount': downloadCount,
    'paperType': paperType,
    'backgroundColorValue': backgroundColorValue,
    'version': version,
    'fileSizeBytes': fileSizeBytes,
    'isFree': isFree,
    'priceInCents': priceInCents,
    'isFeatured': isFeatured,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    if (previewImageUrls.isNotEmpty) 'previewImageUrls': previewImageUrls,
  };

  /// Deserialize from JSON map.
  factory TemplatePackage.fromJson(Map<String, dynamic> json) {
    return TemplatePackage(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String,
      category: TemplateCategory.fromName(json['category'] as String? ?? ''),
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      thumbnailUrl: json['thumbnailUrl'] as String?,
      pageCount: json['pageCount'] as int? ?? 1,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: json['ratingCount'] as int? ?? 0,
      downloadCount: json['downloadCount'] as int? ?? 0,
      paperType: json['paperType'] as String? ?? 'blank',
      backgroundColorValue: json['backgroundColorValue'] as int? ?? 0xFFFFFFFF,
      version: json['version'] as int? ?? 1,
      fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
      isFree: json['isFree'] as bool? ?? true,
      priceInCents: json['priceInCents'] as int? ?? 0,
      isFeatured: json['isFeatured'] as bool? ?? false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAt'] as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['updatedAt'] as int,
      ),
      previewImageUrls: (json['previewImageUrls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  @override
  String toString() =>
      'TemplatePackage(id: $id, title: $title, category: ${category.name}, '
      'rating: $rating, downloads: $downloadCount)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplatePackage &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// =============================================================================
// 🔍 SEARCH QUERY & RESULT — Marketplace browsing
// =============================================================================

/// Search/filter parameters for browsing the marketplace.
///
/// ```dart
/// final query = TemplateSearchQuery(
///   category: TemplateCategory.study,
///   tags: ['cornell', 'lecture'],
///   sortOrder: TemplateSortOrder.topRated,
///   limit: 20,
/// );
/// final results = await marketplace.browseTemplates(query);
/// ```
class TemplateSearchQuery {
  /// Free-text search term (matched against title, description, tags).
  final String? searchTerm;

  /// Filter by category (null = all categories).
  final TemplateCategory? category;

  /// Filter by tags (AND logic — all tags must match).
  final List<String> tags;

  /// Sort order for results.
  final TemplateSortOrder sortOrder;

  /// Only show free templates.
  final bool freeOnly;

  /// Only show featured templates.
  final bool featuredOnly;

  /// Filter by author ID.
  final String? authorId;

  /// Filter by paper type key.
  final String? paperType;

  /// Maximum number of results to return.
  final int limit;

  /// Offset for pagination (0-based).
  final int offset;

  const TemplateSearchQuery({
    this.searchTerm,
    this.category,
    this.tags = const [],
    this.sortOrder = TemplateSortOrder.popular,
    this.freeOnly = false,
    this.featuredOnly = false,
    this.authorId,
    this.paperType,
    this.limit = 20,
    this.offset = 0,
  });

  /// Next page query.
  TemplateSearchQuery nextPage() => TemplateSearchQuery(
    searchTerm: searchTerm,
    category: category,
    tags: tags,
    sortOrder: sortOrder,
    freeOnly: freeOnly,
    featuredOnly: featuredOnly,
    authorId: authorId,
    paperType: paperType,
    limit: limit,
    offset: offset + limit,
  );

  /// Serialize to JSON (for API transport).
  Map<String, dynamic> toJson() => {
    if (searchTerm != null) 'searchTerm': searchTerm,
    if (category != null) 'category': category!.name,
    if (tags.isNotEmpty) 'tags': tags,
    'sortOrder': sortOrder.name,
    if (freeOnly) 'freeOnly': true,
    if (featuredOnly) 'featuredOnly': true,
    if (authorId != null) 'authorId': authorId,
    if (paperType != null) 'paperType': paperType,
    'limit': limit,
    'offset': offset,
  };

  /// Deserialize from JSON.
  factory TemplateSearchQuery.fromJson(Map<String, dynamic> json) {
    return TemplateSearchQuery(
      searchTerm: json['searchTerm'] as String?,
      category: json['category'] != null
          ? TemplateCategory.fromName(json['category'] as String)
          : null,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      sortOrder: TemplateSortOrder.values.firstWhere(
        (s) => s.name == (json['sortOrder'] as String?),
        orElse: () => TemplateSortOrder.popular,
      ),
      freeOnly: json['freeOnly'] as bool? ?? false,
      featuredOnly: json['featuredOnly'] as bool? ?? false,
      authorId: json['authorId'] as String?,
      paperType: json['paperType'] as String?,
      limit: json['limit'] as int? ?? 20,
      offset: json['offset'] as int? ?? 0,
    );
  }
}

/// Paginated search result from the marketplace.
class TemplateSearchResult {
  /// Templates matching the query.
  final List<TemplatePackage> templates;

  /// Total number of results (across all pages).
  final int totalCount;

  /// The query that produced this result.
  final TemplateSearchQuery query;

  const TemplateSearchResult({
    required this.templates,
    required this.totalCount,
    required this.query,
  });

  /// Whether there are more results to load.
  bool get hasMore => query.offset + templates.length < totalCount;

  /// Whether this is the first page.
  bool get isFirstPage => query.offset == 0;

  /// Current page number (1-based).
  int get currentPage => (query.offset ~/ query.limit) + 1;

  /// Total number of pages.
  int get totalPages => (totalCount / query.limit).ceil();

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'templates': templates.map((t) => t.toJson()).toList(),
    'totalCount': totalCount,
    'query': query.toJson(),
  };

  /// Deserialize from JSON.
  factory TemplateSearchResult.fromJson(Map<String, dynamic> json) {
    final queryJson = json['query'] as Map<String, dynamic>? ?? {};
    return TemplateSearchResult(
      templates: (json['templates'] as List<dynamic>)
          .map((e) => TemplatePackage.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalCount: json['totalCount'] as int,
      query: TemplateSearchQuery.fromJson(queryJson),
    );
  }
}

// =============================================================================
// 📥 INSTALLED TEMPLATE — Locally cached template
// =============================================================================

/// A template that has been downloaded and installed locally.
///
/// Combines the marketplace metadata with local storage information.
class InstalledTemplate {
  /// The original marketplace metadata.
  final TemplatePackage package;

  /// Local file path to the cached `.fluera` template file.
  final String localPath;

  /// When this template was installed/downloaded.
  final DateTime installedAt;

  /// Size of the local file in bytes.
  final int localFileSizeBytes;

  /// Whether this template has a newer version available on the marketplace.
  final bool hasUpdate;

  const InstalledTemplate({
    required this.package,
    required this.localPath,
    required this.installedAt,
    this.localFileSizeBytes = 0,
    this.hasUpdate = false,
  });

  /// Template ID shorthand.
  String get id => package.id;

  /// Template title shorthand.
  String get title => package.title;

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'package': package.toJson(),
    'localPath': localPath,
    'installedAt': installedAt.millisecondsSinceEpoch,
    'localFileSizeBytes': localFileSizeBytes,
    'hasUpdate': hasUpdate,
  };

  /// Deserialize from JSON.
  factory InstalledTemplate.fromJson(Map<String, dynamic> json) {
    return InstalledTemplate(
      package: TemplatePackage.fromJson(
        json['package'] as Map<String, dynamic>,
      ),
      localPath: json['localPath'] as String,
      installedAt: DateTime.fromMillisecondsSinceEpoch(
        json['installedAt'] as int,
      ),
      localFileSizeBytes: json['localFileSizeBytes'] as int? ?? 0,
      hasUpdate: json['hasUpdate'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'InstalledTemplate(id: $id, title: $title, path: $localPath)';
}
