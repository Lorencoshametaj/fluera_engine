import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 🔧 Effects Section — Film Grain, Vignette, Blur, Edge Detect
class EditorSectionEffects extends StatelessWidget {
  final double grain;
  final double vignette;
  final int vignetteColor;
  final double blur;
  final double edgeDetect;
  final VoidCallback onPushUndo;
  final ValueChanged<int> onVignetteColorChanged;
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

  const EditorSectionEffects({
    super.key,
    required this.grain,
    required this.vignette,
    required this.vignetteColor,
    required this.blur,
    required this.edgeDetect,
    required this.onPushUndo,
    required this.onVignetteColorChanged,
    required this.sliderBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        // ── Film Grain ──
        Text(
          '🎞️ Film Grain',
          style: tt.labelLarge?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        sliderBuilder(
          icon: Icons.grain_rounded,
          label: 'Amount',
          value: grain,
          min: 0,
          max: 1,
          def: 0,
          onChanged: (_) {},
        ),

        // ── Vignette ──
        const SizedBox(height: 20),
        Text(
          '🔲 Vignette',
          style: tt.labelLarge?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        sliderBuilder(
          icon: Icons.vignette_rounded,
          label: 'Strength',
          value: vignette,
          min: 0,
          max: 1,
          def: 0,
          onChanged: (_) {},
        ),
        const SizedBox(height: 8),
        _vignetteColorRow(cs, tt),

        // ── Blur ──
        const SizedBox(height: 20),
        sliderBuilder(
          icon: Icons.blur_on_rounded,
          label: 'Blur',
          value: blur,
          min: 0,
          max: 50,
          def: 0,
          onChanged: (_) {},
        ),

        // ── Edge Detect ──
        const SizedBox(height: 14),
        sliderBuilder(
          icon: Icons.filter_frames_rounded,
          label: 'Edge Detect',
          value: edgeDetect,
          min: 0,
          max: 1,
          def: 0,
          onChanged: (_) {},
        ),
      ],
    );
  }

  Widget _vignetteColorRow(ColorScheme cs, TextTheme tt) {
    const colors = [0xFF000000, 0xFF1A237E, 0xFF880E4F, 0xFF004D40, 0xFFBF360C];
    return Row(
      children: [
        Text(
          'Color',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        ...colors.map(
          (c) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                onPushUndo();
                onVignetteColorChanged(c);
                HapticFeedback.selectionClick();
              },
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: vignetteColor == c ? cs.primary : cs.outlineVariant,
                    width: vignetteColor == c ? 2.5 : 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
