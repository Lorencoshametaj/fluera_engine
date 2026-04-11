// ============================================================================
// 📦 USER DATA EXPORT SERVICE — Data portability (Art. 20)
//
// Specifica: A16-11 → A16-15
//
// GDPR Art. 20 requires the ability to export ALL personal data in a
// "structured, commonly used, machine-readable format".
//
// EXPORT FORMAT:
//   fluera_export_<date>.zip
//   ├── manifest.json          — export metadata + schema version
//   ├── canvases/
//   │   ├── canvas_<id>.json   — canvas metadata, zone structure
//   │   └── canvas_<id>/
//   │       ├── strokes.json   — all ink strokes (control points)
//   │       ├── ocr_text.json  — recognized text per cluster
//   │       ├── srs_data.json  — SRS card data per concept
//   │       └── images/        — embedded images
//   ├── ai_history/
//   │   ├── socratic_sessions.json
//   │   └── chat_sessions.json
//   ├── audio/
//   │   └── recording_<id>.m4a
//   ├── preferences.json       — user settings
//   └── consents.json          — consent history
//
// RULES:
//   - Format: ZIP file, JSON content
//   - Must include ALL user data (not a subset)
//   - Machine-readable (Art. 20(1))
//   - Must complete within 30 days (Art. 12(3))
//   - Schema versioned for forward compatibility
//
// ARCHITECTURE:
//   Pure model defining the export schema.
//   The host app implements the actual ZIP creation.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'package:flutter/foundation.dart';

/// 📦 Export schema version.
const String kExportSchemaVersion = '1.0.0';

/// 📦 Export status.
enum ExportStatus {
  /// Not started.
  idle,

  /// Gathering data.
  gathering,

  /// Building ZIP.
  packaging,

  /// Complete.
  completed,

  /// Failed.
  failed,
}

/// 📦 A section of the export (one per data type).
class ExportSection {
  /// Section name (e.g., 'canvases', 'ai_history').
  final String name;

  /// Number of items in this section.
  final int itemCount;

  /// Size in bytes (estimated).
  final int sizeBytes;

  /// Whether this section was successfully exported.
  final bool success;

  /// Error if failed.
  final String? error;

  const ExportSection({
    required this.name,
    required this.itemCount,
    this.sizeBytes = 0,
    this.success = true,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'itemCount': itemCount,
        'sizeBytes': sizeBytes,
        'success': success,
        if (error != null) 'error': error,
      };
}

/// 📦 Export manifest (included in the ZIP).
class ExportManifest {
  /// Schema version.
  final String schemaVersion;

  /// When the export was created.
  final DateTime exportedAt;

  /// App version that created the export.
  final String appVersion;

  /// Platform (ios/android).
  final String platform;

  /// Locale.
  final String locale;

  /// Sections included.
  final List<ExportSection> sections;

  /// Total size in bytes.
  int get totalSizeBytes => sections.fold(0, (s, sec) => s + sec.sizeBytes);

  /// Total item count.
  int get totalItemCount => sections.fold(0, (s, sec) => s + sec.itemCount);

  ExportManifest({
    this.schemaVersion = kExportSchemaVersion,
    DateTime? exportedAt,
    this.appVersion = '1.0.0',
    this.platform = 'unknown',
    this.locale = 'it',
    this.sections = const [],
  }) : exportedAt = exportedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'exportedAt': exportedAt.toIso8601String(),
        'appVersion': appVersion,
        'platform': platform,
        'locale': locale,
        'totalSizeBytes': totalSizeBytes,
        'totalItemCount': totalItemCount,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  factory ExportManifest.fromJson(Map<String, dynamic> json) {
    return ExportManifest(
      schemaVersion: json['schemaVersion'] as String? ?? '1.0.0',
      exportedAt: DateTime.tryParse(json['exportedAt'] as String? ?? ''),
      appVersion: json['appVersion'] as String? ?? '1.0.0',
      platform: json['platform'] as String? ?? 'unknown',
      locale: json['locale'] as String? ?? 'it',
      sections: (json['sections'] as List<dynamic>?)
              ?.map((s) => ExportSection(
                    name: s['name'] as String? ?? '',
                    itemCount: (s['itemCount'] as num?)?.toInt() ?? 0,
                    sizeBytes: (s['sizeBytes'] as num?)?.toInt() ?? 0,
                    success: s['success'] as bool? ?? true,
                    error: s['error'] as String?,
                  ))
              .toList() ??
          [],
    );
  }
}

/// 📦 User Data Export Service (A16, Art. 20).
///
/// Orchestrates the complete data export pipeline.
/// The host app registers data gatherers for each section.
///
/// Usage:
/// ```dart
/// final service = UserDataExportService();
///
/// // Register data gatherers
/// service.registerGatherer('canvases', (progress) async {
///   final data = await db.getAllCanvases();
///   return ExportSection(name: 'canvases', itemCount: data.length);
/// });
///
/// // Execute export
/// final manifest = await service.exportAll();
/// ```
class UserDataExportService extends ChangeNotifier {
  /// Registered data gatherers.
  final Map<String, Future<ExportSection> Function(void Function(double))>
      _gatherers = {};

  /// Current export status.
  ExportStatus _status = ExportStatus.idle;
  ExportStatus get status => _status;

  /// Current progress (0.0–1.0).
  double _progress = 0.0;
  double get progress => _progress;

  /// Most recent export manifest.
  ExportManifest? _lastManifest;
  ExportManifest? get lastManifest => _lastManifest;

  /// Whether an export is in progress.
  bool get isExporting =>
      _status == ExportStatus.gathering || _status == ExportStatus.packaging;

  /// Register a data gatherer for a section.
  void registerGatherer(
    String sectionName,
    Future<ExportSection> Function(void Function(double) onProgress) gatherer,
  ) {
    _gatherers[sectionName] = gatherer;
  }

  /// Export all registered sections.
  ///
  /// Returns the [ExportManifest] describing what was exported.
  Future<ExportManifest> exportAll({
    String appVersion = '1.0.0',
    String platform = 'unknown',
    String locale = 'it',
  }) async {
    if (isExporting) throw StateError('Export already in progress');

    _status = ExportStatus.gathering;
    _progress = 0.0;
    notifyListeners();

    final sections = <ExportSection>[];
    final total = _gatherers.length;
    int completed = 0;

    try {
      for (final entry in _gatherers.entries) {
        try {
          final section = await entry.value((p) {
            _progress = (completed + p) / total;
            notifyListeners();
          });
          sections.add(section);
        } catch (e) {
          sections.add(ExportSection(
            name: entry.key,
            itemCount: 0,
            success: false,
            error: e.toString(),
          ));
        }
        completed++;
        _progress = completed / total;
        notifyListeners();
      }

      _status = ExportStatus.packaging;
      notifyListeners();

      final manifest = ExportManifest(
        appVersion: appVersion,
        platform: platform,
        locale: locale,
        sections: sections,
      );

      _lastManifest = manifest;
      _status = ExportStatus.completed;
      _progress = 1.0;
      notifyListeners();

      return manifest;
    } catch (e) {
      _status = ExportStatus.failed;
      notifyListeners();
      rethrow;
    }
  }

  /// Reset export state.
  void reset() {
    _status = ExportStatus.idle;
    _progress = 0.0;
    notifyListeners();
  }

  /// Registered section names.
  List<String> get registeredSections => _gatherers.keys.toList();
}
