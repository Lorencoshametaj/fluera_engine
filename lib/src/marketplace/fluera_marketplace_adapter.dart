import 'dart:typed_data';

import 'template_models.dart';

// =============================================================================
// 🏪 FLUERA MARKETPLACE ADAPTER — Abstract marketplace interface
//
// Backend-agnostic interface for browsing, downloading, and publishing
// templates. The host app implements this with its own backend
// (Firebase, Supabase, REST API, etc.). The SDK only depends on this
// interface, identical to how FlueraCloudStorageAdapter works.
// =============================================================================

/// 🏪 Abstract marketplace adapter for template browsing & distribution.
///
/// The SDK calls these methods to interact with the template marketplace.
/// The host app provides a concrete implementation for its backend.
///
/// **Contract:**
/// - All methods are async and may throw on network/auth errors.
/// - Template data is exchanged as `.fluera` binary files (Uint8List).
/// - Pagination follows offset/limit pattern via [TemplateSearchQuery].
///
/// **Example (Supabase):**
/// ```dart
/// class SupabaseMarketplaceAdapter implements FlueraMarketplaceAdapter {
///   final supabase = Supabase.instance.client;
///
///   @override
///   Future<TemplateSearchResult> browseTemplates(TemplateSearchQuery query) async {
///     var builder = supabase.from('templates').select();
///
///     if (query.category != null) {
///       builder = builder.eq('category', query.category!.name);
///     }
///     if (query.searchTerm != null) {
///       builder = builder.textSearch('title', query.searchTerm!);
///     }
///
///     final data = await builder
///         .order(query.sortOrder == TemplateSortOrder.newest
///             ? 'created_at' : 'download_count',
///             ascending: false)
///         .range(query.offset, query.offset + query.limit - 1);
///
///     return TemplateSearchResult(
///       templates: data.map((e) => TemplatePackage.fromJson(e)).toList(),
///       totalCount: data.length, // or separate count query
///       query: query,
///     );
///   }
///
///   @override
///   Future<Uint8List> downloadTemplateData(String templateId) async {
///     final bytes = await supabase.storage
///         .from('templates')
///         .download('$templateId.fluera');
///     return bytes;
///   }
///
///   @override
///   Future<String> publishTemplate(
///     TemplatePackage metadata,
///     Uint8List flueraFileBytes,
///   ) async {
///     final id = 'tmpl_${DateTime.now().millisecondsSinceEpoch}';
///     await supabase.storage
///         .from('templates')
///         .uploadBinary('$id.fluera', flueraFileBytes);
///     await supabase.from('templates').insert(metadata.copyWith(id: id).toJson());
///     return id;
///   }
/// }
/// ```
///
/// **Example (Firebase):**
/// ```dart
/// class FirebaseMarketplaceAdapter implements FlueraMarketplaceAdapter {
///   final _firestore = FirebaseFirestore.instance;
///   final _storage = FirebaseStorage.instance;
///
///   @override
///   Future<TemplateSearchResult> browseTemplates(TemplateSearchQuery query) async {
///     Query<Map<String, dynamic>> q = _firestore.collection('templates');
///
///     if (query.category != null) {
///       q = q.where('category', isEqualTo: query.category!.name);
///     }
///     if (query.freeOnly) {
///       q = q.where('isFree', isEqualTo: true);
///     }
///
///     final snap = await q.limit(query.limit).get();
///     return TemplateSearchResult(
///       templates: snap.docs.map((d) => TemplatePackage.fromJson(d.data())).toList(),
///       totalCount: snap.size,
///       query: query,
///     );
///   }
///   // ... other methods
/// }
/// ```
abstract class FlueraMarketplaceAdapter {
  // ─── Browsing & Discovery ──────────────────────────────────────────────

  /// Browse templates with search, filter, and pagination.
  ///
  /// Returns a paginated result. Use [TemplateSearchQuery.nextPage] to
  /// request subsequent pages.
  Future<TemplateSearchResult> browseTemplates(TemplateSearchQuery query);

  /// Get detailed metadata for a specific template.
  ///
  /// Returns `null` if the template doesn't exist or was removed.
  Future<TemplatePackage?> getTemplateDetails(String templateId);

  /// Get featured/promoted templates for the marketplace home screen.
  ///
  /// Returns a curated list, typically 5-15 templates.
  Future<List<TemplatePackage>> getFeatured();

  /// Get templates by the same author.
  ///
  /// Useful for "More by this author" sections.
  Future<List<TemplatePackage>> getByAuthor(String authorId, {int limit = 10});

  // ─── Download ──────────────────────────────────────────────────────────

  /// Download the template's `.fluera` file data.
  ///
  /// Returns the raw bytes of the template file. The caller is responsible
  /// for writing to local storage (handled by [TemplateManager]).
  ///
  /// May throw on network errors or if the template doesn't exist.
  Future<Uint8List> downloadTemplateData(String templateId);

  /// Download the template's thumbnail image.
  ///
  /// Returns PNG/WebP bytes, or `null` if no thumbnail is available.
  Future<Uint8List?> downloadThumbnail(String templateId);

  // ─── Publishing ────────────────────────────────────────────────────────

  /// Publish a new template to the marketplace.
  ///
  /// [metadata] contains the template's descriptive information.
  /// [flueraFileBytes] is the raw `.fluera` file (built by
  /// [FlueraFileExportService]).
  ///
  /// Returns the marketplace-assigned template ID.
  ///
  /// The adapter should:
  /// 1. Upload the `.fluera` file to cloud storage
  /// 2. Store the metadata in the database
  /// 3. Generate/store a thumbnail (or accept one from metadata)
  Future<String> publishTemplate(
    TemplatePackage metadata,
    Uint8List flueraFileBytes, {
    Uint8List? thumbnailPng,
  });

  /// Update an existing template (new version).
  ///
  /// Replaces the file and increments the version counter.
  /// Only the original author should be able to update.
  Future<void> updateTemplate(
    String templateId,
    TemplatePackage metadata,
    Uint8List flueraFileBytes,
  );

  /// Remove a template from the marketplace.
  ///
  /// Only the original author (or admin) should have permission.
  /// No-op if the template doesn't exist.
  Future<void> unpublishTemplate(String templateId);

  // ─── Ratings & Feedback ────────────────────────────────────────────────

  /// Submit a rating for a template (1-5).
  ///
  /// One rating per user per template (upsert behavior).
  Future<void> rateTemplate(String templateId, int rating, {String? review});

  /// Get the current user's rating for a template.
  ///
  /// Returns `null` if the user hasn't rated this template.
  Future<int?> getUserRating(String templateId);

  // ─── Reporting ─────────────────────────────────────────────────────────

  /// Report a template for policy violations.
  ///
  /// [reason] should describe the violation (spam, copyright, etc.).
  Future<void> reportTemplate(String templateId, String reason) async {}
}
