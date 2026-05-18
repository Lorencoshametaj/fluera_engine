import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/material.dart';
import '../../drawing/models/brush_preset.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../l10n/fluera_localizations.dart';
import '../fluera_canvas_config.dart' show FlueraSubscriptionTier;

// ============================================================================
// TOOLBAR BRUSH STRIP — Category-tabbed preset selector (single row)
// ============================================================================

/// Professional Brush Strip with inline Writing / Artistic category toggle.
/// Single row: [📝|🎨] separator [pill pill pill ...]
/// Tap category to switch; tap pill to select; long-press for brush editor.
class ToolbarBrushStrip extends StatefulWidget {
  final List<BrushPreset> presets;
  final String? selectedPresetId;
  final bool isPenActive;
  final ValueChanged<BrushPreset> onPresetSelected;
  final VoidCallback? onLongPress;
  final bool isDark;

  /// Current user's subscription tier — pills render a 🔒 badge and
  /// suppress selection on Free for any preset NOT in
  /// [BrushPreset.freePresetIds]. Plus / Pro see no gating.
  final FlueraSubscriptionTier subscriptionTier;

  /// Fired when a Free user taps a locked preset. The host typically
  /// shows a paywall sheet / upgrade banner with the supplied message.
  /// When `null`, taps on locked pills are silently ignored (no UX,
  /// but no crash either).
  final void Function(String message)? onUpgradePrompt;

  const ToolbarBrushStrip({
    super.key,
    required this.presets,
    this.selectedPresetId,
    required this.isPenActive,
    required this.onPresetSelected,
    this.onLongPress,
    required this.isDark,
    this.subscriptionTier = FlueraSubscriptionTier.free,
    this.onUpgradePrompt,
  });

  @override
  State<ToolbarBrushStrip> createState() => _ToolbarBrushStripState();
}

class _ToolbarBrushStripState extends State<ToolbarBrushStrip> {
  // V1: category toggle removed — all non-GPU presets shown in a flat list.
  // Re-enable _CategoryToggle post-launch when GPU pens are ready.

  /// 🔒 Free-tier collapse state (2026-05-16): Free users see ONLY the
  /// brushes they can actually use; a trailing chip with the locked
  /// count reveals the Plus/Pro pills on tap. Plus/Pro tiers are
  /// unaffected (the chip never renders, all pills always visible).
  bool _showLockedOnFree = false;

  bool get _isFreeTier =>
      widget.subscriptionTier == FlueraSubscriptionTier.free;

  List<BrushPreset> get _allPresets => widget.presets.isNotEmpty
      ? widget.presets
      : BrushPreset.defaultPresets;

  /// Presets actually rendered. On Free + collapsed → free-only; on
  /// Free + expanded → all (with lock badges); on Plus/Pro → all.
  List<BrushPreset> get _visiblePresets {
    if (!_isFreeTier || _showLockedOnFree) return _allPresets;
    return _allPresets
        .where((p) => BrushPreset.freePresetIds.contains(p.id))
        .toList();
  }

  int get _lockedCount {
    if (!_isFreeTier) return 0;
    return _allPresets
        .where((p) => !BrushPreset.freePresetIds.contains(p.id))
        .length;
  }

  /// Whether [preset] is locked behind the user's tier. Free users are
  /// limited to [BrushPreset.freePresetIds]; Plus / Pro see no gating.
  bool _isLockedFor(BrushPreset preset) {
    if (!_isFreeTier) return false;
    return !BrushPreset.freePresetIds.contains(preset.id);
  }

  /// Pill tap dispatcher. Routes locked taps to the brush preview sheet
  /// (which then routes to [onUpgradePrompt] when the user accepts) and
  /// blocks the underlying selection (anti-fraud — even if the visual
  /// gate is bypassed via accessibility tools, the selection won't go
  /// through). Unlocked taps go straight to the host callback.
  void _onPillTap(BrushPreset preset, bool isLocked) {
    if (isLocked) {
      _showBrushPreviewSheet(preset);
      return;
    }
    widget.onPresetSelected(preset);
  }

  /// 🎨 Modal bottom sheet with a stylized preview stroke + brush name +
  /// description + paywall CTA. Replaces the previous "instant snackbar
  /// upgrade prompt" with a "preview before paywall" flow — the user
  /// sees what they'd get before being asked to pay.
  Future<void> _showBrushPreviewSheet(BrushPreset preset) async {
    // Resolve the user's currently-selected brush so the comparison row
    // shows their actual baseline (e.g. Highlighter), not a hardcoded
    // Everyday Pen. Falls through to null when nothing is selected or
    // the selection doesn't resolve — the sheet then defaults to
    // Everyday Pen via `_freeBaseline()`.
    BrushPreset? currentPreset;
    final selectedId = widget.selectedPresetId;
    if (selectedId != null && selectedId != preset.id) {
      for (final p in _allPresets) {
        if (p.id == selectedId) {
          currentPreset = p;
          break;
        }
      }
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BrushPreviewSheet(
        preset: preset,
        currentPreset: currentPreset,
        onUnlock: () {
          Navigator.of(ctx).pop();
          widget.onUpgradePrompt?.call(
            'Sblocca "${preset.name}" con Fluera Plus o Pro.',
          );
        },
      ),
    );
  }

