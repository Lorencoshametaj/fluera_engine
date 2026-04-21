import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/generated/fluera_localizations.g.dart';
import '../widgets/latex_preview_card.dart';

/// 🔮 ATLAS RESPONSE CARD — Iron Man HUD holographic floating card.
///
/// FINAL POLISH: retry, slide-out dismiss, RepaintBoundary, adaptive contrast,
/// timeout progress, cached sections, separated AnimatedBuilders.
class AtlasResponseCard extends StatefulWidget {
  final String cardId;
  final Offset position;
  final String responseText;

  final int stackIndex;
  final int totalCards;
  final List<String> conversationHistory;

  final VoidCallback? onDismiss;
  final VoidCallback? onDismissAll;
  final ValueChanged<List<String>>? onGoDeeper;
  final ValueChanged<String>? onFollowUp;
  final ValueChanged<String>? onSaveAsNote;
  final ValueChanged<String>? onSearchWeb;

  /// (1) Called when user taps "Retry" after a failed response.
  final VoidCallback? onRetry;

  /// 🎨 Custom accent color from brush selection (null = default cyan).
  final Color? accentColor;

  /// ⭐ Called when user bookmarks a response.
  final ValueChanged<String>? onBookmark;

  /// Called when user taps "Extract formula" — passes ALL LaTeX sources.
  final ValueChanged<List<String>>? onExtractLatex;

  // ─── Proactive analysis additions ───────────────────────────────────────

  /// 💡 Gap concepts from proactive analysis.
  final List<String>? gapChips;

  /// 💡 Called when user taps a gap chip.
  final ValueChanged<String>? onGapChipTap;

  /// 🌟 Show self-rating row (proactive cards only).
  final bool showSelfRating;

  /// 🌟 Called with rating: -1=non lo so, 0=ho dubbi, 1=lo so già.
  final ValueChanged<int>? onSelfRate;

  /// 🎓 Already-mastered concepts (hidden from chips).
  final Set<String> masteredConcepts;

  /// 📊 Session summary chip callback.
  final VoidCallback? onSessionSummary;

  // ─── Active Recall (R&K 2006) ────────────────────────────────────────────

  /// ✏️ Verify mode: concept to recall (null = show picker).
  final String? verifyQuestion;

  /// ✏️ Un-mastered concepts to pick from in verify picker.
  final List<String>? verifyCandidates;

  /// ✏️ Called with (concept, answer, mode) to trigger Atlas evaluation.
  final Future<void> Function(String concept, String answer, String mode)? onVerifySubmit;

  /// ✏️ Called when user taps Riprova — parent clears card text.
  final VoidCallback? onVerifyReset;

  /// ✏️ Verifica chip tap — opens verify picker card.
  final VoidCallback? onVerify;

  /// 💬 Cornell chip tap — generates a Cornell question for the first gap concept.
  final ValueChanged<String>? onCornell;

  /// ❓ Pre-lettura chip tap — generates Carpenter (2011) priming questions.
  final VoidCallback? onPreLettura;

  /// 🗺️ Vai al cluster chip tap — animates canvas to the source cluster.
  final VoidCallback? onNavigateCluster;

  /// 🙈 Cluster Hide chip tap — hides cluster for retrieval practice.
  final VoidCallback? onClusterHide;

  /// 🧑‍🏫 Feynman chip tap — opens Feynman explanation mode.
  final ValueChanged<String>? onFeynman;

  /// 🧠 Initial verify mode from adaptive selection ('spiega' or 'esempio').
  final String verifyInitialMode;

  /// 🧪 STEM exercise chip tap — generates a practice problem from cluster content.
  final VoidCallback? onStemExercise;

  /// 📊 Dashboard chip tap — shows study statistics.
  final VoidCallback? onDashboard;

  /// 🔀 Interleave chip tap — opens cross-cluster interleaved verify.
  final VoidCallback? onInterleave;

  /// 📋 Export chip tap — exports study data as JSON.
  final VoidCallback? onExport;

  const AtlasResponseCard({
    super.key,
    required this.cardId,
    required this.position,
    required this.responseText,
    this.stackIndex = 0,
    this.totalCards = 1,
    this.conversationHistory = const [],
    this.onDismiss,
    this.onDismissAll,
    this.onGoDeeper,
    this.onFollowUp,
    this.onSaveAsNote,
    this.onSearchWeb,
    this.onRetry,
    this.onExtractLatex,
    this.accentColor,
    this.onBookmark,
    this.gapChips,
    this.onGapChipTap,
    this.showSelfRating = false,
    this.onSelfRate,
    this.masteredConcepts = const {},
    this.onSessionSummary,
    this.verifyQuestion,
    this.verifyCandidates,
    this.onVerifySubmit,
    this.onVerifyReset,
    this.onVerify,
    this.onCornell,
    this.onPreLettura,
    this.onNavigateCluster,
    this.onClusterHide,
    this.onFeynman,
    this.verifyInitialMode = 'spiega',
    this.onStemExercise,
    this.onDashboard,
    this.onInterleave,
    this.onExport,
  });

  @override
  State<AtlasResponseCard> createState() => _AtlasResponseCardState();
}

