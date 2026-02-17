#version 460 core
#include <flutter/runtime_effect.glsl>

// Fountain Pen Pro — Pressure-sensitive ink flow with capillary bleed
// Simulates a high-quality fountain pen with variable line width,
// ink pooling at stroke endpoints, and subtle feathering.

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

    // Transform to segment-local coordinates
    vec2 local = fragCoord - uCenter;
    vec2 perp = vec2(-uDir.y, uDir.x);
    float along = dot(local, uDir);
    float across = dot(local, perp);

    // Capsule SDF with pressure-varying width
    float pressureWidth = uWidth * mix(0.4, 1.2, uPressure);
    float halfLen = uSize.x * 0.5;
    float halfW = pressureWidth * 0.5;
    float clampedAlong = clamp(along, -halfLen, halfLen);
    float dist = length(vec2(along - clampedAlong, across));
    float sdf = dist - halfW;

    if (sdf > 2.0) {
        fragColor = vec4(0.0);
        return;
    }

    // Sharp core with soft anti-aliased edge
    float alpha = 1.0 - smoothstep(-0.5, 0.5, sdf);

    // Ink flow intensity based on pressure
    float inkFlow = mix(0.7, 1.0, uPressure);

    // Subtle ink pooling at low velocity (pen pauses)
    float pool = smoothstep(0.3, 0.0, uVelocity) * 0.15;
    inkFlow += pool;

    // Micro-texture for paper absorption variation
    float tex = noise(fragCoord * 6.0) * 0.08;
    inkFlow -= tex;

    // Edge feathering — capillary bleed effect
    float edgeFactor = smoothstep(halfW * 0.5, halfW, abs(across));
    float bleed = edgeFactor * noise(fragCoord * 12.0) * 0.12;
    alpha -= bleed;

    // Final output
    alpha = clamp(alpha * inkFlow, 0.0, 1.0);
    fragColor = vec4(uColor.rgb, uColor.a * alpha);
}
