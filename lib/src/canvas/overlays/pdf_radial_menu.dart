import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../drawing/models/pro_drawing_point.dart';

// =============================================================================
// 📖 PDF RADIAL TOOL WHEEL v3
//
// Full parity with CanvasRadialMenu:
//   • Mode-aware: 6 sectors (reading) / 7 sectors (drawing)
//   • Color sub-ring on ink tools
//   • Active tool sector glow
//   • _TrailBuffer — multi-point fading finger trail
//   • Velocity-based quick-repeat (flick → immediate undo)
//   • Perf: arc paths only invalidated on sector count change
// =============================================================================

// ─── Reading mode: 10 sectors ───────────────────────────────────────────────
enum PdfReadingAction {
  pen('Pen',           Icons.edit_rounded,                Color(0xFF64B5F6)),
  highlight('Highlight', Icons.highlight_rounded,         Color(0xFFFFEB3B)),
  eraser('Eraser',     Icons.cleaning_services_rounded,   Color(0xFFEF9A9A)),
  undo('Undo',         Icons.undo_rounded,                Color(0xFF80CBC4)),
  textSelect('Select', Icons.text_fields_rounded,         Color(0xFF4FC3F7)),
  search('Search',     Icons.search_rounded,              Color(0xFF81C784)),
  bookmark('Bookmark', Icons.bookmark_rounded,            Color(0xFFEF5350)),
  exportAnnotated('Export', Icons.ios_share_rounded,      Color(0xFF42A5F5)),
  reading('Reading',   Icons.auto_awesome_rounded,        Color(0xFFA87FDB)),
  sidebar('Pages',     Icons.view_sidebar_rounded,        Color(0xFFE8A84C));

  const PdfReadingAction(this.label, this.icon, this.accent);
  final String label;
  final IconData icon;
  final Color accent;
}

// ─── Drawing mode: 7 sectors ────────────────────────────────────────────────
enum PdfDrawingAction {
  ballpoint('Ballpoint', Icons.edit_rounded,              Color(0xFF64B5F6)),
  pencil('Pencil',       Icons.create_rounded,            Color(0xFF90CAF9)),
  fountain('Fountain',   Icons.gesture_rounded,           Color(0xFF7E57C2)),
  highlighter('Highlighter', Icons.highlight_rounded,     Color(0xFFFFEB3B)),
  eraser('Eraser',       Icons.cleaning_services_rounded, Color(0xFFEF9A9A)),
  undo('Undo',           Icons.undo_rounded,              Color(0xFF80CBC4)),
  exitDraw('Done',       Icons.check_circle_outline_rounded, Color(0xFF81C784));

  const PdfDrawingAction(this.label, this.icon, this.accent);
  final String label;
  final IconData icon;
  final Color accent;

  bool get hasColorSubRing =>
      this == ballpoint || this == pencil ||
      this == fountain || this == highlighter;

  ProPenType? get penType {
    switch (this) {
      case ballpoint:   return ProPenType.ballpoint;
      case pencil:      return ProPenType.pencil;
      case fountain:    return ProPenType.fountain;
      case highlighter: return ProPenType.highlighter;
      default:          return null;
    }
  }
}

// ─── Result ──────────────────────────────────────────────────────────────────
class PdfRadialResult {
  final PdfReadingAction? readingAction;
  final PdfDrawingAction? drawingAction;
  final Color? selectedColor;
  final bool quickRepeat;

  const PdfRadialResult.reading(this.readingAction)
      : drawingAction = null, selectedColor = null, quickRepeat = false;
  const PdfRadialResult.drawing(this.drawingAction)
      : readingAction = null, selectedColor = null, quickRepeat = false;
  const PdfRadialResult.color(this.selectedColor)
      : readingAction = null, drawingAction = null, quickRepeat = false;
  const PdfRadialResult.flick()
      : readingAction = null, drawingAction = null, selectedColor = null,
        quickRepeat = true;
  const PdfRadialResult.dismiss()
      : readingAction = null, drawingAction = null, selectedColor = null,
        quickRepeat = false;
}

