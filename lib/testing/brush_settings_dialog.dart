import 'package:flutter/material.dart';
import '../src/l10n/fluera_localizations.dart';
import './brush_test_screen.dart';

/// 🎛️ Modello per i parametri personalizzabili di un pennello
/// v2.0: Added realism parameters (jitter, inkAccumulation, smoothPath)
class BrushSettings {
  // === FOUNTAIN PEN (Stilo) ===
  double fountainMinPressure;
  double fountainMaxPressure;
  int fountainTaperEntry;
  int fountainTaperExit;
  double fountainVelocityInfluence;
  double fountainCurvatureInfluence;
  // Tilt support
  bool fountainTiltEnable;
  double fountainTiltInfluence;
  double fountainTiltEllipseRatio;
  // 🆕 Realismo v2.0
  double fountainJitter;
  double fountainVelocitySensitivity;
  double fountainInkAccumulation;
  bool fountainSmoothPath;
  // 🆕 Physics v3.0
  double fountainThinning;
  double fountainPressureRate;
  double fountainNibAngleDeg;
  double fountainNibStrength;

  // === PENCIL (Matita) ===
  double pencilBaseOpacity;
  double pencilMaxOpacity;
  double pencilBlurRadius;
  double pencilMinPressure;
  double pencilMaxPressure;

  // === HIGHLIGHTER (Evidenziatore) ===
  double highlighterOpacity;
  double highlighterWidthMultiplier;

  // === BALLPOINT (Penna) ===
  double ballpointMinPressure;
  double ballpointMaxPressure;

  BrushSettings({
    // Fountain Pen defaults (bilanciati v2.0)
    this.fountainMinPressure = 0.35,
    this.fountainMaxPressure = 1.5,
    this.fountainTaperEntry = 6,
    this.fountainTaperExit = 8,
    this.fountainVelocityInfluence = 0.6,
    this.fountainCurvatureInfluence = 0.25,
    this.fountainTiltEnable = true,
    this.fountainTiltInfluence = 1.2,
    this.fountainTiltEllipseRatio = 2.5,
    // 🆕 Realismo v2.0 defaults
    this.fountainJitter = 0.08,
    this.fountainVelocitySensitivity = 10.0,
    this.fountainInkAccumulation = 0.15,
    this.fountainSmoothPath = true,
    // 🆕 Physics v3.0 defaults
    this.fountainThinning = 0.5,
    this.fountainPressureRate = 0.275,
    this.fountainNibAngleDeg = 30.0,
    this.fountainNibStrength = 0.2,
    // Pencil defaults
    this.pencilBaseOpacity = 0.4,
    this.pencilMaxOpacity = 0.8,
    this.pencilBlurRadius = 0.3,
    this.pencilMinPressure = 0.5,
    this.pencilMaxPressure = 1.2,
    // Highlighter defaults
    this.highlighterOpacity = 0.35,
    this.highlighterWidthMultiplier = 3.0,
    // Ballpoint defaults
    this.ballpointMinPressure = 0.7,
    this.ballpointMaxPressure = 1.1,
  });

