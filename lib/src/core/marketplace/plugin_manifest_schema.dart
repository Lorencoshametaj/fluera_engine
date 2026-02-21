/// 🔌 PLUGIN MANIFEST SCHEMA — Marketplace manifest with validation.
///
/// Extended plugin metadata for marketplace listing: category, pricing,
/// screenshots, engine compatibility, changelog, and schema validation.
///
/// ```dart
/// final manifest = MarketplaceManifest(
///   id: 'com.example.my-plugin',
///   name: 'My Plugin',
///   version: '1.2.0',
///   author: 'Dev Team',
///   category: ManifestCategory.tools,
/// );
/// final errors = ManifestValidator.validate(manifest);
/// ```
library;

// =============================================================================
// MANIFEST CATEGORY
// =============================================================================

/// Plugin categories for marketplace organization.
enum ManifestCategory {
  tools,
  effects,
  importers,
  exporters,
  integrations,
  themes,
  accessibility,
  analytics,
  other,
}

/// Pricing tier.
enum PricingTier { free, freemium, paid, enterprise }

// =============================================================================
// MARKETPLACE MANIFEST
// =============================================================================

/// Extended plugin manifest for marketplace listing.
class MarketplaceManifest {
  /// Unique plugin identifier (reverse domain, e.g. "com.acme.blur-tool").
  final String id;

  /// Display name.
  final String name;

  /// Semantic version (e.g. "1.2.0").
  final String version;

  /// Author or organization.
  final String author;

  /// Short description (max 200 chars).
  final String description;

  /// Category.
  final ManifestCategory category;

  /// Pricing tier.
  final PricingTier pricing;

  /// Icon URL.
  final String? iconUrl;

  /// Screenshot URLs.
  final List<String> screenshots;

  /// Required engine version range (e.g. ">=2.0.0 <3.0.0").
  final String? engineVersionRange;

  /// Plugin dependencies (id → version constraint).
  final Map<String, String> dependencies;

  /// Changelog entries (version → description).
  final Map<String, String> changelog;

  /// Tags for search.
  final List<String> tags;

  /// Homepage URL.
  final String? homepageUrl;

  /// License identifier (e.g. "MIT", "Apache-2.0").
  final String? license;

  /// Minimum API level required.
  final int minApiLevel;

  const MarketplaceManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    this.description = '',
    this.category = ManifestCategory.other,
    this.pricing = PricingTier.free,
    this.iconUrl,
    this.screenshots = const [],
    this.engineVersionRange,
    this.dependencies = const {},
    this.changelog = const {},
    this.tags = const [],
    this.homepageUrl,
    this.license,
    this.minApiLevel = 1,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'author': author,
    'description': description,
    'category': category.name,
    'pricing': pricing.name,
    if (iconUrl != null) 'iconUrl': iconUrl,
    'screenshots': screenshots,
    if (engineVersionRange != null) 'engineVersionRange': engineVersionRange,
    'dependencies': dependencies,
    'changelog': changelog,
    'tags': tags,
    if (homepageUrl != null) 'homepageUrl': homepageUrl,
    if (license != null) 'license': license,
    'minApiLevel': minApiLevel,
  };

  factory MarketplaceManifest.fromJson(Map<String, dynamic> json) =>
      MarketplaceManifest(
        id: json['id'] as String,
        name: json['name'] as String,
        version: json['version'] as String,
        author: json['author'] as String,
        description: json['description'] as String? ?? '',
        category: ManifestCategory.values.firstWhere(
          (v) => v.name == json['category'],
          orElse: () => ManifestCategory.other,
        ),
        pricing: PricingTier.values.firstWhere(
          (v) => v.name == json['pricing'],
          orElse: () => PricingTier.free,
        ),
        iconUrl: json['iconUrl'] as String?,
        screenshots: (json['screenshots'] as List?)?.cast<String>() ?? [],
        engineVersionRange: json['engineVersionRange'] as String?,
        dependencies:
            (json['dependencies'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, v.toString()),
            ) ??
            {},
        changelog:
            (json['changelog'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, v.toString()),
            ) ??
            {},
        tags: (json['tags'] as List?)?.cast<String>() ?? [],
        homepageUrl: json['homepageUrl'] as String?,
        license: json['license'] as String?,
        minApiLevel: json['minApiLevel'] as int? ?? 1,
      );

  @override
  String toString() => 'MarketplaceManifest($id v$version)';
}

// =============================================================================
// VALIDATION ERROR
// =============================================================================

/// A manifest validation error.
class ManifestError {
  /// Field that failed validation.
  final String field;

  /// Error message.
  final String message;

  /// Severity.
  final ManifestErrorSeverity severity;

  const ManifestError(
    this.field,
    this.message, {
    this.severity = ManifestErrorSeverity.error,
  });

  @override
  String toString() => '${severity.name}: $field — $message';
}

/// Validation error severity.
enum ManifestErrorSeverity { error, warning }

// =============================================================================
// MANIFEST VALIDATOR
// =============================================================================

/// Validates a marketplace manifest.
class ManifestValidator {
  const ManifestValidator._();

  static final _semverRegex = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    r'(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?'
    r'(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$',
  );

  static final _idRegex = RegExp(r'^[a-z][a-z0-9._-]*[a-z0-9]$');

  /// Validate a manifest and return all errors.
  static List<ManifestError> validate(MarketplaceManifest manifest) {
    final errors = <ManifestError>[];

    // Required fields
    if (manifest.id.isEmpty) {
      errors.add(const ManifestError('id', 'Plugin ID is required'));
    } else if (!_idRegex.hasMatch(manifest.id)) {
      errors.add(
        const ManifestError(
          'id',
          'Plugin ID must be lowercase alphanumeric with dots/dashes (e.g. com.acme.plugin)',
        ),
      );
    }

    if (manifest.name.isEmpty) {
      errors.add(const ManifestError('name', 'Plugin name is required'));
    } else if (manifest.name.length > 50) {
      errors.add(const ManifestError('name', 'Name must be ≤50 characters'));
    }

    if (manifest.version.isEmpty) {
      errors.add(const ManifestError('version', 'Version is required'));
    } else if (!_semverRegex.hasMatch(manifest.version)) {
      errors.add(
        const ManifestError(
          'version',
          'Version must follow semantic versioning (e.g. 1.2.3)',
        ),
      );
    }

    if (manifest.author.isEmpty) {
      errors.add(const ManifestError('author', 'Author is required'));
    }

    // Optional field constraints
    if (manifest.description.length > 200) {
      errors.add(
        const ManifestError(
          'description',
          'Description must be ≤200 characters',
          severity: ManifestErrorSeverity.warning,
        ),
      );
    }

    if (manifest.tags.length > 10) {
      errors.add(
        const ManifestError(
          'tags',
          'Maximum 10 tags allowed',
          severity: ManifestErrorSeverity.warning,
        ),
      );
    }

    // Dependency versions
    for (final dep in manifest.dependencies.entries) {
      if (dep.value.isEmpty) {
        errors.add(
          ManifestError(
            'dependencies.${dep.key}',
            'Version constraint is required',
          ),
        );
      }
    }

    return errors;
  }

  /// Check if a manifest is valid (no errors).
  static bool isValid(MarketplaceManifest manifest) =>
      validate(
        manifest,
      ).where((e) => e.severity == ManifestErrorSeverity.error).isEmpty;
}
