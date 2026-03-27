import 'package:flutter/material.dart';

/// ⚡ Light Section — Brightness, Contrast, Highlights, Shadows, Exposure, Fade
class EditorSectionLight extends StatelessWidget {
  final double brightness;
  final double contrast;
  final double highlights;
  final double shadows;
  final double fade;
  final double opacity;
  final VoidCallback onPushUndo;
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

  const EditorSectionLight({
    super.key,
    required this.brightness,
    required this.contrast,
    required this.highlights,
    required this.shadows,
    required this.fade,
    required this.opacity,
    required this.onPushUndo,
    required this.sliderBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        sliderBuilder(
          icon: Icons.brightness_6_rounded,
          label: 'Brightness',
          value: brightness,
          min: -0.5,
          max: 0.5,
          def: 0,
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        sliderBuilder(
          icon: Icons.contrast_rounded,
          label: 'Contrast',
          value: contrast,
          min: -0.5,
          max: 0.5,
          def: 0,
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        sliderBuilder(
          icon: Icons.wb_sunny_rounded,
          label: 'Highlights',
          value: highlights,
          min: -1,
          max: 1,
          def: 0,
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        sliderBuilder(
          icon: Icons.nights_stay_rounded,
          label: 'Shadows',
          value: shadows,
          min: -1,
          max: 1,
          def: 0,
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        sliderBuilder(
          icon: Icons.opacity_rounded,
          label: 'Opacity',
          value: opacity,
          min: 0,
          max: 1,
          def: 1,
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        sliderBuilder(
          icon: Icons.blur_linear_rounded,
          label: 'Fade',
          value: fade,
          min: 0,
          max: 1,
          def: 0,
          onChanged: (_) {},
        ),
      ],
    );
  }
}
