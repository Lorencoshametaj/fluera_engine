import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../core/nodes/pdf_page_node.dart';
import '../../drawing/brushes/brush_engine.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/pdf_page_model.dart';

/// 🎬 Fullscreen PDF presentation mode overlay.
///
/// Shows one page at a time with swipe/tap navigation.
/// Composites PDF page image + linked strokes for faithful rendering.
class PdfPresentationOverlay extends StatefulWidget {
  final PdfDocumentNode doc;
  final int initialPage;
  final Map<int, List<ProStroke>> pageStrokes;
  final VoidCallback? onExit;

  const PdfPresentationOverlay({
    super.key,
    required this.doc,
    this.initialPage = 0,
    this.pageStrokes = const {},
    this.onExit,
  });

  @override
  State<PdfPresentationOverlay> createState() => _PdfPresentationOverlayState();
}

class _PdfPresentationOverlayState extends State<PdfPresentationOverlay>
    with TickerProviderStateMixin {
  late PageController _controller;
  late int _currentPage;

  // Auto-hide controls
  bool _controlsVisible = true;
  Timer? _hideTimer;
  late final AnimationController _controlsFade;

  // Keyboard
  final FocusNode _focusNode = FocusNode();

  // 🔍 Pinch-to-zoom
  final TransformationController _zoomController = TransformationController();
  bool _isZoomed = false;

  // 🔴 Laser pointer
  Offset? _laserPosition; // null = not showing
  bool _laserActive = false;
  late final AnimationController _laserPulse;

  // ⏱️ Timer
  late final Stopwatch _presentationTimer;
  Timer? _timerTick;
  bool _timerRunning = true;

  // 📑 Thumbnail strip
  bool _thumbnailsVisible = false;
  late final AnimationController _thumbFade;
  late final ScrollController _thumbScroll;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _controller = PageController(initialPage: _currentPage);
    _controlsFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );

    _laserPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _thumbFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _thumbScroll = ScrollController();

    // Timer
    _presentationTimer = Stopwatch()..start();
    _timerTick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _timerTick?.cancel();
    _controlsFade.dispose();
    _laserPulse.dispose();
    _thumbFade.dispose();
    _thumbScroll.dispose();
    _controller.dispose();
    _zoomController.dispose();
    _focusNode.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  // ── Auto-hide controls ──

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _controlsFade.reverse();
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _showControls() {
    _controlsFade.forward();
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      _controlsFade.reverse();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  // ── Navigation ──

  void _goToPage(int page) {
    final pages = widget.doc.pageNodes;
    if (page < 0 || page >= pages.length) return;
    HapticFeedback.selectionClick();
    // Reset zoom when changing pages
    _resetZoom();
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
    _showControls();
  }

  void _exit() {
    widget.onExit?.call();
    Navigator.of(context).maybePop();
  }

  // ── Keyboard ──

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.space:
        _goToPage(_currentPage + 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _goToPage(_currentPage - 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _exit();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyT:
        _toggleThumbnails();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  // ── Pinch-to-zoom + Double-tap zoom ──

  void _resetZoom() {
    _zoomController.value = Matrix4.identity();
    _isZoomed = false;
  }

  void _onDoubleTapDown(TapDownDetails details) {
    if (_isZoomed) {
      // Zoom out
      _zoomController.value = Matrix4.identity();
      _isZoomed = false;
    } else {
      // Zoom in 2.5x centered on tap position
      final position = details.localPosition;
      // Compute zoom-in matrix centered on tap position
      final s = 2.5;
      final tx = (1 - s) * position.dx;
      final ty = (1 - s) * position.dy;
      final matrix =
          Matrix4.identity()
            ..[0] = s
            ..[5] = s
            ..[10] = 1.0
            ..[12] = tx
            ..[13] = ty;
      _zoomController.value = matrix;
      _isZoomed = true;
    }
    HapticFeedback.mediumImpact();
    setState(() {});
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    // Check if zoomed
    final scale = _zoomController.value.getMaxScaleOnAxis();
    final wasZoomed = _isZoomed;
    _isZoomed = scale > 1.05;
    if (wasZoomed != _isZoomed) setState(() {});
  }

  // ── Laser pointer ──

  void _onLaserStart(LongPressStartDetails details) {
    HapticFeedback.heavyImpact();
    setState(() {
      _laserActive = true;
      _laserPosition = details.localPosition;
    });
  }

  void _onLaserUpdate(LongPressMoveUpdateDetails details) {
    setState(() => _laserPosition = details.localPosition);
  }

  void _onLaserEnd(LongPressEndDetails details) {
    setState(() {
      _laserActive = false;
      _laserPosition = null;
    });
  }

  // ── Timer ──

  void _toggleTimer() {
    setState(() {
      if (_timerRunning) {
        _presentationTimer.stop();
      } else {
        _presentationTimer.start();
      }
      _timerRunning = !_timerRunning;
    });
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$mins:$secs';
    }
    return '$mins:$secs';
  }

  // ── Thumbnails ──

  void _toggleThumbnails() {
    if (_thumbnailsVisible) {
      _thumbFade.reverse();
    } else {
      _thumbFade.forward();
      // Scroll to current page
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_thumbScroll.hasClients) {
          final target = _currentPage * 76.0; // 64 + 12 margin
          _thumbScroll.animateTo(
            target.clamp(0, _thumbScroll.position.maxScrollExtent),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
    setState(() => _thumbnailsVisible = !_thumbnailsVisible);
    _showControls();
  }

  // ════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final pages = widget.doc.pageNodes;
    final cs = Theme.of(context).colorScheme;
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final elapsed = _presentationTimer.elapsed;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Material(
        color: Colors.black,
        child: Stack(
          children: [
            // ── Page content with swipe + pinch-to-zoom ──
            GestureDetector(
              onDoubleTapDown: _onDoubleTapDown,
              onLongPressStart: _onLaserStart,
              onLongPressMoveUpdate: _onLaserUpdate,
              onLongPressEnd: _onLaserEnd,
              child: PageView.builder(
                controller: _controller,
                physics:
                    _isZoomed
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                itemCount: pages.length,
                onPageChanged: (i) {
                  setState(() => _currentPage = i);
                  _resetZoom();
                  _showControls();
                },
                itemBuilder: (context, index) {
                  final page = pages[index];
                  final size = page.pageModel.originalSize;
                  final image = page.cachedImage;
                  final strokes = widget.pageStrokes[index];

                  return Center(
                    child: AspectRatio(
                      aspectRatio: size.width / size.height,
                      child: InteractiveViewer(
                        transformationController: _zoomController,
                        minScale: 1.0,
                        maxScale: 5.0,
                        onInteractionUpdate: _onInteractionUpdate,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 32,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: CustomPaint(
                              painter: _PresentationPagePainter(
                                pageImage: image,
                                pageSize: size,
                                pagePosition: page.position,
                                strokes: strokes ?? const [],
                                background: page.pageModel.background,
                                isBlank: page.pageModel.isBlank,
                              ),
                              size: Size.infinite,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Tap zones (only when NOT zoomed) ──
            if (!_isZoomed)
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _goToPage(_currentPage - 1),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _toggleControls,
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _goToPage(_currentPage + 1),
                      ),
                    ),
                  ],
                ),
              ),

            // ── 🔴 Laser pointer ──
            if (_laserActive && _laserPosition != null)
              Positioned(
                left: _laserPosition!.dx - 12,
                top: _laserPosition!.dy - 12,
                child: AnimatedBuilder(
                  animation: _laserPulse,
                  builder: (context, _) {
                    final scale = 1.0 + _laserPulse.value * 0.3;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red.withValues(alpha: 0.85),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.5),
                              blurRadius: 16,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            // ── Top bar (auto-hide) ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _controlsFade,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Container(
                    padding: EdgeInsets.only(
                      top: safeTop + 8,
                      left: 12,
                      right: 12,
                      bottom: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        // Close button
                        _pillButton(Icons.close_rounded, _exit),
                        const SizedBox(width: 8),
                        // Thumbnail toggle
                        _pillButton(
                          Icons.grid_view_rounded,
                          _toggleThumbnails,
                          isActive: _thumbnailsVisible,
                          activeColor: cs.primary,
                        ),
                        const Spacer(),
                        // Page counter pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Text(
                            '${_currentPage + 1}  ⁄  ${pages.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Timer
                        GestureDetector(
                          onTap: _toggleTimer,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _timerRunning
                                      ? Icons.timer_rounded
                                      : Icons.pause_rounded,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _formatDuration(elapsed),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom: dots/progress (auto-hide) ──
            Positioned(
              bottom: _thumbnailsVisible ? safeBottom + 100 : safeBottom + 12,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _controlsFade,
                child: Center(
                  child:
                      pages.length <= 20
                          ? _buildDotIndicator(pages.length, cs)
                          : _buildProgressBar(pages.length, cs),
                ),
              ),
            ),

            // ── 📑 Thumbnail strip ──
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _thumbFade,
                child: IgnorePointer(
                  ignoring: !_thumbnailsVisible,
                  child: Container(
                    height: safeBottom + 90,
                    padding: EdgeInsets.only(bottom: safeBottom + 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: ListView.builder(
                      controller: _thumbScroll,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: pages.length,
                      itemBuilder: (context, index) {
                        final page = pages[index];
                        final size = page.pageModel.originalSize;
                        final isActive = index == _currentPage;
                        final thumbHeight = 64.0;
                        final thumbWidth =
                            thumbHeight * (size.width / size.height);

                        return GestureDetector(
                          onTap: () => _goToPage(index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: thumbWidth,
                            height: thumbHeight,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color:
                                    isActive
                                        ? cs.primary
                                        : Colors.white.withValues(alpha: 0.2),
                                width: isActive ? 2 : 1,
                              ),
                              boxShadow:
                                  isActive
                                      ? [
                                        BoxShadow(
                                          color: cs.primary.withValues(
                                            alpha: 0.4,
                                          ),
                                          blurRadius: 8,
                                        ),
                                      ]
                                      : null,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child:
                                  page.cachedImage != null
                                      ? RawImage(
                                        image: page.cachedImage,
                                        fit: BoxFit.cover,
                                      )
                                      : CustomPaint(
                                        painter: _PresentationPagePainter(
                                          pageImage: null,
                                          pageSize: size,
                                          pagePosition: page.position,
                                          strokes: const [],
                                          background: page.pageModel.background,
                                          isBlank: page.pageModel.isBlank,
                                        ),
                                      ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            // ── Zoom indicator badge ──
            if (_isZoomed)
              Positioned(
                top: safeTop + 64,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.zoom_in_rounded,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_zoomController.value.getMaxScaleOnAxis().toStringAsFixed(1)}×',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Shared pill button ──

  Widget _pillButton(
    IconData icon,
    VoidCallback onTap, {
    bool isActive = false,
    Color? activeColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              isActive
                  ? (activeColor ?? Colors.white).withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  // ── Dot indicator ──

  Widget _buildDotIndicator(int total, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final isActive = i == _currentPage;
        return GestureDetector(
          onTap: () => _goToPage(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isActive ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color:
                  isActive ? cs.primary : Colors.white.withValues(alpha: 0.35),
            ),
          ),
        );
      }),
    );
  }

  // ── Progress bar ──

  Widget _buildProgressBar(int total, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: total > 1 ? _currentPage / (total - 1) : 1.0,
          minHeight: 3,
          backgroundColor: Colors.white.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation(cs.primary),
        ),
      ),
    );
  }
}

/// 🎨 Composited page painter — renders PDF image + strokes in page-local coords.
class _PresentationPagePainter extends CustomPainter {
  final ui.Image? pageImage;
  final Size pageSize;
  final Offset pagePosition;
  final List<ProStroke> strokes;
  final PdfPageBackground background;
  final bool isBlank;

  const _PresentationPagePainter({
    required this.pageImage,
    required this.pageSize,
    required this.pagePosition,
    required this.strokes,
    this.background = PdfPageBackground.blank,
    this.isBlank = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1) Draw the PDF page image or background pattern for blank pages
    if (pageImage != null) {
      final src = Rect.fromLTWH(
        0,
        0,
        pageImage!.width.toDouble(),
        pageImage!.height.toDouble(),
      );
      final dst = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawImageRect(pageImage!, src, dst, Paint());
    }

    // 1b) Draw background pattern for blank pages
    if (isBlank && background != PdfPageBackground.blank) {
      _drawPresentationBackground(canvas, size);
    }

    // 2) Draw strokes on top, transformed from canvas-space to page-local-space
    if (strokes.isNotEmpty) {
      // Scale factor from page-space to widget-space
      final scaleX = size.width / pageSize.width;
      final scaleY = size.height / pageSize.height;

      canvas.save();
      canvas.scale(scaleX, scaleY);
      // Translate so page origin maps to (0,0)
      canvas.translate(-pagePosition.dx, -pagePosition.dy);

      for (final stroke in strokes) {
        if (stroke.isFill) {
          // Fill overlays — skip for presentation (rare)
          continue;
        }
        BrushEngine.renderStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
          stroke.penType,
          stroke.settings,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PresentationPagePainter old) =>
      old.pageImage != pageImage ||
      old.strokes != strokes ||
      old.pageSize != pageSize ||
      old.background != background;

  /// Draw background pattern scaled to the presentation widget size.
  void _drawPresentationBackground(Canvas canvas, Size widgetSize) {
    // Scale from page coordinates to widget coordinates
    final sx = widgetSize.width / pageSize.width;
    final sy = widgetSize.height / pageSize.height;
    canvas.save();
    canvas.scale(sx, sy);
    final pageRect = Rect.fromLTWH(0, 0, pageSize.width, pageSize.height);

    switch (background) {
      case PdfPageBackground.blank:
        break;
      case PdfPageBackground.ruled:
        _drawRuled(canvas, pageRect);
      case PdfPageBackground.grid:
        _drawGrid(canvas, pageRect);
      case PdfPageBackground.dotted:
        _drawDotted(canvas, pageRect);
      case PdfPageBackground.music:
        _drawMusic(canvas, pageRect);
      case PdfPageBackground.cornell:
        _drawCornell(canvas, pageRect);
    }
    canvas.restore();
  }

  void _drawRuled(Canvas canvas, Rect r) {
    const spacing = 28.0;
    const marginTop = 80.0;
    final paint =
        Paint()
          ..color = const Color(0x3090CAF9)
          ..strokeWidth = 0.8;
    for (double y = r.top + marginTop; y < r.bottom; y += spacing) {
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), paint);
    }
    // Red margin line
    final marginPaint =
        Paint()
          ..color = const Color(0x30E53935)
          ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(r.left + 72, r.top),
      Offset(r.left + 72, r.bottom),
      marginPaint,
    );
  }

  void _drawGrid(Canvas canvas, Rect r) {
    const spacing = 28.0;
    final paint =
        Paint()
          ..color = const Color(0x2090CAF9)
          ..strokeWidth = 0.5;
    for (double x = r.left; x <= r.right; x += spacing) {
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), paint);
    }
    for (double y = r.top; y <= r.bottom; y += spacing) {
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), paint);
    }
  }

  void _drawDotted(Canvas canvas, Rect r) {
    const spacing = 28.0;
    final paint = Paint()..color = const Color(0x30000000);
    for (double x = r.left + spacing; x < r.right; x += spacing) {
      for (double y = r.top + spacing; y < r.bottom; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  void _drawMusic(Canvas canvas, Rect r) {
    const lineSpacing = 10.0;
    const staffSpacing = 80.0;
    const marginTop = 60.0;
    final paint =
        Paint()
          ..color = const Color(0x30000000)
          ..strokeWidth = 0.6;
    for (
      double staffY = r.top + marginTop;
      staffY + 4 * lineSpacing < r.bottom;
      staffY += staffSpacing
    ) {
      for (int i = 0; i < 5; i++) {
        final y = staffY + i * lineSpacing;
        canvas.drawLine(Offset(r.left + 40, y), Offset(r.right - 20, y), paint);
      }
    }
  }

  void _drawCornell(Canvas canvas, Rect r) {
    final paint =
        Paint()
          ..color = const Color(0x25000000)
          ..strokeWidth = 1.0;
    // Left cue column
    canvas.drawLine(
      Offset(r.left + r.width * 0.3, r.top),
      Offset(r.left + r.width * 0.3, r.bottom - r.height * 0.2),
      paint,
    );
    // Bottom summary area
    canvas.drawLine(
      Offset(r.left, r.bottom - r.height * 0.2),
      Offset(r.right, r.bottom - r.height * 0.2),
      paint,
    );
  }
}
