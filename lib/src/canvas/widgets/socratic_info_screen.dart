import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
              title: const Text(
                'Metodo Socratico',
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
                  _animated(0, _heroCard()),
                  const SizedBox(height: 16),

                  _animated(1, _sectionTitle('Come funziona')),
                  const SizedBox(height: 8),
                  _animated(1, _flowCard()),
                  const SizedBox(height: 16),

                  _animated(2, _sectionTitle('4 tipi di domande')),
                  const SizedBox(height: 8),
                  _animated(2, _questionTypeCard(
                    emoji: '🔍', title: 'Lacuna',
                    subtitle: 'Recall 1-2',
                    description:
                        'Crea un "vuoto cognitivo" che senti il bisogno di colmare. '
                        'Ti chiede cosa COLLEGA due concetti o cosa MANCA.',
                    color: const Color(0xFF42A5F5),
                    principle: 'Zeigarnik Effect + Active Recall',
                  )),
                  const SizedBox(height: 8),
                  _animated(3, _questionTypeCard(
                    emoji: '⚔️', title: 'Sfida',
                    subtitle: 'Recall 3',
                    description:
                        'Presenta un controesempio per metterti in crisi. '
                        'Ti forza a DIFENDERE o RIVEDERE la tua comprensione.',
                    color: const Color(0xFFFF9800),
                    principle: 'Desirable Difficulties (Bjork)',
                  )),
                  const SizedBox(height: 8),
                  _animated(3, _questionTypeCard(
                    emoji: '🔬', title: 'Profondità',
                    subtitle: 'Recall 4',
                    description:
                        'Ti chiede il MECCANISMO, la CAUSA, il PRINCIPIO. '
                        'Sposta dall\'encoding superficiale a quello profondo.',
                    color: const Color(0xFF66BB6A),
                    principle: 'Levels of Processing (Craik & Lockhart)',
                  )),
                  const SizedBox(height: 8),
                  _animated(4, _questionTypeCard(
                    emoji: '🌉', title: 'Transfer',
                    subtitle: 'Recall 5',
                    description:
                        'Analogie con ALTRE materie o applicazioni in contesti NUOVI. '
                        'Crea ponti tra domini per consolidare la conoscenza.',
                    color: const Color(0xFFAB47BC),
                    principle: 'Transfer Learning + Interleaving',
                  )),
                  const SizedBox(height: 16),

                  _animated(5, _sectionTitle('Prova la Confidenza')),
                  const SizedBox(height: 8),
                  _animated(5, const _ConfidenceDemo()),
                  const SizedBox(height: 16),

                  _animated(6, _sectionTitle('3 Indizi Progressivi')),
                  const SizedBox(height: 8),
                  _animated(6, _breadcrumbCard()),
                  const SizedBox(height: 16),

                  _animated(7, _sectionTitle('Ripetizione Spaziata (FSRS)')),
                  const SizedBox(height: 8),
                  _animated(7, _fsrsCard()),
                  const SizedBox(height: 16),

                  _animated(8, _sectionTitle('Matrice di Feedback')),
                  const SizedBox(height: 8),
                  _animated(8, _feedbackMatrixCard()),
                  const SizedBox(height: 24),

                  // CTA
                  _animated(8, _ctaButton()),
                  const SizedBox(height: 16),

                  // Footer
                  Center(
                    child: Text(
                      'Basato su ricerche di Butterfield & Metcalfe (2001),\n'
                      'Bjork (1994), Craik & Lockhart (1972), Vygotsky (1978)',
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
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text('🔶', style: TextStyle(fontSize: 28)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'L\'Interrogazione Socratica',
                    style: TextStyle(
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
              'Fluera analizza i tuoi appunti manoscritti e genera domande '
              'calibrate sulla tua zona di sviluppo prossimale (ZPD). '
              'Non ti dice le risposte — ti guida a trovarle da solo.',
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
                      'Il valore cognitivo sta nel TENTATIVO di retrieval, '
                      'non nella risposta.',
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

  Widget _flowCard() {
    return Card(
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _flowStep('1', '✍️', 'Scrivi', 'Prendi appunti a mano sul canvas'),
            _flowDivider(),
            _flowStep('2', '🤖', 'Analisi',
                'Fluera riconosce il testo (OCR) e identifica la materia'),
            _flowDivider(),
            _flowStep('3', '🔶', 'Domanda',
                'Appare una bolla con la domanda socratica'),
            _flowDivider(),
            _flowStep('4', '🎯', 'Confidenza',
                'Dichiari quanto sei sicuro (1-5)'),
            _flowDivider(),
            _flowStep(
                '5', '🧠', 'Retrieval', 'Pensi alla risposta mentalmente'),
            _flowDivider(),
            _flowStep('6', '✅', 'Auto-valutazione',
                'Dichiari se sapevi o non sapevi'),
            _flowDivider(),
            _flowStep('7', '📊', 'Feedback',
                'Insight personalizzato + FSRS aggiornato'),
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

  Widget _breadcrumbCard() {
    return Card(
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Se non riesci, puoi chiedere fino a 3 indizi progressivi '
              '(scaffolding di Vygotsky):',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _breadcrumbRow(
              '1', '🌫️ L\'Eco Lontano',
              'Direzione vaga — attiva il priming semantico',
              const Color(0xFF78909C),
            ),
            const SizedBox(height: 8),
            _breadcrumbRow(
              '2', '🛤️ Il Sentiero',
              'Circoscrive il dominio — riduce lo spazio di ricerca',
              const Color(0xFFFFB300),
            ),
            const SizedBox(height: 8),
            _breadcrumbRow(
              '3', '🚪 La Soglia',
              'Ultimo scaffolding — la risposta è a un passo',
              const Color(0xFF66BB6A),
            ),
            const SizedBox(height: 12),
            Text(
              'La risposta non viene MAI rivelata — nemmeno al livello 3.',
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

  Widget _fsrsCard() {
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
                  'Ogni risultato viene salvato',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _fsrsRow('✅', 'Corretto', 'Intervallo si allunga',
                const Color(0xFF66BB6A)),
            const SizedBox(height: 6),
            _fsrsRow('❌', 'Errore', 'Intervallo si accorcia',
                const Color(0xFFEF5350)),
            const SizedBox(height: 6),
            _fsrsRow('⚡', 'Ipercorrezione', 'Penalità ridotta (shock = apprendimento)',
                const Color(0xFFFF9800)),
            const SizedBox(height: 6),
            _fsrsRow('💪', 'Alta conf. + corretto', 'Bonus intervallo (+30%)',
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

  Widget _feedbackMatrixCard() {
    return Card(
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Il feedback cambia in base a confidenza × correttezza:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            _matrixRow('💪', 'Sapevo + Alta conf.',
                'Solido! Il ricordo è stabile.', const Color(0xFF66BB6A)),
            const SizedBox(height: 8),
            _matrixRow('🎯', 'Sapevo + Bassa conf.',
                'Sapevi più di quanto pensassi!', const Color(0xFF4CAF50)),
            const SizedBox(height: 8),
            _matrixRow('📌', 'Non sapevo + Bassa conf.',
                'Lacuna nota — è già consapevolezza.', const Color(0xFFFFB300)),
            const SizedBox(height: 8),
            _matrixRow('⚡', 'Non sapevo + Alta conf.',
                'IPERCORREZIONE — vale doppio!', const Color(0xFFEF5350)),
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
      label: const Text('Torna al canvas e provalo!'),
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
    return Card(
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tocca i cerchi per sentire la vibrazione progressiva:',
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
                              '${_selected >= 4 ? 'forte perché dichiari alta sicurezza' : _selected == 3 ? 'media — zona incerta' : 'leggera — sai di non sapere'}',
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
                      'Gli errori ad alta confidenza (⚡ ipercorrezione) '
                      'producono le correzioni più DURATURE.',
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
