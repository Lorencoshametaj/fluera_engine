import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// Journal Entry
// ---------------------------------------------------------------------------

/// State of a single journal entry.
enum JournalEntryState { pending, committed, rolledBack }

/// Single entry in the command journal (WAL).
///
/// Written before command execution (`pending`), then updated to
/// `committed` after success, or `rolledBack` on failure/crash recovery.
class JournalEntry {
  /// Unique entry identifier.
  final String id;

  /// Human-readable label of the command.
  final String commandLabel;

  /// Timestamp when entry was created.
  final DateTime timestamp;

  /// Current state of this entry.
  JournalEntryState state;

  /// Optional metadata (e.g. node IDs affected, command type).
  final Map<String, dynamic>? metadata;

  JournalEntry({
    required this.id,
    required this.commandLabel,
    required this.timestamp,
    this.state = JournalEntryState.pending,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': commandLabel,
    'ts': timestamp.toIso8601String(),
    'state': state.name,
    if (metadata != null) 'meta': metadata,
  };

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
    id: json['id'] as String,
    commandLabel: json['label'] as String,
    timestamp: DateTime.parse(json['ts'] as String),
    state: JournalEntryState.values.firstWhere(
      (s) => s.name == json['state'],
      orElse: () => JournalEntryState.pending,
    ),
    metadata: json['meta'] as Map<String, dynamic>?,
  );
}

// ---------------------------------------------------------------------------
// Command Journal
// ---------------------------------------------------------------------------

/// Write-ahead journal for crash recovery of in-flight commands.
///
/// Before a command executes, a journal entry is written to disk.
/// After successful execution, the entry is marked as committed.
/// On startup, uncommitted entries indicate a crash occurred mid-command.
///
/// The journal is a single JSONL file (one JSON object per line),
/// which is append-only and crash-safe.
///
/// ```dart
/// final journal = CommandJournal(journalPath: '/data/canvas123.jsonl');
///
/// // Before executing a command:
/// await journal.writeBeforeExecute(entry);
///
/// // After successful execution:
/// await journal.markCommitted(entryId);
///
/// // On startup — check for uncommitted entries:
/// final pending = await journal.readUncommitted();
/// for (final entry in pending) {
///   // rollback or replay
/// }
///
/// // After successful save — compact the journal:
/// await journal.checkpoint();
/// ```
class CommandJournal {
  /// Path to the JSONL journal file.
  final String journalPath;

  /// In-memory index for fast state updates. Populated on first access.
  final Map<String, JournalEntry> _entries = {};

  /// Whether the in-memory index has been loaded from disk.
  bool _loaded = false;

  /// Monotonic counter for generating unique entry IDs.
  int _counter = 0;

  CommandJournal({required this.journalPath});

  // -------------------------------------------------------------------------
  // Write operations
  // -------------------------------------------------------------------------

