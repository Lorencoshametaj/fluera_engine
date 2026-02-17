import 'dart:math' as math;
import 'package:flutter/material.dart';
import './pressure_curve.dart';
import './pro_drawing_point.dart';
import './pro_brush_settings.dart';
import '../brushes/brush_engine.dart';
import '../brushes/brush_texture.dart';

/// 🎛️ Material Design 3 — Compact brush settings popup
///
/// Anchored popup positioned next to the brush icon on long-press.
/// Shows only curated, user-meaningful settings per brush type.
class ProBrushSettingsDialog extends StatefulWidget {
  final ProBrushSettings settings;
  final ProPenType currentBrush;
  final Function(ProBrushSettings) onSettingsChanged;
  final Color? currentColor;
  final double? currentWidth;

  const ProBrushSettingsDialog({
    super.key,
    required this.settings,
    required this.currentBrush,
    required this.onSettingsChanged,
    this.currentColor,
    this.currentWidth,
  });

  /// Show anchored popup near [anchorRect] in global coordinates.
  static void show(
    BuildContext context, {
    required ProBrushSettings settings,
    required ProPenType currentBrush,
    required Function(ProBrushSettings) onSettingsChanged,
    Rect? anchorRect,
    Color? currentColor,
    double? currentWidth,
    Color? canvasColor,
  }) {
    Navigator.of(context).push(
      _BrushPopupRoute(
        anchorRect: anchorRect,
        brushSettings: settings,
        currentBrush: currentBrush,
        onSettingsChanged: onSettingsChanged,
        currentColor: currentColor,
        currentWidth: currentWidth,
      ),
    );
  }

  @override
  State<ProBrushSettingsDialog> createState() => _ProBrushSettingsDialogState();
}

// ════════════════════════════════════════════════════════════════════
//  CUSTOM POPUP ROUTE — positions card near anchor
// ════════════════════════════════════════════════════════════════════

class _BrushPopupRoute extends PopupRoute<void> {
  final Rect? anchorRect;
  final ProBrushSettings brushSettings;
  final ProPenType currentBrush;
  final Function(ProBrushSettings) onSettingsChanged;
  final Color? currentColor;
  final double? currentWidth;

  _BrushPopupRoute({
    required this.anchorRect,
    required this.brushSettings,
    required this.currentBrush,
    required this.onSettingsChanged,
    this.currentColor,
    this.currentWidth,
  });

