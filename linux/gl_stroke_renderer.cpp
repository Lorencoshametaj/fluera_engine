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

  // 🚀 Start background tessellation worker
  tessThread_.start();

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
  // 🚀 Acquire pre-reserved vertex vector from pool (zero alloc hot path)
  int poolSlot;
  auto& verts = vertexPool_.acquire(poolSlot);

  if (brushType == 0) {
    // ── FULL RETESSELLATION (ballpoint) ──────────────────────────
    // Ring buffer / FFI already send ALL accumulated points.
    // Tessellate directly — no internal accumulation
    // (allPoints_ caused double-accumulation with ring buffer → fan artifact).
    totalAccumulatedPoints_ = pointCount;

    if (pointCount >= 2) {
      stroke::tessellateStroke(points, pointCount,
                               r, g, b, a, strokeWidth,
                               0, totalPoints, verts,
                               pencilMinPressure, pencilMaxPressure);
    }

    // Copy to vertices_ for rendering
    vertices_.assign(verts.begin(), verts.end());
    vertexPool_.release(poolSlot);
  } else {
    // 🚀 Non-ballpoint: use GPU compute if available, else background thread
    totalAccumulatedPoints_ = pointCount;

    int subsPerSeg = dynamicSubsPerSeg_;  // 🚀 Adaptive LOD

    bool useCompute = computeAvailable_ && brushType != 0;
    if (useCompute) {
      // Store params for deferred compute dispatch (GL context needed)
      pendingComputePoints_.assign(points, points + pointCount * 5);

      // 🚀 Incremental compute: only tessellate NEW segments
      int startSeg = 0;
      if (prevComputePointCount_ >= 2 && pointCount > prevComputePointCount_) {
        // Overlap 1 segment for Catmull-Rom continuity
        startSeg = std::max(0, prevComputePointCount_ - 2);
      }
      int newSubdivs = (pointCount - 1 - startSeg) * subsPerSeg;
      int totalSubdivs = (pointCount - 1) * subsPerSeg;

      incrementalStartSeg_ = startSeg;
      totalComputeVertexCount_ = totalSubdivs * 6;

      pendingComputeParams_ = {};
      pendingComputeParams_.colorR = r; pendingComputeParams_.colorG = g;
      pendingComputeParams_.colorB = b; pendingComputeParams_.colorA = a;
      pendingComputeParams_.strokeWidth = strokeWidth;
      pendingComputeParams_.pointCount = pointCount;
      pendingComputeParams_.brushType = brushType;
      pendingComputeParams_.minPressure = pencilMinPressure;
      pendingComputeParams_.maxPressure = pencilMaxPressure;
      pendingComputeParams_.pencilBaseOpacity = pencilBaseOpacity;
      pendingComputeParams_.pencilMaxOpacity = pencilMaxOpacity;
      pendingComputeParams_.subsPerSeg = subsPerSeg;
      pendingComputeParams_.totalSubdivs = newSubdivs;  // Only new portion!
      pendingComputeParams_.fountainThinning = fountainThinning;
      pendingComputeParams_.fountainNibAngleRad = fountainNibAngleDeg * 3.14159265f / 180.0f;
      pendingComputeParams_.fountainNibStrength = fountainNibStrength;
      pendingComputeVertexCount_ = totalComputeVertexCount_;
      prevComputePointCount_ = pointCount;
      computePending_ = true;
      // Skip CPU tessellation — compute will handle it
    } else {
      // CPU fallback: tessellate on background thread
      auto pointsCopy = std::make_shared<std::vector<float>>(points, points + pointCount * 5);

      tessThread_.submit([=](std::vector<StrokeVertex>& out) {
        const float* pts = pointsCopy->data();
        if (brushType == 1) {
          stroke::tessellateMarker(pts, pointCount, r, g, b, a, strokeWidth, out);
        } else if (brushType == 3) {
          stroke::tessellateTechnicalPen(pts, pointCount, r, g, b, a,
                                         strokeWidth, out);
        } else if (brushType == 4) {
          float nibRad = fountainNibAngleDeg * 3.14159265f / 180.0f;
          stroke::tessellateFountainPen(pts, pointCount, r, g, b, a,
                                        strokeWidth, pointCount, out,
                                        fountainThinning, nibRad, fountainNibStrength,
                                        fountainPressureRate, fountainTaperEntry);
        } else {
          stroke::tessellatePencil(pts, pointCount, r, g, b, a, strokeWidth,
                                   0, pointCount, out,
                                   pencilBaseOpacity, pencilMaxOpacity,
                                   pencilMinPressure, pencilMaxPressure);
        }
      });
    }

    vertexPool_.release(poolSlot);
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

  // 🚀 Try to create compute pipeline (GL 4.3+)
  createComputePipeline();

  return true;
}

