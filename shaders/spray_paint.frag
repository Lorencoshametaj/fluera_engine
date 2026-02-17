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
uniform float uPressure;   // Pressure (controls dot density)
uniform float uVelocity;   // Velocity (controls spread radius)
uniform float uSeed;       // Random seed
uniform float uDensity;    // Dot density (0–1)

out vec4 fragColor;

// Hash noise for stochastic dots
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Hash-based cell noise for spatter pattern
float dotPattern(vec2 p, float density) {
    vec2 cell = floor(p);
    vec2 frac = fract(p);

    float minDist = 1.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 cellId = cell + neighbor;
            // Random dot center within cell
            vec2 dotPos = vec2(hash(cellId), hash(cellId + vec2(13.7, 37.1)));
            vec2 diff = neighbor + dotPos - frac;
            float d = length(diff);
            minDist = min(minDist, d);
        }
    }

    // threshold: lower density → more dots filtered out
    float threshold = 1.0 - density;
    float dotMask = smoothstep(threshold * 0.5, threshold * 0.3, minDist);
    return dotMask;
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

    // Wide gaussian-like falloff for spray cone
    float spreadFactor = 1.0 + uVelocity * 0.5;
    float halfW = w * 0.5 * spreadFactor;
    float gaussian = exp(-2.0 * (dist * dist) / max(halfW * halfW, 0.001));

    // Stochastic dot pattern at multiple scales
    float scale1 = 3.0 + uPressure * 2.0;
    float scale2 = 6.0 + uPressure * 3.0;
    float dots1 = dotPattern(fragCoord * (scale1 / max(w, 1.0)) + uSeed, uDensity * uPressure);
    float dots2 = dotPattern(fragCoord * (scale2 / max(w, 1.0)) + uSeed * 1.7, uDensity * uPressure * 0.6);

    // Combine dot layers: large + fine spatter
    float dots = max(dots1, dots2 * 0.5);

    // Center bias: denser near center, sparser at edges
    float centerBias = gaussian;

    // Final alpha
    float alpha = dots * centerBias * uColorA;
    alpha = clamp(alpha, 0.0, uColorA);

    fragColor = vec4(uColorR * alpha, uColorG * alpha, uColorB * alpha, alpha);
}
