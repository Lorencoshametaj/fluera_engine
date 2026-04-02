// ============================================================================
// 📊 RECALL SUMMARY OVERLAY — Post-comparison result card
//
// Spec: P2-58 → P2-61, P2-35
//
// Displays a premium glassmorphism card with:
//   - Positive message first (P2-58): "Hai ricostruito X su Y dalla memoria!"
//   - Delta improvement vs previous session (P2-59)
//   - Mastered nodes with gold border + star (P2-60)
//   - Zero negative language (P2-61)
//   - Auto-evaluation summary (5-level)
//   - Transition button to Step 3 Socratic (P2-35)
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'recall_mode_controller.dart';
import 'recall_session_model.dart';

/// 📊 Summary card shown after the comparison phase.
class RecallSummaryOverlay extends StatefulWidget {
  final RecallModeController controller;

  /// Previous session summary for delta display (null if first time).
  final RecallSessionSummary? previousSession;

  /// Called when the user wants to start Step 3 (Socratic interrogation).
  final VoidCallback onStartSocratic;

  /// Called to dismiss the summary and exit recall mode.
  final VoidCallback onDismiss;

  /// Called to repeat the recall session.
  final VoidCallback onRepeat;

  /// Called to delete reconstruction strokes from the canvas.
  final VoidCallback? onDeleteReconstruction;

  /// Whether there are reconstruction strokes that can be deleted.
  final bool hasReconstructionStrokes;

  const RecallSummaryOverlay({
    super.key,
    required this.controller,
    this.previousSession,
    required this.onStartSocratic,
    required this.onDismiss,
    required this.onRepeat,
    this.onDeleteReconstruction,
    this.hasReconstructionStrokes = false,
  });

  @override
  State<RecallSummaryOverlay> createState() => _RecallSummaryOverlayState();
}

class _RecallSummaryOverlayState extends State<RecallSummaryOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );
    _slideAnim = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.controller.session;
    if (session == null) return const SizedBox.shrink();

    final recalled = session.recalledCount;
    final total = session.totalOriginalNodes;
    final peeked = session.peekedCount;
    final missed = session.missedCount;
    final delta = widget.controller.deltaImprovement(widget.previousSession);
    final elapsed = widget.controller.elapsed;
    final percentage = total > 0 ? (recalled / total * 100).round() : 0;

    // Mastered count.
    final masteredCount = session.nodeEntries.values
        .where((e) => e.mastered)
        .length;

    return AnimatedBuilder(
      animation: _slideAnim,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _slideAnim.value),
        child: child,
      ),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Center(
            child: Container(
              width: 340,
              constraints: const BoxConstraints(maxHeight: 500),
              decoration: BoxDecoration(
                color: const Color(0xE60A0A14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                    blurRadius: 40,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── POSITIVE MESSAGE FIRST (P2-58) ──
                    Text(
                      _positiveEmoji(percentage),
                      style: const TextStyle(fontSize: 40),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.controller.summaryText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),

                    // ── DELTA IMPROVEMENT (P2-59) ──
                    if (delta != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: delta > 0
                              ? const Color(0xFF30D158).withValues(alpha: 0.15)
                              : delta < 0
                                  ? const Color(0xFFFF9500)
                                      .withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          delta > 0
                              ? '+$delta nodi rispetto all\'ultima volta!'
                              : delta == 0
                                  ? 'Stesso risultato — costanza!'
                                  : 'Qualche nodo in meno — succede!',
                          style: TextStyle(
                            color: delta > 0
                                ? const Color(0xFF30D158)
                                : delta < 0
                                    ? const Color(0xFFFF9500)
                                    : Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // ── STATS GRID ──
                    _buildStatsGrid(
                      recalled: recalled,
                      total: total,
                      missed: missed,
                      peeked: peeked,
                      elapsed: elapsed,
                      masteredCount: masteredCount,
                    ),

                    const SizedBox(height: 16),

                    // ── RECALL LEVEL BREAKDOWN ──
                    _buildLevelBreakdown(session),

                    const SizedBox(height: 20),

                    // ── ACTION BUTTONS ──
                    _buildActions(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATS GRID
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStatsGrid({
    required int recalled,
    required int total,
    required int missed,
    required int peeked,
    required Duration elapsed,
    required int masteredCount,
  }) {
    return Row(
      children: [
        Expanded(
          child: _statTile('✅ Ricordati', '$recalled', const Color(0xFF30D158)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              _statTile('📋 Da rivedere', '$missed', const Color(0xFFFF9500)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statTile('👁️ Sbirciati', '$peeked', const Color(0xFFFFCC00)),
        ),
      ],
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LEVEL BREAKDOWN
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLevelBreakdown(RecallSession session) {
    // Count by level.
    final counts = <RecallLevel, int>{};
    for (final entry in session.nodeEntries.values) {
      counts[entry.recallLevel] = (counts[entry.recallLevel] ?? 0) + 1;
    }

    // Only show levels that have entries.
    final levels = RecallLevel.values
        .where((l) => (counts[l] ?? 0) > 0)
        .toList()
      ..sort((a, b) => b.level.compareTo(a.level));

    if (levels.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dettaglio per livello',
          style: TextStyle(
            color: Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...levels.map((level) {
          final count = counts[level]!;
          final total = session.totalOriginalNodes;
          final fraction = total > 0 ? count / total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Text(level.icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${level.label} ($count)',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 4,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          valueColor: AlwaysStoppedAnimation(
                            Color(level.colorValue),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTION BUTTONS (P2-35)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildActions() {
    final hasGaps = widget.controller.gapClusterIds.isNotEmpty;

    return Column(
      children: [
        // Step 3 transition (P2-35): only show if there are gaps.
        if (hasGaps)
          GestureDetector(
            onTap: () {
              HapticFeedback.heavyImpact();
              widget.onStartSocratic();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                '🎓 Avvia Interrogazione Socratica',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

        const SizedBox(height: 8),

        // Secondary actions.
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onRepeat();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 0.5,
                    ),
                  ),
                  child: const Text(
                    '🔄 Riprova',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onDismiss();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 0.5,
                    ),
                  ),
                  child: const Text(
                    '✓ Chiudi',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // Delete reconstruction strokes button.
        if (widget.hasReconstructionStrokes && widget.onDeleteReconstruction != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              widget.onDeleteReconstruction!();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
              child: const Text(
                '🧹 Cancella tentativo dal canvas',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFF6B6B),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _positiveEmoji(int percentage) {
    if (percentage >= 90) return '🏆';
    if (percentage >= 70) return '🎯';
    if (percentage >= 50) return '💪';
    if (percentage >= 30) return '📈';
    return '🌱'; // Always encouraging (P2-61).
  }
}
