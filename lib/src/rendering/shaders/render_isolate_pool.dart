import 'dart:typed_data';
import 'dart:collection';

/// Describes a tile rendering task to be dispatched to an isolate.
///
/// This is the message format sent to worker isolates for
/// background rasterization. Node data is serialized as JSON
/// since Dart Isolates cannot share `dart:ui` objects.
class RenderTask {
  /// Tile grid coordinates.
  final int tileX;
  final int tileY;

  /// Tile size in pixels.
  final int tileSize;

  /// Device pixel ratio for proper resolution.
  final double devicePixelRatio;

  /// Serialized node data (JSON) for nodes intersecting this tile.
  /// Using serialized data since Isolates cannot share dart:ui objects.
  final List<Map<String, dynamic>> nodeData;

  /// Canvas-space rect this tile covers.
  final double canvasX;
  final double canvasY;
  final double canvasWidth;
  final double canvasHeight;

  const RenderTask({
    required this.tileX,
    required this.tileY,
    required this.tileSize,
    required this.devicePixelRatio,
    required this.nodeData,
    required this.canvasX,
    required this.canvasY,
    required this.canvasWidth,
    required this.canvasHeight,
  });

  /// Unique key for this tile position.
  String get tileKey => '${tileX}_$tileY';

  Map<String, dynamic> toJson() => {
    'tileX': tileX,
    'tileY': tileY,
    'tileSize': tileSize,
    'dpr': devicePixelRatio,
    'nodeData': nodeData,
    'canvasX': canvasX,
    'canvasY': canvasY,
    'canvasW': canvasWidth,
    'canvasH': canvasHeight,
  };
}

/// Result from a completed tile rasterization.
class RenderResult {
  /// Tile coordinates matching the original [RenderTask].
  final int tileX;
  final int tileY;

  /// Rasterized pixel data (RGBA8888).
  /// This can be uploaded to a GPU texture via `decodeImageFromPixels`.
  final Uint8List? pixelData;

  /// Width and height in physical pixels.
  final int pixelWidth;
  final int pixelHeight;

  /// Whether the task completed successfully.
  final bool success;

  /// Error message if [success] is false.
  final String? error;

  const RenderResult({
    required this.tileX,
    required this.tileY,
    this.pixelData,
    this.pixelWidth = 0,
    this.pixelHeight = 0,
    this.success = true,
    this.error,
  });

  String get tileKey => '${tileX}_$tileY';
}

// ---------------------------------------------------------------------------
// Tile Cache
// ---------------------------------------------------------------------------

/// LRU cache for rendered tiles.
///
/// Stores [RenderResult]s and tracks which tiles need re-rendering
/// (dirty tracking). Evicts least-recently-used tiles when the
/// cache exceeds [maxTiles].
class TileCache {
  /// Maximum number of tiles to keep in cache.
  final int maxTiles;

  /// Cached tiles ordered by access time (most recent = last).
  final LinkedHashMap<String, RenderResult> _cache = LinkedHashMap();

  /// Set of tile keys that need re-rendering.
  final Set<String> _dirtyTiles = {};

  TileCache({this.maxTiles = 256});

  /// Get a cached tile, or null if not present.
  /// Moves the tile to most-recently-used position.
  RenderResult? get(String tileKey) {
    final result = _cache.remove(tileKey);
    if (result != null) {
      _cache[tileKey] = result; // Move to end (MRU).
    }
    return result;
  }

