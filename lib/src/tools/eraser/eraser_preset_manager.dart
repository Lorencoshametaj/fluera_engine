import 'dart:convert';
import '../../utils/key_value_store.dart';
import 'eraser_hit_tester.dart';

// ============================================================================
// 💾 ERASER PRESET MANAGER — Save/load/delete named eraser configurations
// ============================================================================

/// Manages eraser configuration presets persisted via SharedPreferences.
/// Each preset stores radius, shape, angle, mode flags, and pressure settings.
class EraserPresetManager {
  static const String _presetsPrefKey = 'eraser_presets';

  /// Save a named preset with the given configuration values.
  static Future<void> save(
    String name, {
    required double radius,
    required EraserShape shape,
    required double shapeWidth,
    required double shapeAngle,
    required bool wholeStroke,
    required bool featheredEdge,
    required bool magneticSnap,
    required bool opacityMode,
    required double opacityStrength,
    required int pressureCurveIndex,
    required double autoCompleteThreshold,
    required bool velocityAdaptive,
  }) async {
    final prefs = await KeyValueStore.getInstance();
    final presets = _loadMap(prefs);
    presets[name] = {
      'radius': radius,
      'shape': shape.index,
      'shapeWidth': shapeWidth,
      'shapeAngle': shapeAngle,
      'wholeStroke': wholeStroke,
      'featheredEdge': featheredEdge,
      'magneticSnap': magneticSnap,
      'opacityMode': opacityMode,
      'opacityStrength': opacityStrength,
      'pressureCurve': pressureCurveIndex,
      'autoComplete': autoCompleteThreshold,
      'velocityAdaptive': velocityAdaptive,
    };
    await prefs.setString(_presetsPrefKey, jsonEncode(presets));
  }

  /// Load a named preset. Returns the preset map, or null if not found.
  static Future<Map<String, dynamic>?> load(String name) async {
    final prefs = await KeyValueStore.getInstance();
    final presets = _loadMap(prefs);
    final preset = presets[name];
    if (preset == null) return null;
    return Map<String, dynamic>.from(preset as Map);
  }

  /// List all saved preset names.
  static Future<List<String>> list() async {
    final prefs = await KeyValueStore.getInstance();
    return _loadMap(prefs).keys.toList();
  }

  /// Delete a named preset.
  static Future<void> delete(String name) async {
    final prefs = await KeyValueStore.getInstance();
    final presets = _loadMap(prefs);
    presets.remove(name);
    await prefs.setString(_presetsPrefKey, jsonEncode(presets));
  }

  // ─── Internal ──────────────────────────────────────────────────────

  static Map<String, dynamic> _loadMap(KeyValueStore prefs) {
    final existing = prefs.getString(_presetsPrefKey) ?? '{}';
    if (existing == '{}') return {};
    return Map<String, dynamic>.from(jsonDecode(existing) as Map);
  }
}
