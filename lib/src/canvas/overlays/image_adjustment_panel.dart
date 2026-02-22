import 'package:flutter/material.dart';
import '../../systems/image_adjustment.dart';

// ============================================================================
// 🖼️ IMAGE ADJUSTMENT PANEL — Brightness, contrast, saturation, hue
// ============================================================================

class ImageAdjustmentPanel extends StatefulWidget {
  const ImageAdjustmentPanel({super.key});

  @override
  State<ImageAdjustmentPanel> createState() => _ImageAdjustmentPanelState();
}

class _ImageAdjustmentPanelState extends State<ImageAdjustmentPanel> {
  double _brightness = 0.0;
  double _contrast = 0.0;
  double _saturation = 0.0;
  double _hue = 0.0;

  void _resetAll() {
    setState(() {
      _brightness = 0.0;
      _contrast = 0.0;
      _saturation = 0.0;
      _hue = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Icon(Icons.tune_rounded, color: cs.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                'Image Adjustments',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              TextButton(onPressed: _resetAll, child: const Text('Reset')),
            ],
          ),
          const SizedBox(height: 12),
          _AdjustSlider(
            icon: Icons.brightness_6_rounded,
            label: 'Brightness',
            value: _brightness,
            min: -1.0,
            max: 1.0,
            color: Colors.amber,
            cs: cs,
            onChanged: (v) => setState(() => _brightness = v),
          ),
          _AdjustSlider(
            icon: Icons.contrast_rounded,
            label: 'Contrast',
            value: _contrast,
            min: -1.0,
            max: 1.0,
            color: Colors.blue,
            cs: cs,
            onChanged: (v) => setState(() => _contrast = v),
          ),
          _AdjustSlider(
            icon: Icons.color_lens_rounded,
            label: 'Saturation',
            value: _saturation,
            min: -1.0,
            max: 1.0,
            color: Colors.pink,
            cs: cs,
            onChanged: (v) => setState(() => _saturation = v),
          ),
          _AdjustSlider(
            icon: Icons.palette_rounded,
            label: 'Hue',
            value: _hue,
            min: -180.0,
            max: 180.0,
            color: Colors.deepPurple,
            cs: cs,
            onChanged: (v) => setState(() => _hue = v),
          ),
        ],
      ),
    );
  }
}

class _AdjustSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final Color color;
  final ColorScheme cs;
  final ValueChanged<double> onChanged;

  const _AdjustSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.cs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: cs.onSurface),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: color,
                inactiveTrackColor: cs.surfaceContainerHighest,
                thumbColor: color,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              value.toStringAsFixed(max > 10 ? 0 : 1),
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