  /// Crea una copia con valori modificati
  BrushSettings copyWith({
    double? fountainMinPressure,
    double? fountainMaxPressure,
    int? fountainTaperEntry,
    int? fountainTaperExit,
    double? fountainVelocityInfluence,
    double? fountainCurvatureInfluence,
    bool? fountainTiltEnable,
    double? fountainTiltInfluence,
    double? fountainTiltEllipseRatio,
    // 🆕 Realismo v2.0
    double? fountainJitter,
    double? fountainVelocitySensitivity,
    double? fountainInkAccumulation,
    bool? fountainSmoothPath,
    // 🆕 Physics v3.0
    double? fountainThinning,
    double? fountainPressureRate,
    double? fountainNibAngleDeg,
    double? fountainNibStrength,
    double? pencilBaseOpacity,
    double? pencilMaxOpacity,
    double? pencilBlurRadius,
    double? pencilMinPressure,
    double? pencilMaxPressure,
    double? highlighterOpacity,
    double? highlighterWidthMultiplier,
    double? ballpointMinPressure,
    double? ballpointMaxPressure,
  }) {
    return BrushSettings(
      fountainMinPressure: fountainMinPressure ?? this.fountainMinPressure,
      fountainMaxPressure: fountainMaxPressure ?? this.fountainMaxPressure,
      fountainTaperEntry: fountainTaperEntry ?? this.fountainTaperEntry,
      fountainTaperExit: fountainTaperExit ?? this.fountainTaperExit,
      fountainVelocityInfluence:
          fountainVelocityInfluence ?? this.fountainVelocityInfluence,
      fountainCurvatureInfluence:
          fountainCurvatureInfluence ?? this.fountainCurvatureInfluence,
      fountainTiltEnable: fountainTiltEnable ?? this.fountainTiltEnable,
      fountainTiltInfluence:
          fountainTiltInfluence ?? this.fountainTiltInfluence,
      fountainTiltEllipseRatio:
          fountainTiltEllipseRatio ?? this.fountainTiltEllipseRatio,
      // 🆕 Realismo v2.0
      fountainJitter: fountainJitter ?? this.fountainJitter,
      fountainVelocitySensitivity:
          fountainVelocitySensitivity ?? this.fountainVelocitySensitivity,
      fountainInkAccumulation:
          fountainInkAccumulation ?? this.fountainInkAccumulation,
      fountainSmoothPath: fountainSmoothPath ?? this.fountainSmoothPath,
      // 🆕 Physics v3.0
      fountainThinning: fountainThinning ?? this.fountainThinning,
      fountainPressureRate: fountainPressureRate ?? this.fountainPressureRate,
      fountainNibAngleDeg: fountainNibAngleDeg ?? this.fountainNibAngleDeg,
      fountainNibStrength: fountainNibStrength ?? this.fountainNibStrength,
      pencilBaseOpacity: pencilBaseOpacity ?? this.pencilBaseOpacity,
      pencilMaxOpacity: pencilMaxOpacity ?? this.pencilMaxOpacity,
      pencilBlurRadius: pencilBlurRadius ?? this.pencilBlurRadius,
      pencilMinPressure: pencilMinPressure ?? this.pencilMinPressure,
      pencilMaxPressure: pencilMaxPressure ?? this.pencilMaxPressure,
      highlighterOpacity: highlighterOpacity ?? this.highlighterOpacity,
      highlighterWidthMultiplier:
          highlighterWidthMultiplier ?? this.highlighterWidthMultiplier,
      ballpointMinPressure: ballpointMinPressure ?? this.ballpointMinPressure,
      ballpointMaxPressure: ballpointMaxPressure ?? this.ballpointMaxPressure,
    );
  }

  /// Reset ai valori di default (v2.0)
  void resetToDefaults() {
    fountainMinPressure = 0.35;
    fountainMaxPressure = 1.5;
    fountainTaperEntry = 6;
    fountainTaperExit = 8;
    fountainVelocityInfluence = 0.6;
    fountainCurvatureInfluence = 0.25;
    fountainTiltEnable = true;
    fountainTiltInfluence = 1.2;
    fountainTiltEllipseRatio = 2.5;
    // 🆕 Realismo v2.0
    fountainJitter = 0.08;
    fountainVelocitySensitivity = 10.0;
    fountainInkAccumulation = 0.15;
    fountainSmoothPath = true;
    // 🆕 Physics v3.0
    fountainThinning = 0.5;
    fountainPressureRate = 0.275;
    fountainNibAngleDeg = 30.0;
    fountainNibStrength = 0.2;
    pencilBaseOpacity = 0.4;
    pencilMaxOpacity = 0.8;
    pencilBlurRadius = 0.3;
    pencilMinPressure = 0.5;
    pencilMaxPressure = 1.2;
    highlighterOpacity = 0.35;
    highlighterWidthMultiplier = 3.0;
    ballpointMinPressure = 0.7;
    ballpointMaxPressure = 1.1;
  }
}

/// 🎨 Dialog per personalizzare i parametri dei pennelli
class BrushSettingsDialog extends StatefulWidget {
  final BrushSettings settings;
  final BrushType currentBrush;
  final ValueChanged<BrushSettings> onSettingsChanged;

  const BrushSettingsDialog({
    super.key,
    required this.settings,
    required this.currentBrush,
    required this.onSettingsChanged,
  });

  /// Mostra il dialog
  static Future<void> show(
    BuildContext context, {
    required BrushSettings settings,
    required BrushType currentBrush,
    required ValueChanged<BrushSettings> onSettingsChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => BrushSettingsDialog(
            settings: settings,
            currentBrush: currentBrush,
            onSettingsChanged: onSettingsChanged,
          ),
    );
  }

