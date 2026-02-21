/// 🗂️ FORMAT CONVERTER — Format-to-format conversion via IR.
///
/// Converts between file formats using the intermediate representation
/// (ParsedDocument) as the bridge. Supports quality, scale, and
/// color space options.
///
/// ```dart
/// final converter = FormatConverter();
/// final result = converter.convert(
///   inputDoc,
///   targetFormat: 'webp',
///   options: ConversionOptions(quality: 80, scale: 0.5),
/// );
/// ```
library;

import 'format_parser.dart';

// =============================================================================
// CONVERSION OPTIONS
// =============================================================================

/// Options for format conversion.
class ConversionOptions {
  /// Output quality (0–100, for lossy formats).
  final int quality;

  /// Scale multiplier.
  final double scale;

  /// Target color space (null = keep original).
  final String? targetColorSpace;

  /// Whether to flatten layers into a single layer.
  final bool flattenLayers;

  /// Whether to preserve metadata.
  final bool preserveMetadata;

  /// Whether to convert text to outlines.
  final bool textToOutlines;

  /// Target DPI (null = keep original).
  final double? targetDpi;

  const ConversionOptions({
    this.quality = 100,
    this.scale = 1.0,
    this.targetColorSpace,
    this.flattenLayers = false,
    this.preserveMetadata = true,
    this.textToOutlines = false,
    this.targetDpi,
  });

  Map<String, dynamic> toJson() => {
    'quality': quality,
    'scale': scale,
    if (targetColorSpace != null) 'targetColorSpace': targetColorSpace,
    'flattenLayers': flattenLayers,
    'preserveMetadata': preserveMetadata,
    'textToOutlines': textToOutlines,
    if (targetDpi != null) 'targetDpi': targetDpi,
  };
}

// =============================================================================
// CONVERSION STATUS
// =============================================================================

/// Status of a conversion operation.
enum ConversionStatus { success, partialSuccess, failed }

// =============================================================================
// CONVERSION RESULT
// =============================================================================

/// Result of a format conversion.
class ConversionResult {
  /// Converted document.
  final ParsedDocument? output;

  /// Conversion status.
  final ConversionStatus status;

  /// Original format.
  final String sourceFormat;

  /// Target format.
  final String targetFormat;

  /// Warnings generated during conversion.
  final List<String> warnings;

  /// Error message (null if succeeded).
  final String? error;

  /// Conversion duration in milliseconds.
  final int durationMs;

  const ConversionResult({
    this.output,
    required this.status,
    required this.sourceFormat,
    required this.targetFormat,
    this.warnings = const [],
    this.error,
    this.durationMs = 0,
  });

  bool get success =>
      status == ConversionStatus.success ||
      status == ConversionStatus.partialSuccess;

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'sourceFormat': sourceFormat,
    'targetFormat': targetFormat,
    if (warnings.isNotEmpty) 'warnings': warnings,
    if (error != null) 'error': error,
    'durationMs': durationMs,
  };

  @override
  String toString() =>
      'ConversionResult($sourceFormat → $targetFormat, ${status.name})';
}

// =============================================================================
// FORMAT CONVERTER
// =============================================================================

/// Converts between file formats using intermediate representation.
class FormatConverter {
  /// Known format conversion rules.
  final Map<String, Set<String>> _conversionPaths = {};

  FormatConverter();

  /// Create with default conversion paths.
  factory FormatConverter.withDefaults() {
    final converter = FormatConverter();
    // Raster → raster is always supported
    const rasterFormats = ['png', 'jpg', 'webp', 'avif', 'tiff'];
    for (final from in rasterFormats) {
      converter._conversionPaths[from] = {...rasterFormats};
    }
    // Design → raster
    for (final design in ['psd', 'figma', 'sketch']) {
      converter._conversionPaths[design] = {...rasterFormats, 'svg', 'pdf'};
    }
    // Vector conversions
    converter._conversionPaths['svg'] = {...rasterFormats, 'pdf'};
    converter._conversionPaths['pdf'] = {...rasterFormats, 'svg'};
    return converter;
  }

  /// Register a conversion path.
  void registerPath(String fromFormat, String toFormat) {
    _conversionPaths.putIfAbsent(fromFormat, () => {}).add(toFormat);
  }

  /// Check if a conversion is supported.
  bool canConvert(String fromFormat, String toFormat) {
    return _conversionPaths[fromFormat]?.contains(toFormat) ?? false;
  }

  /// Get all formats a source format can convert to.
  Set<String> targetFormatsFor(String sourceFormat) =>
      _conversionPaths[sourceFormat] ?? {};

  /// Convert a document to a target format.
  ///
  /// [transform] applies format-specific transformations. If null, basic
  /// metadata mapping is applied.
  ConversionResult convert(
    ParsedDocument input, {
    required String targetFormat,
    ConversionOptions options = const ConversionOptions(),
    ParsedDocument Function(ParsedDocument, ConversionOptions)? transform,
  }) {
    final sw = Stopwatch()..start();
    final warnings = <String>[];

    // Check conversion support
    if (!canConvert(input.sourceFormat, targetFormat)) {
      return ConversionResult(
        status: ConversionStatus.failed,
        sourceFormat: input.sourceFormat,
        targetFormat: targetFormat,
        error: 'No conversion path from ${input.sourceFormat} to $targetFormat',
      );
    }

    try {
      // Apply scaling
      var doc = input;
      if (options.scale != 1.0) {
        doc = ParsedDocument(
          name: doc.name,
          width: doc.width * options.scale,
          height: doc.height * options.scale,
          layers: doc.layers,
          metadata: options.preserveMetadata ? doc.metadata : {},
          sourceFormat: targetFormat,
          colorProfile: options.targetColorSpace ?? doc.colorProfile,
          dpi: options.targetDpi ?? doc.dpi,
        );
      } else {
        doc = ParsedDocument(
          name: doc.name,
          width: doc.width,
          height: doc.height,
          layers:
              options.flattenLayers
                  ? [
                    ParsedLayer(
                      id: 'flattened',
                      name: 'Flattened',
                      width: doc.width,
                      height: doc.height,
                    ),
                  ]
                  : doc.layers,
          metadata: options.preserveMetadata ? doc.metadata : {},
          sourceFormat: targetFormat,
          colorProfile: options.targetColorSpace ?? doc.colorProfile,
          dpi: options.targetDpi ?? doc.dpi,
        );
      }

      // Apply custom transform
      if (transform != null) {
        doc = transform(doc, options);
      }

      // Check for potential quality loss
      if (options.flattenLayers && input.layers.length > 1) {
        warnings.add('Layer data discarded during flatten');
      }

      sw.stop();
      return ConversionResult(
        output: doc,
        status:
            warnings.isEmpty
                ? ConversionStatus.success
                : ConversionStatus.partialSuccess,
        sourceFormat: input.sourceFormat,
        targetFormat: targetFormat,
        warnings: warnings,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return ConversionResult(
        status: ConversionStatus.failed,
        sourceFormat: input.sourceFormat,
        targetFormat: targetFormat,
        error: e.toString(),
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Get all supported conversion paths.
  Map<String, Set<String>> get allPaths => Map.unmodifiable(_conversionPaths);
}
