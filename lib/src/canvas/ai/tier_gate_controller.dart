// ============================================================================
// 💳 TIER GATE CONTROLLER — Granular feature gating per subscription (A17)
//
// Specifica: A17-01 → A17-06
// Updated: v1 Launch Strategy (lancio_v1_strategia_e_scope.md §3)
//
// The FlueraCanvasConfig already has FlueraSubscriptionTier enum with
// broad capabilities (canUseCloudSync, canCollaborate, canUseAIFilters).
//
// This controller adds GRANULAR pedagogical gates:
//   - Passo 3 (Socratic):  3 sessioni/settimana (Free), illimitate (Pro)
//   - Ghost Map:            1 confronto/settimana (Free), illimitati (Pro)
//   - Cross-Domain (P9):    View-only (Free), interactive (Pro)
//   - Pennelli:             3 base (Free), tutti v1 (Pro)
//   - Export:               PNG only (Free), tutti i formati (Pro)
//
// RULES (A17):
//   01: Free tier includes ALL 12 steps (passi 1-12 never locked)
//   02: Free tier limits FREQUENCY, not ACCESS
//   03: Upgrade prompt is a dismissable banner, never a modal
//   04: Upgrade prompt appears AFTER the student hits the limit
//   05: Accessibility features are ALWAYS FREE (A17-05)
//   06: No degradation of existing content when subscription lapses
//
// ARCHITECTURE:
//   Pure controller — no Flutter widgets.
//   The canvas screen queries [canUseFeature] before invoking subsystems.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'package:flutter/foundation.dart';

import '../../canvas/fluera_canvas_config.dart';

/// 💳 Gated pedagogical feature.
enum GatedFeature {
  /// Socratic dialogue: 3 sessions/week (Free), unlimited (Pro).
  socraticSession,

  /// Fog of War: 1 session/zone (Free), unlimited (Pro).
  fogOfWarSession,

  /// Ghost Map: 1 comparison/week (Free), unlimited (Pro).
  ghostMapComparison,

  /// Cross-Domain bridges: view-only (Free), interactive (Pro).
  crossDomainInteractive,

  /// Deep Review: 1/day (Free), unlimited (Pro).
  deepReview,

  /// Brush access: 3 base (Free), all v1 brushes (Pro).
  brushAccess,

  /// Export format: PNG only (Free), all formats (Pro).
  exportFormat,
}

/// 💳 Result of a gate check.
class GateResult {
  /// Whether the feature is allowed right now.
  final bool allowed;

  /// Remaining uses today (null if unlimited).
  final int? remainingToday;

  /// A4: The blocked feature (for L10n resolution at the UI layer).
  final GatedFeature? blockedFeature;

  /// If not allowed, the upgrade message to show (fallback, IT).
  /// UI should prefer resolving [blockedFeature] via FlueraLocalizations.
  String? get upgradeMessage => blockedFeature != null
      ? TierGateController._upgradeMessage(blockedFeature!)
      : null;

  const GateResult.allowed({this.remainingToday})
      : allowed = true,
        blockedFeature = null;

  const GateResult.blocked(this.blockedFeature)
      : allowed = false,
        remainingToday = 0;

  const GateResult.unlimited()
      : allowed = true,
        remainingToday = null,
        blockedFeature = null;
}

/// 💳 Tier Gate Controller (A17).
///
/// Tracks daily usage counts per feature and enforces Free tier limits.
/// Plus/Pro tiers have unlimited access to all features.
///
/// Usage:
/// ```dart
/// final gate = TierGateController(tier: FlueraSubscriptionTier.free);
/// final result = gate.checkFeature(GatedFeature.socraticSession);
/// if (result.allowed) {
///   gate.recordUsage(GatedFeature.socraticSession);
///   _launchSocratic();
/// } else {
///   _showUpgradeBanner(result.upgradeMessage!);
/// }
/// ```
class TierGateController extends ChangeNotifier {
  /// Current subscription tier.
  FlueraSubscriptionTier _tier;

  /// Daily usage counts: feature → count today.
  final Map<GatedFeature, int> _usageCounts = {};

  /// Weekly usage counts: feature → count this week.
  final Map<GatedFeature, int> _weeklyUsageCounts = {};

  /// Per-zone usage counts: "feature:zoneId" → count.
  final Map<String, int> _zoneUsageCounts = {};

  /// The date of the current daily usage counts (resets daily).
  DateTime _usageDate;

  /// The Monday of the current weekly usage counts (resets weekly).
  DateTime _weekStart;

  TierGateController({
    required FlueraSubscriptionTier tier,
  })  : _tier = tier,
        _usageDate = _today(),
        _weekStart = _mondayOfWeek();

