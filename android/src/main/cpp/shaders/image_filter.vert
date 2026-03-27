#version 450

// Fullscreen quad vertex shader for image processing

layout(location = 0) out vec2 fragUV;

void main() {
    // 6 vertices for fullscreen quad (2 triangles)
    const vec2 positions[6] = vec2[](
        vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(-1.0, 1.0),
        vec2(-1.0,  1.0), vec2(1.0, -1.0), vec2(1.0,  1.0)
    );
    const vec2 uvs[6] = vec2[](
        vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0),
        vec2(0.0, 1.0), vec2(1.0, 0.0), vec2(1.0, 1.0)
    );

    fragUV = uvs[gl_VertexIndex];
    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
}
