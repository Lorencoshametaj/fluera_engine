import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../drawing/models/pro_drawing_point.dart';
import '../../l10n/generated/fluera_localizations.g.dart';
import 'components/exam_stroke_storage.dart';
import 'components/mini_canvas_scratchpad.dart';

/// 🎓 EXAM ANSWER FULLSCREEN — closed-book answer page for open-ended and
/// formula questions during an Atlas Exam session.
///
/// Why a fullscreen page (and not an inline scratchpad in the question card):
/// 1. **Closed-book**: an exam must hide the source notes while the student
///    writes their answer. A `MaterialPageRoute` with `fullscreenDialog: true`
///    occludes the canvas + cluster overlay completely. The pedagogical
///    spatial recall of Fluera is delivered by the *Fog of War* phase that
///    runs BEFORE the exam — not by mixing notes into the test.
/// 2. **Stylus-first**: 180px scratchpad is a contradiction of Fluera's
///    handwriting-first promise. Fullscreen gives the student room to write
///    naturally with the stylus.
///
/// Submission flow:
/// - If [onSubmit] is provided → the bottom button is **"Invia risposta"**:
///   tap forces an OCR flush, calls onSubmit(text), pops with the text.
///   The caller doesn't need a separate "Invia" button — the fullscreen
///   IS the submission surface.
/// - If [onSubmit] is null → the bottom button is "Conferma": just pops
///   with the text. Caller submits later (legacy two-step flow).
///
/// Returns the final answer text via `Navigator.pop(context, String)`.
/// Returns `null` on cancel / back gesture so the caller knows to NOT
/// overwrite anything.
class ExamAnswerFullscreen extends StatefulWidget {
  final String questionText;
  final String initialAnswer;
  final bool startsInHandwriting;
  final bool isFormula;

  /// When provided, "Conferma" is replaced by "Invia risposta" — tapping
  /// it submits the answer directly (single-tap exam flow).
  final Future<void> Function(String answer)? onSubmit;

  /// Minimum required answer length (chars after trim). Below this we show
  /// a snackbar instead of accepting. Default 1 (any non-empty answer).
  /// The elaboration page uses 15 (Slamecka & Graf 1978 — meaningful
  /// generation requires more than a single keyword).
  final int minAnswerLength;

  /// Optional accent color override. Defaults to Fluera cyan; the
  /// elaboration page passes red when the previous answer was
  /// overconfident-wrong (hypercorrection visual cue).
  final Color? accentColor;

  /// CTA label override on the bottom button (defaults to "Conferma" or
  /// "Invia risposta" depending on [onSubmit] presence). Use for the
  /// elaboration flow which submits as "Salva".
  final String? submitLabel;

  /// When provided, used INSTEAD of `Navigator.pop(answer)` to return the
  /// confirmed text. This lets the caller mount the page as an
  /// [OverlayEntry] (above any other manual entries) instead of as a
  /// Navigator route — needed when the parent overlay was inserted via
  /// `Overlay.of(context).insert(...)` which sits above all Navigator
  /// routes (z-order would otherwise hide the fullscreen page).
  final ValueChanged<String>? onSubmitted;

  /// When provided, used INSTEAD of `Navigator.pop()` to dismiss the page
  /// (cancel / back). Pairs with [onSubmitted] for OverlayEntry mounts.
  final VoidCallback? onCancelled;

  /// Stable key under which the student's drawn strokes are persisted to
  /// disk. Typically `'<sessionId>__<questionId>'`. When null, strokes
  /// are kept only in memory for the lifetime of the widget. Wires through
  /// [ExamStrokeStorage] for atomic JSON I/O.
  final String? persistKey;

  /// Optional cloud-sync hook fired AFTER each successful local save when
  /// the user has opted into cloud strokes (Pro tier). Receives the same
  /// key + the JSON payload so the host can push to Supabase Storage / etc.
  /// Failures are silent — local persistence remains the source of truth.
  final Future<void> Function(String key, String json)? onCloudUpload;

  const ExamAnswerFullscreen({
    super.key,
    required this.questionText,
    this.initialAnswer = '',
    this.startsInHandwriting = true,
    this.isFormula = false,
    this.onSubmit,
    this.minAnswerLength = 1,
    this.accentColor,
    this.submitLabel,
    this.onSubmitted,
    this.onCancelled,
    this.persistKey,
    this.onCloudUpload,
  });

  @override
  State<ExamAnswerFullscreen> createState() => _ExamAnswerFullscreenState();
}

