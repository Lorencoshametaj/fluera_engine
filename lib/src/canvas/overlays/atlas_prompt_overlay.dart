import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/fluera_localizations.dart';

/// 🌌 ATLAS PROMPT OVERLAY — Floating AI command input.
///
/// Glassmorphism text field that appears near the selection when the user
/// activates Atlas from the radial menu. Features:
/// - Animated fade+scale entrance
/// - True glassmorphism with BackdropFilter
/// - Dynamic context-aware suggestion pills (E)
/// - Auto-focus with single-line input
/// - Contextual loading phases (C)
/// - Response preview with explanation text
class AtlasPromptOverlay extends StatefulWidget {
  /// Whether there are selected nodes (changes hint text).
  final bool hasSelection;

  /// Number of selected nodes (shown in header).
  final int selectedNodeCount;

  /// Called when the user submits a prompt.
  ///
  /// [forceCluster] is true when the prompt comes from a preset chip
  /// (Organizza / Layout / Collega / Colora) that must operate on
  /// concept clusters rather than individual nodes. When false the
  /// caller may infer mode from canvas state. See F8.
  final void Function(String prompt, {bool forceCluster}) onSubmit;

  /// Called when the user dismisses the overlay.
  final VoidCallback onDismiss;

  /// Whether Atlas is currently processing.
  final bool isLoading;

  /// (C) Current loading phase description.
  final String? loadingPhase;

  /// Response explanation from Atlas (shown after completion).
  final String? responseText;

  /// (E) Types of nodes in selection for dynamic suggestions.
  /// Expected values: 'stroke', 'text', 'image', 'latex', 'shape', 'pdf'.
  final Set<String> selectedNodeTypes;

  const AtlasPromptOverlay({
    super.key,
    this.hasSelection = false,
    this.selectedNodeCount = 0,
    required this.onSubmit,
    required this.onDismiss,
    this.isLoading = false,
    this.loadingPhase,
    this.responseText,
    this.selectedNodeTypes = const {},
  });

  @override
  State<AtlasPromptOverlay> createState() => _AtlasPromptOverlayState();
}

