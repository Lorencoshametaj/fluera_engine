import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 🔍 CLUSTER PREVIEW OVERLAY — Premium enlarged thumbnail popup.
///
/// Shows when the user long-presses a bubble without dragging.
/// Displays an enlarged version of the mini-thumbnail with cluster metadata.
///
/// PREMIUM FEATURES:
/// - Animated fade+scale entrance with upward parallax drift
/// - True glassmorphism with BackdropFilter
/// - Animated gradient border (rotating hue)
/// - White thumbnail background for crisp contrast
/// - Connection count indicator
/// - "Vai" zoom-to button with spring animation
class ClusterPreviewOverlay extends StatefulWidget {
  /// The thumbnail image to display enlarged.
  final ui.Image? thumbnail;

  /// Cluster display label (e.g., "3 tratti • 2 forme").
  final String label;

  /// Number of elements in the cluster.
  final int elementCount;

  /// Number of connections from/to this cluster.
  final int connectionCount;

  /// Accent color matching the cluster's theme.
  final Color accentColor;

  /// Called when the user dismisses the preview.
  final VoidCallback onDismiss;

  /// Called when the user taps to zoom-to-cluster.
  final VoidCallback? onZoomTo;

  const ClusterPreviewOverlay({
    super.key,
    required this.thumbnail,
    required this.label,
    required this.elementCount,
    this.connectionCount = 0,
    required this.accentColor,
    required this.onDismiss,
    this.onZoomTo,
  });

  @override
  State<ClusterPreviewOverlay> createState() => _ClusterPreviewOverlayState();
}

class _ClusterPreviewOverlayState extends State<ClusterPreviewOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _slideAnim;

  // Gradient border animation
  late final AnimationController _borderController;

  @override
  void initState() {
    super.initState();

    // Entrance: fade + scale + upward parallax
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );
    // Parallax: slides up 12px during entrance
    _slideAnim = Tween<double>(begin: 12.0, end: 0.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _entranceController.forward();

    // Gradient border: slow continuous rotation
    _borderController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  void dismiss() {
    widget.onDismiss();
    _entranceController.reverse();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _borderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    final hasThumbnail = widget.thumbnail != null;

    return AnimatedBuilder(
      animation: _slideAnim,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _slideAnim.value),
        child: child,
      ),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Material(
            color: Colors.transparent,
            child: AnimatedBuilder(
              animation: _borderController,
              builder: (context, child) {
                // Rotating gradient angle for animated border
                final angle = _borderController.value * 2 * math.pi;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 210,
                      decoration: BoxDecoration(
                        color: const Color(0xCC0A0A12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.transparent,
                          width: 1.5,
                        ),
                        gradient: null,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: accent.withValues(alpha: 0.1),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.transparent,
                          width: 1.5,
                        ),
                        gradient: SweepGradient(
                          center: Alignment.center,
                          startAngle: angle,
                          endAngle: angle + 2 * math.pi,
                          colors: [
                            accent.withValues(alpha: 0.5),
                            accent.withValues(alpha: 0.1),
                            Colors.white.withValues(alpha: 0.15),
                            accent.withValues(alpha: 0.1),
                            accent.withValues(alpha: 0.5),
                          ],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Thumbnail preview ──
                          Container(
                            height: 150,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              // White bg for crisp thumbnail contrast
                              color: hasThumbnail
                                  ? Colors.white.withValues(alpha: 0.95)
                                  : Colors.white.withValues(alpha: 0.03),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(15),
                              ),
                            ),
                            child: hasThumbnail
                                ? ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(15),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: RawImage(
                                        image: widget.thumbnail,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.draw_rounded,
                                          size: 36,
                                          color: accent.withValues(alpha: 0.4),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Anteprima',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.white
                                                .withValues(alpha: 0.3),
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),

                          // ── Info bar ──
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Accent glow dot
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      colors: [
                                        accent,
                                        accent.withValues(alpha: 0.3),
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: accent.withValues(alpha: 0.5),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Cluster info
                                Expanded(
                                  child: Text(
                                    widget.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          Colors.white.withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ── Connection count + Zoom button ──
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            child: Row(
                              children: [
                                // Connection count
                                if (widget.connectionCount > 0) ...[
                                  Icon(
                                    Icons.link_rounded,
                                    size: 12,
                                    color:
                                        Colors.white.withValues(alpha: 0.35),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${widget.connectionCount} connessioni',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white
                                          .withValues(alpha: 0.35),
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                // Zoom-to button
                                if (widget.onZoomTo != null)
                                  GestureDetector(
                                    onTap: () {
                                      widget.onZoomTo!();
                                      _entranceController.reverse();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            accent.withValues(alpha: 0.3),
                                            accent.withValues(alpha: 0.15),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: accent.withValues(alpha: 0.2),
                                          width: 0.5,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.zoom_in_rounded,
                                            size: 13,
                                            color: accent,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Vai',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: accent,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
