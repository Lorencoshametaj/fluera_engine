part of 'pro_brush_settings_dialog.dart';

// ════════════════════════════════════════════════════════════════════
//  PER-BRUSH CONTROLS + STABILIZER
// ════════════════════════════════════════════════════════════════════

extension _BrushDialogControls on _ProBrushSettingsDialogState {
  List<Widget> buildBrushControls(
    ColorScheme cs,
    TextTheme tt,
    Color accent,
  ) => switch (widget.currentBrush) {
    ProPenType.fountain => _fountainControls(cs, tt, accent),
    ProPenType.pencil => _pencilControls(cs, tt, accent),
    ProPenType.ballpoint => _ballpointControls(cs, tt, accent),
    ProPenType.highlighter => _highlighterControls(cs, tt, accent),
    // New brushes — no custom controls yet (stabilizer + texture still available)
    ProPenType.watercolor ||
    ProPenType.marker ||
    ProPenType.charcoal ||
    ProPenType.oilPaint ||
    ProPenType.sprayPaint ||
    ProPenType.neonGlow ||
    ProPenType.inkWash => [],
    ProPenType.technicalPen => _technicalPenControls(cs, tt, accent),
  };

  // ── Technical Pen ──
  List<Widget> _technicalPenControls(
    ColorScheme cs,
    TextTheme tt,
    Color accent,
  ) {
    // Snap angle index for discrete selector
    final snapAngles = [5.0, 10.0, 15.0, 30.0, 45.0, 90.0];
    final snapLabels = ['5°', '10°', '15°', '30°', '45°', '90°'];
    final snapIdx = snapAngles.indexOf(_settings.techSnapAngleDeg);
    final currentSnapIdx = snapIdx >= 0 ? snapIdx : 4; // default 45°

    return [
      presetChips(
        cs: cs,
        tt: tt,
        accent: accent,
        presets: {
          'Freehand':
              () => _update(
                _settings.copyWith(
                  techAngleSnap: false,
                  techEndpointSnap: false,
                  techCornerSharpening: 0.3,
                  techGridSnap: false,
                  techStraightAssist: false,
                  techShowGuides: false,
                  techParallelSnap: false,
                  techPerpSnap: false,
                ),
              ),
          'Technical':
              () => _update(
                _settings.copyWith(
                  techAngleSnap: true,
                  techSnapAngleDeg: 45.0,
                  techEndpointSnap: true,
                  techCornerSharpening: 0.6,
                  techGridSnap: false,
                  techStraightAssist: true,
                  techShowGuides: true,
                  techParallelSnap: false,
                  techPerpSnap: false,
                ),
              ),
          'Precision':
              () => _update(
                _settings.copyWith(
                  techAngleSnap: true,
                  techSnapAngleDeg: 15.0,
                  techEndpointSnap: true,
                  techCornerSharpening: 0.9,
                  techGridSnap: true,
                  techGridSize: 20.0,
                  techStraightAssist: true,
                  techShowGuides: true,
                  techParallelSnap: true,
                  techPerpSnap: true,
                ),
              ),
        },
      ),
      const SizedBox(height: 4),
      switchRow(
        icon: Icons.rotate_90_degrees_cw_rounded,
        label: 'Angle Snap',
        tooltip:
            'When enabled, straight lines snap to angular increments for precise technical drawing.',
        value: _settings.techAngleSnap,
        onChanged: (v) => _update(_settings.copyWith(techAngleSnap: v)),
        cs: cs,
        tt: tt,
        accent: accent,
      ),
      if (_settings.techAngleSnap)
        sliderRow(
          icon: Icons.straighten_rounded,
          label: 'Snap Angle',
          tooltip: 'Angular resolution for line snapping.',
          value: currentSnapIdx.toDouble(),
          min: 0,
          max: 5,
          divisions: 5,
          displayValue: snapLabels[currentSnapIdx],
          onChanged:
              (v) => _update(
                _settings.copyWith(
                  techSnapAngleDeg: snapAngles[v.round().clamp(0, 5)],
                ),
              ),
          cs: cs,
          tt: tt,
        ),
      switchRow(
        icon: Icons.crop_square_rounded,
        label: 'Close Shapes',
        tooltip:
            'Automatically close the shape when the stroke end is near the start.',
        value: _settings.techEndpointSnap,
        onChanged: (v) => _update(_settings.copyWith(techEndpointSnap: v)),
        cs: cs,
        tt: tt,
        accent: accent,
      ),
      sliderRow(
        icon: Icons.change_history_rounded,
        label: 'Corner Sharpness',
        tooltip:
            'How aggressively direction changes become sharp corners instead of smooth curves.',
        value: _settings.techCornerSharpening,
        min: 0.0,
        max: 1.0,
        displayValue: '${(_settings.techCornerSharpening * 100).round()}%',
        onChanged:
            (v) => _update(_settings.copyWith(techCornerSharpening: v)),
        cs: cs,
        tt: tt,
      ),
      switchRow(
        icon: Icons.grid_4x4_rounded,
        label: 'Grid Snap',
        tooltip:
            'Snap drawing positions to a grid for precise alignment.',
        value: _settings.techGridSnap,
        onChanged: (v) => _update(_settings.copyWith(techGridSnap: v)),
        cs: cs,
        tt: tt,
        accent: accent,
      ),
      if (_settings.techGridSnap)
        sliderRow(
          icon: Icons.space_bar_rounded,
          label: 'Grid Size',
          tooltip: 'Size of grid cells in logical pixels.',
          value: _settings.techGridSize,
          min: 5,
          max: 50,
          displayValue: '${_settings.techGridSize.round()}px',
          onChanged: (v) => _update(_settings.copyWith(techGridSize: v)),
          cs: cs,
          tt: tt,
        ),
      switchRow(
        icon: Icons.straighten_rounded,
        label: 'Straight Assist',
        tooltip:
            'Automatically straighten lines when drawing slowly and nearly straight.',
        value: _settings.techStraightAssist,
        onChanged: (v) => _update(_settings.copyWith(techStraightAssist: v)),
        cs: cs,
        tt: tt,
        accent: accent,
      ),
      switchRow(
        icon: Icons.visibility_rounded,
        label: 'Show Guides',
        tooltip:
            'Display visual guide lines, angle badge, and length measurements while drawing.',
        value: _settings.techShowGuides,
        onChanged: (v) => _update(_settings.copyWith(techShowGuides: v)),
        cs: cs,
        tt: tt,
        accent: accent,
      ),
      switchRow(
        icon: Icons.compare_arrows_rounded,
        label: 'Parallel Snap',
        tooltip:
            'Snap to the angle of the previous stroke for parallelism.',
        value: _settings.techParallelSnap,
        onChanged: (v) => _update(_settings.copyWith(techParallelSnap: v)),
        cs: cs,
        tt: tt,
        accent: accent,
      ),
      switchRow(
        icon: Icons.vertical_align_center_rounded,
        label: 'Perpendicular Snap',
        tooltip:
            'Snap to 90° relative to the previous stroke.',
        value: _settings.techPerpSnap,
        onChanged: (v) => _update(_settings.copyWith(techPerpSnap: v)),
        cs: cs,
        tt: tt,
        accent: accent,
      ),
    ];
  }

