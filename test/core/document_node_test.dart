import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/nodes/document_node.dart';

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // PageNode
  // ───────────────────────────────────────────────────────────────────────────

  group('PageNode', () {
    test('creates with defaults', () {
      final page = PageNode(name: 'Test Page');
      expect(page.name, 'Test Page');
      expect(page.id, isNotEmpty);
      expect(page.isVisible, isTrue);
      expect(page.nodeCount, 0);
    });

    test('JSON roundtrip preserves fields', () {
      final page = PageNode(
        id: 'page_1',
        name: 'Components',
        canvasWidth: 1920,
        canvasHeight: 1080,
      );
      page.metadata['key'] = 'value';

      final json = page.toJson();
      final restored = PageNode.fromJson(json);

      expect(restored.id, 'page_1');
      expect(restored.name, 'Components');
      expect(restored.canvasWidth, 1920);
      expect(restored.canvasHeight, 1080);
      expect(restored.metadata['key'], 'value');
    });

    test('duplicate creates independent copy', () {
      final original = PageNode(
        id: 'page_1',
        name: 'Original',
        canvasWidth: 800,
      );

      final copy = original.duplicate(newName: 'Copy');
      expect(copy.name, 'Copy');
      expect(copy.id, isNot(original.id));
      expect(copy.canvasWidth, 800);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // DocumentNode
  // ───────────────────────────────────────────────────────────────────────────

  group('DocumentNode', () {
    test('creates with defaults', () {
      final doc = DocumentNode(name: 'My Design');
      expect(doc.name, 'My Design');
      expect(doc.pageCount, 0);
      expect(doc.activePage, isNull);
    });

    test('addPage and access by index', () {
      final doc = DocumentNode();
      doc.addPage(PageNode(id: 'p1', name: 'Home'));
      doc.addPage(PageNode(id: 'p2', name: 'Icons'));

      expect(doc.pageCount, 2);
      expect(doc.pages[0].name, 'Home');
      expect(doc.pages[1].name, 'Icons');
    });

    test('pageById and pageByName', () {
      final doc = DocumentNode();
      doc.addPage(PageNode(id: 'abc', name: 'Home'));

      expect(doc.pageById('abc')!.name, 'Home');
      expect(doc.pageByName('Home')!.id, 'abc');
      expect(doc.pageById('nonexistent'), isNull);
      expect(doc.pageByName('Nope'), isNull);
    });

    test('insertPage at specific index', () {
      final doc = DocumentNode();
      doc.addPage(PageNode(id: 'a', name: 'A'));
      doc.addPage(PageNode(id: 'c', name: 'C'));
      doc.insertPage(1, PageNode(id: 'b', name: 'B'));

      expect(doc.pages.map((p) => p.name).toList(), ['A', 'B', 'C']);
    });

    test('removePage removes and adjusts activePageIndex', () {
      final doc = DocumentNode();
      doc.addPage(PageNode(id: 'p1', name: 'A'));
      doc.addPage(PageNode(id: 'p2', name: 'B'));
      doc.activePageIndex = 1;

      final removed = doc.removePage('p2');
      expect(removed!.name, 'B');
      expect(doc.pageCount, 1);
      expect(doc.activePageIndex, 0);
    });

    test('reorderPages', () {
      final doc = DocumentNode();
      doc.addPage(PageNode(id: '1', name: 'A'));
      doc.addPage(PageNode(id: '2', name: 'B'));
      doc.addPage(PageNode(id: '3', name: 'C'));

      doc.reorderPages(0, 3); // Move A to end
      expect(doc.pages.map((p) => p.name).toList(), ['B', 'C', 'A']);
    });

    test('duplicatePage creates copy after original', () {
      final doc = DocumentNode();
      doc.addPage(PageNode(id: 'p1', name: 'Original'));

      final copy = doc.duplicatePage('p1', newName: 'Copy');
      expect(copy, isNotNull);
      expect(doc.pageCount, 2);
      expect(doc.pages[0].name, 'Original');
      expect(doc.pages[1].name, 'Copy');
    });

    test('active page tracking', () {
      final doc = DocumentNode();
      doc.addPage(PageNode(id: 'p1', name: 'A'));
      doc.addPage(PageNode(id: 'p2', name: 'B'));

      expect(doc.activePageIndex, 0);
      expect(doc.activePage!.name, 'A');

      doc.activePageIndex = 1;
      expect(doc.activePage!.name, 'B');

      // Invalid index is ignored
      doc.activePageIndex = 99;
      expect(doc.activePageIndex, 1);
    });

    test('JSON roundtrip preserves full document', () {
      final doc = DocumentNode(id: 'doc_1', name: 'Test Doc', schemaVersion: 2);
      doc.addPage(PageNode(id: 'p1', name: 'Page 1'));
      doc.addPage(PageNode(id: 'p2', name: 'Page 2'));
      doc.activePageIndex = 1;

      final json = doc.toJson();
      final restored = DocumentNode.fromJson(json);

      expect(restored.id, 'doc_1');
      expect(restored.name, 'Test Doc');
      expect(restored.schemaVersion, 2);
      expect(restored.pageCount, 2);
      expect(restored.activePageIndex, 1);
      expect(restored.pages[0].name, 'Page 1');
      expect(restored.pages[1].name, 'Page 2');
    });

    test('totalNodeCount aggregates across pages', () {
      final doc = DocumentNode();
      doc.addPage(PageNode(name: 'A'));
      doc.addPage(PageNode(name: 'B'));

      // Empty pages have 0 nodes
      expect(doc.totalNodeCount, 0);
    });

    test('stats returns page breakdown', () {
      final doc = DocumentNode();
      doc.addPage(PageNode(name: 'A'));
      doc.addPage(PageNode(name: 'B'));

      final stats = doc.stats();
      expect(stats['pageCount'], 2);
      expect((stats['pages'] as List).length, 2);
    });

    test('indexOfPage returns correct index', () {
      final doc = DocumentNode();
      doc.addPage(PageNode(id: 'first', name: 'A'));
      doc.addPage(PageNode(id: 'second', name: 'B'));

      expect(doc.indexOfPage('first'), 0);
      expect(doc.indexOfPage('second'), 1);
      expect(doc.indexOfPage('nonexistent'), -1);
    });
  });
}
