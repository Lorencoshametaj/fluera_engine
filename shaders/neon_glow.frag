#version 460 core
#include <flutter/runtime_effect.glsl>

// Uniforms
uniform float uP1x;    // Segment start x (local)
uniform float uP1y;    // Segment start y (local)
uniform float uP2x;    // Segment end x (local)
uniform float uP2y;    // Segment end y (local)
uniform float uW1;     // Width at start
uniform float uW2;     // Width at end
uniform float uColorR; // Stroke color (glow color)
uniform float uColorG;
uniform float uColorB;
uniform float uColorA;
uniform float uPressure;   // Pressure (controls core brightness)
uniform float uVelocity;   // Velocity (unused, reserved)
uniform float uSeed;       // Seed for subtle flicker
uniform float uGlowRadius; // Bloom radius multiplier (0–1)

out vec4 fragColor;

// Hash for subtle flicker
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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

    // Layer 1: Bright white-ish core
    float coreWidth = halfW * 0.3;
    float core = smoothstep(coreWidth, coreWidth * 0.2, dist);

    // Layer 2: Inner glow (saturated color)
    float innerWidth = halfW * 0.7;
    float inner = smoothstep(innerWidth, innerWidth * 0.2, dist);

    // Layer 3: Outer bloom (wide soft glow)
    float bloomWidth = halfW * (1.5 + uGlowRadius * 2.0);
    float bloom = exp(-2.5 * (dist * dist) / max(bloomWidth * bloomWidth, 0.001));

    // Layer 4: Far glow (very faint atmospheric haze)
    float farWidth = halfW * (3.0 + uGlowRadius * 3.0);
    float farGlow = exp(-4.0 * (dist * dist) / max(farWidth * farWidth, 0.001));

    // Subtle flicker variation
    float flicker = 0.95 + 0.05 * hash(vec2(t * 10.0, uSeed));

    // Compose layers with brightness control
    float brightness = 0.7 + uPressure * 0.3;

    // Core is white-hot (color desaturated toward white)
    vec3 coreColor = mix(vec3(uColorR, uColorG, uColorB), vec3(1.0), 0.8);
    vec3 glowColor = vec3(uColorR, uColorG, uColorB);

    // Blend layers
    vec3 color = coreColor * core * brightness * flicker
               + glowColor * inner * 0.8 * brightness
               + glowColor * bloom * 0.4
               + glowColor * farGlow * 0.15;

    float alpha = clamp(core + inner * 0.7 + bloom * 0.35 + farGlow * 0.1, 0.0, 1.0);
    alpha *= uColorA * brightness;

    fragColor = vec4(color * alpha, alpha);
}
