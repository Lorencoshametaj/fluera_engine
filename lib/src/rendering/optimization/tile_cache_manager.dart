import 'dart:collection';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../drawing/brushes/brushes.dart';

import './stroke_data_manager.dart';
import './advanced_tile_optimizer.dart';
import '../../core/engine_scope.dart';

/// 🚀 TILE CACHE MANAGER - Caching per tile scalabile a 100k+ strokes
///
/// STRATEGIA:
/// - Canvas diviso in tile 4096x4096 px
/// - Solo visible tiles vengono rasterizzati
/// - Ogni tile ha una ui.Image cached (HiDPI)
/// - LRU eviction per limitare memoria
/// - Invalidatezione granulare (1 tile invece di tutto)
///
/// PERFORMANCE CON 100k+ STROKES:
/// - Memoria: O(viewport) invece di O(n)
/// - Rendering: O(1) - disegna only themmagini cached
/// - Invalidatezione: O(k) dove k = tile coinvolti (tipicamente 1-2)
///
/// ARCHITETTURA PREDISPOSTA PER:
/// - Fase 2: LOD (Level of Detail) per zoom
/// - Fase 3: Disk-backed tiles per 10M+ strokes
class TileCacheManager {
  // ═══════════════════════════════════════════════════════════════════════════
  // 📐 CONFIGURAZIONE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Size tile in pixel logici
  /// 512px: Con devicePixelRatio 2.75 = 1408px reali
  /// Memoria per tile: 1408² × 4 bytes = ~8MB (era ~127MB con 2048)
  static const double tileSize = 512.0;

  /// Maximum number di tile in cache (LRU eviction)
  /// 32 tile × ~8MB = ~256MB max (era 8×127MB = ~1GB)
  static const int maxCachedTiles = 32;

  /// Margine extra per pre-caricare tile adiacenti
  static const double preloadMargin = 0.5; // 50% of the tile

  // 🐛 DEBUG: Contatori to track il ciclo di vita delle Image/Pictures
  static int _totalImagesCreated = 0;
  static int _totalImagesDisposed = 0;
  static int _totalPicturesCreated = 0;
  static int _totalPicturesDisposed = 0;

