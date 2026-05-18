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

import '../../ai/telemetry_recorder.dart';
import '../../canvas/fluera_canvas_config.dart';

/// 💳 Gated pedagogical / product feature.
///
/// Two families coexist:
///
/// **Frequency-scoped (Free-only limits, V1 launch):** Socratic, Ghost Map,
/// Fog of War, Cross-Domain interactive, Deep Review, Exam, brush + export.
/// Free hits a daily / weekly / per-zone cap; Plus + Pro are unlimited.
///
/// **Feature-scoped (Plus vs Pro split, 2026-05-14):** time travel scrubber,
/// real-time collab, audio-ink sync, voice recording, multi-device, cloud
/// storage, background OCR. Boolean access (or quantity gates queried via
/// dedicated methods like [TierGateController.cloudStorageQuotaBytes]).
/// NOT frequency-counted.
enum GatedFeature {
  // ── Frequency-scoped (Free-tier limits) ────────────────────────────────

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

  /// Exam Session: 1 exam/week (Free), unlimited (Plus/Pro).
  examSession,

  /// Brush access: 3 base (Free), all v1 brushes (Pro).
  brushAccess,

  /// Export format: PNG only (Free), all formats (Pro).
  exportFormat,

  // ── Feature-scoped (Plus vs Pro split, 2026-05-14) ─────────────────────

  /// 💎 Time Travel playback UI (scrubber overlay). Pro pillar #1.
  /// Recording always runs locally (Free: 90 d ring buffer, Plus/Pro: ∞).
  timeTravel,

  /// 💎 Real-time multi-user collaboration (CRDT). Pro pillar #2.
  collaboration,

  /// 💎 Audio-ink synchronisation: tap a stroke → play the audio captured
  /// at that timestamp. Pro pillar #3 (unique vs Notability).
  audioInkSync,

  /// 💎 Voice recording during canvas sessions.
  /// Free: ❌. Plus: ✓ (60 min/mese). Pro: ✓ (illimitato).
  voiceRecording,

  /// 💎 Multi-device cloud sync. Free: 1. Plus: 2. Pro: ∞.
  multiDevice,

  /// 💎 Cloud storage quota. Free: ❌ (local-only). Plus: 5 GB. Pro: 50 GB.
  cloudStorage,

  /// 💎 Background OCR (proactive cluster indexing). Pro-only feature
  /// (Free / Plus rely on on-demand OCR).
  backgroundOcr,
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

  final TelemetryRecorder _telemetry;

  TierGateController({
    required FlueraSubscriptionTier tier,
    TelemetryRecorder? telemetry,
  })  : _tier = tier,
        _telemetry = telemetry ?? TelemetryRecorder.noop,
        _usageDate = _today(),
        _weekStart = _mondayOfWeek();

  /// Update the subscription tier (e.g., after purchase).
  void updateTier(FlueraSubscriptionTier tier) {
    _tier = tier;
    notifyListeners();
  }

  /// Current tier.
  FlueraSubscriptionTier get tier => _tier;

  /// Whether the current tier has unlimited access to **frequency-scoped**
  /// features (the V1 launch set: Socratic, Ghost Map, Fog of War, etc.).
  ///
  /// Does NOT cover feature-scoped gates (time travel, collab, etc.) — for
  /// those use [canUseFeature]. Kept for backward compatibility with
  /// existing call sites that only care about the frequency family.
  bool get isUnlimited =>
      _tier == FlueraSubscriptionTier.plus ||
      _tier == FlueraSubscriptionTier.pro;

  // ── Feature-scoped gates (Plus vs Pro split, 2026-05-14) ────────────────

  /// 💎 Whether the current tier may access [feature].
  ///
  /// For **feature-scoped** gates (timeTravel, collaboration, audioInkSync,
  /// voiceRecording, multiDevice, cloudStorage, backgroundOcr) this is a
  /// boolean access check — Plus and Pro differ.
  ///
  /// For **frequency-scoped** gates (Socratic, Ghost Map, Fog of War, etc.)
  /// it returns true if the user is on Plus/Pro (unlimited) or hasn't yet
  /// hit the Free cap; use [checkFeature] for the full frequency-aware
  /// check that also returns the remaining count.
  bool canUseFeature(GatedFeature feature) {
    return switch (feature) {
      // ── Pro-only feature gates ────────────────────────────────────────
      GatedFeature.timeTravel ||
      GatedFeature.collaboration ||
      GatedFeature.audioInkSync ||
      GatedFeature.backgroundOcr =>
        _tier == FlueraSubscriptionTier.pro,

      // ── Plus+Pro feature gates (paid tiers only) ──────────────────────
      GatedFeature.voiceRecording ||
      GatedFeature.cloudStorage ||
      GatedFeature.multiDevice =>
        _tier == FlueraSubscriptionTier.plus ||
            _tier == FlueraSubscriptionTier.pro,

      // ── Frequency-scoped gates: Plus/Pro = unlimited access, Free =
      //    has access too (the cap lives in [checkFeature]).
      GatedFeature.socraticSession ||
      GatedFeature.fogOfWarSession ||
      GatedFeature.ghostMapComparison ||
      GatedFeature.crossDomainInteractive ||
      GatedFeature.deepReview ||
      GatedFeature.examSession ||
      GatedFeature.brushAccess ||
      GatedFeature.exportFormat =>
        true,
    };
  }

