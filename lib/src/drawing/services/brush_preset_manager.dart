import 'dart:convert';
import '../../utils/key_value_store.dart';
import '../../utils/uid.dart';
import '../models/brush_preset.dart';

/// 🎨 Phase 4C: Brush Preset Manager
///
/// Manages built-in and user-created brush presets.
/// User presets are persisted to SharedPreferences as a JSON list.
class BrushPresetManager {
  static const _storageKey = 'pro_brush_presets_v1';

  List<BrushPreset> _userPresets = [];

  /// All built-in presets (read-only)
  List<BrushPreset> get builtInPresets => BrushPreset.builtInPresets;

  /// User-created presets
  List<BrushPreset> get userPresets => List.unmodifiable(_userPresets);

  /// All presets: built-ins first, then user-created
  List<BrushPreset> get allPresets => [...builtInPresets, ..._userPresets];

  /// Load user presets from SharedPreferences
  Future<void> load() async {
    final prefs = await KeyValueStore.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _userPresets = [];
      return;
    }

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _userPresets =
          list
              .map((e) => BrushPreset.fromJson(e as Map<String, dynamic>))
              .toList();
    } catch (_) {
      _userPresets = [];
    }
  }

  /// Save user presets to SharedPreferences
  Future<void> _persist() async {
    final prefs = await KeyValueStore.getInstance();
    final json = jsonEncode(_userPresets.map((p) => p.toJson()).toList());
    await prefs.setString(_storageKey, json);
  }

  /// Save a new preset or update an existing one by id
  Future<void> savePreset(BrushPreset preset) async {
    final idx = _userPresets.indexWhere((p) => p.id == preset.id);
    if (idx >= 0) {
      _userPresets[idx] = preset;
    } else {
      _userPresets.add(preset);
    }
    await _persist();
  }

  /// Create a new preset from current brush state
  Future<BrushPreset> createPreset({
    required String name,
    required String icon,
    required BrushPreset template,
  }) async {
    final preset = template.copyWith(
      id: 'user_${generateUid()}',
      name: name,
      icon: icon,
      isBuiltIn: false,
    );
    await savePreset(preset);
    return preset;
  }

  /// Delete a user preset
  Future<void> deletePreset(String presetId) async {
    _userPresets.removeWhere((p) => p.id == presetId);
    await _persist();
  }

  /// Duplicate an existing preset
  Future<BrushPreset> duplicatePreset(BrushPreset source) async {
    return createPreset(
      name: '${source.name} Copy',
      icon: source.icon,
      template: source,
    );
  }
}
