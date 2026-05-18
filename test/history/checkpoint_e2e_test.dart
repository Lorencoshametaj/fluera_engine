/// 📍 Checkpoint flow — integration test
///
/// Covers the full save→persist→reload→restore round-trip. Mimics what the
/// canvas does via `_lifecycle_branching.dart`:
///   1. Tier-aware save (Free 3-cap, Plus unlimited)
///   2. JSON persistence via [CheckpointStore]
///   3. Cross-session reload from disk
///   4. Layer snapshot serialization + deserialization roundtrip
///
/// Wire-up of the UI layer (panel, modal, chip) is covered separately in
/// version_history_panel_widget_test.dart + branch_explorer_sheet_widget_test.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/fluera_canvas_config.dart'
    show FlueraSubscriptionTier;
import 'package:fluera_engine/src/core/models/canvas_layer.dart';
import 'package:fluera_engine/src/history/checkpoint_store.dart';
import 'package:fluera_engine/src/history/version_history.dart';
import 'package:fluera_engine/src/services/phase2_service_stubs.dart';
import 'package:fluera_engine/src/time_travel/models/time_travel_session.dart';

class _TestStorage implements FlueraTimeTravelStorage {
  final String basePath;
  _TestStorage(this.basePath);

  @override
  Future<String> getTimeTravelPathForCanvas(String canvasId) async =>
      '$basePath/$canvasId';

  @override
  Future<List<TimeTravelSession>> loadSessionIndex(String canvasId,
          {String? branchId}) async =>
      [];

  @override
  Future<List<TimeTravelEvent>> loadSessionEvents(TimeTravelSession session,
          {String? branchId}) async =>
      [];

  @override
  Future<(List<CanvasLayer>, int)?> loadNearestSnapshot(
          String canvasId, int targetSessionIndex,
          {String? branchId}) async =>
      null;
}

CanvasLayer _layer(String id, {String name = 'L'}) => CanvasLayer(
      id: id,
      name: '$name-$id',
      isVisible: true,
      opacity: 1.0,
      strokes: [],
    );

Map<String, dynamic> _snapshot(List<CanvasLayer> layers) => {
      'layers': layers.map((l) => l.toJson()).toList(),
      'capturedAt': DateTime.now().toIso8601String(),
    };