  /// 💎 Cloud storage quota in bytes. Free: 0 (local-only). Plus: 5 GB.
  /// Pro: 50 GB. Used by the host's cloud sync adapter to enforce the
  /// per-tier ceiling and trigger the upgrade prompt.
  int get cloudStorageQuotaBytes {
    return switch (_tier) {
      FlueraSubscriptionTier.pro => 50 * 1024 * 1024 * 1024,
      FlueraSubscriptionTier.plus => 5 * 1024 * 1024 * 1024,
      FlueraSubscriptionTier.essential => 1 * 1024 * 1024 * 1024,
      FlueraSubscriptionTier.free => 0,
    };
  }

  /// 💎 Maximum simultaneous device count for cloud sync.
  /// Free: 1 device (local-only effectively). Plus: 2. Pro: ∞ (returns
  /// [maxDeviceUnlimited] sentinel so callers can branch on `== -1`).
  static const int maxDeviceUnlimited = -1;
  int get maxDeviceCount {
    return switch (_tier) {
      FlueraSubscriptionTier.pro => maxDeviceUnlimited,
      FlueraSubscriptionTier.plus => 2,
      FlueraSubscriptionTier.essential => 2,
      FlueraSubscriptionTier.free => 1,
    };
  }

  /// 💎 Monthly voice-recording quota in minutes.
  /// Free: 0 (no voice recording). Plus + Pro: unlimited (sentinel
  /// [voiceMonthlyUnlimited] so callers can branch on `== -1`).
  ///
  /// V1.5 (2026-05-14 user pass): voice was promoted to unlimited on Plus
  /// so it stops being a Plus→Pro upgrade lever. The Pro pillars (time
  /// travel, audio↔ink sync, collab, background OCR) own that role now.
  static const int voiceMonthlyUnlimited = -1;
  int get voiceMonthlyMinutes {
    return switch (_tier) {
      FlueraSubscriptionTier.pro => voiceMonthlyUnlimited,
      FlueraSubscriptionTier.plus => voiceMonthlyUnlimited,
      FlueraSubscriptionTier.essential => 30,
      FlueraSubscriptionTier.free => 0,
    };
  }

  // ── Gate Checks ────────────────────────────────────────────────────────

  /// Check if a feature can be used right now.
  ///
  /// For feature-scoped gates (Plus vs Pro split) returns allowed/blocked
  /// based on [canUseFeature] without frequency counting. For frequency-scoped
  /// gates it consults the daily/weekly/zone counters as before.
  GateResult checkFeature(GatedFeature feature, {String? zoneId}) {
    // 💎 Feature-scoped gates: boolean access per tier, never frequency.
    if (_isFeatureScoped(feature)) {
      if (canUseFeature(feature)) return const GateResult.unlimited();
      _emitLimitHit(feature, 'tier', 0);
      return GateResult.blocked(feature);
    }

    // Plus/Pro: unlimited access on frequency-scoped features (A17-01).
    if (isUnlimited) return const GateResult.unlimited();

    _resetIfNewDay();
    _resetIfNewWeek();

    // Zone-scoped features (FoW) use per-zone counts.
    if (zoneId != null && _isZoneScoped(feature)) {
      final key = '${feature.name}:$zoneId';
      final zoneCount = _zoneUsageCounts[key] ?? 0;
      final zoneLimit = _zonelimit(feature);
      if (zoneCount >= zoneLimit) {
        _emitLimitHit(feature, 'zone', 0);
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
        _emitLimitHit(feature, 'weekly', 0);
        return GateResult.blocked(feature);
      }
      return GateResult.allowed(remainingToday: weeklyLimit - weeklyCount);
    }

    // Daily-scoped features.
    final limit = _dailyLimit(feature);
    if (limit == null) return const GateResult.unlimited();

    final count = _usageCounts[feature] ?? 0;
    if (count >= limit) {
      _emitLimitHit(feature, 'daily', 0);
      return GateResult.blocked(feature);
    }
    return GateResult.allowed(remainingToday: limit - count);
  }

  void _emitLimitHit(GatedFeature feature, String scope, int remaining) {
    _telemetry.logEvent('tier_limit_hit', properties: {
      'feature': feature.name,
      'tier': _tier.name,
      'scope': scope,
      'remaining': remaining,
    });
  }

