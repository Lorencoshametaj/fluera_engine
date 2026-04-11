import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/color_manager.dart';
import '../../core/color/color_blindness_simulator.dart';
import '../../core/color/color_palette_store.dart';
import '../../utils/key_value_store.dart';

// =============================================================================
// 🎨 PRO COLOR PICKER — Professional bottom-sheet color picker
//
// 4 tabs: Disc (HSB wheel), Sliders (HSB/RGB/Hex), Palettes, Harmony
// Features: compare bar, eyedropper, color blindness, copy hex, live preview
// =============================================================================

/// Shows the ProColorPicker as a modal bottom sheet.
///
/// Returns the selected [Color] or null if dismissed.
Future<Color?> showProColorPicker({
  required BuildContext context,
  required Color currentColor,
  List<Color> colorHistory = const [],
  VoidCallback? onEyedropperRequested,
}) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (ctx) => ProColorPicker(
          currentColor: currentColor,
          colorHistory: colorHistory,
          onEyedropperRequested: () {
            Navigator.pop(ctx);
            onEyedropperRequested?.call();
          },
          onColorSelected: (c) => Navigator.pop(ctx, c),
        ),
  );
}

/// Professional color picker with 4 tabs.
class ProColorPicker extends StatefulWidget {
  final Color currentColor;
  final List<Color> colorHistory;
  final ValueChanged<Color> onColorSelected;
  final VoidCallback? onEyedropperRequested;

  const ProColorPicker({
    super.key,
    required this.currentColor,
    this.colorHistory = const [],
    required this.onColorSelected,
    this.onEyedropperRequested,
  });

  @override
  State<ProColorPicker> createState() => _ProColorPickerState();
}

