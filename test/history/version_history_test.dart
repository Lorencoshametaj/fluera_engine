import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/history/version_history.dart';

void main() {
  group('VersionHistory', () {
    late VersionHistory history;

    setUp(() {
      history = VersionHistory();
    });

    test('creates and retrieves entries', () {
      final id = history.createEntry(
        title: 'v1',
        authorId: 'alice',
        data: {'scene': 'data1'},
      );
      expect(history.length, 1);
      expect(history.getEntry(id)?.title, 'v1');
    });

    test('newest entry is first', () {
      history.createEntry(title: 'old', authorId: 'a', data: {});
      history.createEntry(title: 'new', authorId: 'a', data: {});
      expect(history.entries.first.title, 'new');
    });

    test('deletes entry', () {
      final id = history.createEntry(title: 'v1', authorId: 'a', data: {});
      expect(history.deleteEntry(id), isTrue);
      expect(history.length, 0);
    });

    test('restores data', () {
      final id = history.createEntry(
        title: 'v1',
        authorId: 'a',
        data: {'key': 'value'},
      );
      final data = history.restore(id);
      expect(data?['key'], 'value');
    });

    test('returns null for unknown restore', () {
      expect(history.restore('nonexistent'), isNull);
    });

    test('filters by author', () {
      history.createEntry(title: 'a1', authorId: 'alice', data: {});
      history.createEntry(title: 'b1', authorId: 'bob', data: {});
      expect(history.byAuthor('alice').length, 1);
    });

    test('filters by tag', () {
      history.createEntry(
        title: 'v1',
        authorId: 'a',
        data: {},
        tags: ['release'],
      );
      history.createEntry(title: 'v2', authorId: 'a', data: {});
      expect(history.byTag('release').length, 1);
    });

    test('diff between versions', () {
      final id1 = history.createEntry(
        title: 'v1',
        authorId: 'a',
        data: {'a': 1, 'b': 2, 'c': 3},
      );
      final id2 = history.createEntry(
        title: 'v2',
        authorId: 'a',
        data: {'b': 99, 'c': 3, 'd': 4},
      );
      final d = history.diff(id1, id2);
      expect(d.added, contains('d'));
      expect(d.removed, contains('a'));
      expect(d.changed, contains('b'));
      expect(d.isEmpty, isFalse);
    });

    test('JSON roundtrip', () {
      history.createEntry(
        title: 'v1',
        authorId: 'alice',
        data: {'x': 1},
        tags: ['autosave'],
      );
      final json = history.toJson();
      final restored = VersionHistory.fromJson(json);
      expect(restored.length, 1);
      expect(restored.entries.first.title, 'v1');
      expect(restored.entries.first.tags, contains('autosave'));
    });
  });
}
