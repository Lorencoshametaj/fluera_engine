part of 'pro_brush_settings_dialog.dart';

// ════════════════════════════════════════════════════════════════════
//  REUSABLE UI WIDGETS — sliders, switches, presets, texture, pressure
// ════════════════════════════════════════════════════════════════════

extension _BrushDialogWidgets on _ProBrushSettingsDialogState {
  // ── Preset chips row ──
  Widget presetChips({
    required ColorScheme cs,
    required TextTheme tt,
    required Color accent,
    required Map<String, VoidCallback> presets,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children:
          presets.entries.map((e) {
            return ActionChip(
              label: Text(
                e.key,
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
              onPressed: e.value,
              backgroundColor: accent.withValues(alpha: 0.08),
              side: BorderSide(
                color: accent.withValues(alpha: 0.25),
                width: 0.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
    );
  }

  // ── Single preset chip with icon ──
  Widget presetChip(
    String label,
    IconData icon,
    ColorScheme cs,
    TextTheme tt,
    VoidCallback onTap,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 14),
      label: Text(label, style: tt.labelSmall),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
    );
  }

  // ── Slider row ──
  Widget sliderRow({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
    required ColorScheme cs,
    required TextTheme tt,
    String? tooltip,
    int? divisions,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tooltip != null) ...[
                  const SizedBox(width: 2),
                  infoIcon(tooltip, cs),
                ],
              ],
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              displayValue,
              textAlign: TextAlign.end,
              style: tt.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Switch row ──
  Widget switchRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required ColorScheme cs,
    required TextTheme tt,
    required Color accent,
    String? tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tooltip != null) ...[
                  const SizedBox(width: 2),
                  infoIcon(tooltip, cs),
                ],
              ],
            ),
          ),
          SizedBox(
            height: 28,
            child: FittedBox(
              child: Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeThumbColor: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Live stroke preview ──
  Widget buildStrokePreview(ColorScheme cs, Color accent) {
    return AnimatedBuilder(
      animation: _previewAnim,
      builder: (context, _) {
        final isComplete = _previewAnim.isCompleted;
        return Stack(
          children: [
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ClipRect(
                  clipper: _RevealClipper(_previewAnim.value),
                  child: CustomPaint(
                    size: const Size(double.infinity, 64),
                    painter: _StrokePreviewPainter(
                      penType: widget.currentBrush,
                      color: widget.currentColor ?? accent,
                      baseWidth: widget.currentWidth ?? 2.5,
                      settings: _settings,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: GestureDetector(
                onTap: () => _previewAnim.forward(from: 0.0),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: (isComplete ? cs.onSurfaceVariant : accent)
                        .withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isComplete
                        ? Icons.replay_rounded
                        : Icons.play_arrow_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Texture Controls ──
  Widget buildTextureControls(ColorScheme cs, TextTheme tt, Color accent) {
    const textures = {
      'none': 'None',
      'pencilGrain': 'Pencil',
      'charcoal': 'Charcoal',
      'watercolor': 'Water',
      'canvas': 'Canvas',
      'kraft': 'Kraft',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.texture_rounded, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Texture',
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const Spacer(),
            infoIcon(
              'Applies a texture overlay to strokes for a more natural feel.',
              cs,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children:
              textures.entries.map((e) {
                final isSelected = _settings.textureType == e.key;
                return ChoiceChip(
                  label: Text(
                    e.value,
                    style: tt.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: isSelected ? cs.onPrimary : null,
                    ),
                  ),
                  selected: isSelected,
                  onSelected:
                      (_) => _update(_settings.copyWith(textureType: e.key)),
                  selectedColor: accent,
                  backgroundColor: accent.withValues(alpha: 0.08),
                  side: BorderSide(
                    color: isSelected ? accent : accent.withValues(alpha: 0.25),
                    width: 0.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                );
              }).toList(),
        ),
        if (_settings.textureType != 'none') ...[
          const SizedBox(height: 8),
          sliderRow(
            icon: Icons.grain_rounded,
            label: 'Intensity',
            tooltip: 'How strongly the texture shows through the stroke.',
            value: _settings.textureIntensity,
            min: 0.05,
            max: 1.0,
            displayValue: '${(_settings.textureIntensity * 100).round()}%',
            onChanged: (v) => _update(_settings.copyWith(textureIntensity: v)),
            cs: cs,
            tt: tt,
          ),
        ],
      ],
    );
  }

  // ── Pressure Curve ──
  Widget buildPressureCurve(ColorScheme cs, TextTheme tt, Color accent) {
    final currentName = _settings.pressureCurve.presetName ?? 'custom';
    final curvePresets = {
      'linear': ('Linear', Icons.linear_scale_rounded),
      'soft': ('Soft', Icons.auto_awesome_rounded),
      'firm': ('Firm', Icons.fitness_center_rounded),
      'sCurve': ('S-Curve', Icons.ssid_chart_rounded),
      'heavy': ('Heavy', Icons.monitor_weight_rounded),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              'Pressure Curve',
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const Spacer(),
            infoIcon(
              'Maps raw stylus pressure to output. Soft = light touch produces more, Firm = needs harder press.',
              cs,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children:
              curvePresets.entries.map((e) {
                final isSelected = currentName == e.key;
                return ChoiceChip(
                  avatar: Icon(e.value.$2, size: 14),
                  label: Text(
                    e.value.$1,
                    style: tt.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: isSelected ? cs.onPrimary : null,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (_) {
                    final preset = PressureCurve.presets[e.key];
                    if (preset != null)
                      _update(_settings.copyWith(pressureCurve: preset));
                  },
                  selectedColor: accent,
                  backgroundColor: accent.withValues(alpha: 0.08),
                  side: BorderSide(
                    color: isSelected ? accent : accent.withValues(alpha: 0.25),
                    width: 0.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                );
              }).toList(),
        ),
      ],
    );
  }

  // ── Info icon with tooltip ──
  Widget infoIcon(String message, ColorScheme cs) {
    return Tooltip(
      message: message,
      preferBelow: true,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        color: cs.onInverseSurface,
        fontSize: 12,
        height: 1.3,
      ),
      child: Icon(
        Icons.info_outline_rounded,
        size: 14,
        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}
