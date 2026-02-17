part of 'pro_brush_settings_dialog.dart';

/// 🎨 Painter that renders a representative stroke with current settings.
/// Generates a sinusoidal wave with varying pressure to showcase brush effects.
class _StrokePreviewPainter extends CustomPainter {
  final ProPenType penType;
  final Color color;
  final double baseWidth;
  final ProBrushSettings settings;

  _StrokePreviewPainter({
    required this.penType,
    required this.color,
    required this.baseWidth,
    required this.settings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final points = switch (penType) {
      ProPenType.fountain => _fountainPoints(size),
      ProPenType.pencil => _pencilPoints(size),
      ProPenType.ballpoint => _ballpointPoints(size),
      ProPenType.highlighter => _highlighterPoints(size),
      // New brushes use ballpoint-like preview curve
      ProPenType.watercolor ||
      ProPenType.marker ||
      ProPenType.charcoal ||
      ProPenType.oilPaint ||
      ProPenType.sprayPaint ||
      ProPenType.neonGlow ||
      ProPenType.inkWash => _ballpointPoints(size),
    };

    BrushEngine.renderStroke(
      canvas,
      points,
      color,
      baseWidth,
      penType,
      settings,
    );
  }

  /// Fountain: flowing S-curve with direction changes to showcase nib angle
  List<ProDrawingPoint> _fountainPoints(Size size) {
    const n = 80;
    final pts = <ProDrawingPoint>[];
    final px = size.width * 0.06;
    final w = size.width - px * 2;
    final cy = size.height / 2;
    final amp = size.height * 0.32;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final x = px + t * w;
      final y = cy + math.sin(t * math.pi * 3.0) * amp;
      final p = (math.sin(t * math.pi) * 0.7 +
              0.2 +
              0.1 * math.sin(t * math.pi * 6.0))
          .clamp(0.1, 1.0);
      pts.add(
        ProDrawingPoint(position: Offset(x, y), pressure: p, timestamp: i),
      );
    }
    return pts;
  }

  /// Pencil: loose sketch feel with jitter
  List<ProDrawingPoint> _pencilPoints(Size size) {
    const n = 60;
    final pts = <ProDrawingPoint>[];
    final px = size.width * 0.06;
    final w = size.width - px * 2;
    final cy = size.height / 2;
    final amp = size.height * 0.25;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final x = px + t * w;
      final jitter = math.sin(t * math.pi * 12.0) * 2.0;
      final y = cy + math.sin(t * math.pi * 2.0) * amp + jitter;
      final p = (0.3 + 0.4 * math.sin(t * math.pi * 4.0)).clamp(0.15, 0.7);
      pts.add(
        ProDrawingPoint(position: Offset(x, y), pressure: p, timestamp: i),
      );
    }
    return pts;
  }

  /// Ballpoint: smooth handwriting-like wave
  List<ProDrawingPoint> _ballpointPoints(Size size) {
    const n = 70;
    final pts = <ProDrawingPoint>[];
    final px = size.width * 0.06;
    final w = size.width - px * 2;
    final cy = size.height / 2;
    final amp = size.height * 0.2;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final x = px + t * w;
      final y = cy + math.sin(t * math.pi * 4.0) * amp * (1.0 - t * 0.3);
      final p = (0.5 + 0.15 * math.sin(t * math.pi * 3.0)).clamp(0.3, 0.8);
      pts.add(
        ProDrawingPoint(position: Offset(x, y), pressure: p, timestamp: i),
      );
    }
    return pts;
  }

  /// Highlighter: wide, nearly-straight line
  List<ProDrawingPoint> _highlighterPoints(Size size) {
    const n = 40;
    final pts = <ProDrawingPoint>[];
    final px = size.width * 0.08;
    final w = size.width - px * 2;
    final cy = size.height / 2;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final x = px + t * w;
      final y = cy + math.sin(t * math.pi * 2.0) * 3.0;
      pts.add(
        ProDrawingPoint(position: Offset(x, y), pressure: 0.5, timestamp: i),
      );
    }
    return pts;
  }

  @override
  bool shouldRepaint(_StrokePreviewPainter old) =>
      old.penType != penType ||
      old.color != color ||
      old.baseWidth != baseWidth ||
      old.settings != settings;
}

/// Clips the child to [0, fraction * width] to create a left-to-right reveal.
class _RevealClipper extends CustomClipper<Rect> {
  final double fraction;
  _RevealClipper(this.fraction);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_RevealClipper old) => old.fraction != fraction;
}
