import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../l10n/nebula_localizations.dart';
import '../core/models/image_element.dart';
import 'image_editor_models.dart';
import 'image_editor_preview.dart';
import 'image_editor_crop.dart';

// ============================================================================
// 🎨 IMAGE EDITOR DIALOG — Material Design 3  (Enterprise Quality)
//
// Entry point for the professional image editor. State, undo/redo, and
// keyboard shortcuts live here. Tabs, painters, and crop are decomposed
// into sibling files.
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
  // Editable state
  late double _scale, _rotation, _brightness, _contrast;
  late double _saturation, _opacity, _vignette, _hueShift, _temperature;
  late bool _flipH, _flipV;
  Rect? _cropRect;

  late final TabController _tabController;
  final FocusNode _focusNode = FocusNode(); // Feature 5: keyboard

  bool _showOriginal = false;
  String _activeFilterId = 'none';
  int _previewKey = 0;

  // Feature 6: Undo/Redo
  final List<EditorSnapshot> _undoStack = [];
  final List<EditorSnapshot> _redoStack = [];

  @override
  void initState() {
    super.initState();
    final e = widget.imageElement;
    _scale = e.scale;
    _rotation = e.rotation;
    _brightness = e.brightness;
    _contrast = e.contrast;
    _saturation = e.saturation;
    _opacity = e.opacity;
    _vignette = e.vignette;
    _hueShift = e.hueShift;
    _temperature = e.temperature;
    _flipH = e.flipHorizontal;
    _flipV = e.flipVertical;
    _cropRect = e.cropRect;
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // State helpers
  // --------------------------------------------------------------------------

  bool get _hasChanges {
    final e = widget.imageElement;
    return _scale != e.scale ||
        _rotation != e.rotation ||
        _brightness != e.brightness ||
        _contrast != e.contrast ||
        _saturation != e.saturation ||
        _opacity != e.opacity ||
        _vignette != e.vignette ||
        _hueShift != e.hueShift ||
        _temperature != e.temperature ||
        _flipH != e.flipHorizontal ||
        _flipV != e.flipVertical ||
        _cropRect != e.cropRect;
  }

  EditorSnapshot _snapshot() => EditorSnapshot(
    rotation: _rotation,
    brightness: _brightness,
    contrast: _contrast,
    saturation: _saturation,
    opacity: _opacity,
    vignette: _vignette,
    hueShift: _hueShift,
    temperature: _temperature,
    flipH: _flipH,
    flipV: _flipV,
    cropRect: _cropRect,
    filterId: _activeFilterId,
  );

  void _pushUndo() {
    _undoStack.add(_snapshot());
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snapshot());
    _restoreSnapshot(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snapshot());
    _restoreSnapshot(_redoStack.removeLast());
  }

  void _restoreSnapshot(EditorSnapshot s) {
    setState(() {
      _rotation = s.rotation;
      _brightness = s.brightness;
      _contrast = s.contrast;
      _saturation = s.saturation;
      _opacity = s.opacity;
      _vignette = s.vignette;
      _hueShift = s.hueShift;
      _temperature = s.temperature;
      _flipH = s.flipH;
      _flipV = s.flipV;
      _cropRect = s.cropRect;
      _activeFilterId = s.filterId;
      _previewKey++;
    });
    HapticFeedback.lightImpact();
  }

  void _resetAll() {
    _pushUndo();
    setState(() {
      // Note: _scale is not reset — it's set via canvas pinch, not editor sliders.
      _rotation = 0;
      _brightness = 0;
      _contrast = 0;
      _saturation = 0;
      _opacity = 1.0;
      _vignette = 0;
      _hueShift = 0;
      _temperature = 0;
      _flipH = false;
      _flipV = false;
      _cropRect = null;
      _activeFilterId = 'none';
      _previewKey++;
    });
    HapticFeedback.mediumImpact();
  }

  void _applyFilter(FilterPreset filter) {
    if (filter.id == _activeFilterId) return;
    _pushUndo();
    setState(() {
      _activeFilterId = filter.id;
      if (filter.id == 'none') {
        _brightness = 0;
        _contrast = 0;
        _saturation = 0;
      } else {
        _brightness = filter.brightness;
        _contrast = filter.contrast;
        _saturation = filter.saturation;
      }
      _previewKey++;
    });
    HapticFeedback.lightImpact();
  }

  // Feature 2: Confirm before discard
  Future<void> _handleClose() async {
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = NebulaLocalizations.of(ctx);
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(l10n.proCanvas_discardChanges),
          content: Text(l10n.proCanvas_discardChangesMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: cs.error),
              child: Text(l10n.proCanvas_discardConfirm),
            ),
          ],
        );
      },
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  // Feature 5: Keyboard shortcuts
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      _undo();
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyY) {
      _redo();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
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
                  children: [
                    _buildTransformTab(cs, tt),
                    _buildColorTab(cs, tt),
                    _buildFiltersTab(cs, tt),
                  ],
                ),
              ),
              _buildActions(cs, tt),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Header — with image info, undo/redo buttons
  // --------------------------------------------------------------------------

  Widget _buildHeader(ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 8, 4),
      child: Row(
        children: [
          Icon(Icons.auto_fix_high_rounded, color: cs.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  NebulaLocalizations.of(context).proCanvas_professionalEditor,
                  style: tt.titleLarge?.copyWith(color: cs.onSurface),
                ),
                Text(
                  '${widget.image.width} × ${widget.image.height}',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _undoStack.isNotEmpty ? _undo : null,
            icon: const Icon(Icons.undo_rounded, size: 20),
            tooltip: 'Undo (Ctrl+Z)',
            style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          ),
          IconButton(
            onPressed: _redoStack.isNotEmpty ? _redo : null,
            icon: const Icon(Icons.redo_rounded, size: 20),
            tooltip: 'Redo (Ctrl+Y)',
            style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          ),
          if (_hasChanges)
            IconButton(
              onPressed: _resetAll,
              icon: const Icon(Icons.restart_alt_rounded),
              tooltip: 'Reset all',
              style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
            ),
          IconButton(
            onPressed: _handleClose,
            icon: const Icon(Icons.close_rounded),
            style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Preview — with before/after toggle + animated transitions
  // --------------------------------------------------------------------------

  Widget _buildPreview(ColorScheme cs) {
    final l10n = NebulaLocalizations.of(context);
    return Column(
      children: [
        Container(
          height: 220,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: CustomPaint(
                key: ValueKey<int>(_previewKey),
                painter: PreviewPainter(
                  image: widget.image,
                  rotation: _showOriginal ? 0 : _rotation,
                  flipHorizontal: _showOriginal ? false : _flipH,
                  flipVertical: _showOriginal ? false : _flipV,
                  brightness: _showOriginal ? 0 : _brightness,
                  contrast: _showOriginal ? 0 : _contrast,
                  saturation: _showOriginal ? 0 : _saturation,
                  opacity: _showOriginal ? 1.0 : _opacity,
                  vignette: _showOriginal ? 0 : _vignette,
                  hueShift: _showOriginal ? 0 : _hueShift,
                  temperature: _showOriginal ? 0 : _temperature,
                  cropRect: _showOriginal ? null : _cropRect,
                  drawingStrokes: widget.imageElement.drawingStrokes,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        if (_hasChanges)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: TextButton.icon(
              onPressed: () => setState(() => _showOriginal = !_showOriginal),
              icon: Icon(
                _showOriginal
                    ? Icons.visibility_off_rounded
                    : Icons.compare_rounded,
                size: 18,
              ),
              label: Text(
                _showOriginal
                    ? l10n.proCanvas_filterNone
                    : l10n.proCanvas_beforeAfter,
                style: const TextStyle(fontSize: 13),
              ),
              style: TextButton.styleFrom(
                foregroundColor:
                    _showOriginal ? cs.primary : cs.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
    final l10n = NebulaLocalizations.of(context);
    return TabBar(
      controller: _tabController,
      labelColor: cs.primary,
      unselectedLabelColor: cs.onSurfaceVariant,
      indicatorColor: cs.primary,
      dividerColor: cs.outlineVariant.withValues(alpha: 0.5),
      labelStyle: const TextStyle(fontSize: 12),
      tabs: [
        Tab(
          icon: const Icon(Icons.transform_rounded, size: 20),
          text: l10n.proCanvas_transformations,
        ),
        Tab(
          icon: const Icon(Icons.tune_rounded, size: 20),
          text: l10n.proCanvas_colorAdjustments,
        ),
        Tab(
          icon: const Icon(Icons.auto_awesome_rounded, size: 20),
          text: l10n.proCanvas_filters,
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Transform Tab
  // --------------------------------------------------------------------------

  Widget _buildTransformTab(ColorScheme cs, TextTheme tt) {
    final l10n = NebulaLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      children: [
        _slider(
          cs,
          tt,
          Icons.rotate_right_rounded,
          l10n.proCanvas_rotation,
          _rotation,
          -math.pi,
          math.pi,
          0,
          '${(_rotation * 180 / math.pi).toInt()}°',
          (v) => setState(() => _rotation = v),
        ),
        const SizedBox(height: 8),
        // Quick rotation presets
        Row(
          children: [
            _quickRotateBtn(cs, 0, '0°'),
            const SizedBox(width: 8),
            _quickRotateBtn(cs, math.pi / 2, '90°'),
            const SizedBox(width: 8),
            _quickRotateBtn(cs, math.pi, '180°'),
            const SizedBox(width: 8),
            _quickRotateBtn(cs, -math.pi / 2, '270°'),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Flip',
          style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              selected: _flipH,
              label: Text(l10n.proCanvas_flipH),
              avatar: const Icon(Icons.flip_rounded, size: 18),
              onSelected: (_) {
                _pushUndo();
                setState(() => _flipH = !_flipH);
                HapticFeedback.lightImpact();
              },
            ),
            FilterChip(
              selected: _flipV,
              label: Text(l10n.proCanvas_flipV),
              avatar: Transform.rotate(
                angle: math.pi / 2,
                child: const Icon(Icons.flip_rounded, size: 18),
              ),
              onSelected: (_) {
                _pushUndo();
                setState(() => _flipV = !_flipV);
                HapticFeedback.lightImpact();
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
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
            onPressed: () {
              _pushUndo();
              setState(() => _cropRect = null);
            },
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(l10n.proCanvas_removeCrop),
            style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _quickRotateBtn(ColorScheme cs, double angle, String label) {
    final active = (_rotation - angle).abs() < 0.01;
    return Expanded(
      child: FilledButton.tonal(
        onPressed: () {
          _pushUndo();
          setState(() => _rotation = angle);
          HapticFeedback.lightImpact();
        },
        style: FilledButton.styleFrom(
          backgroundColor:
              active ? cs.primaryContainer : cs.surfaceContainerHighest,
          foregroundColor: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(vertical: 8),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Color Tab
  // --------------------------------------------------------------------------

  Widget _buildColorTab(ColorScheme cs, TextTheme tt) {
    final l10n = NebulaLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      children: [
        _slider(
          cs,
          tt,
          Icons.brightness_6_rounded,
          l10n.proCanvas_brightness,
          _brightness,
          -0.5,
          0.5,
          0,
          _pct(_brightness),
          (v) => setState(() {
            _brightness = v;
            _activeFilterId = 'none';
          }),
        ),
        const SizedBox(height: 12),
        _slider(
          cs,
          tt,
          Icons.contrast_rounded,
          l10n.proCanvas_contrast,
          _contrast,
          -0.5,
          0.5,
          0,
          _pct(_contrast),
          (v) => setState(() {
            _contrast = v;
            _activeFilterId = 'none';
          }),
        ),
        const SizedBox(height: 12),
        _slider(
          cs,
          tt,
          Icons.palette_rounded,
          l10n.proCanvas_saturation,
          _saturation,
          -1,
          1,
          0,
          _pct(_saturation),
          (v) => setState(() {
            _saturation = v;
            _activeFilterId = 'none';
          }),
        ),
        const SizedBox(height: 12),
        _slider(
          cs,
          tt,
          Icons.opacity_rounded,
          l10n.proCanvas_opacity,
          _opacity,
          0.1,
          1,
          1,
          '${(_opacity * 100).toInt()}%',
          (v) => setState(() => _opacity = v),
        ),
        const SizedBox(height: 12),
        _slider(
          cs,
          tt,
          Icons.vignette_rounded,
          l10n.proCanvas_vignette,
          _vignette,
          0,
          1,
          0,
          '${(_vignette * 100).toInt()}%',
          (v) => setState(() => _vignette = v),
        ),
        const SizedBox(height: 12),
        _slider(
          cs,
          tt,
          Icons.color_lens_rounded,
          l10n.proCanvas_hueShift,
          _hueShift,
          -1,
          1,
          0,
          _pct(_hueShift),
          (v) => setState(() {
            _hueShift = v;
            _activeFilterId = 'none';
          }),
        ),
        const SizedBox(height: 12),
        _slider(
          cs,
          tt,
          Icons.thermostat_rounded,
          l10n.proCanvas_temperature,
          _temperature,
          -1,
          1,
          0,
          _pct(_temperature),
          (v) => setState(() {
            _temperature = v;
            _activeFilterId = 'none';
          }),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Filters Tab — cached thumbnails via RepaintBoundary
  // --------------------------------------------------------------------------

  Widget _buildFiltersTab(ColorScheme cs, TextTheme tt) {
    final l10n = NebulaLocalizations.of(context);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: kFilterPresets.length,
      itemBuilder: (_, i) {
        final f = kFilterPresets[i];
        final active = _activeFilterId == f.id;
        return GestureDetector(
          onTap: () => _applyFilter(f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: active ? cs.primaryContainer : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active ? cs.primary : cs.outlineVariant,
                width: active ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Feature 3: RepaintBoundary for cached thumbnails
                RepaintBoundary(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: cs.surfaceContainerLowest,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CustomPaint(
                        painter: PreviewPainter(
                          image: widget.image,
                          rotation: 0,
                          flipHorizontal: false,
                          flipVertical: false,
                          brightness: f.brightness,
                          contrast: f.contrast,
                          saturation: f.saturation,
                          opacity: 1.0,
                          drawingStrokes: const [],
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  f.labelFn(l10n),
                  style: tt.labelMedium?.copyWith(
                    color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // Slider Row — with double-tap reset + center haptics (Feature 4)
  // --------------------------------------------------------------------------

  Widget _slider(
    ColorScheme cs,
    TextTheme tt,
    IconData icon,
    String label,
    double value,
    double min,
    double max,
    double def,
    String text,
    ValueChanged<double> onChanged,
  ) {
    final isDef = (value - def).abs() < 0.001;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(label, style: tt.labelLarge?.copyWith(color: cs.onSurface)),
            const Spacer(),
            GestureDetector(
              onDoubleTap:
                  isDef
                      ? null
                      : () {
                        _pushUndo();
                        onChanged(def);
                        HapticFeedback.lightImpact();
                      },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:
                      isDef ? cs.surfaceContainerHighest : cs.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  text,
                  style: tt.labelMedium?.copyWith(
                    color: isDef ? cs.onSurfaceVariant : cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        _HapticSlider(
          value: value,
          min: min,
          max: max,
          defaultValue: def,
          onChangeStart: () => _pushUndo(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Actions Footer — with confirm-before-discard
  // --------------------------------------------------------------------------

  Widget _buildActions(ColorScheme cs, TextTheme tt) {
    final l10n = NebulaLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
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
          TextButton(onPressed: _handleClose, child: Text(l10n.cancel)),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () {
              widget.onSave(
                widget.imageElement.copyWith(
                  scale: _scale,
                  rotation: _rotation,
                  brightness: _brightness,
                  contrast: _contrast,
                  saturation: _saturation,
                  opacity: _opacity,
                  vignette: _vignette,
                  hueShift: _hueShift,
                  temperature: _temperature,
                  flipHorizontal: _flipH,
                  flipVertical: _flipV,
                  cropRect: _cropRect,
                  clearCrop:
                      _cropRect == null && widget.imageElement.cropRect != null,
                ),
              );
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
  // Crop Editor — with undo push (Feature 6)
  // --------------------------------------------------------------------------

  Future<void> _openCropEditor() async {
    _pushUndo(); // Feature 6: Crop undo
    final result = await showDialog<Rect?>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) =>
              CropEditorDialog(image: widget.image, initialCropRect: _cropRect),
    );
    if (result != null) {
      setState(() => _cropRect = result);
    } else {
      // User cancelled crop — restore undo
      if (_undoStack.isNotEmpty) {
        _undoStack.removeLast();
      }
    }
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  String _pct(double v) {
    final p = (v * 100).toInt();
    return p >= 0 ? '+$p%' : '$p%';
  }
}

// =============================================================================
// Stateful slider that tracks its own previous value for per-slider haptics.
// Prevents ghost selectionClick when jumping between different sliders.
// =============================================================================

class _HapticSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final VoidCallback onChangeStart;
  final ValueChanged<double> onChanged;

  const _HapticSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.onChangeStart,
    required this.onChanged,
  });

  @override
  State<_HapticSlider> createState() => _HapticSliderState();
}

class _HapticSliderState extends State<_HapticSlider> {
  double _prevValue = 0;

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: widget.value,
      min: widget.min,
      max: widget.max,
      onChangeStart: (_) {
        widget.onChangeStart();
        _prevValue = widget.value;
      },
      onChanged: (v) {
        // Haptic feedback when crossing the default/zero value
        final def = widget.defaultValue;
        if (def >= widget.min && def <= widget.max) {
          final crossed =
              (_prevValue < def && v >= def) || (_prevValue > def && v <= def);
          if (crossed) HapticFeedback.selectionClick();
        }
        _prevValue = v;
        widget.onChanged(v);
      },
    );
  }
}
