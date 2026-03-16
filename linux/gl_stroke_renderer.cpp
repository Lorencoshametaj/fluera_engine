// gl_stroke_renderer.cpp — Deferred OpenGL live stroke renderer
// CPU tessellation on platform thread, GL rendering on raster thread.
#include "gl_stroke_renderer.h"

#include <algorithm>
#include <cstdio>

// ═══════════════════════════════════════════════════════════════════
// EMBEDDED GLSL SHADERS
// ═══════════════════════════════════════════════════════════════════

static const char* kVertexShaderGLSL = R"(
#version 330 core
layout(location = 0) in vec2 aPos;
layout(location = 1) in vec4 aColor;
uniform mat4 uMVP;
out vec4 vColor;
void main() {
    gl_Position = uMVP * vec4(aPos, 0.0, 1.0);
    vColor = aColor;
}
)";

static const char* kFragmentShaderGLSL = R"(
#version 330 core
in vec4 vColor;
out vec4 FragColor;
void main() {
    FragColor = vColor;
}
)";

// ═══════════════════════════════════════════════════════════════════
// DESTRUCTOR
// ═══════════════════════════════════════════════════════════════════

GLStrokeRenderer::~GLStrokeRenderer() { destroy(); }

// ═══════════════════════════════════════════════════════════════════
// INIT (no GL calls — just set dimensions)
// ═══════════════════════════════════════════════════════════════════

void GLStrokeRenderer::init(int width, int height) {
  std::lock_guard<std::mutex> lock(mutex_);
  width_ = width;
  height_ = height;
  pendingWidth_ = width;
  pendingHeight_ = height;
  needsResize_ = true;

  memset(transform_, 0, sizeof(transform_));
  transform_[0] = transform_[5] = transform_[10] = transform_[15] = 1.0f;

  vertices_.reserve(8192);
  frameTimesUs_.reserve(120);

  initialized_ = true;
}

// ═══════════════════════════════════════════════════════════════════
// CPU TESSELLATION (platform thread)
// ═══════════════════════════════════════════════════════════════════

void GLStrokeRenderer::updateVertices(
    const float *points, int pointCount, float r, float g, float b, float a,
    float strokeWidth, int totalPoints, int brushType,
    float pencilBaseOpacity, float pencilMaxOpacity,
    float pencilMinPressure, float pencilMaxPressure,
    float fountainThinning, float fountainNibAngleDeg,
    float fountainNibStrength, float fountainPressureRate,
    int fountainTaperEntry) {

  if (!initialized_ || pointCount < 2) return;

  std::lock_guard<std::mutex> lock(mutex_);

  // ── Tessellation (uses shared stroke_tessellation.h) ──────────
  if (brushType == 0) {
    // ── FULL RETESSELLATION (ballpoint) ──────────────────────────
    // Accumulate raw points, retessellate entire stroke for smooth curves.
    // Incremental tessellation caused sawtooth edges on curves because
    // EMA smoothing + Catmull-Rom only saw each batch.
    int skipFirst = (totalAccumulatedPoints_ > 0) ? 1 : 0;
    for (int i = skipFirst; i < pointCount; i++) {
      for (int j = 0; j < 5; j++)
        allPoints_.push_back(points[i * 5 + j]);
    }
    totalAccumulatedPoints_ = (int)(allPoints_.size() / 5);

    vertices_.clear();
    if (totalAccumulatedPoints_ >= 2) {
      stroke::tessellateStroke(allPoints_.data(), totalAccumulatedPoints_,
                               r, g, b, a, strokeWidth,
                               0, totalPoints, vertices_,
                               pencilMinPressure, pencilMaxPressure);
    }
  } else {
    vertices_.clear();
    totalAccumulatedPoints_ = pointCount;

    if (brushType == 1) {
      stroke::tessellateMarker(points, pointCount, r, g, b, a, strokeWidth,
                               vertices_);
    } else if (brushType == 3) {
      stroke::tessellateTechnicalPen(points, pointCount, r, g, b, a,
                                     strokeWidth, vertices_);
    } else if (brushType == 4) {
      float nibRad = fountainNibAngleDeg * 3.14159265f / 180.0f;
      stroke::tessellateFountainPen(points, pointCount, r, g, b, a,
                                    strokeWidth, pointCount, vertices_,
                                    fountainThinning, nibRad, fountainNibStrength,
                                    fountainPressureRate, fountainTaperEntry);
    } else {
      stroke::tessellatePencil(points, pointCount, r, g, b, a, strokeWidth,
                               0, pointCount, vertices_,
                               pencilBaseOpacity, pencilMaxOpacity,
                               pencilMinPressure, pencilMaxPressure);
    }
  }

  dirty_ = true;
}

