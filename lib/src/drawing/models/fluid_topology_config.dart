/// 🌊 FLUID TOPOLOGY CONFIG — Immutable simulation parameters.
///
/// Controls diffusion speed, drying, viscosity, surface tension,
/// and grid resolution for the fluid topology engine.
///
/// Design mirrors [LiquidCanvasConfig]: immutable, passed at construction,
/// zero cost when `enabled == false`.
///
/// ```dart
/// // Use a preset
/// final config = FluidTopologyConfig.watercolor;
///
/// // Or customize
/// final custom = FluidTopologyConfig(
///   diffusionRate: 0.15,
///   viscosity: 0.3,
/// );
/// ```
library;

/// Immutable configuration for the fluid topology simulation.
class FluidTopologyConfig {
  /// Pigment diffusion rate per simulation tick.
  /// Higher = faster spread. Range: 0.01–0.5.
  final double diffusionRate;

  /// Wetness evaporation rate (exponential decay constant λ).
  /// Higher = faster drying. Range: 0.0005–0.01.
  final double evaporationRate;

  /// Surface tension coefficient.
  /// 0.0 = water (spreads freely), 1.0 = oil (cohesive, resists spread).
  final double surfaceTension;

  /// Viscosity coefficient — resistance to flow.
  /// 0.0 = watercolor (flows easily), 1.0 = thick oil paint.
  final double viscosity;

  /// Grid resolution in world pixels per cell.
  /// Lower = higher quality but more computation. Range: 4–16.
  final int gridResolution;

  /// Maximum number of active cells before pruning aggressively.
  /// Prevents unbounded memory growth on large canvases.
  final int maxActiveCells;

  /// Simulation tick rate in Hz. Decoupled from render frame rate.
  /// 30Hz is a good balance between quality and CPU cost.
  final double tickRate;

  /// Minimum pigment density below which a cell is pruned.
  /// Lower = longer-lasting faint traces, higher = faster cleanup.
  final double pruneThreshold;

  /// Gravity strength (px/s²). Pulls wet pigment downward.
  /// 0.0 = no gravity (abstract), ~20.0 = realistic watercolor sag.
  final double gravity;

  /// Capillary rate — wetness spread into dry neighbor cells.
  /// Simulates paper fiber wicking. Range: 0.0–0.3.
  final double capillaryRate;

  /// Edge darkening strength — pigment concentrates at drying edges
  /// (cauliflower effect). Range: 0.0–1.0.
  final double edgeDarkeningStrength;

  /// Noise amplitude for diffusion perturbation.
  /// Breaks grid-axis symmetry for organic blooming. Range: 0.0–0.5.
  final double noiseAmplitude;

  /// Paper granulation strength [0.0–1.0].
  /// Controls how much pigment settles into paper grain valleys.
  /// 0.0 = smooth, 1.0 = heavily granulated (like cold-pressed paper).
  final double granulationStrength;

  /// Backrun threshold — wetness difference that triggers blooming.
  /// When a wet stroke meets a nearly-dry area with wetness above this
  /// threshold, the new water pushes old pigment outward. Range: 0.05–0.5.
  final double backrunThreshold;

  /// Subtractive blend weight for color mixing [0.0–1.0].
  /// 0.0 = pure linear (additive), 1.0 = fully subtractive (Kubelka-Munk).
  final double subtractiveBlend;

  /// Paper fiber angle in radians [0–2π].
  /// Controls the preferred direction of anisotropic diffusion.
  /// 0 = horizontal fibers, π/2 = vertical fibers.
  final double fiberAngle;

  /// Wet-on-wet turbulence strength [0.0–1.0].
  /// When two wet areas overlap, pigment gets turbulent mixing.
  /// 0.0 = calm mixing, 1.0 = chaotic turbulence.
  final double wetOnWetTurbulence;

  /// Staining factor [0.0–1.0].
  /// How quickly pigment bonds permanently to the surface.
  /// Stained pigment resists lifting during backruns.
  final double stainingFactor;

