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
uniform float uTextureScale;  // 10: 5.0 / (typeScale * widthScale)
uniform float uTexOffsetX;    // 11: Random texture offset X [0,1]
uniform float uTexOffsetY;    // 12: Random texture offset Y [0,1]
uniform float uCosAngle;      // 13: Pre-computed cos(rotation)
uniform float uSinAngle;      // 14: Pre-computed sin(rotation)
uniform float uWetEdge;       // 15: Wet edge darkening (0–1)
uniform float uTexWidth;      // 16: Texture image width in pixels
uniform float uTexHeight;     // 17: Texture image height in pixels

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
    vec2 rotated = vec2(
        fragCoord.x * uCosAngle - fragCoord.y * uSinAngle,
        fragCoord.x * uSinAngle + fragCoord.y * uCosAngle
    );
    // uTextureScale / texSize → e.g. 5.0/640 = 0.0078 UV/pixel (smooth)
    vec2 texSize = vec2(max(uTexWidth, 1.0), max(uTexHeight, 1.0));
    vec2 uv = fract(rotated * uTextureScale / texSize + vec2(uTexOffsetX, uTexOffsetY));

    // Fix Y-axis inversion on OpenGL ES (Android/Impeller)
    #ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
    #endif

    // Sample texture (grayscale — use .r channel)
    float texSample = texture(uTexture, uv).r;

    // ── Pressure & velocity modulation ──
    float pressure = mix(uPressure1, uPressure2, t);
    float pressureFactor = 0.3 + pressure * 0.7;
    float velFactor = mix(1.0, 0.3, uVelocity);

    // ── Wet edge ──
    float edgeRatio = dist / max(halfW, 0.001);
    float wetDarken = 1.0 + uWetEdge * smoothstep(0.3, 0.9, edgeRatio) * 0.6;

    // ── Final erosion ──
    // Invert: dark grain areas → high erosion, white paper → no erosion
    float grain = 1.0 - texSample;
    grain = sqrt(grain); // compress extremes

    float erosion = grain * uIntensity * pressureFactor * velFactor * wetDarken;
    // Direct dstOut per capsule: each capsule erodes the stroke directly.
    // With aggressive coalescing (~8 capsules), overlap accumulates:
    //   8 × 0.03 → total ≈ 22% erosion (1-(1-0.03)^8).
    // This gives visible texture grain without making strokes transparent.
    erosion = clamp(erosion * 0.15, 0.0, 0.03);

    // Output: premultiplied alpha for dstOut erosion.
    float alpha = erosion * mask;
    fragColor = vec4(alpha, alpha, alpha, alpha);
}
