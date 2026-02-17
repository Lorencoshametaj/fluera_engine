#version 460 core
#include <flutter/runtime_effect.glsl>

// Uniforms — must match ShaderTextureRenderer.renderTextureOverlay() layout
uniform float uP1x;           // 0: Segment start x (local)
uniform float uP1y;           // 1: Segment start y (local)
uniform float uP2x;           // 2: Segment end x (local)
uniform float uP2y;           // 3: Segment end y (local)
uniform float uW1;            // 4: Width at start
uniform float uW2;            // 5: Width at end
uniform float uPressure1;     // 6: Pressure at start
uniform float uPressure2;     // 7: Pressure at end
uniform float uVelocity;      // 8: Segment velocity (0–1)
uniform float uIntensity;     // 9: Texture intensity (0–1)
uniform float uTextureScale;  // 10: Inverse scale (1/totalScale)
uniform float uTexOffsetX;    // 11: Random texture offset X
uniform float uTexOffsetY;    // 12: Random texture offset Y
uniform float uCosAngle;      // 13: Pre-computed cos(rotation)
uniform float uSinAngle;      // 14: Pre-computed sin(rotation)
uniform float uWetEdge;       // 15: Wet edge darkening (0–1)

uniform sampler2D uTexture;   // sampler(0): tileable grayscale texture

out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    // ── Capsule SDF ──
    vec2 p1 = vec2(uP1x, uP1y);
    vec2 p2 = vec2(uP2x, uP2y);
    vec2 pa = fragCoord - p1;
    vec2 ba = p2 - p1;
    float segLen2 = dot(ba, ba);
    float t = clamp(dot(pa, ba) / max(segLen2, 0.001), 0.0, 1.0);
    float w = mix(uW1, uW2, t);
    float dist = length(pa - ba * t);

    // Smooth edge falloff
    float halfW = w * 0.5;
    float mask = smoothstep(halfW, halfW - 1.5, dist);
    if (mask <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // ── Rotated texture UV ──
    // Apply rotation matrix [cos -sin; sin cos] * scale + offset
    vec2 rotated = vec2(
        fragCoord.x * uCosAngle - fragCoord.y * uSinAngle,
        fragCoord.x * uSinAngle + fragCoord.y * uCosAngle
    );
    vec2 uv = (rotated + vec2(uTexOffsetX, uTexOffsetY)) * uTextureScale;

    // Sample texture (grayscale — use .r channel)
    float texSample = texture(uTexture, uv).r;

    // ── Pressure interpolation ──
    float pressure = mix(uPressure1, uPressure2, t);
    float pressureFactor = 0.3 + pressure * 0.7;

    // ── Velocity erosion ──
    // Faster strokes → less texture (lighter touch)
    float velFactor = mix(1.0, 0.3, uVelocity);

    // ── Wet edge ──
    // Edge distance ratio: 0 at center, 1 at edge
    float edgeRatio = dist / max(halfW, 0.001);
    // Darken texture near the edges when wet edge > 0
    float wetDarken = 1.0 + uWetEdge * smoothstep(0.3, 0.9, edgeRatio) * 0.6;

    // ── Final erosion alpha ──
    // texSample: 1 = full texture, 0 = no texture
    // We invert: bright areas of texture erode the stroke more
    float erosion = texSample * uIntensity * pressureFactor * velFactor * wetDarken;
    erosion = clamp(erosion * 0.7, 0.0, 1.0);

    // Output: premultiplied alpha (BlendMode.dstOut will subtract this)
    float alpha = erosion * mask;
    fragColor = vec4(alpha, alpha, alpha, alpha);
}
