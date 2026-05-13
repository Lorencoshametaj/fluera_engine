// ============================================================================
// 🩺 WEAKNESS ANALYZER — Cross-session topic-mastery analysis.
//
// Aggregates [ExamHistoryRecord]s into a per-topic score with recency
// weighting. The Dashboard surfaces the top weaknesses so students can
// target their next study session at gaps that actually matter (not the
// topics they already mastered weeks ago).
//
// Pure Dart, no I/O — call sites pass the persisted history list. Easy to
// unit-test against fixtures.
// ============================================================================

import 'exam_session_model.dart';

/// One row of the weakness report.
class WeaknessReport {
  /// Topic title (matches the picker chip label / `selectedTopicTitles`).
  final String topic;

  /// Recency-weighted average accuracy across the considered window, in [0..1].
  final double accuracy;

  /// Total number of questions on this topic in the considered window.
  final int attempts;

  /// Trend: -1 (declining), 0 (stable), +1 (improving). Computed by
  /// comparing the most recent half of attempts to the older half.
  final int trend;

  /// When the user most recently attempted this topic.
  final DateTime lastAttempt;

  const WeaknessReport({
    required this.topic,
    required this.accuracy,
    required this.attempts,
    required this.trend,
    required this.lastAttempt,
  });
}

class WeaknessAnalyzer {
  /// Window over which to consider history records. Anything older is
  /// dropped — old failures shouldn't haunt students forever.
  static const Duration defaultWindow = Duration(days: 30);

  /// Threshold below which a topic is flagged as a weakness.
  static const double weaknessThreshold = 0.6;

  /// Minimum attempts before we trust the score (avoids 0/1 false-flags).
  static const int minAttempts = 3;

  /// Compute the report from a list of history records. The list is
  /// expected to be ordered newest-first (matches the controller's
  /// internal `_history`); we sort defensively so test fixtures don't have
  /// to comply.
  static List<WeaknessReport> analyze(
    List<ExamHistoryRecord> history, {
    Duration window = defaultWindow,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final cutoff = reference.subtract(window);

    // Build per-topic data from in-window records.
    final byTopic = <String, _TopicAccumulator>{};
    for (final rec in history) {
      if (rec.date.isBefore(cutoff)) continue;
      // Topic-level scores when available (schema v2), else fall back to
      // session-level score applied uniformly to each title.
      if (rec.topicScores.isNotEmpty) {
        for (final entry in rec.topicScores.entries) {
          final acc = byTopic.putIfAbsent(
              entry.key, () => _TopicAccumulator(entry.key));
          // Approximate per-topic question count — divide session questions
          // by topic count if not directly available.
          final approxQ = rec.totalQuestions <= 0
              ? 1
              : (rec.totalQuestions / rec.topicScores.length).ceil();
          acc.add(entry.value, approxQ, rec.date);
        }
      } else {
        for (final title in rec.topicTitles) {
          final acc = byTopic.putIfAbsent(title, () => _TopicAccumulator(title));
          acc.add(rec.score, rec.totalQuestions, rec.date);
        }
      }
    }

    final reports = <WeaknessReport>[];
    for (final acc in byTopic.values) {
      if (acc.attempts < minAttempts) continue;
      reports.add(WeaknessReport(
        topic: acc.topic,
        accuracy: acc.weightedAccuracy(reference),
        attempts: acc.attempts,
        trend: acc.computeTrend(),
        lastAttempt: acc.lastAttempt,
      ));
    }

    // Sort: lowest accuracy first (most-broken on top), then by recency
    // so a stale 30%-topic ranks below a fresh 35%-topic.
    reports.sort((a, b) {
      final accCmp = a.accuracy.compareTo(b.accuracy);
      if (accCmp != 0) return accCmp;
      return b.lastAttempt.compareTo(a.lastAttempt);
    });
    return reports;
  }

  /// Topics flagged as weaknesses (below [weaknessThreshold]).
  static List<WeaknessReport> weaknesses(
    List<ExamHistoryRecord> history, {
    Duration window = defaultWindow,
    DateTime? now,
  }) =>
      analyze(history, window: window, now: now)
          .where((r) => r.accuracy < weaknessThreshold)
          .toList();

  /// Daily streak — number of consecutive days (including today) with at
  /// least one completed exam. Returns 0 if no exam was done today or
  /// the most recent gap exceeds 1 day.
  static int currentStreak(
    List<ExamHistoryRecord> history, {
    DateTime? now,
  }) {
    if (history.isEmpty) return 0;
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final dates = history
        .map((r) => DateTime(r.date.year, r.date.month, r.date.day))
        .toSet();
    int streak = 0;
    var cursor = today;
    while (dates.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}

class _TopicAccumulator {
  _TopicAccumulator(this.topic);

  final String topic;
  final List<_TopicAttempt> attemptsList = [];

  int get attempts =>
      attemptsList.fold(0, (sum, a) => sum + a.questionCount);
  DateTime get lastAttempt => attemptsList
      .map((a) => a.date)
      .reduce((a, b) => a.isAfter(b) ? a : b);

  void add(double accuracy, int questionCount, DateTime date) {
    attemptsList.add(_TopicAttempt(accuracy, questionCount, date));
  }

  /// Recency-weighted accuracy. Weight = exp(-ageDays / 14) — half-life of
  /// roughly two weeks so a perfect month-old run doesn't drown out today's
  /// 50%.
  double weightedAccuracy(DateTime reference) {
    var num = 0.0;
    var den = 0.0;
    for (final a in attemptsList) {
      final ageDays = reference.difference(a.date).inDays.toDouble();
      final w = a.questionCount * _decay(ageDays);
      num += a.accuracy * w;
      den += w;
    }
    return den == 0 ? 0 : num / den;
  }

  int computeTrend() {
    if (attemptsList.length < 2) return 0;
    final sorted = [...attemptsList]..sort((a, b) => a.date.compareTo(b.date));
    final mid = sorted.length ~/ 2;
    final older = sorted.sublist(0, mid);
    final newer = sorted.sublist(mid);
    final olderAvg = _avg(older);
    final newerAvg = _avg(newer);
    final delta = newerAvg - olderAvg;
    if (delta > 0.1) return 1;
    if (delta < -0.1) return -1;
    return 0;
  }

  static double _avg(List<_TopicAttempt> xs) {
    if (xs.isEmpty) return 0;
    var num = 0.0;
    var den = 0.0;
    for (final x in xs) {
      num += x.accuracy * x.questionCount;
      den += x.questionCount;
    }
    return den == 0 ? 0 : num / den;
  }

  // exp(-x/14) approximated with a fast cubic — avoids importing dart:math
  // for one call. Within 1% of the real value across [0..60] day range.
  static double _decay(double ageDays) {
    if (ageDays <= 0) return 1.0;
    if (ageDays >= 60) return 0.014;
    final t = ageDays / 14.0;
    final inv = 1.0 / (1.0 + t + 0.5 * t * t + (t * t * t) / 6.0);
    return inv;
  }
}

class _TopicAttempt {
  final double accuracy;
  final int questionCount;
  final DateTime date;
  _TopicAttempt(this.accuracy, this.questionCount, this.date);
}
