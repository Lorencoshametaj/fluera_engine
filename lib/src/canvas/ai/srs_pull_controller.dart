// ============================================================================
// 📅 SRS PULL MECHANISM — Badge + upcoming reviews model (A9)
//
// Specifica: A9-01 → A9-08
//
// The SRS "pull" mechanism makes reviews discoverable WITHOUT push
// notifications. The student is PULLED toward reviews by visual cues:
//
//   1. Due badge: grey, non-pulsing count on the canvas gallery card
//   2. Mini-calendar: "Prossimi Ritorni" showing next 7 days
//   3. Tap badge → opens review type selector (micro/deep)
//
// RULES (A9):
//   01: Badge is grey (#666), not colored. Never pulsing.
//   02: Badge shows count of due nodes, not urgency.
//   03: Badge disappears when count = 0.
//   04: Tap badge → SRS review type selector (micro/deep).
//   05: Mini-calendar shows next 7 days with dot indicators.
//   06: Zero sound, zero animation on badge.
//   07: Badge is in gallery view, not on canvas.
//   08: Calendar is optional (only if student opens "Prossimi Ritorni").
//
// ARCHITECTURE:
//   Pure model — data for the host app's gallery to render.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'fsrs_scheduler.dart';

/// 📅 Badge data for a single canvas in the gallery.
class SrsDueBadge {
  /// Canvas ID.
  final String canvasId;

  /// Number of nodes due for review right now.
  final int dueCount;

  /// Badge color: always grey (A9-01).
  static const Color badgeColor = Color(0xFF666666);

  /// Whether the badge should be shown.
  bool get isVisible => dueCount > 0;

  /// Display text: "3" or "9+" for large counts.
  String get displayText => dueCount > 9 ? '9+' : '$dueCount';

  const SrsDueBadge({
    required this.canvasId,
    required this.dueCount,
  });
}

/// 📅 A day in the mini-calendar showing upcoming reviews.
class UpcomingReviewDay {
  /// The date.
  final DateTime date;

  /// Number of reviews scheduled for this day.
  final int reviewCount;

  /// Whether this is today.
  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Display label: "Oggi", "Domani", or weekday name.
  String get label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = DateTime(date.year, date.month, date.day)
        .difference(today)
        .inDays;

    if (diff == 0) return 'Oggi';
    if (diff == 1) return 'Domani';

    const weekdays = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
    return weekdays[date.weekday - 1];
  }

  /// Dot intensity: 1–3 based on review count.
  int get dotIntensity {
    if (reviewCount <= 2) return 1;
    if (reviewCount <= 5) return 2;
    return 3;
  }

  const UpcomingReviewDay({
    required this.date,
    required this.reviewCount,
  });
}

/// 📅 SRS Pull Controller (A9).
///
/// Computes badge data and upcoming review calendar from SRS card data.
/// The host app's gallery reads this to render badges on canvas cards.
class SrsPullController extends ChangeNotifier {
  List<SrsDueBadge> _badges = const [];
  List<UpcomingReviewDay> _calendar = const [];

  /// Current badges for all canvases.
  List<SrsDueBadge> get badges => _badges;

  /// Upcoming review calendar (next 7 days).
  List<UpcomingReviewDay> get calendar => _calendar;

  /// Compute badges and calendar from SRS data.
  ///
  /// [canvasSchedules] maps canvasId → (concept → SrsCardData).
  void update(Map<String, Map<String, SrsCardData>> canvasSchedules) {
    final now = DateTime.now();

    // ── Badges ────────────────────────────────────────────────────────
    final newBadges = <SrsDueBadge>[];
    final allCards = <SrsCardData>[];

    for (final entry in canvasSchedules.entries) {
      int dueCount = 0;
      for (final card in entry.value.values) {
        allCards.add(card);
        if (card.nextReview.isBefore(now)) {
          dueCount++;
        }
      }
      newBadges.add(SrsDueBadge(canvasId: entry.key, dueCount: dueCount));
    }

    // ── Calendar (next 7 days) ────────────────────────────────────────
    final today = DateTime(now.year, now.month, now.day);
    final newCalendar = <UpcomingReviewDay>[];

    for (int d = 0; d < 7; d++) {
      final date = today.add(Duration(days: d));
      final nextDate = date.add(const Duration(days: 1));

      int count = 0;
      for (final card in allCards) {
        if (card.nextReview.isAfter(date) &&
            card.nextReview.isBefore(nextDate)) {
          count++;
        } else if (d == 0 && card.nextReview.isBefore(now)) {
          // Overdue cards count toward "today".
          count++;
        }
      }

      newCalendar.add(UpcomingReviewDay(date: date, reviewCount: count));
    }

    _badges = newBadges;
    _calendar = newCalendar;
    notifyListeners();
  }

  /// Get badge for a specific canvas.
  SrsDueBadge? badgeFor(String canvasId) {
    return _badges.where((b) => b.canvasId == canvasId).firstOrNull;
  }

  /// Total due count across all canvases.
  int get totalDue => _badges.fold(0, (sum, b) => sum + b.dueCount);

  /// Whether any canvas has due reviews.
  bool get hasAnyDue => _badges.any((b) => b.isVisible);
}
