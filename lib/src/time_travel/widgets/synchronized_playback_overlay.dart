import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../controllers/synchronized_playback_controller.dart';
import '../../drawing/brushes/brushes.dart';

/// 🎵 SYNCHRONIZED PLAYBACK OVERLAY
///
/// Widget overlay showing synchronized stroke playback
/// mentre l'audio is being played. I tratti si "disegnano" progressivamente
/// following the original recording timing.
class SynchronizedPlaybackOverlay extends StatelessWidget {
  final SynchronizedPlaybackController controller;
  final Offset canvasOffset;
  final double canvasScale;
  final VoidCallback? onClose;
  final Color backgroundColor;
  final VoidCallback?
  onNavigateToDrawing; // 🧭 Callback to navigate to drawing
  final void Function(int pageIndex)?
  onNavigateToPage; // 📄 Callback per navigare a una specific page
  final bool showControls; // 🎛️ Mostra controlli interattivi
  final int? forcePageIndex; // 📄 Forza rendering for aa specific page

  const SynchronizedPlaybackOverlay({
    super.key,
    required this.controller,
    required this.canvasOffset,
    required this.canvasScale,
    this.onClose,
    this.backgroundColor = Colors.white,
    this.onNavigateToDrawing,
    this.onNavigateToPage,
    this.showControls = true,
    this.forcePageIndex,
  });

  /// 🧭 Calculate if the punto di disegno corrente is visible nella viewport
  bool _isDrawingVisible(Offset? drawingPos, Size viewportSize) {
    if (drawingPos == null) return true;

    // Convert position canvas in position schermo
    final screenX = drawingPos.dx * canvasScale + canvasOffset.dx;
    final screenY = drawingPos.dy * canvasScale + canvasOffset.dy;

    // Margine per considerare "visibile" (un po' dentro lo schermo)
    const margin = 50.0;

    return screenX >= -margin &&
        screenX <= viewportSize.width + margin &&
        screenY >= -margin &&
        screenY <= viewportSize.height + margin;
  }

  /// 🧭 Calculate l'angolo della an arrow verso il punto di disegno
  double _calculateArrowAngle(Offset drawingPos, Size viewportSize) {
    // Center of the viewport
    final centerX = viewportSize.width / 2;
    final centerY = viewportSize.height / 2;

    // Position of the drawing in screen coordinates
    final screenX = drawingPos.dx * canvasScale + canvasOffset.dx;
    final screenY = drawingPos.dy * canvasScale + canvasOffset.dy;

    // Calculate angolo dal centro verso il punto
    final dx = screenX - centerX;
    final dy = screenY - centerY;

    return math.atan2(dy, dx);
  }

