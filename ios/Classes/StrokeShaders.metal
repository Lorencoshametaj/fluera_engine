// StrokeShaders.metal — Metal Shading Language shaders for live stroke overlay
// Equivalent to the Vulkan SPIR-V in vk_shaders.h
//
// Vertex: position (float2) + color (float4) → transformed by 4×4 matrix
// Fragment: pass-through interpolated color

#include <metal_stdlib>
using namespace metal;

// Must match StrokeVertex layout in MetalStrokeRenderer
struct VertexIn {
    float2 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct Uniforms {
    float4x4 transform;
};

vertex VertexOut stroke_vertex(VertexIn in [[stage_in]],
                               constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.transform * float4(in.position, 0.0, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 stroke_fragment(VertexOut in [[stage_in]]) {
    return in.color;
}
