import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/history/async_command.dart';

/// Minimal test command that completes immediately.
class _InstantCommand extends AsyncCommand {
  bool executed = false;
  bool undone = false;

  _InstantCommand() : super(label: 'Instant');

  @override
  Future<void> executeAsync(AsyncCommandContext ctx) async {
    executed = true;
    ctx.reportProgress(1.0);
  }

  @override
  Future<void> undoAsync(AsyncCommandContext ctx) async {
    undone = true;
  }
}

/// Command that takes time and reports progress.
class _SlowCommand extends AsyncCommand {
  final Duration delay;
  bool executed = false;

  _SlowCommand({this.delay = const Duration(milliseconds: 50)})
    : super(label: 'Slow');

  @override
  Future<void> executeAsync(AsyncCommandContext ctx) async {
    for (int i = 0; i < 5; i++) {
      if (ctx.isCancelled) return;
      await Future.delayed(delay);
      ctx.reportProgress((i + 1) / 5);
    }
    executed = true;
  }

  @override
  Future<void> undoAsync(AsyncCommandContext ctx) async {}
}

/// Command that throws an error.
class _FailingCommand extends AsyncCommand {
  _FailingCommand() : super(label: 'Fail');

  @override
  Future<void> executeAsync(AsyncCommandContext ctx) async {
    throw Exception('Intentional failure');
  }

  @override
  Future<void> undoAsync(AsyncCommandContext ctx) async {}
}

void main() {
  // ===========================================================================
  // AsyncCommandContext
  // ===========================================================================

  group('AsyncCommandContext', () {
    test('initial state', () {
      final ctx = AsyncCommandContext();
      expect(ctx.isCancelled, false);
      expect(ctx.progress.value, 0);
      expect(ctx.status.value, '');
    });

    test('reportProgress clamps value', () {
      final ctx = AsyncCommandContext();
      ctx.reportProgress(0.5);
      expect(ctx.progress.value, 0.5);

      ctx.reportProgress(2.0);
      expect(ctx.progress.value, 1.0);

      ctx.reportProgress(-1.0);
      expect(ctx.progress.value, 0.0);
    });

    test('reportStatus updates', () {
      final ctx = AsyncCommandContext();
      ctx.reportStatus('Loading...');
      expect(ctx.status.value, 'Loading...');
    });
  });

  // ===========================================================================
  // AsyncCommandState
  // ===========================================================================

  group('AsyncCommandState', () {
    test('has all expected values', () {
      expect(AsyncCommandState.values, hasLength(5));
      expect(AsyncCommandState.values, contains(AsyncCommandState.queued));
      expect(AsyncCommandState.values, contains(AsyncCommandState.running));
      expect(AsyncCommandState.values, contains(AsyncCommandState.completed));
      expect(AsyncCommandState.values, contains(AsyncCommandState.cancelled));
      expect(AsyncCommandState.values, contains(AsyncCommandState.failed));
    });
  });

  // ===========================================================================
  // AsyncCommandEntry
  // ===========================================================================

  group('AsyncCommandEntry', () {
    test('initial state is queued', () {
      final entry = AsyncCommandEntry(_InstantCommand());
      expect(entry.state.value, AsyncCommandState.queued);
      expect(entry.error, isNull);
    });

    test('cancel sets cancelled state for queued entry', () {
      final entry = AsyncCommandEntry(_InstantCommand());
      entry.cancel();
      expect(entry.state.value, AsyncCommandState.cancelled);
    });
  });

  // ===========================================================================
  // AsyncCommandRunner
  // ===========================================================================

  group('AsyncCommandRunner', () {
    test('executes command and completes', () async {
      final runner = AsyncCommandRunner();
      final cmd = _InstantCommand();
      final entry = runner.enqueue(cmd);

      await entry.done;

      expect(cmd.executed, true);
      expect(entry.state.value, AsyncCommandState.completed);
      expect(entry.context.progress.value, 1.0);

      runner.dispose();
    });

    test('handles failing command', () async {
      final runner = AsyncCommandRunner();
      final cmd = _FailingCommand();
      final entry = runner.enqueue(cmd);

      await entry.done;

      expect(entry.state.value, AsyncCommandState.failed);
      expect(entry.error, isNotNull);

      runner.dispose();
    });

    test('cancelQueued cancels queued commands', () async {
      // Set concurrency to 1 and enqueue 3 commands — first runs, others queue
      final runner = AsyncCommandRunner(maxConcurrency: 1);
      final slow = _SlowCommand(delay: const Duration(milliseconds: 100));
      final entry1 = runner.enqueue(slow);
      final cmd2 = _InstantCommand();
      final entry2 = runner.enqueue(cmd2);

      // Cancel queued while first is running
      runner.cancelQueued();

      await entry1.done;

      expect(cmd2.executed, false);

      runner.dispose();
    });

    test('isBusy reflects queue state', () async {
      final runner = AsyncCommandRunner();
      expect(runner.isBusy, false);

      final entry = runner.enqueue(_InstantCommand());
      // Might already be done, but isBusy should have been true at some point
      await entry.done;

      expect(runner.isBusy, false);
      runner.dispose();
    });

    test('queuedCount and runningCount', () {
      final runner = AsyncCommandRunner(maxConcurrency: 1);
      expect(runner.queuedCount, 0);
      expect(runner.runningCount, 0);

      runner.dispose();
    });

    test('multiple commands execute sequentially with concurrency 1', () async {
      final runner = AsyncCommandRunner(maxConcurrency: 1);
      final cmd1 = _InstantCommand();
      final cmd2 = _InstantCommand();

      final entry1 = runner.enqueue(cmd1);
      final entry2 = runner.enqueue(cmd2);

      await entry1.done;
      await entry2.done;

      expect(cmd1.executed, true);
      expect(cmd2.executed, true);

      runner.dispose();
    });

    test('dispose cleans up', () {
      final runner = AsyncCommandRunner();
      runner.enqueue(_InstantCommand());
      runner.dispose(); // Should not throw
    });
  });
}
