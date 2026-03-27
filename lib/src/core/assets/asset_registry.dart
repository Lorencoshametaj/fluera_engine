import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../engine_scope.dart';
import '../engine_error.dart';
import '../engine_telemetry.dart';
import '../../rendering/optimization/memory_managed_cache.dart';
import 'asset_handle.dart';

// =============================================================================
// ASSET REGISTRY — Unified, reference-counted asset management.
// =============================================================================

/// Centralized registry for all engine assets (images, fonts, shaders, SVGs).
///
/// Provides:
/// - **Content deduplication** — same content → same [AssetHandle]
/// - **Reference counting** — `acquire()` / `release()`
/// - **Async loading pipeline** — pending → loading → loaded → error
/// - **Memory-pressure integration** — implements [MemoryManagedCache]
/// - **Telemetry** — counters, gauges, spans via [EngineTelemetry]
///
/// ## Usage
/// ```dart
/// final registry = EngineScope.current.assetRegistry;
/// final handle = await registry.acquire('/path/to/image.png', AssetType.image);
/// final image = registry.getData<ui.Image>(handle);
/// // ... when done:
/// registry.release(handle);
/// ```
class AssetRegistry with MemoryManagedCacheMixin implements MemoryManagedCache {
  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// All tracked assets, keyed by handle id.
  final Map<String, AssetEntry> _entries = {};

  /// Reverse index: source path → handle id (for dedup).
  final Map<String, String> _pathToId = {};

  /// Pending load futures to prevent duplicate loads.
  final Map<String, Future<void>> _pendingLoads = {};

  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // MemoryManagedCache
  // ---------------------------------------------------------------------------

  @override
  String get cacheName => 'AssetRegistry';

  @override
  int get estimatedMemoryBytes =>
      _entries.values.fold(0, (sum, e) => sum + e.memoryBytes);

  @override
  int get cacheEntryCount => _entries.length;

  @override
  int get evictionPriority => 10; // cheap to rebuild (disk-backed)

  @override
  void evictFraction(double fraction) {
    final target = (evictableEntries.length * fraction).ceil().clamp(
      0,
      evictableEntries.length,
    );
    _evictOldest(target);
  }