  // ── Fountain ──
  List<Widget> _fountainControls(ColorScheme cs, TextTheme tt, Color accent) {
    final sensitivity = ((_settings.fountainMaxPressure - 1.0) / 2.0).clamp(
      0.0,
      1.0,
    );
    return [
      presetChips(
        cs: cs,
        tt: tt,
        accent: accent,
        presets: {
          'Calligraphic':
              () => _update(
                _settings.copyWith(
                  fountainNibStrength: 0.8,
                  fountainNibAngleDeg: 45.0,
                  fountainThinning: 0.75,
                  fountainVelocityInfluence: 0.3,
                  fountainTaperEntry: 4,
                  fountainTaperExit: 12,
                  fountainMinPressure: 0.15,
                  fountainMaxPressure: 2.5,
                ),
              ),
          'Note-taking': () => _update(const ProBrushSettings()),
          'Sketch':
              () => _update(
                _settings.copyWith(
                  fountainNibStrength: 0.15,
                  fountainNibAngleDeg: 30.0,
                  fountainThinning: 0.35,
                  fountainVelocityInfluence: 0.8,
                  fountainTaperEntry: 2,
                  fountainTaperExit: 3,
                  fountainMinPressure: 0.3,
                  fountainMaxPressure: 1.8,
                ),
              ),
        },
      ),
      const SizedBox(height: 4),
      sliderRow(
        icon: Icons.touch_app_rounded,
        label: 'Sensitivity',
        tooltip:
            'How much the stroke reacts to pen pressure. Higher values create more variation between light and heavy strokes.',
        value: sensitivity,
        min: 0.0,
        max: 1.0,
        displayValue: '${(sensitivity * 100).round()}%',
        onChanged: (v) {
          final newMax = 1.0 + v * 2.0;
          final newMin = 0.5 - v * 0.45;
          _update(
            _settings.copyWith(
              fountainMinPressure: newMin.clamp(0.05, 0.5),
              fountainMaxPressure: newMax.clamp(1.0, 3.0),
            ),
          );
        },
        cs: cs,
        tt: tt,
      ),
      sliderRow(
        icon: Icons.compress_rounded,
        label: 'Thinning',
        tooltip: 'How much pressure affects stroke width.',
        value: _settings.fountainThinning,
        min: 0.2,
        max: 0.9,
        displayValue: '${(_settings.fountainThinning * 100).round()}%',
        onChanged: (v) => _update(_settings.copyWith(fountainThinning: v)),
        cs: cs,
        tt: tt,
      ),
      sliderRow(
        icon: Icons.speed_rounded,
        label: 'Velocity',
        tooltip: 'How much drawing speed affects thickness.',
        value: _settings.fountainVelocityInfluence,
        min: 0.0,
        max: 1.0,
        displayValue: '${(_settings.fountainVelocityInfluence * 100).round()}%',
        onChanged:
            (v) => _update(_settings.copyWith(fountainVelocityInfluence: v)),
        cs: cs,
        tt: tt,
      ),
      switchRow(
        icon: Icons.screen_rotation_rounded,
        label: 'Tilt',
        tooltip: 'When enabled, tilting the stylus changes the stroke shape.',
        value: _settings.fountainTiltEnable,
        onChanged: (v) => _update(_settings.copyWith(fountainTiltEnable: v)),
        cs: cs,
        tt: tt,
        accent: accent,
      ),
      sliderRow(
        icon: Icons.straighten_rounded,
        label: 'Nib Angle',
        tooltip: 'The rotation angle of the pen nib.',
        value: _settings.fountainNibAngleDeg,
        min: 0.0,
        max: 90.0,
        displayValue: '${_settings.fountainNibAngleDeg.round()}°',
        onChanged: (v) => _update(_settings.copyWith(fountainNibAngleDeg: v)),
        cs: cs,
        tt: tt,
      ),
      sliderRow(
        icon: Icons.line_weight_rounded,
        label: 'Nib Strength',
        tooltip: 'How pronounced the nib shape effect is.',
        value: _settings.fountainNibStrength,
        min: 0.0,
        max: 1.0,
        displayValue: '${(_settings.fountainNibStrength * 100).round()}%',
        onChanged: (v) => _update(_settings.copyWith(fountainNibStrength: v)),
        cs: cs,
        tt: tt,
      ),
      sliderRow(
        icon: Icons.start_rounded,
        label: 'Taper Start',
        tooltip: 'Number of points to taper at the beginning.',
        value: _settings.fountainTaperEntry.toDouble(),
        min: 0,
        max: 20,
        displayValue: '${_settings.fountainTaperEntry}',
        onChanged:
            (v) => _update(_settings.copyWith(fountainTaperEntry: v.round())),
        cs: cs,
        tt: tt,
      ),
      sliderRow(
        icon: Icons.keyboard_tab_rounded,
        label: 'Taper End',
        tooltip: 'Number of points to taper at the end.',
        value: _settings.fountainTaperExit.toDouble(),
        min: 0,
        max: 20,
        displayValue: '${_settings.fountainTaperExit}',
        onChanged:
            (v) => _update(_settings.copyWith(fountainTaperExit: v.round())),
        cs: cs,
        tt: tt,
      ),
    ];
  }

