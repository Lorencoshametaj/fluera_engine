import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/models/image_element.dart';

/// Background mode for image viewer.
enum _ViewerBackground { dark, light, checker }

/// 🖼️ Full-screen immersive image viewer with zoom-to-enter / pinch-to-exit.
///
/// Features:
/// - InteractiveViewer with pan/zoom (1×–5×), double-tap 1× ↔ 2.5×
/// - Pinch-to-exit / swipe-down-to-dismiss with vignette + pill + haptics
/// - Auto-hiding glassmorphic chrome, gradient bars
/// - Checkerboard background for transparent images
/// - Color picker on long-press
/// - Rule-of-thirds grid overlay toggle
/// - Background toggle (dark / light / checker)
/// - Spring entry animation
class ImageViewerScreen extends StatefulWidget {
  final ImageElement imageElement;
  final ui.Image image;
  final VoidCallback? onClose;
  final void Function(ImageElement)? onEdit;

  const ImageViewerScreen({
    super.key,
    required this.imageElement,
    required this.image,
    this.onClose,
    this.onEdit,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with TickerProviderStateMixin {
  late final TransformationController _zoomController;
  late final AnimationController _entryController;

  bool _zoomOutExitTriggered = false;
  double _currentZoomScale = 1.0;

  AnimationController? _zoomAnimController;
  Matrix4? _zoomAnimStart;
  Matrix4? _zoomAnimEnd;

  bool _showChrome = true;
  Timer? _chromeHideTimer;

  /// Swipe-down-to-dismiss state.
  double _swipeDismissOffset = 0;
  bool _isSwiping = false;
  AnimationController? _swipeSnapController;

  /// Background mode.
  _ViewerBackground _background = _ViewerBackground.dark;

  /// Rule-of-thirds grid overlay.
  bool _showGrid = false;

  /// Brightness adjustment (1.0 = normal, range 0.3-2.0).
  double _brightness = 1.0;
  bool _isBrightnessAdjusting = false;

  /// Histogram overlay.
  bool _showHistogram = false;
  List<int>? _histoR, _histoG, _histoB;

  /// Color picker state.
  Color? _pickedColor;
  Offset? _pickedPosition;
  Timer? _colorPickerHideTimer;
  ByteData? _cachedPixelData; // Cache pixel data for color picker

  /// File info (cached).
  String? _fileSizeStr;

  /// Cached fitted image dimensions (avoid recomputing every build).
  double _fitW = 0, _fitH = 0;
  late final CurvedAnimation _entryCurve;
  bool _entryDone = false;

  /// Cached painter instances (avoid GC churn).
  static final _checkerPainter = _CheckerPainter();
  static final _gridPainter = _GridPainter();

  /// View rotation (two-finger gesture).
  /// 🐛 FIX: ValueNotifier avoids setState during InteractiveViewer gesture,
  /// preventing intermittent zoom failures from mid-gesture rebuilds.
  final ValueNotifier<double> _viewRotation = ValueNotifier(0);
  double _rotationAtGestureStart = 0;
  bool _isInteracting = false;

  /// Share channel.
  static const _shareChannel = MethodChannel('fluera/share');

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _zoomController = TransformationController();
    _zoomController.addListener(_onZoomChanged);

    // Spring entry animation
    _entryController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _entryCurve = CurvedAnimation(
      parent: _entryController,
      curve: const Cubic(0.34, 1.56, 0.64, 1.0),
    );
    _entryController.addStatusListener((s) {
      if (s == AnimationStatus.completed) _entryDone = true;
    });

    _computeFileSize();
    _computeHistogram();
    _cachePixelData();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _computeFittedDimensions();
        _entryController.forward();
        _startChromeHideTimer();
      }
    });
  }

  @override
  void dispose() {
    _chromeHideTimer?.cancel();
    _colorPickerHideTimer?.cancel();
    _zoomAnimController?.dispose();
    _swipeSnapController?.dispose();
    _entryCurve.dispose();
    _entryController.dispose();
    _zoomController.dispose();
    _viewRotation.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _computeFileSize() {
    if (kIsWeb) return; // No file system on web
    try {
      final file = File(widget.imageElement.imagePath);
      if (file.existsSync()) {
        final bytes = file.lengthSync();
        if (bytes > 1024 * 1024) {
          _fileSizeStr = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
        } else {
          _fileSizeStr = '${(bytes / 1024).toStringAsFixed(0)} KB';
        }
      }
    } catch (_) {}
  }

  /// Compute real histogram from pixel data (sampled for performance).
  void _computeHistogram() {
    widget.image.toByteData(format: ui.ImageByteFormat.rawRgba).then((data) {
      if (data == null || !mounted) return;
      // Also cache for color picker
      _cachedPixelData = data;
      final r = List<int>.filled(256, 0);
      final g = List<int>.filled(256, 0);
      final b = List<int>.filled(256, 0);
      final totalPixels = widget.image.width * widget.image.height;
      final stride = math.max(1, totalPixels ~/ 10000) * 4;
      for (int offset = 0; offset + 3 < data.lengthInBytes; offset += stride) {
        r[data.getUint8(offset)]++;
        g[data.getUint8(offset + 1)]++;
        b[data.getUint8(offset + 2)]++;
      }
      if (mounted) {
        setState(() {
          _histoR = r;
          _histoG = g;
          _histoB = b;
        });
      }
    });
  }

  /// Pre-cache pixel data for color picker (avoids async on every long press).
  void _cachePixelData() {
    if (_cachedPixelData != null) return;
    widget.image.toByteData(format: ui.ImageByteFormat.rawRgba).then((data) {
      if (mounted) _cachedPixelData = data;
    });
  }

  /// Cache fitted image dimensions.
  void _computeFittedDimensions() {
    final screenSize = MediaQuery.sizeOf(context);
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();
    final imgAspect = imgW / imgH;
    final screenAspect = screenSize.width / screenSize.height;
    if (imgAspect > screenAspect) {
      _fitW = screenSize.width;
      _fitH = screenSize.width / imgAspect;
    } else {
      _fitH = screenSize.height;
      _fitW = screenSize.height * imgAspect;
    }
  }

  // ---------------------------------------------------------------------------
  // Chrome
  // ---------------------------------------------------------------------------

  void _startChromeHideTimer() {
    _chromeHideTimer?.cancel();
    if (!_showChrome) setState(() => _showChrome = true);
    _chromeHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _showChrome) setState(() => _showChrome = false);
    });
  }

  void _toggleChrome() {
    setState(() => _showChrome = !_showChrome);
    if (_showChrome) _startChromeHideTimer();
  }

  // ---------------------------------------------------------------------------
  // Zoom + Pinch-to-exit
  // ---------------------------------------------------------------------------

  void _onZoomChanged() {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    final changed = (_currentZoomScale - scale).abs() > 0.01;
    final prev = _currentZoomScale;
    _currentZoomScale = scale;

    // Smarter dirty check — only rebuild for meaningful UI changes
    final needsRebuild = changed && mounted && (
      // Exit hint visibility band
      (prev >= 0.95) != (scale >= 0.95) ||
      (prev >= 0.75) != (scale >= 0.75) ||
      // Zoom badge visibility (only update every 5%)
      (prev * 20).round() != (scale * 20).round() ||
      // Minimap visibility threshold
      (prev > 1.5) != (scale > 1.5)
    );
    if (needsRebuild) setState(() {});

    if (prev >= 0.70 && scale < 0.70 && !_zoomOutExitTriggered) {
      HapticFeedback.mediumImpact();
    }
    if (scale < 0.65 && !_zoomOutExitTriggered) {
      _zoomOutExitTriggered = true;
      HapticFeedback.heavyImpact();
      _dismissViewer();
    }
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    if (scale < 0.75 && !_zoomOutExitTriggered) {
      _zoomOutExitTriggered = true;
      HapticFeedback.heavyImpact();
      _dismissViewer();
      return;
    }
    if (scale < 0.95 && !_zoomOutExitTriggered) {
      _animateZoomTo(Matrix4.identity());
    }
    // 🔄 Rotation snap: snap to nearest 90° if within threshold
    _snapRotationIfNeeded();
  }

  /// Snap rotation to nearest 90° multiple with haptic feedback.
  void _snapRotationIfNeeded() {
    final current = _viewRotation.value;
    if (current.abs() < 0.001) return; // Already at 0

    const snapThreshold = 0.26; // ~15° in radians
    const pi2 = 3.14159265358979 * 2;
    const halfPi = 3.14159265358979 / 2;

    // Normalize to [0, 2π)
    final normalized = (current % pi2 + pi2) % pi2;

    // Find nearest 90° snap point
    final nearestQuarter = (normalized / halfPi).round() * halfPi;
    final diff = (normalized - nearestQuarter).abs();

    if (diff < snapThreshold) {
      // Snap to nearest 90°
      final target = nearestQuarter == pi2 ? 0.0 : nearestQuarter;
      // Account for full rotations
      final fullTurns = (current / pi2).floor() * pi2;
      final snapTarget = fullTurns + target;

      HapticFeedback.lightImpact();
      _animateRotationTo(snapTarget);
    }
  }

  /// Animate rotation to target angle.
  void _animateRotationTo(double target) {
    final startRotation = _viewRotation.value;
    final ctrl = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    final curved = CurvedAnimation(
      parent: ctrl,
      curve: Curves.easeOutCubic,
    );
    curved.addListener(() {
      if (mounted) {
        _viewRotation.value = startRotation + (target - startRotation) * curved.value;
      }
    });
    ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) ctrl.dispose();
    });
    ctrl.forward();
  }

  void _dismissViewer() {
    widget.onClose?.call();
    Navigator.of(context).pop();
  }

  /// Share the image via platform native share sheet.
  Future<void> _shareImage() async {
    final path = widget.imageElement.imagePath;
    try {
      HapticFeedback.lightImpact();
      await _shareChannel.invokeMethod('shareFile', {
        'path': path,
        'mimeType': 'image/*',
      });
    } catch (_) {
      // Fallback: copy path to clipboard
      await Clipboard.setData(ClipboardData(text: path));
      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Path copied to clipboard'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _onDoubleTapZoom(TapDownDetails details) {
    final currentScale = _zoomController.value.getMaxScaleOnAxis();
    HapticFeedback.lightImpact();

    // Cycle: 1× → 2× → 4× → 1×
    double targetScale;
    if (currentScale < 1.3) {
      targetScale = 2.0;
    } else if (currentScale < 2.5) {
      targetScale = 4.0;
    } else {
      targetScale = 1.0;
    }

    if (targetScale <= 1.0) {
      _animateZoomTo(Matrix4.identity());
    } else {
      final p = details.localPosition;
      final matrix = Matrix4.identity()
        ..[0] = targetScale
        ..[5] = targetScale
        ..[10] = 1.0
        ..[12] = (1 - targetScale) * p.dx
        ..[13] = (1 - targetScale) * p.dy;
      _animateZoomTo(matrix);
    }
  }

  void _animateZoomTo(Matrix4 target) {
    _zoomAnimController?.dispose();
    _zoomAnimStart = _zoomController.value.clone();
    _zoomAnimEnd = target;
    final ctrl = AnimationController(
      duration: const Duration(milliseconds: 250), vsync: this,
    );
    _zoomAnimController = ctrl;
    final curved = CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic);
    curved.addListener(() {
      if (_zoomAnimStart != null && _zoomAnimEnd != null) {
        final t = curved.value;
        final m = Matrix4.zero();
        for (int i = 0; i < 16; i++) {
          m.storage[i] = _zoomAnimStart!.storage[i] +
              (_zoomAnimEnd!.storage[i] - _zoomAnimStart!.storage[i]) * t;
        }
        _zoomController.value = m;
      }
    });
    ctrl.forward();
  }

  // ---------------------------------------------------------------------------
  // Swipe down to dismiss
  // ---------------------------------------------------------------------------

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_currentZoomScale > 1.05 || _isInteracting) return; // Don't swipe while zoomed or pinching
    setState(() {
      _isSwiping = true;
      _swipeDismissOffset += d.delta.dy;
    });
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (!_isSwiping) return;
    final velocity = d.velocity.pixelsPerSecond.dy;
    if (_swipeDismissOffset.abs() > 120 || velocity.abs() > 800) {
      HapticFeedback.mediumImpact();
      _dismissViewer();
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
        curve: const Cubic(0.34, 1.56, 0.64, 1.0), // spring overshoot
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

  // ---------------------------------------------------------------------------
  // Color picker (long press)
  // ---------------------------------------------------------------------------

  void _onLongPressImage(LongPressStartDetails details) {
    final data = _cachedPixelData;
    if (data == null) return; // Not yet loaded

    final screenSize = MediaQuery.sizeOf(context);
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();
    final fitW = _fitW > 0 ? _fitW : screenSize.width;
    final fitH = _fitH > 0 ? _fitH : screenSize.height;

    final imageOffsetX = (screenSize.width - fitW) / 2;
    final imageOffsetY = (screenSize.height - fitH) / 2;
    final localX = details.localPosition.dx - imageOffsetX;
    final localY = details.localPosition.dy - imageOffsetY;

    if (localX < 0 || localY < 0 || localX > fitW || localY > fitH) return;

    final pixelX = (localX / fitW * imgW).round().clamp(0, imgW.toInt() - 1);
    final pixelY = (localY / fitH * imgH).round().clamp(0, imgH.toInt() - 1);

    final offset = (pixelY * imgW.toInt() + pixelX) * 4;
    if (offset + 3 >= data.lengthInBytes) return;

    final r = data.getUint8(offset);
    final g = data.getUint8(offset + 1);
    final b = data.getUint8(offset + 2);
    final a = data.getUint8(offset + 3);

    HapticFeedback.mediumImpact();
    setState(() {
      _pickedColor = Color.fromARGB(a, r, g, b);
      _pickedPosition = details.localPosition;
    });

    _colorPickerHideTimer?.cancel();
    _colorPickerHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _pickedColor = null);
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    // Background color based on mode
    final bgColor = switch (_background) {
      _ViewerBackground.dark  => const Color(0xFF0A0A0F),
      _ViewerBackground.light => const Color(0xFFE8E8ED),
      _ViewerBackground.checker => const Color(0xFF1A1A20),
    };

    // Entry spring animation
    final entryAnim = CurvedAnimation(
      parent: _entryController,
      curve: const Cubic(0.34, 1.56, 0.64, 1.0), // spring overshoot
    );

    // Swipe dismiss progress (0 = no swipe, 1 = fully swiped)
    final swipeProgress = (_swipeDismissOffset.abs() / 300).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        color: bgColor,
        child: _entryDone
          // After entry animation completes, skip the AnimatedBuilder entirely
          ? _buildBody(safeTop, safeBottom, swipeProgress, 1.0, 1.0)
          : AnimatedBuilder(
              animation: _entryCurve,
              builder: (context, _) {
                final entryScale = 0.92 + 0.08 * _entryCurve.value;
                final entryOpacity = _entryCurve.value.clamp(0.0, 1.0);
                return _buildBody(safeTop, safeBottom, swipeProgress,
                    entryOpacity, entryScale);
              },
             ),
      ),
    );
  }

  Widget _buildBody(double safeTop, double safeBottom, double swipeProgress,
      double entryOpacity, double entryScale) {
    // Enhanced parallax: opacity fades more, scale shrinks, subtle rotation
    final dismissOpacity = (1.0 - swipeProgress * 0.6).clamp(0.0, 1.0);
    final dismissScale = (1.0 - swipeProgress * 0.15).clamp(0.7, 1.0);
    final dismissTilt = swipeProgress * 0.03 * (_swipeDismissOffset > 0 ? 1 : -1);

    return Opacity(
      opacity: entryOpacity * dismissOpacity,
      child: Transform.scale(
        scale: entryScale * dismissScale,
        child: Transform.rotate(
          angle: dismissTilt,
          child: Transform.translate(
            offset: Offset(0, _swipeDismissOffset),
            child: Stack(
            children: [
                    // ── Checkerboard background ──
                    if (_background == _ViewerBackground.checker)
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: Transform.translate(
                            offset: Offset(
                              _zoomController.value.storage[12] * -0.02,
                              _zoomController.value.storage[13] * -0.02,
                            ),
                            child: CustomPaint(painter: _checkerPainter),
                          ),
                        ),
                      ),

                    // ── Image ──
                    Positioned.fill(
                      child: Semantics(
                        label: 'Image viewer. Double tap to zoom. Pinch to exit.',
                        image: true,
                        child: GestureDetector(
                          onTapUp: (_) => _toggleChrome(),
                          onVerticalDragUpdate: _onVerticalDragUpdate,
                          onVerticalDragEnd: _onVerticalDragEnd,
                          onLongPressStart: _onLongPressImage,
                          behavior: HitTestBehavior.translucent,
                          child: ColorFiltered(
                            colorFilter: ColorFilter.matrix(<double>[
                              _brightness, 0, 0, 0, 0,
                              0, _brightness, 0, 0, 0,
                              0, 0, _brightness, 0, 0,
                              0, 0, 0, 1, 0,
                            ]),
                            child: ValueListenableBuilder<double>(
                              valueListenable: _viewRotation,
                              builder: (_, rotation, child) => Transform.rotate(
                                angle: rotation,
                                child: child,
                              ),
                              child: _buildImageView(),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ── Grid overlay ──
                    if (_showGrid)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(painter: _gridPainter),
                          ),
                        ),
                      ),

                    // ── Focus peaking overlay (edge detect at >2.5×) ──
                    if (_currentZoomScale > 2.5)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: ((_currentZoomScale - 2.5) / 1.0).clamp(0.0, 0.5),
                            duration: const Duration(milliseconds: 300),
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: _FocusPeakingPainter(image: widget.image),
                                size: Size.infinite,
                              ),
                            ),
                          ),
                        ),
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
                        left: 52, top: safeTop + 64,
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

                    // ── Zoom exit hint ──
                    if (_currentZoomScale < 0.95)
                      Positioned.fill(child: _buildZoomExitHint()),

                    // ── Swipe dismiss hint ──
                    if (_isSwiping && swipeProgress > 0.1)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: swipeProgress * 0.5),
                          ),
                        ),
                      ),

                    // ── Color picker popup ──
                    if (_pickedColor != null && _pickedPosition != null)
                      _buildColorPickerPopup(),

                    // ── Zoom badge ──
                    if ((_currentZoomScale - 1.0).abs() > 0.05 && _currentZoomScale >= 0.95)
                      Positioned(
                        top: safeTop + 64,
                        right: 16,
                        child: _buildZoomBadge(),
                      ),

                    // ── Rotation badge ──
                    Positioned(
                      top: safeTop + 64,
                      left: 16,
                      child: ValueListenableBuilder<double>(
                        valueListenable: _viewRotation,
                        builder: (_, rotation, __) {
                          if (rotation.abs() <= 0.01) return const SizedBox.shrink();
                          return _buildRotationBadge();
                        },
                      ),
                    ),

                    // ── Top bar ──
                    Positioned(
                      top: 0, left: 0, right: 0,
                      child: IgnorePointer(
                        ignoring: !_showChrome,
                        child: AnimatedOpacity(
                          opacity: _showChrome ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: _buildTopBar(safeTop),
                        ),
                      ),
                    ),

                    // ── Minimap navigator (when zoomed in) ──
                    Positioned(
                      bottom: safeBottom + 70,
                      right: 16,
                      child: AnimatedOpacity(
                        opacity: _currentZoomScale > 1.5 ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        child: AnimatedScale(
                          scale: _currentZoomScale > 1.5 ? 1.0 : 0.8,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          child: IgnorePointer(
                            ignoring: _currentZoomScale <= 1.5,
                            child: _buildMinimap(),
                          ),
                        ),
                      ),
                    ),

                    // ── Histogram overlay ──
                    if (_showHistogram)
                      Positioned(
                        bottom: safeBottom + 70,
                        left: 16,
                        child: _buildHistogram(),
                      ),

                    // ── Bottom bar ──
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: IgnorePointer(
                        ignoring: !_showChrome,
                        child: AnimatedOpacity(
                          opacity: _showChrome ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: _buildBottomBar(safeBottom),
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

  // ---------------------------------------------------------------------------
  // Rotation badge
  // ---------------------------------------------------------------------------

  Widget _buildRotationBadge() {
    final degrees = (_viewRotation.value * 180 / math.pi) % 360;
    final displayDeg = degrees > 180 ? degrees - 360 : degrees;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _viewRotation.value = 0;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.rotate_right_rounded,
                color: Colors.white.withValues(alpha: 0.7), size: 14),
            const SizedBox(width: 4),
            Text(
              '${displayDeg.toStringAsFixed(1)}°',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Image view
  // ---------------------------------------------------------------------------

  Widget _buildImageView() {
    final screenSize = MediaQuery.sizeOf(context);

    // Use cached fitted dimensions (computed once in initState)
    final fitW = _fitW > 0 ? _fitW : screenSize.width;
    final fitH = _fitH > 0 ? _fitH : screenSize.height;

    return GestureDetector(
      onDoubleTapDown: _onDoubleTapZoom,
      onDoubleTap: () {},
      behavior: HitTestBehavior.translucent,
      child: InteractiveViewer(
        transformationController: _zoomController,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: 0.3,
        maxScale: 5.0,
        onInteractionStart: (details) {
          _isInteracting = true;
          if (details.pointerCount >= 2) {
            _rotationAtGestureStart = _viewRotation.value;
          }
        },
        onInteractionUpdate: (details) {
          // Two-finger rotation
          if (details.pointerCount >= 2 && details.rotation.abs() > 0.01) {
            _viewRotation.value = _rotationAtGestureStart + details.rotation;
          }
        },
        onInteractionEnd: (details) {
          _isInteracting = false;
          _onInteractionEnd(details);
        },
        child: SizedBox(
          width: screenSize.width,
          height: screenSize.height,
          child: Center(
            child: RepaintBoundary(
              child: Container(
                width: fitW,
                height: fitH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: _background == _ViewerBackground.dark
                      ? const [
                          BoxShadow(
                            color: Color(0x80000000),
                            blurRadius: 40,
                            spreadRadius: 4,
                            offset: Offset(0, 12),
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CustomPaint(
                    painter: _ImagePainter(image: widget.image),
                    size: Size(fitW, fitH),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Zoom badge
  // ---------------------------------------------------------------------------

  Widget _buildZoomBadge() {
    // Show snap level name
    String zoomLabel;
    if ((_currentZoomScale - 2.0).abs() < 0.2) {
      zoomLabel = '2×';
    } else if ((_currentZoomScale - 4.0).abs() < 0.3) {
      zoomLabel = '4×';
    } else {
      zoomLabel = '${(_currentZoomScale * 100).round()}%';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.7), size: 14),
          const SizedBox(width: 4),
          Text(
            zoomLabel,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Zoom exit hint
  // ---------------------------------------------------------------------------

  Widget _buildZoomExitHint() {
    final progress = ((0.95 - _currentZoomScale) / 0.30).clamp(0.0, 1.0);
    if (progress <= 0) return const SizedBox.shrink();
    final exitReady = _currentZoomScale < 0.75;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: progress,
        duration: const Duration(milliseconds: 100),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6 * progress),
                    ],
                    radius: 1.2 - (0.3 * progress),
                  ),
                ),
              ),
            ),
            if (progress > 0.15)
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: exitReady ? 28 : 20,
                    vertical: exitReady ? 14 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: exitReady
                        ? const Color(0xFF6C63FF).withValues(alpha: 0.9)
                        : Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(exitReady ? 28 : 24),
                    boxShadow: exitReady
                        ? [BoxShadow(
                            color: const Color(0xFF6C63FF).withValues(alpha: 0.5),
                            blurRadius: 20, spreadRadius: 2,
                          )]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        exitReady ? Icons.check_circle_rounded : Icons.zoom_out_map_rounded,
                        color: Colors.white.withValues(alpha: 0.95),
                        size: exitReady ? 20 : 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        exitReady ? 'Release to go back' : 'Pinch to exit',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: exitReady ? 15 : 14,
                          fontWeight: exitReady ? FontWeight.w600 : FontWeight.w500,
                          letterSpacing: 0.3,
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

  // ---------------------------------------------------------------------------
  // Color picker popup
  // ---------------------------------------------------------------------------

  Widget _buildColorPickerPopup() {
    final c = _pickedColor!;
    final pos = _pickedPosition!;
    final hexR = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final hexG = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final hexB = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    final hex = '#$hexR$hexG$hexB';
    final ri = (c.r * 255).round();
    final gi = (c.g * 255).round();
    final bi = (c.b * 255).round();

    // Position popup above or below the touch point
    final screenH = MediaQuery.sizeOf(context).height;
    final showAbove = pos.dy > screenH / 2;

    return Positioned(
      left: (pos.dx - 70).clamp(16.0, MediaQuery.sizeOf(context).width - 156),
      top: showAbove ? pos.dy - 100 : pos.dy + 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xEE1A1A24),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: const [
              BoxShadow(color: Color(0x60000000), blurRadius: 20),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Color swatch
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
                ),
              ),
              const SizedBox(width: 12),
              // Color info
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: hex.toUpperCase()));
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied $hex'),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hex.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.copy_rounded,
                          color: Colors.white.withValues(alpha: 0.4), size: 13),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'RGB($ri, $gi, $bi)',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top bar
  // ---------------------------------------------------------------------------

  Widget _buildTopBar(double safeTop) {
    final fileName = widget.imageElement.imagePath.split('/').last;
    final displayName = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;

    return Container(
      padding: EdgeInsets.only(top: safeTop + 4, left: 4, right: 4, bottom: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xDD0A0A0F), Color(0x990A0A0F), Colors.transparent],
          stops: [0.0, 0.7, 1.0],
        ),
      ),
      child: Row(
        children: [
          _glassButton(Icons.arrow_back_rounded, onTap: _dismissViewer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(displayName,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w600, letterSpacing: 0.2,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.image.width}×${widget.image.height}'
                  '${_fileSizeStr != null ? '  •  $_fileSizeStr' : ''}'
                  '  •  ${widget.imageElement.imagePath.split('.').last.toUpperCase()}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45), fontSize: 12,
                    fontWeight: FontWeight.w500, letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          // Grid toggle
          _glassButton(
            _showGrid ? Icons.grid_on_rounded : Icons.grid_off_rounded,
            onTap: () => setState(() => _showGrid = !_showGrid),
            active: _showGrid,
            tooltip: 'Grid',
          ),
          const SizedBox(width: 8),
          // Histogram toggle
          _glassButton(
            Icons.bar_chart_rounded,
            onTap: () => setState(() => _showHistogram = !_showHistogram),
            active: _showHistogram,
            tooltip: 'Histogram',
          ),
          const SizedBox(width: 8),
          // Background toggle
          _glassButton(
            _bgIcon,
            onTap: _cycleBackground,
            tooltip: 'Background',
          ),
          const SizedBox(width: 8),
          // Edit
          _glassButton(Icons.tune_rounded,
            onTap: () => widget.onEdit?.call(widget.imageElement),
            tooltip: 'Edit',
          ),
          const SizedBox(width: 8),
          // Share
          _glassButton(Icons.ios_share_rounded,
            onTap: _shareImage,
            tooltip: 'Share',
          ),
        ],
      ),
    );
  }

  IconData get _bgIcon => switch (_background) {
    _ViewerBackground.dark  => Icons.dark_mode_rounded,
    _ViewerBackground.light => Icons.light_mode_rounded,
    _ViewerBackground.checker => Icons.check_box_outline_blank_rounded,
  };

  void _cycleBackground() {
    setState(() {
      _background = switch (_background) {
        _ViewerBackground.dark  => _ViewerBackground.light,
        _ViewerBackground.light => _ViewerBackground.checker,
        _ViewerBackground.checker => _ViewerBackground.dark,
      };
    });
    HapticFeedback.selectionClick();
  }

  Widget _glassButton(IconData icon, {
    VoidCallback? onTap, String? tooltip, bool active = false,
  }) {
    final btn = GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF6C63FF).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? const Color(0xFF6C63FF).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 20),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip, child: btn);
    return btn;
  }

  // ---------------------------------------------------------------------------
  // Bottom bar
  // ---------------------------------------------------------------------------

  Widget _buildBottomBar(double safeBottom) {
    final w = widget.image.width;
    final h = widget.image.height;
    final mp = (w * h / 1000000).toStringAsFixed(1);
    final aspect = _formatAspectRatio(w, h);

    return Container(
      padding: EdgeInsets.only(top: 16, bottom: safeBottom + 12, left: 20, right: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            _background == _ViewerBackground.light
                ? const Color(0xDDE8E8ED)
                : const Color(0xDD0A0A0F),
            Colors.transparent,
          ],
          stops: const [0.0, 1.0],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _infoPill(Icons.aspect_ratio_rounded, aspect),
          const SizedBox(width: 10),
          _infoPill(Icons.camera_rounded, '$mp MP'),
          if (_fileSizeStr != null) ...[
            const SizedBox(width: 10),
            _infoPill(Icons.sd_storage_rounded, _fileSizeStr!),
          ],
        ],
      ),
    );
  }

  String _formatAspectRatio(int w, int h) {
    final g = _gcd(w, h);
    final rw = w ~/ g;
    final rh = h ~/ g;
    if (rw > 30 || rh > 30) {
      final r = w / h;
      if ((r - 16 / 9).abs() < 0.05) return '16:9';
      if ((r - 4 / 3).abs() < 0.05) return '4:3';
      if ((r - 3 / 2).abs() < 0.05) return '3:2';
      if ((r - 1.0).abs() < 0.05) return '1:1';
      if ((r - 9 / 16).abs() < 0.05) return '9:16';
      return '${r.toStringAsFixed(1)}:1';
    }
    return '$rw:$rh';
  }

  int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  Widget _infoPill(IconData icon, String label) {
    final isDark = _background != _ViewerBackground.light;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
            color: isDark
                ? Colors.white.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.4),
            size: 13,
          ),
          const SizedBox(width: 6),
          Text(label,
            style: TextStyle(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.55)
                  : Colors.black.withValues(alpha: 0.55),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Minimap navigator
  // ---------------------------------------------------------------------------

  Widget _buildMinimap() {
    const mapW = 100.0;
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();
    final mapH = mapW * (imgH / imgW);

    final matrix = _zoomController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final screenSize = MediaQuery.sizeOf(context);
    final tx = matrix.storage[12];
    final ty = matrix.storage[13];

    final viewLeft = -tx / scale;
    final viewTop = -ty / scale;
    final viewW = screenSize.width / scale;
    final viewH = screenSize.height / scale;

    final normLeft = (viewLeft / screenSize.width).clamp(0.0, 1.0);
    final normTop = (viewTop / screenSize.height).clamp(0.0, 1.0);
    final normW = (viewW / screenSize.width).clamp(0.0, 1.0);
    final normH = (viewH / screenSize.height).clamp(0.0, 1.0);

    return GestureDetector(
      onPanUpdate: (d) {
        // Drag minimap to navigate
        final dx = d.delta.dx / mapW * screenSize.width * scale;
        final dy = d.delta.dy / mapH * screenSize.height * scale;
        final m = _zoomController.value.clone();
        m.storage[12] -= dx;
        m.storage[13] -= dy;
        _zoomController.value = m;
      },
      child: Container(
        width: mapW,
        height: mapH,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.black.withValues(alpha: 0.6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 12)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              CustomPaint(
                painter: _ImagePainter(image: widget.image),
                size: Size(mapW, mapH),
              ),
              Positioned.fill(
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.3)),
              ),
              Positioned(
                left: normLeft * mapW,
                top: normTop * mapH,
                child: Container(
                  width: (normW * mapW).clamp(8.0, mapW),
                  height: (normH * mapH).clamp(8.0, mapH),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.8),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(2),
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
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
  // Histogram (real pixel data)
  // ---------------------------------------------------------------------------

  Widget _buildHistogram() {
    return Container(
      width: 140,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withValues(alpha: 0.65),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 12)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: (_histoR != null)
              ? CustomPaint(
                  painter: _RealHistogramPainter(
                    rBins: _histoR!, gBins: _histoG!, bBins: _histoB!,
                  ),
                  size: const Size(124, 64),
                )
              : Center(
                  child: SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

// =============================================================================
// Painters
// =============================================================================

/// Draws the image fitted to the given size.
class _ImagePainter extends CustomPainter {
  final ui.Image image;
  _ImagePainter({required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, src, dst, Paint()..filterQuality = FilterQuality.high);
  }

  @override
  bool shouldRepaint(_ImagePainter old) => !identical(old.image, image);
}

/// Checkerboard pattern for transparent images.
class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cellSize = 12.0;
    final paintA = Paint()..color = const Color(0xFF2A2A30);
    final paintB = Paint()..color = const Color(0xFF222228);
    final cols = (size.width / cellSize).ceil();
    final rows = (size.height / cellSize).ceil();
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        canvas.drawRect(
          Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize),
          (r + c).isEven ? paintA : paintB,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => false;
}

/// Rule-of-thirds grid overlay.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Vertical thirds
    for (int i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Horizontal thirds
    for (int i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Center cross (subtle)
    final centerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final crossLen = math.min(size.width, size.height) * 0.03;
    canvas.drawLine(Offset(cx - crossLen, cy), Offset(cx + crossLen, cy), centerPaint);
    canvas.drawLine(Offset(cx, cy - crossLen), Offset(cx, cy + crossLen), centerPaint);
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

/// RGB histogram painter using real pre-computed bin data.
class _RealHistogramPainter extends CustomPainter {
  final List<int> rBins, gBins, bBins;
  _RealHistogramPainter({required this.rBins, required this.gBins, required this.bBins});

  @override
  void paint(Canvas canvas, Size size) {
    // Downsample 256 bins → 64 for display
    final r64 = _downsample(rBins, 64);
    final g64 = _downsample(gBins, 64);
    final b64 = _downsample(bBins, 64);

    final maxVal = [...r64, ...g64, ...b64].reduce(math.max).toDouble();
    if (maxVal <= 0) return;

    _drawChannel(canvas, size, r64, maxVal, Colors.red.withValues(alpha: 0.4));
    _drawChannel(canvas, size, g64, maxVal, Colors.green.withValues(alpha: 0.35));
    _drawChannel(canvas, size, b64, maxVal, Colors.blue.withValues(alpha: 0.4));

    // Luminance outline
    final lum = List.generate(64, (i) =>
        (0.299 * r64[i] + 0.587 * g64[i] + 0.114 * b64[i]).round());
    final lumMax = lum.reduce(math.max).toDouble();
    if (lumMax > 0) {
      final path = Path();
      for (int i = 0; i < 64; i++) {
        final x = i / 63 * size.width;
        final y = size.height * (1.0 - lum[i] / lumMax);
        if (i == 0) path.moveTo(x, y);
        else path.lineTo(x, y);
      }
      canvas.drawPath(path, Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0);
    }
  }

  List<int> _downsample(List<int> bins, int target) {
    final result = List<int>.filled(target, 0);
    final ratio = bins.length / target;
    for (int i = 0; i < target; i++) {
      final start = (i * ratio).floor();
      final end = ((i + 1) * ratio).floor().clamp(start + 1, bins.length);
      int sum = 0;
      for (int j = start; j < end; j++) sum += bins[j];
      result[i] = sum;
    }
    return result;
  }

  void _drawChannel(Canvas canvas, Size size, List<int> bins,
      double maxVal, Color color) {
    final path = Path();
    path.moveTo(0, size.height);
    for (int i = 0; i < bins.length; i++) {
      final x = i / (bins.length - 1) * size.width;
      final y = size.height * (1.0 - bins[i] / maxVal);
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_RealHistogramPainter old) =>
      !identical(old.rBins, rBins);
}

/// Focus peaking painter — highlights sharp edges with colored dots.
/// Uses a simplified gradient magnitude approach for performance.
class _FocusPeakingPainter extends CustomPainter {
  final ui.Image image;
  ByteData? _pixelData;
  bool _loaded = false;

  _FocusPeakingPainter({required this.image}) {
    _loadPixels();
  }

  void _loadPixels() {
    image.toByteData(format: ui.ImageByteFormat.rawRgba).then((data) {
      _pixelData = data;
      _loaded = true;
    });
  }

  double _luminance(int offset, ByteData data) {
    return data.getUint8(offset) * 0.299 +
           data.getUint8(offset + 1) * 0.587 +
           data.getUint8(offset + 2) * 0.114;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!_loaded || _pixelData == null) return;
    final data = _pixelData!;
    final imgW = image.width;
    final imgH = image.height;

    // Sample grid (skip pixels for perf: every 4th pixel)
    const step = 4;
    const threshold = 40.0; // Gradient magnitude threshold

    final paint = Paint()
      ..color = const Color(0xAAFF1744) // Red with transparency
      ..strokeWidth = 1.5
      ..style = PaintingStyle.fill;

    final scaleX = size.width / imgW;
    final scaleY = size.height / imgH;

    for (int y = 1; y < imgH - 1; y += step) {
      for (int x = 1; x < imgW - 1; x += step) {
        final center = (y * imgW + x) * 4;
        final right = (y * imgW + x + 1) * 4;
        final below = ((y + 1) * imgW + x) * 4;

        if (center + 3 >= data.lengthInBytes ||
            right + 3 >= data.lengthInBytes ||
            below + 3 >= data.lengthInBytes) continue;

        final gx = (_luminance(right, data) - _luminance(center, data)).abs();
        final gy = (_luminance(below, data) - _luminance(center, data)).abs();
        final mag = gx + gy;

        if (mag > threshold) {
          canvas.drawCircle(
            Offset(x * scaleX, y * scaleY),
            1.2,
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_FocusPeakingPainter old) => !identical(old.image, image);
}
