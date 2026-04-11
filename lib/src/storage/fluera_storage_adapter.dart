// ============================================================================
// 💾 FLUERA STORAGE ADAPTER — Abstract persistence interface
//
// Defines the contract for canvas persistence. The SDK ships a default
// SqliteStorageAdapter, but apps can provide their own implementation
// (Firebase, Supabase, REST API, etc.) by implementing this interface.
// ============================================================================

import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/painting.dart';

import '../core/models/canvas_layer.dart';
import 'canvas_creation_options.dart';
import 'section_summary.dart';

/// Metadata for a stored canvas (used for listing / browsing).
class CanvasMetadata {
  /// Unique canvas identifier.
  final String canvasId;

  /// Human-readable title (may be null for untitled canvases).
  final String? title;

  /// Last modification timestamp.
  final DateTime updatedAt;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Paper type (e.g. 'blank', 'lined', 'grid').
  final String paperType;

  /// Background color (ARGB int). Defaults to white.
  final int backgroundColorValue;

  /// Background color as a [Color] object.
  Color get backgroundColor => Color(backgroundColorValue);

  /// Parent folder ID (null = root level).
  final String? parentFolderId;

  /// Number of layers in the canvas.
  final int layerCount;

  /// Total number of strokes across all layers.
  final int strokeCount;

  /// Sections in this canvas (extracted from scene graph on save).
  final List<SectionSummary> sections;

  /// Total content bounding box in canvas world space.
  /// Null if the canvas has no content yet.
  final Rect? contentBounds;

  /// Last viewport state (camera position + zoom) when the user left.
  /// Used for "continue where you left off" with exact camera position.
  final ({double dx, double dy, double scale})? lastViewport;

  const CanvasMetadata({
    required this.canvasId,
    this.title,
    required this.updatedAt,
    required this.createdAt,
    required this.paperType,
    this.backgroundColorValue = 0xFFFFFFFF,
    this.parentFolderId,
    this.layerCount = 0,
    this.strokeCount = 0,
    this.sections = const [],
    this.contentBounds,
    this.lastViewport,
  });

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'canvasId': canvasId,
    if (title != null) 'title': title,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'paperType': paperType,
    'backgroundColorValue': backgroundColorValue,
    if (parentFolderId != null) 'parentFolderId': parentFolderId,
    'layerCount': layerCount,
    'strokeCount': strokeCount,
    if (sections.isNotEmpty)
      'sections': sections.map((s) => s.toJson()).toList(),
    if (contentBounds != null)
      'contentBounds': {
        'left': contentBounds!.left,
        'top': contentBounds!.top,
        'right': contentBounds!.right,
        'bottom': contentBounds!.bottom,
      },
    if (lastViewport != null)
      'lastViewport': {
        'dx': lastViewport!.dx,
        'dy': lastViewport!.dy,
        'scale': lastViewport!.scale,
      },
  };

  /// Deserialize from JSON.
  factory CanvasMetadata.fromJson(Map<String, dynamic> json) {
    // Parse sections
    final sectionsJson = json['sections'] as List<dynamic>?;
    final sections = sectionsJson
        ?.map((s) => SectionSummary.fromJson(s as Map<String, dynamic>))
        .toList() ?? const [];

    // Parse content bounds
    final boundsJson = json['contentBounds'] as Map<String, dynamic>?;
    final contentBounds = boundsJson != null
        ? Rect.fromLTRB(
            (boundsJson['left'] as num).toDouble(),
            (boundsJson['top'] as num).toDouble(),
            (boundsJson['right'] as num).toDouble(),
            (boundsJson['bottom'] as num).toDouble(),
          )
        : null;

    // Parse last viewport
    final vpJson = json['lastViewport'] as Map<String, dynamic>?;
    final lastViewport = vpJson != null
        ? (
            dx: (vpJson['dx'] as num).toDouble(),
            dy: (vpJson['dy'] as num).toDouble(),
            scale: (vpJson['scale'] as num).toDouble(),
          )
        : null;

    return CanvasMetadata(
      canvasId: json['canvasId'] as String,
      title: json['title'] as String?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      paperType: json['paperType'] as String? ?? 'blank',
      backgroundColorValue: json['backgroundColorValue'] as int? ?? 0xFFFFFFFF,
      parentFolderId: json['parentFolderId'] as String?,
      layerCount: json['layerCount'] as int? ?? 0,
      strokeCount: json['strokeCount'] as int? ?? 0,
      sections: sections,
      contentBounds: contentBounds,
      lastViewport: lastViewport,
    );
  }

  @override
  String toString() =>
      'CanvasMetadata(id: $canvasId, title: $title, folder: $parentFolderId)';
}

