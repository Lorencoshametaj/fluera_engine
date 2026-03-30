import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../fluera_canvas_config.dart';
import '../../core/models/pdf_document_model.dart';
import '../../core/models/pdf_page_model.dart';
import '../../core/models/pdf_text_rect.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../drawing/brushes/brush_engine.dart';
import '../../drawing/models/pro_brush_settings.dart';
import '../../drawing/models/pro_brush_settings_dialog.dart';
import '../../core/models/shape_type.dart';
import 'package:fluera_engine/src/rendering/gpu/vulkan_stroke_overlay_service.dart';
import '../overlays/pdf_radial_menu.dart';
import '../overlays/floating_color_disc.dart';
import '../../tools/pdf/pdf_text_extractor.dart';
import '../../tools/pdf/pdf_search_controller.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/engine_scope.dart';

// Part files — domain-specific logic extracted from the original monolith.
part '_models.dart';
part '_drawing.dart';
part '_zoom.dart';
part '_rendering.dart';
part '_search.dart';
part '_text_selection.dart';
part '_bookmarks.dart';
part '_bookmarks_panel.dart';
part '_brush_panel.dart';
part '_export.dart';
part '_radial_menu_handler.dart';
part '_painters.dart';
part '_text_sheet.dart';
part '_ui_chrome.dart';

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

  // ─── Zoom / Navigation ───
  late final TransformationController _zoomController;
  late final List<ui.Image?> _pageImages;
  int _currentPageIndex = 0;
  bool _isAnimatingIn = true;
  bool _zoomOutExitTriggered = false;
  double _currentZoomScale = 1.0;
  bool _isInteracting = false;
  Timer? _hiResDebounce;
  Timer? _zoomIndicatorTimer;
  double _zoomIndicatorOpacity = 0.0;
  int _lastSnapLevel = 1;
  AnimationController? _zoomAnimController;
  Matrix4? _zoomAnimStart;
  Matrix4? _zoomAnimEnd;

  // ─── Swipe-dismiss ───
  double _swipeDismissOffset = 0;
  bool _isSwiping = false;
  AnimationController? _swipeSnapController;

  // ─── UI chrome ───
  bool _showSidebar = false;
  bool _showChrome = false;
  Timer? _chromeHideTimer;
  _ReadingMode _readingMode = _ReadingMode.light;
  double _brightness = 1.0;
  bool _isBrightnessAdjusting = false;
  String? _pdfFileSizeStr;

  // ─── Radial menu ───
  bool _showPdfRadialMenu = false;
  Offset _pdfRadialMenuCenter = Offset.zero;
  final _pdfRadialMenuKey = GlobalKey<PdfRadialMenuState>();
  bool _usePdfRadialWheel = true;

  // ─── Bookmarks ───
  final Map<int, _BookmarkData> _bookmarkedPages = {};
  static const _bookmarkColors = [
    Color(0xFFEF5350), Color(0xFF42A5F5), Color(0xFF66BB6A),
    Color(0xFFFFCA28), Color(0xFFAB47BC), Color(0xFFFF7043),
  ];
  Color _activeBookmarkColor = const Color(0xFFEF5350);

  // ─── Export ───
  double _exportScale = 2.0;

  // ─── Rendering cache ───
  final Map<int, double> _pageRenderScale = {};
  List<double>? _cumulativePageTops;
  double? _cachedTotalHeight;
  double? _cumulativeCacheWidth;
  int _lastVisibleCheckPage = -1;

  // ─── Drawing state ───
  bool _isDrawingMode = false;
  bool _isErasing = false;
  Color _penColor = const Color(0xFF1A1A2E);
  double _penWidth = 2.5;
  double _penOpacity = 1.0;
  ProPenType _penType = ProPenType.ballpoint;
  ProBrushSettings _brushSettings = const ProBrushSettings();
  ShapeType _selectedShapeType = ShapeType.freehand;
  Offset? _shapeStartPos;
  Offset? _shapeEndPos;
  int? _shapePageIndex;
  List<ProDrawingPoint>? _livePoints;
  int? _livePageIndex;
  final List<ProDrawingPoint> _liveScreenPoints = [];
  int? _activePointerId;
  double _safeAreaTopCache = 0;
  int _activePointerCount = 0;
  final Map<int, List<ProStroke>> _pageStrokes = {};
  final ValueNotifier<int> _annotationRepaint = ValueNotifier<int>(0);
  bool _showBrushPanel = false;
  static const _colorPresets = [
    Color(0xFF1A1A2E), Color(0xFFE74C3C), Color(0xFF2ECC71),
    Color(0xFF3498DB), Color(0xFFF39C12), Color(0xFF9B59B6), Color(0xFF1ABC9C),
  ];
  static const _highlightColors = [
    Color(0xFFFFEB3B), Color(0xFF76FF03), Color(0xFFFF4081),
    Color(0xFF00E5FF), Color(0xFFFF9100), Color(0xFFE040FB),
  ];
  Color? _savedPenColor;
  double? _savedPenWidth;

  // ─── Text selection ───
  bool _isTextSelectMode = false;
  final Map<int, List<PdfTextRect>> _pageTextRects = {};
  List<PdfTextRect> _selSpans = const [];
  int _selStartIdx = -1;
  int _selEndIdx = -1;
  int _selPageIdx = -1;
  int _selAnchor = -1;
  bool _isExtractingText = false;
  final ValueNotifier<int> _textOverlayRepaint = ValueNotifier<int>(0);

  // ─── Search ───
  final PdfSearchController _searchController = PdfSearchController();
  bool _showSearchBar = false;
  final TextEditingController _searchTextCtrl = TextEditingController();
  bool _searchDocRegistered = false;
  int _ocrProgress = 0;
  int _ocrTotal = 0;
  bool _ocrRunning = false;
  bool _ocrCancelled = false;
  Timer? _searchDebounce;
  List<_SimpleSearchMatch> _searchMatches = const [];
  int _searchCurrentIdx = -1;
  List<_PageTextData>? _providerPageTexts;

  // ─── Vulkan GPU overlay ───
  final VulkanStrokeOverlayService _vulkanOverlay = VulkanStrokeOverlayService();
  int? _vulkanTextureId;
  bool _vulkanActive = false;

  // ─── Lifecycle ───

  @override
  void initState() {
    super.initState();
    _zoomController = TransformationController();
    _zoomController.addListener(_onZoomChanged);
    _pageImages = List<ui.Image?>.filled(widget.documentModel.totalPages, null);
    _loadAnnotationsFromModel();
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
      final totalPages = widget.documentModel.totalPages;
      _pdfFileSizeStr = '$totalPages ${totalPages == 1 ? 'page' : 'pages'}';
    } catch (_) {}
  }

  void _startChromeHideTimer() {
    _chromeHideTimer?.cancel();
    if (!_showChrome) setState(() => _showChrome = true);
    _chromeHideTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (_showChrome) setState(() => _showChrome = false);
    });
  }

  void _toggleChrome() {
    setState(() => _showChrome = !_showChrome);
    if (_showChrome) _startChromeHideTimer();
  }

  void _initVulkanIfNeeded() {
    if (_vulkanActive || _vulkanTextureId != null) return;
    _vulkanOverlay.isAvailable.then((available) {
      if (!available || !mounted) return;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final size = MediaQuery.of(context).size;
      final padding = MediaQuery.of(context).padding;
      final safeHeight = size.height - padding.top - padding.bottom;
      final pw = (size.width * dpr).toInt();
      final ph = (safeHeight * dpr).toInt();
      _vulkanOverlay.init(pw, ph).then((id) {
        if (id != null && mounted) {
          _vulkanOverlay.setScreenSpaceTransform(pw, ph, dpr);
          setState(() { _vulkanTextureId = id; _vulkanActive = true; });
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
    for (final img in _pageImages) { img?.dispose(); }
    super.dispose();
  }

  void _loadAnnotationsFromModel() {
    // Load serialized ink annotations from the document model (stub)
  }

  PdfDocumentModel _buildUpdatedModel() {
    final updatedPages = <PdfPageModel>[];
    for (int i = 0; i < widget.documentModel.totalPages; i++) {
      final page = widget.documentModel.pages[i];
      final strokes = _pageStrokes[i] ?? [];
      updatedPages.add(page.copyWith(
        annotations: strokes.map((s) => s.id).toList(),
        lastModifiedAt: DateTime.now().microsecondsSinceEpoch,
      ));
    }
    return widget.documentModel.copyWith(pages: updatedPages);
  }

  Rect? _computeVisibleRect(int pageIndex, Size displaySize, Size originalSize) {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    if (scale <= 1.05) return null;
    final screenSize = MediaQuery.of(context).size;
    final xOffset = -_zoomController.value.row0.w;
    final yOffset = -_zoomController.value.row1.w;
    double pageTop = 0;
    for (int i = 0; i < pageIndex; i++) { pageTop += _getPageDisplayHeight(i); }
    final viewLeft = xOffset / scale;
    final viewTop = yOffset / scale;
    final viewWidth = screenSize.width / scale;
    final viewHeight = screenSize.height / scale;
    final sx = originalSize.width / displaySize.width;
    final sy = originalSize.height / displaySize.height;
    return Rect.fromLTWH((viewLeft) * sx - 50, (viewTop - pageTop) * sy - 50, viewWidth * sx + 100, viewHeight * sy + 100);
  }

  void _onScroll() {
    final yOffset = -_zoomController.value.row1.w;
    final scale = _zoomController.value.getMaxScaleOnAxis();
    final effectiveOffset = yOffset / scale;
    double accumulated = 0;
    for (int i = 0; i < widget.documentModel.totalPages; i++) {
      final pageHeight = _getPageDisplayHeight(i);
      final pageBottom = accumulated + pageHeight;
      final viewportMid = effectiveOffset + MediaQuery.of(context).size.height / 2;
      if (accumulated <= viewportMid && pageBottom > effectiveOffset) {
        if (_currentPageIndex != i) setState(() => _currentPageIndex = i);
        break;
      }
      accumulated += pageHeight + 16.0;
    }
    _ensureVisiblePagesRendered();
  }

  void _scrollToPage(int pageIndex) {
    double offset = 16;
    for (int i = 0; i < pageIndex; i++) { offset += _getPageDisplayHeight(i) + 16.0; }
    // ignore: deprecated_member_use
    final target = Matrix4.identity()..translate(0.0, -offset);
    _animateZoomTo(target);
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final totalPages = widget.documentModel.totalPages;
    return Theme(
      data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(surface: Color(0xFF1A1A2E), primary: Color(0xFF6C63FF), onSurface: Colors.white)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut, color: const Color(0xFF1A1A2E),
          child: SafeArea(child: Builder(builder: (context) {
            final swipeProgress = (_swipeDismissOffset.abs() / 300).clamp(0.0, 1.0);
            final dismissOpacity = (1.0 - swipeProgress * 0.6).clamp(0.0, 1.0);
            final dismissScale = (1.0 - swipeProgress * 0.15).clamp(0.7, 1.0);
            final dismissTilt = swipeProgress * 0.03 * (_swipeDismissOffset > 0 ? 1 : -1);
            return AnimatedOpacity(duration: const Duration(milliseconds: 300), opacity: _isAnimatingIn ? 0.0 : 1.0,
              child: Opacity(opacity: dismissOpacity, child: Transform.scale(scale: dismissScale,
                child: Transform.rotate(angle: dismissTilt, child: Transform.translate(offset: Offset(0, _swipeDismissOffset),
                  child: Stack(children: [
                    Column(children: [Expanded(child: GestureDetector(onTap: _toggleChrome, behavior: HitTestBehavior.translucent,
                      child: Stack(children: [
                        Row(children: [
                          if (_showSidebar) _buildThumbnailSidebar(),
                          Expanded(child: ColorFiltered(
                            colorFilter: ColorFilter.matrix(<double>[_brightness, 0, 0, 0, 0, 0, _brightness, 0, 0, 0, 0, 0, _brightness, 0, 0, 0, 0, 0, 1, 0]),
                            child: _buildPageList())),
                        ]),
                        if (_vulkanTextureId != null && _isDrawingMode) Positioned.fill(child: IgnorePointer(child: Texture(textureId: _vulkanTextureId!))),
                        if (_currentZoomScale < 0.95 && !_isDrawingMode) _buildZoomExitHint(),
                        if ((_currentZoomScale - 1.0).abs() > 0.05 && !_isDrawingMode)
                          Positioned(top: 12, right: 12, child: IgnorePointer(child: AnimatedOpacity(duration: const Duration(milliseconds: 300), opacity: _zoomIndicatorOpacity,
                            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: const Color(0xAA000000), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x20FFFFFF), width: 0.5)),
                              child: Text('${(_currentZoomScale * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)))))),
                        if (_showSearchBar) _buildSearchBar(),
                      ])))]),
                    // Brightness drag zone
                    Positioned(left: 0, top: 0, bottom: 0, width: 44, child: GestureDetector(behavior: HitTestBehavior.translucent,
                      onVerticalDragStart: (_) { setState(() => _isBrightnessAdjusting = true); HapticFeedback.selectionClick(); },
                      onVerticalDragUpdate: (d) { setState(() { _brightness = (_brightness - d.delta.dy * 0.005).clamp(0.3, 2.0); }); },
                      onVerticalDragEnd: (_) { setState(() => _isBrightnessAdjusting = false); },
                      child: Container(color: Colors.transparent))),
                    if (_isBrightnessAdjusting || (_brightness - 1.0).abs() > 0.05)
                      Positioned(left: 52, top: 80, child: AnimatedOpacity(opacity: _isBrightnessAdjusting ? 1.0 : 0.6, duration: const Duration(milliseconds: 200),
                        child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withValues(alpha: 0.15))),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.brightness_6_rounded, size: 14, color: Colors.white.withValues(alpha: 0.7)), const SizedBox(width: 6),
                            Text('${(_brightness * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))])))),
                    if (_isSwiping && swipeProgress > 0.1) Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: swipeProgress * 0.5)))),
                    if (_showChrome) Positioned(top: 12, left: 68, right: 12, child: IgnorePointer(child: AnimatedOpacity(duration: const Duration(milliseconds: 200), opacity: _showChrome ? 1.0 : 0.0, child: _buildFloatingTitle(totalPages)))),
                    Positioned(top: 8, left: 8, child: _buildBackButton()),
                    if (_isDrawingMode && !_showPdfRadialMenu) FloatingColorDisc(
                      color: _penColor, recentColors: _colorPresets.toList(), strokeSize: _penWidth,
                      onColorChanged: (c) => setState(() => _penColor = c),
                      onStrokeSizeChanged: (s) => setState(() => _penWidth = s.clamp(0.5, 8.0)),
                      onExpand: () async { setState(() => _showBrushPanel = !_showBrushPanel); }),
                    if (_isDrawingMode && _showBrushPanel && !_showPdfRadialMenu) Positioned(bottom: 68, left: 0, right: 0, child: _buildBrushPanel()),
                    if (_showPdfRadialMenu) Positioned.fill(child: PdfRadialMenu(
                      key: _pdfRadialMenuKey, center: _pdfRadialMenuCenter, screenSize: MediaQuery.of(context).size,
                      isDrawingMode: _isDrawingMode, isCurrentPageBookmarked: _bookmarkedPages.containsKey(_currentPageIndex),
                      bookmarkCount: _bookmarkedPages.length, currentPenType: _penType, currentColor: _penColor,
                      colorPresets: _colorPresets.toList(), highlightColors: _highlightColors.toList(),
                      onResult: (result) { setState(() => _showPdfRadialMenu = false); _handlePdfRadialResult(result); })),
                  ]))))));
          })),
        ),
      ),
    );
  }
}
