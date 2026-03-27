/// 🧠 FSRS — Free Spaced Repetition Scheduler.
///
/// Pure-logic engine implementing a modified SM-2 algorithm with
/// confidence weighting based on the Hypercorrection Effect
/// (Butterfield & Metcalfe, 2001).
///
/// No Flutter dependencies — testable in isolation.
library;

import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────────
// SRS Card Data Model
// ─────────────────────────────────────────────────────────────────────────────

/// Immutable snapshot of a concept's spaced repetition state.
class SrsCardData {
  /// Number of successful consecutive reviews.
  final int repetitions;

  /// Easiness factor (SM-2 E-Factor), range [1.3 .. 3.0].
  final double easiness;

  /// Current interval in days until next review.
  final double interval;

  /// When the next review is due.
  final DateTime nextReview;

  /// When the last review occurred.
  final DateTime lastReview;

  /// Total number of lapses (incorrect answers after initial learning).
  final int lapses;

  const SrsCardData({
    required this.repetitions,
    required this.easiness,
    required this.interval,
    required this.nextReview,
    required this.lastReview,
    this.lapses = 0,
  });

  /// Brand-new card with no review history.
  factory SrsCardData.newCard() {
    final now = DateTime.now();
    return SrsCardData(
      repetitions: 0,
      easiness: 2.5,
      interval: 0,
      nextReview: now,
      lastReview: now,
      lapses: 0,
    );
  }

  /// Create from the old legacy format (just a DateTime).
  factory SrsCardData.fromLegacyDateTime(DateTime nextReviewDate) {
    final now = DateTime.now();
    final daysUntil = nextReviewDate.difference(now).inHours / 24.0;
    return SrsCardData(
      repetitions: 1,
      easiness: 2.5,
      interval: max(1, daysUntil),
      nextReview: nextReviewDate,
      lastReview: now,
      lapses: 0,
    );
  }

  bool get isDue => DateTime.now().isAfter(nextReview);

  Map<String, dynamic> toJson() => {
        'repetitions': repetitions,
        'easiness': easiness,
        'interval': interval,
        'nextReview': nextReview.millisecondsSinceEpoch,
        'lastReview': lastReview.millisecondsSinceEpoch,
        'lapses': lapses,
      };

