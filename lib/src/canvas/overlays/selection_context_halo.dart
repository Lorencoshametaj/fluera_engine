import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/fluera_localizations.dart';

/// 🎯 Selection context menu — sober bounding frame + floating action arc.
///
/// Shows a subtle bounding frame around the current selection with a
/// clustered arc of action buttons above (or below). No holographic/orbital
/// decorations — enterprise-sober per leggi_ui_ux.md §II.1-II.7.
class SelectionContextHalo extends StatefulWidget {
  final Rect selectionScreenBounds;
  final int selectionCount;

  // ── Primary actions ──
  final VoidCallback onDelete;
  final VoidCallback onClearSelection;
  final VoidCallback? onCopy;
  final VoidCallback? onDuplicate;
  final VoidCallback? onPaste;
  final bool hasClipboard;

  // ── Transform ──
  final VoidCallback onRotate;
  final VoidCallback onFlipHorizontal;
  final VoidCallback onFlipVertical;

  // ── Arrange ──
  final VoidCallback? onBringToFront;
  final VoidCallback? onSendToBack;
  final VoidCallback? onSelectAll;
  final VoidCallback? onUndo;
  final VoidCallback? onGroup;
  final VoidCallback? onUngroup;

  // ── Advanced ──
  final VoidCallback? onAlignLeft;
  final VoidCallback? onAlignCenterH;
  final VoidCallback? onAlignRight;
  final VoidCallback? onAlignTop;
  final VoidCallback? onAlignCenterV;
  final VoidCallback? onAlignBottom;
  final VoidCallback? onDistributeH;
  final VoidCallback? onDistributeV;
  final VoidCallback? onToggleSnap;
  final bool snapEnabled;
  final VoidCallback? onLock;
  final VoidCallback? onUnlock;
  final bool isSelectionLocked;
  final VoidCallback? onToggleMultiLayer;
  final bool multiLayerMode;
  final VoidCallback? onInverse;
  final VoidCallback? onPasteInPlace;
  final VoidCallback onConvertToText;
  final String? statsSummary;

  // ── Atlas AI ──
  final ValueChanged<String>? onAtlas;
  final VoidCallback? onAtlasCustomPrompt;
  final bool atlasIsLoading;

  const SelectionContextHalo({
    super.key,
    required this.selectionScreenBounds,
    required this.selectionCount,
    required this.onDelete,
    required this.onClearSelection,
    required this.onRotate,
    required this.onFlipHorizontal,
    required this.onFlipVertical,
    required this.onConvertToText,
    this.onCopy,
    this.onDuplicate,
    this.onPaste,
    this.hasClipboard = false,
    this.onBringToFront,
    this.onSendToBack,
    this.onSelectAll,
    this.onUndo,
    this.onGroup,
    this.onUngroup,
    this.onAlignLeft,
    this.onAlignCenterH,
    this.onAlignRight,
    this.onAlignTop,
    this.onAlignCenterV,
    this.onAlignBottom,
    this.onDistributeH,
    this.onDistributeV,
    this.onToggleSnap,
    this.snapEnabled = false,
    this.onLock,
    this.onUnlock,
    this.isSelectionLocked = false,
    this.onToggleMultiLayer,
    this.multiLayerMode = false,
    this.onInverse,
    this.onPasteInPlace,
    this.statsSummary,
    this.onAtlas,
    this.onAtlasCustomPrompt,
    this.atlasIsLoading = false,
  });

  @override
  State<SelectionContextHalo> createState() => _SelectionContextHaloState();
}

