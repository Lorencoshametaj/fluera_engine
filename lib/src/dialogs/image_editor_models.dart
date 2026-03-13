import 'dart:ui';
import '../core/models/text_overlay.dart';
import '../core/models/tone_curve.dart';
import '../core/models/color_adjustments.dart';
import '../core/models/gradient_filter.dart';
import '../core/models/perspective_settings.dart';
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
///
/// Uses composed sub-models for cleaner grouping:
/// - [ColorAdjustments] for color grading (brightness, contrast, etc.)
/// - [GradientFilter] for gradient overlay settings
/// - [PerspectiveSettings] for keystone correction
class EditorSnapshot {
  // ── Composed sub-models ──
  final ColorAdjustments colorAdjustments;
  final GradientFilter gradientFilter;
  final PerspectiveSettings perspective;
  final ToneCurve toneCurve;

  // ── Other state ──
  final double rotation, opacity;
  final double vignette;
  final int vignetteColor;
  final double blurRadius, sharpenAmount;
  final double edgeDetectStrength;
  final int lutIndex;
  final double grainAmount;
  final double grainSize;
  final List<TextOverlay> textOverlays;
  final bool flipH, flipV;
  final Rect? cropRect;
  final String filterId;

  // ── HSL per-channel (kept flat — 21 doubles, "Color Mixer") ──
  final List<double> hslAdjustments;

  // ── Noise reduction ──
  final double noiseReduction;

  const EditorSnapshot({
    this.colorAdjustments = const ColorAdjustments(),
    this.gradientFilter = const GradientFilter(),
    this.perspective = const PerspectiveSettings(),
    this.toneCurve = const ToneCurve(),
    required this.rotation,
    required this.opacity,
    this.vignette = 0.0,
    this.vignetteColor = 0xFF000000,
    this.blurRadius = 0.0,
    this.sharpenAmount = 0.0,
    this.edgeDetectStrength = 0.0,
    this.lutIndex = -1,
    this.grainAmount = 0.0,
    this.grainSize = 1.0,
    this.textOverlays = const [],
    this.flipH = false,
    required this.flipV,
    this.cropRect,
    required this.filterId,
    this.hslAdjustments = const [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ],
    this.noiseReduction = 0.0,
  });

  // ── Convenience getters for backward compat ──
  double get brightness => colorAdjustments.brightness;
  double get contrast => colorAdjustments.contrast;
  double get saturation => colorAdjustments.saturation;
  double get hueShift => colorAdjustments.hueShift;
  double get temperature => colorAdjustments.temperature;
  double get highlights => colorAdjustments.highlights;
  double get shadows => colorAdjustments.shadows;
  double get fade => colorAdjustments.fade;
  double get clarity => colorAdjustments.clarity;
  int get splitHighlightColor => colorAdjustments.splitHighlightColor;
  int get splitShadowColor => colorAdjustments.splitShadowColor;
  double get splitBalance => colorAdjustments.splitBalance;
  double get splitIntensity => colorAdjustments.splitIntensity;
  double get texture => colorAdjustments.texture;
  double get dehaze => colorAdjustments.dehaze;
  double get gradientAngle => gradientFilter.angle;
  double get gradientPosition => gradientFilter.position;
  double get gradientStrength => gradientFilter.strength;
  int get gradientColor => gradientFilter.color;
  double get perspectiveX => perspective.x;
  double get perspectiveY => perspective.y;
}

/// Aspect ratio constraint for the crop editor.
class CropAspectRatio {
  final String label;
  final double? ratio; // null = free

  const CropAspectRatio(this.label, this.ratio);
}
