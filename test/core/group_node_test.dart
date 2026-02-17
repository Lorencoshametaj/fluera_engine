import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/nodes/group_node.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('GroupNode children management', () {
    test('add appends child at end', () {
      final group = testGroupNode();
      final c1 = testStrokeNode(id: 'c1');
      final c2 = testStrokeNode(id: 'c2');

      group.add(c1);
      group.add(c2);

      expect(group.children.length, 2);
      expect(group.children.first.id, 'c1');
      expect(group.children.last.id, 'c2');
    });

    test('add sets child parent', () {
      final group = testGroupNode();
      final child = testStrokeNode(id: 'c');
      group.add(child);
      expect(child.parent, group);
    });

    test('insertAt places child at correct index', () {
      final group = testGroupNode();
      group.add(testStrokeNode(id: 'a'));
      group.add(testStrokeNode(id: 'c'));
      group.insertAt(1, testStrokeNode(id: 'b'));

      expect(group.children[0].id, 'a');
      expect(group.children[1].id, 'b');
      expect(group.children[2].id, 'c');
    });

    test('remove detaches child', () {
      final group = testGroupNode();
      final child = testStrokeNode(id: 'rem');
      group.add(child);
      group.remove(child);

      expect(group.children, isEmpty);
      expect(child.parent, isNull);
    });

    test('removeById removes the correct child', () {
      final group = testGroupNode();
      group.add(testStrokeNode(id: 'keep'));
      group.add(testStrokeNode(id: 'remove'));
      group.removeById('remove');

      expect(group.children.length, 1);
      expect(group.children.first.id, 'keep');
    });

    test('removeAt removes child at index', () {
      final group = testGroupNode();
      group.add(testStrokeNode(id: 'a'));
      group.add(testStrokeNode(id: 'b'));
      group.removeAt(0);

      expect(group.children.length, 1);
      expect(group.children.first.id, 'b');
    });

    test('reorder moves child correctly', () {
      final group = testGroupNode();
      group.add(testStrokeNode(id: 'a'));
      group.add(testStrokeNode(id: 'b'));
      group.add(testStrokeNode(id: 'c'));

      group.reorder(0, 2);

      expect(group.children[0].id, 'b');
      expect(group.children[1].id, 'a');
      expect(group.children[2].id, 'c');
    });

    test('clear removes all children', () {
      final group = testGroupNode();
      final c1 = testStrokeNode(id: 'x');
      final c2 = testStrokeNode(id: 'y');
      group.add(c1);
      group.add(c2);

      group.clear();

      expect(group.children, isEmpty);
      expect(c1.parent, isNull);
      expect(c2.parent, isNull);
    });
  });

  group('GroupNode cycle detection', () {
    test('adding a child that would create a cycle throws StateError', () {
      final parent = testGroupNode(id: 'parent');
      final child = GroupNode(id: 'child');
      parent.add(child);

      // Trying to add parent as child of child should throw
      expect(() => child.add(parent), throwsA(isA<StateError>()));
    });

    test('adding self as child throws StateError', () {
      final group = testGroupNode(id: 'self');
      expect(() => group.add(group), throwsA(isA<StateError>()));
    });
  });

  group('GroupNode search', () {
    test('findChild finds direct child by id', () {
      final group = testGroupNode();
      group.add(testStrokeNode(id: 'target'));
      group.add(testStrokeNode(id: 'other'));

      final found = group.findChild('target');
      expect(found, isNotNull);
      expect(found!.id, 'target');
    });

    test('findChild returns null for non-existing id', () {
      final group = testGroupNode();
      expect(group.findChild('nope'), isNull);
    });

    test('findDescendant searches recursively', () {
      final outer = testGroupNode(id: 'outer');
      final inner = GroupNode(id: 'inner');
      final deep = testStrokeNode(id: 'deep');

      outer.add(inner);
      inner.add(deep);

      expect(outer.findDescendant('deep'), isNotNull);
      expect(outer.findDescendant('deep')!.id, 'deep');
    });

    test('findDescendant returns null for missing node', () {
      final group = testGroupNode();
      expect(group.findDescendant('missing'), isNull);
    });
  });

  group('GroupNode transform propagation', () {
    test('invalidateTransformCache propagates to children', () {
      final parent = testGroupNode();
      final child = testStrokeNode(id: 'child');
      parent.add(child);

      parent.localTransform = Matrix4.translationValues(10, 0, 0);
      child.localTransform = Matrix4.translationValues(0, 5, 0);

      // Access worldTransform to cache it
      final _ = child.worldTransform;

      // Change parent transform and invalidate
      parent.localTransform = Matrix4.translationValues(50, 0, 0);
      parent.invalidateTransformCache();

      // Child should now reflect the new parent transform
      final world = child.worldTransform;
      expect(world.getTranslation().x, closeTo(50.0, 0.001));
      expect(world.getTranslation().y, closeTo(5.0, 0.001));
    });
  });

  group('GroupNode localBounds', () {
    test('localBounds is the union of children bounds', () {
      final group = testGroupNode();
      // ShapeNode with start=(0,0), end=(100,100)
      group.add(testShapeNode(id: 'a'));

      final bounds = group.localBounds;
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));
    });

    test('localBounds is Rect.zero when no children', () {
      final group = testGroupNode();
      expect(group.localBounds, Rect.zero);
    });
  });

  group('GroupNode serialization', () {
    test('toJson includes children array', () {
      final group = testGroupNode(id: 'grp');
      group.add(testStrokeNode(id: 'child-1'));

      final json = group.toJson();
      expect(json['nodeType'], 'group');
      expect(json['children'], isA<List>());
      expect((json['children'] as List).length, 1);
    });
  });

  group('GroupNode hit testing', () {
    test('hitTestChildren returns topmost child', () {
      final group = testGroupNode();
      // Bottom: shape at (0,0)-(100,100)
      group.add(testShapeNode(id: 'bottom'));
      // Top: shape at (0,0)-(100,100)
      group.add(testShapeNode(id: 'top'));

      final hit = group.hitTestChildren(const Offset(50, 50));
      // Should return the topmost (last added) child
      expect(hit, isNotNull);
      expect(hit!.id, 'top');
    });

    test('hitTestChildren returns null for miss', () {
      final group = testGroupNode();
      group.add(testShapeNode());

      final hit = group.hitTestChildren(const Offset(500, 500));
      expect(hit, isNull);
    });
  });
}