GLuint GLStrokeRenderer::renderAndGetTexture() {
  if (!initialized_) return 0;

  std::lock_guard<std::mutex> lock(mutex_);

  // Lazily create GL resources on Flutter's context
  if (!ensureGLResources()) return 0;

  if (needsClear_ || vertices_.empty()) {
    // 🚀 Check for background tessellation results
    if (tessThread_.trySwap()) {
      auto& front = tessThread_.frontVertices();
      vertices_.assign(front.begin(), front.end());
      dirty_ = true;
    }

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
  } else {
    // 🚀 Check for background tessellation results even when not clearing
    if (tessThread_.trySwap()) {
      auto& front = tessThread_.frontVertices();
      vertices_.assign(front.begin(), front.end());
      dirty_ = true;
    }
  }

  auto frameStart = std::chrono::steady_clock::now();

  // 🚀 GPU Compute dispatch (if pending from platform thread)
  bool drawnViaCompute = false;
  if (computePending_ && computeAvailable_ && computeProgram_) {
    dispatchCompute();
    drawnViaCompute = true;
    computePending_ = false;
  }

  if (!drawnViaCompute) {
    // CPU tessellation path: upload from vertices_
    if (vertices_.size() > MAX_VERTICES) return resolveTexture_;

    glBindBuffer(GL_ARRAY_BUFFER, vbo_);
    glBufferSubData(GL_ARRAY_BUFFER, 0,
                    vertices_.size() * sizeof(StrokeVertex),
                    vertices_.data());
  }

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

  if (drawnViaCompute) {
    // Bind compute output SSBO as vertex source
    glBindBuffer(GL_ARRAY_BUFFER, computeVertexSSBO_);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 6 * sizeof(float), (void*)0);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, 6 * sizeof(float), (void*)(2 * sizeof(float)));
    glDrawArrays(GL_TRIANGLES, 0, static_cast<GLsizei>(pendingComputeVertexCount_));
    // Rebind original VBO for next frame
    glBindBuffer(GL_ARRAY_BUFFER, vbo_);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(StrokeVertex), (void*)0);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(StrokeVertex), (void*)(2 * sizeof(float)));
  } else {
    glDrawArrays(GL_TRIANGLES, 0, static_cast<GLsizei>(vertices_.size()));
  }

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
  prevComputePointCount_ = 0;
  statsActive_ = false;
  needsClear_ = true;
  dirty_ = true;
  vertexPool_.releaseAll();
}

// 🚀 Memory pressure management (matches Vulkan pattern)
void GLStrokeRenderer::trimMemory(int level) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (level >= 1) {
    // Warning: trim free pool buffers
    vertexPool_.trim();
  }
  if (level >= 2) {
    // Critical: release ALL pool buffers + shrink vectors
    vertexPool_.releaseAll();
    vertexPool_.trim();
    allPoints_.clear();
    allPoints_.shrink_to_fit();
    vertices_.clear();
    vertices_.shrink_to_fit();
    pendingComputePoints_.clear();
    pendingComputePoints_.shrink_to_fit();
  }
}

