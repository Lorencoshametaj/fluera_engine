/// 💬 DESIGN COMMENTS — Thread-based annotation system for canvas collaboration.
///
/// Supports pinning comments to specific nodes or canvas positions,
/// threaded replies, resolution tracking, and filtering.
///
/// ```dart
/// final system = DesignCommentSystem();
/// final threadId = system.addThread(CommentThread(
///   id: 'thread-1',
///   rootComment: DesignComment(
///     id: 'c1',
///     authorId: 'user-alice',
///     authorName: 'Alice',
///     text: 'This button needs more contrast',
///     createdAt: DateTime.now(),
///   ),
///   anchorNodeId: 'btn-primary',
/// ));
/// system.addReply('thread-1', DesignComment(
///   id: 'c2',
///   authorId: 'user-bob',
///   authorName: 'Bob',
///   text: 'Fixed! Changed to dark blue.',
///   createdAt: DateTime.now(),
/// ));
/// system.resolveThread('thread-1');
/// ```
library;

import 'dart:ui' as ui;

// =============================================================================
// DESIGN COMMENT
// =============================================================================

/// A single comment in a design review thread.
class DesignComment {
  /// Unique comment ID.
  final String id;

  /// Author user ID.
  final String authorId;

  /// Display name of the author.
  final String authorName;

  /// Comment body text.
  String text;

  /// When the comment was created.
  final DateTime createdAt;

  /// When the comment was last edited (null if never edited).
  DateTime? editedAt;

  DesignComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.editedAt,
  });

  /// Edit the comment text.
  void edit(String newText) {
    text = newText;
    editedAt = DateTime.now();
  }

  /// Whether the comment has been edited.
  bool get isEdited => editedAt != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'authorId': authorId,
    'authorName': authorName,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    if (editedAt != null) 'editedAt': editedAt!.toIso8601String(),
  };

  factory DesignComment.fromJson(Map<String, dynamic> json) => DesignComment(
    id: json['id'] as String,
    authorId: json['authorId'] as String,
    authorName: json['authorName'] as String,
    text: json['text'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    editedAt:
        json['editedAt'] != null
            ? DateTime.parse(json['editedAt'] as String)
            : null,
  );
}

// =============================================================================
// COMMENT THREAD
// =============================================================================

/// A threaded conversation anchored to a node or canvas position.
class CommentThread {
  /// Unique thread ID.
  final String id;

  /// The root (first) comment that started this thread.
  final DesignComment rootComment;

  /// Reply comments in chronological order.
  final List<DesignComment> _replies = [];

  /// Node ID this thread is pinned to (null for canvas-anchored).
  final String? anchorNodeId;

  /// Canvas position this thread is pinned to (used when anchorNodeId is null).
  final ui.Offset? anchorPosition;

  /// Whether this thread has been resolved.
  bool isResolved;

  /// When the thread was resolved (null if unresolved).
  DateTime? resolvedAt;

  /// Who resolved the thread.
  String? resolvedBy;

  CommentThread({
    required this.id,
    required this.rootComment,
    this.anchorNodeId,
    this.anchorPosition,
    this.isResolved = false,
    this.resolvedAt,
    this.resolvedBy,
  }) : assert(
         anchorNodeId != null || anchorPosition != null,
         'Thread must be anchored to a node or a canvas position',
       );

  /// All replies (read-only).
  List<DesignComment> get replies => List.unmodifiable(_replies);

  /// Total comment count (root + replies).
  int get commentCount => 1 + _replies.length;

  /// Add a reply to this thread.
  void addReply(DesignComment reply) => _replies.add(reply);

  /// Remove a reply by ID.
  bool removeReply(String commentId) {
    final len = _replies.length;
    _replies.removeWhere((c) => c.id == commentId);
    return _replies.length < len;
  }

  /// Resolve this thread.
  void resolve({required String byUserId}) {
    isResolved = true;
    resolvedAt = DateTime.now();
    resolvedBy = byUserId;
  }

  /// Reopen this thread.
  void unresolve() {
    isResolved = false;
    resolvedAt = null;
    resolvedBy = null;
  }

  /// The most recent comment (root or last reply).
  DesignComment get latestComment =>
      _replies.isNotEmpty ? _replies.last : rootComment;

