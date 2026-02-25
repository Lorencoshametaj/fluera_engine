import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph_snapshot.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';

import '../helpers/test_helpers.dart';

void main() {
  // ===========================================================================
  // DiffEntry
  // ===========================================================================

  group('DiffEntry', () {
    test('toString for added', () {
      final entry = DiffEntry(
        nodeId: 'n1',
        type: DiffType.added,
        nodeName: 'Shape',
      );
      expect(entry.toString(), contains('n1'));
      expect(entry.toString(), contains('Shape'));
    });

    test('toString for removed', () {
      final entry = DiffEntry(nodeId: 'n2', type: DiffType.removed);
      expect(entry.toString(), contains('n2'));
    });

    test('toString for modified', () {
      final entry = DiffEntry(
        nodeId: 'n3',
        type: DiffType.modified,
        nodeName: 'Stroke',
      );
      expect(entry.toString(), contains('n3'));
    });

    test('toString for moved', () {
      final entry = DiffEntry(
        nodeId: 'n4',
        type: DiffType.moved,
        oldParentId: 'p1',
        newParentId: 'p2',
      );
      expect(entry.toString(), contains('p1'));
      expect(entry.toString(), contains('p2'));
    });

    test('toJson includes all set fields', () {
      final entry = DiffEntry(
        nodeId: 'n1',
        type: DiffType.modified,
        nodeName: 'Test',
        oldHash: 100,
        newHash: 200,
      );
      final json = entry.toJson();
      expect(json['nodeId'], 'n1');
      expect(json['type'], 'modified');
      expect(json['name'], 'Test');
      expect(json['oldHash'], 100);
      expect(json['newHash'], 200);
    });

    test('toJson omits null fields', () {
      final entry = DiffEntry(nodeId: 'n1', type: DiffType.added);
      final json = entry.toJson();
      expect(json.containsKey('name'), false);
      expect(json.containsKey('oldParent'), false);
    });
  });

  // ===========================================================================
  // SceneGraphDiff
  // ===========================================================================

  group('SceneGraphDiff', () {
    test('isEmpty when no entries', () {
      final diff = SceneGraphDiff(entries: [], oldVersion: 1, newVersion: 2);
      expect(diff.isEmpty, true);
      expect(diff.length, 0);
    });

    test('filters by type correctly', () {
      final diff = SceneGraphDiff(
        entries: [
          DiffEntry(nodeId: 'a', type: DiffType.added),
          DiffEntry(nodeId: 'r', type: DiffType.removed),
          DiffEntry(nodeId: 'm', type: DiffType.modified),
          DiffEntry(nodeId: 'v', type: DiffType.moved),
        ],
        oldVersion: 1,
        newVersion: 2,
      );

      expect(diff.additions, hasLength(1));
      expect(diff.removals, hasLength(1));
      expect(diff.modifications, hasLength(1));
      expect(diff.moves, hasLength(1));
    });

    test('summary is descriptive', () {
      final diff = SceneGraphDiff(
        entries: [
          DiffEntry(nodeId: 'a', type: DiffType.added),
          DiffEntry(nodeId: 'b', type: DiffType.added),
        ],
        oldVersion: 1,
        newVersion: 2,
      );
      expect(diff.summary, contains('2 added'));
    });

    test('toJson contains expected keys', () {
      final diff = SceneGraphDiff(entries: [], oldVersion: 1, newVersion: 3);
      final json = diff.toJson();
      expect(json['oldVersion'], 1);
      expect(json['newVersion'], 3);
      expect(json['summary'], isA<String>());
      expect(json['entries'], isA<List>());
    });

    test('toString is descriptive', () {
      final diff = SceneGraphDiff(entries: [], oldVersion: 1, newVersion: 2);
      expect(diff.toString(), contains('v1'));
      expect(diff.toString(), contains('v2'));
    });
  });

  // ===========================================================================
  // SceneGraphSnapshot — Capture & Diff
  // ===========================================================================

  group('SceneGraphSnapshot', () {
    test('capture records all nodes', () {
      final sg = SceneGraph();
      final layer = testLayerNode(
        id: NodeId('L1'),
        children: [testStrokeNode(id: 'S1'), testShapeNode(id: 'SH1')],
      );
      sg.addLayer(layer);

      final snap = SceneGraphSnapshot.capture(sg);

      // root + layer + 2 children
      expect(snap.nodeCount, greaterThanOrEqualTo(3));
      expect(snap.nodeIds, containsAll(['L1', 'S1', 'SH1']));
    });

    test('capture records version', () {
      final sg = SceneGraph();
      final snap = SceneGraphSnapshot.capture(sg);
      expect(snap.version, sg.version);
    });

    test('diff detects additions', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));
      sg.addLayer(layer);

      final snapBefore = SceneGraphSnapshot.capture(sg);

      layer.add(testStrokeNode(id: 'new_stroke'));
      final snapAfter = SceneGraphSnapshot.capture(sg);

      final diff = snapBefore.diff(snapAfter);

      expect(diff.additions.any((e) => e.nodeId == 'new_stroke'), true);
    });

    test('diff detects removals', () {
      final sg = SceneGraph();
      final child = testStrokeNode(id: 'to_remove');
      final layer = testLayerNode(id: NodeId('L1'), children: [child]);
      sg.addLayer(layer);

      final snapBefore = SceneGraphSnapshot.capture(sg);

      layer.remove(child);
      final snapAfter = SceneGraphSnapshot.capture(sg);

      final diff = snapBefore.diff(snapAfter);

      expect(diff.removals.any((e) => e.nodeId == 'to_remove'), true);
    });

    test('diff detects modifications via content hash', () {
      final sg = SceneGraph();
      final node = testStrokeNode(id: 'modifiable');
      final layer = testLayerNode(id: NodeId('L1'), children: [node]);
      sg.addLayer(layer);

      final snapBefore = SceneGraphSnapshot.capture(sg);

      // Modifying a property changes the content hash
      node.name = 'Changed Name';
      final snapAfter = SceneGraphSnapshot.capture(sg);

      final diff = snapBefore.diff(snapAfter);

      expect(diff.modifications.any((e) => e.nodeId == 'modifiable'), true);
    });

    test('diff is empty for identical snapshots', () {
      final sg = SceneGraph();
      final layer = testLayerNode(
        id: NodeId('L1'),
        children: [testStrokeNode(id: 'S1')],
      );
      sg.addLayer(layer);

      final snap1 = SceneGraphSnapshot.capture(sg);
      final snap2 = SceneGraphSnapshot.capture(sg);

      final diff = snap1.diff(snap2);
      expect(diff.isEmpty, true);
    });

    test('toJson contains expected keys', () {
      final sg = SceneGraph();
      final snap = SceneGraphSnapshot.capture(sg);
      final json = snap.toJson();

      expect(json, containsPair('version', isA<int>()));
      expect(json, containsPair('timestamp', isA<String>()));
      expect(json, containsPair('nodeCount', isA<int>()));
    });
  });
}
