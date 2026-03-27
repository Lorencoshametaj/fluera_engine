import 'package:flutter/material.dart';
import '../../core/models/tone_curve.dart';
import '../curve_editor_widget.dart';

/// 📈 Curve Section — Interactive tone curve with channel tabs
class EditorSectionCurve extends StatelessWidget {
  final ToneCurve toneCurve;
  final VoidCallback onPushUndo;
  final ValueChanged<ToneCurve> onCurveChanged;

  const EditorSectionCurve({
    super.key,
    required this.toneCurve,
    required this.onPushUndo,
    required this.onCurveChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(
          '📈 Tone Curve',
          style: tt.labelLarge?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap to add points · Drag to adjust · Double-tap to remove',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Center(
          child: CurveEditorWidget(
            curve: toneCurve,
            size: 280,
            onChanged: (curve) {
              onPushUndo();
              onCurveChanged(curve);
            },
          ),
        ),
        const SizedBox(height: 16),
        // Reset button
        if (!toneCurve.isIdentity)
          Center(
            child: TextButton.icon(
              onPressed: () {
                onPushUndo();
                onCurveChanged(const ToneCurve());
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset Curve'),
              style: TextButton.styleFrom(foregroundColor: cs.error),
            ),
          ),
      ],
    );
  }
}
