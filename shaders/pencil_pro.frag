#version 460 core
#include <flutter/runtime_effect.glsl>

// Pencil Pro — Advanced graphite simulation with grain and surface interaction
//
// Uniform layout matches shader_pencil_renderer.dart setFloat(idx++) order:
// Individual floats for maximum clarity and no vec2/vec4 alignment surprises.

uniform float uP1x;         // Segment start x (local to rect)
uniform float uP1y;         // Segment start y
uniform float uP2x;         // Segment end x
uniform float uP2y;         // Segment end y
uniform float uW1;          // Width at start
uniform float uW2;          // Width at end
uniform float uColorR;      // Stroke color
uniform float uColorG;
uniform float uColorB;
uniform float uColorA;
uniform float uOpacity1;    // Per-segment opacity (pressure-based)
uniform float uOpacity2;
uniform float uSeed;        // Random seed
uniform float uTextureScale;// Texture scale (0 = no texture)
uniform float uCosAngle;    // cos(strokeAngle)
uniform float uSinAngle;    // sin(strokeAngle)
// 🧬 Surface material uniforms (0.0 = no surface effect)
uniform float uRoughness;   // 0–1: grain coarseness + paper tooth
uniform float uAbsorption;  // 0–1: graphite retention at speed
uniform float uRetention;   // 0–1: pigment permanence on surface

out vec4 fragColor;

