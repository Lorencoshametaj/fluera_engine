#version 460 core
#include <flutter/runtime_effect.glsl>

// Pencil Pro — Advanced graphite simulation with grain, smudge, and layering
// Uniforms: position, segment dims, direction, color, width, pressure, velocity, time

uniform vec2 uCenter;
uniform vec2 uSize;
uniform vec2 uDir;
uniform vec4 uColor;
uniform float uWidth;
uniform float uPressure;
uniform float uVelocity;
uniform float uTime;

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

// Fractional Brownian Motion for multi-scale grain
float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    // Transform to segment-local coordinates
    vec2 local = fragCoord - uCenter;
    vec2 perp = vec2(-uDir.y, uDir.x);
    float along = dot(local, uDir);
    float across = dot(local, perp);

    // Capsule SDF
    float halfLen = uSize.x * 0.5;
    float halfW = uWidth * 0.5;
    float clampedAlong = clamp(along, -halfLen, halfLen);
    float dist = length(vec2(along - clampedAlong, across));
    float sdf = dist - halfW;

    if (sdf > 1.0) {
        fragColor = vec4(0.0);
        return;
    }

    // Pressure-dependent pencil weight
    float weight = mix(0.15, 0.85, uPressure);

    // Multi-scale graphite grain
    float grainScale = mix(8.0, 3.0, uPressure);
    float grain1 = fbm(fragCoord * grainScale);
    float grain2 = fbm(fragCoord * grainScale * 2.5 + 50.0);
    float grain = mix(grain1, grain2, 0.4);

    // Velocity-driven lightness (faster = lighter)
    float velocityFade = mix(1.0, 0.5, uVelocity);

    // Paper tooth — areas where graphite doesn't stick
    float tooth = smoothstep(0.35, 0.65, grain);
    float coverage = weight * velocityFade * tooth;

    // Edge softness
    float edgeSoft = 1.0 - smoothstep(-1.5, 0.0, sdf);
    coverage *= edgeSoft;

    // Slight edge darkening (pressure pools at edges)
    float edgeDark = smoothstep(halfW * 0.6, halfW, abs(across));
    coverage *= mix(1.0, 1.15, edgeDark * uPressure);

    // Clamp and output
    coverage = clamp(coverage, 0.0, 1.0);
    fragColor = vec4(uColor.rgb, uColor.a * coverage);
}
