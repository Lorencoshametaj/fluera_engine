// d3d11_stroke_renderer.cpp — D3D11 live stroke renderer implementation
#include "d3d11_stroke_renderer.h"

// ═══════════════════════════════════════════════════════════════════
// EMBEDDED HLSL SHADERS
// ═══════════════════════════════════════════════════════════════════

static const char* kVertexShaderHLSL = R"(
cbuffer Constants : register(b0) {
    float4x4 uMVP;
};
struct VSInput {
    float2 pos : POSITION;
    float4 col : COLOR;
};
struct VSOutput {
    float4 pos : SV_POSITION;
    float4 col : COLOR;
};
VSOutput main(VSInput input) {
    VSOutput output;
    output.pos = mul(uMVP, float4(input.pos, 0.0, 1.0));
    output.col = input.col;
    return output;
}
)";

static const char* kPixelShaderHLSL = R"(
struct PSInput {
    float4 pos : SV_POSITION;
    float4 col : COLOR;
};
float4 main(PSInput input) : SV_TARGET {
    return input.col;
}
)";

// ═══════════════════════════════════════════════════════════════════
// DESTRUCTOR
// ═══════════════════════════════════════════════════════════════════

D3D11StrokeRenderer::~D3D11StrokeRenderer() { destroy(); }

// ═══════════════════════════════════════════════════════════════════
// INIT
// ═══════════════════════════════════════════════════════════════════

bool D3D11StrokeRenderer::init(int width, int height) {
  if (initialized_) destroy();
  width_ = width;
  height_ = height;

  memset(transform_, 0, sizeof(transform_));
  transform_[0] = transform_[5] = transform_[10] = transform_[15] = 1.0f;

  if (!createDevice()) return false;
  if (!createRenderTarget(width, height)) return false;
  if (!createPipeline()) return false;
  if (!createVertexBuffer()) return false;

  accumulatedVerts_.reserve(8192);
  allPoints_.reserve(4096);
  frameTimesUs_.reserve(120);

  initialized_ = true;
  return true;
}

bool D3D11StrokeRenderer::createDevice() {
  D3D_FEATURE_LEVEL featureLevel = D3D_FEATURE_LEVEL_11_0;
  UINT flags = 0;
#ifdef _DEBUG
  flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif

  HRESULT hr = D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags,
      &featureLevel, 1, D3D11_SDK_VERSION,
      &device_, nullptr, &context_);
  if (FAILED(hr)) {
    // Fallback to WARP (software)
    hr = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags,
        &featureLevel, 1, D3D11_SDK_VERSION,
        &device_, nullptr, &context_);
  }
  return SUCCEEDED(hr);
}

bool D3D11StrokeRenderer::createRenderTarget(int w, int h) {
  // MSAA render target
  D3D11_TEXTURE2D_DESC msaaDesc = {};
  msaaDesc.Width = w;
  msaaDesc.Height = h;
  msaaDesc.MipLevels = 1;
  msaaDesc.ArraySize = 1;
  msaaDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  msaaDesc.SampleDesc.Count = msaaSampleCount_;
  msaaDesc.SampleDesc.Quality = 0;
  msaaDesc.Usage = D3D11_USAGE_DEFAULT;
  msaaDesc.BindFlags = D3D11_BIND_RENDER_TARGET;

  HRESULT hr = device_->CreateTexture2D(&msaaDesc, nullptr, &msaaTexture_);
  if (FAILED(hr)) return false;

  hr = device_->CreateRenderTargetView(msaaTexture_.Get(), nullptr, &msaaRTV_);
  if (FAILED(hr)) return false;

  // Resolve target (1x, shared with Flutter)
  D3D11_TEXTURE2D_DESC resolveDesc = {};
  resolveDesc.Width = w;
  resolveDesc.Height = h;
  resolveDesc.MipLevels = 1;
  resolveDesc.ArraySize = 1;
  resolveDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  resolveDesc.SampleDesc.Count = 1;
  resolveDesc.SampleDesc.Quality = 0;
  resolveDesc.Usage = D3D11_USAGE_DEFAULT;
  resolveDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  resolveDesc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

  hr = device_->CreateTexture2D(&resolveDesc, nullptr, &resolveTexture_);
  return SUCCEEDED(hr);
}

