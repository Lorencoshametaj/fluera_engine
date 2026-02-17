import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../l10n/nebula_localizations.dart';
import '../core/models/image_element.dart';
import '../drawing/models/pro_drawing_point.dart';

/// 🎨 IMAGE EDITOR DIALOG
/// Editor professionale per modificare immagini on the canvas
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

class _ImageEditorDialogState extends State<ImageEditorDialog> {
  late double _scale;
  late double _rotation;
  late double _brightness;
  late double _contrast;
  late double _saturation;
  late double _opacity;
  late bool _flipHorizontal;
  late bool _flipVertical;
  Rect? _cropRect; // Area di crop (0.0-1.0 relativo all'immagine)

  @override
  void initState() {
    super.initState();

    // 🎨 Debug: verifica strokes ricevuti

    // Initialize dai valori dell'elemento
    _scale = widget.imageElement.scale;
    _rotation = widget.imageElement.rotation;
    _brightness = widget.imageElement.brightness;
    _contrast = widget.imageElement.contrast;
    _saturation = widget.imageElement.saturation;
    _opacity = widget.imageElement.opacity;
    _flipHorizontal = widget.imageElement.flipHorizontal;
    _flipVertical = widget.imageElement.flipVertical;
    _cropRect = widget.imageElement.cropRect;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height * 0.85,
        constraints: const BoxConstraints(maxWidth: 600),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:  0.4),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            _buildHeader(isDark),

            // Image preview (FIXED - always visible)
            _buildPreview(isDark),

            // Controlli (scrollabili)
            Expanded(
              child: SingleChildScrollView(child: _buildControls(isDark)),
            ),

