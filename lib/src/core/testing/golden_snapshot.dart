/// 🧪 GOLDEN SNAPSHOT — Golden image model and store for visual regression testing.
///
/// Captures rendered output as PNG bytes with metadata for comparison.
/// [GoldenStore] provides in-memory CRUD with export/import for CI pipelines.
///
/// ```dart
/// final store = GoldenStore();
/// store.save(GoldenSnapshot(
///   id: 'button_default',
///   imageBytes: pngBytes,
///   width: 200,
///   height: 48,
///   label: 'Default button state',
/// ));
///
/// final golden = store.load('button_default');
/// ```
library;

import 'dart:convert';
import 'dart:typed_data';

// =============================================================================
// GOLDEN SNAPSHOT
// =============================================================================

/// Captured golden image with metadata for visual regression comparison.
class GoldenSnapshot {
  /// Unique test identifier (e.g. `'button_primary_default'`).
  final String id;

  /// PNG-encoded image bytes.
  final Uint8List imageBytes;

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// When this golden was captured.
  final DateTime capturedAt;

  /// Human-readable label.
  final String? label;

  /// Environment metadata (OS, device pixel ratio, Flutter version, etc.).
  final Map<String, dynamic>? metadata;

  GoldenSnapshot({
    required this.id,
    required this.imageBytes,
    required this.width,
    required this.height,
    DateTime? capturedAt,
    this.label,
    this.metadata,
  }) : capturedAt = capturedAt ?? DateTime.now().toUtc();

  /// File size of the image in bytes.
  int get fileSizeBytes => imageBytes.length;

  /// Serialize to JSON (image bytes as base64).
  Map<String, dynamic> toJson() => {
    'id': id,
    'imageBytes': base64Encode(imageBytes),
    'width': width,
    'height': height,
    'capturedAt': capturedAt.toIso8601String(),
    if (label != null) 'label': label,
    if (metadata != null) 'metadata': metadata,
  };

  /// Deserialize from JSON.
  factory GoldenSnapshot.fromJson(Map<String, dynamic> json) => GoldenSnapshot(
    id: json['id'] as String,
    imageBytes: base64Decode(json['imageBytes'] as String),
    width: json['width'] as int,
    height: json['height'] as int,
    capturedAt: DateTime.parse(json['capturedAt'] as String),
    label: json['label'] as String?,
    metadata: json['metadata'] as Map<String, dynamic>?,
  );

  @override
  String toString() =>
      'GoldenSnapshot($id, ${width}x$height, '
      '${(fileSizeBytes / 1024).toStringAsFixed(1)}KB)';
}

// =============================================================================
// GOLDEN STORE
// =============================================================================

/// In-memory store for golden snapshots.
///
/// Provides CRUD operations and bulk export/import for CI artifact storage.
class GoldenStore {
  final Map<String, GoldenSnapshot> _snapshots = {};

  /// Save or update a golden snapshot.
  void save(GoldenSnapshot snapshot) {
    _snapshots[snapshot.id] = snapshot;
  }

  /// Load a golden by ID, or `null` if not found.
  GoldenSnapshot? load(String id) => _snapshots[id];

  /// Delete a golden by ID. Returns `true` if it existed.
  bool delete(String id) => _snapshots.remove(id) != null;

  /// All stored snapshot IDs.
  List<String> get allIds => _snapshots.keys.toList();

  /// Number of stored snapshots.
  int get count => _snapshots.length;

  /// Whether a golden exists for the given ID.
  bool contains(String id) => _snapshots.containsKey(id);

  /// Clear all stored snapshots.
  void clear() => _snapshots.clear();

  /// Export all snapshots as a single JSON-serializable map.
  Map<String, dynamic> exportAll() => {
    'version': 1,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'count': _snapshots.length,
    'snapshots': {
      for (final entry in _snapshots.entries) entry.key: entry.value.toJson(),
    },
  };

  /// Import snapshots from a previously exported map.
  ///
  /// If [overwrite] is true, existing goldens with the same ID are replaced.
  void importAll(Map<String, dynamic> data, {bool overwrite = false}) {
    final snapshots = data['snapshots'] as Map<String, dynamic>?;
    if (snapshots == null) return;

    for (final entry in snapshots.entries) {
      if (!overwrite && _snapshots.containsKey(entry.key)) continue;
      _snapshots[entry.key] = GoldenSnapshot.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
  }

  @override
  String toString() => 'GoldenStore(count=$count)';
}
