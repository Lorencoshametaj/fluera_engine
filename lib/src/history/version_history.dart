/// 📜 VERSION HISTORY — Named snapshots for document version control.
///
/// Complements `command_history.dart` (undo/redo) with explicit named versions
/// that users can create, browse, and restore.
///
/// ```dart
/// final history = VersionHistory();
/// history.createEntry(
///   title: 'Initial layout',
///   authorId: 'alice',
///   data: documentSnapshot,
/// );
/// // Later...
/// history.createEntry(title: 'After review', authorId: 'bob', data: newSnap);
/// final old = history.entries.first;
/// final restored = history.restore(old.id);
/// ```
library;

// =============================================================================
// VERSION ENTRY
// =============================================================================

/// A single named version snapshot.
class VersionEntry {
  /// Unique version ID.
  final String id;

  /// Human-readable title (e.g., "After client review").
  String title;

  /// Optional description.
  String description;

  /// User who created this version.
  final String authorId;

  /// When this version was created.
  final DateTime createdAt;

  /// Serialized document data (opaque blob).
  ///
  /// The caller decides what to store — typically a full or delta snapshot
  /// of the scene graph in JSON/binary form.
  final Map<String, dynamic> data;

  /// Optional tags for categorization.
  final List<String> tags;

  VersionEntry({
    required this.id,
    required this.title,
    this.description = '',
    required this.authorId,
    required this.createdAt,
    required this.data,
    this.tags = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'authorId': authorId,
    'createdAt': createdAt.toIso8601String(),
    'data': data,
    'tags': tags,
  };

  factory VersionEntry.fromJson(Map<String, dynamic> json) => VersionEntry(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    authorId: json['authorId'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    data: Map<String, dynamic>.from(json['data'] as Map),
    tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
  );
}

// =============================================================================
// VERSION HISTORY
// =============================================================================

/// Manages an ordered list of named version snapshots.
class VersionHistory {
  final List<VersionEntry> _entries = [];
  int _autoIdCounter = 0;

  /// All entries, newest first.
  List<VersionEntry> get entries => List.unmodifiable(_entries);

  /// Number of stored versions.
  int get length => _entries.length;

  /// Create a new version entry.
  ///
  /// Returns the created entry's ID.
  String createEntry({
    String? id,
    required String title,
    String description = '',
    required String authorId,
    required Map<String, dynamic> data,
    List<String> tags = const [],
  }) {
    final entryId = id ?? 'v${++_autoIdCounter}';
    _entries.insert(
      0,
      VersionEntry(
        id: entryId,
        title: title,
        description: description,
        authorId: authorId,
        createdAt: DateTime.now(),
        data: Map<String, dynamic>.from(data),
        tags: List<String>.from(tags),
      ),
    );
    return entryId;
  }

  /// Get a version entry by ID.
  VersionEntry? getEntry(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Delete a version entry by ID.
  bool deleteEntry(String id) {
    final len = _entries.length;
    _entries.removeWhere((e) => e.id == id);
    return _entries.length < len;
  }

  /// Restore a version: returns the stored data blob.
  ///
  /// Returns null if the version is not found.
  Map<String, dynamic>? restore(String id) {
    final entry = getEntry(id);
    return entry != null ? Map<String, dynamic>.from(entry.data) : null;
  }

  /// Get entries by author.
  List<VersionEntry> byAuthor(String authorId) =>
      _entries.where((e) => e.authorId == authorId).toList();

  /// Get entries with a specific tag.
  List<VersionEntry> byTag(String tag) =>
      _entries.where((e) => e.tags.contains(tag)).toList();

  /// Get entries in a date range.
  List<VersionEntry> inRange(DateTime start, DateTime end) =>
      _entries
          .where((e) => e.createdAt.isAfter(start) && e.createdAt.isBefore(end))
          .toList();

  /// Compute a simple diff summary between two versions.
  ///
  /// Returns keys that were added, removed, or changed.
  VersionDiff diff(String fromId, String toId) {
    final from = getEntry(fromId);
    final to = getEntry(toId);
    if (from == null || to == null) {
      return const VersionDiff(added: [], removed: [], changed: []);
    }

    final fromKeys = from.data.keys.toSet();
    final toKeys = to.data.keys.toSet();

    return VersionDiff(
      added: toKeys.difference(fromKeys).toList(),
      removed: fromKeys.difference(toKeys).toList(),
      changed:
          fromKeys
              .intersection(toKeys)
              .where((k) => from.data[k] != to.data[k])
              .toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'entries': _entries.map((e) => e.toJson()).toList(),
  };

  static VersionHistory fromJson(Map<String, dynamic> json) {
    final history = VersionHistory();
    for (final e in (json['entries'] as List<dynamic>? ?? [])) {
      history._entries.add(VersionEntry.fromJson(e as Map<String, dynamic>));
    }
    return history;
  }
}

// =============================================================================
// VERSION DIFF
// =============================================================================

/// Summary of differences between two versions.
class VersionDiff {
  final List<String> added;
  final List<String> removed;
  final List<String> changed;

  const VersionDiff({
    required this.added,
    required this.removed,
    required this.changed,
  });

  /// Total number of changes.
  int get totalChanges => added.length + removed.length + changed.length;

  /// Whether the two versions are identical.
  bool get isEmpty => totalChanges == 0;
}