class _SelectionContextHaloState extends State<SelectionContextHalo>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  bool _isExpanded = false;
  late final AnimationController _expandController;
  late final Animation<double> _expandAnim;

  // ── Palette ──
  static const _accent = Color(0xFF8EC8E8);
  static const _accentDim = Color(0xFF5A9AB5);
  static const _danger = Color(0xFFE57373);
  static const _subtle = Color(0xFF9E9E9E);
  static const _teal = Color(0xFF80DEEA);
  static const _panelBg = Color(0xF0121218);

  // ── Arc config ──
  static const double _btnSize = 40.0;
  static const double _labelHeight = 14.0; // space for micro-label below btn
  static const double _arcRadius = 120.0;
  static const double _arcSweep = math.pi * 0.75; // 135°

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandAnim = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _entryController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      _expandController.forward(from: 0);
    } else {
      _expandController.reverse();
    }
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final bounds = widget.selectionScreenBounds;
    final centerX = bounds.center.dx;
    final viewSize = MediaQuery.of(context).size;

    final actions = _buildActions();
    final count = actions.length;

    // Arc origin: just above (or below) the selection
    final bool placeBelow = bounds.top - _arcRadius - _btnSize < 60;
    final arcOrigin = Offset(
      centerX.clamp(_arcRadius + 24, viewSize.width - _arcRadius - 24),
      placeBelow
          ? bounds.bottom + 20
          : bounds.top - 20,
    );

    final midAngle = placeBelow ? math.pi / 2 : -math.pi / 2;
    final startAngle = midAngle - _arcSweep / 2;

    // Selection connection point (top or bottom center)
    final selectionAnchor = Offset(
      bounds.center.dx,
      placeBelow ? bounds.bottom : bounds.top,
    );

    return Stack(
      children: [
        // ── 1. Selection frame ring (sober bounding box) ──
        Positioned.fill(
          child: FadeTransition(
            opacity: _entryController,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SelectionFramePainter(
                  bounds: bounds,
                  color: _accent.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ),

        // ── 2. Action buttons on a gentle arc (no orbital line, no connector) ──
        ...List.generate(count, (i) {
          final t = count > 1 ? i / (count - 1) : 0.5;
          final angle = startAngle + _arcSweep * t;
          final x = arcOrigin.dx + _arcRadius * math.cos(angle);
          final y = arcOrigin.dy + _arcRadius * math.sin(angle);

          return FadeTransition(
            opacity: _entryController,
            child: Positioned(
              left: x - _btnSize / 2,
              top: y - _btnSize / 2,
              child: Tooltip(
                message: actions[i].label,
                waitDuration: const Duration(milliseconds: 500),
                child: _ArcButton(action: actions[i], size: _btnSize),
              ),
            ),
          );
        }),

        // ── 3. Count badge (only when multi-selection) ──
        if (widget.selectionCount > 1)
          Positioned(
            left: arcOrigin.dx - 16,
            top: arcOrigin.dy - 12,
            child: FadeTransition(
              opacity: _entryController,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _panelBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.selectionCount}',
                    style: TextStyle(
                      color: _accent.withValues(alpha: 0.75),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // ── 4. Expanded panel ──
        if (_isExpanded)
          _buildExpandedPanel(arcOrigin, placeBelow, viewSize),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Actions
  // ═══════════════════════════════════════════════════════════════════

  List<_HaloAction> _buildActions() {
    return [
      if (widget.onCopy != null)
        _HaloAction(Icons.copy_rounded, 'Copy', _accent, widget.onCopy!),
      if (widget.onDuplicate != null)
        _HaloAction(Icons.library_add_rounded, 'Dupe', _accentDim,
            widget.onDuplicate!),
      if (widget.onPaste != null && widget.hasClipboard)
        _HaloAction(
            Icons.paste_rounded, 'Paste', _accentDim, widget.onPaste!),
      _HaloAction(
          Icons.delete_outline_rounded, 'Del', _danger, widget.onDelete),
      if (widget.onAtlas != null)
        _HaloAction(Icons.auto_awesome_rounded, 'Analizza', _teal,
            () => widget.onAtlas!('_ANALYZE_')),
      _HaloAction(
        _isExpanded ? Icons.expand_less_rounded : Icons.more_horiz_rounded,
        'More',
        _subtle,
        _toggleExpanded,
      ),
      _HaloAction(Icons.close_rounded, 'Close', _subtle,
          widget.onClearSelection),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════
  // Expanded Panel
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildExpandedPanel(
      Offset arcOrigin, bool placeBelow, Size viewSize) {
    const panelWidth = 280.0;
    final panelLeft = (arcOrigin.dx - panelWidth / 2)
        .clamp(16.0, viewSize.width - panelWidth - 16.0);

    // Position panel away from selection: always on the arc side
    final selBottom = widget.selectionScreenBounds.bottom;
    final rawTop = placeBelow
        ? arcOrigin.dy + _arcRadius + 16 // below the arc
        : selBottom + 12; // below the selection when arc is above
    final maxTop = viewSize.height - 300.0;
    final panelTop = rawTop.clamp(60.0, maxTop);

    return Positioned(
      left: panelLeft,
      top: panelTop,
      child: ScaleTransition(
        scale: _expandAnim,
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: _expandAnim,
          // No BackdropFilter — solid bg is 60fps
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: viewSize.height - panelTop - 40,
            ),
            child: Container(
              width: panelWidth,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF101016), // solid dark, no blur needed
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _accent.withValues(alpha: 0.10), width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _section('TRANSFORM', [
                    _PanelItem(Icons.rotate_90_degrees_ccw_rounded,
                        'Rotate', _accent, widget.onRotate),
                    _PanelItem(Icons.flip, 'Flip H', _accentDim,
                        widget.onFlipHorizontal),
                    _PanelItem(Icons.flip, 'Flip V', _accentDim,
                        widget.onFlipVertical, rotation: 90),
                  ]),
                  const SizedBox(height: 8),
                  _section('ARRANGE', [
                    if (widget.onBringToFront != null)
                      _PanelItem(Icons.flip_to_front_rounded, 'Front',
                          _accent, widget.onBringToFront!),
                    if (widget.onSendToBack != null)
                      _PanelItem(Icons.flip_to_back_rounded, 'Back',
                          _accentDim, widget.onSendToBack!),
                    if (widget.onGroup != null)
                      _PanelItem(Icons.group_work_rounded, 'Group',
                          _accent, widget.onGroup!),
                    if (widget.onUngroup != null)
                      _PanelItem(Icons.workspaces_outline, 'Ungroup',
                          _accentDim, widget.onUngroup!),
                    if (widget.onLock != null)
                      _PanelItem(
                        widget.isSelectionLocked
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        widget.isSelectionLocked ? 'Unlock' : 'Lock',
                        widget.isSelectionLocked ? _danger : _subtle,
                        () => widget.isSelectionLocked
                            ? widget.onUnlock?.call()
                            : widget.onLock!(),
                      ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<_PanelItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 5),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              letterSpacing: 1.5,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: items
              .map((item) => _ArcButton(
                    action: _HaloAction(
                        item.icon, item.label, item.color, item.onTap,
                        rotation: item.rotation),
                    size: 34,
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Data
// ═══════════════════════════════════════════════════════════════════════

class _HaloAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final double rotation;

  const _HaloAction(this.icon, this.label, this.color, this.onTap,
      {this.rotation = 0});
}

class _PanelItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final double rotation;

  const _PanelItem(this.icon, this.label, this.color, this.onTap,
      {this.rotation = 0});
}

// ═══════════════════════════════════════════════════════════════════════
// Arc Button — uniform circles, perfectly symmetric
// ═══════════════════════════════════════════════════════════════════════

class _ArcButton extends StatefulWidget {
  final _HaloAction action;
  final double size;

  const _ArcButton({required this.action, required this.size});

  @override
  State<_ArcButton> createState() => _ArcButtonState();
}

class _ArcButtonState extends State<_ArcButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final s = widget.size;

    return Tooltip(
      message: a.label,
      preferBelow: false,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          HapticFeedback.lightImpact();
          a.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _pressed
                  ? a.color.withValues(alpha: 0.18)
                  : const Color(0xF0121218),
              border: Border.all(
                color: _pressed
                    ? a.color.withValues(alpha: 0.5)
                    : a.color.withValues(alpha: 0.15),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Transform.rotate(
                angle: a.rotation * math.pi / 180,
                child: Icon(
                  a.icon,
                  color: a.color.withValues(alpha: _pressed ? 1.0 : 0.7),
                  size: s * 0.42,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Custom Painters — JARVIS visual details
// ═══════════════════════════════════════════════════════════════════════

/// Thin arc line behind the buttons — the "orbital track"
class _ArcLinePainter extends CustomPainter {
  final Offset center;
  final double radius;
  final double startAngle;
  final double sweepAngle;
  final Color color;

  _ArcLinePainter({
    required this.center,
    required this.radius,
    required this.startAngle,
    required this.sweepAngle,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);

    // Small tick marks at button positions — JARVIS style
    // Draw small 4px ticks at the start / end / center of the arc
    for (final t in [0.0, 0.5, 1.0]) {
      final angle = startAngle + sweepAngle * t;
      final inner = Offset(
        center.dx + (radius - 4) * math.cos(angle),
        center.dy + (radius - 4) * math.sin(angle),
      );
      final outer = Offset(
        center.dx + (radius + 4) * math.cos(angle),
        center.dy + (radius + 4) * math.sin(angle),
      );
      canvas.drawLine(inner, outer, paint);
    }
  }

  @override
  bool shouldRepaint(_ArcLinePainter old) =>
      center != old.center || radius != old.radius;
}

/// Thin connector line from selection to arc origin
class _ConnectorPainter extends CustomPainter {
  final Offset from;
  final Offset to;
  final Color color;

  _ConnectorPainter({
    required this.from,
    required this.to,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        from,
        to,
        [
          color.withValues(alpha: 0.06),
          color.withValues(alpha: 0.18),
          color.withValues(alpha: 0.06),
        ],
        [0.0, 0.5, 1.0],
      )
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(from, to, paint);

    // Small diamond at midpoint — JARVIS detail
    final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
    final diamondPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final d = 2.5;
    final diamond = Path()
      ..moveTo(mid.dx, mid.dy - d)
      ..lineTo(mid.dx + d, mid.dy)
      ..lineTo(mid.dx, mid.dy + d)
      ..lineTo(mid.dx - d, mid.dy)
      ..close();
    canvas.drawPath(diamond, diamondPaint);
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) =>
      from != old.from || to != old.to;
}

/// Subtle rounded-rect frame around the selection area
class _SelectionFramePainter extends CustomPainter {
  final Rect bounds;
  final Color color;

  _SelectionFramePainter({required this.bounds, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Slightly inflated rounded rect
    final inflated = bounds.inflate(3);
    final rrect = RRect.fromRectAndRadius(inflated, const Radius.circular(4));
    canvas.drawRRect(rrect, paint);

    // Corner accents — small L-shaped marks at each corner (JARVIS detail)
    final cornerLen = 8.0;
    final accentPaint = Paint()
      ..color = color.withValues(alpha: 1.0) // Slightly brighter than frame
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(
        Offset(inflated.left, inflated.top + cornerLen),
        inflated.topLeft,
        accentPaint);
    canvas.drawLine(
        inflated.topLeft,
        Offset(inflated.left + cornerLen, inflated.top),
        accentPaint);
    // Top-right
    canvas.drawLine(
        Offset(inflated.right, inflated.top + cornerLen),
        inflated.topRight,
        accentPaint);
    canvas.drawLine(
        inflated.topRight,
        Offset(inflated.right - cornerLen, inflated.top),
        accentPaint);
    // Bottom-left
    canvas.drawLine(
        Offset(inflated.left, inflated.bottom - cornerLen),
        inflated.bottomLeft,
        accentPaint);
    canvas.drawLine(
        inflated.bottomLeft,
        Offset(inflated.left + cornerLen, inflated.bottom),
        accentPaint);
    // Bottom-right
    canvas.drawLine(
        Offset(inflated.right, inflated.bottom - cornerLen),
        inflated.bottomRight,
        accentPaint);
    canvas.drawLine(
        inflated.bottomRight,
        Offset(inflated.right - cornerLen, inflated.bottom),
        accentPaint);
  }

  @override
  bool shouldRepaint(_SelectionFramePainter old) => bounds != old.bounds;
}
