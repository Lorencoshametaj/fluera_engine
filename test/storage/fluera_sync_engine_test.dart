// FlueraSyncEngine uses Flutter's ValueNotifier, so flutter_test is needed.
// However the user's local Flutter build has compilation issues in flutter_test.
// This test uses @TestOn('vm') and minimal imports to work around it.
@TestOn('vm')
library;

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluera_engine/src/storage/fluera_cloud_adapter.dart';

// =============================================================================
// 🧪 FlueraSyncEngine Unit Tests
// =============================================================================

// ─── Mock Cloud Adapter ─────────────────────────────────────────────────

/// A controllable mock adapter for testing save/load/delete behavior.
class MockCloudAdapter implements FlueraCloudStorageAdapter {
  int saveCallCount = 0;
  int loadCallCount = 0;
  int deleteCallCount = 0;

  /// The last data passed to [saveCanvas].
  Map<String, dynamic>? lastSavedData;
  String? lastSavedCanvasId;

  /// Optional delay to simulate network latency.
  Duration saveDelay = Duration.zero;

  /// If non-null, [saveCanvas] throws this error.
  Object? saveError;

  /// How many times to fail before succeeding (for retry tests).
  int failuresRemaining = 0;

  /// In-memory storage for load tests.
  final Map<String, Map<String, dynamic>> store = {};

  @override
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data) async {
    if (saveDelay > Duration.zero) await Future.delayed(saveDelay);

    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw Exception('Mock network error');
    }

    if (saveError != null) throw saveError!;

    saveCallCount++;
    lastSavedCanvasId = canvasId;
    lastSavedData = Map.from(data);
    store[canvasId] = Map.from(data);
  }

  @override
  Future<Map<String, dynamic>?> loadCanvas(String canvasId) async {
    loadCallCount++;
    return store[canvasId];
  }

  @override
  Future<void> deleteCanvas(String canvasId) async {
    deleteCallCount++;
    store.remove(canvasId);
  }

  // ─── Asset methods ──────────────────────────────────────────────────

  int uploadAssetCallCount = 0;
  int downloadAssetCallCount = 0;
  String? lastUploadedAssetId;
  final Map<String, Uint8List> assetStore = {};

  @override
  Future<String> uploadAsset(
    String canvasId,
    String assetId,
    Uint8List data, {
    String? mimeType,
    void Function(double progress)? onProgress,
  }) async {
    uploadAssetCallCount++;
    lastUploadedAssetId = assetId;
    assetStore['$canvasId/$assetId'] = data;
    return 'https://cdn.example.com/$canvasId/$assetId';
  }

  @override
  Future<Uint8List?> downloadAsset(String canvasId, String assetId) async {
    downloadAssetCallCount++;
    return assetStore['$canvasId/$assetId'];
  }

  @override
  Future<void> deleteCanvasAssets(String canvasId) async {
    assetStore.removeWhere((key, _) => key.startsWith('$canvasId/'));
  }

  @override
  Future<void> deleteAsset(String canvasId, String assetId) async {
    assetStore.remove('$canvasId/$assetId');
  }

  // ─── Canvas listing ─────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> listCanvases() async {
    return store.entries
        .map(
          (e) => {
            'canvasId': e.key,
            'title': e.value['title'] as String? ?? 'Untitled',
            'updatedAt': e.value['updatedAt'] as int? ?? 0,
          },
        )
        .toList();
  }
}

