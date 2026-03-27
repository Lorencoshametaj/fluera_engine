import 'dart:math' as math;

/// 🧬 SURFACE MATERIAL — Physical properties of a drawing surface.
///
/// Separates the *medium* from the *tool*: instead of hardcoding material
/// behavior inside each brush, the surface provides physical properties
/// that the [BrushEngine] queries to modify rendering.
///
/// The same brush produces different visual results on different surfaces:
/// - Pencil on smooth paper → clean lines, minimal grain
/// - Pencil on canvas → heavy grain, scattered pigment
/// - Watercolor on watercolor paper → wide spread, high bleed
/// - Watercolor on glass → tight lines, no absorption
///
/// ```dart
/// // Use a preset
/// final surface = SurfaceMaterial.watercolorPaper();
///
/// // Or custom
/// final custom = SurfaceMaterial(
///   roughness: 0.7,
///   absorption: 0.8,
///   grainTexture: 'canvas',
/// );
///
/// // Compute rendering modifiers
/// final mods = surface.computeModifiers(pressure: 0.6, velocity: 500);
/// ```
class SurfaceMaterial {
  /// How rough the surface is. 0.0 = perfectly smooth (glass),
  /// 1.0 = very rough (raw wood). Affects grain texture intensity
  /// and pigment scatter.
  final double roughness;

  /// How much ink the surface absorbs. 0.0 = repels everything (glass),
  /// 1.0 = fully absorbent (watercolor paper). High absorption causes
  /// wider spread and lower surface opacity.
  final double absorption;

  /// How well pigment stays on the surface after application.
  /// 0.0 = pigment slides off, 1.0 = permanent deposit.
  /// Low retention → lighter strokes that can be smudged.
  final double pigmentRetention;

  /// Name of the grain texture to apply. Maps to [TextureType] names:
  /// 'none', 'pencilGrain', 'charcoal', 'watercolor', 'canvas', 'kraft'.
  /// The surface provides a default grain that the brush can override.
  final String grainTexture;

  /// Scale of the grain texture. Smaller values = finer grain,
  /// larger values = coarser, more visible texture pattern.
  final double grainScale;

  const SurfaceMaterial({
    this.roughness = 0.15,
    this.absorption = 0.4,
    this.pigmentRetention = 0.8,
    this.grainTexture = 'none',
    this.grainScale = 1.0,
  });

  // ===========================================================================
  // PRESETS
  // ===========================================================================

  /// 🪟 Glass — perfectly smooth, non-absorbent.
  /// Ink sits on the surface with no grain. Clean, digital feel.
  const SurfaceMaterial.glass()
    : roughness = 0.0,
      absorption = 0.0,
      pigmentRetention = 0.3,
      grainTexture = 'none',
      grainScale = 1.0;

  /// 📄 Smooth paper — slight grain, moderate absorption.
  /// Standard writing/sketching feel. Good for pen and pencil.
  const SurfaceMaterial.smoothPaper()
    : roughness = 0.15,
      absorption = 0.4,
      pigmentRetention = 0.8,
      grainTexture = 'pencilGrain',
      grainScale = 0.8;

  /// 🎨 Watercolor paper — medium roughness, high absorption.
  /// Cold-pressed texture. Pigment spreads and bleeds naturally.
  const SurfaceMaterial.watercolorPaper()
    : roughness = 0.6,
      absorption = 0.8,
      pigmentRetention = 0.7,
      grainTexture = 'watercolor',
      grainScale = 1.2;

  /// 🖼️ Canvas — high roughness, moderate absorption.
  /// Heavy weave texture visible in all strokes. Oil/acrylic feel.
  const SurfaceMaterial.canvas()
    : roughness = 0.8,
      absorption = 0.5,
      pigmentRetention = 0.85,
      grainTexture = 'canvas',
      grainScale = 1.5;

  /// 🪵 Raw wood — very rough, low absorption.
  /// Grain shows through strongly. Charcoal/chalk feel.
  const SurfaceMaterial.rawWood()
    : roughness = 0.9,
      absorption = 0.3,
      pigmentRetention = 0.6,
      grainTexture = 'kraft',
      grainScale = 2.0;

  /// 🖤 Chalkboard — moderate roughness, very low absorption.
  /// Chalk slides on surface. Distinctive matte black feel.
  const SurfaceMaterial.chalkboard()
    : roughness = 0.4,
      absorption = 0.05,
      pigmentRetention = 0.4,
      grainTexture = 'charcoal',
      grainScale = 1.0;

  // ===========================================================================
  // MATERIAL MODIFIERS COMPUTATION
  // ===========================================================================

