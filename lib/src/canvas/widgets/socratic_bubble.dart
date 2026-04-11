import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ai/socratic/socratic_model.dart';
import 'socratic_info_screen.dart';

/// 🔶 SOCRATIC BUBBLE — Spatially-anchored question bubble on the canvas.
///
/// Spec: P3-09 — "Le domande appaiono come bolle semi-trasparenti ancorate
/// spazialmente accanto ai nodi rilevanti."
///
/// Visual states:
///   🟠 active         — amber pulse (P3-30)
///   🟢 correct        — green border
///   🔴 wrongHighConf  — red pulsing shock (P3-21)
///   🟡 wrongLowConf   — amber light
///   ⬛ belowZPD       — dark grey
///   ⬜ skipped        — transparent
///
/// Features:
///   - Leader line from bubble to cluster centroid
///   - Confidence slider (5 dots, P3-17)
///   - Breadcrumb button (💡, P3-24)
///   - Swipe to dismiss (P3-15)
///   - Self-eval buttons (after confidence set)
class SocraticBubble extends StatefulWidget {
  final SocraticQuestion question;
  final Offset screenPosition;
  final bool isActiveQuestion;
  final VoidCallback? onSetConfidence;
  final ValueChanged<int>? onConfidenceSelected;
  final ValueChanged<bool>? onSelfEval;
  final VoidCallback? onRequestBreadcrumb;
  final VoidCallback? onSkip;
  final VoidCallback? onNext;
  final String? currentBreadcrumbText;
  final int breadcrumbsUsed;
  final bool canRequestBreadcrumb;
  final int currentIndex;
  final int totalQuestions;

  const SocraticBubble({
    super.key,
    required this.question,
    required this.screenPosition,
    this.isActiveQuestion = false,
    this.onSetConfidence,
    this.onConfidenceSelected,
    this.onSelfEval,
    this.onRequestBreadcrumb,
    this.onSkip,
    this.onNext,
    this.currentBreadcrumbText,
    this.breadcrumbsUsed = 0,
    this.canRequestBreadcrumb = false,
    this.currentIndex = 0,
    this.totalQuestions = 1,
  });

  @override
  State<SocraticBubble> createState() => _SocraticBubbleState();
}

