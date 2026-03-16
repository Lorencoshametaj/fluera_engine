// d3d11_stroke_overlay_plugin.h — Flutter Windows plugin bridge
// Equivalent to VulkanStrokeOverlayPlugin.kt (Android) and
// MetalStrokeOverlayPlugin.swift (iOS)

#pragma once

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <memory>

#include "d3d11_stroke_renderer.h"

/// Flutter Windows plugin that bridges MethodChannel calls to the
/// D3D11StrokeRenderer and shares the output texture via GpuSurfaceTexture.
class D3D11StrokeOverlayPlugin {
public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  D3D11StrokeOverlayPlugin(flutter::PluginRegistrarWindows *registrar);
  ~D3D11StrokeOverlayPlugin();

private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::TextureRegistrar *textureRegistrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<D3D11StrokeRenderer> renderer_;
  std::unique_ptr<flutter::TextureVariant> texture_;
  int64_t textureId_ = -1;
};
