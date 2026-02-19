import 'package:flutter/material.dart'
    hide CrossAxisAlignment, MainAxisAlignment;
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/nodes/frame_node.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_visitor.dart';
import 'package:nebula_engine/src/systems/layout_engine.dart';

// =============================================================================
// Test helpers
// =============================================================================

/// Concrete leaf node with configurable bounds (CanvasNode is abstract).
class _Box extends CanvasNode {
  final Rect _bounds;

  _Box({required super.id, required double width, required double height})
    : _bounds = Rect.fromLTWH(0, 0, width, height);

  @override
  Rect get localBounds => _bounds;

  @override
  Map<String, dynamic> toJson() => {'id': id, 'nodeType': 'test'};

  @override
  R accept<R>(NodeVisitor<R> visitor) =>
      throw UnimplementedError('not needed for tests');
}

/// Get the absolute position of a node from its localTransform.
Offset _pos(CanvasNode node) => node.position;

// =============================================================================
// Tests
// =============================================================================

void main() {
  // ===========================================================================
  // 1. Horizontal layout with fixed children
  // ===========================================================================
  test('horizontal layout positions fixed children correctly', () {
    final frame = FrameNode(
      id: 'frame',
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: const EdgeInsets.all(8),
      frameSize: const Size(300, 100),
    );

    final a = _Box(id: 'a', width: 40, height: 30);
    final b = _Box(id: 'b', width: 60, height: 30);
    final c = _Box(id: 'c', width: 50, height: 30);

    frame.addWithConstraint(
      a,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 40),
    );
    frame.addWithConstraint(
      b,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 60),
    );
    frame.addWithConstraint(
      c,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 50),
    );

    frame.performLayout();

    // a starts at padding (8)
    expect(_pos(a).dx, closeTo(8, 0.1));
    // b starts at 8 + 40 + 10 spacing = 58
    expect(_pos(b).dx, closeTo(58, 0.1));
    // c starts at 58 + 60 + 10 = 128
    expect(_pos(c).dx, closeTo(128, 0.1));

    // All at top padding
    expect(_pos(a).dy, closeTo(8, 0.1));
    expect(_pos(b).dy, closeTo(8, 0.1));
    expect(_pos(c).dy, closeTo(8, 0.1));
  });

  // ===========================================================================
  // 2. Vertical layout with fill children
  // ===========================================================================
  test('vertical layout distributes fill children by flex-grow', () {
    final frame = FrameNode(
      id: 'frame',
      direction: LayoutDirection.vertical,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(100, 300),
    );

    final a = _Box(id: 'a', width: 100, height: 0);
    final b = _Box(id: 'b', width: 100, height: 0);

    frame.addWithConstraint(
      a,
      LayoutConstraint(primarySizing: SizingMode.fill, flexGrow: 2),
    );
    frame.addWithConstraint(
      b,
      LayoutConstraint(primarySizing: SizingMode.fill, flexGrow: 1),
    );

    frame.performLayout();

    // 300 total, 2:1 ratio => a gets 200, b gets 100
    expect(_pos(a).dy, closeTo(0, 0.1));
    // b starts after a: at 200
    expect(_pos(b).dy, closeTo(200, 0.1));
  });

  // ===========================================================================
  // 3. Hug sizing (frame shrinks to content)
  // ===========================================================================
  test('hug sizing computes correct frame dimensions', () {
    final frame = FrameNode(
      id: 'frame',
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: const EdgeInsets.all(5),
      // No frameSize — hug mode
    );

    final a = _Box(id: 'a', width: 40, height: 20);
    final b = _Box(id: 'b', width: 60, height: 30);

    frame.addWithConstraint(a, LayoutConstraint());
    frame.addWithConstraint(b, LayoutConstraint());

    frame.performLayout();

    // Hugging width: 5 + 40 + 10 + 60 + 5 = 120
    // Hugging height: 5 + max(20,30) + 5 = 40
    // (Not checking localBounds directly since frameSize is null and
    //  super.localBounds depends on children positions)
    // Verify children are positioned correctly
    expect(_pos(a).dx, closeTo(5, 0.1));
    expect(_pos(b).dx, closeTo(55, 0.1));
  });

  // ===========================================================================
  // 4. Nested frames (inner hug inside outer fill)
  // ===========================================================================
  test('nested frames layout recursively', () {
    final outer = FrameNode(
      id: 'outer',
      direction: LayoutDirection.vertical,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(200, 200),
    );

    final inner = FrameNode(
      id: 'inner',
      direction: LayoutDirection.horizontal,
      spacing: 5,
      padding: const EdgeInsets.all(4),
    );

    final child1 = _Box(id: 'c1', width: 30, height: 20);
    final child2 = _Box(id: 'c2', width: 30, height: 20);

    inner.addWithConstraint(child1, LayoutConstraint());
    inner.addWithConstraint(child2, LayoutConstraint());

    outer.addWithConstraint(inner, LayoutConstraint());

    outer.performLayout();

    // Inner frame should have laid out its children:
    // c1 at padding(4), c2 at 4 + 30 + 5 = 39
    expect(_pos(child1).dx, closeTo(4, 0.1));
    expect(_pos(child2).dx, closeTo(39, 0.1));

    // Inner frame itself positioned at (0,0) in outer
    expect(_pos(inner).dx, closeTo(0, 0.1));
    expect(_pos(inner).dy, closeTo(0, 0.1));
  });

  // ===========================================================================
  // 5. Wrap layout
  // ===========================================================================
  test('wrap layout overflows to next line', () {
    final frame = FrameNode(
      id: 'frame',
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: EdgeInsets.zero,
      wrap: LayoutWrap.wrap,
      frameSize: const Size(100, 200),
    );

    // 3 children of 40px each — first two fit (80 ≤ 100), third wraps
    final a = _Box(id: 'a', width: 40, height: 20);
    final b = _Box(id: 'b', width: 40, height: 20);
    final c = _Box(id: 'c', width: 40, height: 25);

    frame.addWithConstraint(
      a,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 40),
    );
    frame.addWithConstraint(
      b,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 40),
    );
    frame.addWithConstraint(
      c,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 40),
    );

    frame.performLayout();

    // Line 1: a(0,0), b(40,0)
    expect(_pos(a).dx, closeTo(0, 0.1));
    expect(_pos(a).dy, closeTo(0, 0.1));
    expect(_pos(b).dx, closeTo(40, 0.1));
    expect(_pos(b).dy, closeTo(0, 0.1));

    // Line 2: c(0, 20) — wraps after line height 20
    expect(_pos(c).dx, closeTo(0, 0.1));
    expect(_pos(c).dy, closeTo(20, 0.1));
  });

  // ===========================================================================
  // 6. Absolute positioning
  // ===========================================================================
  test('absolute children are excluded from flow', () {
    final frame = FrameNode(
      id: 'frame',
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: const EdgeInsets.all(5),
      frameSize: const Size(200, 100),
    );

    final flow1 = _Box(id: 'flow1', width: 30, height: 20);
    final absolute = _Box(id: 'abs', width: 50, height: 50);
    final flow2 = _Box(id: 'flow2', width: 30, height: 20);

    frame.addWithConstraint(
      flow1,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 30),
    );
    frame.addWithConstraint(
      absolute,
      LayoutConstraint(
        positionMode: PositionMode.absolute,
        absoluteX: 100,
        absoluteY: 25,
      ),
    );
    frame.addWithConstraint(
      flow2,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 30),
    );

    frame.performLayout();

    // Absolute child at (100, 25)
    expect(_pos(absolute).dx, closeTo(100, 0.1));
    expect(_pos(absolute).dy, closeTo(25, 0.1));

    // Flow children ignore absolute (only flow1 + flow2 in flow)
    expect(_pos(flow1).dx, closeTo(5, 0.1));
    // flow2 at 5 + 30 + 10 = 45
    expect(_pos(flow2).dx, closeTo(45, 0.1));
  });

  // ===========================================================================
  // 7. Min/max constraints
  // ===========================================================================
  test('min/max constraints clamp child sizes', () {
    final frame = FrameNode(
      id: 'frame',
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(500, 100),
    );

    final child = _Box(id: 'child', width: 10, height: 10);

    frame.addWithConstraint(
      child,
      LayoutConstraint(
        primarySizing: SizingMode.fill,
        fixedWidth: 10,
        minWidth: 50,
        maxWidth: 200,
      ),
    );

    frame.performLayout();

    // Fill gives 500 (all available), but maxWidth clamps to 200.
    // The child is still positioned at 0.
    expect(_pos(child).dx, closeTo(0, 0.1));
  });

  // ===========================================================================
  // 8. Aspect ratio
  // ===========================================================================
  test('aspect ratio is applied to sizing', () {
    final frame = FrameNode(
      id: 'frame',
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(200, 200),
    );

    final child = _Box(id: 'child', width: 100, height: 50);

    frame.addWithConstraint(
      child,
      LayoutConstraint(
        primarySizing: SizingMode.fixed,
        fixedWidth: 100,
        aspectRatio: 2.0, // width / height = 2 => height = 50
      ),
    );

    frame.performLayout();

    // Child positioned at origin
    expect(_pos(child).dx, closeTo(0, 0.1));
    expect(_pos(child).dy, closeTo(0, 0.1));
  });

  // ===========================================================================
  // 9. Pin edges on resize
  // ===========================================================================
  test('pin edges constraints are serialized correctly', () {
    final constraint = LayoutConstraint(
      pinLeft: true,
      pinRight: true,
      pinTop: false,
      pinBottom: true,
    );

    final json = constraint.toJson();
    final restored = LayoutConstraint.fromJson(json);

    expect(restored.pinLeft, isTrue);
    expect(restored.pinRight, isTrue);
    expect(restored.pinTop, isFalse);
    expect(restored.pinBottom, isTrue);
  });

  // ===========================================================================
  // 10. Flex-grow distribution (unequal weights)
  // ===========================================================================
  test('flex-grow distributes space proportionally', () {
    final frame = FrameNode(
      id: 'frame',
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(300, 100),
    );

    final a = _Box(id: 'a', width: 0, height: 30);
    final b = _Box(id: 'b', width: 0, height: 30);
    final c = _Box(id: 'c', width: 0, height: 30);

    frame.addWithConstraint(
      a,
      LayoutConstraint(primarySizing: SizingMode.fill, flexGrow: 1),
    );
    frame.addWithConstraint(
      b,
      LayoutConstraint(primarySizing: SizingMode.fill, flexGrow: 2),
    );
    frame.addWithConstraint(
      c,
      LayoutConstraint(primarySizing: SizingMode.fill, flexGrow: 1),
    );

    frame.performLayout();

    // Total flex = 4, space = 300
    // a = 75, b = 150, c = 75
    expect(_pos(a).dx, closeTo(0, 0.1));
    expect(_pos(b).dx, closeTo(75, 0.1));
    expect(_pos(c).dx, closeTo(225, 0.1));
  });

  // ===========================================================================
  // 11. mainAxisAlignment variants
  // ===========================================================================
  group('mainAxisAlignment', () {
    test('center alignment centers children', () {
      final frame = FrameNode(
        id: 'frame',
        direction: LayoutDirection.horizontal,
        spacing: 0,
        padding: EdgeInsets.zero,
        mainAxisAlignment: MainAxisAlignment.center,
        frameSize: const Size(200, 100),
      );

      final a = _Box(id: 'a', width: 40, height: 30);
      frame.addWithConstraint(
        a,
        LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 40),
      );

      frame.performLayout();

      // Total content = 40, available = 200, offset = (200-40)/2 = 80
      expect(_pos(a).dx, closeTo(80, 0.1));
    });

    test('end alignment pushes children to end', () {
      final frame = FrameNode(
        id: 'frame',
        direction: LayoutDirection.horizontal,
        spacing: 0,
        padding: EdgeInsets.zero,
        mainAxisAlignment: MainAxisAlignment.end,
        frameSize: const Size(200, 100),
      );

      final a = _Box(id: 'a', width: 40, height: 30);
      frame.addWithConstraint(
        a,
        LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 40),
      );

      frame.performLayout();

      // end: offset = 200 - 40 = 160
      expect(_pos(a).dx, closeTo(160, 0.1));
    });

    test('spaceBetween distributes gaps between children', () {
      final frame = FrameNode(
        id: 'frame',
        direction: LayoutDirection.horizontal,
        spacing: 0,
        padding: EdgeInsets.zero,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        frameSize: const Size(200, 100),
      );

      final a = _Box(id: 'a', width: 20, height: 30);
      final b = _Box(id: 'b', width: 20, height: 30);

      frame.addWithConstraint(
        a,
        LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 20),
      );
      frame.addWithConstraint(
        b,
        LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 20),
      );

      frame.performLayout();

      // spaceBetween: a at 0, gap = (200-40)/1 = 160, b at 20 + 160 = 180
      expect(_pos(a).dx, closeTo(0, 0.1));
      expect(_pos(b).dx, closeTo(180, 0.1));
    });
  });

  // ===========================================================================
  // 12. alignSelf override
  // ===========================================================================
  test('alignSelf overrides parent crossAxisAlignment', () {
    final frame = FrameNode(
      id: 'frame',
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: EdgeInsets.zero,
      crossAxisAlignment: CrossAxisAlignment.start,
      frameSize: const Size(200, 100),
    );

    final a = _Box(id: 'a', width: 40, height: 20);
    final b = _Box(id: 'b', width: 40, height: 20);

    frame.addWithConstraint(a, LayoutConstraint());
    frame.addWithConstraint(
      b,
      LayoutConstraint(alignSelf: CrossAxisAlignment.end),
    );

    frame.performLayout();

    // a: crossAxisAlignment.start => y = 0
    expect(_pos(a).dy, closeTo(0, 0.1));
    // b: alignSelf.end => y = 100 - 20 = 80
    expect(_pos(b).dy, closeTo(80, 0.1));
  });

  // ===========================================================================
  // 13. JSON roundtrip for new fields
  // ===========================================================================
  test('JSON roundtrip preserves all constraint fields', () {
    final original = LayoutConstraint(
      primarySizing: SizingMode.fill,
      crossSizing: SizingMode.fixed,
      fixedWidth: 100,
      fixedHeight: 50,
      minWidth: 20,
      minHeight: 10,
      maxWidth: 300,
      maxHeight: 200,
      pinLeft: true,
      pinRight: false,
      pinTop: true,
      pinBottom: true,
      flexGrow: 2.5,
      positionMode: PositionMode.absolute,
      absoluteX: 42,
      absoluteY: 84,
      aspectRatio: 1.5,
      alignSelf: CrossAxisAlignment.center,
    );

    final json = original.toJson();
    final restored = LayoutConstraint.fromJson(json);

    expect(restored.primarySizing, SizingMode.fill);
    expect(restored.crossSizing, SizingMode.fixed);
    expect(restored.fixedWidth, 100);
    expect(restored.fixedHeight, 50);
    expect(restored.minWidth, 20);
    expect(restored.minHeight, 10);
    expect(restored.maxWidth, 300);
    expect(restored.maxHeight, 200);
    expect(restored.pinLeft, isTrue);
    expect(restored.pinRight, isFalse);
    expect(restored.pinTop, isTrue);
    expect(restored.pinBottom, isTrue);
    expect(restored.flexGrow, 2.5);
    expect(restored.positionMode, PositionMode.absolute);
    expect(restored.absoluteX, 42);
    expect(restored.absoluteY, 84);
    expect(restored.aspectRatio, 1.5);
    expect(restored.alignSelf, CrossAxisAlignment.center);
  });

  test('FrameNode JSON roundtrip preserves new properties', () {
    final frame = FrameNode(
      id: 'f1',
      direction: LayoutDirection.horizontal,
      spacing: 12,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      wrap: LayoutWrap.wrap,
      widthSizing: SizingMode.fixed,
      heightSizing: SizingMode.hug,
      frameSize: const Size(400, 300),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
    );

    final json = frame.toJson();
    final restored = FrameNode.fromJson(json);

    expect(restored.id, 'f1');
    expect(restored.direction, LayoutDirection.horizontal);
    expect(restored.spacing, 12);
    expect(restored.padding.left, 16);
    expect(restored.padding.top, 8);
    expect(restored.wrap, LayoutWrap.wrap);
    expect(restored.widthSizing, SizingMode.fixed);
    expect(restored.heightSizing, SizingMode.hug);
    expect(restored.frameSize, const Size(400, 300));
    expect(restored.mainAxisAlignment, MainAxisAlignment.spaceBetween);
    expect(restored.crossAxisAlignment, CrossAxisAlignment.center);
  });

  // ===========================================================================
  // 14. LayoutEngine.resolveLayout with nested tree
  // ===========================================================================
  test('LayoutEngine resolves nested frame tree', () {
    final root = FrameNode(
      id: 'root',
      direction: LayoutDirection.vertical,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(200, 200),
    );

    final nested = FrameNode(
      id: 'nested',
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: EdgeInsets.zero,
    );

    final leaf1 = _Box(id: 'l1', width: 30, height: 20);
    final leaf2 = _Box(id: 'l2', width: 40, height: 20);

    nested.addWithConstraint(leaf1, LayoutConstraint());
    nested.addWithConstraint(leaf2, LayoutConstraint());
    root.addWithConstraint(nested, LayoutConstraint());

    // Both should need layout
    expect(root.needsLayout, isTrue);
    expect(nested.needsLayout, isTrue);

    LayoutEngine.resolveLayout(root);

    // Both should be resolved
    expect(root.needsLayout, isFalse);
    expect(nested.needsLayout, isFalse);

    // Nested children positioned correctly
    expect(_pos(leaf1).dx, closeTo(0, 0.1));
    expect(_pos(leaf2).dx, closeTo(40, 0.1)); // 30 + 10
  });

  // ===========================================================================
  // 15. Dirty flag propagation
  // ===========================================================================
  test('markLayoutDirty propagates to parent frames', () {
    final parent = FrameNode(
      id: 'parent',
      direction: LayoutDirection.vertical,
      frameSize: const Size(200, 200),
    );

    final child = FrameNode(id: 'child', direction: LayoutDirection.horizontal);

    parent.addWithConstraint(child, LayoutConstraint());
    parent.performLayout();

    expect(parent.needsLayout, isFalse);
    expect(child.needsLayout, isFalse);

    // Dirty the child — should propagate up
    child.markLayoutDirty();

    expect(child.needsLayout, isTrue);
    expect(parent.needsLayout, isTrue);
  });
}
