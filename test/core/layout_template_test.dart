import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/layout/layout_template.dart';

void main() {
  // ===========================================================================
  // Factory presets - Flex
  // ===========================================================================

  group('LayoutTemplate - flex presets', () {
    test('horizontalStack is flex', () {
      final t = LayoutTemplate.horizontalStack();
      expect(t.isFlex, isTrue);
      expect(t.isGrid, isFalse);
      expect(t.id, 'horizontal_stack');
    });

    test('verticalStack is flex', () {
      final t = LayoutTemplate.verticalStack();
      expect(t.isFlex, isTrue);
      expect(t.id, 'vertical_stack');
    });

    test('centeredContent is flex', () {
      final t = LayoutTemplate.centeredContent();
      expect(t.isFlex, isTrue);
    });

    test('navigationBar is flex', () {
      final t = LayoutTemplate.navigationBar();
      expect(t.isFlex, isTrue);
    });

    test('wrappingTags is flex', () {
      final t = LayoutTemplate.wrappingTags();
      expect(t.isFlex, isTrue);
    });

    test('custom spacing', () {
      final t = LayoutTemplate.horizontalStack(spacing: 20);
      expect(t.flexConfig!.spacing, 20);
    });
  });

  // ===========================================================================
  // Factory presets - Grid
  // ===========================================================================

  group('LayoutTemplate - grid presets', () {
    test('sidebar is grid', () {
      final t = LayoutTemplate.sidebar();
      expect(t.isGrid, isTrue);
      expect(t.isFlex, isFalse);
    });

    test('magazineGrid has 3 columns', () {
      final t = LayoutTemplate.magazineGrid();
      expect(t.gridConfig!.columns.length, 3);
    });

    test('dashboardGrid has 3 rows', () {
      final t = LayoutTemplate.dashboardGrid();
      expect(t.gridConfig!.rows.length, 3);
    });

    test('presentationSlide is grid', () {
      final t = LayoutTemplate.presentationSlide();
      expect(t.isGrid, isTrue);
    });

    test('cardLayout is grid', () {
      final t = LayoutTemplate.cardLayout();
      expect(t.isGrid, isTrue);
    });
  });

  // ===========================================================================
  // Registry
  // ===========================================================================

  group('LayoutTemplate - allBuiltIn', () {
    test('contains 10 templates', () {
      expect(LayoutTemplate.allBuiltIn.length, 10);
    });

    test('all have unique IDs', () {
      final ids = LayoutTemplate.allBuiltIn.map((t) => t.id).toSet();
      expect(ids.length, 10);
    });
  });

  // ===========================================================================
  // toString
  // ===========================================================================

  group('LayoutTemplate - toString', () {
    test('is readable', () {
      final t = LayoutTemplate.horizontalStack();
      expect(t.toString(), contains('horizontal_stack'));
    });
  });
}
