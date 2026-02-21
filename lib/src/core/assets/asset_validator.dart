/// 📦 ASSET VALIDATOR — Pre-import validation for managed assets.
///
/// Validates assets against configurable rules before they enter
/// the [AssetRegistry]. Catches oversized files, unsupported formats,
/// and policy violations early — before wasting bandwidth or storage.
///
/// ```dart
/// final validator = AssetValidator();
/// final result = validator.validate('/path/to/image.png', AssetType.image);
/// if (!result.isValid) {
///   for (final issue in result.issues) {
///     print('⚠️ ${issue.message}');
///   }
/// }
/// ```
library;

import 'dart:io';

import 'asset_handle.dart';

// =============================================================================
// VALIDATION CONFIG
// =============================================================================

/// Configuration for asset validation rules.
class AssetValidationConfig {
  /// Maximum allowed file size in bytes (default: 50 MB).
  final int maxFileSizeBytes;

  /// Allowed MIME types per asset type. Empty set = allow all.
  final Map<AssetType, Set<String>> allowedMimeTypes;

  /// Maximum image dimension (width or height) in pixels.
  /// Null = no limit.
  final int? maxImageDimension;

  /// Whether to require license metadata on import.
  final bool requireLicenseTag;

  /// Whether to validate that the file actually exists.
  final bool validateFileExists;

  const AssetValidationConfig({
    this.maxFileSizeBytes = 50 * 1024 * 1024, // 50 MB
    this.allowedMimeTypes = const {
      AssetType.image: {'image/png', 'image/jpeg', 'image/webp', 'image/gif'},
      AssetType.font: {'font/ttf', 'font/otf', 'font/woff', 'font/woff2'},
      AssetType.svg: {'image/svg+xml'},
    },
    this.maxImageDimension,
    this.requireLicenseTag = false,
    this.validateFileExists = true,
  });

  /// Permissive config — accepts everything, only checks file existence.
  static const permissive = AssetValidationConfig(
    maxFileSizeBytes: 500 * 1024 * 1024,
    allowedMimeTypes: {},
    requireLicenseTag: false,
  );

  /// Strict config — small files, explicit formats, requires license.
  static const strict = AssetValidationConfig(
    maxFileSizeBytes: 10 * 1024 * 1024,
    requireLicenseTag: true,
    maxImageDimension: 4096,
  );
}

// =============================================================================
// VALIDATION ISSUE
// =============================================================================

/// Severity of a validation issue.
enum ValidationSeverity { error, warning, info }

/// A single validation finding.
class AssetValidationIssue {
  /// Severity level.
  final ValidationSeverity severity;

  /// Machine-readable issue code (e.g. `'file_too_large'`).
  final String code;

  /// Human-readable description.
  final String message;

  const AssetValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
  });

  @override
  String toString() => '${severity.name.toUpperCase()}: $message ($code)';
}

// =============================================================================
// VALIDATION RESULT
// =============================================================================

/// Result of validating an asset before import.
class AssetValidationResult {
  /// Whether all checks passed (no errors).
  final bool isValid;

  /// All issues found during validation.
  final List<AssetValidationIssue> issues;

  /// File size in bytes (if available).
  final int? fileSizeBytes;

  /// Detected MIME type (if available).
  final String? detectedMimeType;

  const AssetValidationResult({
    required this.isValid,
    this.issues = const [],
    this.fileSizeBytes,
    this.detectedMimeType,
  });

  /// Filter issues by severity.
  List<AssetValidationIssue> byLevel(ValidationSeverity severity) =>
      issues.where((i) => i.severity == severity).toList();

  /// True if there are any errors (not just warnings).
  bool get hasErrors =>
      issues.any((i) => i.severity == ValidationSeverity.error);

  @override
  String toString() =>
      'AssetValidationResult(valid=$isValid, '
      'issues=${issues.length})';
}

// =============================================================================
// ASSET VALIDATOR
// =============================================================================

/// Validates assets against configurable rules before import.
///
/// Checks file existence, size limits, format whitelist, and
/// policy requirements. Returns a detailed [AssetValidationResult].
class AssetValidator {
  /// Validation configuration.
  final AssetValidationConfig config;

  const AssetValidator({this.config = const AssetValidationConfig()});

  /// Validate an asset file against all configured rules.
  ///
  /// Returns a [AssetValidationResult] with all discovered issues.
  /// An asset is valid only if there are zero error-severity issues.
  AssetValidationResult validate(String sourcePath, AssetType type) {
    final issues = <AssetValidationIssue>[];
    int? fileSize;
    String? mime;

    // 1. File existence
    if (config.validateFileExists) {
      final file = File(sourcePath);
      if (!file.existsSync()) {
        issues.add(
          const AssetValidationIssue(
            severity: ValidationSeverity.error,
            code: 'file_not_found',
            message: 'Asset file does not exist',
          ),
        );
        return AssetValidationResult(isValid: false, issues: issues);
      }

      // 2. File size
      fileSize = file.lengthSync();
      if (fileSize > config.maxFileSizeBytes) {
        final maxMB = config.maxFileSizeBytes / (1024 * 1024);
        final actualMB = (fileSize / (1024 * 1024)).toStringAsFixed(1);
        issues.add(
          AssetValidationIssue(
            severity: ValidationSeverity.error,
            code: 'file_too_large',
            message:
                'File size ${actualMB}MB exceeds limit of ${maxMB.toStringAsFixed(0)}MB',
          ),
        );
      }
    }

    // 3. MIME type / format detection (from extension)
    mime = _detectMimeType(sourcePath, type);
    final allowedSet = config.allowedMimeTypes[type];
    if (allowedSet != null && allowedSet.isNotEmpty && mime != null) {
      if (!allowedSet.contains(mime)) {
        issues.add(
          AssetValidationIssue(
            severity: ValidationSeverity.error,
            code: 'unsupported_format',
            message:
                'MIME type "$mime" is not allowed for ${type.name} assets. '
                'Allowed: ${allowedSet.join(", ")}',
          ),
        );
      }
    }

    // 4. Extension sanity check
    if (mime == null) {
      issues.add(
        const AssetValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'unknown_format',
          message: 'Could not determine file format from extension',
        ),
      );
    }

    // 5. License requirement
    if (config.requireLicenseTag) {
      issues.add(
        const AssetValidationIssue(
          severity: ValidationSeverity.info,
          code: 'license_required',
          message: 'License metadata must be set after import',
        ),
      );
    }

    final hasErrors = issues.any((i) => i.severity == ValidationSeverity.error);

    return AssetValidationResult(
      isValid: !hasErrors,
      issues: issues,
      fileSizeBytes: fileSize,
      detectedMimeType: mime,
    );
  }

  /// Validate multiple files and return results keyed by path.
  Map<String, AssetValidationResult> validateBatch(
    Map<String, AssetType> assets,
  ) {
    return {
      for (final entry in assets.entries)
        entry.key: validate(entry.key, entry.value),
    };
  }

  /// Detect MIME type from file extension.
  static String? _detectMimeType(String path, AssetType type) {
    final ext = path.split('.').last.toLowerCase();
    return _mimeByExtension[ext];
  }

  static const _mimeByExtension = <String, String>{
    // Images
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'bmp': 'image/bmp',
    'tiff': 'image/tiff',
    'tif': 'image/tiff',
    'avif': 'image/avif',
    // SVG
    'svg': 'image/svg+xml',
    // Fonts
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    // Shaders
    'frag': 'application/x-glsl',
    'vert': 'application/x-glsl',
    'glsl': 'application/x-glsl',
    'spv': 'application/x-spirv',
  };
}
