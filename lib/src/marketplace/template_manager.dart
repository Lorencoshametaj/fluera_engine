import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import '../core/engine_logger.dart';
import '../core/models/canvas_layer.dart';
import '../export/fluera_file_export_service.dart';
import '../storage/fluera_storage_adapter.dart';
import '../storage/canvas_creation_options.dart';
import 'fluera_marketplace_adapter.dart';
import 'template_models.dart';

// =============================================================================
// 📦 TEMPLATE MANAGER — SDK-side template lifecycle orchestrator
//
// Manages the full template lifecycle:
// - Install: download from marketplace → cache locally
// - Apply: create new canvas from installed template
// - Publish: export canvas as template → upload to marketplace
// - Cache: manage installed templates with cleanup
//
// This is the concrete service that the host app interacts with.
// It requires both a FlueraMarketplaceAdapter (for marketplace I/O)
// and a FlueraStorageAdapter (for canvas creation).
// =============================================================================

/// 📦 Template lifecycle manager.
///
/// Orchestrates template installation, application, and publishing.
/// Requires a marketplace adapter (for cloud operations) and a storage
/// adapter (for local canvas creation).
///
/// ```dart
/// final manager = TemplateManager(
///   marketplace: mySupabaseMarketplace,
///   storage: sqliteAdapter,
///   cacheDirectory: '/path/to/app/cache/templates',
/// );
///
/// // Browse
/// final results = await manager.browse(TemplateSearchQuery(
///   category: TemplateCategory.study,
/// ));
///
/// // Install + Apply
/// await manager.installTemplate(results.templates.first.id);
/// final canvasId = await manager.applyTemplate(
///   results.templates.first.id,
///   title: 'My Cornell Notes',
/// );
/// ```
class TemplateManager {
  final FlueraMarketplaceAdapter _marketplace;
  final FlueraStorageAdapter _storage;

  /// Local directory for caching downloaded template files.
  final String cacheDirectory;

  /// In-memory index of installed templates (loaded from disk on init).
  final Map<String, InstalledTemplate> _installed = {};

  /// Whether the manager has been initialized.
  bool _isInitialized = false;

  TemplateManager({
    required FlueraMarketplaceAdapter marketplace,
    required FlueraStorageAdapter storage,
    required this.cacheDirectory,
  })  : _marketplace = marketplace,
        _storage = storage;

  /// Whether the manager has been initialized.
  bool get isInitialized => _isInitialized;

  /// The underlying marketplace adapter.
  FlueraMarketplaceAdapter get marketplace => _marketplace;

  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================

