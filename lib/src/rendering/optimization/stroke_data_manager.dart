import 'dart:collection';
import '../../drawing/models/pro_drawing_point.dart';

/// 🚀 STROKE DATA MANAGER - Lazy loading of points per 1M+ strokes
///
/// PROBLEMA:
/// 1M strokes × 100 punti × ~10 bytes/punto = 1GB di RAM just for points!
///
/// SOLUZIONE:
/// - Mantieni SOLO bounds + metadata in memoria (~64 bytes/stroke)
/// - Load complete points ONLY when needed (tile visibile)
/// - Evict points not used for a while (LRU)
///
/// MEMORIA (1M strokes):
/// - Before: ~1GB (all points in memory)
/// - After: ~64MB (bounds only) + ~10MB (visible points)
///
/// ARCHITETTURA:
/// - StrokeDataManager manages loading/eviction
/// - ProStroke can essere "lazy" (solo bounds) o "loaded" (con punti)
/// - TileCacheManager richiede punti only when rasterizza
class StrokeDataManager {
  // ═══════════════════════════════════════════════════════════════════════════
  // 📐 CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Maximum number di stroke con punti caricati in memoria
  /// Each stroke ha in media ~100 punti × 10 bytes = 1KB
  /// 10000 strokes loaded = ~10MB di punti in memoria
  static const int maxLoadedStrokes = 10000;

  /// Lifetime of points in cache after last access (ms)
  static const int pointsEvictionTimeMs = 30000; // 30 secondi

  // ═══════════════════════════════════════════════════════════════════════════
  // 🗂️ CACHE STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Cache LRU: strokeId -> punti caricati
  /// LinkedHashMap per LRU eviction automatica
  static final LinkedHashMap<String, List<ProDrawingPoint>> _pointsCache =
      LinkedHashMap();

  /// Last access timestamp for each stroke
  static final Map<String, int> _lastAccessTime = {};

  /// Callback for loading points from storage (impostato da FlueraLayerController)
  static Future<List<ProDrawingPoint>> Function(String strokeId)? _pointsLoader;

  /// Storage locale of points per strokes (usato come fallback)
  static final Map<String, List<ProDrawingPoint>> _permanentStorage = {};

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 INIZIALIZZAZIONE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sets il loader to load points on-demand
  /// This is called by FlueraLayerController when needed
  static void setPointsLoader(
    Future<List<ProDrawingPoint>> Function(String strokeId) loader,
  ) {
    _pointsLoader = loader;
  }

  /// Regisamong the punti di uno stroke nel permanent storage
  /// Called when ao stroke is created/aggiunto
  static void registerStrokePoints(
    String strokeId,
    List<ProDrawingPoint> points,
  ) {
    _permanentStorage[strokeId] = points;
    // Also in cache per accesso immediato
    _cachePoints(strokeId, points);
  }