  /// Store a rendered tile.
  void put(String tileKey, RenderResult result) {
    _cache.remove(tileKey); // Remove if exists to update position.
    _cache[tileKey] = result;
    _dirtyTiles.remove(tileKey);

    // Evict LRU tiles if over capacity.
    while (_cache.length > maxTiles) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Mark a tile as needing re-rendering.
  void markDirty(String tileKey) {
    _dirtyTiles.add(tileKey);
  }

  /// Mark all tiles as dirty (e.g. after a global change).
  void markAllDirty() {
    _dirtyTiles.addAll(_cache.keys);
  }

  /// Check if a tile is dirty.
  bool isDirty(String tileKey) => _dirtyTiles.contains(tileKey);

  /// Get all dirty tile keys.
  Set<String> get dirtyTiles => Set.unmodifiable(_dirtyTiles);

  /// Remove a tile from cache.
  void remove(String tileKey) {
    _cache.remove(tileKey);
    _dirtyTiles.remove(tileKey);
  }

  /// Clear all cached tiles.
  void clear() {
    _cache.clear();
    _dirtyTiles.clear();
  }

  /// Current number of cached tiles.
  int get size => _cache.length;

  /// Whether a tile is cached (regardless of dirty state).
  bool contains(String tileKey) => _cache.containsKey(tileKey);
}

// ---------------------------------------------------------------------------
// Render Isolate Pool
// ---------------------------------------------------------------------------

/// Manages a pool of Dart Isolates for background tile rasterization.
///
/// ## Architecture
///
/// ```
/// Main Thread           Isolate Pool (N workers)
/// ─────────────         ─────────────────────────
/// Frame N:
///   compose(viewport)
///   ├── visible tiles?
///   ├── cached? → draw
///   └── dirty? → dispatch RenderTask ──→ Worker picks up
///                                         ├── deserialize nodes
///                                         ├── PictureRecorder.draw()
///                                         └── return RenderResult ──→
/// Frame N+1:
///   receive results ←─────────────────────┘
///   put in TileCache
///   compose(viewport)
/// ```
///
/// > **Note**: Actual Isolate spawning requires device-level testing
/// > because `dart:ui` Canvas/PictureRecorder have specific
/// > constraints in Isolates. This class provides the architecture
/// > and message protocol — spawn integration is a follow-up step.
class RenderIsolatePool {
  /// Number of worker isolates.
  final int workerCount;

  /// Tile size in logical pixels.
  final int tileSize;

  /// Tile cache.
  final TileCache cache;

  /// Whether the pool has been initialized.
  bool _initialized = false;

  /// Pending tasks awaiting dispatch.
  final List<RenderTask> _pendingTasks = [];

  RenderIsolatePool({
    this.workerCount = 2,
    this.tileSize = 256,
    TileCache? cache,
  }) : cache = cache ?? TileCache();

  /// Whether the pool is ready to accept tasks.
  bool get isInitialized => _initialized;

  /// Initialize the isolate pool.
  ///
  /// In production, this spawns [workerCount] Isolates with
  /// SendPort/ReceivePort communication. Currently stubbed.
  Future<void> initialize() async {
    if (_initialized) return;

    // TODO: Spawn isolates with ReceivePort/SendPort pairs.
    // Each worker isolate runs a message loop that:
    // 1. Receives RenderTask (as Map)
    // 2. Creates PictureRecorder + Canvas
    // 3. Deserializes nodes and renders them
    // 4. Converts Picture to Image to pixel data
    // 5. Sends RenderResult back

    _initialized = true;
  }

  /// Dispose of all worker isolates.
  Future<void> dispose() async {
    if (!_initialized) return;

    // TODO: Kill all isolates and close ports.

    _pendingTasks.clear();
    _initialized = false;
  }

  /// Submit a rendering task for background processing.
  void submitTask(RenderTask task) {
    if (!_initialized) return;
    _pendingTasks.add(task);

    // TODO: Dispatch to least-busy worker via SendPort.
  }

  /// Determine which tiles are visible in [viewport] and need rendering.
  List<RenderTask> computeDirtyTiles({
    required double viewportX,
    required double viewportY,
    required double viewportWidth,
    required double viewportHeight,
    required double devicePixelRatio,
    required List<Map<String, dynamic>> allNodeData,
  }) {
    final tasks = <RenderTask>[];

    final startTileX = (viewportX / tileSize).floor();
    final startTileY = (viewportY / tileSize).floor();
    final endTileX = ((viewportX + viewportWidth) / tileSize).ceil();
    final endTileY = ((viewportY + viewportHeight) / tileSize).ceil();

    for (int tx = startTileX; tx <= endTileX; tx++) {
      for (int ty = startTileY; ty <= endTileY; ty++) {
        final key = '${tx}_$ty';
        if (!cache.contains(key) || cache.isDirty(key)) {
          tasks.add(
            RenderTask(
              tileX: tx,
              tileY: ty,
              tileSize: tileSize,
              devicePixelRatio: devicePixelRatio,
              nodeData: allNodeData, // In production: filter to tile bounds
              canvasX: tx * tileSize.toDouble(),
              canvasY: ty * tileSize.toDouble(),
              canvasWidth: tileSize.toDouble(),
              canvasHeight: tileSize.toDouble(),
            ),
          );
        }
      }
    }

    return tasks;
  }

  /// Process any completed results (called on main thread each frame).
  ///
  /// In production, this reads from the ReceivePort and updates the cache.
  void processResults() {
    // TODO: Read from ReceivePort, deserialize RenderResult,
    // and store in cache via cache.put().
  }
}