  static void _logMemoryStats(String context) {
    // No-op: logging removed with singleton migration
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🗂️ CACHE STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Cache LRU: tileKey -> rasterized image
  /// LinkedHashMap mantiene ordine di accesso per LRU
  final LinkedHashMap<String, ui.Image> _tileCache = LinkedHashMap();

  /// Tiles that need to be re-rasterized
  final Set<String> _dirtyTiles = {};

  /// Conteggio strokes per tile per rilevare cambiamenti
  final Map<String, int> _tileStrokeCounts = {};

  /// Device pixel ratio corrente
  double _devicePixelRatio = 1.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 SINGLETON (opzionale, can essere istanza)
  // ═══════════════════════════════════════════════════════════════════════════
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static TileCacheManager get instance => EngineScope.current.tileCacheManager;

  /// Creates a new instance (used by [EngineScope]).
  TileCacheManager.create();

  // ═══════════════════════════════════════════════════════════════════════════
  // 📐 TILE GEOMETRY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Genera chiave univoca per tile
  String _tileKey(int x, int y) => '$x:$y';

  /// Calculatates bounds di un tile in canvas coordinates
  Rect getTileBounds(int tileX, int tileY) {
    return Rect.fromLTWH(
      tileX * tileSize,
      tileY * tileSize,
      tileSize,
      tileSize,
    );
  }

  /// Calculatates quali tile sono visibili in the viewport (con margine preload)
  /// Supporta coordinate negative per canvas infinito
  List<(int, int)> getVisibleTiles(Rect viewport) {
    // Espandi viewport per preload
    final expandedViewport = viewport.inflate(tileSize * preloadMargin);

    final startX = (expandedViewport.left / tileSize).floor();
    final startY = (expandedViewport.top / tileSize).floor();
    final endX = (expandedViewport.right / tileSize).ceil();
    final endY = (expandedViewport.bottom / tileSize).ceil();

    return [
      for (int x = startX; x <= endX; x++)
        for (int y = startY; y <= endY; y++) (x, y),
    ];
  }

  /// Calculatates quali tile sono toccati da un bounds (stroke, shape)
  /// Supporta coordinate negative per canvas infinito
  List<(int, int)> getTilesForBounds(Rect bounds) {
    final startX = (bounds.left / tileSize).floor();
    final startY = (bounds.top / tileSize).floor();
    final endX = (bounds.right / tileSize).ceil();
    final endY = (bounds.bottom / tileSize).ceil();

    return [
      for (int x = startX; x <= endX; x++)
        for (int y = startY; y <= endY; y++) (x, y),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎨 RASTERIZZAZIONE TILE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Rasterize un singolo tile con i suoi strokes a quality massima
  ///
  /// [tileX], [tileY]: Tile coordinates
  /// [strokesInTile]: Strokes che intersecano questo tile
  /// [devicePixelRatio]: Per rendering HiDPI
  void rasterizeTile(
    int tileX,
    int tileY,
    List<ProStroke> strokesInTile,
    double devicePixelRatio,
  ) {
    final key = _tileKey(tileX, tileY);
    _devicePixelRatio = devicePixelRatio;

    // 🗑️ CRITICAL FIX: Dispose immagine precedente PRIMA di creare la nuova
    final oldImage = _tileCache[key];
    if (oldImage != null) {
      // Remove from the cache PRIMA di dispose to avoid race conditions
      _tileCache.remove(key);
      _tileStrokeCounts.remove(key);
      // 🐛 DEBUG: Dispose IMMEDIATO invece di Future.microtask
      oldImage.dispose();
      _totalImagesDisposed++;
    }

    if (strokesInTile.isEmpty) {
      _dirtyTiles.remove(key);
      _logMemoryStats('rasterizeTile-empty');
      return;
    }

    // 🗑️ LRU eviction PRIMA di aggiungere nuovo tile
    _evictOldestTilesBeforeAdd();

    // Create recorder per registrare disegno
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Scala per HiDPI
    canvas.scale(devicePixelRatio);

    // Translate to position tile at origin
    canvas.translate(-tileX * tileSize, -tileY * tileSize);

    // 📦 BATCH RENDERING: group strokes by penType/color/width,
    // then draw each batch in a single pass (ballpoint combined into 1 path).
    final optimizer = AdvancedTileOptimizer.instance;
    final batches = optimizer.batchStrokes(strokesInTile);
    for (final entry in batches.entries) {
      optimizer.drawStrokeBatch(canvas, entry.key, entry.value);
    }

    final picture = recorder.endRecording();
    _totalPicturesCreated++;

    // Rasterize a size HiDPI
    final pixelWidth = (tileSize * devicePixelRatio).ceil();
    final pixelHeight = (tileSize * devicePixelRatio).ceil();

    // toImageSync is synchronous - no lag!
    final image = picture.toImageSync(pixelWidth, pixelHeight);
    _totalImagesCreated++;

    // 🗑️ CRITICAL: Dispose picture dopo rasterizzazione to avoid memory leak
    picture.dispose();
    _totalPicturesDisposed++;

    // Add alla cache (ora c'è spazio garantito)
    _tileCache[key] = image;
    _tileStrokeCounts[key] = strokesInTile.length;
    _dirtyTiles.remove(key);

    _logMemoryStats('rasterizeTile-end');
  }

  /// 🚀 INCREMENTAL UPDATE: Sovrappone un singolo stroke a un existing tile
  ///
  /// Invece di ri-rasterizzare TUTTI gli strokes nel tile, disegna solo
  /// il nuovo stroke sopra la bitmap cached. O(1) per stroke vs O(N) full.
  ///
  /// Returns true se l'update incrementale is riuscito, false se serve full.
  bool incrementalUpdateTile(
    int tileX,
    int tileY,
    ProStroke newStroke,
    double devicePixelRatio,
  ) {
    final key = _tileKey(tileX, tileY);
    final existingImage = _tileCache[key];

    // If non c'è un tile cached, serve full rasterization
    if (existingImage == null) return false;

    _devicePixelRatio = devicePixelRatio;
    final pixelWidth = (tileSize * devicePixelRatio).ceil();
    final pixelHeight = (tileSize * devicePixelRatio).ceil();

    // Create recorder e disegna la bitmap esistente + il nuovo stroke
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Draw bitmap esistente (without scaling — already a size HiDPI)
    canvas.drawImage(existingImage, Offset.zero, Paint());

    // 2. Overlay the new stroke (with HiDPI scaling + tile translation)
    canvas.scale(devicePixelRatio);
    canvas.translate(-tileX * tileSize, -tileY * tileSize);
    _drawStroke(canvas, newStroke);

    final picture = recorder.endRecording();
    _totalPicturesCreated++;

    // Rasterize composito
    final newImage = picture.toImageSync(pixelWidth, pixelHeight);
    _totalImagesCreated++;

    picture.dispose();
    _totalPicturesDisposed++;

    // Dispose vecchia immagine e sostituisci
    _tileCache.remove(key);
    existingImage.dispose();
    _totalImagesDisposed++;

    _tileCache[key] = newImage;
    _tileStrokeCounts[key] = (_tileStrokeCounts[key] ?? 0) + 1;
    _dirtyTiles.remove(key);

    return true;
  }

  /// Draws uno stroke on the canvas a quality massima (zero LOD)
  void _drawStroke(Canvas canvas, ProStroke stroke) {
    // Get punti (lazy loading se configurato)
    final points = StrokeDataManager.getPoints(
      stroke.id,
      fallbackPoints: stroke.points,
    );
    if (points.isEmpty) return;

    BrushEngine.renderStroke(
      canvas,
      points,
      stroke.color,
      stroke.baseWidth,
      stroke.penType,
      stroke.settings,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🖼️ RENDERING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Draws tutti i visible tiles on the canvas
  ///
  /// [canvas]: Canvas su cui disegnare
  /// [viewport]: Current viewport in canvas coordinates
  /// [scale]: Scala corrente of the canvas
  void paintVisibleTiles(Canvas canvas, Rect viewport, double scale) {
    final visibleTiles = getVisibleTiles(viewport);

    for (final (tileX, tileY) in visibleTiles) {
      final key = _tileKey(tileX, tileY);
      final image = _tileCache[key];

      if (image != null) {
        // Update accesso per LRU
        _touchTile(key);

        // Calculate position destinazione
        final destRect = Rect.fromLTWH(
          tileX * tileSize,
          tileY * tileSize,
          tileSize,
          tileSize,
        );

        // Draw tile scalato correttamente
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          destRect,
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    }
  }

  /// 🚀 Draw TUTTI i tile in cache on the canvas
  ///
  /// Used when paint() is called only on stroke changes (not on pan/zoom).
  /// The Transform widget composites the canvas layer → ALL tiles are needed
  /// because la GPU li mostrerà quando l'utente panna.
  /// Costo: 1 drawImageRect per tile cached (max 32) — trascurabile.
  void paintAllCachedTiles(Canvas canvas) {
    final tilePaint = Paint()..filterQuality = FilterQuality.medium;

    for (final entry in _tileCache.entries) {
      final key = entry.key;
      final image = entry.value;

      // Parse tile coordinates from key "x:y"
      final parts = key.split(':');
      if (parts.length != 2) continue;
      final tileX = int.tryParse(parts[0]);
      final tileY = int.tryParse(parts[1]);
      if (tileX == null || tileY == null) continue;

      final destRect = Rect.fromLTWH(
        tileX * tileSize,
        tileY * tileSize,
        tileSize,
        tileSize,
      );

      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        destRect,
        tilePaint,
      );
    }
  }

  /// Updates ordine LRU for a tile
  void _touchTile(String key) {
    if (_tileCache.containsKey(key)) {
      final image = _tileCache.remove(key);
      if (image != null) {
        _tileCache[key] = image;
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔄 INVALIDAZIONE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Invalidate un singolo tile (will come ri-rasterizzato al prossimo paint)
  void invalidateTile(int tileX, int tileY) {
    final key = _tileKey(tileX, tileY);
    _dirtyTiles.add(key);

    // 🗑️ CRITICAL FIX: Dispose image quando invalidiamo il tile
    // The vecchia image non serve more, will come ri-rasterizzata
    final oldImage = _tileCache[key];
    if (oldImage != null) {
      _tileCache.remove(key);
      _tileStrokeCounts.remove(key);

      // 🐛 FIX: Dispose IMMEDIATO (non Future.microtask) to avoid leak
      oldImage.dispose();
      _totalImagesDisposed++;
    }
    _logMemoryStats('invalidateTile');
  }

  /// Invalidate tutti i tile che contengono un certo stroke
  void invalidateTilesForStroke(ProStroke stroke) {
    final bounds = stroke.bounds;
    if (bounds == Rect.zero) return;

    for (final (tileX, tileY) in getTilesForBounds(bounds)) {
      invalidateTile(tileX, tileY);
    }
  }

  /// Invalidate tutti i tile che intersecano un bounds
  void invalidateTilesInBounds(Rect bounds) {
    for (final (tileX, tileY) in getTilesForBounds(bounds)) {
      invalidateTile(tileX, tileY);
    }
  }

  /// Gets i tile che devono essere aggiornati
  Set<String> get dirtyTiles => Set.unmodifiable(_dirtyTiles);

  /// Checks if a specific tile is dirty
  bool isTileDirty(int tileX, int tileY) {
    return _dirtyTiles.contains(_tileKey(tileX, tileY));
  }

  /// Checks if a tile is in cache
  bool hasTileCached(int tileX, int tileY) {
    return _tileCache.containsKey(_tileKey(tileX, tileY));
  }

  /// Gets il number of strokes cached for a tile (0 if not in cache)
  int getTileStrokeCount(int tileX, int tileY) {
    return _tileStrokeCounts[_tileKey(tileX, tileY)] ?? 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🗑️ LRU EVICTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// 🗑️ Removes tile per fare spazio PRIMA di aggiungerne uno nuovo
  void _evictOldestTilesBeforeAdd() {
    if (_tileCache.length < maxCachedTiles) return;

    int evicted = 0;

    // Evict se siamo already al limite (per fare spazio al nuovo)
    while (_tileCache.length >= maxCachedTiles) {
      final oldestKey = _tileCache.keys.first;
      final oldImage = _tileCache[oldestKey];
      if (oldImage != null) {
        // 🐛 DEBUG: Dispose IMMEDIATO invece di Future.microtask
        oldImage.dispose();
        _totalImagesDisposed++;
        evicted++;
      }
      _tileCache.remove(oldestKey);
      _tileStrokeCounts.remove(oldestKey);

      _dirtyTiles.remove(oldestKey);
    }

    _logMemoryStats('evictOldest');
  }

  /// Forza eviction di tile lontani dal viewport
  void evictDistantTiles(Rect viewport) {
    final visibleTiles =
        getVisibleTiles(viewport).map((t) => _tileKey(t.$1, t.$2)).toSet();

    final keysToRemove = <String>[];
    for (final key in _tileCache.keys) {
      if (!visibleTiles.contains(key)) {
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      final oldImage = _tileCache[key];
      if (oldImage != null) {
        // 🐛 DEBUG: Dispose IMMEDIATO
        oldImage.dispose();
        _totalImagesDisposed++;
      }
      _tileCache.remove(key);
      _tileStrokeCounts.remove(key);

      _dirtyTiles.remove(key);
    }

    _logMemoryStats('evictDistant');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📊 STATISTICHE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Number of tile attualmente in cache
  int get cachedTileCount => _tileCache.length;

  /// Number of tile dirty
  int get dirtyTileCount => _dirtyTiles.length;

  /// Memoria stimata usata from the cache (in bytes)
  int get estimatedMemoryUsage {
    int total = 0;
    for (final image in _tileCache.values) {
      total += image.width * image.height * 4; // 4 bytes per pixel (RGBA)
    }
    return total;
  }

  /// Statistics for debugging
  Map<String, dynamic> get stats => {
    'cachedTiles': cachedTileCount,
    'dirtyTiles': dirtyTileCount,
    'memoryMB': (estimatedMemoryUsage / 1024 / 1024).toStringAsFixed(1),
    'devicePixelRatio': _devicePixelRatio,
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧹 CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Invalidate tutti i tile (ricostruzione completa)
  void invalidateAll() {
    _dirtyTiles.addAll(_tileCache.keys);
  }

  /// Clears tutta la cache
  void clear() {
    // Dispose tutte le Image IMMEDIATAMENTE
    for (final image in _tileCache.values) {
      image.dispose();
      _totalImagesDisposed++;
    }
    _tileCache.clear();
    _dirtyTiles.clear();
    _tileStrokeCounts.clear();

    _logMemoryStats('clear');
  }

  /// Dispose del manager
  void dispose() {
    clear();
  }
}
