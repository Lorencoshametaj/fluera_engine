/// 🧠 MEMORY MANAGED CACHE — Interface for pressure-aware cache subsystems
///
/// Each cache in the engine (tiles, images, stroke chunks, path pools)
/// implements this interface so that [MemoryBudgetController] can:
/// 1. Query current memory footprint
/// 2. Request graduated eviction under pressure
/// 3. Emergency-flush everything when critical
/// 4. Respect priority ordering (cheap caches evicted first)
/// 5. Enforce hysteresis refill-lock under sustained pressure
///
/// Design: the controller does NOT manage individual entries — each cache
/// keeps its own LRU policy. The controller only says *how much* to evict.
library;

/// Interface that each cache subsystem implements for coordinated eviction.
///
/// Use `with MemoryManagedCacheMixin` to get default implementations of
/// [evictionPriority], [isRefillAllowed], and [refillAllowed].
abstract class MemoryManagedCache {
  /// Human-readable name for diagnostics and logging.
  String get cacheName;

  /// Estimated memory footprint in bytes.
  ///
  /// Implementations should compute this from their internal data structures
  /// (e.g. `width * height * 4` per image, chunk count × avg size, etc.).
  int get estimatedMemoryBytes;

  /// Number of entries currently held in the cache.
  int get cacheEntryCount;

  /// Eviction priority: **lower values are evicted first**.
  ///
  /// Guidelines:
  /// - 0–20: cheap to rebuild (disk-backed, reload from file)
  /// - 30–60: medium cost (network-fetched images, compressed data)
  /// - 70–100: expensive (GPU rasterization, complex computation)
  int get evictionPriority;

  /// Whether the cache is currently allowed to add new entries.
  ///
  /// The [MemoryBudgetController] sets this to `false` during hysteresis
  /// (sustained pressure) to prevent immediate refill after eviction.
  /// Caches should check this before adding new entries and skip caching
  /// (but NOT skip rendering) when it returns `false`.
  bool get isRefillAllowed;

  /// Called by the controller to lock/unlock refill during hysteresis.
  ///
  /// Do NOT call this from cache implementations — it is managed
  /// exclusively by [MemoryBudgetController].
  set refillAllowed(bool value);

  /// Evict approximately [fraction] (0.0–1.0) of the least-recently-used
  /// entries. The cache decides its own eviction order.
  ///
  /// Example: `evictFraction(0.3)` releases ~30% of entries.
  void evictFraction(double fraction);

  /// Emergency: release as much memory as safely possible.
  ///
  /// After this call [estimatedMemoryBytes] should be close to zero.
  void evictAll();
}

/// Default implementations of [evictionPriority] and [isRefillAllowed].
///
/// Apply `with MemoryManagedCacheMixin` to concrete classes implementing
/// [MemoryManagedCache] to get sensible defaults.
mixin MemoryManagedCacheMixin implements MemoryManagedCache {
  bool _refillAllowed = true;

  @override
  int get evictionPriority => 50;

  @override
  bool get isRefillAllowed => _refillAllowed;

  @override
  set refillAllowed(bool value) => _refillAllowed = value;
}
