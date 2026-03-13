import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

// =============================================================================
// 🎨 EYEDROPPER OVERLAY — Fullscreen pixel-capture with pixel-grid magnifier
//
// Professional magnifier that shows a zoomed pixel grid (like Photoshop/Figma)
// around the pointer position, with the center pixel highlighted.
//
// Usage:
//   final color = await showEyedropperOverlay(context: context, canvasKey: key);
//   if (color != null) { /* use picked color */ }
// =============================================================================

/// Shows a fullscreen eyedropper overlay that captures a color from the screen.
///
/// [canvasKey] should be a [GlobalKey] attached to the widget tree boundary
/// from which pixels will be sampled (typically the canvas `RepaintBoundary`).
/// If null, uses the root render object.
Future<Color?> showEyedropperOverlay({
  required BuildContext context,
  GlobalKey? canvasKey,
}) {
  return Navigator.of(context).push<Color>(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, animation, secondaryAnimation) =>
          FadeTransition(
            opacity: animation,
            child: EyedropperOverlay(canvasKey: canvasKey),
          ),
    ),
  );
}

/// Fullscreen eyedropper overlay with pixel-grid magnifier.
class EyedropperOverlay extends StatefulWidget {
  final GlobalKey? canvasKey;

  const EyedropperOverlay({super.key, this.canvasKey});

  @override
  State<EyedropperOverlay> createState() => _EyedropperOverlayState();
}

class _EyedropperOverlayState extends State<EyedropperOverlay> {
  Offset? _pointerPosition;
  Color _pickedColor = Colors.transparent;
  ui.Image? _snapshot;
  ByteData? _snapshotBytes; // Cached — avoids async toByteData on every drag
  bool _isCapturing = false;
  double _dpr = 1.0;

  // Grid of sampled colors around pointer for the magnifier
  static const int _gridSize = 11; // 11×11 pixel grid
  List<Color>? _magnifierGrid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _captureScreen());
  }

  @override
  void dispose() {
    _snapshot?.dispose();
    super.dispose();
  }

  Future<void> _captureScreen() async {
    if (_isCapturing) return;
    _isCapturing = true;

    try {
      RenderRepaintBoundary? boundary;

      if (widget.canvasKey?.currentContext != null) {
        final renderObject = widget.canvasKey!.currentContext!.findRenderObject();
        if (renderObject is RenderRepaintBoundary) {
          boundary = renderObject;
        }
      }

      if (boundary == null) {
        final renderObject = WidgetsBinding.instance
            .rootElement?.findRenderObject();
        if (renderObject is RenderRepaintBoundary) {
          boundary = renderObject;
        }
      }

      if (boundary != null) {
        _dpr = MediaQuery.of(context).devicePixelRatio;
        final image = await boundary.toImage(pixelRatio: _dpr);
        // Pre-cache the byte data — O(1) per-pixel sampling from here on
        final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (mounted) {
          setState(() {
            _snapshot = image;
            _snapshotBytes = bytes;
          });
        }
      }
    } catch (e) {
      debugPrint('Eyedropper: capture failed: $e');
    } finally {
      _isCapturing = false;
    }
  }

  /// Sample center pixel + surrounding grid synchronously (no await).
  void _sampleAt(Offset position) {
    if (_snapshot == null || _snapshotBytes == null) return;

    final bytes = _snapshotBytes!;
    final imgW = _snapshot!.width;
    final imgH = _snapshot!.height;
    final cx = (position.dx * _dpr).round().clamp(0, imgW - 1);
    final cy = (position.dy * _dpr).round().clamp(0, imgH - 1);

    // Sample center pixel
    _pickedColor = _getPixel(bytes, cx, cy, imgW, imgH);

    // Build magnifier grid
    final halfGrid = _gridSize ~/ 2;
    final grid = <Color>[];
    for (int gy = -halfGrid; gy <= halfGrid; gy++) {
      for (int gx = -halfGrid; gx <= halfGrid; gx++) {
        grid.add(_getPixel(bytes, cx + gx, cy + gy, imgW, imgH));
      }
    }
    _magnifierGrid = grid;
  }

  Color _getPixel(ByteData bytes, int x, int y, int w, int h) {
    final px = x.clamp(0, w - 1);
    final py = y.clamp(0, h - 1);
    final offset = (py * w + px) * 4;
    if (offset + 3 >= bytes.lengthInBytes) return Colors.transparent;
    return Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          HapticFeedback.selectionClick();
          _sampleAt(d.globalPosition);
          setState(() => _pointerPosition = d.globalPosition);
        },
        onPanUpdate: (d) {
          _sampleAt(d.globalPosition);
          setState(() => _pointerPosition = d.globalPosition);
        },
        onPanEnd: (d) {
          HapticFeedback.mediumImpact();
          Navigator.pop(context, _pickedColor);
        },
        onTapUp: (d) {
          _sampleAt(d.globalPosition);
          HapticFeedback.mediumImpact();
          Navigator.pop(context, _pickedColor);
        },
        child: Stack(
          children: [
            // Semi-transparent overlay
            Container(color: Colors.black.withValues(alpha: 0.12)),

            // Pixel-grid magnifier
            if (_pointerPosition != null && _magnifierGrid != null)
              Positioned(
                // Position above finger, flip if near top
                left: _loupeLeft(screenSize),
                top: _loupeTop(screenSize),
                child: _PixelGridMagnifier(
                  grid: _magnifierGrid!,
                  gridSize: _gridSize,
                  centerColor: _pickedColor,
                ),
              ),

            // Crosshair at pointer
            if (_pointerPosition != null)
              Positioned(
                left: _pointerPosition!.dx - 18,
                top: _pointerPosition!.dy - 18,
                child: SizedBox(
                  width: 36, height: 36,
                  child: CustomPaint(
                    painter: _CrosshairPainter(color: _pickedColor),
                  ),
                ),
              ),

            // Instructions banner
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.black : Colors.white)
                        .withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.colorize_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Drag to pick a color • Release to select',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : Colors.black54)),
                    ],
                  ),
                ),
              ),
            ),

            // Cancel button
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.black : Colors.white)
                        .withValues(alpha: 0.88),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Icon(Icons.close, size: 18,
                      color: isDark ? Colors.white70 : Colors.black54),
                ),
              ),
            ),

            // Bottom info bar
            if (_pointerPosition != null)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 16,
                left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: (isDark ? const Color(0xFF2A2A2A) : Colors.white)
                          .withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Color swatch
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: _pickedColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? Colors.white24 : Colors.black12),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Hex + RGB
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('#${_colorToHex(_pickedColor)}',
                              style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700,
                                fontFamily: 'monospace', letterSpacing: 1,
                                color: isDark ? Colors.white : Colors.black87,
                              )),
                            Text(
                              'R:${(_pickedColor.r * 255).round()} '
                              'G:${(_pickedColor.g * 255).round()} '
                              'B:${(_pickedColor.b * 255).round()}',
                              style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w500,
                                fontFamily: 'monospace',
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
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

  // Position the magnifier loupe — flip position when near screen edges
  double _loupeLeft(Size screen) {
    const loupeW = 154.0;
    final x = _pointerPosition!.dx - loupeW / 2;
    return x.clamp(8.0, screen.width - loupeW - 8);
  }

  double _loupeTop(Size screen) {
    const loupeH = 154.0;
    const offset = 80.0;
    // If pointer is near top, show below
    if (_pointerPosition!.dy < loupeH + offset + 60) {
      return _pointerPosition!.dy + 50;
    }
    return _pointerPosition!.dy - loupeH - offset;
  }

  static String _colorToHex(Color c) {
    final r = (c.r * 255).round().clamp(0, 255);
    final g = (c.g * 255).round().clamp(0, 255);
    final b = (c.b * 255).round().clamp(0, 255);
    return '${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  }
}

// =============================================================================
// PIXEL-GRID MAGNIFIER
// =============================================================================

/// Magnifier that renders a zoomed pixel grid with the center pixel highlighted.
/// Like Photoshop's eyedropper zoom or Figma's pixel grid.
class _PixelGridMagnifier extends StatelessWidget {
  final List<Color> grid;
  final int gridSize;
  final Color centerColor;

  const _PixelGridMagnifier({
    required this.grid,
    required this.gridSize,
    required this.centerColor,
  });

  @override
  Widget build(BuildContext context) {
    const loupeSize = 154.0;

    return Container(
      width: loupeSize,
      height: loupeSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: CustomPaint(
          size: const Size(loupeSize, loupeSize),
          painter: _PixelGridPainter(
            grid: grid,
            gridSize: gridSize,
          ),
        ),
      ),
    );
  }
}