  /// 📊 Record that the upgrade paywall was actually shown to the user
  /// after they hit [feature]. Together with [recordPurchase] (in the
  /// host's purchase observer) this closes the loop:
  /// `tier_limit_hit → paywall_shown → purchase_pack | purchase_sub`.
  ///
  /// [trigger] identifies what surfaced the paywall (e.g. `'limit_dialog'`,
  /// `'badge_tap'`, `'settings'`).
  void recordPaywallShown({
    required GatedFeature feature,
    required String trigger,
  }) {
    _telemetry.logEvent('paywall_shown', properties: {
      'feature': feature.name,
      'tier': _tier.name,
      'trigger': trigger,
    });
  }

  /// 📊 Record that the user dismissed the paywall without buying.
  /// Use the same [trigger] string as the matching [recordPaywallShown]
  /// so the funnel SQL can pair them.
  void recordPaywallDismissed({
    required GatedFeature feature,
    required String trigger,
  }) {
    _telemetry.logEvent('paywall_dismissed', properties: {
      'feature': feature.name,
      'tier': _tier.name,
      'trigger': trigger,
    });
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
      GatedFeature.examSession => 1,           // 1 exam/week
      GatedFeature.deepReview => null,         // Daily, not weekly
      GatedFeature.fogOfWarSession => null,    // Zone-scoped, not weekly
      GatedFeature.crossDomainInteractive => 0, // View-only in Free
      GatedFeature.brushAccess => null,        // Not count-based
      GatedFeature.exportFormat => null,       // Not count-based
      // Feature-scoped gates (Plus/Pro split) are NOT frequency-counted.
      // They are checked through [canUseFeature] / [cloudStorageQuotaBytes]
      // / [voiceMonthlyMinutes] / [maxDeviceCount] instead.
      GatedFeature.timeTravel ||
      GatedFeature.collaboration ||
      GatedFeature.audioInkSync ||
      GatedFeature.voiceRecording ||
      GatedFeature.multiDevice ||
      GatedFeature.cloudStorage ||
      GatedFeature.backgroundOcr => null,
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
        feature == GatedFeature.examSession ||
        feature == GatedFeature.crossDomainInteractive;
  }

  /// 💎 Whether a feature is feature-scoped (Plus vs Pro boolean access)
  /// rather than frequency-scoped (Free-only count caps).
  static bool _isFeatureScoped(GatedFeature feature) {
    return switch (feature) {
      GatedFeature.timeTravel ||
      GatedFeature.collaboration ||
      GatedFeature.audioInkSync ||
      GatedFeature.voiceRecording ||
      GatedFeature.multiDevice ||
      GatedFeature.cloudStorage ||
      GatedFeature.backgroundOcr =>
        true,
      _ => false,
    };
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
        'Hai già usato il Confronto Centauro questa settimana. '
            'Con Pro, confronti illimitati ogni volta che vuoi.',
      GatedFeature.crossDomainInteractive =>
        'I collegamenti avanzati tra materie sono solo in visualizzazione nel piano Free. '
            'Con Pro, puoi creare collegamenti interattivi.',
      GatedFeature.deepReview =>
        'Hai già completato il ripasso profondo di oggi. '
            'Con Pro, ripassi profondi illimitati.',
      GatedFeature.examSession =>
        'Hai già fatto la sessione Exam di questa settimana. '
            'Con Plus o Pro, sessioni illimitate + preferenze avanzate.',
      GatedFeature.brushAccess =>
        'Stai usando i 3 pennelli base del piano Free. '
            'Con Pro, sblocchi tutti i pennelli professionali.',
      GatedFeature.exportFormat =>
        'Il piano Free esporta solo in PNG. '
            'Con Pro, esporta in PDF, SVG e tutti i formati.',
      // 💎 Feature-scoped gates (Plus vs Pro split). Tono trasparenza-first:
      // dichiara cosa l\'altro piano sblocca, mai punire la scelta corrente.
      GatedFeature.timeTravel =>
        'Lo scrubber Time Travel — riguardi il tuo studio in playback — '
            'è nel piano Pro. €11,99/mese.',
      GatedFeature.collaboration =>
        'La collaborazione in tempo reale sul canvas è nel piano Pro. '
            'Inviti compagni di studio o colleghi con un link. €11,99/mese.',
      GatedFeature.audioInkSync =>
        'Tocca un tratto e riascolta cosa dicevi in quel momento — '
            'questa magia è nel piano Pro. €11,99/mese.',
      GatedFeature.voiceRecording =>
        'La registrazione audio durante lo studio è nei piani Plus '
            '(60 min/mese) e Pro (illimitata).',
      GatedFeature.multiDevice =>
        'Studi su più dispositivi? Plus sincronizza 2 device, '
            'Pro tutti quelli che vuoi.',
      GatedFeature.cloudStorage =>
        'Il cloud sync è incluso in Plus (5 GB) e Pro (50 GB). '
            'Sul piano Free i canvas restano sul dispositivo.',
      GatedFeature.backgroundOcr =>
        'La ricerca proattiva su tutti i tuoi canvas è nel piano Pro. '
            'Cerchi una formula scritta mesi fa? La trova. €11,99/mese.',
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