  /// Generate a unique entry ID.
  String _nextId() =>
      'j_${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  /// Write a pre-execution journal entry synchronously.
  ///
  /// Uses synchronous file I/O with flush to guarantee durability before
  /// the command begins execution. The entry is written as `pending`.
  ///
  /// Returns the entry ID for later marking.
  String writeBeforeExecuteSync({
    required String commandLabel,
    Map<String, dynamic>? metadata,
  }) {
    final entry = JournalEntry(
      id: _nextId(),
      commandLabel: commandLabel,
      timestamp: DateTime.now(),
      state: JournalEntryState.pending,
      metadata: metadata,
    );
    _ensureDirectoryExists();
    final file = File(journalPath);
    file.writeAsStringSync(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
    _entries[entry.id] = entry;
    return entry.id;
  }

  /// Write a pre-execution journal entry asynchronously.
  ///
  /// Prefer [writeBeforeExecuteSync] for critical-path commands where
  /// durability must be guaranteed before execution.
  Future<String> writeBeforeExecute({
    required String commandLabel,
    Map<String, dynamic>? metadata,
  }) async {
    final entry = JournalEntry(
      id: _nextId(),
      commandLabel: commandLabel,
      timestamp: DateTime.now(),
      state: JournalEntryState.pending,
      metadata: metadata,
    );
    _ensureDirectoryExists();
    final file = File(journalPath);
    await file.writeAsString(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
    _entries[entry.id] = entry;
    return entry.id;
  }

  // -------------------------------------------------------------------------
  // State transitions
  // -------------------------------------------------------------------------

  /// Mark an entry as committed (successful execution).
  ///
  /// Appends an update line to the journal and updates in-memory state.
  void markCommittedSync(String entryId) {
    final entry = _entries[entryId];
    if (entry == null) return;
    entry.state = JournalEntryState.committed;
    _appendStateUpdate(entryId, JournalEntryState.committed);
  }

  /// Mark an entry as rolled back.
  void markRolledBackSync(String entryId) {
    final entry = _entries[entryId];
    if (entry == null) return;
    entry.state = JournalEntryState.rolledBack;
    _appendStateUpdate(entryId, JournalEntryState.rolledBack);
  }

  /// Append a state update to the journal file.
  void _appendStateUpdate(String entryId, JournalEntryState newState) {
    final update = {'_update': entryId, 'state': newState.name};
    final file = File(journalPath);
    if (!file.existsSync()) return;
    file.writeAsStringSync(
      '${jsonEncode(update)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  // -------------------------------------------------------------------------
  // Recovery
  // -------------------------------------------------------------------------

  /// Load and return all uncommitted (pending) entries.
  ///
  /// Call on startup to detect crash-recovery scenarios.
  Future<List<JournalEntry>> readUncommitted() async {
    await _loadFromDisk();
    return _entries.values
        .where((e) => e.state == JournalEntryState.pending)
        .toList();
  }

  /// Synchronous version of [readUncommitted].
  List<JournalEntry> readUncommittedSync() {
    _loadFromDiskSync();
    return _entries.values
        .where((e) => e.state == JournalEntryState.pending)
        .toList();
  }

  // -------------------------------------------------------------------------
  // Compaction
  // -------------------------------------------------------------------------

  /// Truncate all committed/rolled-back entries from the journal.
  ///
  /// Only uncommitted entries are preserved. Call after a successful save
  /// to keep the journal file small.
  Future<void> checkpoint() async {
    await _loadFromDisk();
    final pending =
        _entries.values
            .where((e) => e.state == JournalEntryState.pending)
            .toList();

    // Rewrite file with only pending entries
    final file = File(journalPath);
    if (pending.isEmpty) {
      if (await file.exists()) await file.delete();
      _entries.clear();
      return;
    }

    final buffer = StringBuffer();
    for (final entry in pending) {
      buffer.writeln(jsonEncode(entry.toJson()));
    }
    await file.writeAsString(buffer.toString(), flush: true);

    // Rebuild index
    _entries.clear();
    for (final entry in pending) {
      _entries[entry.id] = entry;
    }
  }

  /// Synchronous version of [checkpoint].
  void checkpointSync() {
    _loadFromDiskSync();
    final pending =
        _entries.values
            .where((e) => e.state == JournalEntryState.pending)
            .toList();

    final file = File(journalPath);
    if (pending.isEmpty) {
      if (file.existsSync()) file.deleteSync();
      _entries.clear();
      return;
    }

    final buffer = StringBuffer();
    for (final entry in pending) {
      buffer.writeln(jsonEncode(entry.toJson()));
    }
    file.writeAsStringSync(buffer.toString(), flush: true);

    _entries.clear();
    for (final entry in pending) {
      _entries[entry.id] = entry;
    }
  }

  // -------------------------------------------------------------------------
  // Diagnostics
  // -------------------------------------------------------------------------

  /// Current journal file size in bytes, or 0 if the file doesn't exist.
  Future<int> get sizeBytes async {
    final file = File(journalPath);
    if (await file.exists()) return file.length();
    return 0;
  }

  /// Number of entries currently tracked in memory.
  int get entryCount => _entries.length;

  /// Whether the journal file exists on disk.
  bool get existsOnDisk => File(journalPath).existsSync();

  // -------------------------------------------------------------------------
  // File I/O internals
  // -------------------------------------------------------------------------

  void _ensureDirectoryExists() {
    final dir = Directory(File(journalPath).parent.path);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  Future<void> _loadFromDisk() async {
    if (_loaded) return;
    _loadFromDiskSync();
  }

  void _loadFromDiskSync() {
    if (_loaded) return;
    _loaded = true;
    final file = File(journalPath);
    if (!file.existsSync()) return;

    final lines = file.readAsLinesSync();
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        if (json.containsKey('_update')) {
          // State update record
          final entryId = json['_update'] as String;
          final newState = JournalEntryState.values.firstWhere(
            (s) => s.name == json['state'],
            orElse: () => JournalEntryState.pending,
          );
          final existing = _entries[entryId];
          if (existing != null) existing.state = newState;
        } else {
          // Full entry record
          final entry = JournalEntry.fromJson(json);
          _entries[entry.id] = entry;
        }
      } catch (_) {
        // Skip corrupted lines
      }
    }
  }
}
