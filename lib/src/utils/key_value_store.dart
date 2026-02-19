import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 💾 Lightweight JSON-file-backed key-value store.
///
/// Drop-in replacement for `SharedPreferences` — same async singleton API,
/// zero platform plugins. Data is persisted to `nebula_prefs.json` in the
/// app documents directory.
///
/// Supported value types: `String`, `bool`, `double`, `int`, `List<String>`.
class KeyValueStore {
  static KeyValueStore? _instance;
  static Future<KeyValueStore>? _pendingInit;

  final File _file;
  Map<String, dynamic> _data;

  KeyValueStore._(this._file, this._data);

  /// Returns the singleton instance, initialising on first call.
  static Future<KeyValueStore> getInstance() async {
    if (_instance != null) return _instance!;
    // Prevent concurrent double-init
    _pendingInit ??= _init();
    _instance = await _pendingInit;
    _pendingInit = null;
    return _instance!;
  }

  static Future<KeyValueStore> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/nebula_prefs.json');

    Map<String, dynamic> data = {};
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        }
      } catch (_) {
        // Corrupted file — start fresh
        data = {};
      }
    }
    return KeyValueStore._(file, data);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════

  String? getString(String key) => _data[key] as String?;
  bool? getBool(String key) => _data[key] as bool?;
  int? getInt(String key) => _data[key] as int?;

  double? getDouble(String key) {
    final v = _data[key];
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return null;
  }

  List<String>? getStringList(String key) {
    final v = _data[key];
    if (v is List) return v.cast<String>();
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SETTERS (all persist immediately)
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> setString(String key, String value) async {
    _data[key] = value;
    await _flush();
  }

  Future<void> setBool(String key, bool value) async {
    _data[key] = value;
    await _flush();
  }

  Future<void> setInt(String key, int value) async {
    _data[key] = value;
    await _flush();
  }

  Future<void> setDouble(String key, double value) async {
    _data[key] = value;
    await _flush();
  }

  Future<void> setStringList(String key, List<String> value) async {
    _data[key] = value;
    await _flush();
  }

  Future<void> remove(String key) async {
    _data.remove(key);
    await _flush();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _flush() async {
    try {
      await _file.writeAsString(jsonEncode(_data));
    } catch (_) {
      // Silent fail — non-critical persistence
    }
  }

  /// Reset for testing — clears in-memory singleton so next [getInstance]
  /// re-reads from disk (or creates a fresh store).
  static void resetForTesting() {
    _instance = null;
    _pendingInit = null;
  }
}
