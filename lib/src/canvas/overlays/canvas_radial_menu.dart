import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

// =============================================================================
// 🎯 RADIAL CONTEXT MENU v4 — Performance Optimized
//
// Optimizations over unoptimized v4:
// 1. 8 AnimationControllers → 1 Ticker + manual interpolation
// 2. Cached TextPainters for icons/labels (avoid 16+ allocs/frame)
// 3. Cached arc Paths (rebuild only on geometry change)
// 4. Circular buffer for trail points (O(1) vs O(n) shift)
// 5. Smart shouldRepaint with value comparison
// 6. RepaintBoundary wrapper
// 7. Single ValueNotifier for tick instead of Listenable.merge
// 8. Minimized Paint.maskFilter toggling
// =============================================================================

enum RadialMenuItem {
  brush('Brush', Icons.brush_rounded, Color(0xFF64B5F6)),
  text('Text', Icons.text_fields_rounded, Color(0xFFA87FDB)),
  insert('Insert', Icons.add_circle_outline_rounded, Color(0xFFE8A84C)),
  shape('Shape', Icons.hexagon_rounded, Color(0xFF6BCB7F)),
  undo('Undo', Icons.undo_rounded, Color(0xFFEF9A9A)),
  tools('Tools', Icons.build_rounded, Color(0xFF80CBC4)),
  knowledgeMap('Map', Icons.hub_rounded, Color(0xFF7EC8E3));

  const RadialMenuItem(this.label, this.icon, this.accent);
  final String label;
  final IconData icon;
  final Color accent;

  HapticType get hapticType {
    switch (this) {
      case RadialMenuItem.undo: return HapticType.heavy;
      case RadialMenuItem.brush:
      case RadialMenuItem.tools:
      case RadialMenuItem.shape:
      case RadialMenuItem.text: return HapticType.medium;
      case RadialMenuItem.insert:
      case RadialMenuItem.knowledgeMap: return HapticType.light;
    }
  }

  int get toolModeIndex {
    switch (this) {
      case RadialMenuItem.brush: return 0;
      case RadialMenuItem.text: return 1;
      case RadialMenuItem.shape: return 3;
      default: return -1;
    }
  }

  /// Whether this sector opens a sub-ring
  bool get hasSubRing => this == brush || this == insert || this == tools;
}

enum HapticType { light, medium, heavy }

enum RadialBrushItem {
  pen('Pen', Icons.edit_rounded),
  pencil('Pencil', Icons.create_rounded),
  marker('Marker', Icons.format_paint_rounded),
  highlighter('Highlighter', Icons.highlight_rounded),
  charcoal('Charcoal', Icons.texture_rounded),
  watercolor('Watercolor', Icons.water_drop_rounded),
  airbrush('Airbrush', Icons.blur_circular_rounded),
  oil('Oil', Icons.brush_rounded);

