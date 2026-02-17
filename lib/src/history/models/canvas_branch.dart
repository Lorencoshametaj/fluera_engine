/// 🌿 Canvas Branch — represents a creative fork from the main canvas timeline
///
/// Like a Git branch, a [CanvasBranch] inherits all events from its parent
/// up to [forkPointEventIndex], then stores its own independent edits in
/// a separate session directory.
///
/// **Storage**: `{canvasDir}/time_travel/branches/{id}/`
/// **Cloud sync**: Metadata → Firestore, snapshots + TT → Cloud Storage
/// **No data duplication**: The branch references parent events by index.
class CanvasBranch {
  /// Unique branch ID (e.g., 'br_1770984278933')
  final String id;

  /// Root canvas this branch belongs to
  final String canvasId;

  /// Parent branch ID — null means forked from main timeline
  final String? parentBranchId;

  /// Event index in parent timeline where this branch splits off
  final int forkPointEventIndex;

  /// Absolute timestamp (epoch ms) of the fork point
  final int forkPointMs;

  /// User-facing display name (e.g., "Idea alternativa")
  final String name;

  /// User ID of the branch creator
  final String createdBy;

  /// When the branch was created
  final DateTime createdAt;

  /// Visual color tag for Branch Explorer UI
  final String? color;

  /// Optional description — explains *why* this branch was created
  final String? description;

  // ============================================================================
  // CLOUD SYNC FIELDS
  // ============================================================================

  /// Epoch ms of last canvas modification on this branch (for LWW conflict detection)
  final int lastModifiedMs;

  /// Increments each time a snapshot is uploaded to Cloud Storage
  final int snapshotVersion;

  /// Cloud Storage path of the latest snapshot (null = never synced)
  final String? snapshotStoragePath;

  /// Number of TT sessions synced to cloud (for incremental sync)
  final int ttSessionCount;

  /// Per-layer MD5 hashes from last upload — enables diff-based sync
  /// `{layerId: md5Hash}` — only layers with changed hashes are re-uploaded
  final Map<String, String>? layerHashes;

  CanvasBranch({
    required this.id,
    required this.canvasId,
    this.parentBranchId,
    required this.forkPointEventIndex,
    required this.forkPointMs,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    this.color,
    this.description,
    this.lastModifiedMs = 0,
    this.snapshotVersion = 0,
    this.snapshotStoragePath,
    this.ttSessionCount = 0,
    this.layerHashes,
  });

  /// Is this branch forked directly from the main timeline?
  bool get isRootBranch => parentBranchId == null;

  /// Has this branch ever been synced to cloud?
  bool get isSyncedToCloud => snapshotStoragePath != null;

  /// Depth level in the tree (0 = forked from main, 1 = forked from a branch)
  /// Computed dynamically by the BranchingManager via tree traversal
  int depthLevel = 0;

  // ============================================================================
  // SERIALIZATION
  // ============================================================================

  Map<String, dynamic> toJson() => {
    'id': id,
    'canvasId': canvasId,
    if (parentBranchId != null) 'parentBranchId': parentBranchId,
    'forkPointEventIndex': forkPointEventIndex,
    'forkPointMs': forkPointMs,
    'name': name,
    'createdBy': createdBy,
    'createdAtMs': createdAt.millisecondsSinceEpoch,
    if (color != null) 'color': color,
    if (description != null) 'description': description,
    'lastModifiedMs': lastModifiedMs,
    'snapshotVersion': snapshotVersion,
    if (snapshotStoragePath != null) 'snapshotStoragePath': snapshotStoragePath,
    'ttSessionCount': ttSessionCount,
    if (layerHashes != null) 'layerHashes': layerHashes,
  };

  factory CanvasBranch.fromJson(Map<String, dynamic> json) {
    return CanvasBranch(
      id: json['id'] as String,
      canvasId: json['canvasId'] as String,
      parentBranchId: json['parentBranchId'] as String?,
      forkPointEventIndex: json['forkPointEventIndex'] as int,
      forkPointMs: json['forkPointMs'] as int,
      name: json['name'] as String,
      createdBy: json['createdBy'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAtMs'] as int,
      ),
      color: json['color'] as String?,
      description: json['description'] as String?,
      lastModifiedMs: json['lastModifiedMs'] as int? ?? 0,
      snapshotVersion: json['snapshotVersion'] as int? ?? 0,
      snapshotStoragePath: json['snapshotStoragePath'] as String?,
      ttSessionCount: json['ttSessionCount'] as int? ?? 0,
      layerHashes: (json['layerHashes'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as String),
      ),
    );
  }

  CanvasBranch copyWith({
    String? name,
    String? color,
    String? description,
    bool clearDescription = false,
    int? lastModifiedMs,
    int? snapshotVersion,
    String? snapshotStoragePath,
    int? ttSessionCount,
    Map<String, String>? layerHashes,
  }) {
    return CanvasBranch(
      id: id,
      canvasId: canvasId,
      parentBranchId: parentBranchId,
      forkPointEventIndex: forkPointEventIndex,
      forkPointMs: forkPointMs,
      name: name ?? this.name,
      createdBy: createdBy,
      createdAt: createdAt,
      color: color ?? this.color,
      description: clearDescription ? null : (description ?? this.description),
      lastModifiedMs: lastModifiedMs ?? this.lastModifiedMs,
      snapshotVersion: snapshotVersion ?? this.snapshotVersion,
      snapshotStoragePath: snapshotStoragePath ?? this.snapshotStoragePath,
      ttSessionCount: ttSessionCount ?? this.ttSessionCount,
      layerHashes: layerHashes ?? this.layerHashes,
    );
  }

  @override
  String toString() =>
      'CanvasBranch($id, "$name", fork@$forkPointEventIndex, '
      'parent: ${parentBranchId ?? "main"}, v$snapshotVersion)';
}
