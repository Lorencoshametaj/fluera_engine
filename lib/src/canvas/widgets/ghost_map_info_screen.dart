import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/fluera_localizations.g.dart';

// ── E-1: Design Tokens ──────────────────────────────────────────────────────
// All colors, durations, and sizing extracted for consistency and theming.

/// Design tokens for the Ghost Map info screen.
abstract final class _Tok {
  // Accent palette
  static const accent = Color(0xFF42A5F5);
  static const accentGreen = Color(0xFF66BB6A);
  static const accentGreenBright = Color(0xFF00C853);
  static const accentAmber = Color(0xFFFFB300);
  static const accentRed = Color(0xFFEF5350);
  static const accentRedDeep = Color(0xFFFF1744);
  static const accentGrey = Color(0xFF90A4AE);
  static const accentIndigo = Color(0xFF7986CB);

  // Surface palette
  static const bgDark = Color(0xFF0D1B2A);
  static const bgDarker = Color(0xFF0A0A1A);
  static const bgCard = Color(0xFF0D1B2A);
  static const bgCanvas = Color(0xFF0A0F1A);
  static const bgNavBar = Color(0xFF1A2332);
  static const bgHeader2 = Color(0xFF1B2838);

  // Durations
  static const staggerDuration = Duration(milliseconds: 2000);
  static const gradientDuration = Duration(seconds: 5);
  static const transitionDuration = Duration(milliseconds: 400);
  static const animSwitchDuration = Duration(milliseconds: 300);
  static const timerDemoDuration = Duration(seconds: 3);

  // Radii
  static const cardRadius = 16.0;
  static const chipRadius = 16.0;
  static const pillRadius = 12.0;
  static const tinyRadius = 8.0;
}

/// 🗺️ Ghost Map info screen — explains how the Ghost Map feature works.
///
/// Material Design 3 with dark theme, staggered animations, interactive
/// node type demo, and rich visual hierarchy. Matches the Socratic and
/// Fog of War info screens in style.
class GhostMapInfoScreen extends StatefulWidget {
  const GhostMapInfoScreen({super.key});

