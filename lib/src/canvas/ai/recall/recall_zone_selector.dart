// ============================================================================
// 📐 RECALL ZONE SELECTOR — Area selection for recall mode activation
//
// Spec: P2-62 → P2-65
//
// Provides the gesture handler for selecting which area of the canvas
// the student will attempt to reconstruct from memory.
//
// Features:
//   - Rectangle selection via drag gesture (P2-63)
//   - Shows cluster count and zone name suggestion (P2-64)
//   - "Seleziona tutto" quick option
//   - Visual feedback: semi-transparent border during drag
//   - Recall mode toggle (Free / Spatial) before activation
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../reflow/content_cluster.dart';
import 'recall_session_model.dart';

/// 📐 Zone selector overlay for recall mode activation.
///
/// Appears when the student activates "Recall Mode" from the toolbar.
/// They select an area, then choose Free or Spatial Recall.
class RecallZoneSelector extends StatefulWidget {
  /// All clusters on the canvas.
  final List<ContentCluster> allClusters;

  /// Canvas controller for coordinate transforms.
  final dynamic canvasController;

  /// Called when a zone is selected and mode is chosen.
  final void Function(Rect zone, RecallPhase mode) onZoneSelected;

  /// Called to dismiss without selecting.
  final VoidCallback onDismiss;

  /// Previous zone suggestions (from session history).
  final List<String>? suggestedZoneNames;

  const RecallZoneSelector({
    super.key,
    required this.allClusters,
    required this.canvasController,
    required this.onZoneSelected,
    required this.onDismiss,
    this.suggestedZoneNames,
  });

  @override
  State<RecallZoneSelector> createState() => _RecallZoneSelectorState();
}

