import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart' as archive_lib;
import 'package:flutter/foundation.dart';
import '../utils/safe_path_provider.dart';

// =============================================================================
// 📦 SHERPA MODEL MANAGER
//
// On-demand download and caching of Sherpa-ONNX ASR models.
// Downloads from GitHub releases, extracts to app support directory,
// and tracks download progress.
// =============================================================================

/// Available ASR model configurations.
enum SherpaModelType {
  /// Whisper base — multilingual, ~74MB, good accuracy.
  whisperBase,

  /// Whisper tiny — multilingual, ~39MB, faster but lower accuracy.
  whisperTiny,

  /// Whisper small — multilingual, ~244MB, highest accuracy.
  whisperSmall,

  /// Zipformer streaming — multilingual, ~13MB, real-time streaming.
  zipformerStreaming,
}

/// Information about a downloadable model.
class SherpaModelInfo {
  final SherpaModelType type;
  final String displayName;
  final String downloadUrl; // Legacy tar.bz2 URL (for whisper models)
  final String directoryName;
  final int approximateSizeMb;
  final List<String> supportedLanguages;
  /// 🚀 Direct file download: list of files to download individually
  /// from HuggingFace (no tar.bz2 extraction needed)
  final List<String>? modelFiles;
  final String? huggingFaceRepo;

  const SherpaModelInfo({
    required this.type,
    required this.displayName,
    required this.downloadUrl,
    required this.directoryName,
    required this.approximateSizeMb,
    required this.supportedLanguages,
    this.modelFiles,
    this.huggingFaceRepo,
  });

  /// Whether this model uses direct file download (no archive extraction).
  bool get usesDirectDownload => modelFiles != null && huggingFaceRepo != null;
}

/// Download progress information.
class ModelDownloadProgress {
  final double progress; // 0.0–1.0
  final int downloadedBytes;
  final int totalBytes;
  final String status; // 'downloading', 'extracting', 'ready', 'error'
  final String? error;

  const ModelDownloadProgress({
    required this.progress,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.status,
    this.error,
  });

  factory ModelDownloadProgress.initial() => const ModelDownloadProgress(
    progress: 0.0,
    downloadedBytes: 0,
    totalBytes: 0,
    status: 'idle',
  );

  factory ModelDownloadProgress.error(String message) => ModelDownloadProgress(
    progress: 0.0,
    downloadedBytes: 0,
    totalBytes: 0,
    status: 'error',
    error: message,
  );

  bool get isComplete => status == 'ready';
  bool get hasError => status == 'error';
  bool get isDownloading => status == 'downloading';
  bool get isExtracting => status == 'extracting';
}

/// Manages on-demand download and caching of Sherpa-ONNX models.
///
/// Models are stored in `<appSupportDir>/sherpa_models/<modelDir>/`.
/// Uses streaming HTTP download with progress tracking.
///
/// ```dart
/// final manager = SherpaModelManager.instance;
///
/// if (!await manager.isModelAvailable(SherpaModelType.whisperBase)) {
///   await for (final progress in manager.downloadModel(SherpaModelType.whisperBase)) {
///     print('Download: ${(progress.progress * 100).toInt()}%');
///   }
/// }
///
/// final modelDir = await manager.getModelDirectory(SherpaModelType.whisperBase);
/// ```
class SherpaModelManager {
  SherpaModelManager._();

  static final SherpaModelManager instance = SherpaModelManager._();

  /// Base URL for model downloads (GitHub releases).
  static const String _baseUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models';

