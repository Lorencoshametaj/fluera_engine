import 'package:flutter/material.dart';
import './pro_brush_settings.dart';
import './pro_drawing_point.dart';

/// 🎨 Phase 4C: Brush Preset model
///
/// Represents a saved brush configuration including pen type, width,
/// color, and all ProBrushSettings parameters.
class BrushPreset {
  final String id;
  final String name;
  final String icon; // emoji
  final ProPenType penType;
  final double baseWidth;
  final Color color;
  final ProBrushSettings settings;
  final bool isBuiltIn;

  const BrushPreset({
    required this.id,
    required this.name,
    required this.icon,
    required this.penType,
    required this.baseWidth,
    required this.color,
    required this.settings,
    this.isBuiltIn = false,
  });

  // ─────────────────────────────────────────────────────────────
  // BUILT-IN PRESETS
  // ─────────────────────────────────────────────────────────────

  static const List<BrushPreset> builtInPresets = [
    BrushPreset(
      id: 'builtin_fine_pen',
      name: 'Fine Pen',
      icon: '✒️',
      penType: ProPenType.fountain,
      baseWidth: 1.5,
      color: Color(0xFF1A1A1A),
      settings: ProBrushSettings(
        fountainMinPressure: 0.2,
        fountainMaxPressure: 0.8,
        fountainThinning: 0.7,
        fountainPressureRate: 0.35,
      ),
      isBuiltIn: true,
    ),
    BrushPreset(
      id: 'builtin_thick_marker',
      name: 'Thick Marker',
      icon: '🖊️',
      penType: ProPenType.ballpoint,
      baseWidth: 6.0,
      color: Color(0xFF2D2D2D),
      settings: ProBrushSettings(
        ballpointMinPressure: 0.8,
        ballpointMaxPressure: 1.2,
      ),
      isBuiltIn: true,
    ),
    BrushPreset(
      id: 'builtin_soft_pencil',
      name: 'Soft Pencil',
      icon: '✏️',
      penType: ProPenType.pencil,
      baseWidth: 3.0,
      color: Color(0xFF4A4A4A),
      settings: ProBrushSettings(
        pencilBaseOpacity: 0.3,
        pencilMaxOpacity: 0.7,
        pencilBlurRadius: 0.5,
        pencilMinPressure: 0.3,
        pencilMaxPressure: 1.0,
      ),
      isBuiltIn: true,
    ),
    BrushPreset(
      id: 'builtin_calligraphy',
      name: 'Calligraphy Nib',
      icon: '🖋️',
      penType: ProPenType.fountain,
      baseWidth: 4.0,
      color: Color(0xFF0D0D0D),
      settings: ProBrushSettings(
        fountainMinPressure: 0.1,
        fountainMaxPressure: 2.0,
        fountainThinning: 0.8,
        fountainNibAngleDeg: 45.0,
        fountainNibStrength: 0.6,
        fountainPressureRate: 0.4,
      ),
      isBuiltIn: true,
    ),
    BrushPreset(
      id: 'builtin_technical',
      name: 'Technical Pen',
      icon: '📏',
      penType: ProPenType.ballpoint,
      baseWidth: 1.0,
      color: Color(0xFF000000),
      settings: ProBrushSettings(
        ballpointMinPressure: 0.95,
        ballpointMaxPressure: 1.05,
      ),
      isBuiltIn: true,
    ),
    BrushPreset(
      id: 'builtin_highlighter',
      name: 'Highlighter',
      icon: '🖍️',
      penType: ProPenType.highlighter,
      baseWidth: 8.0,
      color: Color(0xFFFFEB3B),
      settings: ProBrushSettings(
        highlighterOpacity: 0.3,
        highlighterWidthMultiplier: 3.5,
      ),
      isBuiltIn: true,
    ),
    BrushPreset(
      id: 'builtin_watercolor',
      name: 'Watercolor',
      icon: '💧',
      penType: ProPenType.watercolor,
      baseWidth: 12.0,
      color: Color(0xFF2196F3),
      settings: ProBrushSettings(watercolorSpread: 1.2),
      isBuiltIn: true,
    ),
    BrushPreset(
      id: 'builtin_marker',
      name: 'Marker',
      icon: '🖌️',
      penType: ProPenType.marker,
      baseWidth: 8.0,
      color: Color(0xFF7B1FA2),
      settings: ProBrushSettings(markerFlatness: 0.4),
      isBuiltIn: true,
    ),
    BrushPreset(
      id: 'builtin_charcoal',
      name: 'Charcoal',
      icon: '🪨',
      penType: ProPenType.charcoal,
      baseWidth: 6.0,
      color: Color(0xFF3E2723),
      settings: ProBrushSettings(charcoalGrain: 0.6),
      isBuiltIn: true,
    ),
  ];

  // ─────────────────────────────────────────────────────────────
  // SERIALIZATION
  // ─────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'penType': penType.index,
    'baseWidth': baseWidth,
    'color': color.toARGB32(),
    'settings': settings.toJson(),
  };

  factory BrushPreset.fromJson(Map<String, dynamic> json) {
    return BrushPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String,
      penType: ProPenType.values[json['penType'] as int],
      baseWidth: (json['baseWidth'] as num).toDouble(),
      color: Color(json['color'] as int),
      settings: ProBrushSettings.fromJson(
        json['settings'] as Map<String, dynamic>?,
      ),
    );
  }

  BrushPreset copyWith({
    String? id,
    String? name,
    String? icon,
    ProPenType? penType,
    double? baseWidth,
    Color? color,
    ProBrushSettings? settings,
    bool? isBuiltIn,
  }) {
    return BrushPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      penType: penType ?? this.penType,
      baseWidth: baseWidth ?? this.baseWidth,
      color: color ?? this.color,
      settings: settings ?? this.settings,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushPreset &&
          other.id == id &&
          other.name == name &&
          other.icon == icon;

  @override
  int get hashCode => Object.hash(id, name, icon);
}
