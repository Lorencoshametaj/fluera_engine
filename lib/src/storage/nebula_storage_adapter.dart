// ============================================================================
// 💾 NEBULA STORAGE ADAPTER — Abstract persistence interface
//
// Defines the contract for canvas persistence. The SDK ships a default
// SqliteStorageAdapter, but apps can provide their own implementation
// (Firebase, Supabase, REST API, etc.) by implementing this interface.
// ============================================================================

import '../core/models/canvas_layer.dart';

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

  /// Number of layers in the canvas.
  final int layerCount;

  /// Total number of strokes across all layers.
  final int strokeCount;

  const CanvasMetadata({
    required this.canvasId,
    this.title,
    required this.updatedAt,
    required this.createdAt,
    required this.paperType,
    this.layerCount = 0,
    this.strokeCount = 0,
  });

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'canvasId': canvasId,
    if (title != null) 'title': title,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'paperType': paperType,
    'layerCount': layerCount,
    'strokeCount': strokeCount,
  };

  /// Deserialize from JSON.
  factory CanvasMetadata.fromJson(Map<String, dynamic> json) {
    return CanvasMetadata(
      canvasId: json['canvasId'] as String,
      title: json['title'] as String?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      paperType: json['paperType'] as String? ?? 'blank',
      layerCount: json['layerCount'] as int? ?? 0,
      strokeCount: json['strokeCount'] as int? ?? 0,
    );
  }

  @override
  String toString() =>
      'CanvasMetadata(id: $canvasId, title: $title, layers: $layerCount, strokes: $strokeCount)';
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
/// class MyFirebaseStorage implements NebulaStorageAdapter { ... }
///
/// // Pass to config
/// NebulaCanvasScreen(
///   config: NebulaCanvasConfig(
///     storageAdapter: storage,
///     ...
///   ),
/// )
/// ```
abstract class NebulaStorageAdapter {
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
  /// Ordered by [CanvasMetadata.updatedAt] descending (most recent first).
  Future<List<CanvasMetadata>> listCanvases();

  /// Check if a canvas exists without loading it.
  Future<bool> canvasExists(String canvasId);

  /// Release resources (close DB connections, flush buffers, etc.).
  ///
  /// The adapter should not be used after calling this method.
  Future<void> close();
}
