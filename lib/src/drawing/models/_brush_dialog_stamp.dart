part of 'pro_brush_settings_dialog.dart';

// ════════════════════════════════════════════════════════════════════
//  STAMP DYNAMICS SECTION
// ════════════════════════════════════════════════════════════════════

extension _BrushDialogStampDynamics on _ProBrushSettingsDialogState {
  Widget buildStampDynamics(ColorScheme cs, TextTheme tt, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.grain_rounded, size: 16, color: accent),
            const SizedBox(width: 6),
            Text(
              'Stamp Dynamics',
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        sliderRow(
          icon: Icons.space_dashboard_rounded,
          label: 'Spacing',
          tooltip:
              'Distance between consecutive stamps as a fraction of brush size.',
          value: _settings.stampSpacing,
          min: 0.05,
          max: 1.0,
          displayValue: '${(_settings.stampSpacing * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampSpacing: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.opacity_rounded,
          label: 'Flow',
          tooltip: 'Per-stamp opacity.',
          value: _settings.stampFlow,
          min: 0.1,
          max: 1.0,
          displayValue: '${(_settings.stampFlow * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampFlow: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.water_drop_outlined,
          label: 'Wet Edges',
          tooltip: 'Darker ring around stamp edges.',
          value: _settings.stampWetEdges,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampWetEdges * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampWetEdges: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.speed_rounded,
          label: 'Vel → Size',
          tooltip: 'How much drawing speed shrinks stamp size.',
          value: _settings.stampVelocitySize,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampVelocitySize * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampVelocitySize: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.air_rounded,
          label: 'Vel → Flow',
          tooltip: 'How much drawing speed reduces opacity.',
          value: _settings.stampVelocityFlow,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampVelocityFlow * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampVelocityFlow: v)),
          cs: cs,
          tt: tt,
        ),
        switchRow(
          icon: Icons.layers_rounded,
          label: 'Glaze Mode',
          tooltip: 'ON = caps stroke opacity. OFF = stamps accumulate freely.',
          value: _settings.stampGlazeMode,
          onChanged: (v) => _update(_settings.copyWith(stampGlazeMode: v)),
          cs: cs,
          tt: tt,
          accent: accent,
        ),
        sliderRow(
          icon: Icons.palette_rounded,
          label: 'Hue Jitter',
          tooltip: 'Random hue variation per stamp.',
          value: _settings.stampHueJitter,
          min: 0.0,
          max: 30.0,
          displayValue: '${_settings.stampHueJitter.round()}°',
          onChanged: (v) => _update(_settings.copyWith(stampHueJitter: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.gradient_rounded,
          label: 'Sat Jitter',
          tooltip: 'Random saturation variation per stamp.',
          value: _settings.stampSatJitter,
          min: 0.0,
          max: 0.3,
          displayValue: '${(_settings.stampSatJitter * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampSatJitter: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.brightness_6_rounded,
          label: 'Bright Jitter',
          tooltip: 'Random brightness variation per stamp.',
          value: _settings.stampBrightJitter,
          min: 0.0,
          max: 0.2,
          displayValue: '${(_settings.stampBrightJitter * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampBrightJitter: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.photo_size_select_small_rounded,
          label: 'Size Jitter',
          tooltip: 'Random size variation per stamp.',
          value: _settings.stampSizeJitter,
          min: 0.0,
          max: 0.5,
          displayValue: '${(_settings.stampSizeJitter * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampSizeJitter: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.rotate_right_rounded,
          label: 'Angle Jitter',
          tooltip: 'Random rotation per stamp.',
          value: _settings.stampRotationJitter,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampRotationJitter * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampRotationJitter: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.scatter_plot_rounded,
          label: 'Scatter',
          tooltip: 'Perpendicular offset randomness.',
          value: _settings.stampScatter,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampScatter * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampScatter: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.edit_rounded,
          label: 'Tilt → Rot',
          tooltip: 'How much tilt direction overrides stroke-angle rotation.',
          value: _settings.stampTiltRotation,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampTiltRotation * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampTiltRotation: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.open_in_full_rounded,
          label: 'Tilt → Stretch',
          tooltip: 'How much tilt stretches the stamp elliptically.',
          value: _settings.stampTiltElongation,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampTiltElongation * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampTiltElongation: v)),
          cs: cs,
          tt: tt,
        ),
        // ── Dual Brush ──
        _dualBrushDropdown(cs, tt),
        if (_settings.stampDualTexture != 'none') ...[
          sliderRow(
            icon: Icons.tune_rounded,
            label: 'Dual Blend',
            tooltip: 'Intensity of the secondary texture masking.',
            value: _settings.stampDualBlend,
            min: 0.0,
            max: 1.0,
            displayValue: '${(_settings.stampDualBlend * 100).round()}%',
            onChanged: (v) => _update(_settings.copyWith(stampDualBlend: v)),
            cs: cs,
            tt: tt,
          ),
          sliderRow(
            icon: Icons.aspect_ratio_rounded,
            label: 'Dual Scale',
            tooltip: 'Scale of the dual texture relative to the stamp.',
            value: _settings.stampDualScale,
            min: 0.3,
            max: 3.0,
            displayValue: '${_settings.stampDualScale.toStringAsFixed(1)}×',
            onChanged: (v) => _update(_settings.copyWith(stampDualScale: v)),
            cs: cs,
            tt: tt,
          ),
        ],
        sliderRow(
          icon: Icons.contrast_rounded,
          label: 'Press Color',
          tooltip: 'Harder pressure darkens the color.',
          value: _settings.stampPressureColor,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampPressureColor * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampPressureColor: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.water_drop_rounded,
          label: 'Wet Mix',
          tooltip: 'Color bleed between stamps.',
          value: _settings.stampWetMix,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampWetMix * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampWetMix: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.circle_outlined,
          label: 'Round Jitter',
          tooltip: 'Random elongation variation per stamp.',
          value: _settings.stampRoundnessJitter,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampRoundnessJitter * 100).round()}%',
          onChanged:
              (v) => _update(_settings.copyWith(stampRoundnessJitter: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.gradient_rounded,
          label: 'Color Grad',
          tooltip: 'Fade from brush color toward white along the stroke path.',
          value: _settings.stampColorGradient,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampColorGradient * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampColorGradient: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.vertical_align_top_rounded,
          label: 'Accum Cap',
          tooltip: 'Max opacity in glaze mode. 0 = uncapped.',
          value: _settings.stampAccumCap,
          min: 0.0,
          max: 1.0,
          displayValue:
              _settings.stampAccumCap == 0
                  ? 'Off'
                  : '${(_settings.stampAccumCap * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampAccumCap: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.compress_rounded,
          label: 'Spacing Press',
          tooltip: 'Pressure tightens stamp spacing.',
          value: _settings.stampSpacingPressure,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampSpacingPressure * 100).round()}%',
          onChanged:
              (v) => _update(_settings.copyWith(stampSpacingPressure: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.speed_rounded,
          label: 'Transfer Vel',
          tooltip: 'Slow strokes = more opaque. Fast = lighter.',
          value: _settings.stampTransferVelocity,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampTransferVelocity * 100).round()}%',
          onChanged:
              (v) => _update(_settings.copyWith(stampTransferVelocity: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.grain_rounded,
          label: 'Grain Scale',
          tooltip: 'Zoom grain texture.',
          value: _settings.stampGrainScale,
          min: 0.1,
          max: 3.0,
          displayValue: '${_settings.stampGrainScale.toStringAsFixed(1)}x',
          onChanged: (v) => _update(_settings.copyWith(stampGrainScale: v)),
          cs: cs,
          tt: tt,
        ),
        sliderRow(
          icon: Icons.palette_rounded,
          label: 'Color Press',
          tooltip: 'Pressure shifts color toward white.',
          value: _settings.stampColorPressure,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampColorPressure * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampColorPressure: v)),
          cs: cs,
          tt: tt,
        ),
        // ── Shape, Symmetry, Grain Mode, Eraser ──
        _stampShapeSection(cs, tt),
        sliderRow(
          icon: Icons.auto_awesome_rounded,
          label: 'Symmetry',
          tooltip: 'Mirror stamps across axes.',
          value: _settings.stampSymmetryAxes.toDouble(),
          min: 0,
          max: 8,
          displayValue:
              _settings.stampSymmetryAxes == 0
                  ? 'Off'
                  : '${_settings.stampSymmetryAxes}x',
          onChanged:
              (v) => _update(_settings.copyWith(stampSymmetryAxes: v.round())),
          cs: cs,
          tt: tt,
        ),
        switchRow(
          icon: Icons.texture_rounded,
          label: 'Screen Grain',
          tooltip:
              'ON: grain fixed like paper. OFF: grain rotates with stroke.',
          value: _settings.stampGrainScreenSpace,
          onChanged:
              (v) => _update(_settings.copyWith(stampGrainScreenSpace: v)),
          cs: cs,
          tt: tt,
          accent: accent,
        ),
        switchRow(
          icon: Icons.auto_fix_off_rounded,
          label: 'Eraser Mode',
          tooltip: 'Stamps erase instead of painting.',
          value: _settings.stampEraserMode,
          onChanged: (v) => _update(_settings.copyWith(stampEraserMode: v)),
          cs: cs,
          tt: tt,
          accent: accent,
        ),
        // ── Stamp Presets ──
        _stampPresetsSection(cs, tt),
      ],
    );
  }

  Widget _dualBrushDropdown(ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Icon(Icons.texture_rounded, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              'Dual Tip',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: DropdownButton<String>(
              value: _settings.stampDualTexture,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: tt.bodySmall?.copyWith(color: cs.onSurface),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('None')),
                DropdownMenuItem(
                  value: 'pencilGrain',
                  child: Text('Pencil Grain'),
                ),
                DropdownMenuItem(value: 'charcoal', child: Text('Charcoal')),
                DropdownMenuItem(
                  value: 'watercolor',
                  child: Text('Watercolor'),
                ),
                DropdownMenuItem(value: 'canvas', child: Text('Canvas')),
                DropdownMenuItem(value: 'kraft', child: Text('Kraft')),
              ],
              onChanged: (v) {
                if (v != null) {
                  _update(
                    _settings.copyWith(
                      stampDualTexture: v,
                      stampDualBlend:
                          v == 'none'
                              ? 0.0
                              : (_settings.stampDualBlend < 0.1 ? 0.5 : null),
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _stampShapeSection(ColorScheme cs, TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            'STAMP SHAPE',
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              letterSpacing: 1.2,
            ),
          ),
        ),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final entry
                in {
                  0: ('\u25CF', 'Circle'),
                  1: ('\u25A0', 'Square'),
                  2: ('\u25C6', 'Diamond'),
                  3: ('\u2605', 'Star'),
                  4: ('\u{1F342}', 'Leaf'),
                }.entries)
              ChoiceChip(
                label: Text(
                  entry.value.$1,
                  style: tt.bodySmall?.copyWith(fontSize: 16),
                ),
                selected: _settings.stampShapeType == entry.key,
                onSelected:
                    (_) =>
                        _update(_settings.copyWith(stampShapeType: entry.key)),
                visualDensity: VisualDensity.compact,
                tooltip: entry.value.$2,
              ),
          ],
        ),
      ],
    );
  }

  Widget _stampPresetsSection(ColorScheme cs, TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            'PRESETS',
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              letterSpacing: 1.2,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            presetChip('Watercolor', Icons.water_rounded, cs, tt, () {
              _update(
                _settings.copyWith(
                  stampSpacing: 0.12,
                  stampSoftness: 0.85,
                  stampFlow: 0.25,
                  stampWetEdges: 0.7,
                  stampSizeJitter: 0.15,
                  stampOpacityJitter: 0.2,
                  stampScatter: 0.08,
                  stampWetMix: 0.6,
                  stampPressureColor: 0.3,
                  stampGlazeMode: true,
                ),
              );
            }),
            presetChip('Charcoal', Icons.gesture_rounded, cs, tt, () {
              _update(
                _settings.copyWith(
                  stampSpacing: 0.08,
                  stampSoftness: 0.4,
                  stampFlow: 0.6,
                  stampSizeJitter: 0.2,
                  stampRotationJitter: 0.5,
                  stampScatter: 0.15,
                  stampElongation: 1.3,
                  stampWetEdges: 0.0,
                  stampWetMix: 0.0,
                  stampPressureColor: 0.5,
                  stampGlazeMode: false,
                ),
              );
            }),
            presetChip('Airbrush', Icons.blur_on_rounded, cs, tt, () {
              _update(
                _settings.copyWith(
                  stampSpacing: 0.05,
                  stampSoftness: 1.0,
                  stampFlow: 0.15,
                  stampSizeJitter: 0.0,
                  stampRotationJitter: 0.0,
                  stampScatter: 0.0,
                  stampWetEdges: 0.0,
                  stampWetMix: 0.0,
                  stampPressureColor: 0.0,
                  stampGlazeMode: true,
                ),
              );
            }),
            presetChip('Oil Paint', Icons.brush_rounded, cs, tt, () {
              _update(
                _settings.copyWith(
                  stampSpacing: 0.15,
                  stampSoftness: 0.5,
                  stampFlow: 0.7,
                  stampSizeJitter: 0.1,
                  stampRotationJitter: 0.3,
                  stampElongation: 1.5,
                  stampWetEdges: 0.2,
                  stampWetMix: 0.8,
                  stampPressureColor: 0.4,
                  stampGlazeMode: false,
                  stampTiltRotation: 0.6,
                  stampTiltElongation: 0.5,
                ),
              );
            }),
            presetChip('Ink Splash', Icons.opacity_rounded, cs, tt, () {
              _update(
                _settings.copyWith(
                  stampSpacing: 0.3,
                  stampSoftness: 0.3,
                  stampFlow: 0.9,
                  stampSizeJitter: 0.4,
                  stampRotationJitter: 0.8,
                  stampScatter: 0.5,
                  stampOpacityJitter: 0.3,
                  stampWetEdges: 0.5,
                  stampWetMix: 0.2,
                  stampPressureColor: 0.6,
                  stampGlazeMode: false,
                ),
              );
            }),
          ],
        ),
      ],
    );
  }
}
