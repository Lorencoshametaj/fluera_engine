import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/fluera_engine.dart';

void main() {
  late Directory tmpDir;
  late String journalPath;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('command_journal_test_');
    journalPath = '${tmpDir.path}/test_journal.jsonl';
  });

  tearDown(() {
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  group('CommandJournal', () {
    test('writeBeforeExecuteSync creates a pending entry on disk', () {
      final journal = CommandJournal(journalPath: journalPath);
      final id = journal.writeBeforeExecuteSync(commandLabel: 'AddNode');

      expect(id, isNotEmpty);
      expect(File(journalPath).existsSync(), isTrue);

      final pending = journal.readUncommittedSync();
      expect(pending, hasLength(1));
      expect(pending.first.commandLabel, equals('AddNode'));
      expect(pending.first.state, equals(JournalEntryState.pending));
    });

    test('markCommittedSync transitions entry to committed', () {
      final journal = CommandJournal(journalPath: journalPath);
      final id = journal.writeBeforeExecuteSync(commandLabel: 'Test');
      journal.markCommittedSync(id);

      final pending = journal.readUncommittedSync();
      expect(pending, isEmpty);
    });

    test('markRolledBackSync transitions entry to rolledBack', () {
      final journal = CommandJournal(journalPath: journalPath);
      final id = journal.writeBeforeExecuteSync(commandLabel: 'Test');
      journal.markRolledBackSync(id);

      final pending = journal.readUncommittedSync();
      expect(pending, isEmpty);
    });

    test('readUncommitted returns only pending entries', () async {
      final journal = CommandJournal(journalPath: journalPath);

      final id1 = journal.writeBeforeExecuteSync(commandLabel: 'Cmd1');
      journal.writeBeforeExecuteSync(commandLabel: 'Cmd2');
      final id3 = journal.writeBeforeExecuteSync(commandLabel: 'Cmd3');

      journal.markCommittedSync(id1);
      journal.markRolledBackSync(id3);

      final pending = await journal.readUncommitted();
      expect(pending, hasLength(1));
      expect(pending.first.commandLabel, equals('Cmd2'));
    });

    test('checkpoint compacts journal file', () async {
      final journal = CommandJournal(journalPath: journalPath);

      final id1 = journal.writeBeforeExecuteSync(commandLabel: 'Cmd1');
      journal.writeBeforeExecuteSync(commandLabel: 'Cmd2');

      journal.markCommittedSync(id1);
      await journal.checkpoint();

      // Only Cmd2 should remain
      final journal2 = CommandJournal(journalPath: journalPath);
      final pending = journal2.readUncommittedSync();
      expect(pending, hasLength(1));
      expect(pending.first.commandLabel, equals('Cmd2'));
    });

    test('checkpoint deletes file when all entries are resolved', () async {
      final journal = CommandJournal(journalPath: journalPath);
      final id = journal.writeBeforeExecuteSync(commandLabel: 'Cmd1');
      journal.markCommittedSync(id);

      await journal.checkpoint();
      expect(File(journalPath).existsSync(), isFalse);
    });

    test('crash recovery: fresh journal reads uncommitted from disk', () {
      // Simulate: write pending, then "crash" (create new journal instance)
      final journal1 = CommandJournal(journalPath: journalPath);
      journal1.writeBeforeExecuteSync(commandLabel: 'CrashCmd');

      // New instance (simulated restart after crash)
      final journal2 = CommandJournal(journalPath: journalPath);
      final pending = journal2.readUncommittedSync();

      expect(pending, hasLength(1));
      expect(pending.first.commandLabel, equals('CrashCmd'));
    });

    test('async writeBeforeExecute works correctly', () async {
      final journal = CommandJournal(journalPath: journalPath);
      final id = await journal.writeBeforeExecute(commandLabel: 'AsyncCmd');
      expect(id, isNotEmpty);

      final pending = await journal.readUncommitted();
      expect(pending, hasLength(1));
      expect(pending.first.commandLabel, equals('AsyncCmd'));
    });

    test('entryCount tracks in-memory entries', () {
      final journal = CommandJournal(journalPath: journalPath);
      expect(journal.entryCount, equals(0));

      journal.writeBeforeExecuteSync(commandLabel: 'A');
      journal.writeBeforeExecuteSync(commandLabel: 'B');
      expect(journal.entryCount, equals(2));
    });

    test('existsOnDisk reflects file state', () {
      final journal = CommandJournal(journalPath: journalPath);
      expect(journal.existsOnDisk, isFalse);

      journal.writeBeforeExecuteSync(commandLabel: 'Test');
      expect(journal.existsOnDisk, isTrue);
    });

    test('corrupted lines in journal are skipped', () {
      // Manually write garbage + valid entry
      File(journalPath).writeAsStringSync(
        'GARBAGE_LINE\n'
        '{"id":"j_1","label":"ValidCmd","ts":"2026-01-01T00:00:00.000","state":"pending"}\n',
      );

      final journal = CommandJournal(journalPath: journalPath);
      final pending = journal.readUncommittedSync();
      expect(pending, hasLength(1));
      expect(pending.first.commandLabel, equals('ValidCmd'));
    });
  });

  group('JournalRecoveryMiddleware', () {
    test('writes pending before execute and commits after', () {
      final journal = CommandJournal(journalPath: journalPath);
      final middleware = JournalRecoveryMiddleware(journal: journal);
      final history = CommandHistory(middlewares: [middleware]);

      history.execute(_TestCmd('TestExec'));

      // Should be committed (not pending)
      final pending = journal.readUncommittedSync();
      expect(pending, isEmpty);
      expect(journal.entryCount, equals(1));
    });

    test('writes journal entries for undo and redo', () {
      final journal = CommandJournal(journalPath: journalPath);
      final middleware = JournalRecoveryMiddleware(journal: journal);
      final history = CommandHistory(middlewares: [middleware]);

      history.execute(_TestCmd('UndoRedo'));
      history.undo();
      history.redo();

      // All 3 entries should be committed
      final pending = journal.readUncommittedSync();
      expect(pending, isEmpty);
      expect(journal.entryCount, equals(3));
    });
  });
}

class _TestCmd extends Command {
  bool executed = false;

  _TestCmd(String name) : super(label: name);

  @override
  void execute() => executed = true;

  @override
  void undo() => executed = false;
}
