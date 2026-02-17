#version 460 core
#include <flutter/runtime_effect.glsl>

// Uniforms
uniform float uP1x;    // Segment start x (local)
uniform float uP1y;    // Segment start y (local)
uniform float uP2x;    // Segment end x (local)
uniform float uP2y;    // Segment end y (local)
uniform float uW1;     // Width at start
uniform float uW2;     // Width at end
uniform float uColorR; // Ink color
uniform float uColorG;
uniform float uColorB;
uniform float uColorA;
uniform float uPressure;   // Pressure (controls ink concentration)
uniform float uVelocity;   // Velocity (controls wetness/bleed)
uniform float uSeed;       // Random seed
uniform float uWetness;    // Wet edge amount (0–1)

out vec4 fragColor;

// Hash noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise
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

// FBM for organic ink bleed
float fbm(vec2 p) {
    float value = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amp * noise(p);
        p *= 2.03;
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

    // Wet ink spread: noise-driven edge distortion
    float bleedNoise = fbm(fragCoord * 0.1 + uSeed);
    float bleedAmount = uWetness * (1.0 + uVelocity * 0.5);
    float noisyHalfW = w * 0.5 * (1.0 + bleedNoise * bleedAmount * 0.4);

    // Soft ink edge with organic irregularity
    float edge = smoothstep(noisyHalfW, noisyHalfW * 0.2, dist);

    // Ink concentration: pressure controls darkness
    float concentration = mix(0.2, 1.0, uPressure);

    // Wet-on-wet diffusion: ink is lighter in wet areas
    float diffusion = noise(fragCoord * 0.2 + uSeed * 1.3);
    float wetLightening = mix(0.0, 0.3, uWetness * (1.0 - uPressure));

    // Paper absorption variation: some areas absorb more ink
    float absorption = fbm(fragCoord * 0.05 + uSeed * 0.5);
    float absorptionFactor = mix(0.85, 1.0, absorption);

    // Edge darkening: ink pools at edges (capillary action)
    float edgeRatio = dist / max(noisyHalfW, 0.001);
    float pooling = smoothstep(0.4, 0.9, edgeRatio) * uWetness * 0.25;

    // Final ink density
    float inkDensity = concentration * absorptionFactor * (1.0 - wetLightening * diffusion);
    inkDensity = clamp(inkDensity + pooling, 0.0, 1.0);

    // Final alpha
    float alpha = edge * inkDensity * uColorA;

    // Slight blue-black tint in lighter wash areas (ink dilution)
    float dilutionShift = (1.0 - inkDensity) * 0.05;
    float r = uColorR - dilutionShift;
    float g = uColorG - dilutionShift * 0.5;
    float b = uColorB + dilutionShift * 0.3;

    fragColor = vec4(r * alpha, g * alpha, b * alpha, alpha);
}