  /// Available model configurations.
  static const Map<SherpaModelType, SherpaModelInfo> models = {
    SherpaModelType.whisperBase: SherpaModelInfo(
      type: SherpaModelType.whisperBase,
      displayName: 'Whisper Base (Multilingual)',
      downloadUrl:
          '$_baseUrl/sherpa-onnx-whisper-base.tar.bz2',
      directoryName: 'sherpa-onnx-whisper-base',
      approximateSizeMb: 74,
      supportedLanguages: [
        'auto', 'en', 'it', 'de', 'fr', 'es', 'pt', 'nl',
        'ja', 'ko', 'zh', 'ru', 'ar', 'hi', 'pl', 'uk',
        'tr', 'sv', 'da', 'no', 'fi', 'cs', 'ro', 'hu',
      ],
    ),
    SherpaModelType.whisperTiny: SherpaModelInfo(
      type: SherpaModelType.whisperTiny,
      displayName: 'Whisper Tiny (Multilingual)',
      downloadUrl:
          '$_baseUrl/sherpa-onnx-whisper-tiny.tar.bz2',
      directoryName: 'sherpa-onnx-whisper-tiny',
      approximateSizeMb: 39,
      supportedLanguages: [
        'auto', 'en', 'it', 'de', 'fr', 'es', 'pt', 'nl',
        'ja', 'ko', 'zh', 'ru', 'ar', 'hi', 'pl', 'uk',
      ],
    ),
    SherpaModelType.whisperSmall: SherpaModelInfo(
      type: SherpaModelType.whisperSmall,
      displayName: 'Whisper Small (Multilingual)',
      downloadUrl:
          '$_baseUrl/sherpa-onnx-whisper-small.tar.bz2',
      directoryName: 'sherpa-onnx-whisper-small',
      approximateSizeMb: 244,
      supportedLanguages: [
        'auto', 'en', 'it', 'de', 'fr', 'es', 'pt', 'nl',
        'ja', 'ko', 'zh', 'ru', 'ar', 'hi', 'pl', 'uk',
        'tr', 'sv', 'da', 'no', 'fi', 'cs', 'ro', 'hu',
      ],
    ),
    SherpaModelType.zipformerStreaming: SherpaModelInfo(
      type: SherpaModelType.zipformerStreaming,
      displayName: 'Zipformer Streaming (English)',
      downloadUrl: '', // Not used — direct file download
      directoryName: 'sherpa-onnx-streaming-zipformer-en-20M-2023-02-17',
      approximateSizeMb: 88,
      supportedLanguages: ['en'],
      huggingFaceRepo: 'csukuangfj/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17',
      modelFiles: [
        'encoder-epoch-99-avg-1.onnx',
        'decoder-epoch-99-avg-1.onnx',
        'joiner-epoch-99-avg-1.onnx',
        'tokens.txt',
      ],
    ),
  };

  /// Supported language display names.
  static const Map<String, String> languageNames = {
    'auto': 'Auto-detect',
    'en': 'English',
    'it': 'Italiano',
    'de': 'Deutsch',
    'fr': 'Français',
    'es': 'Español',
    'pt': 'Português',
    'nl': 'Nederlands',
    'ja': '日本語',
    'ko': '한국어',
    'zh': '中文',
    'ru': 'Русский',
    'ar': 'العربية',
    'hi': 'हिन्दी',
    'pl': 'Polski',
    'uk': 'Українська',
    'tr': 'Türkçe',
    'sv': 'Svenska',
    'da': 'Dansk',
    'no': 'Norsk',
    'fi': 'Suomi',
    'cs': 'Čeština',
    'ro': 'Română',
    'hu': 'Magyar',
  };

  String? _modelBaseDir;

