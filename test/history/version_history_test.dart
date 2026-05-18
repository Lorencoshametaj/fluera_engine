import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/fluera_canvas_config.dart'
    show FlueraSubscriptionTier;
import 'package:fluera_engine/src/history/version_history.dart';

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

  group('CheckpointLimits — tier policy', () {
    test('Free tier is capped at 3', () {
      expect(
        CheckpointLimits.limitFor(FlueraSubscriptionTier.free),
        equals(3),
      );
    });

    test('Plus / Pro / Essential are unlimited (null)', () {
      expect(
        CheckpointLimits.limitFor(FlueraSubscriptionTier.plus),
        isNull,
      );
      expect(
        CheckpointLimits.limitFor(FlueraSubscriptionTier.pro),
        isNull,
      );
      expect(
        CheckpointLimits.limitFor(FlueraSubscriptionTier.essential),
        isNull,
      );
    });
  });

  group('VersionHistory.createEntryGated — Free cap enforcement', () {
    late VersionHistory history;

    setUp(() => history = VersionHistory());

    String addOne(FlueraSubscriptionTier tier, [String title = 'cp']) {
      return history.createEntryGated(
        tier: tier,
        title: title,
        authorId: 'tester',
        data: {'snapshot': title},
      );
    }

    test('Free user can create 3 checkpoints', () {
      addOne(FlueraSubscriptionTier.free, 'a');
      addOne(FlueraSubscriptionTier.free, 'b');
      addOne(FlueraSubscriptionTier.free, 'c');
      expect(history.length, 3);
    });

    test('Free user 4th save throws CheckpointLimitError', () {
      addOne(FlueraSubscriptionTier.free, 'a');
      addOne(FlueraSubscriptionTier.free, 'b');
      addOne(FlueraSubscriptionTier.free, 'c');
      expect(
        () => addOne(FlueraSubscriptionTier.free, 'd'),
        throwsA(isA<CheckpointLimitError>()),
      );
      expect(history.length, 3, reason: 'Failed save must not bump count');
    });

    test('CheckpointLimitError carries diagnostic data', () {
      addOne(FlueraSubscriptionTier.free, 'a');
      addOne(FlueraSubscriptionTier.free, 'b');
      addOne(FlueraSubscriptionTier.free, 'c');
      try {
        addOne(FlueraSubscriptionTier.free, 'd');
        fail('Expected CheckpointLimitError');
      } on CheckpointLimitError catch (e) {
        expect(e.tier, FlueraSubscriptionTier.free);
        expect(e.currentCount, 3);
        expect(e.limit, 3);
      }
    });

    test('Plus user is unlimited', () {
      for (var i = 0; i < 10; i++) {
        addOne(FlueraSubscriptionTier.plus, 'cp$i');
      }
      expect(history.length, 10);
    });

    test('Pro user is unlimited', () {
      for (var i = 0; i < 10; i++) {
        addOne(FlueraSubscriptionTier.pro, 'cp$i');
      }
      expect(history.length, 10);
    });

    test('Archiving frees a slot for Free user', () {
      final firstId =
          addOne(FlueraSubscriptionTier.free, 'a');
      addOne(FlueraSubscriptionTier.free, 'b');
      addOne(FlueraSubscriptionTier.free, 'c');
      // Free archive ≡ deleteEntry — frees a slot.
      history.deleteEntry(firstId);
      expect(history.length, 2);
      // 4th save now succeeds.
      addOne(FlueraSubscriptionTier.free, 'd');
      expect(history.length, 3);
    });
  });
}