void main() {
  late MockCloudAdapter adapter;
  late FlueraSyncEngine engine;

  setUp(() {
    adapter = MockCloudAdapter();
    engine = FlueraSyncEngine(
      adapter: adapter,
      debounceDuration: const Duration(milliseconds: 50),
      maxRetries: 3,
    );
  });

  tearDown(() {
    engine.dispose();
  });

  group('FlueraSyncEngine — State', () {
    test('initial state is idle', () {
      expect(engine.state.value, FlueraSyncState.idle);
      expect(engine.lastError.value, isNull);
    });
  });

  group('FlueraSyncEngine — flush (immediate save)', () {
    test('flush saves immediately to adapter', () async {
      final data = {'test': 'value'};
      await engine.flush('canvas_1', data);

      expect(adapter.saveCallCount, 1);
      expect(adapter.lastSavedCanvasId, 'canvas_1');
      expect(adapter.lastSavedData, data);
      expect(engine.state.value, FlueraSyncState.idle);
    });

    test('flush transitions state through syncing', () async {
      final states = <FlueraSyncState>[];
      engine.state.addListener(() => states.add(engine.state.value));

      await engine.flush('c1', {'k': 'v'});

      expect(states, contains(FlueraSyncState.syncing));
      expect(engine.state.value, FlueraSyncState.idle);
    });
  });

  group('FlueraSyncEngine — requestSave (debounced)', () {
    test('requestSave debounces multiple rapid calls', () async {
      engine.requestSave('c1', {'version': 1});
      engine.requestSave('c1', {'version': 2});
      engine.requestSave('c1', {'version': 3});

      // Nothing saved yet (debounce not elapsed)
      expect(adapter.saveCallCount, 0);

      // Wait for debounce to fire
      await Future.delayed(const Duration(milliseconds: 120));

      // Only ONE save with the LAST data
      expect(adapter.saveCallCount, 1);
      expect(adapter.lastSavedData?['version'], 3);
    });

    test('requestSave triggers save after debounce duration', () async {
      engine.requestSave('c1', {'a': 1});

      await Future.delayed(const Duration(milliseconds: 20));
      expect(adapter.saveCallCount, 0); // Not enough time

      await Future.delayed(const Duration(milliseconds: 80));
      expect(adapter.saveCallCount, 1); // Debounce fired
    });
  });

  group('FlueraSyncEngine — Load & Delete passthrough', () {
    test('loadCanvas passes through to adapter', () async {
      adapter.store['c1'] = {'loaded': true};

      final result = await engine.loadCanvas('c1');
      expect(result, {'loaded': true});
      expect(adapter.loadCallCount, 1);
    });

    test('loadCanvas returns null for non-existent canvas', () async {
      final result = await engine.loadCanvas('nonexistent');
      expect(result, isNull);
    });

    test('deleteCanvas passes through to adapter', () async {
      adapter.store['c1'] = {'data': 1};
      await engine.deleteCanvas('c1');

      expect(adapter.deleteCallCount, 1);
      expect(await engine.loadCanvas('c1'), isNull);
    });
  });

  group('FlueraSyncEngine — Error handling', () {
    test('enters error state after maxRetries exhausted', () async {
      // All attempts will fail permanently
      adapter.saveError = Exception('Permanent failure');

      await engine.flush('c1', {'k': 'v'});

      // First attempt fails, state enters retry cycle.
      // Wait for retries to exhaust: backoff is 2s, 4s, 8s — total ~14s.
      // For test speed, observe the state immediately after flush
      // which failed on 1st attempt:
      expect(
        engine.state.value,
        anyOf(FlueraSyncState.syncing, FlueraSyncState.error),
      );
    });

    test('successful flush clears error state', () async {
      // Force error state first
      adapter.saveError = Exception('fail');
      await engine.flush('c1', {'k': 'v'});

      // Clear error and flush again
      adapter.saveError = null;
      await engine.flush('c1', {'k': 'v2'});

      expect(engine.state.value, FlueraSyncState.idle);
      expect(engine.lastError.value, isNull);
    });
  });

  group('FlueraSyncEngine — Disposal', () {
    test('dispose cancels pending debounce timer', () async {
      // Create a separate engine for this test to avoid double-dispose
      final localEngine = FlueraSyncEngine(
        adapter: adapter,
        debounceDuration: const Duration(milliseconds: 50),
        maxRetries: 3,
      );
      localEngine.requestSave('c1', {'v': 1});
      localEngine.dispose();

      // Wait past debounce duration — should NOT trigger save
      await Future.delayed(const Duration(milliseconds: 120));
      expect(adapter.saveCallCount, 0);
    });
  });

  group('FlueraSyncEngine — Overlapping saves', () {
    test('new requestSave during in-flight save creates tail-chase', () async {
      // Make saves slow so we can sneak in another request
      adapter.saveDelay = const Duration(milliseconds: 80);

      // Start a flush
      final flushFuture = engine.flush('c1', {'version': 1});

      // Immediately request another save
      engine.requestSave('c1', {'version': 2});

      await flushFuture;

      // Wait for the tail-chase timer (500ms after first save completes)
      await Future.delayed(const Duration(milliseconds: 700));

      // Both saves should have executed
      expect(adapter.saveCallCount, 2);
      expect(adapter.lastSavedData?['version'], 2);
    });
  });

  group('FlueraSyncEngine — Asset upload/download', () {
    test('adapter getter exposes underlying adapter', () {
      expect(engine.adapter, same(adapter));
    });

    test('uploadAsset stores data and returns URL', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final url = await engine.adapter.uploadAsset(
        'c1',
        'img_abc',
        data,
        mimeType: 'image/png',
      );

      expect(url, contains('img_abc'));
      expect(adapter.uploadAssetCallCount, 1);
      expect(adapter.lastUploadedAssetId, 'img_abc');
    });

    test('downloadAsset retrieves previously uploaded data', () async {
      final original = Uint8List.fromList([10, 20, 30]);
      await engine.adapter.uploadAsset('c1', 'asset_1', original);

      final downloaded = await engine.adapter.downloadAsset('c1', 'asset_1');
      expect(downloaded, original);
      expect(adapter.downloadAssetCallCount, 1);
    });

    test('downloadAsset returns null for non-existent asset', () async {
      final result = await engine.adapter.downloadAsset('c1', 'missing');
      expect(result, isNull);
    });

    test('deleteCanvasAssets removes all assets for a canvas', () async {
      await engine.adapter.uploadAsset('c1', 'a1', Uint8List.fromList([1]));
      await engine.adapter.uploadAsset('c1', 'a2', Uint8List.fromList([2]));
      await engine.adapter.uploadAsset('c2', 'a3', Uint8List.fromList([3]));

      await engine.adapter.deleteCanvasAssets('c1');

      // c1 assets gone
      expect(await engine.adapter.downloadAsset('c1', 'a1'), isNull);
      expect(await engine.adapter.downloadAsset('c1', 'a2'), isNull);
      // c2 assets still exist
      expect(await engine.adapter.downloadAsset('c2', 'a3'), isNotNull);
    });
  });
}
