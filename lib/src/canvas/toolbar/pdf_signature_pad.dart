import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ✍️ PDF Signature Pad — draw a signature with finger/stylus.
///
/// Captures a smooth bezier path and returns the rendered signature
/// as a [ui.Image] for embedding into PDF pages.
class PdfSignaturePad extends StatefulWidget {
  /// Called when the user confirms the signature.
  /// Returns the signature as a [ui.Image] and the stroke [Path].
  final void Function(ui.Image image, Path path)? onConfirm;
  final VoidCallback? onCancel;

  /// Stroke color for the signature.
  final Color strokeColor;

  /// Stroke width for the signature.
  final double strokeWidth;

  const PdfSignaturePad({
    super.key,
    this.onConfirm,
    this.onCancel,
    this.strokeColor = const Color(0xFF1A237E),
    this.strokeWidth = 2.5,
  });

  @override
  State<PdfSignaturePad> createState() => _PdfSignaturePadState();
}

class _PdfSignaturePadState extends State<PdfSignaturePad> {
  final List<Offset?> _points = [];

  void _clear() {
    setState(() => _points.clear());
    HapticFeedback.lightImpact();
  }

  Future<void> _confirm() async {
    if (_points.isEmpty) return;
    HapticFeedback.mediumImpact();

    // Build the path
    final path = Path();
    bool started = false;
    for (final p in _points) {
      if (p == null) {
        started = false;
        continue;
      }
      if (!started) {
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    // Render to image
    final bounds = path.getBounds();
    if (bounds.isEmpty) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, bounds.width + 20, bounds.height + 20),
    );
    canvas.translate(-bounds.left + 10, -bounds.top + 10);
    canvas.drawPath(
      path,
      Paint()
        ..color = widget.strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = widget.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (bounds.width + 20).ceil(),
      (bounds.height + 20).ceil(),
    );

    widget.onConfirm?.call(image, path);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.draw_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Signature',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                TextButton(onPressed: _clear, child: const Text('Clear')),
              ],
            ),
          ),

          // Drawing area
          Container(
            height: 160,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: GestureDetector(
                onPanStart: (d) {
                  setState(() => _points.add(d.localPosition));
                },
                onPanUpdate: (d) {
                  setState(() => _points.add(d.localPosition));
                },
                onPanEnd: (_) {
                  _points.add(null); // Stroke break
                },
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _SignaturePainter(
                    points: _points,
                    color: widget.strokeColor,
                    strokeWidth: widget.strokeWidth,
                  ),
                ),
              ),
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _points.isNotEmpty ? _confirm : null,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Apply'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  final Color color;
  final double strokeWidth;

  _SignaturePainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw baseline
    final basePaint =
        Paint()
          ..color = const Color(0x20000000)
          ..strokeWidth = 0.5;
    final y = size.height * 0.75;
    canvas.drawLine(Offset(20, y), Offset(size.width - 20, y), basePaint);

    // Draw signature strokes
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) => true;
}