  @override
  void evictAll() {
    for (final entry in _entries.values.toList()) {
      if (entry.isEvictable) {
        _evictEntry(entry);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Register/acquire an asset from a file path.
  ///
  /// - If content is already registered, returns the existing handle and
  ///   increments refCount.
  /// - If new, creates entry in [pending] state.
  /// - Loading is triggered lazily on first [getData] or explicitly via [preload].
  Future<AssetHandle> acquire(String sourcePath, AssetType type) async {
    _assertNotDisposed();

    // Check path dedup index first (fast path).
    final existingId = _pathToId[sourcePath];
    if (existingId != null && _entries.containsKey(existingId)) {
      final entry = _entries[existingId]!;
      entry.refCount++;
      entry.touch();
      _emitTelemetry('assets.cache_hits');
      return entry.handle;
    }

    // Compute content hash for true dedup.
    final id = await _computeId(sourcePath);

    // Check if content already registered under a different path.
    if (_entries.containsKey(id)) {
      final entry = _entries[id]!;
      entry.refCount++;
      entry.touch();
      _pathToId[sourcePath] = id;
      _emitTelemetry('assets.cache_hits');
      return entry.handle;
    }

    // New asset.
    final handle = AssetHandle(id: id, type: type, sourcePath: sourcePath);
    final entry = AssetEntry(handle: handle, refCount: 1);
    _entries[id] = entry;
    _pathToId[sourcePath] = id;
    return handle;
  }

  /// Decrement refCount for an asset.
  ///
  /// When refCount reaches 0 the asset becomes eligible for eviction
  /// under memory pressure, but is NOT immediately disposed.
  void release(AssetHandle handle) {
    final entry = _entries[handle.id];
    if (entry == null) return;

    entry.refCount = (entry.refCount - 1).clamp(0, entry.refCount);
    if (entry.refCount == 0) {
      final short =
          handle.id.length > 8 ? handle.id.substring(0, 8) : handle.id;
    }
  }

  /// Retry loading an asset that previously failed.
  ///
  /// Resets the entry to [AssetState.pending] and clears the error,
  /// so the next [getData] or [preload] call will re-trigger loading.
  /// Returns `true` if the asset was in error state and was reset.
  bool retry(AssetHandle handle) {
    final entry = _entries[handle.id];
    if (entry == null || entry.state != AssetState.error) return false;

    entry.error = null;
    entry.errorStack = null;
    entry.transition(AssetState.pending);
    return true;
  }

  /// Get the loaded data, casting to [T].
  ///
  /// Returns null if not yet loaded. Triggers async load if in [pending] state.
  T? getData<T>(AssetHandle handle) {
    final entry = _entries[handle.id];
    if (entry == null) return null;

    entry.touch();

    if (entry.state == AssetState.pending ||
        entry.state == AssetState.evicted) {
      // Trigger async load (fire-and-forget).
      _ensureLoaded(entry);
    }

    if (entry.state == AssetState.loaded && entry.data is T) {
      return entry.data as T;
    }
    return null;
  }

  /// Get the current state of an asset.
  AssetState? getState(AssetHandle handle) => _entries[handle.id]?.state;

  /// Stream of state changes for a specific asset.
  Stream<AssetState>? watchState(AssetHandle handle) =>
      _entries[handle.id]?.stateChanges;

  /// Pre-load a list of assets.
  Future<void> preload(List<AssetHandle> handles) async {
    final futures = <Future<void>>[];
    for (final handle in handles) {
      final entry = _entries[handle.id];
      if (entry != null &&
          (entry.state == AssetState.pending ||
              entry.state == AssetState.evicted)) {
        futures.add(_ensureLoaded(entry));
      }
    }
    await Future.wait(futures);
  }

  /// Evict up to [maxCount] unreferenced assets.
  /// Returns the number actually evicted.
  int evictUnreferenced({int? maxCount}) {
    final target = maxCount ?? evictableEntries.length;
    return _evictOldest(target);
  }

  /// All entries (read-only, for diagnostics).
  Iterable<AssetEntry> get entries => _entries.values;

  /// Entries eligible for eviction (sorted oldest first).
  List<AssetEntry> get evictableEntries {
    final list =
        _entries.values.where((e) => e.isEvictable).toList()
          ..sort((a, b) => a.lastAccessedUs.compareTo(b.lastAccessedUs));
    return list;
  }

  /// Telemetry snapshot.
  Map<String, dynamic> snapshot() => {
    'totalEntries': _entries.length,
    'loadedEntries':
        _entries.values.where((e) => e.state == AssetState.loaded).length,
    'evictableEntries': evictableEntries.length,
    'totalMemoryBytes': estimatedMemoryBytes,
    'totalRefCount': _entries.values.fold<int>(0, (s, e) => s + e.refCount),
  };

  /// Dispose all entries and close streams.
  void dispose() {
    _disposed = true;
    for (final entry in _entries.values) {
      _disposeEntryData(entry);
      entry.transition(AssetState.disposed);
      entry.dispose();
    }
    _entries.clear();
    _pathToId.clear();
    _pendingLoads.clear();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _assertNotDisposed() {
    assert(!_disposed, 'AssetRegistry used after dispose()');
  }

  /// Compute a content-addressable ID for a file.
  ///
  /// Uses **streaming** SHA-256 to avoid loading entire files into RAM.
  /// Falls back to path hash if file is inaccessible.
  Future<String> _computeId(String sourcePath) async {
    try {
      final file = File(sourcePath);
      if (await file.exists()) {
        final digest = await sha256.bind(file.openRead()).first;
        return digest.toString();
      }
    } catch (e) {
      _emitEvent('asset.hash_fallback', {
        'path': sourcePath,
        'error': e.toString(),
      });
    }
    // Fallback: hash the path itself.
    return sha256.convert(utf8.encode(sourcePath)).toString();
  }

  /// Trigger async loading for an entry (idempotent).
  Future<void> _ensureLoaded(AssetEntry entry) {
    final id = entry.handle.id;

    // Already loading — return existing future.
    if (_pendingLoads.containsKey(id)) {
      return _pendingLoads[id]!;
    }

    final future = _loadEntry(entry);
    _pendingLoads[id] = future;
    future.whenComplete(() => _pendingLoads.remove(id));
    return future;
  }

  /// Load an entry based on its asset type.
  Future<void> _loadEntry(AssetEntry entry) async {
    entry.transition(AssetState.loading);

    final span = _startSpan('asset.load');

    try {
      switch (entry.handle.type) {
        case AssetType.image:
          await _loadImage(entry);
        case AssetType.font:
        case AssetType.shader:
        case AssetType.svg:
          // Placeholder — future asset types.
          entry.transition(AssetState.loaded);
      }
      _emitTelemetry('assets.loaded');
    } catch (e, stack) {
      entry.error = e;
      entry.errorStack = stack;
      entry.transition(AssetState.error);

      if (EngineScope.hasScope) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            original: e,
            stack: stack,
            source: 'AssetRegistry.load(${entry.handle.sourcePath})',
            domain: ErrorDomain.rendering,
            severity: ErrorSeverity.transient,
          ),
        );
      }

      _emitEvent('asset.error', {
        'id': entry.handle.id,
        'type': entry.handle.type.name,
        'path': entry.handle.sourcePath,
        'error': e.toString(),
      });
    } finally {
      span?.end();
    }
  }

  /// Load a raster image via the existing ImageCacheService.
  ///
  /// Throws on failure — the caller [_loadEntry] handles the error
  /// transition and telemetry in a single place.
  Future<void> _loadImage(AssetEntry entry) async {
    if (!EngineScope.hasScope) {
      throw StateError('No EngineScope for image loading');
    }

    final image = await EngineScope.current.imageCacheService.loadImage(
      entry.handle.sourcePath,
    );

    if (image == null) {
      throw StateError('Image load returned null: ${entry.handle.sourcePath}');
    }

    entry.data = image;
    entry.memoryBytes = image.width * image.height * 4; // RGBA estimate
    entry.transition(AssetState.loaded);
    _updateMemoryGauge();
  }

  /// Evict the [count] oldest evictable entries.
  int _evictOldest(int count) {
    final targets = evictableEntries.take(count).toList();
    for (final entry in targets) {
      _evictEntry(entry);
    }
    return targets.length;
  }

  /// Evict a single entry: dispose GPU resources, clear data, update state.
  void _evictEntry(AssetEntry entry) {
    _disposeEntryData(entry);
    entry.data = null;
    entry.memoryBytes = 0;
    entry.transition(AssetState.evicted);
    _emitTelemetry('assets.evicted');
    _updateMemoryGauge();

    // Clean stale _pathToId references pointing to this entry.
    _pathToId.removeWhere((_, id) => id == entry.handle.id);
  }

  /// Dispose the native data held by an entry (e.g. ui.Image GPU texture).
  void _disposeEntryData(AssetEntry entry) {
    final data = entry.data;
    if (data is ui.Image) {
      data.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Telemetry helpers
  // ---------------------------------------------------------------------------

  void _emitTelemetry(String counterName) {
    if (EngineScope.hasScope) {
      EngineScope.current.telemetry.counter(counterName).increment();
    }
  }

  void _emitEvent(String name, Map<String, dynamic> data) {
    if (EngineScope.hasScope) {
      EngineScope.current.telemetry.event(name, data);
    }
  }

  TelemetrySpan? _startSpan(String name) {
    if (EngineScope.hasScope) {
      return EngineScope.current.telemetry.startSpan(name);
    }
    return null;
  }

  void _updateMemoryGauge() {
    if (EngineScope.hasScope) {
      final mb = estimatedMemoryBytes / (1024 * 1024);
      EngineScope.current.telemetry.gauge('assets.memory_mb').set(mb);
    }
  }
}
