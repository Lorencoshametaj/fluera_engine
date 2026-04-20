import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/dictionary_lookup_service.dart';
import '../../../services/lookup_attempt_store.dart';

// =============================================================================
// 📖 DICTIONARY LOOKUP SHEET — Paraphrase-first, self-assessed, rewrite-closed
//
// Three-phase pedagogical flow:
//   1. CHALLENGE  (§3 Effetto Generazione + §5 Desirable Difficulties)
//      Student writes a 1-line paraphrase and commits to a 1-5 confidence.
//
//   2. REVEAL + SELF-ASSESSMENT  (§4 Ipercorrezione + T1 Metacognition)
//      Paraphrase is pinned with the confidence badge, definition appears
//      etymology-first (§6 Deep Processing). The student grades themselves:
//      correct / partial / wrong. High-confidence + wrong = heavy haptic so
//      the shock is felt (amigdala-hippocampus tagging per §4).
//
//   3. REWRITE LOOP  (§3 Generazione on the corrected answer)
//      A second text field appears: "Now rewrite it in your own words."
//      This turns the lookup from passive reading into full retrieval +
//      re-encoding. Save commits the full attempt to LookupAttemptStore.
//
// Every terminal action (save, skip, sheet dismissal) persists a record so
// the future spaced-review surface (§1 Ebbinghaus) has data to consume.
// =============================================================================

class DictionaryLookupSheet extends StatefulWidget {
  final String word;

  const DictionaryLookupSheet({super.key, required this.word});

  /// Show the lookup sheet for a word.
  static Future<void> show(BuildContext context, String word) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DictionaryLookupSheet(word: word),
    );
  }

  @override
  State<DictionaryLookupSheet> createState() => _DictionaryLookupSheetState();
}