  /// Initialize the template manager.
  ///
  /// Creates the cache directory if needed, loads the installed template
  /// index from disk. Must be called before any other method.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Ensure cache directory exists
    final dir = Directory(cacheDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Load installed templates index
    await _loadIndex();

    _isInitialized = true;
    EngineLogger.info(
      '📦 TemplateManager initialized — ${_installed.length} templates cached',
    );
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'TemplateManager not initialized. Call initialize() first.',
      );
    }
  }

  // ===========================================================================
  // BROWSING (delegates to marketplace adapter)
  // ===========================================================================

  /// Browse the marketplace with search/filter/pagination.
  Future<TemplateSearchResult> browse(TemplateSearchQuery query) {
    return _marketplace.browseTemplates(query);
  }

  /// Get featured templates.
  Future<List<TemplatePackage>> getFeatured() => _marketplace.getFeatured();

  /// Get full details for a template.
  Future<TemplatePackage?> getDetails(String templateId) {
    return _marketplace.getTemplateDetails(templateId);
  }

  // ===========================================================================
  // INSTALLATION — Download & cache locally
  // ===========================================================================

  /// Download and install a template from the marketplace.
  ///
  /// Downloads the `.fluera` file and caches it locally. The template
  /// can then be applied multiple times without re-downloading.
  ///
  /// Returns the [InstalledTemplate] with local path information.
  /// No-op if the template is already installed (returns existing).
  ///
  /// ```dart
  /// final installed = await manager.installTemplate('tmpl_cornell_v2');
  /// print('Installed: ${installed.localPath}');
  /// ```
  Future<InstalledTemplate> installTemplate(
    String templateId, {
    void Function(double progress)? onProgress,
  }) async {
    _ensureInitialized();

    // Already installed?
    if (_installed.containsKey(templateId)) {
      EngineLogger.info('📦 Template $templateId already installed');
      return _installed[templateId]!;
    }

    onProgress?.call(0.0);

    // 1. Get metadata
    final metadata = await _marketplace.getTemplateDetails(templateId);
    if (metadata == null) {
      throw TemplateNotFoundException(templateId);
    }

    onProgress?.call(0.1);

    // 2. Download .fluera file
    final fileBytes = await _marketplace.downloadTemplateData(templateId);

    onProgress?.call(0.8);

    // 3. Save to local cache
    final localPath = _templateFilePath(templateId);
    final file = File(localPath);
    await file.writeAsBytes(fileBytes);

    onProgress?.call(0.9);

    // 4. Create InstalledTemplate entry
    final installed = InstalledTemplate(
      package: metadata,
      localPath: localPath,
      installedAt: DateTime.now(),
      localFileSizeBytes: fileBytes.length,
    );

    _installed[templateId] = installed;
    await _saveIndex();

    onProgress?.call(1.0);

    EngineLogger.info(
      '📦 Template installed: ${metadata.title} '
      '(${_formatBytes(fileBytes.length)})',
    );

    return installed;
  }

  /// Check if a template is installed locally.
  bool isInstalled(String templateId) {
    return _installed.containsKey(templateId);
  }

  /// List all installed templates.
  List<InstalledTemplate> listInstalled() {
    _ensureInitialized();
    return List.unmodifiable(_installed.values.toList());
  }

  /// Delete an installed template from local cache.
  ///
  /// Removes the cached `.fluera` file and the index entry.
  /// Does NOT affect canvases previously created from this template.
  Future<void> deleteInstalledTemplate(String templateId) async {
    _ensureInitialized();

    final installed = _installed.remove(templateId);
    if (installed == null) return;

    // Delete cached file
    final file = File(installed.localPath);
    if (await file.exists()) {
      await file.delete();
    }

    await _saveIndex();

    EngineLogger.info('📦 Template uninstalled: ${installed.title}');
  }

  /// Delete all installed templates (clear cache).
  Future<void> clearCache() async {
    _ensureInitialized();

    for (final installed in _installed.values) {
      final file = File(installed.localPath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    _installed.clear();
    await _saveIndex();

    EngineLogger.info('📦 Template cache cleared');
  }

  /// Total size of cached template files in bytes.
  int get cacheSizeBytes {
    return _installed.values.fold(0, (sum, t) => sum + t.localFileSizeBytes);
  }

  // ===========================================================================
  // APPLICATION — Create canvas from installed template
  // ===========================================================================

  /// Create a new canvas from an installed template.
  ///
  /// Loads the template's `.fluera` file, extracts layers, and creates
  /// a new canvas via [FlueraStorageAdapter.createCanvas] with the
  /// template's paper type and background color.
  ///
  /// Returns the new canvas ID.
  ///
  /// ```dart
  /// final canvasId = await manager.applyTemplate(
  ///   'tmpl_cornell_v2',
  ///   title: 'Physics 101 — Lecture 5',
  ///   folderId: 'folder_physics',
  /// );
  /// // The canvas is now ready with pre-populated layers from the template
  /// ```
  Future<String> applyTemplate(
    String templateId, {
    String? title,
    String? folderId,
  }) async {
    _ensureInitialized();

    final installed = _installed[templateId];
    if (installed == null) {
      throw TemplateNotInstalledException(templateId);
    }

    // 1. Read the cached .fluera file
    final file = File(installed.localPath);
    if (!await file.exists()) {
      // File was deleted externally — remove from index
      _installed.remove(templateId);
      await _saveIndex();
      throw TemplateNotInstalledException(templateId);
    }

    final fileBytes = await file.readAsBytes();

    // 2. Parse the .fluera file
    final loaded = FlueraFileExportService.loadFlueraFile(fileBytes);

    // 3. Determine canvas properties from template
    final paperType = CanvasPaperType.fromStorageKey(
      installed.package.paperType,
    );
    final bgColor = Color(installed.package.backgroundColorValue);

    // 4. Create the canvas with template options
    final canvasId = await _storage.createCanvas(
      CanvasCreationOptions(
        title: title ?? 'From: ${installed.package.title}',
        paperType: paperType,
        backgroundColor: bgColor,
        folderId: folderId,
      ),
    );

    // 5. Save the template layers into the new canvas
    // Build the full canvas data with template layers
    final canvasData = <String, dynamic>{
      'canvasId': canvasId,
      'title': title ?? 'From: ${installed.package.title}',
      'paperType': paperType.storageKey,
      // ignore: deprecated_member_use
      'backgroundColorValue': bgColor.value,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'layers': loaded.layers.map((l) => l.toJson()).toList(),
      'templateId': templateId,
      'templateVersion': installed.package.version,
    };

    await _storage.saveCanvas(canvasId, canvasData);

    EngineLogger.info(
      '📦 Canvas created from template: $canvasId '
      '(${installed.package.title}, ${loaded.layers.length} layers)',
    );

    return canvasId;
  }

  // ===========================================================================
  // PUBLISHING — Export canvas as template & upload
  // ===========================================================================

  /// Create a template package from an existing canvas and publish it.
  ///
  /// 1. Loads the canvas data from storage
  /// 2. Builds a `.fluera` file with [FlueraFileExportService]
  /// 3. Uploads to the marketplace via the adapter
  /// 4. Returns the marketplace-assigned template ID
  ///
  /// ```dart
  /// final templateId = await manager.publishTemplate(
  ///   canvasId: 'canvas_12345',
  ///   metadata: TemplatePackage(
  ///     id: '', // assigned by marketplace
  ///     title: 'My Study Template',
  ///     authorId: currentUser.id,
  ///     authorName: currentUser.name,
  ///     category: TemplateCategory.study,
  ///     tags: ['study', 'cornell'],
  ///     createdAt: DateTime.now(),
  ///     updatedAt: DateTime.now(),
  ///   ),
  /// );
  /// ```
  Future<String> publishTemplate({
    required String canvasId,
    required TemplatePackage metadata,
    Uint8List? thumbnailPng,
  }) async {
    _ensureInitialized();

    // 1. Load the canvas data
    final canvasData = await _storage.loadCanvas(canvasId);
    if (canvasData == null) {
      throw StateError('Canvas $canvasId not found in storage');
    }

    // 2. Build the .fluera file
    // Extract layers from canvas data
    final layersJson = canvasData['layers'] as List<dynamic>?;
    if (layersJson == null || layersJson.isEmpty) {
      throw StateError('Canvas $canvasId has no layers to publish');
    }

    final layers = layersJson
        .map((l) => CanvasLayer.fromJson(l as Map<String, dynamic>))
        .toList();

    final flueraBytes = await FlueraFileExportService.buildFlueraFile(
      layers: layers,
      title: metadata.title,
      paperType: canvasData['paperType'] as String?,
      backgroundColor: canvasData['backgroundColorValue']?.toString(),
    );

    // 3. Update metadata with file size
    final enrichedMetadata = metadata.copyWith(
      fileSizeBytes: flueraBytes.length,
      pageCount: 1,
      paperType: canvasData['paperType'] as String? ?? 'blank',
      backgroundColorValue:
          canvasData['backgroundColorValue'] as int? ?? 0xFFFFFFFF,
    );

    // 4. Upload to marketplace
    final templateId = await _marketplace.publishTemplate(
      enrichedMetadata,
      flueraBytes,
      thumbnailPng: thumbnailPng,
    );

    EngineLogger.info(
      '📦 Template published: ${metadata.title} → $templateId '
      '(${_formatBytes(flueraBytes.length)})',
    );

    return templateId;
  }

  /// Rate a template on the marketplace.
  Future<void> rateTemplate(String templateId, int rating, {String? review}) {
    return _marketplace.rateTemplate(templateId, rating, review: review);
  }

  // ===========================================================================
  // INTERNAL — Index persistence
  // ===========================================================================

  /// Path to the index file that tracks installed templates.
  String get _indexPath => '$cacheDirectory/template_index.json';

  /// Load the installed templates index from disk.
  Future<void> _loadIndex() async {
    final indexFile = File(_indexPath);
    if (!await indexFile.exists()) return;

    try {
      final jsonStr = await indexFile.readAsString();
      final jsonList = jsonDecode(jsonStr) as List<dynamic>;
      for (final entry in jsonList) {
        final installed = InstalledTemplate.fromJson(
          entry as Map<String, dynamic>,
        );
        // Verify the cached file still exists
        if (await File(installed.localPath).exists()) {
          _installed[installed.id] = installed;
        }
      }
    } catch (e) {
      EngineLogger.warning('📦 Failed to load template index: $e');
      // Index is corrupted — start fresh
      _installed.clear();
    }
  }

  /// Save the installed templates index to disk.
  Future<void> _saveIndex() async {
    final indexFile = File(_indexPath);
    final jsonList = _installed.values.map((t) => t.toJson()).toList();
    await indexFile.writeAsString(jsonEncode(jsonList));
  }

  /// Get the local file path for a template's cached `.fluera` file.
  String _templateFilePath(String templateId) =>
      '$cacheDirectory/$templateId.fluera';

  /// Format bytes as human-readable string.
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Dispose resources.
  void dispose() {
    _installed.clear();
    _isInitialized = false;
  }
}

// =============================================================================
// EXCEPTIONS
// =============================================================================

/// Thrown when a template ID is not found on the marketplace.
class TemplateNotFoundException implements Exception {
  final String templateId;
  const TemplateNotFoundException(this.templateId);

  @override
  String toString() =>
      'TemplateNotFoundException: Template "$templateId" not found on marketplace';
}

/// Thrown when trying to apply a template that isn't installed locally.
class TemplateNotInstalledException implements Exception {
  final String templateId;
  const TemplateNotInstalledException(this.templateId);

  @override
  String toString() =>
      'TemplateNotInstalledException: Template "$templateId" is not installed. '
      'Call installTemplate() first.';
}