bool D3D11StrokeRenderer::createPipeline() {
  ComPtr<ID3DBlob> vsBlob, psBlob, errBlob;

  // Compile vertex shader
  HRESULT hr = D3DCompile(kVertexShaderHLSL, strlen(kVertexShaderHLSL),
      "VS", nullptr, nullptr, "main", "vs_5_0", 0, 0, &vsBlob, &errBlob);
  if (FAILED(hr)) return false;

  hr = device_->CreateVertexShader(vsBlob->GetBufferPointer(),
      vsBlob->GetBufferSize(), nullptr, &vertexShader_);
  if (FAILED(hr)) return false;

  // Compile pixel shader
  hr = D3DCompile(kPixelShaderHLSL, strlen(kPixelShaderHLSL),
      "PS", nullptr, nullptr, "main", "ps_5_0", 0, 0, &psBlob, &errBlob);
  if (FAILED(hr)) return false;

  hr = device_->CreatePixelShader(psBlob->GetBufferPointer(),
      psBlob->GetBufferSize(), nullptr, &pixelShader_);
  if (FAILED(hr)) return false;

  // Input layout: POSITION (float2) + COLOR (float4)
  D3D11_INPUT_ELEMENT_DESC layout[] = {
    {"POSITION", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0},
    {"COLOR", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 8, D3D11_INPUT_PER_VERTEX_DATA, 0},
  };
  hr = device_->CreateInputLayout(layout, 2, vsBlob->GetBufferPointer(),
      vsBlob->GetBufferSize(), &inputLayout_);
  if (FAILED(hr)) return false;

  // Constant buffer (4x4 matrix)
  D3D11_BUFFER_DESC cbDesc = {};
  cbDesc.ByteWidth = sizeof(float) * 16;
  cbDesc.Usage = D3D11_USAGE_DYNAMIC;
  cbDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
  cbDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

  hr = device_->CreateBuffer(&cbDesc, nullptr, &constantBuffer_);
  if (FAILED(hr)) return false;

  // Rasterizer state (no backface culling for 2D)
  D3D11_RASTERIZER_DESC rsDesc = {};
  rsDesc.FillMode = D3D11_FILL_SOLID;
  rsDesc.CullMode = D3D11_CULL_NONE;
  rsDesc.MultisampleEnable = TRUE;
  rsDesc.AntialiasedLineEnable = FALSE;

  hr = device_->CreateRasterizerState(&rsDesc, &rasterizerState_);
  if (FAILED(hr)) return false;

  // Blend state (premultiplied alpha)
  D3D11_BLEND_DESC blendDesc = {};
  blendDesc.RenderTarget[0].BlendEnable = TRUE;
  blendDesc.RenderTarget[0].SrcBlend = D3D11_BLEND_SRC_ALPHA;
  blendDesc.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
  blendDesc.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
  blendDesc.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
  blendDesc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
  blendDesc.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
  blendDesc.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;

  hr = device_->CreateBlendState(&blendDesc, &blendState_);
  return SUCCEEDED(hr);
}

bool D3D11StrokeRenderer::createVertexBuffer() {
  D3D11_BUFFER_DESC desc = {};
  desc.ByteWidth = static_cast<UINT>(MAX_VERTICES * sizeof(StrokeVertex));
  desc.Usage = D3D11_USAGE_DYNAMIC;
  desc.BindFlags = D3D11_BIND_VERTEX_BUFFER;
  desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

  return SUCCEEDED(device_->CreateBuffer(&desc, nullptr, &vertexBuffer_));
}

// ═══════════════════════════════════════════════════════════════════
// UPDATE AND RENDER
// ═══════════════════════════════════════════════════════════════════