  const RadialBrushItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum RadialInsertItem {
  image('Image', Icons.image_rounded),
  pdf('PDF', Icons.picture_as_pdf_rounded),
  latex('LaTeX', Icons.functions_rounded),
  audio('Record', Icons.mic_rounded),
  recordings('Recordings', Icons.headphones_rounded);

  const RadialInsertItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum RadialToolItem {
  lasso('Lasso', Icons.content_cut_rounded),
  ruler('Ruler', Icons.straighten_rounded);

  const RadialToolItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

class RadialMenuResult {
  final RadialMenuItem? item;
  final RadialBrushItem? brushItem;
  final RadialInsertItem? insertItem;
  final RadialToolItem? toolItem;
  final Color? selectedColor;
  final bool eyedropper;
  final bool quickRepeat;

  const RadialMenuResult({this.item, this.brushItem, this.insertItem,
      this.toolItem, this.selectedColor,
      this.eyedropper = false, this.quickRepeat = false});
  const RadialMenuResult.dismiss()
      : item = null, brushItem = null, insertItem = null, toolItem = null,
        selectedColor = null, eyedropper = false, quickRepeat = false;
  const RadialMenuResult.repeat()
      : item = null, brushItem = null, insertItem = null, toolItem = null,
        selectedColor = null, eyedropper = false, quickRepeat = true;
}

// =============================================================================
// ⏱️ MANUAL ANIMATION STATE — replaces 8 AnimationControllers with 1 Ticker
// =============================================================================

class _AnimState {
  double entrance = 0;    // 0→1, 320ms easeOutBack
  double exit = 0;        // 0→1, 150ms
  double subRing = 0;     // 0→1, 180ms
  double iconBounce = 0;  // 0→1, 200ms elasticOut
  double idlePulse = 0;   // 0→1→0, 800ms repeat
  double particle = 0;    // 0→1, 600ms oneshot
  double orbit = 0;       // 0→∞, continuous
  double pulse = 0;       // 0→∞, continuous 1500ms cycle

  // Targets for forward/reverse
  bool entranceForward = true;
  bool exitForward = false;
  bool subRingForward = false;
  bool subRingReverse = false;
  bool iconBounceActive = false;
  bool idlePulseActive = false;

  // Durations (seconds)
  static const double dEntrance = 0.320;
  static const double dExit = 0.150;
  static const double dSubRing = 0.180;
  static const double dBounce = 0.200;
  static const double dIdlePulse = 0.800;
  static const double dParticle = 0.600;

  /// Advance all animations by [dt] seconds. Returns true if any changed.
  bool tick(double dt) {
    bool changed = false;

    // Entrance
    if (entranceForward && entrance < 1) {
      entrance = (entrance + dt / dEntrance).clamp(0, 1);
      changed = true;
    }

    // Exit
    if (exitForward && exit < 1) {
      exit = (exit + dt / dExit).clamp(0, 1);
      changed = true;
    }

    // Sub-ring
    if (subRingForward && subRing < 1) {
      subRing = (subRing + dt / dSubRing).clamp(0, 1);
      changed = true;
    } else if (subRingReverse && subRing > 0) {
      subRing = (subRing - dt / dSubRing).clamp(0, 1);
      changed = true;
      if (subRing <= 0) subRingReverse = false;
    }

    // Icon bounce
    if (iconBounceActive && iconBounce < 1) {
      iconBounce = (iconBounce + dt / dBounce).clamp(0, 1);
      changed = true;
      if (iconBounce >= 1) iconBounceActive = false;
    }

    // Idle pulse (ping-pong)
    if (idlePulseActive) {
      idlePulse += dt / dIdlePulse;
      if (idlePulse > 2) idlePulse -= 2;
      changed = true;
    }

    // Particle (one-shot)
    if (particle < 1) {
      particle = (particle + dt / dParticle).clamp(0, 1);
      changed = true;
    }

    // Continuous: orbit, pulse (always run)
    orbit += dt;
    pulse += dt;
    changed = true; // pulse needs repaint

    return changed;
  }

  double get idlePulseValue => idlePulseActive
      ? (idlePulse <= 1 ? idlePulse : 2 - idlePulse).clamp(0, 1)
      : 0;

  double get pulseNorm => (pulse % 1.5) / 1.5;
  double get orbitNorm => orbit;
}

// =============================================================================
// 🔄 CIRCULAR TRAIL BUFFER — O(1) add, O(1) access
// =============================================================================

class _TrailBuffer {
  static const int capacity = 14;
  final List<Offset> _buf = List.filled(capacity, Offset.zero);
  int _head = 0;
  int _count = 0;

  void add(Offset p) {
    _buf[_head] = p;
    _head = (_head + 1) % capacity;
    if (_count < capacity) _count++;
  }

  int get length => _count;

  Offset operator [](int i) {
    assert(i >= 0 && i < _count);
    return _buf[(_head - _count + i) % capacity];
  }

  List<Offset> toList() {
    if (_count == 0) return const [];
    final list = <Offset>[];
    for (int i = 0; i < _count; i++) list.add(this[i]);
    return list;
  }
}

// =============================================================================
// WIDGET
// =============================================================================

class CanvasRadialMenu extends StatefulWidget {
  final Offset center;
  final List<Color> recentColors;
  final int currentBrushIndex;
  final Color currentColor;
  final bool canUndo;
  final bool canRedo;
  final bool isPanMode;
  final ValueChanged<RadialMenuResult> onResult;
  final Size screenSize;
  final int activeTool;
  final int undoCount;
  final bool hasLastAction;

  const CanvasRadialMenu({
    super.key,
    required this.center,
    required this.onResult,
    this.recentColors = const [],
    this.currentBrushIndex = 0,
    this.currentColor = Colors.white,
    this.canUndo = true,
    this.canRedo = false,
    this.isPanMode = false,
    this.screenSize = Size.zero,
    this.activeTool = 0,
    this.undoCount = 0,
    this.hasLastAction = false,
  });

  @override
  State<CanvasRadialMenu> createState() => CanvasRadialMenuState();
}

class CanvasRadialMenuState extends State<CanvasRadialMenu>
    with SingleTickerProviderStateMixin {
  // ⏱️ OPT #1: Single Ticker instead of 8 AnimationControllers
  late final Ticker _ticker;
  final _anim = _AnimState();
  Duration _lastTick = Duration.zero;
  final _repaintNotifier = ValueNotifier<int>(0); // OPT #7

  int _hoveredSector = -1;
  bool _isSubRingOpen = false;
  RadialMenuItem? _subRingParent;
  int _hoveredSubSector = -1;
  Offset _fingerPos = Offset.zero;
  bool _isExiting = false;
  RadialMenuResult? _pendingResult;
  bool _isInDeadZone = true;
  DateTime _deadZoneEnteredAt = DateTime.now();
  Offset? _prevFingerPos;
  int _lastFingerTime = 0; // For flick-to-select velocity tracking
  Offset _flickVelocity = Offset.zero;

  // OPT #4: Circular trail buffer
  final _trail = _TrailBuffer();

  late final List<_Particle> _particles;
  late Offset _effectiveCenter;

  // OPT #2: Cached TextPainters
  final Map<int, TextPainter> _iconCache = {};
  final Map<String, TextPainter> _labelCache = {};

  List<Path>? _arcPaths;
  int _arcPathsHash = -1;

  // Screen size for sub-ring edge clamping
  Size _screenSize = Size.zero;

  // ── Responsive dimensions: scales down on phones ──
  // Base values (for tablets, shortestSide >= 500)
  static const double _baseArcInner = 68.0, _baseArcOuter = 146.0;
  static const double _baseSubR = 175.0;
  static const double _baseDeadZone = 25.0;
  static const double _basePrimaryRadius = 110.0;

  // Computed responsive values (updated in build)
  double _sf = 1.0; // scale factor
  double get _arcInner => _baseArcInner * _sf;
  double get _arcOuter => _baseArcOuter * _sf;
  double get _subR => _baseSubR * _sf;
  double get _deadZone => _baseDeadZone * _sf;
  double get _primaryRadius => _basePrimaryRadius * _sf;

  static const int N = 7;
  static const double _sa = 2 * math.pi / N;
  static const double _s0 = -math.pi / 2;
  static const double _gap = 3.0 * math.pi / 180;

  @override
  void initState() {
    super.initState();
    _effectiveCenter = widget.center;

    _ticker = createTicker(_onTick)..start();

    final rng = math.Random(42);
    _particles = List.generate(24, (i) {
      final a = rng.nextDouble() * 2 * math.pi;
      final sp = 60.0 + rng.nextDouble() * 120.0;
      final sz = 1.5 + rng.nextDouble() * 2.5;
      return _Particle(angle: a, speed: sp, size: sz,
          color: HSLColor.fromAHSL(1, 200 + rng.nextDouble() * 60, 0.6, 0.7).toColor());
    });

    _fingerPos = _effectiveCenter;
    _lastFingerTime = DateTime.now().microsecondsSinceEpoch;
    HapticFeedback.mediumImpact();
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;

    if (_anim.tick(dt)) {
      _repaintNotifier.value++;
    }

    // Check exit animation completion
    if (_isExiting && _anim.exit >= 1.0 && _pendingResult != null) {
      _ticker.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onResult(_pendingResult!);
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaintNotifier.dispose();
    for (final tp in _iconCache.values) tp.dispose();
    for (final tp in _labelCache.values) tp.dispose();
    super.dispose();
  }

  int _sectorFromAngle(double angle) {
    double rel = angle - _s0;
    if (rel < 0) rel += 2 * math.pi;
    return (rel / _sa).floor() % N;
  }

  /// 🎯 Public: called externally from long-press move events.
  void updateFinger(Offset globalPos) {
    if (_isExiting) return;

    final now = DateTime.now().microsecondsSinceEpoch;
    final dt = (now - _lastFingerTime) / 1000000.0; // in seconds
    _lastFingerTime = now;

    // Track flick velocity
    if (_prevFingerPos != null && dt > 0.001) {
      final delta = globalPos - _prevFingerPos!;
      final instV = delta / dt;
      // Exponential moving average for smooth velocity
      _flickVelocity = Offset(
        _flickVelocity.dx * 0.4 + instV.dx * 0.6,
        _flickVelocity.dy * 0.4 + instV.dy * 0.6,
      );
    }

    _prevFingerPos = _fingerPos;
    _fingerPos = globalPos;
    _trail.add(globalPos);

    final dx = globalPos.dx - _effectiveCenter.dx;
    final dy = globalPos.dy - _effectiveCenter.dy;
    final dist = math.sqrt(dx * dx + dy * dy);

    // Cancel swipe (moved back towards center rapidly)
    if (_prevFingerPos != null && dist < _deadZone) {
      final pd = _prevFingerPos! - _effectiveCenter;
      if (pd.distance > _primaryRadius * 0.5) {
        _triggerExit(const RadialMenuResult.dismiss());
        return;
      }
    }

    if (dist < _deadZone) {
      if (!_isInDeadZone) {
        _isInDeadZone = true;
        _deadZoneEnteredAt = DateTime.now();
      } else if (!_anim.idlePulseActive &&
          DateTime.now().difference(_deadZoneEnteredAt) > const Duration(seconds: 1)) {
        _anim.idlePulseActive = true;
      }
      _hoveredSector = -1;
      _hoveredSubSector = -1;
      _repaintNotifier.value++;
      return;
    }

    if (_isInDeadZone) {
      _isInDeadZone = false;
      _anim.idlePulseActive = false;
      _anim.idlePulse = 0;
    }

    final angle = math.atan2(dy, dx);

    // ⚡ FLICK-TO-SELECT TRIGGER (Velocity > 1500px/s outwards)
    // High threshold to avoid accidental triggers — only intentional fast swipes
    if (dist > _deadZone && _flickVelocity.distance > 1500) {
      // Ensure flick is roughly pointing outward, not tangential
      final flickAngle = math.atan2(_flickVelocity.dy, _flickVelocity.dx);
      // Diff between finger position angle and flick velocity angle
      final angleDiff = (angle - flickAngle).abs() % (2 * math.pi);
      final normalizedDiff = angleDiff > math.pi ? 2 * math.pi - angleDiff : angleDiff;

      // If moving outward (within 45 degrees of radial vector)
      if (normalizedDiff < math.pi / 4) {
        final flickSector = _sectorFromAngle(flickAngle);
        final item = RadialMenuItem.values[flickSector];

        // ⚠️ Skip flick-to-select for sectors with sub-rings (Brush, Color, Insert, Tools)
        // Those open a sub-menu — the user needs to browse sub-items, not select the parent.
        if (!item.hasSubRing) {
          _hoveredSector = flickSector;
          // Fire haptic immediately
          switch (item.hapticType) {
            case HapticType.heavy: HapticFeedback.heavyImpact(); break;
            case HapticType.medium: HapticFeedback.mediumImpact(); break;
            case HapticType.light: HapticFeedback.lightImpact(); break;
          }
          // Early exit — instantaneous selection without waiting for release
          release(); 
          return;
        }
      }
    }

    if (_isSubRingOpen && dist > _primaryRadius + 10 && _subRingParent != null) {
      // Use shared position computation (edge-clamped)
      final positions = _subItemPositions();
      final subCount = positions.length;

      int bestIdx = -1;
      double bestDist = double.infinity;
      for (int i = 0; i < subCount; i++) {
        final d = (globalPos - positions[i]).distance;
        if (d < bestDist) { bestDist = d.abs(); bestIdx = i; }
      }
      if (bestDist < 35) {
        if (bestIdx != _hoveredSubSector) {
          _hoveredSubSector = bestIdx;
          _hoveredSector = -1;
          HapticFeedback.selectionClick();
        }
      }
    } else if (dist > _deadZone) {
      final newSector = _sectorFromAngle(angle);
      if (newSector != _hoveredSector) {
        _hoveredSector = newSector;
        _hoveredSubSector = -1;
        _anim.iconBounce = 0;
        _anim.iconBounceActive = true;
        _arcPaths = null; // invalidate cache

        final item = RadialMenuItem.values[newSector];
        switch (item.hapticType) {
          case HapticType.heavy: HapticFeedback.heavyImpact(); break;
          case HapticType.medium: HapticFeedback.mediumImpact(); break;
          case HapticType.light: HapticFeedback.selectionClick(); break;
        }

        if (item.hasSubRing) {
          if (!_isSubRingOpen || _subRingParent != item) {
            _isSubRingOpen = true;
            _subRingParent = item;
            _anim.subRingForward = true;
            _anim.subRingReverse = false;
            _anim.subRing = 0;
          }
        } else if (_isSubRingOpen) {
          _isSubRingOpen = false;
          _subRingParent = null;
          _anim.subRingForward = false;
          _anim.subRingReverse = true;
        }
      }
    }

    _repaintNotifier.value++;
  }

  void _triggerExit(RadialMenuResult result) {
    if (_isExiting) return;
    _isExiting = true;
    _pendingResult = result;
    _anim.exitForward = true;
    if (result.item != null || result.eyedropper || result.quickRepeat) {
      HapticFeedback.lightImpact();
    }
  }

  /// 🎯 Public: called externally from long-press end events.
  void release() {
    if (_isExiting) return;
    RadialMenuResult result;

    if (_isSubRingOpen && _hoveredSubSector >= 0) {
      if (_subRingParent == RadialMenuItem.brush) {
        result = RadialMenuResult(item: RadialMenuItem.brush,
            brushItem: RadialBrushItem.values[_hoveredSubSector % RadialBrushItem.values.length]);
      } else if (_subRingParent == RadialMenuItem.insert) {
        result = RadialMenuResult(item: RadialMenuItem.insert,
            insertItem: RadialInsertItem.values[_hoveredSubSector % RadialInsertItem.values.length]);
      } else if (_subRingParent == RadialMenuItem.tools) {
        result = RadialMenuResult(item: RadialMenuItem.tools,
            toolItem: RadialToolItem.values[_hoveredSubSector % RadialToolItem.values.length]);
      } else {
        result = const RadialMenuResult.dismiss();
      }
    } else if (_hoveredSector >= 0) {
      result = RadialMenuResult(item: RadialMenuItem.values[_hoveredSector]);
    } else if (_isInDeadZone && widget.hasLastAction) {
      result = const RadialMenuResult.repeat();
    } else {
      result = const RadialMenuResult.dismiss();
    }

    _triggerExit(result);
  }

  List<Color> get _effectiveSubColors {
    final r = widget.recentColors.take(6).toList();
    while (r.length < 7) r.add(Colors.transparent);
    return r;
  }

  // ── OPT #2: TextPainter cache ──
  TextPainter _getIconPainter(IconData icon, Color color, double size) {
    final key = icon.codePoint ^ color.toARGB32() ^ size.hashCode;
    return _iconCache.putIfAbsent(key, () => TextPainter(
      text: TextSpan(text: String.fromCharCode(icon.codePoint),
          style: TextStyle(fontFamily: icon.fontFamily,
              package: icon.fontPackage, fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
    )..layout());
  }

  TextPainter _getLabelPainter(String text, Color color, double size,
      {FontWeight weight = FontWeight.w700}) {
    final key = '$text|${color.toARGB32()}|$size|${weight.index}';
    return _labelCache.putIfAbsent(key, () => TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size,
          fontWeight: weight, color: color, letterSpacing: size < 10 ? 0.3 : 0.5)),
      textDirection: TextDirection.ltr,
    )..layout());
  }

  // ── OPT #3: Arc path cache ──
  List<Path> _getArcPaths() {
    final hash = _hoveredSector ^ (_isSubRingOpen ? 1000 : 0) ^
        (_subRingParent?.index ?? 99) ^ (_anim.subRing * 100).toInt();
    if (_arcPaths != null && _arcPathsHash == hash) return _arcPaths!;

    final paths = <Path>[];
    final outerR = Rect.fromCircle(center: _effectiveCenter, radius: _arcOuter);
    final innerR = Rect.fromCircle(center: _effectiveCenter, radius: _arcInner);

    for (int i = 0; i < N; i++) {
      double startA = _s0 + i * _sa + _gap / 2;
      double sweepA = _sa - _gap;
      final item = RadialMenuItem.values[i];

      // Morphing: widen parent arc when sub-ring open
      if (_isSubRingOpen && _subRingParent == item && _anim.subRing > 0) {
        final expand = 0.08 * _anim.subRing;
        startA -= expand;
        sweepA += expand * 2;
      }

      paths.add(Path()
        ..addArc(outerR, startA, sweepA)
        ..arcTo(innerR, startA + sweepA, -sweepA, false)
        ..close());
    }

    _arcPaths = paths;
    _arcPathsHash = hash;
    return paths;
  }

  // ── Screen-safe sub-item positions (shared between hit-test and painter) ──
  List<Offset> _subItemPositions() {
    if (_subRingParent == null) return const [];
    final parentIdx = RadialMenuItem.values.indexOf(_subRingParent!);
    final parentAngle = _s0 + parentIdx * _sa + _sa / 2;
    final isBrush = _subRingParent == RadialMenuItem.brush;
    final isInsert = _subRingParent == RadialMenuItem.insert;
    final isTools = _subRingParent == RadialMenuItem.tools;
    final subCount = isBrush ? RadialBrushItem.values.length
        : isInsert ? RadialInsertItem.values.length
        : isTools ? RadialToolItem.values.length
        : 0;
    final fanSpread = math.min(math.pi * 0.7, subCount * 0.32);
    final step = fanSpread / math.max(subCount - 1, 1);
    final fanStart = parentAngle - fanSpread / 2;
    final r = _arcOuter + 8 + (_subR - _arcOuter - 8) * _anim.subRing;

    const edgeMargin = 22.0;
    final maxX = _screenSize.width > 0 ? _screenSize.width - edgeMargin : double.infinity;
    final maxY = _screenSize.height > 0 ? _screenSize.height - edgeMargin : double.infinity;

    final positions = <Offset>[];
    for (int i = 0; i < subCount; i++) {
      final angle = fanStart + i * step;
      // Orbit offset
      final orbitOff = math.sin(_anim.orbitNorm * 2 * math.pi / 2.4 + i * 0.8) * 3.0;
      double cx = _effectiveCenter.dx + math.cos(angle) * r + math.cos(angle + math.pi / 2) * orbitOff;
      double cy = _effectiveCenter.dy + math.sin(angle) * r + math.sin(angle + math.pi / 2) * orbitOff;

      // Clamp to screen edges
      cx = cx.clamp(edgeMargin, maxX);
      cy = cy.clamp(edgeMargin, maxY);

      positions.add(Offset(cx, cy));
    }
    return positions;
  }

  @override
  Widget build(BuildContext context) {
    final ss = widget.screenSize == Size.zero
        ? MediaQuery.of(context).size : widget.screenSize;
    _effectiveCenter = _clamp(widget.center, ss);
    _screenSize = ss;

    // Responsive scale: 0.72 on small phones → 1.0 on tablets
    final shortest = ss.shortestSide;
    _sf = (shortest / 500).clamp(0.72, 1.0);

    // 🔧 FIX: Use Listener instead of GestureDetector.
    // The radial menu appears WHILE the finger is already down (from long-press).
    // GestureDetector.onPanUpdate requires onPanStart on itself → never fires.
    // Listener receives raw PointerEvents regardless of where the gesture started.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerMove: (e) => updateFinger(e.position),
      onPointerUp: (_) => release(),
      onPointerCancel: (_) => _triggerExit(const RadialMenuResult.dismiss()),
      // OPT #7: Single ValueNotifier instead of Listenable.merge
      child: ValueListenableBuilder<int>(
        valueListenable: _repaintNotifier,
        builder: (context, _, __) {
          final eT = Curves.easeOutBack.transform(_anim.entrance.clamp(0, 1));
          final xT = _isExiting ? _anim.exit : 0.0;
          final scale = eT * (1.0 - xT * 0.3);
          final alpha = eT * (1.0 - xT);
          if (alpha <= 0.01) return const SizedBox.shrink();

          final blurR = (_isSubRingOpen ? _subR + 60 : _arcOuter + 25) * scale;
          final arcPaths = _getArcPaths();

          return Stack(children: [
            Positioned.fill(child: ClipPath(
              clipper: _CircleClipper(center: _effectiveCenter, radius: blurR),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20 * alpha, sigmaY: 20 * alpha),
                child: Container(color: Colors.transparent),
              ),
            )),
            // OPT #6: RepaintBoundary
            RepaintBoundary(
              child: CustomPaint(
                painter: _PainterV4Opt(
                  center: _effectiveCenter, scale: scale, alpha: alpha,
                  ri: _arcInner, ro: _arcOuter,
                  stagger: _anim.entrance,
                  subRing: _anim.subRing, pulseNorm: _anim.pulseNorm,
                  bounce: _anim.iconBounce,
                  idlePulse: _anim.idlePulseValue,
                  particleT: _anim.particle,
                  orbitT: _anim.orbitNorm,
                  hovered: _hoveredSector, hoveredSub: _hoveredSubSector,
                  isSubOpen: _isSubRingOpen, subParent: _subRingParent,
                  colors: _effectiveSubColors,
                  brushIdx: widget.currentBrushIndex,
                  curColor: widget.currentColor,
                  finger: _fingerPos,
                  trail: _trail.toList(),
                  canUndo: widget.canUndo, particles: _particles,
                  activeTool: widget.activeTool,
                  undoCount: widget.undoCount,
                  hasLastAction: widget.hasLastAction,
                  arcPaths: arcPaths,
                  subPositions: _isSubRingOpen ? _subItemPositions() : const [],
                  getIcon: _getIconPainter,
                  getLabel: _getLabelPainter,
                ),
                size: Size.infinite,
              ),
            ),
          ]);
        },
      ),
    );
  }