class _SocraticBubbleState extends State<SocraticBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  // Drag offset — allows user to move the bubble anywhere
  Offset _dragOffset = Offset.zero;
  bool _hasBeenDragged = false;

  // Colors per status.
  static const _amberColor = Color(0xFFFFB300);
  static const _greenColor = Color(0xFF66BB6A);
  static const _redColor   = Color(0xFFEF5350);
  static const _yellowColor = Color(0xFFFFD54F);
  static const _greyColor  = Color(0xFF546E7A);
  static const _bubbleBg   = Color(0xE60A0A1A);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color get _statusColor => switch (widget.question.status) {
    SocraticBubbleStatus.active ||
    SocraticBubbleStatus.awaitingConfidence ||
    SocraticBubbleStatus.awaitingAnswer => _amberColor,
    SocraticBubbleStatus.correct ||
    SocraticBubbleStatus.correctLowConf => _greenColor,
    SocraticBubbleStatus.wrongHighConf => _redColor,
    SocraticBubbleStatus.wrongLowConf => _yellowColor,
    SocraticBubbleStatus.skipped => Colors.white54,
    SocraticBubbleStatus.belowZPD => _greyColor,
  };

  bool get _isResolved => widget.question.isResolved;
  bool get _isShock =>
      widget.question.status == SocraticBubbleStatus.wrongHighConf;
  bool get _showConfidenceSlider =>
      widget.isActiveQuestion &&
      (widget.question.status == SocraticBubbleStatus.active ||
       widget.question.status == SocraticBubbleStatus.awaitingConfidence);
  bool get _showSelfEval =>
      widget.isActiveQuestion &&
      widget.question.status == SocraticBubbleStatus.awaitingAnswer;

  @override
  Widget build(BuildContext context) {
    final pos = widget.screenPosition;
    final color = _statusColor;
    final isActive = widget.isActiveQuestion && !_isResolved;

    const bubbleWidth = 260.0;
    final screenSize = MediaQuery.of(context).size;
    final topSafeArea = MediaQuery.of(context).padding.top;
    const toolbarHeight = 56.0;
    final minY = topSafeArea + toolbarHeight + 12;

    double bubbleX, bubbleY;
    if (_hasBeenDragged) {
      // User dragged — use their position
      bubbleX = _dragOffset.dx;
      bubbleY = _dragOffset.dy;
    } else {
      // Default: center-right of the screen, safe from toolbar
      bubbleX = screenSize.width - bubbleWidth - 16;
      bubbleY = minY + 8;
    }

    // Always clamp to screen bounds
    bubbleX = bubbleX.clamp(8.0, screenSize.width - bubbleWidth - 8);
    bubbleY = bubbleY.clamp(minY, screenSize.height - 200);

    return Positioned(
      left: bubbleX,
      top: bubbleY,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _hasBeenDragged = true;
            _dragOffset = Offset(
              (bubbleX + details.delta.dx),
              (bubbleY + details.delta.dy),
            );
          });
        },
        child: Dismissible(
          key: ValueKey('socratic_dismiss_${widget.question.id}'),
          direction: _isResolved
              ? DismissDirection.none
              : DismissDirection.horizontal,
          onDismissed: (_) => widget.onSkip?.call(),
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final t = _pulseController.value;
            final borderWidth = _isShock
                ? 2.0 + math.sin(t * math.pi * 3) * 1.5
                : isActive
                    ? 1.0 + math.sin(t * math.pi) * 0.5
                    : 1.0;
            final glowRadius = _isShock
                ? 12.0 + t * 8.0
                : isActive
                    ? 4.0 + t * 4.0
                    : 0.0;

            return Container(
              width: bubbleWidth,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _bubbleBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: color.withValues(alpha: _isShock ? 0.9 : 0.5),
                  width: borderWidth,
                ),
                boxShadow: [
                  if (glowRadius > 0)
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: glowRadius,
                      spreadRadius: glowRadius * 0.3,
                    ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header: type badge + skip button.
                  _buildHeader(color),
                  const SizedBox(height: 8),

                  // Question text (P3-10: only the question, never the answer).
                  Text(
                    widget.question.text,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),

                  // Breadcrumb (if any revealed).
                  if (widget.currentBreadcrumbText != null) ...[
                    const SizedBox(height: 8),
                    _buildBreadcrumb(),
                  ],

                  // Status-specific UI.
                  if (_showConfidenceSlider) ...[
                    const SizedBox(height: 12),
                    _buildConfidenceSlider(),
                  ],

                  if (_showSelfEval) ...[
                    const SizedBox(height: 12),
                    _buildSelfEvalButtons(),
                  ],

                  // Resolved status badge.
                  if (_isResolved) ...[
                    const SizedBox(height: 8),
                    _buildStatusBadge(color),
                    const SizedBox(height: 8),
                    _buildNextButton(),
                  ],

                  // Breadcrumb button (if available and not resolved).
                  if (!_isResolved &&
                      widget.canRequestBreadcrumb &&
                      widget.isActiveQuestion) ...[
                    const SizedBox(height: 8),
                    _buildBreadcrumbButton(),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────

  Widget _buildHeader(Color color) {
    return Row(
      children: [
        // Question type badge.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.question.typeLabel,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        // Session progress
        if (widget.totalQuestions > 1)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              '${widget.currentIndex + 1}/${widget.totalQuestions}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const Spacer(),
        // Info button
        GestureDetector(
          onTap: () => SocraticInfoScreen.show(context),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.help_outline_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ),
        // Skip/dismiss button (P3-15).
        if (!_isResolved && widget.isActiveQuestion)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onSkip?.call();
            },
            child: Icon(
              Icons.close,
              size: 16,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }

  // ── Confidence Slider (P3-17) ──────────────────────────────────────────

  Widget _buildConfidenceSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quanto sei sicuro di poter rispondere? (1-5)',
          style: TextStyle(
            color: _amberColor.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: List.generate(5, (i) {
            final level = i + 1;
            final selected = widget.question.confidence == level;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  // Progressive haptic: heavier = more confident
                  if (level >= 4) {
                    HapticFeedback.heavyImpact();
                  } else if (level == 3) {
                    HapticFeedback.mediumImpact();
                  } else {
                    HapticFeedback.lightImpact();
                  }
                  widget.onConfidenceSelected?.call(level);
                },
                child: Container(
                  height: 32,
                  margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: selected
                        ? _amberColor.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? _amberColor.withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$level',
                      style: TextStyle(
                        color: selected
                            ? _amberColor
                            : Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ── Self-Eval Buttons (P3-20) ──────────────────────────────────────────

  Widget _buildSelfEvalButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pensa alla risposta, poi valutati onestamente:',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _evalButton(
                label: '❌ Non sapevo',
                color: _redColor,
                recalled: false,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _evalButton(
                label: '✅ Sapevo',
                color: _greenColor,
                recalled: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _evalButton({
    required String label,
    required Color color,
    required bool recalled,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onSelfEval?.call(recalled);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ── Breadcrumb ─────────────────────────────────────────────────────────

  Widget _buildBreadcrumb() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _amberColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _amberColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.currentBreadcrumbText!,
              style: TextStyle(
                color: _amberColor.withValues(alpha: 0.85),
                fontSize: 11,
                height: 1.35,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbButton() {
    final label = switch (widget.breadcrumbsUsed) {
      0 => 'Indizio',
      1 => 'Altro indizio',
      2 => 'Ultimo indizio',
      _ => 'Esauriti',
    };

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onRequestBreadcrumb?.call();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 14,
            color: _amberColor.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: _amberColor.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Next Button ────────────────────────────────────────────────────────

  Widget _buildNextButton() {
    if (widget.onNext == null) return const SizedBox.shrink();

    final isLast = widget.currentIndex >= widget.totalQuestions - 1;
    final label = isLast ? 'Fine sessione' : 'Avanti →';

    return GestureDetector(
      onTap: () {
        // Haptic varies by outcome
        if (_isShock) {
          HapticFeedback.heavyImpact();
        } else if (widget.question.wasWrong) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.lightImpact();
        }
        widget.onNext?.call();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ── Status Badge ───────────────────────────────────────────────────────

  Widget _buildStatusBadge(Color color) {
    final q = widget.question;
    final conf = q.confidence ?? 3;

    // ── Determine feedback based on confidence × correctness ──────────
    final (String emoji, String title, String message, Color feedbackColor) =
        switch (q.status) {
      // ✅ Correct + HIGH confidence → brief reinforcement
      SocraticBubbleStatus.correct => (
        '💪',
        'Solido!',
        'Il tuo ricordo è stabile. Continua così.',
        _greenColor,
      ),

      // 🟢 Correct + LOW confidence → metacognitive calibration
      SocraticBubbleStatus.correctLowConf => (
        '🎯',
        'Sapevi più di quanto pensassi!',
        'La tua confidenza era ${conf}/5, ma hai risposto correttamente. '
            'Questo concetto è più solido di quanto credi — fidati di più '
            'del tuo ricordo.',
        const Color(0xFF4CAF50),
      ),

      // 🟡 Wrong + LOW confidence → expected gap, gentle
      SocraticBubbleStatus.wrongLowConf => (
        '📌',
        'Lacuna nota',
        'Sapevi di non saperlo — è già consapevolezza. '
            'Rileggi i tuoi appunti su questo argomento e ritornerà.',
        _amberColor,
      ),

      // ⚡ Wrong + HIGH confidence → HYPERCORRECTION (most powerful!)
      SocraticBubbleStatus.wrongHighConf => (
        '⚡',
        'Momento di apprendimento!',
        'Eri sicuro al ${conf}/5, ma c\'è qualcosa da rivedere. '
            'Le ricerche mostrano che gli errori ad alta confidenza si '
            'correggono MEGLIO — questo momento vale doppio. '
            'Rileggi attentamente i tuoi appunti.',
        _redColor,
      ),

      SocraticBubbleStatus.skipped => (
        '⏭️',
        'Saltata',
        '',
        Colors.grey,
      ),

      SocraticBubbleStatus.belowZPD => (
        '⬛',
        'Fuori dalla tua zona',
        'Questa domanda era fuori portata. Tornerà quando sarai pronto.',
        Colors.grey,
      ),

      _ => ('', '', '', Colors.grey),
    };

    if (title.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: feedbackColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: feedbackColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: feedbackColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
