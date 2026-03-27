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
uniform float uPressure;   // Avg pressure (controls water amount)
uniform float uVelocity;   // Segment velocity (controls pigment density)
uniform float uSeed;       // Random seed for noise
uniform float uSpread;     // Water spread amount (0–1)
uniform float uWetness;    // 🌱 Canvas wetness (0=dry, 1=wet) — wet-on-wet

out vec4 fragColor;

// Simple hash noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth noise
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
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

    // Watercolor spread: wider falloff for wet effect
    float spreadW = w * (1.0 + uSpread * 0.8);
    float edge = smoothstep(spreadW * 0.5, spreadW * 0.25, dist);

    // Water diffusion noise
    float n = noise(fragCoord * 0.15 + uSeed);
    float diffusion = mix(0.7, 1.0, n);

    // Pigment density: faster strokes = lighter wash
    // 🌱 Wetness reduces density (water dilutes pigment)
    float wetDilution = 1.0 - uWetness * 0.3;
    float density = mix(0.3, 1.0, 1.0 - uVelocity * 0.6) * wetDilution;

    // 🌱 Organic: cauliflower pooling — amplified on wet canvas
    float poolNoise = noise(fragCoord * 0.4 + uSeed * 2.0);
    float poolShape = smoothstep(0.3, 0.7, poolNoise);
    // 🌱 Wet canvas = wider spread = bleed starts further from center
    float wetSpreadBoost = 1.0 + uWetness * 0.4;
    float edgeBleed = smoothstep(
        spreadW * 0.15 * wetSpreadBoost,
        spreadW * 0.45 * wetSpreadBoost,
        dist
    );
    // 🌱 Wet canvas = stronger bleed (more pigment migration)
    float bleedStrength = mix(0.1, 0.35, poolShape) * (1.0 + uWetness * 0.5);
    float bleedFactor = edgeBleed * bleedStrength * uPressure;

    // Final alpha: combine edge falloff, diffusion, density
    float alpha = edge * diffusion * density * uColorA;
    alpha += bleedFactor * uColorA;
    alpha = clamp(alpha, 0.0, uColorA);

    fragColor = vec4(uColorR * alpha, uColorG * alpha, uColorB * alpha, alpha);
}