  /// Removes uno stroke dal sistema (chiamato su delete/undo)
  static void unregisterStroke(String strokeId) {
    _permanentStorage.remove(strokeId);
    _pointsCache.remove(strokeId);
    _lastAccessTime.remove(strokeId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📥 LOADING PUNTI
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets i punti for ao stroke (carica se necessario)
  ///
  /// Questa is la funzione principale usata da TileCacheManager
  /// when it needs to rasterize a tile.
  ///
  /// [strokeId]: ID of the stroke
  /// [fallbackPoints]: Punti da usare if not in cache (per retrocompatibility)
  ///
  /// Returns: Lista di punti (mai null)
  static List<ProDrawingPoint> getPoints(
    String strokeId, {
    List<ProDrawingPoint>? fallbackPoints,
  }) {
    // 1. Controlla cache
    final cached = _pointsCache[strokeId];
    if (cached != null) {
      _touchStroke(strokeId);
      return cached;
    }

    // 2. Controlla permanent storage
    final stored = _permanentStorage[strokeId];
    if (stored != null) {
      _cachePoints(strokeId, stored);
      return stored;
    }

    // 3. Usa fallback se fornito
    if (fallbackPoints != null) {
      _cachePoints(strokeId, fallbackPoints);
      return fallbackPoints;
    }

    // 4. Return empty list (should never happen)
    return const [];
  }

  /// Async version for loading from external storage
  static Future<List<ProDrawingPoint>> getPointsAsync(String strokeId) async {
    // 1. Controlla cache
    final cached = _pointsCache[strokeId];
    if (cached != null) {
      _touchStroke(strokeId);
      return cached;
    }

    // 2. Controlla permanent storage
    final stored = _permanentStorage[strokeId];
    if (stored != null) {
      _cachePoints(strokeId, stored);
      return stored;
    }

    // 3. Prova loader esterno
    if (_pointsLoader != null) {
      try {
        final loaded = await _pointsLoader!(strokeId);
        _cachePoints(strokeId, loaded);
        return loaded;
      } catch (e) {
        // Fallback a empty list
        return const [];
      }
    }

    return const [];
  }

  /// Checks se i punti are already in cache (no loading necessario)
  static bool hasPointsCached(String strokeId) {
    return _pointsCache.containsKey(strokeId) ||
        _permanentStorage.containsKey(strokeId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🗑️ CACHE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Adds points to cache
  static void _cachePoints(String strokeId, List<ProDrawingPoint> points) {
    // Evict se necessario
    _evictOldest();

    _pointsCache[strokeId] = points;
    _touchStroke(strokeId);
  }

  /// Updates timestamp accesso
  static void _touchStroke(String strokeId) {
    _lastAccessTime[strokeId] = DateTime.now().millisecondsSinceEpoch;

    // Update ordine LRU
    if (_pointsCache.containsKey(strokeId)) {
      final points = _pointsCache.remove(strokeId);
      if (points != null) {
        _pointsCache[strokeId] = points;
      }
    }
  }

  /// Evict strokes meno usati se cache troppo grande
  static void _evictOldest() {
    while (_pointsCache.length >= maxLoadedStrokes) {
      final oldestKey = _pointsCache.keys.first;
      _pointsCache.remove(oldestKey);
      // NON rimuovere da permanent storage o lastAccessTime
    }
  }

  /// Evict strokes non usati da tempo
  static void evictStaleEntries() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final staleKeys = <String>[];

    for (final entry in _lastAccessTime.entries) {
      if (now - entry.value > pointsEvictionTimeMs) {
        staleKeys.add(entry.key);
      }
    }

    for (final key in staleKeys) {
      // Only from the cache, non dal permanent storage
      _pointsCache.remove(key);
    }
  }

  /// Pre-carica punti for aa list of stroke IDs
  /// Utile per pre-caricare strokes in un tile before rasterizzare
  static void preloadStrokes(List<String> strokeIds) {
    for (final id in strokeIds) {
      if (!_pointsCache.containsKey(id)) {
        final stored = _permanentStorage[id];
        if (stored != null) {
          _cachePoints(id, stored);
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📊 STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Number of strokes con punti in cache
  static int get cachedStrokesCount => _pointsCache.length;

  /// Numero totale di strokes registrati
  static int get totalStrokesCount => _permanentStorage.length;

  /// Memoria stimata usata from the cache punti (in bytes)
  static int get estimatedCacheMemory {
    int total = 0;
    for (final points in _pointsCache.values) {
      // ProDrawingPoint: ~40 bytes (position, pressure, tilt, timestamp)
      total += points.length * 40;
    }
    return total;
  }

  /// Statistics for debugging
  static Map<String, dynamic> get stats => {
    'cachedStrokes': cachedStrokesCount,
    'totalStrokes': totalStrokesCount,
    'maxCached': maxLoadedStrokes,
    'cacheMB': (estimatedCacheMemory / 1024 / 1024).toStringAsFixed(2),
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧹 CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Clears only the cache (mantiene permanent storage)
  static void clearCache() {
    _pointsCache.clear();
    _lastAccessTime.clear();
  }

  /// Clears everything (use with caution!)
  static void clearAll() {
    _pointsCache.clear();
    _lastAccessTime.clear();
    _permanentStorage.clear();
  }
}
