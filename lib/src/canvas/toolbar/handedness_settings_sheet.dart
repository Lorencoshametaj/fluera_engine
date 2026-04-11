import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/handedness_settings.dart';

/// 🖐️ HANDEDNESS SETTINGS SHEET
///
/// Premium bottom sheet for configuring hand preference and palm rejection.
/// Features animated hand illustration, grip position cards, zone preview.
class HandednessSettingsSheet extends StatefulWidget {
  final VoidCallback? onChanged;

  const HandednessSettingsSheet({super.key, this.onChanged});

  /// 🚀 FEATURE 7: Show on first launch (auto-triggered from canvas).
  static Future<void> showIfNeeded(
    BuildContext context, {
    VoidCallback? onChanged,
  }) async {
    if (HandednessSettings.instance.hasCompletedOnboarding) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => HandednessSettingsSheet(onChanged: onChanged),
    );
    HandednessSettings.instance.markOnboardingComplete();
  }

  @override
  State<HandednessSettingsSheet> createState() =>
      _HandednessSettingsSheetState();
}

class _HandednessSettingsSheetState extends State<HandednessSettingsSheet>
    with SingleTickerProviderStateMixin {
  final _settings = HandednessSettings.instance;

  // 🎬 FEATURE 5: Animation controller for hand illustration
  late AnimationController _animController;
  late Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _bounceAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onSettingChanged() {
    // Replay bounce animation on change
    _animController.forward(from: 0);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF7C6FF7) : const Color(0xFF5B4FCF);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── DRAG HANDLE ──
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // ── TITLE ──
              Row(
                children: [
                  Icon(Icons.back_hand_rounded, color: accent, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'Handedness & Palm Rejection',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── 🎬 ANIMATED HAND ILLUSTRATION ──
              _buildHandIllustration(isDark, accent),
              const SizedBox(height: 20),

              // ── HAND SELECTOR ──
              _buildHandSelector(isDark, accent),
              const SizedBox(height: 20),

              // ── GRIP POSITION ──
              _buildGripSelector(isDark, accent),
              const SizedBox(height: 20),

              // ── PALM REJECTION TOGGLE ──
              _buildPalmRejectionToggle(isDark, accent),

              // ── ZONE SIZE SLIDER ──
              if (_settings.palmRejectionEnabled) ...[
                const SizedBox(height: 16),
                _buildZoneSizeSlider(isDark, accent),
              ],

              const SizedBox(height: 12),

              // ── PALM ZONE PREVIEW ──
              if (_settings.palmRejectionEnabled)
                _buildZonePreview(isDark, accent),

              const SizedBox(height: 8),

              // ── FEATURES SUMMARY ──
              _buildFeaturesSummary(isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // 🎬 FEATURE 5: ANIMATED HAND ILLUSTRATION
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildHandIllustration(bool isDark, Color accent) {
    return AnimatedBuilder(
      animation: _bounceAnim,
      builder: (context, child) {
        return Transform.scale(
          scale: 0.8 + (_bounceAnim.value * 0.2),
          child: Opacity(
            opacity: _bounceAnim.value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: SizedBox(
        height: 90,
        width: double.infinity,
        child: CustomPaint(
          painter: _HandIllustrationPainter(
            isLeftHanded: _settings.isLeftHanded,
            gripPosition: _settings.gripPosition,
            accent: accent,
            isDark: isDark,
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // HAND SELECTOR (Left / Right)
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildHandSelector(bool isDark, Color accent) {
    return Row(
      children: [
        Expanded(
          child: _OptionCard(
            label: 'Left',
            icon: Icons.front_hand_rounded,
            isSelected: _settings.isLeftHanded,
            isDark: isDark,
            accent: accent,
            isMirrored: true,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _settings.handedness = Handedness.left);
              _onSettingChanged();
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _OptionCard(
            label: 'Right',
            icon: Icons.front_hand_rounded,
            isSelected: _settings.isRightHanded,
            isDark: isDark,
            accent: accent,
            isMirrored: false,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _settings.handedness = Handedness.right);
              _onSettingChanged();
            },
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // GRIP POSITION (4 options)
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildGripSelector(bool isDark, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Grip Position',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildGripOption(
              GripPosition.belowLeft,
              Alignment.bottomLeft,
              isDark,
              accent,
            ),
            const SizedBox(width: 8),
            _buildGripOption(
              GripPosition.belowRight,
              Alignment.bottomRight,
              isDark,
              accent,
            ),
            const SizedBox(width: 8),
            _buildGripOption(
              GripPosition.aboveLeft,
              Alignment.topLeft,
              isDark,
              accent,
            ),
            const SizedBox(width: 8),
            _buildGripOption(
              GripPosition.aboveRight,
              Alignment.topRight,
              isDark,
              accent,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGripOption(
    GripPosition position,
    Alignment dotAlign,
    bool isDark,
    Color accent,
  ) {
    final isSelected = _settings.gripPosition == position;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _settings.gripPosition = position);
          _onSettingChanged();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 60,
          decoration: BoxDecoration(
            color:
                isSelected
                    ? accent.withValues(alpha: 0.15)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              // Palm zone indicator
              Align(
                alignment: dotAlign,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? accent.withValues(alpha: 0.4)
                            : (isDark ? Colors.white12 : Colors.black12),
                    borderRadius: _cornerRadius(dotAlign),
                  ),
                ),
              ),
              // Pen indicator
              Align(
                alignment: _opposite(dotAlign),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.edit,
                    size: 14,
                    color:
                        isSelected
                            ? accent
                            : (isDark ? Colors.white30 : Colors.black26),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // PALM REJECTION TOGGLE
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildPalmRejectionToggle(bool isDark, Color accent) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Palm Rejection',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                'Ignore accidental palm touches',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: _settings.palmRejectionEnabled,
          activeTrackColor: accent,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            setState(() => _settings.palmRejectionEnabled = v);
            _onSettingChanged();
          },
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // ZONE SIZE SLIDER
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildZoneSizeSlider(bool isDark, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Palm Zone Size',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            Text(
              '${(_settings.palmZoneRatio * 100).round()}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: accent,
            inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.1),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: _settings.palmZoneRatio,
            min: 0.15,
            max: 0.50,
            divisions: 7,
            onChanged: (v) {
              setState(() => _settings.palmZoneRatio = v);
              _onSettingChanged();
            },
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // ZONE PREVIEW
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildZonePreview(bool isDark, Color accent) {
    return Container(
      height: 100,
      width: double.infinity,
      decoration: BoxDecoration(
        color:
            isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final zone = _settings.getPalmExclusionZone(
            Size(constraints.maxWidth, constraints.maxHeight),
          );
          return Stack(
            children: [
              if (zone != Rect.zero)
                Positioned(
                  left: zone.left,
                  top: zone.top,
                  width: zone.width,
                  height: zone.height,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.do_not_touch_rounded,
                        size: 20,
                        color: Colors.red.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              Center(
                child: Text(
                  'Palm rejection zone preview',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // FEATURES SUMMARY (active protection list)
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildFeaturesSummary(bool isDark) {
    if (!_settings.palmRejectionEnabled) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Active Protection',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color:
                  isDark ? Colors.greenAccent.shade200 : Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 6),
          _featureRow(
            '🔴',
            'Temporal rejection — blocks fingers during stylus use',
            isDark,
          ),
          _featureRow(
            '📐',
            'Area analysis — detects large elliptical contacts',
            isDark,
          ),
          _featureRow(
            '🎯',
            'Wrist guard — dynamic zone near pen position',
            isDark,
          ),
          _featureRow('📍', 'Zone rejection — corner exclusion area', isDark),
          _featureRow(
            '📳',
            'Haptic feedback — vibration on rejected touches',
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _featureRow(String emoji, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════════════════

  BorderRadius _cornerRadius(Alignment a) {
    const r = Radius.circular(10);
    if (a == Alignment.bottomRight)
      return const BorderRadius.only(bottomRight: r);
    if (a == Alignment.bottomLeft)
      return const BorderRadius.only(bottomLeft: r);
    if (a == Alignment.topRight) return const BorderRadius.only(topRight: r);
    return const BorderRadius.only(topLeft: r);
  }

  Alignment _opposite(Alignment a) {
    if (a == Alignment.bottomRight) return Alignment.topLeft;
    if (a == Alignment.bottomLeft) return Alignment.topRight;
    if (a == Alignment.topRight) return Alignment.bottomLeft;
    return Alignment.bottomRight;
  }
}

// ══════════════════════════════════════════════════════════════════════════
// OPTION CARD (Left/Right selector)
// ══════════════════════════════════════════════════════════════════════════

class _OptionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isDark;
  final Color accent;
  final bool isMirrored;
  final VoidCallback onTap;

  const _OptionCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isDark,
    required this.accent,
    required this.isMirrored,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? accent.withValues(alpha: 0.15)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Transform(
              alignment: Alignment.center,
              transform:
                  isMirrored
                      ? (Matrix4.identity()..setEntry(0, 0, -1.0))
                      : Matrix4.identity(),
              child: Icon(
                icon,
                size: 32,
                color:
                    isSelected
                        ? accent
                        : (isDark ? Colors.white30 : Colors.black26),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color:
                    isSelected
                        ? accent
                        : (isDark ? Colors.white54 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// 🎬 FEATURE 5: HAND ILLUSTRATION PAINTER
// ══════════════════════════════════════════════════════════════════════════

class _HandIllustrationPainter extends CustomPainter {
  final bool isLeftHanded;
  final GripPosition gripPosition;
  final Color accent;
  final bool isDark;

  _HandIllustrationPainter({
    required this.isLeftHanded,
    required this.gripPosition,
    required this.accent,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Draw tablet outline
    final tabletRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.15, h * 0.05, w * 0.7, h * 0.9),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      tabletRect,
      Paint()
        ..color =
            isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      tabletRect,
      Paint()
        ..color =
            isDark ? Colors.white.withValues(alpha: 0.15) : Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Draw palm zone (colored corner)
    final zoneRect = _getPalmZoneRect(w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(zoneRect, const Radius.circular(4)),
      Paint()..color = Colors.red.withValues(alpha: 0.2),
    );

    // Draw pen position (opposite side)
    final penPos = _getPenPosition(w, h);
    // Pen line
    final penEnd = Offset(
      penPos.dx + (isLeftHanded ? -15 : 15),
      penPos.dy - 20,
    );
    canvas.drawLine(
      penPos,
      penEnd,
      Paint()
        ..color = accent
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    // Pen dot (tip)
    canvas.drawCircle(penPos, 3, Paint()..color = accent);

    // Draw a wavy line (writing simulation)
    final path = Path();
    final startX = penPos.dx - (isLeftHanded ? 30 : -10);
    path.moveTo(startX, penPos.dy + 2);
    for (int i = 0; i < 5; i++) {
      final x = startX + (isLeftHanded ? -(i * 12.0) : (i * 12.0));
      final y = penPos.dy + 2 + (i.isEven ? -3 : 3);
      path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: 0.4)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Draw palm label
    final palmCenter = zoneRect.center;
    final textPainter = TextPainter(
      text: TextSpan(text: '🖐️', style: const TextStyle(fontSize: 20)),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(palmCenter.dx - 10, palmCenter.dy - 10));
  }

  Rect _getPalmZoneRect(double w, double h) {
    final tabletLeft = w * 0.15;
    final tabletTop = h * 0.05;
    final tabletW = w * 0.7;
    final tabletH = h * 0.9;
    final zoneW = tabletW * 0.35;
    final zoneH = tabletH * 0.5;

    switch (gripPosition) {
      case GripPosition.belowRight:
        return Rect.fromLTWH(
          tabletLeft + tabletW - zoneW,
          tabletTop + tabletH - zoneH,
          zoneW,
          zoneH,
        );
      case GripPosition.belowLeft:
        return Rect.fromLTWH(
          tabletLeft,
          tabletTop + tabletH - zoneH,
          zoneW,
          zoneH,
        );
      case GripPosition.aboveRight:
        return Rect.fromLTWH(
          tabletLeft + tabletW - zoneW,
          tabletTop,
          zoneW,
          zoneH,
        );
      case GripPosition.aboveLeft:
        return Rect.fromLTWH(tabletLeft, tabletTop, zoneW, zoneH);
    }
  }

  Offset _getPenPosition(double w, double h) {
    final tabletLeft = w * 0.15;
    final tabletTop = h * 0.05;
    final tabletW = w * 0.7;
    final tabletH = h * 0.9;

    // Pen is in the opposite quadrant from the palm
    switch (gripPosition) {
      case GripPosition.belowRight:
        return Offset(tabletLeft + tabletW * 0.35, tabletTop + tabletH * 0.35);
      case GripPosition.belowLeft:
        return Offset(tabletLeft + tabletW * 0.65, tabletTop + tabletH * 0.35);
      case GripPosition.aboveRight:
        return Offset(tabletLeft + tabletW * 0.35, tabletTop + tabletH * 0.65);
      case GripPosition.aboveLeft:
        return Offset(tabletLeft + tabletW * 0.65, tabletTop + tabletH * 0.65);
    }
  }

  @override
  bool shouldRepaint(covariant _HandIllustrationPainter old) =>
      isLeftHanded != old.isLeftHanded ||
      gripPosition != old.gripPosition ||
      accent != old.accent ||
      isDark != old.isDark;
}
