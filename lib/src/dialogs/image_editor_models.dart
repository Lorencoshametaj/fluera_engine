import 'dart:ui';
import '../l10n/fluera_localizations.dart';

// ============================================================================
// Image Editor — Data Models & Constants
// ============================================================================

/// Named filter preset with pre-computed color matrix values.
class FilterPreset {
  final String id;
  final String Function(FlueraLocalizations) labelFn;
  final double brightness;
  final double contrast;
  final double saturation;

  const FilterPreset({
    required this.id,
    required this.labelFn,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
  });
}

/// All available filter presets.
const kFilterPresets = <FilterPreset>[
  FilterPreset(id: 'none', labelFn: _labelNone),
  FilterPreset(id: 'bw', labelFn: _labelBW, saturation: -1.0),
  FilterPreset(
    id: 'sepia',
    labelFn: _labelSepia,
    saturation: -0.6,
    brightness: 0.05,
    contrast: 0.1,
  ),
  FilterPreset(
    id: 'vintage',
    labelFn: _labelVintage,
    saturation: -0.3,
    brightness: 0.08,
    contrast: -0.1,
  ),
  FilterPreset(
    id: 'cool',
    labelFn: _labelCool,
    saturation: 0.1,
    brightness: -0.03,
    contrast: 0.05,
  ),
  FilterPreset(
    id: 'warm',
    labelFn: _labelWarm,
    saturation: 0.15,
    brightness: 0.06,
    contrast: 0.05,
  ),
  FilterPreset(
    id: 'dramatic',
    labelFn: _labelDramatic,
    saturation: -0.2,
    brightness: -0.05,
    contrast: 0.3,
  ),
];

String _labelNone(FlueraLocalizations l) => l.proCanvas_filterNone;
String _labelBW(FlueraLocalizations l) => l.proCanvas_filterBW;
String _labelSepia(FlueraLocalizations l) => l.proCanvas_filterSepia;
String _labelVintage(FlueraLocalizations l) => l.proCanvas_filterVintage;
String _labelCool(FlueraLocalizations l) => l.proCanvas_filterCool;
String _labelWarm(FlueraLocalizations l) => l.proCanvas_filterWarm;
String _labelDramatic(FlueraLocalizations l) => l.proCanvas_filterDramatic;

/// Snapshot of all editor state values for undo/redo.
class EditorSnapshot {
  final double rotation, brightness, contrast, saturation, opacity;
  final double vignette, hueShift, temperature;
  final bool flipH, flipV;
  final Rect? cropRect;
  final String filterId;

  const EditorSnapshot({
    required this.rotation,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.opacity,
    required this.vignette,
    required this.hueShift,
    required this.temperature,
    required this.flipH,
    required this.flipV,
    this.cropRect,
    required this.filterId,
  });
}

/// Aspect ratio constraint for the crop editor.
class CropAspectRatio {
  final String label;
  final double? ratio; // null = free

  const CropAspectRatio(this.label, this.ratio);
}
