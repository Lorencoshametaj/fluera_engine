#version 460 core
#include <flutter/runtime_effect.glsl>

// Fountain Pen Pro — Pressure-sensitive ink flow with capillary bleed
//
// Uniform layout matches shader_fountain_pen_renderer.dart setFloat(idx++) order:
// Individual floats — no vec2/vec4 alignment surprises.

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
uniform float uPressure1;   // Pressure at start
uniform float uPressure2;   // Pressure at end
uniform float uVelocity;    // Normalized velocity
uniform float uSeed;        // Random seed
uniform float uTextureScale;// Texture scale (0 = no texture)
uniform float uCosAngle;    // cos(strokeAngle)
uniform float uSinAngle;    // sin(strokeAngle)
// 🧬 Surface material uniforms (0.0 = no surface effect)
uniform float uRoughness;   // 0–1: fiber texture visibility
uniform float uAbsorption;  // 0–1: capillary bleed + ink spread
uniform float uRetention;   // 0–1: ink bonding to surface

out vec4 fragColor;

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

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    // Capsule SDF (individual float layout — proven working pattern)
    vec2 p1 = vec2(uP1x, uP1y);
    vec2 p2 = vec2(uP2x, uP2y);
    vec2 pa = fragCoord - p1;
    vec2 ba = p2 - p1;
    float segLen = length(ba);
    float t = clamp(dot(pa, ba) / max(segLen * segLen, 0.001), 0.0, 1.0);

    // Variable width along segment
    float w = mix(uW1, uW2, t);
    float halfW = w * 0.5;
    float dist = length(pa - ba * t);
    float sdf = dist - halfW;

    // 🧬 CAPILLARY BLEED: absorbent surfaces wick ink beyond stroke edge
    float haloRange = 2.0 + uAbsorption * 4.0; // Glass=2px, Watercolor=5.2px
    if (sdf > haloRange) {
        fragColor = vec4(0.0);
        return;
    }

    // Sharp core with soft anti-aliased edge
    // 🧬 Surface roughness creates micro-bleed at edges (paper fibers wick ink)
    float edgeNoise = noise(fragCoord * 0.6 + uSeed * 0.1) * 2.0 - 1.0;
    float edgeWobble = edgeNoise * uRoughness * 1.5;
    float roughSdf = sdf + edgeWobble;
    float alpha = 1.0 - smoothstep(-0.5, 0.5, roughSdf);

    // Capillary bleed halo: organic ink spreading into paper fibers
    float haloNoise = noise(fragCoord * 3.0 + uSeed * 0.5);
    float haloZone = smoothstep(0.0, haloRange, roughSdf);
    float halo = haloZone * haloNoise * uAbsorption * 0.2;
    alpha = max(alpha, halo);

    // Ink flow intensity based on interpolated pressure
    float pressure = mix(uPressure1, uPressure2, t);
    float inkFlow = mix(0.7, 1.0, pressure);

    // ─── ENHANCED INK POOLING ────────────────────────────────────────
    // 🧬 When pen pauses or slows: ink accumulates dramatically.
    // On absorbent paper, pooled ink also spreads into fibers.
    float velocityFactor = smoothstep(0.4, 0.0, uVelocity);
    float poolBase = velocityFactor * 0.25; // much more dramatic than before
    float poolAbsorb = velocityFactor * uAbsorption * 0.1; // extra spread on paper
    inkFlow += poolBase + poolAbsorb;
    // Pooled ink also widens the stroke slightly (simulated via alpha boost at edges)
    float poolEdgeBoost = velocityFactor * smoothstep(halfW * 0.3, halfW, dist) * 0.15;
    alpha += poolEdgeBoost;

    // 🧬 Surface-modulated micro-texture: roughness reveals paper fibers
    float texScale = 6.0 + uRoughness * 16.0;
    float texAmount = 0.06 + uRoughness * 0.25;
    float tex = noise(fragCoord * texScale) * texAmount;
    inkFlow -= tex;

    // 🧬 Surface-modulated capillary bleed
    float edgeFactor = smoothstep(halfW * 0.5, halfW, dist);
    float bleedAmount = 0.08 + uAbsorption * 0.35;
    float bleed = edgeFactor * noise(fragCoord * 12.0) * bleedAmount;
    alpha -= bleed;

    // 🧬 Absorption drain
    float absorptionDrain = uAbsorption * 0.2;
    inkFlow -= absorptionDrain;

    // 🧬 Pressure × Surface
    float pressureSatBoost = pressure * uAbsorption * 0.15;
    inkFlow += pressureSatBoost;

    // 🧬 Anisotropic paper fibers: ink flows along fiber direction
    // On absorbent paper, ink spreads MORE along the fixed 30° fiber axis.
    vec2 fiberDir = normalize(vec2(0.866, 0.5)); // 30°
    float bLen = max(length(ba), 0.001);
    float fiberAlignment = abs(dot(ba / bLen, fiberDir));
    float fiberFlowBoost = fiberAlignment * uAbsorption * 0.06;
    inkFlow += fiberFlowBoost;

    // 🧬 PRESSURE BLOOMS: at segment start/end, ink pools before flowing
    float endProximity = 1.0 - 2.0 * abs(t - 0.5); // 1 at ends, 0 at center
    float bloomIntensity = endProximity * endProximity * pressure * 0.1;
    inkFlow += bloomIntensity;

    // 🧬 Pigment retention
    float retentionFactor = mix(0.2, 1.0, uRetention);

    // Final output (premultiplied alpha — required by Impeller)
    alpha = clamp(alpha * inkFlow * retentionFactor, 0.0, 1.0);
    float finalAlpha = uColorA * alpha;

    // 🧬 Warm color shift + pool darkening
    float warmth = (uRoughness * 0.3 + uAbsorption * 0.4) * 0.05;
    // Ink pools appear slightly darker/warmer
    float poolWarmth = velocityFactor * 0.02;
    float finalR = uColorR + warmth + poolWarmth;
    float finalG = uColorG + warmth * 0.5;
    float finalB = uColorB - warmth * 0.2 - poolWarmth * 0.5;
    fragColor = vec4(finalR * finalAlpha, finalG * finalAlpha, finalB * finalAlpha, finalAlpha);
}
