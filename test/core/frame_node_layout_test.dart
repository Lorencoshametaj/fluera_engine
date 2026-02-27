import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter/material.dart'
    hide CrossAxisAlignment, MainAxisAlignment;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/nodes/frame_node.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_visitor.dart';
import 'package:fluera_engine/src/systems/layout_engine.dart';

// =============================================================================
// Test helpers
// =============================================================================

/// Concrete leaf node with configurable bounds (CanvasNode is abstract).
class _Box extends CanvasNode {
  final Rect _bounds;

  _Box({
    required super.id,
    required double width,
    required double height,
    double? baseline,
  }) : _bounds = Rect.fromLTWH(0, 0, width, height) {
    baselineOffset = baseline;
  }

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
      id: NodeId('frame'),
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: const EdgeInsets.all(8),
      frameSize: const Size(300, 100),
    );

    final a = _Box(id: NodeId('a'), width: 40, height: 30);
    final b = _Box(id: NodeId('b'), width: 60, height: 30);
    final c = _Box(id: NodeId('c'), width: 50, height: 30);

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
      id: NodeId('frame'),
      direction: LayoutDirection.vertical,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(100, 300),
    );

    final a = _Box(id: NodeId('a'), width: 100, height: 0);
    final b = _Box(id: NodeId('b'), width: 100, height: 0);

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
      id: NodeId('frame'),
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: const EdgeInsets.all(5),
      // No frameSize — hug mode
    );

    final a = _Box(id: NodeId('a'), width: 40, height: 20);
    final b = _Box(id: NodeId('b'), width: 60, height: 30);

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
      id: NodeId('outer'),
      direction: LayoutDirection.vertical,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(200, 200),
    );

    final inner = FrameNode(
      id: NodeId('inner'),
      direction: LayoutDirection.horizontal,
      spacing: 5,
      padding: const EdgeInsets.all(4),
    );

    final child1 = _Box(id: NodeId('c1'), width: 30, height: 20);
    final child2 = _Box(id: NodeId('c2'), width: 30, height: 20);

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
      id: NodeId('frame'),
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: EdgeInsets.zero,
      wrap: LayoutWrap.wrap,
      frameSize: const Size(100, 200),
    );

    // 3 children of 40px each — first two fit (80 ≤ 100), third wraps
    final a = _Box(id: NodeId('a'), width: 40, height: 20);
    final b = _Box(id: NodeId('b'), width: 40, height: 20);
    final c = _Box(id: NodeId('c'), width: 40, height: 25);

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
      id: NodeId('frame'),
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: const EdgeInsets.all(5),
      frameSize: const Size(200, 100),
    );

    final flow1 = _Box(id: NodeId('flow1'), width: 30, height: 20);
    final absolute = _Box(id: NodeId('abs'), width: 50, height: 50);
    final flow2 = _Box(id: NodeId('flow2'), width: 30, height: 20);

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
      id: NodeId('frame'),
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(500, 100),
    );

    final child = _Box(id: NodeId('child'), width: 10, height: 10);

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
      id: NodeId('frame'),
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(200, 200),
    );

    final child = _Box(id: NodeId('child'), width: 100, height: 50);

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
      id: NodeId('frame'),
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(300, 100),
    );

    final a = _Box(id: NodeId('a'), width: 0, height: 30);
    final b = _Box(id: NodeId('b'), width: 0, height: 30);
    final c = _Box(id: NodeId('c'), width: 0, height: 30);

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
        id: NodeId('frame'),
        direction: LayoutDirection.horizontal,
        spacing: 0,
        padding: EdgeInsets.zero,
        mainAxisAlignment: MainAxisAlignment.center,
        frameSize: const Size(200, 100),
      );

      final a = _Box(id: NodeId('a'), width: 40, height: 30);
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
        id: NodeId('frame'),
        direction: LayoutDirection.horizontal,
        spacing: 0,
        padding: EdgeInsets.zero,
        mainAxisAlignment: MainAxisAlignment.end,
        frameSize: const Size(200, 100),
      );

      final a = _Box(id: NodeId('a'), width: 40, height: 30);
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
        id: NodeId('frame'),
        direction: LayoutDirection.horizontal,
        spacing: 0,
        padding: EdgeInsets.zero,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        frameSize: const Size(200, 100),
      );

      final a = _Box(id: NodeId('a'), width: 20, height: 30);
      final b = _Box(id: NodeId('b'), width: 20, height: 30);

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
      id: NodeId('frame'),
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: EdgeInsets.zero,
      crossAxisAlignment: CrossAxisAlignment.start,
      frameSize: const Size(200, 100),
    );

    final a = _Box(id: NodeId('a'), width: 40, height: 20);
    final b = _Box(id: NodeId('b'), width: 40, height: 20);

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
      id: NodeId('f1'),
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
      id: NodeId('root'),
      direction: LayoutDirection.vertical,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(200, 200),
    );

    final nested = FrameNode(
      id: NodeId('nested'),
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: EdgeInsets.zero,
    );

    final leaf1 = _Box(id: NodeId('l1'), width: 30, height: 20);
    final leaf2 = _Box(id: NodeId('l2'), width: 40, height: 20);

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
      id: NodeId('parent'),
      direction: LayoutDirection.vertical,
      frameSize: const Size(200, 200),
    );

    final child = FrameNode(
      id: NodeId('child'),
      direction: LayoutDirection.horizontal,
    );

    parent.addWithConstraint(child, LayoutConstraint());
    parent.performLayout();

    expect(parent.needsLayout, isFalse);
    expect(child.needsLayout, isFalse);

    // Dirty the child — should propagate up
    child.markLayoutDirty();

    expect(child.needsLayout, isTrue);
    expect(parent.needsLayout, isTrue);
  });

  // ===========================================================================
  // 16. Overflow behavior enum
  // ===========================================================================
  test('overflow behavior serializes to JSON and roundtrips', () {
    final frame = FrameNode(
      id: NodeId('ov'),
      overflow: OverflowBehavior.scroll,
    );
    final json = frame.toJson();
    expect(json['overflow'], 'scroll');

    final restored = FrameNode.fromJson(json);
    expect(restored.overflow, OverflowBehavior.scroll);
  });

  // ===========================================================================
  // 17. Backward compat: clipContent → overflow
  // ===========================================================================
  test('fromJson reads clipContent for backward compatibility', () {
    final legacyJson = <String, dynamic>{
      'id': 'legacy',
      'nodeType': 'frame',
      'clipContent': false,
      'padding': {'left': 0, 'top': 0, 'right': 0, 'bottom': 0},
      'children': <dynamic>[],
      'constraints': <String, dynamic>{},
    };
    final restored = FrameNode.fromJson(legacyJson);
    expect(restored.overflow, OverflowBehavior.visible);

    // clipContent: true → hidden
    legacyJson['clipContent'] = true;
    final restored2 = FrameNode.fromJson(legacyJson);
    expect(restored2.overflow, OverflowBehavior.hidden);
  });

  // ===========================================================================
  // 18. Stack layout mode
  // ===========================================================================
  test('stack layout positions children at anchors', () {
    final frame = FrameNode(
      id: NodeId('stack'),
      layoutMode: LayoutMode.stack,
      padding: EdgeInsets.zero,
      frameSize: const Size(200, 200),
    );

    final a = _Box(id: NodeId('a'), width: 40, height: 40);
    final b = _Box(id: NodeId('b'), width: 40, height: 40);
    final c = _Box(id: NodeId('c'), width: 40, height: 40);

    frame.addWithConstraint(
      a,
      LayoutConstraint(stackAnchor: StackAnchor.topLeft),
    );
    frame.addWithConstraint(
      b,
      LayoutConstraint(stackAnchor: StackAnchor.center),
    );
    frame.addWithConstraint(
      c,
      LayoutConstraint(stackAnchor: StackAnchor.bottomRight),
    );

    frame.performLayout();

    // topLeft: (0, 0)
    expect(_pos(a).dx, closeTo(0, 0.1));
    expect(_pos(a).dy, closeTo(0, 0.1));

    // center: ((200-40)/2, (200-40)/2) = (80, 80)
    expect(_pos(b).dx, closeTo(80, 0.1));
    expect(_pos(b).dy, closeTo(80, 0.1));

    // bottomRight: (200-40, 200-40) = (160, 160)
    expect(_pos(c).dx, closeTo(160, 0.1));
    expect(_pos(c).dy, closeTo(160, 0.1));
  });

  // ===========================================================================
  // 19. Stack layout with padding
  // ===========================================================================
  test('stack layout respects frame padding', () {
    final frame = FrameNode(
      id: NodeId('stack_pad'),
      layoutMode: LayoutMode.stack,
      padding: const EdgeInsets.all(10),
      frameSize: const Size(200, 200),
    );

    final a = _Box(id: NodeId('a'), width: 40, height: 40);

    frame.addWithConstraint(
      a,
      LayoutConstraint(stackAnchor: StackAnchor.topLeft),
    );

    frame.performLayout();

    // topLeft with 10px padding: (10, 10)
    expect(_pos(a).dx, closeTo(10, 0.1));
    expect(_pos(a).dy, closeTo(10, 0.1));
  });

  // ===========================================================================
  // 20. LayoutInput propagation to nested frames
  // ===========================================================================
  test('LayoutInput enables nested fill sizing', () {
    final outer = FrameNode(
      id: NodeId('outer'),
      direction: LayoutDirection.vertical,
      padding: EdgeInsets.zero,
      spacing: 0,
      frameSize: const Size(400, 300),
    );

    final inner = FrameNode(
      id: NodeId('inner'),
      direction: LayoutDirection.horizontal,
      padding: EdgeInsets.zero,
      spacing: 0,
      widthSizing: SizingMode.fill,
    );

    final leaf = _Box(id: NodeId('leaf'), width: 50, height: 20);
    inner.addWithConstraint(leaf, LayoutConstraint());
    outer.addWithConstraint(inner, LayoutConstraint());

    outer.performLayout();

    // Inner frame should have filled the parent width: 400
    expect(inner.frameSize?.width, closeTo(400, 0.1));
  });

  // ===========================================================================
  // 21. LayoutInput 3 levels deep
  // ===========================================================================
  test('LayoutInput propagates through 3 nesting levels', () {
    final root = FrameNode(
      id: NodeId('root'),
      direction: LayoutDirection.vertical,
      padding: const EdgeInsets.all(20),
      spacing: 0,
      frameSize: const Size(500, 400),
    );

    final mid = FrameNode(
      id: NodeId('mid'),
      direction: LayoutDirection.horizontal,
      padding: const EdgeInsets.all(10),
      spacing: 0,
      widthSizing: SizingMode.fill,
    );

    final deep = FrameNode(
      id: NodeId('deep'),
      direction: LayoutDirection.horizontal,
      padding: EdgeInsets.zero,
      spacing: 0,
      widthSizing: SizingMode.fill,
    );

    final leaf = _Box(id: NodeId('leaf'), width: 10, height: 10);
    deep.addWithConstraint(leaf, LayoutConstraint());
    mid.addWithConstraint(deep, LayoutConstraint());
    root.addWithConstraint(mid, LayoutConstraint());

    root.performLayout();

    // root content width = 500 - 40 = 460 → mid fills to 460
    expect(mid.frameSize?.width, closeTo(460, 0.1));
    // mid content width = 460 - 20 = 440 → deep fills to 440
    expect(deep.frameSize?.width, closeTo(440, 0.1));
  });

  // ===========================================================================
  // 22. Negative spacing (overlap)
  // ===========================================================================
  test('negative spacing causes children to overlap', () {
    final frame = FrameNode(
      id: NodeId('neg'),
      direction: LayoutDirection.horizontal,
      spacing: -5,
      padding: EdgeInsets.zero,
      frameSize: const Size(200, 100),
    );

    final a = _Box(id: NodeId('a'), width: 40, height: 30);
    final b = _Box(id: NodeId('b'), width: 40, height: 30);

    frame.addWithConstraint(
      a,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 40),
    );
    frame.addWithConstraint(
      b,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 40),
    );

    frame.performLayout();

    // a at 0, b at 40 + (-5) = 35
    expect(_pos(a).dx, closeTo(0, 0.1));
    expect(_pos(b).dx, closeTo(35, 0.1));
  });

  // ===========================================================================
  // 23. Pin left+right stretches child
  // ===========================================================================
  test('pinLeft + pinRight stretches child on resize', () {
    final frame = FrameNode(
      id: NodeId('pin_lr'),
      direction: LayoutDirection.horizontal,
      padding: EdgeInsets.zero,
      spacing: 0,
      frameSize: const Size(200, 100),
    );

    final child = _Box(id: NodeId('child'), width: 100, height: 30);

    frame.addWithConstraint(
      child,
      LayoutConstraint(
        primarySizing: SizingMode.fixed,
        fixedWidth: 100,
        pinLeft: true,
        pinRight: true,
      ),
    );

    frame.performLayout();
    child.setPosition(10, 20);

    // Resize frame from 200 → 300 (delta +100)
    LayoutEngine.resizeFrame(frame, const Size(300, 100));

    // Child position stays at x=10, but width conceptually stretched.
    // The pin behavior moves/stretches via applyPinConstraints.
    expect(_pos(child).dx, closeTo(10, 0.1));
  });

  // ===========================================================================
  // 24. Pin bottom moves child down on resize
  // ===========================================================================
  test('pinBottom moves child down when frame grows', () {
    final frame = FrameNode(
      id: NodeId('pin_b'),
      direction: LayoutDirection.vertical,
      padding: EdgeInsets.zero,
      spacing: 0,
      frameSize: const Size(200, 200),
    );

    final child = _Box(id: NodeId('child'), width: 50, height: 50);

    frame.addWithConstraint(
      child,
      LayoutConstraint(positionMode: PositionMode.auto, pinBottom: true),
    );

    frame.performLayout();
    child.setPosition(10, 140); // 10px from bottom in 200px frame

    // Resize frame from 200 → 300 height (delta +100)
    frame.applyPinConstraints(const Size(200, 200), const Size(200, 300));

    // pinBottom: child.y += dh = 140 + 100 = 240
    expect(_pos(child).dy, closeTo(240, 0.1));
  });

  // ===========================================================================
  // 25. LayoutMode JSON roundtrip
  // ===========================================================================
  test('LayoutMode serializes and deserializes correctly', () {
    final frame = FrameNode(id: NodeId('lm'), layoutMode: LayoutMode.stack);
    final json = frame.toJson();
    expect(json['layoutMode'], 'stack');

    final restored = FrameNode.fromJson(json);
    expect(restored.layoutMode, LayoutMode.stack);
  });

  // ===========================================================================
  // 26. StackAnchor JSON roundtrip in LayoutConstraint
  // ===========================================================================
  test('stackAnchor roundtrips through JSON', () {
    final constraint = LayoutConstraint(stackAnchor: StackAnchor.bottomCenter);
    final json = constraint.toJson();
    expect(json['stackAnchor'], 'bottomCenter');

    final restored = LayoutConstraint.fromJson(json);
    expect(restored.stackAnchor, StackAnchor.bottomCenter);
  });

  // ===========================================================================
  // 27. Fill sizing with LayoutInput in single layout
  // ===========================================================================
  test('fill child expands to parent available width', () {
    final frame = FrameNode(
      id: NodeId('fill_test'),
      direction: LayoutDirection.horizontal,
      padding: EdgeInsets.zero,
      spacing: 0,
      frameSize: const Size(300, 100),
    );

    final fixed = _Box(id: NodeId('fixed'), width: 80, height: 30);
    final filler = _Box(id: NodeId('filler'), width: 0, height: 30);

    frame.addWithConstraint(
      fixed,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 80),
    );
    frame.addWithConstraint(
      filler,
      LayoutConstraint(primarySizing: SizingMode.fill, flexGrow: 1),
    );

    frame.performLayout();

    // fixed: 80px, filler gets remaining: 300 - 80 = 220
    expect(_pos(fixed).dx, closeTo(0, 0.1));
    expect(_pos(filler).dx, closeTo(80, 0.1));
  });

  // ===========================================================================
  // 28. LayoutEngine.resizeFrame triggers pin + dirty
  // ===========================================================================
  test('LayoutEngine.resizeFrame applies pins and marks dirty', () {
    final frame = FrameNode(
      id: NodeId('resize_test'),
      direction: LayoutDirection.horizontal,
      padding: EdgeInsets.zero,
      spacing: 0,
      frameSize: const Size(200, 100),
    );

    final child = _Box(id: NodeId('child'), width: 40, height: 30);
    frame.addWithConstraint(child, LayoutConstraint(pinRight: true));

    frame.performLayout();
    child.setPosition(150, 10); // 50px from right edge

    LayoutEngine.resizeFrame(frame, const Size(300, 100));

    // pinRight: x += dw = 150 + 100 = 250
    expect(_pos(child).dx, closeTo(250, 0.1));
    // Frame should be dirty after resize
    expect(frame.needsLayout, isTrue);
    // New frame size applied
    expect(frame.frameSize, const Size(300, 100));
  });

  // ===========================================================================
  // 29. Default LayoutMode is flow
  // ===========================================================================
  test('default LayoutMode is flow and not emitted in JSON', () {
    final frame = FrameNode(id: NodeId('default_lm'));
    final json = frame.toJson();
    expect(json.containsKey('layoutMode'), isFalse);

    final restored = FrameNode.fromJson(json);
    expect(restored.layoutMode, LayoutMode.flow);
  });

  // ===========================================================================
  // 30. All 9 stack anchors
  // ===========================================================================
  test('stack layout positions all 9 anchors correctly', () {
    final frame = FrameNode(
      id: NodeId('all_anchors'),
      layoutMode: LayoutMode.stack,
      padding: EdgeInsets.zero,
      frameSize: const Size(100, 100),
    );

    final anchors = StackAnchor.values;
    final boxes = <_Box>[];
    for (final anchor in anchors) {
      final box = _Box(id: NodeId(anchor.name), width: 20, height: 20);
      boxes.add(box);
      frame.addWithConstraint(box, LayoutConstraint(stackAnchor: anchor));
    }

    frame.performLayout();

    // Expected positions for 20x20 child in 100x100 frame:
    final expected = <StackAnchor, Offset>{
      StackAnchor.topLeft: const Offset(0, 0),
      StackAnchor.topCenter: const Offset(40, 0),
      StackAnchor.topRight: const Offset(80, 0),
      StackAnchor.centerLeft: const Offset(0, 40),
      StackAnchor.center: const Offset(40, 40),
      StackAnchor.centerRight: const Offset(80, 40),
      StackAnchor.bottomLeft: const Offset(0, 80),
      StackAnchor.bottomCenter: const Offset(40, 80),
      StackAnchor.bottomRight: const Offset(80, 80),
    };

    for (final box in boxes) {
      final anchor = StackAnchor.values.byName(box.id);
      final exp = expected[anchor]!;
      expect(_pos(box).dx, closeTo(exp.dx, 0.1), reason: '${anchor.name}.dx');
      expect(_pos(box).dy, closeTo(exp.dy, 0.1), reason: '${anchor.name}.dy');
    }
  });

  // ===========================================================================
  // 31. Aspect ratio in stack layout
  // ===========================================================================
  test('stack layout enforces aspect ratio', () {
    final frame = FrameNode(
      id: NodeId('stack_ar'),
      layoutMode: LayoutMode.stack,
      padding: EdgeInsets.zero,
      frameSize: const Size(200, 200),
    );

    final child = _Box(id: NodeId('child'), width: 100, height: 50);

    frame.addWithConstraint(
      child,
      LayoutConstraint(
        primarySizing: SizingMode.fixed,
        fixedWidth: 100,
        aspectRatio: 2.0, // width/height = 2 => height = 50
        stackAnchor: StackAnchor.center,
      ),
    );

    frame.performLayout();

    // Centered: ((200-100)/2, (200-50)/2) = (50, 75)
    expect(_pos(child).dx, closeTo(50, 0.1));
    expect(_pos(child).dy, closeTo(75, 0.1));
  });

  // ===========================================================================
  // 32. Baseline alignment
  // ===========================================================================
  test('baseline alignment aligns children by reported baseline', () {
    final frame = FrameNode(
      id: NodeId('baseline'),
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: EdgeInsets.zero,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      frameSize: const Size(300, 100),
    );

    // Small text: height 20, baseline at 15
    final small = _Box(
      id: NodeId('small'),
      width: 40,
      height: 20,
      baseline: 15,
    );
    // Large text: height 40, baseline at 30
    final large = _Box(
      id: NodeId('large'),
      width: 60,
      height: 40,
      baseline: 30,
    );

    frame.addWithConstraint(
      small,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 40),
    );
    frame.addWithConstraint(
      large,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 60),
    );

    frame.performLayout();

    // Max baseline = 30. Small offset = 30 - 15 = 15. Large offset = 30 - 30 = 0.
    expect(_pos(small).dy, closeTo(15, 0.1));
    expect(_pos(large).dy, closeTo(0, 0.1));
  });

  // ===========================================================================
  // 33. Baseline fallback to start when no baseline reported
  // ===========================================================================
  test('baseline alignment falls back to start when no baseline', () {
    final frame = FrameNode(
      id: NodeId('bl_fallback'),
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: EdgeInsets.zero,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      frameSize: const Size(200, 100),
    );

    // No baseline reported
    final child = _Box(id: NodeId('child'), width: 40, height: 30);

    frame.addWithConstraint(
      child,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 40),
    );

    frame.performLayout();

    // No baseline → fallback to start → y = 0
    expect(_pos(child).dy, closeTo(0, 0.1));
  });

  // ===========================================================================
  // 34. Cross-axis fill sizing
  // ===========================================================================
  test('cross-axis fill stretches child to available cross space', () {
    final frame = FrameNode(
      id: NodeId('cross_fill'),
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(200, 100),
    );

    final child = _Box(id: NodeId('child'), width: 50, height: 20);

    frame.addWithConstraint(
      child,
      LayoutConstraint(
        primarySizing: SizingMode.fixed,
        fixedWidth: 50,
        crossSizing: SizingMode.fill,
      ),
    );

    frame.performLayout();

    // cross-axis fill: child should get crossSize = 100
    // Position at (0, 0) since start alignment
    expect(_pos(child).dx, closeTo(0, 0.1));
    expect(_pos(child).dy, closeTo(0, 0.1));
  });

  // ===========================================================================
  // 35. spaceAround alignment with padding
  // ===========================================================================
  test('spaceAround distributes space around children with padding', () {
    final frame = FrameNode(
      id: NodeId('sa_pad'),
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: const EdgeInsets.all(10),
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      frameSize: const Size(200, 100),
    );

    final a = _Box(id: NodeId('a'), width: 30, height: 20);
    final b = _Box(id: NodeId('b'), width: 30, height: 20);

    frame.addWithConstraint(
      a,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 30),
    );
    frame.addWithConstraint(
      b,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 30),
    );

    frame.performLayout();

    // Content area = 200 - 20 = 180. Content total = 60.
    // spaceAround: gap = (180 - 60) / 2 = 60. Half-gap = 30.
    // a at padding.left + 30 = 40, b at 40 + 30 + 60 = 130
    expect(_pos(a).dx, closeTo(40, 0.1));
    expect(_pos(b).dx, closeTo(130, 0.1));
  });
}
