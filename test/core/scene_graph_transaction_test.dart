import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/fluera_engine.dart';

/// Helper to create a layer node for testing.
LayerNode _testLayerNode({String? id, String name = 'TestLayer'}) {
  return LayerNode(
    id: NodeId(id ?? 'test_${DateTime.now().microsecondsSinceEpoch}'),
    name: name,
  );
}

void main() {
  group('SceneGraphTransaction', () {
    late SceneGraph graph;

    setUp(() {
      graph = SceneGraph();
    });

    tearDown(() {
      graph.dispose();
    });

    test('beginTransaction returns a transaction object', () {
      final txn = graph.beginTransaction();
      expect(txn, isNotNull);
      expect(txn.isFinished, isFalse);
      expect(graph.isTransacting, isTrue);
      txn.commit();
    });

    test('commit makes mutations persistent', () {
      final layer = _testLayerNode(name: 'A');
      final txn = graph.beginTransaction();
      graph.addLayer(layer);
      txn.commit();

      expect(graph.layers.length, equals(1));
      expect(graph.layers.first.name, equals('A'));
      expect(txn.isFinished, isTrue);
      expect(graph.isTransacting, isFalse);
    });

    test('rollback restores graph to pre-transaction state', () {
      final layerBefore = _testLayerNode(name: 'Before');
      graph.addLayer(layerBefore);
      expect(graph.layers.length, equals(1));

      final txn = graph.beginTransaction();
      graph.addLayer(_testLayerNode(name: 'During'));
      expect(graph.layers.length, equals(2));

      txn.rollback();
      expect(graph.layers.length, equals(1));
      expect(graph.layers.first.name, equals('Before'));
      expect(graph.isTransacting, isFalse);
    });

    test('defers observer notifications during transaction', () {
      final events = <String>[];
      final observer = _SpyObserver(events);
      graph.addObserver(observer);

      final txn = graph.beginTransaction();
      final layer = _testLayerNode(name: 'Deferred');
      graph.addLayer(layer);

      // During transaction — notifications are deferred
      expect(events, isEmpty);

      txn.commit();

      // After commit — notifications are flushed
      expect(events, isNotEmpty);
      expect(events.first, contains('added'));
    });

    test('rollback discards deferred notifications', () {
      final events = <String>[];
      final observer = _SpyObserver(events);
      graph.addObserver(observer);

      final txn = graph.beginTransaction();
      graph.addLayer(_testLayerNode(name: 'WillRollback'));
      txn.rollback();

      // After rollback — no notifications dispatched
      expect(events, isEmpty);
    });

    test('re-entrant beginTransaction throws', () {
      graph.beginTransaction();
      expect(() => graph.beginTransaction(), throwsA(isA<StateError>()));
      // Clean up
      graph.commitTransaction();
    });

    test('commit on already committed transaction throws', () {
      final txn = graph.beginTransaction();
      txn.commit();
      expect(() => txn.commit(), throwsA(isA<StateError>()));
    });

    test('rollback on already committed transaction throws', () {
      final txn = graph.beginTransaction();
      txn.commit();
      expect(() => txn.rollback(), throwsA(isA<StateError>()));
    });

    test('commit on already rolled-back transaction throws', () {
      final txn = graph.beginTransaction();
      txn.rollback();
      expect(() => txn.commit(), throwsA(isA<StateError>()));
    });

    test('commitTransaction throws when no transaction active', () {
      expect(() => graph.commitTransaction(), throwsA(isA<StateError>()));
    });

    test('multiple mutations within a single transaction', () {
      final txn = graph.beginTransaction();
      graph.addLayer(_testLayerNode(name: 'L1'));
      graph.addLayer(_testLayerNode(name: 'L2'));
      graph.addLayer(_testLayerNode(name: 'L3'));
      txn.commit();

      expect(graph.layers.length, equals(3));
    });

    test('rollback after multiple mutations restores empty state', () {
      final txn = graph.beginTransaction();
      graph.addLayer(_testLayerNode(name: 'L1'));
      graph.addLayer(_testLayerNode(name: 'L2'));
      txn.rollback();

      expect(graph.layers, isEmpty);
    });

    test('transaction snapshot is captured at begin time', () {
      graph.addLayer(_testLayerNode(name: 'Existing'));
      final txn = graph.beginTransaction();

      // Snapshot should contain the existing layer
      expect(txn.snapshot.nodeCount, greaterThan(0));
      txn.commit();
    });

    test(
      'EventBus interaction — paused during transaction, resumed on commit',
      () {
        final bus = EngineEventBus();
        graph.connectEventBus(bus);

        final txn = graph.beginTransaction();
        expect(bus.isPaused, isTrue);

        txn.commit();
        expect(bus.isPaused, isFalse);

        bus.dispose();
      },
    );

    test('EventBus interaction — resumed on rollback', () {
      final bus = EngineEventBus();
      graph.connectEventBus(bus);

      final txn = graph.beginTransaction();
      expect(bus.isPaused, isTrue);

      txn.rollback();
      expect(bus.isPaused, isFalse);

      bus.dispose();
    });
  });
}

/// Spy observer that records event descriptions.
class _SpyObserver extends SceneGraphObserver {
  final List<String> log;
  _SpyObserver(this.log);

  @override
  void onNodeAdded(CanvasNode node, String parentId) =>
      log.add('added:${node.id}');

  @override
  void onNodeRemoved(CanvasNode node, String parentId) =>
      log.add('removed:${node.id}');

  @override
  void onNodeChanged(CanvasNode node, String property) =>
      log.add('changed:${node.id}:$property');

  @override
  void onNodeReordered(String parentId, int oldIndex, int newIndex) =>
      log.add('reordered:$parentId:$oldIndex->$newIndex');
}
