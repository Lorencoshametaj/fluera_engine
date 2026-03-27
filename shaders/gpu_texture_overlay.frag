#version 460 core

// GPU texture overlay fragment shader for flutter_gpu (PoC).
//
// Generates a procedural grain erosion mask.
// No texture inputs needed — pure GPU computation.
// Output: premultiplied alpha erosion mask for dstOut compositing.

in vec2 v_uv;
out vec4 fragColor;

// Uniforms
uniform TextureParams {
    float intensity;      // Texture intensity (0–1)
    float grainScale;     // Grain UV scale factor
    float grainOffsetX;   // Random grain UV offset X
    float grainOffsetY;   // Random grain UV offset Y
    float cosAngle;       // Pre-computed cos(rotation)
    float sinAngle;       // Pre-computed sin(rotation)
    float wetEdge;        // Unused in PoC (kept for API compat)
    float noiseType;      // 0 = fine, 1 = coarse, 2 = fibrous
} params;

// Hash-based pseudo-random (GPU-friendly, no texture needed)
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Multi-octave value noise
float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // smoothstep

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// FBM (fractal brownian motion) for natural-looking grain
float fbm(vec2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * valueNoise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void main() {
    // Rotated UV for grain orientation
    vec2 rotUV = vec2(
        v_uv.x * params.cosAngle - v_uv.y * params.sinAngle,
        v_uv.x * params.sinAngle + v_uv.y * params.cosAngle
    );

    vec2 grainUV = rotUV * params.grainScale + vec2(params.grainOffsetX, params.grainOffsetY);

    // Procedural grain based on type
    float grain;
    int noiseT = int(params.noiseType);
    if (noiseT == 0) {
        // Fine grain (pencil-like)
        grain = fbm(grainUV, 4);
    } else if (noiseT == 1) {
        // Coarse grain (charcoal-like)
        grain = fbm(grainUV * 0.5, 3);
        grain = grain * grain; // more contrast
    } else {
        // Fibrous grain (canvas-like)
        float h = fbm(vec2(grainUV.x * 3.0, grainUV.y), 2);
        float v = fbm(vec2(grainUV.x, grainUV.y * 3.0), 2);
        grain = max(h, v);
    }

    // Invert: dark areas → high erosion
    grain = 1.0 - grain;
    grain = sqrt(grain);

    // Final erosion
    float erosion = grain * params.intensity;
    erosion = clamp(erosion, 0.0, 0.85);

    // Output: premultiplied alpha erosion mask
    fragColor = vec4(erosion, erosion, erosion, erosion);
}