  /// Whether the fluid simulation is enabled.
  final bool enabled;

  const FluidTopologyConfig({
    this.diffusionRate = 0.08,
    this.evaporationRate = 0.002,
    this.surfaceTension = 0.3,
    this.viscosity = 0.2,
    this.gridResolution = 6,
    this.maxActiveCells = 10000,
    this.tickRate = 30.0,
    this.pruneThreshold = 0.005,
    this.gravity = 8.0,
    this.capillaryRate = 0.05,
    this.edgeDarkeningStrength = 0.4,
    this.noiseAmplitude = 0.15,
    this.granulationStrength = 0.3,
    this.backrunThreshold = 0.15,
    this.subtractiveBlend = 0.4,
    this.fiberAngle = 0.0,
    this.wetOnWetTurbulence = 0.3,
    this.stainingFactor = 0.2,
    this.enabled = true,
  });

  // ===========================================================================
  // PRESETS
  // ===========================================================================

  /// Watercolor preset — fast diffusion, strong capillary, gravity sag.
  static const watercolor = FluidTopologyConfig(
    diffusionRate: 0.15,
    evaporationRate: 0.001,
    surfaceTension: 0.1,
    viscosity: 0.05,
    gridResolution: 6,
    gravity: 15.0,
    capillaryRate: 0.12,
    edgeDarkeningStrength: 0.6,
    noiseAmplitude: 0.25,
    granulationStrength: 0.5,
    backrunThreshold: 0.1,
    subtractiveBlend: 0.5,
    fiberAngle: 0.1,
    wetOnWetTurbulence: 0.5,
    stainingFactor: 0.15,
  );

  /// Ink wash (sumi-e) preset — moderate diffusion, medium gravity.
  static const inkWash = FluidTopologyConfig(
    diffusionRate: 0.10,
    evaporationRate: 0.0015,
    surfaceTension: 0.2,
    viscosity: 0.15,
    gridResolution: 6,
    gravity: 10.0,
    capillaryRate: 0.08,
    edgeDarkeningStrength: 0.5,
    noiseAmplitude: 0.18,
    granulationStrength: 0.35,
    backrunThreshold: 0.12,
    subtractiveBlend: 0.6,
    fiberAngle: 0.0,
    wetOnWetTurbulence: 0.3,
    stainingFactor: 0.3,
  );

  /// Oil paint preset — minimal flow, very high viscosity.
  static const oilPaint = FluidTopologyConfig(
    diffusionRate: 0.02,
    evaporationRate: 0.0003,
    surfaceTension: 0.8,
    viscosity: 0.85,
    gridResolution: 8,
    gravity: 2.0,
    capillaryRate: 0.01,
    edgeDarkeningStrength: 0.1,
    noiseAmplitude: 0.05,
    granulationStrength: 0.1,
    backrunThreshold: 0.3,
    subtractiveBlend: 0.2,
    fiberAngle: 0.0,
    wetOnWetTurbulence: 0.1,
    stainingFactor: 0.5,
  );

  /// Disabled — all simulation off. Zero performance cost.
  static const disabled = FluidTopologyConfig(enabled: false);

  // ===========================================================================
  // SERIALIZATION
  // ===========================================================================

  Map<String, dynamic> toJson() => {
    'dr': diffusionRate,
    'er': evaporationRate,
    'st': surfaceTension,
    'vi': viscosity,
    'gr': gridResolution,
    'mc': maxActiveCells,
    'tr': tickRate,
    'pt': pruneThreshold,
    'gv': gravity,
    'cp': capillaryRate,
    'ed': edgeDarkeningStrength,
    'na': noiseAmplitude,
    'gs': granulationStrength,
    'bt': backrunThreshold,
    'sb': subtractiveBlend,
    'fa': fiberAngle,
    'wt': wetOnWetTurbulence,
    'sf': stainingFactor,
    'en': enabled,
  };