  /// Update the subscription tier (e.g., after purchase).
  void updateTier(FlueraSubscriptionTier tier) {
    _tier = tier;
    notifyListeners();
  }

  /// Current tier.
  FlueraSubscriptionTier get tier => _tier;

  /// Whether the current tier has unlimited access to all features.
  bool get isUnlimited =>
      _tier == FlueraSubscriptionTier.plus ||
      _tier == FlueraSubscriptionTier.pro;

  // ── Gate Checks ────────────────────────────────────────────────────────

  /// Check if a feature can be used right now.
  GateResult checkFeature(GatedFeature feature, {String? zoneId}) {
    // Plus/Pro: unlimited access (A17-01).
    if (isUnlimited) return const GateResult.unlimited();

    _resetIfNewDay();
    _resetIfNewWeek();

    // Zone-scoped features (FoW) use per-zone counts.
    if (zoneId != null && _isZoneScoped(feature)) {
      final key = '${feature.name}:$zoneId';
      final zoneCount = _zoneUsageCounts[key] ?? 0;
      final zoneLimit = _zonelimit(feature);
      if (zoneCount >= zoneLimit) {
        return GateResult.blocked(feature);
      }
      return GateResult.allowed(remainingToday: zoneLimit - zoneCount);
    }

    // Weekly-scoped features (Socratic, Ghost Map).
    if (_isWeeklyScoped(feature)) {
      final weeklyLimit = _weeklyLimit(feature);
      if (weeklyLimit == null) return const GateResult.unlimited();
      final weeklyCount = _weeklyUsageCounts[feature] ?? 0;
      if (weeklyCount >= weeklyLimit) {
        return GateResult.blocked(feature);
      }
      return GateResult.allowed(remainingToday: weeklyLimit - weeklyCount);
    }

    // Daily-scoped features.
    final limit = _dailyLimit(feature);
    if (limit == null) return const GateResult.unlimited();

    final count = _usageCounts[feature] ?? 0;
    if (count >= limit) {
      return GateResult.blocked(feature);
    }
    return GateResult.allowed(remainingToday: limit - count);
  }

  /// Record one usage of a feature.
  void recordUsage(GatedFeature feature, {String? zoneId}) {
    _resetIfNewDay();
    _resetIfNewWeek();
    _usageCounts[feature] = (_usageCounts[feature] ?? 0) + 1;

    // Weekly tracking.
    if (_isWeeklyScoped(feature)) {
      _weeklyUsageCounts[feature] = (_weeklyUsageCounts[feature] ?? 0) + 1;
    }

    if (zoneId != null && _isZoneScoped(feature)) {
      final key = '${feature.name}:$zoneId';
      _zoneUsageCounts[key] = (_zoneUsageCounts[key] ?? 0) + 1;
    }

    notifyListeners();
  }

  /// Reset daily counters (called automatically, but exposed for testing).
  void resetDaily() {
    _usageCounts.clear();
    _usageDate = _today();
  }

  /// Reset weekly counters (called automatically, but exposed for testing).
  void resetWeekly() {
    _weeklyUsageCounts.clear();
    _weekStart = _mondayOfWeek();
  }

  // ── Limits (A17-02: limits FREQUENCY, not ACCESS) ─────────────────────

  /// Weekly limit for a feature in Free tier.
  /// Returns null if unlimited or if scoped differently.
  static int? _weeklyLimit(GatedFeature feature) {
    return switch (feature) {
      GatedFeature.socraticSession => 3,      // 3 sessions/week
      GatedFeature.ghostMapComparison => 1,   // 1 comparison/week
      GatedFeature.deepReview => null,         // Daily, not weekly
      GatedFeature.fogOfWarSession => null,    // Zone-scoped, not weekly
      GatedFeature.crossDomainInteractive => 0, // View-only in Free
      GatedFeature.brushAccess => null,        // Not count-based
      GatedFeature.exportFormat => null,       // Not count-based
    };
  }

  /// Daily limit for a feature in Free tier.
  /// Returns null if unlimited or weekly-scoped.
  static int? _dailyLimit(GatedFeature feature) {
    return switch (feature) {
      GatedFeature.deepReview => 1, // 1 deep review/day
      _ => null, // All others are weekly or zone-scoped
    };
  }

  /// Per-zone limit for zone-scoped features in Free tier.
  static int _zonelimit(GatedFeature feature) {
    return switch (feature) {
      GatedFeature.fogOfWarSession => 1, // 1 session/zone
      _ => 999, // Not zone-scoped
    };
  }

  /// Whether a feature is zone-scoped (vs daily/weekly-scoped).
  static bool _isZoneScoped(GatedFeature feature) {
    return feature == GatedFeature.fogOfWarSession;
  }