// ═══════════════════════════════════════════════════════════════════
// GL RENDERING (raster thread — Flutter's GL context)
// ═══════════════════════════════════════════════════════════════════

bool GLStrokeRenderer::ensureGLResources() {
  if (glInitialized_ && !needsResize_) return true;

  // Clean up old resources if resizing
  if (glInitialized_) destroyGLResources();

  int w = pendingWidth_;
  int h = pendingHeight_;
  width_ = w;
  height_ = h;
  needsResize_ = false;

  // ── MSAA FBO ──────────────────────────────────────────────────
  // Query max supported MSAA samples and use the best available
  GLint maxSamples = 0;
  glGetIntegerv(GL_MAX_SAMPLES, &maxSamples);
  int samples = std::min((int)msaaSamples_, (int)maxSamples);
  if (samples < 2) samples = 2; // Minimum fallback

  glGenFramebuffers(1, &msaaFBO_);
  glBindFramebuffer(GL_FRAMEBUFFER, msaaFBO_);

  glGenRenderbuffers(1, &msaaColorRBO_);
  glBindRenderbuffer(GL_RENDERBUFFER, msaaColorRBO_);
  glRenderbufferStorageMultisample(GL_RENDERBUFFER, samples, GL_RGBA8, w, h);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, msaaColorRBO_);

  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    fprintf(stderr, "GLStrokeRenderer: MSAA FBO incomplete (samples=%d, max=%d)\\n", samples, maxSamples);
    return false;
  }

  // Clear MSAA FBO to transparent
  glClearColor(0, 0, 0, 0);
  glClear(GL_COLOR_BUFFER_BIT);

  // ── Resolve FBO (1x texture) ──────────────────────────────────
  glGenTextures(1, &resolveTexture_);
  glBindTexture(GL_TEXTURE_2D, resolveTexture_);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

  glGenFramebuffers(1, &resolveFBO_);
  glBindFramebuffer(GL_FRAMEBUFFER, resolveFBO_);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, resolveTexture_, 0);

  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    fprintf(stderr, "GLStrokeRenderer: Resolve FBO incomplete\n");
    return false;
  }

  // Clear resolve FBO to transparent
  glClearColor(0, 0, 0, 0);
  glClear(GL_COLOR_BUFFER_BIT);

  glBindFramebuffer(GL_FRAMEBUFFER, 0);

  // ── Shader pipeline ───────────────────────────────────────────
  GLuint vs = compileShader(GL_VERTEX_SHADER, kVertexShaderGLSL);
  GLuint fs = compileShader(GL_FRAGMENT_SHADER, kFragmentShaderGLSL);
  if (!vs || !fs) return false;

  shaderProgram_ = glCreateProgram();
  glAttachShader(shaderProgram_, vs);
  glAttachShader(shaderProgram_, fs);
  glLinkProgram(shaderProgram_);

  GLint ok;
  glGetProgramiv(shaderProgram_, GL_LINK_STATUS, &ok);
  if (!ok) {
    fprintf(stderr, "GLStrokeRenderer: Shader link failed\n");
    return false;
  }

  glDeleteShader(vs);
  glDeleteShader(fs);

  uniformMVP_ = glGetUniformLocation(shaderProgram_, "uMVP");

  // ── Vertex buffer ─────────────────────────────────────────────
  glGenVertexArrays(1, &vao_);
  glBindVertexArray(vao_);

  glGenBuffers(1, &vbo_);
  glBindBuffer(GL_ARRAY_BUFFER, vbo_);
  glBufferData(GL_ARRAY_BUFFER, MAX_VERTICES * sizeof(StrokeVertex), nullptr, GL_DYNAMIC_DRAW);

  // Position: float2 at offset 0
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(StrokeVertex), (void*)0);

  // Color: float4 at offset 8
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(StrokeVertex), (void*)(2 * sizeof(float)));

  glBindVertexArray(0);

  glInitialized_ = true;
  return true;
}

