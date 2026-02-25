import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/models/pdf_page_model.dart';
import 'package:nebula_engine/src/core/models/pdf_document_model.dart';
import 'package:nebula_engine/src/core/models/pdf_text_rect.dart';
import 'package:nebula_engine/src/core/nodes/pdf_page_node.dart';
import 'package:nebula_engine/src/core/nodes/pdf_document_node.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node_factory.dart';

void main() {
  // ===========================================================================
  // PdfPageModel
  // ===========================================================================

  group('PdfPageModel', () {
    test('serialization roundtrip preserves all fields', () {
      final model = PdfPageModel(
        pageIndex: 3,
        originalSize: const Size(595, 842),
        isLocked: false,
        gridRow: 1,
        gridCol: 2,
        customOffset: const Offset(100, 200),
        rotation: 1.57,
        annotations: ['a-1', 'a-2'],
        lastModifiedAt: 1700000000,
      );

      final json = model.toJson();
      final restored = PdfPageModel.fromJson(json);

      expect(restored.pageIndex, 3);
      expect(restored.originalSize, const Size(595, 842));
      expect(restored.isLocked, false);
      expect(restored.gridRow, 1);
      expect(restored.gridCol, 2);
      expect(restored.customOffset, const Offset(100, 200));
      expect(restored.rotation, 1.57);
      expect(restored.annotations, ['a-1', 'a-2']);
      expect(restored.lastModifiedAt, 1700000000);
    });

    test('defaults are correct', () {
      const model = PdfPageModel(pageIndex: 0, originalSize: Size(595, 842));

      expect(model.isLocked, true);
      expect(model.gridRow, 0);
      expect(model.gridCol, 0);
      expect(model.customOffset, isNull);
      expect(model.rotation, 0.0);
      expect(model.annotations, isEmpty);
    });

    test('copyWith produces correct copy', () {
      const model = PdfPageModel(pageIndex: 0, originalSize: Size(595, 842));
      final modified = model.copyWith(
        isLocked: false,
        customOffset: const Offset(50, 60),
      );

      expect(modified.isLocked, false);
      expect(modified.customOffset, const Offset(50, 60));
      expect(modified.pageIndex, 0); // unchanged
    });

    test('copyWith clearCustomOffset works', () {
      const model = PdfPageModel(
        pageIndex: 0,
        originalSize: Size(595, 842),
        customOffset: Offset(10, 20),
      );
      final modified = model.copyWith(clearCustomOffset: true);

      expect(modified.customOffset, isNull);
    });

    test('optional fields omitted from JSON when default', () {
      const model = PdfPageModel(pageIndex: 0, originalSize: Size(595, 842));
      final json = model.toJson();

      expect(json.containsKey('customOffset'), false);
      expect(json.containsKey('rotation'), false);
      expect(json.containsKey('annotations'), false);
    });
  });

  // ===========================================================================
  // PdfDocumentModel
  // ===========================================================================

  group('PdfDocumentModel', () {
    test('serialization roundtrip preserves all fields', () {
      final model = PdfDocumentModel(
        sourceHash: 'abc123def456',
        totalPages: 10,
        pages: [
          const PdfPageModel(pageIndex: 0, originalSize: Size(595, 842)),
          const PdfPageModel(pageIndex: 1, originalSize: Size(595, 842)),
        ],
        gridColumns: 3,
        gridSpacing: 30.0,
        gridOrigin: const Offset(100, 50),
        createdAt: 1700000000,
        lastModifiedAt: 1700000100,
        timelineRef: 'timeline-abc',
      );

      final json = model.toJson();
      final restored = PdfDocumentModel.fromJson(json);

      expect(restored.sourceHash, 'abc123def456');
      expect(restored.totalPages, 10);
      expect(restored.pages.length, 2);
      expect(restored.gridColumns, 3);
      expect(restored.gridSpacing, 30.0);
      expect(restored.gridOrigin, const Offset(100, 50));
      expect(restored.createdAt, 1700000000);
      expect(restored.lastModifiedAt, 1700000100);
      expect(restored.timelineRef, 'timeline-abc');
    });

    test('defaults are correct', () {
      const model = PdfDocumentModel(
        sourceHash: 'hash',
        totalPages: 1,
        pages: [],
      );

      expect(model.gridColumns, 2);
      expect(model.gridSpacing, 20.0);
      expect(model.gridOrigin, Offset.zero);
      expect(model.timelineRef, isNull);
    });

    test('copyWith clearTimelineRef works', () {
      const model = PdfDocumentModel(
        sourceHash: 'hash',
        totalPages: 1,
        pages: [],
        timelineRef: 'ref-1',
      );
      final modified = model.copyWith(clearTimelineRef: true);

      expect(modified.timelineRef, isNull);
    });
  });

  // ===========================================================================
  // PdfTextRect
  // ===========================================================================

  group('PdfTextRect', () {
    test('serialization roundtrip preserves all fields', () {
      const textRect = PdfTextRect(
        rect: Rect.fromLTRB(10, 20, 100, 40),
        text: 'Hello',
        charOffset: 42,
      );

      final json = textRect.toJson();
      final restored = PdfTextRect.fromJson(json);

      expect(restored.rect, const Rect.fromLTRB(10, 20, 100, 40));
      expect(restored.text, 'Hello');
      expect(restored.charOffset, 42);
    });

    test('containsPoint hit test', () {
      const textRect = PdfTextRect(
        rect: Rect.fromLTRB(10, 20, 100, 40),
        text: 'Test',
        charOffset: 0,
      );

      expect(textRect.containsPoint(const Offset(50, 30)), true);
      expect(textRect.containsPoint(const Offset(5, 30)), false);
      expect(textRect.containsPoint(const Offset(50, 50)), false);
    });
  });

  // ===========================================================================
  // PdfPageNode
  // ===========================================================================

  group('PdfPageNode', () {
    test('serialization roundtrip via factory', () {
      final node = PdfPageNode(
        id: NodeId('pdf-page-1'),
        pageModel: const PdfPageModel(
          pageIndex: 2,
          originalSize: Size(612, 792),
          lastModifiedAt: 1700000000,
        ),
        name: 'Page 3',
      );
      node.opacity = 0.9;

      final json = node.toJson();
      expect(json['nodeType'], 'pdfPage');

      final restored = CanvasNodeFactory.fromJson(json) as PdfPageNode;
      expect(restored.id, 'pdf-page-1');
      expect(restored.pageModel.pageIndex, 2);
      expect(restored.pageModel.originalSize, const Size(612, 792));
      expect(restored.pageModel.lastModifiedAt, 1700000000);
      expect(restored.name, 'Page 3');
      expect(restored.opacity, 0.9);
    });

    test('localBounds uses page original size', () {
      final node = PdfPageNode(
        id: NodeId('bounds-test'),
        pageModel: const PdfPageModel(
          pageIndex: 0,
          originalSize: Size(100, 200),
        ),
      );

      final bounds = node.localBounds;
      expect(bounds.width, 100);
      expect(bounds.height, 200);
    });

    test('text rect hit testing', () {
      final node = PdfPageNode(
        id: NodeId('text-test'),
        pageModel: const PdfPageModel(
          pageIndex: 0,
          originalSize: Size(612, 792),
        ),
      );

      // No text rects loaded
      expect(node.hasTextGeometry, false);
      expect(node.hitTestText(const Offset(50, 50)), isNull);

      // Load text rects (normalized 0.0–1.0 coords)
      node.textRects = const [
        PdfTextRect(
          rect: Rect.fromLTRB(0.02, 0.02, 0.16, 0.04),
          text: 'Hello',
          charOffset: 0,
        ),
        PdfTextRect(
          rect: Rect.fromLTRB(0.02, 0.06, 0.13, 0.08),
          text: 'World',
          charOffset: 6,
        ),
      ];

      expect(node.hasTextGeometry, true);
      // hitTestText normalizes the point by dividing by originalSize
      // Offset(50, 20) / Size(612, 792) ≈ (0.082, 0.025) — inside 'Hello'
      expect(node.hitTestText(const Offset(50, 20))?.text, 'Hello');
      // Offset(50, 50) / Size(612, 792) ≈ (0.082, 0.063) — inside 'World'
      expect(node.hitTestText(const Offset(50, 50))?.text, 'World');
      expect(node.hitTestText(const Offset(200, 200)), isNull);
    });

    test('text rects survive serialization roundtrip', () {
      final node = PdfPageNode(
        id: NodeId('text-serial'),
        pageModel: const PdfPageModel(
          pageIndex: 0,
          originalSize: Size(612, 792),
        ),
      );
      node.textRects = const [
        PdfTextRect(
          rect: Rect.fromLTRB(0.02, 0.02, 0.16, 0.04),
          text: 'Hello',
          charOffset: 0,
        ),
      ];

      final json = node.toJson();
      final restored = PdfPageNode.fromJson(json);

      expect(restored.textRects, isNotNull);
      expect(restored.textRects!.length, 1);
      expect(restored.textRects!.first.text, 'Hello');
    });

    test('hasCacheAtScale tolerance', () {
      final node = PdfPageNode(
        id: NodeId('cache-test'),
        pageModel: const PdfPageModel(
          pageIndex: 0,
          originalSize: Size(612, 792),
        ),
      );

      // No cache
      expect(node.hasCacheAtScale(1.0), false);

      // Simulate a cached image at scale 1.0
      node.cachedScale = 1.0;
      // Still false because cachedImage is null
      expect(node.hasCacheAtScale(1.0), false);
    });

    test('estimatedMemoryBytes is 0 without cache', () {
      final node = PdfPageNode(
        id: NodeId('mem-test'),
        pageModel: const PdfPageModel(
          pageIndex: 0,
          originalSize: Size(612, 792),
        ),
      );
      expect(node.estimatedMemoryBytes, 0);
    });
  });

  // ===========================================================================
  // PdfDocumentNode
  // ===========================================================================

  group('PdfDocumentNode', () {
    test('serialization roundtrip via factory', () {
      final doc = PdfDocumentNode(
        id: NodeId('pdf-doc-1'),
        documentModel: const PdfDocumentModel(
          sourceHash: 'abc123',
          totalPages: 2,
          pages: [],
          gridColumns: 3,
          timelineRef: 'timeline-x',
        ),
        name: 'My PDF',
      );

      // Add child pages
      doc.add(
        PdfPageNode(
          id: NodeId('p-0'),
          pageModel: const PdfPageModel(
            pageIndex: 0,
            originalSize: Size(595, 842),
          ),
        ),
      );
      doc.add(
        PdfPageNode(
          id: NodeId('p-1'),
          pageModel: const PdfPageModel(
            pageIndex: 1,
            originalSize: Size(595, 842),
          ),
        ),
      );

      final json = doc.toJson();
      expect(json['nodeType'], 'pdfDocument');
      expect((json['children'] as List).length, 2);

      final restored = CanvasNodeFactory.fromJson(json) as PdfDocumentNode;
      expect(restored.id, 'pdf-doc-1');
      expect(restored.documentModel.sourceHash, 'abc123');
      expect(restored.documentModel.gridColumns, 3);
      expect(restored.documentModel.timelineRef, 'timeline-x');
      expect(restored.name, 'My PDF');
      expect(restored.children.length, 2);
      expect(restored.children.first, isA<PdfPageNode>());
    });

    test('performGridLayout positions locked pages', () {
      final doc = PdfDocumentNode(
        id: NodeId('grid-test'),
        documentModel: const PdfDocumentModel(
          sourceHash: 'hash',
          totalPages: 4,
          pages: [],
          gridColumns: 2,
          gridSpacing: 10.0,
          gridOrigin: Offset.zero,
        ),
      );

      // Add 4 locked pages (100x100)
      for (int i = 0; i < 4; i++) {
        doc.add(
          PdfPageNode(
            id: NodeId('page-$i'),
            pageModel: PdfPageModel(
              pageIndex: i,
              originalSize: const Size(100, 100),
            ),
          ),
        );
      }

      doc.performGridLayout();

      final pages = doc.pageNodes;
      // Row 0, Col 0: (0, 0)
      expect(pages[0].position, const Offset(0, 0));
      // Row 0, Col 1: (110, 0) — 100 + 10 spacing
      expect(pages[1].position, const Offset(110, 0));
      // Row 1, Col 0: (0, 110)
      expect(pages[2].position, const Offset(0, 110));
      // Row 1, Col 1: (110, 110)
      expect(pages[3].position, const Offset(110, 110));
    });

    test('unlocked page keeps customOffset', () {
      final doc = PdfDocumentNode(
        id: NodeId('unlock-test'),
        documentModel: const PdfDocumentModel(
          sourceHash: 'hash',
          totalPages: 2,
          pages: [],
          gridColumns: 2,
          gridSpacing: 10.0,
        ),
      );

      // Locked page
      doc.add(
        PdfPageNode(
          id: NodeId('locked-page'),
          pageModel: const PdfPageModel(
            pageIndex: 0,
            originalSize: Size(100, 100),
          ),
        ),
      );

      // Unlocked page with custom position
      doc.add(
        PdfPageNode(
          id: NodeId('unlocked-page'),
          pageModel: const PdfPageModel(
            pageIndex: 1,
            originalSize: Size(100, 100),
            isLocked: false,
            customOffset: Offset(500, 300),
          ),
        ),
      );

      doc.performGridLayout();

      // Locked page positioned by grid
      expect(doc.pageNodes[0].position, const Offset(0, 0));
      // Unlocked page at custom position
      expect(doc.pageNodes[1].position, const Offset(500, 300));
    });

    test('togglePageLock switches state and re-layouts', () {
      final doc = PdfDocumentNode(
        id: NodeId('toggle-test'),
        documentModel: const PdfDocumentModel(
          sourceHash: 'hash',
          totalPages: 1,
          pages: [],
          gridColumns: 2,
        ),
      );

      doc.add(
        PdfPageNode(
          id: NodeId('toggle-page'),
          pageModel: const PdfPageModel(
            pageIndex: 0,
            originalSize: Size(100, 100),
          ),
        ),
      );

      // Initially locked
      expect(doc.pageNodes[0].pageModel.isLocked, true);

      // Unlock
      doc.togglePageLock(0);
      expect(doc.pageNodes[0].pageModel.isLocked, false);
      expect(doc.pageNodes[0].pageModel.customOffset, isNotNull);
      expect(doc.pageNodes[0].pageModel.lastModifiedAt, isPositive);

      // Re-lock (lock-in-place: customOffset preserves current position)
      doc.togglePageLock(0);
      expect(doc.pageNodes[0].pageModel.isLocked, true);
      // Lock-in-place: customOffset = current position, not null.
      // Use returnPageToGrid() to snap back to grid (clears customOffset).
      expect(doc.pageNodes[0].pageModel.customOffset, isNotNull);
    });

    test('totalCachedMemoryBytes is 0 without cached images', () {
      final doc = PdfDocumentNode(
        id: NodeId('mem-test'),
        documentModel: const PdfDocumentModel(
          sourceHash: 'hash',
          totalPages: 2,
          pages: [],
        ),
      );
      doc.add(
        PdfPageNode(
          id: NodeId('p0'),
          pageModel: const PdfPageModel(
            pageIndex: 0,
            originalSize: Size(100, 100),
          ),
        ),
      );

      expect(doc.totalCachedMemoryBytes, 0);
    });

    test('pageAt finds correct page', () {
      final doc = PdfDocumentNode(
        id: NodeId('find-test'),
        documentModel: const PdfDocumentModel(
          sourceHash: 'hash',
          totalPages: 3,
          pages: [],
        ),
      );
      for (int i = 0; i < 3; i++) {
        doc.add(
          PdfPageNode(
            id: NodeId('page-$i'),
            pageModel: PdfPageModel(
              pageIndex: i,
              originalSize: const Size(100, 100),
            ),
          ),
        );
      }

      expect(doc.pageAt(1)?.id, 'page-1');
      expect(doc.pageAt(5), isNull);
    });

    test('performGridLayout populates pendingStrokeTranslations', () {
      final doc = PdfDocumentNode(
        id: NodeId('translate-test'),
        documentModel: const PdfDocumentModel(
          sourceHash: 'hash',
          totalPages: 2,
          pages: [],
          gridColumns: 1,
          gridSpacing: 10.0,
          gridOrigin: Offset.zero,
        ),
      );

      // Add 2 locked pages (100x100)
      doc.add(
        PdfPageNode(
          id: NodeId('page-a'),
          pageModel: const PdfPageModel(
            pageIndex: 0,
            originalSize: Size(100, 100),
            annotations: ['stroke-1', 'stroke-2'],
          ),
        ),
      );
      doc.add(
        PdfPageNode(
          id: NodeId('page-b'),
          pageModel: const PdfPageModel(
            pageIndex: 1,
            originalSize: Size(100, 100),
            annotations: ['stroke-3'],
          ),
        ),
      );

      // Initial layout (columns=1)
      doc.performGridLayout();
      // Consume initial translations (from Offset.zero → grid position)
      doc.pendingStrokeTranslations.clear();

      // Verify initial positions: col=1, so page-0 at (0,0), page-1 at (0,110)
      expect(doc.pageNodes[0].position, const Offset(0, 0));
      expect(doc.pageNodes[1].position, const Offset(0, 110));

      // Change to 2 columns → page-1 moves from (0,110) to (110,0)
      doc.setGridColumns(2);

      // page-0 should stay at (0,0) → delta == zero → no translation
      // page-1 moves from (0,110) to (110,0) → delta = (110, -110)
      expect(doc.pendingStrokeTranslations.length, 1);
      final tx = doc.pendingStrokeTranslations.first;
      expect(tx.delta, const Offset(110, -110));
      expect(tx.annotationIds, ['stroke-3']);
    });

    test('reorderPage generates stroke translations', () {
      final doc = PdfDocumentNode(
        id: NodeId('reorder-test'),
        documentModel: const PdfDocumentModel(
          sourceHash: 'hash',
          totalPages: 3,
          pages: [],
          gridColumns: 1,
          gridSpacing: 10.0,
          gridOrigin: Offset.zero,
        ),
      );

      for (int i = 0; i < 3; i++) {
        doc.add(
          PdfPageNode(
            id: NodeId('page-$i'),
            pageModel: PdfPageModel(
              pageIndex: i,
              originalSize: const Size(100, 100),
              annotations: ['stroke-$i'],
            ),
          ),
        );
      }

      doc.performGridLayout();
      doc.pendingStrokeTranslations.clear();

      // Initial: page-0 at y=0, page-1 at y=110, page-2 at y=220
      // Reorder page-2 → position-0 (move to front)
      doc.reorderPage(2, 0);

      // After reorder, pages reshuffle → some translations expected
      expect(doc.pendingStrokeTranslations.isNotEmpty, true);
    });

    test('removePage preserves annotation IDs on removed node', () {
      final doc = PdfDocumentNode(
        id: NodeId('remove-test'),
        documentModel: const PdfDocumentModel(
          sourceHash: 'hash',
          totalPages: 2,
          pages: [],
          gridColumns: 1,
          gridSpacing: 10.0,
        ),
      );

      doc.add(
        PdfPageNode(
          id: NodeId('page-keep'),
          pageModel: const PdfPageModel(
            pageIndex: 0,
            originalSize: Size(100, 100),
          ),
        ),
      );
      doc.add(
        PdfPageNode(
          id: NodeId('page-remove'),
          pageModel: const PdfPageModel(
            pageIndex: 1,
            originalSize: Size(100, 100),
            annotations: ['stroke-on-removed-page'],
          ),
        ),
      );

      doc.performGridLayout();

      final removed = doc.removePage(1);
      expect(removed, isNotNull);
      expect(removed!.pageModel.annotations, ['stroke-on-removed-page']);
    });

    test('unlinkAnnotation removes ID from all pages', () {
      final doc = PdfDocumentNode(
        id: NodeId('unlink-test'),
        documentModel: const PdfDocumentModel(
          sourceHash: 'hash',
          totalPages: 2,
          pages: [],
        ),
      );

      doc.add(
        PdfPageNode(
          id: NodeId('p-0'),
          pageModel: const PdfPageModel(
            pageIndex: 0,
            originalSize: Size(100, 100),
            annotations: ['s-1', 's-2'],
          ),
        ),
      );
      doc.add(
        PdfPageNode(
          id: NodeId('p-1'),
          pageModel: const PdfPageModel(
            pageIndex: 1,
            originalSize: Size(100, 100),
            annotations: ['s-2', 's-3'],
          ),
        ),
      );

      // Unlink s-2 from all pages
      doc.unlinkAnnotation('s-2');

      expect(doc.pageNodes[0].pageModel.annotations, ['s-1']);
      expect(doc.pageNodes[1].pageModel.annotations, ['s-3']);
    });

    test('pages without annotations produce no translations', () {
      final doc = PdfDocumentNode(
        id: NodeId('no-annot-test'),
        documentModel: const PdfDocumentModel(
          sourceHash: 'hash',
          totalPages: 2,
          pages: [],
          gridColumns: 1,
          gridSpacing: 10.0,
          gridOrigin: Offset.zero,
        ),
      );

      doc.add(
        PdfPageNode(
          id: NodeId('page-0'),
          pageModel: const PdfPageModel(
            pageIndex: 0,
            originalSize: Size(100, 100),
            // No annotations
          ),
        ),
      );
      doc.add(
        PdfPageNode(
          id: NodeId('page-1'),
          pageModel: const PdfPageModel(
            pageIndex: 1,
            originalSize: Size(100, 100),
            // No annotations
          ),
        ),
      );

      doc.performGridLayout();
      doc.pendingStrokeTranslations.clear();

      // Change columns — even though pages move, no translations since no annotations
      doc.setGridColumns(2);
      expect(doc.pendingStrokeTranslations, isEmpty);
    });
  });
}
