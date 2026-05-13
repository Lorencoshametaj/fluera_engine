import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/chat_read_tracker.dart';

void main() {
  group('ChatReadTracker.retention7d', () {
    test('returns the 5% floor when wordCount is zero', () {
      expect(
        ChatReadTracker.retention7d(readSeconds: 10, wordCount: 0),
        5,
      );
    });

    test('clamps to the 85% ceiling for very short reads', () {
      // Short read of a few words → ratio ≈ 0 → 0.85 ceiling.
      expect(
        ChatReadTracker.retention7d(readSeconds: 30, wordCount: 1),
        85,
      );
    });

    test('decays monotonically as words/seconds increases', () {
      final fastRead = ChatReadTracker.retention7d(
        readSeconds: 2,
        wordCount: 200,
      );
      final mediumRead = ChatReadTracker.retention7d(
        readSeconds: 8,
        wordCount: 120,
      );
      final slowRead = ChatReadTracker.retention7d(
        readSeconds: 30,
        wordCount: 120,
      );

      // More words per second = lower retention.
      expect(fastRead, lessThan(mediumRead));
      expect(mediumRead, lessThan(slowRead));
    });

    test('typical 8s read of a 120-word reply lands in the 30-60% band', () {
      // Below retrieval practice (Roediger 2006 ≈ 80%+) but above the
      // panic floor. The badge is a calibration nudge, not a guilt trip.
      final r = ChatReadTracker.retention7d(readSeconds: 8, wordCount: 120);
      expect(r, greaterThanOrEqualTo(30));
      expect(r, lessThanOrEqualTo(60));
    });

    test('treats readSeconds < 1 as 1 second (no divide-by-zero)', () {
      // Should not throw; should return a sane integer.
      final r = ChatReadTracker.retention7d(readSeconds: 0, wordCount: 50);
      expect(r, inInclusiveRange(5, 85));
    });
  });

  group('ChatReadTracker.countWords', () {
    test('returns 0 for empty', () {
      expect(ChatReadTracker.countWords(''), 0);
    });

    test('counts simple words', () {
      expect(ChatReadTracker.countWords('one two three'), 3);
    });

    test('ignores punctuation', () {
      expect(ChatReadTracker.countWords('hello, world! how are you?'), 5);
    });

    test('collapses repeated whitespace', () {
      expect(ChatReadTracker.countWords('a  b   c\n\nd'), 4);
    });
  });

  group('ChatReadTracker visibility tracking', () {
    test('markVisible records first-seen and ignores subsequent calls', () {
      final t = ChatReadTracker();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      t.markVisible('msg_1', now: t0);

      // 5 seconds later, mark again — should NOT reset the start.
      final t5 = t0.add(const Duration(seconds: 5));
      t.markVisible('msg_1', now: t5);

      final t8 = t0.add(const Duration(seconds: 8));
      expect(t.secondsRead('msg_1', now: t8), 8);
    });

    test('secondsRead returns 0 for unknown id', () {
      final t = ChatReadTracker();
      expect(t.secondsRead('never_seen'), 0);
    });

    test('forget removes a single message; clear empties everything', () {
      final t = ChatReadTracker();
      final now = DateTime(2026, 1, 1);
      t.markVisible('a', now: now);
      t.markVisible('b', now: now);

      t.forget('a');
      expect(t.secondsRead('a'), 0);
      expect(t.secondsRead('b', now: now.add(const Duration(seconds: 3))), 3);

      t.clear();
      expect(t.secondsRead('b'), 0);
    });
  });
}
