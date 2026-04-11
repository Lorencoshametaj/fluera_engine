import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/editing/adjustment_layer.dart';
import '../fluera_layer_controller.dart';
import '../../core/models/canvas_layer.dart';

/// 🎨 Adjustment panel — bottom sheet with sliders for layer color adjustments.
///
/// Features:
/// - Continuous sliders for brightness, contrast, saturation, exposure, gamma
/// - Toggle controls for invert, threshold
/// - Preset filters (Vintage, B&W, Dramatic, Warm, Cool, Faded, High Key)
/// - Real-time GPU preview via [FlueraLayerController.updateAdjustmentLayer]
/// - **Debounced** slider updates (16ms = 1 frame budget)
/// - **Double-tap** any slider label to reset it to neutral
/// - **Before/After** hold-to-compare toggle
/// - **Smooth spring** animation on sheet open
class AdjustmentPanelDialog extends StatefulWidget {
  final FlueraLayerController controller;
  final CanvasLayer layer;
  final bool isDark;

  const AdjustmentPanelDialog({
    super.key,
    required this.controller,
    required this.layer,
    this.isDark = true,
  });

  /// Show the adjustment panel as a modal bottom sheet with spring animation.
  static void show(
    BuildContext context, {
    required FlueraLayerController controller,
    required CanvasLayer layer,
    required bool isDark,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 400),
      ),
      builder:
          (_) => AdjustmentPanelDialog(
            controller: controller,
            layer: layer,
            isDark: isDark,
          ),
    );
  }

  @override
  State<AdjustmentPanelDialog> createState() => _AdjustmentPanelDialogState();
}

