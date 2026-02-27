import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/assets/asset_dependency_graph.dart';

void main() {
  late AssetDependencyGraph graph;

  setUp(() {
    graph = AssetDependencyGraph();
  });

  tearDown(() {
    graph.dispose();
  });

  // ===========================================================================
  // Link / Unlink
  // ===========================================================================

  group('AssetDependencyGraph - link', () {
    test('links node to asset', () {
      graph.link('node1', 'asset1');
      expect(graph.assetsUsedBy('node1'), contains('asset1'));
      expect(graph.nodesUsing('asset1'), contains('node1'));
    });

    test('idempotent linking', () {
      graph.link('node1', 'asset1');
      graph.link('node1', 'asset1');
      expect(graph.assetsUsedBy('node1').length, 1);
    });

    test('unlinks specific pair', () {
      graph.link('node1', 'asset1');
      graph.unlink('node1', 'asset1');
      expect(graph.assetsUsedBy('node1'), isEmpty);
    });
  });

  // ===========================================================================
  // Unlink node / asset
  // ===========================================================================

  group('AssetDependencyGraph - bulk unlink', () {
    test('unlinkNode removes all assets for a node', () {
      graph.link('node1', 'a1');
      graph.link('node1', 'a2');
      graph.unlinkNode('node1');
      expect(graph.assetsUsedBy('node1'), isEmpty);
    });

    test('unlinkAsset removes all nodes for an asset', () {
      graph.link('n1', 'asset1');
      graph.link('n2', 'asset1');
      graph.unlinkAsset('asset1');
      expect(graph.nodesUsing('asset1'), isEmpty);
    });
  });

  // ===========================================================================
  // Orphaned assets
  // ===========================================================================

  group('AssetDependencyGraph - orphans', () {
    test('finds orphaned assets', () {
      graph.link('node1', 'used_asset');
      final orphans = graph.orphanedAssets({'used_asset', 'unused_asset'});
      expect(orphans, contains('unused_asset'));
      expect(orphans, isNot(contains('used_asset')));
    });
  });

  // ===========================================================================
  // Serialization
  // ===========================================================================

  group('AssetDependencyGraph - toJson', () {
    test('serializes graph', () {
      graph.link('n1', 'a1');
      final json = graph.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });
  });

  // ===========================================================================
  // Clear and toString
  // ===========================================================================

  group('AssetDependencyGraph - clear', () {
    test('clears all links', () {
      graph.link('n1', 'a1');
      graph.clear();
      expect(graph.assetsUsedBy('n1'), isEmpty);
    });

    test('toString is readable', () {
      graph.link('n1', 'a1');
      expect(graph.toString(), isNotEmpty);
    });
  });

  // ===========================================================================
  // BrokenLink
  // ===========================================================================

  group('BrokenLink', () {
    test('toString is readable', () {
      const link = BrokenLink(
        nodeId: 'n1',
        assetId: 'a1',
        reason: BrokenLinkReason.missing,
      );
      expect(link.toString(), isNotEmpty);
    });
  });
}
