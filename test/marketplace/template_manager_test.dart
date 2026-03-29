import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/marketplace/template_models.dart';
import 'package:fluera_engine/src/marketplace/fluera_marketplace_adapter.dart';
import 'package:fluera_engine/src/marketplace/template_manager.dart';
import 'package:fluera_engine/src/storage/fluera_storage_adapter.dart';
import 'package:fluera_engine/src/storage/canvas_creation_options.dart';

// =============================================================================
// 🧪 TEMPLATE MANAGER TESTS
//
// Uses a mock marketplace adapter and a fake storage adapter to test the
// full template lifecycle without any real backend I/O.
// =============================================================================

// ─── Mock Marketplace Adapter ───────────────────────────────────────────────

class MockMarketplaceAdapter implements FlueraMarketplaceAdapter {
  final Map<String, TemplatePackage> _templates = {};
  final Map<String, Uint8List> _templateFiles = {};
  final Map<String, int> _ratings = {};

  String? lastPublishedId;
  int publishCallCount = 0;
  int downloadCallCount = 0;

  void addMockTemplate(TemplatePackage pkg, Uint8List fileBytes) {
    _templates[pkg.id] = pkg;
    _templateFiles[pkg.id] = fileBytes;
  }

  @override
  Future<TemplateSearchResult> browseTemplates(
    TemplateSearchQuery query,
  ) async {
    var results = _templates.values.toList();

    if (query.category != null) {
      results = results.where((t) => t.category == query.category).toList();
    }
    if (query.searchTerm != null) {
      final term = query.searchTerm!.toLowerCase();
      results =
          results.where((t) => t.title.toLowerCase().contains(term)).toList();
    }
    if (query.freeOnly) {
      results = results.where((t) => t.isFree).toList();
    }

    final total = results.length;
    final paged = results.skip(query.offset).take(query.limit).toList();

    return TemplateSearchResult(
      templates: paged,
      totalCount: total,
      query: query,
    );
  }

  @override
  Future<TemplatePackage?> getTemplateDetails(String templateId) async {
    return _templates[templateId];
  }

  @override
  Future<List<TemplatePackage>> getFeatured() async {
    return _templates.values.where((t) => t.isFeatured).toList();
  }

  @override
  Future<List<TemplatePackage>> getByAuthor(
    String authorId, {
    int limit = 10,
  }) async {
    return _templates.values
        .where((t) => t.authorId == authorId)
        .take(limit)
        .toList();
  }

  @override
  Future<Uint8List> downloadTemplateData(String templateId) async {
    downloadCallCount++;
    final data = _templateFiles[templateId];
    if (data == null) throw Exception('Template $templateId not found');
    return data;
  }

  @override
  Future<Uint8List?> downloadThumbnail(String templateId) async => null;

  @override
  Future<String> publishTemplate(
    TemplatePackage metadata,
    Uint8List flueraFileBytes, {
    Uint8List? thumbnailPng,
  }) async {
    publishCallCount++;
    final id = 'tmpl_published_$publishCallCount';
    _templates[id] = metadata.copyWith(id: id);
    _templateFiles[id] = flueraFileBytes;
    lastPublishedId = id;
    return id;
  }

  @override
  Future<void> updateTemplate(
    String templateId,
    TemplatePackage metadata,
    Uint8List flueraFileBytes,
  ) async {
    _templates[templateId] = metadata;
    _templateFiles[templateId] = flueraFileBytes;
  }

  @override
  Future<void> unpublishTemplate(String templateId) async {
    _templates.remove(templateId);
    _templateFiles.remove(templateId);
  }

  @override
  Future<void> rateTemplate(
    String templateId,
    int rating, {
    String? review,
  }) async {
    _ratings[templateId] = rating;
  }

  @override
  Future<int?> getUserRating(String templateId) async => _ratings[templateId];

  @override
  Future<void> reportTemplate(String templateId, String reason) async {}
}

// ─── Fake Storage Adapter ───────────────────────────────────────────────────

class FakeStorageAdapter extends FlueraStorageAdapter {
  final Map<String, Map<String, dynamic>> _canvases = {};
  int createCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<String> createCanvas(CanvasCreationOptions options) async {
    createCount++;
    final id = options.resolveCanvasId();
    _canvases[id] = {'canvasId': id};
    return id;
  }

