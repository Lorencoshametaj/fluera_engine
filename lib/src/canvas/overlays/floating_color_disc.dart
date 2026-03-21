import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

// =============================================================================
// 🎨 FLOATING COLOR DISC v3 — Iron Man HUD + Gestural Hue Control
//
// A holographic HUD indicator showing the current ink color.
// GESTURE: Trace your finger around the disc rim → changes hue in real-time.
// No tapping, no expanding. Like Tony Stark's AR interface.
//
// • Circular gesture around rim = hue rotation
// • Drag from center = reposition
// • Long-press = opens ProColorPicker
// =============================================================================

class FloatingColorDisc extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback? onExpand;
  final Offset initialPosition;
  final List<Color> recentColors;
  final double strokeSize;
  final ValueChanged<double>? onStrokeSizeChanged;

  const FloatingColorDisc({
    super.key,
    required this.color,
    required this.onColorChanged,
    this.onExpand,
    this.initialPosition = const Offset(20, 140),
    this.recentColors = const [],
    this.strokeSize = 2.0,
    this.onStrokeSizeChanged,
  });

  @override
  State<FloatingColorDisc> createState() => _FloatingColorDiscState();
}

class _FloatingColorDiscState extends State<FloatingColorDisc>
    with SingleTickerProviderStateMixin {
  late Offset _position;
  late HSVColor _hsv;

  // HUD animation
  late Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _glowPhase = 0.0;
  double _scanAngle = 0.0;

  // Gesture mode
  bool _isDragging = false;
  bool _isHueGesture = false;
  bool _isSatGesture = false;   // Vertical swipe = saturation
  bool _isSizeGesture = false;  // Horizontal swipe = stroke size
  bool _gestureDecided = false;
  Offset _gestureStartLocal = Offset.zero;
  Offset? _lastDragGlobal;

  // Live stroke size during gesture
  double _liveStrokeSize = 2.0;

  // Pulse on color change (from hue gesture)
  double _changePulse = 0.0;
  // Hue ring visibility (shows during gesture)
  double _hueRingT = 0.0;

  // Particle burst on release
  final List<_DiscParticle> _particles = [];
  double _particleT = 1.0; // 0..1 animation progress (1 = done)

  static const double _radius = 22.0;
  // Gesture zone: if pan starts within this ring, it's a hue gesture
  static const double _gestureZoneInner = 8.0;  // distance from rim inward
  static const double _gestureZoneOuter = 30.0; // distance from rim outward

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _hsv = HSVColor.fromColor(widget.color);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(FloatingColorDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color && !_isHueGesture) {
      _hsv = HSVColor.fromColor(widget.color);
      _changePulse = 1.0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) { _lastTick = elapsed; return; }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;

    bool dirty = false;

    // Idle glow
    _glowPhase += dt * 1.5;
    if (_glowPhase > 2 * math.pi) _glowPhase -= 2 * math.pi;

    // Scan line
    _scanAngle += dt * 0.8;
    if (_scanAngle > 2 * math.pi) _scanAngle -= 2 * math.pi;

    // Color change pulse
    if (_changePulse > 0) {
      _changePulse -= dt * 3.0;
      if (_changePulse < 0) _changePulse = 0;
      dirty = true;
    }

    // Hue ring fade in/out (also active during saturation/size gesture)
    final targetRing = (_isHueGesture || _isSatGesture || _isSizeGesture) ? 1.0 : 0.0;
    if ((_hueRingT - targetRing).abs() > 0.01) {
      _hueRingT += (targetRing - _hueRingT) * math.min(1.0, dt * 8);
      dirty = true;
    }

    // Particle animation
    if (_particleT < 1.0) {
      _particleT += dt * 2.0; // ~500ms to finish
      if (_particleT > 1.0) _particleT = 1.0;
      dirty = true;
    }

    if (dirty || (_glowPhase * 20 / (2 * math.pi)).floor() !=
        ((_glowPhase - dt * 1.5) * 20 / (2 * math.pi)).floor()) {
      setState(() {});
    }
  }

  void _snapToEdge() {
    final size = MediaQuery.of(context).size;
    setState(() {
      _position = Offset(
        _position.dx.clamp(8.0, size.width - 60),
        _position.dy.clamp(8.0, size.height - 60),
      );
    });
  }

  // Fixed widget size — never resizes during gesture (must fit biggest hue ring)
  static const double _fixedTotalSize = (_radius + _gestureZoneOuter + 55) * 2;
  static const double _fixedOffset = _fixedTotalSize / 2 - _radius - 12;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: _position.dx - _fixedOffset,
      bottom: _position.dy - _fixedOffset,
      child: SizedBox(
        width: _fixedTotalSize,
        height: _fixedTotalSize,
        child: GestureDetector(
          // PAN = color gesture (auto-detected: angular=hue, vertical=saturation)
          onPanStart: _onGestureStart,
          onPanUpdate: _onGestureUpdate,
          onPanEnd: _onGestureEnd,
          // LONG-PRESS + DRAG = reposition
          onLongPressStart: (d) {
            _isDragging = true;
            _lastDragGlobal = d.globalPosition;
            HapticFeedback.mediumImpact();
          },
          onLongPressMoveUpdate: (d) {
            if (_isDragging && _lastDragGlobal != null) {
              final delta = d.globalPosition - _lastDragGlobal!;
              _lastDragGlobal = d.globalPosition;
              final screenSize = MediaQuery.of(context).size;
              setState(() {
                _position = Offset(
                  (_position.dx - delta.dx).clamp(0, screenSize.width - 60),
                  (_position.dy - delta.dy).clamp(0, screenSize.height - 60),
                );
              });
            }
          },
          onLongPressEnd: (_) {
            _isDragging = false;
            _lastDragGlobal = null;
          },
          // Double-tap opens ProColorPicker (advanced editing)
          onDoubleTap: () {
            HapticFeedback.mediumImpact();
            widget.onExpand?.call();
          },
          child: CustomPaint(
            painter: _HudReadoutPainter(
              color: _isHueGesture ? _hsv.toColor() : widget.color,
              glowPhase: _glowPhase,
              scanAngle: _scanAngle,
              changePulse: _changePulse,
              radius: _radius,
              hueRingT: _hueRingT,
              currentHue: _hsv.hue,
              currentValue: _hsv.value,
              currentSaturation: _hsv.saturation,
              recentColors: widget.recentColors,
              isSaturationMode: _isSatGesture,
              isSizeMode: _isSizeGesture,
              strokeSize: _isSizeGesture ? _liveStrokeSize : widget.strokeSize,
              particles: _particles,
              particleT: _particleT,
            ),
          ),
        ),
      ),
    );
  }

  void _onGestureStart(DragStartDetails d) {
    _hsv = HSVColor.fromColor(widget.color);
    _liveStrokeSize = widget.strokeSize;
    _gestureDecided = false;
    _isHueGesture = false;
    _isSatGesture = false;
    _isSizeGesture = false;
    _gestureStartLocal = d.localPosition;
    HapticFeedback.selectionClick();
  }

  void _onGestureUpdate(DragUpdateDetails d) {
    // Phase 1: determine gesture direction from first ~15px
    if (!_gestureDecided) {
      final delta = d.localPosition - _gestureStartLocal;
      if (delta.distance < 15) return;

      final absX = delta.dx.abs();
      final absY = delta.dy.abs();
      if (absY > absX * 1.5) {
        // Predominantly vertical → saturation
        _isSatGesture = true;
        _gestureDecided = true;
        HapticFeedback.selectionClick();
      } else if (absX > absY * 1.5) {
        // Predominantly horizontal → stroke size
        _isSizeGesture = true;
        _gestureDecided = true;
        HapticFeedback.selectionClick();
      } else {
        // Angular → hue mode
        _isHueGesture = true;
        _gestureDecided = true;
      }
      return;
    }

    // Phase 2: apply gesture
    if (_isHueGesture) {
      _updateColorFromPosition(d.localPosition);
    } else if (_isSatGesture) {
      _updateSaturationFromDelta(d.delta);
    } else if (_isSizeGesture) {
      _updateSizeFromDelta(d.delta);
    }
  }

  void _updateColorFromPosition(Offset local) {
    const center = Offset(_fixedTotalSize / 2, _fixedTotalSize / 2);
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);

    final angle = math.atan2(dy, dx);
    final hue = ((angle * 180 / math.pi) + 360) % 360;
    final value = (dist / (_radius * 2.5)).clamp(0.15, 1.0);

    final prevHue = _hsv.hue;
    _hsv = _hsv.withHue(hue).withSaturation(1.0).withValue(value);

    // Snap to primary colors (every 60°)
    const primaries = [0.0, 60.0, 120.0, 180.0, 240.0, 300.0];
    for (final p in primaries) {
      final diff = (hue - p).abs();
      if (diff < 8 || diff > 352) {
        _hsv = _hsv.withHue(p);
        if ((prevHue - p).abs() > 8 && (prevHue - p).abs() < 352) {
          HapticFeedback.mediumImpact();
        }
        break;
      }
    }

    // Snap to recent colors
    for (final rc in widget.recentColors) {
      final rcHsv = HSVColor.fromColor(rc);
      final diff = (hue - rcHsv.hue).abs();
      if (rcHsv.saturation > 0.1 && (diff < 12 || diff > 348)) {
        _hsv = rcHsv.withSaturation(1.0).withValue(value);
        if ((prevHue - rcHsv.hue).abs() > 12) {
          HapticFeedback.selectionClick();
        }
        break;
      }
    }
    setState(() {});
  }

  void _updateSaturationFromDelta(Offset delta) {
    // Drag up = more saturated, drag down = less saturated
    final newSat = (_hsv.saturation - delta.dy * 0.008).clamp(0.1, 1.0);
    final prevBucket = (_hsv.saturation * 10).floor();
    _hsv = _hsv.withSaturation(newSat);
    final newBucket = (newSat * 10).floor();
    if (prevBucket != newBucket) {
      HapticFeedback.selectionClick();
    }
    setState(() {});
  }

  void _onGestureEnd(DragEndDetails d) {
    if (_isHueGesture || _isSatGesture) {
      widget.onColorChanged(_hsv.toColor());
      _changePulse = 0.8;
      HapticFeedback.mediumImpact();
      _spawnParticles(_hsv.toColor());
    } else if (_isSizeGesture) {
      widget.onStrokeSizeChanged?.call(_liveStrokeSize);
      _changePulse = 0.5;
      HapticFeedback.mediumImpact();
    }
    _isHueGesture = false;
    _isSatGesture = false;
    _isSizeGesture = false;
    _gestureDecided = false;
  }

  void _updateSizeFromDelta(Offset delta) {
    // Drag right = bigger, drag left = smaller
    final newSize = (_liveStrokeSize + delta.dx * 0.15).clamp(0.5, 30.0);
    final prevBucket = (_liveStrokeSize * 2).floor();
    _liveStrokeSize = newSize;
    final newBucket = (newSize * 2).floor();
    if (prevBucket != newBucket) {
      HapticFeedback.selectionClick();
    }
    setState(() {});
  }

  void _spawnParticles(Color color) {
    _particles.clear();
    final rng = math.Random();
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * math.pi + rng.nextDouble() * 0.4;
      _particles.add(_DiscParticle(
        angle: angle,
        speed: 40.0 + rng.nextDouble() * 60.0,
        size: 2.0 + rng.nextDouble() * 3.0,
        color: HSVColor.fromColor(color)
            .withSaturation((0.5 + rng.nextDouble() * 0.5).clamp(0.0, 1.0))
            .withValue((0.7 + rng.nextDouble() * 0.3).clamp(0.0, 1.0))
            .toColor(),
      ));
    }
    _particleT = 0.0;
  }
}

