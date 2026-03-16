// d3d11_stroke_overlay_plugin.cpp — Flutter Windows plugin implementation
#include "d3d11_stroke_overlay_plugin.h"

#include <flutter/encodable_value.h>

#include <string>
#include <variant>
#include <vector>

using flutter::EncodableMap;
using flutter::EncodableValue;

// ═══════════════════════════════════════════════════════════════════
// REGISTRATION
// ═══════════════════════════════════════════════════════════════════

void D3D11StrokeOverlayPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<D3D11StrokeOverlayPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

D3D11StrokeOverlayPlugin::D3D11StrokeOverlayPlugin(
    flutter::PluginRegistrarWindows *registrar)
    : textureRegistrar_(registrar->texture_registrar()) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "fluera_engine/vulkan_stroke",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue> &call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });
}

D3D11StrokeOverlayPlugin::~D3D11StrokeOverlayPlugin() {
  if (textureId_ >= 0 && textureRegistrar_) {
    textureRegistrar_->UnregisterTexture(textureId_);
  }
  renderer_.reset();
}

// ═══════════════════════════════════════════════════════════════════
// HELPER: safely get values from EncodableMap
// ═══════════════════════════════════════════════════════════════════

static double getDouble(const EncodableMap &m, const std::string &key, double def = 0.0) {
  auto it = m.find(EncodableValue(key));
  if (it == m.end()) return def;
  if (auto *v = std::get_if<double>(&it->second)) return *v;
  if (auto *v = std::get_if<int32_t>(&it->second)) return static_cast<double>(*v);
  if (auto *v = std::get_if<int64_t>(&it->second)) return static_cast<double>(*v);
  return def;
}

static int64_t getInt(const EncodableMap &m, const std::string &key, int64_t def = 0) {
  auto it = m.find(EncodableValue(key));
  if (it == m.end()) return def;
  if (auto *v = std::get_if<int32_t>(&it->second)) return *v;
  if (auto *v = std::get_if<int64_t>(&it->second)) return *v;
  if (auto *v = std::get_if<double>(&it->second)) return static_cast<int64_t>(*v);
  return def;
}

// ═══════════════════════════════════════════════════════════════════
// METHOD CALL HANDLER
// ═══════════════════════════════════════════════════════════════════