class _RecallZoneSelectorState extends State<RecallZoneSelector>
    with SingleTickerProviderStateMixin {
  // Selection rectangle in screen coordinates.
  Offset? _dragStart;
  Offset? _dragCurrent;

  // After selection: confirmation mode.
  Rect? _selectedZone; // Canvas coordinates.
  int _clustersInZone = 0;
  RecallPhase _selectedMode = RecallPhase.freeRecall;

  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
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
    return FadeTransition(
      opacity: _fadeAnim,
      child: Stack(
        children: [
          // ── Nearly-transparent scrim: canvas stays visible (Option B) ──
          Positioned.fill(
            child: GestureDetector(
              onPanStart: (d) =>
                  setState(() => _dragStart = d.localPosition),
              onPanUpdate: (d) =>
                  setState(() => _dragCurrent = d.localPosition),
              onPanEnd: (_) => _finishSelection(),
              child: Container(
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),

          // ── Cluster position indicators (subtle dots) ──
          if (_selectedZone == null)
            ..._buildClusterIndicators(),

          // ── Selection rectangle (during drag) ──
          if (_dragStart != null && _dragCurrent != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SelectionRectPainter(
                    start: _dragStart!,
                    end: _dragCurrent!,
                  ),
                ),
              ),
            ),

          // ── Instruction text (before selection) ──
          if (_selectedZone == null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0A0A14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '📐 Seleziona la zona da ricostruire',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Trascina per selezionare un\'area, oppure:',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // "Select all" button.
                          GestureDetector(
                            onTap: _selectAll,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF6C63FF)
                                        .withValues(alpha: 0.3),
                                    const Color(0xFF6C63FF)
                                        .withValues(alpha: 0.1),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Seleziona tutto',
                                style: TextStyle(
                                  color: Color(0xFF6C63FF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Cancel button.
                          GestureDetector(
                            onTap: widget.onDismiss,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Annulla',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Confirmation card (after selection) ──
          if (_selectedZone != null)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 24,
              right: 24,
              child: _buildConfirmationCard(),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CLUSTER POSITION INDICATORS
  // ─────────────────────────────────────────────────────────────────────────

  /// Render subtle dots showing where clusters are on the canvas.
  /// Helps the user see what they're selecting.
  List<Widget> _buildClusterIndicators() {
    final controller = widget.canvasController;
    if (controller == null) return const [];

    return widget.allClusters.map((cluster) {
      try {
        final screenPos =
            (controller as dynamic).canvasToScreen(cluster.centroid) as Offset;
        final scale = (controller as dynamic).scale as double;
        final w = (cluster.bounds.width * scale).clamp(16.0, 200.0);
        final h = (cluster.bounds.height * scale).clamp(12.0, 150.0);

        return Positioned(
          left: screenPos.dx - w / 2,
          top: screenPos.dy - h / 2,
          child: IgnorePointer(
            child: Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.20),
                  width: 1.0,
                ),
              ),
            ),
          ),
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SELECT ALL
  // ─────────────────────────────────────────────────────────────────────────

  void _selectAll() {
    if (widget.allClusters.isEmpty) {
      widget.onDismiss();
      return;
    }

    // Compute bounds enclosing all clusters.
    var bounds = widget.allClusters.first.bounds;
    for (final c in widget.allClusters.skip(1)) {
      bounds = bounds.expandToInclude(c.bounds);
    }

    // Add some padding.
    final zone = bounds.inflate(50);

    HapticFeedback.mediumImpact();
    setState(() {
      _selectedZone = zone;
      _clustersInZone = widget.allClusters.length;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FINISH DRAG SELECTION
  // ─────────────────────────────────────────────────────────────────────────

  void _finishSelection() {
    if (_dragStart == null || _dragCurrent == null) return;

    final controller = widget.canvasController;
    if (controller == null) return;

    try {
      // Convert screen rect to canvas coordinates.
      final canvasStart =
          (controller as dynamic).screenToCanvas(_dragStart!) as Offset;
      final canvasEnd =
          (controller as dynamic).screenToCanvas(_dragCurrent!) as Offset;

      final zone = Rect.fromPoints(canvasStart, canvasEnd);
      if (zone.width < 30 || zone.height < 30) {
        // Too small — reset.
        setState(() {
          _dragStart = null;
          _dragCurrent = null;
        });
        return;
      }

      // Count clusters in zone.
      final count = widget.allClusters
          .where((c) => zone.overlaps(c.bounds) || zone.contains(c.centroid))
          .length;

      HapticFeedback.mediumImpact();
      setState(() {
        _selectedZone = zone;
        _clustersInZone = count;
        _dragStart = null;
        _dragCurrent = null;
      });
    } catch (_) {
      setState(() {
        _dragStart = null;
        _dragCurrent = null;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONFIRMATION CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildConfirmationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE60A0A14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zone info.
          Text(
            '$_clustersInZone nodi nella zona selezionata',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 12),

          // Mode selection pills (P2-38).
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _modePill(
                '🧠 Free Recall',
                'Tela vuota',
                RecallPhase.freeRecall,
              ),
              const SizedBox(width: 10),
              _modePill(
                '📍 Spatial Recall',
                'Sagome visibili',
                RecallPhase.spatialRecall,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Action buttons.
          Row(
            children: [
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
                    ),
                    child: const Text(
                      'Annulla',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () {
                    if (_selectedZone == null || _clustersInZone == 0) return;
                    HapticFeedback.heavyImpact();
                    widget.onZoneSelected(_selectedZone!, _selectedMode);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C63FF)
                              .withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Text(
                      '🚀 Inizia ricostruzione',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Warning if no clusters.
          if (_clustersInZone == 0) ...[
            const SizedBox(height: 8),
            Text(
              'Nessun contenuto in questa zona',
              style: TextStyle(
                color: const Color(0xFFFF9500).withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modePill(String title, String subtitle, RecallPhase mode) {
    final selected = _selectedMode == mode;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedMode = mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                )
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? const Color(0xFF6C63FF).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.12),
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: selected
                    ? Colors.white.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for the selection rectangle.
class _SelectionRectPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  const _SelectionRectPainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);

    // Fill.
    final fill = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      fill,
    );

    // Border.
    final border = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha: 0.5)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      border,
    );

    // Corner markers.
    final cornerPaint = Paint()
      ..color = const Color(0xFF6C63FF)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const cornerLen = 12.0;
    // Top-left.
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, cornerLen), cornerPaint);
    // Top-right.
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-cornerLen, 0), cornerPaint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, cornerLen), cornerPaint);
    // Bottom-left.
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -cornerLen), cornerPaint);
    // Bottom-right.
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-cornerLen, 0), cornerPaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -cornerLen), cornerPaint);
  }

  @override
  bool shouldRepaint(_SelectionRectPainter oldDelegate) =>
      start != oldDelegate.start || end != oldDelegate.end;
}
