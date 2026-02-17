import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/engine_scope.dart';

/// 🚀 DISK STROKE MANAGER - Storage to disk per 10M+ strokes
///
/// PROBLEMA (10M strokes):
/// - 10M × 100 punti × 40 bytes = 40 GB di punti!
/// - Metadata (bounds) also occupy ~640 MB
/// - Impossibile tenere tutto in RAM
///
/// SOLUZIONE:
/// - Save strokes to disk in "chunks" (file da ~1000 strokes)
/// - Mantieni solo INDEX in memoria (strokeId → chunk file)
/// - Load chunks on-demand when tile is visible
/// - LRU cache per chunks (max 50 chunks = 50k strokes in RAM)
///
/// STRUTTURA DISCO:
/// ```
/// canvas_data/
/// ├── index.json          # strokeId → chunkId mapping
/// ├── chunks/
/// │   ├── chunk_0000.bin  # ~1000 strokes con punti
/// │   ├── chunk_0001.bin
/// │   └── ...
/// └── metadata.json       # bounds per tutti gli strokes (per QuadTree)
/// ```
///
/// MEMORIA (10M strokes):
/// - Index: ~100 MB (10M entries × 10 bytes)
/// - Metadata: ~640 MB (10M × 64 bytes bounds)
/// - Chunks cache: ~40 MB (50 chunks × 800 KB avg)
/// - TOTALE: ~800 MB (invece di 40 GB!)
class DiskStrokeManager {
  // ═══════════════════════════════════════════════════════════════════════════
  // 📐 CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Strokes per chunk (~1000 = buon compromesso I/O vs granularità)
  static const int strokesPerChunk = 1000;

  /// Max chunks in cache RAM
  static const int maxCachedChunks = 50;

  /// Nome cartella per dati canvas
  static const String dataFolderName = 'canvas_strokes_data';

  // ═══════════════════════════════════════════════════════════════════════════
  // 🗂️ STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Index: strokeId → chunkId
  final Map<String, int> _strokeToChunk = {};

  /// Metadata: strokeId → bounds (per spatial query without caricare punti)
  final Map<String, StrokeBounds> _strokeBounds = {};

  /// Cache chunks: chunkId → strokes data
  final Map<int, Map<String, List<ProDrawingPoint>>> _chunkCache = {};

  /// Ordine accesso LRU per chunks
  final List<int> _chunkAccessOrder = [];

  /// Current chunk for new strokes
  int _currentChunkId = 0;
  int _strokesInCurrentChunk = 0;

  /// Directory base per storage
  Directory? _dataDir;

  /// Flag inizializzazione
  bool _initialized = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 SINGLETON
  // ═══════════════════════════════════════════════════════════════════════════
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static DiskStrokeManager get instance => EngineScope.current.diskStrokeManager;

  /// Creates a new instance (used by [EngineScope]).
  DiskStrokeManager.create();

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚀 INIZIALIZZAZIONE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initializes il manager (chiamare all'avvio of the canvas)
  Future<void> initialize(String canvasId) async {
    if (_initialized) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      _dataDir = Directory('${appDir.path}/$dataFolderName/$canvasId');

      // Create directory if not esiste
      if (!await _dataDir!.exists()) {
        await _dataDir!.create(recursive: true);
        await Directory('${_dataDir!.path}/chunks').create();
      }

      // Load index se esiste
      await _loadIndex();

      _initialized = true;
    } catch (e) {
    }
  }

  /// Loads index da disco
  Future<void> _loadIndex() async {
    final indexFile = File('${_dataDir!.path}/index.json');
    if (await indexFile.exists()) {
      try {
        final data = jsonDecode(await indexFile.readAsString());

        // Load stroke → chunk mapping
        final mapping = data['mapping'] as Map<String, dynamic>;
        for (final entry in mapping.entries) {
          _strokeToChunk[entry.key] = entry.value as int;
        }

        // Load metadata corrente
        _currentChunkId = data['currentChunkId'] ?? 0;
        _strokesInCurrentChunk = data['strokesInCurrentChunk'] ?? 0;

        // Load bounds
        await _loadBounds();
      } catch (e) {
      }
    }
  }

  /// Loads bounds da disco
  Future<void> _loadBounds() async {
    final boundsFile = File('${_dataDir!.path}/metadata.json');
    if (await boundsFile.exists()) {
      try {
        final data = jsonDecode(await boundsFile.readAsString());
        final bounds = data['bounds'] as Map<String, dynamic>;

        for (final entry in bounds.entries) {
          _strokeBounds[entry.key] = StrokeBounds.fromJson(entry.value);
        }
      } catch (e) {
      }
    }
  }

  /// Saves index to disk
  Future<void> _saveIndex() async {
    if (_dataDir == null) return;

    final indexFile = File('${_dataDir!.path}/index.json');
    final data = {
      'mapping': _strokeToChunk,
      'currentChunkId': _currentChunkId,
      'strokesInCurrentChunk': _strokesInCurrentChunk,
    };

    await indexFile.writeAsString(jsonEncode(data));
  }

