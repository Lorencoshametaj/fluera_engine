import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import '../l10n/nebula_localizations.dart';
import '../core/models/image_element.dart';
import '../drawing/models/pro_drawing_point.dart';

// ============================================================================
// 🎨 IMAGE EDITOR DIALOG — Material Design 3
// Professional image editor dialog with color adjustments, transforms, and crop.
// ============================================================================

class ImageEditorDialog extends StatefulWidget {
  final ImageElement imageElement;
  final ui.Image image;
  final Function(ImageElement) onSave;
  final VoidCallback onDelete;

  const ImageEditorDialog({
    super.key,
    required this.imageElement,
    required this.image,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<ImageEditorDialog> createState() => _ImageEditorDialogState();
}

class _ImageEditorDialogState extends State<ImageEditorDialog>
    with SingleTickerProviderStateMixin {
  late double _scale;
  late double _rotation;
  late double _brightness;
  late double _contrast;
  late double _saturation;
  late double _opacity;
  late bool _flipHorizontal;
  late bool _flipVertical;
  Rect? _cropRect;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _scale = widget.imageElement.scale;
    _rotation = widget.imageElement.rotation;
    _brightness = widget.imageElement.brightness;
    _contrast = widget.imageElement.contrast;
    _saturation = widget.imageElement.saturation;
    _opacity = widget.imageElement.opacity;
    _flipHorizontal = widget.imageElement.flipHorizontal;
    _flipVertical = widget.imageElement.flipVertical;
    _cropRect = widget.imageElement.cropRect;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Whether any value has been changed from the original.
  bool get _hasChanges =>
      _rotation != widget.imageElement.rotation ||
      _brightness != widget.imageElement.brightness ||
      _contrast != widget.imageElement.contrast ||
      _saturation != widget.imageElement.saturation ||
      _opacity != widget.imageElement.opacity ||
      _flipHorizontal != widget.imageElement.flipHorizontal ||
      _flipVertical != widget.imageElement.flipVertical ||
      _cropRect != widget.imageElement.cropRect;

  void _resetAll() {
    setState(() {
      _rotation = 0;
      _brightness = 0;
      _contrast = 0;
      _saturation = 0;
      _opacity = 1.0;
      _flipHorizontal = false;
      _flipVertical = false;
      _cropRect = null;
    });
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(cs, tt),
            _buildPreview(cs),
            _buildTabBar(cs),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildTransformTab(cs, tt), _buildColorTab(cs, tt)],
              ),
            ),
            _buildActions(cs, tt),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 🏷️ Header
  // --------------------------------------------------------------------------