// =============================================================================
// 🖊️ TRAIL BUFFER — circular buffer of recent finger positions
// =============================================================================

class _TrailBuffer {
  static const int _cap = 48;
  final List<Offset> _pts = List.filled(_cap, Offset.zero);
  int _head = 0;
  int _count = 0;

  void add(Offset pt) {
    _pts[_head] = pt;
    _head = (_head + 1) % _cap;
    if (_count < _cap) _count++;
  }

  int get length => _count;

  Offset operator [](int i) {
    assert(i < _count);
    final idx = (_head - _count + i + _cap * 2) % _cap;
    return _pts[idx];
  }
}

// =============================================================================
// 🎬 ANIMATION STATE
// =============================================================================

class _Anim {
  double entrance = 0;
  double exit = 0;
  double subRing = 0;
  double iconBounce = 0;   // 0→1, 200ms elasticOut (canvas parity)
  double idlePulse = 0;    // ping-pong, 800ms (canvas parity)
  bool entranceForward = true;
  bool exitForward = false;
  bool subRingForward = false;
  bool subRingReverse = false;
  bool iconBounceActive = false;
  bool idlePulseActive = false;
  double orbit = 0;

  static const double dIn = 0.320;  // canvas parity (was 0.260)
  static const double dOut = 0.130;
  static const double dSub = 0.180;
  static const double dBounce = 0.200;
  static const double dIdlePulse = 0.800;

  void tick(double dt) {
    if (entranceForward && entrance < 1) {
      entrance = (entrance + dt / dIn).clamp(0, 1);
    }
    if (exitForward && exit < 1) {
      exit = (exit + dt / dOut).clamp(0, 1);
    }
    if (subRingForward && subRing < 1) {
      subRing = (subRing + dt / dSub).clamp(0, 1);
    } else if (subRingReverse && subRing > 0) {
      subRing = (subRing - dt / dSub).clamp(0, 1);
      if (subRing <= 0) subRingReverse = false;
    }
    if (iconBounceActive && iconBounce < 1) {
      iconBounce = (iconBounce + dt / dBounce).clamp(0, 1);
      if (iconBounce >= 1) iconBounceActive = false;
    }
    if (idlePulseActive) {
      idlePulse += dt / dIdlePulse;
      if (idlePulse > 2) idlePulse -= 2;
    }
    orbit += dt;
  }

  double get idlePulseValue => idlePulseActive
      ? (idlePulse <= 1 ? idlePulse : 2 - idlePulse).clamp(0.0, 1.0)
      : 0.0;
}

// =============================================================================
// WIDGET
// =============================================================================

class PdfRadialMenu extends StatefulWidget {
  final Offset center;
  final bool isDrawingMode;
  final bool isCurrentPageBookmarked;
  final int bookmarkCount;
  final ProPenType currentPenType;
  final Color currentColor;
  final List<Color> colorPresets;
  final List<Color> highlightColors;
  final ValueChanged<PdfRadialResult> onResult;
  final Size screenSize;

  const PdfRadialMenu({
    super.key,
    required this.center,
    required this.onResult,
    this.isDrawingMode = false,
    this.isCurrentPageBookmarked = false,
    this.bookmarkCount = 0,
    this.currentPenType = ProPenType.ballpoint,
    this.currentColor = Colors.black,
    this.colorPresets = const [],
    this.highlightColors = const [],
    this.screenSize = Size.zero,
  });

  @override
  State<PdfRadialMenu> createState() => PdfRadialMenuState();
}