void D3D11StrokeOverlayPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue> &call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {

  const auto &method = call.method_name();

  // ── isAvailable ───────────────────────────────────────────────
  if (method == "isAvailable") {
    result->Success(EncodableValue(true));
    return;
  }

  // ── init ──────────────────────────────────────────────────────
  if (method == "init") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    if (!args) { result->Success(EncodableValue()); return; }

    int w = static_cast<int>(getInt(*args, "width", 1920));
    int h = static_cast<int>(getInt(*args, "height", 1080));

    renderer_ = std::make_unique<D3D11StrokeRenderer>();
    if (!renderer_->init(w, h)) {
      renderer_.reset();
      result->Success(EncodableValue());
      return;
    }

    // Register GPU surface texture with Flutter
    auto surfaceDescriptor = std::make_unique<FlutterDesktopGpuSurfaceDescriptor>();
    texture_ = std::make_unique<flutter::TextureVariant>(
        flutter::GpuSurfaceTexture(
            kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
            [this](size_t w, size_t h) -> const FlutterDesktopGpuSurfaceDescriptor* {
              if (!renderer_ || !renderer_->isInitialized()) return nullptr;
              static FlutterDesktopGpuSurfaceDescriptor desc = {};
              auto *tex = renderer_->getOutputTexture();
              if (!tex) return nullptr;

              // Get DXGI shared handle
              ComPtr<IDXGIResource> dxgiRes;
              tex->QueryInterface(IID_PPV_ARGS(&dxgiRes));
              HANDLE sharedHandle = nullptr;
              if (dxgiRes) dxgiRes->GetSharedHandle(&sharedHandle);

              desc.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
              desc.handle = sharedHandle;
              desc.width = desc.visible_width = static_cast<size_t>(renderer_ ? w : 0);
              desc.height = desc.visible_height = static_cast<size_t>(renderer_ ? h : 0);
              desc.format = kFlutterDesktopPixelFormatRGBA8888;
              desc.release_callback = nullptr;
              return &desc;
            }));

    textureId_ = textureRegistrar_->RegisterTexture(texture_.get());
    result->Success(EncodableValue(textureId_));
    return;
  }

  // ── updateAndRender ───────────────────────────────────────────
  if (method == "updateAndRender") {
    if (!renderer_) { result->Success(EncodableValue()); return; }
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    if (!args) { result->Success(EncodableValue()); return; }

    // Extract points list
    auto ptIt = args->find(EncodableValue("points"));
    if (ptIt == args->end()) { result->Success(EncodableValue()); return; }
    const auto *ptList = std::get_if<std::vector<EncodableValue>>(&ptIt->second);
    if (!ptList || ptList->size() < 10) { result->Success(EncodableValue()); return; }

    // Convert to float array
    std::vector<float> floatPoints(ptList->size());
    for (size_t i = 0; i < ptList->size(); i++) {
      if (auto *v = std::get_if<double>(&(*ptList)[i])) floatPoints[i] = static_cast<float>(*v);
    }

    int64_t color = getInt(*args, "color", 0xFF000000);
    float a_ = static_cast<float>((color >> 24) & 0xFF) / 255.0f;
    float r_ = static_cast<float>((color >> 16) & 0xFF) / 255.0f;
    float g_ = static_cast<float>((color >> 8) & 0xFF) / 255.0f;
    float b_ = static_cast<float>(color & 0xFF) / 255.0f;

    renderer_->updateAndRender(
        floatPoints.data(), static_cast<int>(floatPoints.size() / 5),
        r_, g_, b_, a_,
        static_cast<float>(getDouble(*args, "width", 2.0)),
        static_cast<int>(getInt(*args, "totalPoints", 0)),
        static_cast<int>(getInt(*args, "brushType", 0)),
        static_cast<float>(getDouble(*args, "pencilBaseOpacity", 0.4)),
        static_cast<float>(getDouble(*args, "pencilMaxOpacity", 0.8)),
        static_cast<float>(getDouble(*args, "pencilMinPressure", 0.5)),
        static_cast<float>(getDouble(*args, "pencilMaxPressure", 1.2)),
        static_cast<float>(getDouble(*args, "fountainThinning", 0.5)),
        static_cast<float>(getDouble(*args, "fountainNibAngleDeg", 30.0)),
        static_cast<float>(getDouble(*args, "fountainNibStrength", 0.35)),
        static_cast<float>(getDouble(*args, "fountainPressureRate", 0.275)),
        static_cast<int>(getInt(*args, "fountainTaperEntry", 6)));

    textureRegistrar_->MarkTextureFrameAvailable(textureId_);
    result->Success(EncodableValue());
    return;
  }

  // ── setTransform ──────────────────────────────────────────────
  if (method == "setTransform") {
    if (!renderer_) { result->Success(EncodableValue()); return; }
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    if (!args) { result->Success(EncodableValue()); return; }

    auto mIt = args->find(EncodableValue("matrix"));
    if (mIt == args->end()) { result->Success(EncodableValue()); return; }
    const auto *mList = std::get_if<std::vector<EncodableValue>>(&mIt->second);
    if (!mList || mList->size() < 16) { result->Success(EncodableValue()); return; }

    float matrix[16];
    for (int i = 0; i < 16; i++) {
      if (auto *v = std::get_if<double>(&(*mList)[i])) matrix[i] = static_cast<float>(*v);
    }
    renderer_->setTransform(matrix);
    result->Success(EncodableValue());
    return;
  }

  // ── clear ─────────────────────────────────────────────────────
  if (method == "clear") {
    if (renderer_) {
      renderer_->clearFrame();
      textureRegistrar_->MarkTextureFrameAvailable(textureId_);
    }
    result->Success(EncodableValue());
    return;
  }

  // ── resize ────────────────────────────────────────────────────
  if (method == "resize") {
    if (!renderer_) { result->Success(EncodableValue()); return; }
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    if (!args) { result->Success(EncodableValue()); return; }
    int w = static_cast<int>(getInt(*args, "width", 1920));
    int h = static_cast<int>(getInt(*args, "height", 1080));
    renderer_->resize(w, h);
    result->Success(EncodableValue());
    return;
  }

  // ── destroy ───────────────────────────────────────────────────
  if (method == "destroy") {
    if (textureId_ >= 0 && textureRegistrar_) {
      textureRegistrar_->UnregisterTexture(textureId_);
      textureId_ = -1;
    }
    renderer_.reset();
    texture_.reset();
    result->Success(EncodableValue());
    return;
  }

  // ── getStats ──────────────────────────────────────────────────
  if (method == "getStats") {
    if (!renderer_) { result->Success(EncodableValue()); return; }
    auto stats = renderer_->getStats();
    EncodableMap map;
    map[EncodableValue("frameTimeP50Us")] = EncodableValue(static_cast<double>(stats.frameTimeP50Us));
    map[EncodableValue("frameTimeP90Us")] = EncodableValue(static_cast<double>(stats.frameTimeP90Us));
    map[EncodableValue("frameTimeP99Us")] = EncodableValue(static_cast<double>(stats.frameTimeP99Us));
    map[EncodableValue("vertexCount")] = EncodableValue(static_cast<int64_t>(stats.vertexCount));
    map[EncodableValue("totalFrames")] = EncodableValue(static_cast<int64_t>(stats.totalFrames));
    map[EncodableValue("active")] = EncodableValue(stats.active);
    map[EncodableValue("deviceName")] = EncodableValue(std::string("D3D11"));
    map[EncodableValue("apiVersionMajor")] = EncodableValue(11);
    map[EncodableValue("apiVersionMinor")] = EncodableValue(0);
    map[EncodableValue("apiVersionPatch")] = EncodableValue(0);
    result->Success(EncodableValue(map));
    return;
  }

  result->NotImplemented();
}

