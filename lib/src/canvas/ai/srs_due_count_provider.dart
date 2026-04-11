// ============================================================================
// 📊 SRS DUE COUNT PROVIDER — Lightweight overdue node counter
//
// Spec: A9-01 → A9-05, P8-19
//
// Provides a static method to count how many SRS nodes are due for review
// in a given canvas WITHOUT opening the full canvas. This enables the
// gallery/home screen to show a badge ("6 nodi da rivedere") that acts
// as the pull-based review notification system.
//
// Performance: targets ≤500ms per canvas (A9-01).
// Architecture: pure logic, no Flutter UI. Uses only the storage adapter.
// ============================================================================

import 'fsrs_scheduler.dart';
import 'srs_stage_indicator.dart';

/// Lightweight SRS due count query for gallery badges.
///
/// Usage from the host app:
/// ```dart
/// final count = await SrsDueCountProvider.getDueCount(
///   srsDataJson: rawJsonFromStorage,
/// );
/// // Show badge: "$count nodi da rivedere"
/// ```
class SrsDueCountProvider {
  const SrsDueCountProvider._();

  /// Returns the number of SRS nodes that are past their review date.
  ///
  /// [srsDataJson] is the raw JSON map from storage (concept → SrsCardData JSON).
  /// This avoids loading the full canvas — only the SRS metadata is needed.
  ///
  /// Handles both FSRS v2 format, old SM-2 v1 format, and legacy epoch format.
  /// Returns 0 if the data is null/empty or contains no overdue cards.
  static int getDueCount({
    required Map<String, dynamic>? srsDataJson,
  }) {
    if (srsDataJson == null || srsDataJson.isEmpty) return 0;

    final now = DateTime.now();
    int count = 0;

    for (final entry in srsDataJson.entries) {
      try {
        final card = _parseCard(entry.value);
        if (card != null && card.nextReview.isBefore(now)) {
          count++;
        }
      } catch (_) {
        // Malformed entry — skip silently, don't crash the gallery.
        continue;
      }
    }

    return count;
  }

  /// Returns a breakdown of due nodes by [SrsStage] for richer gallery UI.
  ///
  /// Enables the badge to show e.g. "2 🌱 + 4 🌳" instead of just "6".
  static Map<String, int> getDueCountByStage({
    required Map<String, dynamic>? srsDataJson,
  }) {
    if (srsDataJson == null || srsDataJson.isEmpty) return {};

    final now = DateTime.now();
    final counts = <String, int>{};

    for (final entry in srsDataJson.entries) {
      try {
        final card = _parseCard(entry.value);
        if (card != null && card.nextReview.isBefore(now)) {
          final stageName = stageFromCard(card).name;
          counts[stageName] = (counts[stageName] ?? 0) + 1;
        }
      } catch (_) {
        continue;
      }
    }

    return counts;
  }

  /// Parses a card from any supported format.
  ///
  /// Supports:
  ///   - Map<String, dynamic> → SrsCardData.fromJson (handles v1 SM-2 + v2 FSRS)
  ///   - int → legacy epoch milliseconds
  static SrsCardData? _parseCard(dynamic value) {
    if (value is Map<String, dynamic>) {
      return SrsCardData.fromJson(value);
    } else if (value is int) {
      return SrsCardData.fromLegacyDateTime(
        DateTime.fromMillisecondsSinceEpoch(value),
      );
    }
    return null;
  }
}