class _AdjustmentPanelDialogState extends State<AdjustmentPanelDialog>
    with SingleTickerProviderStateMixin {
  // Slider values — default = neutral (no effect)
  double _brightness = 0.0; // -1..+1
  double _contrast = 1.0; // 0..2
  double _saturation = 1.0; // 0..2
  double _exposure = 0.0; // -3..+3
  double _gamma = 1.0; // 0.2..3
  double _hueShift = 0.0; // -180..+180
  double _sepiaIntensity = 0.0; // 0..1
  bool _invert = false;
  bool _thresholdEnabled = false;
  double _thresholdLevel = 0.5; // 0..1 (only when enabled)

  // Levels
  double _levelsBlack = 0.0;
  double _levelsWhite = 1.0;
  double _levelsMid = 1.0;

  // Before/After comparison
  bool _showingOriginal = false;

  static const String _adjustmentId = 'layer-adjustment';
  bool _hasExisting = false;

  // 🚀 Debounce: batch slider updates to max 1 per frame (16ms)
  Timer? _debounceTimer;

  // Entry animation
  late AnimationController _entryController;
  late Animation<double> _entryAnimation;

  @override
  void initState() {
    super.initState();
    _loadExistingAdjustments();

    // Spring entry animation
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _entryAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.elasticOut,
    );
    _entryController.forward();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _entryController.dispose();
    super.dispose();
  }

  /// Load existing adjustment state if the layer already has adjustments.
  void _loadExistingAdjustments() {
    final node = widget.layer.node;
    final adjustNodes = node.adjustmentNodes;
    if (adjustNodes.isEmpty) return;

    _hasExisting = true;
    final stack = adjustNodes.first.adjustmentStack;

    for (final adj in stack.layers) {
      if (!adj.enabled) continue;
      switch (adj.type) {
        case AdjustmentType.brightness:
          _brightness = adj.parameters['amount'] ?? 0.0;
        case AdjustmentType.contrast:
          _contrast = adj.parameters['factor'] ?? 1.0;
        case AdjustmentType.saturation:
          _saturation = adj.parameters['factor'] ?? 1.0;
        case AdjustmentType.exposure:
          _exposure = adj.parameters['stops'] ?? 0.0;
        case AdjustmentType.gamma:
          _gamma = adj.parameters['gamma'] ?? 1.0;
        case AdjustmentType.hueShift:
          _hueShift = adj.parameters['degrees'] ?? 0.0;
        case AdjustmentType.threshold:
          _thresholdEnabled = true;
          _thresholdLevel = adj.parameters['level'] ?? 0.5;
        case AdjustmentType.sepia:
          _sepiaIntensity = adj.parameters['intensity'] ?? 0.0;
        case AdjustmentType.invert:
          _invert = true;
        case AdjustmentType.levels:
          _levelsBlack = adj.parameters['black'] ?? 0.0;
          _levelsWhite = adj.parameters['white'] ?? 1.0;
          _levelsMid = adj.parameters['midtone'] ?? 1.0;
      }
    }
  }

  AdjustmentStack _buildStack() {
    final layers = <AdjustmentLayer>[];

    if (_brightness != 0.0) {
      layers.add(
        AdjustmentLayer(
          type: AdjustmentType.brightness,
          parameters: {'amount': _brightness},
        ),
      );
    }
    if (_contrast != 1.0) {
      layers.add(
        AdjustmentLayer(
          type: AdjustmentType.contrast,
          parameters: {'factor': _contrast},
        ),
      );
    }
    if (_saturation != 1.0) {
      layers.add(
        AdjustmentLayer(
          type: AdjustmentType.saturation,
          parameters: {'factor': _saturation},
        ),
      );
    }
    if (_exposure != 0.0) {
      layers.add(
        AdjustmentLayer(
          type: AdjustmentType.exposure,
          parameters: {'stops': _exposure},
        ),
      );
    }
    if (_gamma != 1.0) {
      layers.add(
        AdjustmentLayer(
          type: AdjustmentType.gamma,
          parameters: {'gamma': _gamma},
        ),
      );
    }
    if (_hueShift != 0.0) {
      layers.add(
        AdjustmentLayer(
          type: AdjustmentType.hueShift,
          parameters: {'degrees': _hueShift},
        ),
      );
    }
    if (_levelsBlack != 0.0 || _levelsWhite != 1.0 || _levelsMid != 1.0) {
      layers.add(
        AdjustmentLayer(
          type: AdjustmentType.levels,
          parameters: {
            'black': _levelsBlack,
            'white': _levelsWhite,
            'midtone': _levelsMid,
          },
        ),
      );
    }
    if (_invert) {
      layers.add(AdjustmentLayer(type: AdjustmentType.invert, parameters: {}));
    }
    if (_thresholdEnabled) {
      layers.add(
        AdjustmentLayer(
          type: AdjustmentType.threshold,
          parameters: {'level': _thresholdLevel},
        ),
      );
    }
    if (_sepiaIntensity > 0.0) {
      layers.add(
        AdjustmentLayer(
          type: AdjustmentType.sepia,
          parameters: {'intensity': _sepiaIntensity},
        ),
      );
    }

    return AdjustmentStack(layers);
  }

  /// 🚀 Debounced apply — max 1 shader update per frame (16ms).
  void _applyDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 16), _applyAdjustments);
  }

  void _applyAdjustments() {
    if (_showingOriginal) return; // Don't apply while comparing

    final stack = _buildStack();

    if (stack.layers.isEmpty) {
      if (_hasExisting) {
        widget.controller.removeAdjustmentLayer(_adjustmentId);
        _hasExisting = false;
      }
    } else if (_hasExisting) {
      widget.controller.updateAdjustmentLayer(_adjustmentId, stack);
    } else {
      widget.controller.addAdjustmentLayer(_adjustmentId, stack);
      _hasExisting = true;
    }
  }

  void _resetAll() {
    HapticFeedback.mediumImpact();
    setState(() {
      _brightness = 0.0;
      _contrast = 1.0;
      _saturation = 1.0;
      _exposure = 0.0;
      _gamma = 1.0;
      _hueShift = 0.0;
      _sepiaIntensity = 0.0;
      _invert = false;
      _thresholdEnabled = false;
      _thresholdLevel = 0.5;
      _levelsBlack = 0.0;
      _levelsWhite = 1.0;
      _levelsMid = 1.0;
    });
    _applyAdjustments();
  }

  void _applyPreset(String name) {
    HapticFeedback.selectionClick();
    setState(() {
      // Reset first
      _brightness = 0.0;
      _contrast = 1.0;
      _saturation = 1.0;
      _exposure = 0.0;
      _gamma = 1.0;
      _hueShift = 0.0;
      _sepiaIntensity = 0.0;
      _invert = false;
      _thresholdEnabled = false;
      _thresholdLevel = 0.5;
      _levelsBlack = 0.0;
      _levelsWhite = 1.0;
      _levelsMid = 1.0;

      switch (name) {
        case 'vintage':
          _sepiaIntensity = 0.5;
          _contrast = 1.15;
          _saturation = 0.75;
          _brightness = 0.05;
        case 'bw':
          _saturation = 0.0;
          _contrast = 1.3;
        case 'dramatic':
          _contrast = 1.5;
          _saturation = 1.3;
          _brightness = -0.05;
          _gamma = 0.85;
        case 'warm':
          _hueShift = 10.0;
          _saturation = 1.15;
          _brightness = 0.05;
        case 'cool':
          _hueShift = -15.0;
          _saturation = 0.9;
          _brightness = -0.02;
        case 'faded':
          _levelsBlack = 0.1;
          _contrast = 0.9;
          _saturation = 0.8;
        case 'high_key':
          _brightness = 0.15;
          _contrast = 0.8;
          _gamma = 1.3;
      }
    });
    _applyAdjustments();
  }

  // ── Before/After: temporarily remove adjustment ──
  void _startCompare() {
    if (!_hasExisting) return;
    setState(() => _showingOriginal = true);
    HapticFeedback.lightImpact();
    widget.controller.removeAdjustmentLayer(_adjustmentId);
    _hasExisting = false;
  }

  void _stopCompare() {
    setState(() => _showingOriginal = false);
    _applyAdjustments();
    HapticFeedback.lightImpact();
  }

  /// Count how many parameters are modified from their neutral value.
  int get _activeAdjustmentCount {
    int count = 0;
    if (_brightness != 0.0) count++;
    if (_contrast != 1.0) count++;
    if (_saturation != 1.0) count++;
    if (_exposure != 0.0) count++;
    if (_gamma != 1.0) count++;
    if (_hueShift != 0.0) count++;
    if (_sepiaIntensity > 0.0) count++;
    if (_invert) count++;
    if (_thresholdEnabled) count++;
    if (_levelsBlack != 0.0 || _levelsWhite != 1.0 || _levelsMid != 1.0)
      count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDark;
    final bgColor = dark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = dark ? Colors.white : Colors.black87;
    final subtleColor = dark ? Colors.white38 : Colors.black38;
    final accentColor = dark ? const Color(0xFFCE93D8) : Colors.purple;
    final handleColor = dark ? Colors.white24 : Colors.black12;

    return AnimatedBuilder(
      animation: _entryAnimation,
      builder:
          (context, child) => Transform.scale(
            scale: 0.95 + 0.05 * _entryAnimation.value,
            alignment: Alignment.bottomCenter,
            child: Opacity(
              opacity: _entryAnimation.value.clamp(0.0, 1.0),
              child: child,
            ),
          ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle ──
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: handleColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.tune, size: 18, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Adjustments — ${widget.layer.name}',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Active count badge
                  if (_activeAdjustmentCount > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_activeAdjustmentCount',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                  // Before/After hold button
                  GestureDetector(
                    onTapDown: (_) => _startCompare(),
                    onTapUp: (_) => _stopCompare(),
                    onTapCancel: () => _stopCompare(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            _showingOriginal
                                ? accentColor.withValues(alpha: 0.3)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: subtleColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.compare,
                            size: 12,
                            color: _showingOriginal ? accentColor : subtleColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showingOriginal ? 'Original' : 'A/B',
                            style: TextStyle(
                              color:
                                  _showingOriginal ? accentColor : subtleColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _resetAll,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                    ),
                    child: Text(
                      'Reset',
                      style: TextStyle(color: subtleColor, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // ── Presets strip ──
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                children: [
                  _presetChip('Vintage', 'vintage', accentColor, textColor),
                  _presetChip('B&W', 'bw', accentColor, textColor),
                  _presetChip('Dramatic', 'dramatic', accentColor, textColor),
                  _presetChip('Warm', 'warm', accentColor, textColor),
                  _presetChip('Cool', 'cool', accentColor, textColor),
                  _presetChip('Faded', 'faded', accentColor, textColor),
                  _presetChip('High Key', 'high_key', accentColor, textColor),
                ],
              ),
            ),

            const Divider(height: 1),

            // ── Sliders ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  children: [
                    _buildSlider(
                      'Brightness',
                      _brightness,
                      -1.0,
                      1.0,
                      neutral: 0.0,
                      icon: Icons.brightness_6,
                      color: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      onChanged: (v) => setState(() => _brightness = v),
                      onReset: () => setState(() => _brightness = 0.0),
                    ),
                    _buildSlider(
                      'Contrast',
                      _contrast,
                      0.0,
                      2.0,
                      neutral: 1.0,
                      icon: Icons.contrast,
                      color: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      onChanged: (v) => setState(() => _contrast = v),
                      onReset: () => setState(() => _contrast = 1.0),
                    ),
                    _buildSlider(
                      'Saturation',
                      _saturation,
                      0.0,
                      2.0,
                      neutral: 1.0,
                      icon: Icons.color_lens,
                      color: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      onChanged: (v) => setState(() => _saturation = v),
                      onReset: () => setState(() => _saturation = 1.0),
                    ),
                    _buildSlider(
                      'Exposure',
                      _exposure,
                      -3.0,
                      3.0,
                      neutral: 0.0,
                      icon: Icons.exposure,
                      color: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      onChanged: (v) => setState(() => _exposure = v),
                      onReset: () => setState(() => _exposure = 0.0),
                    ),
                    _buildSlider(
                      'Gamma',
                      _gamma,
                      0.2,
                      3.0,
                      neutral: 1.0,
                      icon: Icons.tonality,
                      color: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      onChanged: (v) => setState(() => _gamma = v),
                      onReset: () => setState(() => _gamma = 1.0),
                    ),
                    _buildSlider(
                      'Hue Shift',
                      _hueShift,
                      -180.0,
                      180.0,
                      neutral: 0.0,
                      icon: Icons.palette,
                      color: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      onChanged: (v) => setState(() => _hueShift = v),
                      onReset: () => setState(() => _hueShift = 0.0),
                    ),
                    _buildSlider(
                      'Sepia',
                      _sepiaIntensity,
                      0.0,
                      1.0,
                      neutral: 0.0,
                      icon: Icons.filter_vintage,
                      color: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      onChanged: (v) => setState(() => _sepiaIntensity = v),
                      onReset: () => setState(() => _sepiaIntensity = 0.0),
                    ),

                    const SizedBox(height: 8),

                    // ── Toggles: Invert + Threshold ──
                    _buildToggle(
                      'Invert Colors',
                      _invert,
                      icon: Icons.invert_colors,
                      color: accentColor,
                      textColor: textColor,
                      onChanged: (v) => setState(() => _invert = v),
                    ),

                    // ── Threshold: toggle + conditional slider ──
                    _buildToggle(
                      'Threshold',
                      _thresholdEnabled,
                      icon: Icons.gradient,
                      color: accentColor,
                      textColor: textColor,
                      onChanged: (v) => setState(() => _thresholdEnabled = v),
                    ),
                    if (_thresholdEnabled)
                      Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: _buildSlider(
                          'Level',
                          _thresholdLevel,
                          0.0,
                          1.0,
                          neutral: 0.5,
                          icon: Icons.tune,
                          color: accentColor,
                          textColor: textColor,
                          subtleColor: subtleColor,
                          onChanged: (v) => setState(() => _thresholdLevel = v),
                          onReset: () => setState(() => _thresholdLevel = 0.5),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // ── Levels section ──
                    _buildSectionLabel('Levels', textColor, subtleColor),
                    _buildSlider(
                      'Black Point',
                      _levelsBlack,
                      0.0,
                      0.5,
                      neutral: 0.0,
                      icon: Icons.brightness_1,
                      color: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      onChanged: (v) => setState(() => _levelsBlack = v),
                      onReset: () => setState(() => _levelsBlack = 0.0),
                    ),
                    _buildSlider(
                      'White Point',
                      _levelsWhite,
                      0.5,
                      1.0,
                      neutral: 1.0,
                      icon: Icons.brightness_7,
                      color: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      onChanged: (v) => setState(() => _levelsWhite = v),
                      onReset: () => setState(() => _levelsWhite = 1.0),
                    ),
                    _buildSlider(
                      'Midtone',
                      _levelsMid,
                      0.1,
                      3.0,
                      neutral: 1.0,
                      icon: Icons.brightness_5,
                      color: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      onChanged: (v) => setState(() => _levelsMid = v),
                      onReset: () => setState(() => _levelsMid = 1.0),
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

  Widget _presetChip(
    String label,
    String key,
    Color accentColor,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: textColor)),
        side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
        backgroundColor: accentColor.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onPressed: () => _applyPreset(key),
      ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max, {
    required double neutral,
    required IconData icon,
    required Color color,
    required Color textColor,
    required Color subtleColor,
    required ValueChanged<double> onChanged,
    required VoidCallback onReset,
  }) {
    final isModified = (value - neutral).abs() > 0.01;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: isModified ? color : subtleColor),
          const SizedBox(width: 6),
          // 🎯 Double-tap label → reset to neutral
          GestureDetector(
            onDoubleTap: () {
              HapticFeedback.lightImpact();
              onReset();
              _applyDebounced();
            },
            child: SizedBox(
              width: 72,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isModified ? textColor : subtleColor,
                  fontWeight: isModified ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: color,
                inactiveTrackColor: subtleColor.withValues(alpha: 0.2),
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.12),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: (v) {
                  onChanged(v);
                  _applyDebounced(); // 🚀 Debounced
                },
                onChangeEnd: (_) {
                  HapticFeedback.selectionClick();
                  _applyAdjustments(); // Ensure final value is always applied
                },
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              _formatValue(value, neutral),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                color: isModified ? textColor : subtleColor,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(
    String label,
    bool value, {
    required IconData icon,
    required Color color,
    required Color textColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: value ? color : textColor.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: textColor,
              fontWeight: value ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          const Spacer(),
          Switch(
            value: value,
            onChanged: (v) {
              onChanged(v);
              _applyDebounced();
              HapticFeedback.selectionClick();
            },
            activeThumbColor: color,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label, Color textColor, Color subtleColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: subtleColor.withValues(alpha: 0.3))),
        ],
      ),
    );
  }

  String _formatValue(double value, double neutral) {
    final diff = value - neutral;
    if (diff.abs() < 0.01) return '—';
    if (neutral == 0.0) {
      return diff > 0
          ? '+${value.toStringAsFixed(2)}'
          : value.toStringAsFixed(2);
    }
    return value.toStringAsFixed(2);
  }
}
