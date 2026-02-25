import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/layout/flex_layout_solver.dart';
import 'package:nebula_engine/src/core/layout/auto_layout_config.dart';

void main() {
  // ===========================================================================
  // Basic horizontal layout
  // ===========================================================================

  group('FlexLayoutSolver - horizontal', () {
    test('distributes children horizontally', () {
      final result = FlexLayoutSolver.solve(
        config: AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          spacing: 10,
        ),
        containerSize: const Size(400, 200),
        children: [
          FlexChild(intrinsicSize: const Size(100, 50)),
          FlexChild(intrinsicSize: const Size(80, 40)),
        ],
      );
      expect(result.childRects.length, 2);
      // First child starts at x=0 (or near padding)
      // Second child starts after first + spacing
      expect(
        result.childRects[1].left,
        greaterThan(result.childRects[0].right),
      );
    });

    test('flexGrow distributes remaining space', () {
      final result = FlexLayoutSolver.solve(
        config: AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          spacing: 0,
        ),
        containerSize: const Size(400, 200),
        children: [
          FlexChild(intrinsicSize: const Size(100, 50)),
          FlexChild(intrinsicSize: const Size(100, 50), flexGrow: 1),
        ],
      );
      // Second child should grow to fill remaining space
      expect(result.childRects[1].width, greaterThan(100));
    });
  });

  // ===========================================================================
  // Vertical layout
  // ===========================================================================

  group('FlexLayoutSolver - vertical', () {
    test('distributes children vertically', () {
      final result = FlexLayoutSolver.solve(
        config: AutoLayoutConfig(
          direction: LayoutDirection.vertical,
          spacing: 10,
        ),
        containerSize: const Size(200, 400),
        children: [
          FlexChild(intrinsicSize: const Size(100, 50)),
          FlexChild(intrinsicSize: const Size(100, 60)),
        ],
      );
      expect(result.childRects.length, 2);
      expect(
        result.childRects[1].top,
        greaterThan(result.childRects[0].bottom),
      );
    });
  });

  // ===========================================================================
  // Alignment
  // ===========================================================================

  group('FlexLayoutSolver - alignment', () {
    test('center alignment centers children', () {
      final result = FlexLayoutSolver.solve(
        config: AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          spacing: 0,
          mainAxisAlignment: MainAxisAlignment.center,
        ),
        containerSize: const Size(400, 200),
        children: [FlexChild(intrinsicSize: const Size(100, 50))],
      );
      // Should be centered: (400 - 100) / 2 = 150
      expect(result.childRects[0].left, closeTo(150, 2));
    });

    test('end alignment pushes to end', () {
      final result = FlexLayoutSolver.solve(
        config: AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          spacing: 0,
          mainAxisAlignment: MainAxisAlignment.end,
        ),
        containerSize: const Size(400, 200),
        children: [FlexChild(intrinsicSize: const Size(100, 50))],
      );
      // Should be at the end: 400 - 100 = 300
      expect(result.childRects[0].left, closeTo(300, 2));
    });
  });

  // ===========================================================================
  // Empty children
  // ===========================================================================

  group('FlexLayoutSolver - edge cases', () {
    test('empty children list returns empty rects', () {
      final result = FlexLayoutSolver.solve(
        config: AutoLayoutConfig(direction: LayoutDirection.horizontal),
        containerSize: const Size(400, 200),
        children: [],
      );
      expect(result.childRects, isEmpty);
    });

    test('single child fills with flexGrow', () {
      final result = FlexLayoutSolver.solve(
        config: AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          spacing: 0,
        ),
        containerSize: const Size(400, 200),
        children: [FlexChild(intrinsicSize: const Size(50, 50), flexGrow: 1)],
      );
      expect(result.childRects[0].width, closeTo(400, 2));
    });
  });

  // ===========================================================================
  // Spacing
  // ===========================================================================

  group('FlexLayoutSolver - spacing', () {
    test('spacing creates gaps between children', () {
      final result = FlexLayoutSolver.solve(
        config: AutoLayoutConfig(
          direction: LayoutDirection.horizontal,
          spacing: 20,
        ),
        containerSize: const Size(400, 200),
        children: [
          FlexChild(intrinsicSize: const Size(100, 50)),
          FlexChild(intrinsicSize: const Size(100, 50)),
        ],
      );
      final gap = result.childRects[1].left - result.childRects[0].right;
      expect(gap, closeTo(20, 2));
    });
  });
}
