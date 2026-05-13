import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/scene_graph_crdt.dart';
import 'package:fluera_engine/src/storage/crdt_persistence.dart';
import 'package:fluera_engine/src/storage/sqlite_storage_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// =============================================================================
// 🔄 CRDT persistence — repository roundtrip + outbox + catch-up
//
// Validates that the v18 schema round-trips every CRDTOperation type, that
// the outbox query exposes only unsent ops in FIFO order, and that
// vector-clock + snapshot reads come back identical to the values written.
// =============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late String dbPath;
  late SqliteStorageAdapter adapter;
  late CRDTPersistence repo;

  setUp(() async {
    final dir =
        await Directory.systemTemp.createTemp('fluera_crdt_persist_');
    dbPath = p.join(dir.path, 'test.db');
    adapter = SqliteStorageAdapter(databasePath: dbPath);
    await adapter.initialize();

    // canvas FK target — every CRDT row references a real canvases row.
    await adapter.database.insert('canvases', {
      'canvas_id': 'canvas_x',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    repo = CRDTPersistence(adapter.database);
  });

  tearDown(() async {
    await adapter.close();
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  test('insertOp → loadAllOps roundtrips every op type in HLC order', () async {
    final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
    final ops = <CRDTOperation>[
      crdt.addNode(
        nodeId: 'n1',
        nodeType: 'stroke',
        properties: {'color': '#ff0000'},
      ),
      crdt.setProperty('n1', 'x', 100.0),
      crdt.moveNode('n1', newSortIndex: 7),
      crdt.removeNode('n1'),
    ];

    for (final op in ops) {
      await repo.insertOp('canvas_x', op);
    }

    final reloaded = await repo.loadAllOps('canvas_x');
    expect(reloaded, hasLength(4));
    expect(
      reloaded.map((o) => o.opId).toList(),
      equals(ops.map((o) => o.opId).toList()),
      reason: 'Ops must reload in HLC order',
    );
    expect(reloaded[0].type, equals(CRDTOpType.addNode));
    expect(reloaded[0].payload['color'], equals('#ff0000'));
  });

  test('insertOp is idempotent on duplicate op_id', () async {
    final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
    final op = crdt.addNode(nodeId: 'n1', nodeType: 'stroke');

    await repo.insertOp('canvas_x', op);
    await repo.insertOp('canvas_x', op);
    await repo.insertOp('canvas_x', op);

    expect(await repo.opCount('canvas_x'), equals(1));
  });

  test('unsentOps surfaces only ops where sent_at IS NULL', () async {
    final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
    final op1 = crdt.addNode(nodeId: 'n1', nodeType: 'stroke');
    final op2 = crdt.addNode(nodeId: 'n2', nodeType: 'shape');
    await repo.insertOp('canvas_x', op1);
    await repo.insertOp('canvas_x', op2);

    expect((await repo.unsentOps('canvas_x')).length, equals(2));

    await repo.markBroadcast(op1.opId);
    final pending = await repo.unsentOps('canvas_x');
    expect(pending, hasLength(1));
    expect(pending.single.operation.opId, equals(op2.opId));
  });

  test('opsSinceHlc returns strictly newer ops', () async {
    int wall = 1000;
    final crdt = CRDTSceneGraph(
      localPeerId: 'peer_a',
      wallClock: () => wall,
    );

    final ops = <CRDTOperation>[];
    for (var i = 0; i < 5; i++) {
      wall += 1; // strictly increasing physical time
      ops.add(crdt.addNode(nodeId: 'n$i', nodeType: 'stroke'));
    }
    for (final op in ops) {
      await repo.insertOp('canvas_x', op);
    }

    // Cut at op[1]'s timestamp — opsSinceHlc must return ops 2..4 (strictly
    // greater than the cut).
    final cut = ops[1].timestamp;
    final later = await repo.opsSinceHlc(
      canvasId: 'canvas_x',
      tsMs: cut.physicalMs,
      counter: cut.counter,
      peerIdTieBreak: cut.peerId,
    );
    expect(later.map((o) => o.opId).toList(),
        equals(ops.sublist(2).map((o) => o.opId).toList()));
  });

  test('vector clock is bumped per peer on each insertOp', () async {
    int wallA = 100;
    int wallB = 200;
    final crdtA = CRDTSceneGraph(
      localPeerId: 'peer_a',
      wallClock: () => wallA,
    );
    final crdtB = CRDTSceneGraph(
      localPeerId: 'peer_b',
      wallClock: () => wallB,
    );

    final opA1 = crdtA.addNode(nodeId: 'a1', nodeType: 'stroke');
    wallA += 1;
    final opA2 = crdtA.addNode(nodeId: 'a2', nodeType: 'stroke');
    final opB1 = crdtB.addNode(nodeId: 'b1', nodeType: 'stroke');

    await repo.insertOp('canvas_x', opA1);
    await repo.insertOp('canvas_x', opA2);
    await repo.insertOp('canvas_x', opB1);

    final clocks = await repo.loadVectorClock('canvas_x');
    expect(clocks.keys, containsAll(['peer_a', 'peer_b']));
    // peer_a's frontier must reflect the most recent op (a2), not a1.
    expect(clocks['peer_a']!.physicalMs, equals(opA2.timestamp.physicalMs));
    expect(clocks['peer_b']!.physicalMs, equals(opB1.timestamp.physicalMs));
  });

  test('saveSnapshot / loadSnapshot roundtrips full CRDT state', () async {
    final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
    crdt.addNode(nodeId: 'n1', nodeType: 'stroke', properties: {'x': 10});
    crdt.addNode(nodeId: 'n2', nodeType: 'shape');
    crdt.setProperty('n1', 'color', '#abcdef');
    final cutHlc = crdt.addNode(nodeId: 'n3', nodeType: 'text').timestamp;

    await repo.saveSnapshot(canvasId: 'canvas_x', graph: crdt, hlc: cutHlc);

    final snap = await repo.loadSnapshot('canvas_x');
    expect(snap, isNotNull);
    expect(snap!.hlc.physicalMs, equals(cutHlc.physicalMs));
    expect(snap.hlc.counter, equals(cutHlc.counter));

    // Rehydrate and verify state matches.
    final restored = CRDTSceneGraph.fromJson(snap.graphJson);
    expect(restored.liveNodeIds, equals(crdt.liveNodeIds));
    expect(
      restored.nodeState('n1')?.getProperty('color'),
      equals('#abcdef'),
    );
  });

  test('clearCanvas wipes ops, clocks and snapshots', () async {
    final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
    await repo.insertOp(
      'canvas_x',
      crdt.addNode(nodeId: 'n1', nodeType: 'stroke'),
    );
    await repo.saveSnapshot(
      canvasId: 'canvas_x',
      graph: crdt,
      hlc: crdt.nodeState('n1')!.nodeType.timestamp,
    );

    await repo.clearCanvas('canvas_x');

    expect(await repo.opCount('canvas_x'), equals(0));
    expect(await repo.loadVectorClock('canvas_x'), isEmpty);
    expect(await repo.loadSnapshot('canvas_x'), isNull);
  });
}