void main() {
  late Directory tempDir;
  late CheckpointStore store;
  const canvasId = 'cv_e2e';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fluera_cp_e2e_');
    store = CheckpointStore(storage: _TestStorage(tempDir.path));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Checkpoint E2E — Free tier cap + persistence', () {
    test('Free user: 3 saves succeed + 4th throws + persists across sessions',
        () async {
      // Session 1 — user creates 3 checkpoints
      final session1 = await store.load(canvasId);
      expect(session1.length, 0, reason: 'fresh canvas has no checkpoints');

      session1.createEntryGated(
        tier: FlueraSubscriptionTier.free,
        title: 'After lecture 1',
        authorId: 'student',
        data: _snapshot([_layer('l1')]),
      );
      session1.createEntryGated(
        tier: FlueraSubscriptionTier.free,
        title: 'After lecture 2',
        authorId: 'student',
        data: _snapshot([_layer('l1'), _layer('l2')]),
      );
      session1.createEntryGated(
        tier: FlueraSubscriptionTier.free,
        title: 'Mid-term review',
        authorId: 'student',
        data: _snapshot([_layer('l1'), _layer('l2'), _layer('l3')]),
      );
      await store.save(canvasId, session1);
      expect(session1.length, 3);

      // 4th save is blocked
      expect(
        () => session1.createEntryGated(
          tier: FlueraSubscriptionTier.free,
          title: 'After lecture 4',
          authorId: 'student',
          data: _snapshot([_layer('l1')]),
        ),
        throwsA(isA<CheckpointLimitError>()),
      );

      // Session 2 — fresh load from disk, simulates app restart
      final session2 = await store.load(canvasId);
      expect(session2.length, 3,
          reason: '3 checkpoints persisted across session reload');
      expect(session2.entries.first.title, 'Mid-term review',
          reason: 'newest-first ordering preserved');
      expect(session2.entries.last.title, 'After lecture 1');
    });

    test(
        'Archive one → cap frees → 4th save succeeds + persists',
        () async {
      final s = VersionHistory();
      String id1 = s.createEntryGated(
        tier: FlueraSubscriptionTier.free,
        title: 'cp1',
        authorId: 'u',
        data: _snapshot([_layer('a')]),
      );
      s.createEntryGated(
        tier: FlueraSubscriptionTier.free,
        title: 'cp2',
        authorId: 'u',
        data: _snapshot([_layer('a')]),
      );
      s.createEntryGated(
        tier: FlueraSubscriptionTier.free,
        title: 'cp3',
        authorId: 'u',
        data: _snapshot([_layer('a')]),
      );
      await store.save(canvasId, s);

      // Archive the oldest
      expect(s.deleteEntry(id1), isTrue);
      expect(s.length, 2);

      // 4th save now succeeds
      s.createEntryGated(
        tier: FlueraSubscriptionTier.free,
        title: 'cp4-after-archive',
        authorId: 'u',
        data: _snapshot([_layer('b')]),
      );
      await store.save(canvasId, s);

      // Reload from disk and verify state matches
      final reloaded = await store.load(canvasId);
      expect(reloaded.length, 3);
      expect(reloaded.entries.first.title, 'cp4-after-archive');
      expect(reloaded.getEntry(id1), isNull,
          reason: 'archived entry is gone after reload');
    });
  });

  group('Checkpoint E2E — Plus tier persistence at scale', () {
    test('Plus user: 10 saves all persist round-trip', () async {
      final s = VersionHistory();
      for (var i = 0; i < 10; i++) {
        s.createEntryGated(
          tier: FlueraSubscriptionTier.plus,
          title: 'cp$i',
          authorId: 'u',
          data: _snapshot([_layer('l$i')]),
        );
      }
      await store.save(canvasId, s);

      final reloaded = await store.load(canvasId);
      expect(reloaded.length, 10);
      // Sanity-check oldest entry survived the round-trip
      expect(reloaded.entries.last.title, 'cp0');
    });
  });

  group('Checkpoint E2E — layer snapshot round-trip', () {
    test('Layers in entry.data deserialize back into CanvasLayer instances',
        () async {
      final originalLayers = [
        _layer('layer-1', name: 'Sketch'),
        _layer('layer-2', name: 'Notes'),
      ];

      final s = VersionHistory();
      s.createEntryGated(
        tier: FlueraSubscriptionTier.plus,
        title: 'before exam',
        authorId: 'u',
        data: _snapshot(originalLayers),
      );
      await store.save(canvasId, s);

      // Reload + simulate _restoreCheckpoint deserialization
      final reloaded = await store.load(canvasId);
      final entry = reloaded.entries.first;
      final layersJson = entry.data['layers'] as List<dynamic>;
      final restored = layersJson
          .map(
              (j) => CanvasLayer.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();

      expect(restored, hasLength(2));
      expect(restored[0].id, 'layer-1');
      expect(restored[0].name, 'Sketch-layer-1');
      expect(restored[1].id, 'layer-2');
      expect(restored[1].isVisible, isTrue);
    });
  });

  group('Checkpoint E2E — corruption + empty file resilience', () {
    test('Empty file on disk → load returns empty history (no crash)',
        () async {
      final emptyFile = File('${tempDir.path}/$canvasId/checkpoints.json');
      await emptyFile.parent.create(recursive: true);
      await emptyFile.writeAsString('');

      final history = await store.load(canvasId);
      expect(history.length, 0);
    });

    test('Corrupt JSON on disk → load returns empty history (defensive)',
        () async {
      final corrupt = File('${tempDir.path}/$canvasId/checkpoints.json');
      await corrupt.parent.create(recursive: true);
      await corrupt.writeAsString('{this is not valid json');

      final history = await store.load(canvasId);
      expect(history.length, 0,
          reason: 'corrupt file → fresh history, no exception');
    });

    test('Missing file → load returns empty history', () async {
      final history = await store.load('nonexistent_canvas');
      expect(history.length, 0);
    });
  });
}
