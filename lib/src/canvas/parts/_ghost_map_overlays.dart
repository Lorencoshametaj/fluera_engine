part of '../fluera_canvas_screen.dart';

/// 🗺️ Ghost Map Overlays — Attempt, Compare, and Explanation bottom sheets.
///
/// Split from _ghost_map.dart for maintainability.
/// See _ghost_map.dart for core trigger/tap logic.
/// See _ghost_map_lifecycle.dart for dismiss/progress/navigation.
extension FlueraGhostMapOverlaysExtension on _FlueraCanvasScreenState {

  /// P4-15: Last pen mode preference (persists across attempts).
  static bool _ghostMapLastPenMode = false;


  // ── ATTEMPT OVERLAY ──────────────────────────────────────────────────────

  /// Show a frosted glass overlay for the student to attempt writing
  /// the missing concept, either by typing or drawing with pen (P4-15).
  void _showGhostAttemptOverlay(GhostNode node) {
    final controller = _ghostMapController;
    final l10n = _l10n;

    controller.startAttempt(node.id);

    final textController = TextEditingController();
    // 🗺️ P4-15: Pen mode state
    // Fix #25: Initialize from last preference
    final penModeNotifier = ValueNotifier(_ghostMapLastPenMode);
    final penStrokes = <List<Offset>>[];
    final penPressures = <List<double>>[]; // Fix #4: pressure per stroke
    List<Offset>? currentPenStroke;
    List<double>? _lastPressures; // Fix #4: current stroke pressures
    double sagomaOpacity = 1.0;
    bool isOcrLoading = false; // Fix #3: loading guard

    // 🗺️ P4-21: Show hypercorrection context if applicable
    final isHypercorrection = node.isHypercorrection;
    final isBelowZPD = node.isBelowZPD;

    // Fix #12+#17: Explicit Timer for live countdown — cancelled on sheet close
    Timer? countdownTimer;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Semantics(
        label: l10n.ghostMap_whatIsMissing,
        explicitChildNodes: true,
        child: StatefulBuilder(
        builder: (ctx, setModalState) {
          // 🗺️ P4-09: Timer countdown for reveal gating
          final remaining = controller.secondsUntilReveal;
          final canReveal = controller.canRevealCurrentAttempt;

          // Fix #12: Start a real periodic timer (once only)
          if (!canReveal && countdownTimer == null) {
            countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
              if (!ctx.mounted) { countdownTimer?.cancel(); countdownTimer = null; return; }
              if (controller.canRevealCurrentAttempt) {
                countdownTimer?.cancel();
                countdownTimer = null;
              }
              setModalState(() {});
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(20),
                border: isHypercorrection
                    ? Border.all(color: const Color(0xFFFF1744).withValues(alpha: 0.4), width: 2)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isHypercorrection ? '⚡' : (isBelowZPD ? '📚' : '❓'),
                        style: const TextStyle(fontSize: 24),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isHypercorrection
                              ? l10n.ghostMap_hypercorrectionDetected
                              : (isBelowZPD
                                  ? l10n.ghostMap_conceptToDeepen
                                  : l10n.ghostMap_whatIsMissing),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      // 🗺️ P4-15: Pen/text mode toggle
                      ValueListenableBuilder<bool>(
                        valueListenable: penModeNotifier,
                        builder: (_, isPen, __) => IconButton(
                          icon: Icon(
                            isPen ? Icons.keyboard_rounded : Icons.draw_rounded,
                            size: 22,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          tooltip: isPen ? l10n.ghostMap_typeText : l10n.ghostMap_drawByHand,
                          onPressed: () {
                            penModeNotifier.value = !penModeNotifier.value;
                            // Fix #25: Persist preference
                            _ghostMapLastPenMode = penModeNotifier.value;
                            setModalState(() {});
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          controller.cancelAttempt();
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                  // 🗺️ P4-21: Hypercorrection explanation
                  if (isHypercorrection) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF1744).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        l10n.ghostMap_hypercorrectionExplanation,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFFF1744),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                  if (node.explanation != null && !isHypercorrection) ...[
                    const SizedBox(height: 8),
                    Text(
                      '💡 ${node.explanation}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // 🗺️ P4-15: Dual-mode input area (text or pen)
                  ValueListenableBuilder<bool>(
                    valueListenable: penModeNotifier,
                    builder: (_, isPen, __) {
                      if (!isPen) {
                        return TextField(
                          controller: textController,
                          autofocus: true,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          // Fix #24: Enter submits on physical keyboard
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (textController.text.trim().isNotEmpty) {
                              final attempt = textController.text.trim();
                              node.inputMode = 'text';
                              controller.submitAttempt(node.id, attempt);
                              if (ctx.mounted) Navigator.pop(ctx);
                              _showGhostCompareOverlay(node, attempt);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: isHypercorrection
                                ? l10n.ghostMap_rewriteCorrectConcept
                                : l10n.ghostMap_writeMissingConcept,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                              ),
                            ),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          ),
                        );
                      }
                      // 🗺️ P4-15: PEN MODE — inline drawing canvas
                      return StatefulBuilder(
                        builder: (penCtx, setPenState) {
                          // Fix #21: Accessibility for pen drawing pad
                          return Semantics(
                            label: l10n.ghostMap_drawHereHint,
                            hint: l10n.ghostMap_penModeHint,
                            child: Container(
                            height: 140,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Stack(
                              children: [
                                // 🗺️ P4-16: Sagoma placeholder
                                Positioned.fill(
                                  child: AnimatedOpacity(
                                    opacity: penStrokes.isEmpty && currentPenStroke == null
                                        ? sagomaOpacity : 0.0,
                                    duration: const Duration(milliseconds: 500),
                                    child: Center(
                                      child: Text(
                                        l10n.ghostMap_drawHereHint,
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Drawing surface — Fix #4: Listener for pressure
                                Positioned.fill(
                                  child: Listener(
                                    onPointerDown: (e) {
                                      currentPenStroke = [e.localPosition];
                                      _lastPressures = [e.pressure.clamp(0.1, 1.0)];
                                      sagomaOpacity = 0.0;
                                      setPenState(() {});
                                    },
                                    onPointerMove: (e) {
                                      currentPenStroke?.add(e.localPosition);
                                      _lastPressures?.add(e.pressure.clamp(0.1, 1.0));
                                      setPenState(() {});
                                    },
                                    onPointerUp: (_) {
                                      if (currentPenStroke != null && currentPenStroke!.length >= 2) {
                                        // Fix #6: Filter out accidental micro-strokes
                                        final first = currentPenStroke!.first;
                                        final last = currentPenStroke!.last;
                                        final dist = (last - first).distance;
                                        if (dist > 5.0 || currentPenStroke!.length > 4) {
                                          penStrokes.add(List<Offset>.from(currentPenStroke!));
                                          penPressures.add(List<double>.from(
                                            _lastPressures ?? List.filled(currentPenStroke!.length, 0.5),
                                          ));
                                        }
                                      }
                                      currentPenStroke = null;
                                      _lastPressures = null;
                                      setPenState(() {});
                                    },
                                    child: CustomPaint(
                                      painter: _GhostPenPainter(
                                        strokes: penStrokes,
                                        pressures: penPressures,
                                        currentStroke: currentPenStroke,
                                        currentPressures: _lastPressures,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                      size: Size.infinite,
                                    ),
                                  ),
                                ),
                                // Clear button
                                if (penStrokes.isNotEmpty)
                                  Positioned(
                                    top: 4, right: 4,
                                    child: GestureDetector(
                                      onTap: () {
                                        penStrokes.clear();
                                        penPressures.clear();
                                        currentPenStroke = null;
                                        _lastPressures = null;
                                        sagomaOpacity = 1.0;
                                        setPenState(() {});
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.clear, size: 16,
                                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.visibility, size: 18),
                          label: Text(canReveal
                              ? l10n.ghostMap_reveal
                              : l10n.ghostMap_revealCountdown(remaining)),
                          // 🗺️ P4-09: Disable until 10s elapsed
                          onPressed: canReveal
                              ? () {
                                  controller.revealNode(node.id);
                                  Navigator.pop(ctx);
                                  _showGhostCompareOverlay(node, null);
                                }
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatefulBuilder(
                          builder: (btnCtx, setBtnState) {
                            // Fix #5: Disable when no input
                            final hasInput = penModeNotifier.value
                                ? penStrokes.isNotEmpty
                                : textController.text.trim().isNotEmpty;
                            return FilledButton.icon(
                              icon: isOcrLoading
                                  ? const SizedBox(width: 18, height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check, size: 18),
                              label: Text(isOcrLoading ? l10n.ghostMap_recognizing : l10n.ghostMap_compare),
                              onPressed: (!hasInput || isOcrLoading)
                                  ? null // Fix #5: disable without input
                                  : () async {
                                      String attempt;
                                      if (penModeNotifier.value && penStrokes.isNotEmpty) {
                                        // Fix #3: Show loading state
                                        isOcrLoading = true;
                                        setModalState(() {});
                                        attempt = await _recognizePenAttempt(penStrokes) ?? '';
                                        isOcrLoading = false;
                                        if (attempt.isEmpty && mounted) {
                                          setModalState(() {});
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                l10n.ghostMap_ocrFallbackMessage,
                                              ),
                                              behavior: SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
                                              duration: const Duration(seconds: 3),
                                              backgroundColor: const Color(0xFFE65100),
                                            ),
                                          );
                                          return;
                                        }
                                      } else {
                                        attempt = textController.text.trim();
                                      }
                                      // Fix #8: track input mode
                                      node.inputMode = penModeNotifier.value ? 'pen' : 'text';
                                      controller.submitAttempt(node.id, attempt);
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      _showGhostCompareOverlay(node, attempt);
                                    },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  // 🗺️ P4-20: Dismiss this specific ghost node
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      icon: Icon(Icons.visibility_off_rounded, size: 16,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                      label: Text(
                        l10n.ghostMap_ignoreNode,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                      onPressed: () {
                        final dismissedId = node.id;
                        controller.dismissNode(dismissedId);
                        Navigator.pop(ctx);
                        setState(() {});
                        // Fix #14: Undo snackbar
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.ghostMap_nodeIgnored),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
                              duration: const Duration(seconds: 5),
                              backgroundColor: const Color(0xFF455A64),
                              action: SnackBarAction(
                                label: l10n.ghostMap_undo,
                                textColor: Colors.white,
                                onPressed: () {
                                  controller.undismissNode(dismissedId);
                                  setState(() {});
                                },
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      ),
    ).then((_) {
      if (controller.activeAttemptNodeId == node.id) {
        controller.cancelAttempt();
      }
      // Fix #2+#7: Dispose resources on sheet close
      penModeNotifier.dispose();
      textController.dispose();
      // Fix #17: Cancel countdown timer
      countdownTimer?.cancel();
      countdownTimer = null;
    });
  }

  /// 🗺️ P4-15: Recognize handwritten pen strokes from the inline drawing pad.
  Future<String?> _recognizePenAttempt(List<List<Offset>> penStrokes) async {
    try {
      final inkService = DigitalInkService.instance;
      if (!inkService.isAvailable) return null;

      final strokeSets = <List<ProDrawingPoint>>[];
      for (final stroke in penStrokes) {
        if (stroke.length < 2) continue;
        final points = stroke.map((p) => ProDrawingPoint(
          position: Offset(p.dx, p.dy),
          pressure: 0.5,
        )).toList();
        strokeSets.add(points);
      }

      if (strokeSets.isEmpty) return null;

      final recognized = await inkService.engine.recognizeTextMode(strokeSets);
      debugPrint('🗺️ P4-15: Pen OCR result: "$recognized"');
      return recognized?.trim();
    } catch (e) {
      debugPrint('🗺️ P4-15: Pen OCR failed: $e');
      return null;
    }
  }

  // ── COMPARE OVERLAY ──────────────────────────────────────────────────────

  /// Show the comparison overlay: user attempt vs Atlas answer.
  void _showGhostCompareOverlay(GhostNode node, String? userAttempt) {
    final isCorrect = node.attemptCorrect == true;
    final isHyper = node.isHypercorrection;
    final l10n = _l10n;

    // Fix #1: Closure variables — persist across StatefulBuilder rebuilds
    bool showAtlasAnswer = userAttempt == null; // Immediately for reveal-only
    bool fadeScheduled = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Semantics(
        label: isHyper
            ? l10n.ghostMap_hypercorrectionTitle
            : (isCorrect ? l10n.ghostMap_correctAttempt : l10n.ghostMap_incorrectAttempt),
        explicitChildNodes: true,
        child: StatefulBuilder(
        builder: (ctx, setModalState) {
          // 🗺️ P4-10: Delayed fade-in for Atlas answer (1s)
          // Schedule ONCE, not on every rebuild
          if (!fadeScheduled && userAttempt != null) {
            fadeScheduled = true;
            Future.delayed(const Duration(seconds: 1), () {
              if (ctx.mounted) setModalState(() { showAtlasAnswer = true; });
            });
          }

          return Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isHyper
                    ? const Color(0xFFFF1744).withValues(alpha: 0.3)
                    : (isCorrect
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.orange.withValues(alpha: 0.3)),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isHyper
                          ? '⚡'
                          : (isCorrect ? '✅' : (userAttempt != null ? '📝' : '👁')),
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isHyper
                            ? l10n.ghostMap_hypercorrectionTitle
                            : (isCorrect ? l10n.ghostMap_correctAttempt : l10n.ghostMap_incorrectAttempt),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                // 🗺️ P4-21: Hypercorrection feedback in compare overlay
                if (isHyper) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF1744).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.ghostMap_hypercorrectionExplanation,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFFF1744),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // 🗺️ P4-10: Atlas answer with animated fade-in
                AnimatedOpacity(
                  opacity: showAtlasAnswer || userAttempt == null ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 800),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.ghostMap_atlasAnswer,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          node.concept,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (userAttempt != null && userAttempt.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (isCorrect ? Colors.green : Colors.orange).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (isCorrect ? Colors.green : Colors.orange).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.ghostMap_yourAttempt,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isCorrect ? Colors.green : Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          userAttempt,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
                if (node.explanation != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '💡 ${node.explanation}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                // Fix #13: Self-evaluation buttons (metacognitive override)
                // Only shown when student made an attempt AND Atlas answer visible
                if (userAttempt != null && userAttempt.isNotEmpty && showAtlasAnswer) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          l10n.ghostMap_selfEvalQuestion,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Text('😓', style: TextStyle(fontSize: 16)),
                                label: Text(l10n.ghostMap_selfEvalNo),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFF44336),
                                  side: const BorderSide(color: Color(0x33F44336)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  node.attemptCorrect = false;
                                  _ghostMapController.overrideAttemptResult(node.id, false);
                                  if (ctx.mounted) setModalState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Text('💪', style: TextStyle(fontSize: 16)),
                                label: Text(l10n.ghostMap_selfEvalYes),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF4CAF50),
                                  side: const BorderSide(color: Color(0x334CAF50)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  node.attemptCorrect = true;
                                  _ghostMapController.overrideAttemptResult(node.id, true);
                                  if (ctx.mounted) setModalState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _buildGhostMapProgress(),
              ],
            ),
          );
        },
      ),
      ),
    ).then((_) {
      setState(() {});
    });
  }

  // ── EXPLANATION POPUP ────────────────────────────────────────────────────

  /// Show an explanation popup for a weak/correct/wrongConnection node.
  void _showGhostExplanationPopup(GhostNode node) {
    final l10n = _l10n;
    final isWeak = node.isWeak;
    final isWrongConn = node.isWrongConnection;
    final isCorrect = node.isCorrect;
    final isHighConfCorrect = node.isHighConfidenceCorrect;

    // Determine styling based on node type
    final Color accentColor;
    final String emoji;
    final String title;

    if (isWrongConn) {
      accentColor = Colors.amber;
      emoji = '❓';
      title = l10n.ghostMap_connectionToReview;
    } else if (node.isHypercorrection) {
      accentColor = const Color(0xFFFF1744);
      emoji = '⚡';
      title = l10n.ghostMap_hypercorrectionTitle;
    } else if (node.isBelowZPD) {
      accentColor = Colors.grey;
      emoji = '📚';
      title = l10n.ghostMap_belowZPD;
    } else if (isHighConfCorrect) {
      accentColor = const Color(0xFF00C853);
      emoji = '⭐';
      title = l10n.ghostMap_excellentMastery;
    } else if (isCorrect) {
      accentColor = Colors.green;
      emoji = '✅';
      title = l10n.ghostMap_wellDone;
    } else {
      accentColor = Colors.amber;
      emoji = '⚠️';
      title = l10n.ghostMap_weakPoint;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Semantics(
        label: title,
        explicitChildNodes: true,
        child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // Confidence badge if available
                if (node.confidenceLevel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l10n.ghostMap_confidenceLevel(node.confidenceLevel ?? 0),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 🗺️ P4-21: Hypercorrection-specific message
            if (node.isHypercorrection) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF1744).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l10n.ghostMap_hypercorrectionExplanation,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFFF1744),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            // 🗺️ P4-22: Below-ZPD message
            if (node.isBelowZPD && !node.isHypercorrection) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l10n.ghostMap_belowZPDExplanation,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (node.explanation != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  node.explanation!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            // 🗺️ P4-20: Dismiss this node (for weak/wrongConnection, not correct ones)
            if (isWeak || isWrongConn) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  icon: Icon(Icons.visibility_off_rounded, size: 16,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                  label: Text(
                    l10n.ghostMap_ignoreNode,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  onPressed: () {
                    _ghostMapController.dismissNode(node.id);
                    Navigator.pop(ctx);
                    setState(() {});
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

/// 🗺️ P4-15: Lightweight painter for the inline pen attempt drawing surface.
///
/// Renders completed strokes and the current in-progress stroke using
/// smooth Catmull-Rom curves for natural handwriting appearance.
/// Fix #4: Supports pressure-sensitive stylus input for variable stroke width.
class _GhostPenPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<List<double>> pressures; // Fix #4: pressure per stroke
  final List<Offset>? currentStroke;
  final List<double>? currentPressures; // Fix #4: current stroke pressures
  final Color color;

  // Fix #9: Cache Paint objects — avoid per-frame allocation at 60fps
  late final Paint _strokePaint = Paint()
    ..color = color.withValues(alpha: 0.8)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  late final Paint _activePaint = Paint()
    ..color = color.withValues(alpha: 0.6)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  _GhostPenPainter({
    required this.strokes,
    required this.pressures,
    required this.currentStroke,
    required this.currentPressures,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw completed strokes
    for (int i = 0; i < strokes.length; i++) {
      final p = i < pressures.length ? pressures[i] : null;
      _drawStroke(canvas, strokes[i], p, _strokePaint);
    }

    // Draw current in-progress stroke
    if (currentStroke != null && currentStroke!.isNotEmpty) {
      _drawStroke(canvas, currentStroke!, currentPressures, _activePaint);
    }
  }

  // Fix #4: Pressure-aware stroke rendering
  // Draws segments with variable width based on pressure (1.5-3.5px range)
  void _drawStroke(Canvas canvas, List<Offset> points, List<double>? press, Paint paint) {
    if (points.length < 2) return;

    // If no pressure data or uniform, use simple path
    final hasPressure = press != null && press.length >= points.length &&
        press.any((p) => (p - 0.5).abs() > 0.05);

    if (!hasPressure) {
      // Uniform width — fast path
      paint.strokeWidth = 2.0;
      final path = Path();
      path.moveTo(points[0].dx, points[0].dy);
      if (points.length == 2) {
        path.lineTo(points[1].dx, points[1].dy);
      } else {
        for (int i = 0; i < points.length - 1; i++) {
          final p0 = i > 0 ? points[i - 1] : points[i];
          final p1 = points[i];
          final p2 = points[i + 1];
          final p3 = i < points.length - 2 ? points[i + 2] : points[i + 1];
          path.cubicTo(
            p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6,
            p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6,
            p2.dx, p2.dy,
          );
        }
      }
      canvas.drawPath(path, paint);
      return;
    }

    // Variable width — draw segment-by-segment with interpolated pressure
    for (int i = 0; i < points.length - 1; i++) {
      final pressA = press[i];
      final pressB = press[i + 1];
      final avgPressure = (pressA + pressB) / 2.0;
      // Map pressure [0.1..1.0] → width [1.5..3.5]
      paint.strokeWidth = 1.5 + (avgPressure * 2.0);
      canvas.drawLine(points[i], points[i + 1], paint);
    }
  }

  @override
  // Fix #10: Check currentStroke length for accurate invalidation during drawing
  bool shouldRepaint(_GhostPenPainter oldDelegate) =>
      strokes.length != oldDelegate.strokes.length ||
      currentStroke?.length != oldDelegate.currentStroke?.length ||
      color != oldDelegate.color;
}