class PdfRadialMenuState extends State<PdfRadialMenu>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _anim = _Anim();
  final _trail = _TrailBuffer();
  Duration _lastTick = Duration.zero;
  final _repaint = ValueNotifier<int>(0);

  int _hovered = -1;
  bool _isSubRingOpen = false;
  int _hoveredColor = -1;
  Offset _finger = Offset.zero;
  bool _isExiting = false;
  PdfRadialResult? _pending;
  late Offset _center;
  int _lastN = -1;

  // Velocity tracking for quick-repeat flick
  Offset _lastFingerPos = Offset.zero;
  DateTime _lastFingerTime = DateTime.now();
  double _flickVelocity = 0;

  List<Path>? _arcPaths;
  final Map<int, TextPainter> _iconCache = {};
  final Map<String, TextPainter> _labelCache = {};

  static const double _arcInner = 68.0;  // canvas parity
  static const double _arcOuter = 146.0; // canvas parity
  static const double _subR = 190.0;
  static const double _deadZone = 25.0;
  static const double _s0 = -math.pi / 2;
  static const double _gap = 3.0 * math.pi / 180; // canvas parity (was 3.5)

  // Flick quick-repeat thresholds (match CanvasRadialMenu)
  static const double _flickVelocityThreshold = 900; // px/s
  static const double _flickDistanceMax = 55;         // px from center

  int get _N => widget.isDrawingMode
      ? PdfDrawingAction.values.length   // 7
      : PdfReadingAction.values.length;  // 6
  double get _sa => 2 * math.pi / _N;

  @override
  void initState() {
    super.initState();
    _center = widget.center;
    _finger = _center;
    _lastFingerPos = _center;
    _lastN = _N;
    _ticker = createTicker(_onTick)..start();
    HapticFeedback.mediumImpact();
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) { _lastTick = elapsed; return; }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _anim.tick(dt);
    _repaint.value++;
    if (_isExiting && _anim.exit >= 1.0 && _pending != null) {
      _ticker.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onResult(_pending!);
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    for (final tp in _iconCache.values) tp.dispose();
    for (final tp in _labelCache.values) tp.dispose();
    super.dispose();
  }

  int _sectorFromAngle(double a) {
    double rel = a - _s0;
    if (rel < 0) rel += 2 * math.pi;
    return (rel / _sa).floor() % _N;
  }

  bool get _hoveredHasSubRing =>
      widget.isDrawingMode &&
      _hovered >= 0 &&
      PdfDrawingAction.values[_hovered].hasColorSubRing;

  bool get _hoveredIsHighlighter =>
      widget.isDrawingMode &&
      _hovered >= 0 &&
      PdfDrawingAction.values[_hovered] == PdfDrawingAction.highlighter;

  List<Color> get _activeColors =>
      _hoveredIsHighlighter ? widget.highlightColors : widget.colorPresets;

  List<Offset> _colorPositions() {
    if (_hovered < 0 || !_hoveredHasSubRing) return const [];
    final colors = _activeColors;
    if (colors.isEmpty) return const [];

    final parentAngle = _s0 + _hovered * _sa + _sa / 2;
    final fanSpread = math.min(math.pi * 0.65, colors.length * 0.35);
    final step = fanSpread / math.max(colors.length - 1, 1);
    final fanStart = parentAngle - fanSpread / 2;
    final r = _arcOuter + 8 + (_subR - _arcOuter - 8) * _anim.subRing;

    final ss = widget.screenSize;
    const margin = 20.0;
    final positions = <Offset>[];
    for (int i = 0; i < colors.length; i++) {
      final angle = fanStart + i * step;
      double cx = _center.dx + math.cos(angle) * r;
      double cy = _center.dy + math.sin(angle) * r;
      if (ss != Size.zero) {
        cx = cx.clamp(margin, ss.width - margin);
        cy = cy.clamp(margin, ss.height - margin);
      }
      positions.add(Offset(cx, cy));
    }
    return positions;
  }

  // ── Public API (called from GestureDetector in pdf_reader_screen) ──────────

  void updateFinger(Offset globalPos) {
    if (_isExiting) return;

    // Velocity tracking for flick detection
    final now = DateTime.now();
    final elapsed = now.difference(_lastFingerTime).inMicroseconds / 1e6;
    if (elapsed > 0.005) {
      final dist = (globalPos - _lastFingerPos).distance;
      _flickVelocity = dist / elapsed;
      _lastFingerPos = globalPos;
      _lastFingerTime = now;
    }

    _finger = globalPos;
    _trail.add(globalPos);

    final dx = globalPos.dx - _center.dx;
    final dy = globalPos.dy - _center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);

    if (dist < _deadZone) {
      if (_hovered != -1 || _hoveredColor != -1) {
        _hovered = -1; _hoveredColor = -1;
        _isSubRingOpen = false;
        _anim.subRingForward = false; _anim.subRingReverse = true;
      }
      return;
    }

    // Hit-test color sub-ring dots
    if (_isSubRingOpen && dist > _arcOuter + 10) {
      final positions = _colorPositions();
      int bestIdx = -1; double bestDist = double.infinity;
      for (int i = 0; i < positions.length; i++) {
        final d = (globalPos - positions[i]).distance;
        if (d < bestDist) { bestDist = d; bestIdx = i; }
      }
      if (bestDist < 32) {
        if (bestIdx != _hoveredColor) {
          _hoveredColor = bestIdx; HapticFeedback.selectionClick();
        }
        return;
      }
      _hoveredColor = -1;
    }

    final sector = _sectorFromAngle(math.atan2(dy, dx));
    if (sector != _hovered) {
      _hovered = sector; _hoveredColor = -1;
      // Icon bounce on new sector (canvas parity)
      _anim.iconBounce = 0;
      _anim.iconBounceActive = true;
      // Stop idle pulse
      _anim.idlePulseActive = false;
      HapticFeedback.selectionClick();

      if (_hoveredHasSubRing) {
        if (!_isSubRingOpen) {
          _isSubRingOpen = true;
          _anim.subRingForward = true; _anim.subRingReverse = false;
          _anim.subRing = 0;
        }
      } else if (_isSubRingOpen) {
        _isSubRingOpen = false;
        _anim.subRingForward = false; _anim.subRingReverse = true;
      }
    }
  }

  void release() {
    if (_isExiting) return;
    PdfRadialResult result;

    // ── Quick-repeat flick (fast movement + short distance from center) ──
    final distFromCenter = (_finger - _center).distance;
    if (_flickVelocity > _flickVelocityThreshold &&
        distFromCenter < _flickDistanceMax &&
        _hovered < 0) {
      result = const PdfRadialResult.flick();
      HapticFeedback.mediumImpact();
    } else if (_isSubRingOpen && _hoveredColor >= 0) {
      final colors = _activeColors;
      result = _hoveredColor < colors.length
          ? PdfRadialResult.color(colors[_hoveredColor])
          : const PdfRadialResult.dismiss();
    } else if (_hovered >= 0) {
      result = widget.isDrawingMode
          ? PdfRadialResult.drawing(PdfDrawingAction.values[_hovered])
          : PdfRadialResult.reading(PdfReadingAction.values[_hovered]);
    } else {
      result = const PdfRadialResult.dismiss();
    }

    _isExiting = true;
    _pending = result;
    _anim.exitForward = true;
    if (result.readingAction != null || result.drawingAction != null ||
        result.selectedColor != null) {
      HapticFeedback.lightImpact();
    }
  }

  // ── Arc path cache ────────────────────────────────────────────────────────

  List<Path> _getArcPaths() {
    if (_arcPaths != null && _lastN == _N) return _arcPaths!;
    _lastN = _N;
    final paths = <Path>[];
    final outer = Rect.fromCircle(center: _center, radius: _arcOuter);
    final inner = Rect.fromCircle(center: _center, radius: _arcInner);
    for (int i = 0; i < _N; i++) {
      final startA = _s0 + i * _sa + _gap / 2;
      final sweepA = _sa - _gap;
      paths.add(Path()
        ..addArc(outer, startA, sweepA)
        ..arcTo(inner, startA + sweepA, -sweepA, false)
        ..close());
    }
    _arcPaths = paths;
    return paths;
  }

  TextPainter _iconPainter(IconData icon, Color color, double size) {
    final key = icon.codePoint ^ color.toARGB32() ^ size.hashCode;
    return _iconCache.putIfAbsent(key, () => TextPainter(
      text: TextSpan(text: String.fromCharCode(icon.codePoint),
          style: TextStyle(fontFamily: icon.fontFamily,
              package: icon.fontPackage, fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
    )..layout());
  }

  TextPainter _labelPainter(String text, Color color, double size) {
    final key = '$text|${color.toARGB32()}|$size';
    return _labelCache.putIfAbsent(key, () => TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size,
          fontWeight: FontWeight.w700, color: color, letterSpacing: 0.3)),
      textDirection: TextDirection.ltr,
    )..layout());
  }

  int get _activeToolSector {
    if (!widget.isDrawingMode) return -1;
    for (int i = 0; i < PdfDrawingAction.values.length; i++) {
      if (PdfDrawingAction.values[i].penType == widget.currentPenType) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final ss = widget.screenSize == Size.zero
        ? MediaQuery.of(context).size : widget.screenSize;
    final margin = _arcOuter + 16;
    _center = Offset(
      widget.center.dx.clamp(margin, ss.width - margin),
      widget.center.dy.clamp(margin, ss.height - margin),
    );

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerMove: (e) => updateFinger(e.position),
      onPointerUp: (_) => release(),
      onPointerCancel: (_) {
        _isExiting = true;
        _pending = const PdfRadialResult.dismiss();
        _anim.exitForward = true;
      },
      child: ValueListenableBuilder<int>(
        valueListenable: _repaint,
        builder: (context, _, __) {
          final eT = Curves.easeOutBack.transform(_anim.entrance.clamp(0, 1));
          final xT = _isExiting ? _anim.exit : 0.0;
          final scale = eT * (1.0 - xT * 0.3);
          final alpha = eT * (1.0 - xT);
          if (alpha <= 0.01) return const SizedBox.shrink();

          final blurR = (_isSubRingOpen ? _subR + 50 : _arcOuter + 22) * scale;
          final arcPaths = _getArcPaths();
          final colorPositions = _colorPositions();

          return Stack(children: [
            Positioned.fill(child: ClipPath(
              clipper: _CircleClipper(center: _center, radius: blurR),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                    sigmaX: 20 * alpha, sigmaY: 20 * alpha),
                child: Container(color: Colors.transparent),
              ),
            )),
            RepaintBoundary(
              child: CustomPaint(
                painter: _PdfWheelPainterV3(
                  center: _center,
                  scale: scale,
                  alpha: alpha,
                  hovered: _hovered,
                  hoveredColor: _hoveredColor,
                  isDrawingMode: widget.isDrawingMode,
                  isCurrentPageBookmarked: widget.isCurrentPageBookmarked,
                  bookmarkCount: widget.bookmarkCount,
                  arcPaths: arcPaths,
                  subRing: _anim.subRing,
                  colorPositions: colorPositions,
                  activeColors: _activeColors,
                  currentColor: widget.currentColor,
                  activeToolSector: _activeToolSector,
                  finger: _finger,
                  trail: _trail,
                  getIcon: _iconPainter,
                  getLabel: _labelPainter,
                ),
                size: Size.infinite,
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// =============================================================================
// 🎨 PAINTER V3
// =============================================================================

class _PdfWheelPainterV3 extends CustomPainter {
  final Offset center;
  final double scale, alpha, subRing;
  final int hovered, hoveredColor;
  final bool isDrawingMode;
  final bool isCurrentPageBookmarked;
  final int bookmarkCount;
  final List<Path> arcPaths;
  final List<Offset> colorPositions;
  final List<Color> activeColors;
  final Color currentColor;
  final int activeToolSector;
  final Offset finger;
  final _TrailBuffer trail;
  final TextPainter Function(IconData, Color, double) getIcon;
  final TextPainter Function(String, Color, double) getLabel;

  const _PdfWheelPainterV3({
    required this.center, required this.scale, required this.alpha,
    required this.hovered, required this.hoveredColor, required this.isDrawingMode,
    this.isCurrentPageBookmarked = false,
    this.bookmarkCount = 0,
    required this.arcPaths, required this.subRing, required this.colorPositions,
    required this.activeColors, required this.currentColor,
    required this.activeToolSector, required this.finger,
    required this.trail, required this.getIcon, required this.getLabel,
  });

  static const double _arcInner = 68.0;  // canvas parity
  static const double _arcOuter = 146.0; // canvas parity
  static const double _s0 = -math.pi / 2;

  int get _N => isDrawingMode
      ? PdfDrawingAction.values.length
      : PdfReadingAction.values.length;
  double get _sa => 2 * math.pi / _N;

  Color _accentFor(int i) => isDrawingMode
      ? PdfDrawingAction.values[i].accent
      : PdfReadingAction.values[i].accent;
  IconData _iconFor(int i) {
    if (isDrawingMode) return PdfDrawingAction.values[i].icon;
    final action = PdfReadingAction.values[i];
    if (action == PdfReadingAction.bookmark) {
      return isCurrentPageBookmarked
          ? Icons.bookmark_rounded
          : Icons.bookmark_border_rounded;
    }
    return action.icon;
  }
  String _labelFor(int i) => isDrawingMode
      ? PdfDrawingAction.values[i].label
      : PdfReadingAction.values[i].label;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);

    final p = Paint()..isAntiAlias = true;

    // ── Finger trail ──────────────────────────────────────────────────────
    final n = trail.length;
    if (n >= 2) {
      for (int i = 1; i < n; i++) {
        final tAlpha = (i / n) * 0.35 * alpha;
        final r = 2.5 + (i / n) * 2.5;
        p..color = Colors.white.withValues(alpha: tAlpha)
         ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
         ..style = PaintingStyle.fill;
        canvas.drawCircle(trail[i], r, p);
      }
      p.maskFilter = null;
    }

    // ── Drop shadow disc ──────────────────────────────────────────────────
    p..color = const Color(0xFF050510).withValues(alpha: 0.85 * alpha)
     ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20)
     ..style = PaintingStyle.fill;
    canvas.drawCircle(center, _arcOuter + 8, p);
    p.maskFilter = null;

    // ── Sectors ──────────────────────────────────────────────────────────
    for (int i = 0; i < _N; i++) {
      final isActive = i == hovered;
      final isCurrentTool = i == activeToolSector;
      final accent = _accentFor(i);

      if (isActive) {
        p..color = accent.withValues(alpha: 0.30 * alpha)..style = PaintingStyle.fill;
        canvas.drawPath(arcPaths[i], p);
        p..color = accent.withValues(alpha: 0.65 * alpha)
         ..style = PaintingStyle.stroke..strokeWidth = 2.0;
        canvas.drawPath(arcPaths[i], p);
      } else {
        p..color = const Color(0xFF1A1A36).withValues(alpha: 0.85 * alpha)
         ..style = PaintingStyle.fill;
        canvas.drawPath(arcPaths[i], p);
        if (isCurrentTool) {
          p..color = accent.withValues(alpha: 0.45 * alpha)
           ..style = PaintingStyle.stroke..strokeWidth = 1.6
           ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
          canvas.drawPath(arcPaths[i], p);
          p.maskFilter = null;
          p..color = accent.withValues(alpha: 0.18 * alpha)..style = PaintingStyle.fill;
          canvas.drawPath(arcPaths[i], p);
        } else {
          p..color = Colors.white.withValues(alpha: 0.07 * alpha)
           ..style = PaintingStyle.stroke..strokeWidth = 0.5;
          canvas.drawPath(arcPaths[i], p);
        }
      }
      p.style = PaintingStyle.fill;

      // Icon + label
      final midA = _s0 + i * _sa + _sa / 2;
      final iconR = (_arcInner + _arcOuter) / 2;
      final cx = center.dx + math.cos(midA) * iconR;
      final cy = center.dy + math.sin(midA) * iconR;
      final iconColor = isActive ? _accentFor(i)
          : isCurrentTool ? _accentFor(i).withValues(alpha: 0.85 * alpha)
          : Colors.white.withValues(alpha: 0.60 * alpha);
      final iconSize = isActive ? 20.0 : (isCurrentTool ? 19.0 : 16.0);
      final tp = getIcon(_iconFor(i), iconColor, iconSize);
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2 - 5));
      final lt = getLabel(_labelFor(i),
          isActive ? Colors.white.withValues(alpha: alpha)
          : isCurrentTool ? _accentFor(i).withValues(alpha: 0.9 * alpha)
          : Colors.white.withValues(alpha: 0.40 * alpha),
          isActive ? 8.5 : 7.5);
      lt.paint(canvas, Offset(cx - lt.width / 2, cy + 6));

      // Bookmark count badge
      if (!isDrawingMode && PdfReadingAction.values[i] == PdfReadingAction.bookmark && bookmarkCount > 0) {
        final badgeR = 7.0;
        final bx = cx + iconSize / 2 + 2;
        final by = cy - iconSize / 2 - 2;
        canvas.drawCircle(Offset(bx, by), badgeR + 1, Paint()..color = const Color(0xFF1A1A36).withValues(alpha: alpha));
        canvas.drawCircle(Offset(bx, by), badgeR, Paint()..color = const Color(0xFFEF5350).withValues(alpha: alpha));
        final badgeTp = TextPainter(
          text: TextSpan(
            text: bookmarkCount > 99 ? '99+' : '$bookmarkCount',
            style: TextStyle(color: Colors.white.withValues(alpha: alpha), fontSize: 8, fontWeight: FontWeight.w700),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        badgeTp.paint(canvas, Offset(bx - badgeTp.width / 2, by - badgeTp.height / 2));
      }
    }

    // ── Color sub-ring ────────────────────────────────────────────────────
    if (subRing > 0 && colorPositions.isNotEmpty) {
      for (int i = 0; i < colorPositions.length && i < activeColors.length; i++) {
        final pos = colorPositions[i];
        final c = activeColors[i];
        final isHov = i == hoveredColor;
        final r = isHov ? 14.0 : 10.0;
        if (isHov) {
          p..color = c.withValues(alpha: 0.45 * alpha * subRing)
           ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
          canvas.drawCircle(pos, r + 6, p);
          p.maskFilter = null;
        }
        p..color = c.withValues(alpha: subRing * alpha)..style = PaintingStyle.fill;
        canvas.drawCircle(pos, r, p);
        p..color = (isHov ? Colors.white : Colors.white.withValues(alpha: 0.5))
                .withValues(alpha: subRing * alpha)
           ..style = PaintingStyle.stroke..strokeWidth = isHov ? 2.0 : 1.0;
        canvas.drawCircle(pos, r, p);
        p.style = PaintingStyle.fill;
      }
    }

    // ── Center disc (current color swatch) ───────────────────────────────
    p..color = const Color(0xFF12122A).withValues(alpha: 0.94 * alpha)
     ..style = PaintingStyle.fill..maskFilter = null;
    canvas.drawCircle(center, _arcInner - 4, p);
    p.color = currentColor.withValues(alpha: 0.7 * alpha);
    canvas.drawCircle(center, (_arcInner - 4) * 0.5, p);
    p..color = Colors.white.withValues(alpha: 0.14 * alpha)
     ..style = PaintingStyle.stroke..strokeWidth = 1.0;
    canvas.drawCircle(center, _arcInner - 4, p);
    p.style = PaintingStyle.fill;

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PdfWheelPainterV3 old) =>
      old.hovered != hovered || old.hoveredColor != hoveredColor ||
      old.alpha != alpha || old.scale != scale || old.subRing != subRing ||
      old.trail.length != trail.length;
}

// =============================================================================
// HELPERS
// =============================================================================

class _CircleClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;
  const _CircleClipper({required this.center, required this.radius});
  @override
  Path getClip(Size s) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  @override
  bool shouldReclip(covariant _CircleClipper o) =>
      center != o.center || radius != o.radius;
}