            // Actions
            _buildActions(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              isDark
                  ? [Colors.blue[900]!, Colors.blue[700]!]
                  : [Colors.blue[700]!, Colors.blue[500]!],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:  0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.auto_fix_high_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  NebulaLocalizations.of(context).proCanvas_professionalEditor,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  NebulaLocalizations.of(context).proCanvas_advancedImageEdit,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha:  0.9),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(bool isDark) {
    return Container(
      height: 280,
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:  0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
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

  Widget _buildControls(bool isDark) {
    final l10n = NebulaLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Sezione Transform
          _buildSection(l10n.proCanvas_transformations, isDark),
          _buildSlider(
            icon: Icons.rotate_right_rounded,
            label: l10n.proCanvas_rotation,
            value: _rotation,
            min: -3.14159,
            max: 3.14159,
            onChanged: (value) => setState(() => _rotation = value),
            valueText: '${(_rotation * 180 / 3.14159).toInt()}°',
            isDark: isDark,
          ),
          const SizedBox(height: 12),

          // Flip buttons
          Row(
            children: [
              Expanded(
                child: _buildFlipButton(
                  icon: Icons.flip_rounded,
                  label: NebulaLocalizations.of(context).proCanvas_flipH,
                  isActive: _flipHorizontal,
                  onTap:
                      () => setState(() => _flipHorizontal = !_flipHorizontal),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFlipButton(
                  icon: Icons.flip_rounded,
                  label: NebulaLocalizations.of(context).proCanvas_flipV,
                  isActive: _flipVertical,
                  onTap: () => setState(() => _flipVertical = !_flipVertical),
                  isDark: isDark,
                  rotate: true,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Crop button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openCropEditor(),
              icon: const Icon(Icons.crop_rounded),
              label: Text(
                _cropRect != null
                    ? l10n.proCanvas_editCrop
                    : l10n.proCanvas_cropImage,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? Colors.blue[300] : Colors.blue[700],
                side: BorderSide(
                  color: isDark ? Colors.blue[300]! : Colors.blue[700]!,
                  width: 2,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Reset crop button (se c'è un crop attivo)
          if (_cropRect != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => setState(() => _cropRect = null),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l10n.proCanvas_removeCrop),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Sezione Colori
          _buildSection(l10n.proCanvas_colorAdjustments, isDark),
          _buildSlider(
            icon: Icons.brightness_6_rounded,
            label: l10n.proCanvas_brightness,
            value: _brightness,
            min: -0.5,
            max: 0.5,
            onChanged: (value) => setState(() => _brightness = value),
            valueText:
                _brightness >= 0
                    ? '+${(_brightness * 100).toInt()}%'
                    : '${(_brightness * 100).toInt()}%',
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _buildSlider(
            icon: Icons.contrast_rounded,
            label: l10n.proCanvas_contrast,
            value: _contrast,
            min: -0.5,
            max: 0.5,
            onChanged: (value) => setState(() => _contrast = value),
            valueText:
                _contrast >= 0
                    ? '+${(_contrast * 100).toInt()}%'
                    : '${(_contrast * 100).toInt()}%',
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _buildSlider(
            icon: Icons.palette_rounded,
            label: l10n.proCanvas_saturation,
            value: _saturation,
            min: -1.0,
            max: 1.0,
            onChanged: (value) => setState(() => _saturation = value),
            valueText:
                _saturation >= 0
                    ? '+${(_saturation * 100).toInt()}%'
                    : '${(_saturation * 100).toInt()}%',
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _buildSlider(
            icon: Icons.opacity_rounded,
            label: l10n.proCanvas_opacity,
            value: _opacity,
            min: 0.1,
            max: 1.0,
            onChanged: (value) => setState(() => _opacity = value),
            valueText: '${(_opacity * 100).toInt()}%',
            isDark: isDark,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: isDark ? Colors.blue[400] : Colors.blue[700],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlipButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required bool isDark,
    bool rotate = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color:
              isActive
                  ? (isDark
                      ? Colors.blue[400]!.withValues(alpha:  0.2)
                      : Colors.blue[700]!.withValues(alpha:  0.1))
                  : (isDark ? Colors.grey[800] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isActive
                    ? (isDark ? Colors.blue[400]! : Colors.blue[700]!)
                    : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.rotate(
              angle: rotate ? 1.5708 : 0,
              child: Icon(
                icon,
                color:
                    isActive
                        ? (isDark ? Colors.blue[400] : Colors.blue[700])
                        : (isDark ? Colors.grey[400] : Colors.grey[600]),
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color:
                    isActive
                        ? (isDark ? Colors.blue[400] : Colors.blue[700])
                        : (isDark ? Colors.grey[400] : Colors.grey[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required Function(double) onChanged,
    required String valueText,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
            const Spacer(),
            Text(
              valueText,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.blue[400] : Colors.blue[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: isDark ? Colors.blue[400] : Colors.blue[700],
            inactiveTrackColor: isDark ? Colors.grey[800] : Colors.grey[300],
            thumbColor: isDark ? Colors.blue[400] : Colors.blue[700],
            overlayColor: (isDark ? Colors.blue[400] : Colors.blue[700])!
                .withValues(alpha:  0.2),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }

  Widget _buildActions(bool isDark) {
    final l10n = NebulaLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Delete button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onDelete();
              },
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(l10n.delete),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red[700],
                side: BorderSide(color: Colors.red[700]!),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Save button
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
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

                // 🎨 Debug: verifica strokes mantenuti

                widget.onSave(updated);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check_rounded),
              label: Text(l10n.save),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.blue[400] : Colors.blue[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens il crop editor
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
}

/// 🎯 CROP EDITOR DIALOG
/// Dialog interattivo per ritagliare l'immagine
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
    // Initialize crop rect (default 80% of the image al centro)
    _cropRect =
        widget.initialCropRect ?? const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha:  0.8),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha:  0.2)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.crop_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  NebulaLocalizations.of(context).proCanvas_cropImage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(NebulaLocalizations.of(context).cancel),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _cropRect),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: Text(NebulaLocalizations.of(context).apply),
                ),
              ],
            ),
          ),

          // Area crop interattiva
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanStart: (details) => _onPanStart(details, constraints),
                  onPanUpdate: (details) => _onPanUpdate(details, constraints),
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
                    ),
                  ),
                );
              },
            ),
          ),

          // Istruzioni
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha:  0.8),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha:  0.2)),
              ),
            ),
            child: Text(
              NebulaLocalizations.of(context).proCanvas_cropInstructions,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
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

    // Calculate position crop in pixel
    final cropPixelRect = Rect.fromLTRB(
      imageRect.left + _cropRect.left * imageRect.width,
      imageRect.top + _cropRect.top * imageRect.height,
      imageRect.left + _cropRect.right * imageRect.width,
      imageRect.top + _cropRect.bottom * imageRect.height,
    );

    const handleSize = 40.0;

    // Check handles agli angoli
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

    // Convert delta in coordinate normalizzate (0-1)
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
          break;
        case 'tr':
          _cropRect = Rect.fromLTRB(
            _cropRect.left,
            (_cropRect.top + dy).clamp(0.0, _cropRect.bottom - 0.1),
            (_cropRect.right + dx).clamp(_cropRect.left + 0.1, 1.0),
            _cropRect.bottom,
          );
          break;
        case 'bl':
          _cropRect = Rect.fromLTRB(
            (_cropRect.left + dx).clamp(0.0, _cropRect.right - 0.1),
            _cropRect.top,
            _cropRect.right,
            (_cropRect.bottom + dy).clamp(_cropRect.top + 0.1, 1.0),
          );
          break;
        case 'br':
          _cropRect = Rect.fromLTRB(
            _cropRect.left,
            _cropRect.top,
            (_cropRect.right + dx).clamp(_cropRect.left + 0.1, 1.0),
            (_cropRect.bottom + dy).clamp(_cropRect.top + 0.1, 1.0),
          );
          break;
        case 'center':
          final width = _cropRect.width;
          final height = _cropRect.height;
          var newLeft = _cropRect.left + dx;
          var newTop = _cropRect.top + dy;

          // Mantieni dentro i bordi
          if (newLeft < 0) newLeft = 0;
          if (newTop < 0) newTop = 0;
          if (newLeft + width > 1) newLeft = 1 - width;
          if (newTop + height > 1) newTop = 1 - height;

          _cropRect = Rect.fromLTWH(newLeft, newTop, width, height);
          break;
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

    final left = (constraints.maxWidth - width) / 2;
    final top = (constraints.maxHeight - height) / 2;

    return Rect.fromLTWH(left, top, width, height);
  }
}

/// Painter for the crop editor
class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect cropRect;

  _CropPainter({required this.image, required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate rect per fit contain
    final containerRatio = size.width / size.height;
    final imageRatio = image.width / image.height;

    double width, height, left, top;
    if (containerRatio > imageRatio) {
      height = size.height;
      width = height * imageRatio;
      left = (size.width - width) / 2;
      top = 0;
    } else {
      width = size.width;
      height = width / imageRatio;
      left = 0;
      top = (size.height - height) / 2;
    }

    final imageRect = Rect.fromLTWH(left, top, width, height);

    // Draw immagine
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint(),
    );

    // Overlay scuro fuori dal crop
    final cropPixelRect = Rect.fromLTRB(
      imageRect.left + cropRect.left * imageRect.width,
      imageRect.top + cropRect.top * imageRect.height,
      imageRect.left + cropRect.right * imageRect.width,
      imageRect.top + cropRect.bottom * imageRect.height,
    );

    final overlayPaint = Paint()..color = Colors.black.withValues(alpha:  0.6);

    // Top
    canvas.drawRect(
      Rect.fromLTRB(
        imageRect.left,
        imageRect.top,
        imageRect.right,
        cropPixelRect.top,
      ),
      overlayPaint,
    );
    // Bottom
    canvas.drawRect(
      Rect.fromLTRB(
        imageRect.left,
        cropPixelRect.bottom,
        imageRect.right,
        imageRect.bottom,
      ),
      overlayPaint,
    );
    // Left
    canvas.drawRect(
      Rect.fromLTRB(
        imageRect.left,
        cropPixelRect.top,
        cropPixelRect.left,
        cropPixelRect.bottom,
      ),
      overlayPaint,
    );
    // Right
    canvas.drawRect(
      Rect.fromLTRB(
        cropPixelRect.right,
        cropPixelRect.top,
        imageRect.right,
        cropPixelRect.bottom,
      ),
      overlayPaint,
    );

    // Bordo crop
    final borderPaint =
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
    canvas.drawRect(cropPixelRect, borderPaint);

    // Griglia 3x3
    final gridPaint =
        Paint()
          ..color = Colors.white.withValues(alpha:  0.5)
          ..strokeWidth = 1;

    for (var i = 1; i < 3; i++) {
      final x = cropPixelRect.left + (cropPixelRect.width * i / 3);
      canvas.drawLine(
        Offset(x, cropPixelRect.top),
        Offset(x, cropPixelRect.bottom),
        gridPaint,
      );

      final y = cropPixelRect.top + (cropPixelRect.height * i / 3);
      canvas.drawLine(
        Offset(cropPixelRect.left, y),
        Offset(cropPixelRect.right, y),
        gridPaint,
      );
    }

    // Handle agli angoli
    final handlePaint = Paint()..color = Colors.white;
    final handleSize = 12.0;

    void drawHandle(Offset center) {
      canvas.drawCircle(center, handleSize / 2, handlePaint);
      canvas.drawCircle(
        center,
        handleSize / 2,
        Paint()
          ..color = Colors.blue
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    drawHandle(cropPixelRect.topLeft);
    drawHandle(cropPixelRect.topRight);
    drawHandle(cropPixelRect.bottomLeft);
    drawHandle(cropPixelRect.bottomRight);
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.cropRect != cropRect;
}

/// 🎨 PREVIEW PAINTER
/// Painter for the preview with all effects applied
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

    // Centro of the canvas
    final center = Offset(size.width / 2, size.height / 2);
    canvas.translate(center.dx, center.dy);

    // Rotazione
    if (rotation != 0) {
      canvas.rotate(rotation);
    }

    // Flip
    if (flipHorizontal || flipVertical) {
      canvas.scale(flipHorizontal ? -1.0 : 1.0, flipVertical ? -1.0 : 1.0);
    }

    // Determina area sorgente (con crop if present)
    Rect srcRect;
    double displayWidth, displayHeight;

    if (cropRect != null) {
      // With crop: use only the cropped area
      final imgWidth = image.width.toDouble();
      final imgHeight = image.height.toDouble();
      srcRect = Rect.fromLTRB(
        cropRect!.left * imgWidth,
        cropRect!.top * imgHeight,
        cropRect!.right * imgWidth,
        cropRect!.bottom * imgHeight,
      );
      displayWidth = srcRect.width;
      displayHeight = srcRect.height;
    } else {
      // Without crop: usa l'immagine intera
      srcRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      displayWidth = image.width.toDouble();
      displayHeight = image.height.toDouble();
    }

    // Scala per fit contain nel preview
    final containerRatio = size.width / size.height;
    final imageRatio = displayWidth / displayHeight;

    double scale;
    if (containerRatio > imageRatio) {
      scale = size.height / displayHeight;
    } else {
      scale = size.width / displayWidth;
    }

    // Area destinazione (centrata e scalata)
    final scaledWidth = displayWidth * scale;
    final scaledHeight = displayHeight * scale;
    final dstRect = Rect.fromCenter(
      center: Offset.zero,
      width: scaledWidth,
      height: scaledHeight,
    );

    // Create paint with all filters
    final paint = Paint();

    // Opacity
    if (opacity < 1.0) {
      paint.color = Color.fromRGBO(255, 255, 255, opacity);
      paint.blendMode = BlendMode.dstIn;
    }

    // Color filters
    if (brightness != 0 || contrast != 0 || saturation != 0) {
      paint.colorFilter = ColorFilter.matrix(_getColorMatrix());
    }

    // Draw immagine
    canvas.drawImageRect(image, srcRect, dstRect, paint);

    // 🎨 Draw strokes sopra l'immagine
    if (drawingStrokes.isNotEmpty) {
      // Strokes are in local image coordinates (center = 0,0)
      // The canvas is already centrato, quindi possiamo disegnarli direttamente
      canvas.save();

      // Applica la scala of the image
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
          // Gli strokes are already in coordinate relative al centro of the image
          final offset = point.position;

          if (isFirst) {
            path.moveTo(offset.dx, offset.dy);
            isFirst = false;
          } else {
            path.lineTo(offset.dx, offset.dy);
          }
        }

        canvas.drawPath(path, strokePaint);
      }

      canvas.restore();
    }

    canvas.restore();
  }

