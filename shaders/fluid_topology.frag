#version 460 core
#include <flutter/runtime_effect.glsl>

// ============================================================================
// FLUID TOPOLOGY SHADER v2 — Advanced cell rendering with:
// - FBM multi-octave noise for organic edges
// - Paper grain texture (granulation)
// - Wetness-dependent edge bloom
// - Density variation within cells
// ============================================================================

// Cell geometry
uniform float uCellX;
uniform float uCellY;
uniform float uCellSize;

// Pigment
uniform float uPigmentR;
uniform float uPigmentG;
uniform float uPigmentB;
uniform float uDensity;

// State
uniform float uWetness;
uniform float uGranulation;
uniform float uAbsorption;
uniform float uSeed;

out vec4 fragColor;

// ── Noise functions ─────────────────────────────────────────────────

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // Hermite interpolation
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion — multi-scale noise for organic shapes
float fbm(vec2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// Paper grain — large-scale Voronoi-like texture
float paperGrain(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float minDist = 1.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 point = vec2(hash(i + neighbor), hash(i + neighbor + 31.0));
            vec2 diff = neighbor + point - f;
            minDist = min(minDist, dot(diff, diff));
        }
    }
    return sqrt(minDist);
}

// ── Main ────────────────────────────────────────────────────────────

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    // Normalized position within cell [0,1]
    vec2 cellPos = (fragCoord - vec2(uCellX, uCellY)) / uCellSize;
    vec2 centered = cellPos - 0.5;
    float dist = length(centered);

    // ── Edge shape ──────────────────────────────────────────────
    // FBM noise creates realistic irregular watercolor edges
    float edgeFbm = fbm(fragCoord * 0.2 + uSeed, 4);
    float edgeThreshold = 0.42 + edgeFbm * 0.18;

    // Wetness bloom — wet cells have softer, wider boundaries
    float wetBloom = 1.0 + uWetness * 0.35;
    float edge = smoothstep(edgeThreshold * wetBloom, edgeThreshold * 0.5, dist);

    // ── Paper grain texture ─────────────────────────────────────
    // Simulates cold-pressed watercolor paper
    float grain = paperGrain(fragCoord * 0.08 + uSeed * 0.5);
    float grainEffect = mix(1.0, 0.6 + grain * 0.8, uGranulation);

    // ── Density variation ───────────────────────────────────────
    // Subtle noise in density creates natural pigment distribution
    float densityNoise = fbm(fragCoord * 0.12 + uSeed * 2.7, 3);
    float densityVar = mix(0.8, 1.0, densityNoise);

    // ── Edge darkening ──────────────────────────────────────────
    // Pigment concentrates at the boundary (cauliflower ring)
    float edgeDist = smoothstep(0.15, 0.4, dist);
    float edgeDarken = 1.0 + edgeDist * 0.25 * (1.0 - uWetness);

    // ── Absorption effect ───────────────────────────────────────
    // Absorbed pigment is slightly darker and more permanent
    float absorptionBoost = 1.0 + uAbsorption * 0.15;

    // ── Combine all effects ─────────────────────────────────────
    float alpha = uDensity * edge * grainEffect * densityVar * edgeDarken * absorptionBoost;
    alpha = clamp(alpha, 0.0, min(uDensity * 1.2, 1.0));

    // Premultiplied alpha output
    vec3 color = vec3(uPigmentR, uPigmentG, uPigmentB);

    // Slight desaturation at edges (diluted pigment)
    float edgeDesaturation = smoothstep(0.2, 0.45, dist) * 0.15;
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(color, vec3(luma), edgeDesaturation);

    fragColor = vec4(color * alpha, alpha);
}