  /// The author of the root comment.
  String get authorId => rootComment.authorId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'rootComment': rootComment.toJson(),
    'replies': _replies.map((r) => r.toJson()).toList(),
    if (anchorNodeId != null) 'anchorNodeId': anchorNodeId,
    if (anchorPosition != null)
      'anchorPosition': {'dx': anchorPosition!.dx, 'dy': anchorPosition!.dy},
    'isResolved': isResolved,
    if (resolvedAt != null) 'resolvedAt': resolvedAt!.toIso8601String(),
    if (resolvedBy != null) 'resolvedBy': resolvedBy,
  };

  factory CommentThread.fromJson(Map<String, dynamic> json) {
    final thread = CommentThread(
      id: json['id'] as String,
      rootComment: DesignComment.fromJson(
        json['rootComment'] as Map<String, dynamic>,
      ),
      anchorNodeId: json['anchorNodeId'] as String?,
      anchorPosition:
          json['anchorPosition'] != null
              ? ui.Offset(
                (json['anchorPosition']['dx'] as num).toDouble(),
                (json['anchorPosition']['dy'] as num).toDouble(),
              )
              : null,
      isResolved: json['isResolved'] as bool? ?? false,
      resolvedAt:
          json['resolvedAt'] != null
              ? DateTime.parse(json['resolvedAt'] as String)
              : null,
      resolvedBy: json['resolvedBy'] as String?,
    );
    final repliesJson = json['replies'] as List<dynamic>? ?? [];
    for (final r in repliesJson) {
      thread._replies.add(DesignComment.fromJson(r as Map<String, dynamic>));
    }
    return thread;
  }
}

// =============================================================================
// DESIGN COMMENT SYSTEM
// =============================================================================

/// Manager for all design comment threads in a document.
///
/// Provides CRUD operations, filtering, and serialization.
class DesignCommentSystem {
  final Map<String, CommentThread> _threads = {};

  /// All threads (read-only).
  Map<String, CommentThread> get threads => Map.unmodifiable(_threads);

  /// Total number of threads.
  int get threadCount => _threads.length;

  /// Number of unresolved threads.
  int get unresolvedCount => _threads.values.where((t) => !t.isResolved).length;

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  /// Add a new comment thread. Returns the thread ID.
  String addThread(CommentThread thread) {
    _threads[thread.id] = thread;
    return thread.id;
  }

  /// Remove a thread by ID.
  bool removeThread(String threadId) => _threads.remove(threadId) != null;

  /// Get a thread by ID.
  CommentThread? getThread(String threadId) => _threads[threadId];

  /// Add a reply to an existing thread.
  void addReply(String threadId, DesignComment reply) {
    _threads[threadId]?.addReply(reply);
  }

  /// Resolve a thread.
  void resolveThread(String threadId, {required String byUserId}) {
    _threads[threadId]?.resolve(byUserId: byUserId);
  }

  /// Reopen a resolved thread.
  void unresolveThread(String threadId) {
    _threads[threadId]?.unresolve();
  }

  // ---------------------------------------------------------------------------
  // Filtering
  // ---------------------------------------------------------------------------

  /// All threads anchored to a specific node.
  List<CommentThread> threadsForNode(String nodeId) {
    return _threads.values.where((t) => t.anchorNodeId == nodeId).toList();
  }

  /// All threads by a specific author.
  List<CommentThread> threadsByAuthor(String authorId) {
    return _threads.values.where((t) => t.authorId == authorId).toList();
  }

  /// All unresolved threads.
  List<CommentThread> get unresolvedThreads =>
      _threads.values.where((t) => !t.isResolved).toList();

  /// All resolved threads.
  List<CommentThread> get resolvedThreads =>
      _threads.values.where((t) => t.isResolved).toList();

  /// Threads created within a date range.
  List<CommentThread> threadsInRange(DateTime start, DateTime end) {
    return _threads.values.where((t) {
      final created = t.rootComment.createdAt;
      return created.isAfter(start) && created.isBefore(end);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'threads': _threads.values.map((t) => t.toJson()).toList(),
  };

  static DesignCommentSystem fromJson(Map<String, dynamic> json) {
    final system = DesignCommentSystem();
    final threadsList = json['threads'] as List<dynamic>? ?? [];
    for (final t in threadsList) {
      final thread = CommentThread.fromJson(t as Map<String, dynamic>);
      system._threads[thread.id] = thread;
    }
    return system;
  }
}
