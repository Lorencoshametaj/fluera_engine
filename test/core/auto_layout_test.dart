import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/layout/auto_layout_config.dart';
import 'package:nebula_engine/src/core/layout/flex_layout_solver.dart';
import 'package:nebula_engine/src/core/layout/grid_layout_solver.dart';
import 'package:nebula_engine/src/core/layout/layout_template.dart';

void main() {
  // ===========================================================================
  // AUTO LAYOUT CONFIG
  // ===========================================================================

  group('AutoLayoutConfig', () {
    test('creates with defaults', () {
      const config = AutoLayoutConfig();
      expect(config.direction, LayoutDirection.vertical);
      expect(config.spacing, 0);
      expect(config.mainAxisAlignment, MainAxisAlignment.start);
      expect(config.crossAxisAlignment, CrossAxisAlignment.start);
      expect(config.reversed, isFalse);
    });

    test('isHorizontal helper', () {
      const h = AutoLayoutConfig(direction: LayoutDirection.horizontal);
      const v = AutoLayoutConfig(direction: LayoutDirection.vertical);
      expect(h.isHorizontal, isTrue);
      expect(v.isHorizontal, isFalse);
    });

    test('copyWith preserves unmodified fields', () {
      const original = AutoLayoutConfig(
        spacing: 12,
        direction: LayoutDirection.horizontal,
      );
      final updated = original.copyWith(spacing: 24);
      expect(updated.spacing, 24);
      expect(updated.direction, LayoutDirection.horizontal);
    });

    test('toJson/fromJson round-trips', () {
      const original = AutoLayoutConfig(
        direction: LayoutDirection.horizontal,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        padding: LayoutEdgeInsets.all(8),
        primarySizing: LayoutSizingMode.fillContainer,
        counterSizing: LayoutSizingMode.hugContents,
        overflow: OverflowBehavior.wrap,
        reversed: true,
      );

      final json = original.toJson();
      final restored = AutoLayoutConfig.fromJson(json);

      expect(restored.direction, original.direction);
      expect(restored.mainAxisAlignment, original.mainAxisAlignment);
      expect(restored.crossAxisAlignment, original.crossAxisAlignment);
      expect(restored.spacing, original.spacing);
      expect(restored.reversed, original.reversed);
      expect(restored.overflow, original.overflow);
    });
  });

  group('LayoutEdgeInsets', () {
    test('all constructor', () {
      const insets = LayoutEdgeInsets.all(10);
      expect(insets.horizontal, 20);
      expect(insets.vertical, 20);
    });

    test('symmetric constructor', () {
      const insets = LayoutEdgeInsets.symmetric(horizontal: 10, vertical: 20);
      expect(insets.left, 10);
      expect(insets.right, 10);
      expect(insets.top, 20);
      expect(insets.bottom, 20);
    });

    test('serialization round-trips', () {
      const insets = LayoutEdgeInsets.only(
        left: 1,
        top: 2,
        right: 3,
        bottom: 4,
      );
      final json = insets.toJson();
      final restored = LayoutEdgeInsets.fromJson(json);
      expect(restored, insets);
    });
  });

  // ===========================================================================
  // FLEX LAYOUT SOLVER
  // ===========================================================================

  group('FlexLayoutSolver', () {
    test('empty children', () {
      final result = FlexLayoutSolver.solve(
        config: const AutoLayoutConfig(),
        containerSize: const Size(400, 200),
        children: [],
      );
      expect(result.childRects, isEmpty);
    });

    test('horizontal start alignment', () {
      final result = FlexLayoutSolver.solve(
        config: const AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          spacing: 10,
        ),
        containerSize: const Size(400, 100),
        children: [
          const FlexChild(intrinsicSize: Size(50, 30)),
          const FlexChild(intrinsicSize: Size(60, 40)),
        ],
      );

      expect(result.childRects.length, 2);
      expect(result.childRects[0].left, 0); // starts at 0 (no padding)
      expect(result.childRects[0].width, 50);
      expect(result.childRects[1].left, 60); // 50 + 10 spacing
      expect(result.childRects[1].width, 60);
    });

    test('vertical layout', () {
      final result = FlexLayoutSolver.solve(
        config: const AutoLayoutConfig(
          direction: LayoutDirection.vertical,
          spacing: 8,
        ),
        containerSize: const Size(200, 400),
        children: [
          const FlexChild(intrinsicSize: Size(100, 40)),
          const FlexChild(intrinsicSize: Size(80, 50)),
        ],
      );

      expect(result.childRects[0].top, 0);
      expect(result.childRects[0].height, 40);
      expect(result.childRects[1].top, 48); // 40 + 8
    });

    test('center alignment', () {
      final result = FlexLayoutSolver.solve(
        config: const AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          mainAxisAlignment: MainAxisAlignment.center,
        ),
        containerSize: const Size(400, 100),
        children: [const FlexChild(intrinsicSize: Size(100, 50))],
      );

      // Single 100px child in 400px container, centered = 150px offset
      expect(result.childRects[0].left, closeTo(150, 1));
    });

    test('spaceBetween alignment', () {
      final result = FlexLayoutSolver.solve(
        config: const AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
        ),
        containerSize: const Size(400, 100),
        children: [
          const FlexChild(intrinsicSize: Size(50, 30)),
          const FlexChild(intrinsicSize: Size(50, 30)),
        ],
      );

      expect(result.childRects[0].left, 0);
      expect(result.childRects[1].left, closeTo(350, 1)); // 400 - 50
    });

    test('flex grow distributes free space', () {
      final result = FlexLayoutSolver.solve(
        config: const AutoLayoutConfig(direction: LayoutDirection.horizontal),
        containerSize: const Size(300, 100),
        children: [
          const FlexChild(intrinsicSize: Size(50, 50)),
          const FlexChild(intrinsicSize: Size(50, 50), flexGrow: 1),
        ],
      );

      // First child: 50px fixed
      expect(result.childRects[0].width, 50);
      // Second child: 50px + all free space (300 - 50 - 50 = 200)
      expect(result.childRects[1].width, closeTo(250, 1));
    });

    test('cross axis stretch', () {
      final result = FlexLayoutSolver.solve(
        config: const AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          crossAxisAlignment: CrossAxisAlignment.stretch,
        ),
        containerSize: const Size(400, 100),
        children: [const FlexChild(intrinsicSize: Size(50, 30))],
      );

      expect(result.childRects[0].height, 100); // stretched to container
    });

    test('cross axis center', () {
      final result = FlexLayoutSolver.solve(
        config: const AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          crossAxisAlignment: CrossAxisAlignment.center,
        ),
        containerSize: const Size(400, 100),
        children: [const FlexChild(intrinsicSize: Size(50, 30))],
      );

      expect(result.childRects[0].top, closeTo(35, 1)); // (100-30)/2
    });

    test('padding offsets children', () {
      final result = FlexLayoutSolver.solve(
        config: const AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          padding: LayoutEdgeInsets.all(20),
        ),
        containerSize: const Size(400, 100),
        children: [const FlexChild(intrinsicSize: Size(50, 30))],
      );

      expect(result.childRects[0].left, 20);
      expect(result.childRects[0].top, 20);
    });

    test('overflow detection', () {
      final result = FlexLayoutSolver.solve(
        config: const AutoLayoutConfig(direction: LayoutDirection.horizontal),
        containerSize: const Size(100, 50),
        children: [
          const FlexChild(intrinsicSize: Size(60, 30)),
          const FlexChild(intrinsicSize: Size(60, 30)),
        ],
      );

      expect(result.didOverflow, isTrue);
    });

    test('wrap creates multiple lines', () {
      final result = FlexLayoutSolver.solve(
        config: const AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          spacing: 0,
          overflow: OverflowBehavior.wrap,
        ),
        containerSize: const Size(100, 200),
        children: [
          const FlexChild(intrinsicSize: Size(60, 30)),
          const FlexChild(intrinsicSize: Size(60, 30)),
          const FlexChild(intrinsicSize: Size(40, 30)),
        ],
      );

      // First child on line 1, second wraps to line 2
      expect(result.childRects[0].top, 0);
      expect(result.childRects[1].top, 30); // next line
      expect(result.wrapBreaks, isNotEmpty);
    });

    test('reversed order', () {
      final result = FlexLayoutSolver.solve(
        config: const AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          reversed: true,
        ),
        containerSize: const Size(400, 100),
        children: [
          const FlexChild(intrinsicSize: Size(50, 30)),
          const FlexChild(intrinsicSize: Size(100, 30)),
        ],
      );

      // Reversed: second child (100px) comes first
      expect(result.childRects[0].width, 100);
      expect(result.childRects[1].width, 50);
    });
  });

  // ===========================================================================
  // GRID LAYOUT SOLVER
  // ===========================================================================

  group('GridLayoutSolver', () {
    test('empty grid', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(columns: [], rows: []),
        containerSize: const Size(400, 300),
        children: [],
      );
      expect(result.childRects, isEmpty);
    });

    test('2x2 equal grid', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fr(1), TrackDefinition.fr(1)],
          rows: [TrackDefinition.fr(1), TrackDefinition.fr(1)],
        ),
        containerSize: const Size(200, 200),
        children: [
          const GridChild(), // auto at 0,0
          const GridChild(), // auto at 1,0
          const GridChild(), // auto at 0,1
          const GridChild(), // auto at 1,1
        ],
      );

      expect(result.childRects.length, 4);
      expect(result.columnWidths[0], 100);
      expect(result.columnWidths[1], 100);
      expect(result.childRects[0], const Rect.fromLTWH(0, 0, 100, 100));
      expect(result.childRects[1], const Rect.fromLTWH(100, 0, 100, 100));
      expect(result.childRects[2], const Rect.fromLTWH(0, 100, 100, 100));
    });

    test('fixed + fr columns', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fixed(100), TrackDefinition.fr(1)],
          rows: [TrackDefinition.fr(1)],
        ),
        containerSize: const Size(400, 200),
        children: [const GridChild(), const GridChild()],
      );

      expect(result.columnWidths[0], 100); // fixed
      expect(result.columnWidths[1], 300); // remaining
    });

    test('gaps between tracks', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fr(1), TrackDefinition.fr(1)],
          rows: [TrackDefinition.fr(1)],
          columnGap: 20,
        ),
        containerSize: const Size(220, 100),
        children: [const GridChild(), const GridChild()],
      );

      // 220 - 20 gap = 200, each col = 100
      expect(result.columnWidths[0], 100);
      expect(result.columnWidths[1], 100);
      expect(result.childRects[1].left, 120); // 100 + 20 gap
    });

    test('explicit placement', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fr(1), TrackDefinition.fr(1)],
          rows: [TrackDefinition.fr(1), TrackDefinition.fr(1)],
        ),
        containerSize: const Size(200, 200),
        children: [
          const GridChild(column: 1, row: 1), // bottom-right
        ],
      );

      expect(result.childRects[0].left, 100);
      expect(result.childRects[0].top, 100);
    });

    test('column span', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fr(1), TrackDefinition.fr(1)],
          rows: [TrackDefinition.fr(1)],
        ),
        containerSize: const Size(200, 100),
        children: [const GridChild(column: 0, row: 0, columnSpan: 2)],
      );

      expect(result.childRects[0].width, 200); // spans both columns
    });

    test('auto-placement column-first', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fr(1), TrackDefinition.fr(1)],
          rows: [TrackDefinition.fr(1), TrackDefinition.fr(1)],
          autoFlow: GridAutoFlow.columnFirst,
        ),
        containerSize: const Size(200, 200),
        children: [const GridChild(), const GridChild(), const GridChild()],
      );

      // Column-first: (0,0), (0,1), (1,0)
      expect(result.childRects[0].left, 0);
      expect(result.childRects[0].top, 0);
      expect(result.childRects[1].left, 0);
      expect(result.childRects[1].top, 100);
      expect(result.childRects[2].left, 100);
      expect(result.childRects[2].top, 0);
    });

    test('fr ratio distribution', () {
      final result = GridLayoutSolver.solve(
        config: const GridLayoutConfig(
          columns: [TrackDefinition.fr(1), TrackDefinition.fr(2)],
          rows: [TrackDefinition.fr(1)],
        ),
        containerSize: const Size(300, 100),
        children: [const GridChild()],
      );

      expect(result.columnWidths[0], 100); // 1/3
      expect(result.columnWidths[1], 200); // 2/3
    });
  });

  // ===========================================================================
  // LAYOUT TEMPLATE
  // ===========================================================================

  group('LayoutTemplate', () {
    test('horizontalStack produces flex config', () {
      final t = LayoutTemplate.horizontalStack(spacing: 12);
      expect(t.isFlex, isTrue);
      expect(t.isGrid, isFalse);
      expect(t.flexConfig!.direction, LayoutDirection.horizontal);
      expect(t.flexConfig!.spacing, 12);
    });

    test('verticalStack produces flex config', () {
      final t = LayoutTemplate.verticalStack();
      expect(t.flexConfig!.direction, LayoutDirection.vertical);
      expect(t.flexConfig!.crossAxisAlignment, CrossAxisAlignment.stretch);
    });

    test('centeredContent centers both axes', () {
      final t = LayoutTemplate.centeredContent();
      expect(t.flexConfig!.mainAxisAlignment, MainAxisAlignment.center);
      expect(t.flexConfig!.crossAxisAlignment, CrossAxisAlignment.center);
    });

    test('sidebar produces grid config', () {
      final t = LayoutTemplate.sidebar(sidebarWidth: 200);
      expect(t.isGrid, isTrue);
      expect(t.gridConfig!.columns.length, 2);
      expect(t.gridConfig!.columns[0].fixedSize, 200);
    });

    test('dashboardGrid has 3 rows', () {
      final t = LayoutTemplate.dashboardGrid();
      expect(t.gridConfig!.rows.length, 3);
    });

    test('allBuiltIn returns all templates', () {
      expect(LayoutTemplate.allBuiltIn.length, 10);
      final ids = LayoutTemplate.allBuiltIn.map((t) => t.id).toSet();
      expect(ids.length, 10); // all unique
    });

    test('wrappingTags uses wrap overflow', () {
      final t = LayoutTemplate.wrappingTags();
      expect(t.flexConfig!.overflow, OverflowBehavior.wrap);
    });
  });
}
