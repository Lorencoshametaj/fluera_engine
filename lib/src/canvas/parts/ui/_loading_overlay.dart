part of '../../fluera_canvas_screen.dart';

/// 🎬 Premium loading overlay — shown during canvas initialization.
///
/// Displays either:
/// 1. A blurred snapshot preview of the last saved canvas state (if available)
/// 2. The Fluera logo with a pulsing animation (fallback)
///
/// Both variants show a thin progress bar. The overlay fades out smoothly
/// when loading completes (`_isLoadingNotifier` → `false`).
extension LoadingOverlayExtension on _FlueraCanvasScreenState {
  /// Builds the loading overlay. Returns [SizedBox.shrink] after fade-out.
  /// 🚀 P99 FIX: Uses ValueListenableBuilder so this section rebuilds
  /// independently — parent setState calls don't touch it.
  Widget _buildLoadingOverlay() {
    if (_loadingOverlayDismissed) return const SizedBox.shrink();

    return Positioned.fill(
      child: ValueListenableBuilder<bool>(
        valueListenable: _isLoadingNotifier,
        builder: (context, isLoading, child) {
          return AnimatedOpacity(
            opacity: isLoading ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            onEnd: () {
              // Remove overlay from tree after fade-out completes
              if (!isLoading && mounted) {
                setState(() {
                  _loadingOverlayDismissed = true;
                });
              }
            },
            child: child!,
          );
        },
        child: _CanvasLoadingScreen(
          logoAssetPath:
              _config.splashLogoAsset ??
              'assets/textures/images/fluera_logo.png',
          packageName: _config.splashLogoAsset == null ? 'fluera_engine' : null,
          snapshotPng: _splashSnapshot,
        ),
      ),
    );
  }
}

/// 🎨 The actual loading screen widget (StatefulWidget for animation).
class _CanvasLoadingScreen extends StatefulWidget {
  final String logoAssetPath;
  final String? packageName;
  final Uint8List? snapshotPng;

  const _CanvasLoadingScreen({
    required this.logoAssetPath,
    this.packageName,
    this.snapshotPng,
  });

  @override
  State<_CanvasLoadingScreen> createState() => _CanvasLoadingScreenState();
}

class _CanvasLoadingScreenState extends State<_CanvasLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSnapshot = widget.snapshotPng != null;

    return Container(
      color: const Color(0xFF1A1A2E),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 🖼️ Canvas snapshot preview (blurred background)
          if (hasSnapshot)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Image.memory(
                  widget.snapshotPng!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ),

          // 🌑 Dark overlay on top of snapshot for readability
          if (hasSnapshot)
            Positioned.fill(
              child: Container(
                color: const Color(0xFF1A1A2E).withValues(alpha: 0.55),
              ),
            ),

          // 🎯 Center content: logo + progress bar
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🏷️ Pulsing logo
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _pulseAnimation.value,
                      child: child,
                    );
                  },
                  child: Image.asset(
                    widget.logoAssetPath,
                    package: widget.packageName,
                    width: 96,
                    height: 96,
                    errorBuilder:
                        (_, __, ___) => const Icon(
                          Icons.brush_rounded,
                          size: 64,
                          color: Colors.white70,
                        ),
                  ),
                ),

                const SizedBox(height: 32),

                // 📊 Thin progress indicator
                SizedBox(
                  width: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const LinearProgressIndicator(
                      backgroundColor: Color(0xFF2A2A4A),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF6C63FF),
                      ),
                      minHeight: 3,
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
