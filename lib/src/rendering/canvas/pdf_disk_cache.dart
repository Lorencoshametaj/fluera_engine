import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 💾 Persistent disk cache for rendered PDF bitmaps.
///
/// Enterprise features:
/// - **GZip compression**: ~10x smaller files (5.6MB RGBA → ~500KB .gz)
/// - **Compute isolate**: all I/O runs off main thread via [compute()]
/// - **Atomic writes**: `.tmp` → `rename()` prevents corruption on crash
/// - **Integrity check**: validates decompressed size matches expected RGBA
/// - **Disk budget**: LRU eviction when total exceeds [_kMaxDiskMB]
///
/// Filename format: `cache_{docId}_{page}_{w}x{h}.gz`
class PdfDiskCache {
  final String documentId;
  Directory? _cacheDir;

  /// Maximum total disk cache size in MB (across ALL documents).
  static const int _kMaxDiskMB = 200;

  /// 🗂️ In-memory manifest of known cache keys.
  ///
  /// Avoids `file.exists()` syscalls on every paint frame — O(1) hash lookup.
  /// Populated on init by scanning the cache directory.
  final Set<String> _manifest = {};

  PdfDiskCache({required this.documentId});

  /// Initialize the cache directory and populate the manifest.
  Future<void> _ensureInit() async {
    if (_cacheDir != null) return;
    final temp = await getTemporaryDirectory();
    _cacheDir = Directory('${temp.path}/nebula_pdf_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }

    // 🗂️ Scan existing files to populate manifest + cleanup stale .tmp
    try {
      await for (final entity in _cacheDir!.list()) {
        if (entity is File) {
          if (entity.path.endsWith('.tmp')) {
            // 🧹 Orphaned from crash during atomic write — delete
            await entity.delete();
          } else if (entity.path.endsWith('.gz')) {
            final basename = entity.path.split('/').last;
            if (basename.contains(documentId)) {
              _manifest.add(basename);
            }
          }
        }
      }
    } catch (_) {}
  }

  /// Key for a specific page/resolution.
  String _cacheKey(int pageIndex, int width, int height) =>
      'cache_${documentId}_${pageIndex}_${width}x${height}.gz';

  // ---------------------------------------------------------------------------
  // Load (compute isolate + decompress)
  // ---------------------------------------------------------------------------

  /// 📥 Load a cached image from disk (off main thread).
  ///
  /// Uses in-memory manifest for O(1) miss detection — no filesystem call
  /// if the page was never cached.
  Future<Uint8List?> load(int pageIndex, int width, int height) async {
    try {
      if (_cacheDir == null) await _ensureInit();

      // 🗂️ Fast O(1) manifest check — avoids stat() syscall on miss
      final key = _cacheKey(pageIndex, width, height);
      if (!_manifest.contains(key)) return null;

      final file = File('${_cacheDir!.path}/$key');
      final expectedBytes = width * height * 4;

      // 🚀 Read + decompress on compute isolate
      final result = await compute(
        _readAndDecompress,
        _DiskReadRequest(file.path, expectedBytes),
      );

      // If decompression failed (corrupt file), remove from manifest
      if (result == null) {
        _manifest.remove(key);
      }

      return result;
    } catch (e) {
      debugPrint('[PdfDiskCache] load error: $e');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Save (compute isolate + compress + atomic)
  // ---------------------------------------------------------------------------

  /// 💾 Save rendered pixels to disk (off main thread, compressed, atomic).
  Future<void> save(
    int pageIndex,
    int width,
    int height,
    Uint8List pixels,
  ) async {
    try {
      if (_cacheDir == null) await _ensureInit();
      final key = _cacheKey(pageIndex, width, height);
      final target = File('${_cacheDir!.path}/$key');

      // 🚀 Compress + write on compute isolate (atomic: .tmp → rename)
      await compute(_compressAndWrite, _DiskWriteRequest(target.path, pixels));

      // 🗂️ Update manifest
      _manifest.add(key);

      // 🧹 Enforce disk budget (fire-and-forget, runs async)
      _enforceDiskBudget();
    } catch (e) {
      debugPrint('[PdfDiskCache] save error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Disk budget enforcement
  // ---------------------------------------------------------------------------

  /// 🧹 Evict oldest cache files if total disk usage exceeds [_kMaxDiskMB].
  void _enforceDiskBudget() {
    Future(() async {
      try {
        final dir = _cacheDir;
        if (dir == null || !await dir.exists()) return;

        final files = <File>[];
        int totalBytes = 0;

        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.gz')) {
            files.add(entity);
            totalBytes += await entity.length();
          }
        }

        final maxBytes = _kMaxDiskMB * 1024 * 1024;
        if (totalBytes <= maxBytes) return;

        // Sort by modification time (oldest first)
        final stats = <File, FileStat>{};
        for (final f in files) {
          stats[f] = await f.stat();
        }
        files.sort((a, b) => stats[a]!.modified.compareTo(stats[b]!.modified));

        // Evict oldest until under budget
        for (final f in files) {
          if (totalBytes <= maxBytes) break;
          final size = await f.length();
          // 🗂️ Sync manifest before deleting
          final basename = f.path.split('/').last;
          _manifest.remove(basename);
          await f.delete();
          totalBytes -= size;
        }
      } catch (_) {}
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  File _getFile(int pageIndex, int width, int height) {
    return File('${_cacheDir!.path}/${_cacheKey(pageIndex, width, height)}');
  }

  /// 🧹 Clear all cached files for this document.
  Future<void> clear() async {
    try {
      if (_cacheDir == null) await _ensureInit();
      await for (final entity in _cacheDir!.list()) {
        if (entity is File && entity.path.contains(documentId)) {
          await entity.delete();
        }
      }
      // 🗂️ Clear manifest entries for this document
      _manifest.removeWhere((key) => key.contains(documentId));
    } catch (_) {}
  }
}

// =============================================================================
// Isolate-safe top-level functions (no closures captured)
// =============================================================================

/// Read compressed file and decompress. Returns null if integrity fails.
Uint8List? _readAndDecompress(_DiskReadRequest req) {
  try {
    final file = File(req.path);
    if (!file.existsSync()) return null;

    final compressed = file.readAsBytesSync();
    final decompressed = gzip.decode(compressed);
    final bytes = Uint8List.fromList(decompressed);

    // 🔒 Integrity check: RGBA = 4 bytes per pixel
    if (bytes.length != req.expectedBytes) {
      // Corrupt — delete the file
      try {
        file.deleteSync();
      } catch (_) {}
      return null;
    }

    return bytes;
  } catch (_) {
    return null;
  }
}

/// Compress pixel data and write atomically (.tmp → rename).
void _compressAndWrite(_DiskWriteRequest req) {
  try {
    final compressed = gzip.encode(req.pixels);
    final tmp = File('${req.path}.tmp');
    tmp.writeAsBytesSync(Uint8List.fromList(compressed), flush: true);
    tmp.renameSync(req.path);
  } catch (_) {
    // Silently fail — next render will re-cache
  }
}

/// Data class for isolate message passing (must be sendable).
class _DiskReadRequest {
  final String path;
  final int expectedBytes;
  _DiskReadRequest(this.path, this.expectedBytes);
}

/// Data class for isolate message passing (must be sendable).
class _DiskWriteRequest {
  final String path;
  final Uint8List pixels;
  _DiskWriteRequest(this.path, this.pixels);
}