  /// Whether a feature is weekly-scoped.
  static bool _isWeeklyScoped(GatedFeature feature) {
    return feature == GatedFeature.socraticSession ||
        feature == GatedFeature.ghostMapComparison ||
        feature == GatedFeature.crossDomainInteractive;
  }

  /// Upgrade message for each feature (A17-03: dismissable banner).
  /// v1 Launch Strategy: warm, motivational tone with pricing.
  static String _upgradeMessage(GatedFeature feature) {
    return switch (feature) {
      GatedFeature.socraticSession =>
        'Hai usato le 3 sessioni di questa settimana. '
            'Con Pro, l\'IA è sempre pronta quando tu lo sei. '
            '€3.33/mese.',
      GatedFeature.fogOfWarSession =>
        'Hai già completato il ripasso guidato per questa zona. '
            'Con Pro, puoi ripetere senza limiti.',
      GatedFeature.ghostMapComparison =>
        'Hai già usato l\'analisi delle lacune questa settimana. '
            'Con Pro, confronti illimitati ogni volta che vuoi.',
      GatedFeature.crossDomainInteractive =>
        'I collegamenti avanzati tra materie sono solo in visualizzazione nel piano Free. '
            'Con Pro, puoi creare collegamenti interattivi.',
      GatedFeature.deepReview =>
        'Hai già completato il ripasso profondo di oggi. '
            'Con Pro, ripassi profondi illimitati.',
      GatedFeature.brushAccess =>
        'Stai usando i 3 pennelli base del piano Free. '
            'Con Pro, sblocchi tutti i pennelli professionali.',
      GatedFeature.exportFormat =>
        'Il piano Free esporta solo in PNG. '
            'Con Pro, esporta in PDF, SVG e tutti i formati.',
    };
  }

  // ── Internal ────────────────────────────────────────────────────────────────────

  void _resetIfNewDay() {
    final today = _today();
    if (_usageDate != today) {
      _usageCounts.clear();
      _usageDate = today;
    }
  }

  void _resetIfNewWeek() {
    final monday = _mondayOfWeek();
    if (_weekStart != monday) {
      _weeklyUsageCounts.clear();
      _weekStart = monday;
    }
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Returns the Monday 00:00 of the current ISO week.
  static DateTime _mondayOfWeek() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  // ── Serialization ─────────────────────────────────────────────────────

  /// Serialize for persistence (daily + weekly + zone counts).
  Map<String, dynamic> toJson() => {
        'usageDate': _usageDate.toIso8601String(),
        'weekStart': _weekStart.toIso8601String(),
        'usageCounts': _usageCounts.map(
          (k, v) => MapEntry(k.name, v),
        ),
        'weeklyUsageCounts': _weeklyUsageCounts.map(
          (k, v) => MapEntry(k.name, v),
        ),
        'zoneUsageCounts': _zoneUsageCounts,
      };

  /// Restore from persisted state.
  factory TierGateController.fromJson(
    Map<String, dynamic> json, {
    required FlueraSubscriptionTier tier,
  }) {
    final controller = TierGateController(tier: tier);

    final dateStr = json['usageDate'] as String?;
    if (dateStr != null) {
      final storedDate = DateTime.tryParse(dateStr);
      if (storedDate != null) {
        final today = _today();
        if (storedDate == today) {
          // Same day — restore daily counts.
          final counts = json['usageCounts'] as Map<String, dynamic>? ?? {};
          for (final entry in counts.entries) {
            final feature = GatedFeature.values.where(
              (f) => f.name == entry.key,
            );
            if (feature.isNotEmpty) {
              controller._usageCounts[feature.first] =
                  (entry.value as num).toInt();
            }
          }
          final zoneCounts =
              json['zoneUsageCounts'] as Map<String, dynamic>? ?? {};
          for (final entry in zoneCounts.entries) {
            controller._zoneUsageCounts[entry.key] =
                (entry.value as num).toInt();
          }
        }
        // Different day → daily counts already cleared (fresh start).
      }
    }

    // Restore weekly counts if same week.
    final weekStr = json['weekStart'] as String?;
    if (weekStr != null) {
      final storedWeek = DateTime.tryParse(weekStr);
      if (storedWeek != null && storedWeek == _mondayOfWeek()) {
        final weeklyCounts =
            json['weeklyUsageCounts'] as Map<String, dynamic>? ?? {};
        for (final entry in weeklyCounts.entries) {
          final feature = GatedFeature.values.where(
            (f) => f.name == entry.key,
          );
          if (feature.isNotEmpty) {
            controller._weeklyUsageCounts[feature.first] =
                (entry.value as num).toInt();
          }
        }
      }
      // Different week → weekly counts already cleared.
    }

    return controller;
  }
}