  // ── Pencil ──
  List<Widget> _pencilControls(ColorScheme cs, TextTheme tt, Color accent) {
    final sensitivity = ((_settings.pencilMaxPressure - 0.8) / 0.8).clamp(
      0.0,
      1.0,
    );
    return [
      presetChips(
        cs: cs,
        tt: tt,
        accent: accent,
        presets: {
          'Soft':
              () => _update(
                _settings.copyWith(
                  pencilBaseOpacity: 0.25,
                  pencilMaxOpacity: 0.55,
                  pencilBlurRadius: 2.5,
                  pencilMinPressure: 0.3,
                  pencilMaxPressure: 1.0,
                ),
              ),
          'Medium':
              () => _update(
                _settings.copyWith(
                  pencilBaseOpacity: 0.4,
                  pencilMaxOpacity: 0.8,
                  pencilBlurRadius: 0.3,
                  pencilMinPressure: 0.5,
                  pencilMaxPressure: 1.2,
                ),
              ),
          'Hard':
              () => _update(
                _settings.copyWith(
                  pencilBaseOpacity: 0.6,
                  pencilMaxOpacity: 0.95,
                  pencilBlurRadius: 0.0,
                  pencilMinPressure: 0.7,
                  pencilMaxPressure: 1.5,
                ),
              ),
        },
      ),
      const SizedBox(height: 4),
      sliderRow(
        icon: Icons.opacity_rounded,
        label: 'Opacity',
        tooltip: 'The base transparency of the pencil stroke.',
        value: _settings.pencilBaseOpacity,
        min: 0.05,
        max: 0.9,
        displayValue: '${(_settings.pencilBaseOpacity * 100).round()}%',
        onChanged: (v) => _update(_settings.copyWith(pencilBaseOpacity: v)),
        cs: cs,
        tt: tt,
      ),
      sliderRow(
        icon: Icons.blur_on_rounded,
        label: 'Softness',
        tooltip: 'Adds a soft blur to pencil edges.',
        value: _settings.pencilBlurRadius,
        min: 0.0,
        max: 4.0,
        displayValue: _settings.pencilBlurRadius.toStringAsFixed(1),
        onChanged: (v) => _update(_settings.copyWith(pencilBlurRadius: v)),
        cs: cs,
        tt: tt,
      ),
      sliderRow(
        icon: Icons.touch_app_rounded,
        label: 'Pressure',
        tooltip: 'How much pen pressure affects opacity and thickness.',
        value: sensitivity,
        min: 0.0,
        max: 1.0,
        displayValue: '${(sensitivity * 100).round()}%',
        onChanged: (v) {
          final newMax = 0.8 + v * 0.8;
          final newMin = 0.5 - v * 0.3;
          _update(
            _settings.copyWith(
              pencilMinPressure: newMin.clamp(0.1, 0.7),
              pencilMaxPressure: newMax.clamp(0.8, 1.6),
            ),
          );
        },
        cs: cs,
        tt: tt,
      ),
    ];
  }

