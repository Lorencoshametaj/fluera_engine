// fluera_engine_plugin.cpp — Main Flutter Windows plugin entry point
// Registers all native plugins, including the D3D11 stroke overlay.

#include "d3d11_stroke_overlay_plugin.h"

#include <flutter/plugin_registrar_windows.h>

void FlueraEnginePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  D3D11StrokeOverlayPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
