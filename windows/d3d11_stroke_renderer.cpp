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

  // 🚀 Start background tessellation worker
  tessThread_.start();

  // 🚀 Try to create compute pipeline (CS 5.0)
  createComputePipeline();

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
  // 🚀 Acquire pre-reserved vertex vector from pool (zero alloc hot path)
  int poolSlot;
  auto& verts = vertexPool_.acquire(poolSlot);

  if (brushType == 0) {
    // ── FULL RETESSELLATION (ballpoint) ──────────────────────────
    // FFI / MethodChannel sends ALL accumulated points each frame.
    // Tessellate directly — no internal accumulation.
    totalAccumulatedPoints_ = pointCount;
    accumulatedVerts_.clear();

    if (pointCount >= 2) {
      stroke::tessellateStroke(points, pointCount, r, g, b, a, strokeWidth,
                               0, totalPoints, verts,
                               pencilMinPressure, pencilMaxPressure);
    }

    accumulatedVerts_.assign(verts.begin(), verts.end());
    vertexPool_.release(poolSlot);
  } else {
    // 🚀 Non-ballpoint: use GPU compute if available, else background thread
    accumulatedVerts_.clear();
    totalAccumulatedPoints_ = pointCount;

    bool useCompute = computeAvailable_ && computeShader_ && brushType != 0;
    if (useCompute) {
      int subsPerSeg = dynamicSubsPerSeg_;  // 🚀 Adaptive LOD
      int startSeg = 0;
      if (prevComputePointCount_ >= 2 && pointCount > prevComputePointCount_) {
        startSeg = std::max(0, prevComputePointCount_ - 2);
      }
      int newSubdivs = (pointCount - 1 - startSeg) * subsPerSeg;
      int totalSubdivs = (pointCount - 1) * subsPerSeg;
      int vertexOffset = startSeg * subsPerSeg;

      // Upload points to SRV buffer
      D3D11_MAPPED_SUBRESOURCE mappedPts;
      HRESULT hr = context_->Map(computePointsBuf_.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &mappedPts);
      if (SUCCEEDED(hr)) {
        memcpy(mappedPts.pData, points, pointCount * 5 * sizeof(float));
        context_->Unmap(computePointsBuf_.Get(), 0);
      }

      // Upload params to cbuffer (with incremental fields)
      D3D11_MAPPED_SUBRESOURCE mappedParams;
      hr = context_->Map(computeParamsBuf_.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &mappedParams);
      if (SUCCEEDED(hr)) {
        struct { float cR,cG,cB,cA,sw; int pc,bt; float mnP,mxP,pBO,pMO; int sps,td; float fThin,fNibR,fNibS; int sSeg,vOff; } params;
        params.cR = r; params.cG = g; params.cB = b; params.cA = a;
        params.sw = strokeWidth; params.pc = pointCount; params.bt = brushType;
        params.mnP = pencilMinPressure; params.mxP = pencilMaxPressure;
        params.pBO = pencilBaseOpacity; params.pMO = pencilMaxOpacity;
        params.sps = subsPerSeg; params.td = newSubdivs;  // Only new portion!
        params.fThin = fountainThinning;
        params.fNibR = fountainNibAngleDeg * 3.14159265f / 180.0f;
        params.fNibS = fountainNibStrength;
        params.sSeg = startSeg;
        params.vOff = vertexOffset;
        memcpy(mappedParams.pData, &params, sizeof(params));
        context_->Unmap(computeParamsBuf_.Get(), 0);
      }

      // Dispatch compute (only new subdivisions)
      context_->CSSetShader(computeShader_.Get(), nullptr, 0);
      context_->CSSetShaderResources(0, 1, pointsSRV_.GetAddressOf());
      context_->CSSetUnorderedAccessViews(0, 1, vertexUAV_.GetAddressOf(), nullptr);
      context_->CSSetConstantBuffers(0, 1, computeParamsBuf_.GetAddressOf());
      UINT groups = (newSubdivs + 63) / 64;
      context_->Dispatch(groups, 1, 1);

      prevComputePointCount_ = pointCount;

      // Unbind UAV before vertex read
      ID3D11UnorderedAccessView* nullUAV = nullptr;
      context_->CSSetUnorderedAccessViews(0, 1, &nullUAV, nullptr);

      // Copy compute output to vertex buffer
      // computeVertexBuf_ has the tessellated data as raw floats (6 per vertex)
      // We need to copy totalSubdivs * 6 * 6 * sizeof(float) bytes
      int computeVertexCount = totalSubdivs * 6;
      size_t computeBytes = computeVertexCount * 6 * sizeof(float);
      D3D11_BOX srcBox = {};
      srcBox.right = static_cast<UINT>(computeBytes);
      srcBox.bottom = 1;
      srcBox.back = 1;
      context_->CopySubresourceRegion(vertexBuffer_.Get(), 0, 0, 0, 0,
                                       computeVertexBuf_.Get(), 0, &srcBox);

      // Set vertex count for draw
      accumulatedVerts_.resize(computeVertexCount); // Just for count tracking
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

  // 🚀 Check for background tessellation results
  if (tessThread_.trySwap()) {
    auto& front = tessThread_.frontVertices();
    accumulatedVerts_.assign(front.begin(), front.end());
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
  vertexPool_.releaseAll();

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
  tessThread_.stop();
  initialized_ = false;
  accumulatedVerts_.clear();
  allPoints_.clear();
  vertexPool_.releaseAll();

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

// 🚀 Memory pressure management
void D3D11StrokeRenderer::trimMemory(int level) {
  if (level >= 1) {
    vertexPool_.trim();
  }
  if (level >= 2) {
    vertexPool_.releaseAll();
    vertexPool_.trim();
    allPoints_.clear();
    allPoints_.shrink_to_fit();
    accumulatedVerts_.clear();
    accumulatedVerts_.shrink_to_fit();
  }
}

// 🚀 Adaptive LOD
void D3D11StrokeRenderer::setZoomLevel(float zoom) {
  int prev = dynamicSubsPerSeg_;
  if (zoom < 0.3f) dynamicSubsPerSeg_ = 4;
  else if (zoom < 0.6f) dynamicSubsPerSeg_ = 6;
  else if (zoom > 4.0f) dynamicSubsPerSeg_ = 16;
  else if (zoom > 2.0f) dynamicSubsPerSeg_ = 12;
  else dynamicSubsPerSeg_ = 8;
  if (dynamicSubsPerSeg_ != prev) {
    char msg[128];
    snprintf(msg, sizeof(msg), "D3D11: LOD zoom=%.2f subsPerSeg=%d->%d\n", zoom, prev, dynamicSubsPerSeg_);
    OutputDebugStringA(msg);
  }
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

// ═══════════════════════════════════════════════════════════════════
// 🚀 D3D11 COMPUTE TESSELLATION (CS 5.0)
// ═══════════════════════════════════════════════════════════════════

// Embedded HLSL compute shader — same as shaders/stroke_compute.hlsl
static const char* kComputeShaderHLSL = R"(
cbuffer Params : register(b0) {
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

StructuredBuffer<float>   points : register(t0);
RWStructuredBuffer<float> verts  : register(u0);

float2 catmullRom(float2 p0, float2 p1, float2 p2, float2 p3, float t) {
  float t2=t*t, t3=t2*t;
  return 0.5*((2.0*p1)+(-p0+p2)*t+(2.0*p0-5.0*p1+4.0*p2-p3)*t2+(-p0+3.0*p1-3.0*p2+p3)*t3);
}

float2 catmullRomTangent(float2 p0, float2 p1, float2 p2, float2 p3, float t) {
  float t2=t*t;
  return 0.5*((-p0+p2)+(4.0*p0-10.0*p1+8.0*p2-2.0*p3)*t+(-3.0*p0+9.0*p1-9.0*p2+3.0*p3)*t2);
}

float computeHalfWidth(int bt, float sw, float p, int gi, int N, float mnP, float mxP, float2 dir, float nibR, float nibS, float thin) {
  if(bt==0) return sw*(mnP+0.5*(mxP-mnP))*0.5;
  if(bt==1) return sw*2.5*0.5;
  if(bt==2){float hw=sw*0.5*(mnP+p*(mxP-mnP));if(gi<4){float t=float(gi)/4.0;hw*=0.15+t*(2.0-t)*0.85;}return hw;}
  if(bt==4){float hw=sw*0.5*(0.4+p*0.6*(1.0-thin));float da=abs(atan2(dir.y,dir.x)-nibR);float cn=abs(sin(da));hw*=(0.4+lerp(1.0,cn,nibS)*0.6);if(gi<6){float t=float(gi)/6.0;hw*=0.2+t*0.8;}return hw;}
  return sw*0.5;
}

float computeAlpha(int bt, float base, float p, float pbo, float pmo) {
  if(bt==2) return base*(pbo+(pmo-pbo)*p);
  return base;
}

[numthreads(64,1,1)]
void CSMain(uint3 dtid : SV_DispatchThreadID) {
  int gid=int(dtid.x); if(gid>=totalSubdivs) return;
  int localSeg=gid/subsPerSeg, sub=gid%subsPerSeg;
  int seg=localSeg+startSeg;
  int N=pointCount;
  if(seg>=N-1) return;

  int i0=max(seg-1,0),i1=seg,i2=seg+1,i3=min(seg+2,N-1);
  float2 p0=float2(points[i0*5],points[i0*5+1]);
  float2 p1=float2(points[i1*5],points[i1*5+1]);
  float2 p2=float2(points[i2*5],points[i2*5+1]);
  float2 p3=float2(points[i3*5],points[i3*5+1]);

  float t=float(sub)/float(subsPerSeg);
  float2 pos=catmullRom(p0,p1,p2,p3,t);
  float2 tn=catmullRomTangent(p0,p1,p2,p3,t);
  float tl=length(tn); if(tl<0.0001) tn=float2(1,0); else tn/=tl;

  float2 posN,tanN;
  if(sub<subsPerSeg-1){float tN=float(sub+1)/float(subsPerSeg);posN=catmullRom(p0,p1,p2,p3,tN);tanN=catmullRomTangent(p0,p1,p2,p3,tN);}
  else if(seg+1<N-1){int j0=max(seg,0),j1=seg+1,j2=min(seg+2,N-1),j3=min(seg+3,N-1);
    posN=catmullRom(float2(points[j0*5],points[j0*5+1]),float2(points[j1*5],points[j1*5+1]),float2(points[j2*5],points[j2*5+1]),float2(points[j3*5],points[j3*5+1]),0.0);
    tanN=catmullRomTangent(float2(points[j0*5],points[j0*5+1]),float2(points[j1*5],points[j1*5+1]),float2(points[j2*5],points[j2*5+1]),float2(points[j3*5],points[j3*5+1]),0.0);
  }else{posN=p2;tanN=p2-p1;}
  float tnl=length(tanN); if(tnl<0.0001) tanN=float2(1,0); else tanN/=tnl;

  float2 perp=float2(-tn.y,tn.x), perpN=float2(-tanN.y,tanN.x);
  float pr=lerp(points[i1*5+2],points[i2*5+2],t);
  float prN=lerp(points[i1*5+2],points[i2*5+2],sub<subsPerSeg-1?float(sub+1)/float(subsPerSeg):1.0);
  float hw=computeHalfWidth(brushType,strokeWidth,pr,seg,N,minPressure,maxPressure,tn,fountainNibAngleRad,fountainNibStrength,fountainThinning);
  float hwN=computeHalfWidth(brushType,strokeWidth,prN,seg+(sub==subsPerSeg-1?1:0),N,minPressure,maxPressure,tanN,fountainNibAngleRad,fountainNibStrength,fountainThinning);
  float al=computeAlpha(brushType,colorA,pr,pencilBaseOpacity,pencilMaxOpacity);
  float alN=computeAlpha(brushType,colorA,prN,pencilBaseOpacity,pencilMaxOpacity);

  float2 L=pos+perp*hw,R=pos-perp*hw,LN=posN+perpN*hwN,RN=posN-perpN*hwN;
  int ob=(gid+vertexOffset)*36;
  verts[ob]=L.x;verts[ob+1]=L.y;verts[ob+2]=colorR;verts[ob+3]=colorG;verts[ob+4]=colorB;verts[ob+5]=al;
  verts[ob+6]=R.x;verts[ob+7]=R.y;verts[ob+8]=colorR;verts[ob+9]=colorG;verts[ob+10]=colorB;verts[ob+11]=al;
  verts[ob+12]=LN.x;verts[ob+13]=LN.y;verts[ob+14]=colorR;verts[ob+15]=colorG;verts[ob+16]=colorB;verts[ob+17]=alN;
  verts[ob+18]=R.x;verts[ob+19]=R.y;verts[ob+20]=colorR;verts[ob+21]=colorG;verts[ob+22]=colorB;verts[ob+23]=al;
  verts[ob+24]=LN.x;verts[ob+25]=LN.y;verts[ob+26]=colorR;verts[ob+27]=colorG;verts[ob+28]=colorB;verts[ob+29]=alN;
  verts[ob+30]=RN.x;verts[ob+31]=RN.y;verts[ob+32]=colorR;verts[ob+33]=colorG;verts[ob+34]=colorB;verts[ob+35]=alN;
}
)";

bool D3D11StrokeRenderer::createComputePipeline() {
  if (!device_) return false;

  // Compile HLSL compute shader at runtime
  ComPtr<ID3DBlob> csBlob, errBlob;
  HRESULT hr = D3DCompile(kComputeShaderHLSL, strlen(kComputeShaderHLSL),
      "CS", nullptr, nullptr, "CSMain", "cs_5_0", 0, 0, &csBlob, &errBlob);
  if (FAILED(hr)) {
    if (errBlob) {
      OutputDebugStringA((char*)errBlob->GetBufferPointer());
    }
    return false;
  }

  hr = device_->CreateComputeShader(csBlob->GetBufferPointer(),
      csBlob->GetBufferSize(), nullptr, &computeShader_);
  if (FAILED(hr)) return false;

  // ── Points buffer (SRV — structured, read-only) ──────────────
  static constexpr UINT MAX_POINTS = 5000;
  {
    D3D11_BUFFER_DESC desc = {};
    desc.ByteWidth = MAX_POINTS * 5 * sizeof(float);
    desc.Usage = D3D11_USAGE_DYNAMIC;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    desc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    desc.StructureByteStride = sizeof(float);
    hr = device_->CreateBuffer(&desc, nullptr, &computePointsBuf_);
    if (FAILED(hr)) return false;

    D3D11_SHADER_RESOURCE_VIEW_DESC srvDesc = {};
    srvDesc.ViewDimension = D3D11_SRV_DIMENSION_BUFFER;
    srvDesc.Buffer.NumElements = MAX_POINTS * 5;
    hr = device_->CreateShaderResourceView(computePointsBuf_.Get(), &srvDesc, &pointsSRV_);
    if (FAILED(hr)) return false;
  }

  // ── Vertex output buffer (UAV — structured, read-write) ──────
  {
    static constexpr UINT MAX_VERTS_FLOATS = MAX_POINTS * SUBS_PER_SEG * 36;
    D3D11_BUFFER_DESC desc = {};
    desc.ByteWidth = MAX_VERTS_FLOATS * sizeof(float);
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
    desc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    desc.StructureByteStride = sizeof(float);
    hr = device_->CreateBuffer(&desc, nullptr, &computeVertexBuf_);
    if (FAILED(hr)) return false;

    D3D11_UNORDERED_ACCESS_VIEW_DESC uavDesc = {};
    uavDesc.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
    uavDesc.Buffer.NumElements = MAX_VERTS_FLOATS;
    hr = device_->CreateUnorderedAccessView(computeVertexBuf_.Get(), &uavDesc, &vertexUAV_);
    if (FAILED(hr)) return false;
  }

  // ── Params constant buffer (cbuffer, 16-byte aligned) ────────
  {
    D3D11_BUFFER_DESC desc = {};
    desc.ByteWidth = 64; // 14 members padded to 16-byte boundary
    desc.Usage = D3D11_USAGE_DYNAMIC;
    desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    hr = device_->CreateBuffer(&desc, nullptr, &computeParamsBuf_);
    if (FAILED(hr)) return false;
  }

  computeAvailable_ = true;
  OutputDebugStringA("D3D11StrokeRenderer: 🚀 Compute tessellation ready (CS 5.0)\n");

  // 🔥 Warm-up: dispatch 1-threadgroup dummy compute to pre-compile shader
  {
    float dummyPoints[10] = {0,0,1,0,0, 1,1,1,0,0};
    D3D11_MAPPED_SUBRESOURCE mapped;
    if (SUCCEEDED(context_->Map(computePointsBuf_.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
      memcpy(mapped.pData, dummyPoints, sizeof(dummyPoints));
      context_->Unmap(computePointsBuf_.Get(), 0);
    }
    struct { float cr,cg,cb,ca,sw; int pc,bt; float mnP,mxP,pBO,pMO; int sps,td; float fThin,fNibR,fNibS,fRate; int fTaper,ss,vo; } params = {};
    params.ca = 1.0f; params.sw = 1.0f; params.pc = 2; params.bt = 1;
    params.sps = 8; params.td = 8;
    if (SUCCEEDED(context_->Map(computeParamsBuf_.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
      memcpy(mapped.pData, &params, sizeof(params));
      context_->Unmap(computeParamsBuf_.Get(), 0);
    }
    context_->CSSetShader(computeShader_.Get(), nullptr, 0);
    context_->CSSetShaderResources(0, 1, pointsSRV_.GetAddressOf());
    UINT initCount = 0;
    context_->CSSetUnorderedAccessViews(0, 1, vertexUAV_.GetAddressOf(), nullptr);
    context_->Dispatch(1, 1, 1);
    context_->CSSetShader(nullptr, nullptr, 0);
    OutputDebugStringA("D3D11StrokeRenderer: 🔥 Shader warm-up complete\n");
  }

  return true;
}

void D3D11StrokeRenderer::destroyComputeResources() {
  computeShader_.Reset();
  computePointsBuf_.Reset();
  computeParamsBuf_.Reset();
  computeVertexBuf_.Reset();
  computeCapBuf_.Reset();
  computeCapCounterBuf_.Reset();
  pointsSRV_.Reset();
  vertexUAV_.Reset();
  capUAV_.Reset();
  capCounterUAV_.Reset();
  computeAvailable_ = false;
}

