// gl_stroke_overlay_plugin.h — Flutter Linux plugin bridge
// Equivalent to VulkanStrokeOverlayPlugin.kt (Android),
// MetalStrokeOverlayPlugin.swift (iOS), and
// D3D11StrokeOverlayPlugin (Windows)

#pragma once

#include <flutter_linux/flutter_linux.h>
#include <memory>
#include "gl_stroke_renderer.h"

G_BEGIN_DECLS

// Plugin class declaration (GObject)
#define GL_STROKE_OVERLAY_PLUGIN_TYPE (gl_stroke_overlay_plugin_get_type())
G_DECLARE_FINAL_TYPE(GlStrokeOverlayPlugin, gl_stroke_overlay_plugin,
                     GL_STROKE_OVERLAY, PLUGIN, GObject)

/// Register plugin with Flutter registrar.
void gl_stroke_overlay_plugin_register_with_registrar(
    FlPluginRegistrar *registrar);

G_END_DECLS
