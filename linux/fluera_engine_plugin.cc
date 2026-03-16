// fluera_engine_plugin.cc — Main Flutter Linux plugin entry point
#include "include/fluera_engine/fluera_engine_plugin.h"
#include "gl_stroke_overlay_plugin.h"

void fluera_engine_plugin_register_with_registrar(
    FlPluginRegistrar *registrar) {
  gl_stroke_overlay_plugin_register_with_registrar(registrar);
}