  Offset _clamp(Offset p, Size s) {
    final m = _arcOuter + 20;
    return Offset(p.dx.clamp(m, s.width - m), p.dy.clamp(m, s.height - m));
  }
}

// =============================================================================
// SUPPORT CLASSES
// =============================================================================

class _Particle {
  final double angle, speed, size;
  final Color color;
  const _Particle({required this.angle, required this.speed,
      required this.size, required this.color});
}

class _CircleClipper extends CustomClipper<Path> {
  final Offset center; final double radius;
  _CircleClipper({required this.center, required this.radius});
  @override Path getClip(Size s) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  @override bool shouldReclip(covariant _CircleClipper o) =>
      center != o.center || radius != o.radius;
}

// =============================================================================
// 🎨 PAINTER v4 OPTIMIZED
// =============================================================================

class _PainterV4Opt extends CustomPainter {
  final Offset center;
  final double scale, alpha, stagger, subRing, pulseNorm, bounce;
  final double idlePulse, particleT, orbitT;
  final int hovered, hoveredSub;
  final bool isSubOpen;
  final RadialMenuItem? subParent;
  final List<Color> colors;
  final int brushIdx;
  final Color curColor;
  final Offset finger;
  final List<Offset> trail;
  final bool canUndo;
  final List<_Particle> particles;
  final int activeTool;
  final int undoCount;
  final bool hasLastAction;
  final List<Path> arcPaths;
  final List<Offset> subPositions;
  final TextPainter Function(IconData, Color, double) getIcon;
  final TextPainter Function(String, Color, double, {FontWeight weight}) getLabel;

