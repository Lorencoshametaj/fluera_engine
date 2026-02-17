import 'dart:math' as math;
import 'package:flutter/material.dart';
import './pressure_curve.dart';
import './pro_drawing_point.dart';
import './pro_brush_settings.dart';
import '../brushes/brush_engine.dart';
import '../brushes/brush_texture.dart';

part '_brush_dialog_route.dart';
part '_brush_dialog_controls.dart';
part '_brush_dialog_stamp.dart';
part '_brush_dialog_widgets.dart';
part '_brush_dialog_preview.dart';

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
      ProPenType.watercolor =>
        isDark ? const Color(0xFF80DEEA) : const Color(0xFF00838F),
      ProPenType.marker =>
        isDark ? const Color(0xFFCE93D8) : const Color(0xFF7B1FA2),
      ProPenType.charcoal =>
        isDark ? const Color(0xFFBCAAA4) : const Color(0xFF5D4037),
      ProPenType.oilPaint =>
        isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0),
      ProPenType.sprayPaint =>
        isDark ? const Color(0xFFEF9A9A) : const Color(0xFFE53935),
      ProPenType.neonGlow =>
        isDark ? const Color(0xFF84FFFF) : const Color(0xFF00B8D4),
      ProPenType.inkWash =>
        isDark ? const Color(0xFF9E9E9E) : const Color(0xFF424242),
    };
  }

  IconData _brushIcon() => switch (widget.currentBrush) {
    ProPenType.fountain => Icons.edit_rounded,
    ProPenType.pencil => Icons.draw_rounded,
    ProPenType.ballpoint => Icons.create_rounded,
    ProPenType.highlighter => Icons.highlight_rounded,
    ProPenType.watercolor => Icons.water_drop_rounded,
    ProPenType.marker => Icons.format_paint_rounded,
    ProPenType.charcoal => Icons.texture_rounded,
    ProPenType.oilPaint => Icons.brush_rounded,
    ProPenType.sprayPaint => Icons.blur_on_rounded,
    ProPenType.neonGlow => Icons.flash_on_rounded,
    ProPenType.inkWash => Icons.water_rounded,
  };

  String _brushTitle() => switch (widget.currentBrush) {
    ProPenType.fountain => 'Fountain Pen',
    ProPenType.pencil => 'Pencil',
    ProPenType.ballpoint => 'Ballpoint',
    ProPenType.highlighter => 'Highlighter',
    ProPenType.watercolor => 'Watercolor',
    ProPenType.marker => 'Marker',
    ProPenType.charcoal => 'Charcoal',
    ProPenType.oilPaint => 'Oil Paint',
    ProPenType.sprayPaint => 'Spray Paint',
    ProPenType.neonGlow => 'Neon Glow',
    ProPenType.inkWash => 'Ink Wash',
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
                child: RepaintBoundary(child: buildStrokePreview(cs, accent)),
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
                        ...buildBrushControls(cs, tt, accent),
                        const SizedBox(height: 12),
                        _buildDivider(cs),
                        const SizedBox(height: 8),
                        buildStabilizer(cs, tt, accent),
                        const SizedBox(height: 12),
                        _buildDivider(cs),
                        const SizedBox(height: 8),
                        buildTextureControls(cs, tt, accent),
                        const SizedBox(height: 12),
                        _buildDivider(cs),
                        const SizedBox(height: 8),
                        buildPressureCurve(cs, tt, accent),
                        // ── Stamp Dynamics (only when stamp mode on) ──
                        if (_settings.stampEnabled) ...[
                          const SizedBox(height: 12),
                          _buildDivider(cs),
                          const SizedBox(height: 8),
                          buildStampDynamics(cs, tt, accent),
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
}