GLuint GLStrokeRenderer::renderAndGetTexture() {
  if (!initialized_) return 0;

  std::lock_guard<std::mutex> lock(mutex_);

  // Lazily create GL resources on Flutter's context
  if (!ensureGLResources()) return 0;

  if (needsClear_ || vertices_.empty()) {
    // Clear to transparent
    glBindFramebuffer(GL_FRAMEBUFFER, msaaFBO_);
    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT);

    glBindFramebuffer(GL_READ_FRAMEBUFFER, msaaFBO_);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, resolveFBO_);
    glBlitFramebuffer(0, 0, width_, height_, 0, 0, width_, height_,
                      GL_COLOR_BUFFER_BIT, GL_LINEAR);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    needsClear_ = false;

    if (vertices_.empty()) return resolveTexture_;
  }

  auto frameStart = std::chrono::steady_clock::now();

  // ── Upload vertices ───────────────────────────────────────────
  if (vertices_.size() > MAX_VERTICES) return resolveTexture_;

  glBindBuffer(GL_ARRAY_BUFFER, vbo_);
  glBufferSubData(GL_ARRAY_BUFFER, 0,
                  vertices_.size() * sizeof(StrokeVertex),
                  vertices_.data());

  // ── Save Flutter's GL state ───────────────────────────────────
  GLint prevFBO;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prevFBO);
  GLint prevViewport[4];
  glGetIntegerv(GL_VIEWPORT, prevViewport);
  GLboolean prevBlend = glIsEnabled(GL_BLEND);
  GLboolean prevDepth = glIsEnabled(GL_DEPTH_TEST);
  GLboolean prevCull = glIsEnabled(GL_CULL_FACE);
  GLint prevProgram;
  glGetIntegerv(GL_CURRENT_PROGRAM, &prevProgram);
  GLint prevVAO;
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prevVAO);

  // ── Draw to MSAA FBO ──────────────────────────────────────────
  glBindFramebuffer(GL_FRAMEBUFFER, msaaFBO_);
  glViewport(0, 0, width_, height_);

  // Clear before drawing (we re-tessellate the full stroke each update)
  glClearColor(0, 0, 0, 0);
  glClear(GL_COLOR_BUFFER_BIT);

  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);

  glUseProgram(shaderProgram_);

  // The Flutter/Dart side already sends a complete canvas→NDC matrix
  // (ortho * canvasTransform), so we use it directly as MVP.
  glUniformMatrix4fv(uniformMVP_, 1, GL_FALSE, transform_);



  glBindVertexArray(vao_);
  glDrawArrays(GL_TRIANGLES, 0, static_cast<GLsizei>(vertices_.size()));

  glBindVertexArray(0);

  // ── Resolve MSAA → output texture ─────────────────────────────
  glBindFramebuffer(GL_READ_FRAMEBUFFER, msaaFBO_);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, resolveFBO_);
  glBlitFramebuffer(0, 0, width_, height_, 0, 0, width_, height_,
                    GL_COLOR_BUFFER_BIT, GL_LINEAR);



  // ── Restore Flutter's GL state ────────────────────────────────
  glBindFramebuffer(GL_FRAMEBUFFER, prevFBO);
  glViewport(prevViewport[0], prevViewport[1], prevViewport[2], prevViewport[3]);
  glUseProgram(prevProgram);
  glBindVertexArray(prevVAO);
  if (!prevBlend) glDisable(GL_BLEND);
  if (prevDepth) glEnable(GL_DEPTH_TEST);
  if (prevCull) glEnable(GL_CULL_FACE);

  glFlush();

  dirty_ = false;

  // ── Performance stats ─────────────────────────────────────────
  statsActive_ = true;
  statsTotalFrames_++;
  auto frameEnd = std::chrono::steady_clock::now();
  float us = std::chrono::duration<float, std::micro>(frameEnd - frameStart).count();
  frameTimesUs_.push_back(us);
  if (frameTimesUs_.size() > 120) frameTimesUs_.erase(frameTimesUs_.begin());

  return resolveTexture_;
}