  @override
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data) async {
    _canvases[canvasId] = data;
  }

  @override
  Future<Map<String, dynamic>?> loadCanvas(String canvasId) async {
    return _canvases[canvasId];
  }

  @override
  Future<void> deleteCanvas(String canvasId) async {
    _canvases.remove(canvasId);
  }

  @override
  Future<List<CanvasMetadata>> listCanvases({String? folderId}) async => [];

  @override
  Future<bool> canvasExists(String canvasId) async {
    return _canvases.containsKey(canvasId);
  }

  @override
  Future<void> close() async {}

  @override
  Future<String> createFolder(
    String name, {
    String? parentFolderId,
    Color color = const Color(0xFF6750A4),
  }) async => 'folder_1';

  @override
  Future<void> renameFolder(String folderId, String name) async {}

  @override
  Future<void> deleteFolder(String folderId) async {}

  @override
  Future<List<FolderMetadata>> listFolders({String? parentFolderId}) async =>
      [];

  @override
  Future<void> moveCanvasToFolder(String canvasId, String? folderId) async {}

  @override
  Future<void> moveFolderToFolder(
    String folderId,
    String? parentFolderId,
  ) async {}
}

// =============================================================================
// TESTS
// =============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMarketplaceAdapter mockMarketplace;
  late DateTime now;

  setUp(() {
    mockMarketplace = MockMarketplaceAdapter();
    now = DateTime.now();
  });

  // ===========================================================================
  // MockMarketplaceAdapter
  // ===========================================================================

  group('MockMarketplaceAdapter', () {
    test('browseTemplates returns all with default query', () async {
      mockMarketplace.addMockTemplate(
        _pkg('t1', 'Template 1', category: TemplateCategory.study),
        Uint8List.fromList([1, 2, 3]),
      );
      mockMarketplace.addMockTemplate(
        _pkg('t2', 'Template 2', category: TemplateCategory.planner),
        Uint8List.fromList([4, 5, 6]),
      );

      final result = await mockMarketplace.browseTemplates(
        const TemplateSearchQuery(),
      );
      expect(result.templates.length, 2);
      expect(result.totalCount, 2);
    });

    test('browseTemplates filters by category', () async {
      mockMarketplace.addMockTemplate(
        _pkg('t1', 'Study', category: TemplateCategory.study),
        Uint8List.fromList([1]),
      );
      mockMarketplace.addMockTemplate(
        _pkg('t2', 'Planner', category: TemplateCategory.planner),
        Uint8List.fromList([2]),
      );

      final result = await mockMarketplace.browseTemplates(
        const TemplateSearchQuery(category: TemplateCategory.study),
      );
      expect(result.templates.length, 1);
      expect(result.templates.first.id, 't1');
    });

    test('browseTemplates filters by searchTerm', () async {
      mockMarketplace.addMockTemplate(
        _pkg('t1', 'Cornell Notes'),
        Uint8List.fromList([1]),
      );
      mockMarketplace.addMockTemplate(
        _pkg('t2', 'Weekly Planner'),
        Uint8List.fromList([2]),
      );

      final result = await mockMarketplace.browseTemplates(
        const TemplateSearchQuery(searchTerm: 'cornell'),
      );
      expect(result.templates.length, 1);
      expect(result.templates.first.title, 'Cornell Notes');
    });

    test('getTemplateDetails returns existing template', () async {
      mockMarketplace.addMockTemplate(
        _pkg('existing', 'Exists'),
        Uint8List.fromList([1]),
      );

      final details = await mockMarketplace.getTemplateDetails('existing');
      expect(details, isNotNull);
      expect(details!.id, 'existing');
    });

    test('getTemplateDetails returns null for unknown', () async {
      final details = await mockMarketplace.getTemplateDetails('nonexistent');
      expect(details, isNull);
    });

    test('downloadTemplateData returns bytes', () async {
      final bytes = Uint8List.fromList([10, 20, 30, 40]);
      mockMarketplace.addMockTemplate(_pkg('dl', 'DL'), bytes);

      final downloaded = await mockMarketplace.downloadTemplateData('dl');
      expect(downloaded, bytes);
      expect(mockMarketplace.downloadCallCount, 1);
    });

    test('downloadTemplateData throws for unknown', () async {
      expect(
        () => mockMarketplace.downloadTemplateData('unknown'),
        throwsA(isA<Exception>()),
      );
    });

    test('publishTemplate assigns unique ID', () async {
      final id = await mockMarketplace.publishTemplate(
        _pkg('', 'New Template'),
        Uint8List.fromList([1, 2, 3]),
      );

      expect(id, isNotEmpty);
      expect(mockMarketplace.publishCallCount, 1);
    });

    test('rateTemplate stores rating', () async {
      await mockMarketplace.rateTemplate('t1', 5);
      final rating = await mockMarketplace.getUserRating('t1');
      expect(rating, 5);
    });

    test('getFeatured returns only featured', () async {
      mockMarketplace.addMockTemplate(
        _pkg('feat', 'Featured', isFeatured: true),
        Uint8List.fromList([1]),
      );
      mockMarketplace.addMockTemplate(
        _pkg('normal', 'Normal'),
        Uint8List.fromList([2]),
      );

      final featured = await mockMarketplace.getFeatured();
      expect(featured.length, 1);
      expect(featured.first.id, 'feat');
    });

    test('unpublishTemplate removes template', () async {
      mockMarketplace.addMockTemplate(
        _pkg('rm', 'Remove'),
        Uint8List.fromList([1]),
      );

      await mockMarketplace.unpublishTemplate('rm');
      expect(await mockMarketplace.getTemplateDetails('rm'), isNull);
    });
  });

  // ===========================================================================
  // TemplateManager — unit (no filesystem)
  // ===========================================================================

  group('TemplateManager unit', () {
    test('throws StateError before initialization', () {
      final m = TemplateManager(
        marketplace: mockMarketplace,
        storage: FakeStorageAdapter(),
        cacheDirectory: '/tmp/fluera_t_${now.millisecondsSinceEpoch}_1',
      );
      expect(() => m.listInstalled(), throwsA(isA<StateError>()));
      m.dispose();
    });

    test('isInitialized is false before initialize()', () {
      final m = TemplateManager(
        marketplace: mockMarketplace,
        storage: FakeStorageAdapter(),
        cacheDirectory: '/tmp/fluera_t_${now.millisecondsSinceEpoch}_2',
      );
      expect(m.isInitialized, isFalse);
      m.dispose();
    });

    test('marketplace getter returns adapter', () {
      final m = TemplateManager(
        marketplace: mockMarketplace,
        storage: FakeStorageAdapter(),
        cacheDirectory: '/tmp/fluera_t_${now.millisecondsSinceEpoch}_3',
      );
      expect(m.marketplace, same(mockMarketplace));
      m.dispose();
    });

    test('TemplateNotFoundException has descriptive message', () {
      const ex = TemplateNotFoundException('tmpl_xyz');
      expect(ex.toString(), contains('tmpl_xyz'));
      expect(ex.toString(), contains('not found'));
    });

    test('TemplateNotInstalledException has descriptive message', () {
      const ex = TemplateNotInstalledException('tmpl_abc');
      expect(ex.toString(), contains('tmpl_abc'));
      expect(ex.toString(), contains('not installed'));
    });
  });

  // ===========================================================================
  // TemplateManager — integration (uses real filesystem for cache)
  // ===========================================================================

  group('TemplateManager integration', () {
    late TemplateManager manager;
    late String cacheDir;

    setUp(() async {
      cacheDir = '/tmp/fluera_tmpl_${now.millisecondsSinceEpoch}';
      manager = TemplateManager(
        marketplace: mockMarketplace,
        storage: FakeStorageAdapter(),
        cacheDirectory: cacheDir,
      );
      await manager.initialize();
    });

    tearDown(() async {
      manager.dispose();
      final dir = Directory(cacheDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('initialize creates cache directory', () async {
      expect(manager.isInitialized, isTrue);
      expect(await Directory(cacheDir).exists(), isTrue);
    });

    test('initialize is idempotent', () async {
      await manager.initialize();
      expect(manager.isInitialized, isTrue);
    });

    test('listInstalled empty initially', () {
      expect(manager.listInstalled(), isEmpty);
    });

    test('isInstalled false for unknown', () {
      expect(manager.isInstalled('unknown'), isFalse);
    });

    test('cacheSizeBytes is 0 when empty', () {
      expect(manager.cacheSizeBytes, 0);
    });

    test('installTemplate downloads and caches', () async {
      final testBytes = Uint8List.fromList(List.generate(100, (i) => i));
      mockMarketplace.addMockTemplate(
        _pkg('tmpl_inst', 'Install Test'),
        testBytes,
      );

      final installed = await manager.installTemplate('tmpl_inst');

      expect(installed.id, 'tmpl_inst');
      expect(installed.title, 'Install Test');
      expect(installed.localFileSizeBytes, 100);
      expect(manager.isInstalled('tmpl_inst'), isTrue);
      expect(manager.listInstalled().length, 1);
      expect(manager.cacheSizeBytes, 100);
      // Verify file exists on disk
      expect(await File(installed.localPath).exists(), isTrue);
    });

    test('installTemplate is no-op if already installed', () async {
      mockMarketplace.addMockTemplate(
        _pkg('tmpl_dup', 'Dup'),
        Uint8List.fromList([1, 2, 3]),
      );

      await manager.installTemplate('tmpl_dup');
      final dlBefore = mockMarketplace.downloadCallCount;
      await manager.installTemplate('tmpl_dup');
      expect(mockMarketplace.downloadCallCount, dlBefore);
    });

    test('installTemplate throws for unknown template', () {
      expect(
        () => manager.installTemplate('nonexistent'),
        throwsA(isA<TemplateNotFoundException>()),
      );
    });

    test('installTemplate reports progress', () async {
      mockMarketplace.addMockTemplate(
        _pkg('tmpl_prog', 'Progress'),
        Uint8List.fromList([1]),
      );

      final progress = <double>[];
      await manager.installTemplate(
        'tmpl_prog',
        onProgress: (p) => progress.add(p),
      );

      expect(progress, isNotEmpty);
      expect(progress.first, 0.0);
      expect(progress.last, 1.0);
    });

    test('deleteInstalledTemplate removes from index and disk', () async {
      mockMarketplace.addMockTemplate(
        _pkg('tmpl_del', 'Delete'),
        Uint8List.fromList([1, 2, 3]),
      );

      final installed = await manager.installTemplate('tmpl_del');
      expect(manager.isInstalled('tmpl_del'), isTrue);

      await manager.deleteInstalledTemplate('tmpl_del');
      expect(manager.isInstalled('tmpl_del'), isFalse);
      expect(await File(installed.localPath).exists(), isFalse);
    });

    test('deleteInstalledTemplate is no-op for unknown', () async {
      await manager.deleteInstalledTemplate('nonexistent');
    });

    test('clearCache removes everything', () async {
      for (var i = 0; i < 3; i++) {
        mockMarketplace.addMockTemplate(
          _pkg('tmpl_c_$i', 'Clear $i'),
          Uint8List.fromList([i]),
        );
        await manager.installTemplate('tmpl_c_$i');
      }

      expect(manager.listInstalled().length, 3);
      await manager.clearCache();
      expect(manager.listInstalled(), isEmpty);
      expect(manager.cacheSizeBytes, 0);
    });

    test('browse delegates to marketplace', () async {
      mockMarketplace.addMockTemplate(
        _pkg('b1', 'Browse', category: TemplateCategory.study),
        Uint8List.fromList([1]),
      );

      final result = await manager.browse(
        const TemplateSearchQuery(category: TemplateCategory.study),
      );
      expect(result.templates.length, 1);
    });

    test('getFeatured delegates to marketplace', () async {
      mockMarketplace.addMockTemplate(
        _pkg('f1', 'Featured', isFeatured: true),
        Uint8List.fromList([1]),
      );

      final featured = await manager.getFeatured();
      expect(featured.length, 1);
    });

    test('rateTemplate delegates to marketplace', () async {
      await manager.rateTemplate('t1', 5);
      expect(await mockMarketplace.getUserRating('t1'), 5);
    });
  });
}

// ─── Helper ─────────────────────────────────────────────────────────────────

TemplatePackage _pkg(
  String id,
  String title, {
  TemplateCategory category = TemplateCategory.custom,
  bool isFeatured = false,
}) {
  final now = DateTime.now();
  return TemplatePackage(
    id: id,
    title: title,
    authorId: 'test_author',
    authorName: 'Test Author',
    category: category,
    isFeatured: isFeatured,
    createdAt: now,
    updatedAt: now,
  );
}
