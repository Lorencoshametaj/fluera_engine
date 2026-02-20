import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter/material.dart'
    hide CrossAxisAlignment, MainAxisAlignment;
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/nodes/frame_node.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_visitor.dart';
import 'package:nebula_engine/src/systems/layout_engine.dart';
import 'package:nebula_engine/src/systems/responsive_breakpoint.dart';
import 'package:nebula_engine/src/systems/responsive_variant.dart';

// =============================================================================
// Test helpers
// =============================================================================

/// Concrete leaf node with configurable bounds.
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

/// Get the absolute position of a node.
Offset _pos(CanvasNode node) => node.position;

// =============================================================================
// Tests
// =============================================================================

void main() {
  // ===========================================================================
  // 1. Breakpoint matching
  // ===========================================================================
  group('ResponsiveBreakpoint', () {
    test('default presets match correct width ranges', () {
      // Mobile: 0–599
      expect(ResponsiveBreakpoint.mobile.matches(0), isTrue);
      expect(ResponsiveBreakpoint.mobile.matches(375), isTrue);
      expect(ResponsiveBreakpoint.mobile.matches(599), isTrue);
      expect(ResponsiveBreakpoint.mobile.matches(600), isFalse);

      // Tablet: 600–1023
      expect(ResponsiveBreakpoint.tablet.matches(600), isTrue);
      expect(ResponsiveBreakpoint.tablet.matches(768), isTrue);
      expect(ResponsiveBreakpoint.tablet.matches(1023), isTrue);
      expect(ResponsiveBreakpoint.tablet.matches(1024), isFalse);

      // Desktop: 1024–∞
      expect(ResponsiveBreakpoint.desktop.matches(1024), isTrue);
      expect(ResponsiveBreakpoint.desktop.matches(1920), isTrue);
      expect(ResponsiveBreakpoint.desktop.matches(1023), isFalse);
    });

    test('resolve finds first matching breakpoint', () {
      final bp = ResponsiveBreakpoint.resolve(
        768,
        ResponsiveBreakpoint.defaultPresets,
      );
      expect(bp, isNotNull);
      expect(bp!.name, 'tablet');
    });

    test('resolve returns null when no match', () {
      final bp = ResponsiveBreakpoint.resolve(500, [
        const ResponsiveBreakpoint(name: 'large', minWidth: 1000),
      ]);
      expect(bp, isNull);
    });

    test('JSON roundtrip preserves all fields', () {
      const bp = ResponsiveBreakpoint(
        name: 'custom',
        minWidth: 200,
        maxWidth: 499,
      );
      final json = bp.toJson();
      final restored = ResponsiveBreakpoint.fromJson(json);

      expect(restored.name, 'custom');
      expect(restored.minWidth, 200);
      expect(restored.maxWidth, 499);
    });

    test('JSON roundtrip handles infinity maxWidth', () {
      const bp = ResponsiveBreakpoint(name: 'open', minWidth: 0);
      final json = bp.toJson();
      expect(json.containsKey('maxWidth'), isFalse);

      final restored = ResponsiveBreakpoint.fromJson(json);
      expect(restored.maxWidth, double.infinity);
    });

    test('equality works correctly', () {
      const a = ResponsiveBreakpoint(
        name: 'mobile',
        minWidth: 0,
        maxWidth: 599,
      );
      const b = ResponsiveBreakpoint(
        name: 'mobile',
        minWidth: 0,
        maxWidth: 599,
      );
      const c = ResponsiveBreakpoint(name: 'tablet', minWidth: 600);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  // ===========================================================================
  // 2. ResponsiveVariant serialization
  // ===========================================================================
  group('ResponsiveVariant', () {
    test('JSON roundtrip preserves all fields', () {
      final variant = ResponsiveVariant(
        breakpointName: 'mobile',
        direction: LayoutDirection.vertical,
        padding: const EdgeInsets.all(8),
        spacing: 4,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        wrap: LayoutWrap.wrap,
        frameSize: const Size(375, 812),
        widthSizing: SizingMode.fixed,
        heightSizing: SizingMode.hug,
        constraintOverrides: {
          'child1': LayoutConstraint(
            primarySizing: SizingMode.fill,
            flexGrow: 2.0,
          ),
        },
      );

      final json = variant.toJson();
      final restored = ResponsiveVariant.fromJson(json);

      expect(restored.breakpointName, 'mobile');
      expect(restored.direction, LayoutDirection.vertical);
      expect(restored.padding, const EdgeInsets.all(8));
      expect(restored.spacing, 4);
      expect(restored.mainAxisAlignment, MainAxisAlignment.center);
      expect(restored.crossAxisAlignment, CrossAxisAlignment.stretch);
      expect(restored.wrap, LayoutWrap.wrap);
      expect(restored.frameSize, const Size(375, 812));
      expect(restored.widthSizing, SizingMode.fixed);
      expect(restored.heightSizing, SizingMode.hug);
      expect(restored.constraintOverrides.length, 1);
      expect(
        restored.constraintOverrides['child1']!.primarySizing,
        SizingMode.fill,
      );
      expect(restored.constraintOverrides['child1']!.flexGrow, 2.0);
    });

    test('JSON roundtrip preserves null fields (inherit)', () {
      const variant = ResponsiveVariant(
        breakpointName: 'tablet',
        direction: LayoutDirection.horizontal,
        // All other fields null = inherit
      );

      final json = variant.toJson();
      final restored = ResponsiveVariant.fromJson(json);

      expect(restored.breakpointName, 'tablet');
      expect(restored.direction, LayoutDirection.horizontal);
      expect(restored.padding, isNull);
      expect(restored.spacing, isNull);
      expect(restored.mainAxisAlignment, isNull);
      expect(restored.crossAxisAlignment, isNull);
      expect(restored.wrap, isNull);
      expect(restored.frameSize, isNull);
      expect(restored.widthSizing, isNull);
      expect(restored.heightSizing, isNull);
      expect(restored.constraintOverrides, isEmpty);
    });
  });

  // ===========================================================================
  // 3. FrameNode responsive variant API
  // ===========================================================================
  group('FrameNode responsive variants', () {
    test('hasResponsiveVariants starts false', () {
      final frame = FrameNode(id: NodeId('f'), direction: LayoutDirection.horizontal);
      expect(frame.hasResponsiveVariants, isFalse);
    });

    test('add/remove/query variants', () {
      final frame = FrameNode(id: NodeId('f'), direction: LayoutDirection.horizontal);

      const mobileVariant = ResponsiveVariant(
        breakpointName: 'mobile',
        direction: LayoutDirection.vertical,
      );
      const tabletVariant = ResponsiveVariant(
        breakpointName: 'tablet',
        spacing: 16,
      );

      frame.addResponsiveVariant(mobileVariant);
      frame.addResponsiveVariant(tabletVariant);

      expect(frame.hasResponsiveVariants, isTrue);
      expect(frame.responsiveVariants.length, 2);
      expect(frame.variantFor('mobile'), isNotNull);
      expect(frame.variantFor('tablet'), isNotNull);
      expect(frame.variantFor('desktop'), isNull);

      frame.removeResponsiveVariant('tablet');
      expect(frame.responsiveVariants.length, 1);
      expect(frame.variantFor('tablet'), isNull);
    });

    test('variant overrides only non-null fields', () {
      final frame = FrameNode(
        id: NodeId('f'),
        direction: LayoutDirection.horizontal,
        spacing: 10,
        padding: const EdgeInsets.all(16),
        frameSize: const Size(400, 300),
      );

      // Mobile variant: only change direction and spacing
      const mobileVariant = ResponsiveVariant(
        breakpointName: 'mobile',
        direction: LayoutDirection.vertical,
        spacing: 4,
        // padding: null → inherits EdgeInsets.all(16)
      );

      frame.addResponsiveVariant(mobileVariant);
      frame.applyResponsiveOverrides(375); // Mobile width

      expect(frame.direction, LayoutDirection.vertical);
      expect(frame.spacing, 4);
      expect(frame.padding, const EdgeInsets.all(16)); // Inherited

      // Restore base values
      frame.restoreBaseValues();
      expect(frame.direction, LayoutDirection.horizontal);
      expect(frame.spacing, 10);
      expect(frame.padding, const EdgeInsets.all(16));
    });

    test('constraint overrides per child per breakpoint', () {
      final frame = FrameNode(
        id: NodeId('f'),
        direction: LayoutDirection.horizontal,
        spacing: 0,
        padding: EdgeInsets.zero,
        frameSize: const Size(400, 100),
      );

      final childA = _Box(id: NodeId('a'), width: 50, height: 30);
      final childB = _Box(id: NodeId('b'), width: 50, height: 30);

      frame.addWithConstraint(
        childA,
        LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 50),
      );
      frame.addWithConstraint(
        childB,
        LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 50),
      );

      // Mobile: child A becomes fill
      final mobileVariant = ResponsiveVariant(
        breakpointName: 'mobile',
        constraintOverrides: {
          'a': LayoutConstraint(primarySizing: SizingMode.fill, flexGrow: 1),
        },
      );

      frame.addResponsiveVariant(mobileVariant);
      frame.applyResponsiveOverrides(375);

      // Constraint for 'a' should now be fill
      expect(frame.constraintFor('a').primarySizing, SizingMode.fill);
      // Constraint for 'b' should remain fixed
      expect(frame.constraintFor('b').primarySizing, SizingMode.fixed);

      frame.restoreBaseValues();

      // Back to original
      expect(frame.constraintFor('a').primarySizing, SizingMode.fixed);
    });
  });

  // ===========================================================================
  // 4. No-variant fallback (backward compatibility)
  // ===========================================================================
  test('frame without variants behaves identically to original', () {
    final frame = FrameNode(
      id: NodeId('f'),
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: const EdgeInsets.all(8),
      frameSize: const Size(300, 100),
    );

    final a = _Box(id: NodeId('a'), width: 40, height: 30);
    final b = _Box(id: NodeId('b'), width: 60, height: 30);

    frame.addWithConstraint(
      a,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 40),
    );
    frame.addWithConstraint(
      b,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 60),
    );

    frame.performLayout();

    expect(_pos(a).dx, closeTo(8, 0.1));
    expect(_pos(b).dx, closeTo(58, 0.1));
  });

  // ===========================================================================
  // 5. FrameNode JSON roundtrip with responsive data
  // ===========================================================================
  test('FrameNode JSON roundtrip preserves responsive variants', () {
    final frame = FrameNode(
      id: NodeId('responsive-frame'),
      direction: LayoutDirection.horizontal,
      spacing: 12,
      padding: const EdgeInsets.all(16),
      frameSize: const Size(400, 300),
      breakpoints: [
        const ResponsiveBreakpoint(name: 'small', minWidth: 0, maxWidth: 599),
        const ResponsiveBreakpoint(name: 'large', minWidth: 600),
      ],
    );

    frame.addResponsiveVariant(
      const ResponsiveVariant(
        breakpointName: 'small',
        direction: LayoutDirection.vertical,
        spacing: 4,
      ),
    );

    final json = frame.toJson();
    final restored = FrameNode.fromJson(json);

    expect(restored.id, 'responsive-frame');
    expect(restored.breakpoints.length, 2);
    expect(restored.breakpoints[0].name, 'small');
    expect(restored.breakpoints[1].name, 'large');
    expect(restored.hasResponsiveVariants, isTrue);
    expect(restored.variantFor('small'), isNotNull);
    expect(restored.variantFor('small')!.direction, LayoutDirection.vertical);
    expect(restored.variantFor('small')!.spacing, 4);
  });

  // ===========================================================================
  // 6. Layout changes per breakpoint
  // ===========================================================================
  test('layout changes direction and spacing per breakpoint', () {
    final frame = FrameNode(
      id: NodeId('f'),
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: EdgeInsets.zero,
      frameSize: const Size(400, 400),
    );

    final a = _Box(id: NodeId('a'), width: 50, height: 30);
    final b = _Box(id: NodeId('b'), width: 50, height: 30);

    frame.addWithConstraint(
      a,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 50),
    );
    frame.addWithConstraint(
      b,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 50),
    );

    // Mobile: vertical with 4px spacing
    frame.addResponsiveVariant(
      const ResponsiveVariant(
        breakpointName: 'mobile',
        direction: LayoutDirection.vertical,
        spacing: 4,
      ),
    );

    // --- Desktop layout (default) ---
    frame.performLayout();
    // Horizontal: a at 0, b at 50+10=60
    expect(_pos(a).dx, closeTo(0, 0.1));
    expect(_pos(b).dx, closeTo(60, 0.1));
    expect(_pos(a).dy, closeTo(0, 0.1));
    expect(_pos(b).dy, closeTo(0, 0.1));

    // --- Mobile layout ---
    frame.applyResponsiveOverrides(375);
    frame.markLayoutDirty();
    frame.performLayout();
    // Vertical: a at y=0, b at y=30+4=34
    expect(_pos(a).dx, closeTo(0, 0.1));
    expect(_pos(a).dy, closeTo(0, 0.1));
    expect(_pos(b).dx, closeTo(0, 0.1));
    expect(_pos(b).dy, closeTo(34, 0.1));

    frame.restoreBaseValues();
    expect(frame.direction, LayoutDirection.horizontal);
    expect(frame.spacing, 10);
  });

  // ===========================================================================
  // 7. Nested responsive frames
  // ===========================================================================
  test('nested responsive frames each resolve their own breakpoint', () {
    final outer = FrameNode(
      id: NodeId('outer'),
      direction: LayoutDirection.horizontal,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(400, 400),
    );

    final inner = FrameNode(
      id: NodeId('inner'),
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: EdgeInsets.zero,
    );

    final leaf1 = _Box(id: NodeId('l1'), width: 40, height: 20);
    final leaf2 = _Box(id: NodeId('l2'), width: 40, height: 20);

    inner.addWithConstraint(leaf1, LayoutConstraint());
    inner.addWithConstraint(leaf2, LayoutConstraint());
    outer.addWithConstraint(inner, LayoutConstraint());

    // Inner frame switches to vertical on mobile
    inner.addResponsiveVariant(
      const ResponsiveVariant(
        breakpointName: 'mobile',
        direction: LayoutDirection.vertical,
        spacing: 5,
      ),
    );

    // Use LayoutEngine for full tree resolution
    LayoutEngine.resolveResponsiveLayout(outer, 375);

    // Inner should have been laid out as vertical then restored
    // But positions should reflect the mobile layout
    // leaf1 at y=0, leaf2 at y=20+5=25
    expect(_pos(leaf1).dx, closeTo(0, 0.1));
    expect(_pos(leaf1).dy, closeTo(0, 0.1));
    expect(_pos(leaf2).dx, closeTo(0, 0.1));
    expect(_pos(leaf2).dy, closeTo(25, 0.1));

    // Inner direction should be restored to base
    expect(inner.direction, LayoutDirection.horizontal);
    expect(inner.spacing, 10);
  });

  // ===========================================================================
  // 8. resolveResponsiveLayout full tree
  // ===========================================================================
  test('resolveResponsiveLayout applies variants across the entire tree', () {
    final root = FrameNode(
      id: NodeId('root'),
      direction: LayoutDirection.vertical,
      spacing: 0,
      padding: EdgeInsets.zero,
      frameSize: const Size(300, 600),
    );

    final child = _Box(id: NodeId('c1'), width: 100, height: 50);
    root.addWithConstraint(
      child,
      LayoutConstraint(primarySizing: SizingMode.fixed, fixedWidth: 100),
    );

    // On mobile, center align
    root.addResponsiveVariant(
      const ResponsiveVariant(
        breakpointName: 'mobile',
        mainAxisAlignment: MainAxisAlignment.center,
      ),
    );

    LayoutEngine.resolveResponsiveLayout(root, 375);

    // Child should be centered on main axis (vertical):
    // available = 600, childHeight = 50 (from fixed height in bounds),
    // center offset = (600-50)/2 = 275
    expect(_pos(child).dy, closeTo(275, 0.1));

    // Base values restored
    expect(root.mainAxisAlignment, MainAxisAlignment.start);
  });

  // ===========================================================================
  // 9. Edge case: no matching breakpoint
  // ===========================================================================
  test('no matching breakpoint leaves frame unchanged', () {
    final frame = FrameNode(
      id: NodeId('f'),
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: EdgeInsets.zero,
      frameSize: const Size(200, 100),
      breakpoints: [
        const ResponsiveBreakpoint(
          name: 'xlarge',
          minWidth: 2000,
          maxWidth: 3000,
        ),
      ],
    );

    frame.addResponsiveVariant(
      const ResponsiveVariant(
        breakpointName: 'xlarge',
        direction: LayoutDirection.vertical,
      ),
    );

    // Width 375 doesn't match any breakpoint
    frame.applyResponsiveOverrides(375);
    expect(frame.direction, LayoutDirection.horizontal); // Unchanged
    frame.restoreBaseValues(); // Should be a no-op
    expect(frame.direction, LayoutDirection.horizontal);
  });

  // ===========================================================================
  // 10. Custom breakpoints override defaults
  // ===========================================================================
  test('custom breakpoints on frame override default presets', () {
    final frame = FrameNode(
      id: NodeId('f'),
      direction: LayoutDirection.horizontal,
      spacing: 10,
      padding: EdgeInsets.zero,
      frameSize: const Size(200, 100),
      breakpoints: [
        const ResponsiveBreakpoint(name: 'small', minWidth: 0, maxWidth: 399),
        const ResponsiveBreakpoint(name: 'big', minWidth: 400),
      ],
    );

    frame.addResponsiveVariant(
      const ResponsiveVariant(
        breakpointName: 'small',
        direction: LayoutDirection.vertical,
      ),
    );
    frame.addResponsiveVariant(
      const ResponsiveVariant(breakpointName: 'big', spacing: 20),
    );

    // 375 matches 'small' (custom), not 'mobile' (default)
    frame.applyResponsiveOverrides(375);
    expect(frame.direction, LayoutDirection.vertical);
    frame.restoreBaseValues();

    // 500 matches 'big' (custom)
    frame.applyResponsiveOverrides(500);
    expect(frame.spacing, 20);
    expect(frame.direction, LayoutDirection.horizontal); // Unchanged
    frame.restoreBaseValues();
  });

  // ===========================================================================
  // 11. Breakpoint copyWith
  // ===========================================================================
  test('ResponsiveBreakpoint copyWith', () {
    const bp = ResponsiveBreakpoint(name: 'mobile', minWidth: 0, maxWidth: 599);
    final modified = bp.copyWith(name: 'small-mobile', maxWidth: 399);

    expect(modified.name, 'small-mobile');
    expect(modified.minWidth, 0); // Inherited
    expect(modified.maxWidth, 399);
  });

  // ===========================================================================
  // 12. Variant copyWith
  // ===========================================================================
  test('ResponsiveVariant copyWith', () {
    const variant = ResponsiveVariant(
      breakpointName: 'mobile',
      direction: LayoutDirection.vertical,
      spacing: 4,
    );
    final modified = variant.copyWith(spacing: 8);

    expect(modified.breakpointName, 'mobile');
    expect(modified.direction, LayoutDirection.vertical); // Inherited
    expect(modified.spacing, 8);
  });
}