  void _toggleLockedVisibility() {
    setState(() => _showLockedOnFree = !_showLockedOnFree);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showExpandChip = _isFreeTier && _lockedCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
      // AnimatedSize smooths the width change when the user toggles
      // locked visibility, so the strip grows/shrinks instead of
      // snapping.
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final preset in _visiblePresets)
              ToolbarBrushPill(
                key: ValueKey('brush_pill_${preset.id}'),
                preset: preset,
                isSelected: widget.selectedPresetId == preset.id,
                isPenActive: widget.isPenActive,
                isDark: widget.isDark,
                isLocked: _isLockedFor(preset),
                onTap: () => _onPillTap(preset, _isLockedFor(preset)),
                onLongPress: _isLockedFor(preset) ||
                        widget.selectedPresetId != preset.id
                    ? null
                    : widget.onLongPress,
              ),
            if (showExpandChip)
              _ExpandLockedChip(
                lockedCount: _lockedCount,
                isExpanded: _showLockedOnFree,
                isDark: widget.isDark,
                onTap: _toggleLockedVisibility,
              ),
          ],
        ),
      ),
    );
  }
}

/// 🔒 Trailing chip on the Free tier brush strip. Tap to reveal the
/// locked Plus/Pro brushes; tap again to hide them. The badge counter
/// communicates "there's more behind the paywall" without clutter.
class _ExpandLockedChip extends StatelessWidget {
  final int lockedCount;
  final bool isExpanded;
  final bool isDark;
  final VoidCallback onTap;