  List<double> _getColorMatrix() {
    // Brightness
    final b = brightness * 255;

    // Contrast
    final c = contrast + 1.0;
    final t = (1.0 - c) / 2.0 * 255;

    // Saturation
    final s = saturation + 1.0;
    final lumR = 0.3086;
    final lumG = 0.6094;
    final lumB = 0.0820;
    final sr = (1 - s) * lumR;
    final sg = (1 - s) * lumG;
    final sb = (1 - s) * lumB;

    // Color matrix 4x5 (20 elements)
    return [
      (sr + s) * c, sg * c, sb * c, 0, b + t, // R
      sr * c, (sg + s) * c, sb * c, 0, b + t, // G
      sr * c, sg * c, (sb + s) * c, 0, b + t, // B
      0, 0, 0, 1, 0, // A
    ];
  }

  @override
  bool shouldRepaint(_PreviewPainter oldDelegate) {
    return oldDelegate.rotation != rotation ||
        oldDelegate.flipHorizontal != flipHorizontal ||
        oldDelegate.flipVertical != flipVertical ||
        oldDelegate.brightness != brightness ||
        oldDelegate.contrast != contrast ||
        oldDelegate.saturation != saturation ||
        oldDelegate.opacity != opacity ||
        oldDelegate.cropRect != cropRect ||
        oldDelegate.drawingStrokes != drawingStrokes;
  }
}
