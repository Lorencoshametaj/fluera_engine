import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../canvas/fluera_canvas_config.dart';
import '../core/models/pdf_document_model.dart';
import '../core/models/pdf_page_model.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../drawing/brushes/brush_engine.dart';
import '../drawing/models/pro_brush_settings.dart';
import 'package:fluera_engine/src/rendering/gpu/vulkan_stroke_overlay_service.dart';

/// Reading mode for PDF pages.
enum _ReadingMode { light, dark, sepia }

/// 📖 Full-screen PDF reader with annotation support.
///
/// Renders pages via [FlueraPdfProvider.renderPage] and overlays
/// a self-contained drawing system using [BrushEngine.renderStroke].
class PdfReaderScreen extends StatefulWidget {
  final PdfDocumentModel documentModel;
  final FlueraPdfProvider provider;
  final String documentId;
  final void Function(PdfDocumentModel updatedModel)? onClose;

  const PdfReaderScreen({
    super.key,
    required this.documentModel,
    required this.provider,
    required this.documentId,
    this.onClose,
  });

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen>
    with TickerProviderStateMixin {
  late final TransformationController _zoomController;
  late final List<ui.Image?> _pageImages;

  int _currentPageIndex = 0;
  bool _showSidebar = false;
  bool _isAnimatingIn = true;

  /// Whether a zoom-out exit has been triggered (prevent double-pop).
  bool _zoomOutExitTriggered = false;

  /// Current interactive zoom scale.
  double _currentZoomScale = 1.0;

  /// Animation controller for smooth zoom transitions.
  AnimationController? _zoomAnimController;
  Matrix4? _zoomAnimStart;
  Matrix4? _zoomAnimEnd;

  /// Reading mode (light / dark / sepia).
  _ReadingMode _readingMode = _ReadingMode.light;

  /// Auto-hide chrome (top bar + bottom bar).
  bool _showChrome = true;
  Timer? _chromeHideTimer;

  /// Swipe-down-to-dismiss state.
  double _swipeDismissOffset = 0;
  bool _isSwiping = false;
  AnimationController? _swipeSnapController;

  /// Brightness adjustment (1.0 = normal, range 0.3-2.0).
  double _brightness = 1.0;
  bool _isBrightnessAdjusting = false;

  /// File info cached.
  String? _pdfFileSizeStr;

  /// Track the render-scale each page was rendered at.
  final Map<int, double> _pageRenderScale = {};

  // ---------------------------------------------------------------------------
  // Drawing state
  // ---------------------------------------------------------------------------

  /// Whether annotation mode is active (pen/eraser).
  bool _isDrawingMode = false;

  /// Whether eraser is active (vs pen).
  bool _isErasing = false;

  /// Current pen settings.
  Color _penColor = const Color(0xFF1A1A2E);
  double _penWidth = 2.5;
  ProPenType _penType = ProPenType.ballpoint;

  /// Live stroke in progress (PDF-page coordinates).
  List<ProDrawingPoint>? _livePoints;
  int? _livePageIndex;

  /// Committed strokes per page (in PDF-page coordinate space).
  final Map<int, List<ProStroke>> _pageStrokes = {};

  // ---------------------------------------------------------------------------
  // Vulkan live stroke overlay
  // ---------------------------------------------------------------------------
  final VulkanStrokeOverlayService _vulkanOverlay = VulkanStrokeOverlayService();
  int? _vulkanTextureId;
  bool _vulkanActive = false;

  /// Preset colors for the quick color picker.
  static const _colorPresets = [
    Color(0xFF1A1A2E), // Dark navy
    Color(0xFFE74C3C), // Red
    Color(0xFF2ECC71), // Green
    Color(0xFF3498DB), // Blue
    Color(0xFFF39C12), // Orange
    Color(0xFF9B59B6), // Purple
    Color(0xFF1ABC9C), // Teal
  ];

  @override
  void initState() {
    super.initState();
    _zoomController = TransformationController();
    _zoomController.addListener(_onZoomChanged);

    final pageCount = widget.documentModel.totalPages;
    _pageImages = List<ui.Image?>.filled(pageCount, null);

    // Load existing annotations from model
    _loadAnnotationsFromModel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _isAnimatingIn = false);
        _renderAllPages();
        _computePdfFileSize();
        _startChromeHideTimer();
      }
    });
  }

  void _computePdfFileSize() {
    try {
      // Try to get file size from the document model path or provider
      final totalPages = widget.documentModel.totalPages;
      _pdfFileSizeStr = '$totalPages ${totalPages == 1 ? 'page' : 'pages'}';
    } catch (_) {}
  }

  /// Starts/resets the auto-hide chrome timer.
  void _startChromeHideTimer() {
    _chromeHideTimer?.cancel();
    if (!_showChrome) {
      setState(() => _showChrome = true);
    }
    _chromeHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _isDrawingMode) return;
      if (_showChrome) {
        setState(() => _showChrome = false);
      }
    });
  }

  /// Toggle chrome visibility on tap.
  void _toggleChrome() {
    setState(() => _showChrome = !_showChrome);
    if (_showChrome) {
      _startChromeHideTimer();
    }
  }

  /// Lazily initialize Vulkan overlay when drawing mode is first activated.
  void _initVulkanIfNeeded() {
    if (_vulkanActive || _vulkanTextureId != null) return;
    _vulkanOverlay.isAvailable.then((available) {
      if (!available || !mounted) return;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final size = MediaQuery.of(context).size;
      final pw = (size.width * dpr).toInt();
      final ph = (size.height * dpr).toInt();
      _vulkanOverlay.init(pw, ph).then((id) {
        if (id != null && mounted) {
          _vulkanOverlay.setScreenSpaceTransform(pw, ph, dpr);
          setState(() {
            _vulkanTextureId = id;
            _vulkanActive = true;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _chromeHideTimer?.cancel();
    _swipeSnapController?.dispose();
    _vulkanOverlay.dispose();
    _zoomAnimController?.dispose();
    _zoomController.dispose();
    for (final img in _pageImages) {
      img?.dispose();
    }
    super.dispose();
  }

  void _loadAnnotationsFromModel() {
    // Load any serialized ink annotations from the document model
    for (int i = 0; i < widget.documentModel.totalPages; i++) {
      final page = widget.documentModel.pages[i];
      if (page.annotations.isNotEmpty) {
        // annotations field stores stroke IDs — actual strokes stored separately
        // For now, start with blank strokes per page
      }
    }
  }

  PdfDocumentModel _buildUpdatedModel() {
    // Return updated model with stroke annotation IDs
    final updatedPages = <PdfPageModel>[];
    for (int i = 0; i < widget.documentModel.totalPages; i++) {
      final page = widget.documentModel.pages[i];
      final strokes = _pageStrokes[i] ?? [];
      final strokeIds = strokes.map((s) => s.id).toList();
      updatedPages.add(page.copyWith(
        annotations: strokeIds,
        lastModifiedAt: DateTime.now().microsecondsSinceEpoch,
      ));
    }
    return widget.documentModel.copyWith(pages: updatedPages);
  }

  // ---------------------------------------------------------------------------
  // PDF page rendering
  // ---------------------------------------------------------------------------

  Future<void> _renderAllPages() async {
    final provider = widget.provider;
    final totalPages = widget.documentModel.totalPages;

    // Only render first few pages initially to avoid OOM
    final initialPages = totalPages.clamp(0, 5);
    for (int i = 0; i < initialPages; i++) {
      if (!mounted) return;
      await _renderPage(i, provider);
    }
  }

  /// Ensure visible pages (current ± 3) are rendered and dispose far-away pages.
  int _lastVisibleCheckPage = -1;
  void _ensureVisiblePagesRendered() {
    final total = widget.documentModel.totalPages;
    final current = _currentPageIndex;
    
    // Skip if we already checked for this page
    if (current == _lastVisibleCheckPage) return;
    _lastVisibleCheckPage = current;
    
    const buffer = 3;

    // Render nearby pages
    for (int i = (current - buffer).clamp(0, total); i < (current + buffer + 1).clamp(0, total); i++) {
      if (_pageImages[i] == null) {
        _renderPage(i, widget.provider);
      }
    }

    // Dispose far-away pages to save memory (keep ±7 pages)
    for (int i = 0; i < total; i++) {
      if ((i - current).abs() > buffer + 4 && _pageImages[i] != null) {
        _pageImages[i]?.dispose();
        _pageImages[i] = null;
        _pageRenderScale.remove(i);
      }
    }
  }

  Future<void> _renderPage(int pageIndex, FlueraPdfProvider provider, {
    double renderScale = 1.0,
  }) async {
    // Check if already rendered at this or higher scale
    final existingScale = _pageRenderScale[pageIndex] ?? 0.0;
    if (existingScale >= renderScale && _pageImages[pageIndex] != null) return;

    final page = widget.documentModel.pages[pageIndex];
    final screenWidth = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    if (screenWidth <= 0) return;

    final targetWidth = (screenWidth * dpr * renderScale).clamp(200.0, 2048.0);
    final scale = (targetWidth / page.originalSize.width).clamp(0.5, 3.0);

    try {
      final image = await provider.renderPage(
        pageIndex: pageIndex,
        scale: scale,
        targetSize: Size(
          targetWidth,
          targetWidth * page.originalSize.height / page.originalSize.width,
        ),
      );

      if (mounted) {
        final oldImage = _pageImages[pageIndex];
        setState(() {
          _pageImages[pageIndex] = image;
          _pageRenderScale[pageIndex] = renderScale;
        });
        // Dispose old lower-res image
        oldImage?.dispose();
      }
    } catch (_) {}
  }


  // ---------------------------------------------------------------------------
  // Drawing input handling
  // ---------------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent event, int pageIndex, Size pageDisplaySize) {
    if (!_isDrawingMode) return;

    final page = widget.documentModel.pages[pageIndex];
    // Transform screen position to PDF-page coordinates
    final scaleX = page.originalSize.width / pageDisplaySize.width;
    final scaleY = page.originalSize.height / pageDisplaySize.height;

    final pos = Offset(
      event.localPosition.dx * scaleX,
      event.localPosition.dy * scaleY,
    );

    if (_isErasing) {
      _eraseAtPoint(pageIndex, pos, page.originalSize);
      return;
    }

    setState(() {
      _livePageIndex = pageIndex;
      _livePoints = [
        ProDrawingPoint(
          position: pos,
          pressure: event.pressure > 0 ? event.pressure : 0.5,
          tiltX: event.tilt,
          timestamp: event.timeStamp.inMilliseconds,
        ),
      ];
    });
  }

  void _onPointerMove(PointerMoveEvent event, int pageIndex, Size pageDisplaySize) {
    if (!_isDrawingMode) return;

    final page = widget.documentModel.pages[pageIndex];
    final scaleX = page.originalSize.width / pageDisplaySize.width;
    final scaleY = page.originalSize.height / pageDisplaySize.height;

    final pos = Offset(
      event.localPosition.dx * scaleX,
      event.localPosition.dy * scaleY,
    );

    if (_isErasing) {
      _eraseAtPoint(pageIndex, pos, page.originalSize);
      return;
    }

    if (_livePoints != null && _livePageIndex == pageIndex) {
      _livePoints!.add(ProDrawingPoint(
        position: pos,
        pressure: event.pressure > 0 ? event.pressure : 0.5,
        tiltX: event.tilt,
        timestamp: event.timeStamp.inMilliseconds,
      ));

      // Forward to Vulkan GPU for real-time rendering.
      // Use global screen coordinates (event.position) since the Vulkan
      // SurfaceTexture spans the entire screen.
      if (_vulkanActive && _livePoints!.length >= 2) {
        _vulkanOverlay.updateAndRender(
          _livePoints!.map((p) {
            // PDF-page coords → screen coords (global)
            final sx = p.position.dx / page.originalSize.width * pageDisplaySize.width;
            final sy = p.position.dy / page.originalSize.height * pageDisplaySize.height;
            // event.position - event.localPosition = page widget's global offset
            final pageGlobalOffset = event.position - event.localPosition;
            return ProDrawingPoint(
              position: Offset(sx + pageGlobalOffset.dx, sy + pageGlobalOffset.dy),
              pressure: p.pressure,
              tiltX: p.tiltX,
              tiltY: p.tiltY,
              timestamp: p.timestamp,
            );
          }).toList(),
          _penColor,
          _penWidth,
          brushType: _penType == ProPenType.pencil ? 2
              : _penType == ProPenType.fountain ? 4
              : 0,
        );
      }

      setState(() {}); // Trigger repaint for annotation overlay
    }
  }

  void _onPointerUp(PointerUpEvent event, int pageIndex, Size pageDisplaySize) {
    if (!_isDrawingMode || _isErasing) return;

    if (_livePoints != null && _livePoints!.length >= 2 && _livePageIndex == pageIndex) {
      // Commit stroke
      final stroke = ProStroke(
        id: 'pdf_${widget.documentId}_p${pageIndex}_${DateTime.now().millisecondsSinceEpoch}',
        points: List.from(_livePoints!),
        color: _penColor,
        baseWidth: _penWidth,
        penType: _penType,
        createdAt: DateTime.now(),
      );

      setState(() {
        _pageStrokes.putIfAbsent(pageIndex, () => []);
        _pageStrokes[pageIndex]!.add(stroke);
        _livePoints = null;
        _livePageIndex = null;
      });

      // Clear Vulkan live stroke overlay
      if (_vulkanActive) _vulkanOverlay.clear();
      HapticFeedback.lightImpact();
    } else {
      if (_vulkanActive) _vulkanOverlay.clear();
      setState(() {
        _livePoints = null;
        _livePageIndex = null;
      });
    }
  }

  void _eraseAtPoint(int pageIndex, Offset pos, Size pageSize) {
    final strokes = _pageStrokes[pageIndex];
    if (strokes == null || strokes.isEmpty) return;

    final eraserRadius = _penWidth * 5;
    final eraserRect = Rect.fromCircle(center: pos, radius: eraserRadius);

    final toRemove = <int>[];
    for (int i = 0; i < strokes.length; i++) {
      if (strokes[i].bounds.overlaps(eraserRect)) {
        toRemove.add(i);
      }
    }

    if (toRemove.isNotEmpty) {
      setState(() {
        for (final idx in toRemove.reversed) {
          strokes.removeAt(idx);
        }
      });
      HapticFeedback.selectionClick();
    }
  }

  void _undoLastStroke() {
    final strokes = _pageStrokes[_currentPageIndex];
    if (strokes != null && strokes.isNotEmpty) {
      setState(() => strokes.removeLast());
      HapticFeedback.lightImpact();
    }
  }

  // ---------------------------------------------------------------------------
  // Scroll & page tracking
  // ---------------------------------------------------------------------------

  void _onScroll() {
    // Page tracking from TransformationController offset
    final yOffset = -_zoomController.value.row1.w;
    final scale = _zoomController.value.getMaxScaleOnAxis();
    final effectiveOffset = yOffset / scale;

    double accumulated = 0;
    for (int i = 0; i < widget.documentModel.totalPages; i++) {
      final pageHeight = _getPageDisplayHeight(i);
      final pageBottom = accumulated + pageHeight;
      final viewportMid = effectiveOffset + MediaQuery.of(context).size.height / 2;

      if (accumulated <= viewportMid && pageBottom > effectiveOffset) {
        if (_currentPageIndex != i) {
          setState(() => _currentPageIndex = i);
        }
        break;
      }
      accumulated += pageHeight + 16.0;
    }

    // Always ensure nearby pages are rendered when scrolling
    _ensureVisiblePagesRendered();
  }

  // ---------------------------------------------------------------------------
  // Pinch-to-zoom & zoom-out-to-exit
  // ---------------------------------------------------------------------------

  void _onZoomChanged() {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    final changed = (_currentZoomScale - scale).abs() > 0.01;
    final previousScale = _currentZoomScale;
    _currentZoomScale = scale;

    // Only rebuild when zoom indicator visibility or exit hint actually changes
    final needsRebuild = changed && mounted && (
      // Zoom indicator visibility changed
      (previousScale - 1.0).abs() <= 0.05 != (scale - 1.0).abs() <= 0.05 ||
      // Exit hint visibility changed  
      (previousScale >= 0.95) != (scale >= 0.95) ||
      // Exit-ready state changed
      (previousScale >= 0.75) != (scale >= 0.75) ||
      // Zoom percentage display changed
      (previousScale * 100).round() != (scale * 100).round()
    );
    
    if (needsRebuild) {
      setState(() {});
    }

    // Update page tracking on every scroll
    if (changed && mounted) {
      _onScroll();
    }

    // Haptic when crossing the exit-ready threshold
    if (previousScale >= 0.70 && scale < 0.70 && !_zoomOutExitTriggered) {
      HapticFeedback.mediumImpact();
    }

    // Zoom-out-to-exit: when scale drops below 0.65, go back to canvas
    if (scale < 0.65 && !_zoomOutExitTriggered) {
      _zoomOutExitTriggered = true;
      HapticFeedback.heavyImpact();
      widget.onClose?.call(_buildUpdatedModel());
      Navigator.of(context).pop();
    }
  }

  /// Called when the pinch gesture ends — snap back or exit.
  void _onInteractionEnd(ScaleEndDetails details) {
    final scale = _zoomController.value.getMaxScaleOnAxis();

    // Exit if released at low zoom
    if (scale < 0.75 && !_zoomOutExitTriggered) {
      _zoomOutExitTriggered = true;
      HapticFeedback.heavyImpact();
      widget.onClose?.call(_buildUpdatedModel());
      Navigator.of(context).pop();
      return;
    }

    // If zoomed out at all, snap back smoothly
    if (scale < 0.95 && !_zoomOutExitTriggered) {
      // Preserve current scroll offset, just reset scale
      final currentY = _zoomController.value.row1.w;
      // ignore: deprecated_member_use
      final target = Matrix4.identity()..translate(0.0, currentY);
      _animateZoomTo(target);
    }
  }

  // ---------------------------------------------------------------------------
  // Swipe down to dismiss
  // ---------------------------------------------------------------------------

  void _onSwipeDragUpdate(DragUpdateDetails d) {
    if (_currentZoomScale > 1.05 || _isDrawingMode) return;
    setState(() {
      _isSwiping = true;
      _swipeDismissOffset += d.delta.dy;
    });
  }

  void _onSwipeDragEnd(DragEndDetails d) {
    if (!_isSwiping) return;
    final velocity = d.velocity.pixelsPerSecond.dy;
    if (_swipeDismissOffset.abs() > 120 || velocity.abs() > 800) {
      HapticFeedback.mediumImpact();
      widget.onClose?.call(_buildUpdatedModel());
      Navigator.of(context).pop();
    } else {
      // Rubber-band snap back
      _swipeSnapController?.dispose();
      final startOffset = _swipeDismissOffset;
      final ctrl = AnimationController(
        duration: const Duration(milliseconds: 350), vsync: this,
      );
      _swipeSnapController = ctrl;
      final curved = CurvedAnimation(
        parent: ctrl,
        curve: const Cubic(0.34, 1.56, 0.64, 1.0),
      );
      curved.addListener(() {
        if (mounted) {
          setState(() {
            _swipeDismissOffset = startOffset * (1.0 - curved.value);
          });
        }
      });
      ctrl.addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() {
            _swipeDismissOffset = 0;
            _isSwiping = false;
          });
        }
      });
      ctrl.forward();
    }
  }

  /// Double-tap: toggle between 1x and 2.5x zoom centered on tap.
  void _onDoubleTapZoom(TapDownDetails details) {
    final currentScale = _zoomController.value.getMaxScaleOnAxis();

    if (currentScale > 1.5) {
      // Animate back to 1x, preserving scroll position
      final currentY = _zoomController.value.row1.w;
      // ignore: deprecated_member_use
      final target = Matrix4.identity()..translate(0.0, currentY);
      _animateZoomTo(target);
    } else {
      // Animate to 2.5x centered on tap position
      final position = details.localPosition;
      const targetScale = 2.5;
      // ignore: deprecated_member_use
      final matrix = Matrix4.identity()
        ..translate(position.dx, position.dy) // ignore: deprecated_member_use
        ..scale(targetScale) // ignore: deprecated_member_use
        ..translate(-position.dx, -position.dy); // ignore: deprecated_member_use
      _animateZoomTo(matrix);
    }
  }

  /// Smoothly animate the zoom transformation.
  void _animateZoomTo(Matrix4 target) {
    _zoomAnimController?.dispose();
    _zoomAnimStart = _zoomController.value.clone();
    _zoomAnimEnd = target;

    final controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _zoomAnimController = controller;

    final curve = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );

    curve.addListener(() {
      if (!mounted) return;
      final t = curve.value;
      // Lerp each element of the 4x4 matrix
      final start = _zoomAnimStart!;
      final end = _zoomAnimEnd!;
      final result = Matrix4.zero();
      for (int i = 0; i < 16; i++) {
        result.storage[i] = start.storage[i] + (end.storage[i] - start.storage[i]) * t;
      }
      _zoomController.value = result;
    });

    curve.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
        if (_zoomAnimController == controller) {
          _zoomAnimController = null;
        }
      }
    });

    controller.forward();
  }

  double _getPageDisplayHeight(int pageIndex) {
    final page = widget.documentModel.pages[pageIndex];
    final screenWidth = MediaQuery.sizeOf(context).width - (_showSidebar ? 120 : 0) - 32;
    return screenWidth * page.originalSize.height / page.originalSize.width;
  }

  void _scrollToPage(int pageIndex) {
    double offset = 16; // top padding
    for (int i = 0; i < pageIndex; i++) {
      offset += _getPageDisplayHeight(i) + 16.0;
    }
    // ignore: deprecated_member_use
    final target = Matrix4.identity()..translate(0.0, -offset);
    _animateZoomTo(target);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final totalPages = widget.documentModel.totalPages;

    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF1A1A2E),
          primary: Color(0xFF6C63FF),
          onSurface: Colors.white,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          color: const Color(0xFF1A1A2E),
          child: SafeArea(
            child: Builder(
              builder: (context) {
                final swipeProgress = (_swipeDismissOffset.abs() / 300).clamp(0.0, 1.0);
                final dismissOpacity = (1.0 - swipeProgress * 0.6).clamp(0.0, 1.0);
                final dismissScale = (1.0 - swipeProgress * 0.15).clamp(0.7, 1.0);
                final dismissTilt = swipeProgress * 0.03 * (_swipeDismissOffset > 0 ? 1 : -1);

                return AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _isAnimatingIn ? 0.0 : 1.0,
                  child: Opacity(
                    opacity: dismissOpacity,
                    child: Transform.scale(
                      scale: dismissScale,
                      child: Transform.rotate(
                        angle: dismissTilt,
                        child: Transform.translate(
                          offset: Offset(0, _swipeDismissOffset),
                          child: Stack(
                            children: [
                              // ── Main content area ──
                              Column(
                                children: [
                                  // Animated space for top bar
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    height: _showChrome ? 56 : 0,
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: _isDrawingMode ? null : _toggleChrome,
                                      onVerticalDragUpdate: _isDrawingMode ? null : _onSwipeDragUpdate,
                                      onVerticalDragEnd: _isDrawingMode ? null : _onSwipeDragEnd,
                                      behavior: HitTestBehavior.translucent,
                                      child: Stack(
                                        children: [
                                          Row(
                                            children: [
                                              if (_showSidebar) _buildThumbnailSidebar(),
                                              Expanded(
                                                child: ColorFiltered(
                                                  colorFilter: ColorFilter.matrix(<double>[
                                                    _brightness, 0, 0, 0, 0,
                                                    0, _brightness, 0, 0, 0,
                                                    0, 0, _brightness, 0, 0,
                                                    0, 0, 0, 1, 0,
                                                  ]),
                                                  child: _buildPageList(),
                                                ),
                                              ),
                                            ],
                                          ),
                                          // 🔥 Vulkan GPU live stroke overlay
                                          if (_vulkanTextureId != null && _isDrawingMode)
                                            Positioned.fill(
                                              child: IgnorePointer(
                                                child: Texture(textureId: _vulkanTextureId!),
                                              ),
                                            ),
                                          // 🔙 Zoom-out exit hint
                                          if (_currentZoomScale < 0.95 && !_isDrawingMode)
                                            _buildZoomExitHint(),
                                          // 🔍 Zoom level indicator
                                          if ((_currentZoomScale - 1.0).abs() > 0.05 && !_isDrawingMode)
                                            Positioned(
                                              top: 12,
                                              right: 12,
                                              child: IgnorePointer(
                                                child: AnimatedOpacity(
                                                  duration: const Duration(milliseconds: 200),
                                                  opacity: 1.0,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 10, vertical: 5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xAA000000),
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(
                                                        color: const Color(0x20FFFFFF), width: 0.5,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '${(_currentZoomScale * 100).round()}%',
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w600,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_isDrawingMode) _buildDrawingToolbar(),
                                  // Animated space for bottom bar
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    height: _showChrome ? 51 : 0,
                                  ),
                                ],
                              ),

                              // ── Brightness drag zone (left edge) ──
                              Positioned(
                                left: 0, top: 0, bottom: 0, width: 44,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onVerticalDragStart: (_) {
                                    setState(() => _isBrightnessAdjusting = true);
                                    HapticFeedback.selectionClick();
                                  },
                                  onVerticalDragUpdate: (d) {
                                    setState(() {
                                      _brightness = (_brightness - d.delta.dy * 0.005)
                                          .clamp(0.3, 2.0);
                                    });
                                  },
                                  onVerticalDragEnd: (_) {
                                    setState(() => _isBrightnessAdjusting = false);
                                  },
                                  child: Container(color: Colors.transparent),
                                ),
                              ),

                              // ── Brightness indicator badge ──
                              if (_isBrightnessAdjusting || (_brightness - 1.0).abs() > 0.05)
                                Positioned(
                                  left: 52, top: 80,
                                  child: AnimatedOpacity(
                                    opacity: _isBrightnessAdjusting ? 1.0 : 0.6,
                                    duration: const Duration(milliseconds: 200),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.brightness_6_rounded,
                                            size: 14, color: Colors.white.withValues(alpha: 0.7)),
                                          const SizedBox(width: 6),
                                          Text('${(_brightness * 100).round()}%',
                                            style: const TextStyle(
                                              color: Colors.white, fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                              // ── Swipe dismiss hint ──
                              if (_isSwiping && swipeProgress > 0.1)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: ColoredBox(
                                      color: Colors.black.withValues(alpha: swipeProgress * 0.5),
                                    ),
                                  ),
                                ),

                              // ── Sliding top bar ──
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: AnimatedSlide(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOutCubic,
                                  offset: _showChrome ? Offset.zero : const Offset(0, -1),
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity: _showChrome ? 1.0 : 0.0,
                                    child: _buildTopBar(totalPages),
                                  ),
                                ),
                              ),
                              // ── Sliding bottom bar ──
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: AnimatedSlide(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOutCubic,
                                  offset: _showChrome ? Offset.zero : const Offset(0, 1),
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity: _showChrome ? 1.0 : 0.0,
                                    child: _buildBottomBar(totalPages),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
    );
  }

  Widget _buildTopBar(int totalPages) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF16213E),
        border: Border(bottom: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              widget.onClose?.call(_buildUpdatedModel());
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            tooltip: 'Back to canvas',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.documentModel.fileName ?? 'PDF Document',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_pdfFileSizeStr ?? ''}  •  PDF',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45), fontSize: 12,
                    fontWeight: FontWeight.w500, letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          // Undo button (visible when drawing mode is on)
          if (_isDrawingMode)
            IconButton(
              onPressed: _undoLastStroke,
              icon: const Icon(Icons.undo_rounded, color: Colors.white70),
              tooltip: 'Undo',
            ),
          // Drawing mode toggle
          IconButton(
            onPressed: () {
              setState(() {
                _isDrawingMode = !_isDrawingMode;
                if (!_isDrawingMode) _isErasing = false;
              });
              if (_isDrawingMode) _initVulkanIfNeeded();
            },
            icon: Icon(
              _isDrawingMode ? Icons.edit : Icons.edit_outlined,
              color: _isDrawingMode ? const Color(0xFF6C63FF) : Colors.white70,
            ),
            tooltip: _isDrawingMode ? 'Exit drawing' : 'Annotate',
          ),
          // Reading mode toggle (light → dark → sepia → light)
          IconButton(
            onPressed: () {
              setState(() {
                _readingMode = _ReadingMode.values[
                  (_readingMode.index + 1) % _ReadingMode.values.length
                ];
              });
            },
            icon: Icon(
              _readingMode == _ReadingMode.dark
                  ? Icons.dark_mode_rounded
                  : _readingMode == _ReadingMode.sepia
                      ? Icons.coffee_rounded
                      : Icons.light_mode_rounded,
              color: _readingMode == _ReadingMode.dark
                  ? const Color(0xFF90CAF9)
                  : _readingMode == _ReadingMode.sepia
                      ? const Color(0xFFFFA726)
                      : Colors.white70,
            ),
            tooltip: _readingMode == _ReadingMode.light
                ? 'Dark mode'
                : _readingMode == _ReadingMode.dark
                    ? 'Sepia mode'
                    : 'Light mode',
          ),
          IconButton(
            onPressed: () => setState(() => _showSidebar = !_showSidebar),
            icon: Icon(
              _showSidebar ? Icons.view_sidebar : Icons.view_sidebar_outlined,
              color: _showSidebar ? const Color(0xFF6C63FF) : Colors.white70,
            ),
            tooltip: 'Toggle thumbnails',
          ),
        ],
      ),
    );
  }

  Widget _buildDrawingToolbar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        // Glassmorphism: semi-transparent dark with blur
        color: const Color(0xCC0D1B2A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0x20FFFFFF),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.08),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
          const BoxShadow(
            color: Color(0x40000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
        children: [
          // ── Pen / Eraser segment ──
          _premiumToolPill(
            icon: Icons.edit_rounded,
            isActive: !_isErasing,
            onTap: () => setState(() => _isErasing = false),
          ),
          const SizedBox(width: 2),
          _premiumToolPill(
            icon: Icons.cleaning_services_rounded,
            isActive: _isErasing,
            onTap: () => setState(() => _isErasing = true),
          ),

          _separator(),

          // ── Pen type chips (segmented) ──
          _premiumPenChip(ProPenType.ballpoint, '✒️'),
          _premiumPenChip(ProPenType.fountain, '🖋️'),
          _premiumPenChip(ProPenType.pencil, '✏️'),
          _premiumPenChip(ProPenType.highlighter, '🖍️'),

          _separator(),

          // ── Color palette ──
          ...List.generate(_colorPresets.length, (i) {
            final c = _colorPresets[i];
            final isActive = _penColor.toARGB32() == c.toARGB32();
            return GestureDetector(
              onTap: () => setState(() => _penColor = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: isActive ? 26 : 20,
                height: isActive ? 26 : 20,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive ? Colors.white : const Color(0x30FFFFFF),
                    width: isActive ? 2.5 : 1,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: c.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            );
          }),

          const SizedBox(width: 8),

          // ── Width preview + slider ──
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: (_penWidth * 2.5).clamp(6.0, 20.0),
            height: (_penWidth * 2.5).clamp(6.0, 20.0),
            decoration: BoxDecoration(
              color: _penColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _penColor.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 72,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: const Color(0xFF6C63FF),
                inactiveTrackColor: const Color(0x20FFFFFF),
                thumbColor: Colors.white,
                overlayColor: const Color(0x206C63FF),
              ),
              child: Slider(
                value: _penWidth,
                min: 0.5,
                max: 8.0,
                onChanged: (v) => setState(() => _penWidth = v),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _premiumToolPill({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isActive ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 18,
          color: isActive ? Colors.white : const Color(0x80FFFFFF),
        ),
      ),
    );
  }

  Widget _premiumPenChip(ProPenType type, String emoji) {
    final isActive = _penType == type && !_isErasing;
    return GestureDetector(
      onTap: () => setState(() {
        _penType = type;
        _isErasing = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: isActive ? const Color(0x25FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? const Color(0x40FFFFFF) : Colors.transparent,
            width: 0.5,
          ),
        ),
        child: Text(
          emoji,
          style: TextStyle(
            fontSize: isActive ? 18 : 15,
          ),
        ),
      ),
    );
  }

  Widget _separator() {
    return Container(
      height: 24,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0x30FFFFFF),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailSidebar() {
    return Container(
      width: 100,
      decoration: const BoxDecoration(
        color: Color(0xFF0F3460),
        border: Border(right: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: widget.documentModel.totalPages,
        itemBuilder: (context, index) {
          final isActive = index == _currentPageIndex;
          final page = widget.documentModel.pages[index];
          final aspect = page.originalSize.height / page.originalSize.width;
          final img = _pageImages[index];

          return GestureDetector(
            onTap: () => _scrollToPage(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive ? const Color(0xFF6C63FF) : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80 * aspect,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: img != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: RawImage(image: img, fit: BoxFit.cover),
                          )
                        : Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Color(0xFF999999), fontSize: 18,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isActive ? const Color(0xFF6C63FF) : Colors.white54,
                        fontSize: 10,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPageList() {
    final screenWidth = MediaQuery.of(context).size.width - (_showSidebar ? 120 : 0);

    return GestureDetector(
      onDoubleTapDown: _isDrawingMode ? null : _onDoubleTapZoom,
      onDoubleTap: () {}, // Required for onDoubleTapDown to fire
      behavior: HitTestBehavior.translucent,
      child: InteractiveViewer(
        transformationController: _zoomController,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: 0.3,
        maxScale: 4.0,
        panEnabled: !_isDrawingMode,
        scaleEnabled: !_isDrawingMode,
        onInteractionEnd: _isDrawingMode ? null : _onInteractionEnd,
        child: SizedBox(
          width: screenWidth,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (int i = 0; i < widget.documentModel.totalPages; i++)
                  RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildPageWidget(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Zoom-out exit hint: vignette + text that appears as scale drops below 0.95.
  Widget _buildZoomExitHint() {
    // Progress from 0→1 as scale goes from 0.95 → 0.65
    final progress = ((0.95 - _currentZoomScale) / 0.30).clamp(0.0, 1.0);
    if (progress <= 0) return const SizedBox.shrink();

    // Exit-ready zone (scale < 0.75)
    final exitReady = _currentZoomScale < 0.75;

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            // Vignette darkening — stronger and earlier
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0x00000000),
                      Color.fromARGB(
                        (progress * 180).round(), 0, 0, 0,
                      ),
                    ],
                    stops: const [0.2, 1.0],
                    radius: 1.1,
                  ),
                ),
              ),
            ),
            // "Release to go back" indicator
            if (progress > 0.15)
              Center(
                child: Opacity(
                  opacity: ((progress - 0.15) / 0.5).clamp(0.0, 1.0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.symmetric(
                      horizontal: exitReady ? 28 : 24,
                      vertical: exitReady ? 14 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: exitReady
                          ? const Color(0xCC6C63FF)
                          : const Color(0x88000000),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: exitReady
                            ? const Color(0x60FFFFFF)
                            : const Color(0x30FFFFFF),
                        width: exitReady ? 1.5 : 0.5,
                      ),
                      boxShadow: exitReady
                          ? [
                              BoxShadow(
                                color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          exitReady
                              ? Icons.check_circle_outline_rounded
                              : Icons.zoom_out_map_rounded,
                          color: Colors.white.withValues(alpha: 0.95),
                          size: exitReady ? 20 : 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          exitReady
                              ? 'Release to go back'
                              : 'Pinch to exit',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontSize: exitReady ? 15 : 14,
                            fontWeight: exitReady
                                ? FontWeight.w600
                                : FontWeight.w500,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageWidget(int pageIndex) {
    final page = widget.documentModel.pages[pageIndex];
    final screenWidth = MediaQuery.sizeOf(context).width - (_showSidebar ? 120 : 0) - 32;
    final aspect = page.originalSize.height / page.originalSize.width;
    final displayHeight = screenWidth * aspect;
    final img = _pageImages[pageIndex];
    final pageDisplaySize = Size(screenWidth, displayHeight);
    final strokes = _pageStrokes[pageIndex] ?? const [];
    final isLivePage = _livePageIndex == pageIndex;
    final isZoomed = _currentZoomScale > 1.1;

    Widget pageContent = Container(
      width: screenWidth,
      height: displayHeight,
      decoration: BoxDecoration(
        color: _readingMode == _ReadingMode.dark
            ? const Color(0xFF2A2A2A)
            : _readingMode == _ReadingMode.sepia
                ? const Color(0xFFF5E6D3)
                : Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Color(_readingMode != _ReadingMode.light ? 0x60000000 : 0x30000000),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            // PDF page image
            if (img != null)
              CustomPaint(
                painter: _DirectPagePainter(
                  image: img,
                  isZoomed: isZoomed,
                ),
                size: pageDisplaySize,
              )
            else
              SizedBox(
                width: screenWidth,
                height: displayHeight,
                child: const _PageShimmer(),
              ),

            // Annotation strokes overlay (committed + live)
            if (strokes.isNotEmpty || (isLivePage && _livePoints != null))
              CustomPaint(
                painter: _AnnotationOverlayPainter(
                  strokes: strokes,
                  livePoints: isLivePage ? _livePoints : null,
                  liveColor: _penColor,
                  liveWidth: _penWidth,
                  livePenType: _penType,
                  pageOriginalSize: page.originalSize,
                  displaySize: pageDisplaySize,
                ),
                size: pageDisplaySize,
              ),

            // Touch input overlay (drawing mode only)
            if (_isDrawingMode)
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _onPointerDown(e, pageIndex, pageDisplaySize),
                onPointerMove: (e) => _onPointerMove(e, pageIndex, pageDisplaySize),
                onPointerUp: (e) => _onPointerUp(e, pageIndex, pageDisplaySize),
                child: SizedBox(width: screenWidth, height: displayHeight),
              ),
          ],
        ),
      ),
    );

    // Apply reading mode filter
    if (_readingMode == _ReadingMode.dark) {
      pageContent = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          -0.9, 0,    0,    0, 230,
           0,  -0.9,  0,    0, 220,
           0,   0,   -0.9,  0, 210,
           0,   0,    0,    1,   0,
        ]),
        child: pageContent,
      );
    } else if (_readingMode == _ReadingMode.sepia) {
      pageContent = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.95, 0.05, 0.02, 0, 10,
          0.02, 0.90, 0.05, 0,  5,
          0.02, 0.05, 0.80, 0,  0,
          0,    0,    0,    1,  0,
        ]),
        child: pageContent,
      );
    }

    return pageContent;
  }

  Widget _buildBottomBar(int totalPages) {
    final progress = totalPages > 1
        ? _currentPageIndex / (totalPages - 1)
        : 1.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reading progress bar
        SizedBox(
          height: 3,
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0x22FFFFFF),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF6C63FF)),
          ),
        ),
        Container(
          height: 48,
          decoration: const BoxDecoration(
            color: Color(0xFF16213E),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _currentPageIndex > 0
                    ? () => _scrollToPage(_currentPageIndex - 1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
                iconSize: 20, color: Colors.white70, disabledColor: Colors.white24,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x22FFFFFF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Page ${_currentPageIndex + 1} of $totalPages',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 13,
                    fontWeight: FontWeight.w500, letterSpacing: 0.3,
                  ),
                ),
              ),
              IconButton(
                onPressed: _currentPageIndex < totalPages - 1
                    ? () => _scrollToPage(_currentPageIndex + 1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
                iconSize: 20, color: Colors.white70, disabledColor: Colors.white24,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Painters
// =============================================================================

/// Draws the pre-rendered PDF page image.
class _DirectPagePainter extends CustomPainter {
  final ui.Image image;
  final bool isZoomed;
  _DirectPagePainter({required this.image, this.isZoomed = false});

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(
      image, src, dst,
      Paint()..filterQuality = isZoomed ? FilterQuality.medium : FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(_DirectPagePainter old) =>
      !identical(old.image, image) || old.isZoomed != isZoomed;
}

/// Draws annotation strokes on top of a PDF page.
///
/// Strokes are stored in PDF-page coordinates. This painter transforms
/// them to display coordinates before rendering via [BrushEngine].
class _AnnotationOverlayPainter extends CustomPainter {
  final List<ProStroke> strokes;
  final List<ProDrawingPoint>? livePoints;
  final Color liveColor;
  final double liveWidth;
  final ProPenType livePenType;
  final Size pageOriginalSize;
  final Size displaySize;

  _AnnotationOverlayPainter({
    required this.strokes,
    this.livePoints,
    required this.liveColor,
    required this.liveWidth,
    required this.livePenType,
    required this.pageOriginalSize,
    required this.displaySize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Scale from PDF-page coords to display coords
    final sx = displaySize.width / pageOriginalSize.width;
    final sy = displaySize.height / pageOriginalSize.height;

    canvas.save();
    canvas.scale(sx, sy);

    // Draw committed strokes
    for (final stroke in strokes) {
      BrushEngine.renderStroke(
        canvas,
        stroke.points,
        stroke.color,
        stroke.baseWidth,
        stroke.penType,
        stroke.settings,
        engineVersion: stroke.engineVersion,
      );
    }

    // Draw live stroke
    if (livePoints != null && livePoints!.length >= 2) {
      BrushEngine.renderStroke(
        canvas,
        livePoints!,
        liveColor,
        liveWidth,
        livePenType,
        const ProBrushSettings(),
        isLive: true,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_AnnotationOverlayPainter old) {
    return old.strokes.length != strokes.length ||
           old.liveColor != liveColor ||
           old.liveWidth != liveWidth ||
           old.livePenType != livePenType ||
           !identical(old.livePoints, livePoints) ||
           (livePoints != null && old.livePoints != null &&
            old.livePoints!.length != livePoints!.length);
  }
}

/// Shimmer loading placeholder for pages not yet rendered.
class _PageShimmer extends StatefulWidget {
  const _PageShimmer();

  @override
  State<_PageShimmer> createState() => _PageShimmerState();
}

class _PageShimmerState extends State<_PageShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
              end: Alignment(-0.5 + 2.0 * _controller.value, 0),
              colors: const [
                Color(0x08FFFFFF),
                Color(0x18FFFFFF),
                Color(0x08FFFFFF),
              ],
            ),
          ),
        );
      },
    );
  }
}