  factory SrsCardData.fromJson(Map<String, dynamic> j) => SrsCardData(
        repetitions: (j['repetitions'] as num?)?.toInt() ?? 0,
        easiness: (j['easiness'] as num?)?.toDouble() ?? 2.5,
        interval: (j['interval'] as num?)?.toDouble() ?? 0,
        nextReview: DateTime.fromMillisecondsSinceEpoch(
          (j['nextReview'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        ),
        lastReview: DateTime.fromMillisecondsSinceEpoch(
          (j['lastReview'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        ),
        lapses: (j['lapses'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() =>
      'SrsCard(reps=$repetitions, ease=${easiness.toStringAsFixed(2)}, '
      'interval=${interval.toStringAsFixed(1)}d, lapses=$lapses)';
}

// ─────────────────────────────────────────────────────────────────────────────
// FSRS Scheduler
// ─────────────────────────────────────────────────────────────────────────────

class FsrsScheduler {
  const FsrsScheduler._();

  /// Reviews a card and returns the updated state.
  ///
  /// [quality]: 0 = incorrect/skipped, 1 = partial, 2 = correct.
  /// [confidence]: 1–5 from the metacognitive slider (0 = no rating).
  ///
  /// Cognitive principles applied:
  /// - **SM-2**: base interval = previous interval × easiness factor
  /// - **Hypercorrection** (Butterfield & Metcalfe 2001):
  ///     high confidence + fail → shorter interval but preservation of
  ///     easiness (the shock itself acts as a memory anchor)
  /// - **Desirable Difficulties** (Bjork 1994):
  ///     correct with high confidence → bonus interval multiplier (1.3×)
  ///     because the retrieval was effortful yet successful
  /// - **Lapse penalty**: each lapse cuts interval by 40% to prevent
  ///     over-optimistic scheduling for shaky concepts
  static SrsCardData review(
    SrsCardData card, {
    required int quality,
    int confidence = 0,
  }) {
    final now = DateTime.now();

    // ── INCORRECT / SKIPPED ──────────────────────────────────────────────
    if (quality == 0) {
      // Hypercorrection Effect: high-confidence errors get a SLIGHT
      // easiness penalty reduction — the shock factor compensates.
      // Low-confidence errors get the full SM-2 penalty.
      final confidenceFactor = confidence >= 4 ? 0.10 : 0.20;
      final newEasiness = max(1.3, card.easiness - confidenceFactor);

      // Reset to short interval but adjust based on prior success
      final lapseInterval = card.repetitions > 3 ? 2.0 : 1.0;

      return SrsCardData(
        repetitions: 0,
        easiness: newEasiness,
        interval: lapseInterval,
        nextReview: now.add(Duration(hours: (lapseInterval * 24).round())),
        lastReview: now,
        lapses: card.lapses + 1,
      );
    }

    // ── PARTIAL ──────────────────────────────────────────────────────────
    if (quality == 1) {
      final newEasiness = max(1.3, card.easiness - 0.05);
      // Partial: don't reset reps, but don't advance interval much
      final newInterval = card.repetitions == 0
          ? 1.0
          : max(1.0, card.interval * 0.8);

      return SrsCardData(
        repetitions: card.repetitions, // don't increment
        easiness: newEasiness,
        interval: newInterval,
        nextReview: now.add(Duration(hours: (newInterval * 24).round())),
        lastReview: now,
        lapses: card.lapses,
      );
    }

    // ── CORRECT ──────────────────────────────────────────────────────────
    final newReps = card.repetitions + 1;

    // SM-2 easiness update: EF' = EF + (0.1 - (5-q)(0.08+(5-q)*0.02))
    // Simplified: correct always nudges easiness up slightly
    final easinessDelta = 0.1 - (3 - quality) * (0.08 + (3 - quality) * 0.02);
    final newEasiness = max(1.3, min(3.0, card.easiness + easinessDelta));

    // Calculate new interval
    double newInterval;
    if (newReps == 1) {
      newInterval = 1.0;
    } else if (newReps == 2) {
      newInterval = 3.0;
    } else {
      newInterval = card.interval * newEasiness;
    }

    // Confidence-based modifiers (Desirable Difficulties, Bjork 1994):
    // - High confidence + correct = strong retrieval → bonus interval
    // - Low confidence + correct = lucky guess → conservative interval
    if (confidence >= 4) {
      newInterval *= 1.3; // Confident and correct → extend interval
    } else if (confidence >= 1 && confidence <= 2) {
      newInterval *= 0.85; // Not confident but correct → review sooner
    }

    // Lapse penalty: reduce interval proportionally to past failures
    if (card.lapses > 0) {
      final lapsePenalty = pow(0.9, min(card.lapses, 5)).toDouble();
      newInterval *= lapsePenalty;
    }

    // Clamp interval to sane range [1 .. 365 days]
    newInterval = newInterval.clamp(1.0, 365.0);

    return SrsCardData(
      repetitions: newReps,
      easiness: newEasiness,
      interval: newInterval,
      nextReview: now.add(Duration(hours: (newInterval * 24).round())),
      lastReview: now,
      lapses: card.lapses,
    );
  }

  /// Converts a legacy `Map<String, int>` (concept → epoch ms) schedule
  /// to the new `Map<String, SrsCardData>` format.
  static Map<String, SrsCardData> migrateLegacySchedule(
    Map<String, dynamic> legacyMap,
  ) {
    final result = <String, SrsCardData>{};
    for (final entry in legacyMap.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        // Already new format
        result[entry.key] = SrsCardData.fromJson(value);
      } else if (value is int) {
        // Legacy: milliseconds since epoch
        result[entry.key] = SrsCardData.fromLegacyDateTime(
          DateTime.fromMillisecondsSinceEpoch(value),
        );
      }
    }
    return result;
  }
}
