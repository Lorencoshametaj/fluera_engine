import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'command_history.dart';

// ---------------------------------------------------------------------------
// AsyncCommand
// ---------------------------------------------------------------------------

/// An undoable command whose execution is asynchronous.
///
/// Use for long-running operations like batch transforms on 10k+ nodes,
/// export pipelines, AI-assisted operations, or network-dependent work.
///
/// ```dart
/// class BatchTransformCommand extends AsyncCommand {
///   final List<String> nodeIds;
///   BatchTransformCommand(this.nodeIds)
///     : super(label: 'Transform ${nodeIds.length} nodes');
///
///   @override
///   Future<void> executeAsync(AsyncCommandContext ctx) async {
///     for (int i = 0; i < nodeIds.length; i++) {
///       if (ctx.isCancelled) return;
///       await transformNode(nodeIds[i]);
///       ctx.reportProgress(i / nodeIds.length);
///     }
///   }
///
///   @override
///   Future<void> undoAsync(AsyncCommandContext ctx) async {
///     await reverseTransforms();
///   }
/// }
/// ```
abstract class AsyncCommand {
  /// Human-readable label for UI and history.
  final String label;

  AsyncCommand({required this.label});

  /// Execute the command asynchronously.
  ///
  /// Use [ctx] to report progress and check for cancellation.
  Future<void> executeAsync(AsyncCommandContext ctx);

  /// Undo the command asynchronously.
  Future<void> undoAsync(AsyncCommandContext ctx);
}

// ---------------------------------------------------------------------------
// AsyncCommandContext
// ---------------------------------------------------------------------------

/// Context provided to [AsyncCommand.executeAsync] and
/// [AsyncCommand.undoAsync] for progress reporting and cancellation.
class AsyncCommandContext {
  /// Whether cancellation has been requested.
  bool get isCancelled => _isCancelled;
  bool _isCancelled = false;

  /// Report progress (0.0 – 1.0).
  void reportProgress(double value) {
    _progress.value = value.clamp(0.0, 1.0);
  }

  /// Report a status message.
  void reportStatus(String message) {
    _status.value = message;
  }

  /// Current progress (0.0 – 1.0).
  final ValueNotifier<double> _progress = ValueNotifier(0);
  ValueListenable<double> get progress => _progress;

  /// Current status message.
  final ValueNotifier<String> _status = ValueNotifier('');
  ValueListenable<String> get status => _status;

  /// Mark as cancelled.
  void _cancel() => _isCancelled = true;

  /// Dispose notifiers.
  void _dispose() {
    _progress.dispose();
    _status.dispose();
  }
}

// ---------------------------------------------------------------------------
// AsyncCommandState
// ---------------------------------------------------------------------------

/// State of an async command execution.
enum AsyncCommandState {
  /// Waiting in queue.
  queued,

  /// Currently executing.
  running,

  /// Completed successfully.
  completed,

  /// Cancelled by user.
  cancelled,

  /// Failed with an error.
  failed,
}

// ---------------------------------------------------------------------------
// AsyncCommandEntry
// ---------------------------------------------------------------------------

/// Tracks the lifecycle of a single [AsyncCommand] execution.
class AsyncCommandEntry {
  /// The command being executed.
  final AsyncCommand command;

  /// Current state.
  final ValueNotifier<AsyncCommandState> state = ValueNotifier(
    AsyncCommandState.queued,
  );

  /// Execution context (progress, status, cancellation).
  final AsyncCommandContext context = AsyncCommandContext();

  /// Error if state is [AsyncCommandState.failed].
  Object? error;

  /// Completer for awaiting completion.
  final Completer<void> _completer = Completer<void>();

  AsyncCommandEntry(this.command);

  /// Future that completes when the command finishes (success, cancel, or fail).
  Future<void> get done => _completer.future;

  /// Cancel this command.
  void cancel() {
    context._cancel();
    if (state.value == AsyncCommandState.queued) {
      state.value = AsyncCommandState.cancelled;
      if (!_completer.isCompleted) _completer.complete();
    }
  }

  void _dispose() {
    state.dispose();
    context._dispose();
  }
}

// ---------------------------------------------------------------------------
// AsyncCommandRunner
// ---------------------------------------------------------------------------

/// Manages a queue of [AsyncCommand]s with concurrency control.
///
/// ```dart
/// final runner = AsyncCommandRunner();
///
/// final entry = runner.enqueue(BatchTransformCommand(nodeIds));
/// entry.context.progress.addListener(() {
///   print('Progress: ${entry.context.progress.value}');
/// });
///
/// // Cancel if needed:
/// entry.cancel();
///
/// // Or wait for completion:
/// await entry.done;
/// ```
class AsyncCommandRunner {
  /// Maximum concurrent commands.
  final int maxConcurrency;

  /// Queue of pending commands.
  final Queue<AsyncCommandEntry> _queue = Queue();

  /// Currently executing entries.
  final List<AsyncCommandEntry> _running = [];

  /// Completed entries (ring buffer).
  final Queue<AsyncCommandEntry> _completed = Queue();

  /// Maximum completed entries to retain.
  final int maxRetained;

  /// Optional command history for undo integration.
  final CommandHistory? commandHistory;

  AsyncCommandRunner({
    this.maxConcurrency = 1,
    this.maxRetained = 50,
    this.commandHistory,
  });

  /// Number of queued commands.
  int get queuedCount => _queue.length;

  /// Number of currently running commands.
  int get runningCount => _running.length;

  /// Whether any commands are running or queued.
  bool get isBusy => _running.isNotEmpty || _queue.isNotEmpty;

  /// Enqueue a command for execution.
  ///
  /// Returns an [AsyncCommandEntry] for tracking progress and cancellation.
  AsyncCommandEntry enqueue(AsyncCommand command) {
    final entry = AsyncCommandEntry(command);
    _queue.addLast(entry);
    _processQueue();
    return entry;
  }

  /// Cancel all queued (not yet running) commands.
  void cancelQueued() {
    for (final entry in _queue) {
      entry.cancel();
    }
    _queue.clear();
  }

  /// Cancel everything (queued + running).
  void cancelAll() {
    cancelQueued();
    for (final entry in _running) {
      entry.cancel();
    }
  }

  void _processQueue() {
    while (_running.length < maxConcurrency && _queue.isNotEmpty) {
      final entry = _queue.removeFirst();
      if (entry.state.value == AsyncCommandState.cancelled) continue;
      _running.add(entry);
      _executeEntry(entry);
    }
  }

  Future<void> _executeEntry(AsyncCommandEntry entry) async {
    entry.state.value = AsyncCommandState.running;
    entry.context.reportProgress(0);

    try {
      await entry.command.executeAsync(entry.context);

      if (entry.context.isCancelled) {
        entry.state.value = AsyncCommandState.cancelled;
        // Best-effort undo on cancel.
        try {
          await entry.command.undoAsync(entry.context);
        } catch (_) {
          // Ignore undo errors on cancellation.
        }
      } else {
        entry.state.value = AsyncCommandState.completed;
        entry.context.reportProgress(1.0);
      }
    } catch (e) {
      entry.error = e;
      entry.state.value = AsyncCommandState.failed;
    } finally {
      _running.remove(entry);
      _completed.addLast(entry);
      if (_completed.length > maxRetained) {
        _completed.removeFirst()._dispose();
      }
      if (!entry._completer.isCompleted) {
        entry._completer.complete();
      }
      _processQueue();
    }
  }

  /// Dispose all entries and clear queues.
  void dispose() {
    cancelAll();
    for (final e in _completed) {
      e._dispose();
    }
    _completed.clear();
  }
}