// ═══════════════════════════════════════════════════════════════════
// SET TRANSFORM / CLEAR / RESIZE / DESTROY
// ═══════════════════════════════════════════════════════════════════

void GLStrokeRenderer::setTransform(const float *matrix4x4) {
  std::lock_guard<std::mutex> lock(mutex_);
  memcpy(transform_, matrix4x4, sizeof(float) * 16);
  dirty_ = true;
}

void GLStrokeRenderer::clearFrame() {
  std::lock_guard<std::mutex> lock(mutex_);
  vertices_.clear();
  allPoints_.clear();
  totalAccumulatedPoints_ = 0;
  statsActive_ = false;
  needsClear_ = true;
  dirty_ = true;
}

void GLStrokeRenderer::resize(int width, int height) {
  std::lock_guard<std::mutex> lock(mutex_);
  pendingWidth_ = width;
  pendingHeight_ = height;
  needsResize_ = true;
  dirty_ = true;
}

void GLStrokeRenderer::destroyGLResources() {
  if (vbo_) { glDeleteBuffers(1, &vbo_); vbo_ = 0; }
  if (vao_) { glDeleteVertexArrays(1, &vao_); vao_ = 0; }
  if (shaderProgram_) { glDeleteProgram(shaderProgram_); shaderProgram_ = 0; }
  if (msaaColorRBO_) { glDeleteRenderbuffers(1, &msaaColorRBO_); msaaColorRBO_ = 0; }
  if (msaaFBO_) { glDeleteFramebuffers(1, &msaaFBO_); msaaFBO_ = 0; }
  if (resolveTexture_) { glDeleteTextures(1, &resolveTexture_); resolveTexture_ = 0; }
  if (resolveFBO_) { glDeleteFramebuffers(1, &resolveFBO_); resolveFBO_ = 0; }
  glInitialized_ = false;
}

void GLStrokeRenderer::destroy() {
  std::lock_guard<std::mutex> lock(mutex_);
  initialized_ = false;
  vertices_.clear();

  // Note: GL resources can only be destroyed with a valid context.
  // They will be cleaned up by destroyGLResources if a context is active,
  // or leaked if the context is already gone (acceptable at shutdown).
  if (glInitialized_) destroyGLResources();
}

GLuint GLStrokeRenderer::compileShader(GLenum type, const char *source) {
  GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, nullptr);
  glCompileShader(shader);

  GLint ok;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    char log[512];
    glGetShaderInfoLog(shader, 512, nullptr, log);
    fprintf(stderr, "GLStrokeRenderer: Shader compile error: %s\n", log);
    glDeleteShader(shader);
    return 0;
  }
  return shader;
}

GLStrokeStats GLStrokeRenderer::getStats() const {
  GLStrokeStats stats = {};
  std::lock_guard<std::mutex> lock(mutex_);
  stats.vertexCount = static_cast<uint32_t>(vertices_.size());
  stats.totalFrames = statsTotalFrames_;
  stats.active = statsActive_;

  if (!frameTimesUs_.empty()) {
    auto sorted = frameTimesUs_;
    std::sort(sorted.begin(), sorted.end());
    size_t c = sorted.size();
    stats.frameTimeP50Us = sorted[c / 2];
    stats.frameTimeP90Us = sorted[std::min(c - 1, (size_t)(c * 0.9f))];
    stats.frameTimeP99Us = sorted[std::min(c - 1, (size_t)(c * 0.99f))];
  }
  return stats;
}
