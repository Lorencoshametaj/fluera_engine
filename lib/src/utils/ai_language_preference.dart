import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;

import 'key_value_store.dart';

/// 🛡️ Socratic native-validation tier for a target language.
///
/// Distinguishes hand-written + native-speaker-reviewed pedagogy cells
/// from AI-bootstrapped translations. The Socratic feature is live for
/// all 16 target languages from day-1; the UI shows a disclaimer banner
/// when the active language is in [aiBootstrap] tier.
///
/// Languages graduate from [aiBootstrap] → [productionNative] once they
/// pass the protocol in `docs/socratic_native_validation_protocol.md`
/// (5-step, 4-axis scoring, ≥80% pass-rate).
enum SocraticValidationStatus {
  /// Hand-written native cells, reviewed by native speakers. Currently:
  /// `it`, `en`.
  productionNative,

  /// AI-translated from the IT/EN source-of-truth via Gemini Pro 1.5.
  /// Production-usable but flagged in UI. Currently all other supported
  /// languages.
  aiBootstrap,
}

/// 🌍 Centralised target-language source-of-truth for Fluera AI features.
///
/// Resolves the language used for Socratic / Exam / Chat / Ghost Map
/// outputs in this priority:
///   1. User-selected preference (stored in `KeyValueStore` under
///      [_prefKey]) — when set, OVERRIDES the device locale.
///   2. Device locale (`PlatformDispatcher.instance.locale.languageCode`)
///      — default for first-launch users.
///
/// Use cases:
/// - Student notes in Italian, device locale EN → user can pick "Italian"
///   to get Socratic questions in Italian.
/// - Multilingual student studying in a foreign country (e.g. Italian
///   PhD student abroad with EN system) — explicit override avoids
///   surprises.
///
/// API is sync-after-init. Call [initialize] once on app start (the app
/// already initialises other KeyValueStore-backed singletons), then use
/// [code] / [displayName] anywhere.
class AiLanguagePreference {
  static const String _prefKey = 'fluera_ai_preferred_language';

  /// Tier-1 i18n target languages (10) + Tier-2 (6). ISO 639-1 codes.
  /// Display names match the `langName` argument used in
  /// `atlas_ai_service.dart` prompt builders.
  static const Map<String, String> _supportedLanguages = {
    'en': 'English',
    'it': 'Italian',
    'es': 'Spanish',
    'pt': 'Portuguese',
    'fr': 'French',
    'de': 'German',
    'ja': 'Japanese',
    'ko': 'Korean',
    'hi': 'Hindi',
    'ar': 'Arabic',
    'zh': 'Chinese',
    'ru': 'Russian',
    'nl': 'Dutch',
    'sv': 'Swedish',
    'pl': 'Polish',
    'tr': 'Turkish',
  };

  /// In-memory cached preference. `null` means "use device locale".
  /// Loaded from disk by [initialize].
  static String? _cached;

  /// Whether [initialize] has run. Pre-init reads fall back to device
  /// locale (safe default — equivalent to the legacy behavior).
  static bool _initialized = false;