  Widget _buildHeader(ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 8, 4),
      child: Row(
        children: [
          Icon(Icons.auto_fix_high_rounded, color: cs.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              NebulaLocalizations.of(context).proCanvas_professionalEditor,
              style: tt.titleLarge?.copyWith(color: cs.onSurface),
            ),
          ),
          if (_hasChanges)
            IconButton(
              onPressed: _resetAll,
              icon: const Icon(Icons.restart_alt_rounded),
              tooltip: 'Reset all',
              style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
            ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 🖼️ Preview
  // --------------------------------------------------------------------------

  Widget _buildPreview(ColorScheme cs) {
    return Container(
      height: 240,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: CustomPaint(
          painter: _PreviewPainter(
            image: widget.image,
            rotation: _rotation,
            flipHorizontal: _flipHorizontal,
            flipVertical: _flipVertical,
            brightness: _brightness,
            contrast: _contrast,
            saturation: _saturation,
            opacity: _opacity,
            cropRect: _cropRect,
            drawingStrokes: widget.imageElement.drawingStrokes,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 🗂️ Tab Bar
  // --------------------------------------------------------------------------

  Widget _buildTabBar(ColorScheme cs) {
    final l10n = NebulaLocalizations.of(context);
    return TabBar(
      controller: _tabController,
      labelColor: cs.primary,
      unselectedLabelColor: cs.onSurfaceVariant,
      indicatorColor: cs.primary,
      dividerColor: cs.outlineVariant.withValues(alpha: 0.5),
      tabs: [
        Tab(
          icon: const Icon(Icons.transform_rounded, size: 20),
          text: l10n.proCanvas_transformations,
        ),
        Tab(
          icon: const Icon(Icons.palette_rounded, size: 20),
          text: l10n.proCanvas_colorAdjustments,
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // 🔄 Transform Tab
  // --------------------------------------------------------------------------

  Widget _buildTransformTab(ColorScheme cs, TextTheme tt) {
    final l10n = NebulaLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      children: [
        // Rotation slider
        _buildSliderRow(
          cs: cs,
          tt: tt,
          icon: Icons.rotate_right_rounded,
          label: l10n.proCanvas_rotation,
          value: _rotation,
          min: -3.14159,
          max: 3.14159,
          valueText: '${(_rotation * 180 / 3.14159).toInt()}°',
          onChanged: (v) => setState(() => _rotation = v),
        ),
        const SizedBox(height: 20),

        // Flip chips
        Text(
          'Flip',
          style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              selected: _flipHorizontal,
              label: Text(l10n.proCanvas_flipH),
              avatar: const Icon(Icons.flip_rounded, size: 18),
              onSelected: (_) {
                setState(() => _flipHorizontal = !_flipHorizontal);
                HapticFeedback.lightImpact();
              },
            ),
            FilterChip(
              selected: _flipVertical,
              label: Text(l10n.proCanvas_flipV),
              avatar: Transform.rotate(
                angle: 1.5708,
                child: const Icon(Icons.flip_rounded, size: 18),
              ),
              onSelected: (_) {
                setState(() => _flipVertical = !_flipVertical);
                HapticFeedback.lightImpact();
              },
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Crop
        FilledButton.tonalIcon(
          onPressed: _openCropEditor,
          icon: const Icon(Icons.crop_rounded),
          label: Text(
            _cropRect != null
                ? l10n.proCanvas_editCrop
                : l10n.proCanvas_cropImage,
          ),
        ),
        if (_cropRect != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _cropRect = null),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(l10n.proCanvas_removeCrop),
            style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  // --------------------------------------------------------------------------
  // 🎨 Color Tab
  // --------------------------------------------------------------------------

  Widget _buildColorTab(ColorScheme cs, TextTheme tt) {
    final l10n = NebulaLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      children: [
        _buildSliderRow(
          cs: cs,
          tt: tt,
          icon: Icons.brightness_6_rounded,
          label: l10n.proCanvas_brightness,
          value: _brightness,
          min: -0.5,
          max: 0.5,
          valueText: _formatPercent(_brightness),
          onChanged: (v) => setState(() => _brightness = v),
        ),
        const SizedBox(height: 16),
        _buildSliderRow(
          cs: cs,
          tt: tt,
          icon: Icons.contrast_rounded,
          label: l10n.proCanvas_contrast,
          value: _contrast,
          min: -0.5,
          max: 0.5,
          valueText: _formatPercent(_contrast),
          onChanged: (v) => setState(() => _contrast = v),
        ),
        const SizedBox(height: 16),
        _buildSliderRow(
          cs: cs,
          tt: tt,
          icon: Icons.palette_rounded,
          label: l10n.proCanvas_saturation,
          value: _saturation,
          min: -1.0,
          max: 1.0,
          valueText: _formatPercent(_saturation),
          onChanged: (v) => setState(() => _saturation = v),
        ),
        const SizedBox(height: 16),
        _buildSliderRow(
          cs: cs,
          tt: tt,
          icon: Icons.opacity_rounded,
          label: l10n.proCanvas_opacity,
          value: _opacity,
          min: 0.1,
          max: 1.0,
          valueText: '${(_opacity * 100).toInt()}%',
          onChanged: (v) => setState(() => _opacity = v),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // 🎚️ Slider Row — MD3 native
  // --------------------------------------------------------------------------

  Widget _buildSliderRow({
    required ColorScheme cs,
    required TextTheme tt,
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required String valueText,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(label, style: tt.labelLarge?.copyWith(color: cs.onSurface)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                valueText,
                style: tt.labelMedium?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // ✅ Actions Footer
  // --------------------------------------------------------------------------

  Widget _buildActions(ColorScheme cs, TextTheme tt) {
    final l10n = NebulaLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          // Delete
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete();
            },
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(l10n.delete),
            style: TextButton.styleFrom(foregroundColor: cs.error),
          ),
          const Spacer(),

          // Cancel
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          const SizedBox(width: 8),

          // Save
          FilledButton.icon(
            onPressed: () {
              final updated = widget.imageElement.copyWith(
                scale: _scale,
                rotation: _rotation,
                brightness: _brightness,
                contrast: _contrast,
                saturation: _saturation,
                opacity: _opacity,
                flipHorizontal: _flipHorizontal,
                flipVertical: _flipVertical,
                cropRect: _cropRect,
                clearCrop:
                    _cropRect == null && widget.imageElement.cropRect != null,
              );
              widget.onSave(updated);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.check_rounded),
            label: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // ✂️ Crop Editor
  // --------------------------------------------------------------------------

  Future<void> _openCropEditor() async {
    final result = await showDialog<Rect?>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => _CropEditorDialog(
            image: widget.image,
            initialCropRect: _cropRect,
          ),
    );

    if (result != null) {
      setState(() => _cropRect = result);
    }
  }

  // --------------------------------------------------------------------------
  // 🛠️ Helpers
  // --------------------------------------------------------------------------

  String _formatPercent(double v) {
    final pct = (v * 100).toInt();
    return pct >= 0 ? '+$pct%' : '$pct%';
  }
}

// ============================================================================
// ✂️ CROP EDITOR DIALOG — Material Design 3
// Interactive crop editor with rule-of-thirds grid and corner handles.
// ============================================================================

class _CropEditorDialog extends StatefulWidget {
  final ui.Image image;
  final Rect? initialCropRect;

  const _CropEditorDialog({required this.image, this.initialCropRect});

  @override
  State<_CropEditorDialog> createState() => _CropEditorDialogState();
}

class _CropEditorDialogState extends State<_CropEditorDialog> {
  late Rect _cropRect;
  Offset? _dragStart;
  String? _dragHandle; // 'tl', 'tr', 'bl', 'br', 'center'

  @override
  void initState() {
    super.initState();
    _cropRect =
        widget.initialCropRect ?? const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = NebulaLocalizations.of(context);

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
                      painter: _CropPainter(
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

    if (_dragHandle != null) {
      _dragStart = localPos;
    }
  }

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (_dragStart == null || _dragHandle == null) return;

    final delta = details.localPosition - _dragStart!;
    final imageRect = _getImageRect(constraints);
    final dx = delta.dx / imageRect.width;
    final dy = delta.dy / imageRect.height;

    setState(() {
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
        case 'center':
          final w = _cropRect.width;
          final h = _cropRect.height;
          var newLeft = (_cropRect.left + dx).clamp(0.0, 1.0 - w);
          var newTop = (_cropRect.top + dy).clamp(0.0, 1.0 - h);
          _cropRect = Rect.fromLTWH(newLeft, newTop, w, h);
      }
      _dragStart = details.localPosition;
    });
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
// 🎨 CROP PAINTER
// Renders the image with a dark overlay outside the crop area, rule-of-thirds
// grid, and corner handles using the theme's primary color.
// ============================================================================

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect cropRect;
  final Color primaryColor;

  _CropPainter({
    required this.image,
    required this.cropRect,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fit-contain the image
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

    // Draw image
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    // Dark overlay outside crop
    final cropPixel = Rect.fromLTRB(
      imageRect.left + cropRect.left * imageRect.width,
      imageRect.top + cropRect.top * imageRect.height,
      imageRect.left + cropRect.right * imageRect.width,
      imageRect.top + cropRect.bottom * imageRect.height,
    );

    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);

    // Top, Bottom, Left, Right bands
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
  bool shouldRepaint(_CropPainter old) =>
      old.cropRect != cropRect || old.primaryColor != primaryColor;
}

// ============================================================================
// 🖼️ PREVIEW PAINTER
// Renders image with all effects (rotation, flip, crop, color adjustments,
// opacity) and any drawing strokes on top.
// ============================================================================

class _PreviewPainter extends CustomPainter {
  final ui.Image image;
  final double rotation;
  final bool flipHorizontal;
  final bool flipVertical;
  final double brightness;
  final double contrast;
  final double saturation;
  final double opacity;
  final Rect? cropRect;
  final List<ProStroke> drawingStrokes;

  _PreviewPainter({
    required this.image,
    required this.rotation,
    required this.flipHorizontal,
    required this.flipVertical,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.opacity,
    this.cropRect,
    this.drawingStrokes = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    final center = Offset(size.width / 2, size.height / 2);
    canvas.translate(center.dx, center.dy);

    if (rotation != 0) canvas.rotate(rotation);

    if (flipHorizontal || flipVertical) {
      canvas.scale(flipHorizontal ? -1.0 : 1.0, flipVertical ? -1.0 : 1.0);
    }

    // Source rect (with crop if present)
    Rect srcRect;
    double displayWidth, displayHeight;

    if (cropRect != null) {
      final imgW = image.width.toDouble();
      final imgH = image.height.toDouble();
      srcRect = Rect.fromLTRB(
        cropRect!.left * imgW,
        cropRect!.top * imgH,
        cropRect!.right * imgW,
        cropRect!.bottom * imgH,
      );
      displayWidth = srcRect.width;
      displayHeight = srcRect.height;
    } else {
      srcRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      displayWidth = image.width.toDouble();
      displayHeight = image.height.toDouble();
    }

    // Fit-contain scale
    final containerRatio = size.width / size.height;
    final imageRatio = displayWidth / displayHeight;
    final scale =
        containerRatio > imageRatio
            ? size.height / displayHeight
            : size.width / displayWidth;

    final dstRect = Rect.fromCenter(
      center: Offset.zero,
      width: displayWidth * scale,
      height: displayHeight * scale,
    );

    // Paint with effects
    final paint = Paint()..filterQuality = FilterQuality.medium;

    // 🔧 Opacity via paint.color alpha (NOT BlendMode.dstIn)
    if (opacity < 1.0) {
      paint.color = Color.fromRGBO(255, 255, 255, opacity);
    }

    // Color matrix filter
    if (brightness != 0 || contrast != 0 || saturation != 0) {
      paint.colorFilter = ColorFilter.matrix(_getColorMatrix());
    }

    canvas.drawImageRect(image, srcRect, dstRect, paint);

    // Draw strokes on top
    if (drawingStrokes.isNotEmpty) {
      canvas.save();
      canvas.scale(scale);

      for (final stroke in drawingStrokes) {
        if (stroke.points.isEmpty) continue;

        final strokePaint =
            Paint()
              ..color = stroke.color
              ..strokeWidth = stroke.baseWidth
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..style = PaintingStyle.stroke;

        final path = Path();
        bool isFirst = true;

        for (final point in stroke.points) {
          if (isFirst) {
            path.moveTo(point.position.dx, point.position.dy);
            isFirst = false;
          } else {
            path.lineTo(point.position.dx, point.position.dy);
          }
        }

        canvas.drawPath(path, strokePaint);
      }

      canvas.restore();
    }

    canvas.restore();
  }

  List<double> _getColorMatrix() {
    final b = brightness * 255;
    final c = contrast + 1.0;
    final t = (1.0 - c) / 2.0 * 255;
    final s = saturation + 1.0;

    const lumR = 0.3086;
    const lumG = 0.6094;
    const lumB = 0.0820;

    final sr = (1 - s) * lumR;
    final sg = (1 - s) * lumG;
    final sb = (1 - s) * lumB;

    return [
      (sr + s) * c,
      sg * c,
      sb * c,
      0,
      b + t,
      sr * c,
      (sg + s) * c,
      sb * c,
      0,
      b + t,
      sr * c,
      sg * c,
      (sb + s) * c,
      0,
      b + t,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.rotation != rotation ||
      old.flipHorizontal != flipHorizontal ||
      old.flipVertical != flipVertical ||
      old.brightness != brightness ||
      old.contrast != contrast ||
      old.saturation != saturation ||
      old.opacity != opacity ||
      old.cropRect != cropRect ||
      old.drawingStrokes != drawingStrokes;
}