  const _ExpandLockedChip({
    required this.lockedCount,
    required this.isExpanded,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = FlueraLocalizations.of(context);
    final tooltip = isExpanded
        ? (l10n?.proCanvas_hideLockedBrushes ?? 'Hide locked')
        : (l10n?.proCanvas_unlockBrushes ?? 'Unlock more brushes');
    final accent = cs.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            splashColor: accent.withValues(alpha: 0.18),
            highlightColor: accent.withValues(alpha: 0.08),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isExpanded
                    ? accent.withValues(alpha: isDark ? 0.18 : 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: accent.withValues(alpha: isExpanded ? 0.45 : 0.22),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    isExpanded
                        ? Icons.lock_open_rounded
                        : Icons.workspace_premium_rounded,
                    size: 13,
                    color: accent,
                  ),
                  if (!isExpanded) ...[
                    const SizedBox(width: 3),
                    Text(
                      '$lockedCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accent,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact inline category toggle: two emoji buttons side by side.
class _CategoryToggle extends StatelessWidget {
  final BrushCategory activeCategory;
  final bool selectedInOtherCategory;
  final BrushCategory? selectedCategory;
  final bool isDark;
  final ValueChanged<BrushCategory> onCategoryChanged;

  const _CategoryToggle({
    required this.activeCategory,
    required this.selectedInOtherCategory,
    required this.selectedCategory,
    required this.isDark,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(9),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTab(context, '📝', 'Writing', BrushCategory.writing, cs),
          _buildTab(context, '🎨', 'Artistic', BrushCategory.artistic, cs),
        ],
      ),
    );
  }

  Widget _buildTab(
    BuildContext context,
    String emoji,
    String tooltip,
    BrushCategory category,
    ColorScheme cs,
  ) {
    final isActive = activeCategory == category;
    final hasDot = selectedInOtherCategory && selectedCategory == category;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: () => onCategoryChanged(category),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color:
                isActive
                    ? cs.primary.withValues(alpha: isDark ? 0.3 : 0.15)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              if (hasDot)
                Positioned(
                  top: -3,
                  right: -5,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Individual brush preset pill
class ToolbarBrushPill extends StatelessWidget {
  final BrushPreset preset;
  final bool isSelected;
  final bool isPenActive;
  final bool isDark;
  /// Free-tier lock — when true, the pill renders dimmed with a 🔒
  /// badge. The owning strip routes the tap to an upgrade prompt
  /// instead of selecting the preset.
  final bool isLocked;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ToolbarBrushPill({
    super.key,
    required this.preset,
    required this.isSelected,
    required this.isPenActive,
    required this.isDark,
    required this.onTap,
    this.onLongPress,
    this.isLocked = false,
  });

  /// Accent color based on pen type
  Color get _accentColor {
    switch (preset.penType) {
      case ProPenType.ballpoint:
        return isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2);
      case ProPenType.fountain:
        return isDark ? const Color(0xFF81C784) : const Color(0xFF388E3C);
      case ProPenType.pencil:
        return isDark ? const Color(0xFFFFB74D) : const Color(0xFFF57C00);
      case ProPenType.highlighter:
        return isDark ? const Color(0xFFFFF176) : const Color(0xFFFBC02D);
      case ProPenType.watercolor:
        return isDark ? const Color(0xFF80DEEA) : const Color(0xFF00838F);
      case ProPenType.marker:
        return isDark ? const Color(0xFFCE93D8) : const Color(0xFF7B1FA2);
      case ProPenType.charcoal:
        return isDark ? const Color(0xFFBCAAA4) : const Color(0xFF5D4037);
      case ProPenType.oilPaint:
        return isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);
      case ProPenType.sprayPaint:
        return isDark ? const Color(0xFFEF9A9A) : const Color(0xFFE53935);
      case ProPenType.neonGlow:
        return isDark ? const Color(0xFF84FFFF) : const Color(0xFF00B8D4);
      case ProPenType.inkWash:
        return isDark ? const Color(0xFF9E9E9E) : const Color(0xFF424242);
      case ProPenType.technicalPen:
        return isDark ? const Color(0xFF78909C) : const Color(0xFF37474F);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Locked pills never show as "active" even if their id matches the
    // current selection — paying-tier downgrades shouldn't leave a
    // dangling highlight on a now-forbidden brush.
    final isHighlighted = isSelected && isPenActive && !isLocked;
    final pillBody = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(
        horizontal: isHighlighted ? 10 : 7,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        gradient:
            isHighlighted
                ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _accentColor.withValues(alpha: isDark ? 0.35 : 0.18),
                    _accentColor.withValues(alpha: isDark ? 0.2 : 0.08),
                  ],
                )
                : null,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              isHighlighted
                  ? _accentColor.withValues(alpha: 0.6)
                  : Colors.transparent,
          width: 1.5,
        ),
        boxShadow:
            isHighlighted
                ? [
                  BoxShadow(
                    color: _accentColor.withValues(alpha: 0.25),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ]
                : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: isLocked ? 0.4 : 1.0,
            child: Text(
              preset.icon,
              style: TextStyle(fontSize: isHighlighted ? 16 : 14),
            ),
          ),
          if (isHighlighted) ...[
            const SizedBox(width: 5),
            Text(
              preset.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _accentColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );

    // 🔒 Free-tier lock badge — anchored top-right outside the pill
    // body so it doesn't shift the selected-state width animation.
    final lockBadge = Positioned(
      right: -2,
      top: -2,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: isDark ? Colors.black87 : Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.lock_rounded,
            size: 9,
            color: (isDark ? Colors.white : Colors.black87)
                .withValues(alpha: 0.7),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: isSelected && !isLocked ? onLongPress : null,
          borderRadius: BorderRadius.circular(10),
          splashColor: _accentColor.withValues(alpha: isLocked ? 0.05 : 0.2),
          highlightColor:
              _accentColor.withValues(alpha: isLocked ? 0.03 : 0.1),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              pillBody,
              if (isLocked) lockBadge,
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 🎨 BRUSH PREVIEW SHEET — Free-tier "see-before-you-buy" upgrade UX
//
// When a Free user taps a locked premium brush we open this modal sheet
// instead of jumping straight to a snackbar / paywall. The sheet shows:
//
//   • a stylized example stroke for the brush type (CustomPainter)
//   • the brush name + accent + a one-line description of the feel
//   • two CTAs: "Unlock with Plus" (fires onUpgradePrompt) / "Maybe later"
//
// Aligns with the trasparenza-first pillar — preview the value before
// asking for money — without hiding the paywall.
// ============================================================================

class _BrushPreviewSheet extends StatefulWidget {
  final BrushPreset preset;
  /// The user's currently-selected brush, used as the "Your current
  /// brush" baseline in the comparison row. Nullable — when omitted the
  /// sheet falls back to Everyday Pen so the row still renders.
  final BrushPreset? currentPreset;
  final VoidCallback onUnlock;

  const _BrushPreviewSheet({
    required this.preset,
    required this.onUnlock,
    this.currentPreset,
  });

  @override
  State<_BrushPreviewSheet> createState() => _BrushPreviewSheetState();
}

/// Test hook: when `true`, the preview sheet draws once and stops —
/// no auto-replay loop. Necessary because widget tests `pumpAndSettle`
/// would otherwise spin forever waiting for a never-stopping animation.
@visibleForTesting
bool debugDisableBrushPreviewAutoReplay = false;

class _BrushPreviewSheetState extends State<_BrushPreviewSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drawCtrl;
  late final Animation<double> _drawProgress;
  Timer? _loopTimer;

  /// How long the completed stroke sits visible before the next replay
  /// starts. Long enough to read the brush, short enough to feel alive.
  static const _loopPause = Duration(milliseconds: 2200);

  @override
  void initState() {
    super.initState();
    _drawCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _drawProgress = CurvedAnimation(
      parent: _drawCtrl,
      curve: Curves.easeOutCubic,
    );
    // Auto-replay loop: when the stroke completes, wait then redraw.
    // Manual tap (gesture detector below) also reschedules via this
    // same listener so the two flows don't fight.
    _drawCtrl.addStatusListener(_onAnimationStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _drawCtrl.forward();
    });
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      if (debugDisableBrushPreviewAutoReplay) return;
      _loopTimer?.cancel();
      _loopTimer = Timer(_loopPause, () {
        if (mounted) {
          _drawCtrl
            ..reset()
            ..forward();
        }
      });
    }
  }

  /// Called from the GestureDetector tap on the hero card. Cancels the
  /// pending auto-loop so the user-initiated replay isn't immediately
  /// followed by another one.
  void _manualReplay() {
    _loopTimer?.cancel();
    _drawCtrl
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    _drawCtrl.removeStatusListener(_onAnimationStatus);
    _drawCtrl.dispose();
    super.dispose();
  }

  BrushPreset get preset => widget.preset;

  /// "Your current brush" baseline for the comparison row.
  ///
  /// Resolution order:
  ///   1. `widget.currentPreset` — what the user is actually using
  ///      right now (e.g. they selected Highlighter, then tapped a
  ///      premium pill → comparison shows their Highlighter)
  ///   2. Built-in Everyday Pen as the canonical fallback
  ///   3. Any free preset id (if Everyday Pen was excluded from the
  ///      host's brush list)
  ///   4. First default preset (last-resort, never empty)
  BrushPreset _freeBaseline() {
    if (widget.currentPreset != null) return widget.currentPreset!;
    return BrushPreset.defaultPresets.firstWhere(
      (p) => p.id == 'builtin_everyday_pen',
      orElse: () => BrushPreset.defaultPresets.firstWhere(
        (p) => BrushPreset.freePresetIds.contains(p.id),
        orElse: () => BrushPreset.defaultPresets.first,
      ),
    );
  }

  /// Returns a stroke color that has enough contrast with [bg] so the
  /// preview is always visible. Most builtin brushes ship with near-black
  /// ink which works on the ivory paper card, but a hypothetical white /
  /// very-light brush would vanish — in that case we darken it so the
  /// preview still reads.
  Color _previewColorOn(Color bg, Color stroke) {
    final bgLum = bg.computeLuminance();
    final strokeLum = stroke.computeLuminance();
    // Contrast against light paper: if the stroke is itself very light
    // (luminance > 0.78) and the bg is light (>0.75), darken the stroke
    // so it doesn't disappear.
    if (bgLum > 0.75 && strokeLum > 0.78) {
      return Color.lerp(stroke, Colors.black, 0.55)!;
    }
    return stroke;
  }

  /// One-line "what this brush feels like" copy keyed off the pen type.
  /// Hardcoded IT — descriptions are short marketing copy that benefits
  /// from being tuned in one place rather than scattered across 16 ARB
  /// files. Other languages fall back to this string until phase 3
  /// translation lands (memory `feedback_auto_extract_ui_strings`).
  String _description() {
    switch (preset.penType) {
      case ProPenType.ballpoint:
        return 'Tratto pulito e costante, perfetto per scrivere veloce.';
      case ProPenType.fountain:
        return 'Spessore variabile sotto pressione — eleganza calligrafica.';
      case ProPenType.pencil:
        return 'Grana morbida tipo grafite, ottima per schizzi e annotazioni.';
      case ProPenType.highlighter:
        return 'Tratto largo e trasparente per sottolineare senza coprire.';
      case ProPenType.marker:
        return 'Inchiostro pieno e deciso — sezioni in evidenza, titoli.';
      case ProPenType.charcoal:
        return 'Tratto granuloso e sfumato, ideale per ombre artistiche.';
      case ProPenType.watercolor:
        return 'Inchiostro bagnato con sfumature naturali — solo Pro.';
      case ProPenType.oilPaint:
        return 'Pennellata densa e materica, per illustrazioni — solo Pro.';
      case ProPenType.sprayPaint:
        return 'Vernice spray con grana — effetti street art — solo Pro.';
      case ProPenType.neonGlow:
        return 'Tratto luminoso con alone — accenti luminosi — solo Pro.';
      case ProPenType.inkWash:
        return 'Inchiostro acquerellato — sfondi morbidi — solo Pro.';
      case ProPenType.technicalPen:
        return 'Linea sottile uniforme — schemi tecnici e diagrammi.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = FlueraLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                (l10n?.proCanvas_brushPreviewTagline ??
                        'Premium brush · preview')
                    .toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(preset.icon, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      preset.name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _manualReplay,
                child: _PreviewCard(
                  height: 100,
                  preset: preset,
                  strokeColor: _previewColorOn(
                      const Color(0xFFFAF8F3), preset.color),
                  outlineColor: cs.outlineVariant.withValues(alpha: 0.6),
                  progress: _drawProgress,
                ),
              ),

              // Comparison row: Free user's current brush (Everyday Pen
              // baseline) vs the premium brush they're previewing. Makes
              // the value diff concrete instead of abstract.
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ComparisonRow(
                      label: l10n?.proCanvas_brushPreviewYourCurrent ??
                          'Your current brush',
                      preset: _freeBaseline(),
                      progress: _drawProgress,
                      outlineColor:
                          cs.outlineVariant.withValues(alpha: 0.6),
                      isMuted: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ComparisonRow(
                      label: l10n?.proCanvas_brushPreviewThisOne ??
                          'This one',
                      preset: preset,
                      progress: _drawProgress,
                      outlineColor: cs.primary.withValues(alpha: 0.45),
                      accentLabel: cs.primary,
                      isMuted: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _description(),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: cs.onSurfaceVariant,
                      ),
                      child: Text(
                        l10n?.proCanvas_brushPreviewMaybeLater ??
                            'Maybe later',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: widget.onUnlock,
                      icon: const Icon(Icons.workspace_premium_rounded,
                          size: 18),
                      label: Text(
                        l10n?.proCanvas_brushPreviewUnlock ??
                            'Unlock with Plus',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable preview card shared by the hero preview and the smaller
/// comparison cards in the Free→Premium row. Renders the brush stroke
/// over an always-ivory paper background so dark-mode app themes don't
/// hide near-black ink.
class _PreviewCard extends StatelessWidget {
  final BrushPreset preset;
  final Color strokeColor;
  final Color outlineColor;
  final Animation<double> progress;
  final double height;

  const _PreviewCard({
    required this.preset,
    required this.strokeColor,
    required this.outlineColor,
    required this.progress,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8F3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: outlineColor, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: AnimatedBuilder(
          animation: progress,
          builder: (context, _) => CustomPaint(
            painter: _BrushPreviewPainter(
              penType: preset.penType,
              color: strokeColor,
              baseWidth: preset.baseWidth,
              isDark: false,
              progress: progress.value,
            ),
          ),
        ),
      ),
    );
  }
}

/// One cell of the Free→Premium comparison row: a labelled small
/// preview card. Tracks the same animation as the hero preview so all
/// three strokes draw in sync.
class _ComparisonRow extends StatelessWidget {
  final String label;
  final BrushPreset preset;
  final Animation<double> progress;
  final Color outlineColor;
  final Color? accentLabel;
  final bool isMuted;

  const _ComparisonRow({
    required this.label,
    required this.preset,
    required this.progress,
    required this.outlineColor,
    required this.isMuted,
    this.accentLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: accentLabel ?? cs.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        _PreviewCard(
          // 60dp gives each per-pen-type path room to breathe without
          // crowding the sheet vertically.
          height: 60,
          preset: preset,
          // Muted strokes (the Free baseline) render slightly faded so
          // the eye gravitates toward the premium side.
          strokeColor: isMuted
              ? Color.lerp(preset.color, const Color(0xFFFAF8F3), 0.35)!
              : preset.color,
          outlineColor: outlineColor,
          progress: progress,
        ),
      ],
    );
  }
}

/// Stylized example stroke for the preview sheet. Draws a single S-curve
/// across the available canvas and tunes color, width, opacity, and
/// texture per [ProPenType] so the user gets a "feel" of the brush
/// before paying. NOT a faithful render of the GPU brush engine — a
/// representative sample drawn with stock Flutter painting APIs.
class _BrushPreviewPainter extends CustomPainter {
  final ProPenType penType;
  final Color color;
  final double baseWidth;
  final bool isDark;

  /// 0.0 → empty card, 1.0 → fully drawn stroke. Driven by the sheet's
  /// AnimationController so the preview "writes itself" on open.
  final double progress;

  _BrushPreviewPainter({
    required this.penType,
    required this.color,
    required this.baseWidth,
    required this.isDark,
    this.progress = 1.0,
  });

  /// Returns the path family appropriate for [penType]. Four families:
  ///   • writing — cursive "n n" + swash (ballpoint, pencil)
  ///   • calligraphic — single broad S-swash with ascender (fountain,
  ///                    marker, technicalPen, charcoal stroke)
  ///   • horizontal — gently arcing underline (highlighter, inkWash)
  ///   • splat — closed organic blob (watercolor, oilPaint, sprayPaint,
  ///             neonGlow)
  ///
  /// Dispatching by [penType] is what gives each brush a recognisable
  /// silhouette in the preview — the previous design used a single
  /// "n n" path for all 12 types, so Marker, Fountain Pen and Pencil
  /// all looked like the same wave with different ink density.
  Path _pathFor(ProPenType penType, Size size) {
    switch (penType) {
      case ProPenType.ballpoint:
      case ProPenType.pencil:
        return _writingPath(size);
      case ProPenType.fountain:
      case ProPenType.marker:
      case ProPenType.charcoal:
        return _calligraphicPath(size);
      case ProPenType.highlighter:
      case ProPenType.inkWash:
      case ProPenType.technicalPen:
        return _horizontalPath(size);
      case ProPenType.watercolor:
      case ProPenType.oilPaint:
      case ProPenType.sprayPaint:
      case ProPenType.neonGlow:
        return _splatPath(size);
    }
  }

  /// Handwriting-like path — a single continuous cursive flow (two
  /// up-down arcs reminiscent of "n n" + a small upward swash). Reads
  /// more like a brush sample than an abstract S-curve.
  ///
  /// Each anchor is perturbed by deterministic ±jitter so the curve
  /// reads as a human hand motion rather than a mathematically perfect
  /// spline. Jitter is keyed off the index so it's stable across
  /// repaints (no Random — `shouldRepaint` stays meaningful).
  Path _writingPath(Size size) {
    final inset = size.width * 0.10;
    final w = size.width - inset * 2;
    final cy = size.height / 2;
    final amp = size.height * 0.28;
    final left = inset;
    final ascent = cy - amp * 0.9;
    final descent = cy + amp * 0.55;
    // Jitter scale — sub-pixel range so the curve still reads as
    // intentional, just no longer machine-perfect.
    final j = math.min(size.width, size.height) * 0.008;

    int seed = 0;
    Offset pt(double x, double y) {
      // Deterministic 2D jitter via a tiny PRNG keyed off `seed`.
      final hx = (((seed * 1103515245) + 12345) % 100) / 100.0 - 0.5;
      final hy = (((seed * 1664525) + 1013904223) % 100) / 100.0 - 0.5;
      seed++;
      return Offset(x + hx * j * 2, y + hy * j * 2);
    }

    final p0 = pt(left, descent);
    final c0a = pt(left + w * 0.05, ascent - amp * 0.10);
    final c0b = pt(left + w * 0.18, ascent - amp * 0.10);
    final p1 = pt(left + w * 0.25, descent);
    final c1a = pt(left + w * 0.32, descent + amp * 0.10);
    final c1b = pt(left + w * 0.38, ascent - amp * 0.05);
    final p2 = pt(left + w * 0.50, ascent + amp * 0.05);
    final c2a = pt(left + w * 0.60, ascent - amp * 0.10);
    final c2b = pt(left + w * 0.70, descent + amp * 0.05);
    final p3 = pt(left + w * 0.78, descent - amp * 0.10);
    final c3a = pt(left + w * 0.85, descent - amp * 0.30);
    final c3b = pt(left + w * 0.95, ascent + amp * 0.20);
    final p4 = pt(left + w, ascent + amp * 0.10);

    return Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(c0a.dx, c0a.dy, c0b.dx, c0b.dy, p1.dx, p1.dy)
      ..cubicTo(c1a.dx, c1a.dy, c1b.dx, c1b.dy, p2.dx, p2.dy)
      ..cubicTo(c2a.dx, c2a.dy, c2b.dx, c2b.dy, p3.dx, p3.dy)
      ..cubicTo(c3a.dx, c3a.dy, c3b.dx, c3b.dy, p4.dx, p4.dy);
  }

  /// Broad single S-swash with a leading ascender — reads as
  /// calligraphic / nib stroke. Used for fountain pen, marker, charcoal:
  /// pens whose value is their fluid expressive line.
  Path _calligraphicPath(Size size) {
    final w = size.width;
    final h = size.height;
    final inset = w * 0.08;
    final left = inset;
    final right = w - inset;
    final cy = h / 2;
    final amp = h * 0.30;
    return Path()
      ..moveTo(left, cy - amp * 0.55)
      ..cubicTo(
        left + w * 0.05, cy - amp * 1.05,
        left + w * 0.18, cy - amp * 0.95,
        left + w * 0.30, cy - amp * 0.20,
      )
      ..cubicTo(
        left + w * 0.40, cy + amp * 0.40,
        left + w * 0.55, cy + amp * 0.85,
        left + w * 0.70, cy + amp * 0.40,
      )
      ..cubicTo(
        left + w * 0.80, cy + amp * 0.10,
        left + w * 0.90, cy - amp * 0.20,
        right, cy - amp * 0.45,
      );
  }

  /// Long, almost-straight underline with a tiny dip in the middle.
  /// Reads as "highlight a sentence" — the natural use case for
  /// highlighter, ink wash, technical underline tool.
  Path _horizontalPath(Size size) {
    final w = size.width;
    final h = size.height;
    final inset = w * 0.08;
    final left = inset;
    final right = w - inset;
    final cy = h * 0.55; // slight bias below center, like a real underline
    final dip = h * 0.07;
    return Path()
      ..moveTo(left, cy)
      ..cubicTo(
        left + w * 0.25, cy - dip,
        left + w * 0.55, cy + dip,
        left + w * 0.78, cy - dip * 0.3,
      )
      ..cubicTo(
        left + w * 0.88, cy - dip * 0.5,
        left + w * 0.96, cy + dip * 0.2,
        right, cy,
      );
  }

  /// Closed organic blob — reads as a paint splat / wash patch.
  /// Used for watercolor, oilPaint, sprayPaint, neonGlow: brushes
  /// whose value is filling areas, not drawing lines.
  Path _splatPath(Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final rx = math.min(w * 0.38, h * 0.85);
    final ry = h * 0.36;
    return Path()
      ..moveTo(cx - rx, cy)
      ..cubicTo(
        cx - rx * 1.10, cy - ry * 1.15,
        cx - rx * 0.25, cy - ry * 1.30,
        cx + rx * 0.30, cy - ry * 0.90,
      )
      ..cubicTo(
        cx + rx * 1.15, cy - ry * 0.55,
        cx + rx * 1.05, cy + ry * 0.55,
        cx + rx * 0.25, cy + ry * 1.05,
      )
      ..cubicTo(
        cx - rx * 0.35, cy + ry * 1.25,
        cx - rx * 1.15, cy + ry * 0.40,
        cx - rx, cy,
      );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    _paintPaperTexture(canvas, size);

    // Path family is per-pen-type now (writing / calligraphic /
    // horizontal / splat) so each brush has a recognisable silhouette
    // even before texture details kick in.
    final path = _pathFor(penType, size);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final totalLen =
        metrics.fold<double>(0, (s, m) => s + m.length);
    if (totalLen <= 0) return;
    final visibleLen = (totalLen * progress).clamp(0.0, totalLen);

    // Stroke width scales with the card's height (100dp is the hero
    // reference). Without this, small comparison cards rendered the
    // stroke at the same absolute width as the hero, making mid- and
    // wide brushes overflow the 48–60dp viewport vertically. Clamped
    // to [0.55, 1.0] so the comparison cells stay legible.
    final viewportScale = (size.height / 100.0).clamp(0.55, 1.0);
    final coreWidth = (baseWidth.clamp(1.0, 12.0) + 3.0) * viewportScale;

    switch (penType) {
      case ProPenType.ballpoint:
        // Round 5: factor bumped 0.34→0.50 + secondary ink-core pass.
        // The previous 0.34 left Thick Marker (penType=ballpoint,
        // baseWidth=6) rendering nearly identical to Everyday Pen
        // (baseWidth=2) — both looked like thin ballpoint scribbles.
        // The bump and the darker inner pass make baseWidth swing
        // visually convincing across the ballpoint family.
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.92),
          maxRadius: coreWidth * 0.50,
          taper: 0.45,
          density: 0.7,
        );
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color,
          maxRadius: coreWidth * 0.30,
          taper: 0.40,
          density: 0.7,
        );
      case ProPenType.fountain:
        // Wide ink with pronounced taper — classic broad-nib calligraphy.
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.92),
          maxRadius: coreWidth * 0.75,
          taper: 0.7,
          density: 0.55,
        );
        // Inner darker thread for ink concentration.
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color,
          maxRadius: coreWidth * 0.38,
          taper: 0.55,
          density: 0.7,
        );
      case ProPenType.pencil:
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.78),
          maxRadius: coreWidth * 0.40,
          taper: 0.55,
          density: 0.55,
          jitter: 0.6,
        );
        _drawGrain(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.30),
          count: 26,
          spread: coreWidth * 0.55,
          dotRadius: 0.8,
        );
      case ProPenType.highlighter:
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.34),
          maxRadius: coreWidth * 1.7,
          taper: 0.15,
          density: 0.5,
          blend: BlendMode.multiply,
        );
      case ProPenType.marker:
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.93),
          maxRadius: coreWidth * 0.95,
          taper: 0.20,
          density: 0.55,
        );
      case ProPenType.charcoal:
        // Soft outer cloud + scratchy core.
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.30),
          maxRadius: coreWidth * 1.10,
          taper: 0.45,
          density: 0.55,
          blur: 2.0,
          jitter: 0.8,
        );
        _drawGrain(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.55),
          count: 60,
          spread: coreWidth * 1.6,
          dotRadius: 1.1,
        );
      case ProPenType.watercolor:
        // Wet halo (soft blur) + wet-edge accumulation (slightly darker
        // band along the stroke spine).
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.22),
          maxRadius: coreWidth * 1.5,
          taper: 0.35,
          density: 0.5,
          blur: 5.0,
        );
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.48),
          maxRadius: coreWidth * 0.55,
          taper: 0.65,
          density: 0.6,
        );
      case ProPenType.oilPaint:
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color,
          maxRadius: coreWidth * 1.15,
          taper: 0.25,
          density: 0.5,
        );
        _drawGrain(
          canvas, metrics, totalLen, visibleLen,
          color: Colors.white.withValues(alpha: 0.28),
          count: 30,
          spread: coreWidth * 0.9,
          dotRadius: 1.0,
        );
      case ProPenType.sprayPaint:
        // Pure stipple — denser at the spine, sparser at the edges.
        _drawGrain(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.65),
          count: 110,
          spread: coreWidth * 2.0,
          dotRadius: 1.1,
        );
        _drawGrain(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.85),
          count: 50,
          spread: coreWidth * 0.7,
          dotRadius: 0.9,
        );
      case ProPenType.neonGlow:
        // Outer halo + crisp white core.
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.45),
          maxRadius: coreWidth * 1.6,
          taper: 0.15,
          density: 0.5,
          blur: 6.0,
        );
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: Colors.white.withValues(alpha: 0.95),
          maxRadius: coreWidth * 0.38,
          taper: 0.50,
          density: 0.6,
        );
      case ProPenType.inkWash:
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color.withValues(alpha: 0.40),
          maxRadius: coreWidth * 2.0,
          taper: 0.20,
          density: 0.5,
          blur: 4.0,
        );
      case ProPenType.technicalPen:
        _drawStamps(
          canvas, metrics, totalLen, visibleLen,
          color: color,
          maxRadius: coreWidth * 0.22,
          taper: 0.05,
          density: 0.85,
        );
    }
  }

  /// Stamp-based renderer with pressure taper + progressive reveal.
  /// Walks the path metrics, drops circles at sampled points, and
  /// modulates radius by a sin-curve so the stroke is thin at the
  /// extremities and thick in the middle — the same shape a real
  /// pressure-sensitive pen produces on a casual hand motion.
  ///
  /// [taper] controls how much the stamp radius shrinks at the edges
  /// (0 = constant width, 1 = pure sine). [density] is the spacing
  /// factor: smaller = more stamps for smoother strokes (more cost).
  /// [jitter] adds deterministic positional noise scaled by maxRadius.
  void _drawStamps(
    Canvas canvas,
    List<PathMetric> metrics,
    double totalLen,
    double visibleLen, {
    required Color color,
    required double maxRadius,
    double taper = 0.5,
    double density = 0.55,
    double jitter = 0.0,
    double blur = 0.0,
    BlendMode? blend,
  }) {
    if (visibleLen <= 0 || maxRadius <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    if (blur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    }
    if (blend != null) paint.blendMode = blend;

    // Stamp every (maxRadius * density) units along the path — gives
    // overlapping circles that read as a continuous stroke.
    final step = math.max(0.4, maxRadius * density);
    final stamps = (visibleLen / step).floor().clamp(2, 800);

    for (int i = 0; i <= stamps; i++) {
      final pos = (i / stamps) * visibleLen;
      final t = visibleLen <= 0 ? 0.0 : pos / totalLen; // 0..progress
      // Pressure curve: thin at start (t→0) and end-of-stroke (t→1),
      // thick in the middle. Taper=0 disables (constant width).
      final pressure = (1 - taper) + taper * math.sin(math.pi * t.clamp(0.0, 1.0));
      final radius = maxRadius * pressure;
      final point = _sampleAt(metrics, pos);
      if (point == null) continue;
      Offset offset = point;
      if (jitter > 0) {
        final hx = ((i * 1103515245 + 12345) % 100) / 100.0 - 0.5;
        final hy = ((i * 1664525 + 1013904223) % 100) / 100.0 - 0.5;
        offset = offset.translate(hx * jitter * maxRadius,
            hy * jitter * maxRadius);
      }
      canvas.drawCircle(offset, radius, paint);
    }
  }

  /// Scatters [count] small dots along the visible portion of the path
  /// with deterministic jitter perpendicular to the spine. Used for
  /// texture-rich brushes (pencil grain, charcoal scatter, spray paint).
  void _drawGrain(
    Canvas canvas,
    List<PathMetric> metrics,
    double totalLen,
    double visibleLen, {
    required Color color,
    required int count,
    required double spread,
    double dotRadius = 1.0,
  }) {
    if (visibleLen <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (int i = 0; i < count; i++) {
      final t = (i + 0.5) / count;
      final pos = t * visibleLen;
      final tangent = _tangentAt(metrics, pos);
      if (tangent == null) continue;
      final hx = ((i * 1103515245 + 12345) % 100) / 100.0 - 0.5;
      final hy = ((i * 1664525 + 1013904223) % 100) / 100.0 - 0.5;
      // Bias jitter perpendicular to the spine so grains scatter around
      // the stroke rather than along it.
      final n = Offset(-tangent.vector.dy, tangent.vector.dx);
      final perp = n * (hy * spread);
      final along = tangent.vector * (hx * spread * 0.4);
      canvas.drawCircle(
        tangent.position + perp + along,
        dotRadius + (i % 3) * 0.25,
        paint,
      );
    }
  }

  /// Subtle paper-grain noise behind the stroke so the card doesn't
  /// look like a sterile rectangle. ~40 short hairlines arranged with
  /// deterministic positions.
  void _paintPaperTexture(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black)
          .withValues(alpha: 0.035)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    const lines = 38;
    for (int i = 0; i < lines; i++) {
      final hx = ((i * 1103515245 + 12345) % 1000) / 1000.0;
      final hy = ((i * 1664525 + 1013904223) % 1000) / 1000.0;
      final x = hx * size.width;
      final y = hy * size.height;
      // Tiny 2–4 px hairline at a deterministic angle.
      final len = 1.5 + ((i * 7919) % 30) / 14.0;
      final ang = ((i * 31337) % 360) * math.pi / 180.0;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + math.cos(ang) * len, y + math.sin(ang) * len),
        paint,
      );
    }
  }

  Offset? _sampleAt(List<PathMetric> metrics, double pos) {
    double running = 0;
    for (final m in metrics) {
      if (running + m.length >= pos) {
        return m.getTangentForOffset(pos - running)?.position;
      }
      running += m.length;
    }
    return metrics.last
        .getTangentForOffset(metrics.last.length)
        ?.position;
  }

  Tangent? _tangentAt(List<PathMetric> metrics, double pos) {
    double running = 0;
    for (final m in metrics) {
      if (running + m.length >= pos) {
        return m.getTangentForOffset(pos - running);
      }
      running += m.length;
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant _BrushPreviewPainter old) =>
      old.penType != penType ||
      old.color != color ||
      old.baseWidth != baseWidth ||
      old.isDark != isDark ||
      old.progress != progress;
}