  factory FluidTopologyConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FluidTopologyConfig();
    return FluidTopologyConfig(
      diffusionRate: (json['dr'] as num?)?.toDouble() ?? 0.08,
      evaporationRate: (json['er'] as num?)?.toDouble() ?? 0.002,
      surfaceTension: (json['st'] as num?)?.toDouble() ?? 0.3,
      viscosity: (json['vi'] as num?)?.toDouble() ?? 0.2,
      gridResolution: (json['gr'] as num?)?.toInt() ?? 6,
      maxActiveCells: (json['mc'] as num?)?.toInt() ?? 10000,
      tickRate: (json['tr'] as num?)?.toDouble() ?? 30.0,
      pruneThreshold: (json['pt'] as num?)?.toDouble() ?? 0.005,
      gravity: (json['gv'] as num?)?.toDouble() ?? 8.0,
      capillaryRate: (json['cp'] as num?)?.toDouble() ?? 0.05,
      edgeDarkeningStrength: (json['ed'] as num?)?.toDouble() ?? 0.4,
      noiseAmplitude: (json['na'] as num?)?.toDouble() ?? 0.15,
      granulationStrength: (json['gs'] as num?)?.toDouble() ?? 0.3,
      backrunThreshold: (json['bt'] as num?)?.toDouble() ?? 0.15,
      subtractiveBlend: (json['sb'] as num?)?.toDouble() ?? 0.4,
      fiberAngle: (json['fa'] as num?)?.toDouble() ?? 0.0,
      wetOnWetTurbulence: (json['wt'] as num?)?.toDouble() ?? 0.3,
      stainingFactor: (json['sf'] as num?)?.toDouble() ?? 0.2,
      enabled: (json['en'] as bool?) ?? true,
    );
  }

  FluidTopologyConfig copyWith({
    double? diffusionRate,
    double? evaporationRate,
    double? surfaceTension,
    double? viscosity,
    int? gridResolution,
    int? maxActiveCells,
    double? tickRate,
    double? pruneThreshold,
    double? gravity,
    double? capillaryRate,
    double? edgeDarkeningStrength,
    double? noiseAmplitude,
    double? granulationStrength,
    double? backrunThreshold,
    double? subtractiveBlend,
    double? fiberAngle,
    double? wetOnWetTurbulence,
    double? stainingFactor,
    bool? enabled,
  }) => FluidTopologyConfig(
    diffusionRate: diffusionRate ?? this.diffusionRate,
    evaporationRate: evaporationRate ?? this.evaporationRate,
    surfaceTension: surfaceTension ?? this.surfaceTension,
    viscosity: viscosity ?? this.viscosity,
    gridResolution: gridResolution ?? this.gridResolution,
    maxActiveCells: maxActiveCells ?? this.maxActiveCells,
    tickRate: tickRate ?? this.tickRate,
    pruneThreshold: pruneThreshold ?? this.pruneThreshold,
    gravity: gravity ?? this.gravity,
    capillaryRate: capillaryRate ?? this.capillaryRate,
    edgeDarkeningStrength: edgeDarkeningStrength ?? this.edgeDarkeningStrength,
    noiseAmplitude: noiseAmplitude ?? this.noiseAmplitude,
    granulationStrength: granulationStrength ?? this.granulationStrength,
    backrunThreshold: backrunThreshold ?? this.backrunThreshold,
    subtractiveBlend: subtractiveBlend ?? this.subtractiveBlend,
    fiberAngle: fiberAngle ?? this.fiberAngle,
    wetOnWetTurbulence: wetOnWetTurbulence ?? this.wetOnWetTurbulence,
    stainingFactor: stainingFactor ?? this.stainingFactor,
    enabled: enabled ?? this.enabled,
  );

  @override
  String toString() =>
      'FluidTopologyConfig(diffusion: $diffusionRate, evaporation: $evaporationRate, '
      'tension: $surfaceTension, viscosity: $viscosity, grid: ${gridResolution}px, '
      'enabled: $enabled)';
}
