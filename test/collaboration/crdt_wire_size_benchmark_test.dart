import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/fluera_realtime_adapter.dart';
import 'package:fluera_engine/src/collaboration/scene_graph_crdt.dart';
import 'package:fluera_engine/src/drawing/models/pro_brush_settings.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';

// =============================================================================
// 📏 CRDT wire-size benchmark
//
// Supabase Realtime Broadcast caps payloads at ~256 KB per message (Phoenix
// channel default 50 KB lifted to 256 KB on the Supabase plan). If a single
// stroke commit produces a CRDTOperation that exceeds this, the broadcast
// silently fails on real devices — exactly the kind of bug a pure-mock test
// suite hides.
//
// This benchmark measures the wire-size of [CRDTOperation.toJson] →
// [CanvasRealtimeEvent.fromCRDTOperation] → `jsonEncode` for a stroke at
// progressive point counts. The thresholds we assert against are the actual
// Supabase limits, NOT arbitrary numbers — so a regression in the encoded
// payload (e.g. someone adds a verbose field to ProDrawingPoint) trips the
// build before it reaches a device.
//
// Limits (in bytes), from Supabase Realtime docs:
//   • _kHardLimitBytes — 256 KiB. Anything above this is dropped server-side.
//   • _kWarnThresholdBytes — 64 KiB. Above this we lose headroom for retries
//     and for batching multiple ops into a single broadcast frame.
// =============================================================================

const int _kHardLimitBytes = 256 * 1024; // Supabase ceiling.
const int _kWarnThresholdBytes = 64 * 1024; // Comfortable single-op size.

ProStroke _strokeWith(int pointCount) {
  final points = List<ProDrawingPoint>.generate(
    pointCount,
    (i) => ProDrawingPoint(
      position: Offset(i * 1.5, i * 0.7),
      pressure: 0.4 + (i % 7) * 0.05,
      timestamp: i * 16,
      // tilt + azimuth on a stylus stroke — realistic worst case.
      tiltX: (i % 23) * 0.05,
      tiltY: (i % 19) * 0.05,
    ),
  );
  return ProStroke(
    id: 'stroke_$pointCount',
    points: points,
    color: const Color(0xFF1A2B3C),
    baseWidth: 2.5,
    penType: ProPenType.fountain,
    createdAt: DateTime(2026, 5, 5),
  );
}

int _wireBytesFor(ProStroke stroke) {
  final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
  final op = crdt.addNode(
    nodeId: stroke.id,
    nodeType: 'stroke',
    parentId: 'layer_root',
    properties: stroke.toJson(),
  );
  final event = CanvasRealtimeEvent.fromCRDTOperation(
    op,
    senderId: 'peer_a',
  );
  return utf8.encode(jsonEncode(event.toJson())).length;
}

void main() {
  group('CRDT wire size — single stroke commit', () {
    test('100 points stroke fits comfortably under warn threshold', () {
      final bytes = _wireBytesFor(_strokeWith(100));
      expect(bytes, lessThan(_kWarnThresholdBytes),
          reason: 'A typical short stroke must stay well under 64 KB '
              '(observed: $bytes bytes)');
    });

    test('1000 points stroke stays under Supabase hard limit', () {
      final bytes = _wireBytesFor(_strokeWith(1000));
      expect(bytes, lessThan(_kHardLimitBytes),
          reason: 'A long stroke must fit in a single Supabase broadcast '
              '(observed: $bytes bytes, limit: $_kHardLimitBytes)');
    });

    test('5000 points stroke produces a measurable upper bound', () {
      // We don't assert "must fit" here — 5k-point strokes are pathological
      // and the user-facing brush engine caps live drawing well below this.
      // The measurement is recorded so a future regression in payload size
      // is visible at review time.
      final bytes = _wireBytesFor(_strokeWith(5000));
      expect(bytes, greaterThan(0));
      // ignore: avoid_print
      print(
        'wire-size benchmark: 5000-point stroke = $bytes bytes '
        '(${(bytes / 1024).toStringAsFixed(1)} KiB)',
      );
    });
  });

  group('CRDT wire size — outbox batch', () {
    test('100 small ops queued offline fit within hard limit when drained',
        () {
      // The outbox drain re-broadcasts ops one-by-one, but if a future
      // optimization batches them via CRDTOperation.batchOp, we want to
      // know the batch size budget upfront.
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final ops = <CRDTOperation>[];
      for (var i = 0; i < 100; i++) {
        ops.add(crdt.addNode(
          nodeId: 'n$i',
          nodeType: 'stroke',
          properties: {'x': i * 1.5, 'color': '#abcdef', 'baseWidth': 2.0},
        ));
      }
      final batch = CRDTOperation.batchOp(
        opId: 'batch_outbox_drain',
        timestamp: ops.last.timestamp,
        peerId: 'peer_a',
        operations: ops,
      );
      final event = CanvasRealtimeEvent.fromCRDTOperation(
        batch,
        senderId: 'peer_a',
      );
      final bytes = utf8.encode(jsonEncode(event.toJson())).length;
      expect(bytes, lessThan(_kHardLimitBytes),
          reason: '100-op batch must fit in a single broadcast '
              '(observed: $bytes bytes, limit: $_kHardLimitBytes)');
    });
  });

  group('CRDT wire size — JSON roundtrip preserves bytes', () {
    test('encode → decode → encode is stable', () {
      final stroke = _strokeWith(500);
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final op = crdt.addNode(
        nodeId: stroke.id,
        nodeType: 'stroke',
        properties: stroke.toJson(),
      );
      final encoded = jsonEncode(op.toJson());
      final decoded = CRDTOperation.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      final reEncoded = jsonEncode(decoded.toJson());
      expect(reEncoded.length, equals(encoded.length),
          reason:
              'A round-trip through JSON must preserve byte size exactly');
    });
  });
}