class _DictionaryLookupSheetState extends State<DictionaryLookupSheet>
    with SingleTickerProviderStateMixin {
  // ── Definition fetch ────────────────────────────────────────────────────
  DictionaryLookupResult? _result;
  bool _loading = true;
  String? _error;

  // ── Phase 1: challenge ──────────────────────────────────────────────────
  final TextEditingController _paraphraseCtrl = TextEditingController();
  final FocusNode _paraphraseFocus = FocusNode();
  int _confidence = 3;
  bool _revealed = false;
  String? _submittedParaphrase;
  int? _submittedConfidence;

  // ── Phase 2: self-assessment ────────────────────────────────────────────
  LookupAssessment? _assessment;

  // ── Phase 3: rewrite loop ───────────────────────────────────────────────
  final TextEditingController _rewriteCtrl = TextEditingController();
  final FocusNode _rewriteFocus = FocusNode();

  // ── Finalization guard (record once) ────────────────────────────────────
  bool _recorded = false;

  static const List<String> _confidenceLabels = [
    'Guessing', 'Unsure', 'Maybe', 'Confident', 'Certain',
  ];

  @override
  void initState() {
    super.initState();
    _lookUp();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _paraphraseFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    // Record an incomplete attempt if the user dismissed the sheet without
    // an explicit terminal action — we still want the metacognitive trace.
    _finalizeIfNeeded(dismissed: true);
    _paraphraseCtrl.dispose();
    _paraphraseFocus.dispose();
    _rewriteCtrl.dispose();
    _rewriteFocus.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    try {
      final result = await DictionaryLookupService.instance.lookUp(widget.word);
      if (mounted) {
        setState(() {
          _result = result;
          _loading = false;
          if (result == null || !result.hasDefinitions) {
            _error = 'No reference definition found for "${widget.word}"';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not connect to dictionary';
        });
      }
    }
  }

  // ── Transitions ────────────────────────────────────────────────────────

  void _reveal() {
    final text = _paraphraseCtrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.mediumImpact();
    _paraphraseFocus.unfocus();
    setState(() {
      _submittedParaphrase = text;
      _submittedConfidence = _confidence;
      _revealed = true;
    });
  }

  void _remindMeLater() {
    HapticFeedback.selectionClick();
    _finalizeIfNeeded(skipped: true);
    if (mounted) Navigator.of(context).pop();
  }

  void _assess(LookupAssessment value) {
    // High-confidence + wrong → heavy haptic. The amigdala-hippocampus shock
    // of §4 is the entire point of the metacognitive slider: do not soften.
    final conf = _submittedConfidence ?? 0;
    if (value == LookupAssessment.wrong && conf >= 4) {
      HapticFeedback.heavyImpact();
    } else if (value == LookupAssessment.partial) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    setState(() => _assessment = value);
    // Give the rewrite field focus after the UI settles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rewriteFocus.requestFocus();
    });
  }

  void _saveAndClose() {
    HapticFeedback.lightImpact();
    _rewriteFocus.unfocus();
    _finalizeIfNeeded();
    if (mounted) Navigator.of(context).pop();
  }

  void _setConfidence(int value) {
    if (_confidence == value) return;
    HapticFeedback.selectionClick();
    setState(() => _confidence = value);
  }

  /// Persist one attempt record to [LookupAttemptStore].
  /// Called at most once per sheet instance.
  void _finalizeIfNeeded({bool skipped = false, bool dismissed = false}) {
    if (_recorded) return;
    _recorded = true;

    // If the sheet was dismissed before any engagement, don't record noise.
    if (dismissed && !_revealed && _paraphraseCtrl.text.trim().isEmpty) {
      return;
    }

    final rewrite = _rewriteCtrl.text.trim();
    final attempt = LookupAttempt(
      word: widget.word,
      timestamp: DateTime.now(),
      paraphrase: _submittedParaphrase,
      confidence: _submittedConfidence,
      assessment: _assessment,
      improvedParaphrase: rewrite.isEmpty ? null : rewrite,
      skipped: skipped,
    );
    // Fire-and-forget: disk write is debounced inside the store.
    LookupAttemptStore.instance.record(attempt);
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _buildHeader(isDark, showPhonetic: _revealed),
            ),
            const SizedBox(height: 16),
            if (!_revealed)
              Flexible(child: _buildChallenge(isDark))
            else
              Flexible(child: _buildReveal(isDark)),
          ],
        ),
      ),
    );
  }

  // ── Phase 1: Challenge ────────────────────────────────────────────────

  Widget _buildChallenge(bool isDark) {
    final accent = isDark ? Colors.blue[300]! : Colors.blue[600]!;
    final muted = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final canSubmit = _paraphraseCtrl.text.trim().isNotEmpty;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        Text(
          'Before you see the definition — what does it mean to you?',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Write it in your own words — one line is enough.',
          style: TextStyle(fontSize: 12, color: muted, height: 1.3),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _paraphraseCtrl,
          focusNode: _paraphraseFocus,
          maxLines: 2,
          minLines: 1,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _reveal(),
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white : Colors.black87,
            height: 1.4,
          ),
          decoration: InputDecoration(
            hintText: 'Explain it in one line…',
            hintStyle: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF2C2C2E) : Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: accent, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'How sure are you?',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 10),
        _buildConfidenceSegments(isDark, accent),
        const SizedBox(height: 6),
        Text(
          _confidenceLabels[_confidence - 1],
          style: TextStyle(
            fontSize: 12,
            color: accent,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: canSubmit ? _reveal : null,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              disabledBackgroundColor: isDark
                  ? Colors.grey[800]
                  : Colors.grey[300],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Compare with definition',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _remindMeLater,
            style: TextButton.styleFrom(
              foregroundColor: muted,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: const Text(
              'Not ready — remind me later',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfidenceSegments(bool isDark, Color accent) {
    return Row(
      children: List.generate(5, (i) {
        final level = i + 1;
        final active = level <= _confidence;
        final isSelected = level == _confidence;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 4 ? 6 : 0),
            child: Semantics(
              button: true,
              selected: isSelected,
              label: 'Confidence $level of 5, ${_confidenceLabels[i]}',
              child: GestureDetector(
                onTap: () => _setConfidence(level),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 36,
                  decoration: BoxDecoration(
                    color: active
                        ? accent.withValues(alpha: isSelected ? 1.0 : 0.7)
                        : (isDark
                            ? const Color(0xFF2C2C2E)
                            : Colors.grey[200]),
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected
                        ? Border.all(color: accent, width: 2)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$level',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? Colors.white
                          : (isDark ? Colors.grey[500] : Colors.grey[600]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── Phase 2 + 3: Reveal, Self-Assessment, Rewrite ─────────────────────

  Widget _buildReveal(bool isDark) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        if (_submittedParaphrase != null) ...[
          _buildParaphraseCard(isDark),
          const SizedBox(height: 16),
        ],
        if (_loading)
          _buildInlineLoading(isDark)
        else if (_error != null)
          _buildInlineError(isDark)
        else
          ..._buildDefinitionSections(isDark),

        // Gate self-assessment behind a successful definition load so the
        // student has something to compare against.
        if (!_loading && _error == null) ...[
          const SizedBox(height: 20),
          _buildAssessmentBar(isDark),
        ],

        // Rewrite loop appears after the student has graded themselves.
        if (_assessment != null) ...[
          const SizedBox(height: 20),
          _buildRewriteSection(isDark),
        ],
      ],
    );
  }

  Widget _buildParaphraseCard(bool isDark) {
    final conf = _submittedConfidence ?? 3;
    final confColor = _colorForConfidence(conf, isDark);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.blue.withValues(alpha: 0.08)
            : Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.blue.withValues(alpha: 0.2)
              : Colors.blue.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'YOUR PARAPHRASE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isDark ? Colors.blue[300] : Colors.blue[700],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: confColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_confidenceLabels[conf - 1]} · $conf/5',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: confColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _submittedParaphrase!,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black87,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssessmentBar(bool isDark) {
    final muted = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WAS YOUR PARAPHRASE ON TRACK?',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: muted,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _assessmentButton(
                isDark,
                value: LookupAssessment.correct,
                label: 'Correct',
                icon: Icons.check_circle_outline,
                color: isDark ? Colors.green[300]! : Colors.green[700]!,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _assessmentButton(
                isDark,
                value: LookupAssessment.partial,
                label: 'Partial',
                icon: Icons.change_history_outlined,
                color: isDark ? Colors.amber[300]! : Colors.amber[700]!,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _assessmentButton(
                isDark,
                value: LookupAssessment.wrong,
                label: 'Wrong',
                icon: Icons.close_rounded,
                color: isDark ? Colors.redAccent[100]! : Colors.red[700]!,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _assessmentButton(
    bool isDark, {
    required LookupAssessment value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final selected = _assessment == value;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: () => _assess(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.15)
                : (isDark ? const Color(0xFF2C2C2E) : Colors.grey[100]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRewriteSection(bool isDark) {
    final accent = isDark ? Colors.blue[300]! : Colors.blue[600]!;
    final muted = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final prompt = switch (_assessment!) {
      LookupAssessment.correct =>
        'Now rewrite it in your own words — richer than before.',
      LookupAssessment.partial =>
        'Now rewrite it, filling the gap you just spotted.',
      LookupAssessment.wrong =>
        'Now rewrite it correctly, in your own words.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          prompt,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Re-encoding in your own words is what locks it in.',
          style: TextStyle(fontSize: 11, color: muted, height: 1.3),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _rewriteCtrl,
          focusNode: _rewriteFocus,
          maxLines: 3,
          minLines: 2,
          onChanged: (_) => setState(() {}),
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white : Colors.black87,
            height: 1.4,
          ),
          decoration: InputDecoration(
            hintText: 'Rewrite without copying from the definition…',
            hintStyle: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF2C2C2E) : Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: accent, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton(
            onPressed: _rewriteCtrl.text.trim().isEmpty ? null : _saveAndClose,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              disabledBackgroundColor: isDark
                  ? Colors.grey[800]
                  : Colors.grey[300],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Save & close',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _colorForConfidence(int conf, bool isDark) {
    if (conf <= 2) return isDark ? Colors.amber[300]! : Colors.amber[700]!;
    if (conf == 3) return isDark ? Colors.grey[400]! : Colors.grey[600]!;
    return isDark ? Colors.deepOrange[300]! : Colors.deepOrange[700]!;
  }

  List<Widget> _buildDefinitionSections(bool isDark) {
    final result = _result!;
    final widgets = <Widget>[];

    if (result.origin != null) {
      widgets.add(_buildOrigin(result, isDark));
      widgets.add(const SizedBox(height: 16));
    }
    if (result.allSynonyms.isNotEmpty) {
      widgets.add(_buildSynonyms(result, isDark));
      widgets.add(const SizedBox(height: 16));
    }
    widgets.addAll(_buildDefinitions(result, isDark));
    if (result.allAntonyms.isNotEmpty) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(_buildAntonyms(result, isDark));
    }
    return widgets;
  }

  Widget _buildInlineLoading(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: 22, height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: isDark ? Colors.blue[300] : Colors.blue[600],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineError(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 36,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 10),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared sub-widgets ────────────────────────────────────────────────

  Widget _buildHeader(bool isDark, {required bool showPhonetic}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            _result?.word ?? widget.word,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
              letterSpacing: -0.5,
            ),
          ),
        ),
        if (showPhonetic && _result?.phonetic != null) ...[
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _result!.phonetic!,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.blue[300] : Colors.blue[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildDefinitions(
    DictionaryLookupResult result,
    bool isDark,
  ) {
    final grouped = <String, List<WordDefinition>>{};
    for (final def in result.definitions) {
      grouped.putIfAbsent(def.partOfSpeech, () => []).add(def);
    }

    final widgets = <Widget>[];
    for (final entry in grouped.entries) {
      widgets.add(
        Container(
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.purple.withValues(alpha: 0.15)
                : Colors.purple.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            entry.key,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.purple[200] : Colors.purple[700],
              letterSpacing: 0.5,
            ),
          ),
        ),
      );

      for (int i = 0; i < entry.value.length && i < 3; i++) {
        final def = entry.value[i];
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}. ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        def.definition,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.black87,
                          height: 1.4,
                        ),
                      ),
                      if (def.example != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey[800]
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '"${def.example}"',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _buildSynonyms(DictionaryLookupResult result, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Synonyms',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.green[300] : Colors.green[700],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: result.allSynonyms.take(8).map((syn) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                syn,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.green[300] : Colors.green[700],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAntonyms(DictionaryLookupResult result, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Antonyms',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.orange[300] : Colors.orange[700],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: result.allAntonyms.take(6).map((ant) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.orange.withValues(alpha: 0.12)
                    : Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                ant,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.orange[300] : Colors.orange[700],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildOrigin(DictionaryLookupResult result, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Origin',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          result.origin!,
          style: TextStyle(
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: isDark ? Colors.grey[400] : Colors.grey[700],
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
