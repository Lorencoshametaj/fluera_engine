import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ai/exam_session_model.dart';
import '../ai/exam_session_controller.dart';
import '../widgets/latex_preview_card.dart';
import 'components/handwriting_scratchpad.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 🎓 ATLAS EXAM OVERLAY — Fullscreen interrogation mode (v2)
//
// Features:
//   ✅ Cluster-based scope picker (argomenti, non viewport)
//   ✅ Configurable question count (5 / 7 / 10)
//   ✅ Optional per-question countdown timer (30s)
//   ✅ Differentiated haptics (heavy=correct, none=wrong, light=partial)
//   ✅ LaTeX rendering for formula questions
//   ✅ Robust eval text parsing (VOTO/FEEDBACK strip)
//   ✅ Skip API call when answer is empty (instant reveal)
//   ✅ Question shuffle (done at model level)
//   ✅ Session history panel
//   ✅ Adaptive difficulty notification banner
// ─────────────────────────────────────────────────────────────────────────────

class ExamOverlay extends StatefulWidget {
  final Map<String, String> availableClusters; // clusterId → display title
  final Map<String, String> clusterTexts;       // clusterId → OCR text
  final ExamSessionController controller;
  final VoidCallback onClose;
  final void Function(List<String> mastered, Map<String, Duration> review) onComplete;

  const ExamOverlay({
    super.key,
    required this.availableClusters,
    required this.clusterTexts,
    required this.controller,
    required this.onClose,
    required this.onComplete,
  });

  @override
  State<ExamOverlay> createState() => _ExamOverlayState();
}

class _ExamOverlayState extends State<ExamOverlay> with TickerProviderStateMixin {
  late final AnimationController _enterController;
  late final AnimationController _glowController;

  // Scope
  final Set<String> _selectedIds = {};
  bool _scopeSelected = false;
  int _questionCount = 7;
  bool _timerEnabled = false;
  bool _showHistory = false;

  // Question state
  final TextEditingController _answerCtrl = TextEditingController();
  final TextEditingController _elaborationCtrl = TextEditingController();
  bool _isHandwritingMode = true;
  bool _revealed = false;
  String _evalText = '';
  String? _difficultyBanner;
  int? _selectedChoiceIndex;   // tracks which MC/TF button was tapped
  String? _hintText;           // Atlas hint for current question
  bool _loadingHint = false;

  // 🧠 Hypercorrection shock state
  late final AnimationController _shakeController;
  bool _shockFlashVisible = false;

  // Confidence rating (1-5) — Hypercorrection Effect
  int _confidenceLevel = 0; // 0 = not set, 1-5 = selected
  static const _confidenceEmoji = ['', '😟', '🤔', '😐', '😊', '😎'];

  // Streak counter — Goal Gradient Effect
  int _currentStreak = 0;

  // Language selector
  String _examLang = 'Italian'; // language passed to controller

  // Timer
  Timer? _questionTimer;
  int _timerSecondsLeft = 30;
  static const _timerDuration = 30;
  late final AnimationController _timerController;

  // 📦 Progressive Chunking
  bool _showingChunkBreak = false;

  static const _cyan = Color(0xFF00E5FF);
  static const _green = Color(0xFF69F0AE);
  static const _red = Color(0xFFFF5252);
  static const _orange = Color(0xFFFFAB40);
  static const _purple = Color(0xFFCE93D8);
  static const _bg = Color(0xF00A0A1A);

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..forward();
    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _timerController = AnimationController(vsync: this, duration: const Duration(seconds: _timerDuration));
    // 🧠 Hypercorrection shock: shake animation (3 cycles, 400ms)
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Listen to controller: start timer when first question appears
    widget.controller.addListener(_onControllerChange);