void D3D11StrokeRenderer::updateAndRender(
    const float *points, int pointCount, float r, float g, float b, float a,
    float strokeWidth, int totalPoints, int brushType,
    float pencilBaseOpacity, float pencilMaxOpacity,
    float pencilMinPressure, float pencilMaxPressure,
    float fountainThinning, float fountainNibAngleDeg,
    float fountainNibStrength, float fountainPressureRate,
    int fountainTaperEntry) {

  if (!initialized_ || pointCount < 2) return;

  auto frameStart = std::chrono::steady_clock::now();

  // ── Tessellation (uses shared stroke_tessellation.h) ──────────
  if (brushType == 0) {
    // Incremental (ballpoint)
    int startIdx = totalAccumulatedPoints_;
    totalAccumulatedPoints_ += pointCount;
    int adjustedStart = startIdx > 0 ? startIdx - 1 : 0;
    stroke::tessellateStroke(points, pointCount, r, g, b, a, strokeWidth,
                             adjustedStart, totalPoints, accumulatedVerts_,
                             pencilMinPressure, pencilMaxPressure);
  } else {
    // Full retessellation
    accumulatedVerts_.clear();
    totalAccumulatedPoints_ = pointCount;

    if (brushType == 1) {
      stroke::tessellateMarker(points, pointCount, r, g, b, a, strokeWidth,
                               accumulatedVerts_);
    } else if (brushType == 3) {
      stroke::tessellateTechnicalPen(points, pointCount, r, g, b, a,
                                     strokeWidth, accumulatedVerts_);
    } else if (brushType == 4) {
      float nibRad = fountainNibAngleDeg * 3.14159265f / 180.0f;
      stroke::tessellateFountainPen(points, pointCount, r, g, b, a,
                                    strokeWidth, pointCount, accumulatedVerts_,
                                    fountainThinning, nibRad, fountainNibStrength,
                                    fountainPressureRate, fountainTaperEntry);
    } else {
      // brushType == 2 (pencil)
      stroke::tessellatePencil(points, pointCount, r, g, b, a, strokeWidth,
                               0, pointCount, accumulatedVerts_,
                               pencilBaseOpacity, pencilMaxOpacity,
                               pencilMinPressure, pencilMaxPressure);
    }
  }

  if (accumulatedVerts_.empty() || accumulatedVerts_.size() > MAX_VERTICES) return;

  // ── Upload vertices ───────────────────────────────────────────
  D3D11_MAPPED_SUBRESOURCE mapped;
  HRESULT hr = context_->Map(vertexBuffer_.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
  if (FAILED(hr)) return;
  memcpy(mapped.pData, accumulatedVerts_.data(),
         accumulatedVerts_.size() * sizeof(StrokeVertex));
  context_->Unmap(vertexBuffer_.Get(), 0);

  // ── Update constant buffer (transform matrix) ─────────────────
  hr = context_->Map(constantBuffer_.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
  if (FAILED(hr)) return;
  memcpy(mapped.pData, transform_, sizeof(transform_));
  context_->Unmap(constantBuffer_.Get(), 0);

  // ── Draw ──────────────────────────────────────────────────────
  context_->OMSetRenderTargets(1, msaaRTV_.GetAddressOf(), nullptr);

  D3D11_VIEWPORT vp = {};
  vp.Width = static_cast<float>(width_);
  vp.Height = static_cast<float>(height_);
  vp.MaxDepth = 1.0f;
  context_->RSSetViewports(1, &vp);
  context_->RSSetState(rasterizerState_.Get());

  float blendFactor[4] = {0, 0, 0, 0};
  context_->OMSetBlendState(blendState_.Get(), blendFactor, 0xFFFFFFFF);

  context_->IASetInputLayout(inputLayout_.Get());
  UINT stride = sizeof(StrokeVertex), offset = 0;
  context_->IASetVertexBuffers(0, 1, vertexBuffer_.GetAddressOf(), &stride, &offset);
  context_->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

  context_->VSSetShader(vertexShader_.Get(), nullptr, 0);
  context_->VSSetConstantBuffers(0, 1, constantBuffer_.GetAddressOf());
  context_->PSSetShader(pixelShader_.Get(), nullptr, 0);

  context_->Draw(static_cast<UINT>(accumulatedVerts_.size()), 0);

  // ── Resolve MSAA → output texture ─────────────────────────────
  context_->ResolveSubresource(resolveTexture_.Get(), 0, msaaTexture_.Get(), 0,
                               DXGI_FORMAT_R8G8B8A8_UNORM);
  context_->Flush();

  // ── Performance stats ─────────────────────────────────────────
  statsActive_ = true;
  statsTotalFrames_++;
  auto frameEnd = std::chrono::steady_clock::now();
  float us = std::chrono::duration<float, std::micro>(frameEnd - frameStart).count();
  frameTimesUs_.push_back(us);
  if (frameTimesUs_.size() > 120) frameTimesUs_.erase(frameTimesUs_.begin());
}

// ═══════════════════════════════════════════════════════════════════
// SET TRANSFORM / CLEAR / RESIZE / DESTROY
// ═══════════════════════════════════════════════════════════════════

void D3D11StrokeRenderer::setTransform(const float *matrix4x4) {
  memcpy(transform_, matrix4x4, sizeof(float) * 16);
}

void D3D11StrokeRenderer::clearFrame() {
  if (!initialized_) return;
  accumulatedVerts_.clear();
  allPoints_.clear();
  totalAccumulatedPoints_ = 0;
  statsActive_ = false;

  // Clear MSAA target to transparent
  float clearColor[4] = {0, 0, 0, 0};
  context_->ClearRenderTargetView(msaaRTV_.Get(), clearColor);

  // Resolve cleared target to output
  context_->ResolveSubresource(resolveTexture_.Get(), 0, msaaTexture_.Get(), 0,
                               DXGI_FORMAT_R8G8B8A8_UNORM);
  context_->Flush();
}

void D3D11StrokeRenderer::destroyRenderTarget() {
  msaaRTV_.Reset();
  msaaTexture_.Reset();
  resolveTexture_.Reset();
}

bool D3D11StrokeRenderer::resize(int width, int height) {
  if (!initialized_) return false;
  destroyRenderTarget();
  width_ = width;
  height_ = height;
  return createRenderTarget(width, height);
}

void D3D11StrokeRenderer::destroy() {
  initialized_ = false;
  accumulatedVerts_.clear();
  allPoints_.clear();

  vertexBuffer_.Reset();
  constantBuffer_.Reset();
  blendState_.Reset();
  rasterizerState_.Reset();
  inputLayout_.Reset();
  pixelShader_.Reset();
  vertexShader_.Reset();
  destroyRenderTarget();
  context_.Reset();
  device_.Reset();
}

D3D11StrokeStats D3D11StrokeRenderer::getStats() const {
  D3D11StrokeStats stats = {};
  stats.vertexCount = static_cast<uint32_t>(accumulatedVerts_.size());
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
