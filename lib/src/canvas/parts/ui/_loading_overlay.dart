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

class _CanvasLoadingScreenState extends State<_CanvasLoadingScreen> {
  @override
  Widget build(BuildContext context) {
    final hasSnapshot = widget.snapshotPng != null;

    return Container(
      color: const Color(0xFF1A1A2E),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 🖼️ Canvas snapshot preview (blurred background) — gives specificity:
          // the user sees their own canvas, faded, while it fully loads.
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

          // 🎯 Center content — minimal.
          // With snapshot: only a thin progress bar (the snapshot IS the feedback).
          // Without snapshot: static logo + progress bar + "Apertura…" text.
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!hasSnapshot) ...[
                  Image.asset(
                    widget.logoAssetPath,
                    package: widget.packageName,
                    width: 64,
                    height: 64,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.brush_rounded,
                      size: 48,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

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

                if (!hasSnapshot) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Apertura\u2026',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