/// Paints a pixel grid, each "pixel" as a colored cell.
/// The center cell gets a highlighted border.
class _PixelGridPainter extends CustomPainter {
  final List<Color> grid;
  final int gridSize;

  _PixelGridPainter({required this.grid, required this.gridSize});

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / gridSize;
    final center = gridSize ~/ 2;

    for (int y = 0; y < gridSize; y++) {
      for (int x = 0; x < gridSize; x++) {
        final idx = y * gridSize + x;
        if (idx >= grid.length) break;

        final rect = Rect.fromLTWH(
          x * cellSize, y * cellSize, cellSize, cellSize);
        canvas.drawRect(rect, Paint()..color = grid[idx]);

        // Subtle grid lines
        canvas.drawRect(rect, Paint()
          ..color = Colors.black.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5);
      }
    }

    // Highlight center pixel with a thick white border + dark outline
    final centerRect = Rect.fromLTWH(
      center * cellSize, center * cellSize, cellSize, cellSize);
    canvas.drawRect(centerRect, Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
    canvas.drawRect(centerRect, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_PixelGridPainter old) => true;
}

// =============================================================================
// CROSSHAIR
// =============================================================================

/// Crosshair targeting indicator with shadow for visibility.
class _CrosshairPainter extends CustomPainter {
  final Color color;
  _CrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Shadow for visibility on any background
    canvas.drawCircle(center, radius,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..isAntiAlias = true);

    // White outer ring
    canvas.drawCircle(center, radius,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..isAntiAlias = true);

    // Inner circle showing the sampled color
    canvas.drawCircle(center, radius * 0.35,
        Paint()
          ..color = color
          ..isAntiAlias = true);
    canvas.drawCircle(center, radius * 0.35,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) => old.color != color;
}