class _AtlasResponseCardState extends State<AtlasResponseCard>
    with TickerProviderStateMixin {
  // Animation controllers
  late final AnimationController _enterController;
  late final AnimationController _glowController;
  late final AnimationController _scanLineController;
  late final AnimationController _beamController;
  late final AnimationController _glowTextController;

  // (4) Tony Stark fling dismiss — velocity-based trajectory + rotation
  late final AnimationController _slideOutController;
  Offset _flingVelocity = Offset.zero; // full fling vector for trajectory

  bool _dismissing = false;
  bool _copied = false;
  bool _isBookmarked = false;

  // Streaming
  String _displayedText = '';
  bool _streamingDone = false;
  int _lastSectionCount = 0;

  // Typewriter
  int _revealedLength = 0;
  Timer? _typewriterTimer;
  bool _typewriterDone = true;

  // Auto-scroll
  final ScrollController _scrollController = ScrollController();

  // States
  bool _isPinned = false;
  bool _isMinimized = false;
  final Set<String> _collapsedSections = {};
  int _historyIndex = -1;

  // Auto-dismiss
  Timer? _autoDismissTimer;
  bool _userInteracting = false;

  // Drag & snap
  Offset _dragOffset = Offset.zero;
  bool _isSnapped = false;
  _SnapEdge _snapEdge = _SnapEdge.none;

  // Auto-width
  double _cardWidth = 320.0;
  static const _minWidth = 220.0;
  static const _maxWidth = 460.0;

  // Cached values (OPT #3 & #4)
  List<_ParsedSection>? _cachedSections;
  String? _cachedSectionsSource;
  List<String>? _cachedChips;
  String? _cachedChipsSource;

  bool _swipeHintShown = false;

  // (8) Timeout progress
  Timer? _timeoutTimer;
  int _waitSeconds = 0;

  // (1) Error detection
  bool get _isErrorResponse =>
      (widget.verifyCandidates == null || widget.verifyCandidates!.isEmpty) && // Verify eval responses use ⚠️/❌ legitimately
      (_displayedText.startsWith('⚠️') ||
      _displayedText.startsWith('❌') ||
      _displayedText.startsWith('🌐') ||
      _displayedText.startsWith('🤖') ||
      _displayedText.startsWith('⏱️'));

  /// Extract all LaTeX formulas from text ($...$ or $$...$$).
  static final _latexPattern = RegExp(r'\$\$(.+?)\$\$|\$(.+?)\$');

  List<String> get _extractedLatex {
    final text = _activeText;
    final matches = _latexPattern.allMatches(text);
    return matches.map((m) => m.group(1) ?? m.group(2) ?? '').where((s) => s.isNotEmpty).toList();
  }

  bool get _hasLatex => _latexPattern.hasMatch(_activeText);

  // (7) Adaptive colors — detect if canvas is light
  Color get _cyan {
    final c = widget.accentColor;
    if (c == null) return const Color(0xFF00E5FF);
    // Luminance guard: too-dark accents are invisible on dark card
    return c.computeLuminance() < 0.25 ? const Color(0xFF00E5FF) : c;
  }
  Color get _green => const Color(0xFF69F0AE);
  Color _getCardBg(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.light
        ? const Color(0xEE1A1A2E) // darker for light canvases
        : const Color(0xDD0A0A1A);
  }

  @override
  void initState() {
    super.initState();

    _enterController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600),
    )..forward();

    _glowController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _scanLineController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500),
    )..repeat();

    _beamController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800),
    )..forward();

    _glowTextController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200),
    );

    // (4) Slide-out controller
    _slideOutController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300),
    );

    _displayedText = widget.responseText;
    _revealedLength = _displayedText.length; // no typewriter on initial text
    _typewriterDone = _displayedText.isNotEmpty;
    _autoSizeWidth();
    _playJarvisHaptic();

    // (8) Start timeout counter
    if (_displayedText.isEmpty) _startTimeoutCounter();
  }

  void _playJarvisHaptic() async {
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    HapticFeedback.heavyImpact();
  }

  // (8) Timeout progress counter
  void _startTimeoutCounter() {
    _waitSeconds = 0;
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted && _displayedText.isEmpty) {
        setState(() => _waitSeconds = t.tick);
      } else {
        t.cancel();
      }
    });
  }

  @override
  void didUpdateWidget(AtlasResponseCard old) {
    super.didUpdateWidget(old);
    if (widget.responseText != old.responseText) {
      final wasEmpty = old.responseText.isEmpty;
      _displayedText = widget.responseText;
      _historyIndex = -1;

      _cachedSections = null;
      _cachedSectionsSource = null;
      _cachedChips = null;
      _cachedChipsSource = null;

      final newSectionCount = _countSections(_displayedText);
      if (newSectionCount > _lastSectionCount && _lastSectionCount > 0) {
        HapticFeedback.lightImpact();
      }
      _lastSectionCount = newSectionCount;
      _streamingDone = false;
      _restartStreamingCheck();
      _autoSizeWidth();

      // Typewriter: reveal new chars incrementally
      if (_displayedText.length > _revealedLength) {
        _startTypewriter();
      } else {
        _revealedLength = _displayedText.length;
      }

      if (wasEmpty && _displayedText.isNotEmpty) {
        _scanLineController.duration = const Duration(milliseconds: 1500);
        _glowTextController.forward(from: 0);
        _timeoutTimer?.cancel(); // (8) Stop counter
      }

      _autoScrollToBottom();
    }
  }

  void _autoScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && !_userInteracting && _historyIndex < 0) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _autoSizeWidth() {
    final len = _displayedText.length;
    _cardWidth = len < 100 ? _minWidth : len < 300 ? 280 : len < 600 ? 340 : _maxWidth;
  }

  Timer? _streamCheckTimer;

  void _restartStreamingCheck() {
    _streamCheckTimer?.cancel();
    _streamCheckTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && !_streamingDone) {
        setState(() => _streamingDone = true);
        _scanLineController.stop();
        _scheduleAutoDismiss();
        if (widget.conversationHistory.isNotEmpty && !_swipeHintShown) {
          _swipeHintShown = true;
          setState(() {});
        }
      }
    });
  }

  int _countSections(String text) => RegExp(r'▸\s*(SCAN|CONN|NOTE)\s*:').allMatches(text).length;

  // ─── Typewriter ─────────────────────────────────────────────────────

  void _startTypewriter() {
    _typewriterDone = false;
    _typewriterTimer?.cancel();
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 12), (t) {
      if (!mounted) { t.cancel(); return; }
      // Accelerate: start at 2 chars, ramp to 6
      final speed = (_revealedLength / 200).clamp(0.0, 1.0);
      final step = (2 + speed * 4).round();
      _revealedLength = (_revealedLength + step).clamp(0, _displayedText.length);
      setState(() {});
      if (_revealedLength >= _displayedText.length) {
        t.cancel();
        _typewriterDone = true;
      }
    });
  }

  void _skipTypewriter() {
    _typewriterTimer?.cancel();
    if (_revealedLength < _displayedText.length) {
      setState(() {
        _revealedLength = _displayedText.length;
        _typewriterDone = true;
      });
    }
  }

  /// The text to display — respects typewriter reveal and history.
  String get _visibleText {
    final text = _activeText;
    if (_historyIndex >= 0) return text; // history = show full
    if (_revealedLength >= text.length) return text;
    return text.substring(0, _revealedLength);
  }

  void _scheduleAutoDismiss() {
    _autoDismissTimer?.cancel();
    if (_userInteracting || _isPinned) return;
    final ms = (5000 + widget.responseText.length * 40).clamp(8000, 25000);
    _autoDismissTimer = Timer(Duration(milliseconds: ms), _dismiss);
  }

  void _onUserInteractionStart() { _userInteracting = true; _autoDismissTimer?.cancel(); }
  void _onUserInteractionEnd() {
    _userInteracting = false;
    if (_streamingDone && !_isPinned) {
      _autoDismissTimer?.cancel();
      _autoDismissTimer = Timer(const Duration(seconds: 4), _dismiss);
    }
  }

  void _togglePin() {
    HapticFeedback.selectionClick();
    setState(() {
      _isPinned = !_isPinned;
      if (_isPinned) _autoDismissTimer?.cancel();
      else if (_streamingDone) _scheduleAutoDismiss();
    });
  }

  void _toggleMinimize() { HapticFeedback.selectionClick(); setState(() => _isMinimized = !_isMinimized); }

  // (4) Tony Stark fling dismiss — card flies away in fling direction
  void _dismiss({Offset? velocity}) {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    _autoDismissTimer?.cancel();
    _streamCheckTimer?.cancel();
    _timeoutTimer?.cancel();
    _flingVelocity = velocity ?? const Offset(0, -800); // default: fling up like Stark
    HapticFeedback.heavyImpact();
    _slideOutController.forward().then((_) => widget.onDismiss?.call());
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _activeText));
    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 1), () { if (mounted) setState(() => _copied = false); });
    }
  }

  String get _activeText {
    if (_historyIndex >= 0 && _historyIndex < widget.conversationHistory.length) {
      return widget.conversationHistory[_historyIndex];
    }
    return _displayedText;
  }

  bool get _canSwipeBack => widget.conversationHistory.isNotEmpty && (_historyIndex < 0 || _historyIndex > 0);
  bool get _canSwipeForward => _historyIndex >= 0 && _historyIndex < widget.conversationHistory.length;

  // ─── Cached chip labels ───────────────────────────────────────────────

  static const _chipLabels = <String, Map<String, List<String>>>{
    'math': { 'it': ['Risolvi passo passo', 'Mostra dimostrazione', 'Dai esempi'], 'en': ['Solve step by step', 'Show proof', 'Give examples'] },
    'code': { 'it': ['Ottimizza', 'Spiega complessità', 'Mostra alternative'], 'en': ['Optimize this', 'Explain complexity', 'Show alternatives'] },
    'default': { 'it': ['Spiega di più', 'Dai esempi', 'Semplifica'], 'en': ['Explain further', 'Give examples', 'Simplify'] },
  };

  List<String> _getFollowUpSuggestions() {
    final text = _activeText;
    if (text.length < 30 || _isErrorResponse) return const [];
    if (_cachedChipsSource == text && _cachedChips != null) return _cachedChips!;
    _cachedChipsSource = text;

    final lang = ui.PlatformDispatcher.instance.locale.languageCode;
    final hasMath = text.contains('formula') || text.contains('equazione');
    final hasCode = text.contains('function') || text.contains('funzione');
    final cat = hasMath ? 'math' : hasCode ? 'code' : 'default';
    final labels = _chipLabels[cat]?[lang] ?? _chipLabels[cat]?['en'] ?? _chipLabels['default']!['en']!;

    final m = RegExp(r'▸\s*SCAN\s*:\s*(.+?)(?=▸|$)', dotAll: true).firstMatch(text);
    if (m != null) {
      final d = RegExp(r'—\s*(\w+(?:\s+\w+){0,2})').firstMatch(m.group(1)!.trim());
      if (d != null) {
        final deeper = lang == 'it' ? 'Di più su ${d.group(1)}' : 'More on ${d.group(1)}';
        _cachedChips = [deeper, ...labels.take(2)];
        return _cachedChips!;
      }
    }
    _cachedChips = labels.take(3).toList();
    return _cachedChips!;
  }

  // ─── ✏️ Verify state ────────────────────────────────────────────────────
  int? _selectedRating;
  String? _expandedCategory = '📝'; // Only Studia open by default
  final Set<String> _verifiedInSession = {}; // Track tested concepts for progress
  bool _showAllGapChips = false;
  final Set<String> _usedGapChips = {};

  final TextEditingController _verifyController = TextEditingController();
  bool _verifySubmitting = false;
  bool _verifyDone = false;
  String? _selectedConcept;
  late String _verifyMode = widget.verifyInitialMode;
  String _verifyResult = '';

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _streamCheckTimer?.cancel();
    _timeoutTimer?.cancel();
    _typewriterTimer?.cancel();
    _scrollController.dispose();
    _enterController.dispose();
    _glowController.dispose();
    _scanLineController.dispose();
    _beamController.dispose();
    _glowTextController.dispose();
    _slideOutController.dispose();
    _verifyController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const cardPadding = 20.0;
    final maxCardHeight = _isMinimized ? 50.0 : screenSize.height * 0.45;
    const bottomNavReserve = 60.0;
    final cardBg = _getCardBg(context); // (7) adaptive

    final stackOff = widget.stackIndex * 30.0;
    double cardX, cardY;
    if (_isSnapped) {
      cardX = _snapEdge == _SnapEdge.left ? cardPadding : screenSize.width - _cardWidth - cardPadding;
      cardY = widget.position.dy + 20 + _dragOffset.dy + stackOff;
    } else {
      cardX = widget.position.dx - _cardWidth / 2 + _dragOffset.dx + stackOff;
      cardY = widget.position.dy + 20 + _dragOffset.dy + stackOff;
    }
    final maxX = (screenSize.width - _cardWidth - cardPadding).clamp(cardPadding, double.infinity);
    cardX = cardX.clamp(cardPadding, maxX);
    final maxY = (screenSize.height - maxCardHeight - bottomNavReserve).clamp(cardPadding, double.infinity);
    if (cardY > maxY) cardY = widget.position.dy - maxCardHeight - 20 + _dragOffset.dy;
    cardY = cardY.clamp(cardPadding, maxY);

    // (4) Slide-out + enter combined
    return AnimatedBuilder(
      animation: Listenable.merge([_enterController, _slideOutController]),
      builder: (context, _) {
        final enter = Curves.easeOutBack.transform(_enterController.value);
        final slideOut = Curves.easeIn.transform(_slideOutController.value);
        final opacity = (_enterController.value * (1.0 - slideOut)).clamp(0.0, 1.0);

        // (4) Tony Stark fling — trajectory follows velocity, card rotates
        final flingDist = _flingVelocity.distance.clamp(0, 2000) / 2000;
        final maxTravel = 200 + flingDist * 400; // 200-600px travel
        final normalizedVel = _flingVelocity == Offset.zero
            ? const Offset(0, -1)
            : _flingVelocity / _flingVelocity.distance;
        final flingOffsetX = normalizedVel.dx * maxTravel * slideOut;
        final flingOffsetY = normalizedVel.dy * maxTravel * slideOut;
        // Rotation based on horizontal velocity — like a thrown card
        final flingRotation = (normalizedVel.dx * 0.3) * slideOut;

        return Positioned(
          left: cardX + flingOffsetX, top: cardY + flingOffsetY,
          child: GestureDetector(
            onDoubleTap: () {
              HapticFeedback.mediumImpact();
              setState(() {
                if (_isSnapped) { _isSnapped = false; _snapEdge = _SnapEdge.none; }
                else {
                  _isSnapped = true;
                  _snapEdge = (widget.position.dx + _dragOffset.dx) < screenSize.width / 2
                      ? _SnapEdge.left : _SnapEdge.right;
                  _dragOffset = Offset.zero;
                }
              });
            },
            onPanUpdate: (d) {
              _onUserInteractionStart();
              setState(() { _dragOffset += d.delta; _isSnapped = false; });
            },
            onPanEnd: (d) {
              _onUserInteractionEnd();
              final vel = d.velocity.pixelsPerSecond;
              if (vel.dx.abs() > 300 && vel.dx.abs() > vel.dy.abs()) {
                if (vel.dx > 0 && _canSwipeBack) {
                  HapticFeedback.selectionClick();
                  setState(() { _historyIndex = _historyIndex < 0 ? widget.conversationHistory.length - 1 : _historyIndex - 1; });
                } else if (vel.dx < 0 && _canSwipeForward) {
                  HapticFeedback.selectionClick();
                  setState(() { _historyIndex = _historyIndex + 1 >= widget.conversationHistory.length ? -1 : _historyIndex + 1; });
                }
              }
              // (4) Tony Stark fling dismiss — flies in swipe direction
              if (vel.dy.abs() > 300 && vel.dy.abs() > vel.dx.abs()) {
                _dismiss(velocity: vel);
              }
            },
            onLongPress: _copyToClipboard,
            child: Opacity(
              opacity: opacity,
              child: Transform.rotate(
                angle: flingRotation,
                child: Transform.scale(
                  scale: (0.8 + enter * 0.2) * (1.0 - slideOut * 0.7),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: _cardWidth,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Card body with glow scope
                        AnimatedBuilder(
                          animation: _glowController,
                          builder: (context, _) => _buildCardBody(
                            0.6 + _glowController.value * 0.4, maxCardHeight, cardBg,
                          ),
                        ),

                        // HUD corners — spread directly into outer Stack (avoid inner Stack with only Positioned children)
                        ...(() {
                          final gp = 0.6 + _glowController.value * 0.4;
                          return _buildHudCorners(gp);
                        })(),

                        if (widget.totalCards > 1 && widget.stackIndex == 0)
                          _buildCardCounterBadge(),

                        if (_isSnapped)
                          Positioned(
                            top: 0, bottom: 0,
                            left: _snapEdge == _SnapEdge.left ? -4 : null,
                            right: _snapEdge == _SnapEdge.right ? -4 : null,
                            child: Container(width: 2, decoration: BoxDecoration(
                              color: _cyan.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(1),
                              boxShadow: [BoxShadow(color: _cyan.withValues(alpha: 0.3), blurRadius: 4)],
                            )),
                          ),

                        if (!_isMinimized)
                          Positioned(right: 0, bottom: 0, child: GestureDetector(
                            onPanUpdate: (d) { _onUserInteractionStart(); setState(() => _cardWidth = (_cardWidth + d.delta.dx).clamp(_minWidth, _maxWidth)); },
                            onPanEnd: (_) => _onUserInteractionEnd(),
                            child: Container(width: 20, height: 20, alignment: Alignment.bottomRight,
                              child: Icon(Icons.drag_handle, size: 12, color: _cyan.withValues(alpha: 0.3))),
                          )),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Card body ────────────────────────────────────────────────────────

  Widget _buildCardBody(double glowPulse, double maxCardHeight, Color cardBg) {
    final ac = _isPinned ? _green : _cyan;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          clipBehavior: Clip.hardEdge,
          constraints: BoxConstraints(maxHeight: maxCardHeight),
          decoration: BoxDecoration(
            color: cardBg, // (7) adaptive
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ac.withValues(alpha: 0.4 * glowPulse), width: 1.5),
            boxShadow: [BoxShadow(color: ac.withValues(alpha: 0.15 * glowPulse), blurRadius: 30, spreadRadius: 5)],
          ),
          child: Stack(children: [
            // (5) RepaintBoundary around beam painter
            if (!_isMinimized)
              AnimatedBuilder(
                animation: _beamController,
                builder: (context, _) {
                  if (_beamController.value >= 1.0) return const SizedBox.shrink();
                  return Positioned.fill(child: IgnorePointer(child: RepaintBoundary(
                    child: CustomPaint(painter: _BeamInPainter(progress: _beamController.value, color: _cyan)),
                  )));
                },
              ),

            Column(mainAxisSize: MainAxisSize.min, children: [
              _buildHeader(glowPulse),

              if (!_isMinimized) ...[
                if (widget.conversationHistory.isNotEmpty) _buildHistoryIndicator(),
                if (_swipeHintShown && widget.conversationHistory.isNotEmpty) _buildSwipeHint(),

                // (8) Typing + timeout progress
                if (_displayedText.isEmpty && _historyIndex < 0)
                  AnimatedBuilder(
                    animation: _scanLineController,
                    builder: (context, _) => _buildTypingIndicator(_scanLineController.value),
                  ),

                Flexible(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is ScrollStartNotification) _onUserInteractionStart();
                      else if (n is ScrollEndNotification) _onUserInteractionEnd();
                      return false;
                    },
                    child: ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.white, Colors.white, Colors.white, Colors.transparent],
                        stops: [0.0, 0.85, 0.95, 1.0],
                      ).createShader(b),
                      blendMode: BlendMode.dstIn,
                      child: GestureDetector(
                        onTap: _skipTypewriter,
                        behavior: HitTestBehavior.opaque,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          physics: const BouncingScrollPhysics(),
                          child: _buildStructuredText(_visibleText),
                        ),
                      ),
                    ),
                  ),
                ),

                // (1) Retry button for error responses
                if (_streamingDone && _isErrorResponse && widget.onRetry != null)
                  Flexible(fit: FlexFit.loose, child: _buildRetryButton()),

                // ✏️ Verify mode — replaces rating + gap chips
                if (widget.verifyQuestion != null || widget.verifyCandidates != null)
                  Flexible(fit: FlexFit.loose, child: _buildVerifyInput()),

                // 💡 Gap chips — shown in proactive mode, hidden in verify mode
                if (widget.gapChips != null && widget.gapChips!.isNotEmpty &&
                    widget.verifyQuestion == null && widget.verifyCandidates == null)
                  Flexible(fit: FlexFit.loose, child: _buildGapChips()),

                if (_streamingDone && _activeText.isNotEmpty && !_isErrorResponse && _historyIndex < 0
                    && !widget.showSelfRating)
                  Flexible(fit: FlexFit.loose, child: _buildFollowUpChips()),

                if (_streamingDone && _activeText.isNotEmpty)
                  _buildActionBar(glowPulse),
              ],
            ]),

            // (5) RepaintBoundary around scan-line painter
            if (!_streamingDone && _displayedText.isNotEmpty && !_isMinimized)
              AnimatedBuilder(
                animation: _scanLineController,
                builder: (context, _) => Positioned.fill(child: IgnorePointer(child: RepaintBoundary(
                  child: CustomPaint(painter: _ScanLinePainter(progress: _scanLineController.value, color: _cyan)),
                ))),
              ),
          ]),
        ),
      ),
    );
  }

  // ─── (1) Retry button ─────────────────────────────────────────────────

  Widget _buildRetryButton() {
    final lang = ui.PlatformDispatcher.instance.locale.languageCode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onRetry?.call();
          _dismiss();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B6B).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.3), width: 0.5),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.refresh_rounded, size: 14, color: const Color(0xFFFF6B6B).withValues(alpha: 0.8)),
            const SizedBox(width: 6),
            Text(lang == 'it' ? 'Riprova' : 'Retry', style: TextStyle(
              fontSize: 11, color: const Color(0xFFFF6B6B).withValues(alpha: 0.9), fontWeight: FontWeight.w600,
            )),
          ]),
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────

  Widget _buildHeader(double glowPulse) {
    final ac = _isPinned ? _green : _cyan;
    return GestureDetector(
      onTap: _toggleMinimize,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 0),
        child: Column(children: [
          Row(children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ac.withValues(alpha: 0.15),
                border: Border.all(color: ac.withValues(alpha: 0.5), width: 1),
                boxShadow: [BoxShadow(color: ac.withValues(alpha: 0.3 * glowPulse), blurRadius: 8)],
              ),
              child: Icon(Icons.auto_awesome_rounded, size: 10, color: ac.withValues(alpha: 0.85)),
            ),
            const SizedBox(width: 6),
            Text('Risposta', style: TextStyle(
              color: ac.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2,
            )),
            const SizedBox(width: 4),
            Icon(_isMinimized ? Icons.expand_more : Icons.expand_less, size: 12, color: ac.withValues(alpha: 0.4)),
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _historyIndex >= 0 ? 'L${_historyIndex + 1}/${widget.conversationHistory.length}'
                      : (_streamingDone ? '✓' : '…'),
                  key: ValueKey('$_streamingDone$_historyIndex'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _streamingDone ? _green.withValues(alpha: 0.7) : _cyan.withValues(alpha: 0.4),
                    fontSize: 9, fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            _headerBtn(_isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              _isPinned ? _green : Colors.white.withValues(alpha: 0.3), _togglePin),
            _headerBtn(_isBookmarked ? Icons.star_rounded : Icons.star_outline_rounded,
              _isBookmarked ? const Color(0xFFFFD600) : Colors.white.withValues(alpha: 0.3), () {
                HapticFeedback.mediumImpact();
                setState(() => _isBookmarked = !_isBookmarked);
                if (_isBookmarked) widget.onBookmark?.call(_activeText);
              }),
            _headerBtn(_copied ? Icons.check_rounded : Icons.copy_rounded,
              _copied ? _green : Colors.white.withValues(alpha: 0.3), _copyToClipboard),
            _headerBtn(Icons.close, Colors.white.withValues(alpha: 0.3), () => _dismiss()),
          // ↑ default fling = up, like Tony flicking it away
          ]),
          const SizedBox(height: 10),
          Container(height: 1, decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [ac.withValues(alpha: 0), ac.withValues(alpha: 0.4 * glowPulse), ac.withValues(alpha: 0)],
              stops: const [0.0, 0.5, 1.0],
            ),
          )),
        ]),
      ),
    );
  }

  Widget _headerBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 13, color: color)));

  // ─── (8) Typing indicator with timeout ────────────────────────────────

  Widget _buildTypingIndicator(double pulse) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (i) {
          final offset = sin((pulse + i * 0.2) * 3.14159) * 3;
          return Transform.translate(
            offset: Offset(0, -offset.abs()),
            child: Container(
              width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cyan.withValues(alpha: 0.3 + pulse * 0.4),
                boxShadow: [BoxShadow(color: _cyan.withValues(alpha: 0.15), blurRadius: 4)],
              ),
            ),
          );
        })),
        // (8) Timeout counter
        if (_waitSeconds > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${_waitSeconds}s',
              style: TextStyle(color: _cyan.withValues(alpha: 0.25), fontSize: 9, fontWeight: FontWeight.w400),
            ),
          ),
      ]),
    );
  }

  // ─── HUD corners ─────────────────────────────────────────────────────

  List<Widget> _buildHudCorners(double gp) {
    final color = (_isPinned ? _green : _cyan).withValues(alpha: 0.3 * gp);
    final side = BorderSide(color: color, width: 1.5);
    const none = BorderSide.none;
    const s = 14.0;
    Widget c(Alignment a, BorderSide t, BorderSide r, BorderSide b, BorderSide l) =>
        Positioned.fill(child: Align(alignment: a, child: Container(
          width: s, height: s, decoration: BoxDecoration(border: Border(top: t, right: r, bottom: b, left: l)))));
    return [c(Alignment.topLeft, side, none, none, side), c(Alignment.topRight, side, side, none, none),
      c(Alignment.bottomLeft, none, none, side, side), c(Alignment.bottomRight, none, side, side, none)];
  }

  // ─── Card counter ────────────────────────────────────────────────────

  Widget _buildCardCounterBadge() => Positioned(right: -8, top: -8, child: GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); widget.onDismissAll?.call(); },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _cyan.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _cyan.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${widget.totalCards}', style: TextStyle(color: _cyan, fontSize: 10, fontWeight: FontWeight.w700)),
        const SizedBox(width: 2),
        Icon(Icons.close, size: 8, color: _cyan.withValues(alpha: 0.6)),
      ]),
    ),
  ));

  // ─── History indicator ────────────────────────────────────────────────

  Widget _buildHistoryIndicator() {
    final total = widget.conversationHistory.length + 1;
    final active = _historyIndex < 0 ? total - 1 : _historyIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.chevron_left, size: 12, color: _canSwipeBack ? _cyan.withValues(alpha: 0.5) : Colors.transparent),
        const SizedBox(width: 4),
        for (int i = 0; i < total; i++)
          Container(width: i == active ? 12 : 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(3),
              color: _cyan.withValues(alpha: i == active ? 0.8 : 0.2))),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right, size: 12, color: _canSwipeForward ? _cyan.withValues(alpha: 0.5) : Colors.transparent),
      ]),
    );
  }

  // ─── Swipe hint ───────────────────────────────────────────────────────

  Widget _buildSwipeHint() {
    final lang = ui.PlatformDispatcher.instance.locale.languageCode;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: 0.0), duration: const Duration(seconds: 3),
      builder: (_, op, child) => op <= 0 ? const SizedBox.shrink() : Opacity(opacity: op, child: child),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.arrow_back_ios, size: 10, color: _cyan.withValues(alpha: 0.4)),
          Text(lang == 'it' ? 'scorri per la cronologia' : 'swipe for history',
            style: TextStyle(color: _cyan.withValues(alpha: 0.3), fontSize: 9, fontStyle: FontStyle.italic)),
          Icon(Icons.arrow_forward_ios, size: 10, color: _cyan.withValues(alpha: 0.4)),
        ]),
      ),
    );
  }

  // ─── Follow-up chips ──────────────────────────────────────────────────

  // ─── 💡 GAP CHIPS ────────────────────────────────────────────────────────

  Widget _buildGapChips() {
    final gaps = widget.gapChips ?? [];
    final unmastered = gaps.where((g) => !widget.masteredConcepts.contains(g)).toList();
    if (unmastered.isEmpty) return const SizedBox.shrink();

    const chipColor = Color(0xFF00B0FF);
    final visible = _showAllGapChips ? unmastered : unmastered.take(3).toList();
    final extra = unmastered.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Wrap(
            spacing: 6, runSpacing: 6,
            children: [
              ...visible.map((g) => GestureDetector(
                onTap: () { HapticFeedback.selectionClick(); widget.onGapChipTap?.call(g); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: chipColor.withValues(alpha: 0.35), width: 1)),
                  child: Text(
                    g.length > 20 ? g.substring(0, 18) + '…' : g,
                    style: const TextStyle(color: chipColor, fontSize: 11)),
                ),
              )),
              if (extra > 0)
                GestureDetector(
                  onTap: () { HapticFeedback.selectionClick(); setState(() => _showAllGapChips = true); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: chipColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: chipColor.withValues(alpha: 0.2), width: 1)),
                    child: Text('+' + extra.toString(),
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
                ),
            ],
          ),
        ),
        // 📊 Riepilogo chip
        // ── Action chips (student-friendly verbs) ──
        if (widget.showSelfRating) ...[
          // ╭─ 📝 STUDIA ─────────────────────────────────────────
          _chipCategoryHeader('📝', 'Studia', const Color(0xFFFFD54F)),
          if (_expandedCategory == '📝') ...[
            if (widget.onVerify != null)
              _actionChip('✏️ Mettiti alla prova', const Color(0xFFFFD54F), const Color(0xFFFF8F00), () => widget.onVerify?.call()),
            if (widget.onCornell != null && unmastered.isNotEmpty)
              _actionChip('💬 Domanda chiave', const Color(0xFFCE93D8), const Color(0xFF311B92), () => widget.onCornell?.call(unmastered.first)),
            if (widget.onFeynman != null && unmastered.isNotEmpty)
              _actionChip('🗣️ Spiegalo tu', const Color(0xFF80CBC4), const Color(0xFF00695C), () => widget.onFeynman?.call(unmastered.first)),
            if (widget.onStemExercise != null)
              _actionChip('🧮 Esercizio pratico', const Color(0xFFFFCC80), const Color(0xFFE65100), () => widget.onStemExercise?.call()),
            if (widget.onPreLettura != null)
              _actionChip('🔮 Anticipa', const Color(0xFF90CAF9), const Color(0xFF1565C0), () => widget.onPreLettura?.call()),
          ],

          // ╭─ 🧭 ESPLORA ─────────────────────────────────────
          _chipCategoryHeader('🧭', 'Esplora', const Color(0xFF90A4AE)),
          if (_expandedCategory == '🧭') ...[
            if (widget.onNavigateCluster != null)
              _actionChip('📍 Vai al punto', const Color(0xFF90A4AE), const Color(0xFF37474F), () => widget.onNavigateCluster?.call()),
            if (widget.onClusterHide != null)
              _actionChip('🙈 Nascondi e ricorda', const Color(0xFFF48FB1), const Color(0xFF880E4F), () => widget.onClusterHide?.call()),
            if (widget.onInterleave != null)
              _actionChip('🔀 Mescola concetti', const Color(0xFFAB47BC), const Color(0xFF4A148C), () => widget.onInterleave?.call()),
          ],

          // ╭─ 📊 PROGRESSI ────────────────────────────────────────────
          _chipCategoryHeader('📊', 'Progressi', const Color(0xFF42A5F5)),
          if (_expandedCategory == '📊') ...[
            if (widget.onDashboard != null)
              _actionChip('📊 I miei progressi', const Color(0xFF42A5F5), const Color(0xFF0D47A1), () => widget.onDashboard?.call()),
            if (widget.onSessionSummary != null)
              _actionChip('📋 Riepilogo sessione', const Color(0xFF9FA8DA), const Color(0xFF1A237E), () => widget.onSessionSummary?.call()),
            if (widget.onExport != null)
              _actionChip('💾 Esporta', const Color(0xFF66BB6A), const Color(0xFF1B5E20), () => widget.onExport?.call()),
          ],
        ],
      ],
    );
  }
  // ─── Chip category helpers ──────────────────────────────────────────────

  Widget _chipCategoryHeader(String icon, String label, Color color) {
    final isOpen = _expandedCategory == icon;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _expandedCategory = isOpen ? null : icon);
        },
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$icon $label',
            style: TextStyle(color: color.withValues(alpha: isOpen ? 0.9 : 0.5),
              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(width: 4),
          Text(isOpen ? '▾' : '▸',
            style: TextStyle(color: color.withValues(alpha: 0.4), fontSize: 10)),
        ]),
      ),
    );
  }

  Widget _actionChip(String label, Color textColor, Color bgColor, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 1, 12, 1),
      child: GestureDetector(
        onTap: () { HapticFeedback.mediumImpact(); onTap?.call(); },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: bgColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: textColor.withValues(alpha: 0.4), width: 1)),
          child: Text(label,
            style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  // ─── ✏️ ACTIVE RECALL VERIFY INPUT (R&K 2006) ───────────────────────────

  Widget _buildVerifyInput() {
    final concept = _selectedConcept ?? widget.verifyQuestion;
    final candidates = widget.verifyCandidates ??
        (widget.verifyQuestion != null ? [widget.verifyQuestion!] : <String>[]);
    if (candidates.isEmpty) return const SizedBox.shrink();

    const vc = Color(0xFFFFD54F);
    const ec = Color(0xFF80DEEA);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [

          // ── PHASE A: concept picker ──────────────────────────────────────
          if (concept == null) ...[
            const Text('✏️ QUALE CONCETTO VUOI TESTARE?',
              style: TextStyle(color: vc, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: candidates.map((c) => GestureDetector(
                onTap: () { HapticFeedback.selectionClick(); setState(() => _selectedConcept = c); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: vc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: vc.withValues(alpha: 0.4), width: 1)),
                  child: Text(c.length > 26 ? c.substring(0, 24) + '…' : c,
                    style: const TextStyle(color: vc, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              )).toList(),
            ),
          ],

          // ── PHASES B + C + D: concept selected ──────────────────────────
          if (concept != null) ...[
            // Concept heading
            Text('💭 $concept',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),

            // ── PHASE D: result badge (only for ✅ mastery) ──────────────
            if (_verifyDone && _verifyResult == '✅')
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.3, end: 1.0),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.elasticOut,
                  builder: (_, v, child) => Transform.scale(scale: v, child: child),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _vBadgeColor(_verifyResult).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _vBadgeColor(_verifyResult).withValues(alpha: 0.5), width: 1.5)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_verifyResult, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Text(_vBadgeLabel(_verifyResult),
                        style: TextStyle(color: _vBadgeColor(_verifyResult),
                          fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),

            // ── PHASE B: 3 confidence chips (zero keyboard) ───────────────
            if (!_verifyDone && !_verifySubmitting)
              Column(mainAxisSize: MainAxisSize.min, children: [
                _confidenceChip('🟢 So spiegarlo', 1, const Color(0xFF69F0AE), concept),
                const SizedBox(height: 6),
                _confidenceChip('🟡 Ho dubbi', 0, const Color(0xFFFFD54F), concept),
                const SizedBox(height: 6),
                _confidenceChip('🔴 Non ricordo', -1, const Color(0xFFEF5350), concept),
              ]),

            // ── Submitting indicator ───────────────────────────────────────
            if (_verifySubmitting)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5,
                      color: vc.withValues(alpha: 0.7))),
                  const SizedBox(width: 8),
                  Text('Un momento…',
                    style: TextStyle(color: vc.withValues(alpha: 0.6),
                      fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),


            // ── PHASE E: Prossimo concetto (Zeigarnik → auto-advance) ───
            if (_verifyDone)
              Builder(builder: (_) {
                if (!_verifiedInSession.contains(concept)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _verifiedInSession.add(concept));
                  });
                }
                final candidates = widget.verifyCandidates ?? [];
                final nextConcept = candidates
                    .where((c) => c != concept && !_verifiedInSession.contains(c))
                    .firstOrNull;
                final tested = _verifiedInSession.length;
                final total = candidates.length;
                if (nextConcept == null) {
                  if (total > 1) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('🎉 $tested/$total completati!',
                        style: const TextStyle(color: Color(0xFF69F0AE), fontSize: 12, fontWeight: FontWeight.w600)),
                    );
                  }
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedConcept = nextConcept;
                        _verifyDone = false; _verifySubmitting = false;
                        _verifyResult = '';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4), width: 1)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('$tested/$total',
                          style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Text('Prossimo → ${nextConcept.length > 20 ? '${nextConcept.substring(0, 18)}…' : nextConcept}',
                          style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                );
              }),
          ], // concept != null
        ],
      ),
      ),
    );
  }

  Widget _confidenceChip(String label, int level, Color color, String concept) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        if (level == 1) {
          // 🟢 So spiegarlo → trust the student, skip Atlas eval entirely
          setState(() {
            _verifyDone = true;
            _verifyResult = '✅';
          });
          // Mark mastered + SR via callback (fire-and-forget)
          widget.onVerifySubmit?.call(concept, 'So spiegarlo', 'confidence_1');
        } else {
          // 🟡 Ho dubbi / 🔴 Non ricordo → Atlas explains the concept
          final answers = {0: 'Ho dubbi', -1: 'Non ricordo'};
          setState(() => _verifySubmitting = true);
          await widget.onVerifySubmit?.call(concept, answers[level]!, 'confidence_$level');
          if (mounted) {
            setState(() {
              _verifySubmitting = false;
              _verifyDone = true;
              _verifyResult = level == 0 ? '🧠' : '📚'; // No badge shown (only ✅ shows)
            });
          }
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1)),
        child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Color _vBadgeColor(String e) => switch (e) {
    '✅' => const Color(0xFF69F0AE),
    '🧠' => const Color(0xFF80DEEA),   // growth: teal = awareness
    '📚' => const Color(0xFF90CAF9),   // growth: blue = learning
    '⚠️' => const Color(0xFFFFD54F),
    _ => const Color(0xFFFF5252),
  };

  String _vBadgeLabel(String e) => switch (e) {
    '✅' => 'Ottimo!',
    _ => '', // 🧠/📚: la spiegazione è il valore, il badge è rumore
  };

  // ─── Follow-up chips ─────────────────────────────────────────────────────

  Widget _buildFollowUpChips() {

    final suggestions = _getFollowUpSuggestions();
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Wrap(spacing: 6, runSpacing: 4, children: suggestions.map((s) => GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); _autoDismissTimer?.cancel(); widget.onFollowUp?.call(s); },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: _cyan.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _cyan.withValues(alpha: 0.15), width: 0.5)),
          child: Text(s, style: TextStyle(fontSize: 10, color: _cyan.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
        ),
      )).toList()),
    );
  }

  // ─── Action bar ───────────────────────────────────────────────────────

  Widget _buildActionBar(double gp) {
    final lang = ui.PlatformDispatcher.instance.locale.languageCode;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(children: [
        if (widget.onGoDeeper != null && _historyIndex < 0 && !_isErrorResponse)
          _actionBtn(Icons.unfold_more_rounded, lang == 'it' ? 'Approfondisci' : 'Go deeper', () {
            _autoDismissTimer?.cancel(); HapticFeedback.selectionClick();
            widget.onGoDeeper?.call([...widget.conversationHistory, _displayedText]);
          }, gp),
        const SizedBox(width: 6),
        if (widget.onSearchWeb != null && !_isErrorResponse)
          _actionBtn(Icons.search_rounded, 'Search', () {
            HapticFeedback.selectionClick();
            final m = RegExp(r'▸\s*SCAN\s*:\s*(.+?)(?=▸|$)', dotAll: true).firstMatch(_activeText);
            widget.onSearchWeb?.call(m?.group(1)?.trim() ?? _activeText.substring(0, min(60, _activeText.length)));
          }, gp),
        const SizedBox(width: 6),
        if (widget.onSaveAsNote != null && !_isErrorResponse)
          _actionBtn(Icons.note_add_rounded, FlueraLocalizations.of(context)!.save, () {
            _autoDismissTimer?.cancel(); HapticFeedback.selectionClick();
            widget.onSaveAsNote?.call(_activeText); _dismiss();
          }, gp),
        // LaTeX extraction button — with formula count badge
        if (widget.onExtractLatex != null && !_isErrorResponse && _hasLatex) ...[
          const SizedBox(width: 6),
          _buildExtractButton(lang, gp),
        ],
      ]),
    );
  }

  // ─── Extract button with badge + picker ────────────────────────────────

  Widget _buildExtractButton(String lang, double gp) {
    final formulas = _extractedLatex;
    final count = formulas.length;
    final label = FlueraLocalizations.of(context)!.atlas_extractFn;

    return Expanded(child: GestureDetector(
      onTap: () {
        _autoDismissTimer?.cancel(); HapticFeedback.mediumImpact();
        if (formulas.isEmpty) return;
        // #2: Picker dialog for 5+ formulas
        if (count >= 5) {
          _showFormulaPicker(formulas);
        } else {
          widget.onExtractLatex?.call(formulas);
        }
      },
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(color: _cyan.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _cyan.withValues(alpha: 0.2 * gp), width: 0.5)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.functions_rounded, size: 12, color: _cyan.withValues(alpha: 0.7)), const SizedBox(width: 4),
            Flexible(child: Text(label, style: TextStyle(fontSize: 10, color: _cyan.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500, letterSpacing: 0.3), overflow: TextOverflow.ellipsis)),
          ]),
        ),
        // #1: Badge ×N
        if (count > 1)
          Positioned(right: -4, top: -6, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(color: _cyan, borderRadius: BorderRadius.circular(7)),
            child: Text('×$count', style: const TextStyle(fontSize: 8, color: Colors.black, fontWeight: FontWeight.w700)),
          )),
      ]),
    ));
  }

  // #2: Formula picker dialog
  void _showFormulaPicker(List<String> formulas) {
    final selected = List.generate(formulas.length, (_) => true);
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Row(children: [
          Icon(Icons.functions_rounded, color: _cyan, size: 20),
          const SizedBox(width: 8),
          Text(FlueraLocalizations.of(context)!.atlas_formulaCount(formulas.length), style: TextStyle(color: _cyan, fontSize: 16)),
        ]),
        content: SizedBox(width: double.maxFinite, child: ListView.builder(
          shrinkWrap: true, itemCount: formulas.length,
          itemBuilder: (_, i) => CheckboxListTile(
            value: selected[i], dense: true, activeColor: _cyan,
            title: Text(formulas[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            onChanged: (v) => setD(() => selected[i] = v ?? false),
          ),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text(FlueraLocalizations.of(context)!.cancel, style: TextStyle(color: _cyan.withValues(alpha: 0.6)))),
          TextButton(onPressed: () {
            Navigator.pop(ctx);
            final picked = <String>[];
            for (int i = 0; i < formulas.length; i++) { if (selected[i]) picked.add(formulas[i]); }
            if (picked.isNotEmpty) widget.onExtractLatex?.call(picked);
          }, child: Text(FlueraLocalizations.of(context)!.atlas_extractCount(selected.where((s) => s).length), style: TextStyle(color: _cyan, fontWeight: FontWeight.w600))),
        ],
      ),
    ));
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap, double gp) => Expanded(
    child: GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(color: _cyan.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _cyan.withValues(alpha: 0.2 * gp), width: 0.5)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: _cyan.withValues(alpha: 0.7)), const SizedBox(width: 4),
        Flexible(child: Text(label, style: TextStyle(fontSize: 10, color: _cyan.withValues(alpha: 0.8),
          fontWeight: FontWeight.w500, letterSpacing: 0.3), overflow: TextOverflow.ellipsis)),
      ]),
    )),
  );

  // ─── Structured text ──────────────────────────────────────────────────

  Widget _buildStructuredText(String text) {
    if (text.isEmpty) return const SizedBox.shrink();

    final sections = _getParsedSections(text);
    if (sections.isEmpty) return _buildMarkdownText(text);

    final widgets = <Widget>[];
    for (int i = 0; i < sections.length; i++) {
      final sec = sections[i];
      if (sec.label == null) { widgets.add(_buildMarkdownText(sec.content)); widgets.add(const SizedBox(height: 8)); continue; }

      final isCollapsed = _collapsedSections.contains(sec.label);
      widgets.add(TweenAnimationBuilder<double>(
        key: ValueKey('sec_${sec.label}'), tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut,
        builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 8*(1-v)), child: child)),
        child: Padding(
          padding: EdgeInsets.only(top: i > 0 ? 12.0 : 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: () { HapticFeedback.selectionClick();
                setState(() { isCollapsed ? _collapsedSections.remove(sec.label) : _collapsedSections.add(sec.label!); }); },
              child: Row(children: [
                Text('▸ ${sec.label}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: _cyan.withValues(alpha: 0.7), letterSpacing: 2)),
                const SizedBox(width: 4),
                Icon(isCollapsed ? Icons.expand_more : Icons.expand_less, size: 12, color: _cyan.withValues(alpha: 0.3)),
              ]),
            ),
            const SizedBox(height: 4),
            if (!isCollapsed && sec.content.isNotEmpty)
              AnimatedSize(duration: const Duration(milliseconds: 200), child: _buildMarkdownText(sec.content)),
            if (isCollapsed) Text('…', style: TextStyle(color: _cyan.withValues(alpha: 0.3), fontSize: 11)),
          ]),
        ),
      ));
    }

    if (!_streamingDone && _historyIndex < 0) {
      widgets.add(Text('▌', style: TextStyle(color: _cyan.withValues(alpha: 0.6), fontSize: 12)));
    }

    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
    return AnimatedBuilder(
      animation: _glowTextController,
      builder: (_, child) {
        final t = _glowTextController.value;
        if (t <= 0 || t >= 1) return child!;
        return ShaderMask(
          shaderCallback: (b) => LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.white, const Color(0xFF69F0AE).withValues(alpha: 0.3), Colors.white],
            stops: [(t-0.1).clamp(0.0,1.0), t.clamp(0.0,1.0), (t+0.1).clamp(0.0,1.0)],
          ).createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
          blendMode: BlendMode.modulate, child: child!,
        );
      },
      child: content,
    );
  }

  List<_ParsedSection> _getParsedSections(String text) {
    if (_cachedSectionsSource == text && _cachedSections != null) return _cachedSections!;
    _cachedSectionsSource = text;
    final pat = RegExp(r'▸\s*(SCAN|CONN|NOTE)\s*:\s*');
    final ms = pat.allMatches(text).toList();
    if (ms.isEmpty) { _cachedSections = const []; return _cachedSections!; }
    final r = <_ParsedSection>[];
    if (ms.first.start > 0) { final pre = text.substring(0, ms.first.start).trim(); if (pre.isNotEmpty) r.add(_ParsedSection(null, pre)); }
    for (int i = 0; i < ms.length; i++) {
      final end = i+1 < ms.length ? ms[i+1].start : text.length;
      r.add(_ParsedSection(ms[i].group(1), text.substring(ms[i].end, end).trim()));
    }
    _cachedSections = r;
    return r;
  }

  // ─── Markdown ─────────────────────────────────────────────────────────

  Widget _buildMarkdownText(String text) {
    // Match code blocks AND display math $$...$$
    final cbp = RegExp(r'```(\w*)\n?([\s\S]*?)```');
    final dmp = RegExp(r'\$\$(.+?)\$\$', dotAll: true);
    final allBlocks = <_BlockMatch>[];
    for (final m in cbp.allMatches(text)) allBlocks.add(_BlockMatch(m.start, m.end, 'code', m.group(2)?.trim() ?? ''));
    for (final m in dmp.allMatches(text)) {
      if (!allBlocks.any((b) => m.start >= b.s && m.start < b.e)) {
        allBlocks.add(_BlockMatch(m.start, m.end, 'math', m.group(1)?.trim() ?? ''));
      }
    }
    allBlocks.sort((a, b) => a.s.compareTo(b.s));

    if (allBlocks.isEmpty) return _buildRichText(text);

    final parts = <Widget>[]; int lastEnd = 0;
    for (final b in allBlocks) {
      if (b.s > lastEnd) parts.add(_buildRichText(text.substring(lastEnd, b.s)));
      if (b.t == 'code') {
        parts.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.all(10), width: double.infinity,
          decoration: BoxDecoration(color: const Color(0xFF0D0D22), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _cyan.withValues(alpha: 0.15), width: 0.5)),
          child: _buildHighlightedCode(b.c),
        ));
      } else {
        // #3: Display math — rendered via LatexPreviewCard
        parts.add(GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onExtractLatex?.call([b.c]);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _cyan.withValues(alpha: 0.2), width: 0.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LatexPreviewCard(
                latexSource: b.c,
                fontSize: 18,
                color: _cyan,
                minHeight: 36,
                backgroundColor: const Color(0xFF0D0D22),
              ),
            ),
          ),
        ));
      }
      lastEnd = b.e;
    }
    if (lastEnd < text.length) parts.add(_buildRichText(text.substring(lastEnd)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: parts);
  }

  // ─── Feature 3: Syntax Highlighting ────────────────────────────────────

  static final _codeTokenPattern = RegExp(
    r'''(\/\/.*$|\#.*$)'''   // group 1: line comments
    r"""|(('[^']*'|"[^"]*"))"""   // group 2: strings
    r'''|(\b\d+\.?\d*\b)'''   // group 3: numbers
    r'''|(\b(?:if|else|for|while|return|class|def|func|function|import|export|from|const|var|let|final|void|int|double|bool|String|true|false|null|async|await|try|catch|throw|new|this|super|static|abstract|override|extends|implements|with|enum|switch|case|break|continue|in|is|as)\b)''',  // group 4: keywords
    multiLine: true,
  );

  Widget _buildHighlightedCode(String code) {
    final defaultStyle = TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5, color: _green.withValues(alpha: 0.85));
    final keywordStyle = TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5, color: _cyan.withValues(alpha: 0.95), fontWeight: FontWeight.w600);
    final stringStyle = TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5, color: const Color(0xFFFFD54F).withValues(alpha: 0.9));
    final numberStyle = TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5, color: const Color(0xFFCE93D8).withValues(alpha: 0.9));
    final commentStyle = TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5, color: Colors.white.withValues(alpha: 0.3), fontStyle: FontStyle.italic);

    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final m in _codeTokenPattern.allMatches(code)) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: code.substring(lastEnd, m.start), style: defaultStyle));
      }
      final TextStyle style;
      if (m.group(1) != null) style = commentStyle;
      else if (m.group(2) != null) style = stringStyle;
      else if (m.group(3) != null) style = numberStyle;
      else style = keywordStyle;

      spans.add(TextSpan(text: m.group(0), style: style));
      lastEnd = m.end;
    }
    if (lastEnd < code.length) {
      spans.add(TextSpan(text: code.substring(lastEnd), style: defaultStyle));
    }

    return Text.rich(TextSpan(children: spans));
  }

  Widget _buildRichText(String text) {
    final spans = <InlineSpan>[]; final bp = RegExp(r'\*\*(.+?)\*\*'); final cp = RegExp(r'`([^`]+)`');
    final lines = text.split('\n');
    for (int li = 0; li < lines.length; li++) {
      var line = lines[li]; if (li > 0) spans.add(const TextSpan(text: '\n'));
      if (line.trimLeft().startsWith('- ') || line.trimLeft().startsWith('• ')) {
        line = line.trimLeft().substring(2);
        spans.add(TextSpan(text: '  • ', style: TextStyle(color: _cyan.withValues(alpha: 0.6), fontSize: 13)));
      }
      final allM = <_MdM>[]; for (final m in bp.allMatches(line)) allM.add(_MdM(m.start, m.end, 'b', m.group(1)!));
      for (final m in cp.allMatches(line)) {
        if (!allM.any((a) => m.start >= a.s && m.start < a.e || m.end > a.s && m.end <= a.e))
          allM.add(_MdM(m.start, m.end, 'c', m.group(1)!));
      }
      // Detect inline LaTeX $...$
      final lp = RegExp(r'\$\$(.+?)\$\$|\$(.+?)\$');
      for (final m in lp.allMatches(line)) {
        if (!allM.any((a) => m.start >= a.s && m.start < a.e || m.end > a.s && m.end <= a.e)) {
          allM.add(_MdM(m.start, m.end, 'l', m.group(1) ?? m.group(2) ?? ''));
        }
      }
      allM.sort((a, b) => a.s.compareTo(b.s));
      int last = 0;
      for (final m in allM) {
        if (m.s > last) spans.add(TextSpan(text: line.substring(last, m.s), style: _bodyStyle));
        if (m.t == 'b') spans.add(TextSpan(text: m.c, style: _bodyStyle.copyWith(fontWeight: FontWeight.w600, color: Colors.white)));
        else if (m.t == 'l') {
          // Inline LaTeX — rendered via compact LatexPreviewCard (tap=extract, long-press=copy)
          spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onExtractLatex?.call([m.c]);
            },
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: m.c));
              HapticFeedback.mediumImpact();
            },
            child: Container(
              constraints: const BoxConstraints(maxWidth: 200),
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              decoration: BoxDecoration(
                color: _cyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _cyan.withValues(alpha: 0.25), width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LatexPreviewCard(
                  latexSource: m.c,
                  fontSize: 14,
                  color: _cyan,
                  minHeight: 22,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
          )));
        }
        else if (m.t == 'c') {
          spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(color: const Color(0xFF0D0D22), borderRadius: BorderRadius.circular(4)),
            child: Text(m.c, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: _green.withValues(alpha: 0.85))))));
        }
        last = m.e;
      }
      if (last < line.length) spans.add(TextSpan(text: line.substring(last), style: _bodyStyle));
    }
    return Text.rich(TextSpan(children: spans));
  }

  static final _bodyStyle = TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, height: 1.6, fontWeight: FontWeight.w400);
}

