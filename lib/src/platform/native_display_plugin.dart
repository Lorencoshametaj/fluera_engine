import 'package:flutter/services.dart';

/// 🖥️ NATIVE DISPLAY PLUGIN
///
/// Platform channel per comunicare con codice nativo Android/iOS
/// per rilevare e forzare il refresh rate of the display.
///
/// **Android**: Usa WindowManager + FlutterView API
/// **iOS**: Not supported (fallback a frame-based detection)
class NativeDisplayPlugin {
  static const MethodChannel _channel = MethodChannel('nebulaengine/display');

  /// Detects il refresh rate nativo of the display (bypassa Flutter)
  ///
  /// **Returns**: Refresh rate in Hz (es. 60, 90, 120, 144)
  ///
  /// **Android**: Legge da WindowManager.getDefaultDisplay().getRefreshRate()
  /// **iOS/Other**: Ritorna null (usa fallback)
  static Future<int?> getNativeRefreshRate() async {
    try {
      final rate = await _channel.invokeMethod<int>('getRefreshRate');
      return rate;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // Platform non supportata (es. iOS, Desktop)
      return null;
    }
  }

  /// Forza Flutter a renderizzare al refresh rate specificato
  ///
  /// **Android**: Chiama FlutterView.setFrameRate() e Window.setPreferredRefreshRate()
  /// **iOS/Other**: Not implemented
  ///
  /// **Note**: Richiede Android API 30+ per setFrameRate, altrimenti usa solo Window API
  static Future<bool> setPreferredRefreshRate(int hz) async {
    try {
      await _channel.invokeMethod('setRefreshRate', {'rate': hz});
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Platform non supportata
      return false;
    }
  }

  /// Checks if the native plugin is available on this platform
  static Future<bool> isAvailable() async {
    try {
      await _channel.invokeMethod('ping');
      return true;
    } catch (_) {
      return false;
    }
  }
}
