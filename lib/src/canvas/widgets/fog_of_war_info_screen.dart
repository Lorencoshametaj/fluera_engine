import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 🌫️ Fog of War info screen — explains how the feature works.
///
/// Material Design 3 with dark theme, staggered animations, interactive
/// fog level demo, and rich visual hierarchy. Mirrors the Socratic info screen
/// in structure and aesthetics.
class FogOfWarInfoScreen extends StatefulWidget {
  const FogOfWarInfoScreen({super.key});

  static void show(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const FogOfWarInfoScreen(),
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
  State<FogOfWarInfoScreen> createState() => _FogOfWarInfoScreenState();
}

class _FogOfWarInfoScreenState extends State<FogOfWarInfoScreen>
    with TickerProviderStateMixin {
  late final AnimationController _staggerController;
  late final AnimationController _gradientController;

  static const _totalSections = 10;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();

    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _gradientController.dispose();
    super.dispose();
  }

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

  // Accent color for the Fog of War theme.
  static const _accent = Color(0xFF90CAF9); // soft blue-ice

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            // ── Animated App Bar ────────────────────────────────
            SliverAppBar.large(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: const Text(
                'Fog of War',
                style: TextStyle(fontWeight: FontWeight.w700),
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
                            Color.lerp(const Color(0xFF0A1628),
                                const Color(0xFF1A0A28), t)!,
                            const Color(0xFF050510),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Content ─────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList.list(
                children: [
                  _animated(0, _heroCard()),
                  const SizedBox(height: 16),

                  _animated(1, _sectionTitle('Come funziona')),
                  const SizedBox(height: 8),
                  _animated(1, _flowCard()),
                  const SizedBox(height: 16),

                  _animated(2, _sectionTitle('3 Livelli di Nebbia')),
                  const SizedBox(height: 8),
                  _animated(2, const _FogLevelDemo()),
                  const SizedBox(height: 16),

                  _animated(3, _sectionTitle('Mappa di Padronanza')),
                  const SizedBox(height: 8),
                  _animated(3, _masteryMapCard()),
                  const SizedBox(height: 16),

                  _animated(4, _sectionTitle('Auto-Valutazione (1-5)')),
                  const SizedBox(height: 8),
                  _animated(4, _selfEvalCard()),
                  const SizedBox(height: 16),

                  _animated(5, _sectionTitle('Percorso Chirurgico')),
                  const SizedBox(height: 8),
                  _animated(5, _surgicalPathCard()),
                  const SizedBox(height: 16),

                  _animated(6, _sectionTitle('§XI.4 — Muro Rosso')),
                  const SizedBox(height: 8),
                  _animated(6, _muroRossoCard()),
                  const SizedBox(height: 16),

                  _animated(7, _sectionTitle('Statistiche & Progressi')),
                  const SizedBox(height: 8),
                  _animated(7, _statsCard()),
                  const SizedBox(height: 16),

                  _animated(8, _sectionTitle('Memoria Cross-Sessione')),
                  const SizedBox(height: 8),
                  _animated(8, _crossSessionCard()),
                  const SizedBox(height: 16),

                  _animated(9, _sectionTitle('Badge & Gamification')),
                  const SizedBox(height: 8),
                  _animated(9, _badgesCard()),
                  const SizedBox(height: 24),

                  // CTA
                  _animated(9, _ctaButton()),
                  const SizedBox(height: 16),

                  // Footer
                  Center(
                    child: Text(
                      'Basato su: Active Recall (Karpicke, 2011),\n'
                      'Testing Effect (Roediger & Butler, 2011),\n'
                      'Generation Effect (Slamecka & Graf, 1978)',
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

  Widget _heroCard() {
    return Card(
      color: const Color(0xFF0F1A2E),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Stack(
        children: [
          // Animated fog particles background.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _gradientController,
              builder: (_, __) => CustomPaint(
                painter: _FogParticlePainter(
                  time: _gradientController.value * 10.0,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('⚔️', style: TextStyle(fontSize: 28)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'La Nebbia di Guerra',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'La Fog of War nasconde i tuoi appunti sotto una nebbia: '
                  'il tuo compito è ricordare DOVE e COSA hai scritto. '
                  'Non è un quiz sulle risposte — testa la tua memoria spaziale '
                  'e la struttura della conoscenza.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                _scienceCallout(
                  icon: Icons.psychology,
                  text: 'Il Testing Effect mostra che tentare di ricordare '
                      'è più potente di rileggere.',
                  principle: 'Roediger & Butler (2011)',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Reusable science principle callout box.
  Widget _scienceCallout({
    required IconData icon,
    required String text,
    String? principle,
    Color color = _accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (principle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    principle,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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

  Widget _flowCard() {
    return Card(
      color: const Color(0xFF0F1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _flowStep('1', '⚔️', 'Scegli', 'Seleziona il livello di nebbia e l\'area'),
            _flowDivider(),
            _flowStep('2', '🌫️', 'Oscuramento',
                'I tuoi appunti vengono nascosti dalla nebbia'),
            _flowDivider(),
            _flowStep('3', '🔍', 'Esplora',
                'Cerca i tuoi nodi — toccali per rivelarli'),
            _flowDivider(),
            _flowStep('4', '🎯', 'Auto-Valuta',
                'Dichiari la tua confidenza (1-5) prima di vedere'),
            _flowDivider(),
            _flowStep('5', '🗺️', 'Mappa',
                'Vedi la mappa di padronanza con i risultati'),
            _flowDivider(),
            _flowStep('6', '🧭', 'Ripasso',
                'Segui il percorso chirurgico per i nodi critici'),
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
              color: _accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number,
                  style: const TextStyle(
                      color: _accent,
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
          color: _accent.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  Widget _masteryMapCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _MasteryMapDemo(),
        const SizedBox(height: 8),
        _scienceCallout(
          icon: Icons.science,
          text: 'La mappa rivela la differenza tra "so di non sapere" '
              'e "non so di non sapere" — il vero punto cieco cognitivo.',
          principle: 'Metacognition (Flavell, 1979)',
          color: const Color(0xFF4CAF50),
        ),
      ],
    );
  }


  Widget _selfEvalCard() {
    return Card(
      color: const Color(0xFF0F1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quando tocchi un nodo nascosto, PRIMA di vederlo '
              'dichiari la tua confidenza su una scala 1-5:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            _evalRow('1', '😵', 'Non ricordo nulla',
                'Intervallo FSRS → reset', const Color(0xFFEF5350)),
            const SizedBox(height: 6),
            _evalRow('2', '🤔', 'Qualcosa mi dice…',
                'Incerto — scaffolding consigliato', const Color(0xFFFF9800)),
            const SizedBox(height: 6),
            _evalRow('3', '😊', 'Credo di sapere',
                'Recall parziale', const Color(0xFFFFB300)),
            const SizedBox(height: 6),
            _evalRow('4', '💪', 'Sono sicuro',
                'Recall solido', const Color(0xFF66BB6A)),
            const SizedBox(height: 6),
            _evalRow('5', '🔥', 'Certissimo!',
                'Mastery — intervallo allungato', const Color(0xFF4CAF50)),
            const SizedBox(height: 12),
            _scienceCallout(
              icon: Icons.flash_on,
              text: 'Confidenza alta + sbagliato = Ipercorrezione! '
                  'Le sorprese negative creano il ricordo più forte.',
              principle: 'Hypercorrection Effect (Butterfield & Metcalfe, 2001)',
              color: const Color(0xFFEF5350),
            ),
          ],
        ),
      ),
    );
  }

  Widget _evalRow(String level, String emoji, String label,
      String effect, Color color) {
    return Row(
      children: [
        Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(level,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 6),
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Text(effect,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4), fontSize: 10)),
      ],
    );
  }

  Widget _surgicalPathCard() {
    return Card(
      color: const Color(0xFF0F1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route, size: 20, color: Color(0xFFFFB74D)),
                const SizedBox(width: 8),
                Text(
                  'Guida Ripasso',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Dopo la mappa di padronanza, puoi attivare il percorso '
              'chirurgico: la camera vola automaticamente ai nodi '
              'critici (dimenticati + punti ciechi) in ordine spaziale.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _surgicalStep('1', 'Nearest-neighbor',
                'Parte dal nodo più vicino al tuo viewport attuale',
                const Color(0xFFFFB74D)),
            const SizedBox(height: 6),
            _surgicalStep('2', 'Fly-to automatico',
                'La camera vola con animazione spring al nodo corrente',
                const Color(0xFFFFB74D)),
            const SizedBox(height: 6),
            _surgicalStep('3', 'Segna come rivisto',
                'Tocca "Prossimo" per marchare e procedere',
                const Color(0xFF4CAF50)),
            const SizedBox(height: 12),
            _scienceCallout(
              icon: Icons.explore,
              text: 'L\'ordine spaziale sfrutta il Method of Loci — '
                  'la memoria spaziale è evolutivamente più robusta.',
              principle: 'Spatial Memory (O\'Keefe & Nadel, 1978)',
              color: const Color(0xFFFFB74D),
            ),
          ],
        ),
      ),
    );
  }

  Widget _surgicalStep(
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

  Widget _muroRossoCard() {
    return Card(
      color: const Color(0xFF0F1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Se dimentichi troppi nodi (<50%), la Fog of War attiva '
              'il protocollo Muro Rosso per proteggere la motivazione:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            _muroRow('🔴 → 📝', 'Nodi rossi → neutri',
                'I "dimenticato" diventano grigi con suggerimento "📝 Riscrivi"',
                const Color(0xFF78909C)),
            const SizedBox(height: 8),
            _muroRow('🟢 → 🌟', 'Verdi potenziati',
                'I nodi ricordati brillano di più — focus sulle vittorie',
                const Color(0xFF66BB6A)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF78909C).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF78909C).withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined,
                      size: 18, color: Color(0xFF78909C)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Il Generation Effect suggerisce di RISCRIVERE '
                      'i concetti dimenticati — più potente della rilettura.',
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

  Widget _muroRow(
      String badge, String label, String description, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Text(badge, style: const TextStyle(fontSize: 14)),
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

  Widget _statsCard() {
    return Card(
      color: const Color(0xFF0F1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ogni sessione registra metriche dettagliate per il tracciamento '
              'longitudinale:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            _statRow('⏱️', 'Durata sessione',
                'Quanto tempo hai impiegato', _accent),
            const SizedBox(height: 6),
            _statRow('⚡', 'Velocità media',
                'Secondi per nodo — più basso = più fluido', _accent),
            const SizedBox(height: 6),
            _statRow('📊', 'Confidenza media',
                'Trend della tua auto-percezione (1-5)', _accent),
            const SizedBox(height: 6),
            _statRow('📈', 'Delta vs precedente',
                'Progresso rispetto all\'ultima sessione', _accent),
            const SizedBox(height: 6),
            _statRow('📉', 'Sparkline',
                'Mini grafico del trend confidenza nelle history card', _accent),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String emoji, String label, String description, Color color) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Flexible(
          child: Text(description,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
              textAlign: TextAlign.end),
        ),
      ],
    );
  }

  Widget _crossSessionCard() {
    return Card(
      color: const Color(0xFF0F1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sync, size: 20, color: Color(0xFFFFB74D)),
                const SizedBox(width: 8),
                Text(
                  'Memoria tra le sessioni',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'La Fog of War ricorda i tuoi errori precedenti. '
              'Nella sessione successiva, i nodi che avevi dimenticato '
              'mostrano un indicatore ⚠️ "critico l\'ultima volta" — '
              'così puoi monitorare se hai davvero consolidato.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badgesCard() {
    return Card(
      color: const Color(0xFF0F1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'I badge si sbloccano automaticamente in base alla tua performance:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            _badgeRow('🔥', 'In forma', '3+ sessioni consecutive ≥70%',
                const Color(0xFFFF6D00)),
            const SizedBox(height: 8),
            _badgeRow('🌟', 'Memoria solida', '5+ sessioni consecutive ≥70%',
                const Color(0xFFFFD600)),
            const SizedBox(height: 8),
            _badgeRow('💎', 'Palazzo della Memoria', '10+ sessioni ≥70%',
                const Color(0xFF7C4DFF)),
            const SizedBox(height: 8),
            _badgeRow('📈', 'Crescita costante',
                'Confidenza media in aumento per 3 sessioni',
                const Color(0xFF00C853)),
          ],
        ),
      ),
    );
  }

  Widget _badgeRow(
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
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
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
      label: const Text('Torna al canvas e provalo!'),
      style: FilledButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: const Color(0xFF050510),
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
// Interactive Fog Level Demo — isolated StatefulWidget
// ════════════════════════════════════════════════════════════════════════════

class _FogLevelDemo extends StatefulWidget {
  const _FogLevelDemo();

  @override
  State<_FogLevelDemo> createState() => _FogLevelDemoState();
}

class _FogLevelDemoState extends State<_FogLevelDemo> {
  int _selected = 0; // 0 = none, 1 = light, 2 = medium, 3 = total

  static const _titles = ['', '🌤️ Nebbia Leggera', '🌫️ Nebbia Media', '🌑 Nebbia Totale'];
  static const _descriptions = [
    '',
    'Le sagome dei nodi sono visibili, ma il contenuto è nascosto. '
        'Sai DOVE sono i tuoi appunti, devi ricordare COSA dicono.',
    'Visibilità limitata a 300px intorno alla tua posizione. '
        'Devi muoverti sulla canvas per "trovare" i nodi — come una torcia nel buio.',
    'Buio totale. Non vedi nulla. Solo la tua memoria spaziale '
        'ti guida a toccare i punti giusti.',
  ];
  static const _difficulties = ['', 'Media', 'Alta', 'Massima'];
  static const _colors = <Color>[
    Colors.transparent,
    Color(0xFF64B5F6),
    Color(0xFFFFB74D),
    Color(0xFFEF5350),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF0F1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tocca un livello per scoprire come funziona:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(3, (i) {
                final level = i + 1;
                final isSelected = _selected == level;
                final color = _colors[level];
                return GestureDetector(
                  onTap: () {
                    setState(() => _selected = _selected == level ? 0 : level);
                    if (level == 3) {
                      HapticFeedback.heavyImpact();
                    } else if (level == 2) {
                      HapticFeedback.mediumImpact();
                    } else {
                      HapticFeedback.lightImpact();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: isSelected ? 90 : 80,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? color
                            : Colors.white.withValues(alpha: 0.08),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(
                              color: color.withValues(alpha: 0.2),
                              blurRadius: 10,
                            )]
                          : null,
                    ),
                    child: Column(
                      children: [
                        Text(
                          ['🌤️', '🌫️', '🌑'][i],
                          style: TextStyle(fontSize: isSelected ? 28 : 24),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _difficulties[level],
                          style: TextStyle(
                            color: isSelected
                                ? color
                                : Colors.white.withValues(alpha: 0.4),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
            // Animated description.
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: _selected > 0
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(height: 0),
              secondChild: _selected > 0
                  ? Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _colors[_selected].withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _colors[_selected].withValues(alpha: 0.15),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _titles[_selected],
                              style: TextStyle(
                                color: _colors[_selected],
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _descriptions[_selected],
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 🌫️ Animated Fog Particle Painter — drifting circles in hero card
// ════════════════════════════════════════════════════════════════════════════

class _FogParticlePainter extends CustomPainter {
  final double time;
  _FogParticlePainter({required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final rng = math.Random(42); // deterministic seed for consistency

    for (int i = 0; i < 15; i++) {
      final baseX = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final radius = 15.0 + rng.nextDouble() * 30.0;
      final speed = 0.3 + rng.nextDouble() * 0.7;
      final phase = rng.nextDouble() * math.pi * 2;

      final x = baseX + math.sin(time * speed + phase) * 20;
      final y = baseY + math.cos(time * speed * 0.7 + phase) * 10;
      final alpha = 0.03 + 0.04 * math.sin(time * speed + phase).abs();

      paint.color = Color.fromRGBO(144, 202, 249, alpha);
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.8);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FogParticlePainter old) =>
      (time - old.time).abs() > 0.02;
}

// ════════════════════════════════════════════════════════════════════════════
// 🗺️ Interactive Mastery Map Demo — tap nodes to cycle states
// ════════════════════════════════════════════════════════════════════════════

class _MasteryMapDemo extends StatefulWidget {
  const _MasteryMapDemo();

  @override
  State<_MasteryMapDemo> createState() => _MasteryMapDemoState();
}

enum _DemoNodeState { hidden, recalled, forgotten, blindSpot, explored }

class _MasteryMapDemoState extends State<_MasteryMapDemo> {
  // 6 nodes with initial states
  final _states = List<_DemoNodeState>.filled(6, _DemoNodeState.hidden);

  static const _nodeLabels = [
    'Mitocondrio', 'ATP', 'Krebs', 'Fotosintesi', 'DNA', 'Ribosoma'
  ];

  static const _stateData = <_DemoNodeState, ({String emoji, String label, Color color})>{
    _DemoNodeState.hidden: (emoji: '🌫️', label: 'Nascosto', color: Color(0xFF455A64)),
    _DemoNodeState.recalled: (emoji: '✅', label: 'Ricordato', color: Color(0xFF4CAF50)),
    _DemoNodeState.forgotten: (emoji: '❌', label: 'Dimenticato', color: Color(0xFFEF5350)),
    _DemoNodeState.blindSpot: (emoji: '👁‍🗨', label: 'Punto Cieco', color: Color(0xFF9E9E9E)),
    _DemoNodeState.explored: (emoji: '📖', label: 'Rivelato', color: Color(0xFF64B5F6)),
  };

  void _cycleState(int index) {
    setState(() {
      const order = _DemoNodeState.values;
      final next = (order.indexOf(_states[index]) + 1) % order.length;
      _states[index] = order[next];
    });
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF0F1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tocca i nodi per vedere i diversi stati:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            // 2×3 grid of interactive nodes
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(6, (i) {
                final data = _stateData[_states[i]]!;
                return GestureDetector(
                  onTap: () => _cycleState(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    width: 100,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
                    decoration: BoxDecoration(
                      color: data.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: data.color.withValues(alpha: 0.5),
                        width: 2,
                      ),
                      boxShadow: _states[i] != _DemoNodeState.hidden
                          ? [
                              BoxShadow(
                                color: data.color.withValues(alpha: 0.15),
                                blurRadius: 8,
                              )
                            ]
                          : null,
                    ),
                    child: Column(
                      children: [
                        Text(data.emoji,
                            style: const TextStyle(fontSize: 22)),
                        const SizedBox(height: 4),
                        Text(
                          _nodeLabels[i],
                          style: TextStyle(
                            color: data.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          data.label,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Tocca per cambiare stato →',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