// =============================================================================
// 🎨 HUD READOUT PAINTER
// =============================================================================

class _HudReadoutPainter extends CustomPainter {
  final Color color;
  final double glowPhase;
  final double scanAngle;
  final double changePulse;
  final double radius;
  final double hueRingT; // 0 = hidden, 1 = fully visible
  final double currentHue;
  final double currentValue;
  final double currentSaturation;
  final List<Color> recentColors;
  final bool isSaturationMode;
  final bool isSizeMode;
  final double strokeSize;
  final List<_DiscParticle> particles;
  final double particleT;

  _HudReadoutPainter({
    required this.color,
    required this.glowPhase,
    required this.scanAngle,
    required this.changePulse,
    required this.radius,
    required this.hueRingT,
    required this.currentHue,
    required this.currentValue,
    required this.currentSaturation,
    required this.recentColors,
    required this.isSaturationMode,
    required this.isSizeMode,
    required this.strokeSize,
    required this.particles,
    required this.particleT,
  });

  static final List<Color> _hueColors = List.generate(
    13,
    (i) => HSVColor.fromAHSV(1, (i * 30.0) % 360, 1, 1).toColor(),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final p = Paint();

    // ── 1. HUE RING (appears during gesture) ── BIGGER & BRIGHTER
    if (hueRingT > 0.01) {
      final ringR = radius + 18 + hueRingT * 30; // Larger ring
      final ringWidth = 10.0 * hueRingT; // Thicker
      final hueRect = Rect.fromCircle(center: center, radius: ringR);
      final hueGradient = SweepGradient(colors: _hueColors);

      // Ring glow (stronger)
      p..shader = hueGradient.createShader(hueRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth + 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(center, ringR, p);

      // Ring solid
      p..maskFilter = null
        ..strokeWidth = ringWidth;
      canvas.drawCircle(center, ringR, p);
      p.shader = null;

      // Primary color tick marks (every 60°)
      for (int i = 0; i < 6; i++) {
        final tickAngle = i * 60.0 * math.pi / 180;
        final inner = ringR - ringWidth / 2 - 3;
        final outer = ringR + ringWidth / 2 + 3;
        p..color = Colors.white.withValues(alpha: 0.7 * hueRingT)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          Offset(center.dx + inner * math.cos(tickAngle),
                 center.dy + inner * math.sin(tickAngle)),
          Offset(center.dx + outer * math.cos(tickAngle),
                 center.dy + outer * math.sin(tickAngle)),
          p,
        );
      }

      // Recent color dots on ring
      for (int i = 0; i < recentColors.length && i < 6; i++) {
        final rcHsv = HSVColor.fromColor(recentColors[i]);
        if (rcHsv.saturation < 0.1) continue; // Skip grays
        final rcAngle = rcHsv.hue * math.pi / 180;
        final rcPos = Offset(
          center.dx + (ringR + ringWidth / 2 + 8) * math.cos(rcAngle),
          center.dy + (ringR + ringWidth / 2 + 8) * math.sin(rcAngle),
        );
        // Dot bg
        p..color = Colors.white.withValues(alpha: 0.6 * hueRingT)
          ..style = PaintingStyle.fill
          ..maskFilter = null;
        canvas.drawCircle(rcPos, 4.5, p);
        // Dot color fill
        p.color = recentColors[i].withValues(alpha: hueRingT);
        canvas.drawCircle(rcPos, 3.5, p);
      }

      // Hue indicator dot (current selection)
      final hueAngle = currentHue * math.pi / 180;
      final dotPos = Offset(
        center.dx + ringR * math.cos(hueAngle),
        center.dy + ringR * math.sin(hueAngle),
      );
      // Glow
      p..color = HSVColor.fromAHSV(1, currentHue, 1, 1).toColor()
          .withValues(alpha: 0.8 * hueRingT)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(dotPos, 9, p);
      // White dot
      p..color = Colors.white.withValues(alpha: hueRingT)
        ..maskFilter = null;
      canvas.drawCircle(dotPos, 7, p);
      // Color fill
      p.color = HSVColor.fromAHSV(1, currentHue, 1, 1).toColor()
          .withValues(alpha: hueRingT);
      canvas.drawCircle(dotPos, 5, p);
    }

    // ── 2. OUTER NEON GLOW ──
    final breathe = 0.25 + 0.15 * math.sin(glowPhase);
    final glowAlpha = (breathe + changePulse * 0.5).clamp(0.0, 1.0);

    p..color = color.withValues(alpha: glowAlpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 + changePulse * 4;
    canvas.drawCircle(center, radius + 3 + changePulse * 6, p);

    // ── 3. CHANGE PULSE RING ──
    if (changePulse > 0.01) {
      p..color = color.withValues(alpha: (changePulse * 0.6).clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, radius + 8 + (1 - changePulse) * 15, p);
    }

    // ── 3b. IDLE STROKE SIZE RING ── (always visible when not gesturing)
    if (hueRingT < 0.5 && strokeSize > 0.5) {
      final idleAlpha = (1.0 - hueRingT * 2).clamp(0.0, 1.0) * 0.35;
      final sizeR = radius + 2 + (strokeSize / 30.0).clamp(0.0, 1.0) * 10;
      p..color = color.withValues(alpha: idleAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (strokeSize * 0.15).clamp(0.5, 2.5)
        ..maskFilter = null;
      canvas.drawCircle(center, sizeR, p);
    }

    // ── 4. GLASS BASE ──
    p..color = const Color(0xCC0A0E1A)
      ..maskFilter = null
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, p);

    // ── 5. SCAN LINE ──
    final tickLen = radius * 0.25;
    final tickInner = radius - 2;
    final tickOuter = tickInner + tickLen;
    p..color = const Color(0x5082C8FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawLine(
      Offset(
        center.dx + tickInner * math.cos(scanAngle),
        center.dy + tickInner * math.sin(scanAngle),
      ),
      Offset(
        center.dx + tickOuter * math.cos(scanAngle),
        center.dy + tickOuter * math.sin(scanAngle),
      ),
      p,
    );
    p.maskFilter = null;

    // ── 6. INNER COLOR FILL ──
    p..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.70, p);

    // ── 7. HUD RIM ──
    p..color = const Color(0x5082C8FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius - 1, p);

    p..color = color.withValues(alpha: 0.4)
      ..strokeWidth = 0.8;
    canvas.drawCircle(center, radius * 0.70 + 2, p);

    // ── 8. IDLE HINT (subtle rainbow arc every ~5s) ──
    if (hueRingT < 0.01) {
      // Pulse a small arc hint using glowPhase
      final hintT = math.sin(glowPhase * 0.6); // Slower pulse
      if (hintT > 0.7) {
        final hintAlpha = ((hintT - 0.7) / 0.3 * 0.35).clamp(0.0, 0.35);
        final hintAngle = glowPhase * 2;
        final hintArc = math.pi * 0.4; // Short arc
        final hintRect = Rect.fromCircle(center: center, radius: radius + 4);
        final gradient = SweepGradient(
          startAngle: hintAngle,
          endAngle: hintAngle + hintArc,
          colors: [
            Colors.red.withValues(alpha: hintAlpha),
            Colors.yellow.withValues(alpha: hintAlpha),
            Colors.cyan.withValues(alpha: hintAlpha),
          ],
          stops: const [0.0, 0.5, 1.0],
        );
        p..shader = gradient.createShader(hintRect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawArc(hintRect, hintAngle, hintArc, false, p);
        p..shader = null..maskFilter = null;
      }
    }

    // ── 9. BRIGHTNESS RING (during hue gesture) ──
    if (hueRingT > 0.3 && !isSaturationMode) {
      final bAlpha = ((hueRingT - 0.3) * 1.4).clamp(0.0, 1.0);
      final bR = radius + 5;
      final bRect = Rect.fromCircle(center: center, radius: bR);
      p..color = Colors.white.withValues(alpha: 0.15 * bAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawArc(bRect, math.pi * 0.6, math.pi * 0.8, false, p);
      final vAngle = math.pi * 0.6 + math.pi * 0.8 * currentValue;
      final vPos = Offset(
        center.dx + bR * math.cos(vAngle),
        center.dy + bR * math.sin(vAngle),
      );
      p..color = Colors.white.withValues(alpha: bAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(vPos, 3.0, p);
    }

    // ── 10. COMPLEMENTARY COLOR INDICATOR ──
    if (hueRingT > 0.3 && !isSaturationMode) {
      final compHue = (currentHue + 180) % 360;
      final compAngle = compHue * math.pi / 180;
      final ringR = radius + 18 + hueRingT * 30;
      final compPos = Offset(
        center.dx + ringR * math.cos(compAngle),
        center.dy + ringR * math.sin(compAngle),
      );
      final compAlpha = (hueRingT * 0.4).clamp(0.0, 1.0);
      // Dashed circle (ghost)
      p..color = HSVColor.fromAHSV(1, compHue, 0.7, 1).toColor()
            .withValues(alpha: compAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(compPos, 6, p);
      p..maskFilter = null
        ..style = PaintingStyle.fill
        ..color = HSVColor.fromAHSV(1, compHue, 0.7, 1).toColor()
            .withValues(alpha: compAlpha * 0.5);
      canvas.drawCircle(compPos, 3, p);
    }

    // ── 11. STROKE PREVIEW (mini line in center during gesture) ──
    if (hueRingT > 0.2) {
      final previewAlpha = ((hueRingT - 0.2) * 1.25).clamp(0.0, 1.0);
      final lineLen = radius * 0.45;
      final path = Path();
      // Small wavy stroke to simulate a brush mark
      path.moveTo(center.dx - lineLen, center.dy + 2);
      path.cubicTo(
        center.dx - lineLen * 0.3, center.dy - 4,
        center.dx + lineLen * 0.3, center.dy + 4,
        center.dx + lineLen, center.dy - 2,
      );
      // Shadow (for contrast)
      p..color = Colors.black.withValues(alpha: previewAlpha * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawPath(path, p);
      // White stroke (visible on any color)
      p..color = Colors.white.withValues(alpha: previewAlpha * 0.9)
        ..strokeWidth = 2.5
        ..maskFilter = null;
      canvas.drawPath(path, p);
    }

    // ── 12. SATURATION SLIDER (during vertical swipe gesture) ──
    if (isSaturationMode && hueRingT > 0.1) {
      final sAlpha = hueRingT.clamp(0.0, 1.0);
      final sliderH = radius * 2.5;
      final sliderX = center.dx + radius + 14;
      final top = center.dy - sliderH / 2;

      // Gradient bar (desaturated at bottom, saturated at top)
      final gradRect = Rect.fromLTWH(sliderX - 4, top, 8, sliderH);
      final desatColor = HSVColor.fromAHSV(1, currentHue, 0.1, currentValue).toColor();
      final satColor = HSVColor.fromAHSV(1, currentHue, 1.0, currentValue).toColor();
      p..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [desatColor, satColor],
      ).createShader(gradRect)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(gradRect, const Radius.circular(4)),
        p,
      );
      p.shader = null;

      // Rim
      p..color = Colors.white.withValues(alpha: 0.4 * sAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(gradRect, const Radius.circular(4)),
        p,
      );

      // Indicator dot
      final satY = top + sliderH * (1.0 - currentSaturation);
      p..color = Colors.white.withValues(alpha: sAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(sliderX, satY), 5, p);
      p..color = color.withValues(alpha: sAlpha);
      canvas.drawCircle(Offset(sliderX, satY), 3.5, p);
    }

    // ── 13. PARTICLE BURST (on color release) ──
    if (particleT < 1.0 && particles.isNotEmpty) {
      final t = Curves.easeOut.transform(particleT);
      final fade = 1.0 - Curves.easeIn.transform(particleT);
      for (final particle in particles) {
        final dist = particle.speed * t;
        final px = center.dx + math.cos(particle.angle) * dist;
        final py = center.dy + math.sin(particle.angle) * dist;
        final s = particle.size * (1.0 - particleT * 0.5);
        p..color = particle.color.withValues(alpha: fade * 0.5)
          ..style = PaintingStyle.fill
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 2);
        canvas.drawCircle(Offset(px, py), s * 1.5, p);
        p..color = particle.color.withValues(alpha: fade)
          ..maskFilter = null;
        canvas.drawCircle(Offset(px, py), s, p);
      }
    }

    // ── 14. STROKE SIZE BAR (during horizontal swipe) ──
    if (isSizeMode && hueRingT > 0.1) {
      final sAlpha = hueRingT.clamp(0.0, 1.0);
      final barW = radius * 3.5;
      final barY = center.dy + radius + 20;
      final left = center.dx - barW / 2;

      // Dark background pill (visible on any canvas color)
      final barRect = Rect.fromLTWH(left - 4, barY - 8, barW + 8, 16);
      p..color = const Color(0xDD101020)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, const Radius.circular(8)), p);
      p.maskFilter = null;

      // Cyan accent rim
      p..color = const Color(0xFF82C8FF).withValues(alpha: 0.5 * sAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, const Radius.circular(8)), p);

      // Track gradient (thin→thick visual)
      final trackRect = Rect.fromLTWH(left, barY - 2, barW, 4);
      p..shader = LinearGradient(
        colors: [
          const Color(0xFF82C8FF).withValues(alpha: 0.2 * sAlpha),
          const Color(0xFF82C8FF).withValues(alpha: 0.5 * sAlpha),
        ],
      ).createShader(trackRect)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(trackRect, const Radius.circular(2)), p);
      p.shader = null;

      // Size indicator position (0.5..30 mapped to bar)
      final sizeT = ((strokeSize - 0.5) / 29.5).clamp(0.0, 1.0);
      final dotX = left + barW * sizeT;

      // Preview circle (actual stroke size, with glow)
      final previewR = (strokeSize / 2).clamp(1.5, 12.0);
      p..color = color.withValues(alpha: sAlpha * 0.4)
        ..style = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, previewR * 1.5);
      canvas.drawCircle(Offset(dotX, barY), previewR * 1.2, p);
      p..color = color.withValues(alpha: sAlpha)
        ..maskFilter = null;
      canvas.drawCircle(Offset(dotX, barY), previewR * 0.7, p);

