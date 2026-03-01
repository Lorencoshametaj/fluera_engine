#version 460 core
#include <flutter/runtime_effect.glsl>

// ═══════════════════════════════════════════════════════════════════════════════
// ADJUSTMENT LAYER — GPU-accelerated non-destructive color transforms
// ═══════════════════════════════════════════════════════════════════════════════
//
// Applies all 10 AdjustmentType effects in a single pass.
// Zero-value uniforms = no-op for that effect → combine freely.
//
// Uniform layout matches adjustment_shader_service.dart setFloat(idx++) order.

// --- Resolution (for UV computation) ---
uniform float uResX;
uniform float uResY;

// --- Per-adjustment uniforms ---
uniform float uBrightness;     // -1..+1 (amount)
uniform float uContrast;       // 0..2   (factor, 1 = neutral)
uniform float uSaturation;     // 0..2   (factor, 1 = neutral)
uniform float uHueShift;       // -180..+180 degrees
uniform float uExposure;       // -5..+5 stops
uniform float uGamma;          // 0.1..3  (1 = linear)
uniform float uLevelsInBlack;  // 0..1
uniform float uLevelsInWhite;  // 0..1
uniform float uLevelsOutBlack; // 0..1
uniform float uLevelsOutWhite; // 0..1
uniform float uLevelsMidtone;  // 0.1..3  (1 = linear)
uniform float uInvert;         // 0 or 1
uniform float uThreshold;      // -1 = off, 0..1 = threshold value
uniform float uSepiaIntensity; // 0..1

// --- Input texture (the content below this adjustment node) ---
uniform sampler2D uTexture;

out vec4 fragColor;

// ═══════════════════════════════════════════════════════════════════════════════
// HSL CONVERSION (matches Dart AdjustmentLayer._rgbToHsl / _hslToRgb)
// ═══════════════════════════════════════════════════════════════════════════════

vec3 rgbToHsl(vec3 c) {
    float cMax = max(c.r, max(c.g, c.b));
    float cMin = min(c.r, min(c.g, c.b));
    float delta = cMax - cMin;
    float l = (cMax + cMin) * 0.5;
    float s = 0.0;
    float h = 0.0;

    if (delta > 0.0001) {
        s = l < 0.5 ? delta / (cMax + cMin) : delta / (2.0 - cMax - cMin);

        if (cMax == c.r) {
            h = mod((c.g - c.b) / delta, 6.0) * 60.0;
        } else if (cMax == c.g) {
            h = ((c.b - c.r) / delta + 2.0) * 60.0;
        } else {
            h = ((c.r - c.g) / delta + 4.0) * 60.0;
        }
        if (h < 0.0) h += 360.0;
    }

    return vec3(h, s, l);
}

float hueToRgb(float p, float q, float t) {
    if (t < 0.0) t += 1.0;
    if (t > 1.0) t -= 1.0;
    if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
    if (t < 0.5)       return q;
    if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    return p;
}

vec3 hslToRgb(vec3 hsl) {
    float h = hsl.x / 360.0;
    float s = hsl.y;
    float l = hsl.z;

    if (s < 0.0001) return vec3(l);

    float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
    float p = 2.0 * l - q;

    return vec3(
        hueToRgb(p, q, h + 1.0 / 3.0),
        hueToRgb(p, q, h),
        hueToRgb(p, q, h - 1.0 / 3.0)
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// LEVELS (matches Dart AdjustmentLayer._applyLevels)
// ═══════════════════════════════════════════════════════════════════════════════

float applyLevels(float v, float inB, float inW, float outB, float outW, float mid) {
    float range = inW - inB;
    if (range <= 0.0) return outB;
    float normalized = clamp((v - inB) / range, 0.0, 1.0);
    if (mid != 1.0 && mid > 0.0) {
        normalized = pow(normalized, 1.0 / mid);
    }
    return clamp(outB + normalized * (outW - outB), 0.0, 1.0);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / vec2(uResX, uResY);

    vec4 color = texture(uTexture, uv);

    // Early out for fully transparent pixels
    if (color.a < 0.001) {
        fragColor = color;
        return;
    }

    // Un-premultiply alpha for correct color math
    vec3 rgb = color.rgb / color.a;

    // ─── 1. BRIGHTNESS ───────────────────────────────────────────────
    rgb = clamp(rgb + uBrightness, 0.0, 1.0);

    // ─── 2. CONTRAST ─────────────────────────────────────────────────
    if (uContrast != 1.0) {
        rgb = clamp((rgb - 0.5) * uContrast + 0.5, 0.0, 1.0);
    }

    // ─── 3. SATURATION ───────────────────────────────────────────────
    if (uSaturation != 1.0) {
        float lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
        rgb = clamp(vec3(lum) + (rgb - vec3(lum)) * uSaturation, 0.0, 1.0);
    }

    // ─── 4. HUE SHIFT ────────────────────────────────────────────────
    if (abs(uHueShift) > 0.01) {
        vec3 hsl = rgbToHsl(rgb);
        hsl.x = mod(hsl.x + uHueShift + 360.0, 360.0);
        rgb = hslToRgb(hsl);
    }

    // ─── 5. EXPOSURE ─────────────────────────────────────────────────
    if (abs(uExposure) > 0.001) {
        float multiplier = pow(2.0, uExposure);
        rgb = clamp(rgb * multiplier, 0.0, 1.0);
    }

    // ─── 6. GAMMA ────────────────────────────────────────────────────
    if (uGamma != 1.0 && uGamma > 0.0) {
        float invGamma = 1.0 / uGamma;
        rgb = pow(clamp(rgb, 0.0, 1.0), vec3(invGamma));
    }

    // ─── 7. LEVELS ───────────────────────────────────────────────────
    if (uLevelsInBlack > 0.001 || uLevelsInWhite < 0.999 ||
        uLevelsOutBlack > 0.001 || uLevelsOutWhite < 0.999 ||
        uLevelsMidtone != 1.0) {
        rgb.r = applyLevels(rgb.r, uLevelsInBlack, uLevelsInWhite,
                           uLevelsOutBlack, uLevelsOutWhite, uLevelsMidtone);
        rgb.g = applyLevels(rgb.g, uLevelsInBlack, uLevelsInWhite,
                           uLevelsOutBlack, uLevelsOutWhite, uLevelsMidtone);
        rgb.b = applyLevels(rgb.b, uLevelsInBlack, uLevelsInWhite,
                           uLevelsOutBlack, uLevelsOutWhite, uLevelsMidtone);
    }

    // ─── 8. INVERT ───────────────────────────────────────────────────
    if (uInvert > 0.5) {
        rgb = 1.0 - rgb;
    }

    // ─── 9. THRESHOLD ────────────────────────────────────────────────
    if (uThreshold >= 0.0) {
        float lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
        float v = lum >= uThreshold ? 1.0 : 0.0;
        rgb = vec3(v);
    }

    // ─── 10. SEPIA ───────────────────────────────────────────────────
    if (uSepiaIntensity > 0.001) {
        vec3 sepia = vec3(
            clamp(rgb.r * 0.393 + rgb.g * 0.769 + rgb.b * 0.189, 0.0, 1.0),
            clamp(rgb.r * 0.349 + rgb.g * 0.686 + rgb.b * 0.168, 0.0, 1.0),
            clamp(rgb.r * 0.272 + rgb.g * 0.534 + rgb.b * 0.131, 0.0, 1.0)
        );
        rgb = mix(rgb, sepia, uSepiaIntensity);
    }

    // Re-premultiply alpha (required by Impeller/Skia compositing)
    fragColor = vec4(rgb * color.a, color.a);
}
