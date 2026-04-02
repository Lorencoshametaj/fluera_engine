import 'dart:io';
import '../utils/safe_path_provider.dart';

// =============================================================================
// WHEEL MODE PREFERENCE — Cross-session radial wheel vs toolbar toggle
// =============================================================================

/// Persists the user's preference for radial wheel mode vs toolbar mode.
///
/// When [enabled] is `true`, long-press opens the radial context menu instead
/// of showing a toolbar. The preference is stored as a tiny file on disk.
///
/// Used by both the main canvas screen and the multiview orchestrator.
class WheelModePref {
  static bool _enabled = false;
  static bool _loaded = false;

  static bool get enabled => _enabled;
  static set enabled(bool v) {
    _enabled = v;
    _save();
  }

  /// Load from disk (fire-and-forget, safe to call multiple times).
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return;
      final f = File('${dir.path}/.fluera_wheel_pref');
      if (await f.exists()) {
        _enabled = (await f.readAsString()).trim() == '1';
      }
    } catch (_) {}
  }

  static void _save() {
    getSafeDocumentsDirectory().then((dir) {
      if (dir == null) return;
      File('${dir.path}/.fluera_wheel_pref')
          .writeAsString(_enabled ? '1' : '0');
    }).catchError((_) {});
  }
}
