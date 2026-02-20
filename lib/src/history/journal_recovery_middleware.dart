import './command_history.dart';
import './command_journal.dart';

// ---------------------------------------------------------------------------
// Journal Recovery Middleware
// ---------------------------------------------------------------------------

/// A [CommandMiddleware] that bridges [CommandHistory] to [CommandJournal].
///
/// Before every command execution, a journal entry is written to disk.
/// After successful execution, the entry is marked as committed.
/// This ensures crash recovery: uncommitted entries on startup indicate
/// commands that were interrupted mid-execution.
///
/// ```dart
/// final journal = CommandJournal(journalPath: '/data/journal.jsonl');
/// final middleware = JournalRecoveryMiddleware(journal: journal);
/// history.addMiddleware(middleware);
/// ```
class JournalRecoveryMiddleware extends CommandMiddleware {
  /// The command journal to write to.
  final CommandJournal journal;

  /// Tracks the last entry ID for marking as committed.
  String? _lastEntryId;

  JournalRecoveryMiddleware({required this.journal});

  @override
  bool beforeExecute(Command cmd) {
    _lastEntryId = journal.writeBeforeExecuteSync(commandLabel: cmd.label);
    return true;
  }

  @override
  void afterExecute(Command cmd) {
    if (_lastEntryId != null) {
      journal.markCommittedSync(_lastEntryId!);
      _lastEntryId = null;
    }
  }

  @override
  void onExecuteError(Command cmd, Object error, StackTrace stack) {
    if (_lastEntryId != null) {
      journal.markRolledBackSync(_lastEntryId!);
      _lastEntryId = null;
    }
  }

  @override
  void beforeUndo(Command cmd) {
    _lastEntryId = journal.writeBeforeExecuteSync(
      commandLabel: 'undo:${cmd.label}',
    );
  }

  @override
  void afterUndo(Command cmd) {
    if (_lastEntryId != null) {
      journal.markCommittedSync(_lastEntryId!);
      _lastEntryId = null;
    }
  }

  @override
  void onUndoError(Command cmd, Object error, StackTrace stack) {
    if (_lastEntryId != null) {
      journal.markRolledBackSync(_lastEntryId!);
      _lastEntryId = null;
    }
  }

  @override
  void beforeRedo(Command cmd) {
    _lastEntryId = journal.writeBeforeExecuteSync(
      commandLabel: 'redo:${cmd.label}',
    );
  }

  @override
  void afterRedo(Command cmd) {
    if (_lastEntryId != null) {
      journal.markCommittedSync(_lastEntryId!);
      _lastEntryId = null;
    }
  }

  @override
  void onRedoError(Command cmd, Object error, StackTrace stack) {
    if (_lastEntryId != null) {
      journal.markRolledBackSync(_lastEntryId!);
      _lastEntryId = null;
    }
  }
}
