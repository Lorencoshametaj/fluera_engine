import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/generated/fluera_localizations.g.dart';
import '../ai/exam_session_model.dart';
import '../ai/exam_session_controller.dart';
import '../widgets/latex_preview_card.dart';
import 'components/handwriting_scratchpad.dart';
import 'exam_answer_fullscreen.dart';

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

/// 🎓 Visual layout of the [ExamOverlay] (Sprint 6).
///
/// `fullscreen` is the legacy behaviour — the overlay paints an opaque
/// background covering the whole screen. Used when the student opens the
/// exam from the Atlas menu / chat keyword, where the canvas is irrelevant
/// to the question.
///
/// `surgicalPath` paints the question card in the lower third of the screen
/// while leaving the canvas above visible. Pairs with the
/// [SurgicalPathOverlayPainter] which highlights blind-spot clusters and
/// pulses the current question's source cluster — preserves the spatial
/// memory grounding (`teoria_cognitiva_apprendimento.md` §22) when the
/// exam is launched from the Fog of War mastery summary.
enum ExamOverlayLayout {
  fullscreen,
  surgicalPath,
}

class ExamOverlay extends StatefulWidget {
  final Map<String, String> availableClusters; // clusterId → display title
  final Map<String, String> clusterTexts;       // clusterId → OCR text
  final ExamSessionController controller;
  final VoidCallback onClose;
  final void Function(List<String> mastered, Map<String, Duration> review) onComplete;

  /// Pre-selected cluster IDs at the scope picker.
  ///
  /// Used by the **Fog of War → Atlas Examiner** integration (Sprint 5):
  /// when the student finishes the spatial recall and taps "Interrogami
  /// sui blind spot", the picker opens with the forgotten/blind-spot
  /// clusters already ticked so they only need to confirm with "Inizia".
  ///
  /// Empty / null → normal first-run picker behaviour.
  final Set<String>? initialSelectedClusterIds;

  /// Visual layout — see [ExamOverlayLayout].
  ///
  /// Defaults to [ExamOverlayLayout.fullscreen] for backwards compatibility
  /// with the Atlas menu / chat keyword entry points (Sprint 1-4).
  /// Set to [ExamOverlayLayout.surgicalPath] when launched from Fog of War
  /// (Sprint 6) so the canvas behind stays visible.
  final ExamOverlayLayout layout;

  /// Initial number of questions for the picker slider. Defaults to 7
  /// (legacy behavior). The host app reads from [ExamPreferences] and
  /// passes the persisted value here.
  final int initialQuestionCount;

  /// Initial input mode (handwriting vs keyboard). Defaults to handwriting.
  final bool initialHandwritingMode;

  /// Master switch for the hypercorrection shock UI (red flash + shake on
  /// overconfident-wrong answers). Defaults to true. Disabling skips the
  /// visceral feedback while preserving the cognitive logic in the model.
  final bool hypercorrectionEnabled;

  /// When true, the exam overlay disables glow/pulse loops + pre-fires the
  /// hypercorrection haptic without the shake. The widget also honours the
  /// OS-level [MediaQueryData.disableAnimations] independently.
  final bool reduceMotion;

  /// When true, swap the result palette to a deuteranopia-safe set
  /// (blue=correct, orange-dark=incorrect, yellow=partial) and ensure every
  /// feedback row is also tagged with a glyph (✓ ≈ ✗) so colour-blind
  /// students don't lose information.
  final bool colorBlindSafePalette;

  /// Persistence callbacks — fired when the user changes a preference inside
  /// the picker (slider drag, mode toggle). Host app forwards to
  /// [ExamPreferences] setters. Optional — picker works without persistence.
  final ValueChanged<int>? onQuestionCountChanged;
  final ValueChanged<bool>? onHandwritingModeChanged;

  /// Cloud sink for stroke JSON. Non-null = "cloud sync enabled" (the
  /// host gates this on tier — Plus / Pro pass a sink, Free passes
  /// null). Called AFTER each successful local save with the storage
  /// key + JSON payload. Failures are silent — local persistence is
  /// the source of truth.
  final Future<void> Function(String key, String json)? onUploadExamStrokes;

  /// Scope-narrowing telemetry: how many topics WERE in the canvas vs how
  /// many made it into the picker. Drives a banner so the student
  /// understands "you're seeing 8/137 because of X". `null` when no
  /// scope filter was applied (full canvas already small enough).
  final int? scopeTotalClusterCount;

  /// One of `'viewport'`, `'lasso'`, or null. Picks the banner copy.
  final String? scopeReason;

  /// Fired when the user taps "Show all" in the scope banner. The host
  /// re-mounts the overlay without the scope filter.
  final VoidCallback? onShowAllClusters;

  /// 🌉 Recently accepted Cross-Zone Bridges to be validated as
  /// NON-Socratic exam questions appended after the main batch.
  /// Tuple shape mirrors `GeminiProvider.generateCrossDomainQuestions`.
  /// When null or empty no extra questions are generated.
  final List<({
    String sourceLabel,
    String targetLabel,
    String socraticQuestion,
    String sourceClusterId,
    String targetClusterId,
  })>? crossZoneBridges;

