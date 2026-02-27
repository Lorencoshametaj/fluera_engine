import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import '../l10n/fluera_localizations.dart';
import 'image_editor_models.dart';

// ============================================================================
// Image Editor — Crop Editor Dialog
// Full-screen crop tool with aspect ratio lock and rule-of-thirds grid.
// ============================================================================

class CropEditorDialog extends StatefulWidget {
  final ui.Image image;
  final Rect? initialCropRect;

  const CropEditorDialog({
    super.key,
    required this.image,
    this.initialCropRect,
  });

  @override
  State<CropEditorDialog> createState() => _CropEditorDialogState();
}

class _CropEditorDialogState extends State<CropEditorDialog> {
  late Rect _cropRect;
  Offset? _dragStart;
  String? _dragHandle;
  int _selectedAspectIndex = 0;

  late final List<CropAspectRatio> _aspectRatios;

  @override
  void initState() {
    super.initState();
    _cropRect =
        widget.initialCropRect ?? const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);

    final imgRatio = widget.image.width / widget.image.height;
    _aspectRatios = [
      const CropAspectRatio('Free', null),
      const CropAspectRatio('1:1', 1.0),
      const CropAspectRatio('4:3', 4 / 3),
      const CropAspectRatio('16:9', 16 / 9),
      const CropAspectRatio('3:2', 3 / 2),
      CropAspectRatio('Original', imgRatio),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = FlueraLocalizations.of(context);

    return Dialog(
      backgroundColor: cs.surfaceContainerHighest,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 8, 8),
            child: Row(
              children: [
                Icon(Icons.crop_rounded, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.proCanvas_cropImage,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: cs.onSurface),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _cropRect),
                  child: Text(l10n.apply),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),

          // Aspect ratio selector chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: List.generate(_aspectRatios.length, (i) {
                final ar = _aspectRatios[i];
                final isSelected = _selectedAspectIndex == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: isSelected,
                    label: Text(ar.label),
                    onSelected: (_) => _selectAspectRatio(i),
                  ),
                );
              }),
            ),
          ),

          Divider(height: 1, color: cs.outlineVariant),

          // Interactive crop area
          Expanded(
            child: Container(
              color: cs.surfaceContainerLowest,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onPanStart: (d) => _onPanStart(d, constraints),
                    onPanUpdate: (d) => _onPanUpdate(d, constraints),
                    onPanEnd:
                        (_) => setState(() {
                          _dragStart = null;
                          _dragHandle = null;
                        }),
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: CropPainter(
                        image: widget.image,
                        cropRect: _cropRect,
                        primaryColor: cs.primary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Instructions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(
              l10n.proCanvas_cropInstructions,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Aspect ratio
  // --------------------------------------------------------------------------

  void _selectAspectRatio(int index) {
    setState(() {
      _selectedAspectIndex = index;
      final ar = _aspectRatios[index];
      if (ar.ratio != null) _applyCropAspectRatio(ar.ratio!);
    });
    HapticFeedback.lightImpact();
  }

  void _applyCropAspectRatio(double targetRatio) {
    final imgRatio = widget.image.width / widget.image.height;
    final normalizedRatio = targetRatio / imgRatio;

    final cx = (_cropRect.left + _cropRect.right) / 2;
    final cy = (_cropRect.top + _cropRect.bottom) / 2;

    double w, h;
    if (normalizedRatio > _cropRect.width / _cropRect.height) {
      w = _cropRect.width;
      h = w / normalizedRatio;
    } else {
      h = _cropRect.height;
      w = h * normalizedRatio;
    }

    final left = (cx - w / 2).clamp(0.0, 1.0 - w);
    final top = (cy - h / 2).clamp(0.0, 1.0 - h);
    setState(() => _cropRect = Rect.fromLTWH(left, top, w, h));
  }

  // --------------------------------------------------------------------------
  // Gesture handling
  // --------------------------------------------------------------------------

  void _onPanStart(DragStartDetails details, BoxConstraints constraints) {
    final localPos = details.localPosition;
    final imageRect = _getImageRect(constraints);
    final cropPixelRect = Rect.fromLTRB(
      imageRect.left + _cropRect.left * imageRect.width,
      imageRect.top + _cropRect.top * imageRect.height,
      imageRect.left + _cropRect.right * imageRect.width,
      imageRect.top + _cropRect.bottom * imageRect.height,
    );

    const handleSize = 40.0;
    if ((localPos - cropPixelRect.topLeft).distance < handleSize) {
      _dragHandle = 'tl';
    } else if ((localPos - cropPixelRect.topRight).distance < handleSize) {
      _dragHandle = 'tr';
    } else if ((localPos - cropPixelRect.bottomLeft).distance < handleSize) {
      _dragHandle = 'bl';
    } else if ((localPos - cropPixelRect.bottomRight).distance < handleSize) {
      _dragHandle = 'br';
    } else if (cropPixelRect.contains(localPos)) {
      _dragHandle = 'center';
    }

    if (_dragHandle != null) _dragStart = localPos;
  }

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (_dragStart == null || _dragHandle == null) return;

    final delta = details.localPosition - _dragStart!;
    final imageRect = _getImageRect(constraints);
    final dx = delta.dx / imageRect.width;
    final dy = delta.dy / imageRect.height;

    final lockedRatio = _aspectRatios[_selectedAspectIndex].ratio;

    setState(() {
      if (_dragHandle == 'center') {
        final w = _cropRect.width;
        final h = _cropRect.height;
        _cropRect = Rect.fromLTWH(
          (_cropRect.left + dx).clamp(0.0, 1.0 - w),
          (_cropRect.top + dy).clamp(0.0, 1.0 - h),
          w,
          h,
        );
      } else if (lockedRatio != null) {
        _resizeWithAspectRatio(dx, dy, lockedRatio);
      } else {
        _resizeFree(dx, dy);
      }
      _dragStart = details.localPosition;
    });
  }

  void _resizeFree(double dx, double dy) {
    switch (_dragHandle!) {
      case 'tl':
        _cropRect = Rect.fromLTRB(
          (_cropRect.left + dx).clamp(0.0, _cropRect.right - 0.1),
          (_cropRect.top + dy).clamp(0.0, _cropRect.bottom - 0.1),
          _cropRect.right,
          _cropRect.bottom,
        );
      case 'tr':
        _cropRect = Rect.fromLTRB(
          _cropRect.left,
          (_cropRect.top + dy).clamp(0.0, _cropRect.bottom - 0.1),
          (_cropRect.right + dx).clamp(_cropRect.left + 0.1, 1.0),
          _cropRect.bottom,
        );
      case 'bl':
        _cropRect = Rect.fromLTRB(
          (_cropRect.left + dx).clamp(0.0, _cropRect.right - 0.1),
          _cropRect.top,
          _cropRect.right,
          (_cropRect.bottom + dy).clamp(_cropRect.top + 0.1, 1.0),
        );
      case 'br':
        _cropRect = Rect.fromLTRB(
          _cropRect.left,
          _cropRect.top,
          (_cropRect.right + dx).clamp(_cropRect.left + 0.1, 1.0),
          (_cropRect.bottom + dy).clamp(_cropRect.top + 0.1, 1.0),
        );
    }
  }

  void _resizeWithAspectRatio(double dx, double dy, double targetRatio) {
    final imgRatio = widget.image.width / widget.image.height;
    final normalizedRatio = targetRatio / imgRatio;
    final delta = (dx.abs() > dy.abs()) ? dx : dy;

    double newW, newH;
    switch (_dragHandle!) {
      case 'br':
        newW = (_cropRect.width + delta).clamp(0.1, 1.0 - _cropRect.left);
        newH = newW / normalizedRatio;
        if (_cropRect.top + newH > 1.0) {
          newH = 1.0 - _cropRect.top;
          newW = newH * normalizedRatio;
        }
        _cropRect = Rect.fromLTWH(_cropRect.left, _cropRect.top, newW, newH);
      case 'tl':
        newW = (_cropRect.width - delta).clamp(0.1, _cropRect.right);
        newH = newW / normalizedRatio;
        _cropRect = Rect.fromLTWH(
          (_cropRect.right - newW).clamp(0.0, 1.0),
          (_cropRect.bottom - newH).clamp(0.0, 1.0),
          newW,
          newH,
        );
      case 'tr':
        newW = (_cropRect.width + delta).clamp(0.1, 1.0 - _cropRect.left);
        newH = newW / normalizedRatio;
        _cropRect = Rect.fromLTWH(
          _cropRect.left,
          (_cropRect.bottom - newH).clamp(0.0, 1.0),
          newW,
          newH,
        );
      case 'bl':
        newW = (_cropRect.width - delta).clamp(0.1, _cropRect.right);
        newH = newW / normalizedRatio;
        _cropRect = Rect.fromLTWH(
          (_cropRect.right - newW).clamp(0.0, 1.0),
          _cropRect.top,
          newW,
          newH,
        );
    }
  }

  Rect _getImageRect(BoxConstraints constraints) {
    final containerRatio = constraints.maxWidth / constraints.maxHeight;
    final imageRatio = widget.image.width / widget.image.height;

    double width, height;
    if (containerRatio > imageRatio) {
      height = constraints.maxHeight;
      width = height * imageRatio;
    } else {
      width = constraints.maxWidth;
      height = width / imageRatio;
    }

    return Rect.fromLTWH(
      (constraints.maxWidth - width) / 2,
      (constraints.maxHeight - height) / 2,
      width,
      height,
    );
  }
}

// ============================================================================
// Crop Painter
// ============================================================================

class CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect cropRect;
  final Color primaryColor;

  CropPainter({
    required this.image,
    required this.cropRect,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final containerRatio = size.width / size.height;
    final imageRatio = image.width / image.height;

    double w, h, left, top;
    if (containerRatio > imageRatio) {
      h = size.height;
      w = h * imageRatio;
      left = (size.width - w) / 2;
      top = 0;
    } else {
      w = size.width;
      h = w / imageRatio;
      left = 0;
      top = (size.height - h) / 2;
    }

    final imageRect = Rect.fromLTWH(left, top, w, h);

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    final cropPixel = Rect.fromLTRB(
      imageRect.left + cropRect.left * imageRect.width,
      imageRect.top + cropRect.top * imageRect.height,
      imageRect.left + cropRect.right * imageRect.width,
      imageRect.top + cropRect.bottom * imageRect.height,
    );

    // Overlay (4 rects around crop)
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawRect(
      Rect.fromLTRB(
        imageRect.left,
        imageRect.top,
        imageRect.right,
        cropPixel.top,
      ),
      overlayPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        imageRect.left,
        cropPixel.bottom,
        imageRect.right,
        imageRect.bottom,
      ),
      overlayPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        imageRect.left,
        cropPixel.top,
        cropPixel.left,
        cropPixel.bottom,
      ),
      overlayPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        cropPixel.right,
        cropPixel.top,
        imageRect.right,
        cropPixel.bottom,
      ),
      overlayPaint,
    );

    // Crop border
    canvas.drawRect(
      cropPixel,
      Paint()
        ..color = primaryColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // Rule-of-thirds grid
    final gridPaint =
        Paint()
          ..color = primaryColor.withValues(alpha: 0.35)
          ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = cropPixel.left + (cropPixel.width * i / 3);
      canvas.drawLine(
        Offset(x, cropPixel.top),
        Offset(x, cropPixel.bottom),
        gridPaint,
      );
      final y = cropPixel.top + (cropPixel.height * i / 3);
      canvas.drawLine(
        Offset(cropPixel.left, y),
        Offset(cropPixel.right, y),
        gridPaint,
      );
    }

    // Corner handles
    const handleRadius = 6.0;
    final handleFill = Paint()..color = primaryColor;
    final handleStroke =
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

    for (final corner in [
      cropPixel.topLeft,
      cropPixel.topRight,
      cropPixel.bottomLeft,
      cropPixel.bottomRight,
    ]) {
      canvas.drawCircle(corner, handleRadius, handleFill);
      canvas.drawCircle(corner, handleRadius, handleStroke);
    }
  }

  @override
  bool shouldRepaint(CropPainter old) =>
      old.cropRect != cropRect || old.primaryColor != primaryColor;
}
