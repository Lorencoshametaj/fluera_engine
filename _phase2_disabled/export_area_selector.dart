import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/export_preset.dart';
import '../services/canvas_export_service.dart';

/// 🎯 EXPORT AREA SELECTOR
///
/// Widget overlay per selezionare visivamente l'area da esportare.
/// Presenta un rettangolo ridimensionabile con 8 handles (4 angoli + 4 lati)
/// e oscura l'area esterna per evidenziare la selezione.
///
/// FEATURES:
/// - ✅ 8 handles di ridimensionamento
/// - ✅ Drag per spostare l'intera selezione
/// - ✅ Indicatore dimensioni live
/// - ✅ Snap a preset (A4, Instagram, etc.)
/// - ✅ Snap ad aspect ratio
/// - ✅ Animazioni fluide
class ExportAreaSelector extends StatefulWidget {
  /// Bounds iniziali della selezione (in coordinate canvas)
  final Rect initialBounds;

  /// Bounds massimi consentiti (limiti del canvas)
  final Rect maxBounds;

  /// Callback quando i bounds cambiano
  final ValueChanged<Rect> onBoundsChanged;

  /// Preset corrente (per mantenere aspect ratio)
  final ExportPreset? preset;

  /// Qualità export corrente (per calcolo dimensioni pixel)
  final ExportQuality quality;

  /// Scala del canvas (zoom level)
  final double canvasScale;

  /// Offset del canvas (pan position)
  final Offset canvasOffset;

  /// Se true, mantiene l'aspect ratio durante il resize
  final bool lockAspectRatio;

  const ExportAreaSelector({
    super.key,
    required this.initialBounds,
    required this.maxBounds,
    required this.onBoundsChanged,
    this.preset,
    required this.quality,
    required this.canvasScale,
    required this.canvasOffset,
    this.lockAspectRatio = false,
  });

  @override
  State<ExportAreaSelector> createState() => _ExportAreaSelectorState();
}

