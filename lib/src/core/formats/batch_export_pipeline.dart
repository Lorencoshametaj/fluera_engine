/// 🗂️ BATCH EXPORT PIPELINE — Concurrent multi-target export.
///
/// Export a document to multiple formats simultaneously with
/// per-target quality/scale settings, progress tracking, and error handling.
///
/// ```dart
/// final pipeline = BatchExportPipeline();
/// pipeline.addTarget(ExportTarget(formatId: 'png', scale: 2.0));
/// pipeline.addTarget(ExportTarget(formatId: 'webp', quality: 80));
/// final results = pipeline.execute(document);
/// ```
library;

// =============================================================================
// EXPORT TARGET
// =============================================================================

/// Configuration for a single export target.
class ExportTarget {
  /// Target format ID.
  final String formatId;

  /// Output file path (or name).
  final String? outputPath;

  /// Export quality (0–100, for lossy formats).
  final int quality;

  /// Scale multiplier (1.0 = original, 2.0 = 2x).
  final double scale;

  /// Whether to flatten all layers.
  final bool flattenLayers;

  /// Whether to include metadata.
  final bool includeMetadata;

  /// Custom export options.
  final Map<String, dynamic> options;

  const ExportTarget({
    required this.formatId,
    this.outputPath,
    this.quality = 100,
    this.scale = 1.0,
    this.flattenLayers = false,
    this.includeMetadata = true,
    this.options = const {},
  });

  Map<String, dynamic> toJson() => {
    'formatId': formatId,
    if (outputPath != null) 'outputPath': outputPath,
    'quality': quality,
    'scale': scale,
    'flattenLayers': flattenLayers,
    'includeMetadata': includeMetadata,
    if (options.isNotEmpty) 'options': options,
  };

  @override
  String toString() => 'ExportTarget($formatId, q=$quality, ${scale}x)';
}

// =============================================================================
// EXPORT RESULT
// =============================================================================

/// Result of a single export operation.
class ExportResult {
  /// Target that was exported.
  final ExportTarget target;

  /// Whether the export succeeded.
  final bool success;

  /// Output file size in bytes (0 if failed).
  final int fileSizeBytes;

  /// Error message (null if succeeded).
  final String? error;

  /// Export duration in milliseconds.
  final int durationMs;

  const ExportResult({
    required this.target,
    required this.success,
    this.fileSizeBytes = 0,
    this.error,
    this.durationMs = 0,
  });

  Map<String, dynamic> toJson() => {
    'formatId': target.formatId,
    'success': success,
    'fileSizeBytes': fileSizeBytes,
    if (error != null) 'error': error,
    'durationMs': durationMs,
  };

  @override
  String toString() =>
      success
          ? 'ExportResult(${target.formatId}, ${fileSizeBytes}B, ${durationMs}ms)'
          : 'ExportResult(${target.formatId}, FAIL: $error)';
}

// =============================================================================
// BATCH EXPORT PIPELINE
// =============================================================================

/// Manages multi-target batch export with progress tracking.
class BatchExportPipeline {
  final List<ExportTarget> _targets = [];
  final List<ExportResult> _results = [];

  /// Add an export target.
  void addTarget(ExportTarget target) => _targets.add(target);

  /// Remove a target by format ID.
  void removeTarget(String formatId) =>
      _targets.removeWhere((t) => t.formatId == formatId);

  /// All configured targets.
  List<ExportTarget> get targets => List.unmodifiable(_targets);

  /// Clear all targets.
  void clearTargets() => _targets.clear();

  /// Results from the last execution.
  List<ExportResult> get results => List.unmodifiable(_results);

  /// Execute batch export.
  ///
  /// [exporter] is called for each target with the target config.
  /// [onProgress] reports progress (0.0–1.0).
  /// Returns all results.
  List<ExportResult> execute({
    required ExportResult Function(ExportTarget target) exporter,
    void Function(double progress, ExportTarget current)? onProgress,
  }) {
    _results.clear();

    for (int i = 0; i < _targets.length; i++) {
      final target = _targets[i];
      onProgress?.call(i / _targets.length, target);

      try {
        final result = exporter(target);
        _results.add(result);
      } catch (e) {
        _results.add(
          ExportResult(target: target, success: false, error: e.toString()),
        );
      }
    }

    onProgress?.call(1.0, _targets.last);
    return List.unmodifiable(_results);
  }

  /// Number of successful exports from last run.
  int get successCount => _results.where((r) => r.success).length;

  /// Number of failed exports from last run.
  int get failCount => _results.where((r) => !r.success).length;

  /// Total file size of all successful exports.
  int get totalFileSizeBytes => _results
      .where((r) => r.success)
      .fold(0, (sum, r) => sum + r.fileSizeBytes);

  /// Generate a batch export summary.
  Map<String, dynamic> summary() => {
    'totalTargets': _targets.length,
    'succeeded': successCount,
    'failed': failCount,
    'totalFileSizeBytes': totalFileSizeBytes,
    'results': _results.map((r) => r.toJson()).toList(),
  };
}