  /// Compute rendering modifiers based on surface properties and current
  /// input state (pressure, velocity).
  ///
  /// When [wetness] is provided (0.0–1.0), it amplifies absorption effects:
  /// wet surfaces spread ink further and reduce surface opacity.
  ///
  /// These modifiers are multiplied into the brush engine's existing
  /// parameters to produce surface-dependent rendering.
  MaterialModifiers computeModifiers({
    required double pressure,
    required double velocity,
    double wetness = 0.0,
  }) {
    final clampedPressure = pressure.clamp(0.0, 1.0);
    final normalizedVelocity = (velocity / 1000.0).clamp(0.0, 1.0);
    final clampedWetness = wetness.clamp(0.0, 1.0);

    // Roughness: high roughness → more grain, slightly wider strokes
    // At high pressure, you "push through" the grain (less visible)
    final pressureGrainReduction = clampedPressure * 0.4;
    final grainIntensity = (roughness * (1.0 - pressureGrainReduction)).clamp(
      0.0,
      1.0,
    );

    // Absorption: high absorption → ink spreads wider, opacity drops slightly
    // Fast strokes deposit less ink (less time to absorb)
    // Wetness amplifies absorption (wet paper absorbs and spreads more)
    final velocityAbsorptionReduction = normalizedVelocity * 0.3;
    final wetnessBoost = clampedWetness * 0.3;
    final effectiveAbsorption =
        (absorption + wetnessBoost) * (1.0 - velocityAbsorptionReduction);
    final spreadFactor = 1.0 + effectiveAbsorption * 0.5; // 1.0–1.65
    final opacityMultiplier = 1.0 - effectiveAbsorption * 0.15; // ~0.80–1.0

    // Width: rougher surfaces cause slight width increase (pigment scatter)
    final widthMultiplier = 1.0 + roughness * 0.1; // 1.0–1.1

    return MaterialModifiers(
      opacityMultiplier: opacityMultiplier.clamp(0.0, 2.0),
      widthMultiplier: widthMultiplier.clamp(0.5, 2.0),
      grainIntensity: grainIntensity,
      spreadFactor: spreadFactor.clamp(0.5, 2.0),
    );
  }

  // ===========================================================================
  // SERIALIZATION
  // ===========================================================================

  Map<String, dynamic> toJson() => {
    'r': roughness,
    'a': absorption,
    'pr': pigmentRetention,
    if (grainTexture != 'none') 'gt': grainTexture,
    if (grainScale != 1.0) 'gs': grainScale,
  };

  factory SurfaceMaterial.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SurfaceMaterial();

    return SurfaceMaterial(
      roughness: (json['r'] as num?)?.toDouble() ?? 0.15,
      absorption: (json['a'] as num?)?.toDouble() ?? 0.4,
      pigmentRetention: (json['pr'] as num?)?.toDouble() ?? 0.8,
      grainTexture: (json['gt'] as String?) ?? 'none',
      grainScale: (json['gs'] as num?)?.toDouble() ?? 1.0,
    );
  }

  // ===========================================================================
  // COPY / EQUALITY
  // ===========================================================================

  SurfaceMaterial copyWith({
    double? roughness,
    double? absorption,
    double? pigmentRetention,
    String? grainTexture,
    double? grainScale,
  }) {
    return SurfaceMaterial(
      roughness: roughness ?? this.roughness,
      absorption: absorption ?? this.absorption,
      pigmentRetention: pigmentRetention ?? this.pigmentRetention,
      grainTexture: grainTexture ?? this.grainTexture,
      grainScale: grainScale ?? this.grainScale,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SurfaceMaterial &&
        other.roughness == roughness &&
        other.absorption == absorption &&
        other.pigmentRetention == pigmentRetention &&
        other.grainTexture == grainTexture &&
        other.grainScale == grainScale;
  }

  @override
  int get hashCode => Object.hash(
    roughness,
    absorption,
    pigmentRetention,
    grainTexture,
    grainScale,
  );

  @override
  String toString() =>
      'SurfaceMaterial('
      'roughness: $roughness, '
      'absorption: $absorption, '
      'pigmentRetention: $pigmentRetention, '
      'grainTexture: $grainTexture, '
      'grainScale: $grainScale)';
}

/// Computed rendering modifiers derived from [SurfaceMaterial] properties
/// and current input state.
///
/// These are multiplied into the brush engine's existing parameters.
/// All values are multiplicative factors centered around 1.0:
/// - 1.0 = no change from default behavior
/// - <1.0 = reduce the parameter
/// - >1.0 = increase the parameter
class MaterialModifiers {
  /// Opacity multiplier. <1.0 on absorbent surfaces (ink sinks in).
  final double opacityMultiplier;

  /// Width multiplier. >1.0 on rough surfaces (pigment scatters).
  final double widthMultiplier;

  /// Grain texture intensity. High on rough surfaces, reduced by pressure.
  final double grainIntensity;

  /// Spread factor for wet media. >1.0 on absorbent surfaces.
  final double spreadFactor;

  const MaterialModifiers({
    this.opacityMultiplier = 1.0,
    this.widthMultiplier = 1.0,
    this.grainIntensity = 0.0,
    this.spreadFactor = 1.0,
  });

  /// Identity modifiers — no surface effect.
  static const identity = MaterialModifiers();

  @override
  String toString() =>
      'MaterialModifiers('
      'opacity: $opacityMultiplier, '
      'width: $widthMultiplier, '
      'grain: $grainIntensity, '
      'spread: $spreadFactor)';
}