// Hash-based noise for pencil grain
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Fractional Brownian Motion — 3 octaves (optimized from 5)
// Last 2 octaves contribute <19% of signal but cost 40% of compute
float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    for (int i = 0; i < 3; i++) {
        v += a * noise(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// Cheap single-sample noise for secondary effects (edge wobble, halo)
float cheapNoise(vec2 p) {
    return hash(floor(p) + fract(p) * 0.3);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    // Capsule SDF (same approach as charcoal.frag — proven working)
    vec2 p1 = vec2(uP1x, uP1y);
    vec2 p2 = vec2(uP2x, uP2y);
    vec2 pa = fragCoord - p1;
    vec2 ba = p2 - p1;
    float segLen = length(ba);
    float t = clamp(dot(pa, ba) / max(segLen * segLen, 0.001), 0.0, 1.0);
    float w = mix(uW1, uW2, t);
    float dist = length(pa - ba * t);
    float halfW = w * 0.5;

    // Soft edge — gradient from center to edge (charcoal-proven pattern)
    // 🧬 Surface roughness wobbles the edge — rough surfaces create
    // irregular pencil edges like real paper tooth eating the stroke.
    float edgeNoise = cheapNoise(fragCoord * 0.5 + uSeed * 0.15) * 2.0 - 1.0;
    float edgeWobble = edgeNoise * halfW * uRoughness * 0.12;
    float roughDist = dist + edgeWobble;

    // 🧬 CAPILLARY BLEED HALO: on absorbent surfaces, graphite/pigment
    // extends beyond the normal stroke edge via paper fiber wicking.
    // When two nearby strokes overlap in the halo zone → bleed effect.
    float haloExtent = halfW * (1.0 + uAbsorption * 0.5); // up to 50% wider
    if (roughDist > haloExtent) {
        fragColor = vec4(0.0);
        return;
    }

    float edge = smoothstep(halfW, halfW * 0.3, roughDist);

    // Bleed halo: very faint, noise-modulated alpha beyond the normal edge
    float haloNoise = cheapNoise(fragCoord * 2.5 + uSeed * 0.7);
    float haloZone = smoothstep(halfW * 0.8, haloExtent, roughDist);
    float halo = haloZone * haloNoise * uAbsorption * 0.15;
    // Halo adds to edge (faint graphite spread into paper fibers)
    edge = max(edge, halo);

    // Pressure-dependent pencil weight (interpolate opacity along segment)
    float opacity = mix(uOpacity1, uOpacity2, t);
    float weight = mix(0.15, 0.85, opacity);

    // ─── SURFACE-SPECIFIC NOISE PATTERNS ─────────────────────────────
    // Different surfaces produce fundamentally different grain patterns.
    // Blended based on roughness/absorption — no extra uniforms needed.

    float roughnessGrainBoost = 1.0 + uRoughness * 2.0;
    float grainScale = mix(8.0, 3.0, opacity) * roughnessGrainBoost;

    // 🧬 MULTI-PASS BUILDUP: seed-based grain displacement
    // On rough surfaces, each stroke/segment has a slightly different grain
    // offset. Overlapping strokes fill DIFFERENT valleys → gradual darkening.
    // On glass (roughness=0), offset=0 → identical grain → instant darkening.
    float seedOffset = uSeed * 0.07 * uRoughness;
    vec2 grainPos = fragCoord + seedOffset;

    // 🧬 Surface pattern weights (computed ONCE, used for conditional skipping)
    float canvasWeight = smoothstep(0.5, 0.9, uRoughness) * smoothstep(0.3, 0.6, uAbsorption);
    float woodWeight = smoothstep(0.6, 0.95, uRoughness) * (1.0 - smoothstep(0.1, 0.5, uAbsorption));

    // Stroke direction (shared by wood pattern + directional grain)
    float bLen = max(segLen, 0.001);
    vec2 strokeDir = ba / bLen;
    vec2 crossDir = vec2(-strokeDir.y, strokeDir.x);

    // Pattern A: Base grain (always computed — single FBM + cheap noise)
    float baseGrain = fbm(grainPos * grainScale);
    float grain2 = cheapNoise(grainPos * grainScale * 2.5 + 50.0);
    float isoGrain = mix(baseGrain, grain2, 0.25);

    // 🧬 DIRECTIONAL GRAIN: anisotropic stretch on rough surfaces
    float anisoBlend = uRoughness * 0.5;
    float grain = isoGrain;
    if (anisoBlend > 0.05) {
        vec2 anisoCoord = vec2(
            dot(grainPos, strokeDir) * 0.7,
            dot(grainPos, crossDir) * 1.3
        );
        float dirGrain = fbm(anisoCoord * grainScale * 0.9 + uSeed * 0.3);
        grain = mix(isoGrain, dirGrain, anisoBlend);
    }

    // Pattern B: Canvas weave (ONLY if weight > threshold — saves ~12 hash ops)
    if (canvasWeight > 0.01) {
        float weaveFreq = grainScale * 0.8;
        float weaveX = sin(grainPos.x * weaveFreq) * 0.5 + 0.5;
        float weaveY = sin(grainPos.y * weaveFreq) * 0.5 + 0.5;
        float weavePattern = weaveX * weaveY;
        weavePattern += cheapNoise(grainPos * grainScale * 0.5) * 0.3;
        grain = mix(grain, clamp(weavePattern, 0.0, 1.0), canvasWeight * 0.6);
    }

    // Pattern C: Wood grain (ONLY if weight > threshold)
    if (woodWeight > 0.01) {
        float alongStroke = dot(grainPos, strokeDir);
        float crossStroke = dot(grainPos, crossDir);
        float woodWobble = cheapNoise(vec2(alongStroke * 0.3, 0.0) + uSeed) * 3.0;
        float woodLines = sin((crossStroke + woodWobble) * grainScale * 0.6) * 0.5 + 0.5;
        woodLines += cheapNoise(grainPos * grainScale * 0.8) * 0.2;
        grain = mix(grain, clamp(woodLines, 0.0, 1.0), woodWeight * 0.5);
    }

    // 🧬 Surface-modulated velocity fade: absorption dampens fast-stroke fade
    float vel = (segLen / max(uW1 * 4.0, 1.0));
    vel = clamp(vel, 0.0, 1.0);
    float velocityFadeRange = mix(0.3, 0.9, uAbsorption);
    float velocityFade = mix(1.0, velocityFadeRange, vel);

    // 🧬 Surface-modulated paper tooth: roughness creates visible white gaps
    // Glass (0.0) → smooth coverage, barely any tooth
    // Canvas (0.8) → heavy tooth, lots of white show-through
    float toothLow = 0.35 - uRoughness * 0.30;
    float toothHigh = 0.65 - uRoughness * 0.20;

    // 🧬 Pressure × Surface: light pressure on rough surface = graphite
    // only touches the peaks of the paper grain → lots of white showing.
    // Heavy pressure pushes graphite into valleys → fuller coverage.
    // On glass, this effect is minimal (no paper tooth to fill).
    float pressureToothMod = (1.0 - opacity) * uRoughness * 0.12;
    toothLow += pressureToothMod;
    toothHigh += pressureToothMod;

    // 🧬 Anisotropic paper fibers: fixed fiber direction at ~30° for
    // watercolor/canvas. Graphite spreads MORE along fiber direction.
    // Creates subtle directional bias in the grain pattern.
    vec2 fiberDir = normalize(vec2(0.866, 0.5)); // 30° angle
    float fiberAlignment = abs(dot(normalize(ba), fiberDir));
    float fiberEffect = fiberAlignment * uAbsorption * 0.08;
    // Fibers subtly bias the grain threshold — aligned strokes penetrate more
    toothLow -= fiberEffect;

    float tooth = smoothstep(toothLow, toothHigh, grain);
    float coverage = edge * weight * velocityFade * tooth;

    // Slight edge darkening (pressure pools at edges)
    float edgeDark = smoothstep(halfW * 0.6, halfW, roughDist);
    coverage *= mix(1.0, 1.15, edgeDark * opacity);

    // 🧬 PRESSURE BLOOMS: at segment endpoints (t≈0 or t≈1), graphite
    // pools before flowing → slightly darker, wider saturation zones.
    float endProximity = 1.0 - 2.0 * abs(t - 0.5); // 1 at ends, 0 at center
    float bloomIntensity = endProximity * endProximity * opacity * 0.08;
    coverage += bloomIntensity;

    // 🧬 Pigment retention
    float retentionFactor = mix(0.1, 1.0, uRetention);
    coverage *= retentionFactor;

    // Clamp and output (premultiplied alpha — required by Impeller)
    coverage = clamp(coverage, 0.0, 1.0);
    float finalAlpha = uColorA * coverage;

    // ─── METALLIC SHEEN ──────────────────────────────────────────────
    // 🧬 Real graphite has a specular metallic sheen that shifts with angle.
    // On glass/smooth → very visible (glossy graphite).
    // On rough surfaces → barely visible (matte).
    float smoothness = 1.0 - uRoughness;
    float strokeAngle = atan(ba.y, ba.x);
    // Simulated "light direction" at 45° — sheen appears when stroke
    // is roughly perpendicular to light direction
    float lightAngle = 0.785; // π/4 = 45°
    float angleDiff = abs(sin(strokeAngle - lightAngle));
    float sheen = angleDiff * smoothness * smoothness * 0.12;
    // Sheen is brightest at the stroke center, fades at edges
    float sheenMask = smoothstep(halfW, halfW * 0.2, roughDist);
    sheen *= sheenMask * opacity;

    // 🧬 Warm color shift + metallic sheen combined
    float warmth = (uRoughness * 0.4 + uAbsorption * 0.2) * 0.06;
    float finalR = uColorR + warmth + sheen * 0.15;
    float finalG = uColorG + warmth * 0.65 + sheen * 0.12;
    float finalB = uColorB - warmth * 0.25 + sheen * 0.08;
    fragColor = vec4(finalR * finalAlpha, finalG * finalAlpha, finalB * finalAlpha, finalAlpha);
}
