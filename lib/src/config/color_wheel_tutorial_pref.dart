import 'dart:io';
import '../utils/safe_path_provider.dart';

// =============================================================================
// COLOR WHEEL TUTORIAL PREF — One-shot first-touch tutorial flag
// =============================================================================

/// Persists whether the user has already seen the FloatingColorDisc gesture
/// tutorial overlay. Mirrors [WheelModePref] — a tiny bool stored in a hidden
/// file under the documents directory. Once set to true the overlay never
/// reappears unless the file is deleted.
class ColorWheelTutorialPref {
  static bool _seen = false;
  static bool _loaded = false;

  static bool get seen => _seen;
  static set seen(bool v) {
    _seen = v;
    _save();
  }

  /// Load from disk (fire-and-forget, safe to call multiple times).
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return;
      final f = File('${dir.path}/.fluera_color_wheel_tutorial_seen');
      if (await f.exists()) {
        _seen = (await f.readAsString()).trim() == '1';
      }
    } catch (_) {}
  }

  static void _save() {
    getSafeDocumentsDirectory().then((dir) {
      if (dir == null) return;
      File('${dir.path}/.fluera_color_wheel_tutorial_seen')
          .writeAsString(_seen ? '1' : '0');
    }).catchError((_) {});
  }
}