// ═══════════════════════════════════════════════════════════════════
// 🚀 FFI EXPORT — Direct Dart→C++ hot path (replaces MethodChannel)
// ═══════════════════════════════════════════════════════════════════

#define FLUERA_FFI_CMD           0
#define FLUERA_FFI_POINT_COUNT   1
#define FLUERA_FFI_COLOR_R       2
#define FLUERA_FFI_COLOR_G       3
#define FLUERA_FFI_COLOR_B       4
#define FLUERA_FFI_COLOR_A       5
#define FLUERA_FFI_STROKE_WIDTH  6
#define FLUERA_FFI_TOTAL_POINTS  7
#define FLUERA_FFI_BRUSH_TYPE    8
#define FLUERA_FFI_PENCIL_BASE   9
#define FLUERA_FFI_PENCIL_MAX    10
#define FLUERA_FFI_PENCIL_MIN_P  11
#define FLUERA_FFI_PENCIL_MAX_P  12
#define FLUERA_FFI_FOUNTAIN_THIN 13
#define FLUERA_FFI_FOUNTAIN_ANGLE 14
#define FLUERA_FFI_FOUNTAIN_STR  15
#define FLUERA_FFI_FOUNTAIN_RATE 16
#define FLUERA_FFI_FOUNTAIN_TAPER 17
#define FLUERA_FFI_TRANSFORM     20
#define FLUERA_FFI_POINTS        36
#define FLUERA_CMD_UPDATE_AND_RENDER  1.0f
#define FLUERA_CMD_SET_TRANSFORM     2.0f
#define FLUERA_CMD_CLEAR             3.0f

static D3D11StrokeOverlayPlugin *g_d3d_plugin = nullptr;

extern "C" {

__declspec(dllexport)
void fluera_stroke_execute(float* buf) {
  if (!buf || !g_d3d_plugin) return;

  auto *renderer = g_d3d_plugin->renderer_.get();
  if (!renderer || !renderer->isInitialized()) return;

  const float cmd = buf[FLUERA_FFI_CMD];

  if (cmd == FLUERA_CMD_CLEAR) {
    renderer->clearFrame();
    if (g_d3d_plugin->textureRegistrar_ && g_d3d_plugin->textureId_ >= 0) {
      g_d3d_plugin->textureRegistrar_->MarkTextureFrameAvailable(g_d3d_plugin->textureId_);
    }
    return;
  }

  if (cmd == FLUERA_CMD_SET_TRANSFORM) {
    renderer->setTransform(&buf[FLUERA_FFI_TRANSFORM]);
    return;
  }

  if (cmd == FLUERA_CMD_UPDATE_AND_RENDER) {
    const int pointCount = (int)buf[FLUERA_FFI_POINT_COUNT];
    if (pointCount < 2) return;

    renderer->updateAndRender(
        &buf[FLUERA_FFI_POINTS], pointCount,
        buf[FLUERA_FFI_COLOR_R],
        buf[FLUERA_FFI_COLOR_G],
        buf[FLUERA_FFI_COLOR_B],
        buf[FLUERA_FFI_COLOR_A],
        buf[FLUERA_FFI_STROKE_WIDTH],
        (int)buf[FLUERA_FFI_TOTAL_POINTS],
        (int)buf[FLUERA_FFI_BRUSH_TYPE],
        buf[FLUERA_FFI_PENCIL_BASE],
        buf[FLUERA_FFI_PENCIL_MAX],
        buf[FLUERA_FFI_PENCIL_MIN_P],
        buf[FLUERA_FFI_PENCIL_MAX_P],
        buf[FLUERA_FFI_FOUNTAIN_THIN],
        buf[FLUERA_FFI_FOUNTAIN_ANGLE],
        buf[FLUERA_FFI_FOUNTAIN_STR],
        buf[FLUERA_FFI_FOUNTAIN_RATE],
        (int)buf[FLUERA_FFI_FOUNTAIN_TAPER]);

    if (g_d3d_plugin->textureRegistrar_ && g_d3d_plugin->textureId_ >= 0) {
      g_d3d_plugin->textureRegistrar_->MarkTextureFrameAvailable(g_d3d_plugin->textureId_);
    }
  }
}

} // extern "C"
