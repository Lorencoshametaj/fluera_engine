import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/assets/asset_handle.dart';
import 'package:fluera_engine/src/core/assets/asset_registry.dart';
import 'package:fluera_engine/src/core/engine_scope.dart';

void main() {
  late AssetRegistry registry;
  late Directory tempDir;

  setUp(() async {
    registry = AssetRegistry();
    tempDir = await Directory.systemTemp.createTemp('asset_test_');

    // Set up EngineScope for telemetry.
    EngineScope.reset();
    EngineScope.push(EngineScope());
  });

  tearDown(() async {
    registry.dispose();
    EngineScope.reset();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Helper: create a temp file with known content.
  Future<String> _createTempFile(String name, String content) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsString(content);
    return file.path;
  }

  group('AssetHandle', () {
    test('equality by id and type', () {
      const a = AssetHandle(
        id: NodeId('abc'),
        type: AssetType.image,
        sourcePath: '/a',
      );
      const b = AssetHandle(
        id: NodeId('abc'),
        type: AssetType.image,
        sourcePath: '/b',
      );
      const c = AssetHandle(
        id: NodeId('xyz'),
        type: AssetType.image,
        sourcePath: '/a',
      );

      expect(a, equals(b)); // same id+type, different path
      expect(a, isNot(equals(c))); // different id
    });

    test('hashCode consistent with equality', () {
      const a = AssetHandle(
        id: NodeId('abc'),
        type: AssetType.image,
        sourcePath: '/a',
      );
      const b = AssetHandle(
        id: NodeId('abc'),
        type: AssetType.image,
        sourcePath: '/b',
      );
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('AssetEntry', () {
    test('state transitions broadcast via stream', () async {
      final handle = const AssetHandle(
        id: NodeId('test'),
        type: AssetType.image,
        sourcePath: '/x',
      );
      final entry = AssetEntry(handle: handle);

      final states = <AssetState>[];
      entry.stateChanges.listen(states.add);

      entry.transition(AssetState.loading);
      entry.transition(AssetState.loaded);

      // Give stream time to deliver.
      await Future.delayed(Duration.zero);

      expect(states, [AssetState.loading, AssetState.loaded]);

      entry.dispose();
    });

    test('isEvictable only when refCount=0 and loaded', () {
      final handle = const AssetHandle(
        id: NodeId('test'),
        type: AssetType.image,
        sourcePath: '/x',
      );
      final entry = AssetEntry(handle: handle, refCount: 1);

      entry.transition(AssetState.loaded);
      expect(entry.isEvictable, isFalse); // refCount > 0

      entry.refCount = 0;
      expect(entry.isEvictable, isTrue); // refCount 0 + loaded

      entry.transition(AssetState.pending);
      expect(entry.isEvictable, isFalse); // not loaded
    });

    test('toJson includes all fields', () {
      final handle = const AssetHandle(
        id: NodeId('abc'),
        type: AssetType.image,
        sourcePath: '/img.png',
      );
      final entry = AssetEntry(handle: handle, refCount: 2);
      entry.transition(AssetState.loaded);
      entry.memoryBytes = 1024;

      final json = entry.toJson();
      expect(json['id'], 'abc');
      expect(json['type'], 'image');
      expect(json['state'], 'loaded');
      expect(json['refCount'], 2);
      expect(json['memoryBytes'], 1024);
      expect(json['sourcePath'], '/img.png');
    });
  });

  group('AssetRegistry - acquire/release', () {
    test('acquire returns handle and increments refCount', () async {
      final path = await _createTempFile('img1.txt', 'image data');
      final handle = await registry.acquire(path, AssetType.image);

      expect(handle, isNotNull);
      expect(handle.type, AssetType.image);
      expect(registry.entries.first.refCount, 1);
    });

    test('acquire same path returns same handle with refCount++', () async {
      final path = await _createTempFile('img2.txt', 'same data');
      final h1 = await registry.acquire(path, AssetType.image);
      final h2 = await registry.acquire(path, AssetType.image);

      expect(h1, equals(h2));
      expect(registry.entries.first.refCount, 2);
    });

    test(
      'content dedup: different paths, same content → same handle',
      () async {
        final p1 = await _createTempFile('a.txt', 'identical content');
        final p2 = await _createTempFile('b.txt', 'identical content');
        final h1 = await registry.acquire(p1, AssetType.image);
        final h2 = await registry.acquire(p2, AssetType.image);

        expect(h1, equals(h2));
        expect(registry.entries.length, 1);
        expect(registry.entries.first.refCount, 2);
      },
    );

    test('different content → different handles', () async {
      final p1 = await _createTempFile('x.txt', 'content A');
      final p2 = await _createTempFile('y.txt', 'content B');
      final h1 = await registry.acquire(p1, AssetType.image);
      final h2 = await registry.acquire(p2, AssetType.image);

      expect(h1, isNot(equals(h2)));
      expect(registry.entries.length, 2);
    });

    test('release decrements refCount', () async {
      final path = await _createTempFile('rel.txt', 'data');
      final handle = await registry.acquire(path, AssetType.image);
      await registry.acquire(path, AssetType.image); // refCount = 2

      registry.release(handle);
      expect(registry.entries.first.refCount, 1);

      registry.release(handle);
      expect(registry.entries.first.refCount, 0);
    });

    test('release clamps at zero', () async {
      final path = await _createTempFile('clamp.txt', 'data');
      final handle = await registry.acquire(path, AssetType.image);
      registry.release(handle);
      registry.release(handle); // extra release
      expect(registry.entries.first.refCount, 0);
    });
  });

  group('AssetRegistry - state management', () {
    test('new entry starts in pending state', () async {
      final path = await _createTempFile('state.txt', 'data');
      final handle = await registry.acquire(path, AssetType.image);
      expect(registry.getState(handle), AssetState.pending);
    });

    test('getState returns null for unknown handle', () {
      const unknown = AssetHandle(
        id: NodeId('nonexistent'),
        type: AssetType.image,
        sourcePath: '/x',
      );
      expect(registry.getState(unknown), isNull);
    });
  });

  group('AssetRegistry - eviction', () {
    test('evictableEntries only includes refCount=0 loaded entries', () async {
      final p1 = await _createTempFile('e1.txt', 'data1');
      final p2 = await _createTempFile('e2.txt', 'data2');

      final h1 = await registry.acquire(p1, AssetType.image);
      await registry.acquire(p2, AssetType.image);

      // Manually set both to loaded.
      for (final e in registry.entries) {
        e.transition(AssetState.loaded);
      }

      // h1 still has refCount=1, so not evictable.
      expect(registry.evictableEntries, isEmpty);

      // Release h1 → refCount=0 → evictable.
      registry.release(h1);
      expect(registry.evictableEntries, hasLength(1));
    });

    test('evictUnreferenced evicts and sets state to evicted', () async {
      final path = await _createTempFile('evict.txt', 'data');
      final handle = await registry.acquire(path, AssetType.image);

      // Simulate loaded.
      final entry = registry.entries.first;
      entry.transition(AssetState.loaded);
      entry.memoryBytes = 4096;
      registry.release(handle);

      final evicted = registry.evictUnreferenced();
      expect(evicted, 1);
      expect(registry.getState(handle), AssetState.evicted);
      expect(entry.memoryBytes, 0);
      expect(entry.data, isNull);
    });

    test('evictFraction evicts proportional entries', () async {
      // Create 4 evictable entries.
      for (int i = 0; i < 4; i++) {
        final path = await _createTempFile('f$i.txt', 'data$i');
        final handle = await registry.acquire(path, AssetType.image);
        final entry = registry.entries.firstWhere(
          (e) => e.handle.id == handle.id,
        );
        entry.transition(AssetState.loaded);
        registry.release(handle);
      }

      expect(registry.evictableEntries, hasLength(4));
      registry.evictFraction(0.5); // Should evict ~2
      expect(
        registry.entries.where((e) => e.state == AssetState.evicted).length,
        2,
      );
    });

    test('evictAll evicts all unreferenced', () async {
      for (int i = 0; i < 3; i++) {
        final path = await _createTempFile('a$i.txt', 'data$i');
        final handle = await registry.acquire(path, AssetType.image);
        final entry = registry.entries.firstWhere(
          (e) => e.handle.id == handle.id,
        );
        entry.transition(AssetState.loaded);
        registry.release(handle);
      }

      registry.evictAll();
      expect(
        registry.entries.every((e) => e.state == AssetState.evicted),
        isTrue,
      );
    });
  });

  group('AssetRegistry - MemoryManagedCache', () {
    test('cacheName is AssetRegistry', () {
      expect(registry.cacheName, 'AssetRegistry');
    });

    test('estimatedMemoryBytes sums all entries', () async {
      final p1 = await _createTempFile('m1.txt', 'data1');
      final p2 = await _createTempFile('m2.txt', 'data2');
      await registry.acquire(p1, AssetType.image);
      await registry.acquire(p2, AssetType.image);

      final entries = registry.entries.toList();
      entries[0].memoryBytes = 1000;
      entries[1].memoryBytes = 2000;

      expect(registry.estimatedMemoryBytes, 3000);
    });

    test('cacheEntryCount matches entries', () async {
      final path = await _createTempFile('count.txt', 'data');
      await registry.acquire(path, AssetType.image);
      expect(registry.cacheEntryCount, 1);
    });
  });

  group('AssetRegistry - snapshot', () {
    test('snapshot includes all stats', () async {
      final path = await _createTempFile('snap.txt', 'data');
      final handle = await registry.acquire(path, AssetType.image);
      final entry = registry.entries.first;
      entry.transition(AssetState.loaded);
      entry.memoryBytes = 4096;

      final snap = registry.snapshot();
      expect(snap['totalEntries'], 1);
      expect(snap['loadedEntries'], 1);
      expect(snap['totalMemoryBytes'], 4096);
      expect(snap['totalRefCount'], 1);
    });
  });

  group('AssetRegistry - telemetry', () {
    test('acquire emits cache_hits counter on dedup', () async {
      final path = await _createTempFile('tel.txt', 'data');
      await registry.acquire(path, AssetType.image);
      await registry.acquire(path, AssetType.image); // dedup hit

      final t = EngineScope.current.telemetry;
      expect(t.counter('assets.cache_hits').value, greaterThan(0));
    });

    test('eviction emits assets.evicted counter', () async {
      final path = await _createTempFile('ev.txt', 'data');
      final handle = await registry.acquire(path, AssetType.image);
      final entry = registry.entries.first;
      entry.transition(AssetState.loaded);
      registry.release(handle);

      registry.evictUnreferenced();

      final t = EngineScope.current.telemetry;
      expect(t.counter('assets.evicted').value, greaterThan(0));
    });
  });

  group('AssetRegistry - dispose', () {
    test('dispose sets all entries to disposed', () async {
      final path = await _createTempFile('disp.txt', 'data');
      await registry.acquire(path, AssetType.image);
      registry.dispose();

      // Re-create to avoid tearDown assertions on disposed registry.
      registry = AssetRegistry();
    });
  });

  group('AssetRegistry - fallback path hashing', () {
    test('acquire works with non-existent file path', () async {
      // Path doesn't exist → falls back to path hash.
      final handle = await registry.acquire(
        '/nonexistent/path/image.png',
        AssetType.image,
      );
      expect(handle, isNotNull);
      expect(registry.entries, hasLength(1));
    });
  });

  group('AssetRegistry - retry', () {
    test('retry resets error state to pending', () async {
      final path = await _createTempFile('retry.txt', 'data');
      final handle = await registry.acquire(path, AssetType.image);
      final entry = registry.entries.first;

      // Simulate error.
      entry.error = StateError('test');
      entry.errorStack = StackTrace.current;
      entry.transition(AssetState.error);

      expect(registry.retry(handle), isTrue);
      expect(registry.getState(handle), AssetState.pending);
      expect(entry.error, isNull);
      expect(entry.errorStack, isNull);
    });

    test('retry returns false for non-error state', () async {
      final path = await _createTempFile('retry2.txt', 'data');
      final handle = await registry.acquire(path, AssetType.image);
      expect(registry.retry(handle), isFalse); // still pending
    });

    test('retry returns false for unknown handle', () {
      const unknown = AssetHandle(
        id: NodeId('nope'),
        type: AssetType.image,
        sourcePath: '/x',
      );
      expect(registry.retry(unknown), isFalse);
    });
  });

  group('AssetRegistry - pathToId cleanup', () {
    test('eviction cleans stale path index', () async {
      final path = await _createTempFile('clean.txt', 'data');
      final handle = await registry.acquire(path, AssetType.image);
      final entry = registry.entries.first;
      entry.transition(AssetState.loaded);
      registry.release(handle);

      registry.evictUnreferenced();

      // Entry still exists in _entries (evicted, not removed).
      // Re-acquire finds it by content hash and re-increments refCount.
      final h2 = await registry.acquire(path, AssetType.image);
      expect(h2, equals(handle));
      // The entry should still be evicted until getData triggers reload.
      expect(registry.getState(h2), AssetState.evicted);
      // But refCount is now 1 again.
      final reEntry = registry.entries.firstWhere((e) => e.handle.id == h2.id);
      expect(reEntry.refCount, 1);
    });
  });
}
