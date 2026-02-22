import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/collaboration/design_comment.dart';

void main() {
  group('DesignComment', () {
    test('creates with required fields', () {
      final c = DesignComment(
        id: 'c1',
        authorId: 'alice',
        authorName: 'Alice',
        text: 'Looks good!',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(c.id, 'c1');
      expect(c.text, 'Looks good!');
      expect(c.isEdited, isFalse);
    });

    test('edit updates text and editedAt', () {
      final c = DesignComment(
        id: 'c1',
        authorId: 'alice',
        authorName: 'Alice',
        text: 'Original',
        createdAt: DateTime(2026, 1, 1),
      );
      c.edit('Updated');
      expect(c.text, 'Updated');
      expect(c.isEdited, isTrue);
    });

    test('JSON roundtrip', () {
      final c = DesignComment(
        id: 'c1',
        authorId: 'alice',
        authorName: 'Alice',
        text: 'Hello',
        createdAt: DateTime(2026, 1, 15),
      );
      final restored = DesignComment.fromJson(c.toJson());
      expect(restored.id, 'c1');
      expect(restored.text, 'Hello');
      expect(restored.authorName, 'Alice');
    });
  });

  group('CommentThread', () {
    CommentThread _thread() => CommentThread(
      id: 'thread-1',
      rootComment: DesignComment(
        id: 'c1',
        authorId: 'alice',
        authorName: 'Alice',
        text: 'Fix the contrast',
        createdAt: DateTime(2026, 1, 1),
      ),
      anchorNodeId: 'btn-1',
    );

    test('add and count replies', () {
      final thread = _thread();
      expect(thread.commentCount, 1);
      thread.addReply(
        DesignComment(
          id: 'c2',
          authorId: 'bob',
          authorName: 'Bob',
          text: 'Done.',
          createdAt: DateTime(2026, 1, 2),
        ),
      );
      expect(thread.commentCount, 2);
      expect(thread.latestComment.text, 'Done.');
    });

    test('resolve and unresolve', () {
      final thread = _thread();
      expect(thread.isResolved, isFalse);
      thread.resolve(byUserId: 'bob');
      expect(thread.isResolved, isTrue);
      expect(thread.resolvedBy, 'bob');
      thread.unresolve();
      expect(thread.isResolved, isFalse);
      expect(thread.resolvedBy, isNull);
    });

    test('remove reply by ID', () {
      final thread = _thread();
      thread.addReply(
        DesignComment(
          id: 'c2',
          authorId: 'bob',
          authorName: 'Bob',
          text: 'Reply',
          createdAt: DateTime(2026, 1, 2),
        ),
      );
      expect(thread.removeReply('c2'), isTrue);
      expect(thread.commentCount, 1);
      expect(thread.removeReply('nonexistent'), isFalse);
    });

    test('JSON roundtrip with replies', () {
      final thread = _thread();
      thread.addReply(
        DesignComment(
          id: 'c2',
          authorId: 'bob',
          authorName: 'Bob',
          text: 'Fixed!',
          createdAt: DateTime(2026, 1, 2),
        ),
      );
      final json = thread.toJson();
      final restored = CommentThread.fromJson(json);
      expect(restored.id, 'thread-1');
      expect(restored.anchorNodeId, 'btn-1');
      expect(restored.replies.length, 1);
      expect(restored.replies.first.text, 'Fixed!');
    });

    test('canvas-anchored thread', () {
      final thread = CommentThread(
        id: 'thread-2',
        rootComment: DesignComment(
          id: 'c3',
          authorId: 'alice',
          authorName: 'Alice',
          text: 'General note',
          createdAt: DateTime(2026, 1, 5),
        ),
        anchorPosition: const Offset(100, 200),
      );
      final restored = CommentThread.fromJson(thread.toJson());
      expect(restored.anchorPosition, const Offset(100, 200));
      expect(restored.anchorNodeId, isNull);
    });
  });

  group('DesignCommentSystem', () {
    DesignCommentSystem _system() {
      final system = DesignCommentSystem();
      system.addThread(
        CommentThread(
          id: 't1',
          rootComment: DesignComment(
            id: 'c1',
            authorId: 'alice',
            authorName: 'Alice',
            text: 'Issue 1',
            createdAt: DateTime(2026, 2, 1),
          ),
          anchorNodeId: 'node-A',
        ),
      );
      system.addThread(
        CommentThread(
          id: 't2',
          rootComment: DesignComment(
            id: 'c2',
            authorId: 'bob',
            authorName: 'Bob',
            text: 'Issue 2',
            createdAt: DateTime(2026, 2, 10),
          ),
          anchorNodeId: 'node-B',
        ),
      );
      return system;
    }

    test('CRUD operations', () {
      final system = _system();
      expect(system.threadCount, 2);
      expect(system.getThread('t1')?.rootComment.text, 'Issue 1');
      system.removeThread('t1');
      expect(system.threadCount, 1);
    });

    test('filter by node', () {
      final system = _system();
      expect(system.threadsForNode('node-A').length, 1);
      expect(system.threadsForNode('nonexistent').length, 0);
    });

    test('filter by author', () {
      final system = _system();
      expect(system.threadsByAuthor('alice').length, 1);
      expect(system.threadsByAuthor('bob').length, 1);
    });

    test('resolved/unresolved filtering', () {
      final system = _system();
      expect(system.unresolvedCount, 2);
      system.resolveThread('t1', byUserId: 'bob');
      expect(system.unresolvedCount, 1);
      expect(system.resolvedThreads.length, 1);
      expect(system.unresolvedThreads.length, 1);
    });

    test('date range filtering', () {
      final system = _system();
      final results = system.threadsInRange(
        DateTime(2026, 2, 5),
        DateTime(2026, 2, 15),
      );
      expect(results.length, 1);
      expect(results.first.id, 't2');
    });

    test('JSON roundtrip', () {
      final system = _system();
      system.resolveThread('t1', byUserId: 'bob');
      final json = system.toJson();
      final restored = DesignCommentSystem.fromJson(json);
      expect(restored.threadCount, 2);
      expect(restored.getThread('t1')?.isResolved, isTrue);
    });
  });
}