  static void show(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const GhostMapInfoScreen(),
        transitionsBuilder: (_, a, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  State<GhostMapInfoScreen> createState() => _GhostMapInfoScreenState();
}

class _GhostMapInfoScreenState extends State<GhostMapInfoScreen>
    with TickerProviderStateMixin {
  late final AnimationController _staggerController;
  late final AnimationController _gradientController;

  static const _totalSections = 10;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: _Tok.staggerDuration,
    )..forward();

    _gradientController = AnimationController(
      vsync: this,
      duration: _Tok.gradientDuration,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _gradientController.dispose();
    super.dispose();
  }

  /// Returns a staggered animation for item at [index].
  Animation<double> _fadeFor(int index) {
    final start = (index / _totalSections) * 0.6;
    final end = start + 0.4;
    return CurvedAnimation(
      parent: _staggerController,
      curve: Interval(start, end.clamp(0, 1), curve: Curves.easeOut),
    );
  }

  Widget _animated(int index, Widget child) {
    return FadeTransition(
      opacity: _fadeFor(index),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(_fadeFor(index)),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = FlueraLocalizations.of(context)!;
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _Tok.accent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      child: Semantics(
        label: l10n.ghostMapInfo_a11yLabel,
        explicitChildNodes: true,
        child: Scaffold(
        body: CustomScrollView(
          slivers: [
            // ── Animated App Bar ────────────────────────────────────
            SliverAppBar.large(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                l10n.ghostMapInfo_title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              flexibleSpace: AnimatedBuilder(
                animation: _gradientController,
                builder: (_, __) {
                  final t = _gradientController.value;
                  return FlexibleSpaceBar(
                    background: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(_Tok.bgDark,
                                _Tok.bgHeader2, t)!,
                            _Tok.bgDarker,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Content ─────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList.list(
                children: [
                  _animated(0, _heroCard(l10n)),
                  const SizedBox(height: 16),

                  _animated(1, _sectionTitle(l10n.ghostMapInfo_sectionHowItWorks)),
                  const SizedBox(height: 8),
                  _animated(1, _flowCard(l10n)),
                  const SizedBox(height: 16),

                  _animated(2, _sectionTitle(l10n.ghostMapInfo_sectionNodeTypes)),
                  const SizedBox(height: 8),
                  _animated(2, RepaintBoundary(child: _NodeTypeDemo(l10n: l10n))),
                  const SizedBox(height: 16),

                  _animated(3, _sectionTitle(l10n.ghostMapInfo_sectionAttempts)),
                  const SizedBox(height: 8),
                  _animated(3, _attemptCard(l10n)),
                  const SizedBox(height: 8),
                  _animated(3, RepaintBoundary(child: _AttemptFlowDemo(l10n: l10n))),
                  const SizedBox(height: 16),

                  _animated(4, _sectionTitle(l10n.ghostMapInfo_sectionHypercorrection)),
                  const SizedBox(height: 8),
                  _animated(4, _hypercorrectionCard(l10n)),
                  const SizedBox(height: 16),

                  _animated(5, _sectionTitle(l10n.ghostMapInfo_sectionZPD)),
                  const SizedBox(height: 8),
                  _animated(5, _zpdCard(l10n)),
                  const SizedBox(height: 16),

                  _animated(6, _sectionTitle(l10n.ghostMapInfo_sectionNavigation)),
                  const SizedBox(height: 8),
                  _animated(6, _navigationCard(l10n)),
                  const SizedBox(height: 16),

                  _animated(7, _sectionTitle(l10n.ghostMapInfo_sectionFSRS)),
                  const SizedBox(height: 8),
                  _animated(7, _fsrsCard(l10n)),
                  const SizedBox(height: 16),

                  _animated(8, _sectionTitle(l10n.ghostMapInfo_sectionGrowth)),
                  const SizedBox(height: 8),
                  _animated(8, _growthCard(l10n)),
                  const SizedBox(height: 8),
                  _animated(8, RepaintBoundary(child: _BeforeAfterDemo(l10n: l10n))),
                  const SizedBox(height: 16),

                  _animated(9, _sectionTitle(l10n.ghostMapInfo_sectionSleep)),
                  const SizedBox(height: 8),
                  _animated(9, _sleepCard(l10n)),
                  const SizedBox(height: 24),

                  // CTA
                  _animated(9, _ctaButton(l10n)),
                  const SizedBox(height: 16),

                  // Footer
                  Center(
                    child: Text(
                      l10n.ghostMapInfo_footer,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
          ),
      ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // WIDGETS
  // ════════════════════════════════════════════════════════════════════════

  Widget _heroCard(FlueraLocalizations l10n) {
    return Card(
      color: _Tok.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Animated pulsing ghost node
                _PulsingGhostNode(animation: _gradientController),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.ghostMapInfo_heroTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _Tok.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.ghostMapInfo_heroDescription,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _Tok.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _Tok.accent.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 18, color: _Tok.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.ghostMapInfo_heroPrinciple,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _flowCard(FlueraLocalizations l10n) {
    return Card(
      color: _Tok.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _flowStep('1', '✍️', l10n.ghostMapInfo_flowWrite, l10n.ghostMapInfo_flowWriteDesc),
            _flowDivider(),
            _flowStep('2', '🗺️', l10n.ghostMapInfo_flowActivate,
                l10n.ghostMapInfo_flowActivateDesc),
            _flowDivider(),
            _flowStep('3', '🤖', l10n.ghostMapInfo_flowAnalysis,
                l10n.ghostMapInfo_flowAnalysisDesc),
            _flowDivider(),
            _flowStep('4', '👻', l10n.ghostMapInfo_flowOverlay,
                l10n.ghostMapInfo_flowOverlayDesc),
            _flowDivider(),
            _flowStep('5', '✏️', l10n.ghostMapInfo_flowAttempt,
                l10n.ghostMapInfo_flowAttemptDesc),
            _flowDivider(),
            _flowStep('6', '🔍', l10n.ghostMapInfo_flowCompare,
                l10n.ghostMapInfo_flowCompareDesc),
            _flowDivider(),
            _flowStep('7', '📊', l10n.ghostMapInfo_flowResults,
                l10n.ghostMapInfo_flowResultsDesc),
          ],
        ),
      ),
    );
  }

  Widget _flowStep(
      String number, String emoji, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _Tok.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number,
                  style: const TextStyle(
                      color: _Tok.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 10),
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(description,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _flowDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 1,
          height: 12,
          color: _Tok.accent.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  Widget _attemptCard(FlueraLocalizations l10n) {
    return Card(
      color: _Tok.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.ghostMapInfo_attemptIntro,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _attemptRow(
              Icons.keyboard_rounded,
              l10n.ghostMapInfo_attemptType,
              l10n.ghostMapInfo_attemptTypeDesc,
              _Tok.accent,
            ),
            const SizedBox(height: 8),
            _attemptRow(
              Icons.draw_rounded,
              l10n.ghostMapInfo_attemptDraw,
              l10n.ghostMapInfo_attemptDrawDesc,
              _Tok.accentGreen,
            ),
            const SizedBox(height: 8),
            _attemptRow(
              Icons.visibility,
              l10n.ghostMapInfo_attemptReveal,
              l10n.ghostMapInfo_attemptRevealDesc,
              _Tok.accentAmber,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _Tok.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer, size: 14, color: _Tok.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.ghostMapInfo_attemptTimerNote,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attemptRow(
      IconData icon, String title, String description, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Icon(icon, size: 18, color: color)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              Text(description,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hypercorrectionCard(FlueraLocalizations l10n) {
    return Card(
      color: _Tok.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _Tok.accentRedDeep.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                      child: Text('⚡', style: TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.ghostMapInfo_hypercorrectionTitle,
                    style: TextStyle(
                      color: _Tok.accentRedDeep,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.ghostMapInfo_hypercorrectionDesc,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _Tok.accentRedDeep.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _Tok.accentRedDeep.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.ghostMapInfo_hypercorrectionCitation,
                    style: TextStyle(
                      color: _Tok.accentRedDeep.withValues(alpha: 0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.ghostMapInfo_hypercorrectionQuote,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.ghostMapInfo_hypercorrectionVisual,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zpdCard(FlueraLocalizations l10n) {
    return Card(
      color: _Tok.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                      child: Text('📚', style: TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.ghostMapInfo_zpdTitle,
                    style: TextStyle(
                      color: _Tok.accentGrey,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.ghostMapInfo_zpdDesc,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            _zpdRow(
              '🟢',
              l10n.ghostMapInfo_zpdComfort,
              l10n.ghostMapInfo_zpdComfortDesc,
              _Tok.accentGreen,
            ),
            const SizedBox(height: 6),
            _zpdRow(
              '🟡',
              l10n.ghostMapInfo_zpdZone,
              l10n.ghostMapInfo_zpdZoneDesc,
              _Tok.accentAmber,
            ),
            const SizedBox(height: 6),
            _zpdRow(
              '⚪',
              l10n.ghostMapInfo_zpdAdvanced,
              l10n.ghostMapInfo_zpdAdvancedDesc,
              _Tok.accentGrey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _zpdRow(
      String emoji, String title, String description, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              Text(description,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _navigationCard(FlueraLocalizations l10n) {
    return Card(
      color: _Tok.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.ghostMapInfo_navIntro,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            // Mock navigation bar
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _Tok.bgNavBar,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left,
                        size: 20, color: Colors.white.withValues(alpha: 0.5)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _Tok.accentRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('🔴 3',
                          style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _Tok.accentAmber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('🟡 2',
                          style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    Text('2/5',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right,
                        size: 20, color: Colors.white.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Icon(Icons.close,
                        size: 16, color: Colors.white.withValues(alpha: 0.3)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _navFeature(
              Icons.circle, l10n.ghostMapInfo_navMissing,
              l10n.ghostMapInfo_navMissingDesc,
              _Tok.accentRed,
            ),
            const SizedBox(height: 6),
            _navFeature(
              Icons.circle, l10n.ghostMapInfo_navWeak,
              l10n.ghostMapInfo_navWeakDesc,
              _Tok.accentAmber,
            ),
            const SizedBox(height: 6),
            _navFeature(
              Icons.pan_tool_alt, l10n.ghostMapInfo_navArrows,
              l10n.ghostMapInfo_navArrowsDesc,
              _Tok.accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navFeature(
      IconData icon, String title, String description, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              Text(description,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fsrsCard(FlueraLocalizations l10n) {
    return Card(
      color: _Tok.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_repeat,
                    size: 20, color: _Tok.accent),
                const SizedBox(width: 8),
                Text(
                  l10n.ghostMapInfo_fsrsTitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _fsrsRow('✅', l10n.ghostMapInfo_fsrsCorrect, l10n.ghostMapInfo_fsrsCorrectEffect,
                _Tok.accentGreen),
            const SizedBox(height: 6),
            _fsrsRow('❌', l10n.ghostMapInfo_fsrsWrong, l10n.ghostMapInfo_fsrsWrongEffect,
                _Tok.accentRed),
            const SizedBox(height: 6),
            _fsrsRow('⚡', l10n.ghostMapInfo_fsrsHyper, l10n.ghostMapInfo_fsrsHyperEffect,
                const Color(0xFFFF9800)),
            const SizedBox(height: 6),
            _fsrsRow('👁', l10n.ghostMapInfo_fsrsRevealed, l10n.ghostMapInfo_fsrsRevealedEffect,
                const Color(0xFF78909C)),
            const SizedBox(height: 6),
            _fsrsRow('🟢', l10n.ghostMapInfo_fsrsOnCanvas, l10n.ghostMapInfo_fsrsOnCanvasEffect,
                _Tok.accent),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _Tok.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.ghostMapInfo_fsrsNote,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fsrsRow(String emoji, String label, String effect, Color color) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(effect,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
      ],
    );
  }

  Widget _growthCard(FlueraLocalizations l10n) {
    return Card(
      color: _Tok.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('📈', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Text(
                  l10n.ghostMapInfo_growthTitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.ghostMapInfo_growthIntro,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            _growthRow('✅', l10n.ghostMapInfo_growthCorrect, l10n.ghostMapInfo_growthCorrectDesc),
            const SizedBox(height: 4),
            _growthRow('⚠️', l10n.ghostMapInfo_growthImprove, l10n.ghostMapInfo_growthImproveDesc),
            const SizedBox(height: 4),
            _growthRow('❓', l10n.ghostMapInfo_growthMissing, l10n.ghostMapInfo_growthMissingDesc),
            const SizedBox(height: 4),
            _growthRow('🎯', l10n.ghostMapInfo_growthAttempts, l10n.ghostMapInfo_growthAttemptsDesc),
            const SizedBox(height: 4),
            _growthRow('📈', l10n.ghostMapInfo_growthPercent, l10n.ghostMapInfo_growthPercentDesc),
            const SizedBox(height: 12),
            // Mock progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: 0.65,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                color: _Tok.accent,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                l10n.ghostMapInfo_growthExplored(65),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _growthRow(String emoji, String label, String description) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const Spacer(),
        Flexible(
          child: Text(description,
              textAlign: TextAlign.end,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
        ),
      ],
    );
  }

  Widget _sleepCard(FlueraLocalizations l10n) {
    return Card(
      color: _Tok.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🌙', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Text(
                  l10n.ghostMapInfo_sleepTitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.ghostMapInfo_sleepDesc,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF1A237E).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bedtime,
                      size: 14, color: _Tok.accentIndigo),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.ghostMapInfo_sleepCitation,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctaButton(FlueraLocalizations l10n) {
    return FilledButton.icon(
      onPressed: () => Navigator.of(context).pop(),
      icon: const Icon(Icons.arrow_back),
      label: Text(l10n.ghostMapInfo_cta),
      style: FilledButton.styleFrom(
        backgroundColor: _Tok.accent,
        foregroundColor: const Color(0xFF0A0A1A),
        padding: const EdgeInsets.symmetric(vertical: 14),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Interactive Node Type Demo — isolated StatefulWidget for minimal rebuilds
// ════════════════════════════════════════════════════════════════════════════

class _NodeTypeDemo extends StatefulWidget {
  final FlueraLocalizations l10n;
  const _NodeTypeDemo({required this.l10n});

  @override
  State<_NodeTypeDemo> createState() => _NodeTypeDemoState();
}

class _NodeTypeDemoState extends State<_NodeTypeDemo> {
  int _selectedIndex = -1;

  List<_NodeTypeInfo> get _types => [
    _NodeTypeInfo(
      emoji: '❓',
      title: widget.l10n.ghostMapInfo_nodeMissingTitle,
      color: _Tok.accentRed,
      description: widget.l10n.ghostMapInfo_nodeMissingDesc,
      principle: widget.l10n.ghostMapInfo_nodeMissingPrinciple,
    ),
    _NodeTypeInfo(
      emoji: '⚠️',
      title: widget.l10n.ghostMapInfo_nodeWeakTitle,
      color: _Tok.accentAmber,
      description: widget.l10n.ghostMapInfo_nodeWeakDesc,
      principle: widget.l10n.ghostMapInfo_nodeWeakPrinciple,
    ),
    _NodeTypeInfo(
      emoji: '✅',
      title: widget.l10n.ghostMapInfo_nodeCorrectTitle,
      color: _Tok.accentGreen,
      description: widget.l10n.ghostMapInfo_nodeCorrectDesc,
      principle: widget.l10n.ghostMapInfo_nodeCorrectPrinciple,
    ),
    _NodeTypeInfo(
      emoji: '⭐',
      title: widget.l10n.ghostMapInfo_nodeExcellentTitle,
      color: _Tok.accentGreenBright,
      description: widget.l10n.ghostMapInfo_nodeExcellentDesc,
      principle: widget.l10n.ghostMapInfo_nodeExcellentPrinciple,
    ),
    _NodeTypeInfo(
      emoji: '⚡',
      title: widget.l10n.ghostMapInfo_nodeHyperTitle,
      color: _Tok.accentRedDeep,
      description: widget.l10n.ghostMapInfo_nodeHyperDesc,
      principle: widget.l10n.ghostMapInfo_nodeHyperPrinciple,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _Tok.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.l10n.ghostMapInfo_nodeTypeTapHint,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            // Node pills row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_types.length, (i) {
                final type = _types[i];
                final isSelected = _selectedIndex == i;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedIndex = i);
                    HapticFeedback.lightImpact();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: isSelected ? 54 : 44,
                    height: isSelected ? 54 : 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? type.color.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: isSelected
                            ? type.color
                            : Colors.white.withValues(alpha: 0.1),
                        width: isSelected ? 2.5 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: type.color.withValues(alpha: 0.3),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(type.emoji,
                          style: TextStyle(
                              fontSize: isSelected ? 22 : 18)),
                    ),
                  ),
                );
              }),
            ),
            // Selected info
            if (_selectedIndex >= 0) ...[
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _buildNodeInfo(_types[_selectedIndex]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNodeInfo(_NodeTypeInfo type) {
    return Container(
      key: ValueKey(type.title),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: type.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: type.color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(type.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(type.title,
                  style: TextStyle(
                      color: type.color,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(type.description,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                  height: 1.4)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: type.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(type.principle,
                style: TextStyle(
                    color: type.color.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _NodeTypeInfo {
  final String emoji;
  final String title;
  final Color color;
  final String description;
  final String principle;

  const _NodeTypeInfo({
    required this.emoji,
    required this.title,
    required this.color,
    required this.description,
    required this.principle,
  });
}

// ════════════════════════════════════════════════════════════════════════════
// Pulsing Ghost Node — animated dashed circle in the hero card
// ════════════════════════════════════════════════════════════════════════════

class _PulsingGhostNode extends StatelessWidget {
  final Animation<double> animation;
  const _PulsingGhostNode({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final t = animation.value;
        final scale = 1.0 + 0.08 * math.sin(t * math.pi * 2);
        final glowAlpha = 0.15 + 0.1 * math.sin(t * math.pi * 2);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _Tok.accent.withValues(alpha: 0.6),
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
              boxShadow: [
                BoxShadow(
                  color: _Tok.accent.withValues(alpha: glowAlpha),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: CustomPaint(
              painter: _DashedCirclePainter(
                color: _Tok.accent.withValues(alpha: 0.4),
                dashCount: 12,
                rotation: t * math.pi * 2,
              ),
              child: const Center(
                child: Text('🗺️', style: TextStyle(fontSize: 20)),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final int dashCount;
  final double rotation;

  _DashedCirclePainter({
    required this.color,
    required this.dashCount,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    final dashAngle = (2 * math.pi) / (dashCount * 2);

    for (int i = 0; i < dashCount; i++) {
      final startAngle = rotation + i * dashAngle * 2;
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(rect, startAngle, dashAngle, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) =>
      rotation != old.rotation || color != old.color;
}

// ════════════════════════════════════════════════════════════════════════════
// Attempt Flow Demo — interactive mini-simulation of the reveal timer
// ════════════════════════════════════════════════════════════════════════════

class _AttemptFlowDemo extends StatefulWidget {
  final FlueraLocalizations l10n;
  const _AttemptFlowDemo({required this.l10n});

  @override
  State<_AttemptFlowDemo> createState() => _AttemptFlowDemoState();
}

class _AttemptFlowDemoState extends State<_AttemptFlowDemo>
    with SingleTickerProviderStateMixin {
  int _step = 0; // 0=idle, 1=thinking, 2=revealed, 3=correct, 4=wrong
  late final AnimationController _timerController;
  Timer? _resetTimer; // E-3: Cancellable auto-reset timer

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      vsync: this,
      duration: _Tok.timerDemoDuration,
    );
    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _step == 1) {
        setState(() => _step = 2);
        HapticFeedback.mediumImpact();
      }
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel(); // E-3: Prevent setState after dispose
    _timerController.dispose();
    super.dispose();
  }

  void _startDemo() {
    _resetTimer?.cancel();
    setState(() => _step = 1);
    _timerController.forward(from: 0);
    HapticFeedback.lightImpact();
  }

  void _selectResult(bool correct) {
    setState(() => _step = correct ? 3 : 4);
    HapticFeedback.heavyImpact();
    // E-3: Cancellable auto-reset
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _step = 0);
    });
  }

  void _reset() {
    _resetTimer?.cancel();
    setState(() {
      _step = 0;
      _timerController.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Interactive attempt flow demonstration',
      explicitChildNodes: true,
      child: Card(
      key: const Key('ghost_map_info_attempt_demo'),
      color: _Tok.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.touch_app, size: 16, color: _Tok.accent),
                const SizedBox(width: 6),
                Text(
                  widget.l10n.ghostMapInfo_demoTitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // State machine visualization
            AnimatedSwitcher(
              duration: _Tok.animSwitchDuration,
              child: _buildStep(),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _idleStep();
      case 1:
        return _thinkingStep();
      case 2:
        return _revealedStep();
      case 3:
        return _resultStep(true);
      case 4:
        return _resultStep(false);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _idleStep() {
    return GestureDetector(
      key: const ValueKey('idle'),
      onTap: _startDemo,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: _Tok.accentRed.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _Tok.accentRed.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('❓', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Text(
              widget.l10n.ghostMapInfo_demoTapToStart,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thinkingStep() {
    return Container(
      key: const ValueKey('thinking'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _Tok.accentAmber.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _Tok.accentAmber.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Text(widget.l10n.ghostMapInfo_demoThinking, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _timerController,
            builder: (_, __) {
              return Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _timerController.value,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      color: _Tok.accentAmber,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(3 - 3 * _timerController.value).ceil()}s',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _revealedStep() {
    return Container(
      key: const ValueKey('revealed'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _Tok.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _Tok.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Text(widget.l10n.ghostMapInfo_demoRevealTitle, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.l10n.ghostMapInfo_demoRevealExample,
              style: TextStyle(
                color: _Tok.accent,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.l10n.ghostMapInfo_demoRevealQuestion,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _selectResult(true),
                icon: const Icon(Icons.check, size: 16),
                label: Text(widget.l10n.ghostMapInfo_demoYes),
                style: FilledButton.styleFrom(
                  backgroundColor: _Tok.accentGreen.withValues(alpha: 0.15),
                  foregroundColor: _Tok.accentGreen,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: () => _selectResult(false),
                icon: const Icon(Icons.close, size: 16),
                label: Text(widget.l10n.ghostMapInfo_demoNo),
                style: FilledButton.styleFrom(
                  backgroundColor: _Tok.accentRed.withValues(alpha: 0.15),
                  foregroundColor: _Tok.accentRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultStep(bool correct) {
    final color = correct ? _Tok.accentGreen : _Tok.accentRed;
    final emoji = correct ? '✅' : '⚡';
    final title = correct
        ? widget.l10n.ghostMapInfo_demoCorrect
        : widget.l10n.ghostMapInfo_demoWrong;
    final fsrsLabel = correct
        ? widget.l10n.ghostMapInfo_demoFsrsUp
        : widget.l10n.ghostMapInfo_demoFsrsDown;

    return GestureDetector(
      key: ValueKey('result_$correct'),
      onTap: _reset,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text('$emoji $title',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(fsrsLabel,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
            const SizedBox(height: 4),
            Text(widget.l10n.ghostMapInfo_demoRetry,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Before/After Demo — interactive toggle showing canvas growth
// ════════════════════════════════════════════════════════════════════════════

class _BeforeAfterDemo extends StatefulWidget {
  final FlueraLocalizations l10n;
  const _BeforeAfterDemo({required this.l10n});

  @override
  State<_BeforeAfterDemo> createState() => _BeforeAfterDemoState();
}

class _BeforeAfterDemoState extends State<_BeforeAfterDemo> {
  bool _showAfter = false;

  // Before: student's original map (sparse)
  static const _beforeNodes = [
    _MockNode('Cellula', 0.3, 0.3, Color(0xFF42A5F5)),
    _MockNode('DNA', 0.7, 0.25, Color(0xFF42A5F5)),
    _MockNode('Proteine', 0.5, 0.7, Color(0xFF42A5F5)),
  ];

  // After: with ghost nodes filled in
  static const _afterNodes = [
    _MockNode('Cellula', 0.3, 0.3, Color(0xFF42A5F5)),
    _MockNode('DNA', 0.7, 0.25, Color(0xFF42A5F5)),
    _MockNode('Proteine', 0.5, 0.7, Color(0xFF42A5F5)),
    _MockNode('RNA', 0.5, 0.2, Color(0xFF66BB6A)),
    _MockNode('Ribosomi', 0.65, 0.55, Color(0xFF66BB6A)),
    _MockNode('Mitocondri', 0.2, 0.6, Color(0xFF66BB6A)),
    _MockNode('ATP', 0.15, 0.45, Color(0xFFFFB300)),
  ];

  @override
  Widget build(BuildContext context) {
    final nodes = _showAfter ? _afterNodes : _beforeNodes;
    return Card(
      color: _Tok.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.cardRadius)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Toggle row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _toggleChip(widget.l10n.ghostMapInfo_beforeAfterBefore, !_showAfter, () {
                  setState(() => _showAfter = false);
                  HapticFeedback.selectionClick();
                }),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 14,
                    color: _Tok.accent),
                const SizedBox(width: 8),
                _toggleChip(widget.l10n.ghostMapInfo_beforeAfterAfter, _showAfter, () {
                  setState(() => _showAfter = true);
                  HapticFeedback.selectionClick();
                }),
              ],
            ),
            const SizedBox(height: 12),
            // Mini canvas
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _Tok.bgCanvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Stack(
                children: [
                  // Grid dots background
                  CustomPaint(
                    painter: _GridDotsPainter(),
                    size: Size.infinite,
                  ),
                  // Nodes
                  ...nodes.map((n) => _buildMockNode(n)),
                  // Connection lines (after only)
                  if (_showAfter)
                    CustomPaint(
                      painter: _ConnectionLinesPainter(),
                      size: Size.infinite,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _showAfter
                    ? widget.l10n.ghostMapInfo_beforeAfterResultAfter
                    : widget.l10n.ghostMapInfo_beforeAfterResultBefore,
                key: ValueKey(_showAfter),
                style: TextStyle(
                  color: (_showAfter
                          ? _Tok.accentGreen
                          : Colors.white)
                      .withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? _Tok.accent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(_Tok.cardRadius),
          border: Border.all(
            color: active
                ? _Tok.accent
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: active
                    ? _Tok.accent
                    : Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }

  Widget _buildMockNode(_MockNode n) {
    return Positioned(
      left: 0,
      top: 0,
      right: 0,
      bottom: 0,
      child: LayoutBuilder(
        builder: (_, constraints) {
          final x = n.x * constraints.maxWidth - 25;
          final y = n.y * constraints.maxHeight - 12;
          return Stack(
            children: [
              Positioned(
                left: x.clamp(0, constraints.maxWidth - 50),
                top: y.clamp(0, constraints.maxHeight - 24),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: n.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: n.color.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      n.label,
                      style: TextStyle(
                        color: n.color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MockNode {
  final String label;
  final double x, y;
  final Color color;
  const _MockNode(this.label, this.x, this.y, this.color);
}

class _GridDotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;
    const spacing = 20.0;
    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridDotsPainter old) => false;
}

class _ConnectionLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _Tok.accent.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw a few connections
    final connections = [
      [Offset(0.3 * size.width, 0.3 * size.height),
       Offset(0.5 * size.width, 0.2 * size.height)],
      [Offset(0.5 * size.width, 0.2 * size.height),
       Offset(0.7 * size.width, 0.25 * size.height)],
      [Offset(0.7 * size.width, 0.25 * size.height),
       Offset(0.65 * size.width, 0.55 * size.height)],
      [Offset(0.65 * size.width, 0.55 * size.height),
       Offset(0.5 * size.width, 0.7 * size.height)],
      [Offset(0.3 * size.width, 0.3 * size.height),
       Offset(0.2 * size.width, 0.6 * size.height)],
      [Offset(0.2 * size.width, 0.6 * size.height),
       Offset(0.15 * size.width, 0.45 * size.height)],
    ];

    for (final c in connections) {
      canvas.drawLine(c[0], c[1], paint);
    }
  }

  @override
  bool shouldRepaint(_ConnectionLinesPainter old) => false;
}