class _ExportAreaSelectorState extends State<ExportAreaSelector>
    with SingleTickerProviderStateMixin {
  late Rect _bounds;
  String? _activeHandle;
  Offset? _dragStart;
  Rect? _boundsAtDragStart;

  // Animazione per il bordo pulsante
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Dimensione degli handles
  static const double _handleSize = 24.0;
  static const double _handleHitArea = 44.0;
  static const double _minSize = 50.0;

  @override
  void initState() {
    super.initState();
    _bounds = widget.initialBounds;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ExportAreaSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialBounds != oldWidget.initialBounds &&
        _activeHandle == null) {
      _bounds = widget.initialBounds;
    }
  }

  /// Converti coordinate canvas → screen
  Offset _canvasToScreen(Offset canvasPoint) {
    return (canvasPoint - widget.canvasOffset) * widget.canvasScale;
  }

  /// Converti coordinate screen → canvas
  Offset _screenToCanvas(Offset screenPoint) {
    return widget.canvasOffset + (screenPoint / widget.canvasScale);
  }

  /// Ottieni il rettangolo in coordinate screen
  Rect get _screenBounds {
    final topLeft = _canvasToScreen(_bounds.topLeft);
    final bottomRight = _canvasToScreen(_bounds.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenBounds = _screenBounds;

        return Stack(
          children: [
            // Overlay scuro fuori dalla selezione
            _buildDarkOverlay(constraints.biggest, screenBounds),

            // Bordo della selezione
            Positioned(
              left: screenBounds.left,
              top: screenBounds.top,
              width: screenBounds.width,
              height: screenBounds.height,
              child: _buildSelectionBorder(),
            ),

            // Handles di ridimensionamento
            ..._buildHandles(screenBounds),

            // Indicatore dimensioni
            _buildDimensionsIndicator(screenBounds),

            // Griglia interna (regola dei terzi)
            Positioned(
              left: screenBounds.left,
              top: screenBounds.top,
              width: screenBounds.width,
              height: screenBounds.height,
              child: IgnorePointer(child: _buildGridOverlay()),
            ),
          ],
        );
      },
    );
  }

  /// Overlay scuro che oscura l'area fuori dalla selezione
  Widget _buildDarkOverlay(Size containerSize, Rect selectionRect) {
    return CustomPaint(
      size: containerSize,
      painter: _DarkOverlayPainter(
        selectionRect: selectionRect,
        overlayColor: Colors.black.withValues(alpha: 0.5),
      ),
    );
  }

  /// Bordo animato della selezione
  Widget _buildSelectionBorder() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.white.withValues(alpha: _pulseAnimation.value),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(
                  alpha: 0.3 * _pulseAnimation.value,
                ),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart:
                (details) => _onDragStart('center', details.localPosition),
            onPanUpdate:
                (details) =>
                    _onDragUpdate(details.localPosition, details.delta),
            onPanEnd: (_) => _onDragEnd(),
          ),
        );
      },
    );
  }

  /// Costruisce gli 8 handles di ridimensionamento
  List<Widget> _buildHandles(Rect bounds) {
    final handles = <Widget>[];

    final positions = {
      'tl': bounds.topLeft,
      'tc': Offset(bounds.center.dx, bounds.top),
      'tr': bounds.topRight,
      'ml': Offset(bounds.left, bounds.center.dy),
      'mr': Offset(bounds.right, bounds.center.dy),
      'bl': bounds.bottomLeft,
      'bc': Offset(bounds.center.dx, bounds.bottom),
      'br': bounds.bottomRight,
    };

    for (final entry in positions.entries) {
      handles.add(_buildHandle(entry.key, entry.value));
    }

    return handles;
  }

  /// Singolo handle di ridimensionamento
  Widget _buildHandle(String id, Offset position) {
    final isCorner = id.length == 2 && !id.contains('c');
    final size = isCorner ? _handleSize : _handleSize * 0.7;

    return Positioned(
      left: position.dx - _handleHitArea / 2,
      top: position.dy - _handleHitArea / 2,
      width: _handleHitArea,
      height: _handleHitArea,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _onDragStart(id, details.localPosition),
        onPanUpdate:
            (details) => _onDragUpdate(details.localPosition, details.delta),
        onPanEnd: (_) => _onDragEnd(),
        child: Center(
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, _) {
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: isCorner ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: isCorner ? BorderRadius.circular(4) : null,
                  border: Border.all(color: Colors.blue, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Indicatore delle dimensioni in tempo reale
  Widget _buildDimensionsIndicator(Rect bounds) {
    final scale = widget.quality.dpi / 72.0;
    final widthPx = (_bounds.width * scale).round();
    final heightPx = (_bounds.height * scale).round();

    final exceedsLimit =
        widthPx > CanvasExportService.maxImageDimension ||
        heightPx > CanvasExportService.maxImageDimension;

    return Positioned(
      left: bounds.left,
      top: bounds.bottom + 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              exceedsLimit
                  ? Colors.orange.withValues(alpha: 0.9)
                  : Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                exceedsLimit
                    ? Colors.orange
                    : Colors.white.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (exceedsLimit) ...[
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 14,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              '$widthPx × $heightPx px',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '@ ${widget.quality.dpi.toInt()} DPI',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
            if (exceedsLimit) ...[
              const SizedBox(width: 8),
              const Text(
                '(Large)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Griglia dei terzi sovrapposta alla selezione
  Widget _buildGridOverlay() {
    return CustomPaint(painter: _GridOverlayPainter());
  }

  // ============================================================
  // GESTURE HANDLING
  // ============================================================

  void _onDragStart(String handleId, Offset localPosition) {
    setState(() {
      _activeHandle = handleId;
      _dragStart = localPosition;
      _boundsAtDragStart = _bounds;
    });
    HapticFeedback.lightImpact();
  }

  void _onDragUpdate(Offset localPosition, Offset delta) {
    if (_activeHandle == null || _boundsAtDragStart == null) return;

    // Converti delta da screen a canvas
    final canvasDelta = delta / widget.canvasScale;

    setState(() {
      switch (_activeHandle!) {
        case 'center':
          _bounds = _moveBounds(canvasDelta);
          break;
        case 'tl':
          _bounds = _resizeFromTopLeft(canvasDelta);
          break;
        case 'tr':
          _bounds = _resizeFromTopRight(canvasDelta);
          break;
        case 'bl':
          _bounds = _resizeFromBottomLeft(canvasDelta);
          break;
        case 'br':
          _bounds = _resizeFromBottomRight(canvasDelta);
          break;
        case 'tc':
          _bounds = _resizeFromTop(canvasDelta);
          break;
        case 'bc':
          _bounds = _resizeFromBottom(canvasDelta);
          break;
        case 'ml':
          _bounds = _resizeFromLeft(canvasDelta);
          break;
        case 'mr':
          _bounds = _resizeFromRight(canvasDelta);
          break;
      }

      // Notifica il cambio
      widget.onBoundsChanged(_bounds);
    });
  }

  void _onDragEnd() {
    if (_activeHandle != null) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      _activeHandle = null;
      _dragStart = null;
      _boundsAtDragStart = null;
    });
  }

  // ============================================================
  // RESIZE HELPERS
  // ============================================================

  Rect _moveBounds(Offset delta) {
    var newBounds = _bounds.shift(delta);

    // Limita ai bounds massimi
    if (newBounds.left < widget.maxBounds.left) {
      newBounds = newBounds.translate(
        widget.maxBounds.left - newBounds.left,
        0,
      );
    }
    if (newBounds.top < widget.maxBounds.top) {
      newBounds = newBounds.translate(0, widget.maxBounds.top - newBounds.top);
    }
    if (newBounds.right > widget.maxBounds.right) {
      newBounds = newBounds.translate(
        widget.maxBounds.right - newBounds.right,
        0,
      );
    }
    if (newBounds.bottom > widget.maxBounds.bottom) {
      newBounds = newBounds.translate(
        0,
        widget.maxBounds.bottom - newBounds.bottom,
      );
    }

    return newBounds;
  }

  Rect _resizeFromTopLeft(Offset delta) {
    final newLeft = (_bounds.left + delta.dx).clamp(
      widget.maxBounds.left,
      _bounds.right - _minSize,
    );
    final newTop = (_bounds.top + delta.dy).clamp(
      widget.maxBounds.top,
      _bounds.bottom - _minSize,
    );

    if (widget.lockAspectRatio && widget.preset?.aspectRatio != null) {
      return _adjustForAspectRatio(
        Rect.fromLTRB(newLeft, newTop, _bounds.right, _bounds.bottom),
        'tl',
      );
    }

    return Rect.fromLTRB(newLeft, newTop, _bounds.right, _bounds.bottom);
  }

  Rect _resizeFromTopRight(Offset delta) {
    final newRight = (_bounds.right + delta.dx).clamp(
      _bounds.left + _minSize,
      widget.maxBounds.right,
    );
    final newTop = (_bounds.top + delta.dy).clamp(
      widget.maxBounds.top,
      _bounds.bottom - _minSize,
    );

    if (widget.lockAspectRatio && widget.preset?.aspectRatio != null) {
      return _adjustForAspectRatio(
        Rect.fromLTRB(_bounds.left, newTop, newRight, _bounds.bottom),
        'tr',
      );
    }

    return Rect.fromLTRB(_bounds.left, newTop, newRight, _bounds.bottom);
  }

  Rect _resizeFromBottomLeft(Offset delta) {
    final newLeft = (_bounds.left + delta.dx).clamp(
      widget.maxBounds.left,
      _bounds.right - _minSize,
    );
    final newBottom = (_bounds.bottom + delta.dy).clamp(
      _bounds.top + _minSize,
      widget.maxBounds.bottom,
    );

    if (widget.lockAspectRatio && widget.preset?.aspectRatio != null) {
      return _adjustForAspectRatio(
        Rect.fromLTRB(newLeft, _bounds.top, _bounds.right, newBottom),
        'bl',
      );
    }

    return Rect.fromLTRB(newLeft, _bounds.top, _bounds.right, newBottom);
  }

  Rect _resizeFromBottomRight(Offset delta) {
    final newRight = (_bounds.right + delta.dx).clamp(
      _bounds.left + _minSize,
      widget.maxBounds.right,
    );
    final newBottom = (_bounds.bottom + delta.dy).clamp(
      _bounds.top + _minSize,
      widget.maxBounds.bottom,
    );

    if (widget.lockAspectRatio && widget.preset?.aspectRatio != null) {
      return _adjustForAspectRatio(
        Rect.fromLTRB(_bounds.left, _bounds.top, newRight, newBottom),
        'br',
      );
    }

    return Rect.fromLTRB(_bounds.left, _bounds.top, newRight, newBottom);
  }

  Rect _resizeFromTop(Offset delta) {
    final newTop = (_bounds.top + delta.dy).clamp(
      widget.maxBounds.top,
      _bounds.bottom - _minSize,
    );
    return Rect.fromLTRB(_bounds.left, newTop, _bounds.right, _bounds.bottom);
  }

  Rect _resizeFromBottom(Offset delta) {
    final newBottom = (_bounds.bottom + delta.dy).clamp(
      _bounds.top + _minSize,
      widget.maxBounds.bottom,
    );
    return Rect.fromLTRB(_bounds.left, _bounds.top, _bounds.right, newBottom);
  }

  Rect _resizeFromLeft(Offset delta) {
    final newLeft = (_bounds.left + delta.dx).clamp(
      widget.maxBounds.left,
      _bounds.right - _minSize,
    );
    return Rect.fromLTRB(newLeft, _bounds.top, _bounds.right, _bounds.bottom);
  }

  Rect _resizeFromRight(Offset delta) {
    final newRight = (_bounds.right + delta.dx).clamp(
      _bounds.left + _minSize,
      widget.maxBounds.right,
    );
    return Rect.fromLTRB(_bounds.left, _bounds.top, newRight, _bounds.bottom);
  }

  /// Aggiusta i bounds per mantenere l'aspect ratio
  Rect _adjustForAspectRatio(Rect newBounds, String corner) {
    final aspect = widget.preset!.aspectRatio!;
    final width = newBounds.width;
    final height = newBounds.height;
    final currentAspect = width / height;

    if (currentAspect > aspect) {
      // Troppo largo, aggiusta width
      final newWidth = height * aspect;
      switch (corner) {
        case 'tl':
        case 'bl':
          return Rect.fromLTRB(
            newBounds.right - newWidth,
            newBounds.top,
            newBounds.right,
            newBounds.bottom,
          );
        default:
          return Rect.fromLTRB(
            newBounds.left,
            newBounds.top,
            newBounds.left + newWidth,
            newBounds.bottom,
          );
      }
    } else {
      // Troppo alto, aggiusta height
      final newHeight = width / aspect;
      switch (corner) {
        case 'tl':
        case 'tr':
          return Rect.fromLTRB(
            newBounds.left,
            newBounds.bottom - newHeight,
            newBounds.right,
            newBounds.bottom,
          );
        default:
          return Rect.fromLTRB(
            newBounds.left,
            newBounds.top,
            newBounds.right,
            newBounds.top + newHeight,
          );
      }
    }
  }

  /// Imposta i bounds per fit al contenuto
  void fitToContent(Rect contentBounds) {
    setState(() {
      _bounds = contentBounds;
    });
    widget.onBoundsChanged(_bounds);
  }

  /// Imposta i bounds per un preset specifico mantenendo il centro
  void applyPreset(ExportPreset preset) {
    if (preset.aspectRatio == null) return;

    final center = _bounds.center;
    final currentArea = _bounds.width * _bounds.height;

    // Calcola nuove dimensioni mantenendo area simile
    final aspect = preset.aspectRatio!;
    final newHeight = (currentArea / aspect).abs();
    final newWidth = newHeight * aspect;

    final newBounds = Rect.fromCenter(
      center: center,
      width: newWidth,
      height: newHeight,
    );

    // Limita ai bounds massimi
    setState(() {
      _bounds = newBounds.intersect(widget.maxBounds);
    });
    widget.onBoundsChanged(_bounds);
  }
}

// ============================================================
// PAINTERS
// ============================================================

/// Painter per l'overlay scuro
class _DarkOverlayPainter extends CustomPainter {
  final Rect selectionRect;
  final Color overlayColor;

  _DarkOverlayPainter({
    required this.selectionRect,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = overlayColor;
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Disegna 4 rettangoli intorno alla selezione
    // Top
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, selectionRect.top), paint);
    // Bottom
    canvas.drawRect(
      Rect.fromLTRB(0, selectionRect.bottom, size.width, size.height),
      paint,
    );
    // Left
    canvas.drawRect(
      Rect.fromLTRB(
        0,
        selectionRect.top,
        selectionRect.left,
        selectionRect.bottom,
      ),
      paint,
    );
    // Right
    canvas.drawRect(
      Rect.fromLTRB(
        selectionRect.right,
        selectionRect.top,
        size.width,
        selectionRect.bottom,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_DarkOverlayPainter oldDelegate) {
    return selectionRect != oldDelegate.selectionRect ||
        overlayColor != oldDelegate.overlayColor;
  }
}

/// Painter per la griglia dei terzi
class _GridOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.3)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;

    // Linee verticali (terzi)
    final thirdWidth = size.width / 3;
    canvas.drawLine(
      Offset(thirdWidth, 0),
      Offset(thirdWidth, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(thirdWidth * 2, 0),
      Offset(thirdWidth * 2, size.height),
      paint,
    );

    // Linee orizzontali (terzi)
    final thirdHeight = size.height / 3;
    canvas.drawLine(
      Offset(0, thirdHeight),
      Offset(size.width, thirdHeight),
      paint,
    );
    canvas.drawLine(
      Offset(0, thirdHeight * 2),
      Offset(size.width, thirdHeight * 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GridOverlayPainter oldDelegate) => false;
}
