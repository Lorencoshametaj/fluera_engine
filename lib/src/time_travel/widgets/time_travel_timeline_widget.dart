import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/time_travel_playback_engine.dart';

/// ⏱️ Time Travel Timeline Widget — Material Design 3
///
/// Player overlay for the replay Time Travel, costruito con:
/// - M3 color scheme (`Theme.of(context).colorScheme`)
/// - M3 components (IconButton, FilledButton.tonal)
/// - M3 typography (`Theme.of(context).textTheme`)
/// - Surface tonal elevation + border radius 28dp
/// - Custom heatmap with theme colors
class TimeTravelTimelineWidget extends StatefulWidget {
  final TimeTravelPlaybackEngine engine;
  final VoidCallback onExit;
  final VoidCallback? onExportRequested;
  final VoidCallback? onRecoverRequested;
  final VoidCallback? onNewBranch;
  final VoidCallback? onBranchExplorer;
  final String? activeBranchName;

  const TimeTravelTimelineWidget({
    super.key,
    required this.engine,
    required this.onExit,
    this.onExportRequested,
    this.onRecoverRequested,
    this.onNewBranch,
    this.onBranchExplorer,
    this.activeBranchName,
  });

  @override
  State<TimeTravelTimelineWidget> createState() =>
      _TimeTravelTimelineWidgetState();
}

