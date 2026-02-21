import 'dart:async';

import 'asset_metadata.dart';

// =============================================================================
// ASSET HANDLE — Content-addressable identifier for managed assets.
// =============================================================================

/// Type of managed asset.
enum AssetType {
  /// Raster image (PNG, JPEG, WebP).
  image,

  /// Font file (TTF, OTF).
  font,

  /// Fragment shader program (GLSL/SPIR-V).
  shader,

  /// Vector graphic (SVG).
  svg,
}

/// Current lifecycle state of an asset in the pipeline.
enum AssetState {
  /// Registered but not yet loaded.
  pending,

  /// Actively being loaded/decoded.
  loading,

  /// Successfully loaded and ready to use.
  loaded,

  /// Load failed — see [AssetEntry.error].
  error,

  /// Evicted from memory (can be reloaded).
  evicted,

  /// Permanently disposed — cannot be reloaded.
  disposed,
}

/// Unique, content-addressable identifier for a managed asset.
///
/// Two assets with identical content produce the same [id] (SHA-256),
/// enabling automatic deduplication.
class AssetHandle {
  /// Content-addressed identifier (SHA-256 hex or legacy path hash).
  final String id;

  /// Asset type for dispatch to the correct loader.
  final AssetType type;

  /// Original source path on disk.
  final String sourcePath;

  const AssetHandle({
    required this.id,
    required this.type,
    required this.sourcePath,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetHandle && id == other.id && type == other.type;

  @override
  int get hashCode => Object.hash(id, type);

  @override
  String toString() => 'AssetHandle($id, ${type.name})';
}

/// Metadata and runtime state for a single managed asset.
class AssetEntry {
  /// The asset's unique handle.
  final AssetHandle handle;

  /// Current lifecycle state.
  AssetState state;

  /// Number of active consumers holding this asset.
  int refCount;

  /// Estimated memory footprint in bytes (0 if not loaded).
  int memoryBytes;

  /// The loaded data (e.g. `ui.Image`, `ByteData`). Null if not loaded.
  Object? data;

  /// Error from the last load attempt. Null if no error.
  Object? error;

  /// Stack trace from the last load error.
  StackTrace? errorStack;

  /// Last access timestamp (microseconds since epoch).
  int lastAccessedUs;

  /// Rich metadata (tags, license, dimensions, etc.).
  AssetMetadata? metadata;

  /// Version history for this asset (newest first).
  final List<AssetVersion> versions;

  /// State change broadcast controller (lazy).
  StreamController<AssetState>? _stateController;

  AssetEntry({
    required this.handle,
    this.state = AssetState.pending,
    this.refCount = 0,
    this.memoryBytes = 0,
    this.data,
    this.error,
    this.errorStack,
    this.metadata,
    List<AssetVersion>? versions,
    int? lastAccessedUs,
  }) : versions = versions ?? [],
       lastAccessedUs = lastAccessedUs ?? DateTime.now().microsecondsSinceEpoch;

  /// Stream of state changes for this asset.
  Stream<AssetState> get stateChanges {
    _stateController ??= StreamController<AssetState>.broadcast();
    return _stateController!.stream;
  }

  /// Update state and notify listeners.
  void transition(AssetState newState) {
    if (state == newState) return;
    state = newState;
    _stateController?.add(newState);
  }

  /// Whether this asset can be safely evicted (zero refs).
  bool get isEvictable => refCount <= 0 && state == AssetState.loaded;

  /// Touch access timestamp.
  void touch() {
    lastAccessedUs = DateTime.now().microsecondsSinceEpoch;
  }

  /// Close the state stream.
  void dispose() {
    _stateController?.close();
    _stateController = null;
  }

  Map<String, dynamic> toJson() => {
    'id': handle.id,
    'type': handle.type.name,
    'state': state.name,
    'refCount': refCount,
    'memoryBytes': memoryBytes,
    'sourcePath': handle.sourcePath,
    if (error != null) 'error': error.toString(),
    if (metadata != null) 'metadata': metadata!.toJson(),
    if (versions.isNotEmpty)
      'versions': versions.map((v) => v.toJson()).toList(),
  };
}
