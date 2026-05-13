import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../collaboration/scene_graph_crdt.dart';

// =============================================================================
// 🔄 CRDT PERSISTENCE REPOSITORY
//
// Backed by the v18 schema (`crdt_operations`, `crdt_vector_clocks`,
// `crdt_snapshots`). Encapsulates every read/write the realtime layer needs
// so the SQLite specifics never leak into [_collaboration.dart].
//
// Two responsibilities:
//
//   1. **Outbox**: persist a [CRDTOperation] before it is broadcast so a
//      crash between `apply` and `send` doesn't lose the mutation.
//      `markBroadcast` flips `sent_at` when the transport ack lands.
//
//   2. **Catch-up**: at canvas open, replay every stored op into the in-memory
//      [CRDTSceneGraph]; on reconnect, query [opsSinceHlc] to ship the local
//      backlog to peers without re-broadcasting the full snapshot.
//
// Vector clocks are computed from applied ops (`MAX(ts_ms, counter)` per
// `peer_id`) and persisted on every `recordApplied` so a fresh process can
// resume the causal frontier without scanning the log.
// =============================================================================

/// Result of an unsent-ops query — preserves order required for FIFO replay.
class PendingCRDTOperation {
  /// The deserialized operation.
  final CRDTOperation operation;

  /// Wall-clock millisecond at which this op was inserted (for diagnostics).
  final int appliedAtMs;

  const PendingCRDTOperation({
    required this.operation,
    required this.appliedAtMs,
  });
}

/// Repository wrapping the v18 CRDT tables.
class CRDTPersistence {
  final Database _db;

  CRDTPersistence(this._db);

  // ───────────────────────────────────────────────────────────────────────────
  // Operations log
  // ───────────────────────────────────────────────────────────────────────────

