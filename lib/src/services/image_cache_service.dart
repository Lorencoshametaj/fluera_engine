import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/engine_scope.dart';

/// 🖼️ IMAGE CACHE SERVICE v2.0
/// Handles il caricamento e caching of images for the canvas
/// - Cache in memoria (veloce)
/// - Cache to disk persistente (sopravvive a restart app)
/// - LRU eviction automatica
/// - Decode ottimizzato
class ImageCacheService {
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static ImageCacheService get instance =>
      EngineScope.current.imageCacheService;

  /// Creates a new instance (used by [EngineScope]).
  ImageCacheService.create();

  // ====== CONFIGURATION ======
  static const int _maxMemoryCacheCount = 30; // Max immagini in RAM
  static const int _maxDiskCacheCount = 100; // Max immagini to disk
  static const int _maxDiskCacheSizeMB = 50; // Max size cache disco
  static const String _diskCacheDir = 'image_cache';
  static const String _lruMetadataKey = 'image_cache_lru_metadata';

  // ====== CACHE IN MEMORIA ======
  // Cache immagini: path -> ui.Image
  final Map<String, ui.Image> _imageCache = {};

  // LRU tracking memoria: path -> timestamp ultimo accesso
  final Map<String, DateTime> _memoryAccessTime = {};

  // Loading state: path -> Future
  final Map<String, Future<ui.Image?>> _loadingImages = {};

  // ====== CACHE SU DISCO ======
  Directory? _cacheDirectory;
  bool _initialized = false;

  // LRU metadata disco: hash -> {originalPath, size, lastAccess}
  Map<String, _DiskCacheEntry> _diskLruMetadata = {};

  /// Initializes il servizio (da chiamare all'avvio app)
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDirectory = Directory('${appDir.path}/$_diskCacheDir');

      if (!await _cacheDirectory!.exists()) {
        await _cacheDirectory!.create(recursive: true);
      }

      // Load LRU metadata da SharedPreferences
      await _loadLruMetadata();

