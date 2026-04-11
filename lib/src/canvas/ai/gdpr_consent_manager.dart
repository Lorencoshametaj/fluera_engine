// ============================================================================
// 📋 GDPR CONSENT MANAGER — Granular opt-in consents (Art. 6/7)
//
// Specifica: A16-01 → A16-05
//
// GDPR Art. 7 requires EXPLICIT, SEPARATE consent for each data
// processing purpose. This manager tracks 4 independent consent
// categories, each with timestamp and version tracking.
//
// RULES:
//   - All consents default to FALSE (opt-in, never opt-out)
//   - Each consent is independently togglable
//   - Consent changes are timestamped for audit trail
//   - Consent version tracks privacy policy changes
//   - Withdrawal of consent is as easy as giving it (Art. 7(3))
//
// ARCHITECTURE:
//   Pure model — serializable, no UI, no platform dependencies.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'package:flutter/foundation.dart';

/// 📋 GDPR consent categories.
enum ConsentCategory {
  /// Core analytics (session duration, feature usage). Anonymous.
  analytics,

  /// AI features (sending note content to LLM for Socratic questions).
  aiProcessing,

  /// Cloud sync (backup to Firebase/server).
  cloudSync,

  /// Crash reporting (stack traces, device info).
  crashReporting,
}

/// 📋 A single consent record with timestamp.
class ConsentRecord {
  /// Whether consent is granted.
  final bool granted;

  /// When this consent state was set.
  final DateTime timestamp;

  /// Privacy policy version at time of consent.
  final String policyVersion;

  const ConsentRecord({
    required this.granted,
    required this.timestamp,
    required this.policyVersion,
  });

  Map<String, dynamic> toJson() => {
        'granted': granted,
        'timestamp': timestamp.toIso8601String(),
        'policyVersion': policyVersion,
      };

  factory ConsentRecord.fromJson(Map<String, dynamic> json) => ConsentRecord(
        granted: json['granted'] as bool? ?? false,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        policyVersion: json['policyVersion'] as String? ?? '1.0.0',
      );
}

/// 📋 GDPR Consent Manager (A16).
///
/// Manages granular opt-in consents per GDPR Art. 7.
/// All consents default to FALSE — the student must explicitly opt in.
///
/// Usage:
/// ```dart
/// final consent = GdprConsentManager();
///
/// // Check before sending data to LLM
/// if (!consent.isGranted(ConsentCategory.aiProcessing)) {
///   // Don't send — show consent dialog
///   return;
/// }
///
/// // Grant consent
/// consent.grant(ConsentCategory.analytics);
///
/// // Withdraw consent (Art. 7(3))
/// consent.revoke(ConsentCategory.cloudSync);
/// ```
class GdprConsentManager extends ChangeNotifier {
  /// Current privacy policy version.
  final String policyVersion;

  /// Consent records per category.
  final Map<ConsentCategory, ConsentRecord> _consents;

  /// History of all consent changes (for audit trail).
  final List<ConsentChangeEvent> _history;

  GdprConsentManager({
    this.policyVersion = '1.0.0',
    Map<ConsentCategory, ConsentRecord>? initialConsents,
  })  : _consents = initialConsents ?? {},
        _history = [];

  // ── Queries ───────────────────────────────────────────────────────────

  /// Check if a specific consent is granted.
  bool isGranted(ConsentCategory category) =>
      _consents[category]?.granted ?? false;

  /// Check if ALL specified consents are granted.
  bool areAllGranted(List<ConsentCategory> categories) =>
      categories.every(isGranted);

  /// Check if ANY consent has been granted (user has interacted).
  bool get hasAnyConsent => _consents.values.any((r) => r.granted);

  /// Check if the user has made a decision on all categories.
  bool get hasDecidedAll =>
      ConsentCategory.values.every((c) => _consents.containsKey(c));

  /// Get the consent record for a category (null if never set).
  ConsentRecord? getRecord(ConsentCategory category) => _consents[category];

  /// Get all consent change history (for GDPR audit).
  List<ConsentChangeEvent> get history => List.unmodifiable(_history);

  /// Check if a consent was granted under an older policy version.
  ///
  /// When the privacy policy changes, previously granted consents
  /// should be re-confirmed by the user (the legal basis changed).
  bool isConsentStale(ConsentCategory category) {
    final record = _consents[category];
    if (record == null || !record.granted) return false;
    return record.policyVersion != policyVersion;
  }

  /// Check if ANY consent is stale (needs re-confirmation).
  bool get hasStaleConsents =>
      ConsentCategory.values.any(isConsentStale);

  // ── Actions ───────────────────────────────────────────────────────────

  /// Grant consent for a category.
  void grant(ConsentCategory category) =>
      _setConsent(category, true);

  /// Revoke consent for a category (Art. 7(3)).
  void revoke(ConsentCategory category) =>
      _setConsent(category, false);

  /// Revoke ALL consents.
  void revokeAll() {
    for (final category in ConsentCategory.values) {
      if (isGranted(category)) {
        _setConsent(category, false);
      }
    }
  }

  void _setConsent(ConsentCategory category, bool granted) {
    final now = DateTime.now();
    final record = ConsentRecord(
      granted: granted,
      timestamp: now,
      policyVersion: policyVersion,
    );

    _consents[category] = record;

    _history.add(ConsentChangeEvent(
      category: category,
      granted: granted,
      timestamp: now,
      policyVersion: policyVersion,
    ));

    notifyListeners();
  }

  // ── Serialization ─────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'policyVersion': policyVersion,
        'consents': _consents.map(
          (k, v) => MapEntry(k.name, v.toJson()),
        ),
        'history': _history.map((e) => e.toJson()).toList(),
      };

  factory GdprConsentManager.fromJson(Map<String, dynamic> json) {
    final consents = <ConsentCategory, ConsentRecord>{};
    final rawConsents = json['consents'] as Map<String, dynamic>? ?? {};
    for (final entry in rawConsents.entries) {
      final category = ConsentCategory.values
          .where((c) => c.name == entry.key)
          .firstOrNull;
      if (category != null && entry.value is Map<String, dynamic>) {
        consents[category] =
            ConsentRecord.fromJson(entry.value as Map<String, dynamic>);
      }
    }

    final mgr = GdprConsentManager(
      policyVersion: json['policyVersion'] as String? ?? '1.0.0',
      initialConsents: consents,
    );

    // Restore history.
    final rawHistory = json['history'] as List<dynamic>? ?? [];
    for (final item in rawHistory) {
      if (item is Map<String, dynamic>) {
        mgr._history.add(ConsentChangeEvent.fromJson(item));
      }
    }

    return mgr;
  }
}

/// 📋 A consent change event (for audit trail).
class ConsentChangeEvent {
  final ConsentCategory category;
  final bool granted;
  final DateTime timestamp;
  final String policyVersion;

  const ConsentChangeEvent({
    required this.category,
    required this.granted,
    required this.timestamp,
    required this.policyVersion,
  });

  Map<String, dynamic> toJson() => {
        'category': category.name,
        'granted': granted,
        'timestamp': timestamp.toIso8601String(),
        'policyVersion': policyVersion,
      };

  factory ConsentChangeEvent.fromJson(Map<String, dynamic> json) =>
      ConsentChangeEvent(
        category: ConsentCategory.values
                .where((c) => c.name == (json['category'] as String? ?? ''))
                .firstOrNull ??
            ConsentCategory.analytics,
        granted: json['granted'] as bool? ?? false,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        policyVersion: json['policyVersion'] as String? ?? '1.0.0',
      );
}
