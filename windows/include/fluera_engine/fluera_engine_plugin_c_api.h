// Flutter plugin public header for Windows
// This header is auto-included by the Flutter build system.

#ifndef FLUTTER_PLUGIN_FLUERA_ENGINE_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUERA_ENGINE_PLUGIN_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void FlueraEnginePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_FLUERA_ENGINE_PLUGIN_H_
