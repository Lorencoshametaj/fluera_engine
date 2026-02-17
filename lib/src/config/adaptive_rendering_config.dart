import '../platform/display_capabilities_detector.dart';

/// 🎯 ADAPTIVE RENDERING CONFIG
///
/// Configuretion rendering adattiva basata su refresh rate of the display.
///
/// Filosofia:
/// - 120Hz: Ultra-minimal (no smoothing, aggressive culling, GPU-first)
/// - 90Hz: Balanced (light smoothing, medium culling)
/// - 60Hz: Full features (full smoothing, normal culling)
///
/// Trade-off chiave @ 120Hz:
/// Frame budget = 8.33ms → we must eliminate all non-essential overhead
class AdaptiveRenderingConfig {
  /// Target refresh rate
  final RefreshRate targetRefreshRate;

  /// Frame budget in millisecondi
  final double frameBudgetMs;

  // ============================================================================
  // LOD (Level of Detail) Thresholds
  // ============================================================================

  /// Soglia distanza normalizzata per LOD center (massima quality)
  /// 120Hz: 0.10 | 90Hz: 0.12 | 60Hz: 0.15
  final double lodCenterThreshold;

  /// Soglia distanza normalizzata per LOD medium (buona quality)
  /// 120Hz: 0.30 | 90Hz: 0.35 | 60Hz: 0.40
  final double lodMediumThreshold;

  /// Soglia distanza normalizzata per LOD far (quality accettabile)
  /// 120Hz: 0.60 | 90Hz: 0.65 | 60Hz: 0.70
  final double lodFarThreshold;

  // ============================================================================
  // Input Processing & Smoothing
  // ============================================================================

  /// Enable OneEuroFilter for input smoothing
  /// 120Hz: false (troppo pesante, ~2-3ms overhead)
  /// 60Hz: true (necessario per smooth strokes)
  final bool enableOneEuroFilter;

  /// Enable predictive rendering (ghost trail)
  /// 120Hz: false (overhead ~1ms, non necessario ad alta frequenza)
  /// 60Hz: true (migliora percezione fluidità)
  final bool enablePredictiveRendering;

  /// Massimo number of punti per stroke (hard limit)
  /// 120Hz: 128 (limite aggressivo per rispettare frame budget)
  /// 60Hz: 256 (more punti per maggiore quality)
  final int maxPointsPerStroke;

  // ============================================================================
  // Viewport Culling
  // ============================================================================

  /// Padding viewport per culling (in pixels)
  /// 120Hz: 0px (render ONLY visible elements, zero margin)
  /// 60Hz: 50px (margine per smooth transitions)
  final double viewportPadding;

  /// Enable tile caching for many strokes
  /// 120Hz: false (overhead invalidation > beneficio)
  /// 60Hz: false (direct rendering + LOD more efficiente)
  final bool enableTileCaching;

  const AdaptiveRenderingConfig({
    required this.targetRefreshRate,
    required this.frameBudgetMs,
    required this.lodCenterThreshold,
    required this.lodMediumThreshold,
    required this.lodFarThreshold,
    required this.enableOneEuroFilter,
    required this.enablePredictiveRendering,
    required this.maxPointsPerStroke,
    required this.viewportPadding,
    required this.enableTileCaching,
  });

  /// Factory per creare config ottimale basato su refresh rate
  factory AdaptiveRenderingConfig.forRefreshRate(RefreshRate rate) {
    switch (rate) {
      case RefreshRate.hz144:
      case RefreshRate.hz120:
        // 🔥 ULTRA-PERFORMANCE MODE
        // Frame budget: 8.33ms → eliminate all overhead
        return AdaptiveRenderingConfig(
          targetRefreshRate: rate,
          frameBudgetMs: 1000.0 / rate.value,
          // Ultra-aggressive LOD: only absolute center is full quality
          lodCenterThreshold: 0.10,
          lodMediumThreshold: 0.30,
          lodFarThreshold: 0.60,
          // Input processing: raw, zero latency
          enableOneEuroFilter: false, // Troppo pesante (2-3ms)
          enablePredictiveRendering: false, // Overhead inutile
          maxPointsPerStroke: 128, // Hard limit aggressivo
          // Culling: zero tolerance
          viewportPadding: 0.0, // Render ONLY visible
          enableTileCaching:
              false, // ⚠️ Disableto: bitmap tiles creano texture GPU grandi
        );

      case RefreshRate.hz90:
        // ⚡ BALANCED MODE
        // Frame budget: 11.11ms → possiamo permetterci un po' di smoothing
        return AdaptiveRenderingConfig(
          targetRefreshRate: rate,
          frameBudgetMs: 1000.0 / rate.value,
          // LOD bilanciato
          lodCenterThreshold: 0.12,
          lodMediumThreshold: 0.35,
          lodFarThreshold: 0.65,
          // Light smoothing
          enableOneEuroFilter: true,
          enablePredictiveRendering: false, // Still too much for 11ms
          maxPointsPerStroke: 192,
          // Culling moderato
          viewportPadding: 25.0,
          enableTileCaching:
              false, // ⚠️ Disableto: bitmap tiles creano texture GPU grandi
        );

      case RefreshRate.hz60:
        // ✅ FULL FEATURES MODE
        // Frame budget: 16.67ms → possiamo usare tutte le features
        return AdaptiveRenderingConfig(
          targetRefreshRate: rate,
          frameBudgetMs: 1000.0 / rate.value,
          // LOD normale
          lodCenterThreshold: 0.15,
          lodMediumThreshold: 0.40,
          lodFarThreshold: 0.70,
          // Full smoothing & features
          enableOneEuroFilter: true,
          enablePredictiveRendering: true,
          maxPointsPerStroke: 256,
          // Culling standard
          viewportPadding: 50.0,
          enableTileCaching:
              false, // ⚠️ Disableto: bitmap tiles creano texture GPU grandi
        );
    }
  }

  @override
  String toString() {
    return 'AdaptiveRenderingConfig(\n'
        '  target: $targetRefreshRate,\n'
        '  frameBudget: ${frameBudgetMs.toStringAsFixed(2)}ms,\n'
        '  LOD: [${lodCenterThreshold.toStringAsFixed(2)}, '
        '${lodMediumThreshold.toStringAsFixed(2)}, '
        '${lodFarThreshold.toStringAsFixed(2)}],\n'
        '  smoothing: $enableOneEuroFilter,\n'
        '  predictive: $enablePredictiveRendering,\n'
        '  maxPoints: $maxPointsPerStroke\n'
        ')';
  }
}