class _TimeTravelTimelineWidgetState extends State<TimeTravelTimelineWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;

  // Speed disponibili for the playback
  static const List<double> _speeds = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0];
  int _speedIndex = 2; // Default 1x (index of 1.0 in the list)

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    // 🎯 Chain: non sovrascrivere il callback of the canvas screen
    final existingOnStateChanged = widget.engine.onStateChanged;
    widget.engine.onStateChanged = () {
      existingOnStateChanged?.call(); // Update strokes in the canvas
      if (mounted) setState(() {}); // Update timeline UI
    };

    widget.engine.onPlaybackStateChanged = (_) {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Positioned(
      left: 12,
      right: 12,
      bottom: MediaQuery.of(context).padding.bottom + 12,
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _fadeController,
          curve: Curves.easeOutCubic,
        ),
        child: Material(
          type: MaterialType.card,
          color: cs.surfaceContainerHighest,
          surfaceTintColor: cs.primary,
          elevation: 6,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ─── Header: titolo + tempo + Exit ─────────
                _buildHeader(cs, tt),
                const SizedBox(height: 12),

                // ─── Heatmap + Scrubber ────────────────────
                _buildScrubber(cs),
                const SizedBox(height: 4),

                // ─── Time labels sotto la barra ────────────
                _buildTimeLabels(cs, tt),
                const SizedBox(height: 12),

                // ─── Controls ──────────────────────────────
                _buildControls(cs, tt),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // HEADER
  // ============================================================================

  Widget _buildHeader(ColorScheme cs, TextTheme tt) {
    return Row(
      children: [
        // ⏱ Icon chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history_rounded,
                color: cs.onPrimaryContainer,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Time Travel',
                style: tt.labelMedium?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // 🌿 Branch badge (if on a branch)
        if (widget.activeBranchName != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.alt_route_rounded,
                  color: Color(0xFF7C4DFF),
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.activeBranchName!,
                  style: tt.labelSmall?.copyWith(
                    color: const Color(0xFF7C4DFF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],

        const Spacer(),

        // 🌿 Branch Explorer
        if (widget.onBranchExplorer != null)
          IconButton(
            onPressed: widget.onBranchExplorer,
            icon: const Icon(Icons.account_tree_rounded),
            iconSize: 18,
            tooltip: 'Branch Explorer',
            color: cs.onSurfaceVariant,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),

        // ✕ Exit — M3 IconButton
        IconButton.outlined(
          onPressed: widget.onExit,
          icon: const Icon(Icons.close_rounded),
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            side: BorderSide(color: cs.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // SCRUBBER (Heatmap + GestureDetector)
  // ============================================================================

  Widget _buildScrubber(ColorScheme cs) {
    final dateMarkers = widget.engine.getSessionDateMarkers();

    return SizedBox(
      height: 64,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // Dynamic segments: ~1 segment per 4px
          final segments = (width / 4).round().clamp(20, 300);
          final density = widget.engine.getEventDensity(segments: segments);
          final maxDensity =
              density.isEmpty
                  ? 0.0
                  : density.reduce((a, b) => a > b ? a : b).toDouble();

          return GestureDetector(
            onHorizontalDragUpdate: (details) {
              final progress = (details.localPosition.dx / width).clamp(
                0.0,
                1.0,
              );
              widget.engine.seekToProgress(progress);
            },
            onTapDown: (details) {
              final progress = (details.localPosition.dx / width).clamp(
                0.0,
                1.0,
              );
              widget.engine.seekToProgress(progress);
            },
            child: CustomPaint(
              size: Size(width, 64),
              painter: _TimelineHeatmapPainter(
                density: density,
                maxDensity: maxDensity,
                progress: widget.engine.progress,
                dateMarkers: dateMarkers,
                activeColor: cs.primary,
                activeColorLight: cs.primaryContainer,
                inactiveColor: cs.surfaceContainerHigh,
                inactiveColorLight: cs.outlineVariant,
                labelColor: cs.onSurfaceVariant,
                playheadColor: cs.onSurface,
                playheadGlow: cs.primary,
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================================
  // DATE/TIME LABELS (sotto la barra scrubber)
  // ============================================================================

  Widget _buildTimeLabels(ColorScheme cs, TextTheme tt) {
    final absoluteTime = widget.engine.currentAbsoluteTime;
    final eventIdx = widget.engine.currentEventIndex;
    final totalEvents = widget.engine.totalEventCount;

    return Row(
      children: [
        // 📅 Absolute date/time of the current event
        Icon(Icons.calendar_today_rounded, size: 12, color: cs.primary),
        const SizedBox(width: 4),
        Text(
          absoluteTime != null ? _formatAbsoluteTime(absoluteTime) : '--',
          style: tt.bodySmall?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),

        const Spacer(),

        // #evento / totale
        Text(
          '$eventIdx / $totalEvents',
          style: tt.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // CONTROLS
  // ============================================================================

  Widget _buildControls(ColorScheme cs, TextTheme tt) {
    final isPlaying = widget.engine.state == TimeTravelPlaybackState.playing;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: SizedBox(
        width:
            MediaQuery.of(context).size.width -
            48, // tighter to prevent overflow
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            // ─── Left: mode chips (flexible per adattarsi) ──
            Flexible(
              flex: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🏎️ Speed — tap cicla, long press popup
                  _buildSpeedChip(cs, tt),

                  const SizedBox(width: 4),

                  // 🎯 Stroke-by-stroke
                  _buildChipButton(
                    label: '1→1',
                    icon:
                        widget.engine.strokeByStroke
                            ? Icons.gesture_rounded
                            : Icons.layers_rounded,
                    cs: cs,
                    tt: tt,
                    isActive: widget.engine.strokeByStroke,
                    onTap: () {
                      setState(() {
                        widget.engine.strokeByStroke =
                            !widget.engine.strokeByStroke;
                      });
                    },
                  ),
                ],
              ),
            ),

            const Spacer(),

            // ─── Center: transport controls ───────────────
            // ⏮ Previous session
            IconButton(
              onPressed: widget.engine.skipToPreviousSession,
              icon: const Icon(Icons.skip_previous_rounded),
              color: cs.onSurfaceVariant,
              tooltip: 'Previous session',
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),

            // ▶️ / ⏸️ Play/Pause — M3 filled tonal
            IconButton.filledTonal(
              onPressed: isPlaying ? widget.engine.pause : widget.engine.play,
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 24,
              ),
              style: IconButton.styleFrom(
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
              ),
              tooltip: isPlaying ? 'Pausa' : 'Riproduci',
            ),

            // ⏭ Next session
            IconButton(
              onPressed: widget.engine.skipToNextSession,
              icon: const Icon(Icons.skip_next_rounded),
              color: cs.onSurfaceVariant,
              tooltip: 'Next session',
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),

            const Spacer(),

            // ─── Right: branch + recover + export ────────────────────
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🌿 New Branch from current position
                  if (widget.onNewBranch != null)
                    IconButton(
                      onPressed: widget.onNewBranch,
                      icon: Image.asset(
                        'assets/looponia_images/looponia_git.png',
                        width: 18,
                        height: 18,
                        color: const Color(0xFF7C4DFF),
                      ),
                      iconSize: 18,
                      tooltip: 'New Branch from here',
                      color: const Color(0xFF7C4DFF),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),

                  // 🔮 Recupera nel presente
                  if (widget.onRecoverRequested != null)
                    IconButton(
                      onPressed: widget.onRecoverRequested,
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      iconSize: 18,
                      tooltip: 'Recupera nel presente',
                      color: cs.tertiary,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),

                  if (widget.onExportRequested != null)
                    IconButton(
                      onPressed: widget.onExportRequested,
                      icon: const Icon(Icons.movie_creation_outlined),
                      iconSize: 18,
                      tooltip: 'Export timelapse',
                      color: cs.onSurfaceVariant,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🏎️ Speed chip: tap cicla, long press mostra popup lista
  Widget _buildSpeedChip(ColorScheme cs, TextTheme tt) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _speedIndex = (_speedIndex + 1) % _speeds.length;
          widget.engine.playbackSpeed = _speeds[_speedIndex];
        });
      },
      onLongPressStart: (details) {
        _showSpeedPopup(context, details.globalPosition, cs, tt);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed_rounded, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              '${_speeds[_speedIndex]}x',
              style: tt.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Speed list popup (appears on long press)
  void _showSpeedPopup(
    BuildContext context,
    Offset globalPosition,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<double>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromCenter(center: globalPosition, width: 0, height: 0),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cs.surfaceContainerHighest,
      elevation: 4,
      items:
          _speeds.asMap().entries.map((entry) {
            final idx = entry.key;
            final speed = entry.value;
            final isSelected = idx == _speedIndex;

            return PopupMenuItem<double>(
              value: speed,
              height: 40,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? cs.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${speed}x',
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                  ),
                ),
              ),
            );
          }).toList(),
    ).then((value) {
      if (value != null) {
        setState(() {
          _speedIndex = _speeds.indexOf(value);
          widget.engine.playbackSpeed = value;
        });
      }
    });
  }

  /// Reusable chip-button for controls
  Widget _buildChipButton({
    required String label,
    required IconData icon,
    required ColorScheme cs,
    required TextTheme tt,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? cs.primaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isActive
                    ? cs.primary.withValues(alpha: 0.3)
                    : cs.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: tt.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isActive ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // FORMATTING HELPERS
  // ============================================================================

  /// Formatta timestamp assoluto in modo smart:
  /// - Oggi: "14:30"
  /// - This week: "Mon 14:30"
  /// - Quest'anno: "12 Feb, 14:30"
  /// - Altro: "12 Feb 2025"
  String _formatAbsoluteTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(eventDay).inDays;

    if (diff == 0) {
      // Oggi → solo ora
      return DateFormat.Hm().format(dt);
    } else if (diff == 1) {
      return 'Ieri, ${DateFormat.Hm().format(dt)}';
    } else if (diff < 7) {
      // This week → day + time
      return '${DateFormat.E().format(dt)}, ${DateFormat.Hm().format(dt)}';
    } else if (dt.year == now.year) {
      // Quest'anno → giorno mese + ora
      return DateFormat('d MMM, HH:mm').format(dt);
    } else {
      // Anno diverso
      return DateFormat('d MMM y').format(dt);
    }
  }
}

// =============================================================================
// HEATMAP PAINTER — Continuous gradient + dates + M3
// =============================================================================

/// 🎨 Painter for the heatmap timeline — continuous gradient with date labels
class _TimelineHeatmapPainter extends CustomPainter {
  final List<int> density;
  final double maxDensity;
  final double progress;
  final List<({double position, DateTime date})> dateMarkers;

  // M3 colors
  final Color activeColor;
  final Color activeColorLight;
  final Color inactiveColor;
  final Color inactiveColorLight;
  final Color labelColor;
  final Color playheadColor;
  final Color playheadGlow;

  _TimelineHeatmapPainter({
    required this.density,
    required this.maxDensity,
    required this.progress,
    required this.dateMarkers,
    required this.activeColor,
    required this.activeColorLight,
    required this.inactiveColor,
    required this.inactiveColorLight,
    required this.labelColor,
    required this.playheadColor,
    required this.playheadGlow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Layout: date labels in alto (16px), heatmap in basso (resto)
    const dateAreaHeight = 16.0;
    final heatmapTop = dateAreaHeight + 2;
    final heatmapHeight = height - heatmapTop;
    final heatmapCenter = heatmapTop + heatmapHeight / 2;

    // ─── Background track (rounded) ────────────────────
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        0,
        heatmapTop + heatmapHeight * 0.2,
        width,
        heatmapHeight * 0.6,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(bgRect, Paint()..color = inactiveColor);

    // ─── Played portion fill ──────────────────────────
    final playedWidth = width * progress;
    if (playedWidth > 0) {
      final playedRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(
          0,
          heatmapTop + heatmapHeight * 0.2,
          playedWidth,
          heatmapHeight * 0.6,
        ),
        topLeft: const Radius.circular(6),
        bottomLeft: const Radius.circular(6),
      );
      canvas.drawRRect(
        playedRect,
        Paint()..color = activeColorLight.withValues(alpha: 0.3),
      );
    }

    // ─── Continuous gradient (log scale) ────────────────
    if (density.isNotEmpty && maxDensity > 0) {
      final logMax = math.log(1 + maxDensity);
      final segmentWidth = width / density.length;

      for (int i = 0; i < density.length; i++) {
        if (density[i] <= 0) continue;

        // Scala logaritmica
        final logIntensity = math.log(1 + density[i]) / logMax;
        final barHeight = (heatmapHeight * 0.8) * logIntensity;
        final y = heatmapCenter - barHeight / 2;

        final isBeforeProgress = (i / density.length) <= progress;
        final color =
            isBeforeProgress
                ? Color.lerp(activeColorLight, activeColor, logIntensity)!
                : Color.lerp(
                  inactiveColor.withValues(alpha: 0.6),
                  inactiveColorLight,
                  logIntensity,
                )!;

        // Thin bars without gap → continuous visual result
        canvas.drawRect(
          Rect.fromLTWH(i * segmentWidth, y, segmentWidth + 0.5, barHeight),
          Paint()..color = color,
        );
      }
    }

    // ─── Date labels (anti-overlap) ───────────────────
    _paintDateLabels(canvas, size, dateAreaHeight);

    // ─── Playhead ─────────────────────────────────────
    final playheadX = progress * width;

    // Glow
    canvas.drawCircle(
      Offset(playheadX, heatmapCenter),
      7,
      Paint()
        ..color = playheadGlow.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Linea
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(playheadX, heatmapCenter),
          width: 2.5,
          height: heatmapHeight - 4,
        ),
        const Radius.circular(1.5),
      ),
      Paint()..color = playheadColor,
    );

    // Cerchio
    canvas.drawCircle(
      Offset(playheadX, heatmapCenter),
      5,
      Paint()..color = playheadColor,
    );

    // Inner dot
    canvas.drawCircle(
      Offset(playheadX, heatmapCenter),
      2,
      Paint()..color = activeColor,
    );
  }

  /// 📅 Draw le date labels con anti-overlap
  void _paintDateLabels(Canvas canvas, Size size, double areaHeight) {
    if (dateMarkers.isEmpty) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const minSpacing = 60.0; // px minimo tra etichette

    // Prepara label con position
    final labels = <({double x, String text})>[];
    for (final marker in dateMarkers) {
      final x = marker.position * size.width;
      final text = _formatDateLabel(marker.date, today, now);
      labels.add((x: x, text: text));
    }

    // Anti-overlap: mantieni solo quelle con spazio sufficiente
    final visible = <({double x, String text})>[];
    for (int i = 0; i < labels.length; i++) {
      if (i == 0) {
        // First always visible
        visible.add(labels[i]);
      } else if (i == labels.length - 1) {
        // Last always visible (if no overlap with the second-to-last visible)
        if (visible.isEmpty || (labels[i].x - visible.last.x) >= minSpacing) {
          visible.add(labels[i]);
        }
      } else {
        // Intermedie: only if c'è spazio
        if (visible.isEmpty || (labels[i].x - visible.last.x) >= minSpacing) {
          visible.add(labels[i]);
        }
      }
    }

    // Draw
    for (final label in visible) {
      final tp = TextPainter(
        text: TextSpan(
          text: label.text,
          style: TextStyle(
            color: labelColor,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      // Centra la label sulla position, clamp ai bordi
      final labelX = (label.x - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(labelX, (areaHeight - tp.height) / 2));

      // Linea sottile dal label alla heatmap
      canvas.drawLine(
        Offset(label.x, areaHeight - 1),
        Offset(label.x, areaHeight + 3),
        Paint()
          ..color = labelColor.withValues(alpha: 0.3)
          ..strokeWidth = 1,
      );
    }
  }

  /// Formatta data per etichetta compatta
  String _formatDateLabel(DateTime dt, DateTime today, DateTime now) {
    final eventDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(eventDay).inDays;

    if (diff == 0) return 'Oggi';
    if (diff == 1) return 'Ieri';
    if (dt.year == now.year) {
      return DateFormat('d MMM').format(dt);
    }
    return DateFormat('d MMM y').format(dt);
  }

  @override
  bool shouldRepaint(covariant _TimelineHeatmapPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.density != density ||
        oldDelegate.dateMarkers != dateMarkers;
  }
}
