import 'dart:async';
import 'dart:isolate';
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
// Worker Isolate Message Protocol
// ---------------------------------------------------------------------------

/// Message types for isolate communication.
enum _WorkerMessageType { task, shutdown }

/// Message sent to a worker isolate.
class _WorkerMessage {
  final _WorkerMessageType type;
  final Map<String, dynamic>? taskData;

  const _WorkerMessage({required this.type, this.taskData});
}

/// Represents a single worker isolate with its communication ports.
class _Worker {
  final Isolate isolate;
  final SendPort sendPort;
  bool busy = false;

  _Worker({required this.isolate, required this.sendPort});
}

// ---------------------------------------------------------------------------
// Render Isolate Pool
// ---------------------------------------------------------------------------

/// Manages a pool of Dart Isolates for background tile data preparation.
///
/// ## Architecture
///
/// ```
/// Main Thread              Isolate Pool (N workers)
/// ─────────────            ─────────────────────────
/// Frame N:
///   compose(viewport)
///   ├── visible tiles?
///   ├── cached? → draw
///   └── dirty? → dispatch RenderTask ──→ Worker picks up
///                                         ├── deserialize nodes
///                                         ├── filter/simplify points
///                                         └── return RenderResult ──→
/// Frame N+1:
///   receive results ←─────────────────────┘
///   rasterize on main thread (dart:ui)
///   put in TileCache
///   compose(viewport)
/// ```
///
/// > **Note**: `dart:ui` Canvas/PictureRecorder require the root isolate.
/// > Workers perform CPU-bound data prep (point filtering, simplification,
/// > spatial queries). Rasterization happens on the main thread.
class RenderIsolatePool {
  /// Number of worker isolates.
  final int workerCount;

  /// Tile size in logical pixels.
  final int tileSize;

  /// Tile cache.
  final TileCache cache;

  /// Whether the pool has been initialized.
  bool _initialized = false;

  /// Worker isolates.
  final List<_Worker> _workers = [];

  /// Pending tasks awaiting dispatch.
  final List<RenderTask> _pendingTasks = [];

  /// Completed results ready for main thread consumption.
  final List<RenderResult> _completedResults = [];

  /// Port to receive results from workers.
  ReceivePort? _resultPort;

  /// Subscription for incoming results.
  StreamSubscription<dynamic>? _resultSubscription;

  RenderIsolatePool({
    this.workerCount = 2,
    this.tileSize = 256,
    TileCache? cache,
  }) : cache = cache ?? TileCache();

  /// Whether the pool is ready to accept tasks.
  bool get isInitialized => _initialized;

  /// Number of pending tasks.
  int get pendingTaskCount => _pendingTasks.length;

  /// Number of completed results awaiting processing.
  int get completedResultCount => _completedResults.length;

  /// Initialize the isolate pool.
  ///
  /// Spawns [workerCount] persistent Isolates with
  /// SendPort/ReceivePort communication channels.
  Future<void> initialize() async {
    if (_initialized) return;

    _resultPort = ReceivePort();

    // Listen for results from workers
    _resultSubscription = _resultPort!.listen((message) {
      if (message is Map<String, dynamic>) {
        _completedResults.add(
          RenderResult(
            tileX: message['tileX'] as int,
            tileY: message['tileY'] as int,
            pixelData: message['pixelData'] as Uint8List?,
            pixelWidth: message['pixelWidth'] as int? ?? 0,
            pixelHeight: message['pixelHeight'] as int? ?? 0,
            success: message['success'] as bool? ?? true,
            error: message['error'] as String?,
          ),
        );

        // Mark the worker as not busy
        final workerIndex = message['workerIndex'] as int? ?? 0;
        if (workerIndex < _workers.length) {
          _workers[workerIndex].busy = false;
        }

        // Try to dispatch next pending task
        _dispatchNextTask();
      }
    });

    // Spawn worker isolates
    for (int i = 0; i < workerCount; i++) {
      try {
        final worker = await _spawnWorker(i);
        _workers.add(worker);
      } catch (e) {
        // If spawning fails, continue with fewer workers
        // (graceful degradation — main thread handles all work)
      }
    }

    _initialized = true;
  }

  /// Spawn a single worker isolate.
  Future<_Worker> _spawnWorker(int index) async {
    final receivePort = ReceivePort();

    final isolate = await Isolate.spawn(
      _workerEntryPoint,
      _WorkerInitMessage(
        sendPort: receivePort.sendPort,
        resultPort: _resultPort!.sendPort,
        workerIndex: index,
      ),
    );

    // Wait for the worker's SendPort
    final workerSendPort = await receivePort.first as SendPort;
    receivePort.close();

    return _Worker(isolate: isolate, sendPort: workerSendPort);
  }

