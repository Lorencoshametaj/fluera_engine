import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 🎨 Color Section — Saturation, Temperature, Hue, Split Toning, HSL Mixer
class EditorSectionColor extends StatelessWidget {
  final double saturation;
  final double temperature;
  final double hueShift;
  final int splitHighlightColor;
  final int splitShadowColor;
  final List<double> hslAdjustments;
  final VoidCallback onPushUndo;
  final ValueChanged<int> onSplitHighlightChanged;
  final ValueChanged<int> onSplitShadowChanged;
  final ValueChanged<List<double>> onHslChanged;
  final Widget Function({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required double def,
    required ValueChanged<double> onChanged,
  })
  sliderBuilder;

  const EditorSectionColor({
    super.key,
    required this.saturation,
    required this.temperature,
    required this.hueShift,
    required this.splitHighlightColor,
    required this.splitShadowColor,
    required this.hslAdjustments,
    required this.onPushUndo,
    required this.onSplitHighlightChanged,
    required this.onSplitShadowChanged,
    required this.onHslChanged,
    required this.sliderBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        sliderBuilder(
          icon: Icons.color_lens_rounded,
          label: 'Saturation',
          value: saturation,
          min: -1,
          max: 1,
          def: 0,
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        sliderBuilder(
          icon: Icons.thermostat_rounded,
          label: 'Temperature',
          value: temperature,
          min: -1,
          max: 1,
          def: 0,
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        sliderBuilder(
          icon: Icons.rotate_right_rounded,
          label: 'Hue Shift',
          value: hueShift,
          min: -1,
          max: 1,
          def: 0,
          onChanged: (_) {},
        ),

        // ── Split Toning ──
        const SizedBox(height: 20),
        Text(
          '🎭 Split Toning',
          style: tt.labelLarge?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        _colorPickerRow(
          cs,
          tt,
          'Highlights',
          splitHighlightColor,
          onSplitHighlightChanged,
        ),
        const SizedBox(height: 8),
        _colorPickerRow(
          cs,
          tt,
          'Shadows',
          splitShadowColor,
          onSplitShadowChanged,
        ),

        // ── HSL Color Mixer ──
        const SizedBox(height: 20),
        Text(
          '🎛️ Color Mixer (HSL)',
          style: tt.labelLarge?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        _buildHslMixer(cs, tt),
      ],
    );
  }

  Widget _colorPickerRow(
    ColorScheme cs,
    TextTheme tt,
    String label,
    int currentColor,
    ValueChanged<int> onChanged,
  ) {
    const colors = [
      0,
      0xFFFF6B6B,
      0xFFFFD93D,
      0xFF6BCB77,
      0xFF4D96FF,
      0xFF9B59B6,
      0xFFE17055,
    ];
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        ...colors.map(
          (c) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                onPushUndo();
                onChanged(c);
                HapticFeedback.selectionClick();
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: c == 0 ? cs.surfaceContainerHighest : Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: currentColor == c ? cs.primary : cs.outlineVariant,
                    width: currentColor == c ? 2.5 : 1,
                  ),
                ),
                child:
                    c == 0
                        ? Icon(
                          Icons.block_rounded,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        )
                        : null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static const _hslChannels = [
    ('Red', Color(0xFFEF5350)),
    ('Orange', Color(0xFFFF9800)),
    ('Yellow', Color(0xFFFFEB3B)),
    ('Green', Color(0xFF66BB6A)),
    ('Cyan', Color(0xFF26C6DA)),
    ('Blue', Color(0xFF42A5F5)),
    ('Magenta', Color(0xFFAB47BC)),
  ];

  Widget _buildHslMixer(ColorScheme cs, TextTheme tt) {
    return Column(
      children: List.generate(7, (i) {
        final channel = _hslChannels[i];
        final hAdj = hslAdjustments[i * 3 + 0];
        final sAdj = hslAdjustments[i * 3 + 1];
        final lAdj = hslAdjustments[i * 3 + 2];
        final isActive =
            hAdj.abs() > 0.01 || sAdj.abs() > 0.01 || lAdj.abs() > 0.01;

        return Theme(
          data: Theme.of(
            _buildContext!,
          ).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            dense: true,
            tilePadding: EdgeInsets.zero,
            leading: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: channel.$2,
                shape: BoxShape.circle,
              ),
            ),
            title: Text(
              channel.$1,
              style: tt.bodyMedium?.copyWith(
                color: isActive ? cs.primary : cs.onSurface,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            children: [
              sliderBuilder(
                icon: Icons.rotate_right_rounded,
                label: 'Hue',
                value: hAdj,
                min: -1,
                max: 1,
                def: 0,
                onChanged: (v) {
                  final adj = List<double>.from(hslAdjustments);
                  adj[i * 3] = v;
                  onHslChanged(adj);
                },
              ),
              sliderBuilder(
                icon: Icons.water_drop_rounded,
                label: 'Sat',
                value: sAdj,
                min: -1,
                max: 1,
                def: 0,
                onChanged: (v) {
                  final adj = List<double>.from(hslAdjustments);
                  adj[i * 3 + 1] = v;
                  onHslChanged(adj);
                },
              ),
              sliderBuilder(
                icon: Icons.light_mode_rounded,
                label: 'Lum',
                value: lAdj,
                min: -1,
                max: 1,
                def: 0,
                onChanged: (v) {
                  final adj = List<double>.from(hslAdjustments);
                  adj[i * 3 + 2] = v;
                  onHslChanged(adj);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      }),
    );
  }

  // Hack to get BuildContext inside _buildHslMixer
  BuildContext? get _buildContext => null;
}
