// d3d11_stroke_renderer.h — D3D11 live stroke renderer for Windows
// Renders tessellated triangles with MSAA 4x into a shared ID3D11Texture2D
// for Flutter TextureRegistrar.

#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi.h>
#include <wrl/client.h>

#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

#include "../shared/stroke_tessellation.h"
#include "../shared/tessellation_thread.h"
#include "../shared/vertex_buffer_pool.h"

using Microsoft::WRL::ComPtr;

/// Performance statistics snapshot.
struct D3D11StrokeStats {
  float frameTimeP50Us;
  float frameTimeP90Us;
  float frameTimeP99Us;
  uint32_t vertexCount;
  uint32_t totalFrames;
  bool active;
};

/// D3D11 live stroke renderer — renders tessellated triangle lists with MSAA.
class D3D11StrokeRenderer {
public:
  D3D11StrokeRenderer() = default;
  ~D3D11StrokeRenderer();

  /// Initialize D3D11 device and render resources.
  bool init(int width, int height);

  /// Tessellate + render. Same signature as Vulkan/Metal.
  void updateAndRender(const float *points, int pointCount, float r, float g,
                       float b, float a, float strokeWidth, int totalPoints,
                       int brushType = 0,
                       float pencilBaseOpacity = 0.4f, float pencilMaxOpacity = 0.8f,
                       float pencilMinPressure = 0.5f, float pencilMaxPressure = 1.2f,
                       float fountainThinning = 0.5f, float fountainNibAngleDeg = 30.0f,
                       float fountainNibStrength = 0.35f, float fountainPressureRate = 0.275f,
                       int fountainTaperEntry = 6);

  /// Set canvas transform (4x4 column-major matrix).
  void setTransform(const float *matrix4x4);

  /// Clear render target to transparent.
  void clearFrame();

  /// Resize render target.
  bool resize(int width, int height);

  /// Destroy all resources.
  void destroy();

  /// 🚀 Memory pressure: release non-essential buffers
  void trimMemory(int level = 1);

  /// 🚀 Adaptive LOD: set current zoom level for dynamic subdivision count
  void setZoomLevel(float zoom);

  bool isInitialized() const { return initialized_; }

  /// Get the output texture for Flutter TextureRegistrar.
  ID3D11Texture2D* getOutputTexture() const { return resolveTexture_.Get(); }

  /// Get performance stats.
  D3D11StrokeStats getStats() const;

private:
  // ─── D3D11 Core ───────────────────────────────────────────────
  ComPtr<ID3D11Device> device_;
  ComPtr<ID3D11DeviceContext> context_;
  ComPtr<IDXGIDevice> dxgiDevice_;

  // ─── MSAA render target (4x) ─────────────────────────────────
  ComPtr<ID3D11Texture2D> msaaTexture_;
  ComPtr<ID3D11RenderTargetView> msaaRTV_;
  static constexpr UINT msaaSampleCount_ = 4;

  // ─── Resolved output (1x, shared with Flutter) ───────────────
  ComPtr<ID3D11Texture2D> resolveTexture_;

  // ─── Pipeline ─────────────────────────────────────────────────
  ComPtr<ID3D11VertexShader> vertexShader_;
  ComPtr<ID3D11PixelShader> pixelShader_;
  ComPtr<ID3D11InputLayout> inputLayout_;
  ComPtr<ID3D11Buffer> vertexBuffer_;
  ComPtr<ID3D11Buffer> constantBuffer_;
  ComPtr<ID3D11RasterizerState> rasterizerState_;
  ComPtr<ID3D11BlendState> blendState_;

  // ─── State ────────────────────────────────────────────────────
  float transform_[16] = {};
  int width_ = 0, height_ = 0;
  bool initialized_ = false;

  // ─── Tessellation accumulator ─────────────────────────────────
  static constexpr size_t MAX_VERTICES = 524288;
  std::vector<StrokeVertex> accumulatedVerts_;
  std::vector<float> allPoints_;
  int totalAccumulatedPoints_ = 0;

  // 🚀 Multi-threaded tessellation + pooling
  TessellationThread<StrokeVertex> tessThread_;
  VertexBufferPool<StrokeVertex> vertexPool_;

  // ─── Performance tracking ─────────────────────────────────────
  std::vector<float> frameTimesUs_;
  uint32_t statsTotalFrames_ = 0;
  bool statsActive_ = false;
  std::chrono::steady_clock::time_point lastFrameTime_;
  bool hasLastFrameTime_ = false;

  // ─── 🚀 GPU Compute Tessellation ──────────────────────────────
  ComPtr<ID3D11ComputeShader> computeShader_;
  ComPtr<ID3D11Buffer> computePointsBuf_;
  ComPtr<ID3D11Buffer> computeParamsBuf_;
  ComPtr<ID3D11Buffer> computeVertexBuf_;
  ComPtr<ID3D11Buffer> computeCapBuf_;
  ComPtr<ID3D11Buffer> computeCapCounterBuf_;
  ComPtr<ID3D11ShaderResourceView> pointsSRV_;
  ComPtr<ID3D11UnorderedAccessView> vertexUAV_;
  ComPtr<ID3D11UnorderedAccessView> capUAV_;
  ComPtr<ID3D11UnorderedAccessView> capCounterUAV_;
  bool computeAvailable_ = false;
  int prevComputePointCount_ = 0;  // 🚀 Incremental compute tracking
  static constexpr int SUBS_PER_SEG = 8;
  int dynamicSubsPerSeg_ = 8;  // 🚀 Adaptive LOD: 4-16 based on zoom
  bool createComputePipeline();
  void destroyComputeResources();

  // ─── Init helpers ─────────────────────────────────────────────
  bool createDevice();
  bool createRenderTarget(int width, int height);
  bool createPipeline();
  bool createVertexBuffer();
  void destroyRenderTarget();
};