  /// Persist [op] for [canvasId] before it is broadcast or applied locally.
  ///
  /// Idempotent: re-inserting the same `op_id` is a no-op, mirroring the
  /// in-memory CRDT dedup. Caller can safely retry on transient errors.
  ///
  /// Wrapped in a transaction so the op-log row and the vector-clock bump
  /// land atomically — without this, the two separate writes are individual
  /// statements that interleave with concurrent canvas-save transactions
  /// and trigger SQLITE_BUSY (even with `busy_timeout`, splitting them
  /// doubles the lock-acquisition pressure on the WAL writer).
  Future<void> insertOp(String canvasId, CRDTOperation op) async {
    await _db.transaction((txn) async {
      await txn.insert(
        'crdt_operations',
        {
          'op_id': op.opId,
          'canvas_id': canvasId,
          'peer_id': op.peerId,
          'op_type': op.type.name,
          'node_id': op.nodeId,
          'ts_ms': op.timestamp.physicalMs,
          'counter': op.timestamp.counter,
          'payload_json': jsonEncode(op.toJson()),
          'applied_at': DateTime.now().millisecondsSinceEpoch,
          'sent_at': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await _bumpVectorClockInTxn(txn, canvasId, op.timestamp);
    });
  }

  /// Mark [opId] as broadcast — flips `sent_at` to the current wall-clock so
  /// it stops appearing in [unsentOps] on the next reconnect.
  Future<void> markBroadcast(String opId) async {
    await _db.update(
      'crdt_operations',
      {'sent_at': DateTime.now().millisecondsSinceEpoch},
      where: 'op_id = ?',
      whereArgs: [opId],
    );
  }

  /// Stream every persisted op for [canvasId] in HLC order.
  ///
  /// Used at canvas open to repopulate the in-memory [CRDTSceneGraph] before
  /// the realtime adapter connects.
  Future<List<CRDTOperation>> loadAllOps(String canvasId) async {
    final rows = await _db.query(
      'crdt_operations',
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
      orderBy: 'ts_ms ASC, counter ASC, peer_id ASC',
    );
    return rows.map(_rowToOperation).toList();
  }

  /// Ops produced after a remote peer's HLC snapshot — used for catch-up
  /// replication. Returns ops that are strictly newer than [tsMs]/[counter]
  /// in HLC ordering (peer_id used as tie-breaker, matching [HLCTimestamp]).
  Future<List<CRDTOperation>> opsSinceHlc({
    required String canvasId,
    required int tsMs,
    required int counter,
    String peerIdTieBreak = '',
  }) async {
    final rows = await _db.rawQuery('''
      SELECT * FROM crdt_operations
      WHERE canvas_id = ?
        AND (
          ts_ms > ?
          OR (ts_ms = ? AND counter > ?)
          OR (ts_ms = ? AND counter = ? AND peer_id > ?)
        )
      ORDER BY ts_ms ASC, counter ASC, peer_id ASC
    ''', [
      canvasId,
      tsMs,
      tsMs,
      counter,
      tsMs,
      counter,
      peerIdTieBreak,
    ]);
    return rows.map(_rowToOperation).toList();
  }

  /// Ops queued for broadcast (sent_at IS NULL), oldest first.
  ///
  /// Drained on reconnect so offline mutations propagate exactly once.
  Future<List<PendingCRDTOperation>> unsentOps(String canvasId) async {
    final rows = await _db.query(
      'crdt_operations',
      where: 'canvas_id = ? AND sent_at IS NULL',
      whereArgs: [canvasId],
      orderBy: 'ts_ms ASC, counter ASC, peer_id ASC',
    );
    return rows
        .map((r) => PendingCRDTOperation(
              operation: _rowToOperation(r),
              appliedAtMs: r['applied_at'] as int,
            ))
        .toList();
  }

  /// Total operation count for [canvasId] — diagnostics + GC trigger.
  Future<int> opCount(String canvasId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM crdt_operations WHERE canvas_id = ?',
      [canvasId],
    );
    return (rows.single['c'] as int?) ?? 0;
  }

  /// Highest op-counter ever produced by [peerId] on [canvasId].
  ///
  /// `opId` is encoded as `{peerId}_{counter}`. We parse it rather than
  /// adding a dedicated column so the schema stays minimal — opCount is
  /// O(N) anyway and this query runs once per canvas-open.
  ///
  /// Returns `-1` when the peer has never produced an op on this canvas
  /// (caller advances the in-memory counter to `result + 1`, which is `0`).
  Future<int> maxOpCounterForPeer({
    required String canvasId,
    required String peerId,
  }) async {
    final rows = await _db.rawQuery(
      'SELECT op_id FROM crdt_operations '
      'WHERE canvas_id = ? AND peer_id = ?',
      [canvasId, peerId],
    );
    var maxCounter = -1;
    for (final r in rows) {
      final opId = r['op_id'] as String;
      // opId format: "{peerId}_{counter}". Find the last '_' so peerIds
      // that themselves contain '_' (they do — "device_<rand>_<rand>")
      // still parse cleanly.
      final i = opId.lastIndexOf('_');
      if (i < 0 || i == opId.length - 1) continue;
      final n = int.tryParse(opId.substring(i + 1));
      if (n != null && n > maxCounter) maxCounter = n;
    }
    return maxCounter;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Vector clocks
  // ───────────────────────────────────────────────────────────────────────────

  /// Latest HLC observed per peer for [canvasId]. Empty when the canvas is
  /// brand-new — caller treats that as "request full snapshot".
  Future<Map<String, HLCTimestamp>> loadVectorClock(String canvasId) async {
    final rows = await _db.query(
      'crdt_vector_clocks',
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );
    return {
      for (final r in rows)
        r['peer_id'] as String: HLCTimestamp(
          physicalMs: r['ts_ms'] as int,
          counter: r['counter'] as int,
          peerId: r['peer_id'] as String,
        ),
    };
  }

  Future<void> _bumpVectorClockInTxn(
    DatabaseExecutor txn,
    String canvasId,
    HLCTimestamp ts,
  ) async {
    await txn.rawInsert('''
      INSERT INTO crdt_vector_clocks
        (canvas_id, peer_id, ts_ms, counter, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT (canvas_id, peer_id) DO UPDATE SET
        ts_ms = CASE
          WHEN excluded.ts_ms > ts_ms
            OR (excluded.ts_ms = ts_ms AND excluded.counter > counter)
          THEN excluded.ts_ms ELSE ts_ms END,
        counter = CASE
          WHEN excluded.ts_ms > ts_ms
            OR (excluded.ts_ms = ts_ms AND excluded.counter > counter)
          THEN excluded.counter ELSE counter END,
        updated_at = excluded.updated_at
    ''', [
      canvasId,
      ts.peerId,
      ts.physicalMs,
      ts.counter,
      DateTime.now().millisecondsSinceEpoch,
    ]);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Snapshots
  // ───────────────────────────────────────────────────────────────────────────

  /// Persist a snapshot for [canvasId] — replaces any prior snapshot.
  ///
  /// The snapshot is a JSON dump of [CRDTSceneGraph.toJson] anchored at the
  /// HLC timestamp returned by [CRDTSceneGraph.clock] when the dump was
  /// taken (passed in via [hlc]). On reload, ops with HLC ≤ snapshot HLC
  /// can be skipped (the snapshot already reflects them).
  Future<void> saveSnapshot({
    required String canvasId,
    required CRDTSceneGraph graph,
    required HLCTimestamp hlc,
  }) async {
    await _db.insert(
      'crdt_snapshots',
      {
        'canvas_id': canvasId,
        'snapshot_json': jsonEncode(graph.toJson()),
        'hlc_ts_ms': hlc.physicalMs,
        'hlc_counter': hlc.counter,
        'hlc_peer_id': hlc.peerId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load the latest snapshot for [canvasId], or `null` if none exists.
  Future<CRDTSnapshotRecord?> loadSnapshot(String canvasId) async {
    final rows = await _db.query(
      'crdt_snapshots',
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return CRDTSnapshotRecord(
      graphJson: jsonDecode(row['snapshot_json'] as String)
          as Map<String, dynamic>,
      hlc: HLCTimestamp(
        physicalMs: row['hlc_ts_ms'] as int,
        counter: row['hlc_counter'] as int,
        peerId: row['hlc_peer_id'] as String,
      ),
      createdAtMs: row['created_at'] as int,
    );
  }

  /// Delete all CRDT state for [canvasId]. Used by `deleteCanvas` flows; the
  /// FK CASCADE handles this automatically when the canvas row is deleted,
  /// but exposing it explicitly keeps unit tests transport-agnostic.
  Future<void> clearCanvas(String canvasId) async {
    await _db.delete(
      'crdt_operations',
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );
    await _db.delete(
      'crdt_vector_clocks',
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );
    await _db.delete(
      'crdt_snapshots',
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Internal
  // ───────────────────────────────────────────────────────────────────────────

  CRDTOperation _rowToOperation(Map<String, Object?> row) {
    final json = jsonDecode(row['payload_json'] as String);
    return CRDTOperation.fromJson(json as Map<String, dynamic>);
  }
}

/// Snapshot row materialized into Dart types for the engine to consume.
class CRDTSnapshotRecord {
  final Map<String, dynamic> graphJson;
  final HLCTimestamp hlc;
  final int createdAtMs;

  const CRDTSnapshotRecord({
    required this.graphJson,
    required this.hlc,
    required this.createdAtMs,
  });
}
