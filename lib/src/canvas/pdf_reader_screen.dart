import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../canvas/fluera_canvas_config.dart';
import '../core/models/pdf_document_model.dart';
import '../core/models/pdf_page_model.dart';
import '../core/models/pdf_text_rect.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../drawing/brushes/brush_engine.dart';
import '../drawing/models/pro_brush_settings.dart';
import '../drawing/models/pro_brush_settings_dialog.dart';
import '../core/models/shape_type.dart';
import 'package:fluera_engine/src/rendering/gpu/vulkan_stroke_overlay_service.dart';
import 'overlays/pdf_radial_menu.dart';
import 'overlays/floating_color_disc.dart';
import '../tools/pdf/pdf_text_extractor.dart';
import '../tools/pdf/pdf_search_controller.dart';
import 'package:path_provider/path_provider.dart';
import '../core/engine_scope.dart';

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

/// Data for a single bookmark.
class _BookmarkData {
  final Color color;
  String note;
  _BookmarkData({this.color = const Color(0xFFEF5350), this.note = ''});
}

class _PdfReaderScreenState extends State<PdfReaderScreen>
    with TickerProviderStateMixin {
  late final TransformationController _zoomController;
  late final List<ui.Image?> _pageImages;

  int _currentPageIndex = 0;

  /// Bookmarked pages with optional color tag and note.
  final Map<int, _BookmarkData> _bookmarkedPages = {};

  /// Available bookmark tag colors.
  static const _bookmarkColors = [
    Color(0xFFEF5350), // Red
    Color(0xFF42A5F5), // Blue
    Color(0xFF66BB6A), // Green
    Color(0xFFFFCA28), // Yellow
    Color(0xFFAB47BC), // Purple
    Color(0xFFFF7043), // Orange
  ];

  /// Current selected bookmark color for new bookmarks.
  Color _activeBookmarkColor = const Color(0xFFEF5350);

  /// Export quality multiplier.
  double _exportScale = 2.0;
  bool _showSidebar = false;
  bool _isAnimatingIn = true;

  /// Whether a zoom-out exit has been triggered (prevent double-pop).
  bool _zoomOutExitTriggered = false;

  /// Current interactive zoom scale.
  double _currentZoomScale = 1.0;

  /// Whether the user is actively pinch-zooming (suppress expensive work).
  bool _isInteracting = false;

  /// Timer for debounced hi-res re-render after zoom settles.
  Timer? _hiResDebounce;

  /// Zoom indicator auto-fade timer and opacity.
  Timer? _zoomIndicatorTimer;
  double _zoomIndicatorOpacity = 0.0;

  /// Track last zoom snap level for haptic feedback.
  int _lastSnapLevel = 1;

  /// Animation controller for smooth zoom transitions.
  AnimationController? _zoomAnimController;
  Matrix4? _zoomAnimStart;
  Matrix4? _zoomAnimEnd;

  /// Reading mode (light / dark / sepia).
  _ReadingMode _readingMode = _ReadingMode.light;

  /// Auto-hide chrome (floating title pill).
  bool _showChrome = false;
  Timer? _chromeHideTimer;

  /// PDF Radial Tool Wheel state.
  bool _showPdfRadialMenu = false;
  Offset _pdfRadialMenuCenter = Offset.zero;
  final _pdfRadialMenuKey = GlobalKey<PdfRadialMenuState>();

  /// Whether the radial wheel is enabled (user can toggle in toolbar).
  bool _usePdfRadialWheel = true;

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
  double _penOpacity = 1.0;
  ProPenType _penType = ProPenType.ballpoint;
  ProBrushSettings _brushSettings = const ProBrushSettings();

  /// Shape drawing mode.
  ShapeType _selectedShapeType = ShapeType.freehand;
  Offset? _shapeStartPos;
  Offset? _shapeEndPos;
  int? _shapePageIndex;

  /// Live stroke in progress (PDF-page coordinates).
  List<ProDrawingPoint>? _livePoints;
  int? _livePageIndex;

  /// 🚀 Screen-space points for Vulkan GPU rendering.
  /// Tracked separately because the InteractiveViewer's transform makes
  /// converting PDF-page coords back to screen coords unreliable.
  final List<ProDrawingPoint> _liveScreenPoints = [];

  /// Active pointer ID for drawing — only one finger draws at a time.
  /// Second finger is left for InteractiveViewer (pan/zoom).
  int? _activePointerId;

  /// Cached SafeArea top padding for Vulkan screen-space offset correction.
  /// Set once per stroke in _onPointerDown to avoid hot-path MediaQuery calls.
  double _safeAreaTopCache = 0;

  /// Number of active pointers touching the screen.
  int _activePointerCount = 0;

  /// Committed strokes per page (in PDF-page coordinate space).
  final Map<int, List<ProStroke>> _pageStrokes = {};

  /// 🚀 PERF: Repaint notifier for annotation overlay — avoids full setState
  /// during live drawing. Only the CustomPaint widget listening to this
  /// notifier repaints, not the entire page list.
  final ValueNotifier<int> _annotationRepaint = ValueNotifier<int>(0);

  // ---------------------------------------------------------------------------
  // Text selection state
  // ---------------------------------------------------------------------------

  /// Whether text selection mode is active.
  bool _isTextSelectMode = false;

  /// Extracted text rects per page (lazy, cached). Null = not yet extracted.
  final Map<int, List<PdfTextRect>> _pageTextRects = {};

  /// Currently selected text spans.
  List<PdfTextRect> _selSpans = const [];

  /// Selection range indices into the page's text rects list.
  int _selStartIdx = -1;
  int _selEndIdx = -1;
  int _selPageIdx = -1;

  /// Anchor index for drag-extend selection.
  int _selAnchor = -1;

  /// Whether text geometry is currently being extracted.
  bool _isExtractingText = false;

  /// Repaint notifier for text overlay (selection + search highlights).
  final ValueNotifier<int> _textOverlayRepaint = ValueNotifier<int>(0);

  // ---------------------------------------------------------------------------
  // Search state
  // ---------------------------------------------------------------------------

  /// Search controller — manages query, matches, navigation.
  final PdfSearchController _searchController = PdfSearchController();

  /// Whether the search bar is visible.
  bool _showSearchBar = false;

  /// Text input controller for search.
  final TextEditingController _searchTextCtrl = TextEditingController();

  /// Whether we've registered the document bytes with the search controller.
  bool _searchDocRegistered = false;

  /// OCR progress tracking.
  int _ocrProgress = 0;
  int _ocrTotal = 0;
  bool _ocrRunning = false;
  bool _ocrCancelled = false;

  // ---------------------------------------------------------------------------
  // Vulkan live stroke overlay
  // ---------------------------------------------------------------------------
  final VulkanStrokeOverlayService _vulkanOverlay = VulkanStrokeOverlayService();
  int? _vulkanTextureId;
  bool _vulkanActive = false;

  /// Whether the brush settings panel is shown (user-toggled, not auto).
  bool _showBrushPanel = false;

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

  /// Highlight-specific bright colors (shown when highlighter is active).
  static const _highlightColors = [
    Color(0xFFFFEB3B), // Yellow
    Color(0xFF76FF03), // Lime green
    Color(0xFFFF4081), // Pink
    Color(0xFF00E5FF), // Cyan
    Color(0xFFFF9100), // Orange
    Color(0xFFE040FB), // Magenta
  ];

  /// Saved pen color/width before switching to highlighter.
  Color? _savedPenColor;
  double? _savedPenWidth;

  @override
  void initState() {
    super.initState();
    _zoomController = TransformationController();
    _zoomController.addListener(_onZoomChanged);

    final pageCount = widget.documentModel.totalPages;
    _pageImages = List<ui.Image?>.filled(pageCount, null);

    // Load existing annotations from model
    _loadAnnotationsFromModel();

    // Restore persisted bookmarks
    _loadBookmarksFromModel();

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
    _chromeHideTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
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
      final padding = MediaQuery.of(context).padding;
      // Size the texture to the SafeArea content area, NOT full screen.
      // If the texture is oversized, Flutter scales it to fit the Texture
      // widget bounds, causing vertical/horizontal shifts.
      final safeHeight = size.height - padding.top - padding.bottom;
      final pw = (size.width * dpr).toInt();
      final ph = (safeHeight * dpr).toInt();
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
    _hiResDebounce?.cancel();
    _zoomIndicatorTimer?.cancel();
    _swipeSnapController?.dispose();
    _vulkanOverlay.dispose();
    _zoomAnimController?.dispose();
    _zoomController.dispose();
    _annotationRepaint.dispose();
    _textOverlayRepaint.dispose();
    _searchController.dispose();
    _searchTextCtrl.dispose();
    _searchDebounce?.cancel();
    _cancelOcr();
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

    _activePointerCount++;

    // If a second finger touches, cancel the live stroke and let
    // InteractiveViewer handle the 2-finger pan/zoom gesture.
    if (_activePointerCount > 1) {
      if (_livePoints != null || _shapeStartPos != null) {
        setState(() {
          _livePoints = null;
          _livePageIndex = null;
          _activePointerId = null;
          _shapeStartPos = null;
          _shapeEndPos = null;
          _shapePageIndex = null;
        });
        _liveScreenPoints.clear();
        if (_vulkanActive) _vulkanOverlay.clear();
      }
      return;
    }

    // Only the first finger draws
    _activePointerId = event.pointer;

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

    // Shape drawing mode — record start position
    if (_selectedShapeType != ShapeType.freehand) {
      setState(() {
        _shapeStartPos = pos;
        _shapeEndPos = pos;
        _shapePageIndex = pageIndex;
      });
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

    // Cache SafeArea top padding once per stroke (avoid hot-path MediaQuery).
    _safeAreaTopCache = MediaQuery.of(context).padding.top;

    // Track screen-space position for Vulkan.
    // Subtract SafeArea top padding because the Texture widget is inside
    // SafeArea but event.position is in global screen coordinates.
    _liveScreenPoints.clear();
    _liveScreenPoints.add(ProDrawingPoint(
      position: Offset(event.position.dx, event.position.dy - _safeAreaTopCache),
      pressure: event.pressure > 0 ? event.pressure : 0.5,
      tiltX: event.tilt,
      timestamp: event.timeStamp.inMilliseconds,
    ));
  }

  void _onPointerMove(PointerMoveEvent event, int pageIndex, Size pageDisplaySize) {
    if (!_isDrawingMode) return;
    // Only track the drawing pointer — ignore 2nd finger moves
    if (event.pointer != _activePointerId) return;

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

    // Shape drawing mode — update end position
    if (_selectedShapeType != ShapeType.freehand && _shapeStartPos != null) {
      setState(() => _shapeEndPos = pos);
      _annotationRepaint.value++;
      return;
    }

    if (_livePoints != null && _livePageIndex == pageIndex) {
      _livePoints!.add(ProDrawingPoint(
        position: pos,
        pressure: event.pressure > 0 ? event.pressure : 0.5,
        tiltX: event.tilt,
        timestamp: event.timeStamp.inMilliseconds,
      ));

      // Track screen-space position for Vulkan
      _liveScreenPoints.add(ProDrawingPoint(
        position: Offset(event.position.dx, event.position.dy - _safeAreaTopCache),
        pressure: event.pressure > 0 ? event.pressure : 0.5,
        tiltX: event.tilt,
        timestamp: event.timeStamp.inMilliseconds,
      ));

      // Forward to Vulkan GPU for real-time rendering.
      if (_vulkanActive && _liveScreenPoints.length >= 2) {
        _vulkanOverlay.updateAndRender(
          _liveScreenPoints,
          _penColor,
          _penWidth,
          brushType: _penType == ProPenType.pencil ? 2
              : _penType == ProPenType.fountain ? 4
              : 0,
        );
      }

      // 🚀 PERF: Bump notifier instead of setState — only repaints
      // the annotation overlay CustomPaint, not the entire widget tree.
      _annotationRepaint.value++;
    }
  }

  void _onPointerUp(PointerUpEvent event, int pageIndex, Size pageDisplaySize) {
    _activePointerCount = (_activePointerCount - 1).clamp(0, 10);
    if (!_isDrawingMode || _isErasing) return;
    // Only commit from the drawing pointer
    if (event.pointer != _activePointerId) return;
    _activePointerId = null;

    // Shape commit — generate shape points from start/end
    if (_selectedShapeType != ShapeType.freehand &&
        _shapeStartPos != null && _shapeEndPos != null &&
        _shapePageIndex == pageIndex) {
      final shapePoints = _generateShapePoints(_shapeStartPos!, _shapeEndPos!, _selectedShapeType);
      if (shapePoints.length >= 2) {
        final effectiveColor = _penColor.withValues(alpha: _penOpacity);
        final page = widget.documentModel.pages[pageIndex];
        final widthScale = page.originalSize.width / pageDisplaySize.width;
        final stroke = ProStroke(
          id: 'pdf_${widget.documentId}_p${pageIndex}_${DateTime.now().millisecondsSinceEpoch}',
          points: shapePoints,
          color: effectiveColor,
          baseWidth: _penWidth * widthScale,
          penType: _penType,
          settings: _brushSettings,
          createdAt: DateTime.now(),
        );
        setState(() {
          final existing = _pageStrokes[pageIndex] ?? const [];
          _pageStrokes[pageIndex] = [...existing, stroke];
          _shapeStartPos = null;
          _shapeEndPos = null;
          _shapePageIndex = null;
        });
        HapticFeedback.lightImpact();

        // Auto-bookmark annotated page (orange tag)
        if (!_bookmarkedPages.containsKey(pageIndex)) {
          setState(() {
            _bookmarkedPages[pageIndex] = _BookmarkData(
              color: const Color(0xFFFF7043),
            );
          });
          _syncBookmarkToModel(pageIndex, true);
        }
      } else {
        setState(() {
          _shapeStartPos = null;
          _shapeEndPos = null;
          _shapePageIndex = null;
        });
      }
      return;
    }

    if (_livePoints != null && _livePoints!.length >= 2 && _livePageIndex == pageIndex) {
      // Commit stroke — apply opacity to color alpha
      final effectiveColor = _penColor.withValues(alpha: _penOpacity);
      final page = widget.documentModel.pages[pageIndex];
      final widthScale = page.originalSize.width / pageDisplaySize.width;
      final stroke = ProStroke(
        id: 'pdf_${widget.documentId}_p${pageIndex}_${DateTime.now().millisecondsSinceEpoch}',
        points: List.from(_livePoints!),
        color: effectiveColor,
        baseWidth: _penWidth * widthScale,
        penType: _penType,
        settings: _brushSettings,
        createdAt: DateTime.now(),
      );

      setState(() {
        // 🐛 FIX: Create a NEW list instead of mutating in-place.
        final existing = _pageStrokes[pageIndex] ?? const [];
        _pageStrokes[pageIndex] = [...existing, stroke];
        _livePoints = null;
        _livePageIndex = null;
      });

      // Clear Vulkan live stroke overlay and screen-space points
      _liveScreenPoints.clear();
      if (_vulkanActive) _vulkanOverlay.clear();
      HapticFeedback.lightImpact();

      // Auto-bookmark annotated page (orange tag)
      if (!_bookmarkedPages.containsKey(pageIndex)) {
        setState(() {
          _bookmarkedPages[pageIndex] = _BookmarkData(
            color: const Color(0xFFFF7043), // orange = annotated
          );
        });
        _syncBookmarkToModel(pageIndex, true);
      }
    } else {
      _liveScreenPoints.clear();
      if (_vulkanActive) _vulkanOverlay.clear();
      setState(() {
        _livePoints = null;
        _livePageIndex = null;
      });
    }
  }

  /// Generate shape points from drag start/end positions.
  List<ProDrawingPoint> _generateShapePoints(Offset start, Offset end, ShapeType type) {
    List<Offset> pts;
    switch (type) {
      case ShapeType.freehand:
        return [];
      case ShapeType.line:
        pts = [start, end];
        break;
      case ShapeType.rectangle:
        pts = [
          start,
          Offset(end.dx, start.dy),
          end,
          Offset(start.dx, end.dy),
          start, // Close
        ];
        break;
      case ShapeType.circle:
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final rx = (end.dx - start.dx).abs() / 2;
        final ry = (end.dy - start.dy).abs() / 2;
        const segments = 36;
        pts = List.generate(segments + 1, (i) {
          final angle = 2 * math.pi * i / segments;
          return Offset(
            center.dx + rx * math.cos(angle),
            center.dy + ry * math.sin(angle),
          );
        });
        break;
      case ShapeType.triangle:
        final midX = (start.dx + end.dx) / 2;
        pts = [
          Offset(midX, start.dy),
          Offset(end.dx, end.dy),
          Offset(start.dx, end.dy),
          Offset(midX, start.dy), // Close
        ];
        break;
      case ShapeType.arrow:
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 1) return [];
        final nx = dx / len;
        final ny = dy / len;
        final headLen = len * 0.2;
        final headW = headLen * 0.6;
        final arrowBase = Offset(end.dx - nx * headLen, end.dy - ny * headLen);
        pts = [
          start,
          arrowBase,
          Offset(arrowBase.dx - ny * headW, arrowBase.dy + nx * headW),
          end,
          Offset(arrowBase.dx + ny * headW, arrowBase.dy - nx * headW),
          arrowBase,
        ];
        break;
      case ShapeType.star:
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final rx = (end.dx - start.dx).abs() / 2;
        final ry = (end.dy - start.dy).abs() / 2;
        pts = [];
        for (int i = 0; i <= 10; i++) {
          final angle = math.pi / 2 + (2 * math.pi * i / 10);
          final r = i.isEven ? 1.0 : 0.4;
          pts.add(Offset(center.dx + rx * r * math.cos(angle), center.dy - ry * r * math.sin(angle)));
        }
        break;
      case ShapeType.heart:
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final w = (end.dx - start.dx).abs() / 2;
        final h = (end.dy - start.dy).abs() / 2;
        pts = List.generate(37, (i) {
          final t = 2 * math.pi * i / 36;
          return Offset(
            center.dx + w * 16 * math.pow(math.sin(t), 3) / 16,
            center.dy - h * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) / 16,
          );
        });
        break;
      case ShapeType.diamond:
        final cx = (start.dx + end.dx) / 2;
        final cy = (start.dy + end.dy) / 2;
        pts = [
          Offset(cx, start.dy),
          Offset(end.dx, cy),
          Offset(cx, end.dy),
          Offset(start.dx, cy),
          Offset(cx, start.dy),
        ];
        break;
      case ShapeType.pentagon:
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final rx = (end.dx - start.dx).abs() / 2;
        final ry = (end.dy - start.dy).abs() / 2;
        pts = List.generate(6, (i) {
          final angle = -math.pi / 2 + 2 * math.pi * i / 5;
          return Offset(center.dx + rx * math.cos(angle), center.dy + ry * math.sin(angle));
        });
        break;
      case ShapeType.hexagon:
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final rx = (end.dx - start.dx).abs() / 2;
        final ry = (end.dy - start.dy).abs() / 2;
        pts = List.generate(7, (i) {
          final angle = 2 * math.pi * i / 6;
          return Offset(center.dx + rx * math.cos(angle), center.dy + ry * math.sin(angle));
        });
        break;
    }
    return pts.map((p) => ProDrawingPoint(position: p, pressure: 0.5)).toList();
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
        // Create new list excluding erased strokes (avoid in-place mutation)
        final updated = <ProStroke>[
          for (int i = 0; i < strokes.length; i++)
            if (!toRemove.contains(i)) strokes[i],
        ];
        _pageStrokes[pageIndex] = updated;
      });
      HapticFeedback.selectionClick();
    }
  }

  void _undoLastStroke() {
    final strokes = _pageStrokes[_currentPageIndex];
    if (strokes != null && strokes.isNotEmpty) {
      // Create new list without last stroke (avoid in-place mutation)
      _pageStrokes[_currentPageIndex] = strokes.sublist(0, strokes.length - 1);
      setState(() {});
      HapticFeedback.lightImpact();
    }
  }

  // ---------------------------------------------------------------------------
  // Viewport culling helper
  // ---------------------------------------------------------------------------

  /// Compute the visible viewport rect in page-coordinate space.
  /// Used by _AnnotationOverlayPainter for stroke culling.
  Rect? _computeVisibleRect(int pageIndex, Size displaySize, Size originalSize) {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    if (scale <= 1.05) return null; // Not zoomed, render all

    final screenSize = MediaQuery.of(context).size;
    final xOffset = -_zoomController.value.row0.w;
    final yOffset = -_zoomController.value.row1.w;

    // Compute page Y offset in the scroll layout
    double pageTop = 0;
    for (int i = 0; i < pageIndex; i++) {
      pageTop += _getPageDisplayHeight(i);
    }

    // Viewport in scroll-layout coordinates
    final viewLeft = xOffset / scale;
    final viewTop = yOffset / scale;
    final viewWidth = screenSize.width / scale;
    final viewHeight = screenSize.height / scale;

    // Convert to page-local coordinates
    final localLeft = viewLeft;
    final localTop = viewTop - pageTop;

    // Scale from display coords to original PDF coords
    final sx = originalSize.width / displaySize.width;
    final sy = originalSize.height / displaySize.height;

    return Rect.fromLTWH(
      localLeft * sx - 50, // padding for stroke width
      localTop * sy - 50,
      viewWidth * sx + 100,
      viewHeight * sy + 100,
    );
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

    // 📍 Haptic snap at round zoom levels (1×, 2×, 3×)
    final currentSnap = scale.round();
    if (currentSnap != _lastSnapLevel && currentSnap >= 1 && currentSnap <= 4) {
      final diff = (scale - currentSnap).abs();
      if (diff < 0.05) {
        HapticFeedback.selectionClick();
        _lastSnapLevel = currentSnap;
      }
    }

    // Show zoom indicator and schedule auto-fade
    if (changed && (scale - 1.0).abs() > 0.05) {
      _zoomIndicatorTimer?.cancel();
      if (_zoomIndicatorOpacity < 1.0) {
        _zoomIndicatorOpacity = 1.0;
      }
      _zoomIndicatorTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _zoomIndicatorOpacity = 0.0);
      });
    } else if ((scale - 1.0).abs() <= 0.05) {
      _zoomIndicatorOpacity = 0.0;
    }

    // Only rebuild when zoom indicator visibility or exit hint actually changes
    final needsRebuild = changed && mounted && (
      // Zoom indicator visibility changed
      (previousScale - 1.0).abs() <= 0.05 != (scale - 1.0).abs() <= 0.05 ||
      // Exit hint visibility changed  
      (previousScale >= 0.95) != (scale >= 0.95) ||
      // Exit-ready state changed
      (previousScale >= 0.75) != (scale >= 0.75) ||
      // Zoom percentage display changed (skip during active interaction for perf)
      (!_isInteracting && (previousScale * 100).round() != (scale * 100).round())
    );
    
    if (needsRebuild) {
      setState(() {});
    }

    // Update page tracking on every scroll (but not during active pinch)
    if (changed && mounted && !_isInteracting) {
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

  /// Detect swipe-down-to-dismiss from InteractiveViewer's own pan gestures.
  ///
  /// Activates only when the document is at the top (over-scrolled past origin)
  /// and the user is panning down with one finger (not pinching to zoom).
  void _onInteractionUpdate(ScaleUpdateDetails details) {
    // Mark as actively interacting to suppress expensive work
    if (!_isInteracting) _isInteracting = true;

    if (_currentZoomScale > 1.05 || _isDrawingMode) return;

    // Only single-finger pan (not pinch-to-zoom)
    if (details.pointerCount > 1) return;

    // Check if document is at/above the top (positive Y = over-scrolled past top)
    final yTranslation = _zoomController.value.row1.w;
    if (yTranslation > 0 && details.focalPointDelta.dy > 0) {
      // Over-scrolled past top AND still pulling down → dismiss gesture
      setState(() {
        _isSwiping = true;
        _swipeDismissOffset = yTranslation * 0.5; // Damped offset for visual feedback
      });
    } else if (_isSwiping && yTranslation <= 0) {
      // Released back into content → cancel dismiss
      setState(() {
        _isSwiping = false;
        _swipeDismissOffset = 0;
      });
    }
  }

  /// Called when the pinch gesture ends — snap back or exit.
  void _onInteractionEnd(ScaleEndDetails details) {
    // End interaction mode — resume expensive work
    _isInteracting = false;
    final scale = _zoomController.value.getMaxScaleOnAxis();

    // Deferred: update page tracking and ensure renders
    _onScroll();
    _ensureVisiblePagesRendered();

    // Prefetch extra pages if zoomed out (more pages visible)
    if (scale < 0.9) {
      final total = widget.documentModel.totalPages;
      final extraBuffer = (1.0 / scale).ceil() + 1;
      for (int i = (_currentPageIndex - extraBuffer).clamp(0, total);
           i < (_currentPageIndex + extraBuffer + 1).clamp(0, total); i++) {
        if (_pageImages[i] == null) {
          _renderPage(i, widget.provider);
        }
      }
    }

    // Schedule hi-res re-render if zoomed in
    _scheduleHiResRender(scale);

    // Force a final setState with correct isZoomed/FilterQuality
    if (mounted) setState(() {});

    // ── Swipe-down-to-dismiss: check if dismiss threshold reached ──
    if (_isSwiping) {
      final velocity = details.velocity.pixelsPerSecond.dy;
      if (_swipeDismissOffset > 120 || velocity > 800) {
        HapticFeedback.mediumImpact();
        widget.onClose?.call(_buildUpdatedModel());
        Navigator.of(context).pop();
        return;
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
        return;
      }
    }

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
    // No-op: dismiss logic now handled in _onInteractionEnd
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
      duration: const Duration(milliseconds: 200), // 🚀 Faster
      vsync: this,
    );
    _zoomAnimController = controller;

    final curve = CurvedAnimation(
      parent: controller,
      curve: Curves.fastOutSlowIn, // 🚀 Smoother deceleration
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
        // Schedule hi-res after programmatic zoom settles
        _scheduleHiResRender(_zoomController.value.getMaxScaleOnAxis());
      }
    });

    controller.forward();
  }

  /// Schedule hi-res re-render when zoom settles above 1.5x.
  void _scheduleHiResRender(double scale) {
    _hiResDebounce?.cancel();
    if (scale > 1.5) {
      _hiResDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        // Re-render current page at higher resolution
        final hiResScale = (scale / 1.5).clamp(1.0, 2.5);
        _renderPage(_currentPageIndex, widget.provider, renderScale: hiResScale);
        // Also render adjacent pages
        if (_currentPageIndex > 0) {
          _renderPage(_currentPageIndex - 1, widget.provider, renderScale: hiResScale);
        }
        if (_currentPageIndex < widget.documentModel.totalPages - 1) {
          _renderPage(_currentPageIndex + 1, widget.provider, renderScale: hiResScale);
        }
      });
    }
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
                              // ── Main content area (no toolbar space reserved) ──
                              Column(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: _toggleChrome,
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
                                                  duration: const Duration(milliseconds: 300),
                                                  opacity: _zoomIndicatorOpacity,
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
                                          // 🔍 Search bar overlay
                                          if (_showSearchBar)
                                            _buildSearchBar(),
                                        ],
                                      ),
                                    ),
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

                               // ── 🏷️ Floating glass title pill (auto-dismiss) ──
                               if (_showChrome)
                                 Positioned(
                                   top: 12,
                                   left: 68,
                                   right: 12,
                                   child: IgnorePointer(
                                     child: AnimatedOpacity(
                                       duration: const Duration(milliseconds: 200),
                                       opacity: _showChrome ? 1.0 : 0.0,
                                       child: _buildFloatingTitle(totalPages),
                                     ),
                                   ),
                                 ),

                               // ── 🔙 Fixed back button (always visible, glassmorphic) ──
                               Positioned(
                                 top: 8,
                                 left: 8,
                                 child: _buildBackButton(),
                               ),

                               // ── 🎨 FloatingColorDisc (drawing mode only) ──
                               if (_isDrawingMode && !_showPdfRadialMenu)
                                 FloatingColorDisc(
                                   color: _penColor,
                                   recentColors: _colorPresets.toList(),
                                   strokeSize: _penWidth,
                                   onColorChanged: (c) => setState(() => _penColor = c),
                                   onStrokeSizeChanged: (s) => setState(() => _penWidth = s.clamp(0.5, 8.0)),
                                   onExpand: () async {
                                     // Double-tap → brush panel slide-up
                                     setState(() => _showBrushPanel = !_showBrushPanel);
                                   },
                                 ),

                               // ── 🖌️ Brush panel (on-demand via double-tap on disc) ──
                               if (_isDrawingMode && _showBrushPanel && !_showPdfRadialMenu)
                                 Positioned(
                                   bottom: 68,
                                   left: 0,
                                   right: 0,
                                   child: _buildBrushPanel(),
                                 ),

                               // ── 🎯 PDF Radial Tool Wheel V2 ──
                               if (_showPdfRadialMenu)
                                 Positioned.fill(
                                   child: PdfRadialMenu(
                                     key: _pdfRadialMenuKey,
                                     center: _pdfRadialMenuCenter,
                                     screenSize: MediaQuery.of(context).size,
                                     isDrawingMode: _isDrawingMode,
                                     isCurrentPageBookmarked: _bookmarkedPages.containsKey(_currentPageIndex),
                                     bookmarkCount: _bookmarkedPages.length,
                                     currentPenType: _penType,
                                     currentColor: _penColor,
                                     colorPresets: _colorPresets.toList(),
                                     highlightColors: _highlightColors.toList(),
                                     onResult: (result) {
                                       setState(() => _showPdfRadialMenu = false);
                                       _handlePdfRadialResult(result);
                                     },
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


  // ---------------------------------------------------------------------------
  // 🏷️ Floating title pill (appears briefly on tap, then auto-dismisses)
  // ---------------------------------------------------------------------------

  Widget _buildFloatingTitle(int totalPages) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text(
                  widget.documentModel.fileName ?? 'PDF Document',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_currentPageIndex + 1}/$totalPages',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🔙 Fixed back button (always visible, small glassmorphic circle)
  // ---------------------------------------------------------------------------

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () {
        widget.onClose?.call(_buildUpdatedModel());
        Navigator.of(context).pop();
      },
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.40),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🖌️ Brush FAB — small glassmorphic toggle for the brush panel
  // ---------------------------------------------------------------------------

  Widget _buildBrushFab() {
    return GestureDetector(
      onTap: () {
        setState(() => _showBrushPanel = !_showBrushPanel);
        HapticFeedback.selectionClick();
      },
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _showBrushPanel
                  ? const Color(0xFF6C63FF).withValues(alpha: 0.85)
                  : Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
              border: Border.all(
                color: _showBrushPanel
                    ? Colors.white.withValues(alpha: 0.30)
                    : Colors.white.withValues(alpha: 0.15),
              ),
              boxShadow: _showBrushPanel
                  ? [BoxShadow(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                      blurRadius: 12, spreadRadius: 1,
                    )]
                  : null,
            ),
            child: Icon(
              Icons.brush_rounded,
              color: _showBrushPanel ? Colors.white : Colors.white70,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // 🖌️ Brush panel — floating bottom panel in drawing mode
  // ---------------------------------------------------------------------------

  Widget _buildBrushPanel() {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.60),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // ── Pen / Eraser ──
                  _premiumToolPill(
                    icon: Icons.edit_rounded,
                    isActive: !_isErasing && _selectedShapeType == ShapeType.freehand,
                    onTap: () => setState(() {
                      _isErasing = false;
                      _selectedShapeType = ShapeType.freehand;
                    }),
                  ),
                  const SizedBox(width: 2),
                  _premiumToolPill(
                    icon: Icons.cleaning_services_rounded,
                    isActive: _isErasing,
                    onTap: () => setState(() => _isErasing = true),
                  ),

                  _separator(),

                  // ── Pen type chips ──
                  _premiumPenChip(ProPenType.fountain, '✒️'),
                  _premiumPenChip(ProPenType.ballpoint, '🖋️'),
                  _premiumPenChip(ProPenType.pencil, '✏️'),
                  _premiumPenChip(ProPenType.highlighter, '🖍️'),
                  _premiumPenChip(ProPenType.watercolor, '💧'),
                  _premiumPenChip(ProPenType.marker, '🖊️'),

                  _separator(),

                  // ── Shapes ──
                  _buildShapeButton(ShapeType.line, Icons.show_chart),
                  _buildShapeButton(ShapeType.rectangle, Icons.crop_square),
                  _buildShapeButton(ShapeType.circle, Icons.circle_outlined),
                  _buildShapeButton(ShapeType.arrow, Icons.arrow_forward),

                  _separator(),

                  // ── Color palette ──
                  ...List.generate(
                    _penType == ProPenType.highlighter
                        ? _highlightColors.length
                        : _colorPresets.length,
                    (i) {
                      final c = _penType == ProPenType.highlighter
                          ? _highlightColors[i]
                          : _colorPresets[i];
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
                                ? [BoxShadow(
                                    color: c.withValues(alpha: 0.5),
                                    blurRadius: 8, spreadRadius: 1,
                                  )]
                                : null,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 8),

                  // ── Width dot + slider ──
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: (_penWidth * 2.5).clamp(6.0, 20.0),
                    height: (_penWidth * 2.5).clamp(6.0, 20.0),
                    decoration: BoxDecoration(
                      color: _penColor.withValues(alpha: _penOpacity),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _penColor.withValues(alpha: 0.4 * _penOpacity),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 80,
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

                  _separator(),

                  // ── Opacity ──
                  const Icon(Icons.opacity_rounded, size: 14, color: Colors.white54),
                  SizedBox(
                    width: 72,
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: const Color(0xFF9B59B6),
                        inactiveTrackColor: const Color(0x20FFFFFF),
                        thumbColor: Colors.white,
                        overlayColor: const Color(0x209B59B6),
                      ),
                      child: Slider(
                        value: _penOpacity,
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        onChanged: (v) => setState(() => _penOpacity = v),
                      ),
                    ),
                  ),
                  Text(
                    '${(_penOpacity * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
    return Builder(
      builder: (chipContext) => GestureDetector(
      onTap: () => setState(() {
        final wasHighlighter = _penType == ProPenType.highlighter;
        _penType = type;
        _isErasing = false;
        _selectedShapeType = ShapeType.freehand;
        // Auto-switch to highlight color + width when selecting highlighter
        if (type == ProPenType.highlighter && !wasHighlighter) {
          _savedPenColor = _penColor;
          _savedPenWidth = _penWidth;
          _penColor = _highlightColors[0]; // Yellow
          _penWidth = 6.0; // Wide highlight stroke
        } else if (type != ProPenType.highlighter && wasHighlighter && _savedPenColor != null) {
          _penColor = _savedPenColor!;
          _penWidth = _savedPenWidth ?? 2.0;
          _savedPenColor = null;
          _savedPenWidth = null;
        }
      }),
      onLongPress: () {
        // 🎛️ Long-press → Show brush settings popup anchored to this chip
        HapticFeedback.mediumImpact();
        final box = chipContext.findRenderObject() as RenderBox;
        final pos = box.localToGlobal(Offset.zero);
        ProBrushSettingsDialog.show(
          chipContext,
          settings: _brushSettings,
          currentBrush: type,
          anchorRect: pos & box.size,
          currentColor: _penColor,
          currentWidth: _penWidth,
          onSettingsChanged: (newSettings) {
            setState(() => _brushSettings = newSettings);
          },
        );
      },
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
    ),
    );
  }

  Widget _buildShapeButton(ShapeType type, IconData icon) {
    final isActive = _selectedShapeType == type;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedShapeType = isActive ? ShapeType.freehand : type;
        _isErasing = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(6),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isActive ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 16,
          color: isActive ? Colors.white : const Color(0x80FFFFFF),
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
                  Stack(
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
                      // Bookmark dot indicator (matches tag color)
                      if (_bookmarkedPages.containsKey(index))
                        Positioned(
                          top: 4, right: 4,
                          child: Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              color: _bookmarkedPages[index]?.color ?? const Color(0xFFEF5350),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (_bookmarkedPages[index]?.color ?? const Color(0xFFEF5350)).withValues(alpha: 0.4),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
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
      // ── Long-press → PDF radial wheel ──
      onLongPressStart: (d) {
        if (!_usePdfRadialWheel) return;
        setState(() {
          _showPdfRadialMenu = true;
          _pdfRadialMenuCenter = d.globalPosition;
        });
        HapticFeedback.mediumImpact();
      },
      onLongPressMoveUpdate: (d) =>
          _pdfRadialMenuKey.currentState?.updateFinger(d.globalPosition),
      onLongPressEnd: (_) =>
          _pdfRadialMenuKey.currentState?.release(),
      child: InteractiveViewer(
        transformationController: _zoomController,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: 0.3,
        maxScale: 4.0,
        // panEnabled: false in drawing mode → prevents 1-finger pan from
        // competing with drawing. InteractiveViewer's _onScaleUpdate returns
        // early for pointerCount < 2 when panEnabled is false.
        // scaleEnabled: always true → 2-finger pinch-zoom/pan works even
        // during annotation.
        panEnabled: !_isDrawingMode,
        scaleEnabled: true,
        onInteractionUpdate: _onInteractionUpdate,
        onInteractionEnd: _onInteractionEnd,
        child: SizedBox(
          width: screenWidth,
          child: _buildVirtualizedPages(screenWidth),
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

  // ---------------------------------------------------------------------------
  // Virtualized page rendering — O(visible) instead of O(N)
  // ---------------------------------------------------------------------------

  /// Cached cumulative page tops for O(1) lookup.
  List<double>? _cumulativePageTops;
  double? _cachedTotalHeight;
  double? _cumulativeCacheWidth; // invalidate cache on width change

  /// Rebuild cumulative tops cache if needed.
  void _ensureCumulativeCache() {
    final screenWidth = MediaQuery.sizeOf(context).width - (_showSidebar ? 120 : 0) - 32;
    if (_cumulativePageTops != null && _cumulativeCacheWidth == screenWidth) return;

    final totalPages = widget.documentModel.totalPages;
    final tops = List<double>.filled(totalPages, 0.0);
    double acc = 16.0;
    for (int i = 0; i < totalPages; i++) {
      tops[i] = acc;
      acc += _getPageDisplayHeight(i) + 16.0;
    }
    _cumulativePageTops = tops;
    _cachedTotalHeight = acc;
    _cumulativeCacheWidth = screenWidth;
  }

  /// Cumulative Y offset for a page index — O(1) with cache.
  double _getPageTop(int pageIndex) {
    _ensureCumulativeCache();
    return _cumulativePageTops![pageIndex];
  }

  /// Total content height for all pages — O(1) with cache.
  double _getTotalContentHeight() {
    _ensureCumulativeCache();
    return _cachedTotalHeight!;
  }

  /// Build only the pages visible in the current viewport.
  /// This replaces the Column approach and scales O(visible) for N→∞ pages.
  Widget _buildVirtualizedPages(double screenWidth) {
    final totalPages = widget.documentModel.totalPages;
    final totalHeight = _getTotalContentHeight();
    final contentWidth = screenWidth - 32; // padding

    // Compute visible range from InteractiveViewer transform
    final scale = _zoomController.value.getMaxScaleOnAxis();
    final yOffset = -_zoomController.value.row1.w / scale;
    final viewportHeight = MediaQuery.of(context).size.height / scale;
    final viewTop = yOffset;
    final viewBottom = yOffset + viewportHeight;

    // Find first and last visible page indices (with buffer)
    const buffer = 3;
    int firstVisible = 0;
    int lastVisible = totalPages - 1;

    double accumulated = 16.0;
    for (int i = 0; i < totalPages; i++) {
      final pageHeight = _getPageDisplayHeight(i);
      final pageBottom = accumulated + pageHeight;

      if (pageBottom < viewTop) {
        firstVisible = i + 1;
      }
      if (accumulated > viewBottom && lastVisible == totalPages - 1) {
        lastVisible = i;
        break;
      }
      accumulated = pageBottom + 16.0;
    }

    // Clamp with buffer
    firstVisible = (firstVisible - buffer).clamp(0, totalPages - 1);
    lastVisible = (lastVisible + buffer).clamp(0, totalPages - 1);

    // Build only visible pages as Positioned children
    return SizedBox(
      width: screenWidth,
      height: totalHeight,
      child: Stack(
        children: [
          for (int i = firstVisible; i <= lastVisible; i++)
            Positioned(
              left: 16,
              top: _getPageTop(i),
              width: contentWidth,
              height: _getPageDisplayHeight(i),
              child: RepaintBoundary(
                child: (i - _currentPageIndex).abs() <= 5
                    ? _buildPageWidget(i)
                    : _pageImages[i] != null
                        ? CustomPaint(
                            painter: _DirectPagePainter(
                              image: _pageImages[i]!,
                              isZoomed: false,
                            ),
                            size: Size(contentWidth, _getPageDisplayHeight(i)),
                          )
                        : const _PageShimmer(),
              ),
            ),
        ],
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
    final isZoomed = _isInteracting || _currentZoomScale > 1.1;

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
            // PDF page image + Annotation strokes (combined for correct blend modes)
            if (img != null && (strokes.isNotEmpty || (isLivePage && _livePoints != null) || (isLivePage && _shapeStartPos != null)))
              RepaintBoundary(
                child: CustomPaint(
                  painter: _AnnotationOverlayPainter(
                    strokes: strokes,
                    // 🔧 FIX: When Vulkan GPU overlay is active it already
                    // renders the live stroke — skip software painter to avoid
                    // double stroke artefacts.
                    livePoints: (isLivePage && !_vulkanActive) ? _livePoints : null,
                    liveColor: _penColor.withValues(alpha: _penOpacity),
                    liveWidth: _penWidth * (page.originalSize.width / pageDisplaySize.width),
                    livePenType: _penType,
                    pageOriginalSize: page.originalSize,
                    displaySize: pageDisplaySize,
                    visibleRect: _computeVisibleRect(pageIndex, pageDisplaySize, page.originalSize),
                    repaintNotifier: isLivePage ? _annotationRepaint : null,
                    shapeStart: (isLivePage && _shapePageIndex == pageIndex) ? _shapeStartPos : null,
                    shapeEnd: (isLivePage && _shapePageIndex == pageIndex) ? _shapeEndPos : null,
                    shapeType: _selectedShapeType,
                    liveBrushSettings: _brushSettings,
                    pageImage: img,
                    isZoomed: isZoomed,
                  ),
                  size: pageDisplaySize,
                ),
              )
            // Page only (no annotations) — lightweight painter
            else if (img != null)
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

            // Touch input overlay (drawing mode only)

            // Bookmark ribbon (top-right corner) — tap/double-tap/long-press
            Positioned(
              top: 0, right: 16,
              child: GestureDetector(
                onTap: () {
                  if (_bookmarkedPages.containsKey(pageIndex)) {
                    // Remove with undo
                    _removeBookmarkWithUndo(pageIndex);
                  }
                },
                onDoubleTap: () {
                  if (_bookmarkedPages.containsKey(pageIndex)) {
                    _editBookmarkNote(pageIndex);
                  }
                },
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  _showBookmarksPanel();
                },
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  offset: _bookmarkedPages.containsKey(pageIndex)
                      ? Offset.zero
                      : const Offset(0, -1.5),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _bookmarkedPages.containsKey(pageIndex) ? 1.0 : 0.0,
                    child: CustomPaint(
                      size: const Size(24, 36),
                      painter: _BookmarkRibbonPainter(
                        color: _bookmarkedPages[pageIndex]?.color ?? const Color(0xFFEF5350),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (_isDrawingMode)
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _onPointerDown(e, pageIndex, pageDisplaySize),
                onPointerMove: (e) => _onPointerMove(e, pageIndex, pageDisplaySize),
                onPointerUp: (e) => _onPointerUp(e, pageIndex, pageDisplaySize),
                child: SizedBox(width: screenWidth, height: displayHeight),
              ),

            // 📝 Text selection + Search highlights overlay
            if (_isTextSelectMode || _searchMatches.isNotEmpty)
              Positioned.fill(
                child: ValueListenableBuilder<int>(
                  valueListenable: _textOverlayRepaint,
                  builder: (_, __, ___) => CustomPaint(
                    painter: _TextHighlightPainter(
                      selectionSpans: (pageIndex == _selPageIdx) ? _selSpans : const [],
                      searchHighlights: _searchHighlightsForPage(pageIndex),
                      currentSearchHighlight: _currentSearchHighlightForPage(pageIndex),
                    ),
                    size: pageDisplaySize,
                  ),
                ),
              ),

            // 📝 Text selection gesture area
            if (_isTextSelectMode && !_isDrawingMode)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: (d) => _onTextSelectStart(
                  pageIndex,
                  d.localPosition,
                  pageDisplaySize,
                ),
                onLongPressMoveUpdate: (d) => _onTextSelectUpdate(
                  pageIndex,
                  d.localPosition,
                  pageDisplaySize,
                ),
                onLongPressEnd: (_) => _onTextSelectEnd(),
                onTap: () => setState(_clearTextSelection),
                child: SizedBox(width: screenWidth, height: displayHeight),
              ),

            // 📋 Copy/Select All toolbar
            if (pageIndex == _selPageIdx && _selSpans.isNotEmpty)
              _buildTextSelectionToolbar(pageDisplaySize),
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

  /// 🎯 Handle a result from the PDF radial tool wheel (V3).
  void _handlePdfRadialResult(PdfRadialResult result) {
    // ── Quick-repeat flick → instant undo ──
    if (result.quickRepeat) {
      _undoLastStroke();
      HapticFeedback.mediumImpact();
      return;
    }

    // ── Color selected from sub-ring ──
    if (result.selectedColor != null) {
      setState(() => _penColor = result.selectedColor!);
      HapticFeedback.selectionClick();
      return;
    }

    // ── Reading mode actions ──
    if (result.readingAction != null) {
      switch (result.readingAction!) {
        case PdfReadingAction.pen:
          setState(() {
            _isDrawingMode = true;
            _isErasing = false;
            _penType = ProPenType.ballpoint;
            _selectedShapeType = ShapeType.freehand;
            if (_penType == ProPenType.highlighter && _savedPenColor != null) {
              _penColor = _savedPenColor!;
              _penWidth = _savedPenWidth ?? 2.0;
              _savedPenColor = null;
              _savedPenWidth = null;
            }
          });
          _initVulkanIfNeeded();
          HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.highlight:
          setState(() {
            _isDrawingMode = true;
            _isErasing = false;
            _penType = ProPenType.highlighter;
            _selectedShapeType = ShapeType.freehand;
            if (_savedPenColor == null) {
              _savedPenColor = _penColor;
              _savedPenWidth = _penWidth;
              _penColor = _highlightColors[0];
              _penWidth = 6.0;
            }
          });
          _initVulkanIfNeeded();
          HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.eraser:
          setState(() { _isDrawingMode = true; _isErasing = true; });
          HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.undo:
          _undoLastStroke();
          break;
        case PdfReadingAction.reading:
          setState(() {
            _readingMode = _ReadingMode.values[
                (_readingMode.index + 1) % _ReadingMode.values.length];
          });
          HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.textSelect:
          setState(() {
            _isTextSelectMode = !_isTextSelectMode;
            if (_isTextSelectMode) {
              _isDrawingMode = false;
              _isErasing = false;
              _showSearchBar = false;
            } else {
              _clearTextSelection();
            }
          });
          HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.search:
          setState(() {
            _showSearchBar = !_showSearchBar;
            if (_showSearchBar) {
              _isDrawingMode = false;
              _isErasing = false;
              _isTextSelectMode = false;
              _clearTextSelection();
              _ensureSearchDocRegistered();
            } else {
              _searchController.clearSearch();
              _searchTextCtrl.clear();
              _textOverlayRepaint.value++;
            }
          });
          HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.sidebar:
          setState(() => _showSidebar = !_showSidebar);
          HapticFeedback.selectionClick();
          break;
        case PdfReadingAction.bookmark:
          _toggleBookmark();
          break;
        case PdfReadingAction.exportAnnotated:
          _showExportSheet();
          break;
      }
      return;
    }

    // ── Drawing mode actions ──
    if (result.drawingAction != null) {
      switch (result.drawingAction!) {
        case PdfDrawingAction.ballpoint:
        case PdfDrawingAction.pencil:
        case PdfDrawingAction.fountain:
          final penType = result.drawingAction!.penType!;
          setState(() {
            _isErasing = false;
            _penType = penType;
            _selectedShapeType = ShapeType.freehand;
            // Restore color if coming from highlighter
            if (_savedPenColor != null) {
              _penColor = _savedPenColor!;
              _penWidth = _savedPenWidth ?? 2.0;
              _savedPenColor = null;
              _savedPenWidth = null;
            }
          });
          HapticFeedback.selectionClick();
          break;
        case PdfDrawingAction.highlighter:
          setState(() {
            _isErasing = false;
            _penType = ProPenType.highlighter;
            _selectedShapeType = ShapeType.freehand;
            if (_savedPenColor == null) {
              _savedPenColor = _penColor;
              _savedPenWidth = _penWidth;
              _penColor = _highlightColors[0];
              _penWidth = 6.0;
            }
          });
          HapticFeedback.selectionClick();
          break;
        case PdfDrawingAction.eraser:
          setState(() => _isErasing = true);
          HapticFeedback.selectionClick();
          break;
        case PdfDrawingAction.undo:
          _undoLastStroke();
          break;
        case PdfDrawingAction.exitDraw:
          setState(() {
            _isDrawingMode = false;
            _isErasing = false;
            if (_savedPenColor != null) {
              _penColor = _savedPenColor!;
              _penWidth = _savedPenWidth ?? 2.0;
              _savedPenColor = null;
              _savedPenWidth = null;
            }
          });
          HapticFeedback.mediumImpact();
          break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PDF Text Extraction
  // ---------------------------------------------------------------------------

  /// Opens the text extraction bottom sheet immediately, resolving text in background.
  void _showPdfTextExtractionSheet() {
    HapticFeedback.mediumImpact();

    // Build the extraction Future lazily — the sheet opens IMMEDIATELY
    // and shows a spinner until it resolves.
    final filePath = widget.documentModel.filePath;
    final pageIndex = _currentPageIndex;
    final totalPages = widget.documentModel.totalPages;

    final Future<String> textFuture = () async {
      if (filePath == null || filePath.isEmpty) return '';
      try {
        final bytes = await File(filePath).readAsBytes();
        final pages = await PdfTextExtractor.extractInIsolate(
          bytes,
          pageCount: totalPages,
        );
        if (pageIndex < pages.length) {
          return pages[pageIndex].text.trim();
        }
      } catch (_) {}
      return '';
    }();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PdfTextSheet(
        pageIndex: pageIndex,
        textFuture: textFuture,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Text Selection Logic
  // ---------------------------------------------------------------------------

  /// Clear current text selection.
  void _clearTextSelection() {
    _selSpans = const [];
    _selStartIdx = -1;
    _selEndIdx = -1;
    _selPageIdx = -1;
    _selAnchor = -1;
    _textOverlayRepaint.value++;
  }

  /// Extract text rects for a page (lazy, via native provider).
  /// Phase 1: fast getPageText() on all pages.
  /// Phase 2 (background OCR) is started separately by _startBackgroundOcr.
  Future<List<PdfTextRect>> _ensureTextRects(int pageIndex) async {
    if (_pageTextRects.containsKey(pageIndex)) {
      return _pageTextRects[pageIndex]!;
    }
    if (_isExtractingText) {
      return const [];
    }

    _isExtractingText = true;
    try {
      final provider = widget.provider;
      final totalPages = widget.documentModel.totalPages;

      // Phase 1: fast native text extraction (no OCR)
      final pageTexts = <_PageTextData>[];
      for (int i = 0; i < totalPages; i++) {
        final text = await provider.getPageText(i);

        List<PdfTextRect> rects = const [];
        if (text.trim().isNotEmpty) {
          try {
            rects = await provider.extractTextGeometry(i);
          } catch (_) {}
        }

        _pageTextRects[i] = rects;
        pageTexts.add(_PageTextData(text: text, rects: rects));
      }

      _providerPageTexts = pageTexts;
    } catch (e, st) {
      debugPrint('📝 ERROR in _ensureTextRects: $e\n$st');
      _pageTextRects[pageIndex] = const [];
    } finally {
      _isExtractingText = false;
    }
    return _pageTextRects[pageIndex] ?? const [];
  }

  /// Start background OCR for pages with no text (scanned pages).
  /// Updates search results incrementally as each page completes.
  void _startBackgroundOcr() {
    if (_ocrRunning || _providerPageTexts == null) return;

    final emptyPages = <int>[];
    for (int i = 0; i < _providerPageTexts!.length; i++) {
      if (_providerPageTexts![i].text.trim().isEmpty) {
        emptyPages.add(i);
      }
    }

    if (emptyPages.isEmpty) return;

    _ocrCancelled = false;
    _ocrRunning = true;
    _ocrTotal = emptyPages.length;
    _ocrProgress = 0;
    setState(() {});

    _runOcrBatch(emptyPages);
  }

  /// Process OCR pages one at a time in background.
  Future<void> _runOcrBatch(List<int> pages) async {
    final provider = widget.provider;

    for (int i = 0; i < pages.length; i++) {
      if (!mounted || _ocrCancelled) break;

      final pageIdx = pages[i];
      try {
        final ocrResult = await provider.ocrPage(pageIdx);
        if (ocrResult != null && ocrResult.text.isNotEmpty) {
          // Update page text data
          _providerPageTexts![pageIdx] = _PageTextData(
            text: ocrResult.text,
            rects: ocrResult.toTextRects(),
          );
          _pageTextRects[pageIdx] = ocrResult.toTextRects();
        }
      } catch (_) {}

      if (!mounted || _ocrCancelled) break;

      setState(() {
        _ocrProgress = i + 1;
      });

      // Re-run search with current query if user has typed something
      final q = _searchTextCtrl.text.trim();
      if (q.isNotEmpty) {
        _searchInPages(q);
      }
    }

    if (mounted) {
      setState(() {
        _ocrRunning = false;
      });
    }
  }

  /// Cancel background OCR.
  void _cancelOcr() {
    _ocrCancelled = true;
    _ocrRunning = false;
  }

  /// Provider-sourced page texts (for search).
  List<_PageTextData>? _providerPageTexts;

  /// Find the text rect index at a normalized position on the page.
  int _textRectIndexAt(int pageIndex, Offset normalizedPos) {
    final rects = _pageTextRects[pageIndex];
    if (rects == null || rects.isEmpty) return -1;

    // Direct hit test
    for (int i = 0; i < rects.length; i++) {
      if (rects[i].rect.contains(normalizedPos)) return i;
    }

    // Fallback: closest within tolerance
    const tolerance = 0.03; // 3% of page dimension
    double closest = double.infinity;
    int closestIdx = -1;
    for (int i = 0; i < rects.length; i++) {
      final center = rects[i].rect.center;
      final dist = (center - normalizedPos).distance;
      if (dist < closest && dist < tolerance) {
        closest = dist;
        closestIdx = i;
      }
    }
    return closestIdx;
  }

  /// Handle long-press start in text selection mode.
  void _onTextSelectStart(int pageIndex, Offset localPos, Size pageDisplaySize) {
    final page = widget.documentModel.pages[pageIndex];
    // Convert to normalized 0-1 coordinates
    final normX = localPos.dx / pageDisplaySize.width;
    final normY = localPos.dy / pageDisplaySize.height;
    final normPos = Offset(normX, normY);

    _ensureTextRects(pageIndex).then((rects) {
      if (!mounted || rects.isEmpty) return;
      final idx = _textRectIndexAt(pageIndex, normPos);
      if (idx < 0) {
        setState(_clearTextSelection);
        return;
      }
      setState(() {
        _selPageIdx = pageIndex;
        _selAnchor = idx;
        _selStartIdx = idx;
        _selEndIdx = idx;
        _selSpans = [rects[idx]];
      });
      _textOverlayRepaint.value++;
      HapticFeedback.selectionClick();
    });
  }

  /// Handle drag update in text selection mode.
  void _onTextSelectUpdate(int pageIndex, Offset localPos, Size pageDisplaySize) {
    if (_selPageIdx != pageIndex || _selAnchor < 0) return;
    final rects = _pageTextRects[pageIndex];
    if (rects == null || rects.isEmpty) return;

    final normX = localPos.dx / pageDisplaySize.width;
    final normY = localPos.dy / pageDisplaySize.height;
    final idx = _textRectIndexAt(pageIndex, Offset(normX, normY));
    if (idx < 0) return;

    final startIdx = idx < _selAnchor ? idx : _selAnchor;
    final endIdx = idx < _selAnchor ? _selAnchor : idx;

    if (startIdx != _selStartIdx || endIdx != _selEndIdx) {
      _selStartIdx = startIdx;
      _selEndIdx = endIdx;
      _selSpans = rects.sublist(startIdx, endIdx + 1);
      _textOverlayRepaint.value++;
    }
  }

  /// Handle release in text selection mode.
  void _onTextSelectEnd() {
    if (_selSpans.isNotEmpty) {
      // Show copy context action
      HapticFeedback.lightImpact();
    }
  }

  /// Copy selected text to clipboard.
  void _copySelectedText() {
    if (_selSpans.isEmpty) return;
    final buf = StringBuffer();
    for (int i = 0; i < _selSpans.length; i++) {
      if (i > 0) {
        final prevBottom = _selSpans[i - 1].rect.bottom;
        final currTop = _selSpans[i].rect.top;
        final lineH = _selSpans[i - 1].rect.height;
        if ((currTop - prevBottom).abs() < lineH * 0.5) {
          // Same line → space
          buf.write(' ');
        } else {
          buf.write('\n');
        }
      }
      buf.write(_selSpans[i].text);
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: const Color(0xFF2A2A4A),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Combined selected text string.
  String get _selectedText {
    if (_selSpans.isEmpty) return '';
    final buf = StringBuffer();
    for (int i = 0; i < _selSpans.length; i++) {
      if (i > 0) buf.write(' ');
      buf.write(_selSpans[i].text);
    }
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Search Logic
  // ---------------------------------------------------------------------------

  /// Register the PDF document bytes with the search controller.
  /// Also eagerly starts text extraction so search is ready when user types.
  void _ensureSearchDocRegistered() {
    if (_searchDocRegistered) return;
    final filePath = widget.documentModel.filePath;
    if (filePath == null || filePath.isEmpty) return;

    File(filePath).readAsBytes().then((bytes) {
      if (!mounted) return;
      _searchController.registerDocument(
        widget.documentId,
        bytes,
        provider: widget.provider,
      );
      _searchDocRegistered = true;
    });
    // Eagerly extract text geometry so it's ready when user types
    _ensureTextRects(0).then((_) {
      if (!mounted) return;
      // Check if PDF has pages with no text (scanned PDF)
      final hasText = _providerPageTexts?.any((p) => p.text.trim().isNotEmpty) ?? false;
      final hasEmptyPages = _providerPageTexts?.any((p) => p.text.trim().isEmpty) ?? false;

      if (hasEmptyPages && _showSearchBar) {
        // Start background OCR for scanned pages
        _startBackgroundOcr();
      }

      // If user already typed something while we were extracting, search now
      final q = _searchTextCtrl.text.trim();
      if (q.isNotEmpty && _searchMatches.isEmpty) {
        _searchInPages(q);
      }
    });
  }

  /// Debounce timer for search input.
  Timer? _searchDebounce;

  /// Run a search query (debounced 300ms).
  void _runSearch(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      _searchController.clearSearch();
      _searchMatches = const [];
      _searchCurrentIdx = -1;
      _textOverlayRepaint.value++;
      setState(() {});
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      // If text rects already extracted, search immediately
      if (_providerPageTexts != null) {
        _searchInPages(query);
      }
      // Otherwise, _ensureSearchDocRegistered's eager extraction
      // will pick up the query when it completes.
    });
  }

  /// Execute search across extracted page texts.
  void _searchInPages(String query) {
    final lowerQuery = query.trim().toLowerCase();
    if (lowerQuery.isEmpty) return;

    debugPrint('🔍 _searchInPages("$lowerQuery"), _providerPageTexts=${_providerPageTexts?.length}');
    if (_providerPageTexts == null) return;

    // Clear previous search state
    _searchController.clearSearch();

    final matches = <_SimpleSearchMatch>[];
    for (int pi = 0; pi < _providerPageTexts!.length; pi++) {
      final pageText = _providerPageTexts![pi].text.toLowerCase();
      int searchFrom = 0;
      while (true) {
        final idx = pageText.indexOf(lowerQuery, searchFrom);
        if (idx < 0) break;
        matches.add(_SimpleSearchMatch(
          pageIndex: pi,
          startOffset: idx,
          endOffset: idx + query.trim().length,
          snippet: _providerPageTexts![pi].text.substring(
            (idx - 20).clamp(0, _providerPageTexts![pi].text.length),
            (idx + query.trim().length + 20).clamp(0, _providerPageTexts![pi].text.length),
          ),
        ));
        searchFrom = idx + 1;
      }
    }

    debugPrint('🔍 Found ${matches.length} matches for "$lowerQuery"');
    setState(() {
      _searchMatches = matches;
      _searchCurrentIdx = matches.isNotEmpty ? 0 : -1;
    });
    _textOverlayRepaint.value++;

    // Auto-scroll to first match
    if (matches.isNotEmpty) {
      _scrollToPage(matches.first.pageIndex);
    }
  }

  /// Simple search matches (in-process, no PdfDocumentNode needed).
  List<_SimpleSearchMatch> _searchMatches = const [];
  int _searchCurrentIdx = -1;

  void _searchNext() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _searchCurrentIdx = (_searchCurrentIdx + 1) % _searchMatches.length;
    });
    _scrollToPage(_searchMatches[_searchCurrentIdx].pageIndex);
    _textOverlayRepaint.value++;
  }

  void _searchPrev() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _searchCurrentIdx = (_searchCurrentIdx - 1 + _searchMatches.length) % _searchMatches.length;
    });
    _scrollToPage(_searchMatches[_searchCurrentIdx].pageIndex);
    _textOverlayRepaint.value++;
  }

  /// Get search highlight rects for a specific page (normalized 0-1 coords).
  List<Rect> _searchHighlightsForPage(int pageIndex) {
    final rects = <Rect>[];
    final pageRects = _pageTextRects[pageIndex];
    if (pageRects == null || pageRects.isEmpty) return rects;

    for (final match in _searchMatches) {
      if (match.pageIndex != pageIndex) continue;
      // Find text rects that overlap this match's character range
      for (final tr in pageRects) {
        final trEnd = tr.charOffset + tr.text.length;
        if (trEnd <= match.startOffset) continue;
        if (tr.charOffset >= match.endOffset) break;
        rects.add(tr.rect);
      }
    }
    return rects;
  }

  /// Get the current search match highlight rect for a page.
  Rect? _currentSearchHighlightForPage(int pageIndex) {
    if (_searchCurrentIdx < 0 || _searchCurrentIdx >= _searchMatches.length) {
      return null;
    }
    final match = _searchMatches[_searchCurrentIdx];
    if (match.pageIndex != pageIndex) return null;

    final pageRects = _pageTextRects[pageIndex];
    if (pageRects == null) return null;

    Rect? union;
    for (final tr in pageRects) {
      final trEnd = tr.charOffset + tr.text.length;
      if (trEnd <= match.startOffset) continue;
      if (tr.charOffset >= match.endOffset) break;
      union = union == null ? tr.rect : union.expandToInclude(tr.rect);
    }
    return union;
  }

  // ---------------------------------------------------------------------------
  // Search Bar Widget
  // ---------------------------------------------------------------------------

  Widget _buildSearchBar() {
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        offset: _showSearchBar ? Offset.zero : const Offset(0, -2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _showSearchBar ? 1.0 : 0.0,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xDD1A1A36),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0x30FFFFFF),
                width: 0.5,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x60000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                const Icon(Icons.search_rounded,
                    color: Color(0x99FFFFFF), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchTextCtrl,
                    autofocus: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Search in PDF...',
                      hintStyle: TextStyle(
                        color: Color(0x66FFFFFF),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: _runSearch,
                    onSubmitted: (_) => _searchNext(),
                  ),
                ),
                // Match count badge
                if (_searchMatches.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0x30FFFFFF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_searchCurrentIdx + 1}/${_searchMatches.length}',
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                // OCR progress indicator
                if (_ocrRunning)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x30FF9800),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 10, height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation(Color(0xCCFF9800)),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$_ocrProgress/$_ocrTotal',
                          style: const TextStyle(
                            color: Color(0xCCFF9800),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Prev/Next buttons
                if (_searchMatches.isNotEmpty) ...[
                  _searchNavButton(Icons.keyboard_arrow_up_rounded, _searchPrev),
                  _searchNavButton(Icons.keyboard_arrow_down_rounded, _searchNext),
                ],
                // Close button
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0x99FFFFFF), size: 18),
                  onPressed: () {
                    _cancelOcr();
                    setState(() {
                      _showSearchBar = false;
                      _searchController.clearSearch();
                      _searchTextCtrl.clear();
                      _searchMatches = const [];
                      _searchCurrentIdx = -1;
                    });
                    _textOverlayRepaint.value++;
                  },
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchNavButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: const Color(0xBBFFFFFF), size: 20),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bookmarks
  // ---------------------------------------------------------------------------

  /// Toggle bookmark on the current visible page.
  void _toggleBookmark() {
    final page = _currentPageIndex;
    if (_bookmarkedPages.containsKey(page)) {
      _removeBookmarkWithUndo(page);
    } else {
      setState(() {
        _bookmarkedPages[page] = _BookmarkData(color: _activeBookmarkColor);
      });
      _syncBookmarkToModel(page, true);
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Page ${page + 1} bookmarked'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: const Color(0xFF2A2A4A),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// Remove a bookmark with undo support.
  void _removeBookmarkWithUndo(int pageIndex) {
    final savedData = _bookmarkedPages[pageIndex];
    setState(() => _bookmarkedPages.remove(pageIndex));
    _syncBookmarkToModel(pageIndex, false);
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Page ${pageIndex + 1} bookmark removed'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: const Color(0xFF2A2A4A),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          textColor: const Color(0xFF42A5F5),
          onPressed: () {
            if (savedData != null) {
              setState(() => _bookmarkedPages[pageIndex] = savedData);
              _syncBookmarkToModel(pageIndex, true);
            }
          },
        ),
      ),
    );
  }

  /// Jump to the previous bookmarked page.
  void _jumpToPrevBookmark() {
    if (_bookmarkedPages.isEmpty) return;
    final sorted = _bookmarkedPages.keys.toList()..sort();
    final before = sorted.where((p) => p < _currentPageIndex).toList();
    if (before.isNotEmpty) {
      _scrollToPage(before.last);
    } else {
      _scrollToPage(sorted.last);
    }
    HapticFeedback.selectionClick();
  }

  /// Jump to the next bookmarked page.
  void _jumpToNextBookmark() {
    if (_bookmarkedPages.isEmpty) return;
    final sorted = _bookmarkedPages.keys.toList()..sort();
    final after = sorted.where((p) => p > _currentPageIndex).toList();
    if (after.isNotEmpty) {
      _scrollToPage(after.first);
    } else {
      _scrollToPage(sorted.first);
    }
    HapticFeedback.selectionClick();
  }

  /// Open note editor for a specific bookmark (used by double-tap on ribbon).
  void _editBookmarkNote(int pageIndex) {
    final bm = _bookmarkedPages[pageIndex];
    if (bm == null) return;
    final ctrl = TextEditingController(text: bm.note);
    showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A36),
        title: Text('Note - Page ${pageIndex + 1}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Add a note...',
            hintStyle: const TextStyle(color: Colors.white24),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0x33FFFFFF)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF6C63FF)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, ctrl.text),
            child: const Text('Save', style: TextStyle(color: Color(0xFF6C63FF))),
          ),
        ],
      ),
    ).then((result) {
      if (result != null) {
        setState(() => bm.note = result);
      }
    });
  }

  /// Export bookmark summary as a text file.
  Future<void> _exportBookmarkSummary() async {
    final sorted = _bookmarkedPages.keys.toList()..sort();
    if (sorted.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln('Bookmark Summary');
    buffer.writeln('========================================');
    buffer.writeln('Total bookmarks: ${sorted.length}');
    buffer.writeln('');
    for (final pageIdx in sorted) {
      final bm = _bookmarkedPages[pageIdx]!;
      buffer.writeln('Page ${pageIdx + 1}');
      if (bm.note.isNotEmpty) {
        buffer.writeln('   Note: ${bm.note}');
      }
      final hasAnnotations = (_pageStrokes[pageIdx]?.isNotEmpty ?? false);
      buffer.writeln('   Annotations: ${hasAnnotations ? 'Yes' : 'None'}');
      buffer.writeln('');
    }
    final tmpDir = await getTemporaryDirectory();
    final file = File('${tmpDir.path}/bookmark_summary.txt');
    await file.writeAsString(buffer.toString());
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Bookmark summary (${sorted.length} pages)',
      ),
    );
  }

  /// Sync bookmark state to PdfPageModel for persistence.
  void _syncBookmarkToModel(int pageIndex, bool isBookmarked) {
    final pages = widget.documentModel.pages;
    if (pageIndex < pages.length) {
      pages[pageIndex] = pages[pageIndex].copyWith(isBookmarked: isBookmarked);
    }
  }

  /// Load bookmarks from model on init.
  void _loadBookmarksFromModel() {
    for (int i = 0; i < widget.documentModel.pages.length; i++) {
      if (widget.documentModel.pages[i].isBookmarked) {
        _bookmarkedPages[i] = _BookmarkData();
      }
    }
  }

  /// Show bookmarks list panel for quick navigation.
  void _showBookmarksPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A36),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final sorted = _bookmarkedPages.keys.toList()..sort();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0x40FFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Header with quick-jump arrows
                  Row(
                    children: [
                      const Icon(Icons.bookmark_rounded, color: Color(0xFFEF5350), size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bookmarks (${sorted.length})',
                              style: const TextStyle(
                                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (sorted.isNotEmpty)
                              Text(
                                [
                                  '${_bookmarkedPages.values.where((b) => b.note.isNotEmpty).length} with notes',
                                  '${sorted.where((p) => (_pageStrokes[p]?.isNotEmpty ?? false)).length} annotated',
                                ].join(' | '),
                                style: const TextStyle(color: Colors.white30, fontSize: 10),
                              ),
                          ],
                        ),
                      ),
                      if (sorted.length > 1) ...[
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white54, size: 24),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _jumpToPrevBookmark();
                          },
                          tooltip: 'Previous bookmark',
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 24),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _jumpToNextBookmark();
                          },
                          tooltip: 'Next bookmark',
                        ),
                      ],
                    ],
                  ),
                  // Color picker row
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 32,
                    child: Row(
                      children: [
                        const Text('Tag color: ',
                            style: TextStyle(color: Colors.white38, fontSize: 11)),
                        const SizedBox(width: 4),
                        for (final c in _bookmarkColors)
                          GestureDetector(
                            onTap: () {
                              setState(() => _activeBookmarkColor = c);
                              setSheetState(() {});
                            },
                            child: Container(
                              width: 22, height: 22,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _activeBookmarkColor == c ? Colors.white : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (sorted.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No bookmarks yet.\nUse the bookmark sector to add pages.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                      ),
                    )
                  else
                    SizedBox(
                      height: math.min(sorted.length * 80.0, 360),
                      child: ListView.builder(
                        itemCount: sorted.length,
                        itemBuilder: (_, idx) {
                          final pageIdx = sorted[idx];
                          final bm = _bookmarkedPages[pageIdx]!;
                          final page = widget.documentModel.pages[pageIdx];
                          final aspect = page.originalSize.height / page.originalSize.width;
                          final img = _pageImages[pageIdx];
                          return Dismissible(
                            key: ValueKey('bm_$pageIdx'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB71C1C),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.delete_rounded, color: Colors.white),
                            ),
                            onDismissed: (_) {
                              setState(() => _bookmarkedPages.remove(pageIdx));
                              _syncBookmarkToModel(pageIdx, false);
                              setSheetState(() {});
                            },
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _scrollToPage(pageIdx);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      // Color indicator bar
                                      Container(
                                        width: 4, height: 40,
                                        margin: const EdgeInsets.only(right: 10),
                                        decoration: BoxDecoration(
                                          color: bm.color,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      // Page thumbnail
                                      Container(
                                        width: 48,
                                        height: 48 * aspect,
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
                                                  '${pageIdx + 1}',
                                                  style: const TextStyle(
                                                    color: Color(0xFF999999), fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Page ${pageIdx + 1}',
                                                style: const TextStyle(
                                                    color: Colors.white, fontSize: 14,
                                                    fontWeight: FontWeight.w500)),
                                            if (bm.note.isNotEmpty)
                                              Text(bm.note,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      color: Colors.white38, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                      // Add/edit note
                                      IconButton(
                                        icon: Icon(
                                          bm.note.isEmpty ? Icons.note_add_rounded : Icons.edit_note_rounded,
                                          color: const Color(0x66FFFFFF), size: 20,
                                        ),
                                        onPressed: () async {
                                          final ctrl = TextEditingController(text: bm.note);
                                          final result = await showDialog<String>(
                                            context: context,
                                            builder: (dCtx) => AlertDialog(
                                              backgroundColor: const Color(0xFF1A1A36),
                                              title: Text('Note — Page ${pageIdx + 1}',
                                                  style: const TextStyle(color: Colors.white, fontSize: 16)),
                                              content: TextField(
                                                controller: ctrl,
                                                autofocus: true,
                                                maxLines: 3,
                                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                                decoration: InputDecoration(
                                                  hintText: 'Add a note...',
                                                  hintStyle: const TextStyle(color: Colors.white24),
                                                  enabledBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                    borderSide: const BorderSide(color: Color(0x33FFFFFF)),
                                                  ),
                                                  focusedBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                    borderSide: const BorderSide(color: Color(0xFF6C63FF)),
                                                  ),
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(dCtx),
                                                  child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.pop(dCtx, ctrl.text),
                                                  child: const Text('Save', style: TextStyle(color: Color(0xFF6C63FF))),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (result != null) {
                                            setState(() => bm.note = result);
                                            setSheetState(() {});
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
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

  // ---------------------------------------------------------------------------
  // Export Annotated
  // ---------------------------------------------------------------------------

  /// Show export options bottom sheet.
  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A36),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0x40FFFFFF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Export Annotated PDF',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                // Quality selector
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Quality: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    for (final q in [1.0, 2.0, 3.0])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text('${q.toInt()}×',
                              style: TextStyle(
                                color: _exportScale == q ? Colors.white : Colors.white54,
                                fontSize: 12, fontWeight: FontWeight.w600,
                              )),
                          selected: _exportScale == q,
                          selectedColor: const Color(0xFF42A5F5),
                          backgroundColor: const Color(0x15FFFFFF),
                          side: BorderSide.none,
                          onSelected: (_) {
                            setState(() => _exportScale = q);
                            setSheetState(() {});
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _exportOption(
                  ctx,
                  icon: Icons.insert_drive_file_rounded,
                  label: 'Current Page',
                  subtitle: 'Page ${_currentPageIndex + 1}',
                  pages: [_currentPageIndex],
                ),
                if (_bookmarkedPages.isNotEmpty)
                  _exportOption(
                    ctx,
                    icon: Icons.bookmark_rounded,
                    label: 'Bookmarked Pages',
                    subtitle: '${_bookmarkedPages.length} pages',
                    pages: _bookmarkedPages.keys.toList()..sort(),
                  ),
                _exportOption(
                  ctx,
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'All Pages',
                  subtitle: '${widget.documentModel.totalPages} pages',
                  pages: List.generate(
                      widget.documentModel.totalPages, (i) => i),
                ),
                const SizedBox(height: 8),
                // Bookmark summary export
                if (_bookmarkedPages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: const Color(0x15FFFFFF),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.pop(ctx);
                          _exportBookmarkSummary();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0x20FFFFFF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.summarize_rounded, color: Color(0xFF80CBC4), size: 18),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Bookmark Summary',
                                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                                    Text('${_bookmarkedPages.length} bookmarks with notes',
                                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, color: Colors.white24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _exportOption(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required String subtitle,
    required List<int> pages,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0x15FFFFFF),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.pop(ctx);
            _exportAnnotatedPages(pages);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF42A5F5), size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Color(0x99FFFFFF), fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0x66FFFFFF), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Export selected pages as annotated PNG images.
  Future<void> _exportAnnotatedPages(List<int> pageIndices) async {
    // Show progress overlay
    final progressNotifier = ValueNotifier<double>(0.0);
    final progressText = ValueNotifier<String>('Preparing export...');
    OverlayEntry? overlay;
    overlay = OverlayEntry(
      builder: (_) => Material(
        color: const Color(0xCC000000),
        child: Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A36),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Color(0x40000000), blurRadius: 20),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.ios_share_rounded, color: Color(0xFF42A5F5), size: 32),
                const SizedBox(height: 16),
                const Text('Exporting...',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (_, v, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: v,
                      backgroundColor: const Color(0x20FFFFFF),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF42A5F5)),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<String>(
                  valueListenable: progressText,
                  builder: (_, t, __) => Text(t,
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(overlay);

    try {
      final tmpDir = await getTemporaryDirectory();
      final exportDir = Directory(
          '${tmpDir.path}/pdf_export_${DateTime.now().millisecondsSinceEpoch}');
      await exportDir.create(recursive: true);

      final exportedPaths = <String>[];
      final total = pageIndices.length;

      for (int i = 0; i < total; i++) {
        final pageIdx = pageIndices[i];
        if (!mounted) return;

        progressText.value = 'Page ${i + 1} of $total';
        progressNotifier.value = i / total;

        // 1. Render the page image at selected resolution
        final originalSize = widget.documentModel.pages[pageIdx].originalSize;
        final scale = _exportScale;
        final targetSize = Size(
          originalSize.width * scale,
          originalSize.height * scale,
        );

        final pageImage = await widget.provider.renderPage(
          pageIndex: pageIdx,
          scale: scale,
          targetSize: targetSize,
        );
        if (pageImage == null) continue;

        // 2. Composite page image + strokes using PictureRecorder
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        // Draw page image
        canvas.drawImage(pageImage, Offset.zero, Paint());

        // Draw annotation strokes
        final strokes = _pageStrokes[pageIdx] ?? [];
        if (strokes.isNotEmpty) {
          final scaleX = targetSize.width / originalSize.width;
          final scaleY = targetSize.height / originalSize.height;
          canvas.save();
          canvas.scale(scaleX, scaleY);
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
          canvas.restore();
        }

        final picture = recorder.endRecording();
        final composited = await picture.toImage(
          targetSize.width.toInt(),
          targetSize.height.toInt(),
        );

        // 3. Encode as PNG
        final byteData = await composited.toByteData(
            format: ui.ImageByteFormat.png);
        if (byteData == null) continue;

        final filePath = '${exportDir.path}/page_${pageIdx + 1}.png';
        await File(filePath).writeAsBytes(byteData.buffer.asUint8List());
        exportedPaths.add(filePath);

        // Dispose images
        pageImage.dispose();
        composited.dispose();

        // 🚀 Yield to UI thread between pages — keeps progress overlay responsive
        await Future<void>.delayed(Duration.zero);
      }

      if (!mounted) return;

      overlay.remove();
      overlay = null;

      // Share via system share sheet
      if (exportedPaths.isNotEmpty) {
        await SharePlus.instance.share(
          ShareParams(
            files: exportedPaths.map((p) => XFile(p)).toList(),
            text: 'Annotated PDF export (${exportedPaths.length} pages)',
          ),
        );
      }
    } catch (e) {
      overlay?.remove();
      overlay = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          backgroundColor: const Color(0xFFB71C1C),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Text Selection Context Toolbar
  // ---------------------------------------------------------------------------

  Widget _buildTextSelectionToolbar(Size pageDisplaySize) {
    if (_selSpans.isEmpty || _selPageIdx < 0) return const SizedBox.shrink();

    // Compute the top-center of the selection in page-display coordinates
    double minY = double.infinity;
    double sumX = 0;
    for (final span in _selSpans) {
      final top = span.rect.top * pageDisplaySize.height;
      if (top < minY) minY = top;
      sumX += span.rect.center.dx * pageDisplaySize.width;
    }
    final avgX = sumX / _selSpans.length;

    return Positioned(
      left: (avgX - 50).clamp(4.0, pageDisplaySize.width - 100),
      top: (minY - 44).clamp(0.0, pageDisplaySize.height - 36),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xEE1A1A36),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x30FFFFFF), width: 0.5),
          boxShadow: const [
            BoxShadow(color: Color(0x60000000), blurRadius: 8),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ctxButton('Copy', Icons.copy_rounded, _copySelectedText),
            _ctxButton('All', Icons.select_all_rounded, () {
              final rects = _pageTextRects[_selPageIdx];
              if (rects == null || rects.isEmpty) return;
              setState(() {
                _selStartIdx = 0;
                _selEndIdx = rects.length - 1;
                _selSpans = rects;
              });
              _textOverlayRepaint.value++;
            }),
          ],
        ),
      ),
    );
  }

  Widget _ctxButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xCCFFFFFF)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(
              color: Color(0xCCFFFFFF), fontSize: 11,
              fontWeight: FontWeight.w600,
            )),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 📄 PDF Text Extraction Bottom Sheet  (v2)
// =============================================================================

class _PdfTextSheet extends StatefulWidget {
  final int pageIndex;

  /// Resolves to the extracted page text (may take 1-2 s for large PDFs).
  /// The sheet opens immediately and shows a spinner while this is pending.
  final Future<String> textFuture;

  const _PdfTextSheet({required this.pageIndex, required this.textFuture});

  @override
  State<_PdfTextSheet> createState() => _PdfTextSheetState();
}

class _PdfTextSheetState extends State<_PdfTextSheet> {
  // ── Copy state ──
  bool _copied = false;

  // ── Search state ──
  final _searchCtrl = TextEditingController();
  bool _showSearch = false;
  String _query = '';

  // ── Atlas state ──
  bool _atlasLoading = false;
  String _atlasReply = '';
  StreamSubscription<String>? _atlasSub;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _atlasSub?.cancel();
    super.dispose();
  }

  // ── Helpers ──

  String _highlightText(String text, String q) => text; // SelectableText handles it

  int _wordCount(String t) =>
      t.trim().isEmpty ? 0 : t.trim().split(RegExp(r'\s+')).length;

  Future<void> _askAtlas(String text) async {
    if (text.isEmpty || _atlasLoading) return;
    setState(() {
      _atlasLoading = true;
      _atlasReply = '';
    });
    HapticFeedback.lightImpact();

    try {
      final provider = EngineScope.current.atlasProvider;
      if (!provider.isInitialized) await provider.initialize();

      final prompt =
          'Sei ATLAS, un tutor accademico di alto livello. '
          'L\'utente sta leggendo un documento PDF. '
          'Analizza il seguente testo estratto dalla pagina ${widget.pageIndex + 1} e fornisci:\n'
          '1. Un riassunto conciso (max 3 frasi)\n'
          '2. I 3 concetti chiave\n'
          '3. Una domanda di riflessione\n\n'
          'Rispondi nella stessa lingua del testo.\n\n'
          '---\n$text\n---';

      final buffer = StringBuffer();
      final stream = provider.askAtlasStream(prompt, []);
      _atlasSub = stream
          .timeout(const Duration(seconds: 30), onTimeout: (s) => s.close())
          .listen(
            (chunk) {
              buffer.write(chunk);
              if (mounted) setState(() => _atlasReply = buffer.toString());
            },
            onDone: () {
              if (mounted) setState(() => _atlasLoading = false);
            },
            onError: (_) {
              if (mounted) setState(() {
                _atlasLoading = false;
                if (_atlasReply.isEmpty) _atlasReply = '⚠️ Errore nella risposta di Atlas.';
              });
            },
          );
    } catch (e) {
      if (mounted) setState(() {
        _atlasLoading = false;
        _atlasReply = '⚠️ Atlas non disponibile: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) {
        return FutureBuilder<String>(
          future: widget.textFuture,
          builder: (context, snap) {
            final isLoading = snap.connectionState != ConnectionState.done;
            final text = snap.data ?? '';
            final hasText = text.isNotEmpty;

            // Apply search filter
            final displayText = _query.isEmpty
                ? text
                : text; // SelectableText doesn't support inline highlight;
                         // we show filtered paragraphs below instead.

            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF12122A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // ── Handle bar ──
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // ── Header row ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.text_snippet_rounded,
                            color: Color(0xFF80DEEA), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pagina ${widget.pageIndex + 1} — Testo estratto',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              if (!isLoading && hasText)
                                Text(
                                  '${_wordCount(text)} parole · ${text.length} caratteri',
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Search toggle
                        IconButton(
                          onPressed: () => setState(() {
                            _showSearch = !_showSearch;
                            if (!_showSearch) {
                              _searchCtrl.clear();
                              _query = '';
                            }
                          }),
                          icon: Icon(
                            _showSearch ? Icons.search_off_rounded : Icons.search_rounded,
                            color: _showSearch ? const Color(0xFF80DEEA) : Colors.white38,
                            size: 20,
                          ),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Cerca nel testo',
                        ),
                        // Copy button
                        if (hasText && !isLoading)
                          GestureDetector(
                            onTap: () async {
                              await Clipboard.setData(ClipboardData(text: text));
                              setState(() => _copied = true);
                              await Future.delayed(const Duration(seconds: 2));
                              if (mounted) setState(() => _copied = false);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                color: _copied
                                    ? const Color(0xFF4CAF50).withValues(alpha: 0.2)
                                    : const Color(0xFF80DEEA).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _copied
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFF80DEEA).withValues(alpha: 0.5),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                                    size: 13,
                                    color: _copied
                                        ? const Color(0xFF4CAF50)
                                        : const Color(0xFF80DEEA),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _copied ? 'Copiato!' : 'Copia',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _copied
                                          ? const Color(0xFF4CAF50)
                                          : const Color(0xFF80DEEA),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ── Search bar (animated) ──
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: _showSearch
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: TextField(
                              controller: _searchCtrl,
                              autofocus: true,
                              onChanged: (v) => setState(() => _query = v.toLowerCase()),
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Cerca nel testo…',
                                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                                prefixIcon: const Icon(Icons.search_rounded,
                                    color: Colors.white38, size: 18),
                                suffixIcon: _query.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded,
                                            color: Colors.white38, size: 16),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() => _query = '');
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: Colors.white10,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  const Divider(color: Colors.white10, height: 1),

                  // ── Main content ──
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Text area
                          if (isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Column(
                                  children: [
                                    CircularProgressIndicator(
                                      color: Color(0xFF80DEEA),
                                      strokeWidth: 2,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Estrazione in corso…',
                                      style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (!hasText)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.text_fields_rounded,
                                      color: Colors.white24, size: 40),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Nessun testo trovato.\nPotrebbe essere un PDF scansionato.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (_query.isNotEmpty)
                            // ── Filtered view: show only matching paragraphs ──
                            ..._buildFilteredParagraphs(text, _query)
                          else
                            SelectableText(
                              text,
                              style: const TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 13.5,
                                height: 1.7,
                                letterSpacing: 0.1,
                              ),
                            ),

                          // ── Atlas section ──
                          if (!isLoading && hasText) ...[
                            const SizedBox(height: 20),
                            const Divider(color: Colors.white10),
                            const SizedBox(height: 12),

                            // CTA button
                            if (_atlasReply.isEmpty && !_atlasLoading)
                              _AtlasCta(onTap: () => _askAtlas(text))
                            else
                              _AtlasReplyCard(
                                reply: _atlasReply,
                                isLoading: _atlasLoading,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Returns paragraph widgets that contain [query], with the match highlighted.
  List<Widget> _buildFilteredParagraphs(String text, String query) {
    final paragraphs = text.split('\n').where((p) => p.trim().isNotEmpty).toList();
    final matches = paragraphs
        .where((p) => p.toLowerCase().contains(query))
        .toList();

    if (matches.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'Nessun risultato per "$_query".',
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      ];
    }

    return [
      Text(
        '${matches.length} risultat${matches.length == 1 ? 'o' : 'i'} per "$_query"',
        style: const TextStyle(
            color: Color(0xFF80DEEA), fontSize: 11, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      for (final para in matches)
        _HighlightedParagraph(text: para, query: query),
    ];
  }
}

// ── Highlighted paragraph widget ──────────────────────────────────────────────

class _HighlightedParagraph extends StatelessWidget {
  final String text;
  final String query;
  const _HighlightedParagraph({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final idx = lower.indexOf(query, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(
          backgroundColor: Color(0x4480DEEA),
          color: Color(0xFF80DEEA),
          fontWeight: FontWeight.w700,
        ),
      ));
      start = idx + query.length;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x2080DEEA)),
        ),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(
                color: Color(0xCCFFFFFF), fontSize: 13, height: 1.6),
            children: spans,
          ),
        ),
      ),
    );
  }
}

// ── Atlas CTA button ───────────────────────────────────────────────────────────

class _AtlasCta extends StatelessWidget {
  final VoidCallback onTap;
  const _AtlasCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF80DEEA)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              'Chiedi ad Atlas',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Atlas reply card ──────────────────────────────────────────────────────────

class _AtlasReplyCard extends StatelessWidget {
  final String reply;
  final bool isLoading;
  const _AtlasReplyCard({required this.reply, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: Color(0xFF6C63FF), size: 15),
              const SizedBox(width: 6),
              const Text(
                'Atlas',
                style: TextStyle(
                  color: Color(0xFF6C63FF),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              if (isLoading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 10, height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Color(0xFF6C63FF),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            reply.isNotEmpty ? reply : '…',
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 13,
              height: 1.65,
            ),
          ),
        ],
      ),
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

/// Draws a red bookmark ribbon (flag shape).
class _BookmarkRibbonPainter extends CustomPainter {
  final Color color;
  _BookmarkRibbonPainter({this.color = const Color(0xFFEF5350)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * 0.72)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);

    // Subtle shadow
    final shadowPaint = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BookmarkRibbonPainter old) => old.color != color;
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
  final Rect? visibleRect;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final ShapeType shapeType;
  final ProBrushSettings liveBrushSettings;
  final ui.Image? pageImage;
  final bool isZoomed;

  _AnnotationOverlayPainter({
    required this.strokes,
    this.livePoints,
    required this.liveColor,
    required this.liveWidth,
    required this.livePenType,
    required this.pageOriginalSize,
    required this.displaySize,
    this.visibleRect,
    this.shapeStart,
    this.shapeEnd,
    this.shapeType = ShapeType.freehand,
    this.liveBrushSettings = const ProBrushSettings(),
    this.pageImage,
    this.isZoomed = false,
    ValueNotifier<int>? repaintNotifier,
  }) : super(repaint: repaintNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the page image first so brush blend modes (multiply, etc.)
    // composite against actual page pixels rather than transparent.
    if (pageImage != null) {
      final src = Rect.fromLTWH(0, 0, pageImage!.width.toDouble(), pageImage!.height.toDouble());
      final dst = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawImageRect(
        pageImage!, src, dst,
        Paint()..filterQuality = isZoomed ? FilterQuality.medium : FilterQuality.high,
      );
    }

    // Scale from PDF-page coords to display coords
    final sx = displaySize.width / pageOriginalSize.width;
    final sy = displaySize.height / pageOriginalSize.height;

    canvas.save();
    canvas.scale(sx, sy);

    // Draw committed strokes (native blend modes work correctly
    // since they composite against the page drawn above)
    // 🚀 VIEWPORT CULLING: skip strokes completely outside visible area
    for (final stroke in strokes) {
      if (visibleRect != null && !stroke.bounds.overlaps(visibleRect!)) {
        continue; // Off-screen, skip rendering
      }
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
        liveBrushSettings,
        isLive: true,
      );
    }

    // Draw live shape preview
    if (shapeStart != null && shapeEnd != null && shapeType != ShapeType.freehand) {
      _drawShapePreview(canvas, shapeStart!, shapeEnd!, shapeType);
    }

    canvas.restore();
  }

  void _drawShapePreview(Canvas canvas, Offset start, Offset end, ShapeType type) {
    final paint = Paint()
      ..color = liveColor
      ..strokeWidth = liveWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (type) {
      case ShapeType.freehand:
        break;
      case ShapeType.line:
        canvas.drawLine(start, end, paint);
        break;
      case ShapeType.rectangle:
        canvas.drawRect(Rect.fromPoints(start, end), paint);
        break;
      case ShapeType.circle:
        canvas.drawOval(Rect.fromPoints(start, end), paint);
        break;
      case ShapeType.arrow:
        // Arrow with head
        canvas.drawLine(start, end, paint);
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len > 1) {
          final nx = dx / len;
          final ny = dy / len;
          final headLen = len * 0.2;
          final headW = headLen * 0.6;
          final path = ui.Path()
            ..moveTo(end.dx - nx * headLen - ny * headW, end.dy - ny * headLen + nx * headW)
            ..lineTo(end.dx, end.dy)
            ..lineTo(end.dx - nx * headLen + ny * headW, end.dy - ny * headLen - nx * headW);
          canvas.drawPath(path, paint);
        }
        break;
      default:
        // For triangle, star, heart, diamond, pentagon, hexagon — draw as path
        final path = ui.Path();
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final rx = (end.dx - start.dx).abs() / 2;
        final ry = (end.dy - start.dy).abs() / 2;
        List<Offset> pts;
        switch (type) {
          case ShapeType.triangle:
            pts = [
              Offset(center.dx, start.dy),
              Offset(end.dx, end.dy),
              Offset(start.dx, end.dy),
              Offset(center.dx, start.dy),
            ];
            break;
          case ShapeType.star:
            pts = [];
            for (int i = 0; i <= 10; i++) {
              final angle = math.pi / 2 + (2 * math.pi * i / 10);
              final r = i.isEven ? 1.0 : 0.4;
              pts.add(Offset(center.dx + rx * r * math.cos(angle), center.dy - ry * r * math.sin(angle)));
            }
            break;
          case ShapeType.diamond:
            pts = [
              Offset(center.dx, start.dy),
              Offset(end.dx, center.dy),
              Offset(center.dx, end.dy),
              Offset(start.dx, center.dy),
              Offset(center.dx, start.dy),
            ];
            break;
          case ShapeType.pentagon:
            pts = List.generate(6, (i) {
              final angle = -math.pi / 2 + 2 * math.pi * i / 5;
              return Offset(center.dx + rx * math.cos(angle), center.dy + ry * math.sin(angle));
            });
            break;
          case ShapeType.hexagon:
            pts = List.generate(7, (i) {
              final angle = 2 * math.pi * i / 6;
              return Offset(center.dx + rx * math.cos(angle), center.dy + ry * math.sin(angle));
            });
            break;
          case ShapeType.heart:
            pts = List.generate(37, (i) {
              final t = 2 * math.pi * i / 36;
              return Offset(
                center.dx + rx * 16 * math.pow(math.sin(t), 3) / 16,
                center.dy - ry * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) / 16,
              );
            });
            break;
          default:
            pts = [];
        }
        if (pts.length >= 2) {
          path.moveTo(pts.first.dx, pts.first.dy);
          for (int i = 1; i < pts.length; i++) {
            path.lineTo(pts[i].dx, pts[i].dy);
          }
          canvas.drawPath(path, paint);
        }
    }
  }

  @override
  bool shouldRepaint(_AnnotationOverlayPainter old) {
    // Notifier-driven repaints handle live strokes.
    // Only rebuild compare committed strokes, settings, and viewport.
    return old.strokes.length != strokes.length ||
           !identical(old.pageImage, pageImage) ||
           old.visibleRect != visibleRect ||
           old.liveColor != liveColor ||
           old.liveWidth != liveWidth ||
           old.livePenType != livePenType ||
           old.shapeStart != shapeStart ||
           old.shapeEnd != shapeEnd ||
           old.shapeType != shapeType ||
           old.isZoomed != isZoomed;
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

// =============================================================================
// 📝 Text Highlight Painter — selection + search highlights
// =============================================================================

class _TextHighlightPainter extends CustomPainter {
  final List<PdfTextRect> selectionSpans;
  final List<Rect> searchHighlights;
  final Rect? currentSearchHighlight;

  _TextHighlightPainter({
    required this.selectionSpans,
    this.searchHighlights = const [],
    this.currentSearchHighlight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Search highlights (yellow)
    if (searchHighlights.isNotEmpty) {
      final searchPaint = Paint()
        ..color = const Color(0x55FFEB3B)
        ..style = PaintingStyle.fill;
      for (final r in searchHighlights) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              r.left * size.width,
              r.top * size.height,
              r.right * size.width,
              r.bottom * size.height,
            ),
            const Radius.circular(2),
          ),
          searchPaint,
        );
      }
    }

    // 2. Current search match (orange)
    if (currentSearchHighlight != null) {
      final r = currentSearchHighlight!;
      final currentPaint = Paint()
        ..color = const Color(0x88FF9800)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            r.left * size.width,
            r.top * size.height,
            r.right * size.width,
            r.bottom * size.height,
          ),
          const Radius.circular(2),
        ),
        currentPaint,
      );
      // Orange border for current match
      final borderPaint = Paint()
        ..color = const Color(0xCCFF9800)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            r.left * size.width,
            r.top * size.height,
            r.right * size.width,
            r.bottom * size.height,
          ),
          const Radius.circular(2),
        ),
        borderPaint,
      );
    }

    // 3. Text selection highlights (blue)
    if (selectionSpans.isNotEmpty) {
      final selPaint = Paint()
        ..color = const Color(0x444FC3F7)
        ..style = PaintingStyle.fill;
      for (final span in selectionSpans) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              span.rect.left * size.width,
              span.rect.top * size.height,
              span.rect.right * size.width,
              span.rect.bottom * size.height,
            ),
            const Radius.circular(2),
          ),
          selPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TextHighlightPainter old) =>
      selectionSpans != old.selectionSpans ||
      searchHighlights != old.searchHighlights ||
      currentSearchHighlight != old.currentSearchHighlight;
}

// =============================================================================
// 🔍 Simple Search Match (standalone, no PdfDocumentNode needed)
// =============================================================================

class _SimpleSearchMatch {
  final int pageIndex;
  final int startOffset;
  final int endOffset;
  final String snippet;

  const _SimpleSearchMatch({
    required this.pageIndex,
    required this.startOffset,
    required this.endOffset,
    required this.snippet,
  });
}

/// Simple page text data holder (text + geometry rects).
class _PageTextData {
  final String text;
  final List<PdfTextRect> rects;

  const _PageTextData({required this.text, required this.rects});
}