/// Metadata for a folder (used for listing / browsing).
class FolderMetadata {
  /// Unique folder identifier.
  final String folderId;

  /// Display name.
  final String name;

  /// Parent folder ID (null = root level).
  final String? parentFolderId;

  /// Accent color (ARGB int). Defaults to blue.
  final int colorValue;

  /// Accent color as a [Color] object.
  Color get color => Color(colorValue);

  /// Creation timestamp.
  final DateTime createdAt;

  /// Last modification timestamp.
  final DateTime updatedAt;

  /// Number of canvases directly in this folder.
  final int canvasCount;

  /// Number of subfolders directly in this folder.
  final int subfolderCount;

  const FolderMetadata({
    required this.folderId,
    required this.name,
    this.parentFolderId,
    this.colorValue = 0xFF6750A4,
    required this.createdAt,
    required this.updatedAt,
    this.canvasCount = 0,
    this.subfolderCount = 0,
  });
}

/// 💾 Abstract storage adapter for canvas persistence.
///
/// DESIGN PRINCIPLES:
/// - Zero-dependency: implementations decide the backend (SQLite, Firebase, etc.)
/// - Async-first: all operations return Futures for non-blocking I/O
/// - Canvas-centric: one canvas = one save/load unit
/// - Metadata support: enables canvas listing/browsing without loading full data
///
/// USAGE (app-side):
/// ```dart
/// // Option 1: Use built-in SQLite (zero config)
/// final storage = SqliteStorageAdapter();
/// await storage.initialize();
///
/// // Option 2: Custom implementation
/// class MyFirebaseStorage implements FlueraStorageAdapter { ... }
///
/// // Pass to config
/// FlueraCanvasScreen(
///   config: FlueraCanvasConfig(
///     storageAdapter: storage,
///     ...
///   ),
/// )
/// ```
abstract class FlueraStorageAdapter {
  /// 🔐 Current user ID for data isolation.
  ///
  /// When set, storage operations are scoped to this user.
  /// When null, all data is visible (legacy / offline mode).
  String? get currentUserId => null;
  set currentUserId(String? userId) {}

  /// Initialize the storage backend (create DB, run migrations, etc.).
  ///
  /// Must be called before any other method. Safe to call multiple times.
  Future<void> initialize();

