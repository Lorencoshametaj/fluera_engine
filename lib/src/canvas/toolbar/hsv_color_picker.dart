import 'package:flutter/material.dart';

/// 🎨 Custom HSV Color Picker — replaces `flutter_colorpicker` dependency.
///
/// A compact Material-3-style color picker with:
/// - **Saturation/Value** gradient area (2D pick)
/// - **Hue** slider (1D rainbow bar)
/// - **Live preview** swatch
///
/// Drop-in replacement for [ColorPicker] from `flutter_colorpicker`.
class HsvColorPicker extends StatefulWidget {
  /// Initial color shown when the picker opens.
  final Color pickerColor;

  /// Called on every drag move as the user picks a color.
  final ValueChanged<Color> onColorChanged;

  /// Relative height of the SV area (0.0–1.0 of available width).
  final double pickerAreaHeightPercent;

  const HsvColorPicker({
    super.key,
    required this.pickerColor,
    required this.onColorChanged,
    this.pickerAreaHeightPercent = 0.8,
  });

  @override
  State<HsvColorPicker> createState() => _HsvColorPickerState();
}

class _HsvColorPickerState extends State<HsvColorPicker> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.pickerColor);
  }

  void _update(HSVColor hsv) {
    setState(() => _hsv = hsv);
    widget.onColorChanged(hsv.toColor());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Saturation / Value area ──
        AspectRatio(
          aspectRatio: 1 / widget.pickerAreaHeightPercent,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onPanStart: (d) => _onSvPan(d.localPosition, constraints),
                onPanUpdate: (d) => _onSvPan(d.localPosition, constraints),
                child: CustomPaint(
                  painter: _SvPainter(hue: _hsv.hue),
                  child: Stack(
                    children: [
                      Positioned(
                        left: _hsv.saturation * constraints.maxWidth - 8,
                        top: (1 - _hsv.value) * constraints.maxHeight - 8,
                        child: _Thumb(color: _hsv.toColor()),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        // ── Hue slider ──
        SizedBox(
          height: 24,
          child: LayoutBuilder(
            builder:
                (context, constraints) => GestureDetector(
                  onPanStart: (d) => _onHuePan(d.localPosition, constraints),
                  onPanUpdate: (d) => _onHuePan(d.localPosition, constraints),
                  child: CustomPaint(
                    painter: _HueBarPainter(),
                    child: Stack(
                      children: [
                        Positioned(
                          left: (_hsv.hue / 360) * constraints.maxWidth - 8,
                          top: 0,
                          bottom: 0,
                          child: _Thumb(
                            color:
                                HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
        ),

        const SizedBox(height: 12),

        // ── Preview swatch ──
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: _hsv.toColor(),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24, width: 1),
          ),
        ),
      ],
    );
  }

  void _onSvPan(Offset local, BoxConstraints c) {
    final s = (local.dx / c.maxWidth).clamp(0.0, 1.0);
    final v = (1 - local.dy / c.maxHeight).clamp(0.0, 1.0);
    _update(_hsv.withSaturation(s).withValue(v));
  }

  void _onHuePan(Offset local, BoxConstraints c) {
    final hue = ((local.dx / c.maxWidth) * 360).clamp(0.0, 360.0);
    _update(_hsv.withHue(hue));
  }
}

/// Thumb indicator for sliders and the SV area.
class _Thumb extends StatelessWidget {
  final Color color;
  const _Thumb({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

/// Paints the Saturation (x) / Value (y) gradient.
class _SvPainter extends CustomPainter {
  final double hue;
  _SvPainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Layer 1: white → hue (saturation gradient, left to right)
    final satGradient = LinearGradient(
      colors: [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()],
    );
    canvas.drawRect(rect, Paint()..shader = satGradient.createShader(rect));

    // Layer 2: transparent → black (value gradient, top to bottom)
    final valGradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    );
    canvas.drawRect(rect, Paint()..shader = valGradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_SvPainter old) => old.hue != hue;
}

/// Paints the rainbow hue bar.
class _HueBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = List<Color>.generate(
      7,
      (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
    );
    final gradient = LinearGradient(colors: colors);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_HueBarPainter old) => false;
}
