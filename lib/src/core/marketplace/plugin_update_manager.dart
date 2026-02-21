/// 🔌 PLUGIN UPDATE MANAGER — Version checking, rollout, and rollback.
///
/// Manages plugin update lifecycle: version comparison, staged rollout,
/// automatic rollback on failure, and update history audit trail.
///
/// ```dart
/// final manager = PluginUpdateManager();
/// manager.registerInstalled('com.acme.blur', '1.0.0');
/// final updates = manager.checkForUpdates({'com.acme.blur': '1.1.0'});
/// ```
library;

import 'dart:math' as math;

import 'semver_resolver.dart';

// =============================================================================
// UPDATE STATUS
// =============================================================================

/// Status of a plugin update.
enum UpdateStatus {
  available,
  downloading,
  installing,
  installed,
  failed,
  rolledBack,
}

// =============================================================================
// UPDATE ENTRY
// =============================================================================

/// Record of a plugin update attempt.
class UpdateEntry {
  /// Plugin ID.
  final String pluginId;

  /// Previous version.
  final String fromVersion;

  /// Target version.
  final String toVersion;

  /// Update status.
  UpdateStatus status;

  /// Timestamp (epoch ms).
  final int timestampMs;

  /// Error message (if failed).
  String? error;

  UpdateEntry({
    required this.pluginId,
    required this.fromVersion,
    required this.toVersion,
    this.status = UpdateStatus.available,
    required this.timestampMs,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'pluginId': pluginId,
    'fromVersion': fromVersion,
    'toVersion': toVersion,
    'status': status.name,
    'timestampMs': timestampMs,
    if (error != null) 'error': error,
  };
}

// =============================================================================
// AVAILABLE UPDATE
// =============================================================================

/// Describes an available update for an installed plugin.
class AvailableUpdate {
  final String pluginId;
  final Semver currentVersion;
  final Semver newVersion;

  AvailableUpdate({
    required this.pluginId,
    required this.currentVersion,
    required this.newVersion,
  });

  bool get isMajor => newVersion.major > currentVersion.major;
  bool get isMinor => !isMajor && newVersion.minor > currentVersion.minor;
  bool get isPatch =>
      !isMajor && !isMinor && newVersion.patch > currentVersion.patch;

  @override
  String toString() =>
      '$pluginId: $currentVersion → $newVersion '
      '(${newVersion.major > currentVersion.major
          ? "MAJOR"
          : newVersion.minor > currentVersion.minor
          ? "minor"
          : "patch"})';
}

// =============================================================================
// PLUGIN UPDATE MANAGER
// =============================================================================

/// Manages plugin updates with staged rollout and rollback.
class PluginUpdateManager {
  /// Installed plugin versions (id → version string).
  final Map<String, String> _installed = {};

  /// Update history.
  final List<UpdateEntry> _history = [];

  /// Rollout percentage (0–100). Only users within rollout see updates.
  double rolloutPercent;

  /// Random source for rollout determination.
  final math.Random _random;

  PluginUpdateManager({this.rolloutPercent = 100.0, math.Random? random})
    : _random = random ?? math.Random();

  /// Register an installed plugin version.
  void registerInstalled(String pluginId, String version) {
    _installed[pluginId] = version;
  }

  /// Unregister a plugin.
  void unregister(String pluginId) => _installed.remove(pluginId);

  /// Get installed version for a plugin.
  String? getInstalledVersion(String pluginId) => _installed[pluginId];

  /// All installed plugins.
  Map<String, String> get installed => Map.unmodifiable(_installed);

  /// Check for available updates.
  ///
  /// [latestVersions] maps plugin ID → latest available version string.
  List<AvailableUpdate> checkForUpdates(Map<String, String> latestVersions) {
    final updates = <AvailableUpdate>[];

    for (final entry in _installed.entries) {
      final latestStr = latestVersions[entry.key];
      if (latestStr == null) continue;

      final current = Semver.parse(entry.value);
      final latest = Semver.parse(latestStr);

      if (latest > current) {
        // Apply rollout check
        if (rolloutPercent < 100.0) {
          if (_random.nextDouble() * 100 > rolloutPercent) continue;
        }

        updates.add(
          AvailableUpdate(
            pluginId: entry.key,
            currentVersion: current,
            newVersion: latest,
          ),
        );
      }
    }

    return updates;
  }

  /// Begin an update (sets status to downloading).
  UpdateEntry beginUpdate(String pluginId, String toVersion) {
    final fromVersion = _installed[pluginId] ?? '0.0.0';
    final entry = UpdateEntry(
      pluginId: pluginId,
      fromVersion: fromVersion,
      toVersion: toVersion,
      status: UpdateStatus.downloading,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
    _history.add(entry);
    return entry;
  }

  /// Complete an update (sets installed version).
  void completeUpdate(UpdateEntry entry) {
    entry.status = UpdateStatus.installed;
    _installed[entry.pluginId] = entry.toVersion;
  }

  /// Fail an update and trigger rollback.
  void failUpdate(UpdateEntry entry, String error) {
    entry.status = UpdateStatus.failed;
    entry.error = error;
    rollback(entry);
  }

  /// Rollback to previous version.
  void rollback(UpdateEntry entry) {
    _installed[entry.pluginId] = entry.fromVersion;
    entry.status = UpdateStatus.rolledBack;
  }

  /// Get update history for a plugin.
  List<UpdateEntry> historyFor(String pluginId) =>
      _history.where((e) => e.pluginId == pluginId).toList();

  /// Full update history.
  List<UpdateEntry> get history => List.unmodifiable(_history);

  /// Number of successful updates.
  int get successfulUpdates =>
      _history.where((e) => e.status == UpdateStatus.installed).length;

  /// Number of failed updates.
  int get failedUpdates =>
      _history
          .where(
            (e) =>
                e.status == UpdateStatus.failed ||
                e.status == UpdateStatus.rolledBack,
          )
          .length;

  /// Clear history.
  void clearHistory() => _history.clear();

  /// Reset everything.
  void reset() {
    _installed.clear();
    _history.clear();
  }
}
