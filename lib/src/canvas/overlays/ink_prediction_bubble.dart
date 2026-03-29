import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/ink_prediction_service.dart';

// =============================================================================
// 🔮 INK PREDICTION BUBBLE v3 — Premium autocomplete overlay
//
// v3 ENHANCEMENTS:
//   ✅ Smart positioning (LTR → right of anchor, RTL → left)
//   ✅ Tab-to-accept keyboard shortcut via FocusNode
//   ✅ Haptic tick when prediction label changes
//   ✅ Multi-candidate chips, ghost suffix, confidence bar (from v2)
//   ✅ Auto-fade after 2.5s with graceful exit animation
// =============================================================================

class InkPredictionBubble extends StatefulWidget {
  /// Screen-space anchor position (end of last stroke).
  final Offset anchor;

  /// The prediction to display.
  final InkPrediction prediction;

  /// Writing direction for smart positioning.
  final WritingDirection writingDirection;

  /// The portion of text the user has already written (for ghost suffix).
  final String? writtenPrefix;

  /// Called when user accepts a prediction candidate.
  final ValueChanged<String> onAccept;

  /// Called when user dismisses.
  final VoidCallback onDismiss;

  const InkPredictionBubble({
    super.key,
    required this.anchor,
    required this.prediction,
    this.writingDirection = WritingDirection.ltr,
    this.writtenPrefix,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  State<InkPredictionBubble> createState() => _InkPredictionBubbleState();
}

class _InkPredictionBubbleState extends State<InkPredictionBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  Timer? _autoFadeTimer;
  bool _expanded = false;

  /// Focus node for Tab-to-accept keyboard shortcut.
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    // Slide direction depends on writing direction
    final isRtl = widget.writingDirection == WritingDirection.rtl;

    _scaleAnim = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _fadeAnim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _slideAnim = Tween(
      begin: Offset(isRtl ? 8.0 : -8.0, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
    _startAutoFade();

    // Request focus for Tab shortcut (non-intrusive — doesn't steal keyboard)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _startAutoFade() {
    _autoFadeTimer?.cancel();
    _autoFadeTimer = Timer(const Duration(milliseconds: 4000), () {
      if (mounted && !_expanded) {
        _controller.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant InkPredictionBubble old) {
    super.didUpdateWidget(old);
    if (old.prediction.label != widget.prediction.label) {
      // ✨ Haptic tick on prediction change
      HapticFeedback.selectionClick();
      _startAutoFade();
      if (!_controller.isAnimating) {
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _autoFadeTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Handle keyboard events (Tab to accept, Escape to dismiss).
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      HapticFeedback.lightImpact();
      widget.onAccept(widget.prediction.label);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isRtl = widget.writingDirection == WritingDirection.rtl;

    // ── Smart positioning: BELOW or ABOVE based on screen position ────
    double left, top;
    final isLowerHalf = widget.anchor.dy > screenSize.height * 0.6;
    left = widget.anchor.dx - 80;
    if (isLowerHalf) {
      // Near bottom → show ABOVE
      top = widget.anchor.dy - 70;
    } else {
      // Normal → show BELOW
      top = widget.anchor.dy + 40;
    }

    // Clamp to screen bounds
    left = left.clamp(8.0, screenSize.width - 310);
    top = top.clamp(8.0, screenSize.height - 80);

    return Positioned(
      left: left,
      top: top,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeAnim.value,
              child: Transform.translate(
                offset: _slideAnim.value,
                child: Transform.scale(
                  scale: _scaleAnim.value,
                  alignment:
                      isRtl ? Alignment.centerRight : Alignment.centerLeft,
                  child: child,
                ),
              ),
            );
          },
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity!.abs() > 100) {
                HapticFeedback.lightImpact();
                widget.onDismiss();
              }
            },
            child: Column(
              crossAxisAlignment: isRtl
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMainBubble(),
                // Show candidate chips directly if > 1 candidate
                if (widget.prediction.candidates.length > 1)
                  _buildCandidateChips(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Main Bubble ──────────────────────────────────────────────────────────

  Widget _buildMainBubble() {
    final label = widget.prediction.label;
    final confidence = widget.prediction.confidence;
    final hasCandidates = widget.prediction.candidates.length > 1;

    // Ghost suffix
    String displayText = label;
    String? ghostPrefix;
    if (widget.writtenPrefix != null &&
        widget.writtenPrefix!.isNotEmpty &&
        label.toLowerCase().startsWith(widget.writtenPrefix!.toLowerCase())) {
      ghostPrefix = widget.writtenPrefix!;
      displayText = label.substring(widget.writtenPrefix!.length);
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onAccept(label);
      },
      onLongPress: hasCandidates
          ? () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
              _autoFadeTimer?.cancel();
            }
          : null,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xCC1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Color.lerp(
              const Color(0x20A78BFA),
              const Color(0x80A78BFA),
              confidence.clamp(0.0, 1.0),
            )!,
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0x30A78BFA).withValues(
                alpha: 0.15 + confidence * 0.25,
              ),
              blurRadius: 16,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🔮 Prediction icon
            const Icon(
              Icons.auto_fix_high,
              color: Color(0xFFA78BFA),
              size: 15,
            ),
            const SizedBox(width: 8),

            // Ghost prefix + completion suffix
            Flexible(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    if (ghostPrefix != null)
                      TextSpan(
                        text: ghostPrefix,
                        style: const TextStyle(
                          color: Color(0x80FFFFFF),
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.2,
                        ),
                      ),
                    TextSpan(
                      text: displayText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Candidate expand
            if (hasCandidates) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _expanded = !_expanded);
                  if (_expanded) _autoFadeTimer?.cancel();
                },
                child: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x30A78BFA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.prediction.candidates.length}',
                          style: const TextStyle(
                            color: Color(0xFFA78BFA),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Icon(
                          Icons.expand_more,
                          color: Color(0xFFA78BFA),
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(width: 7),

            // Confidence mini-bar
            SizedBox(
              width: 3,
              height: 18,
              child: CustomPaint(
                painter: _ConfidenceBarPainter(confidence),
              ),
            ),

            const SizedBox(width: 6),

            // Accept indicator with Tab hint
            Tooltip(
              message: 'Tab per accettare',
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Color(0x30A78BFA),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.keyboard_tab_rounded,
                  color: Color(0xFFA78BFA),
                  size: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Candidate Chips ────────────────────────────────────────────────────

  Widget _buildCandidateChips() {
    final candidates = widget.prediction.topCandidates(max: 5);
    if (candidates.length <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (int i = 0; i < candidates.length; i++)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onAccept(candidates[i]);
              },
              child: AnimatedContainer(
                duration: Duration(milliseconds: 200 + i * 50),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: i == 0
                      ? const Color(0x50A78BFA)
                      : const Color(0x301A1A2E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: i == 0
                        ? const Color(0x80A78BFA)
                        : const Color(0x20A78BFA),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  candidates[i],
                  style: TextStyle(
                    color: i == 0
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                    fontWeight: i == 0 ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Confidence Bar Painter ──────────────────────────────────────────────────

class _ConfidenceBarPainter extends CustomPainter {
  final double confidence;

  _ConfidenceBarPainter(this.confidence);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0x20FFFFFF),
    );

    final fillHeight = size.height * confidence.clamp(0.0, 1.0);
    final fillColor = Color.lerp(
      const Color(0xFFFF6B6B),
      const Color(0xFF51CF66),
      confidence.clamp(0.0, 1.0),
    )!;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height - fillHeight, size.width, fillHeight),
        const Radius.circular(2),
      ),
      Paint()..color = fillColor,
    );
  }

  @override
  bool shouldRepaint(covariant _ConfidenceBarPainter old) =>
      old.confidence != confidence;
}
