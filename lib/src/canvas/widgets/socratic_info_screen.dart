import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/fluera_localizations.g.dart';

/// 🔶 Socratic Method info screen — explains how the feature works.
///
/// Material Design 3 with dark theme, staggered animations, interactive
/// confidence demo, and rich visual hierarchy.
class SocraticInfoScreen extends StatefulWidget {
  const SocraticInfoScreen({super.key});

  static void show(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SocraticInfoScreen(),
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
  State<SocraticInfoScreen> createState() => _SocraticInfoScreenState();
}

class _SocraticInfoScreenState extends State<SocraticInfoScreen>
    with TickerProviderStateMixin {
  late final AnimationController _staggerController;
  late final AnimationController _gradientController;

  static const _totalSections = 9;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();

    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
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
    // A4: Resolve L10n once per build.
    final l10n = FlueraLocalizations.of(context)!;
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFB300),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
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
                l10n.socraticInfo_title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              flexibleSpace: AnimatedBuilder(
                animation: _gradientController,
                builder: (_, __) {
                  final t = _gradientController.value;
                  return FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(const Color(0xFF1A1A2E),
                                const Color(0xFF2A1A0E), t)!,
                            const Color(0xFF0A0A1A),
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

                  _animated(1, _sectionTitle(l10n.socraticInfo_howItWorks)),
                  const SizedBox(height: 8),
                  _animated(1, _flowCard(l10n)),
                  const SizedBox(height: 16),

                  _animated(2, _sectionTitle(l10n.socraticInfo_questionTypes)),
                  const SizedBox(height: 8),
                  _animated(2, _questionTypeCard(
                    emoji: '🔍', title: l10n.socraticInfo_typeLacunaTitle,
                    subtitle: l10n.socraticInfo_typeLacunaSubtitle,
                    description: l10n.socraticInfo_typeLacunaBody,
                    color: const Color(0xFF42A5F5),
                    principle: l10n.socraticInfo_typeLacunaPrinciple,
                  )),
                  const SizedBox(height: 8),
                  _animated(3, _questionTypeCard(
                    emoji: '⚔️', title: l10n.socraticInfo_typeChallengeTitle,
                    subtitle: l10n.socraticInfo_typeChallengeSubtitle,
                    description: l10n.socraticInfo_typeChallengeBody,
                    color: const Color(0xFFFF9800),
                    principle: l10n.socraticInfo_typeChallengePrinciple,
                  )),
                  const SizedBox(height: 8),
                  _animated(3, _questionTypeCard(
                    emoji: '🔬', title: l10n.socraticInfo_typeDepthTitle,
                    subtitle: l10n.socraticInfo_typeDepthSubtitle,
                    description: l10n.socraticInfo_typeDepthBody,
                    color: const Color(0xFF66BB6A),
                    principle: l10n.socraticInfo_typeDepthPrinciple,
                  )),
                  const SizedBox(height: 8),
                  _animated(4, _questionTypeCard(
                    emoji: '🌉', title: l10n.socraticInfo_typeTransferTitle,
                    subtitle: l10n.socraticInfo_typeTransferSubtitle,
                    description: l10n.socraticInfo_typeTransferBody,
                    color: const Color(0xFFAB47BC),
                    principle: l10n.socraticInfo_typeTransferPrinciple,
                  )),
                  const SizedBox(height: 16),

                  _animated(5, _sectionTitle(l10n.socraticInfo_tryConfidence)),
                  const SizedBox(height: 8),
                  _animated(5, const _ConfidenceDemo()),
                  const SizedBox(height: 16),

                  _animated(6, _sectionTitle(l10n.socraticInfo_breadcrumbSection)),
                  const SizedBox(height: 8),
                  _animated(6, _breadcrumbCard(l10n)),
                  const SizedBox(height: 16),

                  _animated(7, _sectionTitle(l10n.socraticInfo_spacedRepetition)),
                  const SizedBox(height: 8),
                  _animated(7, _fsrsCard(l10n)),
                  const SizedBox(height: 16),

                  _animated(8, _sectionTitle(l10n.socraticInfo_feedbackMatrix)),
                  const SizedBox(height: 8),
                  _animated(8, _feedbackMatrixCard(l10n)),
                  const SizedBox(height: 24),

                  // CTA
                  _animated(8, _ctaButton()),
                  const SizedBox(height: 16),

                  // Footer
                  Center(
                    child: Text(
                      l10n.socraticInfo_references,
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
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // WIDGETS
  // ════════════════════════════════════════════════════════════════════════

  Widget _heroCard(FlueraLocalizations l10n) {
    return Card(
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🔶', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.socraticInfo_heroTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFFB300),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.socraticInfo_heroBody,
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
                color: const Color(0xFFFFB300).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.psychology,
                      size: 18, color: Color(0xFFFFB300)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.socraticInfo_whyItWorks,
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
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _flowStep('1', '✍️', l10n.socraticInfo_flowStep1Title, l10n.socraticInfo_flowStep1Body),
            _flowDivider(),
            _flowStep('2', '🤖', l10n.socraticInfo_flowStep2Title, l10n.socraticInfo_flowStep2Body),
            _flowDivider(),
            _flowStep('3', '🔶', l10n.socraticInfo_flowStep3Title, l10n.socraticInfo_flowStep3Body),
            _flowDivider(),
            _flowStep('4', '🎯', l10n.socraticInfo_flowStep4Title, l10n.socraticInfo_flowStep4Body),
            _flowDivider(),
            _flowStep('5', '🧠', l10n.socraticInfo_flowStep5Title, l10n.socraticInfo_flowStep5Body),
            _flowDivider(),
            _flowStep('6', '✅', l10n.socraticInfo_flowStep6Title, l10n.socraticInfo_flowStep6Body),
            _flowDivider(),
            _flowStep('7', '📊', l10n.socraticInfo_flowStep7Title, l10n.socraticInfo_flowStep7Body),
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
              color: const Color(0xFFFFB300).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number,
                  style: const TextStyle(
                      color: Color(0xFFFFB300),
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
          color: const Color(0xFFFFB300).withValues(alpha: 0.2),
        ),
      ),
    );
  }

  Widget _questionTypeCard({
    required String emoji,
    required String title,
    required String subtitle,
    required String description,
    required Color color,
    required String principle,
  }) {
    return Card(
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: color,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(subtitle,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(description,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                          height: 1.4)),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(principle,
                        style: TextStyle(
                            color: color.withValues(alpha: 0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Confidence demo is now a separate widget (_ConfidenceDemo) below.

  Widget _breadcrumbCard(FlueraLocalizations l10n) {
    return Card(
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.socraticInfo_breadcrumbIntro,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _breadcrumbRow(
              '1', l10n.socraticInfo_breadcrumb1Title,
              l10n.socraticInfo_breadcrumb1Body,
              const Color(0xFF78909C),
            ),
            const SizedBox(height: 8),
            _breadcrumbRow(
              '2', l10n.socraticInfo_breadcrumb2Title,
              l10n.socraticInfo_breadcrumb2Body,
              const Color(0xFFFFB300),
            ),
            const SizedBox(height: 8),
            _breadcrumbRow(
              '3', l10n.socraticInfo_breadcrumb3Title,
              l10n.socraticInfo_breadcrumb3Body,
              const Color(0xFF66BB6A),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.socraticInfo_breadcrumbNote,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _breadcrumbRow(
      String number, String title, String description, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w600)),
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
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_repeat,
                    size: 20, color: Color(0xFF42A5F5)),
                const SizedBox(width: 8),
                Text(
                  l10n.socraticInfo_fsrsIntro,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _fsrsRow('✅', l10n.socraticInfo_fsrsCorrect, l10n.socraticInfo_fsrsCorrectEffect,
                const Color(0xFF66BB6A)),
            const SizedBox(height: 6),
            _fsrsRow('❌', l10n.socraticInfo_fsrsWrong, l10n.socraticInfo_fsrsWrongEffect,
                const Color(0xFFEF5350)),
            const SizedBox(height: 6),
            _fsrsRow('⚡', l10n.socraticInfo_fsrsHyper, l10n.socraticInfo_fsrsHyperEffect,
                const Color(0xFFFF9800)),
            const SizedBox(height: 6),
            _fsrsRow('💪', l10n.socraticInfo_fsrsHighConf, l10n.socraticInfo_fsrsHighConfEffect,
                const Color(0xFF42A5F5)),
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

  Widget _feedbackMatrixCard(FlueraLocalizations l10n) {
    return Card(
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.socraticInfo_matrixIntro,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            _matrixRow('💪', l10n.socraticInfo_matrixSolid,
                l10n.socraticInfo_matrixSolidMsg, const Color(0xFF66BB6A)),
            const SizedBox(height: 8),
            _matrixRow('🎯', l10n.socraticInfo_matrixSurprise,
                l10n.socraticInfo_matrixSurpriseMsg, const Color(0xFF4CAF50)),
            const SizedBox(height: 8),
            _matrixRow('📌', l10n.socraticInfo_matrixGap,
                l10n.socraticInfo_matrixGapMsg, const Color(0xFFFFB300)),
            const SizedBox(height: 8),
            _matrixRow('⚡', l10n.socraticInfo_matrixHyper,
                l10n.socraticInfo_matrixHyperMsg, const Color(0xFFEF5350)),
          ],
        ),
      ),
    );
  }

  Widget _matrixRow(
      String emoji, String label, String description, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
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
      ),
    );
  }

  Widget _ctaButton() {
    return FilledButton.icon(
      onPressed: () => Navigator.of(context).pop(),
      icon: const Icon(Icons.arrow_back),
      label: Text(FlueraLocalizations.of(context)?.socraticInfo_ctaButton ?? 'Torna al canvas e provalo!'),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFFB300),
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
// Interactive Confidence Demo — isolated StatefulWidget for minimal rebuilds
// ════════════════════════════════════════════════════════════════════════════

class _ConfidenceDemo extends StatefulWidget {
  const _ConfidenceDemo();

  @override
  State<_ConfidenceDemo> createState() => _ConfidenceDemoState();
}

class _ConfidenceDemoState extends State<_ConfidenceDemo> {
  int _selected = 0;

  static const _labels = ['', 'Non so', 'Forse…', 'Credo sì', 'Sicuro', 'Certissimo!'];
  static const _hapticLabels = ['', '🤏 Leggera', '🤏 Leggera', '✊ Media', '💪 Forte', '💪 Forte'];
  static const _colors = <Color>[
    Colors.transparent,
    Color(0xFF42A5F5), Color(0xFF42A5F5),
    Color(0xFFFFB300),
    Color(0xFFEF5350), Color(0xFFEF5350),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = FlueraLocalizations.of(context)!;
    return Card(
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.socraticInfo_confidencePromptDemo,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(5, (i) {
                final level = i + 1;
                final isSelected = _selected == level;
                final color = _colors[level];
                return GestureDetector(
                  onTap: () {
                    setState(() => _selected = level);
                    if (level >= 4) {
                      HapticFeedback.heavyImpact();
                    } else if (level == 3) {
                      HapticFeedback.mediumImpact();
                    } else {
                      HapticFeedback.lightImpact();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: isSelected ? 48 : 40,
                    height: isSelected ? 48 : 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? color.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.05),
                      border: Border.all(
                        color: isSelected
                            ? color
                            : Colors.white.withValues(alpha: 0.1),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(
                              color: color.withValues(alpha: 0.3),
                              blurRadius: 12,
                              spreadRadius: 2,
                            )]
                          : null,
                    ),
                    child: Center(
                      child: Text('$level',
                          style: TextStyle(
                            color: isSelected ? color : Colors.white54,
                            fontSize: isSelected ? 18 : 15,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _selected > 0
                  ? Container(
                      key: ValueKey(_selected),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _colors[_selected].withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _colors[_selected].withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(_hapticLabels[_selected],
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_labels[_selected]} — vibrazione '
                              '${_selected >= 4 ? l10n.socraticInfo_confidenceHigh : _selected == 3 ? l10n.socraticInfo_confidenceMedium : l10n.socraticInfo_confidenceLow}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(height: 44),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF5350).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFEF5350).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Text('⚡', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.socraticInfo_hypercorrectionNote,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
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
}
