#version 460 core
#include <flutter/runtime_effect.glsl>

// Brush Stamp — Texture-based brush stamp for natural bristle/sponge effects
// Applies a procedural bristle pattern modulated by pressure and velocity.

uniform vec2 uCenter;
uniform vec2 uSize;
uniform vec2 uDir;
uniform vec4 uColor;
uniform float uWidth;
uniform float uPressure;
uniform float uVelocity;
uniform float uTime;

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

    // Circular stamp SDF
    float dist = length(fragCoord - uCenter);
    float radius = uWidth * 0.5;

    if (dist > radius + 1.0) {
        fragColor = vec4(0.0);
        return;
    }

    // Radial falloff
    float radialFalloff = 1.0 - smoothstep(radius * 0.7, radius, dist);

    // Bristle pattern — directional noise aligned with stroke
    float angle = atan(uDir.y, uDir.x);
    vec2 rotated = vec2(
        (fragCoord.x - uCenter.x) * cos(angle) + (fragCoord.y - uCenter.y) * sin(angle),
        -(fragCoord.x - uCenter.x) * sin(angle) + (fragCoord.y - uCenter.y) * cos(angle)
    );

    // Multi-scale bristle
    float bristle1 = noise(rotated * vec2(0.5, 4.0));
    float bristle2 = noise(rotated * vec2(0.3, 8.0) + 100.0);
    float bristle = mix(bristle1, bristle2, 0.5);

    // Pressure controls density
    float density = mix(0.3, 0.9, uPressure);
    float coverage = step(1.0 - density, bristle) * radialFalloff;

    // Slight ink variation
    float inkVar = 1.0 - noise(fragCoord * 3.0) * 0.1;
    coverage *= inkVar;

    // Output
    coverage = clamp(coverage, 0.0, 1.0);
    fragColor = vec4(uColor.rgb, uColor.a * coverage);
}