  @override
  Color? get barrierColor => Colors.black26;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss brush settings';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        alignment: _scaleAlignment(context),
        child: child,
      ),
    );
  }

  Alignment _scaleAlignment(BuildContext context) {
    if (anchorRect == null) return Alignment.center;
    final size = MediaQuery.of(context).size;
    final cx = anchorRect!.center.dx / size.width * 2 - 1;
    final cy = anchorRect!.center.dy / size.height * 2 - 1;
    return Alignment(cx.clamp(-1.0, 1.0), cy.clamp(-1.0, 1.0));
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _BrushPopupLayout(
      anchorRect: anchorRect,
      child: ProBrushSettingsDialog(
        settings: brushSettings,
        currentBrush: currentBrush,
        onSettingsChanged: onSettingsChanged,
        currentColor: currentColor,
        currentWidth: currentWidth,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  LAYOUT — positions the card relative to anchor
// ════════════════════════════════════════════════════════════════════

class _BrushPopupLayout extends StatelessWidget {
  final Rect? anchorRect;
  final Widget child;

  const _BrushPopupLayout({required this.anchorRect, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenSize = mq.size;
    final padding = mq.padding;

    const popupWidth = 300.0;
    const popupMaxHeight = 420.0;
    const margin = 12.0;

    if (anchorRect == null) {
      // Fallback: center on screen
      return Align(
        alignment: const Alignment(0, -0.2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: popupWidth,
            maxHeight: popupMaxHeight,
          ),
          child: child,
        ),
      );
    }

    // Calculate position: try above anchor, then below
    final anchor = anchorRect!;
    final spaceAbove = anchor.top - padding.top - margin;
    final spaceBelow =
        screenSize.height - anchor.bottom - padding.bottom - margin;

    final showAbove =
        spaceAbove >= popupMaxHeight * 0.5 || spaceAbove > spaceBelow;
    final availableHeight =
        showAbove
            ? spaceAbove.clamp(100.0, popupMaxHeight)
            : spaceBelow.clamp(100.0, popupMaxHeight);

    // Horizontal: center on anchor, but clamp to screen
    double left = anchor.center.dx - popupWidth / 2;
    left = left.clamp(margin, screenSize.width - popupWidth - margin);

    double top;
    if (showAbove) {
      top = anchor.top - availableHeight - 8;
    } else {
      top = anchor.bottom + 8;
    }
    top = top.clamp(
      padding.top + margin,
      screenSize.height - availableHeight - padding.bottom - margin,
    );

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: popupWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: availableHeight),
            child: child,
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  POPUP CONTENT — curated settings
// ════════════════════════════════════════════════════════════════════

class _ProBrushSettingsDialogState extends State<ProBrushSettingsDialog>
    with SingleTickerProviderStateMixin {
  late ProBrushSettings _settings;
  late AnimationController _previewAnim;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _previewAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    // Preload texture assets so they're available for overlay
    BrushTexture.preloadAll();
  }

  @override
  void dispose() {
    _previewAnim.dispose();
    super.dispose();
  }

  void _update(ProBrushSettings s) {
    setState(() => _settings = s);
    widget.onSettingsChanged(s);
  }

  // ── Accent color per brush type ──
  Color _accent(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return switch (widget.currentBrush) {
      ProPenType.fountain =>
        isDark ? const Color(0xFF9FA8DA) : const Color(0xFF3949AB),
      ProPenType.pencil =>
        isDark ? const Color(0xFFFFD54F) : const Color(0xFFF9A825),
      ProPenType.ballpoint =>
        isDark ? const Color(0xFF80CBC4) : const Color(0xFF00897B),
      ProPenType.highlighter =>
        isDark ? const Color(0xFFF48FB1) : const Color(0xFFD81B60),
    };
  }

  IconData _brushIcon() => switch (widget.currentBrush) {
    ProPenType.fountain => Icons.edit_rounded,
    ProPenType.pencil => Icons.draw_rounded,
    ProPenType.ballpoint => Icons.create_rounded,
    ProPenType.highlighter => Icons.highlight_rounded,
  };

  String _brushTitle() => switch (widget.currentBrush) {
    ProPenType.fountain => 'Fountain Pen',
    ProPenType.pencil => 'Pencil',
    ProPenType.ballpoint => 'Ballpoint',
    ProPenType.highlighter => 'Highlighter',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = _accent(context);
    final isDark = cs.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 40,
              spreadRadius: -4,
            ),
          ],
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──
              _buildHeader(cs, tt, accent),

              // 🎨 Sticky stroke preview (outside scroll)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: RepaintBoundary(child: _buildStrokePreview(cs, accent)),
              ),

              // ── Scrollable content ──
              Flexible(
                child: SliderTheme(
                  data: _sliderTheme(accent),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ..._buildBrushControls(cs, tt, accent),
                        const SizedBox(height: 12),
                        _buildDivider(cs),
                        const SizedBox(height: 8),
                        _buildStabilizer(cs, tt, accent),
                        const SizedBox(height: 12),
                        _buildDivider(cs),
                        const SizedBox(height: 8),
                        _buildTextureControls(cs, tt, accent),
                        const SizedBox(height: 12),
                        _buildDivider(cs),
                        const SizedBox(height: 8),
                        _buildPressureCurve(cs, tt, accent),
                        // ── Stamp Dynamics (only when stamp mode on) ──
                        if (_settings.stampEnabled) ...[
                          const SizedBox(height: 12),
                          _buildDivider(cs),
                          const SizedBox(height: 8),
                          _buildStampDynamics(cs, tt, accent),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header with brush icon + title + reset ──
  Widget _buildHeader(ColorScheme cs, TextTheme tt, Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: BoxDecoration(color: accent.withValues(alpha: 0.06)),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_brushIcon(), color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _brushTitle(),
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: TextButton(
              onPressed: () => _update(const ProBrushSettings()),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: cs.onSurfaceVariant,
                textStyle: tt.labelSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              child: const Text('Reset'),
            ),
          ),
        ],
      ),
    );
  }

  // ── SliderTheme ──
  SliderThemeData _sliderTheme(Color accent) => SliderThemeData(
    activeTrackColor: accent,
    inactiveTrackColor: accent.withValues(alpha: 0.12),
    thumbColor: accent,
    overlayColor: accent.withValues(alpha: 0.1),
    trackHeight: 3,
    thumbShape: const RoundSliderThumbShape(
      enabledThumbRadius: 7,
      elevation: 1,
    ),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
  );

  Widget _buildDivider(ColorScheme cs) =>
      Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2));

  // ════════════════════════════════════════════════════════════════
  //  PER-BRUSH CONTROLS (curated)
  // ════════════════════════════════════════════════════════════════

  List<Widget> _buildBrushControls(
    ColorScheme cs,
    TextTheme tt,
    Color accent,
  ) => switch (widget.currentBrush) {
    ProPenType.fountain => _fountainControls(cs, tt, accent),
    ProPenType.pencil => _pencilControls(cs, tt, accent),
    ProPenType.ballpoint => _ballpointControls(cs, tt, accent),
    ProPenType.highlighter => _highlighterControls(cs, tt, accent),
  };

  // ════════════════════════════════════════════════════════════════
  //  STAMP DYNAMICS
  // ════════════════════════════════════════════════════════════════

  Widget _buildStampDynamics(ColorScheme cs, TextTheme tt, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Section header
        Row(
          children: [
            Icon(Icons.grain_rounded, size: 16, color: accent),
            const SizedBox(width: 6),
            Text(
              'Stamp Dynamics',
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // ── Shape ──
        _sliderRow(
          icon: Icons.space_dashboard_rounded,
          label: 'Spacing',
          tooltip:
              'Distance between consecutive stamps as a fraction of brush size. Lower = smoother, higher = more textured.',
          value: _settings.stampSpacing,
          min: 0.05,
          max: 1.0,
          displayValue: '${(_settings.stampSpacing * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampSpacing: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.opacity_rounded,
          label: 'Flow',
          tooltip:
              'Per-stamp opacity. Lower flow creates lighter, more transparent stamps that build up with overlap.',
          value: _settings.stampFlow,
          min: 0.1,
          max: 1.0,
          displayValue: '${(_settings.stampFlow * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampFlow: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.water_drop_outlined,
          label: 'Wet Edges',
          tooltip:
              'Darker ring around stamp edges, mimicking watercolor or ink pooling.',
          value: _settings.stampWetEdges,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampWetEdges * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampWetEdges: v)),
          cs: cs,
          tt: tt,
        ),
        // ── Velocity ──
        _sliderRow(
          icon: Icons.speed_rounded,
          label: 'Vel → Size',
          tooltip:
              'How much drawing speed shrinks stamp size. Fast strokes → thinner marks.',
          value: _settings.stampVelocitySize,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampVelocitySize * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampVelocitySize: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.air_rounded,
          label: 'Vel → Flow',
          tooltip:
              'How much drawing speed reduces opacity. Fast strokes → lighter marks.',
          value: _settings.stampVelocityFlow,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampVelocityFlow * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampVelocityFlow: v)),
          cs: cs,
          tt: tt,
        ),
        // ── Glaze / Buildup ──
        _switchRow(
          icon: Icons.layers_rounded,
          label: 'Glaze Mode',
          tooltip:
              'ON = caps stroke opacity (like a single wash). OFF = stamps accumulate freely (buildup).',
          value: _settings.stampGlazeMode,
          onChanged: (v) => _update(_settings.copyWith(stampGlazeMode: v)),
          cs: cs,
          tt: tt,
          accent: accent,
        ),
        // ── Color Dynamics ──
        _sliderRow(
          icon: Icons.palette_rounded,
          label: 'Hue Jitter',
          tooltip:
              'Random hue variation per stamp (in degrees). Adds organic color shifts.',
          value: _settings.stampHueJitter,
          min: 0.0,
          max: 30.0,
          displayValue: '${_settings.stampHueJitter.round()}°',
          onChanged: (v) => _update(_settings.copyWith(stampHueJitter: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.gradient_rounded,
          label: 'Sat Jitter',
          tooltip:
              'Random saturation variation per stamp. Adds richness to color.',
          value: _settings.stampSatJitter,
          min: 0.0,
          max: 0.3,
          displayValue: '${(_settings.stampSatJitter * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampSatJitter: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.brightness_6_rounded,
          label: 'Bright Jitter',
          tooltip:
              'Random brightness variation per stamp. Creates subtle light/dark shifts.',
          value: _settings.stampBrightJitter,
          min: 0.0,
          max: 0.2,
          displayValue: '${(_settings.stampBrightJitter * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampBrightJitter: v)),
          cs: cs,
          tt: tt,
        ),
        // ── Jitter & Scatter ──
        _sliderRow(
          icon: Icons.photo_size_select_small_rounded,
          label: 'Size Jitter',
          tooltip: 'Random size variation per stamp.',
          value: _settings.stampSizeJitter,
          min: 0.0,
          max: 0.5,
          displayValue: '${(_settings.stampSizeJitter * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampSizeJitter: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.rotate_right_rounded,
          label: 'Angle Jitter',
          tooltip: 'Random rotation per stamp.',
          value: _settings.stampRotationJitter,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampRotationJitter * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampRotationJitter: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.scatter_plot_rounded,
          label: 'Scatter',
          tooltip:
              'Perpendicular offset randomness, displacing stamps off the stroke path.',
          value: _settings.stampScatter,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampScatter * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampScatter: v)),
          cs: cs,
          tt: tt,
        ),
        // ── Tilt Dynamics ──
        _sliderRow(
          icon: Icons.edit_rounded,
          label: 'Tilt → Rot',
          tooltip:
              'How much Apple Pencil tilt direction overrides stroke-angle rotation.',
          value: _settings.stampTiltRotation,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampTiltRotation * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampTiltRotation: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.open_in_full_rounded,
          label: 'Tilt → Stretch',
          tooltip: 'How much tilt altitude stretches the stamp elliptically.',
          value: _settings.stampTiltElongation,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampTiltElongation * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampTiltElongation: v)),
          cs: cs,
          tt: tt,
        ),
        // ── Dual Brush ──
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Row(
            children: [
              Icon(Icons.texture_rounded, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: Text(
                  'Dual Tip',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: DropdownButton<String>(
                  value: _settings.stampDualTexture,
                  isExpanded: true,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: tt.bodySmall?.copyWith(color: cs.onSurface),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('None')),
                    DropdownMenuItem(
                      value: 'pencilGrain',
                      child: Text('Pencil Grain'),
                    ),
                    DropdownMenuItem(
                      value: 'charcoal',
                      child: Text('Charcoal'),
                    ),
                    DropdownMenuItem(
                      value: 'watercolor',
                      child: Text('Watercolor'),
                    ),
                    DropdownMenuItem(value: 'canvas', child: Text('Canvas')),
                    DropdownMenuItem(value: 'kraft', child: Text('Kraft')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      _update(
                        _settings.copyWith(
                          stampDualTexture: v,
                          stampDualBlend:
                              v == 'none'
                                  ? 0.0
                                  : (_settings.stampDualBlend < 0.1
                                      ? 0.5
                                      : null),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        if (_settings.stampDualTexture != 'none') ...[
          _sliderRow(
            icon: Icons.tune_rounded,
            label: 'Dual Blend',
            tooltip:
                'Intensity of the secondary texture masking (0=off, 100%=full mask).',
            value: _settings.stampDualBlend,
            min: 0.0,
            max: 1.0,
            displayValue: '${(_settings.stampDualBlend * 100).round()}%',
            onChanged: (v) => _update(_settings.copyWith(stampDualBlend: v)),
            cs: cs,
            tt: tt,
          ),
          _sliderRow(
            icon: Icons.aspect_ratio_rounded,
            label: 'Dual Scale',
            tooltip:
                'Scale of the dual texture relative to the stamp. Lower = finer pattern.',
            value: _settings.stampDualScale,
            min: 0.3,
            max: 3.0,
            displayValue: '${_settings.stampDualScale.toStringAsFixed(1)}×',
            onChanged: (v) => _update(_settings.copyWith(stampDualScale: v)),
            cs: cs,
            tt: tt,
          ),
        ],
        // ── Pressure → Color & Wet Mix ──
        _sliderRow(
          icon: Icons.contrast_rounded,
          label: 'Press Color',
          tooltip:
              'Harder pressure darkens the color, mimicking real ink/paint absorption.',
          value: _settings.stampPressureColor,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampPressureColor * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampPressureColor: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.water_drop_rounded,
          label: 'Wet Mix',
          tooltip:
              'Color bleed between stamps. Each stamp absorbs a bit of the previous color.',
          value: _settings.stampWetMix,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampWetMix * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampWetMix: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.circle_outlined,
          label: 'Round Jitter',
          tooltip: 'Random elongation variation per stamp for organic shapes.',
          value: _settings.stampRoundnessJitter,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampRoundnessJitter * 100).round()}%',
          onChanged:
              (v) => _update(_settings.copyWith(stampRoundnessJitter: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.gradient_rounded,
          label: 'Color Grad',
          tooltip: 'Fade from brush color toward white along the stroke path.',
          value: _settings.stampColorGradient,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampColorGradient * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampColorGradient: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.vertical_align_top_rounded,
          label: 'Accum Cap',
          tooltip:
              'Max opacity in glaze mode. Prevents over-saturation. 0 = uncapped.',
          value: _settings.stampAccumCap,
          min: 0.0,
          max: 1.0,
          displayValue:
              _settings.stampAccumCap == 0
                  ? 'Off'
                  : '${(_settings.stampAccumCap * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampAccumCap: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.compress_rounded,
          label: 'Spacing Press',
          tooltip:
              'Pressure tightens stamp spacing. More pressure = denser stamps.',
          value: _settings.stampSpacingPressure,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampSpacingPressure * 100).round()}%',
          onChanged:
              (v) => _update(_settings.copyWith(stampSpacingPressure: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.speed_rounded,
          label: 'Transfer Vel',
          tooltip:
              'Slow strokes = more opaque. Fast = lighter. Separate from flow velocity.',
          value: _settings.stampTransferVelocity,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampTransferVelocity * 100).round()}%',
          onChanged:
              (v) => _update(_settings.copyWith(stampTransferVelocity: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.grain_rounded,
          label: 'Grain Scale',
          tooltip:
              'Zoom grain texture. <1 = fine (pencil), >1 = coarse (charcoal).',
          value: _settings.stampGrainScale,
          min: 0.1,
          max: 3.0,
          displayValue: '${_settings.stampGrainScale.toStringAsFixed(1)}x',
          onChanged: (v) => _update(_settings.copyWith(stampGrainScale: v)),
          cs: cs,
          tt: tt,
        ),
        _sliderRow(
          icon: Icons.palette_rounded,
          label: 'Color Press',
          tooltip:
              'Pressure shifts color toward white. Like Procreate Color Pressure.',
          value: _settings.stampColorPressure,
          min: 0.0,
          max: 1.0,
          displayValue: '${(_settings.stampColorPressure * 100).round()}%',
          onChanged: (v) => _update(_settings.copyWith(stampColorPressure: v)),
          cs: cs,
          tt: tt,
        ),
        // ── Shape, Symmetry, Grain Mode, Eraser ──
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            'STAMP SHAPE',
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              letterSpacing: 1.2,
            ),
          ),
        ),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final entry
                in {
                  0: ('\u25CF', 'Circle'),
                  1: ('\u25A0', 'Square'),
                  2: ('\u25C6', 'Diamond'),
                  3: ('\u2605', 'Star'),
                  4: ('\u{1F342}', 'Leaf'),
                }.entries)
              ChoiceChip(
                label: Text(
                  entry.value.$1,
                  style: tt.bodySmall?.copyWith(fontSize: 16),
                ),
                selected: _settings.stampShapeType == entry.key,
                onSelected:
                    (_) =>
                        _update(_settings.copyWith(stampShapeType: entry.key)),
                visualDensity: VisualDensity.compact,
                tooltip: entry.value.$2,
              ),
          ],
        ),
        _sliderRow(
          icon: Icons.auto_awesome_rounded,
          label: 'Symmetry',
          tooltip: 'Mirror stamps across axes. 0=off, 2=bilateral, 3+=radial.',
          value: _settings.stampSymmetryAxes.toDouble(),
          min: 0,
          max: 8,
          displayValue:
              _settings.stampSymmetryAxes == 0
                  ? 'Off'
                  : '${_settings.stampSymmetryAxes}x',
          onChanged:
              (v) => _update(_settings.copyWith(stampSymmetryAxes: v.round())),
          cs: cs,
          tt: tt,
        ),
        _switchRow(
          icon: Icons.texture_rounded,
          label: 'Screen Grain',
          tooltip:
              'ON: grain fixed like paper. OFF: grain rotates with stroke.',
          value: _settings.stampGrainScreenSpace,
          onChanged:
              (v) => _update(_settings.copyWith(stampGrainScreenSpace: v)),
          cs: cs,
          tt: tt,
          accent: accent,
        ),
        _switchRow(
          icon: Icons.auto_fix_off_rounded,
          label: 'Eraser Mode',
          tooltip: 'Stamps erase instead of painting.',
          value: _settings.stampEraserMode,
          onChanged: (v) => _update(_settings.copyWith(stampEraserMode: v)),
          cs: cs,
          tt: tt,
          accent: accent,
        ),
        // ── Stamp Presets ──
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            'PRESETS',
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              letterSpacing: 1.2,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _presetChip('Watercolor', Icons.water_rounded, cs, tt, () {
              _update(
                _settings.copyWith(
                  stampSpacing: 0.12,
                  stampSoftness: 0.85,
                  stampFlow: 0.25,
                  stampWetEdges: 0.7,
                  stampSizeJitter: 0.15,
                  stampOpacityJitter: 0.2,
                  stampScatter: 0.08,
                  stampWetMix: 0.6,
                  stampPressureColor: 0.3,
                  stampGlazeMode: true,
                ),
              );
            }),
            _presetChip('Charcoal', Icons.gesture_rounded, cs, tt, () {
              _update(
                _settings.copyWith(
                  stampSpacing: 0.08,
                  stampSoftness: 0.4,
                  stampFlow: 0.6,
                  stampSizeJitter: 0.2,
                  stampRotationJitter: 0.5,
                  stampScatter: 0.15,
                  stampElongation: 1.3,
                  stampWetEdges: 0.0,
                  stampWetMix: 0.0,
                  stampPressureColor: 0.5,
                  stampGlazeMode: false,
                ),
              );
            }),
            _presetChip('Airbrush', Icons.blur_on_rounded, cs, tt, () {
              _update(
                _settings.copyWith(
                  stampSpacing: 0.05,
                  stampSoftness: 1.0,
                  stampFlow: 0.15,
                  stampSizeJitter: 0.0,
                  stampRotationJitter: 0.0,
                  stampScatter: 0.0,
                  stampWetEdges: 0.0,
                  stampWetMix: 0.0,
                  stampPressureColor: 0.0,
                  stampGlazeMode: true,
                ),
              );
            }),
            _presetChip('Oil Paint', Icons.brush_rounded, cs, tt, () {
              _update(
                _settings.copyWith(
                  stampSpacing: 0.15,
                  stampSoftness: 0.5,
                  stampFlow: 0.7,
                  stampSizeJitter: 0.1,
                  stampRotationJitter: 0.3,
                  stampElongation: 1.5,
                  stampWetEdges: 0.2,
                  stampWetMix: 0.8,
                  stampPressureColor: 0.4,
                  stampGlazeMode: false,
                  stampTiltRotation: 0.6,
                  stampTiltElongation: 0.5,
                ),
              );
            }),
            _presetChip('Ink Splash', Icons.opacity_rounded, cs, tt, () {
              _update(
                _settings.copyWith(
                  stampSpacing: 0.3,
                  stampSoftness: 0.3,
                  stampFlow: 0.9,
                  stampSizeJitter: 0.4,
                  stampRotationJitter: 0.8,
                  stampScatter: 0.5,
                  stampOpacityJitter: 0.3,
                  stampWetEdges: 0.5,
                  stampWetMix: 0.2,
                  stampPressureColor: 0.6,
                  stampGlazeMode: false,
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  // ── Fountain: Sensitivity + Tilt + Nib Angle + Nib Strength + Advanced ──
  List<Widget> _fountainControls(ColorScheme cs, TextTheme tt, Color accent) {
    // Map min/max pressure to a single 0-1 "sensitivity" feel
    final sensitivity = ((_settings.fountainMaxPressure - 1.0) / 2.0).clamp(
      0.0,
      1.0,
    );
    return [
      // 🎨 Presets
      _presetChips(
        cs: cs,
        tt: tt,
        accent: accent,
        presets: {
          'Calligraphic':
              () => _update(
                _settings.copyWith(
                  fountainNibStrength: 0.8,
                  fountainNibAngleDeg: 45.0,
                  fountainThinning: 0.75,
                  fountainVelocityInfluence: 0.3,
                  fountainTaperEntry: 4,
                  fountainTaperExit: 12,
                  fountainMinPressure: 0.15,
                  fountainMaxPressure: 2.5,
                ),
              ),
          'Note-taking': () => _update(const ProBrushSettings()),
          'Sketch':
              () => _update(
                _settings.copyWith(
                  fountainNibStrength: 0.15,
                  fountainNibAngleDeg: 30.0,
                  fountainThinning: 0.35,
                  fountainVelocityInfluence: 0.8,
                  fountainTaperEntry: 2,
                  fountainTaperExit: 3,
                  fountainMinPressure: 0.3,
                  fountainMaxPressure: 1.8,
                ),
              ),
        },
      ),
      const SizedBox(height: 4),
      _sliderRow(
        icon: Icons.touch_app_rounded,
        label: 'Sensitivity',
        tooltip:
            'How much the stroke reacts to pen pressure. Higher values create more variation between light and heavy strokes.',
        value: sensitivity,
        min: 0.0,
        max: 1.0,
        displayValue: '${(sensitivity * 100).round()}%',
        onChanged: (v) {
          final newMax = 1.0 + v * 2.0;
          final newMin = 0.5 - v * 0.45;
          _update(
            _settings.copyWith(
              fountainMinPressure: newMin.clamp(0.05, 0.5),
              fountainMaxPressure: newMax.clamp(1.0, 3.0),
            ),
          );
        },
        cs: cs,
        tt: tt,
      ),
      _sliderRow(
        icon: Icons.compress_rounded,
        label: 'Thinning',
        tooltip:
            'How much pressure affects stroke width. Low values give uniform width, high values create dramatic thin-to-thick variation.',
        value: _settings.fountainThinning,
        min: 0.2,
        max: 0.9,
        displayValue: '${(_settings.fountainThinning * 100).round()}%',
        onChanged: (v) => _update(_settings.copyWith(fountainThinning: v)),
        cs: cs,
        tt: tt,
      ),
      _sliderRow(
        icon: Icons.speed_rounded,
        label: 'Velocity',
        tooltip:
            'How much drawing speed affects thickness. Higher values make fast strokes thinner and slow strokes thicker.',
        value: _settings.fountainVelocityInfluence,
        min: 0.0,
        max: 1.0,
        displayValue: '${(_settings.fountainVelocityInfluence * 100).round()}%',
        onChanged:
            (v) => _update(_settings.copyWith(fountainVelocityInfluence: v)),
        cs: cs,
        tt: tt,
      ),
      _switchRow(
        icon: Icons.screen_rotation_rounded,
        label: 'Tilt',
        tooltip:
            'When enabled, tilting the stylus changes the stroke shape, simulating a real fountain pen angle.',
        value: _settings.fountainTiltEnable,
        onChanged: (v) => _update(_settings.copyWith(fountainTiltEnable: v)),
        cs: cs,
        tt: tt,
        accent: accent,
      ),
      _sliderRow(
        icon: Icons.straighten_rounded,
        label: 'Nib Angle',
        tooltip:
            'The rotation angle of the pen nib. Changes which direction produces thin vs thick strokes.',
        value: _settings.fountainNibAngleDeg,
        min: 0.0,
        max: 90.0,
        displayValue: '${_settings.fountainNibAngleDeg.round()}°',
        onChanged: (v) => _update(_settings.copyWith(fountainNibAngleDeg: v)),
        cs: cs,
        tt: tt,
      ),
      _sliderRow(
        icon: Icons.line_weight_rounded,
        label: 'Nib Strength',
        tooltip:
            'How pronounced the nib shape effect is. At 0% the stroke is round, at 100% it\'s fully directional.',
        value: _settings.fountainNibStrength,
        min: 0.0,
        max: 1.0,
        displayValue: '${(_settings.fountainNibStrength * 100).round()}%',
        onChanged: (v) => _update(_settings.copyWith(fountainNibStrength: v)),
        cs: cs,
        tt: tt,
      ),
      _sliderRow(
        icon: Icons.start_rounded,
        label: 'Taper Start',
        tooltip:
            'Number of points to taper at the beginning. Creates a smooth entry effect.',
        value: _settings.fountainTaperEntry.toDouble(),
        min: 0,
        max: 20,
        displayValue: '${_settings.fountainTaperEntry}',
        onChanged:
            (v) => _update(_settings.copyWith(fountainTaperEntry: v.round())),
        cs: cs,
        tt: tt,
      ),
      _sliderRow(
        icon: Icons.keyboard_tab_rounded,
        label: 'Taper End',
        tooltip:
            'Number of points to taper at the end. Creates a smooth trailing-off effect.',
        value: _settings.fountainTaperExit.toDouble(),
        min: 0,
        max: 20,
        displayValue: '${_settings.fountainTaperExit}',
        onChanged:
            (v) => _update(_settings.copyWith(fountainTaperExit: v.round())),
        cs: cs,
        tt: tt,
      ),
    ];
  }

  // ── Pencil: Opacity + Softness + Pressure ──
  List<Widget> _pencilControls(ColorScheme cs, TextTheme tt, Color accent) {
    final sensitivity = ((_settings.pencilMaxPressure - 0.8) / 0.8).clamp(
      0.0,
      1.0,
    );
    return [
      _presetChips(
        cs: cs,
        tt: tt,
        accent: accent,
        presets: {
          'Soft':
              () => _update(
                _settings.copyWith(
                  pencilBaseOpacity: 0.25,
                  pencilMaxOpacity: 0.55,
                  pencilBlurRadius: 2.5,
                  pencilMinPressure: 0.3,
                  pencilMaxPressure: 1.0,
                ),
              ),
          'Medium':
              () => _update(
                _settings.copyWith(
                  pencilBaseOpacity: 0.4,
                  pencilMaxOpacity: 0.8,
                  pencilBlurRadius: 0.3,
                  pencilMinPressure: 0.5,
                  pencilMaxPressure: 1.2,
                ),
              ),
          'Hard':
              () => _update(
                _settings.copyWith(
                  pencilBaseOpacity: 0.6,
                  pencilMaxOpacity: 0.95,
                  pencilBlurRadius: 0.0,
                  pencilMinPressure: 0.7,
                  pencilMaxPressure: 1.5,
                ),
              ),
        },
      ),
      const SizedBox(height: 4),
      _sliderRow(
        icon: Icons.opacity_rounded,
        label: 'Opacity',
        tooltip:
            'The base transparency of the pencil stroke. Lower values give a lighter, sketchier feel.',
        value: _settings.pencilBaseOpacity,
        min: 0.05,
        max: 0.9,
        displayValue: '${(_settings.pencilBaseOpacity * 100).round()}%',
        onChanged: (v) => _update(_settings.copyWith(pencilBaseOpacity: v)),
        cs: cs,
        tt: tt,
      ),
      _sliderRow(
        icon: Icons.blur_on_rounded,
        label: 'Softness',
        tooltip:
            'Adds a soft blur to pencil edges. Higher values create a smoother, more diffused stroke.',
        value: _settings.pencilBlurRadius,
        min: 0.0,
        max: 4.0,
        displayValue: _settings.pencilBlurRadius.toStringAsFixed(1),
        onChanged: (v) => _update(_settings.copyWith(pencilBlurRadius: v)),
        cs: cs,
        tt: tt,
      ),
      _sliderRow(
        icon: Icons.touch_app_rounded,
        label: 'Pressure',
        tooltip:
            'How much pen pressure affects opacity and thickness. Higher values create more variation.',
        value: sensitivity,
        min: 0.0,
        max: 1.0,
        displayValue: '${(sensitivity * 100).round()}%',
        onChanged: (v) {
          final newMax = 0.8 + v * 0.8;
          final newMin = 0.5 - v * 0.3;
          _update(
            _settings.copyWith(
              pencilMinPressure: newMin.clamp(0.1, 0.7),
              pencilMaxPressure: newMax.clamp(0.8, 1.6),
            ),
          );
        },
        cs: cs,
        tt: tt,
      ),
    ];
  }

  // ── Ballpoint: Pressure Sensitivity ──
  List<Widget> _ballpointControls(ColorScheme cs, TextTheme tt, Color accent) {
    final sensitivity = ((_settings.ballpointMaxPressure - 0.8) / 1.0).clamp(
      0.0,
      1.0,
    );
    return [
      _presetChips(
        cs: cs,
        tt: tt,
        accent: accent,
        presets: {
          'Fine':
              () => _update(
                _settings.copyWith(
                  ballpointMinPressure: 0.8,
                  ballpointMaxPressure: 0.9,
                ),
              ),
          'Standard':
              () => _update(
                _settings.copyWith(
                  ballpointMinPressure: 0.7,
                  ballpointMaxPressure: 1.1,
                ),
              ),
        },
      ),
      const SizedBox(height: 4),
      _sliderRow(
        icon: Icons.touch_app_rounded,
        label: 'Pressure',
        tooltip:
            'Controls how much pen pressure affects line thickness. Low values give uniform width, high values vary with pressure.',
        value: sensitivity,
        min: 0.0,
        max: 1.0,
        displayValue: '${(sensitivity * 100).round()}%',
        onChanged: (v) {
          final newMax = 0.8 + v * 1.0;
          final newMin = 0.7 - v * 0.3;
          _update(
            _settings.copyWith(
              ballpointMinPressure: newMin.clamp(0.3, 1.0),
              ballpointMaxPressure: newMax.clamp(0.8, 1.8),
            ),
          );
        },
        cs: cs,
        tt: tt,
      ),
    ];
  }

  // ── Highlighter: Opacity + Width ──
  List<Widget> _highlighterControls(
    ColorScheme cs,
    TextTheme tt,
    Color accent,
  ) => [
    _presetChips(
      cs: cs,
      tt: tt,
      accent: accent,
      presets: {
        'Subtle':
            () => _update(
              _settings.copyWith(
                highlighterOpacity: 0.2,
                highlighterWidthMultiplier: 2.5,
              ),
            ),
        'Bold':
            () => _update(
              _settings.copyWith(
                highlighterOpacity: 0.55,
                highlighterWidthMultiplier: 4.0,
              ),
            ),
      },
    ),
    const SizedBox(height: 4),
    _sliderRow(
      icon: Icons.opacity_rounded,
      label: 'Opacity',
      tooltip:
          'The transparency of the highlighter. Lower values create a subtler highlight effect.',
      value: _settings.highlighterOpacity,
      min: 0.1,
      max: 0.7,
      displayValue: '${(_settings.highlighterOpacity * 100).round()}%',
      onChanged: (v) => _update(_settings.copyWith(highlighterOpacity: v)),
      cs: cs,
      tt: tt,
    ),
    _sliderRow(
      icon: Icons.width_normal_rounded,
      label: 'Width',
      tooltip:
          'Multiplies the base stroke width for the highlighter. Higher values create broader highlights.',
      value: _settings.highlighterWidthMultiplier,
      min: 1.5,
      max: 5.0,
      displayValue:
          '${_settings.highlighterWidthMultiplier.toStringAsFixed(1)}×',
      onChanged:
          (v) => _update(_settings.copyWith(highlighterWidthMultiplier: v)),
      cs: cs,
      tt: tt,
    ),
  ];

  // ── Stabilizer (common) ──
  Widget _buildStabilizer(ColorScheme cs, TextTheme tt, Color accent) {
    final label = switch (_settings.stabilizerLevel) {
      0 => 'Off',
      <= 3 => 'Light',
      <= 6 => 'Medium',
      <= 9 => 'Heavy',
      _ => 'Max',
    };
    return _sliderRow(
      icon: Icons.gesture_rounded,
      label: 'Stabilizer',
      tooltip:
          'Smooths out hand tremor and jitter. Higher levels produce steadier lines but add slight input lag.',
      value: _settings.stabilizerLevel.toDouble(),
      min: 0,
      max: 10,
      displayValue: label,
      divisions: 10,
      onChanged: (v) => _update(_settings.copyWith(stabilizerLevel: v.toInt())),
      cs: cs,
      tt: tt,
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  PRESET CHIPS
  // ════════════════════════════════════════════════════════════════

  Widget _presetChips({
    required ColorScheme cs,
    required TextTheme tt,
    required Color accent,
    required Map<String, VoidCallback> presets,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children:
          presets.entries.map((e) {
            return ActionChip(
              label: Text(
                e.key,
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
              onPressed: e.value,
              backgroundColor: accent.withValues(alpha: 0.08),
              side: BorderSide(
                color: accent.withValues(alpha: 0.25),
                width: 0.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  REUSABLE SLIDER / SWITCH  ROW
  // ════════════════════════════════════════════════════════════════

  Widget _presetChip(
    String label,
    IconData icon,
    ColorScheme cs,
    TextTheme tt,
    VoidCallback onTap,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 14),
      label: Text(label, style: tt.labelSmall),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
    );
  }

  Widget _sliderRow({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
    required ColorScheme cs,
    required TextTheme tt,
    String? tooltip,
    int? divisions,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tooltip != null) ...[
                  const SizedBox(width: 2),
                  _infoIcon(tooltip, cs),
                ],
              ],
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              displayValue,
              textAlign: TextAlign.end,
              style: tt.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required ColorScheme cs,
    required TextTheme tt,
    required Color accent,
    String? tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tooltip != null) ...[
                  const SizedBox(width: 2),
                  _infoIcon(tooltip, cs),
                ],
              ],
            ),
          ),
          SizedBox(
            height: 28,
            child: FittedBox(
              child: Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeThumbColor: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Live stroke preview ──
  Widget _buildStrokePreview(ColorScheme cs, Color accent) {
    return AnimatedBuilder(
      animation: _previewAnim,
      builder: (context, _) {
        final isComplete = _previewAnim.isCompleted;
        return Stack(
          children: [
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ClipRect(
                  clipper: _RevealClipper(_previewAnim.value),
                  child: CustomPaint(
                    size: const Size(double.infinity, 64),
                    painter: _StrokePreviewPainter(
                      penType: widget.currentBrush,
                      color: widget.currentColor ?? accent,
                      baseWidth: widget.currentWidth ?? 2.5,
                      settings: _settings,
                    ),
                  ),
                ),
              ),
            ),
            // ▶ Play / replay button
            Positioned(
              right: 4,
              top: 4,
              child: GestureDetector(
                onTap: () => _previewAnim.forward(from: 0.0),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: (isComplete ? cs.onSurfaceVariant : accent)
                        .withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isComplete
                        ? Icons.replay_rounded
                        : Icons.play_arrow_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Texture Controls ──
  Widget _buildTextureControls(ColorScheme cs, TextTheme tt, Color accent) {
    const textures = {
      'none': 'None',
      'pencilGrain': 'Pencil',
      'charcoal': 'Charcoal',
      'watercolor': 'Water',
      'canvas': 'Canvas',
      'kraft': 'Kraft',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.texture_rounded, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Texture',
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const Spacer(),
            _infoIcon(
              'Applies a texture overlay to strokes for a more natural feel.',
              cs,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children:
              textures.entries.map((e) {
                final isSelected = _settings.textureType == e.key;
                return ChoiceChip(
                  label: Text(
                    e.value,
                    style: tt.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: isSelected ? cs.onPrimary : null,
                    ),
                  ),
                  selected: isSelected,
                  onSelected:
                      (_) => _update(_settings.copyWith(textureType: e.key)),
                  selectedColor: accent,
                  backgroundColor: accent.withValues(alpha: 0.08),
                  side: BorderSide(
                    color: isSelected ? accent : accent.withValues(alpha: 0.25),
                    width: 0.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                );
              }).toList(),
        ),
        if (_settings.textureType != 'none') ...[
          const SizedBox(height: 8),
          _sliderRow(
            icon: Icons.grain_rounded,
            label: 'Intensity',
            tooltip: 'How strongly the texture shows through the stroke.',
            value: _settings.textureIntensity,
            min: 0.05,
            max: 1.0,
            displayValue: '${(_settings.textureIntensity * 100).round()}%',
            onChanged: (v) => _update(_settings.copyWith(textureIntensity: v)),
            cs: cs,
            tt: tt,
          ),
        ],
      ],
    );
  }

  // ── Pressure Curve ──
  Widget _buildPressureCurve(ColorScheme cs, TextTheme tt, Color accent) {
    final currentName = _settings.pressureCurve.presetName ?? 'custom';
    final curvePresets = {
      'linear': ('Linear', Icons.linear_scale_rounded),
      'soft': ('Soft', Icons.auto_awesome_rounded),
      'firm': ('Firm', Icons.fitness_center_rounded),
      'sCurve': ('S-Curve', Icons.ssid_chart_rounded),
      'heavy': ('Heavy', Icons.monitor_weight_rounded),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              'Pressure Curve',
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const Spacer(),
            _infoIcon(
              'Maps raw stylus pressure to output. Soft = light touch produces more, Firm = needs harder press, S-Curve = responsive in the middle.',
              cs,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children:
              curvePresets.entries.map((e) {
                final isSelected = currentName == e.key;
                return ChoiceChip(
                  avatar: Icon(e.value.$2, size: 14),
                  label: Text(
                    e.value.$1,
                    style: tt.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: isSelected ? cs.onPrimary : null,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (_) {
                    final preset = PressureCurve.presets[e.key];
                    if (preset != null) {
                      _update(_settings.copyWith(pressureCurve: preset));
                    }
                  },
                  selectedColor: accent,
                  backgroundColor: accent.withValues(alpha: 0.08),
                  side: BorderSide(
                    color: isSelected ? accent : accent.withValues(alpha: 0.25),
                    width: 0.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                );
              }).toList(),
        ),
      ],
    );
  }

  // ── Info icon with tooltip ──
  Widget _infoIcon(String message, ColorScheme cs) {
    return Tooltip(
      message: message,
      preferBelow: true,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        color: cs.onInverseSurface,
        fontSize: 12,
        height: 1.3,
      ),
      child: Icon(
        Icons.info_outline_rounded,
        size: 14,
        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

/// 🎨 Painter that renders a representative stroke with current settings.
/// Generates a sinusoidal wave with varying pressure to showcase brush effects.
class _StrokePreviewPainter extends CustomPainter {
  final ProPenType penType;
  final Color color;
  final double baseWidth;
  final ProBrushSettings settings;

  _StrokePreviewPainter({
    required this.penType,
    required this.color,
    required this.baseWidth,
    required this.settings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final points = switch (penType) {
      ProPenType.fountain => _fountainPoints(size),
      ProPenType.pencil => _pencilPoints(size),
      ProPenType.ballpoint => _ballpointPoints(size),
      ProPenType.highlighter => _highlighterPoints(size),
    };

    BrushEngine.renderStroke(
      canvas,
      points,
      color,
      baseWidth,
      penType,
      settings,
    );
  }

  /// Fountain: flowing S-curve with direction changes to showcase nib angle
  List<ProDrawingPoint> _fountainPoints(Size size) {
    const n = 80;
    final pts = <ProDrawingPoint>[];
    final px = size.width * 0.06;
    final w = size.width - px * 2;
    final cy = size.height / 2;
    final amp = size.height * 0.32;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final x = px + t * w;
      final y = cy + math.sin(t * math.pi * 3.0) * amp;
      final p = (math.sin(t * math.pi) * 0.7 +
              0.2 +
              0.1 * math.sin(t * math.pi * 6.0))
          .clamp(0.1, 1.0);
      pts.add(
        ProDrawingPoint(position: Offset(x, y), pressure: p, timestamp: i),
      );
    }
    return pts;
  }

  /// Pencil: loose sketch feel with jitter
  List<ProDrawingPoint> _pencilPoints(Size size) {
    const n = 60;
    final pts = <ProDrawingPoint>[];
    final px = size.width * 0.06;
    final w = size.width - px * 2;
    final cy = size.height / 2;
    final amp = size.height * 0.25;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final x = px + t * w;
      final jitter = math.sin(t * math.pi * 12.0) * 2.0;
      final y = cy + math.sin(t * math.pi * 2.0) * amp + jitter;
      final p = (0.3 + 0.4 * math.sin(t * math.pi * 4.0)).clamp(0.15, 0.7);
      pts.add(
        ProDrawingPoint(position: Offset(x, y), pressure: p, timestamp: i),
      );
    }
    return pts;
  }

  /// Ballpoint: smooth handwriting-like wave
  List<ProDrawingPoint> _ballpointPoints(Size size) {
    const n = 70;
    final pts = <ProDrawingPoint>[];
    final px = size.width * 0.06;
    final w = size.width - px * 2;
    final cy = size.height / 2;
    final amp = size.height * 0.2;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final x = px + t * w;
      final y = cy + math.sin(t * math.pi * 4.0) * amp * (1.0 - t * 0.3);
      final p = (0.5 + 0.15 * math.sin(t * math.pi * 3.0)).clamp(0.3, 0.8);
      pts.add(
        ProDrawingPoint(position: Offset(x, y), pressure: p, timestamp: i),
      );
    }
    return pts;
  }

  /// Highlighter: wide, nearly-straight line
  List<ProDrawingPoint> _highlighterPoints(Size size) {
    const n = 40;
    final pts = <ProDrawingPoint>[];
    final px = size.width * 0.08;
    final w = size.width - px * 2;
    final cy = size.height / 2;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final x = px + t * w;
      final y = cy + math.sin(t * math.pi * 2.0) * 3.0;
      pts.add(
        ProDrawingPoint(position: Offset(x, y), pressure: 0.5, timestamp: i),
      );
    }
    return pts;
  }

  @override
  bool shouldRepaint(_StrokePreviewPainter old) =>
      old.penType != penType ||
      old.color != color ||
      old.baseWidth != baseWidth ||
      old.settings != settings;
}

/// Clips the child to [0, fraction * width] to create a left-to-right reveal.
class _RevealClipper extends CustomClipper<Rect> {
  final double fraction;
  _RevealClipper(this.fraction);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_RevealClipper old) => old.fraction != fraction;
}
