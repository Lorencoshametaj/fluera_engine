import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pro_brush_settings.dart';
import '../../../testing/brush_settings_dialog.dart';
import '../../core/engine_scope.dart';

/// 🎛️ Servizio centralizzato per la gestione dei parametri pennello
///
/// FEATURES:
/// - Singleton: shared between all screens
/// - Persistence: save to SharedPreferences (survives app close)
/// - Notifications: use ChangeNotifier to update all UIs
/// - Conversione: converte tra ProBrushSettings e BrushSettings
class BrushSettingsService extends ChangeNotifier {
  static const String _prefsKey = 'brush_settings_v1';
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static BrushSettingsService get instance => EngineScope.current.brushSettingsService;

  /// Creates a new instance (used by [EngineScope]).
  BrushSettingsService.create();

  // Settings correnti
  ProBrushSettings _settings = const ProBrushSettings();
  ProBrushSettings get settings => _settings;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Initializes il servizio caricando i settings salvati
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_prefsKey);

      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        _settings = ProBrushSettings.fromJson(json);
      }
    } catch (e) {
      // Fallback to defaults on error
      _settings = const ProBrushSettings();
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Updates i settings e salva su disco
  Future<void> updateSettings(ProBrushSettings newSettings) async {
    if (_settings == newSettings) return;

    _settings = newSettings;
    notifyListeners();

    // Save su SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(newSettings.toJson());
      await prefs.setString(_prefsKey, jsonString);
    } catch (e) {
      // Silent fail for settings save
    }
  }

  /// Reset ai valori di default
  Future<void> resetToDefaults() async {
    await updateSettings(const ProBrushSettings());
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 🔄 CONVERSION between ProBrushSettings and BrushSettings (brush testing lab)
  // ══════════════════════════════════════════════════════════════════════════

  /// Converts ProBrushSettings in BrushSettings (per brush testing lab)
  BrushSettings toBrushSettings() {
    return BrushSettings(
      fountainMinPressure: _settings.fountainMinPressure,
      fountainMaxPressure: _settings.fountainMaxPressure,
      fountainTaperEntry: _settings.fountainTaperEntry,
      fountainTaperExit: _settings.fountainTaperExit,
      fountainVelocityInfluence: _settings.fountainVelocityInfluence,
      fountainCurvatureInfluence: _settings.fountainCurvatureInfluence,
      pencilBaseOpacity: _settings.pencilBaseOpacity,
      pencilMaxOpacity: _settings.pencilMaxOpacity,
      pencilBlurRadius: _settings.pencilBlurRadius,
      pencilMinPressure: _settings.pencilMinPressure,
      pencilMaxPressure: _settings.pencilMaxPressure,
      highlighterOpacity: _settings.highlighterOpacity,
      highlighterWidthMultiplier: _settings.highlighterWidthMultiplier,
      ballpointMinPressure: _settings.ballpointMinPressure,
      ballpointMaxPressure: _settings.ballpointMaxPressure,
    );
  }

  /// Updates da BrushSettings (dal brush testing lab)
  Future<void> updateFromBrushSettings(BrushSettings brushSettings) async {
    final newSettings = ProBrushSettings(
      fountainMinPressure: brushSettings.fountainMinPressure,
      fountainMaxPressure: brushSettings.fountainMaxPressure,
      fountainTaperEntry: brushSettings.fountainTaperEntry,
      fountainTaperExit: brushSettings.fountainTaperExit,
      fountainVelocityInfluence: brushSettings.fountainVelocityInfluence,
      fountainCurvatureInfluence: brushSettings.fountainCurvatureInfluence,
      pencilBaseOpacity: brushSettings.pencilBaseOpacity,
      pencilMaxOpacity: brushSettings.pencilMaxOpacity,
      pencilBlurRadius: brushSettings.pencilBlurRadius,
      pencilMinPressure: brushSettings.pencilMinPressure,
      pencilMaxPressure: brushSettings.pencilMaxPressure,
      highlighterOpacity: brushSettings.highlighterOpacity,
      highlighterWidthMultiplier: brushSettings.highlighterWidthMultiplier,
      ballpointMinPressure: brushSettings.ballpointMinPressure,
      ballpointMaxPressure: brushSettings.ballpointMaxPressure,
    );

    await updateSettings(newSettings);
  }
}
