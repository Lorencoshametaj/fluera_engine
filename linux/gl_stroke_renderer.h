// gl_stroke_renderer.h — OpenGL live stroke renderer for Linux
// Uses DEFERRED RENDERING: CPU tessellation on method call,
// GL rendering inside Flutter's populate callback (Flutter's GL context).

#pragma once

#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glext.h>

#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <vector>

#include "../shared/stroke_tessellation.h"

/// Performance statistics snapshot.
struct GLStrokeStats {
  float frameTimeP50Us;
  float frameTimeP90Us;
  float frameTimeP99Us;
  uint32_t vertexCount;
  uint32_t totalFrames;
  bool active;
};

/// OpenGL live stroke renderer — deferred rendering pattern.
/// CPU tessellation runs on the platform thread (method channel).
/// GL rendering runs on the raster thread (FlTextureGL populate).
class GLStrokeRenderer {
public:
  GLStrokeRenderer() = default;
  ~GLStrokeRenderer();

  /// Set dimensions (no GL calls).
  void init(int width, int height);

  /// CPU-only: tessellate stroke vertices. Thread-safe.
  void updateVertices(const float *points, int pointCount, float r, float g,
                      float b, float a, float strokeWidth, int totalPoints,
                      int brushType = 0,
                      float pencilBaseOpacity = 0.4f, float pencilMaxOpacity = 0.8f,
                      float pencilMinPressure = 0.5f, float pencilMaxPressure = 1.2f,
                      float fountainThinning = 0.5f, float fountainNibAngleDeg = 30.0f,
                      float fountainNibStrength = 0.35f, float fountainPressureRate = 0.275f,
                      int fountainTaperEntry = 6);

  /// GL rendering — MUST be called with Flutter's GL context active.
  /// Called from FlTextureGL populate callback on raster thread.
  /// Returns the output texture name (valid in Flutter's context).
  GLuint renderAndGetTexture();

  /// Set canvas transform (4x4 column-major matrix). Thread-safe.
  void setTransform(const float *matrix4x4);

  /// Clear all vertices. Thread-safe.
  void clearFrame();

  /// Resize render target. Thread-safe (GL resources recreated on next render).
  void resize(int width, int height);

  /// Destroy GL resources (must be called with a valid GL context).
  void destroy();

  bool isInitialized() const { return initialized_; }
  bool isDirty() const { return dirty_; }
  int getWidth() const { return width_; }
  int getHeight() const { return height_; }

  GLStrokeStats getStats() const;

private:
  // ─── GL resources (created lazily on raster thread) ───────────
  GLuint msaaFBO_ = 0;
  GLuint msaaColorRBO_ = 0;
  static constexpr int msaaSamples_ = 16; // Desktop GPU can handle max MSAA
  GLuint resolveFBO_ = 0;
  GLuint resolveTexture_ = 0;
  GLuint shaderProgram_ = 0;
  GLuint vao_ = 0;
  GLuint vbo_ = 0;
  GLint uniformMVP_ = -1;
  bool glInitialized_ = false;

  // ─── Shared state (protected by mutex) ────────────────────────
  mutable std::mutex mutex_;
  float transform_[16] = {};
  int width_ = 0, height_ = 0;
  int pendingWidth_ = 0, pendingHeight_ = 0;
  bool initialized_ = false;
  bool dirty_ = false;
  bool needsResize_ = false;
  bool needsClear_ = false;

  // ─── Vertex data (written on platform thread, read on raster) ─
  static constexpr size_t MAX_VERTICES = 524288;
  std::vector<StrokeVertex> vertices_;
  std::vector<float> allPoints_;              // Raw accumulated points (stride 5)
  int totalAccumulatedPoints_ = 0;

  // ─── Performance tracking ─────────────────────────────────────
  std::vector<float> frameTimesUs_;
  uint32_t statsTotalFrames_ = 0;
  bool statsActive_ = false;

  // ─── GL init helpers (called on raster thread) ────────────────
  bool ensureGLResources();
  void destroyGLResources();
  GLuint compileShader(GLenum type, const char *source);
};