  /// Get the base directory for model storage.
  Future<String> _getModelBaseDir() async {
    if (_modelBaseDir != null) return _modelBaseDir!;
    final appDir = await getSafeAppSupportDirectory();
    if (appDir == null) {
      throw StateError('Cannot access app support directory');
    }
    final modelsDir = Directory('${appDir.path}/sherpa_models');
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }
    _modelBaseDir = modelsDir.path;
    return _modelBaseDir!;
  }

  /// Check if a model is already downloaded and available.
  Future<bool> isModelAvailable(SherpaModelType type) async {
    try {
      final info = models[type]!;
      final baseDir = await _getModelBaseDir();
      final modelDir = Directory('$baseDir/${info.directoryName}');
      if (!modelDir.existsSync()) return false;

      // Streaming models have transducer files, Whisper has encoder/decoder
      if (type == SherpaModelType.zipformerStreaming) {
        final tokensFile = File('$baseDir/${info.directoryName}/tokens.txt');
        return tokensFile.existsSync();
      }

      // Check for essential model files
      final encoderFile = File(
        '$baseDir/${info.directoryName}/${info.directoryName}-encoder.onnx',
      );
      final decoderFile = File(
        '$baseDir/${info.directoryName}/${info.directoryName}-decoder.onnx',
      );
      // Whisper has encoder + decoder
      return encoderFile.existsSync() || decoderFile.existsSync();
    } catch (e) {
      return false;
    }
  }

  /// Get the local directory path for a model.
  ///
  /// Returns `null` if the model is not downloaded.
  Future<String?> getModelDirectory(SherpaModelType type) async {
    if (!await isModelAvailable(type)) return null;
    final baseDir = await _getModelBaseDir();
    final info = models[type]!;
    return '$baseDir/${info.directoryName}';
  }

  /// Download a model with progress tracking.
  ///
  /// Returns a stream of [ModelDownloadProgress] events.
  /// The last event will have `status == 'ready'` on success.
  Stream<ModelDownloadProgress> downloadModel(SherpaModelType type) async* {
    final info = models[type]!;

    yield ModelDownloadProgress.initial();

    try {
      final baseDir = await _getModelBaseDir();
      final targetDir = Directory('$baseDir/${info.directoryName}');

      // If already available, return immediately
      if (await isModelAvailable(type)) {
        yield const ModelDownloadProgress(
          progress: 1.0,
          downloadedBytes: 0,
          totalBytes: 0,
          status: 'ready',
        );
        return;
      }

      // 🚀 Direct file download (no tar.bz2 extraction needed)
      if (info.usesDirectDownload) {
        yield* _downloadDirectFiles(info, targetDir);
        return;
      }

      // Legacy: tar.bz2 archive download (for whisper models)
      yield* _downloadArchive(info, baseDir, targetDir);
    } catch (e) {
      debugPrint('📥 Download error: $e');
      yield ModelDownloadProgress.error('Download error: $e');
    }
  }

  /// 🚀 Download individual model files directly from HuggingFace.
  /// No archive extraction — each file is saved directly to disk.
  Stream<ModelDownloadProgress> _downloadDirectFiles(
    SherpaModelInfo info,
    Directory targetDir,
  ) async* {
    final files = info.modelFiles!;
    final repo = info.huggingFaceRepo!;
    final totalFiles = files.length;
    int completedFiles = 0;
    int totalDownloaded = 0;
    final estimatedTotal = info.approximateSizeMb * 1024 * 1024;

    // Create target directory
    await targetDir.create(recursive: true);

    final client = HttpClient()..autoUncompress = false;
    try {
      for (final fileName in files) {
        final url = 'https://huggingface.co/$repo/resolve/main/$fileName';
        debugPrint('📥 [$completedFiles/$totalFiles] $fileName');

        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();

        if (response.statusCode != 200) {
          await response.drain<void>();
          debugPrint('📥 HTTP ${response.statusCode} for $fileName');
          yield ModelDownloadProgress.error(
            'Download failed: HTTP ${response.statusCode} for $fileName',
          );
          // Clean up partial download
          if (targetDir.existsSync()) await targetDir.delete(recursive: true);
          return;
        }

        // Stream file to disk
        final outFile = File('${targetDir.path}/$fileName');
        final sink = outFile.openWrite();
        DateTime lastYield = DateTime.now();

        await for (final chunk in response) {
          sink.add(chunk);
          totalDownloaded += chunk.length;

          // Throttled progress yield (max 5/sec)
          final now = DateTime.now();
          if (now.difference(lastYield).inMilliseconds >= 200) {
            lastYield = now;
            final progress = (totalDownloaded / estimatedTotal).clamp(0.0, 0.99);
            yield ModelDownloadProgress(
              progress: progress,
              downloadedBytes: totalDownloaded,
              totalBytes: estimatedTotal,
              status: 'downloading',
            );
          }
        }
        await sink.flush();
        await sink.close();

        completedFiles++;
        debugPrint('📥 ✅ $fileName (${(totalDownloaded / 1024 / 1024).toStringAsFixed(1)} MB)');
      }
    } finally {
      client.close();
    }

    // Verify
    if (targetDir.existsSync()) {
      debugPrint('📥 All ${files.length} files downloaded successfully');
      yield ModelDownloadProgress(
        progress: 1.0,
        downloadedBytes: totalDownloaded,
        totalBytes: totalDownloaded,
        status: 'ready',
      );
    } else {
      yield ModelDownloadProgress.error('Download verification failed');
    }
  }

  /// Legacy: download tar.bz2 archive and extract.
  Stream<ModelDownloadProgress> _downloadArchive(
    SherpaModelInfo info,
    String baseDir,
    Directory targetDir,
  ) async* {
    final tempFile = File('$baseDir/${info.directoryName}.tar.bz2');
    final client = HttpClient()..autoUncompress = false;
    try {
      debugPrint('📥 Download URL: ${info.downloadUrl}');
      final request = await client.getUrl(Uri.parse(info.downloadUrl));
      final response = await request.close();

      debugPrint('📥 HTTP status: ${response.statusCode}, content-length: ${response.contentLength}');

      if (response.statusCode != 200) {
        await response.drain<void>();
        yield ModelDownloadProgress.error('Download failed: HTTP ${response.statusCode}');
        return;
      }

      // Stream to disk with throttled progress
      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : info.approximateSizeMb * 1024 * 1024;
      int downloadedBytes = 0;
      DateTime lastYield = DateTime.now();

      final sink = tempFile.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastYield).inMilliseconds >= 200) {
            lastYield = now;
            yield ModelDownloadProgress(
              progress: (downloadedBytes / totalBytes).clamp(0.0, 0.8),
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes,
              status: 'downloading',
            );
          }
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        await sink.close();
        yield ModelDownloadProgress.error('Download stream error: $e');
        return;
      }

      // Extract
      yield ModelDownloadProgress(progress: 0.85, downloadedBytes: downloadedBytes, totalBytes: totalBytes, status: 'extracting');
      try {
        final bytes = await tempFile.readAsBytes();
        final files = await compute(_extractTarBz2, bytes);
        for (final entry in files.entries) {
          final outFile = File('$baseDir/${entry.key}');
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.value);
        }
        debugPrint('📦 Extracted ${files.length} files');
      } catch (e) {
        debugPrint('📦 Extraction error: $e');
        yield ModelDownloadProgress.error('Extraction error: $e');
        return;
      }
      if (tempFile.existsSync()) await tempFile.delete();

      if (targetDir.existsSync()) {
        yield ModelDownloadProgress(progress: 1.0, downloadedBytes: downloadedBytes, totalBytes: totalBytes, status: 'ready');
      } else {
        yield ModelDownloadProgress.error('Extraction failed: directory not found');
      }
    } finally {
      client.close();
    }
  }

  /// Delete a downloaded model to free disk space.
  Future<bool> deleteModel(SherpaModelType type) async {
    try {
      final modelDir = await getModelDirectory(type);
      if (modelDir == null) return false;
      final dir = Directory(modelDir);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get the disk space used by a downloaded model (in bytes).
  Future<int> getModelSize(SherpaModelType type) async {
    try {
      final modelDir = await getModelDirectory(type);
      if (modelDir == null) return 0;
      final dir = Directory(modelDir);
      if (!dir.existsSync()) return 0;

      int totalSize = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  /// Get info about all available models with their download status.
  Future<List<ModelStatus>> getModelStatuses() async {
    final statuses = <ModelStatus>[];
    for (final entry in models.entries) {
      final available = await isModelAvailable(entry.key);
      final size = available ? await getModelSize(entry.key) : 0;
      statuses.add(
        ModelStatus(
          info: entry.value,
          isDownloaded: available,
          diskSizeBytes: size,
        ),
      );
    }
    return statuses;
  }
}

/// Status of a model (downloaded or not).
class ModelStatus {
  final SherpaModelInfo info;
  final bool isDownloaded;
  final int diskSizeBytes;

  const ModelStatus({
    required this.info,
    required this.isDownloaded,
    required this.diskSizeBytes,
  });

  String get diskSizeFormatted {
    if (diskSizeBytes == 0) return '—';
    if (diskSizeBytes < 1024 * 1024) {
      return '${(diskSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(diskSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Top-level function for `compute()` — extracts tar.bz2 archive in isolate.
/// Returns a Map<String, Uint8List> of relative path → file bytes.
Map<String, Uint8List> _extractTarBz2(Uint8List archiveBytes) {
  // Step 1: Decompress bzip2
  final decompressed = archive_lib.BZip2Decoder().decodeBytes(archiveBytes);

  // Step 2: Decode tar
  final tarArchive = archive_lib.TarDecoder().decodeBytes(decompressed);

  // Step 3: Extract files (skip directories)
  final result = <String, Uint8List>{};
  for (final file in tarArchive.files) {
    if (file.isFile) {
      result[file.name] = Uint8List.fromList(file.content as List<int>);
    }
  }
  return result;
}