    widget.controller.evalTextStream.listen((text) {
      if (mounted) setState(() => _evalText = text);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    _enterController.dispose();
    _glowController.dispose();
    _timerController.dispose();
    _shakeController.dispose();
    _answerCtrl.dispose();
    _elaborationCtrl.dispose();
    _questionTimer?.cancel();
    super.dispose();
  }

  // Called whenever controller state changes: detect first question load
  String? _lastQuestionId;
  void _onControllerChange() {
    final q = widget.controller.session?.currentQuestion;
    if (q != null && q.id != _lastQuestionId && !q.isAnswered) {
      _lastQuestionId = q.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startTimer();
      });
    }
  }

  // ─── Timer ──────────────────────────────────────────────────────────────

  void _startTimer() {
    if (!_timerEnabled) return;
    _questionTimer?.cancel();
    _timerSecondsLeft = _timerDuration;
    _timerController.forward(from: 0);
    _questionTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _timerSecondsLeft--);
      if (_timerSecondsLeft <= 0) {
        t.cancel();
        _autoTimeOut();
      }
    });
  }

  void _stopTimer() {
    _questionTimer?.cancel();
    _timerController.stop();
  }

  void _autoTimeOut() {
    final q = widget.controller.session?.currentQuestion;
    if (q == null || q.isAnswered) return;
    HapticFeedback.lightImpact();
    widget.controller.skipQuestion();
    setState(() { _revealed = true; _evalText = q.explanation; });
  }

  // ─── Haptic ─────────────────────────────────────────────────────────────

  void _hapticForResult(ExamAnswerResult result) {
    switch (result) {
      case ExamAnswerResult.correct:
        HapticFeedback.heavyImpact();          // Strong positive
      case ExamAnswerResult.partial:
        HapticFeedback.lightImpact();          // Soft neutral
      case ExamAnswerResult.incorrect:
        // No haptic — silence is more powerful than vibration
        break;
      case ExamAnswerResult.skipped:
        HapticFeedback.selectionClick();
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _enterController,
      builder: (_, child) => FadeTransition(opacity: _enterController, child: child),
      child: Material(
        color: _bg,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (_, __) {
              // Adaptive difficulty banner
              final hint = widget.controller.loadingHint;
              if (hint != null && hint.contains('Livello aumentato') && _difficultyBanner == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _difficultyBanner = hint);
                    Future.delayed(const Duration(seconds: 3), () {
                      if (mounted) setState(() => _difficultyBanner = null);
                    });
                  }
                });
              }
              return Stack(
                children: [
                  _buildBody(),
                  if (_difficultyBanner != null) _buildDifficultyBanner(_difficultyBanner!),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final ctrl = widget.controller;
    if (ctrl.error != null) return _buildError(ctrl.error!);
    if (ctrl.isLoading && widget.controller.session == null) {
      return _buildLoading(ctrl.loadingHint ?? '🌌 Atlas al lavoro...');
    }
    if (!_scopeSelected) return _buildScopePicker();

    final session = ctrl.session;
    if (session == null) return _buildLoading('🌌 Generando le domande...');
    if (session.isComplete) return _buildResults(session);
    if (_showingChunkBreak) return _buildChunkBreak(session);
    if (_showHistory) return _buildHistoryPanel();
    return _buildQuestion(session);
  }

  // ─── SCOPE PICKER ───────────────────────────────────────────────────────

  Widget _buildScopePicker() {
    final hasSelection = _selectedIds.isNotEmpty;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildHeader('Su cosa vuoi essere interrogato?', showClose: true),
      const SizedBox(height: 8),

      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Seleziona gli argomenti (max 10)',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
          const SizedBox(height: 12),
          Wrap(spacing: 9, runSpacing: 9, children: [
            _chip(id: '__all__', title: '🗂 Tutti', selected: _selectedIds.contains('__all__'),
              onTap: () => setState(() {
                if (_selectedIds.contains('__all__')) _selectedIds.clear();
                else { _selectedIds.clear(); _selectedIds.add('__all__'); }
              })),
            ...widget.availableClusters.entries.map((e) =>
              _chip(id: e.key, title: e.value, selected: _selectedIds.contains(e.key),
                onTap: () => setState(() {
                  _selectedIds.remove('__all__');
                  _selectedIds.contains(e.key) ? _selectedIds.remove(e.key)
                    : (_selectedIds.length < 10 ? _selectedIds.add(e.key) : null);
                }))),
          ]),
          const SizedBox(height: 24),

          // ── Language selector ───────────────────────────────────────────
          const SizedBox(height: 16),
          Row(children: [
            Text('Lingua', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
            const Spacer(),
            SegmentedButton<String>(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.selected) ? _cyan.withValues(alpha: 0.15) : Colors.transparent),
                foregroundColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.selected) ? _cyan : Colors.white54),
                side: WidgetStateProperty.all(BorderSide(color: _cyan.withValues(alpha: 0.2))),
                visualDensity: VisualDensity.compact,
              ),
              segments: const [
                ButtonSegment(value: 'Italian', label: Text('IT', style: TextStyle(fontSize: 11))),
                ButtonSegment(value: 'English', label: Text('EN', style: TextStyle(fontSize: 11))),
                ButtonSegment(value: 'Spanish', label: Text('ES', style: TextStyle(fontSize: 11))),
                ButtonSegment(value: 'French', label: Text('FR', style: TextStyle(fontSize: 11))),
              ],
              selected: {_examLang},
              onSelectionChanged: (s) => setState(() => _examLang = s.first),
            ),
          ]),
          const SizedBox(height: 4),

          // ── Question count slider ───────────────────────────────────────
          Row(children: [
            Text('Domande', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
            const Spacer(),
            Text('$_questionCount', style: TextStyle(color: _cyan, fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _cyan,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: _cyan,
              overlayColor: _cyan.withValues(alpha: 0.1),
            ),
            child: Slider(
              min: 5, max: 15, divisions: 10,
              value: _questionCount.toDouble(),
              onChanged: (v) => setState(() => _questionCount = v.round()),
            ),
          ),
          const SizedBox(height: 4),

          // ── Timer toggle ───────────────────────────────────────────────
          Row(children: [
            Text('Timer per domanda (${_timerDuration}s)',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
            const Spacer(),
            Switch.adaptive(
              value: _timerEnabled,
              onChanged: (v) => setState(() => _timerEnabled = v),
              activeThumbColor: _cyan,
            ),
          ]),

          // History button
          if (widget.controller.history.isNotEmpty) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() { _scopeSelected = true; _showHistory = true; }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(children: [
                  Icon(Icons.history_rounded, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                  const SizedBox(width: 8),
                  Text('${widget.controller.history.length} sessioni precedenti',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 16, color: Colors.white.withValues(alpha: 0.3)),
                ]),
              ),
            ),
          ],
        ]),
      )),

      Padding(
        padding: const EdgeInsets.all(20),
        child: GestureDetector(
          onTap: hasSelection ? _startExam : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 54,
            decoration: BoxDecoration(
              color: hasSelection ? _cyan.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasSelection ? _cyan.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.1), width: 1.5),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.play_arrow_rounded,
                color: hasSelection ? _cyan : Colors.white.withValues(alpha: 0.2)),
              const SizedBox(width: 8),
              Text(
                hasSelection ? 'Inizia l\'interrogazione →' : 'Seleziona almeno un argomento',
                style: TextStyle(
                  color: hasSelection ? _cyan : Colors.white.withValues(alpha: 0.2),
                  fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _chip({required String id, required String title, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _cyan.withValues(alpha: 0.13) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? _cyan.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.1), width: 1.1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (selected) ...[Icon(Icons.check_circle_rounded, size: 13, color: _cyan), const SizedBox(width: 5)],
          Flexible(child: Text(title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: selected ? _cyan : Colors.white.withValues(alpha: 0.7),
              fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.normal))),
        ]),
      ),
    );
  }

  void _startExam() {
    final Map<String, String> texts = _selectedIds.contains('__all__')
        ? Map.from(widget.clusterTexts)
        : { for (final id in _selectedIds) if (widget.clusterTexts.containsKey(id)) id: widget.clusterTexts[id]! };
    if (texts.isEmpty) return;

    // Set topic titles for history
    widget.controller.selectedTopicTitles = _selectedIds.contains('__all__')
        ? widget.availableClusters.values.toList()
        : _selectedIds.map((id) => widget.availableClusters[id] ?? id).toList();

    setState(() { _scopeSelected = true; _revealed = false; _evalText = ''; _selectedChoiceIndex = null; _hintText = null; });
    widget.controller.startExam(texts, count: _questionCount);
  }

  // ─── QUESTION SCREEN ────────────────────────────────────────────────────

  Widget _buildQuestion(ExamSession session) {
    final q = session.currentQuestion!;
    final progress = (session.currentIndex + 1) / session.questions.length;

    // Reset on new question
    if (!q.isAnswered && _revealed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _revealed = false;
            _evalText = '';
            _answerCtrl.clear();
            _elaborationCtrl.clear();
            _selectedChoiceIndex = null;
            _hintText = null;
            _confidenceLevel = 0;
          });
        }
      });
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildProgressBar(session.currentIndex + 1, session.questions.length, progress, session, q),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey('q_${session.currentIndex}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _typeBadge(q.type),
                const SizedBox(height: 14),
                _questionCard(q),
                const SizedBox(height: 22),
                // Confidence slider BEFORE input (metacognitive monitoring)
                if (!q.isAnswered && _confidenceLevel == 0) _buildConfidenceSlider(q),
                if (!q.isAnswered && _confidenceLevel > 0) _buildInputArea(q),
                if (q.isAnswered || _revealed) _buildRevealArea(q),
                if (_hintText != null) _buildHintBubble(_hintText!),
              ],
            ),
          ),
        ),
      ),
      _buildBottomBar(session, q),
    ]);
  }

  Widget _buildProgressBar(int cur, int total, double progress, ExamSession session, ExamQuestion currentQ) {
    final timerColor = _timerSecondsLeft <= 10 ? _red : _cyan;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(children: [
        Row(children: [
          GestureDetector(onTap: _confirmClose,
            child: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.35), size: 19)),
          const SizedBox(width: 12),
          Expanded(child: Stack(children: [
            ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withValues(alpha: 0.07),
                valueColor: AlwaysStoppedAnimation<Color>(_progressColor(session)),
                minHeight: 5)),
          ])),
          const SizedBox(width: 10),
          Text('$cur/$total', style: TextStyle(color: _cyan.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600)),
          // Streak badge
          if (_currentStreak >= 2) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _orange.withValues(alpha: 0.4))),
              child: Text('🔥 $_currentStreak', style: TextStyle(color: _orange, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ],
          const SizedBox(width: 8),
          Text('${session.correctCount}✓', style: TextStyle(color: _green.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _showHistory = true),
            child: Icon(Icons.history_rounded, size: 16, color: Colors.white.withValues(alpha: 0.25)),
          ),
        ]),
        // Timer bar (if enabled)
        if (_timerEnabled && !currentQ.isAnswered) ...[
          const SizedBox(height: 6),
          AnimatedBuilder(
            animation: _timerController,
            builder: (_, __) => ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: 1.0 - _timerController.value,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                valueColor: AlwaysStoppedAnimation<Color>(timerColor.withValues(alpha: 0.6)),
                minHeight: 3,
              ),
            ),
          ),
          Align(alignment: Alignment.centerRight,
            child: Text('${_timerSecondsLeft}s',
              style: TextStyle(color: timerColor.withValues(alpha: _timerSecondsLeft <= 10 ? 0.9 : 0.4), fontSize: 10))),
        ],
      ]),
    );
  }

  // ─── Hint bubble ────────────────────────────────────────────────────────

  Widget _buildHintBubble(String hint) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _orange.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Text('💡', style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(child: Text(hint, style: TextStyle(color: _orange, fontSize: 13))),
      ]),
    );
  }

  // ─── Confidence slider ────────────────────────────────────────────────────

  Widget _buildConfidenceSlider(ExamQuestion q) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _purple.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Quanto sei sicuro/a?',
          style: TextStyle(color: _purple, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Sistema la tua fiducia prima di rispondere',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(5, (i) {
            final level = i + 1;
            final selected = _confidenceLevel == level;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                q.confidenceLevel = level;
                setState(() => _confidenceLevel = level);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: selected ? _purple.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: selected ? _purple.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_confidenceEmoji[level], style: const TextStyle(fontSize: 18)),
                  Text('$level', style: TextStyle(
                    color: selected ? _purple : Colors.white.withValues(alpha: 0.3),
                    fontSize: 10, fontWeight: FontWeight.w600)),
                ]),
              ),
            );
          }),
        ),
      ]),
    );
  }

  Widget _questionCard(ExamQuestion q) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (_, __) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cyan.withValues(alpha: 0.18 + _glowController.value * 0.08)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(q.questionText,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w500, height: 1.5)),
          // Render LaTeX formula if this is a formula question and text contains $
          if (q.type == ExamQuestionType.formulaRecall && q.questionText.contains(r'$')) ...[
            const SizedBox(height: 12),
            _buildLatexFromText(q.questionText, fontSize: 20),
          ],
        ]),
      ),
    );
  }

  Widget _buildLatexFromText(String text, {double fontSize = 20}) {
    // Extract $...$ or $$...$$ patterns
    final latexMatches = RegExp(r'\$\$(.+?)\$\$|\$(.+?)\$').allMatches(text);
    if (latexMatches.isEmpty) return const SizedBox.shrink();
    final src = latexMatches.first.group(1) ?? latexMatches.first.group(2) ?? '';
    if (src.isEmpty) return const SizedBox.shrink();
    return LatexPreviewCard(
      latexSource: src,
      fontSize: fontSize,
      color: _cyan,
      backgroundColor: Colors.transparent,
      minHeight: 60,
    );
  }

  Widget _typeBadge(ExamQuestionType type) {
    final (label, color) = switch (type) {
      ExamQuestionType.openEnded => ('RISPOSTA APERTA', _cyan),
      ExamQuestionType.multipleChoice => ('SCELTA MULTIPLA', _orange),
      ExamQuestionType.trueOrFalse => ('VERO / FALSO', _purple),
      ExamQuestionType.formulaRecall => ('FORMULA', _green),
    };
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.28))),
        child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
      ),
    ]);
  }

  Widget _buildInputArea(ExamQuestion q) {
    return switch (q.type) {
      ExamQuestionType.multipleChoice => _buildChoices(q),
      ExamQuestionType.trueOrFalse   => _buildTrueFalse(q),
      _                              => _buildOpenInput(q),
    };
  }

  Widget _buildChoices(ExamQuestion q) {
    return Column(children: q.choices.asMap().entries.map((e) {
      final idx = e.key;
      // Color state after answer
      Color borderColor = Colors.white.withValues(alpha: 0.11);
      Color bgColor = Colors.white.withValues(alpha: 0.04);
      if (q.isAnswered) {
        if (idx == q.correctChoiceIndex) {
          borderColor = _green.withValues(alpha: 0.6);
          bgColor = _green.withValues(alpha: 0.07);
        } else if (idx == _selectedChoiceIndex) {
          borderColor = _red.withValues(alpha: 0.5);
          bgColor = _red.withValues(alpha: 0.06);
        }
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GestureDetector(
          onTap: q.isAnswered ? null : () {
            _stopTimer();
            setState(() => _selectedChoiceIndex = idx);
            widget.controller.submitChoiceAnswer(idx);
            final res = q.result ?? ExamAnswerResult.incorrect;
            _hapticForResult(res);
            _updateStreak(res);
            setState(() { _revealed = true; _evalText = q.explanation; });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor)),
            child: Row(children: [
              Container(
                width: 27, height: 27,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: q.isAnswered && idx == q.correctChoiceIndex
                      ? _green.withValues(alpha: 0.7)
                      : _cyan.withValues(alpha: 0.4))),
                child: Center(child: Text(
                  q.isAnswered && idx == q.correctChoiceIndex ? '✓'
                  : q.isAnswered && idx == _selectedChoiceIndex ? '✗'
                  : String.fromCharCode(65 + idx),
                  style: TextStyle(
                    color: q.isAnswered && idx == q.correctChoiceIndex ? _green
                        : q.isAnswered && idx == _selectedChoiceIndex ? _red
                        : _cyan,
                    fontSize: 12, fontWeight: FontWeight.w700))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(e.value.replaceFirst(RegExp(r'^[A-Da-d]:\s*'), ''),
                style: const TextStyle(color: Colors.white, fontSize: 14))),
            ]),
          ),
        ),
      );
    }).toList());
  }

  Widget _buildTrueFalse(ExamQuestion q) {
    return Row(children: [
      Expanded(child: _tfBtn(q, 0, 'Vero', _green)),
      const SizedBox(width: 12),
      Expanded(child: _tfBtn(q, 1, 'Falso', _red)),
    ]);
  }

  Widget _tfBtn(ExamQuestion q, int idx, String label, Color color) {
    return GestureDetector(
      onTap: () {
        _stopTimer();
        widget.controller.submitChoiceAnswer(idx);
        final res = q.result ?? ExamAnswerResult.incorrect;
        _hapticForResult(res);
        _updateStreak(res);
        setState(() { _revealed = true; _evalText = q.explanation; });
      },
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Center(child: Text(label, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600))),
      ),
    );
  }

  Widget _buildOpenInput(ExamQuestion q) {
    final isFormula = q.type == ExamQuestionType.formulaRecall;
    
    // Toggle label
    final modeLabel = _isHandwritingMode ? '✍️ Modalità scrittura' : '⌨️ Modalità tastiera';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── Toggle Bar ──
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(isFormula ? 'Scrivi la formula / calcolo' : 'La tua risposta', 
               style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isHandwritingMode = !_isHandwritingMode);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(modeLabel, style: const TextStyle(color: _cyan, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),

      // ── Scrittura Mista ──
      if (_isHandwritingMode)
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: HandwritingScratchpad(
            height: 180,
            inkColor: _cyan,
            onRecognizedText: (text) {
              if (mounted) {
                setState(() {
                  // Append with space if there's already text, or just set it
                  final current = _answerCtrl.text.trim();
                  if (current.isEmpty) {
                    _answerCtrl.text = text;
                  } else {
                    _answerCtrl.text = '$current $text';
                  }
                  // Move cursor to end
                  _answerCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: _answerCtrl.text.length),
                  );
                });
              }
            },
          ),
        ),

      Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _cyan.withValues(alpha: 0.22))),
        child: TextField(
          controller: _answerCtrl,
          readOnly: _isHandwritingMode,
          style: TextStyle(
            color: Colors.white, fontSize: 15,
            fontFamily: isFormula ? 'monospace' : null),
          maxLines: isFormula ? 2 : (_isHandwritingMode ? 2 : 4),
          decoration: InputDecoration(
            hintText: _isHandwritingMode 
                ? 'Testo riconosciuto...' 
                : (isFormula ? 'Scrivi la formula (es. F = ma)...' : 'Scrivi la tua risposta...'),
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.28)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(16)),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _btn(label: 'Invia', color: _cyan, onTap: () {
          _stopTimer();
          final answer = _answerCtrl.text.trim();
          setState(() { _revealed = true; _evalText = ''; });
          widget.controller.submitOpenAnswer(answer).then((_) {
            if (mounted) {
              final res = q.result ?? ExamAnswerResult.skipped;
              _hapticForResult(res);
              _updateStreak(res);
            }
          });
        })),
        const SizedBox(width: 8),
        // Hint button — uses GestureDetector directly so onTap can be null
        GestureDetector(
          onTap: _loadingHint ? null : () {
            setState(() { _loadingHint = true; _hintText = null; });
            widget.controller.getHint().then((hint) {
              if (mounted) setState(() { _hintText = hint; _loadingHint = false; });
            });
          },
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _orange.withValues(alpha: 0.3))),
            child: Center(child: Text(
              _loadingHint ? '...' : '💡',
              style: TextStyle(color: _orange, fontSize: 15, fontWeight: FontWeight.w600))),
          ),
        ),
        const SizedBox(width: 8),
        _btn(label: 'Rivela', color: Colors.white.withValues(alpha: 0.18), small: true, onTap: () {
          _stopTimer();
          HapticFeedback.selectionClick();
          widget.controller.skipQuestion();
          setState(() { _revealed = true; _evalText = q.explanation; });
        }),
      ]),
    ]);
  }

  // ─── REVEAL AREA ────────────────────────────────────────────────────────

  Widget _buildRevealArea(ExamQuestion q) {
    final result = q.result;
    // 🧠 GROWTH MINDSET: Praise effort/strategy, not talent (Dweck, 2006)
    final (icon, color, label) = switch (result) {
      ExamAnswerResult.correct  => ('✓', _green, 'Il tuo sforzo ha funzionato!'),
      ExamAnswerResult.partial  => ('≈', _orange, 'Ci sei quasi — continua così'),
      ExamAnswerResult.incorrect => ('✗', _red, 'Ogni errore crea una connessione più forte'),
      ExamAnswerResult.skipped  => ('→', Colors.white.withValues(alpha: 0.35), 'Ci tornerai più preparato'),
      null                      => ('…', _cyan, 'Valutazione...'),
    };

    // ── Robust eval text parsing ────────────────────────────────────────
    String feedbackText;
    if (_evalText.isNotEmpty) {
      // Strip "VOTO: CORRETTO/PARZIALE/SBAGLIATO" line
      final stripped = _evalText
        .replaceFirst(RegExp(r'VOTO:\s*\w+[\s\S]*?(?=FEEDBACK:)', caseSensitive: false), '')
        .replaceFirst(RegExp(r'FEEDBACK:\s*', caseSensitive: false), '')
        .trim();
      feedbackText = stripped.isEmpty ? _evalText.trim() : stripped;
    } else if (q.explanation.isNotEmpty) {
      feedbackText = q.explanation;
    } else {
      feedbackText = '';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 14),
      // ⚡ HYPERCORRECTION SHOCK: Visceral feedback for overconfident errors
      // (Butterfield & Metcalfe, 2001 — errors with high confidence are remembered 3× better)
      if (q.wasOverconfident) ...[
        // Trigger shake + flash on first render
        Builder(builder: (_) {
          // Fire shake only once per reveal
          if (!_shakeController.isAnimating && _shakeController.value == 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _shakeController.forward(from: 0);
                HapticFeedback.heavyImpact();
                Future.delayed(const Duration(milliseconds: 200), () {
                  if (mounted) HapticFeedback.selectionClick();
                });
                setState(() => _shockFlashVisible = true);
                Future.delayed(const Duration(milliseconds: 600), () {
                  if (mounted) setState(() => _shockFlashVisible = false);
                });
              }
            });
          }
          return const SizedBox.shrink();
        }),
        // Red flash overlay
        if (_shockFlashVisible)
          AnimatedOpacity(
            opacity: _shockFlashVisible ? 0.3 : 0.0,
            duration: const Duration(milliseconds: 600),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: _red,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        // Shake wrapper for the shock banner
        AnimatedBuilder(
          animation: _shakeController,
          builder: (_, child) {
            final shake = math.sin(_shakeController.value * math.pi * 6) * 8;
            return Transform.translate(offset: Offset(shake, 0), child: child);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _red.withValues(alpha: 0.45), width: 1.5),
            ),
            child: Row(children: [
              const Text('⚡', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Eri sicuro/a al ${q.confidenceLevel}/5, ma hai sbagliato — '
                'questo shock aiuta la memoria 3× di più! '
                '(Butterfield & Metcalfe, 2001)',
                style: TextStyle(color: _red.withValues(alpha: 0.95), fontSize: 12, height: 1.35))),
            ]),
          ),
        ),
      ],
      Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.14)),
          child: Center(child: Text(icon, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800))),
        ),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
        if (widget.controller.isLoading) ...[
          const SizedBox(width: 10),
          SizedBox(width: 12, height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: _cyan.withValues(alpha: 0.6))),
        ],
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: color.withValues(alpha: 0.18))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (feedbackText.isNotEmpty)
            Text(feedbackText, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
          if ((result == ExamAnswerResult.incorrect || result == ExamAnswerResult.skipped) &&
              q.correctAnswer.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Risposta corretta:', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
            const SizedBox(height: 4),
            // Render LaTeX if formula question
            if (q.type == ExamQuestionType.formulaRecall &&
                (q.correctAnswer.contains(r'$') || q.correctAnswer.contains(r'\\')))
              LatexPreviewCard(
                latexSource: q.correctAnswer.replaceAll(r'$', ''),
                fontSize: 18,
                color: _green,
                backgroundColor: Colors.transparent,
                minHeight: 40,
              )
            else
              Text(q.correctAnswer,
                style: TextStyle(color: _green, fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ]),
      ),
      // Elaboration prompt (Generation Effect) — for wrong/overconfident answers
      // 🧠 ENFORCED ELABORATION: mandatory when overconfident (Slamecka & Graf, 1978)
      if ((result == ExamAnswerResult.incorrect || result == ExamAnswerResult.skipped ||
           q.wasOverconfident) &&
          q.elaboration == null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: q.wasOverconfident
                ? _red.withValues(alpha: 0.06)
                : _cyan.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: q.wasOverconfident
                ? _red.withValues(alpha: 0.20)
                : _cyan.withValues(alpha: 0.15)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              q.wasOverconfident
                  ? '⚡ Riscrivi con parole tue — gli errori ad alta fiducia si fissano 3× meglio se rielabori!'
                  : '✍️ Riscrivi con parole tue per consolidare:',
              style: TextStyle(
                color: (q.wasOverconfident ? _red : _cyan).withValues(alpha: 0.7),
                fontSize: 12)),
            const SizedBox(height: 6),
            // Handwriting scratchpad for elaboration (same cognitive benefit)
            if (_isHandwritingMode)
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: HandwritingScratchpad(
                  height: 120,
                  inkColor: q.wasOverconfident ? _red : _cyan,
                  onRecognizedText: (text) {
                    if (mounted) {
                      setState(() {
                        final current = _elaborationCtrl.text.trim();
                        if (current.isEmpty) {
                          _elaborationCtrl.text = text;
                        } else {
                          _elaborationCtrl.text = '$current $text';
                        }
                        _elaborationCtrl.selection = TextSelection.fromPosition(
                          TextPosition(offset: _elaborationCtrl.text.length),
                        );
                      });
                    }
                  },
                ),
              ),
            TextField(
              controller: _elaborationCtrl,
              readOnly: _isHandwritingMode,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: _isHandwritingMode ? 1 : 2,
              onChanged: (_) => setState(() {}), // rebuild for char counter
              decoration: InputDecoration(
                hintText: _isHandwritingMode
                    ? 'Testo riconosciuto...'
                    : 'Scrivi qui per memorizzare meglio...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              // 📊 Character counter with color transition
              Builder(builder: (_) {
                final len = _elaborationCtrl.text.trim().length;
                final enough = len >= 15;
                return Text(
                  '$len/15 caratteri',
                  style: TextStyle(
                    color: enough
                        ? _green.withValues(alpha: 0.7)
                        : _red.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                );
              }),
              GestureDetector(
                onTap: () {
                  if (_elaborationCtrl.text.trim().length >= 15) {
                    q.elaboration = _elaborationCtrl.text.trim();
                    HapticFeedback.selectionClick();
                    setState(() {});
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _elaborationCtrl.text.trim().length >= 15
                        ? _cyan.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Salva',
                    style: TextStyle(
                      color: _elaborationCtrl.text.trim().length >= 15
                          ? _cyan
                          : Colors.white.withValues(alpha: 0.25),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ]),
        ),
      ],
      if (q.elaboration != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Text('✓', style: TextStyle(color: _green, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(child: Text('Elaborazione salvata — ti aiuterà a ricordare!',
              style: TextStyle(color: _green.withValues(alpha: 0.7), fontSize: 11))),
          ]),
        ),
      ],
    ]);
  }

  // ─── BOTTOM BAR ─────────────────────────────────────────────────────────

  Widget _buildBottomBar(ExamSession session, ExamQuestion q) {
    final isLast = session.currentIndex >= session.questions.length - 1;
    final answered = q.isAnswered;

    // 🧠 ENFORCED ELABORATION GATE: Block "Next" when overconfident error needs to be rielaborated
    final needsElaboration = answered &&
        (q.wasOverconfident || q.result == ExamAnswerResult.incorrect) &&
        q.elaboration == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: answered
        ? needsElaboration
          ? _btn(
              label: '✍️ Riscrivi prima di procedere',
              color: Colors.white.withValues(alpha: 0.08),
              onTap: null) // Disabled button
          : _btn(
              label: isLast ? 'Vedi i risultati 🎓' : 'Prossima →',
              color: _cyan,
              onTap: () {
                HapticFeedback.mediumImpact();
                _stopTimer();
                _answerCtrl.clear();
                _elaborationCtrl.clear();
                _shakeController.reset();
                _shockFlashVisible = false;
                setState(() { _revealed = false; _evalText = ''; });
                widget.controller.nextQuestion();
                // 📦 PROGRESSIVE CHUNKING: show break between blocks
                final s = widget.controller.session;
                if (s != null && !s.isComplete && s.isChunkBoundary) {
                  setState(() => _showingChunkBreak = true);
                  return;
                }
                if (!session.isComplete) _startTimer();
              })
        : _btn(label: 'Salta →', color: Colors.white.withValues(alpha: 0.14), onTap: () {
            HapticFeedback.selectionClick();
            _stopTimer();
            widget.controller.skipQuestion();
            setState(() { _revealed = true; _evalText = q.explanation; });
          }),
    );
  }

  // ─── CHUNK BREAK ─────────────────────────────────────────────────────────

  static const _growthMessages = [
    'Ogni domanda ha rafforzato le tue connessioni neurali',
    'Lo sforzo che stai facendo è il vero apprendimento',
    'Le difficoltà che senti sono il cervello che cresce',
    'Stai costruendo conoscenza che durerà nel tempo',
    'Il tuo impegno sta creando nuovi percorsi neurali',
  ];

  Widget _buildChunkBreak(ExamSession session) {
    final chunk = session.currentChunk - 1; // just completed
    final correct = session.chunkCorrectCount(chunk);
    final total = session.chunkTotalCount(chunk);
    final msg = _growthMessages[chunk % _growthMessages.length];

    // Auto-dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _showingChunkBreak) {
        setState(() => _showingChunkBreak = false);
        _startTimer();
      }
    });

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📦', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 16),
          Text('Blocco ${chunk + 1}/${session.totalChunks} completato',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text('$correct/$total consolidate in questo blocco',
            style: TextStyle(color: _cyan.withValues(alpha: 0.7), fontSize: 14)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _green.withValues(alpha: 0.15)),
            ),
            child: Text('🌱 $msg',
              textAlign: TextAlign.center,
              style: TextStyle(color: _green.withValues(alpha: 0.8), fontSize: 13, height: 1.4, fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 24),
          _btn(label: 'Continua →', color: _cyan, onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _showingChunkBreak = false);
            _startTimer();
          }),
        ]),
      ),
    );
  }

  // ─── METACOGNITIVE CALIBRATION CARD ─────────────────────────────────────

  Widget _buildCalibrationCard(ExamSession session) {
    // Calculate confidence-accuracy calibration
    final answered = session.questions.where((q) => q.isAnswered && q.confidenceLevel != null).toList();
    if (answered.isEmpty) return const SizedBox.shrink();

    // Normalize: confidence 1-5 → 0-1, accuracy binary 0/1
    double sumDelta = 0;
    for (final q in answered) {
      final confNorm = (q.confidenceLevel! - 1) / 4.0; // 0.0 → 1.0
      final accNorm = q.isCorrect ? 1.0 : 0.0;
      sumDelta += confNorm - accNorm;
    }
    final avgDelta = sumDelta / answered.length; // positive = overconfident

    final String insight;
    final Color barColor;
    if (avgDelta > 0.3) {
      insight = 'Tendi a sopravvalutarti — prova a essere più cauto prima di rispondere';
      barColor = _orange;
    } else if (avgDelta < -0.3) {
      insight = 'Ti sottovaluti — fidati di più delle tue conoscenze!';
      barColor = _cyan;
    } else {
      insight = 'Ottima calibrazione metacognitiva — conosci bene i tuoi limiti';
      barColor = _green;
    }

    // Bar position: -1 (underconfident) to +1 (overconfident), center = calibrated
    final barPos = avgDelta.clamp(-1.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: barColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: barColor.withValues(alpha: 0.20)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📊 La tua calibrazione', style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        // Calibration bar
        SizedBox(height: 20, child: LayoutBuilder(builder: (_, constraints) {
          final w = constraints.maxWidth;
          final indicatorX = (barPos + 1) / 2 * w; // 0 → w
          return Stack(children: [
            // Track
            Positioned(top: 8, left: 0, right: 0, child: Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF69F0AE), Color(0xFFFFAB40)]),
              ),
            )),
            // Labels
            Positioned(top: 0, left: 0, child: Text('Sottovaluti',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 8))),
            Positioned(top: 0, right: 0, child: Text('Sopravvaluti',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 8))),
            // Indicator dot
            Positioned(top: 4, left: indicatorX - 6, child: Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: barColor,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
              ),
            )),
          ]);
        })),
        const SizedBox(height: 8),
        Text(insight, style: TextStyle(color: barColor.withValues(alpha: 0.8), fontSize: 11, height: 1.3)),
      ]),
    );
  }

  // ─── RESULTS ────────────────────────────────────────────────────────────

  Widget _buildResults(ExamSession session) {
    final score = (session.score * 100).round();
    final review = session.clustersToReview;
    final mins = session.durationSeconds ~/ 60;
    final secs = session.durationSeconds % 60;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildHeader('Risultati', showClose: false),
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Stars
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedBuilder(animation: _enterController, builder: (_, __) =>
                Transform.scale(scale: i < session.stars ? (0.7 + 0.3 * _enterController.value) : 0.75,
                  child: Icon(
                    i < session.stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 42, color: i < session.stars ? const Color(0xFFFFD600) : Colors.white.withValues(alpha: 0.12)),
                )),
            ))),
          const SizedBox(height: 18),

          // Score circle
          _ScoreCircle(score: score, color: _progressColor(session)),
          const SizedBox(height: 6),
          Text('Hai affrontato ${session.questions.length} sfide — ${session.correctCount} consolidate',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
          const SizedBox(height: 4),
          Text('Durata: ${mins}m ${secs.toString().padLeft(2, '0')}s',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
          const SizedBox(height: 20),

          // 📊 METACOGNITIVE CALIBRATION CARD
          _buildCalibrationCard(session),
          const SizedBox(height: 20),

          // 📦 PER-CHUNK BREAKDOWN
          if (session.totalChunks > 1) ...[
            Align(alignment: Alignment.centerLeft,
              child: Text('📦 Rendimento per blocco:', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12))),
            const SizedBox(height: 8),
            ...List.generate(session.totalChunks, (chunk) {
              final correct = session.chunkCorrectCount(chunk);
              final total = session.chunkTotalCount(chunk);
              final pct = total > 0 ? correct / total : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  SizedBox(width: 50, child: Text('B${chunk + 1}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11))),
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      valueColor: AlwaysStoppedAnimation(pct > 0.7 ? _green : pct > 0.4 ? _orange : _red)),
                  )),
                  SizedBox(width: 40, child: Text(' $correct/$total',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
                    textAlign: TextAlign.right)),
                ]),
              );
            }),
            const SizedBox(height: 8),
          ],

          // Per-question
          ...session.questions.map((q) => _questionResultRow(q)),

          // Review chips
          if (review.isNotEmpty) ...[
            const SizedBox(height: 20),
            Align(alignment: Alignment.centerLeft,
              child: Text('⏰ Da ripassare:', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8,
              children: review.take(6).map((t) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _red.withValues(alpha: 0.28))),
                child: Text(t, style: TextStyle(color: _red.withValues(alpha: 0.8), fontSize: 12)),
              )).toList()),
          ],
        ]),
      )),

       Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(children: [
          // Error replay button
          if (widget.controller.incorrectQuestions.isNotEmpty) ...[
            _btn(label: '🔄 Rafforza ${widget.controller.incorrectQuestions.length} concetti — ogni ripasso è crescita', color: _orange, onTap: () {
              HapticFeedback.mediumImpact();
              setState(() { _scopeSelected = true; _revealed = false; _evalText = ''; _confidenceLevel = 0; _currentStreak = 0; });
              widget.controller.startErrorReplay();
            }),
            const SizedBox(height: 8),
          ],
          _btn(label: 'Torna al canvas', color: _cyan, onTap: () {
            widget.onComplete(widget.controller.masteredConcepts, widget.controller.reviewSchedule);
            widget.onClose();
          }),
        ]),
      ),
    ]);
  }

  Widget _questionResultRow(ExamQuestion q) {
    final (icon, color) = switch (q.result) {
      ExamAnswerResult.correct   => ('✓', _green),
      ExamAnswerResult.partial   => ('≈', _orange),
      ExamAnswerResult.incorrect => ('✗', _red),
      _ => ('→', Colors.white.withValues(alpha: 0.25)),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(children: [
        Text(icon, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 9),
        Expanded(child: Text(
          q.questionText.length > 58 ? '${q.questionText.substring(0, 55)}...' : q.questionText,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12))),
      ]),
    );
  }

  // ─── HISTORY PANEL ──────────────────────────────────────────────────────

  Widget _buildHistoryPanel() {
    final history = widget.controller.history;
    // Build sparkline data per topic
    final Map<String, List<double>> topicScores = {};
    for (final r in history) {
      for (final t in r.topicTitles) {
        topicScores.putIfAbsent(t, () => []);
        topicScores[t]!.add(r.score);
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(children: [
          GestureDetector(
            onTap: () => setState(() => _showHistory = false),
            child: Icon(Icons.arrow_back_rounded, color: Colors.white.withValues(alpha: 0.5), size: 20)),
          const SizedBox(width: 10),
          Text('Storico sessioni', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      ),
      // Sparklines per-topic
      if (topicScores.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(children: topicScores.entries.take(5).map((e) {
            final scores = e.value.reversed.take(6).toList().reversed.toList();
            final trending = scores.length >= 2 && scores.last >= scores.first;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(child: Text(e.key,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11))),
                const SizedBox(width: 8),
                SizedBox(width: 60, height: 18,
                  child: CustomPaint(painter: _SparklinePainter(
                    scores: scores,
                    color: trending ? _green : _red,
                  ))),
                const SizedBox(width: 6),
                Text(trending ? '↑' : '↓',
                  style: TextStyle(color: trending ? _green : _red, fontSize: 12)),
              ]),
            );
          }).toList()),
        ),
        Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
      ],
      Expanded(
        child: history.isEmpty
          ? Center(child: Text('Nessuna sessione completata finora.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13)))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: history.length,
              itemBuilder: (_, i) {
                final r = history[i];
                final score = (r.score * 100).round();
                final color = score >= 70 ? _green : score >= 40 ? _orange : _red;
                final date = '${r.date.day}/${r.date.month} ${r.date.hour}:${r.date.minute.toString().padLeft(2,'0')}';
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.2))),
                  child: Row(children: [
                    Text('$score%', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.topicTitles.take(3).join(', '),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                      const SizedBox(height: 2),
                      Text('$date · ${r.correctCount}/${r.totalQuestions}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
                    ])),
                  ]),
                );
              },
            ),
      ),
    ]);
  }


  // ─── Streak helper ────────────────────────────────────────────────────────

  void _updateStreak(ExamAnswerResult result) {
    if (result == ExamAnswerResult.correct) {
      _currentStreak++;
      if (_currentStreak >= 5) HapticFeedback.heavyImpact();
    } else {
      _currentStreak = 0;
    }
  }

  // ─── SHARED ─────────────────────────────────────────────────────────────

  Widget _buildHeader(String title, {required bool showClose}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Row(children: [
        AnimatedBuilder(animation: _glowController, builder: (_, __) =>
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: _cyan.withValues(alpha: 0.11),
              border: Border.all(color: _cyan.withValues(alpha: 0.35 + _glowController.value * 0.2)),
              boxShadow: [BoxShadow(color: _cyan.withValues(alpha: 0.15 + _glowController.value * 0.1), blurRadius: 8)]),
            child: const Center(child: Text('🎓', style: TextStyle(fontSize: 11))),
          )),
        const SizedBox(width: 9),
        Text('ATLAS EXAM', style: TextStyle(color: _cyan.withValues(alpha: 0.85), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2)),
        const SizedBox(width: 6),
        Text('·', style: TextStyle(color: Colors.white.withValues(alpha: 0.18))),
        const SizedBox(width: 6),
        Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
        if (showClose)
          GestureDetector(onTap: _confirmClose,
            child: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.35), size: 19)),
      ]),
    );
  }

  Widget _buildLoading(String hint) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(animation: _glowController, builder: (_, __) =>
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(shape: BoxShape.circle,
            border: Border.all(color: _cyan.withValues(alpha: 0.25 + _glowController.value * 0.3), width: 1.5),
            boxShadow: [BoxShadow(color: _cyan.withValues(alpha: 0.08 + _glowController.value * 0.12), blurRadius: 20)]),
          child: const Center(child: Text('⚡', style: TextStyle(fontSize: 24))),
        )),
      const SizedBox(height: 16),
      Text(hint, style: TextStyle(color: _cyan.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(height: 10),
      SizedBox(width: 180,
        child: LinearProgressIndicator(
          backgroundColor: Colors.white.withValues(alpha: 0.05),
          valueColor: AlwaysStoppedAnimation<Color>(_cyan.withValues(alpha: 0.45)))),
    ]));
  }

  Widget _buildError(String message) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('⚠️', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 14),
        Text(message, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 14), textAlign: TextAlign.center),
        const SizedBox(height: 22),
        _btn(label: 'Chiudi', color: Colors.white.withValues(alpha: 0.14), onTap: widget.onClose),
      ]),
    ));
  }

  Widget _buildDifficultyBanner(String text) {
    return Positioned(
      top: 60, left: 16, right: 16,
      child: AnimatedOpacity(
        opacity: _difficultyBanner != null ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _orange.withValues(alpha: 0.4))),
          child: Row(children: [
            Text('🎯', style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(child: Text(text.replaceFirst('🎯 ', ''),
              style: TextStyle(color: _orange, fontSize: 13, fontWeight: FontWeight.w500))),
          ]),
        ),
      ),
    );
  }

  Widget _btn({required String label, required Color color, required VoidCallback? onTap, bool small = false}) {
    final isGhost = color.a < 0.5;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: small ? 42 : 50,
        padding: EdgeInsets.symmetric(horizontal: small ? 14 : 0),
        decoration: BoxDecoration(
          color: isGhost ? color.withValues(alpha: 0.12) : color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: isGhost ? color.withValues(alpha: 0.2) : color.withValues(alpha: 0.5))),
        child: Center(child: Text(label, style: TextStyle(
          color: isGhost ? Colors.white.withValues(alpha: 0.45) : color,
          fontSize: small ? 13 : 15, fontWeight: FontWeight.w600))),
      ),
    );
  }

  Color _progressColor(ExamSession session) {
    final s = session.answeredCount == 0 ? 0.5 : session.correctCount / session.answeredCount;
    if (s >= 0.7) return _green;
    if (s >= 0.4) return _orange;
    return _red;
  }

  void _confirmClose() {
    final session = widget.controller.session;
    if (session != null && !session.isComplete && session.answeredCount > 0) {
      showDialog(context: context, builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Uscire dall\'esame?', style: TextStyle(color: Colors.white)),
        content: Text('Hai già risposto a ${session.answeredCount} domande.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.55))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Continua')),
          TextButton(onPressed: () { Navigator.pop(context); widget.onClose(); },
            child: const Text('Esci', style: TextStyle(color: Color(0xFFFF5252)))),
        ],
      ));
    } else {
      widget.onClose();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Score Circle
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreCircle extends StatelessWidget {
  final int score;
  final Color color;
  const _ScoreCircle({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110, height: 110,
      child: CustomPaint(
        painter: _CirclePainter(score / 100, color),
        child: Center(child: Text('$score%',
          style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w700))),
      ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  final double progress;
  final Color color;
  _CirclePainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    canvas.drawCircle(c, r, Paint()..color = Colors.white.withValues(alpha: 0.05)..style = PaintingStyle.stroke..strokeWidth = 7);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2, 2 * math.pi * progress, false,
      Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 7..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_CirclePainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sparkline Painter — mini trend chart for history topics
// ─────────────────────────────────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final List<double> scores;
  final Color color;
  _SparklinePainter({required this.scores, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.length < 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final path = ui.Path();
    final dx = size.width / (scores.length - 1);
    for (int i = 0; i < scores.length; i++) {
      final x = i * dx;
      final y = size.height - (scores[i].clamp(0, 1) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    // Dot at last point
    final lastX = (scores.length - 1) * dx;
    final lastY = size.height - (scores.last.clamp(0, 1) * size.height);
    canvas.drawCircle(Offset(lastX, lastY), 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => true;
}
