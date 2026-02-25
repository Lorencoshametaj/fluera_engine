#version 460 core
#include <flutter/runtime_effect.glsl>

// Uniforms
uniform float uP1x;    // Segment start x (local)
uniform float uP1y;    // Segment start y (local)
uniform float uP2x;    // Segment end x (local)
uniform float uP2y;    // Segment end y (local)
uniform float uW1;     // Width at start
uniform float uW2;     // Width at end
uniform float uColorR; // Stroke color
uniform float uColorG;
uniform float uColorB;
uniform float uColorA;
uniform float uPressure;   // Pressure (controls darkness)
uniform float uVelocity;   // Velocity (controls grain density)
uniform float uSeed;       // Random seed
uniform float uGrain;      // Grain intensity (0–1)
// 🧬 Surface material uniforms (0.0 = no surface effect)
uniform float uRoughness;   // 0–1: grain stickiness in valleys
uniform float uAbsorption;  // 0–1: charcoal sinks deeper
uniform float uRetention;   // 0–1: pigment permanence

out vec4 fragColor;

// Hash noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// FBM noise — 3 octaves (optimized from 4)
float fbmNoise(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 3; i++) {
        value += amplitude * hash(p);
        p *= 2.17;
        amplitude *= 0.5;
    }
    return value;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    // Segment capsule SDF
    vec2 p1 = vec2(uP1x, uP1y);
    vec2 p2 = vec2(uP2x, uP2y);
    vec2 pa = fragCoord - p1;
    vec2 ba = p2 - p1;
    float segLen = length(ba);
    float t = clamp(dot(pa, ba) / max(segLen * segLen, 0.001), 0.0, 1.0);
    float w = mix(uW1, uW2, t);
    float dist = length(pa - ba * t);
    float halfW = w * 0.5;

    // Soft edge falloff (natural charcoal has fuzzy edges)
    // 🧬 Surface roughness wobbles the edge
    float edgeNoise = hash(fragCoord * 0.4 + uSeed * 0.2) * 2.0 - 1.0;
    float edgeWobble = edgeNoise * halfW * uRoughness * 0.15;
    float roughDist = dist + edgeWobble;

    // 🧬 CAPILLARY BLEED HALO: absorbent surfaces wick charcoal beyond edge
    float haloExtent = halfW * (1.0 + uAbsorption * 0.4);
    if (roughDist > haloExtent) {
        fragColor = vec4(0.0);
        return;
    }

    float edge = smoothstep(halfW, halfW * 0.3, roughDist);

    // Bleed halo: faint charcoal spread into paper fibers
    float haloNoise = hash(fragCoord * 2.0 + uSeed * 0.9);
    float haloZone = smoothstep(halfW * 0.7, haloExtent, roughDist);
    float halo = haloZone * haloNoise * uAbsorption * 0.12;
    edge = max(edge, halo);

    // 🌱 Organic grain: pressure modulates frequency — light = coarse, heavy = fine
    float grainFreq = mix(0.5, 1.2, uPressure);

    // ─── SURFACE-SPECIFIC NOISE PATTERNS ─────────────────────────────
    // Different surfaces produce fundamentally different charcoal textures.

    // 🧬 MULTI-PASS BUILDUP: seed-based grain displacement
    // Each stroke has slightly different grain on rough surfaces → gradual darkening.
    // On glass (roughness=0), offset=0 → same grain → immediate darkening.
    float seedOffset = uSeed * 0.08 * uRoughness;
    vec2 grainPos = fragCoord + seedOffset;

    // Surface pattern weights (compute ONCE for conditional skipping)
    float canvasWeight = smoothstep(0.5, 0.9, uRoughness) * smoothstep(0.3, 0.6, uAbsorption);
    float woodWeight = smoothstep(0.6, 0.95, uRoughness) * (1.0 - smoothstep(0.1, 0.5, uAbsorption));

    // 🌱 Anisotropic grain: directional from drawing motion
    float bLen = max(segLen, 0.001);
    vec2 grainDir = ba / bLen;
    vec2 crossDir = vec2(-grainDir.y, grainDir.x);

    // Pattern A: Base grain (single FBM + directional blend)
    float isoGrain = fbmNoise(grainPos * grainFreq + uSeed);
    float dirBlend = 0.3 + uRoughness * 0.3;
    float grainNoise = isoGrain;
    if (dirBlend > 0.1) {
        float alongStroke = dot(grainPos, grainDir);
        float crossStroke = dot(grainPos, crossDir);
        float dirGrain = fbmNoise(vec2(alongStroke, crossStroke) * 1.5 + uSeed * 0.5);
        grainNoise = mix(isoGrain, dirGrain, dirBlend);
    }

    // Pattern B: Canvas weave (ONLY when needed)
    if (canvasWeight > 0.01) {
        float weaveFreq = grainFreq * 6.0;
        float weaveX = sin(grainPos.x * weaveFreq) * 0.5 + 0.5;
        float weaveY = sin(grainPos.y * weaveFreq) * 0.5 + 0.5;
        float weaveGrain = weaveX * weaveY;
        weaveGrain += hash(grainPos * grainFreq * 0.5) * 0.25;
        grainNoise = mix(grainNoise, clamp(weaveGrain, 0.0, 1.0), canvasWeight * 0.55);
    }

    // Pattern C: Wood grain (ONLY when needed)
    if (woodWeight > 0.01) {
        float alongStroke = dot(grainPos, grainDir);
        float crossStroke = dot(grainPos, crossDir);
        float woodWobble = hash(vec2(alongStroke * 0.2, 0.0) + uSeed) * 4.0;
        float woodLines = sin((crossStroke + woodWobble) * grainFreq * 3.0) * 0.5 + 0.5;
        woodLines += hash(grainPos * grainFreq * 0.7) * 0.2;
        grainNoise = mix(grainNoise, clamp(woodLines, 0.0, 1.0), woodWeight * 0.45);
    }

    // Velocity affects grain: slow = dense, fast = scattered
    float velocityGrain = mix(0.3, 0.9, uVelocity);
    float grainThreshold = mix(0.2, velocityGrain, uGrain);

    // 🧬 Surface roughness: rough surfaces catch MORE charcoal in valleys
    grainThreshold -= uRoughness * 0.35;

    // 🧬 Pressure × Surface: light pressure on rough surface = only peaks
    float pressureSurfaceMod = (1.0 - uPressure) * uRoughness * 0.15;
    grainThreshold += pressureSurfaceMod;

    // 🧬 Anisotropic paper fibers: fixed fiber direction at ~30°
    // Charcoal catches more in fibers aligned with stroke direction.
    vec2 fiberDir = normalize(vec2(0.866, 0.5)); // 30° angle
    float fiberAlignment = abs(dot(grainDir, fiberDir));
    float fiberBias = fiberAlignment * uAbsorption * 0.06;
    grainThreshold -= fiberBias;

    // Erode: where noise is below threshold, charcoal doesn't stick
    float erosion = smoothstep(grainThreshold - 0.1, grainThreshold + 0.1, grainNoise);

    // Pressure controls overall darkness
    float darkness = mix(0.4, 1.0, uPressure);
    darkness += uAbsorption * 0.35;
    darkness = clamp(darkness, 0.0, 1.0);

    // 🧬 PRESSURE BLOOMS: charcoal pools at segment endpoints
    float endProximity = 1.0 - 2.0 * abs(t - 0.5); // 1 at ends, 0 at center
    float bloomIntensity = endProximity * endProximity * uPressure * 0.06;
    darkness += bloomIntensity;
    darkness = clamp(darkness, 0.0, 1.0);

    // ─── POWDER SCATTER ──────────────────────────────────────────────
    float smoothness = 1.0 - uRoughness;
    float scatterZone = smoothstep(halfW * 0.4, halfW * 1.3, dist);
    float scatterNoise = hash(fragCoord * 3.0 + uSeed * 1.7);
    float scatterThreshold = 0.65 - smoothness * 0.25;
    float scatter = scatterZone * step(scatterThreshold, scatterNoise) * smoothness * 0.5;
    float scatterFade = smoothstep(halfW * 2.0, halfW * 0.8, dist);
    scatter *= scatterFade * uPressure;

    // ─── VELOCITY SMEAR ──────────────────────────────────────────────
    // 🧬 On smooth surfaces at high velocity, charcoal leaves a faint
    // directional ghost trail — particles dragged by motion.
    // On rough surfaces, particles stick immediately (no smear).
    float smearAmount = uVelocity * smoothness * smoothness;
    // Offset the SDF in the stroke direction to create trailing shadow
    vec2 smearOffset = grainDir * halfW * smearAmount * 0.3;
    float smearDist = length(pa - ba * t - smearOffset);
    float smearEdge = smoothstep(halfW * 1.5, halfW * 0.5, smearDist);
    float smearNoise = hash(fragCoord * 2.0 + uSeed * 2.3);
    float smear = smearEdge * smearNoise * smearAmount * 0.15;

    // Combine: edge shape × grain erosion × darkness + scatter + smear
    float alpha = (edge * erosion * darkness + scatter + smear) * uColorA;

    // 🧬 Pigment retention
    float retentionFactor = mix(0.08, 1.0, uRetention);
    alpha *= retentionFactor;

    // 🧬 Warm color shift
    float warmth = (uRoughness * 0.5 + uAbsorption * 0.3) * 0.08;
    float colorShift = (1.0 - erosion) * 0.05;

    float finalR = uColorR + colorShift + warmth;
    float finalG = uColorG + colorShift * 0.5 + warmth * 0.6;
    float finalB = uColorB - warmth * 0.3;
    fragColor = vec4(finalR * alpha, finalG * alpha, finalB * alpha, alpha);
}