  /// Save a canvas snapshot.
  ///
  /// If a canvas with the same ID already exists, it is overwritten (upsert).
  /// The implementation should store all layers, strokes, shapes, text, and
  /// image references atomically (transaction).
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data);

  /// Load a canvas by its ID.
  ///
  /// Returns the full canvas data as a JSON map (same format as [saveCanvas]),
  /// or `null` if no canvas with that ID exists.
  Future<Map<String, dynamic>?> loadCanvas(String canvasId);

  /// Delete a canvas and all its associated data.
  ///
  /// No-op if the canvas does not exist.
  Future<void> deleteCanvas(String canvasId);

  /// List all stored canvases with metadata.
  ///
  /// Returns metadata only (no full layer data) for efficient browsing.
  /// If [folderId] is provided, only canvases in that folder are returned.
  /// Pass `null` to list root-level canvases only, or omit for all canvases.
  Future<List<CanvasMetadata>> listCanvases({String? folderId});

  /// Check if a canvas exists without loading it.
  Future<bool> canvasExists(String canvasId);

  /// Release resources (close DB connections, flush buffers, etc.).
  Future<void> close();

  // ─────────────────────── FOLDER OPERATIONS ───────────────────────────────

  /// Create a new folder.
  ///
  /// Returns the folder ID.
  /// ```dart
  /// final folderId = await storage.createFolder('Math Notes');
  /// ```
  Future<String> createFolder(
    String name, {
    String? parentFolderId,
    Color color = const Color(0xFF6750A4),
  });

  /// Rename a folder.
  Future<void> renameFolder(String folderId, String name);

  /// Delete a folder.
  ///
  /// All canvases and subfolders inside are moved to the parent folder.
  Future<void> deleteFolder(String folderId);

  /// List folders.
  ///
  /// If [parentFolderId] is provided, only subfolders of that folder.
  /// Pass `null` for root-level folders.
  Future<List<FolderMetadata>> listFolders({String? parentFolderId});

  /// Move a canvas to a folder (or to root if [folderId] is null).
  Future<void> moveCanvasToFolder(String canvasId, String? folderId);

  /// Move a folder inside another folder (or to root if [parentFolderId] is null).
  Future<void> moveFolderToFolder(String folderId, String? parentFolderId);

  /// Create a new canvas with the given options.
  ///
  /// Returns the canvas ID (auto-generated if not specified in options).
  /// The default implementation creates metadata and saves an empty canvas.
  ///
  /// ```dart
  /// final id = await storage.createCanvas(CanvasCreationOptions(
  ///   title: 'Math Notes',
  ///   paperType: CanvasPaperType.grid5mm,
  ///   backgroundColor: Color(0xFFFFFBF0),
  /// ));
  /// ```
  Future<String> createCanvas(CanvasCreationOptions options) async {
    final id = options.resolveCanvasId();
    final now = DateTime.now();
    final data = <String, dynamic>{
      'canvasId': id,
      'title': options.title,
      'paperType': options.paperType.storageKey,
      'backgroundColorValue': options.backgroundColor.toARGB32(),
      'createdAt': now.millisecondsSinceEpoch,
      'updatedAt': now.millisecondsSinceEpoch,
      'layers': <Map<String, dynamic>>[],
    };
    await saveCanvas(id, data);
    return id;
  }

  /// Save a canvas viewport snapshot (PNG bytes) for splash screen preview.
  ///
  /// Called after each auto-save. The snapshot is a low-resolution PNG
  /// (~480px long side, ~50-100KB) that is displayed during the next
  /// loading screen to give the user immediate visual context.
  ///
  /// Default: no-op (splash screen falls back to logo animation).
  Future<void> saveSnapshot(String canvasId, Uint8List png) async {}

  /// Load the splash screen snapshot for a canvas.
  ///
  /// Returns the PNG bytes saved by [saveSnapshot], or `null` if no
  /// snapshot exists. This is loaded during the splash screen pipeline
  /// and should be fast (sub-millisecond for SQLite BLOB reads).
  Future<Uint8List?> loadSnapshot(String canvasId) async => null;

  // ─────────────────────── SECTION METADATA ─────────────────────────────────

  /// Save pre-computed section summaries for a canvas.
  ///
  /// Called during auto-save to persist lightweight section metadata
  /// that the gallery can query without loading the full canvas JSON.
  /// Also persists content bounds and last viewport state.
  ///
  /// Default: no-op (gallery falls back to metadata without sections).
  Future<void> saveSectionSummaries(
    String canvasId, {
    required List<SectionSummary> sections,
    Rect? contentBounds,
    ({double dx, double dy, double scale})? lastViewport,
  }) async {}

  /// Load the last saved viewport state for a canvas.
  ///
  /// Returns the camera position + zoom when the user last left the canvas,
  /// enabling self-contained "continue where you left off" without relying
  /// on the host app to pass in initialViewport.
  ///
  /// Default: returns null (no stored viewport).
  Future<({double dx, double dy, double scale})?> loadLastViewport(
    String canvasId,
  ) async => null;
}