  // ── Ballpoint ──
  List<Widget> _ballpointControls(ColorScheme cs, TextTheme tt, Color accent) {
    final sensitivity = ((_settings.ballpointMaxPressure - 0.8) / 1.0).clamp(
      0.0,
      1.0,
    );
    return [
      presetChips(
        cs: cs,
        tt: tt,
        accent: accent,
        presets: {
          'Fine':
              () => _update(
                _settings.copyWith(
                  ballpointMinPressure: 0.8,
                  ballpointMaxPressure: 0.9,
                ),
              ),
          'Standard':
              () => _update(
                _settings.copyWith(
                  ballpointMinPressure: 0.7,
                  ballpointMaxPressure: 1.1,
                ),
              ),
        },
      ),
      const SizedBox(height: 4),
      sliderRow(
        icon: Icons.touch_app_rounded,
        label: 'Pressure',
        tooltip: 'Controls how much pen pressure affects line thickness.',
        value: sensitivity,
        min: 0.0,
        max: 1.0,
        displayValue: '${(sensitivity * 100).round()}%',
        onChanged: (v) {
          final newMax = 0.8 + v * 1.0;
          final newMin = 0.7 - v * 0.3;
          _update(
            _settings.copyWith(
              ballpointMinPressure: newMin.clamp(0.3, 1.0),
              ballpointMaxPressure: newMax.clamp(0.8, 1.8),
            ),
          );
        },
        cs: cs,
        tt: tt,
      ),
    ];
  }

