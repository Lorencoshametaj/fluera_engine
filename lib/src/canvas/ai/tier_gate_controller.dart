// ============================================================================
// 💳 TIER GATE CONTROLLER — Granular feature gating per subscription (A17)
//
// Specifica: A17-01 → A17-06
//
// The FlueraCanvasConfig already has FlueraSubscriptionTier enum with
// broad capabilities (canUseCloudSync, canCollaborate, canUseAIFilters).
//
// This controller adds GRANULAR pedagogical gates:
//   - Passo 3 (Socratic):  5 domande/giorno (Free), illimitate (Plus/Pro)
//   - Passo 10 (FoW):      1 sessione/zona (Free), illimitate (Plus/Pro)
//   - Ghost Map:            1 confronto/zona (Free), illimitati (Plus/Pro)
//   - Cross-Domain (P9):    View-only (Free), interactive (Plus/Pro)
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
  /// Socratic dialogue: 5 questions/day (Free), unlimited (Plus/Pro).
  socraticQuestion,

  /// Fog of War: 1 session/zone (Free), unlimited (Plus/Pro).
  fogOfWarSession,

  /// Ghost Map: 1 comparison/zone (Free), unlimited (Plus/Pro).
  ghostMapComparison,

  /// Cross-Domain bridges: view-only (Free), interactive (Plus/Pro).
  crossDomainInteractive,

  /// Deep Review: 1/day (Free), unlimited (Plus/Pro).
  deepReview,
}

/// 💳 Result of a gate check.
class GateResult {
  /// Whether the feature is allowed right now.
  final bool allowed;

  /// Remaining uses today (null if unlimited).
  final int? remainingToday;

  /// If not allowed, the upgrade message to show.
  final String? upgradeMessage;

  const GateResult.allowed({this.remainingToday})
      : allowed = true,
        upgradeMessage = null;

  const GateResult.blocked(this.upgradeMessage)
      : allowed = false,
        remainingToday = 0;

  const GateResult.unlimited()
      : allowed = true,
        remainingToday = null,
        upgradeMessage = null;
}

/// 💳 Tier Gate Controller (A17).
///
/// Tracks daily usage counts per feature and enforces Free tier limits.
/// Plus/Pro tiers have unlimited access to all features.
///
/// Usage:
/// ```dart
/// final gate = TierGateController(tier: FlueraSubscriptionTier.free);
/// final result = gate.checkFeature(GatedFeature.socraticQuestion);
/// if (result.allowed) {
///   gate.recordUsage(GatedFeature.socraticQuestion);
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

  /// Per-zone usage counts: "feature:zoneId" → count.
  final Map<String, int> _zoneUsageCounts = {};

  /// The date of the current usage counts (resets daily).
  DateTime _usageDate;

  TierGateController({
    required FlueraSubscriptionTier tier,
  })  : _tier = tier,
        _usageDate = _today();

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

    // Zone-scoped features (FoW, Ghost Map) use per-zone counts.
    if (zoneId != null && _isZoneScoped(feature)) {
      final key = '${feature.name}:$zoneId';
      final zoneCount = _zoneUsageCounts[key] ?? 0;
      final zoneLimit = _zonelimit(feature);
      if (zoneCount >= zoneLimit) {
        return GateResult.blocked(_upgradeMessage(feature));
      }
      return GateResult.allowed(remainingToday: zoneLimit - zoneCount);
    }

    // Daily-scoped features.
    final limit = _dailyLimit(feature);
    if (limit == null) return const GateResult.unlimited();

    final count = _usageCounts[feature] ?? 0;
    if (count >= limit) {
      return GateResult.blocked(_upgradeMessage(feature));
    }
    return GateResult.allowed(remainingToday: limit - count);
  }

  /// Record one usage of a feature.
  void recordUsage(GatedFeature feature, {String? zoneId}) {
    _resetIfNewDay();
    _usageCounts[feature] = (_usageCounts[feature] ?? 0) + 1;

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

  // ── Limits (A17-02: limits FREQUENCY, not ACCESS) ─────────────────────

  /// Daily limit for a feature in Free tier.
  /// Returns null if unlimited.
  static int? _dailyLimit(GatedFeature feature) {
    return switch (feature) {
      GatedFeature.socraticQuestion => 5, // 5 questions/day
      GatedFeature.deepReview => 1, // 1 deep review/day
      GatedFeature.fogOfWarSession => null, // Zone-scoped, not daily
      GatedFeature.ghostMapComparison => null, // Zone-scoped, not daily
      GatedFeature.crossDomainInteractive => 0, // View-only in Free
    };
  }

  /// Per-zone limit for zone-scoped features in Free tier.
  static int _zonelimit(GatedFeature feature) {
    return switch (feature) {
      GatedFeature.fogOfWarSession => 1, // 1 session/zone
      GatedFeature.ghostMapComparison => 1, // 1 comparison/zone
      _ => 999, // Not zone-scoped
    };
  }

  /// Whether a feature is zone-scoped (vs daily-scoped).
  static bool _isZoneScoped(GatedFeature feature) {
    return feature == GatedFeature.fogOfWarSession ||
        feature == GatedFeature.ghostMapComparison;
  }

  /// Upgrade message for each feature (A17-03: dismissable banner).
  static String _upgradeMessage(GatedFeature feature) {
    return switch (feature) {
      GatedFeature.socraticQuestion =>
        'Hai usato le 5 domande socratiche gratuite di oggi. '
            'Con Plus, le domande sono illimitate.',
      GatedFeature.fogOfWarSession =>
        'Hai già completato la Fog of War per questa zona. '
            'Con Plus, puoi ripetere senza limiti.',
      GatedFeature.ghostMapComparison =>
        'Hai già confrontato questa zona con la Ghost Map. '
            'Con Plus, confronti illimitati.',
      GatedFeature.crossDomainInteractive =>
        'I ponti cross-dominio sono solo in visualizzazione nel piano Free. '
            'Con Plus, puoi creare ponti interattivi.',
      GatedFeature.deepReview =>
        'Hai già completato il ripasso profondo di oggi. '
            'Con Plus, ripassi profondi illimitati.',
    };
  }

  // ── Internal ──────────────────────────────────────────────────────────

  void _resetIfNewDay() {
    final today = _today();
    if (_usageDate != today) {
      _usageCounts.clear();
      _usageDate = today;
    }
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // ── Serialization ─────────────────────────────────────────────────────

  /// Serialize for persistence (daily counts + zone counts).
  Map<String, dynamic> toJson() => {
        'usageDate': _usageDate.toIso8601String(),
        'usageCounts': _usageCounts.map(
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
          // Same day — restore counts.
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
        // Different day → counts already cleared (fresh start).
      }
    }

    return controller;
  }
}