class _AtlasPromptOverlayState extends State<AtlasPromptOverlay>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  bool _submitted = false;

  static const _accent = Color(0xFF00E5FF); // Atlas neon cyan

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animController.forward();

    // Auto-focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.isLoading) {
        _focusNode.requestFocus();
      }
    });
  }

  void _doSubmit([String? overrideText, bool forceCluster = false]) {
    if (_submitted || widget.isLoading) return;
    final text = (overrideText ?? _controller.text).trim();
    if (text.isEmpty) return;
    _submitted = true;
    HapticFeedback.mediumImpact();
    widget.onSubmit(text, forceCluster: forceCluster);
  }

  void _dismiss() {
    if (_submitted) return;
    _submitted = true;
    widget.onDismiss();
    _animController.reverse();
  }

  /// Bottom sheet that explains the default command chips. Surfaced from
  /// the (i) icon in the header. Users frequently confuse this overlay
  /// with the conversational "Chiedi a Fluera AI" surface; the footer of
  /// the sheet points them there for content questions.
  void _showHelpSheet() {
    HapticFeedback.selectionClick();
    final l10n = FlueraLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12122A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                l10n?.atlasPrompt_helpTitle ?? 'Atlas commands',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n?.atlasPrompt_helpIntro ??
                    'Atlas reshapes the canvas — it does not produce content to read.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l10n?.atlasPrompt_helpDefaults ??
                    'Without a selection, the quick commands work on concept CLUSTERS.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n?.atlasPrompt_helpHow ??
                    'With a lasso selection, type-specific commands appear:',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              _helpRow(l10n?.atlasPrompt_help_text
                  ?? '📝 Text — Translate.'),
              _helpRow(l10n?.atlasPrompt_help_latex
                  ?? '🧮 Formulas — Solve, Graph.'),
              _helpRow(l10n?.atlasPrompt_help_image
                  ?? '🖼️ Images — Describe.'),
              _helpRow(l10n?.atlasPrompt_help_pdf
                  ?? '📄 PDF — Connect to notes.'),
              _helpRow(l10n?.atlasPrompt_help_stroke
                  ?? '✍️ Handwriting — Convert to text, Analyze.'),
              const SizedBox(height: 12),
              Text(
                l10n?.atlasPrompt_helpFooter ??
                    'You can also write a free-form command in the text box above.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _helpRow(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 13,
            height: 1.5,
          ),
        ),
      );

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // (E) Dynamic suggestion pills — context-aware based on selection types
  // ─────────────────────────────────────────────────────────────────────────

  List<_SuggestionItem> _buildDynamicSuggestions() {
    final types = widget.selectedNodeTypes;
    final items = <_SuggestionItem>[];

    if (!widget.hasSelection || types.isEmpty) {
      // No selection → CLUSTER-mode preset chips.
      //
      // These chips dispatch in cluster mode (F8) so commands like
      // "Organizza" operate on concept groups rather than individual
      // strokes — fixing the scatter-the-handwriting bug. Each chip's
      // prompt is phrased in terms of "cluster" so the AI's response
      // stays aligned with the cluster system prompt.
      return const [
        _SuggestionItem(
          '🗺️',
          'Organizza',
          'organizza i cluster visibili in una mappa concettuale per topic',
          forceCluster: true,
        ),
        _SuggestionItem(
          '📐',
          'Layout',
          'allinea e distribuisci i cluster in modo pulito',
          forceCluster: true,
        ),
        _SuggestionItem(
          '🔗',
          'Collega',
          'connetti cluster con relazioni semantiche evidenti',
          forceCluster: true,
        ),
        _SuggestionItem(
          '🎨',
          'Colora',
          'colora i cluster per topic',
          forceCluster: true,
        ),
      ];
    }

    // Stroke-specific
    if (types.contains('stroke')) {
      items.add(const _SuggestionItem('✍️', 'Converti', '_CONVERT_'));
      items.add(const _SuggestionItem('🔍', 'Analizza', '_ANALYZE_'));
    }

    // Text-specific. "Riassumi" removed: would produce a passive read of
    // AI-generated content (§3 Generation, §11 Fluency).
    if (types.contains('text')) {
      items.add(const _SuggestionItem('🌐', 'Traduci', 'translate the selected text to English'));
    }

    // LaTeX-specific. "Spiega" removed: explanation is passive consumption
    // (§6 Levels of Processing). "Risolvi" kept as a workflow utility but
    // worth revisiting — solving for the student trades short-term help for
    // long-term Productive Failure (T4).
    if (types.contains('latex')) {
      items.add(const _SuggestionItem('🧮', 'Risolvi', 'solve this equation step by step'));
      items.add(const _SuggestionItem('📊', 'Grafica', 'graph this function'));
    }

    // Image-specific
    if (types.contains('image')) {
      items.add(const _SuggestionItem('🏷️', 'Descrivi', 'describe what is in this image'));
    }

    // PDF-specific. "Riassumi sul PDF" removed: violates
    // feedback_pdf_is_source_not_ai_input — the PDF is the source, not an
    // input the AI feeds back as a digested summary.
    if (types.contains('pdf')) {
      items.add(const _SuggestionItem('🔗', 'Collega', 'find connections between this PDF and the visible notes'));
    }

    // Universal actions (always available when selection exists).
    // "Brainstorm" removed: the AI would generate ideas the student reads
    // passively (§3 Generation Effect).
    if (!items.any((i) => i.label == 'Analizza')) {
      items.add(const _SuggestionItem('🔍', 'Analizza', '_ANALYZE_'));
    }
    items.add(const _SuggestionItem('🔗', 'Connetti', 'find and create connections between these nodes'));

    // Deduplicate by label (keep first)
    final seen = <String>{};
    return items.where((i) => seen.add(i.label)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──
                _buildHeader(),
                const SizedBox(height: 6),

                // ── Input or Loading ──
                if (widget.isLoading)
                  _buildLoadingState()
                else if (widget.responseText != null)
                  _buildResponse()
                else ...[
                  _buildInput(),
                  const SizedBox(height: 6),
                  _buildSuggestions(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xCC0D0D14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _accent.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              // Atlas glow icon
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      _accent.withValues(alpha: 0.4),
                      _accent.withValues(alpha: 0.05),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: _accent,
                ),
              ),
              const SizedBox(width: 8),
              // Title — neutral voice, no brand character.
              // "Comandi" (was "Chiedi") makes the action-only nature of this
              // overlay explicit: it sends commands that act on canvas nodes,
              // not conversational questions (those live in the Chiedi a
              // Fluera AI chat overlay).
              Text(
                FlueraLocalizations.of(context)?.atlasPrompt_title ?? 'Commands',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _accent,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              // Info button — explains what the command chips do.
              // Added because the chips ("Organizza", "Layout", "Collega",
              // "Colora") read as commands of unclear scope; the bottom
              // sheet clarifies that Atlas reshapes the canvas vs the
              // separate "Chiedi a Fluera AI" surface that converses.
              Tooltip(
                message: FlueraLocalizations.of(context)?.atlasPrompt_helpTooltip
                    ?? 'What do these commands do?',
                child: GestureDetector(
                  onTap: _showHelpSheet,
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Selection badge
              if (widget.hasSelection)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.selectedNodeCount} nodi',
                    style: TextStyle(
                      fontSize: 11,
                      color: _accent.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              // Close button
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _dismiss,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xCC0D0D14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _accent.withValues(alpha: 0.25),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.08),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: 2,
                  minLines: 1,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                  ),
                  cursorColor: _accent,
                  cursorWidth: 1.5,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    isCollapsed: true,
                    hintText: widget.hasSelection
                        ? (FlueraLocalizations.of(context)?.atlasPrompt_hintWithSelection ?? 'What do you want to do with these nodes?')
                        : (FlueraLocalizations.of(context)?.atlasPrompt_hintNoSelection ?? 'What do you want to do on the canvas?'),
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  onSubmitted: (_) => _doSubmit(),
                  textInputAction: TextInputAction.send,
                ),
              ),
              const SizedBox(width: 8),
              // Send button
              GestureDetector(
                onTap: _doSubmit,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _accent.withValues(alpha: 0.4),
                        _accent.withValues(alpha: 0.2),
                      ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_upward_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// (E) Dynamic suggestion pills built from selection context.
  Widget _buildSuggestions() {
    final suggestions = _buildDynamicSuggestions();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x990D0D14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
              width: 0.5,
            ),
          ),
          child: suggestions.isEmpty
              ? Row(children: [
                  Icon(Icons.touch_app_rounded,
                      size: 14, color: Colors.white.withValues(alpha: 0.4)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      FlueraLocalizations.of(context)
                              ?.atlasPrompt_emptySelectionHint ??
                          'Select nodes with the lasso to see commands.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.55),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ])
              : Wrap(
            spacing: 5,
            runSpacing: 4,
            children: suggestions.map((item) {
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _doSubmit(item.prompt, item.forceCluster);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _accent.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    '${item.icon} ${item.label}',
                    style: TextStyle(
                      fontSize: 12,
                      color: _accent.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// (C) Contextual loading state — shows current phase.
  Widget _buildLoadingState() {
    final phaseText = widget.loadingPhase ?? 'Analizzo\u2026';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xCC0D0D14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _accent.withValues(alpha: 0.3),
              width: 1.0,
            ),
          ),
          child: Column(
            children: [
              // Pulsing scanner animation
              SizedBox(
                width: 40,
                height: 40,
                child: _AtlasPulseAnimation(color: _accent),
              ),
              const SizedBox(height: 12),
              // (C) Animated phase text — cross-fades on change
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  phaseText,
                  key: ValueKey(phaseText),
                  style: TextStyle(
                    fontSize: 13,
                    color: _accent.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponse() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xCC0D0D14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _accent.withValues(alpha: 0.3),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: const Color(0xFF69F0AE),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Fatto!',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF69F0AE),
                    ),
                  ),
                ],
              ),
              if (widget.responseText != null && widget.responseText!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  widget.responseText!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Dynamic suggestion pill data model (E)
// =============================================================================

class _SuggestionItem {
  final String icon;
  final String label;
  final String prompt;

  /// When true, the prompt is dispatched in CLUSTER mode regardless of
  /// the current selection. Default false: existing chips operate on
  /// the user's lasso selection at node granularity.
  final bool forceCluster;

  const _SuggestionItem(
    this.icon,
    this.label,
    this.prompt, {
    this.forceCluster = false,
  });
}

// =============================================================================
// Pulsing animation for loading state
// =============================================================================

/// Pulsing concentric circles animation for Atlas loading state.
class _AtlasPulseAnimation extends StatefulWidget {
  final Color color;
  const _AtlasPulseAnimation({required this.color});

  @override
  State<_AtlasPulseAnimation> createState() => _AtlasPulseAnimationState();
}

class _AtlasPulseAnimationState extends State<_AtlasPulseAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _PulsePainter(
            progress: _controller.value,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double progress;
  final Color color;

  _PulsePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Draw 3 concentric expanding/fading circles
    for (int i = 0; i < 3; i++) {
      final phase = (progress + i * 0.33) % 1.0;
      final radius = maxRadius * phase;
      final opacity = (1.0 - phase) * 0.5;

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(center, radius, paint);
    }

    // Center dot
    canvas.drawCircle(
      center,
      3,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
