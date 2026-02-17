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

out vec4 fragColor;

// Hash noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// FBM noise for grain texture
float fbmNoise(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
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
    float edge = smoothstep(halfW, halfW * 0.3, dist);

    // Grain erosion: FBM noise creates paper grain effect
    float grainNoise = fbmNoise(fragCoord * 0.8 + uSeed);

    // Velocity affects grain: slow = dense, fast = scattered
    float velocityGrain = mix(0.3, 0.9, uVelocity);
    float grainThreshold = mix(0.2, velocityGrain, uGrain);

    // Erode: where noise is below threshold, charcoal doesn't stick
    float erosion = smoothstep(grainThreshold - 0.1, grainThreshold + 0.1, grainNoise);

    // Pressure controls overall darkness
    float darkness = mix(0.4, 1.0, uPressure);

    // Combine: edge shape × grain erosion × pressure darkness
    float alpha = edge * erosion * darkness * uColorA;

    // Slight color variation from grain (warmer in light areas)
    float colorShift = (1.0 - erosion) * 0.05;

    float finalR = uColorR + colorShift;
    float finalG = uColorG + colorShift * 0.5;
    float finalB = uColorB;
    fragColor = vec4(finalR * alpha, finalG * alpha, finalB * alpha, alpha);
}
