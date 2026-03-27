#version 460 core

// Full-screen quad vertex shader for flutter_gpu texture overlay.
// Generates a quad from vertex index (0-5) covering the full clip space.
// Passes UV coordinates to the fragment shader.

in vec2 position;
in vec2 uv;

out vec2 v_uv;

void main() {
    v_uv = uv;
    gl_Position = vec4(position, 0.0, 1.0);
}
