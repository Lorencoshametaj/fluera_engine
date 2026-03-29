import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/marketplace/template_models.dart';

void main() {
  // ===========================================================================
  // TemplateCategory
  // ===========================================================================

  group('TemplateCategory', () {
    test('fromName resolves known categories (case-insensitive)', () {
      expect(TemplateCategory.fromName('study'), TemplateCategory.study);
      expect(TemplateCategory.fromName('PLANNER'), TemplateCategory.planner);
      expect(TemplateCategory.fromName('Music'), TemplateCategory.music);
      expect(TemplateCategory.fromName('mindMap'), TemplateCategory.mindMap);
    });

    test('fromName returns custom for unknown names', () {
      expect(TemplateCategory.fromName('unknown'), TemplateCategory.custom);
      expect(TemplateCategory.fromName(''), TemplateCategory.custom);
    });

    test('all categories have non-empty label and icon', () {
      for (final cat in TemplateCategory.values) {
        expect(cat.label, isNotEmpty, reason: '${cat.name} has empty label');
        expect(cat.icon, isNotEmpty, reason: '${cat.name} has empty icon');
      }
    });

    test('enum has expected number of categories', () {
      expect(TemplateCategory.values.length, 11);
    });
  });

  // ===========================================================================
  // TemplatePackage
  // ===========================================================================

  group('TemplatePackage', () {
    late TemplatePackage template;
    late DateTime now;

    setUp(() {
      now = DateTime.now();
      template = TemplatePackage(
        id: 'tmpl_cornell_v2',
        title: 'Cornell Notes Pro',
        description: 'Professional Cornell note-taking template',
        authorId: 'user_123',
        authorName: 'StudyMaster',
        category: TemplateCategory.study,
        tags: ['cornell', 'notes', 'lecture'],
        thumbnailUrl: 'https://cdn.fluera.dev/tmpl/cornell.png',
        pageCount: 3,
        rating: 4.7,
        ratingCount: 256,
        downloadCount: 5800,
        paperType: 'cornell',
        backgroundColorValue: 0xFFFFFBF0,
        version: 2,
        fileSizeBytes: 48200,
        isFree: true,
        priceInCents: 0,
        isFeatured: true,
        createdAt: now,
        updatedAt: now,
        previewImageUrls: ['https://cdn.fluera.dev/preview1.png'],
      );
    });

    test('toJson/fromJson roundtrip preserves all fields', () {
      final json = template.toJson();
      final restored = TemplatePackage.fromJson(json);

      expect(restored.id, equals('tmpl_cornell_v2'));
      expect(restored.title, equals('Cornell Notes Pro'));
      expect(restored.description, contains('Cornell'));
      expect(restored.authorId, equals('user_123'));
      expect(restored.authorName, equals('StudyMaster'));
      expect(restored.category, TemplateCategory.study);
      expect(restored.tags, equals(['cornell', 'notes', 'lecture']));
      expect(restored.thumbnailUrl, isNotNull);
      expect(restored.pageCount, 3);
      expect(restored.rating, closeTo(4.7, 0.01));
      expect(restored.ratingCount, 256);
      expect(restored.downloadCount, 5800);
      expect(restored.paperType, 'cornell');
      expect(restored.backgroundColorValue, 0xFFFFFBF0);
      expect(restored.version, 2);
      expect(restored.fileSizeBytes, 48200);
      expect(restored.isFree, true);
      expect(restored.priceInCents, 0);
      expect(restored.isFeatured, true);
      expect(restored.previewImageUrls, hasLength(1));
      expect(
        restored.createdAt.millisecondsSinceEpoch,
        equals(now.millisecondsSinceEpoch),
      );
    });

    test('fromJson uses defaults for missing optional fields', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final minimal = TemplatePackage.fromJson({
        'id': 'tmpl_minimal',
        'title': 'Minimal',
        'authorId': 'user_1',
        'authorName': 'Author',
        'createdAt': nowMs,
        'updatedAt': nowMs,
      });

      expect(minimal.description, '');
      expect(minimal.category, TemplateCategory.custom);
      expect(minimal.tags, isEmpty);
      expect(minimal.thumbnailUrl, isNull);
      expect(minimal.pageCount, 1);
      expect(minimal.rating, 0.0);
      expect(minimal.ratingCount, 0);
      expect(minimal.downloadCount, 0);
      expect(minimal.paperType, 'blank');
      expect(minimal.backgroundColorValue, 0xFFFFFFFF);
      expect(minimal.version, 1);
      expect(minimal.fileSizeBytes, 0);
      expect(minimal.isFree, true);
      expect(minimal.priceInCents, 0);
      expect(minimal.isFeatured, false);
      expect(minimal.previewImageUrls, isEmpty);
    });

    test('copyWith creates modified copy', () {
      final updated = template.copyWith(
        title: 'Cornell Notes Pro v3',
        version: 3,
        rating: 4.9,
        downloadCount: 10000,
      );

      expect(updated.title, 'Cornell Notes Pro v3');
      expect(updated.version, 3);
      expect(updated.rating, closeTo(4.9, 0.01));
      expect(updated.downloadCount, 10000);
      // Unchanged fields
      expect(updated.id, template.id);
      expect(updated.authorId, template.authorId);
      expect(updated.category, template.category);
    });

    test('equality is based on id', () {
      final duplicate = TemplatePackage(
        id: 'tmpl_cornell_v2',
        title: 'Different Title',
        authorId: 'different_author',
        authorName: 'Other',
        createdAt: DateTime(2020),
        updatedAt: DateTime(2020),
      );

      expect(template, equals(duplicate));
      expect(template.hashCode, equals(duplicate.hashCode));
    });

    test('toString contains key info', () {
      final str = template.toString();
      expect(str, contains('tmpl_cornell_v2'));
      expect(str, contains('Cornell Notes Pro'));
      expect(str, contains('study'));
    });

    test('toJson omits null thumbnailUrl and empty previewImageUrls', () {
      final noThumb = TemplatePackage(
        id: 'test',
        title: 'Test',
        authorId: 'a',
        authorName: 'A',
        createdAt: now,
        updatedAt: now,
      );
      final json = noThumb.toJson();
      expect(json.containsKey('thumbnailUrl'), isFalse);
      expect(json.containsKey('previewImageUrls'), isFalse);
    });
  });

  // ===========================================================================
  // TemplateSearchQuery
  // ===========================================================================

  group('TemplateSearchQuery', () {
    test('toJson/fromJson roundtrip preserves all fields', () {
      final query = TemplateSearchQuery(
        searchTerm: 'cornell',
        category: TemplateCategory.study,
        tags: ['notes', 'lecture'],
        sortOrder: TemplateSortOrder.topRated,
        freeOnly: true,
        featuredOnly: false,
        authorId: 'user_1',
        paperType: 'cornell',
        limit: 15,
        offset: 30,
      );

      final json = query.toJson();
      final restored = TemplateSearchQuery.fromJson(json);

      expect(restored.searchTerm, 'cornell');
      expect(restored.category, TemplateCategory.study);
      expect(restored.tags, ['notes', 'lecture']);
      expect(restored.sortOrder, TemplateSortOrder.topRated);
      expect(restored.freeOnly, true);
      expect(restored.featuredOnly, false);
      expect(restored.authorId, 'user_1');
      expect(restored.paperType, 'cornell');
      expect(restored.limit, 15);
      expect(restored.offset, 30);
    });

    test('default query has sensible defaults', () {
      const query = TemplateSearchQuery();
      expect(query.searchTerm, isNull);
      expect(query.category, isNull);
      expect(query.tags, isEmpty);
      expect(query.sortOrder, TemplateSortOrder.popular);
      expect(query.freeOnly, false);
      expect(query.featuredOnly, false);
      expect(query.limit, 20);
      expect(query.offset, 0);
    });

    test('nextPage increments offset by limit', () {
      const query = TemplateSearchQuery(limit: 10, offset: 0);
      final page2 = query.nextPage();
      expect(page2.offset, 10);
      expect(page2.limit, 10);

      final page3 = page2.nextPage();
      expect(page3.offset, 20);
    });

    test('toJson omits null/false/empty optional fields', () {
      const query = TemplateSearchQuery();
      final json = query.toJson();

      expect(json.containsKey('searchTerm'), isFalse);
      expect(json.containsKey('category'), isFalse);
      expect(json.containsKey('tags'), isFalse);
      expect(json.containsKey('freeOnly'), isFalse);
      expect(json.containsKey('featuredOnly'), isFalse);
      expect(json.containsKey('authorId'), isFalse);
      expect(json.containsKey('paperType'), isFalse);
      // Always present
      expect(json['sortOrder'], 'popular');
      expect(json['limit'], 20);
      expect(json['offset'], 0);
    });
  });

  // ===========================================================================
  // TemplateSearchResult
  // ===========================================================================

  group('TemplateSearchResult', () {
    late DateTime now;

    setUp(() {
      now = DateTime.now();
    });

    TemplatePackage _makeTemplate(String id) => TemplatePackage(
      id: id,
      title: 'Template $id',
      authorId: 'author',
      authorName: 'Author',
      createdAt: now,
      updatedAt: now,
    );

    test('hasMore is true when more results exist', () {
      final result = TemplateSearchResult(
        templates: List.generate(10, (i) => _makeTemplate('t_$i')),
        totalCount: 50,
        query: const TemplateSearchQuery(limit: 10, offset: 0),
      );

      expect(result.hasMore, isTrue);
      expect(result.currentPage, 1);
      expect(result.totalPages, 5);
    });

    test('hasMore is false on last page', () {
      final result = TemplateSearchResult(
        templates: List.generate(5, (i) => _makeTemplate('t_$i')),
        totalCount: 15,
        query: const TemplateSearchQuery(limit: 10, offset: 10),
      );

      expect(result.hasMore, isFalse);
      expect(result.currentPage, 2);
    });

    test('toJson/fromJson roundtrip', () {
      final result = TemplateSearchResult(
        templates: [_makeTemplate('t_1'), _makeTemplate('t_2')],
        totalCount: 100,
        query: const TemplateSearchQuery(limit: 2, offset: 0),
      );

      final json = result.toJson();
      final restored = TemplateSearchResult.fromJson(json);

      expect(restored.templates.length, 2);
      expect(restored.totalCount, 100);
      expect(restored.templates.first.id, 't_1');
    });

    test('isFirstPage is true when offset is 0', () {
      final result = TemplateSearchResult(
        templates: [],
        totalCount: 0,
        query: const TemplateSearchQuery(offset: 0),
      );
      expect(result.isFirstPage, isTrue);
    });
  });

  // ===========================================================================
  // InstalledTemplate
  // ===========================================================================

  group('InstalledTemplate', () {
    test('toJson/fromJson roundtrip preserves all fields', () {
      final now = DateTime.now();
      final installed = InstalledTemplate(
        package: TemplatePackage(
          id: 'tmpl_1',
          title: 'My Template',
          authorId: 'user_1',
          authorName: 'Author',
          category: TemplateCategory.planner,
          createdAt: now,
          updatedAt: now,
        ),
        localPath: '/cache/templates/tmpl_1.fluera',
        installedAt: now,
        localFileSizeBytes: 32768,
        hasUpdate: true,
      );

      final json = installed.toJson();
      final restored = InstalledTemplate.fromJson(json);

      expect(restored.id, 'tmpl_1');
      expect(restored.title, 'My Template');
      expect(restored.localPath, '/cache/templates/tmpl_1.fluera');
      expect(restored.localFileSizeBytes, 32768);
      expect(restored.hasUpdate, true);
      expect(restored.package.category, TemplateCategory.planner);
      expect(
        restored.installedAt.millisecondsSinceEpoch,
        equals(now.millisecondsSinceEpoch),
      );
    });

    test('id and title are shortcuts to package fields', () {
      final now = DateTime.now();
      final installed = InstalledTemplate(
        package: TemplatePackage(
          id: 'tmpl_abc',
          title: 'ABC Template',
          authorId: 'u',
          authorName: 'U',
          createdAt: now,
          updatedAt: now,
        ),
        localPath: '/tmp/tmpl_abc.fluera',
        installedAt: now,
      );

      expect(installed.id, 'tmpl_abc');
      expect(installed.title, 'ABC Template');
    });

    test('toString contains key info', () {
      final now = DateTime.now();
      final installed = InstalledTemplate(
        package: TemplatePackage(
          id: 'x',
          title: 'X',
          authorId: 'a',
          authorName: 'A',
          createdAt: now,
          updatedAt: now,
        ),
        localPath: '/tmp/x.fluera',
        installedAt: now,
      );

      final str = installed.toString();
      expect(str, contains('x'));
      expect(str, contains('/tmp/x.fluera'));
    });
  });

  // ===========================================================================
  // TemplateSortOrder
  // ===========================================================================

  group('TemplateSortOrder', () {
    test('has 4 values', () {
      expect(TemplateSortOrder.values.length, 4);
    });

    test('names are correct', () {
      expect(TemplateSortOrder.popular.name, 'popular');
      expect(TemplateSortOrder.newest.name, 'newest');
      expect(TemplateSortOrder.topRated.name, 'topRated');
      expect(TemplateSortOrder.alphabetical.name, 'alphabetical');
    });
  });
}
