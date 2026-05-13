import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/crdt_layer_controller_applier.dart';
import 'package:fluera_engine/src/collaboration/crdt_layer_controller_observer.dart';
import 'package:fluera_engine/src/collaboration/scene_graph_crdt.dart';
import 'package:fluera_engine/src/layers/layer_controller.dart';
import 'package:fluera_engine/src/storage/crdt_persistence.dart';
import 'package:fluera_engine/src/storage/sqlite_storage_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_helpers.dart';

// =============================================================================
// 💾 CRDT persistence — kill / restart / outbox drain
//
// Simulates the full offline-first lifecycle:
//
//   1. Peer A draws strokes while online — every op is persisted via the
//      observer's `onLocalOperation` callback (mirroring _collaboration.dart).
//   2. The "process" exits: the in-memory state is dropped.
//   3. A new SQLite session is opened on the same database file. State is
//      rehydrated from the persisted op-log into a fresh CRDT + LayerController.
//   4. Peer A draws more strokes while disconnected (no live transport).
//      The observer persists each op with `sent_at = NULL`.
//   5. The transport reconnects. Pending ops are drained in HLC order and
//      delivered to peer B, which converges on the same state.
// =============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late String dbPath;
  late SqliteStorageAdapter adapter;
  late CRDTPersistence persistence;

  Future<void> openDb() async {
    adapter = SqliteStorageAdapter(databasePath: dbPath);
    await adapter.initialize();
    persistence = CRDTPersistence(adapter.database);
  }

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('fluera_crdt_e2e_');
    dbPath = p.join(dir.path, 'test.db');
    await openDb();
    await adapter.database.insert('canvases', {
      'canvas_id': 'canvas_x',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  });

  tearDown(() async {
    await adapter.close();
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  test('strokes drawn before kill-restart are still on the canvas', () async {
    // ── Session 1 ───────────────────────────────────────────────────────────
    final crdt1 = CRDTSceneGraph(localPeerId: 'device_a');
    final lc1 = LayerController();
    final outbox1 = <CRDTOperation>[];
    final observer1 = CRDTLayerControllerObserver(
      crdt1,
      onLocalOperation: (op) async {
        await persistence.insertOp('canvas_x', op);
        outbox1.add(op);
        await persistence.markBroadcast(op.opId);
      },
    );
    lc1.addMutationObserver(observer1.onMutation);

    lc1.addStroke(testStroke(id: 's1'));
    lc1.addStroke(testStroke(id: 's2'));
    // Settle async persistence work scheduled by the observer.
    await Future.delayed(const Duration(milliseconds: 30));

    expect(await persistence.opCount('canvas_x'), greaterThanOrEqualTo(2));

    // ── Process exit ───────────────────────────────────────────────────────
    await adapter.close();

    // ── Session 2 ───────────────────────────────────────────────────────────
    await openDb();
    final crdt2 = CRDTSceneGraph(localPeerId: 'device_a');
    final lc2 = LayerController();
    final observer2 = CRDTLayerControllerObserver(crdt2);
    final applier2 = CRDTToLayerControllerApplier(
      crdt: crdt2,
      layerController: lc2,
      observer: observer2,
    );

    // Replay every persisted op with the observer suspended (mirrors
    // _collaboration.dart's startup logic).
    await observer2.runSilently(() async {
      for (final op in await persistence.loadAllOps('canvas_x')) {
        applier2.applyRemote(op);
      }
    });

    final ids = lc2.activeLayer!.strokes.map((s) => s.id).toSet();
    expect(ids, containsAll(['s1', 's2']),
        reason: 'Persisted strokes must rehydrate into the new LayerController');
    // Persistence layer must NOT have re-emitted the replayed ops.
    expect(await persistence.opCount('canvas_x'), equals(2));
  });

  test('ops produced offline are drained on reconnect in HLC order', () async {
    // Peer A draws while disconnected — each op lands in the outbox with
    // sent_at = NULL.
    final crdtA = CRDTSceneGraph(localPeerId: 'device_a');
    final lcA = LayerController();
    final observerA = CRDTLayerControllerObserver(
      crdtA,
      onLocalOperation: (op) async {
        await persistence.insertOp('canvas_x', op);
        // sent_at intentionally left NULL — simulating offline mode.
      },
    );
    lcA.addMutationObserver(observerA.onMutation);

    lcA.addStroke(testStroke(id: 'offline_1'));
    lcA.addStroke(testStroke(id: 'offline_2'));
    lcA.addStroke(testStroke(id: 'offline_3'));
    await Future.delayed(const Duration(milliseconds: 30));

    final beforeDrain = await persistence.unsentOps('canvas_x');
    expect(beforeDrain, hasLength(3));
    expect(beforeDrain.map((p) => p.operation.nodeId).toList(),
        equals(['offline_1', 'offline_2', 'offline_3']),
        reason: 'Outbox must surface ops in HLC order');

    // Reconnect: drain.
    final delivered = <CRDTOperation>[];
    for (final entry in beforeDrain) {
      delivered.add(entry.operation);
      await persistence.markBroadcast(entry.operation.opId);
    }
    expect(await persistence.unsentOps('canvas_x'), isEmpty);

    // Peer B applies the drained ops and converges on peer A's state.
    final crdtB = CRDTSceneGraph(localPeerId: 'device_b');
    final lcB = LayerController();
    final observerB = CRDTLayerControllerObserver(crdtB);
    final applierB = CRDTToLayerControllerApplier(
      crdt: crdtB,
      layerController: lcB,
      observer: observerB,
    );
    for (final op in delivered) {
      applierB.applyRemote(op);
    }

    final aIds = lcA.activeLayer!.strokes.map((s) => s.id).toSet();
    final bIds = lcB.activeLayer!.strokes.map((s) => s.id).toSet();
    expect(bIds, equals(aIds));
  });

  test('hybrid rehydration: snapshot + opsSinceHlc skips pre-snapshot ops',
      () async {
    // Build up a CRDT graph and persist every op.
    final crdt1 = CRDTSceneGraph(localPeerId: 'device_a');
    for (var i = 0; i < 10; i++) {
      await persistence.insertOp(
        'canvas_x',
        crdt1.addNode(nodeId: 'n$i', nodeType: 'stroke'),
      );
    }
    // Snapshot at the current frontier — captures all 10 ops.
    final snapshotHlc = crdt1.localClock;
    await persistence.saveSnapshot(
      canvasId: 'canvas_x',
      graph: crdt1,
      hlc: snapshotHlc,
    );

    // Ten more ops produced after the snapshot.
    for (var i = 10; i < 20; i++) {
      await persistence.insertOp(
        'canvas_x',
        crdt1.addNode(nodeId: 'n$i', nodeType: 'stroke'),
      );
    }

    // Hybrid rehydrate: load snapshot, then replay only ops > snapshot HLC.
    final snap = (await persistence.loadSnapshot('canvas_x'))!;
    final crdt2 = CRDTSceneGraph.fromJson(snap.graphJson);
    final newer = await persistence.opsSinceHlc(
      canvasId: 'canvas_x',
      tsMs: snap.hlc.physicalMs,
      counter: snap.hlc.counter,
      peerIdTieBreak: snap.hlc.peerId,
    );

    // The hybrid replay must touch only the 10 post-snapshot ops, not all 20.
    expect(newer.length, equals(10),
        reason: 'opsSinceHlc must filter out ops folded into the snapshot');
    for (final op in newer) {
      crdt2.apply(op);
    }
    expect(crdt2.liveNodeIds, equals(crdt1.liveNodeIds));
  });

  test('vector clock survives kill-restart and tracks both peers', () async {
    // Peer A produces an op that lands in the log.
    final crdtA = CRDTSceneGraph(localPeerId: 'device_a');
    await persistence.insertOp(
      'canvas_x',
      crdtA.addNode(nodeId: 'a1', nodeType: 'stroke'),
    );

    // A remote op from peer B is also persisted (mirrors the receive path).
    final crdtB = CRDTSceneGraph(localPeerId: 'device_b');
    await persistence.insertOp(
      'canvas_x',
      crdtB.addNode(nodeId: 'b1', nodeType: 'stroke'),
    );

    await adapter.close();
    await openDb();

    final clocks = await persistence.loadVectorClock('canvas_x');
    expect(clocks.keys, containsAll(['device_a', 'device_b']));
    // Each peer's frontier must be the HLC of its only op.
    expect(clocks['device_a']!.peerId, equals('device_a'));
    expect(clocks['device_b']!.peerId, equals('device_b'));
  });
}