class _ExamAnswerFullscreenState extends State<ExamAnswerFullscreen>
    with WidgetsBindingObserver {
  static const _defaultAccent = Color(0xFF00E5FF);
  static const _bgDark = Color(0xFF0A0A1A);

  Color get _cyan => widget.accentColor ?? _defaultAccent;

  late final TextEditingController _answerCtrl;
  late final FocusNode _keyboardFocus;
  late bool _isHandwritingMode;
  bool _submitting = false;

  /// Key into the mini-canvas scratchpad's public state. Used to flush
  /// pending OCR before submission and to read `hasUnconfirmedStrokes` for
  /// the PopScope discard-confirmation guard.
  final GlobalKey<MiniCanvasScratchpadState> _scratchpadKey = GlobalKey();

  /// Local [ScaffoldMessenger] so SnackBars rendered from this page (e.g.
  /// the "answer too short" validation) sit ABOVE the page rather than
  /// being captured by the MaterialApp-level messenger, which renders
  /// behind any free-standing OverlayEntry. Without this, the Save button
  /// looked like a no-op for elaboration answers shorter than the
  /// minimum length — the snackbar fired but was hidden under the page.
  final GlobalKey<ScaffoldMessengerState> _localMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Strokes loaded from disk on initial mount (when [widget.persistKey] is
  /// set). `null` until the load future resolves, then either an empty list
  /// (no prior session) or the previous strokes. Drives the
  /// [MiniCanvasScratchpad.initialStrokes] parameter.
  List<ProStroke>? _initialStrokes;
  bool _initialStrokesLoaded = false;

  @override
  void initState() {
    super.initState();
    _answerCtrl = TextEditingController(text: widget.initialAnswer);
    _keyboardFocus = FocusNode();
    _isHandwritingMode = widget.startsInHandwriting;
    _answerCtrl.addListener(_onAnswerChanged);
    // Intercept Android system back gesture / button at the binding layer.
    // BackButtonListener (needs Router) doesn't work because we're mounted
    // as a free-standing OverlayEntry, not a Navigator route.
    WidgetsBinding.instance.addObserver(this);
    // Async-load any persisted strokes for this question. The build skips
    // the scratchpad until this completes so we don't render an empty pad
    // and then yank the strokes in.
    _loadInitialStrokes();
  }

  /// Persists strokes locally and (when opted in) uploads to the cloud.
  /// Awaitable — callers in critical paths (submit) await; auto-save and
  /// dispose use fire-and-forget. Cloud upload runs after the local write
  /// completes, so a failed upload still leaves the device with the truth.
  Future<void> _persistStrokes(List<ProStroke> strokes) async {
    final key = widget.persistKey;
    if (key == null || key.isEmpty) return;
    await ExamStrokeStorage.save(key, strokes);
    final upload = widget.onCloudUpload;
    if (upload != null && strokes.isNotEmpty) {
      try {
        final json = jsonEncode(strokes.map((s) => s.toJson()).toList());
        await upload(key, json);
      } catch (e) {
        debugPrint('🖋️ ExamAnswerFullscreen: cloud upload failed: $e');
      }
    }
  }

  Future<void> _loadInitialStrokes() async {
    final key = widget.persistKey;
    if (key == null || key.isEmpty) {
      if (!mounted) return;
      setState(() {
        _initialStrokes = const [];
        _initialStrokesLoaded = true;
      });
      return;
    }
    final loaded = await ExamStrokeStorage.load(key);
    if (!mounted) return;
    setState(() {
      _initialStrokes = loaded ?? const [];
      _initialStrokesLoaded = true;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Persist strokes on dispose so kill-app-mid-edit doesn't lose work.
    // We grab the snapshot before disposing the rest; the actual write is
    // fire-and-forget (no await — dispose can't be async). Cloud upload
    // (if opted in) is also fire-and-forget — see [_persistStrokes].
    final strokes = _scratchpadKey.currentState?.currentStrokes;
    if (strokes != null) {
      // ignore: discarded_futures
      _persistStrokes(strokes);
    }
    _answerCtrl.removeListener(_onAnswerChanged);
    _answerCtrl.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  /// Called by the Flutter binding when the OS asks to pop a route (back
  /// button / back gesture on Android, swipe-from-edge on iOS). Returning
  /// `true` consumes the event so the underlying canvas screen doesn't
  /// accidentally close. We funnel through [_attemptCancel] for the same
  /// UX as the X / Annulla buttons (with discard-confirmation).
  @override
  Future<bool> didPopRoute() async {
    await _attemptCancel();
    return true;
  }

  void _onAnswerChanged() {
    // Trigger rebuild for the live word counter under the submit button.
    if (mounted) setState(() {});
  }

  void _toggleMode() {
    HapticFeedback.selectionClick();
    setState(() => _isHandwritingMode = !_isHandwritingMode);
    // Autofocus the TextField when switching to keyboard mode.
    if (!_isHandwritingMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _keyboardFocus.requestFocus();
      });
    }
  }

  Future<void> _confirmOrSubmit() async {
    if (_submitting) return;

    // 1. Force-recognize any strokes still in the OCR debounce window so the
    //    last word the user wrote isn't lost. No-op in keyboard mode.
    if (_isHandwritingMode) {
      await _scratchpadKey.currentState?.flushPendingRecognition();
    }

    final answer = _answerCtrl.text.trim();
    if (answer.length < widget.minAnswerLength) {
      if (!mounted) return;
      final l10n = FlueraLocalizations.of(context)!;
      final msg = widget.minAnswerLength <= 1
          ? l10n.exam_answer_emptyValidation
          : l10n.exam_answer_minLengthValidation(widget.minAnswerLength, answer.length);
      // Use the local messenger (scoped to this OverlayEntry's Scaffold)
      // so the snackbar renders ABOVE this page. Falling back to the
      // app-level messenger would route the snackbar behind the page.
      _localMessengerKey.currentState?.showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
      debugPrint('🎓 ExamAnswerFullscreen: validation failed — '
          'answer.length=${answer.length} < minLength=${widget.minAnswerLength}');
      return;
    }

    HapticFeedback.lightImpact();

    // 2. Single-tap submit: if the caller provided onSubmit, fire it BEFORE
    //    popping so the loading state can be observed elsewhere; pop with
    //    the text either way.
    if (widget.onSubmit != null) {
      setState(() => _submitting = true);
      try {
        await widget.onSubmit!(answer);
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
    }
    if (!mounted) return;
    // Persist strokes synchronously before popping — submit is the
    // authoritative "this is my answer" moment, can't lose them on a
    // dispose race. Awaits the cloud upload too (if opted in) so the
    // "submit succeeded" UX guarantees both local + cloud durability.
    final strokes = _scratchpadKey.currentState?.currentStrokes;
    if (strokes != null) {
      await _persistStrokes(strokes);
    }
    if (!mounted) return;
    // OverlayEntry path (preferred when caller has z-order issues with
    // Navigator). Falls back to Navigator.pop for legacy callers.
    if (widget.onSubmitted != null) {
      widget.onSubmitted!(answer);
    } else {
      Navigator.of(context).pop(answer);
    }
  }

  Future<void> _attemptCancel() async {
    final hasPending = _scratchpadKey.currentState?.hasUnconfirmedStrokes ?? false;
    final hasText = _answerCtrl.text.trim().isNotEmpty;
    if (!hasPending && !hasText) {
      if (widget.onCancelled != null) {
        widget.onCancelled!();
      } else {
        Navigator.of(context).pop();
      }
      return;
    }
    // OverlayEntry-based confirm modal — same z-order trap as the outer
    // ExamOverlay's "X" close: this fullscreen page is mounted as an
    // OverlayEntry above the MaterialApp's Navigator, so `showDialog`
    // renders the dialog UNDER us → tap X looks dead. Mounting the
    // confirm modal as a sibling OverlayEntry puts it ON TOP.
    final discard = await _showDiscardConfirm();
    if (discard == true && mounted) {
      // User explicitly discarded — wipe persisted strokes so re-opening
      // the page starts fresh. The dispose() save would otherwise re-write
      // them right back.
      final key = widget.persistKey;
      if (key != null && key.isNotEmpty) {
        await ExamStrokeStorage.delete(key);
      }
      if (widget.onCancelled != null) {
        widget.onCancelled!();
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  /// Renders the "discard answer?" confirm modal as an [OverlayEntry] so
  /// it sits at the same z-level as the fullscreen page. Returns `true`
  /// when the user picked "Scarta", `false` (or `null`) otherwise.
  Future<bool?> _showDiscardConfirm() {
    final l10n = FlueraLocalizations.of(context)!;
    final completer = Completer<bool?>();
    late OverlayEntry entry;
    void close(bool? result) {
      try {
        entry.remove();
      } catch (_) {/* already removed */}
      if (!completer.isCompleted) completer.complete(result);
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
              color: const Color(0xFF14142B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.exam_answer_discardTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.exam_answer_discardBody,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                    onPressed: () => close(false),
                    child: Text(
                      l10n.exam_answer_keepWriting,
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => close(true),
                    child: Text(
                      l10n.exam_answer_discard,
                      style: const TextStyle(
                        color: Color(0xFFFF5252),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    ));
    Overlay.of(context).insert(entry);
    return completer.future;
  }

  int get _wordCount {
    final t = _answerCtrl.text.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final l10n = FlueraLocalizations.of(context)!;
    final modeLabel = _isHandwritingMode ? '⌨️' : '✍️';
    final submitLabel = widget.submitLabel ??
        (widget.onSubmit != null ? l10n.exam_answer_send : l10n.exam_answer_confirm);

    // Back gesture / button is intercepted at the binding layer via
    // [didPopRoute] (see [WidgetsBindingObserver] mixin) — works without
    // a Router/Navigator ancestor, unlike BackButtonListener. PopScope
    // remains as a no-op safety net for any rare Navigator-mounted reuse.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _attemptCancel();
      },
      child: ScaffoldMessenger(
        // Local messenger — see [_localMessengerKey] doc. Without this,
        // SnackBars for validation errors render below this OverlayEntry
        // and the user only sees the Save button "do nothing".
        key: _localMessengerKey,
        child: Scaffold(
        backgroundColor: _bgDark,
        appBar: AppBar(
          backgroundColor: _bgDark,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: _attemptCancel,
            tooltip: l10n.exam_answer_cancel,
          ),
          title: Text(
            widget.isFormula
                ? l10n.exam_answer_pageTitleFormula
                : l10n.exam_answer_pageTitleOpen,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              child: GestureDetector(
                onTap: _toggleMode,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _cyan.withValues(alpha: 0.3)),
                  ),
                  child: Text(modeLabel, style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(children: [
            // ── Question header (scrollable if very long) ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: _cyan.withValues(alpha: 0.18),
                    width: 1,
                  ),
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: mediaQuery.size.height * 0.22,
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.questionText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),

            // ── Answer area (fills remaining space) ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _isHandwritingMode
                    ? _buildHandwritingArea()
                    : _buildKeyboardArea(),
              ),
            ),

            // ── Bottom bar: word count + submit ──
            Container(
              padding: EdgeInsets.fromLTRB(
                16, 10, 16, 12 + mediaQuery.padding.bottom,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                border: Border(
                  top: BorderSide(
                    color: _cyan.withValues(alpha: 0.12),
                    width: 1,
                  ),
                ),
              ),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        l10n.exam_answer_words(_wordCount),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(children: [
                  Expanded(
                    flex: 1,
                    child: Semantics(
                      button: true,
                      enabled: !_submitting,
                      label: l10n.exam_answer_cancel,
                      child: TextButton(
                      onPressed: _submitting ? null : _attemptCancel,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: Colors.white60,
                      ),
                      child: Text(
                        l10n.exam_answer_cancel,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                    ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Semantics(
                      button: true,
                      enabled: !_submitting,
                      label: submitLabel,
                      child: ElevatedButton(
                      onPressed: _submitting ? null : _confirmOrSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _cyan,
                        foregroundColor: _bgDark,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _bgDark,
                              ),
                            )
                          : Text(
                              submitLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
      ),
    );
  }

  Widget _buildHandwritingArea() {
    return Column(children: [
      // Recognized-text preview (shrinks to content)
      if (_answerCtrl.text.trim().isNotEmpty)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _cyan.withValues(alpha: 0.18)),
          ),
          child: Text(
            _answerCtrl.text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
              fontFamily: widget.isFormula ? 'monospace' : null,
            ),
          ),
        ),
      // Handwriting canvas — fills the rest. Mounts as a real Fluera-style
      // mini-canvas: 2-finger pinch zoom, 1-finger pan, stylus draws,
      // strokes persist across rebuild + (when persistKey is set) across
      // app launches.
      Expanded(
        child: !_initialStrokesLoaded
            // Wait for the persisted strokes to load before mounting the
            // scratchpad — otherwise we'd render an empty pad and yank
            // the prior strokes in mid-rebuild.
            ? const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : MiniCanvasScratchpad(
                key: _scratchpadKey,
                inkColor: _cyan,
                initialStrokes: _initialStrokes,
                // Auto-save throttled at 1s — survives kill-app crashes
                // mid-session without waiting for the dispose hook. Cloud
                // upload (when opted in) piggybacks via [_persistStrokes].
                onStrokesChanged: (strokes) {
                  // ignore: discarded_futures
                  _persistStrokes(strokes);
                },
                onRecognizedText: (text) {
                  if (!mounted) return;
                  // Recognition over an entire stroke list returns the
                  // full transcript every time — overwrite, don't append.
                  // (HandwritingScratchpad appended because it cleared the
                  // strokes after each pass; we keep them, so appending
                  // would duplicate the recognized words on every redraw.)
                  setState(() {
                    _answerCtrl.text = text;
                    _answerCtrl.selection = TextSelection.fromPosition(
                      TextPosition(offset: _answerCtrl.text.length),
                    );
                  });
                },
              ),
      ),
    ]);
  }

  Widget _buildKeyboardArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _cyan.withValues(alpha: 0.22)),
      ),
      child: TextField(
        controller: _answerCtrl,
        focusNode: _keyboardFocus,
        autofocus: true,
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          height: 1.5,
          fontFamily: widget.isFormula ? 'monospace' : null,
        ),
        decoration: InputDecoration(
          hintText: widget.isFormula
              ? FlueraLocalizations.of(context)!.exam_answer_writeFormulaHint
              : FlueraLocalizations.of(context)!.exam_answer_writeAnswerHint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.28)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }
}