// ─── Helpers ────────────────────────────────────────────────────────────
enum _SnapEdge { none, left, right }
class _ParsedSection { final String? label; final String content; const _ParsedSection(this.label, this.content); }
class _MdM { final int s, e; final String t, c; const _MdM(this.s, this.e, this.t, this.c); }
class _BlockMatch { final int s, e; final String t, c; const _BlockMatch(this.s, this.e, this.t, this.c); }

// ═════════════════════════════════════════════════════════════════════════
// Painters
// ═════════════════════════════════════════════════════════════════════════

class _BeamInPainter extends CustomPainter {
  final double progress; final Color color;
  _BeamInPainter({required this.progress, required this.color});
  @override void paint(Canvas canvas, Size size) {
    if (size.width < 2 || size.height < 2) return;
    try {
      final y = progress * size.height; final op = (1.0 - progress).clamp(0.0, 1.0);
      if (op <= 0) return;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()
        ..shader = ui.Gradient.linear(Offset(0, y), Offset(size.width, y),
          [color.withValues(alpha: 0), color.withValues(alpha: 0.6*op), color.withValues(alpha: 0.6*op), color.withValues(alpha: 0)],
          [0.0, 0.15, 0.85, 1.0])
        ..strokeWidth = 2 ..style = PaintingStyle.stroke);
      if (y > 1) canvas.drawRect(Rect.fromLTRB(0, 0, size.width, y), Paint()
        ..shader = ui.Gradient.linear(const Offset(0,0), Offset(0,y),
          [color.withValues(alpha: 0), color.withValues(alpha: 0.04*op)]));
    } catch (_) {}
  }
  @override bool shouldRepaint(_BeamInPainter old) => old.progress != progress;
}