class _ProColorPickerState extends State<ProColorPicker>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late HSVColor _hsv;
  late Color _originalColor;

  // Slider mode toggle
  _SliderMode _sliderMode = _SliderMode.hsb;

  // Harmony mode
  _HarmonyMode _harmonyMode = _HarmonyMode.complementary;

  // Color blindness simulation
  bool _showCvdPreview = false;

  // P3 gamut mode
  bool _isP3Mode = false;
  late final bool _deviceSupportsP3;

  // Hex input
  final TextEditingController _hexController = TextEditingController();
  final FocusNode _hexFocus = FocusNode();

  // Drag state for haptic throttling
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _hsv = HSVColor.fromColor(widget.currentColor);
    _originalColor = widget.currentColor;
    _hexController.text = _colorToHex(_hsv.toColor());
    _deviceSupportsP3 = ColorManager.isWideGamutSupported;
    _isP3Mode = widget.currentColor.colorSpace == ui.ColorSpace.displayP3;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hexController.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  void _updateColor(HSVColor hsv) {
    setState(() => _hsv = hsv);
    _hexController.text = _colorToHex(hsv.toColor());
  }

  Color get _currentColor => _hsv.toColor();

  static String _colorToHex(Color c) {
    final r = (c.r * 255).round().clamp(0, 255);
    final g = (c.g * 255).round().clamp(0, 255);
    final b = (c.b * 255).round().clamp(0, 255);
    return '${r.toRadixString(16).padLeft(2, '0')}'
            '${g.toRadixString(16).padLeft(2, '0')}'
            '${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  static Color? _hexToColor(String hex) {
    final clean = hex.replaceFirst('#', '').trim();
    if (clean.length != 6 && clean.length != 8) return null;
    final value = int.tryParse(clean, radix: 16);
    if (value == null) return null;
    if (clean.length == 6) {
      return Color((0xFF << 24) | value);
    }
    return Color(value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle bar ──
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Top bar: compare + color name + actions ──
            _buildTopBar(cs, isDark),

            // ── Tab bar ──
            TabBar(
              controller: _tabController,
              isScrollable: false,
              labelColor: cs.primary,
              unselectedLabelColor: cs.onSurface.withValues(alpha: 0.5),
              indicatorColor: cs.primary,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              dividerHeight: 0,
              tabs: const [
                Tab(
                  text: 'Disc',
                  icon: Icon(Icons.radio_button_unchecked, size: 16),
                ),
                Tab(text: 'Sliders', icon: Icon(Icons.tune_rounded, size: 16)),
                Tab(
                  text: 'Palettes',
                  icon: Icon(Icons.grid_view_rounded, size: 16),
                ),
                Tab(
                  text: 'Harmony',
                  icon: Icon(Icons.auto_awesome_rounded, size: 16),
                ),
              ],
            ),

            // ── Tab content ──
            Flexible(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDiscTab(isDark),
                  _buildSlidersTab(cs, isDark),
                  _buildPalettesTab(cs, isDark),
                  _buildHarmonyTab(cs, isDark),
                ],
              ),
            ),

            // ── Bottom action bar ──
            _buildBottomBar(cs, isDark),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TOP BAR — compare swatch + color name + hex + copy + eyedropper + CVD
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildTopBar(ColorScheme cs, bool isDark) {
    final colorName = ColorManager.colorName(_currentColor);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Compare swatches (side by side with transition arrow)
          _CompareBox(color: _originalColor, label: 'Before'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: cs.onSurface.withValues(alpha: 0.25),
            ),
          ),
          _CompareBox(color: _currentColor, label: 'After'),

          const SizedBox(width: 12),

          // Color name + hex
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  colorName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '#${_colorToHex(_currentColor)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                        letterSpacing: 0.8,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Copy hex button
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: '#${_colorToHex(_currentColor)}'),
                        );
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Copied #${_colorToHex(_currentColor)}',
                            ),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                            width: 200,
                          ),
                        );
                      },
                      child: Icon(
                        Icons.copy_rounded,
                        size: 12,
                        color: cs.onSurface.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // P3/sRGB gamut toggle
          if (_deviceSupportsP3)
            _TopBarAction(
              icon: Icons.hdr_strong_rounded,
              isActive: _isP3Mode,
              activeColor: const Color(0xFF00C853),
              tooltip: _isP3Mode ? 'Display P3 (wide gamut)' : 'sRGB',
              onTap: () => setState(() => _isP3Mode = !_isP3Mode),
            ),

          // CVD preview toggle
          _TopBarAction(
            icon: Icons.visibility_rounded,
            isActive: _showCvdPreview,
            activeColor: cs.primary,
            tooltip: 'Color blindness preview',
            onTap: () => setState(() => _showCvdPreview = !_showCvdPreview),
          ),

          // Eyedropper
          if (widget.onEyedropperRequested != null)
            _TopBarAction(
              icon: Icons.colorize_rounded,
              tooltip: 'Eyedropper',
              onTap: widget.onEyedropperRequested!,
            ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 1 — DISC (HSB Color Wheel)
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildDiscTab(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Color wheel
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final size = math.min(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return Center(
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Hue ring
                        CustomPaint(
                          size: Size(size, size),
                          painter: _HueRingPainter(
                            selectedHue: _hsv.hue,
                            ringWidth: size * 0.12,
                          ),
                        ),
                        // Hue ring gesture
                        GestureDetector(
                          onPanStart: (d) {
                            _isDragging = true;
                            HapticFeedback.selectionClick();
                            _onHueRingPan(d.localPosition, size);
                          },
                          onPanUpdate:
                              (d) => _onHueRingPan(d.localPosition, size),
                          onPanEnd: (_) => _isDragging = false,
                          child: SizedBox(width: size, height: size),
                        ),
                        // Inner SV square
                        Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.all(size * 0.16),
                            child: LayoutBuilder(
                              builder: (ctx, innerConstraints) {
                                final innerSize = math.min(
                                  innerConstraints.maxWidth,
                                  innerConstraints.maxHeight,
                                );
                                return Center(
                                  child: SizedBox(
                                    width: innerSize,
                                    height: innerSize,
                                    child: GestureDetector(
                                      onPanStart: (d) {
                                        _isDragging = true;
                                        HapticFeedback.selectionClick();
                                        _onSvPan(d.localPosition, innerSize);
                                      },
                                      onPanUpdate:
                                          (d) => _onSvPan(
                                            d.localPosition,
                                            innerSize,
                                          ),
                                      onPanEnd: (_) => _isDragging = false,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: CustomPaint(
                                          size: Size(innerSize, innerSize),
                                          painter: _SvSquarePainter(
                                            hue: _hsv.hue,
                                          ),
                                          child: Stack(
                                            children: [
                                              Positioned(
                                                left:
                                                    _hsv.saturation *
                                                        innerSize -
                                                    12,
                                                top:
                                                    (1 - _hsv.value) *
                                                        innerSize -
                                                    12,
                                                child: _ThumbIndicator(
                                                  color: _currentColor,
                                                  size: 24,
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

                        // Live preview swatch at center of ring
                        Positioned(
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (isDark
                                      ? Colors.black.withValues(alpha: 0.7)
                                      : Colors.white.withValues(alpha: 0.85)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'H:${_hsv.hue.round()}° S:${(_hsv.saturation * 100).round()}% B:${(_hsv.value * 100).round()}%',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Alpha slider with checkerboard
          _buildAlphaSlider(isDark),

          // CVD preview row
          if (_showCvdPreview) ...[
            const SizedBox(height: 8),
            _buildCvdPreviewRow(isDark),
          ],
        ],
      ),
    );
  }

  void _onHueRingPan(Offset local, double size) {
    final center = Offset(size / 2, size / 2);
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final angle = math.atan2(dy, dx);
    final hue = ((angle * 180 / math.pi) + 360) % 360;
    _updateColor(_hsv.withHue(hue));
  }

  void _onSvPan(Offset local, double size) {
    final s = (local.dx / size).clamp(0.0, 1.0);
    final v = (1 - local.dy / size).clamp(0.0, 1.0);
    _updateColor(_hsv.withSaturation(s).withValue(v));
  }

  Widget _buildAlphaSlider(bool isDark) {
    return Row(
      children: [
        Text(
          'α',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CustomPaint(
                painter: _CheckerboardPainter(),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _currentColor.withValues(alpha: 0.0),
                        _currentColor.withValues(alpha: 1.0),
                      ],
                    ),
                  ),
                  child: SliderTheme(
                    data: const SliderThemeData(
                      trackHeight: 0,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
                      overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: _hsv.alpha,
                      onChanged: (v) => _updateColor(_hsv.withAlpha(v)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            '${(_hsv.alpha * 100).round()}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildCvdPreviewRow(bool isDark) {
    const types = [
      ColorBlindnessType.protanopia,
      ColorBlindnessType.deuteranopia,
      ColorBlindnessType.tritanopia,
      ColorBlindnessType.achromatopsia,
    ];
    const sim = ColorBlindnessSimulator();
    final c = _currentColor;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final type = types[i];
          final simulated = sim.simulate(c.r, c.g, c.b, type);
          final simColor = Color.fromARGB(
            255,
            (simulated.r * 255).round().clamp(0, 255),
            (simulated.g * 255).round().clamp(0, 255),
            (simulated.b * 255).round().clamp(0, 255),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: simColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _cvdShortName(type),
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _cvdShortName(ColorBlindnessType t) => switch (t) {
    ColorBlindnessType.protanopia => 'Prot.',
    ColorBlindnessType.deuteranopia => 'Deut.',
    ColorBlindnessType.tritanopia => 'Trit.',
    ColorBlindnessType.achromatopsia => 'Achro.',
    ColorBlindnessType.normal => 'Norm.',
  };

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 2 — SLIDERS (HSB / RGB / Hex)
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildSlidersTab(ColorScheme cs, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Mode toggle
          SegmentedButton<_SliderMode>(
            segments: const [
              ButtonSegment(value: _SliderMode.hsb, label: Text('HSB')),
              ButtonSegment(value: _SliderMode.rgb, label: Text('RGB')),
              ButtonSegment(value: _SliderMode.hsl, label: Text('HSL')),
            ],
            selected: {_sliderMode},
            onSelectionChanged: (s) => setState(() => _sliderMode = s.first),
            style: SegmentedButton.styleFrom(
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),

          const SizedBox(height: 16),

          // Sliders
          if (_sliderMode == _SliderMode.hsb) ...[
            _GradientSlider(
              label: 'H',
              value: _hsv.hue / 360,
              gradient: LinearGradient(
                colors: List.generate(
                  7,
                  (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
                ),
              ),
              onChanged: (v) => _updateColor(_hsv.withHue(v * 360)),
              displayValue: '${_hsv.hue.round()}°',
            ),
            const SizedBox(height: 12),
            _GradientSlider(
              label: 'S',
              value: _hsv.saturation,
              gradient: LinearGradient(
                colors: [
                  HSVColor.fromAHSV(1, _hsv.hue, 0, _hsv.value).toColor(),
                  HSVColor.fromAHSV(1, _hsv.hue, 1, _hsv.value).toColor(),
                ],
              ),
              onChanged: (v) => _updateColor(_hsv.withSaturation(v)),
              displayValue: '${(_hsv.saturation * 100).round()}%',
            ),
            const SizedBox(height: 12),
            _GradientSlider(
              label: 'B',
              value: _hsv.value,
              gradient: LinearGradient(
                colors: [
                  HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 0).toColor(),
                  HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 1).toColor(),
                ],
              ),
              onChanged: (v) => _updateColor(_hsv.withValue(v)),
              displayValue: '${(_hsv.value * 100).round()}%',
            ),
          ] else if (_sliderMode == _SliderMode.rgb) ...[
            _GradientSlider(
              label: 'R',
              value: _currentColor.r,
              gradient: LinearGradient(
                colors: [
                  Color.fromARGB(
                    255,
                    0,
                    (_currentColor.g * 255).round(),
                    (_currentColor.b * 255).round(),
                  ),
                  Color.fromARGB(
                    255,
                    255,
                    (_currentColor.g * 255).round(),
                    (_currentColor.b * 255).round(),
                  ),
                ],
              ),
              onChanged:
                  (v) => _updateColor(
                    HSVColor.fromColor(
                      Color.fromARGB(
                        255,
                        (v * 255).round(),
                        (_currentColor.g * 255).round(),
                        (_currentColor.b * 255).round(),
                      ),
                    ),
                  ),
              displayValue: '${(_currentColor.r * 255).round()}',
            ),
            const SizedBox(height: 12),
            _GradientSlider(
              label: 'G',
              value: _currentColor.g,
              gradient: LinearGradient(
                colors: [
                  Color.fromARGB(
                    255,
                    (_currentColor.r * 255).round(),
                    0,
                    (_currentColor.b * 255).round(),
                  ),
                  Color.fromARGB(
                    255,
                    (_currentColor.r * 255).round(),
                    255,
                    (_currentColor.b * 255).round(),
                  ),
                ],
              ),
              onChanged:
                  (v) => _updateColor(
                    HSVColor.fromColor(
                      Color.fromARGB(
                        255,
                        (_currentColor.r * 255).round(),
                        (v * 255).round(),
                        (_currentColor.b * 255).round(),
                      ),
                    ),
                  ),
              displayValue: '${(_currentColor.g * 255).round()}',
            ),
            const SizedBox(height: 12),
            _GradientSlider(
              label: 'B',
              value: _currentColor.b,
              gradient: LinearGradient(
                colors: [
                  Color.fromARGB(
                    255,
                    (_currentColor.r * 255).round(),
                    (_currentColor.g * 255).round(),
                    0,
                  ),
                  Color.fromARGB(
                    255,
                    (_currentColor.r * 255).round(),
                    (_currentColor.g * 255).round(),
                    255,
                  ),
                ],
              ),
              onChanged:
                  (v) => _updateColor(
                    HSVColor.fromColor(
                      Color.fromARGB(
                        255,
                        (_currentColor.r * 255).round(),
                        (_currentColor.g * 255).round(),
                        (v * 255).round(),
                      ),
                    ),
                  ),
              displayValue: '${(_currentColor.b * 255).round()}',
            ),
          ] else if (_sliderMode == _SliderMode.hsl) ...[
            // ── HSL mode ──
            () {
              final hsl = HSLColor.fromColor(_currentColor);
              return Column(
                children: [
                  _GradientSlider(
                    label: 'H',
                    value: hsl.hue / 360,
                    gradient: LinearGradient(
                      colors: List.generate(
                        7,
                        (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
                      ),
                    ),
                    onChanged:
                        (v) => _updateColor(
                          HSVColor.fromColor(hsl.withHue(v * 360).toColor()),
                        ),
                    displayValue: '${hsl.hue.round()}°',
                  ),
                  const SizedBox(height: 12),
                  _GradientSlider(
                    label: 'S',
                    value: hsl.saturation,
                    gradient: LinearGradient(
                      colors: [
                        hsl.withSaturation(0).toColor(),
                        hsl.withSaturation(1).toColor(),
                      ],
                    ),
                    onChanged:
                        (v) => _updateColor(
                          HSVColor.fromColor(hsl.withSaturation(v).toColor()),
                        ),
                    displayValue: '${(hsl.saturation * 100).round()}%',
                  ),
                  const SizedBox(height: 12),
                  _GradientSlider(
                    label: 'L',
                    value: hsl.lightness,
                    gradient: LinearGradient(
                      colors: [
                        hsl.withLightness(0).toColor(),
                        hsl.withLightness(0.5).toColor(),
                        hsl.withLightness(1).toColor(),
                      ],
                    ),
                    onChanged:
                        (v) => _updateColor(
                          HSVColor.fromColor(hsl.withLightness(v).toColor()),
                        ),
                    displayValue: '${(hsl.lightness * 100).round()}%',
                  ),
                ],
              );
            }(),
          ],

          const SizedBox(height: 16),

          // Hex input row with copy button
          Row(
            children: [
              Text(
                '#',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _hexController,
                  focusNode: _hexFocus,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    letterSpacing: 1.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: cs.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: cs.primary, width: 1.5),
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Copy
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          tooltip: 'Copy hex',
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: '#${_hexController.text}'),
                            );
                            HapticFeedback.lightImpact();
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                        // Paste
                        IconButton(
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            size: 16,
                          ),
                          tooltip: 'Paste hex',
                          onPressed: _pasteHex,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onSubmitted: _applyHex,
                  onChanged: _applyHex,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          _buildAlphaSlider(isDark),
        ],
      ),
    );
  }

  void _applyHex(String value) {
    final c = _hexToColor(value);
    if (c != null) {
      _updateColor(HSVColor.fromColor(c).withAlpha(_hsv.alpha));
    }
  }

  Future<void> _pasteHex() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      final hex = data!.text!.replaceFirst('#', '').trim();
      if (hex.length == 6 || hex.length == 8) {
        _hexController.text = hex.substring(0, 6).toUpperCase();
        _applyHex(_hexController.text);
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 3 — PALETTES
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildPalettesTab(ColorScheme cs, bool isDark) {
    final store = ColorPaletteStore.withBuiltIns();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Color history
          if (widget.colorHistory.isNotEmpty) ...[
            _PaletteSectionHeader(label: 'Recent', isDark: isDark),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  widget.colorHistory
                      .map(
                        (c) => _PaletteSwatch(
                          color: c,
                          isSelected: c.toARGB32() == _currentColor.toARGB32(),
                          onTap: () => _updateColor(HSVColor.fromColor(c)),
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Built-in palettes
          for (final paletteId in store.paletteIds) ...[
            _PaletteSectionHeader(
              label: store.getPalette(paletteId)!.name,
              isDark: isDark,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  store.getPalette(paletteId)!.swatches.map((swatch) {
                    final c = Color.fromARGB(
                      255,
                      (swatch.r * 255).round().clamp(0, 255),
                      (swatch.g * 255).round().clamp(0, 255),
                      (swatch.b * 255).round().clamp(0, 255),
                    );
                    return _PaletteSwatch(
                      color: c,
                      isSelected: c.toARGB32() == _currentColor.toARGB32(),
                      onTap: () => _updateColor(HSVColor.fromColor(c)),
                      tooltip: swatch.name,
                    );
                  }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 4 — HARMONY
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildHarmonyTab(ColorScheme cs, bool isDark) {
    final harmonies = _getHarmonyColors();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Harmony mode selector
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  _HarmonyMode.values.map((mode) {
                    final isActive = mode == _harmonyMode;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(mode.label),
                        selected: isActive,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() => _harmonyMode = mode);
                        },
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w500,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // Harmony wheel visualization
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final size = math.min(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return Center(
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: CustomPaint(
                      painter: _HarmonyWheelPainter(
                        colors: harmonies,
                        hue: _hsv.hue,
                        ringWidth: size * 0.10,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Harmony colors row with hex codes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children:
                harmonies.map((c) {
                  final isBase = c.toARGB32() == _currentColor.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _updateColor(HSVColor.fromColor(c));
                    },
                    onLongPress: () {
                      // Copy harmony color hex on long press
                      Clipboard.setData(
                        ClipboardData(text: '#${_colorToHex(c)}'),
                      );
                      HapticFeedback.mediumImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied #${_colorToHex(c)}'),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                          width: 200,
                        ),
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isBase ? 52 : 42,
                      height: isBase ? 52 : 42,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              isBase
                                  ? cs.primary
                                  : (isDark ? Colors.white24 : Colors.black12),
                          width: isBase ? 2.5 : 1,
                        ),
                        boxShadow:
                            isBase
                                ? [
                                  BoxShadow(
                                    color: c.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  ),
                                ]
                                : null,
                      ),
                      child: Center(
                        child: Text(
                          '#${_colorToHex(c).substring(0, 3)}',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color:
                                c.computeLuminance() > 0.5
                                    ? Colors.black54
                                    : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  List<Color> _getHarmonyColors() {
    final base = _currentColor;
    return switch (_harmonyMode) {
      _HarmonyMode.complementary => [base, ColorManager.complementary(base)],
      _HarmonyMode.analogous => ColorManager.analogous(base),
      _HarmonyMode.triadic => ColorManager.triadic(base),
      _HarmonyMode.splitComplementary => ColorManager.splitComplementary(base),
      _HarmonyMode.tetradic => ColorManager.tetradic(base),
    };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // BOTTOM ACTION BAR
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildBottomBar(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                // Convert to P3 if in wide-gamut mode
                final output =
                    _isP3Mode
                        ? ColorManager.toDisplayP3(_currentColor)
                        : _currentColor;
                widget.onColorSelected(output);
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: cs.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Apply Color'),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ENUMS
// =============================================================================

enum _SliderMode { hsb, rgb, hsl }

enum _HarmonyMode {
  complementary('Compl.'),
  analogous('Analog.'),
  triadic('Triadic'),
  splitComplementary('Split'),
  tetradic('Tetrad.');

  final String label;
  const _HarmonyMode(this.label);
}

// =============================================================================
// SUPPORT WIDGETS
// =============================================================================

/// Top bar icon action button.
class _TopBarAction extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color? activeColor;
  final String tooltip;
  final VoidCallback onTap;

  const _TopBarAction({
    required this.icon,
    this.isActive = false,
    this.activeColor,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color:
            isActive
                ? (activeColor ?? cs.primary).withValues(alpha: 0.12)
                : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: 20,
              color:
                  isActive
                      ? (activeColor ?? cs.primary)
                      : cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compare color swatch (before/after).
class _CompareBox extends StatelessWidget {
  final Color color;
  final String label;
  const _CompareBox({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  Theme.of(context).brightness == Brightness.dark
                      ? Colors.white12
                      : Colors.black12,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }
}

/// Palette section header label.
class _PaletteSectionHeader extends StatelessWidget {
  final String label;
  final bool isDark;
  const _PaletteSectionHeader({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 3,
        height: 12,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
    ],
  );
}

/// Thumb indicator for the SV area.
class _ThumbIndicator extends StatelessWidget {
  final Color color;
  final double size;
  const _ThumbIndicator({required this.color, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

/// Gradient-backed slider row.
class _GradientSlider extends StatelessWidget {
  final String label;
  final double value;
  final LinearGradient gradient;
  final ValueChanged<double> onChanged;
  final String displayValue;

  const _GradientSlider({
    required this.label,
    required this.value,
    required this.gradient,
    required this.onChanged,
    required this.displayValue,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 0,
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                thumbColor: Colors.white,
                overlayColor: Colors.white.withValues(alpha: 0.2),
              ),
              child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            displayValue,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: isDark ? Colors.white54 : Colors.black45,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Palette swatch widget.
class _PaletteSwatch extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final String? tooltip;

  const _PaletteSwatch({
    required this.color,
    this.isSelected = false,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget swatch = GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: isSelected ? 34 : 30,
        height: isSelected ? 34 : 30,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? cs.primary : Colors.white24,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow:
              isSelected
                  ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ]
                  : null,
        ),
        child:
            isSelected
                ? Icon(
                  Icons.check,
                  size: 14,
                  color:
                      color.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white,
                )
                : null,
      ),
    );
    if (tooltip != null) {
      swatch = Tooltip(message: tooltip!, child: swatch);
    }
    return swatch;
  }
}

// =============================================================================
// PAINTERS
// =============================================================================

/// Checkerboard background for alpha visualization.
class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cellSize = 6.0;
    final light = Paint()..color = const Color(0xFFCCCCCC);
    final dark = Paint()..color = const Color(0xFF999999);

    for (double y = 0; y < size.height; y += cellSize) {
      for (double x = 0; x < size.width; x += cellSize) {
        final row = (y / cellSize).floor();
        final col = (x / cellSize).floor();
        canvas.drawRect(
          Rect.fromLTWH(x, y, cellSize, cellSize),
          (row + col) % 2 == 0 ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter old) => false;
}

/// Paints the outer hue ring with anti-aliasing.
class _HueRingPainter extends CustomPainter {
  final double selectedHue;
  final double ringWidth;

  _HueRingPainter({required this.selectedHue, required this.ringWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = math.min(size.width, size.height) / 2;

    // Draw hue ring with sweep gradient (anti-aliased)
    final gradient = SweepGradient(
      colors: List.generate(
        13,
        (i) => HSVColor.fromAHSV(1, (i * 30.0) % 360, 1, 1).toColor(),
      ),
    );

    final rect = Rect.fromCircle(center: center, radius: outerRadius);
    final paint =
        Paint()
          ..shader = gradient.createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth
          ..isAntiAlias = true;

    canvas.drawCircle(center, outerRadius - ringWidth / 2, paint);

    // Hue indicator
    final hueAngle = selectedHue * math.pi / 180 - math.pi / 2;
    final indicatorRadius = outerRadius - ringWidth / 2;
    final indicatorPos = Offset(
      center.dx + indicatorRadius * math.cos(hueAngle),
      center.dy + indicatorRadius * math.sin(hueAngle),
    );

    // Shadow
    canvas.drawCircle(
      indicatorPos,
      ringWidth / 2 + 3,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..isAntiAlias = true,
    );

    // White ring
    canvas.drawCircle(
      indicatorPos,
      ringWidth / 2 + 2,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..isAntiAlias = true,
    );

    // Color fill
    canvas.drawCircle(
      indicatorPos,
      ringWidth / 2 - 1,
      Paint()
        ..color = HSVColor.fromAHSV(1, selectedHue, 1, 1).toColor()
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_HueRingPainter old) => old.selectedHue != selectedHue;
}

/// Paints the inner SV square.
class _SvSquarePainter extends CustomPainter {
  final double hue;
  _SvSquarePainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // White → Hue (saturation)
    final satGradient = LinearGradient(
      colors: [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()],
    );
    canvas.drawRect(rect, Paint()..shader = satGradient.createShader(rect));
    // Transparent → Black (value)
    final valGradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    );
    canvas.drawRect(rect, Paint()..shader = valGradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_SvSquarePainter old) => old.hue != hue;
}

/// Paints the harmony wheel with color indicators.
class _HarmonyWheelPainter extends CustomPainter {
  final List<Color> colors;
  final double hue;
  final double ringWidth;

  _HarmonyWheelPainter({
    required this.colors,
    required this.hue,
    required this.ringWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = math.min(size.width, size.height) / 2;

    // Background hue ring (faded, anti-aliased)
    final gradient = SweepGradient(
      colors: List.generate(
        13,
        (i) => HSVColor.fromAHSV(0.35, (i * 30.0) % 360, 0.8, 0.9).toColor(),
      ),
    );
    final rect = Rect.fromCircle(center: center, radius: outerRadius);
    canvas.drawCircle(
      center,
      outerRadius - ringWidth / 2,
      Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..isAntiAlias = true,
    );

    // Draw lines between harmony colors
    final indicatorRadius = outerRadius - ringWidth / 2;
    final positions = <Offset>[];
    for (final c in colors) {
      final hsv = HSVColor.fromColor(c);
      final angle = hsv.hue * math.pi / 180 - math.pi / 2;
      positions.add(
        Offset(
          center.dx + indicatorRadius * math.cos(angle),
          center.dy + indicatorRadius * math.sin(angle),
        ),
      );
    }

    if (positions.length >= 2) {
      // Glow line
      final glowPaint =
          Paint()
            ..color = Colors.white.withValues(alpha: 0.1)
            ..strokeWidth = 4
            ..style = PaintingStyle.stroke
            ..isAntiAlias = true;
      final linePaint =
          Paint()
            ..color = Colors.white.withValues(alpha: 0.4)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke
            ..isAntiAlias = true;
      final path = Path()..moveTo(positions.first.dx, positions.first.dy);
      for (int i = 1; i < positions.length; i++) {
        path.lineTo(positions[i].dx, positions[i].dy);
      }
      path.close();
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, linePaint);
    }

    // Draw color indicators
    for (int i = 0; i < colors.length; i++) {
      final pos = positions[i];
      final isBase = i == 0;
      final r = isBase ? ringWidth * 0.7 : ringWidth * 0.55;

      // Shadow
      canvas.drawCircle(
        pos,
        r + 2,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2)
          ..isAntiAlias = true,
      );

      // White ring
      canvas.drawCircle(
        pos,
        r + 2,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..isAntiAlias = true,
      );

      // Color fill
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..color = colors[i]
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(_HarmonyWheelPainter old) =>
      old.hue != hue || old.colors.length != colors.length;
}
