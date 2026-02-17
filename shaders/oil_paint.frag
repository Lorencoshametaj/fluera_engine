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
uniform float uPressure;   // Pressure (controls thickness/opacity)
uniform float uVelocity;   // Velocity (controls smear directionality)
uniform float uSeed;       // Random seed for noise
uniform float uImpasto;    // Impasto thickness (0–1)

out vec4 fragColor;

// Hash noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise with smooth interpolation
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

// FBM for thick paint texture
float fbm(vec2 p) {
    float value = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amp * noise(p);
        p *= 2.13;
        amp *= 0.5;
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

    // Thick edge: slow falloff for impasto look
    float edge = smoothstep(halfW, halfW * 0.15, dist);

    // Stroke direction for directional smear
    vec2 dir = segLen > 0.001 ? ba / segLen : vec2(1.0, 0.0);
    vec2 perp = vec2(-dir.y, dir.x);
    float along = dot(fragCoord - p1, dir);
    float across = dot(fragCoord - p1, perp);

    // Directional streaks aligned with motion
    float streaks = noise(vec2(along * 0.3, across * 0.8) + uSeed);
    float streakIntensity = mix(0.0, 0.15, uVelocity);

    // Impasto texture: thick paint ridges
    float impastoNoise = fbm(fragCoord * 0.12 + uSeed * 0.7);
    float impastoFactor = mix(0.0, 0.2, uImpasto * uPressure);

    // Color variation from paint thickness (thicker = slightly lighter)
    float thickness = impastoNoise * impastoFactor;
    float lightShift = thickness * 0.8;

    // Edge ridge effect: thicker paint accumulates at edges
    float edgeRatio = dist / max(halfW, 0.001);
    float ridgeHighlight = smoothstep(0.5, 0.85, edgeRatio) * uImpasto * 0.12;

    // Final alpha
    float alpha = edge * uColorA * (0.85 + uPressure * 0.15);

    // Apply color shifts
    float r = clamp(uColorR + lightShift + streaks * streakIntensity + ridgeHighlight, 0.0, 1.0);
    float g = clamp(uColorG + lightShift * 0.8 + streaks * streakIntensity * 0.8 + ridgeHighlight * 0.8, 0.0, 1.0);
    float b = clamp(uColorB + lightShift * 0.6 + streaks * streakIntensity * 0.6 + ridgeHighlight * 0.6, 0.0, 1.0);

    fragColor = vec4(r * alpha, g * alpha, b * alpha, alpha);
}