  /// 🧭 Calculate la distanza dal centro della viewport al disegno
  double _calculateDistance(Offset drawingPos, Size viewportSize) {
    final centerX = viewportSize.width / 2;
    final centerY = viewportSize.height / 2;

    final screenX = drawingPos.dx * canvasScale + canvasOffset.dx;
    final screenY = drawingPos.dy * canvasScale + canvasOffset.dy;

    final dx = screenX - centerX;
    final dy = screenY - centerY;

    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            // 📄 Retrieve specific strokes for the page (if forced) or current
            final activeStrokes =
                forcePageIndex != null
                    ? controller.getActiveStrokesForPage(forcePageIndex!)
                    : controller.activeStrokes;
            final ghostStrokes =
                forcePageIndex != null
                    ? controller.getGhostStrokesForPage(forcePageIndex!)
                    : controller.ghostStrokes;

            // 🧭 Calculate drawing position using same activeStrokes as rendering
            // This fix ensures that l'indicator works even con forcePageIndex (split view)
            Offset? drawingPos;
            if (activeStrokes.isNotEmpty) {
              final lastStroke = activeStrokes.last;
              if (lastStroke.points.isNotEmpty) {
                drawingPos = lastStroke.points.last.position;
              }
            }
            final isVisible = _isDrawingVisible(drawingPos, viewportSize);

            return Stack(
              children: [
                // 🎨 Layer tratti con sfondo to cover i original strokes
                // Use IgnorePointer per permettere tocchi al canvas sotto
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true, // Forza passthrough di tutti gli eventi
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _SyncedStrokesPainter(
                          activeStrokes: activeStrokes,
                          ghostStrokes: ghostStrokes,
                          canvasOffset: canvasOffset,
                          canvasScale: canvasScale,
                          backgroundColor: backgroundColor,
                          ghostOpacity:
                              controller
                                  .ghostOpacity, // 🎚️ Opacity controllabile
                        ),
                        size: Size.infinite,
                        willChange: true, // Optimization for animations
                      ),
                    ),
                  ),
                ),

                // 🧭 STROKE COMPASS - show drawing direction if off-screen
                if (!isVisible && drawingPos != null)
                  Positioned.fill(
                    child: _StrokeCompass(
                      angle: _calculateArrowAngle(drawingPos, viewportSize),
                      distance: _calculateDistance(drawingPos, viewportSize),
                      onTap: onNavigateToDrawing,
                    ),
                  ),

                // 📄 INDICATORE PAGINA - mostra on which page sta la riproduzione
                // NON mostrare per registrazioni 'note' (solo per PDF)
                if (showControls &&
                    controller.isPlayingOnDifferentPage &&
                    controller.recording?.recordingType ==
                        'pdf') // Only per PDF
                  Positioned(
                    top: 80,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _PageIndicatorBadge(
                        pageNumber: (controller.activeDrawingPage ?? 0) + 1,
                        onTap: () {
                          final activePage = controller.activeDrawingPage;
                          if (activePage != null && onNavigateToPage != null) {
                            onNavigateToPage!(activePage);
                          }
                        },
                      ),
                    ),
                  ),

                // 🎛️ Barra controlli: Questa SÌ deve essere interattiva
                // Positionta in modo da non coprire troppo il canvas
                if (showControls)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: _PlaybackControlsBar(
                      controller: controller,
                      onClose: onClose,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// 🧭 STROKE COMPASS
/// Widget showing an arrow indicating the drawing direction
class _StrokeCompass extends StatelessWidget {
  final double angle; // Angolo in radianti
  final double distance; // Distanza dal centro
  final VoidCallback? onTap;

  const _StrokeCompass({
    required this.angle,
    required this.distance,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate position della an arrow sul bordo dello schermo
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerX = constraints.maxWidth / 2;
        final centerY = constraints.maxHeight / 2;

        // Distanza dal centro al bordo (approssimata)
        final maxRadius = math.min(centerX, centerY) - 60;

        // Position della an arrow
        final arrowX = centerX + math.cos(angle) * maxRadius;
        final arrowY = centerY + math.sin(angle) * maxRadius;

        // Calculate intensity del colore basata sulla distanza
        final normalizedDistance = (distance / 1000).clamp(0.0, 1.0);
        final color = Color.lerp(Colors.amber, Colors.red, normalizedDistance)!;

        return Stack(
          children: [
            // Freccia indicatore
            Positioned(
              left: arrowX - 30,
              top: arrowY - 30,
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Transform.rotate(
                    angle: angle,
                    child: const Icon(
                      Icons.arrow_forward,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),

            // Etichetta "Vai al disegno"
            Positioned(
              left: arrowX - 50,
              top: arrowY + 35,
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Vai al disegno',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 📄 INDICATORE PAGINA
/// Widget showing which page playback is occurring on
class _PageIndicatorBadge extends StatelessWidget {
  final int pageNumber;
  final VoidCallback? onTap;

  const _PageIndicatorBadge({required this.pageNumber, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple.shade600, Colors.deepPurple.shade400],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.deepPurple.withValues(alpha: 0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Riproduzione a pagina $pageNumber',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_forward,
                color: Colors.white,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 🎨 Painter per i tratti sincronizzati
class _SyncedStrokesPainter extends CustomPainter {
  final List<ProStroke> activeStrokes;
  final List<ProStroke> ghostStrokes;
  final Offset canvasOffset;
  final double canvasScale;
  final Color backgroundColor;
  final double ghostOpacity; // 🎚️ Opacity glow ghost controllabile

  _SyncedStrokesPainter({
    required this.activeStrokes,
    required this.ghostStrokes,
    required this.canvasOffset,
    required this.canvasScale,
    required this.backgroundColor,
    required this.ghostOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ❌ NIENTE sfondo - il canvas originale resta visibile e interattivo!

    // Applica trasformazione canvas (pan/zoom)
    canvas.save();
    canvas.translate(canvasOffset.dx, canvasOffset.dy);
    canvas.scale(canvasScale);

    // 1. Draw ghost strokes with GLOW to distinguish them from original strokes
    for (final stroke in ghostStrokes) {
      _drawStrokeWithGlow(canvas, stroke, isGhost: true);
    }

    // 2. Draw active strokes con GLOW more intenso
    for (final stroke in activeStrokes) {
      _drawStrokeWithGlow(canvas, stroke, isGhost: false);
    }

    canvas.restore();
  }

  /// Draws uno stroke con effetto glow per distinguerlo dai original strokes
  void _drawStrokeWithGlow(
    Canvas canvas,
    ProStroke stroke, {
    required bool isGhost,
  }) {
    if (stroke.points.isEmpty) return;

    // 🌟 GLOW: disegna prima un contorno luminoso
    // L'opacity ghost is controllata dallo slider nel player!
    // ⚠️ Clamp to ensure opacity is always in the 0.0-1.0 range
    final glowColor =
        isGhost
            ? Colors.blue.withValues(
              alpha: ghostOpacity.clamp(0.0, 1.0),
            ) // Ghost: glow blu (opacity variabile)
            : Colors.amber.withValues(
              alpha: (0.6 + ghostOpacity).clamp(0.0, 1.0),
            ); // Active: glow dorato more intenso

    final glowWidth = stroke.baseWidth + (isGhost ? 6.0 : 10.0);

    // Draw il glow (contorno esterno)
    _drawStrokeSimple(canvas, stroke.points, glowColor, glowWidth);

    // Draw il tratto vero sopra il glow
    _drawStroke(canvas, stroke);
  }

  /// Draws un tratto semplice (for the glow)
  void _drawStrokeSimple(
    Canvas canvas,
    List<ProDrawingPoint> points,
    Color color,
    double width,
  ) {
    if (points.length < 2) return;

    final paint =
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            3.0,
          ); // Blur per effetto glow

    final path = Path();
    path.moveTo(points.first.position.dx, points.first.position.dy);

    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].position.dx, points[i].position.dy);
    }

    canvas.drawPath(path, paint);
  }

  void _drawStroke(Canvas canvas, ProStroke stroke) {
    if (stroke.points.isEmpty) return;

    switch (stroke.penType) {
      case ProPenType.ballpoint:
        BallpointBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
        );
        break;
      case ProPenType.fountain:
        FountainPenBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
        );
        break;
      case ProPenType.pencil:
        PencilBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
        );
        break;
      case ProPenType.highlighter:
        HighlighterBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
        );
        break;
      case ProPenType.watercolor:
      case ProPenType.marker:
      case ProPenType.charcoal:
        // Use ballpoint fallback for playback overlay
        BallpointBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(_SyncedStrokesPainter oldDelegate) {
    return oldDelegate.activeStrokes != activeStrokes ||
        oldDelegate.ghostStrokes != ghostStrokes ||
        oldDelegate.canvasOffset != canvasOffset ||
        oldDelegate.canvasScale != canvasScale;
  }
}

/// 🎛️ Barra controlli playback
class _PlaybackControlsBar extends StatefulWidget {
  final SynchronizedPlaybackController controller;
  final VoidCallback? onClose;

  const _PlaybackControlsBar({required this.controller, this.onClose});

  @override
  State<_PlaybackControlsBar> createState() => _PlaybackControlsBarState();
}

class _PlaybackControlsBarState extends State<_PlaybackControlsBar> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // HEADER ROW: Always visible - responsive based on available width
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 300;

              return Row(
                children: [
                  // Icona e titolo (only if espanso E non compact)
                  if (_isExpanded && !isCompact) ...[
                    const Icon(
                      Icons.music_note,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Riproduzione sincronizzata',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Info strokes (hide in compact)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${widget.controller.visibleStrokesCount}/${widget.controller.totalStrokes}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ] else if (_isExpanded && isCompact) ...[
                    // COMPACT EXPANDED MODE - minimal header
                    const Icon(
                      Icons.music_note,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${widget.controller.visibleStrokesCount}/${widget.controller.totalStrokes}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else ...[
                    // COLLAPSED MODE HEADER
                    // Play/Pause mini
                    IconButton(
                      icon: Icon(
                        widget.controller.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () => widget.controller.togglePlayPause(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      tooltip:
                          widget.controller.isPlaying ? 'Pausa' : 'Riproduci',
                    ),
                    if (!isCompact) ...[
                      const SizedBox(width: 12),
                      // Time / Duration
                      Text(
                        '${_formatDuration(widget.controller.position)} / ${_formatDuration(widget.controller.duration)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                    const Spacer(),
                  ],

                  const SizedBox(width: 8),

                  // Toggle Expand/Collapse Button
                  IconButton(
                    icon: Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      color: Colors.white70,
                      size: 24,
                    ),
                    onPressed: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    tooltip: _isExpanded ? 'Riduci' : 'Espandi',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),

                  // Pulsante chiudi (sempre disponibile)
                  if (widget.onClose != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 20,
                      ),
                      onPressed: widget.onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),

          // EXPANDED BODY
          AnimatedCrossFade(
            firstChild: Container(), // Empty for collapsed
            secondChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),

                // Slider progresso
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                    activeTrackColor: Colors.blue[400],
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: Colors.blue.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: widget.controller.progress,
                    onChanged: (value) {
                      widget.controller.seekToProgress(value);
                    },
                    onChangeStart: (_) {
                      if (widget.controller.isPlaying) {
                        widget.controller.pause();
                      }
                    },
                  ),
                ),

                const SizedBox(height: 8),

                // Riga controlli e tempo - responsive per pannelli stretti
                LayoutBuilder(
                  builder: (context, constraints) {
                    // If pannello is too stretto, usa layout compatto
                    final isNarrow = constraints.maxWidth < 280;

                    if (isNarrow) {
                      // Layout compatto: solo pulsanti essenziali
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Pulsante riavvia
                          IconButton(
                            icon: const Icon(
                              Icons.replay,
                              color: Colors.white70,
                            ),
                            onPressed: () => widget.controller.restart(),
                            iconSize: 20,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),

                          // Pulsante play/pause
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.blue[600],
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: Icon(
                                widget.controller.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              iconSize: 24,
                              onPressed:
                                  () => widget.controller.togglePlayPause(),
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                            ),
                          ),

                          // Stop button
                          IconButton(
                            icon: const Icon(Icons.stop, color: Colors.white70),
                            onPressed: () => widget.controller.stop(),
                            iconSize: 20,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                        ],
                      );
                    }

                    // Layout normale
                    return Row(
                      children: [
                        // Tempo corrente
                        Text(
                          _formatDuration(widget.controller.position),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),

                        const Spacer(),

                        // Pulsante riavvia
                        IconButton(
                          icon: const Icon(Icons.replay, color: Colors.white70),
                          onPressed: () => widget.controller.restart(),
                          tooltip: 'Riavvia',
                        ),

                        // Play/pause button (Main)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.blue[600],
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              widget.controller.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                            ),
                            onPressed:
                                () => widget.controller.togglePlayPause(),
                            tooltip:
                                widget.controller.isPlaying
                                    ? 'Pausa'
                                    : 'Riproduci',
                          ),
                        ),

                        // Stop button
                        IconButton(
                          icon: const Icon(Icons.stop, color: Colors.white70),
                          onPressed: () => widget.controller.stop(),
                          tooltip: 'Stop',
                        ),

                        const Spacer(),

                        // Tempo totale
                        Text(
                          _formatDuration(widget.controller.duration),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 8),

                // Toggle ghost strokes - responsive
                Row(
                  children: [
                    const Icon(
                      Icons.visibility,
                      color: Colors.white54,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Mostra tratti',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Switch(
                      value: widget.controller.showGhostStrokes,
                      onChanged:
                          (value) =>
                              widget.controller.setShowGhostStrokes(value),
                      activeThumbColor: Colors.blue[400],
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),

                // Slider opacity ghost (only if attivo)
                if (widget.controller.showGhostStrokes) ...[
                  Row(
                    children: [
                      Flexible(
                        flex: 0,
                        child: Text(
                          '${(widget.controller.ghostOpacity * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: widget.controller.ghostOpacity,
                          min: 0.05,
                          max: 0.5,
                          onChanged:
                              (value) =>
                                  widget.controller.setGhostOpacity(value),
                          activeColor: Colors.white54,
                          inactiveColor: Colors.white24,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            crossFadeState:
                _isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 🎵 Compact widget to start synchronized playback
/// To use in the list of saved recordings
class SyncedRecordingListItem extends StatelessWidget {
  final String title;
  final Duration duration;
  final int strokeCount;
  final VoidCallback onPlay;
  final VoidCallback? onDelete;

  const SyncedRecordingListItem({
    super.key,
    required this.title,
    required this.duration,
    required this.strokeCount,
    required this.onPlay,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.play_circle_filled,
          color: Colors.blue,
          size: 28,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            _formatDuration(duration),
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(width: 12),
          Icon(Icons.gesture, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            '$strokeCount tratti',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // "Synchronized" indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sync, size: 12, color: Colors.green),
                SizedBox(width: 4),
                Text(
                  'Sync',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onDelete,
              color: Colors.red[400],
            ),
          ],
        ],
      ),
      onTap: onPlay,
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
