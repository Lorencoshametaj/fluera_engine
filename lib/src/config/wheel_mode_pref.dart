import 'dart:io';
import 'package:flutter/foundation.dart';

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
///
/// Round 4.3 (2026-05-15) — `enabledListenable` exposes live notifications
/// so subscribers (canvas screen) can rebuild when the toggle flips
/// mid-session instead of requiring a canvas reopen.
class WheelModePref {
  /// Live notifier for the current value. Listen to this in widgets that
  /// need to rebuild on toggle (canvas screen, multiview orchestrator).
  static final ValueNotifier<bool> enabledListenable = ValueNotifier(false);

  /// Whether the user has already seen the wheel-mode intro dialog.
  /// Drives the "show explainer on first activation" flow — once true,
  /// further activations don't re-prompt.
  static bool _introSeen = false;

  static bool _loaded = false;

  static bool get enabled => enabledListenable.value;
  static set enabled(bool v) {
    enabledListenable.value = v;
    _save();
  }

  /// True once the user has dismissed the first-time intro dialog.
  /// Setter persists to disk so the dialog is shown at most once across
  /// app sessions.
  static bool get introSeen => _introSeen;
  static set introSeen(bool v) {
    if (_introSeen == v) return;
    _introSeen = v;
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
        final raw = (await f.readAsString()).trim();
        // Format: "enabled|introSeen" (e.g. "1|1"). Legacy single-char
        // payloads ("0"/"1") still parse — introSeen defaults to false
        // so a returning user sees the explainer at most once.
        final parts = raw.split('|');
        enabledListenable.value = parts.isNotEmpty && parts[0] == '1';
        _introSeen = parts.length >= 2 && parts[1] == '1';
      }
    } catch (_) {}
  }

  static void _save() {
    final enabledValue = enabledListenable.value ? '1' : '0';
    final introValue = _introSeen ? '1' : '0';
    final payload = '$enabledValue|$introValue';
    getSafeDocumentsDirectory().then((dir) {
      if (dir == null) return;
      File('${dir.path}/.fluera_wheel_pref').writeAsString(payload);
    }).catchError((_) {});
  }
}