// 🚀 Adaptive LOD: compute dynamic subdivision count from zoom
void GLStrokeRenderer::setZoomLevel(float zoom) {
  std::lock_guard<std::mutex> lock(mutex_);
  int prev = dynamicSubsPerSeg_;
  zoomLevel_ = zoom;
  if (zoom < 0.3f) dynamicSubsPerSeg_ = 4;
  else if (zoom < 0.6f) dynamicSubsPerSeg_ = 6;
  else if (zoom > 4.0f) dynamicSubsPerSeg_ = 16;
  else if (zoom > 2.0f) dynamicSubsPerSeg_ = 12;
  else dynamicSubsPerSeg_ = 8;
  if (dynamicSubsPerSeg_ != prev) {
    fprintf(stderr, "GLStrokeRenderer: \xF0\x9F\x94\x8D LOD zoom=%.2f subsPerSeg=%d→%d\n", zoom, prev, dynamicSubsPerSeg_);
  }
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
  tessThread_.stop();
  std::lock_guard<std::mutex> lock(mutex_);
  initialized_ = false;
  vertices_.clear();
  vertexPool_.releaseAll();

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

// ═══════════════════════════════════════════════════════════════════
// 🚀 GL COMPUTE TESSELLATION (GL 4.3+)
// ═══════════════════════════════════════════════════════════════════

// OpenGL 4.3 compute shader — adapted from stroke_compute.comp
// Uses binding= instead of set=,binding= for GL compatibility.
static const char* kComputeShaderGLSL = R"(
#version 430

layout(local_size_x = 64) in;

layout(std140, binding = 0) uniform Params {
  float colorR, colorG, colorB, colorA;
  float strokeWidth;
  int   pointCount;
  int   brushType;
  float minPressure, maxPressure;
  float pencilBaseOpacity, pencilMaxOpacity;
  int   subsPerSeg;
  int   totalSubdivs;
  float fountainThinning, fountainNibAngleRad, fountainNibStrength;
  int   startSeg;
  int   vertexOffset;
};

layout(std430, binding = 1) readonly buffer PointsIn { float points[]; };
layout(std430, binding = 2) writeonly buffer VerticesOut { float verts[]; };

float getX(int i) { return points[i * 5]; }
float getY(int i) { return points[i * 5 + 1]; }
float getP(int i) { return points[i * 5 + 2]; }

vec2 catmullRom(vec2 p0, vec2 p1, vec2 p2, vec2 p3, float t) {
  float t2 = t*t, t3 = t2*t;
  return 0.5 * ((2.0*p1) + (-p0+p2)*t + (2.0*p0-5.0*p1+4.0*p2-p3)*t2 + (-p0+3.0*p1-3.0*p2+p3)*t3);
}

vec2 catmullRomTangent(vec2 p0, vec2 p1, vec2 p2, vec2 p3, float t) {
  float t2 = t*t;
  return 0.5 * ((-p0+p2) + (4.0*p0-10.0*p1+8.0*p2-2.0*p3)*t + (-3.0*p0+9.0*p1-9.0*p2+3.0*p3)*t2);
}

void writeVertex(int idx, float x, float y, float r, float g, float b, float a) {
  int base = idx * 6;
  verts[base]=x; verts[base+1]=y; verts[base+2]=r; verts[base+3]=g; verts[base+4]=b; verts[base+5]=a;
}

float computeHalfWidth(int bt, float sw, float p, int gi, int N, float mnP, float mxP, vec2 dir, float nibR, float nibS, float thin) {
  if (bt==0) return sw * (mnP + 0.5*(mxP-mnP)) * 0.5;
  if (bt==1) return sw * 2.5 * 0.5;
  if (bt==2) { float hw = sw*0.5*(mnP+p*(mxP-mnP)); if(gi<4){float t=float(gi)/4.0;hw*=0.15+t*(2.0-t)*0.85;} return hw; }
  if (bt==4) { float hw=sw*0.5*(0.4+p*0.6*(1.0-thin)); float da=abs(atan(dir.y,dir.x)-nibR); float cn=abs(sin(da)); hw*=(0.4+mix(1.0,cn,nibS)*0.6); if(gi<6){float t=float(gi)/6.0;hw*=0.2+t*0.8;} return hw; }
  return sw * 0.5;
}

void main() {
  int gid = int(gl_GlobalInvocationID.x);
  if (gid >= totalSubdivs) return;
  int localSeg = gid / subsPerSeg, sub = gid % subsPerSeg;
  int seg = localSeg + startSeg;
  int N = pointCount;
  if (seg >= N-1) return;

  int i0=max(seg-1,0), i1=seg, i2=seg+1, i3=min(seg+2,N-1);
  vec2 p0=vec2(getX(i0),getY(i0)), p1=vec2(getX(i1),getY(i1));
  vec2 p2=vec2(getX(i2),getY(i2)), p3=vec2(getX(i3),getY(i3));

  float t = float(sub)/float(subsPerSeg);
  vec2 pos = catmullRom(p0,p1,p2,p3,t);
  vec2 tan = catmullRomTangent(p0,p1,p2,p3,t);
  float tl = length(tan); if(tl<0.0001) tan=vec2(1,0); else tan/=tl;

  float tN; vec2 posN, tanN;
  if (sub < subsPerSeg-1) { tN=float(sub+1)/float(subsPerSeg); posN=catmullRom(p0,p1,p2,p3,tN); tanN=catmullRomTangent(p0,p1,p2,p3,tN); }
  else if (seg+1<N-1) { int j0=max(seg,0),j1=seg+1,j2=min(seg+2,N-1),j3=min(seg+3,N-1);
    posN=catmullRom(vec2(getX(j0),getY(j0)),vec2(getX(j1),getY(j1)),vec2(getX(j2),getY(j2)),vec2(getX(j3),getY(j3)),0.0);
    tanN=catmullRomTangent(vec2(getX(j0),getY(j0)),vec2(getX(j1),getY(j1)),vec2(getX(j2),getY(j2)),vec2(getX(j3),getY(j3)),0.0);
  } else { posN=p2; tanN=p2-p1; }
  float tnl=length(tanN); if(tnl<0.0001) tanN=vec2(1,0); else tanN/=tnl;

  vec2 perp=vec2(-tan.y,tan.x), perpN=vec2(-tanN.y,tanN.x);
  float pr=mix(getP(i1),getP(i2),t), prN=mix(getP(i1),getP(i2),sub<subsPerSeg-1?tN:1.0);
  float hw=computeHalfWidth(brushType,strokeWidth,pr,seg,N,minPressure,maxPressure,tan,fountainNibAngleRad,fountainNibStrength,fountainThinning);
  float hwN=computeHalfWidth(brushType,strokeWidth,prN,seg+(sub==subsPerSeg-1?1:0),N,minPressure,maxPressure,tanN,fountainNibAngleRad,fountainNibStrength,fountainThinning);
  float al=colorA, alN=colorA;
  if(brushType==2){al*=pencilBaseOpacity+(pencilMaxOpacity-pencilBaseOpacity)*pr;alN*=pencilBaseOpacity+(pencilMaxOpacity-pencilBaseOpacity)*prN;}

  vec2 L=pos+perp*hw, R=pos-perp*hw, LN=posN+perpN*hwN, RN=posN-perpN*hwN;
  int ob=(gid+vertexOffset)*6;
  writeVertex(ob,L.x,L.y,colorR,colorG,colorB,al); writeVertex(ob+1,R.x,R.y,colorR,colorG,colorB,al);
  writeVertex(ob+2,LN.x,LN.y,colorR,colorG,colorB,alN); writeVertex(ob+3,R.x,R.y,colorR,colorG,colorB,al);
  writeVertex(ob+4,LN.x,LN.y,colorR,colorG,colorB,alN); writeVertex(ob+5,RN.x,RN.y,colorR,colorG,colorB,alN);
}
)";