      _initialized = true;
    } catch (e) {}
  }

  /// Get immagine da cache o caricala
  ui.Image? getCachedImage(String imagePath) {
    final cached = _imageCache[imagePath];
    if (cached != null) {
      // Update LRU timestamp
      _memoryAccessTime[imagePath] = DateTime.now();
    }
    return cached;
  }

  /// Loads immagine in modo asincrono
  /// Ordine: memoria → disco → file originale
  Future<ui.Image?> loadImage(String imagePath) async {
    // 1. Controlla cache memoria
    if (_imageCache.containsKey(imagePath)) {
      _memoryAccessTime[imagePath] = DateTime.now();
      return _imageCache[imagePath];
    }

    // If already in loading, attendi il Future esistente
    if (_loadingImages.containsKey(imagePath)) {
      return _loadingImages[imagePath];
    }

    // Start caricamento
    final loadingFuture = _loadImageInternal(imagePath);
    _loadingImages[imagePath] = loadingFuture;

    try {
      final image = await loadingFuture;
      if (image != null) {
        await _addToMemoryCache(imagePath, image);
      }
      return image;
    } finally {
      _loadingImages.remove(imagePath);
    }
  }

  /// Internal loading: disk → original file
  Future<ui.Image?> _loadImageInternal(String imagePath) async {
    await initialize();

    // 2. Controlla cache disco
    final diskImage = await _loadFromDiskCache(imagePath);
    if (diskImage != null) {
      return diskImage;
    }

    // 3. Load da file originale e salva in cache disco
    final image = await _loadImageFromFile(imagePath);
    if (image != null) {
      // Save in cache disco per futuri caricamenti
      await _saveToDiskCache(imagePath, image);
    }
    return image;
  }

  /// Loads immagine from the cache to disk
  Future<ui.Image?> _loadFromDiskCache(String imagePath) async {
    if (_cacheDirectory == null) return null;

    try {
      final hash = _hashPath(imagePath);
      final cacheFile = File('${_cacheDirectory!.path}/$hash.png');

      if (!await cacheFile.exists()) return null;

      // Update LRU timestamp
      _updateDiskLruAccess(hash);

      final bytes = await cacheFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      return null;
    }
  }

  /// Saves immagine in the cache to disk (come PNG)
  Future<void> _saveToDiskCache(String imagePath, ui.Image image) async {
    if (_cacheDirectory == null) return;

    try {
      // Clear cache se necessario
      await _performDiskCacheEviction();

      final hash = _hashPath(imagePath);
      final cacheFile = File('${_cacheDirectory!.path}/$hash.png');

      // Convert ui.Image → PNG bytes
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      await cacheFile.writeAsBytes(bytes);

      // Update LRU metadata
      _diskLruMetadata[hash] = _DiskCacheEntry(
        originalPath: imagePath,
        sizeBytes: bytes.length,
        lastAccess: DateTime.now(),
      );
      await _saveLruMetadata();
    } catch (e) {}
  }

  /// Loads immagine da file originale
  Future<ui.Image?> _loadImageFromFile(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 1200, // Limita size massima for performance
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      return null;
    }
  }

  /// Adds image to memory cache with LRU eviction
  Future<void> _addToMemoryCache(String imagePath, ui.Image image) async {
    // Eviction se cache piena
    if (_imageCache.length >= _maxMemoryCacheCount) {
      await _performMemoryCacheEviction();
    }

    _imageCache[imagePath] = image;
    _memoryAccessTime[imagePath] = DateTime.now();
  }

  /// Eviction LRU from the cache memoria
  Future<void> _performMemoryCacheEviction() async {
    if (_memoryAccessTime.isEmpty) return;

    // Find the least used 20%
    final entries =
        _memoryAccessTime.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    final toRemove = (entries.length * 0.2).ceil().clamp(1, entries.length);

    for (int i = 0; i < toRemove; i++) {
      final path = entries[i].key;
      final image = _imageCache.remove(path);
      _memoryAccessTime.remove(path);
      image?.dispose();
    }
  }

  /// Eviction LRU from the cache disco
  Future<void> _performDiskCacheEviction() async {
    if (_cacheDirectory == null) return;

    // Calculate size totale
    int totalSize = _diskLruMetadata.values.fold(
      0,
      (sum, e) => sum + e.sizeBytes,
    );
    final maxBytes = _maxDiskCacheSizeMB * 1024 * 1024;

    // If sotto limite e sotto max count, non serve eviction
    if (totalSize < maxBytes && _diskLruMetadata.length < _maxDiskCacheCount) {
      return;
    }

    // Sort per ultimo accesso (LRU first)
    final sortedEntries =
        _diskLruMetadata.entries.toList()
          ..sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));

    // Remove fino a essere sotto il 70% del limite
    final targetSize = (maxBytes * 0.7).toInt();
    final targetCount = (_maxDiskCacheCount * 0.7).toInt();

    for (final entry in sortedEntries) {
      if (totalSize <= targetSize && _diskLruMetadata.length <= targetCount) {
        break;
      }

      try {
        final cacheFile = File('${_cacheDirectory!.path}/${entry.key}.png');
        if (await cacheFile.exists()) {
          await cacheFile.delete();
        }
        totalSize -= entry.value.sizeBytes;
        _diskLruMetadata.remove(entry.key);
      } catch (e) {}
    }

    await _saveLruMetadata();
  }

  /// Updates timestamp accesso disco
  void _updateDiskLruAccess(String hash) {
    final entry = _diskLruMetadata[hash];
    if (entry != null) {
      _diskLruMetadata[hash] = _DiskCacheEntry(
        originalPath: entry.originalPath,
        sizeBytes: entry.sizeBytes,
        lastAccess: DateTime.now(),
      );
      // Save async (non bloccare)
      _saveLruMetadata();
    }
  }

  /// Genera hash del path per nome file cache
  String _hashPath(String path) {
    final bytes = utf8.encode(path);
    return md5.convert(bytes).toString();
  }

  /// Loads LRU metadata da SharedPreferences
  Future<void> _loadLruMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_lruMetadataKey);
      if (json != null) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        _diskLruMetadata = data.map(
          (k, v) => MapEntry(k, _DiskCacheEntry.fromJson(v)),
        );
      }
    } catch (e) {
      _diskLruMetadata = {};
    }
  }

  /// Saves LRU metadata in SharedPreferences
  Future<void> _saveLruMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _diskLruMetadata.map((k, v) => MapEntry(k, v.toJson()));
      await prefs.setString(_lruMetadataKey, jsonEncode(data));
    } catch (e) {}
  }

  /// Pre-carica una list of immagini
  Future<void> preloadImages(List<String> imagePaths) async {
    await Future.wait(imagePaths.map((path) => loadImage(path)));
  }

  /// Clears cache memoria
  void clearMemoryCache() {
    for (final image in _imageCache.values) {
      image.dispose();
    }
    _imageCache.clear();
    _memoryAccessTime.clear();
    _loadingImages.clear();
  }

  /// Clears cache disco
  Future<void> clearDiskCache() async {
    if (_cacheDirectory == null) return;

    try {
      if (await _cacheDirectory!.exists()) {
        await _cacheDirectory!.delete(recursive: true);
        await _cacheDirectory!.create(recursive: true);
      }
      _diskLruMetadata.clear();
      await _saveLruMetadata();
    } catch (e) {}
  }

  /// Clears the entire cache (memoria + disco)
  Future<void> clearCache() async {
    clearMemoryCache();
    await clearDiskCache();
  }

  /// Remove singola immagine from the cache (memoria + disco)
  Future<void> removeFromCache(String imagePath) async {
    // Remove da memoria
    final image = _imageCache.remove(imagePath);
    _memoryAccessTime.remove(imagePath);
    image?.dispose();

    // Remove da disco
    if (_cacheDirectory != null) {
      try {
        final hash = _hashPath(imagePath);
        final cacheFile = File('${_cacheDirectory!.path}/$hash.png');
        if (await cacheFile.exists()) {
          await cacheFile.delete();
        }
        _diskLruMetadata.remove(hash);
        await _saveLruMetadata();
      } catch (e) {}
    }
  }

  /// Size cache memoria (numero immagini)
  int get memoryCacheSize => _imageCache.length;

  /// Size cache disco (numero file)
  int get diskCacheSize => _diskLruMetadata.length;

  /// Size cache disco in bytes
  int get diskCacheSizeBytes =>
      _diskLruMetadata.values.fold(0, (sum, e) => sum + e.sizeBytes);

  /// Statistiche cache
  Map<String, dynamic> get cacheStats => {
    'memoryCacheCount': memoryCacheSize,
    'diskCacheCount': diskCacheSize,
    'diskCacheSizeMB': (diskCacheSizeBytes / 1024 / 1024).toStringAsFixed(2),
    'maxMemoryCacheCount': _maxMemoryCacheCount,
    'maxDiskCacheCount': _maxDiskCacheCount,
    'maxDiskCacheSizeMB': _maxDiskCacheSizeMB,
  };

  // Legacy getter per retrocompatibility
  int get cacheSize => memoryCacheSize;

  /// Reset singleton state for testing. Clears all caches without disk I/O.
  @visibleForTesting
  void resetForTesting() {
    for (final image in _imageCache.values) {
      image.dispose();
    }
    _imageCache.clear();
    _memoryAccessTime.clear();
    _loadingImages.clear();
    _diskLruMetadata.clear();
    _initialized = false;
    _cacheDirectory = null;
  }
}

/// Entry metadata per cache disco
class _DiskCacheEntry {
  final String originalPath;
  final int sizeBytes;
  final DateTime lastAccess;

  _DiskCacheEntry({
    required this.originalPath,
    required this.sizeBytes,
    required this.lastAccess,
  });

  Map<String, dynamic> toJson() => {
    'path': originalPath,
    'size': sizeBytes,
    'ts': lastAccess.millisecondsSinceEpoch,
  };

  factory _DiskCacheEntry.fromJson(Map<String, dynamic> json) =>
      _DiskCacheEntry(
        originalPath: json['path'] as String,
        sizeBytes: json['size'] as int,
        lastAccess: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
      );
}