  const ExamOverlay({
    super.key,
    required this.availableClusters,
    required this.clusterTexts,
    required this.controller,
    required this.onClose,
    required this.onComplete,
    this.initialSelectedClusterIds,
    this.layout = ExamOverlayLayout.fullscreen,
    this.initialQuestionCount = 7,
    this.initialHandwritingMode = true,
    this.hypercorrectionEnabled = true,
    this.reduceMotion = false,
    this.colorBlindSafePalette = false,
    this.onQuestionCountChanged,
    this.onHandwritingModeChanged,
    this.scopeTotalClusterCount,
    this.scopeReason,
    this.onShowAllClusters,
    this.onUploadExamStrokes,
    this.crossZoneBridges,
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
  // _questionCount is initialised from `widget.initialQuestionCount` in
  // initState; when the user drags the slider, the change is propagated to
  // the host app via `widget.onQuestionCountChanged` for persistence.
  int _questionCount = 7;
  bool _timerEnabled = false;
  bool _showHistory = false;

  // Question state
  final TextEditingController _answerCtrl = TextEditingController();
  final TextEditingController _elaborationCtrl = TextEditingController();
  // _isHandwritingMode initialised from `widget.initialHandwritingMode` in
  // initState; toggling propagates via `widget.onHandwritingModeChanged`.
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

  // Pseudo-determinate progress while Gemini generates the question batch.
  // Uses an asymptotic curve (1 - exp(-t/τ)) instead of an AnimationController
  // tween: the bar approaches 1.0 forever-but-never-reaches without a hard
  // stall, even on Gemini calls that exceed 60+ seconds. The earlier
  // implementation stalled visibly at 99% when the call took longer than
  // the controller duration — easy to perceive as "frozen".
  Stopwatch? _loadingStopwatch;
  Timer? _loadingTickTimer;
  // Snap-to-100% transition state. When the controller flips loading=false
  // we record the current progress + snap start time; the getter then
  // linearly interpolates to 1.0 over 350ms for the satisfying "click".
  double? _snapFromValue;
  Stopwatch? _snapStopwatch;
  bool _wasLoading = false;

  // True between the moment the user taps "Inizia l'interrogazione" and
  // the controller actually flips `isLoading=true`. Without this the button
  // looks unresponsive during the anti-cramming dialog / language sync gap
  // (the loading screen only mounts after the controller call fires).
  bool _starting = false;

  // Confidence rating (1-5) — Hypercorrection Effect (Butterfield & Metcalfe, 2001)
  // Numeric only — emoji removed (see leggi_ui_ux.md §V.2: no gamification cheap).
  int _confidenceLevel = 0; // 0 = not set, 1-5 = selected

  // Language selector — initialised from the controller's language (which
  // is set from the device locale at construction). Picker change overrides.
  late String _examLang;

  // Timer
  Timer? _questionTimer;
  int _timerSecondsLeft = 30;
  static const _timerDuration = 30;
  late final AnimationController _timerController;

  // 📦 Progressive Chunking
  bool _showingChunkBreak = false;

  // ── Palette ────────────────────────────────────────────────────────────
  // Accent colors are vivid enough to read against either brightness.
  // Full light-mode coverage (text/background contrast on every surface)
  // is deferred to Sprint 5+ — would require auditing 100+ inline
  // `Colors.white.withValues(alpha: x)` calls. For V1 the overlay is
  // dark-mode-first; only the root background adapts.
  static const _cyan = Color(0xFF00E5FF);
  static const _greenDefault = Color(0xFF69F0AE);
  static const _redDefault = Color(0xFFFF5252);
  static const _orangeDefault = Color(0xFFFFAB40);
  // Deuteranopia-safe palette (used when widget.colorBlindSafePalette is on).
  // Reference: Wong (2011) "Points of view: Color blindness", Nature Methods.
  static const _greenSafe = Color(0xFF1976D2); // Blue (correct)
  static const _redSafe = Color(0xFFE65100);   // Dark orange (incorrect)
  static const _orangeSafe = Color(0xFFFBC02D); // Yellow (partial)
  static const _purple = Color(0xFFCE93D8);
  static const _bgDark = Color(0xF00A0A1A);
  static const _bgLight = Color(0xFFEFEFF4);

  Color get _green => widget.colorBlindSafePalette ? _greenSafe : _greenDefault;
  Color get _red => widget.colorBlindSafePalette ? _redSafe : _redDefault;
  Color get _orange => widget.colorBlindSafePalette ? _orangeSafe : _orangeDefault;

  /// Background that adapts to the parent theme's brightness.
  /// Falls back to dark when no theme is in scope (legacy behaviour).
  Color get _bg {
    if (!mounted) return _bgDark;
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.light ? _bgLight : _bgDark;
  }

  @override
  void initState() {
    super.initState();
    _examLang = widget.controller.language;
    _questionCount = widget.initialQuestionCount.clamp(3, 15);
    _isHandwritingMode = widget.initialHandwritingMode;
    _enterController = AnimationController(
      vsync: this,
      duration: widget.reduceMotion ? Duration.zero : const Duration(milliseconds: 500),
    )..forward();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (!widget.reduceMotion) {
      _glowController.repeat(reverse: true);
    }
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

    // Sprint 5 — Fog↔Exam handoff: pre-tick the picker with the cluster
    // IDs the caller passed (typically the forgotten / blind-spot nodes
    // from the Fog of War surgical plan).
    final initial = widget.initialSelectedClusterIds;
    if (initial != null && initial.isNotEmpty) {
      for (final id in initial) {
        if (widget.availableClusters.containsKey(id)) {
          _selectedIds.add(id);
        }
      }
    }

    // Defensive: if the controller is ALREADY loading at mount time (e.g.
    // a programmatic `startExam` call that fired before the overlay built),
    // bootstrap the progress animation so the user sees feedback in the
    // first frame instead of a flat 0% bar.
    if (widget.controller.isLoading && widget.controller.session == null) {
      _wasLoading = true;
      _startLoadingProgress();
    }

    // Resume support: if a session is already loaded (e.g. from checkpoint),
    // skip the scope picker and rehydrate the UI state for the current Q.
    // Complete sessions also skip the picker — the build path will render
    // the results screen directly (covers test rehydration + any future
    // "view a past session" entry-point that mounts an old session).
    final resumed = widget.controller.session;
    if (resumed != null && resumed.isComplete) {
      _scopeSelected = true;
    }
    if (resumed != null && !resumed.isComplete) {
      _scopeSelected = true;
      final q = resumed.currentQuestion;
      if (q != null) {
        _confidenceLevel = q.confidenceLevel ?? 0;
        if (q.userAnswer != null) _answerCtrl.text = q.userAnswer!;
        if (q.elaboration != null) _elaborationCtrl.text = q.elaboration!;
        // If the Q was already answered before the crash, jump straight to
        // the reveal/feedback state so the student can continue with elaboration
        // or move to the next question.
        if (q.isAnswered) {
          _revealed = true;
          _evalText = widget.controller.currentEvalText.isNotEmpty
              ? widget.controller.currentEvalText
              : q.explanation;
        }
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    _enterController.dispose();
    _glowController.dispose();
    _timerController.dispose();
    _shakeController.dispose();
    _loadingTickTimer?.cancel();
    _loadingStopwatch?.stop();
    _snapStopwatch?.stop();
    _answerCtrl.dispose();
    _elaborationCtrl.dispose();
    _questionTimer?.cancel();
    _chunkPauseTimer?.cancel();
    super.dispose();
  }

  // ─── Loading progress (asymptotic, never stalls) ─────────────────────────

  /// Time constant τ in milliseconds. Larger τ = slower curve.
  /// τ=18000 means: 12% at 2.4s, 39% at 9s, 63% at 18s, 86% at 36s, 95% at
  /// 54s, 98% at 72s — bar always visibly moving even on slow Gemini calls.
  static const int _loadingTau = 18000;

  void _startLoadingProgress() {
    _loadingTickTimer?.cancel();
    _snapStopwatch = null;
    _snapFromValue = null;
    _loadingStopwatch = Stopwatch()..start();
    // 50ms tick (~20 FPS) is enough — the bar moves slowly anyway.
    _loadingTickTimer =
        Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _finishLoadingProgress() {
    if (_loadingStopwatch == null) return;
    _snapFromValue = _rawLoadingProgress();
    _snapStopwatch = Stopwatch()..start();
    // Keep the tick going for the snap-to-100 (~350ms), then stop.
    _loadingStopwatch?.stop();
    _loadingTickTimer?.cancel();
    _loadingTickTimer =
        Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (!mounted) { t.cancel(); return; }
      if ((_snapStopwatch?.elapsedMilliseconds ?? 0) >= 360) {
        t.cancel();
        _snapStopwatch?.stop();
      }
      setState(() {});
    });
  }

  double _rawLoadingProgress() {
    final ms = _loadingStopwatch?.elapsedMilliseconds ?? 0;
    if (ms <= 0) return 0;
    // Asymptotic: 1 - exp(-t/τ). Approaches 1.0 forever-but-never-reaches.
    final t = ms / _loadingTau;
    // exp(-t) — fast convergence approximation. dart:math.exp is fine but we
    // cap at t=8 to avoid floating noise (1 - exp(-8) = 0.9997).
    final clamped = t > 8 ? 8.0 : t;
    return 1.0 - math.exp(-clamped);
  }

  double get _loadingProgress {
    if (_snapStopwatch != null) {
      final t = (_snapStopwatch!.elapsedMilliseconds / 350.0).clamp(0.0, 1.0);
      final from = _snapFromValue ?? 0.0;
      // easeOut for the snap so the final 30ms decelerate (feels like "click")
      final eased = 1 - math.pow(1 - t, 2).toDouble();
      return from + (1.0 - from) * eased;
    }
    return _rawLoadingProgress();
  }

  // Called whenever controller state changes: detect first question load
  String? _lastQuestionId;
  void _onControllerChange() {
    // ── Loading progress lifecycle ────────────────────────────────────────
    // We're "loading" specifically while building the first batch — no
    // session yet but the controller has flipped isLoading. After the
    // session arrives, the progress bar belongs to a different state and
    // we don't drive it.
    final isLoading =
        widget.controller.isLoading && widget.controller.session == null;
    if (isLoading && !_wasLoading) {
      _startLoadingProgress();
    } else if (!isLoading && _wasLoading) {
      // Snap to 100% on completion — visible "click! pronto" feedback.
      _finishLoadingProgress();
    }
    _wasLoading = isLoading;

    // ── First-question timer kickoff (existing) ──────────────────────────
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
    // Sprint 6 — surgicalPath layout: the canvas behind must stay visible,
    // so the root Material is transparent and the body sits in the
    // lower-third only. Telemetry fires once per overlay lifetime so we
    // can measure adoption of the integrated flow.
    final isSurgicalPath = widget.layout == ExamOverlayLayout.surgicalPath;
    if (isSurgicalPath && !_surgicalTelemetryFired) {
      _surgicalTelemetryFired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Telemetry recorder lives on the controller, where the rest of
        // step_11 events are emitted.
        widget.controller.logSurgicalPathRendered();
      });
    }

    return AnimatedBuilder(
      animation: _enterController,
      builder: (_, child) => FadeTransition(opacity: _enterController, child: child),
      child: Material(
        // Transparent in surgicalPath — see comment above.
        color: isSurgicalPath ? Colors.transparent : _bg,
        // Desktop keyboard shortcuts (P3.4) — wraps the whole overlay so
        // the focus stays even after dialogs close. autofocus=true so the
        // student can use 1/2/3/4 immediately without clicking first.
        child: Focus(
          autofocus: true,
          onKeyEvent: _handleKey,
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
                return isSurgicalPath
                    ? _buildSurgicalPathLayout()
                    : Stack(
                        children: [
                          _buildBody(),
                          if (_difficultyBanner != null)
                            _buildDifficultyBanner(_difficultyBanner!),
                        ],
                      );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Sprint 6 — surgicalPath layout: lower-third question card with a
  /// drag handle that expands to fullscreen on demand. The upper area is
  /// touch-pass-through so the canvas behind handles pinch/pan normally.
  ///
  /// The drag handle is the affordance for "I want to focus, hide the
  /// canvas" — it ramps the card up to full height with a Tween.
  bool _surgicalExpanded = false;

  Widget _buildSurgicalPathLayout() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final h = constraints.maxHeight;
        // 0.42 of screen height is enough for question + confidence + input
        // on phones in portrait. Tablet portrait gets the same.
        final cardHeight = _surgicalExpanded ? h : (h * 0.42).clamp(280.0, 520.0);
        return Stack(
          children: [
            // The upper 58% is pass-through — Stack children with no
            // Positioned + no Container with hit testing don't intercept
            // gestures, so the canvas behind reacts naturally to pinch.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: Container(color: Colors.transparent),
              ),
            ),
            if (_difficultyBanner != null) _buildDifficultyBanner(_difficultyBanner!),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                height: cardHeight,
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Drag handle — tap toggles expanded/collapsed.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() {
                        _surgicalExpanded = !_surgicalExpanded;
                      }),
                      onVerticalDragUpdate: (d) {
                        // Drag up by ≥30 px → expand; drag down → collapse.
                        if (d.delta.dy < -3 && !_surgicalExpanded) {
                          setState(() => _surgicalExpanded = true);
                        } else if (d.delta.dy > 3 && _surgicalExpanded) {
                          setState(() => _surgicalExpanded = false);
                        }
                      },
                      child: SizedBox(
                        height: 26,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.30),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: _buildBody()),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _surgicalTelemetryFired = false;

  /// Desktop keyboard shortcuts (P3.4).
  ///
  /// Number keys map to the visible choice buttons of the current question
  /// when applicable. Enter advances. Esc closes (with confirmation).
  /// `?` opens the hint. Skips the handler entirely if the user is typing
  /// in a text field (we don't want '1' to mean "answer A" while writing
  /// an open-ended response).
  KeyEventResult _handleKey(FocusNode node, KeyEvent ev) {
    if (ev is! KeyDownEvent) return KeyEventResult.ignored;

    // Don't steal keys while the user is in a text input.
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary != node && primary.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }
    if (_answerCtrl.text.isNotEmpty || _elaborationCtrl.text.isNotEmpty) {
      // Heuristic: if any text field has user input, focus is likely there.
      // Bail out for digits to avoid mid-typing surprise.
      if (ev.logicalKey == LogicalKeyboardKey.digit1 ||
          ev.logicalKey == LogicalKeyboardKey.digit2 ||
          ev.logicalKey == LogicalKeyboardKey.digit3 ||
          ev.logicalKey == LogicalKeyboardKey.digit4) {
        return KeyEventResult.ignored;
      }
    }

    final ctrl = widget.controller;
    final session = ctrl.session;
    final q = session?.currentQuestion;

    // Esc → confirm close (works at any state).
    if (ev.logicalKey == LogicalKeyboardKey.escape) {
      _confirmClose();
      return KeyEventResult.handled;
    }

    if (q == null || session == null) return KeyEventResult.ignored;

    // Backspace (or Alt+ArrowLeft) → previous question. Same flow as the
    // back button: rehydrate the prior answer state.
    final isBack = ev.logicalKey == LogicalKeyboardKey.backspace ||
        (ev.logicalKey == LogicalKeyboardKey.arrowLeft &&
            HardwareKeyboard.instance.isAltPressed);
    if (isBack && ctrl.canGoPrevious) {
      // Don't steal Backspace while the user is editing handwriting label.
      final primaryNow = FocusManager.instance.primaryFocus;
      if (primaryNow != null &&
          primaryNow.context?.widget is EditableText) {
        return KeyEventResult.ignored;
      }
      HapticFeedback.selectionClick();
      _stopTimer();
      _answerCtrl.clear();
      _elaborationCtrl.clear();
      _shakeController.reset();
      _shockFlashVisible = false;
      setState(() { _revealed = false; _evalText = ''; });
      if (ctrl.previousQuestion()) {
        final pq = ctrl.session?.currentQuestion;
        if (pq != null) {
          if (pq.userAnswer != null) _answerCtrl.text = pq.userAnswer!;
          if (pq.elaboration != null) _elaborationCtrl.text = pq.elaboration!;
          if (pq.isAnswered) {
            setState(() { _revealed = true; _evalText = pq.explanation; });
          }
        }
      }
      return KeyEventResult.handled;
    }

    // B → toggle bookmark on current question (review later flag).
    if (ev.character?.toLowerCase() == 'b') {
      HapticFeedback.selectionClick();
      setState(() => q.markedForReview = !q.markedForReview);
      return KeyEventResult.handled;
    }

    // Enter → next question if a result is shown, otherwise submit open answer.
    if (ev.logicalKey == LogicalKeyboardKey.enter ||
        ev.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (q.isAnswered || _revealed) {
        // Trigger "next" via the same path the bottom button uses.
        // We find it by simulating its tap behaviour.
        _advanceAfterReveal();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // ? → request hint
    if (ev.character == '?' && !q.isAnswered && !_revealed) {
      _requestHint();
      return KeyEventResult.handled;
    }

    // 1-5 → confidence picker (when not yet set)
    if (!q.isAnswered && _confidenceLevel == 0) {
      final lvl = _digitKeyToInt(ev.logicalKey, max: 5);
      if (lvl != null) {
        HapticFeedback.selectionClick();
        widget.controller.setConfidence(lvl);
        setState(() => _confidenceLevel = lvl);
        return KeyEventResult.handled;
      }
    }

    // 1-4 → choice answer (multiple choice)
    if (!q.isAnswered &&
        _confidenceLevel > 0 &&
        q.type == ExamQuestionType.multipleChoice) {
      final n = _digitKeyToInt(ev.logicalKey, max: 4);
      if (n != null) {
        final idx = n - 1;
        if (idx < q.choices.length) {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedChoiceIndex = idx;
            _revealed = true;
          });
          widget.controller.submitChoiceAnswer(idx);
          _stopTimer();
          return KeyEventResult.handled;
        }
      }
    }

    // V/F → true/false answer
    if (!q.isAnswered &&
        _confidenceLevel > 0 &&
        q.type == ExamQuestionType.trueOrFalse) {
      final char = ev.character?.toLowerCase();
      int? idx;
      if (char == 'v' || char == 't') idx = 0; // Vero / True
      if (char == 'f') idx = 1; // Falso / False
      if (idx != null && idx < q.choices.length) {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedChoiceIndex = idx;
          _revealed = true;
        });
        widget.controller.submitChoiceAnswer(idx);
        _stopTimer();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  /// Map a digit key (1-9) to its integer value, capped at [max].
  /// Returns null if the key isn't a digit in the supported range.
  /// We can't use a const Map<LogicalKeyboardKey, int> because
  /// LogicalKeyboardKey lacks primitive equality (build error on Linux).
  int? _digitKeyToInt(LogicalKeyboardKey key, {required int max}) {
    if (key == LogicalKeyboardKey.digit1 && 1 <= max) return 1;
    if (key == LogicalKeyboardKey.digit2 && 2 <= max) return 2;
    if (key == LogicalKeyboardKey.digit3 && 3 <= max) return 3;
    if (key == LogicalKeyboardKey.digit4 && 4 <= max) return 4;
    if (key == LogicalKeyboardKey.digit5 && 5 <= max) return 5;
    return null;
  }

  /// Advance to the next question. Used by both the keyboard Enter shortcut
  /// and the on-screen "Prossima →" button. Mirrors the inline logic that
  /// was previously duplicated inside the bottom-bar onTap.
  void _advanceAfterReveal() {
    final session = widget.controller.session;
    if (session == null) return;
    HapticFeedback.lightImpact();
    _stopTimer();
    _selectedChoiceIndex = null;
    _hintText = null;
    _confidenceLevel = 0;
    _answerCtrl.clear();
    _elaborationCtrl.clear();
    _shakeController.reset();
    _shockFlashVisible = false;
    setState(() { _revealed = false; _evalText = ''; });
    widget.controller.nextQuestion();
    final s = widget.controller.session;
    if (s != null && !s.isComplete && s.isChunkBoundary) {
      setState(() => _showingChunkBreak = true);
      return;
    }
    if (s != null && !s.isComplete) _startTimer();
  }

  /// Request a hint from Atlas for the current question.
  /// Used by both the keyboard shortcut '?' and the on-screen lightbulb button.
  Future<void> _requestHint() async {
    if (_loadingHint || _hintText != null) return;
    setState(() => _loadingHint = true);
    try {
      final h = await widget.controller.getHint();
      if (mounted) setState(() => _hintText = h);
    } finally {
      if (mounted) setState(() => _loadingHint = false);
    }
  }

  Widget _buildBody() {
    final ctrl = widget.controller;
    final l10n = FlueraLocalizations.of(context)!;
    if (ctrl.error != null) return _buildError(_localizedError(ctrl, l10n));
    if (ctrl.isLoading && widget.controller.session == null) {
      return _buildLoading(ctrl.loadingHint ?? l10n.exam_loading_atlasWorking);
    }
    if (!_scopeSelected) return _buildScopePicker();

    final session = ctrl.session;
    if (session == null) return _buildLoading(l10n.exam_loading_generating);
    if (session.isComplete) return _buildResults(session);
    if (_showingChunkBreak) return _buildChunkBreak(session);
    if (_showHistory) return _buildHistoryPanel();
    return _buildQuestion(session);
  }

  // ─── SCOPE PICKER ───────────────────────────────────────────────────────

  /// Banner shown above the topic chips when the picker pre-selected a
  /// subset based on viewport/lasso. The picker now ALWAYS shows every
  /// cluster — banner clarifies which ones are pre-ticked and offers a
  /// "Deselect all" shortcut for users who prefer to start from blank.
  Widget _scopeBanner() {
    final l10n = FlueraLocalizations.of(context)!;
    final preselected = _selectedIds.length;
    final isLasso = widget.scopeReason == 'lasso';
    final message = isLasso
        ? l10n.exam_scopeBanner_lasso(preselected)
        : l10n.exam_scopeBanner_viewport(preselected);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: _cyan.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _cyan.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            // Primary action — "Mostra tutto" — re-mounts the picker
            // without the viewport filter so the user can pick a topic
            // they wrote far away on the canvas (e.g. Termodinamica
            // while looking at Newton). Hidden when the host didn't
            // wire the re-mount callback (Fog of War surgical path,
            // resume mode, etc.) since those flows pass `null`.
            if (widget.onShowAllClusters != null) ...[
              Expanded(
                child: Semantics(
                  button: true,
                  label: l10n.exam_scopeBanner_showAll,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onShowAllClusters!();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _cyan.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _cyan.withValues(alpha: 0.5)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        l10n.exam_scopeBanner_showAll,
                        style: TextStyle(
                          color: _cyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Secondary action — "Deseleziona tutti" — clears the pre-
            // ticked chips. Useful for the user who wants to start from
            // a blank picker and tick only one of the visible topics.
            Expanded(
              child: Semantics(
                button: true,
                label: l10n.exam_scopeBanner_deselectAll,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedIds.clear());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      l10n.exam_scopeBanner_deselectAll,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildScopePicker() {
    final hasSelection = _selectedIds.isNotEmpty;

    // 🔭 Viewport-narrow filter — when the host pre-narrowed the scope
    // (viewport / lasso intersection), the picker shows ONLY the chips
    // for the in-scope clusters. The "Mostra tutto" button on the
    // scope banner is the explicit escape hatch for the user who
    // wants a chip outside the current viewport (it re-mounts the
    // overlay with `forceShowAll: true` → `scopeReason == null`).
    //
    // Why filter here instead of pre-selecting + showing all: an earlier
    // implementation pre-selected in-scope chips while showing the full
    // chip list. Confirmed UX expectation (user, 2026-05-08): "5 cluster
    // con 2 visibili → mi aspetto il picker filtri a 2." Pre-selection
    // looked like clutter and broke the "what you see is what you get"
    // mental model.
    final entries = (widget.scopeReason != null &&
            widget.initialSelectedClusterIds != null)
        ? widget.availableClusters.entries
            .where((e) => widget.initialSelectedClusterIds!.contains(e.key))
            .toList()
        : widget.availableClusters.entries.toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildHeader('Su cosa vuoi essere interrogato?', showClose: true),
      const SizedBox(height: 8),

      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 🔭 Scope banner — clarifies the pre-selection (viewport / lasso
          // visible cluster IDs were pre-ticked). Hidden when:
          //   • no scope reason (fallback to all-clusters)
          //   • initial selection covers everything (banner adds no info)
          //   • zero clusters are actually pre-selected (would say "0 pre-
          //     selected" — confusing — happens when scope IDs reference
          //     clusters whose OCR text was empty so they got skipped)
          //   • user manually deselected all via the deselect-all button
          if (widget.scopeReason != null &&
              widget.initialSelectedClusterIds != null &&
              widget.initialSelectedClusterIds!.length <
                  widget.availableClusters.length &&
              _selectedIds.isNotEmpty) ...[
            _scopeBanner(),
            const SizedBox(height: 10),
          ],
          Text(FlueraLocalizations.of(context)!.exam_selectTopicsHint,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(height: 12),
          Wrap(spacing: 9, runSpacing: 9, children: [
            _chip(id: '__all__', title: '🗂 Tutti', selected: _selectedIds.contains('__all__'),
              onTap: () => setState(() {
                if (_selectedIds.contains('__all__')) _selectedIds.clear();
                else { _selectedIds.clear(); _selectedIds.add('__all__'); }
              })),
            ...entries.map((e) =>
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
              onChanged: (v) {
                final next = v.round();
                if (next == _questionCount) return;
                setState(() => _questionCount = next);
                widget.onQuestionCountChanged?.call(next);
              },
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
        child: Semantics(
          button: true,
          enabled: hasSelection && !_starting,
          label: hasSelection
              ? FlueraLocalizations.of(context)!.exam_iniziaCta
              : FlueraLocalizations.of(context)!.exam_iniziaSelectAtLeastOne,
          child: GestureDetector(
          onTap: (hasSelection && !_starting) ? () { _startExam(); } : null,
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
              if (_starting && hasSelection) ...[
                SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_cyan),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  FlueraLocalizations.of(context)!.exam_iniziaPreparing,
                  style: TextStyle(
                    color: _cyan, fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ] else ...[
                Icon(Icons.play_arrow_rounded,
                  color: hasSelection ? _cyan : Colors.white.withValues(alpha: 0.2)),
                const SizedBox(width: 8),
                Text(
                  hasSelection
                      ? FlueraLocalizations.of(context)!.exam_iniziaCta
                      : FlueraLocalizations.of(context)!.exam_iniziaSelectAtLeastOne,
                  style: TextStyle(
                    color: hasSelection ? _cyan : Colors.white.withValues(alpha: 0.2),
                    fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ],
            ]),
          ),
        ),
        ),
      ),
    ]);
  }

  Widget _chip({required String id, required String title, required bool selected, required VoidCallback onTap}) {
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: GestureDetector(
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
      ),
    );
  }

  Future<void> _startExam() async {
    if (_starting) return; // double-tap guard
    final Map<String, String> texts = _selectedIds.contains('__all__')
        ? Map.from(widget.clusterTexts)
        : { for (final id in _selectedIds) if (widget.clusterTexts.containsKey(id)) id: widget.clusterTexts[id]! };
    if (texts.isEmpty) return;

    // Immediate visual feedback: button shows a spinner the instant the
    // user taps. Cleared on early-return (anti-cramming cancel / no
    // selection) and naturally subsumed once the controller flips
    // `isLoading=true` and the loading screen takes over.
    setState(() => _starting = true);

    // 🛌 Anti-cramming check (P1.2): warn if any selected cluster was
    // examined less than 4 hours ago. Theory: Spacing Effect — back-to-back
    // testing on the same material produces fragile, transient memory.
    final warning = widget.controller.recentExamFor(texts.keys);
    if (warning != null) {
      final proceed = await _showAntiCrammingDialog(warning);
      if (!mounted) return;
      if (proceed != true) {
        setState(() => _starting = false);
        return; // user cancelled or dismissed
      }
    }

    // Set topic titles for history
    widget.controller.selectedTopicTitles = _selectedIds.contains('__all__')
        ? widget.availableClusters.values.toList()
        : _selectedIds.map((id) => widget.availableClusters[id] ?? id).toList();

    // 🌐 Propagate the picker's language selection to the controller. Until
    // 2026-05-07 the selector was a dead UI control — Italian device users
    // got English questions because the controller's `language` came from
    // the device locale at construction time, not from the picker.
    widget.controller.language = _examLang;

    setState(() { _scopeSelected = true; _revealed = false; _evalText = ''; _selectedChoiceIndex = null; _hintText = null; });
    await widget.controller.startExam(texts, count: _questionCount);

    // 🌉 Passo 9 → Passo 11: validate recently accepted bridges with one
    // NON-Socratic question each. Safe no-op when no bridges qualify.
    final bridges = widget.crossZoneBridges;
    if (mounted && bridges != null && bridges.isNotEmpty) {
      await widget.controller.appendCrossDomainQuestions(
        bridges: bridges,
        clusterTexts: texts,
      );
    }
  }

  /// Returns `true` if the student insists on running the exam now,
  /// `false` (or null) if they cancel.
  Future<bool?> _showAntiCrammingDialog(AntiCrammingWarning warning) {
    // OverlayEntry-based modal — see _confirmClose for the rationale.
    // showDialog can't be used here because ExamOverlay is mounted as a
    // free-standing OverlayEntry above the MaterialApp's Navigator.
    final completer = Completer<bool?>();
    late OverlayEntry entry;
    void close(bool? result) {
      if (!completer.isCompleted) completer.complete(result);
      try {
        entry.remove();
      } catch (_) {/* already removed */}
    }
    entry = OverlayEntry(builder: (_) => Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: GestureDetector(
        onTap: () => close(null), // tap outside dismisses
        child: Center(
          child: GestureDetector(
            onTap: () {}, // intercept inner taps so they don't dismiss
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Builder(builder: (innerCtx) {
                  final l10n = FlueraLocalizations.of(innerCtx)!;
                  return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('🛌', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l10n.exam_antiCramming_title,
                        style: const TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.w600, fontSize: 16))),
                  ]),
                  const SizedBox(height: 12),
                  Text(l10n.exam_antiCramming_body(warning.humanRelative),
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 10),
                  Text(
                    l10n.exam_antiCramming_explainer,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      onPressed: () => close(false),
                      child: Text(l10n.exam_antiCramming_cancel, style: const TextStyle(color: Colors.white70)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => close(true),
                      child: Text(l10n.exam_antiCramming_proceed,
                          style: const TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ]);
                }),
              ),
            ),
          ),
        ),
      ),
    ));
    Overlay.of(context).insert(entry);
    return completer.future;
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
          Semantics(
            button: true,
            label: 'Chiudi esame',
            child: GestureDetector(onTap: _confirmClose,
              child: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.35), size: 19)),
          ),
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
  // Each level maps to a concrete cognitive state. Explicit labels are
  // critical for the Hypercorrection Effect (Butterfield & Metcalfe 2001):
  // if students don't understand the scale, the high-confidence wrong shock
  // is dampened and the +3× memory consolidation never fires.
  static const Map<int, String> _confidenceLabels = {
    1: 'Indovino',
    2: 'Poco sicuro',
    3: 'Più o meno',
    4: 'Quasi certo',
    5: 'Sicurissimo',
  };

  Widget _buildConfidenceSlider(ExamQuestion q) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _purple.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Text('Quanto sei sicuro/a?',
              style: TextStyle(color: _purple, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            // First-time onboarding affordance: tap the (?) to learn why this
            // matters. We do NOT auto-show a tutorial — agency stays with the user.
            GestureDetector(
              onTap: _showConfidenceExplainer,
              child: Icon(
                Icons.help_outline_rounded,
                size: 14,
                color: _purple.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Sii onesto: gli errori commessi con alta sicurezza si ricordano 3× di più',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11, height: 1.4)),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(5, (i) {
            final level = i + 1;
            final selected = _confidenceLevel == level;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: i == 0 || i == 4 ? 0 : 3),
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: 'Fiducia $level su 5: ${_confidenceLabels[level]}',
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.controller.setConfidence(level);
                      setState(() => _confidenceLevel = level);
                    },
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 48,
                          decoration: BoxDecoration(
                            color: selected ? _purple.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: selected ? _purple.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Center(
                            child: Text('$level', style: TextStyle(
                              color: selected ? _purple : Colors.white.withValues(alpha: 0.45),
                              fontSize: 18, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _confidenceLabels[level]!,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TextStyle(
                            color: selected ? _purple.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.35),
                            fontSize: 9.5,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }

  /// Bottom sheet that explains the Hypercorrection Effect in one screen.
  /// Triggered only on user tap of the (?) icon — never auto-shown.
  void _showConfidenceExplainer() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14142A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SingleChildScrollView(
        // Scroll instead of overflow on short viewports (foldables, small
        // tablets in landscape, test viewports). Content rarely needs to
        // scroll, but bounding the height prevents a yellow-stripe overflow.
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(children: [
              Text('🧠', style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                'Perché la tua fiducia conta',
                style: TextStyle(color: _purple, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ]),
            const SizedBox(height: 14),
            Text(
              'Prima di rispondere ti chiediamo quanto sei sicuro/a su una scala 1-5.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 10),
            Text(
              'Se sbagli con alta sicurezza (4-5), il tuo cervello riceve uno "shock" cognitivo che fissa la correzione 3× più forte di un errore "indovinato" (Butterfield & Metcalfe, 2001).',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12, height: 1.55),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _purple.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline_rounded, size: 16, color: _purple.withValues(alpha: 0.8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Non barare. Fingere bassa fiducia per "non fare brutta figura" annulla il beneficio.',
                      style: TextStyle(color: _purple.withValues(alpha: 0.9), fontSize: 11.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Capito', style: TextStyle(color: _purple)),
              ),
            ),
          ],
        ),
      ),
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
          // 🌉 Cross-Domain badge: signals that this question validates a
          // previously accepted bridge, so the student knows the context
          // (transfer-learning check, not a fresh recall).
          if (q.isCrossDomain) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.45),
                  width: 0.8,
                ),
              ),
              child: const Text(
                '🌉 Cross-Domain',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(q.questionText,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      height: 1.5)),
            ),
            const SizedBox(width: 8),
            // Bookmark "review later" toggle. The cognitive logic remains
            // tier-agnostic (just a flag on the question) but the chip in
            // the results view filters to bookmarked items + the FSRS
            // scheduler on completion uses a slightly tighter interval.
            Semantics(
              button: true,
              toggled: q.markedForReview,
              label: q.markedForReview
                  ? 'Rimuovi dai segnalibri'
                  : 'Segna per ripasso successivo',
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => q.markedForReview = !q.markedForReview);
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    q.markedForReview
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_outline_rounded,
                    color: q.markedForReview
                        ? _orange
                        : Colors.white.withValues(alpha: 0.4),
                    size: 22,
                  ),
                ),
              ),
            ),
          ]),
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
    // Screen-reader fallback (P2.1d): the rendered formula is an image, so
    // assistive tech sees nothing useful. We expose the raw LaTeX source
    // as the semantic label — far from perfect (it's still LaTeX syntax),
    // but readable by NVDA/TalkBack and infinitely better than silence.
    return Semantics(
      label: 'Formula: $src',
      child: ExcludeSemantics(
        child: LatexPreviewCard(
          latexSource: src,
          fontSize: fontSize,
          color: _cyan,
          backgroundColor: Colors.transparent,
          minHeight: 60,
        ),
      ),
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
      final letter = String.fromCharCode(65 + idx); // A, B, C, D
      final cleanText = e.value.replaceFirst(RegExp(r'^[A-Da-d]:\s*'), '');
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Semantics(
          button: true,
          enabled: !q.isAnswered,
          selected: _selectedChoiceIndex == idx,
          label: 'Risposta $letter: $cleanText',
          child: GestureDetector(
          onTap: q.isAnswered ? null : () {
            _stopTimer();
            setState(() => _selectedChoiceIndex = idx);
            widget.controller.submitChoiceAnswer(idx);
            final res = q.result ?? ExamAnswerResult.incorrect;
            _hapticForResult(res);
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
              Expanded(child: Text(cleanText,
                style: const TextStyle(color: Colors.white, fontSize: 14))),
            ]),
          ),
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
    return Semantics(
      button: true,
      enabled: !q.isAnswered,
      label: 'Risposta $label',
      child: GestureDetector(
        onTap: q.isAnswered ? null : () {
          _stopTimer();
          widget.controller.submitChoiceAnswer(idx);
          final res = q.result ?? ExamAnswerResult.incorrect;
          _hapticForResult(res);
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
      ),
    );
  }

  /// Translates the controller's structured [ExamErrorCode] into a localized
  /// message. Falls back to the controller's legacy IT string if no code is
  /// set (defensive — older code paths or the empty-content branch may set
  /// only `error` without a code).
  String _localizedError(ExamSessionController ctrl, FlueraLocalizations l10n) {
    final code = ctrl.errorCode;
    switch (code) {
      case ExamErrorCode.quotaExceeded:
        return l10n.exam_error_quotaExceeded;
      case ExamErrorCode.offline:
        return l10n.exam_error_offline;
      case ExamErrorCode.timeout:
        return l10n.exam_error_timeout;
      case ExamErrorCode.unexpected:
        if (ctrl.errorDetail == 'empty_content') return l10n.exam_error_emptyContent;
        if (ctrl.errorDetail == 'replay_failed') return l10n.exam_error_replayFailed;
        return l10n.exam_error_unexpected(ctrl.errorDetail);
      case null:
        return ctrl.error ?? l10n.exam_error_unexpected('');
    }
  }

  /// Compact preview of `_answerCtrl.text` for the inline CTA "Modifica
  /// risposta" subtitle. Single-line, ellipsised by the parent Text widget.
  String _truncatedAnswerPreview() {
    final t = _answerCtrl.text.trim();
    if (t.length <= 60) return t;
    return '${t.substring(0, 58)}…';
  }

  /// Builds a plain-text report of the completed session and copies it to
  /// the clipboard. Includes per-question prompt + user answer + result +
  /// AI explanation. Acts as the V1 "export" feature — pdf package would
  /// be ideal but adding a new dependency is out of scope.
  Future<void> _exportSessionReport(ExamSession session) async {
    final sb = StringBuffer();
    final score = (session.score * 100).round();
    final mins = session.durationSeconds ~/ 60;
    final secs = session.durationSeconds % 60;
    sb.writeln('🎓 Esame Atlas — riepilogo');
    sb.writeln('Punteggio: $score% (${session.correctCount}/${session.questions.length})');
    sb.writeln('Durata: ${mins}m ${secs}s');
    if (widget.controller.selectedTopicTitles.isNotEmpty) {
      sb.writeln('Argomenti: ${widget.controller.selectedTopicTitles.join(", ")}');
    }
    sb.writeln();
    for (var i = 0; i < session.questions.length; i++) {
      final q = session.questions[i];
      sb.writeln('— Domanda ${i + 1} —');
      sb.writeln('Q: ${q.questionText}');
      if (q.userAnswer != null && q.userAnswer!.trim().isNotEmpty) {
        sb.writeln('Tua risposta: ${q.userAnswer}');
      }
      sb.writeln('Risposta corretta: ${q.correctAnswer}');
      final glyph = switch (q.result) {
        ExamAnswerResult.correct => '✓',
        ExamAnswerResult.partial => '≈',
        ExamAnswerResult.incorrect => '✗',
        ExamAnswerResult.skipped => '→',
        null => '…',
      };
      sb.writeln('Esito: $glyph');
      if (q.explanation.isNotEmpty) {
        sb.writeln('Spiegazione: ${q.explanation}');
      }
      if (q.markedForReview) sb.writeln('🔖 Segnato per ripasso');
      if (q.elaboration != null && q.elaboration!.trim().isNotEmpty) {
        sb.writeln('Rielaborazione: ${q.elaboration}');
      }
      sb.writeln();
    }
    await Clipboard.setData(ClipboardData(text: sb.toString()));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('📋 Riepilogo copiato negli appunti'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));
  }

  /// Stable key used by [ExamAnswerFullscreen] to persist the student's
  /// strokes per-question. Format: `<sessionId>__<questionId>`.
  /// Returns `null` (ephemeral, no persistence) when no session is loaded —
  /// e.g. immediately after picker submit, before the controller has set
  /// up the session.
  String? _strokePersistKeyFor(ExamQuestion q, {String suffix = 'answer'}) {
    final sessionId = widget.controller.session?.sessionId;
    if (sessionId == null) return null;
    return '${sessionId}__${q.id}__$suffix';
  }

  /// Cloud sync hook. Forwarded to the answer / elaboration fullscreen
  /// pages. The host gates by tier (passes `null` for Free / signed-out),
  /// so the engine doesn't need a per-feature toggle here.
  Future<void> Function(String key, String json)? get _cloudUploadIfEnabled =>
      widget.onUploadExamStrokes;

  /// Cleans a raw OCR sourceText for the "to review" chip when no topic
  /// title is available. Strips LaTeX residue and truncates to ~40 chars.
  String _sanitizeReviewLabel(String raw) {
    if (raw.isEmpty) return '';
    var cleaned = raw
        .replaceAll(RegExp(r'\\(begin|end)\{[^}]*\}'), '')
        .replaceAll(RegExp(r'\\[A-Za-z]+'), '')
        .replaceAll(RegExp(r'[\{\}\[\]\\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.length > 40) cleaned = '${cleaned.substring(0, 38)}…';
    return cleaned;
  }

  /// Opens the closed-book fullscreen answer page. The page hides the
  /// canvas + cluster overlay completely (the source notes are not visible
  /// during the test). The fullscreen page is the **submission surface** —
  /// tapping "Invia risposta" submits to the controller and pops; the
  /// inline "Invia" button on the compact card is bypassed entirely for
  /// the handwriting flow. This collapses two taps into one.
  Future<void> _openFullscreenAnswer(ExamQuestion q) async {
    final isFormula = q.type == ExamQuestionType.formulaRecall;
    HapticFeedback.selectionClick();
    debugPrint('🎓 ExamOverlay: opening fullscreen answer (formula=$isFormula)');
    // Mount as an OverlayEntry on top of the parent Overlay (the same one
    // that holds ExamOverlay itself). Navigator.push would put the page
    // inside the MaterialApp Navigator which is BELOW any free-standing
    // OverlayEntry — so the fullscreen would render hidden under us. The
    // OverlayEntry path puts it ABOVE.
    final completer = Completer<String?>();
    late OverlayEntry entry;
    void close(String? result) {
      if (!completer.isCompleted) completer.complete(result);
      try {
        entry.remove();
      } catch (_) {/* already removed */}
    }
    try {
      entry = OverlayEntry(builder: (_) => ExamAnswerFullscreen(
            questionText: q.questionText,
            initialAnswer: _answerCtrl.text,
            startsInHandwriting: _isHandwritingMode,
            isFormula: isFormula,
            // Stable key so the mini-canvas restores prior strokes if the
            // student re-opens this same question (back nav + retry).
            persistKey: _strokePersistKeyFor(q),
            onCloudUpload: _cloudUploadIfEnabled,
            onSubmit: (answer) async {
              _stopTimer();
              if (mounted) {
                setState(() {
                  _answerCtrl.text = answer;
                  _revealed = true;
                  _evalText = '';
                });
              }
              await widget.controller.submitOpenAnswer(answer);
              if (mounted) {
                final res = q.result ?? ExamAnswerResult.skipped;
                _hapticForResult(res);
              }
            },
            onSubmitted: (answer) => close(answer),
            onCancelled: () => close(null),
          ));
      Overlay.of(context).insert(entry);
    } catch (e, st) {
      debugPrint('🎓 ExamOverlay: overlay insert failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(FlueraLocalizations.of(context)!
              .exam_error_openFullscreenFailed(e.toString())),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      }
      return;
    }
    final result = await completer.future;
    if (!mounted) return;
    if (result != null && result.trim().isNotEmpty && !_revealed) {
      setState(() {
        _answerCtrl.text = result;
        _answerCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _answerCtrl.text.length),
        );
      });
    }
  }

  /// Opens the fullscreen elaboration page (Generation Effect — Slamecka &
  /// Graf 1978). Same closed-book layout as [_openFullscreenAnswer] but with
  /// a 15-char minimum + red accent when the previous answer was
  /// overconfident-wrong (hypercorrection cue). Submits via
  /// `controller.saveElaboration` directly so the user gets a single-tap
  /// flow here too.
  Future<void> _openFullscreenElaboration(ExamQuestion q) async {
    HapticFeedback.selectionClick();
    debugPrint('🎓 ExamOverlay: opening fullscreen elaboration (overconfident=${q.wasOverconfident})');
    final l10n = FlueraLocalizations.of(context)!;
    final prompt = q.wasOverconfident
        ? l10n.exam_elaboration_promptOverconfident
        : l10n.exam_elaboration_promptStandard(q.questionText, q.correctAnswer);
    final completer = Completer<String?>();
    late OverlayEntry entry;
    void close(String? result) {
      if (!completer.isCompleted) completer.complete(result);
      try {
        entry.remove();
      } catch (_) {/* already removed */}
    }
    try {
      entry = OverlayEntry(builder: (_) => ExamAnswerFullscreen(
            questionText: prompt,
            initialAnswer: _elaborationCtrl.text,
            startsInHandwriting: _isHandwritingMode,
            // Soft guard: only reject the empty string. The original
            // 15-char minimum was a guardrail against gaming ("ok",
            // ".") but on Android the OCR drops characters reliably,
            // so a user who actually wrote "Le leggi di Newton…" gets
            // recognised as "Lore" and is then BLOCKED — punishing the
            // tool's limit, not the student's effort. The Hypercorrection
            // Effect (Butterfield & Metcalfe 2001) benefits even from
            // short elaborations; the prompt copy already encourages
            // detail, and this surface only fires on overconfident-
            // wrong answers where intrinsic motivation is already high.
            minAnswerLength: 1,
            accentColor: q.wasOverconfident ? _red : _cyan,
            submitLabel: l10n.exam_elaboration_save,
            // Distinct suffix from the answer page so the elaboration
            // strokes don't overwrite the answer strokes for the same q.
            persistKey: _strokePersistKeyFor(q, suffix: 'elaboration'),
            onCloudUpload: _cloudUploadIfEnabled,
            onSubmit: (answer) async {
              widget.controller.saveElaboration(answer);
              if (mounted) {
                setState(() => _elaborationCtrl.text = answer);
              }
            },
            onSubmitted: (answer) => close(answer),
            onCancelled: () => close(null),
          ));
      Overlay.of(context).insert(entry);
    } catch (e, st) {
      debugPrint('🎓 ExamOverlay: elaboration insert failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(FlueraLocalizations.of(context)!
              .exam_error_openElaborationFailed(e.toString())),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      }
      return;
    }
    final result = await completer.future;
    if (!mounted) return;
    if (result != null && result.trim().isNotEmpty) {
      setState(() => _elaborationCtrl.text = result);
    }
  }

  Widget _buildOpenInput(ExamQuestion q) {
    final isFormula = q.type == ExamQuestionType.formulaRecall;
    final l10n = FlueraLocalizations.of(context)!;

    // Toggle label
    final modeLabel = _isHandwritingMode ? '✍️ Modalità scrittura' : '⌨️ Modalità tastiera';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── Toggle Bar ──
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(isFormula ? l10n.exam_answer_writeFormulaLabel : l10n.exam_answer_yourAnswerLabel,
               style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isHandwritingMode = !_isHandwritingMode);
              widget.onHandwritingModeChanged?.call(_isHandwritingMode);
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

      // ── Answer area ──
      // Handwriting mode: CTA "✍️ Rispondi" → fullscreen closed-book page.
      //   Source notes are NOT visible during the answer phase. Spatial
      //   memory is delivered by the Fog of War phase BEFORE the exam.
      //   Once confirmed, the recognized text is shown read-only here so
      //   the student can review it before tapping Invia.
      // Keyboard mode: inline TextField (compact card flow).
      if (_isHandwritingMode)
        Semantics(
          button: true,
          label: _answerCtrl.text.trim().isEmpty
              ? FlueraLocalizations.of(context)!.exam_answer_writeByHand
              : FlueraLocalizations.of(context)!.exam_answer_editAnswer,
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openFullscreenAnswer(q),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: BoxDecoration(
              color: _cyan.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _cyan.withValues(alpha: 0.32), width: 1.4),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _cyan.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Text('✍️', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _answerCtrl.text.trim().isEmpty
                          ? l10n.exam_answer_writeByHand
                          : l10n.exam_answer_editAnswer,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _answerCtrl.text.trim().isEmpty
                          ? l10n.exam_answer_writeByHandSubtitle
                          : _truncatedAnswerPreview(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.fullscreen,
                color: _cyan.withValues(alpha: 0.7),
                size: 22,
              ),
            ]),
          ),
          ),
        )
      else
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _cyan.withValues(alpha: 0.22))),
          child: TextField(
            controller: _answerCtrl,
            style: TextStyle(
              color: Colors.white, fontSize: 15,
              fontFamily: isFormula ? 'monospace' : null),
            maxLines: isFormula ? 2 : 4,
            decoration: InputDecoration(
              hintText: isFormula
                  ? l10n.exam_answer_writeFormulaHint
                  : l10n.exam_answer_writeAnswerHint,
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
      // The user can disable the shake via ExamPreferences without losing the
      // cognitive logic in the model (q.wasOverconfident still drives FSRS
      // bumps and analytics).
      if (q.wasOverconfident && widget.hypercorrectionEnabled) ...[
        // Trigger shake + flash on first render.
        // Reduce-motion (P2.1a): when the OS asks for fewer animations
        // (`MediaQuery.disableAnimations`) OR the user opted into the
        // ExamPreferences reduceMotion toggle, we still show the red flash
        // briefly + heavy haptic — the *cognitive* shock matters more than
        // the visual one — but skip the shake so users with vestibular
        // sensitivities don't suffer it.
        Builder(builder: (ctx) {
          // Fire shake only once per reveal
          if (!_shakeController.isAnimating && _shakeController.value == 0) {
            final reduceMotion =
                (MediaQuery.maybeOf(ctx)?.disableAnimations ?? false) ||
                    widget.reduceMotion;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                if (!reduceMotion) {
                  _shakeController.forward(from: 0);
                  HapticFeedback.heavyImpact();
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (mounted) HapticFeedback.selectionClick();
                  });
                } else {
                  // Single haptic, no shake — still signals the moment.
                  HapticFeedback.heavyImpact();
                }
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
                  ? FlueraLocalizations.of(context)!.exam_elaboration_cardOverconfident
                  : FlueraLocalizations.of(context)!.exam_elaboration_cardStandard,
              style: TextStyle(
                color: (q.wasOverconfident ? _red : _cyan).withValues(alpha: 0.7),
                fontSize: 12)),
            const SizedBox(height: 8),
            // Handwriting mode: tap CTA → fullscreen elaboration page (same
            // closed-book pattern as the main answer flow). Keyboard mode:
            // inline TextField (compact card).
            if (_isHandwritingMode)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openFullscreenElaboration(q),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                  decoration: BoxDecoration(
                    color: (q.wasOverconfident ? _red : _cyan).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: (q.wasOverconfident ? _red : _cyan).withValues(alpha: 0.3),
                      width: 1.2,
                    ),
                  ),
                  child: Row(children: [
                    Text(q.wasOverconfident ? '⚡' : '✍️', style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _elaborationCtrl.text.trim().isEmpty
                            ? FlueraLocalizations.of(context)!.exam_elaboration_writeByHand
                            : FlueraLocalizations.of(context)!
                                .exam_elaboration_editElaboration(_elaborationCtrl.text.trim().length),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.fullscreen,
                      color: (q.wasOverconfident ? _red : _cyan).withValues(alpha: 0.7),
                      size: 18,
                    ),
                  ]),
                ),
              )
            else
              TextField(
                controller: _elaborationCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Scrivi qui per memorizzare meglio...',
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
                    widget.controller.saveElaboration(_elaborationCtrl.text.trim());
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
                  child: Text(FlueraLocalizations.of(context)!.save,
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
            Expanded(child: Text(FlueraLocalizations.of(context)!.exam_elaborationSaved,
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

    // 🧠 SELECTIVE ELABORATION GATE — refined 2026-05-07.
    //
    // Pedagogical baseline (Slamecka & Graf 1978, Butterfield & Metcalfe
    // 2001): elaboration consolidates wrong answers and is *3× more*
    // effective on overconfident errors. So we hard-gate the highest-ROI
    // moment — `wasOverconfident == true` — and let the student skip the
    // soft case (ordinary incorrect/skipped) with the CTA still prominent
    // but "Prossima" enabled. Tradeoffs: minor loss of consolidation on
    // garden-variety errors vs. significantly lower abandonment rate
    // (research on Anki shows hard gates >70% on every wrong card cause
    // session quitting).
    //
    // Hard gate fires ONLY when:
    //   • the answer was overconfident-wrong
    //   • elaboration not yet saved
    //   • the user hasn't actively dismissed the prompt this turn (no flag
    //     yet — kept simple for V1).
    final needsElaboration = answered &&
        q.wasOverconfident &&
        q.elaboration == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: Row(children: [
        // Back button — visible from question 2 onwards. Lets the student
        // re-read or re-edit a previous answer. Compact (44dp tap target,
        // ~14% width) so it doesn't overshadow the primary CTA.
        if (widget.controller.canGoPrevious) ...[
          Semantics(
            button: true,
            label: 'Indietro',
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _stopTimer();
                _answerCtrl.clear();
                _elaborationCtrl.clear();
                _shakeController.reset();
                _shockFlashVisible = false;
                setState(() { _revealed = false; _evalText = ''; });
                final ok = widget.controller.previousQuestion();
                // Rehydrate UI state from the now-current question so the
                // student sees what they originally wrote / answered.
                if (ok) {
                  final q = widget.controller.session?.currentQuestion;
                  if (q != null) {
                    if (q.userAnswer != null) _answerCtrl.text = q.userAnswer!;
                    if (q.elaboration != null) _elaborationCtrl.text = q.elaboration!;
                    if (q.isAnswered) {
                      setState(() { _revealed = true; _evalText = q.explanation; });
                    }
                  }
                }
              },
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Icon(Icons.arrow_back_rounded,
                    color: Colors.white.withValues(alpha: 0.6), size: 20),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(child: answered
        ? needsElaboration
          ? _btn(
              label: '✍️ Riscrivi prima di procedere',
              color: Colors.white.withValues(alpha: 0.08),
              onTap: null) // Disabled button
          : _btn(
              label: isLast ? 'Vedi i risultati 🎓' : 'Prossima →',
              color: _cyan,
              // Delegate to the canonical advance method — keeps a SINGLE
              // source of truth for "what gets reset between questions".
              // The previous inline body forgot to clear _hintText,
              // _confidenceLevel, and _selectedChoiceIndex, so the
              // previous question's hint bubble + selected radio button
              // bled into the next question.
              onTap: _advanceAfterReveal)
        : _btn(label: 'Salta →', color: Colors.white.withValues(alpha: 0.14), onTap: () {
            HapticFeedback.selectionClick();
            _stopTimer();
            widget.controller.skipQuestion();
            setState(() { _revealed = true; _evalText = q.explanation; });
          })),
      ]),
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

  /// Optional anti-fatigue mindfulness pause between chunks.
  /// 60s is short enough to not break flow but long enough to let working
  /// memory consolidate (Cowan 2001: WM consolidation needs ~10-20s).
  Timer? _chunkPauseTimer;
  int _chunkPauseRemaining = 0;
  bool _chunkPauseActive = false;
  // Tracks which chunk was the most recently auto-shown break, to dedupe
  // the post-frame auto-dismiss timer set up below.
  int? _chunkBreakShownFor;

  Widget _buildChunkBreak(ExamSession session) {
    final chunk = session.currentChunk - 1; // just completed
    final correct = session.chunkCorrectCount(chunk);
    final total = session.chunkTotalCount(chunk);
    final msg = _growthMessages[chunk % _growthMessages.length];

    // Mounting effect: schedule auto-dismiss exactly once per chunk break,
    // not on every rebuild (the previous impl re-armed the timer on every
    // build → stacked dismissals + lost user-tap-skip → confusing UX).
    if (_chunkBreakShownFor != chunk) {
      _chunkBreakShownFor = chunk;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(seconds: 8), () {
          if (mounted && _showingChunkBreak && _chunkBreakShownFor == chunk &&
              !_chunkPauseActive) {
            _exitChunkBreak();
          }
        });
      });
    }

    // Per-question outcome icons (✓ correct, ◐ partial, ✗ wrong, ○ skipped).
    final chunkStart = chunk * ExamSession.chunkSize;
    final chunkEnd =
        (chunkStart + ExamSession.chunkSize).clamp(0, session.questions.length);
    final chunkQs = session.questions.sublist(chunkStart, chunkEnd);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📦', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 16),
          Text('Blocco ${chunk + 1}/${session.totalChunks} completato',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(FlueraLocalizations.of(context)!.exam_chunkBreakSummary(correct, total),
            style: TextStyle(color: _cyan.withValues(alpha: 0.7), fontSize: 14)),
          const SizedBox(height: 14),
          // Per-question outcome strip — at-a-glance recap of the chunk.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: chunkQs.map((q) {
              final IconData icon;
              final Color color;
              switch (q.result) {
                case ExamAnswerResult.correct:
                  icon = Icons.check_circle_rounded;
                  color = _green;
                  break;
                case ExamAnswerResult.partial:
                  icon = Icons.adjust_rounded;
                  color = _orange;
                  break;
                case ExamAnswerResult.incorrect:
                  icon = Icons.cancel_rounded;
                  color = _red;
                  break;
                case ExamAnswerResult.skipped:
                case null:
                  icon = Icons.radio_button_unchecked_rounded;
                  color = Colors.white.withValues(alpha: 0.25);
                  break;
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(icon, size: 22, color: color),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _green.withValues(alpha: 0.15)),
            ),
            child: Text(FlueraLocalizations.of(context)!.exam_growthPrefix(msg),
              textAlign: TextAlign.center,
              style: TextStyle(color: _green.withValues(alpha: 0.8), fontSize: 13, height: 1.4, fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 22),
          if (_chunkPauseActive) ...[
            // Mindfulness countdown — stops the auto-dismiss + the per-Q timer.
            Text(
              '⏸️  ${_chunkPauseRemaining}s',
              style: TextStyle(
                color: _purple,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Respira. Quando riparti, la memoria è più solida.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _cancelChunkPause,
              child: Text('Riprendi ora', style: TextStyle(color: _cyan)),
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _startChunkPause,
                  icon: Icon(Icons.spa_rounded, size: 16, color: _purple),
                  label: Text(
                    'Pausa 60s',
                    style: TextStyle(color: _purple, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                _btn(
                  label: FlueraLocalizations.of(context)!.exam_continueArrow,
                  color: _cyan,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _exitChunkBreak();
                  },
                ),
              ],
            ),
          ],
        ]),
      ),
    );
  }

  void _exitChunkBreak() {
    _chunkPauseTimer?.cancel();
    _chunkPauseTimer = null;
    if (!mounted) return;
    setState(() {
      _showingChunkBreak = false;
      _chunkPauseActive = false;
      _chunkPauseRemaining = 0;
    });
    _startTimer();
  }

  void _startChunkPause() {
    _chunkPauseTimer?.cancel();
    setState(() {
      _chunkPauseActive = true;
      _chunkPauseRemaining = 60;
    });
    _chunkPauseTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _chunkPauseRemaining--);
      if (_chunkPauseRemaining <= 0) {
        t.cancel();
        _exitChunkBreak();
      }
    });
  }

  void _cancelChunkPause() {
    _chunkPauseTimer?.cancel();
    setState(() {
      _chunkPauseActive = false;
      _chunkPauseRemaining = 0;
    });
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

    final l10n = FlueraLocalizations.of(context)!;
    final String insight;
    final Color barColor;
    if (avgDelta > 0.3) {
      insight = l10n.exam_insightOverconfident;
      barColor = _orange;
    } else if (avgDelta < -0.3) {
      insight = l10n.exam_insightUnderconfident;
      barColor = _cyan;
    } else {
      insight = l10n.exam_insightCalibrated;
      barColor = _green;
    }

    // Bar position: -1 (underconfident) to +1 (overconfident), center = calibrated
    final barPos = avgDelta.clamp(-1.0, 1.0);

    // Per-level breakdown: how many at each confidence level, and how many correct.
    // This is the actual calibration data (dial is just the headline).
    final byLevel = <int, _ConfidenceBucket>{};
    for (int lvl = 1; lvl <= 5; lvl++) {
      byLevel[lvl] = _ConfidenceBucket();
    }
    for (final q in answered) {
      final b = byLevel[q.confidenceLevel!]!;
      b.total++;
      if (q.isCorrect) b.correct++;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: barColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: barColor.withValues(alpha: 0.20)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.exam_calibrationTitle, style: TextStyle(
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
            Positioned(top: 0, left: 0, child: Text(l10n.exam_calibrationUnder,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 8))),
            Positioned(top: 0, right: 0, child: Text(l10n.exam_calibrationOver,
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
        const SizedBox(height: 10),
        // Per-confidence-level breakdown — the actionable calibration data
        // ("at conf=5 you were right X/Y times").
        ...List.generate(5, (i) {
          final lvl = 5 - i; // descending so high confidence is first
          final b = byLevel[lvl]!;
          if (b.total == 0) return const SizedBox.shrink();
          final pct = b.correct / b.total;
          // Highlight overconfident wrongs (≥4 conf, low accuracy) — that's
          // exactly where the Hypercorrection Effect fires.
          final isOverconfRow = lvl >= 4 && pct < 0.5;
          final rowColor = isOverconfRow
              ? _orange
              : (pct >= 0.7 ? _green : (pct >= 0.4 ? _cyan : _red));
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(
                width: 70,
                child: Text(
                  '${_confidenceLabels[lvl] ?? "—"} ($lvl)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    valueColor: AlwaysStoppedAnimation(rowColor.withValues(alpha: 0.85)),
                  ),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  ' ${b.correct}/${b.total}',
                  style: TextStyle(
                    color: rowColor.withValues(alpha: 0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ]),
          );
        }),
        const SizedBox(height: 8),
        Text(insight, style: TextStyle(color: barColor.withValues(alpha: 0.8), fontSize: 11, height: 1.3)),
      ]),
    );
  }

  // ─── RESULTS ────────────────────────────────────────────────────────────

  Widget _buildResults(ExamSession session) {
    final score = (session.score * 100).round();
    // Build the "to review" list using the topic titles the user saw in the
    // picker, NOT the raw OCR sourceText (which is fragmented junk like
    // "LEGGID 1 NEWTON PRIMALELE CORPO A RIPOSO O t.RU SE NESSUNA FORZA").
    // Falls back to a sanitized excerpt if no topic title is available
    // (e.g. exams launched from Fog of War with raw cluster IDs).
    final review = <String>{};
    for (final q in session.questions) {
      if (q.result != ExamAnswerResult.incorrect &&
          q.result != ExamAnswerResult.skipped) continue;
      final title = widget.availableClusters[q.sourceClusterId];
      if (title != null && title.trim().isNotEmpty) {
        review.add(title.trim());
      } else {
        final sanitized = _sanitizeReviewLabel(q.sourceText);
        if (sanitized.isNotEmpty) review.add(sanitized);
      }
    }
    final reviewList = review.toList();
    final mins = session.durationSeconds ~/ 60;
    final secs = session.durationSeconds % 60;
    final l10n = FlueraLocalizations.of(context)!;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildHeader(l10n.exam_resultsTitle, showClose: false),
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
          Text(l10n.exam_resultsSummary(session.questions.length, session.correctCount),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
          const SizedBox(height: 4),
          Text(l10n.exam_resultsDuration(mins, secs.toString().padLeft(2, '0')),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
          const SizedBox(height: 20),

          // 📊 METACOGNITIVE CALIBRATION CARD
          _buildCalibrationCard(session),
          const SizedBox(height: 20),

          // 📦 PER-CHUNK BREAKDOWN
          if (session.totalChunks > 1) ...[
            Align(alignment: Alignment.centerLeft,
              child: Text(l10n.exam_chunkPerformance, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12))),
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
          if (reviewList.isNotEmpty) ...[
            const SizedBox(height: 20),
            Align(alignment: Alignment.centerLeft,
              child: Text(l10n.exam_reviewNeeded, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8,
              children: reviewList.take(6).map((t) => Container(
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
            _btn(label: l10n.exam_errorReplay(widget.controller.incorrectQuestions.length), color: _orange, onTap: () {
              HapticFeedback.mediumImpact();
              setState(() { _scopeSelected = true; _revealed = false; _evalText = ''; _confidenceLevel = 0; });
              widget.controller.startErrorReplay();
            }),
            const SizedBox(height: 8),
          ],
          // Share / export session as plain text. Copies a structured report
          // to the clipboard (pdf package isn't a dependency, but Clipboard
          // is universally available; the user pastes into mail/notes/etc).
          GestureDetector(
            onTap: () => _exportSessionReport(session),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.copy_rounded, color: Colors.white.withValues(alpha: 0.65), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Esporta riepilogo (copia)',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          _btn(label: l10n.exam_backToCanvas, color: _cyan, onTap: () {
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
          ? Center(child: Text(FlueraLocalizations.of(context)!.exam_historyEmpty,
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


  // ─── SHARED ─────────────────────────────────────────────────────────────

  Widget _buildHeader(String title, {required bool showClose}) {
    final l10n = FlueraLocalizations.of(context)!;
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
            child: Icon(Icons.school_rounded, size: 11, color: _cyan.withValues(alpha: 0.85)),
          )),
        const SizedBox(width: 9),
        Text(l10n.exam_headerLabel, style: TextStyle(color: _cyan.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
        const SizedBox(width: 6),
        Text('·', style: TextStyle(color: Colors.white.withValues(alpha: 0.18))),
        const SizedBox(width: 6),
        Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
        if (showClose)
          Semantics(
            button: true,
            label: 'Chiudi esame',
            child: GestureDetector(onTap: _confirmClose,
              child: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.35), size: 19)),
          ),
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
      const SizedBox(height: 14),
      Builder(
        builder: (_) {
          final v = _loadingProgress;
          final pct = (v * 100).round();
          final l10n = FlueraLocalizations.of(context)!;
          // Thresholds tuned for asymptotic curve τ=18s. Each band lasts
          // longer than the previous (the curve slows down) so phase labels
          // stay visible for the right amount of time even on slow Gemini
          // calls (40-60s+ are common when Bloom retry fires).
          //   < 25%  → ~ first 5s  → "Leggo gli appunti…"
          //   < 55%  → ~ 5-15s     → "Analizzo i concetti chiave…"
          //   < 85%  → ~ 15-35s    → "Genero le domande…"
          //   < 99%  → ~ 35-80s    → "Verifico la qualità pedagogica…"
          //   ≥ 99%  → snap to 100 → "Pronto!"
          final phase = v < 0.25
              ? l10n.exam_loading_phaseRead
              : v < 0.55
                  ? l10n.exam_loading_phaseAnalyze
                  : v < 0.85
                      ? l10n.exam_loading_phaseGenerate
                      : v < 0.99
                          ? l10n.exam_loading_phaseValidate
                          : l10n.exam_loading_phaseReady;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  valueColor: AlwaysStoppedAnimation<Color>(_cyan.withValues(alpha: 0.85)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$pct%',
              style: TextStyle(
                color: _cyan.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              phase,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ]);
        },
      ),
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
        _btn(label: FlueraLocalizations.of(context)!.close, color: Colors.white.withValues(alpha: 0.14), onTap: widget.onClose),
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
    if (session == null || session.isComplete || session.answeredCount == 0) {
      widget.onClose();
      return;
    }
    final l10n = FlueraLocalizations.of(context)!;
    // showDialog pushes onto the MaterialApp's Navigator which is BELOW
    // the OverlayEntry hosting ExamOverlay (z-order). Result: tap "X" →
    // dialog mounts but is hidden under the overlay → user sees no
    // reaction. Same root cause as the fullscreen answer page bug.
    // Mount the confirm modal as a sibling OverlayEntry so it renders ON
    // TOP of ExamOverlay.
    late OverlayEntry entry;
    void close(bool confirmed) {
      try {
        entry.remove();
      } catch (_) {/* already removed */}
      if (confirmed) widget.onClose();
    }
    entry = OverlayEntry(builder: (_) => Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.exam_exitTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text(l10n.exam_exitBody(session.answeredCount),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: () => close(false),
                  child: Text(l10n.exam_exitContinue,
                      style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => close(true),
                  child: Text(l10n.exam_exitConfirm,
                      style: const TextStyle(color: Color(0xFFFF5252), fontWeight: FontWeight.w600)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    ));
    Overlay.of(context).insert(entry);
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

/// Per-confidence-level tally used by the calibration chart.
/// Mutable on purpose — it's only ever built locally inside _buildCalibrationCard.
class _ConfidenceBucket {
  int total = 0;
  int correct = 0;
}