// 🚀 Dispatch GPU compute tessellation (called on raster thread with GL context)
void GLStrokeRenderer::dispatchCompute() {
  // Upload points to SSBO
  size_t pointBytes = pendingComputePoints_.size() * sizeof(float);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, computePointsSSBO_);
  glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, pointBytes, pendingComputePoints_.data());

  // Upload params to UBO (std140 layout)
  glBindBuffer(GL_UNIFORM_BUFFER, computeParamsUBO_);
  float uboData[20] = {};
  uboData[0] = pendingComputeParams_.colorR;
  uboData[1] = pendingComputeParams_.colorG;
  uboData[2] = pendingComputeParams_.colorB;
  uboData[3] = pendingComputeParams_.colorA;
  uboData[4] = pendingComputeParams_.strokeWidth;
  memcpy(&uboData[5], &pendingComputeParams_.pointCount, sizeof(int));
  memcpy(&uboData[6], &pendingComputeParams_.brushType, sizeof(int));
  uboData[7] = pendingComputeParams_.minPressure;
  uboData[8] = pendingComputeParams_.maxPressure;
  uboData[9] = pendingComputeParams_.pencilBaseOpacity;
  uboData[10] = pendingComputeParams_.pencilMaxOpacity;
  memcpy(&uboData[11], &pendingComputeParams_.subsPerSeg, sizeof(int));
  memcpy(&uboData[12], &pendingComputeParams_.totalSubdivs, sizeof(int));
  uboData[13] = pendingComputeParams_.fountainThinning;
  uboData[14] = pendingComputeParams_.fountainNibAngleRad;
  uboData[15] = pendingComputeParams_.fountainNibStrength;
  memcpy(&uboData[16], &incrementalStartSeg_, sizeof(int));
  int vertexOffset = incrementalStartSeg_ * pendingComputeParams_.subsPerSeg;
  memcpy(&uboData[17], &vertexOffset, sizeof(int));
  glBufferSubData(GL_UNIFORM_BUFFER, 0, sizeof(uboData), uboData);

  // Bind resources
  glBindBufferBase(GL_UNIFORM_BUFFER, 0, computeParamsUBO_);
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, computePointsSSBO_);
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, computeVertexSSBO_);

  // Dispatch
  glUseProgram(computeProgram_);
  GLuint groups = (pendingComputeParams_.totalSubdivs + 63) / 64;
  glDispatchCompute(groups, 1, 1);

  // Memory barrier: compute writes → vertex reads
  glMemoryBarrier(GL_VERTEX_ATTRIB_ARRAY_BARRIER_BIT);

  glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
  glBindBuffer(GL_UNIFORM_BUFFER, 0);
}

