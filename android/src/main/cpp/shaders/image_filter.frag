#version 450

// Combined color grading + vignette fragment shader

layout(location = 0) in vec2 fragUV;
layout(location = 0) out vec4 outColor;

layout(binding = 0) uniform sampler2D srcTexture;

layout(push_constant) uniform Params {
    float brightness;   // -1..+1
    float contrast;     // -1..+1
    float saturation;   // -1..+1
    float hueShift;     // -1..+1 (maps to -π..+π)
    float temperature;  // -1..+1
    float opacity;      // 0..1
    float vignette;     // 0..1
    float _pad;
} params;

void main() {
    vec4 color = texture(srcTexture, fragUV);

    // Brightness
    color.rgb += params.brightness;

    // Contrast
    float c = params.contrast + 1.0;
    color.rgb = (color.rgb - 0.5) * c + 0.5;

    // Saturation
    float s = params.saturation + 1.0;
    float luminance = dot(color.rgb, vec3(0.3086, 0.6094, 0.0820));
    color.rgb = mix(vec3(luminance), color.rgb, s);

    // Hue rotation (Rodrigues' formula in RGB space)
    if (abs(params.hueShift) > 0.001) {
        float angle = params.hueShift * 3.14159265;
        float cosA = cos(angle);
        float sinA = sin(angle);
        float k = 1.0 / 3.0;
        float sq = 0.57735; // 1/sqrt(3)

        mat3 hueMatrix = mat3(
            cosA + (1.0 - cosA) * k,
            k * (1.0 - cosA) + sq * sinA,
            k * (1.0 - cosA) - sq * sinA,

            k * (1.0 - cosA) - sq * sinA,
            cosA + (1.0 - cosA) * k,
            k * (1.0 - cosA) + sq * sinA,

            k * (1.0 - cosA) + sq * sinA,
            k * (1.0 - cosA) - sq * sinA,
            cosA + (1.0 - cosA) * k
        );
        color.rgb = hueMatrix * color.rgb;
    }

    // Temperature (warm = +red +green*0.4 -blue)
    if (abs(params.temperature) > 0.001) {
        float temp = params.temperature * 0.12;
        color.r += temp;
        color.g += temp * 0.4;
        color.b -= temp;
    }

    // Vignette (radial darkening)
    if (params.vignette > 0.001) {
        vec2 center = fragUV - 0.5;
        float dist = length(center) * 1.414;
        float vig = smoothstep(0.3, 1.0, dist);
        color.rgb *= 1.0 - vig * params.vignette * 0.7;
    }

    // Opacity
    color.a *= params.opacity;

    // Clamp
    outColor = clamp(color, 0.0, 1.0);
}