  // ── Highlighter ──
  List<Widget> _highlighterControls(
    ColorScheme cs,
    TextTheme tt,
    Color accent,
  ) => [
    presetChips(
      cs: cs,
      tt: tt,
      accent: accent,
      presets: {
        'Subtle':
            () => _update(
              _settings.copyWith(
                highlighterOpacity: 0.2,
                highlighterWidthMultiplier: 2.5,
                highlighterAutoStraighten: true,
              ),
            ),
        'Bold':
            () => _update(
              _settings.copyWith(
                highlighterOpacity: 0.55,
                highlighterWidthMultiplier: 4.0,
                highlighterAutoStraighten: true,
              ),
            ),
      },
    ),
    const SizedBox(height: 4),
    sliderRow(
      icon: Icons.opacity_rounded,
      label: 'Opacity',
      tooltip: 'The transparency of the highlighter.',
      value: _settings.highlighterOpacity,
      min: 0.1,
      max: 0.7,
      displayValue: '${(_settings.highlighterOpacity * 100).round()}%',
      onChanged: (v) => _update(_settings.copyWith(highlighterOpacity: v)),
      cs: cs,
      tt: tt,
    ),
    sliderRow(
      icon: Icons.width_normal_rounded,
      label: 'Width',
      tooltip: 'Multiplies the base stroke width for the highlighter.',
      value: _settings.highlighterWidthMultiplier,
      min: 1.5,
      max: 5.0,
      displayValue:
          '${_settings.highlighterWidthMultiplier.toStringAsFixed(1)}×',
      onChanged:
          (v) => _update(_settings.copyWith(highlighterWidthMultiplier: v)),
      cs: cs,
      tt: tt,
    ),
    switchRow(
      icon: Icons.straighten_rounded,
      label: 'Auto-Straighten',
      tooltip: 'Automatically straightens nearly-horizontal highlight lines.',
      value: _settings.highlighterAutoStraighten,
      onChanged: (v) => _update(_settings.copyWith(highlighterAutoStraighten: v)),
      cs: cs,
      tt: tt,
      accent: accent,
    ),
  ];

  // ── Stabilizer (common) ──
  Widget buildStabilizer(ColorScheme cs, TextTheme tt, Color accent) {
    final label = switch (_settings.stabilizerLevel) {
      0 => 'Off',
      <= 3 => 'Light',
      <= 6 => 'Medium',
      <= 9 => 'Heavy',
      _ => 'Max',
    };
    return sliderRow(
      icon: Icons.gesture_rounded,
      label: 'Stabilizer',
      tooltip: 'Smooths out hand tremor and jitter.',
      value: _settings.stabilizerLevel.toDouble(),
      min: 0,
      max: 10,
      displayValue: label,
      divisions: 10,
      onChanged: (v) => _update(_settings.copyWith(stabilizerLevel: v.toInt())),
      cs: cs,
      tt: tt,
    );
  }
}