  _PainterV4Opt({
    required this.center, required this.scale, required this.alpha,
    required this.ri, required this.ro,
    required this.stagger, required this.subRing, required this.pulseNorm,
    required this.bounce, required this.idlePulse, required this.particleT,
    required this.orbitT, required this.hovered, required this.hoveredSub,
    required this.isSubOpen, required this.subParent, required this.colors,
    required this.brushIdx, required this.curColor, required this.finger,
    required this.trail, required this.canUndo, required this.particles,
    required this.activeTool, required this.undoCount, required this.hasLastAction,
    required this.arcPaths, required this.subPositions,
    required this.getIcon, required this.getLabel,
  });

  static const int N = 7;
  static const double _sa = 2 * math.pi / N;
  static const double _s0 = -math.pi / 2;
  final double ri, ro;

  final _p = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0.01) return;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);

    final a = (alpha * 255).toInt().clamp(0, 255);

    _paintTrail(canvas, a);

    _p..color = Color.fromARGB((a * 0.7).toInt(), 8, 8, 18)
      ..style = PaintingStyle.fill..maskFilter = null;
    canvas.drawCircle(center, ro + 10, _p);

    // ✨ IRON MAN GLOW: Holographic outer ring with breathing pulse
    final glowPhase = math.sin(pulseNorm * 2 * math.pi);
    final glowAlpha = (0.15 + 0.08 * glowPhase) * alpha;
    // Outer neon ring
    _p..color = Color.fromARGB((glowAlpha * 255).toInt(), 80, 200, 255)
      ..style = PaintingStyle.stroke..strokeWidth = 2.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);
    canvas.drawCircle(center, ro + 6, _p);
    // Inner glow ring
    _p..color = Color.fromARGB(((glowAlpha * 0.6) * 255).toInt(), 120, 220, 255)
      ..strokeWidth = 1.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
    canvas.drawCircle(center, ri - 4, _p);
    // Radial scan line (rotating)
    final scanAngle = orbitT * 2 * math.pi / 3.0;
    final scanStart = Offset(center.dx + math.cos(scanAngle) * (ri + 5),
        center.dy + math.sin(scanAngle) * (ri + 5));
    final scanEnd = Offset(center.dx + math.cos(scanAngle) * (ro + 2),
        center.dy + math.sin(scanAngle) * (ro + 2));
    _p..color = Color.fromARGB(((glowAlpha * 0.5) * 255).toInt(), 100, 220, 255)
      ..strokeWidth = 1.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawLine(scanStart, scanEnd, _p);
    _p.maskFilter = null;

    _paintParticles(canvas, a);
    _paintConnectors(canvas, a);

    if (idlePulse > 0.01) {
      _p..color = Color.fromARGB((a * 0.15 * idlePulse).toInt(), 100, 180, 255)
        ..style = PaintingStyle.stroke..strokeWidth = 3.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
      canvas.drawCircle(center, (ri + ro) / 2, _p);
      _p.maskFilter = null;
    }

    // Breadcrumb
    if (isSubOpen && subParent != null) {
      final pi = RadialMenuItem.values.indexOf(subParent!);
      final pa = _s0 + pi * _sa + _sa / 2;
      _p..color = subParent!.accent.withValues(alpha: 0.25 * subRing)
        ..style = PaintingStyle.stroke..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
      canvas.drawLine(
        Offset(center.dx + math.cos(pa) * 20, center.dy + math.sin(pa) * 20),
        Offset(center.dx + math.cos(pa) * ro, center.dy + math.sin(pa) * ro),
        _p,
      );
      _p.maskFilter = null;
    }

    for (int i = 0; i < N; i++) _paintArc(canvas, i, a);
    if (isSubOpen && subRing > 0.01) _paintSubRing(canvas, a);

    _p..color = Color.fromARGB(a ~/ 6, 100, 180, 255)
      ..style = PaintingStyle.stroke..strokeWidth = 1.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawCircle(center, ro + 5, _p);
    _p.maskFilter = null;

    _paintCenter(canvas, a);
    canvas.restore();
  }

  void _paintParticles(Canvas c, int a) {
    if (particleT >= 1.0) return;
    final t = Curves.easeOut.transform(particleT);
    final fade = 1.0 - Curves.easeIn.transform(particleT);
    for (final p in particles) {
      final d = p.speed * t;
      _p..color = p.color.withValues(alpha: fade * alpha * 0.6)
        ..style = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size);
      c.drawCircle(Offset(center.dx + math.cos(p.angle) * d,
          center.dy + math.sin(p.angle) * d), p.size, _p);
    }
    _p.maskFilter = null;
  }

  void _paintTrail(Canvas c, int a) {
    if (trail.length < 2) return;
    final gc = hovered >= 0
        ? RadialMenuItem.values[hovered].accent : const Color(0xFF64B5F6);

    // Outer neon glow trail
    for (int i = 1; i < trail.length; i++) {
      final t = i / trail.length;
      final r = 3.0 + t * 8.0;
      _p..color = gc.withValues(alpha: t * alpha * 0.2)
        ..style = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.5);
      c.drawCircle(trail[i], r * 0.6, _p);
    }

    // Inner bright core trail
    for (int i = 1; i < trail.length; i++) {
      final t = i / trail.length;
      final r = 1.0 + t * 3.0;
      _p..color = Colors.white.withValues(alpha: t * alpha * 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r);
      c.drawCircle(trail[i], r * 0.3, _p);
    }

    // Bright tip dot (laser pointer)
    if (trail.isNotEmpty) {
      _p..color = gc.withValues(alpha: alpha * 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      c.drawCircle(trail.last, 4, _p);
      _p..color = Colors.white.withValues(alpha: alpha * 0.8)
        ..maskFilter = null;
      c.drawCircle(trail.last, 2, _p);
    }

    _p.maskFilter = null;
  }

  void _paintConnectors(Canvas c, int a) {
    final pa = 0.06 + 0.05 * math.sin(pulseNorm * 2 * math.pi);
    for (int i = 0; i < N; i++) {
      final angle = _s0 + i * _sa + _sa / 2;
      final h = i == hovered;
      final st = _stagger(i);
      if (st < 0.1) continue;
      _p..color = RadialMenuItem.values[i].accent.withValues(
          alpha: (h ? 0.45 : pa) * st)
        ..style = PaintingStyle.stroke..strokeWidth = h ? 2.0 : 0.8
        ..maskFilter = null;
      c.drawLine(
        Offset(center.dx + math.cos(angle) * 18, center.dy + math.sin(angle) * 18),
        Offset(center.dx + math.cos(angle) * (ri - 4),
            center.dy + math.sin(angle) * (ri - 4)),
        _p,
      );
    }
  }

  void _paintArc(Canvas c, int i, int a) {
    final item = RadialMenuItem.values[i];
    final h = i == hovered;
    final st = _stagger(i);
    if (st < 0.01) return;
    final sa = (a * st).toInt().clamp(0, 255);
    final isActive = item.toolModeIndex >= 0 && item.toolModeIndex == activeTool;

    // ✨ IRON MAN EXPAND: sectors grow from center during stagger
    final expandT = Curves.easeOutCubic.transform(st.clamp(0, 1));
    final eRi = ri * expandT;
    final eRo = ri + (ro - ri) * expandT;

    // Build expanding path (can't use cached path during animation)
    final Path path;
    if (expandT >= 0.99) {
      path = arcPaths[i]; // fully expanded — use cached
    } else {
      // Dynamic path with expanding radii
      final startA = _s0 + i * _sa + (3.0 * math.pi / 180);
      final sweepA = _sa - 2 * (3.0 * math.pi / 180);
      path = Path()
        ..arcTo(Rect.fromCircle(center: center, radius: eRo), startA, sweepA, true)
        ..arcTo(Rect.fromCircle(center: center, radius: eRi), startA + sweepA, -sweepA, false)
        ..close();
    }

    if (isActive && !h) {
      _p..color = item.accent.withValues(alpha: 0.12 * st)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      c.drawPath(path, _p);
      _p.maskFilter = null;
    }

    if (h) {
      _p..color = item.accent.withValues(alpha: 0.25 * st)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);
      c.drawPath(path, _p);
      _p.maskFilter = null;
      _p..color = item.accent.withValues(alpha: 0.18 * st)..style = PaintingStyle.fill;
      c.drawPath(path, _p);
      _p..color = item.accent.withValues(alpha: 0.8 * st)
        ..style = PaintingStyle.stroke..strokeWidth = 2.0;
      c.drawPath(path, _p);
    } else {
      _p..color = Color.fromARGB(sa ~/ 3, 18, 18, 35)..style = PaintingStyle.fill;
      c.drawPath(path, _p);
      _p..color = isActive ? item.accent.withValues(alpha: 0.3 * st)
          : Color.fromARGB(sa ~/ 6, 130, 200, 255)
        ..style = PaintingStyle.stroke..strokeWidth = isActive ? 1.5 : 0.6;
      c.drawPath(path, _p);
    }

    // Icon with magnetic snap
    final startA = _s0 + i * _sa + (isSubOpen && subParent == item ? 0 : _sa * 0.0);
    final midA = _s0 + i * _sa + _sa / 2;
    final midR = (ri + ro) / 2;
    double ix = center.dx + math.cos(midA) * midR;
    double iy = center.dy + math.sin(midA) * midR;

    if (h) {
      final fd = finger - center;
      if (fd.distance > 1) {
        ix += (fd.dx / fd.distance) * 4;
        iy += (fd.dy / fd.distance) * 4;
      }
    }

    double iconScale = st;
    if (h && bounce < 1) {
      iconScale *= 0.7 + 0.3 * Curves.elasticOut.transform(bounce.clamp(0, 1));
    }

    IconData icon = item.icon;
    if (item == RadialMenuItem.undo && !canUndo) icon = Icons.redo_rounded;

    // OPT #2: cached TextPainter
    final tp = getIcon(icon,
        (h ? Colors.white : (isActive ? Colors.white : Colors.white70))
            .withValues(alpha: st),
        20 * iconScale);
    tp.paint(c, Offset(ix - tp.width / 2, iy - tp.height / 2));

    // Mini-label with dark shadow pill for contrast on any canvas
    final labelR = ro + 16;
    final lx = center.dx + math.cos(midA) * labelR;
    final ly = center.dy + math.sin(midA) * labelR;
    String label = item.label;
    if (item == RadialMenuItem.undo && !canUndo) label = 'Redo';
    final ltp = getLabel(label,
        (h ? item.accent : Colors.white).withValues(alpha: st),
        9, weight: FontWeight.w600);
    // Dark shadow pill behind label
    final lRect = Rect.fromCenter(
        center: Offset(lx, ly),
        width: ltp.width + 8, height: ltp.height + 4);
    _p..color = Color.fromARGB((180 * st).toInt(), 0, 0, 0)
      ..style = PaintingStyle.fill..maskFilter = null;
    c.drawRRect(RRect.fromRectAndRadius(lRect, const Radius.circular(4)), _p);
    ltp.paint(c, Offset(lx - ltp.width / 2, ly - ltp.height / 2));

    // Undo badge
    if (item == RadialMenuItem.undo && undoCount > 0) {
      _p..color = const Color(0xFFFF5252)..style = PaintingStyle.fill
        ..maskFilter = null;
      c.drawCircle(Offset(ix + 12, iy - 12), 8, _p);
      final bt = getLabel(undoCount > 99 ? '99+' : '$undoCount',
          Colors.white, 8, weight: FontWeight.w800);
      bt.paint(c, Offset(ix + 12 - bt.width / 2, iy - 12 - bt.height / 2));
    }
  }

  void _paintSubRing(Canvas c, int a) {
    if (subParent == null || subPositions.isEmpty) return;
    final pi = RadialMenuItem.values.indexOf(subParent!);
    final pa = _s0 + pi * _sa + _sa / 2;
    final isBrush = subParent == RadialMenuItem.brush;
    final isInsert = subParent == RadialMenuItem.insert;
    final isTools = subParent == RadialMenuItem.tools;
    final sa = (subRing * a).toInt().clamp(0, 255);

    final px = center.dx + math.cos(pa) * ro;
    final py = center.dy + math.sin(pa) * ro;

    for (int i = 0; i < subPositions.length; i++) {
      final cx = subPositions[i].dx;
      final cy = subPositions[i].dy;

      _p..color = subParent!.accent.withValues(alpha: 0.12 * subRing)
        ..style = PaintingStyle.stroke..strokeWidth = 0.8..maskFilter = null;
      c.drawLine(Offset(px, py), Offset(cx, cy), _p);

      final h = i == hoveredSub;
      const bgR = 22.0;

      if (isBrush) {
        _paintBrushSub(c, cx, cy, bgR, i, h, sa);
      } else if (isInsert) {
        _paintIconSub(c, cx, cy, bgR, i, h, sa,
            RadialInsertItem.values[i % RadialInsertItem.values.length].icon,
            RadialInsertItem.values[i % RadialInsertItem.values.length].label,
            subParent!.accent);
      } else if (isTools) {
        _paintIconSub(c, cx, cy, bgR, i, h, sa,
            RadialToolItem.values[i % RadialToolItem.values.length].icon,
            RadialToolItem.values[i % RadialToolItem.values.length].label,
            subParent!.accent);
      } else {
        _paintColorSub(c, cx, cy, bgR, i, h, sa);
      }
    }
  }

  void _paintBrushSub(Canvas c, double x, double y, double r, int i,
      bool h, int sa) {
    final cur = i == brushIdx;
    if (h) {
      _p..color = const Color(0xFF64B5F6).withValues(alpha: 0.2)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      c.drawCircle(Offset(x, y), r + 3, _p);
      _p.maskFilter = null;
    }
    _p..color = Color.fromARGB(sa ~/ 2, 16, 16, 32)..style = PaintingStyle.fill;
    c.drawCircle(Offset(x, y), r, _p);
    _p..color = cur ? const Color(0xFF64B5F6).withValues(alpha: 0.9)
        : Color.fromARGB(sa ~/ 5, 130, 200, 255)
      ..style = PaintingStyle.stroke..strokeWidth = cur ? 2.5 : 0.6;
    c.drawCircle(Offset(x, y), r, _p);
    if (i < RadialBrushItem.values.length) {
      final tp = getIcon(RadialBrushItem.values[i].icon,
          h ? Colors.white : Colors.white54, 17);
      tp.paint(c, Offset(x - tp.width / 2, y - tp.height / 2));

      // 🖌️ BRUSH PREVIEW STROKE — shows when hovered
      if (h) {
        final previewPath = Path();
        final pw = r * 0.7; // Preview half-width
        previewPath.moveTo(x - pw, y + r + 8);
        previewPath.cubicTo(
          x - pw * 0.3, y + r + 4,
          x + pw * 0.3, y + r + 12,
          x + pw, y + r + 8,
        );
        // Stroke width varies by brush type
        final strokeW = i == 0 ? 2.0  // Ballpoint
            : i == 1 ? 3.5  // Felt tip
            : i == 2 ? 1.0  // Fountain pen
            : i == 3 ? 5.0  // Marker
            : 2.5;          // Pencil
        _p..color = curColor.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round;
        c.drawPath(previewPath, _p);
      }
    }
  }

  /// Generic icon sub-item (used by Insert and Tools sub-rings)
  void _paintIconSub(Canvas c, double x, double y, double r, int i,
      bool h, int sa, IconData icon, String label, Color accent) {
    if (h) {
      _p..color = accent.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      c.drawCircle(Offset(x, y), r + 3, _p);
      _p.maskFilter = null;
    }
    _p..color = Color.fromARGB(sa ~/ 2, 16, 16, 32)..style = PaintingStyle.fill;
    c.drawCircle(Offset(x, y), r, _p);
    _p..color = (h ? accent : accent.withValues(alpha: 0.3))
      ..style = PaintingStyle.stroke..strokeWidth = h ? 2.0 : 0.6;
    c.drawCircle(Offset(x, y), r, _p);
    final tp = getIcon(icon, h ? Colors.white : Colors.white70, 17);
    tp.paint(c, Offset(x - tp.width / 2, y - tp.height / 2));
    // Mini-label below sub-item
    final ltp = getLabel(label, h ? Colors.white : Colors.white54,
        7, weight: FontWeight.w500);
    ltp.paint(c, Offset(x - ltp.width / 2, y + r + 3));
  }

  void _paintColorSub(Canvas c, double x, double y, double r, int i,
      bool h, int sa) {
    final cl = i < colors.length ? colors[i] : Colors.transparent;
    final isEye = cl == Colors.transparent;
    if (h) {
      _p..color = (isEye ? const Color(0xFFFFAB91) : cl).withValues(alpha: 0.25)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      c.drawCircle(Offset(x, y), r + 3, _p);
      _p.maskFilter = null;
    }
    if (isEye) {
      _p..color = Color.fromARGB(sa ~/ 2, 16, 16, 32)..style = PaintingStyle.fill;
      c.drawCircle(Offset(x, y), r, _p);
      final tp = getIcon(Icons.colorize_rounded, h ? Colors.white : Colors.white54, 17);
      tp.paint(c, Offset(x - tp.width / 2, y - tp.height / 2));
    } else {
      _p..color = cl..style = PaintingStyle.fill;
      c.drawCircle(Offset(x, y), r, _p);
      _p..color = Colors.white.withValues(alpha: h ? 0.7 : 0.25)
        ..style = PaintingStyle.stroke..strokeWidth = h ? 2.5 : 1.0;
      c.drawCircle(Offset(x, y), r, _p);
    }
  }

  void _paintCenter(Canvas c, int a) {
    _p..color = Color.fromARGB((a * 0.55).toInt(), 12, 12, 25)
      ..style = PaintingStyle.fill..maskFilter = null;
    c.drawCircle(center, 24, _p);
    _p..color = Color.fromARGB(a ~/ 4, 130, 200, 255)
      ..style = PaintingStyle.stroke..strokeWidth = 1.5;
    c.drawCircle(center, 24, _p);

    if (hasLastAction) {
      final tp = getIcon(Icons.replay_rounded,
          Color.fromARGB(a ~/ 2, 130, 200, 255), 16);
      tp.paint(c, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
    } else {
      _p..color = Color.fromARGB(a ~/ 3, 100, 180, 255)..style = PaintingStyle.fill;
      c.drawCircle(center, 5, _p);
    }

    // Center hover label
    if (hovered >= 0) {
      final item = RadialMenuItem.values[hovered];
      String l = item.label;
      if (item == RadialMenuItem.undo && !canUndo) l = 'Redo';
      final tp = getLabel(l, item.accent, 11);
      tp.paint(c, Offset(center.dx - tp.width / 2, center.dy + 36));
    } else if (hoveredSub >= 0 && isSubOpen) {
      String l = '';
      Color ac = const Color(0xFF64B5F6);
      if (subParent == RadialMenuItem.brush) {
        l = RadialBrushItem.values[hoveredSub % RadialBrushItem.values.length].label;
      } else if (subParent == RadialMenuItem.insert) {
        l = RadialInsertItem.values[hoveredSub % RadialInsertItem.values.length].label;
        ac = const Color(0xFFE8A84C);
      } else if (subParent == RadialMenuItem.tools) {
        l = RadialToolItem.values[hoveredSub % RadialToolItem.values.length].label;
        ac = const Color(0xFF80CBC4);
      }
      if (l.isNotEmpty) {
        final tp = getLabel(l, ac, 11);
        tp.paint(c, Offset(center.dx - tp.width / 2, center.dy + 36));
      }
    }
  }

  double _stagger(int i) {
    // ✨ Slower stagger for more dramatic expansion effect
    const d = 0.08;
    final raw = ((stagger - i * d) / (1.0 - i * d)).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(raw);
  }

  // OPT #5: Smart shouldRepaint
  @override
  bool shouldRepaint(covariant _PainterV4Opt o) =>
      // Only repaint when something visual actually changed
      hovered != o.hovered ||
      hoveredSub != o.hoveredSub ||
      isSubOpen != o.isSubOpen ||
      scale != o.scale ||
      alpha != o.alpha ||
      stagger != o.stagger ||
      subRing != o.subRing ||
      bounce != o.bounce ||
      particleT != o.particleT ||
      idlePulse != o.idlePulse ||
      undoCount != o.undoCount ||
      finger != o.finger ||
      pulseNorm != o.pulseNorm ||
      orbitT != o.orbitT;
}