class _ScanLinePainter extends CustomPainter {
  final double progress; final Color color;
  _ScanLinePainter({required this.progress, required this.color});
  @override void paint(Canvas canvas, Size size) {
    if (size.width < 2 || size.height < 2) return;
    try {
      final y = progress * size.height;
      canvas.drawLine(Offset(0,y), Offset(size.width,y), Paint()
        ..shader = ui.Gradient.linear(Offset(0,y), Offset(size.width,y),
          [color.withValues(alpha: 0), color.withValues(alpha: 0.3), color.withValues(alpha: 0.3), color.withValues(alpha: 0)],
          [0.0, 0.2, 0.8, 1.0])
        ..strokeWidth = 1.5 ..style = PaintingStyle.stroke);
      canvas.drawRect(Rect.fromLTRB(0, y-20, size.width, y+20), Paint()
        ..shader = ui.Gradient.linear(Offset(size.width/2, y-20), Offset(size.width/2, y+20),
          [color.withValues(alpha: 0), color.withValues(alpha: 0.08), color.withValues(alpha: 0.08), color.withValues(alpha: 0)],
          [0.0, 0.3, 0.7, 1.0]));
    } catch (_) {}
  }
  @override bool shouldRepaint(_ScanLinePainter old) => old.progress != progress;
}