      // Cyan indicator ring
      p..color = const Color(0xFF82C8FF).withValues(alpha: sAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(dotX, barY), previewR * 0.7 + 2, p);

      // Min/max size reference dots
      p..color = const Color(0xFF82C8FF).withValues(alpha: 0.4 * sAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(left + 3, barY), 1.5, p);
      canvas.drawCircle(Offset(left + barW - 3, barY), 4.5, p);

      // Px label text
      final label = strokeSize < 10
          ? '${strokeSize.toStringAsFixed(1)} px'
          : '${strokeSize.toStringAsFixed(0)} px';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: const Color(0xFF82C8FF).withValues(alpha: sAlpha),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(center.dx - tp.width / 2, barY + 10));
    }
  }

  @override
  bool shouldRepaint(_HudReadoutPainter old) =>
      old.color != color || old.changePulse != changePulse ||
      old.hueRingT != hueRingT || old.currentHue != currentHue ||
      old.currentValue != currentValue ||
      old.currentSaturation != currentSaturation ||
      old.isSaturationMode != isSaturationMode ||
      old.isSizeMode != isSizeMode ||
      old.strokeSize != strokeSize ||
      old.particleT != particleT ||
      (old.glowPhase * 10).floor() != (glowPhase * 10).floor();
}

// ────────────────────────────────────────────────────────────
// 💥 PARTICLE DATA
// ────────────────────────────────────────────────────────────

class _DiscParticle {
  final double angle;
  final double speed;
  final double size;
  final Color color;

  const _DiscParticle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
  });
}