bool GLStrokeRenderer::createComputePipeline() {
  // Check GL 4.3 compute shader support
  GLint major = 0, minor = 0;
  glGetIntegerv(GL_MAJOR_VERSION, &major);
  glGetIntegerv(GL_MINOR_VERSION, &minor);
  if (major < 4 || (major == 4 && minor < 3)) {
    fprintf(stderr, "GLStrokeRenderer: GL %d.%d — compute shaders require 4.3+\n", major, minor);
    return false;
  }

  // Compile compute shader
  GLuint cs = glCreateShader(GL_COMPUTE_SHADER);
  glShaderSource(cs, 1, &kComputeShaderGLSL, nullptr);
  glCompileShader(cs);
  GLint ok;
  glGetShaderiv(cs, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    char log[512];
    glGetShaderInfoLog(cs, 512, nullptr, log);
    fprintf(stderr, "GLStrokeRenderer: Compute shader compile error: %s\n", log);
    glDeleteShader(cs);
    return false;
  }

  computeProgram_ = glCreateProgram();
  glAttachShader(computeProgram_, cs);
  glLinkProgram(computeProgram_);
  glGetProgramiv(computeProgram_, GL_LINK_STATUS, &ok);
  glDeleteShader(cs);
  if (!ok) {
    fprintf(stderr, "GLStrokeRenderer: Compute program link failed\n");
    glDeleteProgram(computeProgram_);
    computeProgram_ = 0;
    return false;
  }

  // Create SSBOs
  static constexpr size_t MAX_POINTS = 5000;
  static constexpr size_t POINTS_BUF_SIZE = MAX_POINTS * 5 * sizeof(float);
  static constexpr size_t VERTS_BUF_SIZE = MAX_POINTS * SUBS_PER_SEG * 6 * 6 * sizeof(float);

  glGenBuffers(1, &computePointsSSBO_);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, computePointsSSBO_);
  glBufferData(GL_SHADER_STORAGE_BUFFER, POINTS_BUF_SIZE, nullptr, GL_DYNAMIC_DRAW);

  glGenBuffers(1, &computeVertexSSBO_);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, computeVertexSSBO_);
  glBufferData(GL_SHADER_STORAGE_BUFFER, VERTS_BUF_SIZE, nullptr, GL_DYNAMIC_DRAW);

  // Params UBO (std140 layout, 13 members padded)
  glGenBuffers(1, &computeParamsUBO_);
  glBindBuffer(GL_UNIFORM_BUFFER, computeParamsUBO_);
  glBufferData(GL_UNIFORM_BUFFER, 256, nullptr, GL_DYNAMIC_DRAW); // padded

  glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
  glBindBuffer(GL_UNIFORM_BUFFER, 0);

  computeAvailable_ = true;
  fprintf(stderr, "GLStrokeRenderer: 🚀 Compute tessellation ready (GL %d.%d)\n", major, minor);

  // 🚀 Warm-up: dispatch 1-workgroup dummy compute to pre-compile shader
  {
    float dummyPoints[10] = {0,0,1,0,0, 1,1,1,0,0}; // 2 points
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, computePointsSSBO_);
    glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, sizeof(dummyPoints), dummyPoints);

    float ubo[18] = {0};
    ubo[0] = 0; ubo[1] = 0; ubo[2] = 0; ubo[3] = 1; // color
    ubo[4] = 1.0f; // strokeWidth
    int pc = 2; memcpy(&ubo[5], &pc, sizeof(int)); // pointCount
    int bt = 1; memcpy(&ubo[6], &bt, sizeof(int)); // brushType
    int sps = 8; memcpy(&ubo[11], &sps, sizeof(int));
    int td = 8; memcpy(&ubo[12], &td, sizeof(int));
    glBindBuffer(GL_UNIFORM_BUFFER, computeParamsUBO_);
    glBufferSubData(GL_UNIFORM_BUFFER, 0, sizeof(ubo), ubo);

    glUseProgram(computeProgram_);
    glBindBufferBase(GL_UNIFORM_BUFFER, 0, computeParamsUBO_);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, computePointsSSBO_);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, computeVertexSSBO_);
    glDispatchCompute(1, 1, 1);
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);
    glUseProgram(0);
    fprintf(stderr, "GLStrokeRenderer: 🔥 Shader warm-up complete\n");
  }

  return true;
}

void GLStrokeRenderer::destroyComputeResources() {
  if (computeProgram_) { glDeleteProgram(computeProgram_); computeProgram_ = 0; }
  if (computePointsSSBO_) { glDeleteBuffers(1, &computePointsSSBO_); computePointsSSBO_ = 0; }
  if (computeVertexSSBO_) { glDeleteBuffers(1, &computeVertexSSBO_); computeVertexSSBO_ = 0; }
  if (computeParamsUBO_) { glDeleteBuffers(1, &computeParamsUBO_); computeParamsUBO_ = 0; }
  if (computeCapSSBO_) { glDeleteBuffers(1, &computeCapSSBO_); computeCapSSBO_ = 0; }
  if (computeCapCounterSSBO_) { glDeleteBuffers(1, &computeCapCounterSSBO_); computeCapCounterSSBO_ = 0; }
  computeAvailable_ = false;
}