  @override
  State<BrushSettingsDialog> createState() => _BrushSettingsDialogState();
}

class _BrushSettingsDialogState extends State<BrushSettingsDialog> {
  late BrushSettings _settings;
  late BrushType _selectedBrush;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings.copyWith();
    _selectedBrush = widget.currentBrush;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFBDBDBD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.tune, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Parametri Pennello',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _resetToDefaults,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reset'),
                ),
              ],
            ),
          ),

          // Brush selector tabs
          _buildBrushTabs(),

          const Divider(height: 1),

          // Settings content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildSettingsForBrush(),
            ),
          ),

          // Apply button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    widget.onSettingsChanged(_settings);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Applica'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrushTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children:
            BrushType.values.map((brush) {
              final isSelected = brush == _selectedBrush;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_getBrushName(brush)),
                  avatar: Icon(
                    _getBrushIcon(brush),
                    size: 18,
                    color: isSelected ? Colors.white : null,
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedBrush = brush);
                    }
                  },
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildSettingsForBrush() {
    switch (_selectedBrush) {
      case BrushType.fountainPen:
        return _buildFountainPenSettings();
      case BrushType.pencil:
        return _buildPencilSettings();
      case BrushType.highlighter:
        return _buildHighlighterSettings();
      case BrushType.ballpoint:
        return _buildBallpointSettings();
    }
  }

  // =====================
  // FOUNTAIN PEN SETTINGS
  // =====================
  Widget _buildFountainPenSettings() {
    final l10n = FlueraLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('✒️ ${l10n.brush_styloPressure}'),
        _buildSlider(
          label: l10n.brush_minWidth,
          value: _settings.fountainMinPressure,
          min: 0.1,
          max: 0.5,
          divisions: 8,
          suffix: 'x',
          onChanged: (v) => setState(() => _settings.fountainMinPressure = v),
        ),
        _buildSlider(
          label: l10n.brush_maxWidth,
          value: _settings.fountainMaxPressure,
          min: 1.0,
          max: 2.5,
          divisions: 15,
          suffix: 'x',
          onChanged: (v) => setState(() => _settings.fountainMaxPressure = v),
        ),

        const SizedBox(height: 16),
        _buildSectionTitle('✒️ ${l10n.brush_styloTapering}'),
        _buildSlider(
          label: l10n.brush_taperEntry,
          value: _settings.fountainTaperEntry.toDouble(),
          min: 0,
          max: 15,
          divisions: 15,
          suffix: ' ${l10n.brush_points}',
          isInt: true,
          onChanged:
              (v) => setState(() => _settings.fountainTaperEntry = v.round()),
        ),
        _buildSlider(
          label: l10n.brush_taperExit,
          value: _settings.fountainTaperExit.toDouble(),
          min: 0,
          max: 20,
          divisions: 20,
          suffix: ' ${l10n.brush_points}',
          isInt: true,
          onChanged:
              (v) => setState(() => _settings.fountainTaperExit = v.round()),
        ),

        const SizedBox(height: 16),
        _buildSectionTitle('✒️ ${l10n.brush_styloDynamics}'),
        _buildSlider(
          label: l10n.brush_velocityInfluence,
          value: _settings.fountainVelocityInfluence,
          min: 0.0,
          max: 1.5,
          divisions: 15,
          suffix: '',
          description: l10n.brush_velocityInfluenceDesc,
          onChanged:
              (v) => setState(() => _settings.fountainVelocityInfluence = v),
        ),
        _buildSlider(
          label: l10n.brush_curvatureInfluence,
          value: _settings.fountainCurvatureInfluence,
          min: 0.0,
          max: 0.8,
          divisions: 8,
          suffix: '',
          description: l10n.brush_curvatureInfluenceDesc,
          onChanged:
              (v) => setState(() => _settings.fountainCurvatureInfluence = v),
        ),

        const SizedBox(height: 16),
        _buildSectionTitle('✒️ ${l10n.brush_styloRealism}'),
        _buildSlider(
          label: l10n.brush_naturalJitter,
          value: _settings.fountainJitter,
          min: 0.0,
          max: 0.15,
          divisions: 15,
          suffix: '',
          description: l10n.brush_jitterDesc,
          onChanged: (v) => setState(() => _settings.fountainJitter = v),
        ),
        _buildSlider(
          label: l10n.brush_velocitySensitivity,
          value: _settings.fountainVelocitySensitivity,
          min: 5.0,
          max: 20.0,
          divisions: 15,
          suffix: 'px',
          description: l10n.brush_velocitySensitivityDesc,
          onChanged:
              (v) => setState(() => _settings.fountainVelocitySensitivity = v),
        ),
        _buildSlider(
          label: l10n.brush_inkAccumulation,
          value: _settings.fountainInkAccumulation,
          min: 0.0,
          max: 0.4,
          divisions: 8,
          suffix: '',
          description: l10n.brush_inkAccumulationDesc,
          onChanged:
              (v) => setState(() => _settings.fountainInkAccumulation = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.brush_pathSmoothSpline),
          subtitle: Text(l10n.brush_pathSmoothDesc),
          value: _settings.fountainSmoothPath,
          onChanged: (v) => setState(() => _settings.fountainSmoothPath = v),
        ),

        const SizedBox(height: 16),
        _buildSectionTitle('✒️ Tilt'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable Tilt'),
          subtitle: const Text('Use stylus tilt for calligraphic variation'),
          value: _settings.fountainTiltEnable,
          onChanged: (v) => setState(() => _settings.fountainTiltEnable = v),
        ),
        if (_settings.fountainTiltEnable) ...[
          _buildSlider(
            label: 'Tilt Influence',
            value: _settings.fountainTiltInfluence,
            min: 0.0,
            max: 2.0,
            divisions: 20,
            suffix: 'x',
            description: 'How much tilt affects stroke width',
            onChanged:
                (v) => setState(() => _settings.fountainTiltInfluence = v),
          ),
          _buildSlider(
            label: 'Tilt Ellipse Ratio',
            value: _settings.fountainTiltEllipseRatio,
            min: 1.0,
            max: 4.0,
            divisions: 15,
            suffix: 'x',
            description: 'Ellipse elongation when tilted',
            onChanged:
                (v) => setState(() => _settings.fountainTiltEllipseRatio = v),
          ),
        ],

        const SizedBox(height: 16),
        _buildSectionTitle('🔬 Ink Physics'),
        _buildSlider(
          label: 'Thinning',
          value: _settings.fountainThinning,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          suffix: '',
          description:
              'Pressure → width ratio (0 = uniform, 1 = very variable)',
          onChanged: (v) => setState(() => _settings.fountainThinning = v),
        ),
        _buildSlider(
          label: 'Pressure Rate',
          value: _settings.fountainPressureRate,
          min: 0.1,
          max: 1.0,
          divisions: 18,
          suffix: '',
          description: 'How fast pressure updates follow input',
          onChanged: (v) => setState(() => _settings.fountainPressureRate = v),
        ),
        _buildSlider(
          label: 'Nib Angle',
          value: _settings.fountainNibAngleDeg,
          min: 0.0,
          max: 90.0,
          divisions: 18,
          suffix: '°',
          description: 'Nib rotation angle for calligraphic effect',
          onChanged: (v) => setState(() => _settings.fountainNibAngleDeg = v),
        ),
        _buildSlider(
          label: 'Nib Strength',
          value: _settings.fountainNibStrength,
          min: 0.0,
          max: 0.6,
          divisions: 12,
          suffix: '',
          description: 'Calligraphic effect intensity',
          onChanged: (v) => setState(() => _settings.fountainNibStrength = v),
        ),
      ],
    );
  }

  // ================
  // PENCIL SETTINGS
  // ================
  Widget _buildPencilSettings() {
    final l10n = FlueraLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('✏️ ${l10n.brush_pencilOpacity}'),
        _buildSlider(
          label: l10n.brush_baseOpacity,
          value: _settings.pencilBaseOpacity,
          min: 0.1,
          max: 0.8,
          divisions: 14,
          suffix: '',
          onChanged: (v) => setState(() => _settings.pencilBaseOpacity = v),
        ),
        _buildSlider(
          label: l10n.brush_maxOpacity,
          value: _settings.pencilMaxOpacity,
          min: 0.5,
          max: 1.0,
          divisions: 10,
          suffix: '',
          onChanged: (v) => setState(() => _settings.pencilMaxOpacity = v),
        ),

        const SizedBox(height: 16),
        _buildSectionTitle('✏️ ${l10n.brush_pencilTexture}'),
        _buildSlider(
          label: l10n.brush_graphiteBlur,
          value: _settings.pencilBlurRadius,
          min: 0.0,
          max: 2.0,
          divisions: 20,
          suffix: 'px',
          description: l10n.brush_graphiteBlurDesc,
          onChanged: (v) => setState(() => _settings.pencilBlurRadius = v),
        ),

        const SizedBox(height: 16),
        _buildSectionTitle('✏️ ${l10n.brush_pencilPressure}'),
        _buildSlider(
          label: l10n.brush_minWidth,
          value: _settings.pencilMinPressure,
          min: 0.2,
          max: 0.8,
          divisions: 12,
          suffix: 'x',
          onChanged: (v) => setState(() => _settings.pencilMinPressure = v),
        ),
        _buildSlider(
          label: l10n.brush_maxWidth,
          value: _settings.pencilMaxPressure,
          min: 1.0,
          max: 2.0,
          divisions: 10,
          suffix: 'x',
          onChanged: (v) => setState(() => _settings.pencilMaxPressure = v),
        ),
      ],
    );
  }

  // =====================
  // HIGHLIGHTER SETTINGS
  // =====================
  Widget _buildHighlighterSettings() {
    final l10n = FlueraLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('🖍️ ${l10n.brush_highlighter}'),
        _buildSlider(
          label: l10n.proCanvas_opacity,
          value: _settings.highlighterOpacity,
          min: 0.1,
          max: 0.6,
          divisions: 10,
          suffix: '',
          description: l10n.brush_highlighterOpacityDesc,
          onChanged: (v) => setState(() => _settings.highlighterOpacity = v),
        ),
        _buildSlider(
          label: l10n.brush_widthMultiplier,
          value: _settings.highlighterWidthMultiplier,
          min: 1.5,
          max: 5.0,
          divisions: 14,
          suffix: 'x',
          description: l10n.brush_widthMultiplierDesc,
          onChanged:
              (v) => setState(() => _settings.highlighterWidthMultiplier = v),
        ),
      ],
    );
  }

  // ===================
  // BALLPOINT SETTINGS
  // ===================
  Widget _buildBallpointSettings() {
    final l10n = FlueraLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('🖊️ ${l10n.brush_ballpoint}'),
        _buildSlider(
          label: l10n.brush_minWidth,
          value: _settings.ballpointMinPressure,
          min: 0.5,
          max: 1.0,
          divisions: 10,
          suffix: 'x',
          description: l10n.brush_minWidthLightPressure,
          onChanged: (v) => setState(() => _settings.ballpointMinPressure = v),
        ),
        _buildSlider(
          label: l10n.brush_maxWidth,
          value: _settings.ballpointMaxPressure,
          min: 1.0,
          max: 1.5,
          divisions: 10,
          suffix: 'x',
          description: l10n.brush_maxWidthFullPressure,
          onChanged: (v) => setState(() => _settings.ballpointMaxPressure = v),
        ),

        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.blue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.brush_ballpointInfo,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =================
  // HELPER WIDGETS
  // =================
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String suffix,
    String? description,
    bool isInt = false,
    required ValueChanged<double> onChanged,
  }) {
    // 🛡️ Clamp value to valid range to prevent slider assertion errors
    final clampedValue = value.clamp(min, max);
    final displayValue =
        isInt
            ? clampedValue.round().toString()
            : clampedValue.toStringAsFixed(2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$displayValue$suffix',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        if (description != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              description,
              style: TextStyle(fontSize: 11, color: const Color(0xFF757575)),
            ),
          ),
        Slider(
          value: clampedValue,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  void _resetToDefaults() {
    setState(() {
      _settings.resetToDefaults();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Parametri resettati ai valori di default'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _getBrushName(BrushType brush) {
    switch (brush) {
      case BrushType.fountainPen:
        return 'Stilo';
      case BrushType.pencil:
        return 'Matita';
      case BrushType.highlighter:
        return 'Evidenziatore';
      case BrushType.ballpoint:
        return 'Penna';
    }
  }

  IconData _getBrushIcon(BrushType brush) {
    switch (brush) {
      case BrushType.fountainPen:
        return Icons.brush;
      case BrushType.pencil:
        return Icons.create;
      case BrushType.highlighter:
        return Icons.highlight;
      case BrushType.ballpoint:
        return Icons.edit;
    }
  }
}