  /// Loads the saved preference (if any) from `KeyValueStore`. Idempotent;
  /// subsequent calls are no-ops. Call once on app startup.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      final store = await KeyValueStore.getInstance();
      final saved = store.getString(_prefKey);
      if (saved != null && _supportedLanguages.containsKey(saved)) {
        _cached = saved;
        debugPrint('🌍 AiLanguagePreference loaded saved override: '
            '"$saved" (${_supportedLanguages[saved]})');
      } else if (saved != null) {
        debugPrint('⚠️ AiLanguagePreference saved value "$saved" is not in '
            'the supported set; ignoring. Falling back to device locale.');
      } else {
        debugPrint('🌍 AiLanguagePreference no saved override; using device '
            'locale (${ui.PlatformDispatcher.instance.locale.languageCode}).');
      }
    } catch (e) {
      debugPrint('⚠️ AiLanguagePreference initialize failed: $e — falling '
          'back to device locale.');
    }
    _initialized = true;
  }

  /// Returns the ISO 639-1 code currently in effect for AI output.
  /// Synchronous — pre-init it returns the device locale; post-init it
  /// returns the saved preference (if any) or the device locale.
  static String code() {
    if (_cached != null) return _cached!;
    final deviceCode = ui.PlatformDispatcher.instance.locale.languageCode;
    if (_supportedLanguages.containsKey(deviceCode)) return deviceCode;
    return 'en'; // fallback for unsupported locales
  }

  /// Display name for the current language (e.g. "Italian"), matching
  /// the `langName` interpolation in prompts.
  static String displayName() {
    final c = code();
    return _supportedLanguages[c] ?? 'English';
  }

  /// Map of all supported ISO codes → display names. Used by the
  /// settings UI dropdown.
  static Map<String, String> supportedLanguages() =>
      Map.unmodifiable(_supportedLanguages);

  /// Returns `true` when the user has explicitly chosen a preferred
  /// language (vs. falling back to device locale).
  static bool hasExplicitOverride() => _cached != null;

  /// 🌍 Native-language instruction string for the given ISO code, written
  /// IN the target language itself (e.g. for `'it'`: "RISPONDI ESCLUSIVAMENTE
  /// IN ITALIANO. Non usare l'inglese."). Far more effective than an English
  /// "REPLY ONLY IN Italian" because the model reads it in the target
  /// language's own context — measurably reduces IT→EN drift on titles
  /// (memory: `feedback_atlas_title_drift_pattern`).
  ///
  /// Returns an empty string for `'en'` (no enforcement needed when the
  /// target is English) and for any unsupported code.
  ///
  /// Mirrors the local map in [`_atlas_ai.dart::_nativeLangInstruction`]
  /// but exposed as a single-source-of-truth here so cleanOcr / title /
  /// super-node-theme prompts can all share it. Add new languages here
  /// once — every caller picks them up.
  static String nativeLangInstruction(String code) {
    const map = {
      'it': "RISPONDI ESCLUSIVAMENTE IN ITALIANO. Non usare l'inglese.",
      'es': 'RESPONDE EXCLUSIVAMENTE EN ESPAÑOL. No uses el inglés.',
      'fr': "RÉPONDS EXCLUSIVEMENT EN FRANÇAIS. N'utilise pas l'anglais.",
      'de': 'ANTWORTE AUSSCHLIESSLICH AUF DEUTSCH. Verwende kein Englisch.',
      'pt': 'RESPONDA EXCLUSIVAMENTE EM PORTUGUÊS. Não use o inglês.',
      'ja': '必ず日本語で回答してください。英語を使用しないでください。',
      'ko': '반드시 한국어로만 답변하세요. 영어를 사용하지 마세요.',
      'zh': '请仅用中文回答。不要使用英语。',
      'hi': 'केवल हिन्दी में उत्तर दें। अंग्रेज़ी का प्रयोग न करें।',
      'nl': 'ANTWOORD UITSLUITEND IN HET NEDERLANDS. Gebruik geen Engels.',
      'ar': 'أجب باللغة العربية فقط. لا تستخدم الإنجليزية.',
      'ru': 'ОТВЕЧАЙ ИСКЛЮЧИТЕЛЬНО НА РУССКОМ. Не используй английский.',
      'pl': 'ODPOWIADAJ WYŁĄCZNIE PO POLSKU. Nie używaj angielskiego.',
      'tr': 'YALNIZCA TÜRKÇE YANIT VER. İngilizce kullanma.',
      'sv': 'SVARA UTESLUTANDE PÅ SVENSKA. Använd inte engelska.',
      'en': '', // English device — no enforcement needed
    };
    return map[code] ?? '';
  }

  /// Sets the user's preferred AI language. Pass `null` to clear the
  /// override (fall back to device locale). Persists to KeyValueStore.
  static Future<void> setPreferred(String? isoCode) async {
    if (isoCode != null && !_supportedLanguages.containsKey(isoCode)) {
      throw ArgumentError(
          'Unsupported AI language code: $isoCode. '
          'Supported: ${_supportedLanguages.keys.join(", ")}');
    }
    _cached = isoCode;
    try {
      final store = await KeyValueStore.getInstance();
      if (isoCode == null) {
        await store.remove(_prefKey);
        debugPrint('🌍 AiLanguagePreference override cleared (device locale).');
      } else {
        await store.setString(_prefKey, isoCode);
        // Verify the write landed — readback the same key. If readback
        // doesn't match, the persistence chain is broken (file write
        // failed silently). This guards the user complaint "language
        // setting must persist" — we now see the failure in logs
        // instead of silently reverting on next app start.
        final readback = store.getString(_prefKey);
        if (readback == isoCode) {
          debugPrint('🌍 AiLanguagePreference saved + verified: "$isoCode" '
              '(${_supportedLanguages[isoCode]}). Will persist across '
              'app restarts.');
        } else {
          debugPrint('⚠️ AiLanguagePreference write succeeded but readback '
              'returned "$readback" (expected "$isoCode") — persistence '
              'chain may be broken!');
        }
      }
    } catch (e) {
      debugPrint('⚠️ AiLanguagePreference setPreferred persistence failed: $e '
          '— in-memory change still applies for this session only.');
    }
  }

  /// Resets the in-memory cache. **Tests only** — never call in
  /// production. Allows tests to reset state between cases.
  static void resetForTests() {
    _cached = null;
    _initialized = false;
  }

  /// Sets the in-memory preference synchronously, bypassing the
  /// `KeyValueStore` persistence. **Tests only** — production callers
  /// must use [setPreferred] (async, persists).
  static void setForTests(String? isoCode) {
    _cached = isoCode;
    _initialized = true;
  }

  /// Socratic native-validation tier for the given language code.
  /// `it` and `en` are `productionNative` (hand-written cells,
  /// native-speaker reviewed). All others are `aiBootstrap`
  /// (AI-translated from the IT source-of-truth) until they pass the
  /// native-validation protocol.
  static SocraticValidationStatus validationStatusFor(String langCode) {
    return switch (langCode) {
      'it' || 'en' => SocraticValidationStatus.productionNative,
      _ => SocraticValidationStatus.aiBootstrap,
    };
  }

  /// Convenience: status of the currently active language.
  static SocraticValidationStatus currentValidationStatus() =>
      validationStatusFor(code());
}
