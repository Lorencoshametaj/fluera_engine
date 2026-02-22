import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/nodes/frame_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:nebula_engine/src/core/nodes/shape_node.dart';

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // resizeWithConstraintPropagation
  // ───────────────────────────────────────────────────────────────────────────

  group('resizeWithConstraintPropagation', () {
    /// Helper: create a FrameNode with the given size.
    FrameNode makeFrame(String id, double w, double h) {
      return FrameNode(
        id: NodeId(id),
        name: 'Frame $id',
        frameSize: Size(w, h),
      );
    }

    test('direct children get pin constraints applied', () {
      final parent = makeFrame('parent', 400, 300);
      final child = makeFrame('child', 200, 150);
      parent.add(child);
      parent.setConstraint(
        child.id,
        LayoutConstraint(pinLeft: true, pinRight: true),
      );

      parent.resizeWithConstraintPropagation(Size(400, 300), Size(600, 400));

      // Child should have stretched by dw = 200
      expect(parent.frameSize!.width, 600);
      expect(parent.frameSize!.height, 400);
    });

    test('nested frames cascade resize 2 levels deep', () {
      // grandparent → parent → child
      final grandparent = makeFrame('gp', 400, 300);
      final parent = makeFrame('p', 300, 200);
      final child = makeFrame('c', 200, 100);

      grandparent.add(parent);
      parent.add(child);

      // Pin parent left+right in grandparent
      grandparent.setConstraint(
        parent.id,
        LayoutConstraint(pinLeft: true, pinRight: true),
      );
      // Pin child left+right in parent
      parent.setConstraint(
        child.id,
        LayoutConstraint(pinLeft: true, pinRight: true),
      );

      // Resize grandparent: +100 width
      grandparent.resizeWithConstraintPropagation(
        Size(400, 300),
        Size(500, 300),
      );

      // grandparent is now 500 wide
      expect(grandparent.frameSize!.width, 500);
      // parent should stretch by +100 → 400
      expect(parent.frameSize!.width, 400);
      // child should cascade stretch by +100 → 300
      expect(child.frameSize!.width, 300);
    });

    test('vertical pin stretches height', () {
      final parent = makeFrame('parent', 400, 300);
      final child = makeFrame('child', 200, 150);
      parent.add(child);
      parent.setConstraint(
        child.id,
        LayoutConstraint(pinTop: true, pinBottom: true),
      );

      parent.resizeWithConstraintPropagation(Size(400, 300), Size(400, 500));

      // dh = 200, child should have grown vertically
      expect(child.frameSize!.height, 350);
    });

    test('no pin means no resize', () {
      final parent = makeFrame('parent', 400, 300);
      final child = makeFrame('child', 200, 150);
      parent.add(child);
      // No pins set — default constraint

      parent.resizeWithConstraintPropagation(Size(400, 300), Size(600, 500));

      // Child should NOT have changed
      expect(child.frameSize!.width, 200);
      expect(child.frameSize!.height, 150);
    });

    test('3 levels deep propagation', () {
      final l1 = makeFrame('l1', 500, 400);
      final l2 = makeFrame('l2', 400, 300);
      final l3 = makeFrame('l3', 300, 200);
      final l4 = makeFrame('l4', 200, 100);

      l1.add(l2);
      l2.add(l3);
      l3.add(l4);

      l1.setConstraint(l2.id, LayoutConstraint(pinLeft: true, pinRight: true));
      l2.setConstraint(l3.id, LayoutConstraint(pinLeft: true, pinRight: true));
      l3.setConstraint(l4.id, LayoutConstraint(pinLeft: true, pinRight: true));

      l1.resizeWithConstraintPropagation(Size(500, 400), Size(600, 400));

      // Each level should cascade +100
      expect(l2.frameSize!.width, 500);
      expect(l3.frameSize!.width, 400);
      expect(l4.frameSize!.width, 300);
    });

    test('respects min/max width constraints', () {
      final parent = makeFrame('parent', 400, 300);
      final child = makeFrame('child', 200, 150);
      parent.add(child);
      parent.setConstraint(
        child.id,
        LayoutConstraint(pinLeft: true, pinRight: true, maxWidth: 250),
      );

      parent.resizeWithConstraintPropagation(
        Size(400, 300),
        Size(600, 300), // dw = +200, would make child 400
      );

      // Should be clamped to maxWidth 250
      expect(child.frameSize!.width, 250);
    });
  });
}
