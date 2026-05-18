import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;

import 'ai_language_preference.dart';
import 'key_value_store.dart';

/// 🌐 User-selected UI language preference for the Fluera app.
///
/// Sibling of [AiLanguagePreference]: that one drives the AI content
/// language (Socratic / Exam / Chat output); this one drives the UI
/// chrome (buttons, labels, dialogs, error messages).
///
/// The two are intentionally orthogonal — an Italian student may want
/// Italian Socratic questions even on an English device, or vice versa.
/// Unifying them would force a trade-off users don't want.
///
/// The supported language set is shared with [AiLanguagePreference] via
/// [AiLanguagePreference.supportedLanguages] so there is one source of
/// truth for "Fluera ships in these 16 locales".
///
/// Resolution priority:
///   1. User override saved in `KeyValueStore` under [_prefKey]
///   2. Device locale (`PlatformDispatcher.instance.locale.languageCode`)
///      if it is in the supported set
///   3. `null` (MaterialApp will then fall back to its first
///      `supportedLocales` entry, which is `en`)
///
/// Call [initialize] once on app start (alongside the other singletons),
/// then read [code] / [locale] / [displayName] anywhere synchronously.
class UiLanguagePreference {
  static const String _prefKey = 'fluera_ui_preferred_language';

  /// In-memory cached preference. `null` = no explicit override.
  static String? _cached;

  /// Whether [initialize] has run. Pre-init reads behave as if no
  /// override is set (safe default).
  static bool _initialized = false;

  /// Broadcast stream of UI locale changes. Emits the new [Locale] when
  /// the override is set; emits `null` when the override is cleared
  /// (fall back to device locale).
  ///
  /// Wired to the root `MaterialApp` so the UI rebuilds without an app
  /// restart when the user picks a different language from settings.
  static final StreamController<ui.Locale?> _changes =
      StreamController<ui.Locale?>.broadcast();

  /// Stream of locale changes for reactive subscribers (typically the
  /// root `MaterialApp`).
  static Stream<ui.Locale?> get changes => _changes.stream;

  /// Loads the saved preference (if any) from `KeyValueStore`.
  /// Idempotent; subsequent calls are no-ops. Call once on app startup.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      final store = await KeyValueStore.getInstance();
      final saved = store.getString(_prefKey);
      if (saved != null &&
          AiLanguagePreference.supportedLanguages().containsKey(saved)) {
        _cached = saved;
        debugPrint('🌐 UiLanguagePreference loaded saved override: "$saved"');
      } else if (saved != null) {
        debugPrint(
            '⚠️ UiLanguagePreference saved value "$saved" is not in the '
            'supported set; ignoring. Falling back to device locale.');
      } else {
        debugPrint(
            '🌐 UiLanguagePreference no saved override; using device locale '
            '(${ui.PlatformDispatcher.instance.locale.languageCode}).');
      }
    } catch (e) {
      debugPrint('⚠️ UiLanguagePreference initialize failed: $e — falling '
          'back to device locale.');
    }
    _initialized = true;
  }

  /// Returns the ISO 639-1 code of the user override, or `null` if none.
  /// `null` means "let MaterialApp resolve from device locale".
  static String? code() => _cached;

  /// Returns the user-overridden [Locale] for `MaterialApp.locale`, or
  /// `null` if there is no override (let Flutter use device locale).
  static ui.Locale? locale() => _cached == null ? null : ui.Locale(_cached!);

  /// Display name of the current UI language. When there is no explicit
  /// override, resolves the device locale's display name (or "English"
  /// if the device locale is not in the supported set).
  static String displayName() {
    final c = _cached ?? ui.PlatformDispatcher.instance.locale.languageCode;
    return AiLanguagePreference.supportedLanguages()[c] ?? 'English';
  }

  /// Map of supported ISO codes → display names. Single source of truth
  /// is [AiLanguagePreference.supportedLanguages]; this getter exists so
  /// the settings UI can call `UiLanguagePreference.supportedLanguages()`
  /// without importing the AI class.
  static Map<String, String> supportedLanguages() =>
      AiLanguagePreference.supportedLanguages();

  /// `true` when the user has explicitly chosen a UI language.
  static bool hasExplicitOverride() => _cached != null;

  /// Sets the user's preferred UI language. Pass `null` to clear the
  /// override and fall back to device locale.
  ///
  /// Persists to `KeyValueStore` and broadcasts the change on [changes]
  /// so the root `MaterialApp` rebuilds. No app restart required.
  static Future<void> setPreferred(String? isoCode) async {
    if (isoCode != null &&
        !AiLanguagePreference.supportedLanguages().containsKey(isoCode)) {
      throw ArgumentError(
          'Unsupported UI language code: $isoCode. '
          'Supported: ${AiLanguagePreference.supportedLanguages().keys.join(", ")}');
    }
    final previous = _cached;
    _cached = isoCode;
    try {
      final store = await KeyValueStore.getInstance();
      if (isoCode == null) {
        await store.remove(_prefKey);
        debugPrint('🌐 UiLanguagePreference override cleared (device locale).');
      } else {
        await store.setString(_prefKey, isoCode);
        // Readback verification — same persistence guard as
        // AiLanguagePreference. Catches silent write failures.
        final readback = store.getString(_prefKey);
        if (readback == isoCode) {
          debugPrint('🌐 UiLanguagePreference saved + verified: "$isoCode". '
              'Will persist across app restarts.');
        } else {
          debugPrint('⚠️ UiLanguagePreference write succeeded but readback '
              'returned "$readback" (expected "$isoCode") — persistence '
              'chain may be broken!');
        }
      }
    } catch (e) {
      // Persistence failed but in-memory change still applies for this
      // session — broadcast so the UI still reflects the choice. The
      // next restart will revert.
      debugPrint('⚠️ UiLanguagePreference setPreferred persistence failed: '
          '$e — in-memory change applies for this session only.');
    }
    if (previous != isoCode) {
      _changes.add(locale());
    }
  }

  /// Resets the in-memory cache. **Tests only.**
  static void resetForTests() {
    _cached = null;
    _initialized = false;
  }

  /// Sets the in-memory preference synchronously without persistence.
  /// **Tests only** — production callers must use [setPreferred].
  static void setForTests(String? isoCode) {
    _cached = isoCode;
    _initialized = true;
  }
}
