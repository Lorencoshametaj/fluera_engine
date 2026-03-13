import 'package:flutter/material.dart';

/// 📐 Detail Section — Clarity, Texture, Sharpen, Noise Reduction
class EditorSectionDetail extends StatelessWidget {
  final double clarity;
  final double sharpen;
  final double noiseReduction;
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

  const EditorSectionDetail({
    super.key,
    required this.clarity,
    required this.sharpen,
    required this.noiseReduction,
    required this.onPushUndo,
    required this.sliderBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        sliderBuilder(
          icon: Icons.hdr_strong_rounded,
          label: 'Clarity',
          value: clarity,
          min: -1,
          max: 1,
          def: 0,
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        sliderBuilder(
          icon: Icons.deblur_rounded,
          label: 'Sharpen',
          value: sharpen,
          min: 0,
          max: 2,
          def: 0,
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        sliderBuilder(
          icon: Icons.grain_rounded,
          label: 'Noise Reduction',
          value: noiseReduction,
          min: 0,
          max: 1,
          def: 0,
          onChanged: (_) {},
        ),
      ],
    );
  }
}