  /// Saves bounds to disk
  Future<void> _saveBounds() async {
    if (_dataDir == null) return;

    final boundsFile = File('${_dataDir!.path}/metadata.json');
    final boundsMap = <String, dynamic>{};

    for (final entry in _strokeBounds.entries) {
      boundsMap[entry.key] = entry.value.toJson();
    }

    await boundsFile.writeAsString(jsonEncode({'bounds': boundsMap}));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📥 AGGIUNGERE STROKES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Saves uno stroke to disk
  ///
  /// Call after the stroke was added to the NebulaLayerController.
  /// I punti verranno salvati nel chunk corrente.
  Future<void> saveStroke(
    String strokeId,
    List<ProDrawingPoint> points,
    StrokeBounds bounds,
  ) async {
    if (!_initialized || _dataDir == null) return;

    // Add a index
    _strokeToChunk[strokeId] = _currentChunkId;
    _strokeBounds[strokeId] = bounds;

    // Add current cache chunk
    _ensureChunkInCache(_currentChunkId);
    _chunkCache[_currentChunkId]![strokeId] = points;

    // Incrementa contatore
    _strokesInCurrentChunk++;

    // If chunk pieno, salva e crea nuovo
    if (_strokesInCurrentChunk >= strokesPerChunk) {
      await _flushCurrentChunk();
      _currentChunkId++;
      _strokesInCurrentChunk = 0;
    }

    // Save index periodicamente (ogni 100 strokes)
    if (_strokeToChunk.length % 100 == 0) {
      await _saveIndex();
      await _saveBounds();
    }
  }

  /// 🚀 Save batch di strokes (ottimizzato per operazioni bulk)
  /// Evita loop di await individuali e gestisce scrittura disco in modo efficiente
  Future<void> saveStrokesBatch(
    List<String> strokeIds,
    List<List<ProDrawingPoint>> pointsList,
    List<StrokeBounds> boundsList,
  ) async {
    if (!_initialized || _dataDir == null) return;
    if (strokeIds.isEmpty ||
        strokeIds.length != pointsList.length ||
        strokeIds.length != boundsList.length) {
      return;
    }

    final batchStartTime = DateTime.now();

    // Build index and bounds in memory (fast)
    for (int i = 0; i < strokeIds.length; i++) {
      _strokeToChunk[strokeIds[i]] = _currentChunkId;
      _strokeBounds[strokeIds[i]] = boundsList[i];

      // Add to current chunk cache
      _ensureChunkInCache(_currentChunkId);
      _chunkCache[_currentChunkId]![strokeIds[i]] = pointsList[i];

      _strokesInCurrentChunk++;

      // If chunk full, flush and move to next
      if (_strokesInCurrentChunk >= strokesPerChunk) {
        await _flushCurrentChunk();
        _currentChunkId++;
        _strokesInCurrentChunk = 0;
      }
    }

    // Flush any remaining strokes
    if (_strokesInCurrentChunk > 0) {
      await _flushCurrentChunk();
    }

    // Save index and bounds once at the end
    await _saveIndex();
    await _saveBounds();

    final elapsed = DateTime.now().difference(batchStartTime).inMilliseconds;
  }

  /// Saves chunk corrente to disk
  Future<void> _flushCurrentChunk() async {
    if (!_chunkCache.containsKey(_currentChunkId)) return;

    final chunkFile = File(
      '${_dataDir!.path}/chunks/chunk_${_currentChunkId.toString().padLeft(6, '0')}.json',
    );
    final chunkData = <String, dynamic>{};

    for (final entry in _chunkCache[_currentChunkId]!.entries) {
      chunkData[entry.key] = entry.value.map((p) => p.toJson()).toList();
    }

    await chunkFile.writeAsString(jsonEncode(chunkData));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📤 CARICARE STROKES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets i punti for ao stroke (carica da disco se necessario)
  Future<List<ProDrawingPoint>?> getPoints(String strokeId) async {
    // Check se stroke esiste
    final chunkId = _strokeToChunk[strokeId];
    if (chunkId == null) return null;

    // Check cache
    if (_chunkCache.containsKey(chunkId)) {
      _touchChunk(chunkId);
      return _chunkCache[chunkId]![strokeId];
    }

    // Load chunk da disco
    await _loadChunk(chunkId);

    return _chunkCache[chunkId]?[strokeId];
  }

  /// Loads un chunk da disco
  Future<void> _loadChunk(int chunkId) async {
    if (_dataDir == null) return;

    final chunkFile = File(
      '${_dataDir!.path}/chunks/chunk_${chunkId.toString().padLeft(6, '0')}.json',
    );

    if (!await chunkFile.exists()) {
      return;
    }

    try {
      final data =
          jsonDecode(await chunkFile.readAsString()) as Map<String, dynamic>;
      final chunkData = <String, List<ProDrawingPoint>>{};

      for (final entry in data.entries) {
        final points =
            (entry.value as List)
                .map((p) => ProDrawingPoint.fromJson(p as Map<String, dynamic>))
                .toList();
        chunkData[entry.key] = points;
      }

      // Evict vecchi chunks se necessario
      _evictOldChunks();

      _chunkCache[chunkId] = chunkData;
      _touchChunk(chunkId);

    } catch (e) {
    }
  }

  /// Pre-carica chunks for aa list of stroke IDs
  Future<void> preloadStrokes(List<String> strokeIds) async {
    final chunksToLoad = <int>{};

    for (final id in strokeIds) {
      final chunkId = _strokeToChunk[id];
      if (chunkId != null && !_chunkCache.containsKey(chunkId)) {
        chunksToLoad.add(chunkId);
      }
    }

    // Load chunks in parallelo (max 3 at a time)
    for (final chunkId in chunksToLoad.take(3)) {
      await _loadChunk(chunkId);
    }
  }

  /// Updates ordine LRU
  void _touchChunk(int chunkId) {
    _chunkAccessOrder.remove(chunkId);
    _chunkAccessOrder.add(chunkId);
  }

  /// Ensures a chunk is in cache
  void _ensureChunkInCache(int chunkId) {
    if (!_chunkCache.containsKey(chunkId)) {
      _chunkCache[chunkId] = {};
    }
    _touchChunk(chunkId);
  }

  /// Evict chunks meno usati
  void _evictOldChunks() {
    while (_chunkCache.length >= maxCachedChunks &&
        _chunkAccessOrder.isNotEmpty) {
      final oldestChunkId = _chunkAccessOrder.removeAt(0);

      // Do not evictare chunk corrente
      if (oldestChunkId == _currentChunkId) continue;

      _chunkCache.remove(oldestChunkId);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔍 QUERY SPAZIALI
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets stroke IDs che intersecano un bounds
  /// Use metadata in memoria, non carica punti
  List<String> getStrokesInBounds(StrokeBounds queryBounds) {
    final result = <String>[];

    for (final entry in _strokeBounds.entries) {
      if (entry.value.overlaps(queryBounds)) {
        result.add(entry.key);
      }
    }

    return result;
  }

  /// Gets bounds for ao stroke (without caricare punti)
  StrokeBounds? getBounds(String strokeId) {
    return _strokeBounds[strokeId];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📊 STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Numero totale strokes salvati
  int get totalStrokes => _strokeToChunk.length;

  /// Numero chunks in cache
  int get cachedChunks => _chunkCache.length;

  /// Strokes stimati in cache
  int get cachedStrokes {
    int count = 0;
    for (final chunk in _chunkCache.values) {
      count += chunk.length;
    }
    return count;
  }

  /// Statistics for debugging
  Map<String, dynamic> get stats => {
    'totalStrokes': totalStrokes,
    'totalChunks': _currentChunkId + 1,
    'cachedChunks': cachedChunks,
    'cachedStrokes': cachedStrokes,
    'maxCachedChunks': maxCachedChunks,
    'strokesPerChunk': strokesPerChunk,
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧹 CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Remove a single stroke from index, bounds, and chunk cache.
  ///
  /// Note: the on-disk chunk file is not rewritten immediately — the
  /// stale entry is simply absent from the index, so it will never be
  /// loaded again. The next [flush] or chunk rotation will persist the
  /// updated state.
  void removeStroke(String strokeId) {
    final chunkId = _strokeToChunk.remove(strokeId);
    _strokeBounds.remove(strokeId);

    // Also remove from in-memory chunk cache if present
    if (chunkId != null && _chunkCache.containsKey(chunkId)) {
      _chunkCache[chunkId]!.remove(strokeId);
    }
  }

  /// Saves everything to disk (call before closing the canvas)
  Future<void> flush() async {
    await _flushCurrentChunk();
    await _saveIndex();
    await _saveBounds();
  }

  /// Clears cache RAM (non tocca disco)
  void clearCache() {
    _chunkCache.clear();
    _chunkAccessOrder.clear();
  }

  /// Elimina tutti i dati (disco + RAM)
  Future<void> deleteAll() async {
    if (_dataDir != null && await _dataDir!.exists()) {
      await _dataDir!.delete(recursive: true);
    }

    _strokeToChunk.clear();
    _strokeBounds.clear();
    _chunkCache.clear();
    _chunkAccessOrder.clear();
    _currentChunkId = 0;
    _strokesInCurrentChunk = 0;
    _initialized = false;
  }
}

/// Bounds semplificato per storage efficiente
class StrokeBounds {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const StrokeBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  factory StrokeBounds.fromRect(Rect rect) => StrokeBounds(
    left: rect.left,
    top: rect.top,
    right: rect.right,
    bottom: rect.bottom,
  );

  factory StrokeBounds.fromJson(Map<String, dynamic> json) => StrokeBounds(
    left: (json['l'] as num).toDouble(),
    top: (json['t'] as num).toDouble(),
    right: (json['r'] as num).toDouble(),
    bottom: (json['b'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'l': left,
    't': top,
    'r': right,
    'b': bottom,
  };

  Rect toRect() => Rect.fromLTRB(left, top, right, bottom);

  bool overlaps(StrokeBounds other) {
    return left <= other.right &&
        right >= other.left &&
        top <= other.bottom &&
        bottom >= other.top;
  }
}
