import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../systems/animation_timeline.dart';
import '../../systems/animation_player.dart';
import '../../systems/stagger_animation.dart';
import '../../systems/spring_simulation.dart';
import '../../systems/path_motion.dart';

// ============================================================================
// 🎬 ANIMATION TIMELINE PANEL — Keyframe timeline with playback controls
// ============================================================================

class AnimationTimelinePanel extends StatefulWidget {
  const AnimationTimelinePanel({super.key});

  @override
  State<AnimationTimelinePanel> createState() => _AnimationTimelinePanelState();
}

class _AnimationTimelinePanelState extends State<AnimationTimelinePanel>
    with SingleTickerProviderStateMixin {
  bool _isPlaying = false;
  double _progress = 0.0;
  bool _isLooping = false;
  late AnimationController _playbackController;

  @override
  void initState() {
    super.initState();
    _playbackController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addListener(() {
      setState(() => _progress = _playbackController.value);
    });
  }

  @override
  void dispose() {
    _playbackController.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    HapticFeedback.selectionClick();
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      _playbackController.repeat();
    } else {
      _playbackController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.15,
      maxChildSize: 0.6,
      builder:
          (ctx, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header with controls
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.animation_rounded,
                        color: cs.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Animation Timeline',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      // Loop toggle
                      IconButton(
                        icon: Icon(
                          Icons.loop_rounded,
                          color: _isLooping ? cs.primary : cs.onSurfaceVariant,
                          size: 20,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _isLooping = !_isLooping);
                        },
                        tooltip: 'Loop',
                      ),
                      // Play/Pause
                      IconButton.filled(
                        icon: Icon(
                          _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 22,
                        ),
                        onPressed: _togglePlayback,
                        tooltip: _isPlaying ? 'Pause' : 'Play',
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                // Progress bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          activeTrackColor: cs.primary,
                          inactiveTrackColor: cs.surfaceContainerHighest,
                          thumbColor: cs.primary,
                        ),
                        child: Slider(
                          value: _progress,
                          onChanged: (v) {
                            setState(() => _progress = v);
                            _playbackController.value = v;
                          },
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${(_progress * 2000).toInt()}ms',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            '2000ms',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Keyframe tracks
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    children: [
                      _KeyframeTrack(
                        label: 'Position X',
                        color: Colors.blue,
                        cs: cs,
                      ),
                      const SizedBox(height: 6),
                      _KeyframeTrack(
                        label: 'Position Y',
                        color: Colors.green,
                        cs: cs,
                      ),
                      const SizedBox(height: 6),
                      _KeyframeTrack(
                        label: 'Opacity',
                        color: Colors.orange,
                        cs: cs,
                      ),
                      const SizedBox(height: 6),
                      _KeyframeTrack(
                        label: 'Rotation',
                        color: Colors.purple,
                        cs: cs,
                      ),
                      const SizedBox(height: 6),
                      _KeyframeTrack(label: 'Scale', color: Colors.red, cs: cs),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

class _KeyframeTrack extends StatelessWidget {
  final String label;
  final Color color;
  final ColorScheme cs;

  const _KeyframeTrack({
    required this.label,
    required this.color,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                // Keyframe dots
                Positioned(
                  left: 10,
                  top: 12,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  right: 30,
                  top: 12,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