  /// Worker isolate entry point.
  static void _workerEntryPoint(_WorkerInitMessage init) {
    final receivePort = ReceivePort();
    init.sendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final type = message['type'] as String;

        if (type == 'shutdown') {
          receivePort.close();
          return;
        }

        if (type == 'task') {
          // CPU-bound data preparation work
          final result = _processTaskInIsolate(message, init.workerIndex);
          init.resultPort.send(result);
        }
      }
    });
  }

  /// Process a render task inside the worker isolate.
  ///
  /// Since dart:ui is not available in isolates, this performs
  /// CPU-bound data preparation:
  /// - Point filtering (remove duplicate/overlapping points)
  /// - Bounding box calculations
  /// - Node data sorting by z-order
  static Map<String, dynamic> _processTaskInIsolate(
    Map<String, dynamic> taskData,
    int workerIndex,
  ) {
    try {
      final nodeData = taskData['nodeData'] as List<dynamic>? ?? [];
      final tileX = taskData['tileX'] as int;
      final tileY = taskData['tileY'] as int;
      final tileSz = taskData['tileSize'] as int;

      // Filter nodes that actually intersect this tile
      final tileLeft = tileX * tileSz.toDouble();
      final tileTop = tileY * tileSz.toDouble();
      final tileRight = tileLeft + tileSz;
      final tileBottom = tileTop + tileSz;

      final filteredNodes = <Map<String, dynamic>>[];

      for (final node in nodeData) {
        if (node is! Map<String, dynamic>) continue;
        final bounds = node['bounds'] as Map<String, dynamic>?;
        if (bounds == null) continue;

        final left = (bounds['left'] as num?)?.toDouble() ?? 0;
        final top = (bounds['top'] as num?)?.toDouble() ?? 0;
        final right = (bounds['right'] as num?)?.toDouble() ?? 0;
        final bottom = (bounds['bottom'] as num?)?.toDouble() ?? 0;

        // AABB intersection test
        if (right >= tileLeft &&
            left <= tileRight &&
            bottom >= tileTop &&
            top <= tileBottom) {
          filteredNodes.add(node);
        }
      }

      // Sort by z-order if available
      filteredNodes.sort((a, b) {
        final za = (a['zOrder'] as num?)?.toInt() ?? 0;
        final zb = (b['zOrder'] as num?)?.toInt() ?? 0;
        return za.compareTo(zb);
      });

      return {
        'tileX': tileX,
        'tileY': tileY,
        'nodeCount': filteredNodes.length,
        'filteredNodes': filteredNodes,
        'success': true,
        'workerIndex': workerIndex,
        'pixelWidth': 0,
        'pixelHeight': 0,
      };
    } catch (e) {
      return {
        'tileX': taskData['tileX'] ?? 0,
        'tileY': taskData['tileY'] ?? 0,
        'success': false,
        'error': e.toString(),
        'workerIndex': workerIndex,
        'pixelWidth': 0,
        'pixelHeight': 0,
      };
    }
  }

  /// Dispose of all worker isolates.
  Future<void> dispose() async {
    if (!_initialized) return;

    // Send shutdown to all workers
    for (final worker in _workers) {
      worker.sendPort.send({'type': 'shutdown'});
      worker.isolate.kill(priority: Isolate.beforeNextEvent);
    }

    _workers.clear();
    _pendingTasks.clear();
    _completedResults.clear();

    await _resultSubscription?.cancel();
    _resultSubscription = null;
    _resultPort?.close();
    _resultPort = null;

    _initialized = false;
  }

  /// Submit a rendering task for background processing.
  void submitTask(RenderTask task) {
    if (!_initialized || _workers.isEmpty) return;
    _pendingTasks.add(task);
    _dispatchNextTask();
  }

  /// Dispatch next pending task to an available worker.
  void _dispatchNextTask() {
    if (_pendingTasks.isEmpty) return;

    // Find a free worker
    for (final worker in _workers) {
      if (!worker.busy && _pendingTasks.isNotEmpty) {
        final task = _pendingTasks.removeAt(0);
        worker.busy = true;
        worker.sendPort.send({'type': 'task', ...task.toJson()});
      }
    }
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
  /// Returns list of completed results since last call.
  /// The caller is responsible for rasterizing these on the main thread
  /// (since dart:ui requires the root isolate).
  List<RenderResult> processResults() {
    if (_completedResults.isEmpty) return const [];
    final results = List<RenderResult>.from(_completedResults);
    _completedResults.clear();
    return results;
  }

  /// Statistics for monitoring.
  Map<String, dynamic> get stats => {
    'initialized': _initialized,
    'workers': _workers.length,
    'busyWorkers': _workers.where((w) => w.busy).length,
    'pendingTasks': _pendingTasks.length,
    'completedResults': _completedResults.length,
    'cachedTiles': cache.size,
  };
}

/// Initialization message for worker isolates.
class _WorkerInitMessage {
  final SendPort sendPort;
  final SendPort resultPort;
  final int workerIndex;

  const _WorkerInitMessage({
    required this.sendPort,
    required this.resultPort,
    required this.workerIndex,
  });
}
