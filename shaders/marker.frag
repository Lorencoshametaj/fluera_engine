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
uniform float uFlatness; // Tip flatness (0=round, 1=chisel)

out vec4 fragColor;

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

    // Flat chisel tip: compress perpendicular to stroke direction
    vec2 nearest = p1 + ba * t;
    vec2 diff = fragCoord - nearest;

    // Rotate diff into stroke-local space
    vec2 dir = segLen > 0.001 ? ba / segLen : vec2(1.0, 0.0);
    vec2 perp = vec2(-dir.y, dir.x);
    float along = dot(diff, dir);
    float across = dot(diff, perp);

    // Apply flatness: stretch across direction
    float flatScale = 1.0 + uFlatness * 1.5;
    float adjustedDist = length(vec2(along, across * flatScale));

    // Sharp edges for marker (minimal anti-aliasing)
    float halfW = w * 0.5 * flatScale;
    float edge = smoothstep(halfW, halfW - 1.5, adjustedDist);

    // Slight edge darkening for ink pooling
    float edgeDark = smoothstep(halfW * 0.3, halfW, adjustedDist);
    float darkening = edgeDark * 0.08;

    float alpha = edge * uColorA;

    // Darken at edges
    float r = uColorR * (1.0 - darkening);
    float g = uColorG * (1.0 - darkening);
    float b = uColorB * (1.0 - darkening);

    fragColor = vec4(r * alpha, g * alpha, b * alpha, alpha);
}
