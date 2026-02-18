part of '../../nebula_canvas_screen.dart';

/// 🎬 Premium loading overlay — shown during canvas initialization.
///
/// Displays the Fluera logo with a pulsing animation and a thin progress bar.
/// Fades out smoothly when loading completes (`_isLoading` → `false`).
extension LoadingOverlayExtension on _NebulaCanvasScreenState {
  /// Builds the loading overlay. Returns [SizedBox.shrink] after fade-out.
  Widget _buildLoadingOverlay() {
    return AnimatedOpacity(
      opacity: _isLoading ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      onEnd: () {
        // Remove overlay from tree after fade-out completes
        if (!_isLoading && mounted) {
          setState(() {
            _loadingOverlayDismissed = true;
          });
        }
      },
      child:
          _loadingOverlayDismissed
              ? const SizedBox.shrink()
              : _CanvasLoadingScreen(
                logoAssetPath:
                    _config.splashLogoAsset ??
                    'assets/textures/images/fluera_logo.png',
                packageName:
                    _config.splashLogoAsset == null ? 'nebula_engine' : null,
              ),
    );
  }
}

/// 🎨 The actual loading screen widget (StatefulWidget for animation).
class _CanvasLoadingScreen extends StatefulWidget {
  final String logoAssetPath;
  final String? packageName;

  const _CanvasLoadingScreen({required this.logoAssetPath, this.packageName});

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
    return Positioned.fill(
      child: Container(
        color: const Color(0xFF1A1A2E),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🏷️ Pulsing logo
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Opacity(opacity: _pulseAnimation.value, child: child);
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
      ),
    );
  }
}
