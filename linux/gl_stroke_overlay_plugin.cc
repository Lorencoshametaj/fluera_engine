// gl_stroke_overlay_plugin.cc — Flutter Linux plugin implementation
// Uses DEFERRED RENDERING: CPU tessellation on method channel (platform thread),
// GL rendering inside FlTextureGL populate callback (raster thread, Flutter's context).

#include "gl_stroke_overlay_plugin.h"

#include <cstdio>
#include <cstring>
#include <memory>

// ═══════════════════════════════════════════════════════════════════
// GOBJECT PRIVATE STRUCT
// ═══════════════════════════════════════════════════════════════════

struct _GlStrokeOverlayPlugin {
  GObject parent_instance;
  FlMethodChannel *channel;
  FlTextureRegistrar *texture_registrar;
  FlTexture *texture;
  GLStrokeRenderer *renderer;
  int64_t texture_id;
};

G_DEFINE_TYPE(GlStrokeOverlayPlugin, gl_stroke_overlay_plugin, G_TYPE_OBJECT)

// ═══════════════════════════════════════════════════════════════════
// TEXTURE GL IMPLEMENTATION (FlTextureGL subclass)
// Populate callback runs on Flutter's raster thread with GL context.
// ═══════════════════════════════════════════════════════════════════

#define STROKE_TEXTURE_GL_TYPE (stroke_texture_gl_get_type())
G_DECLARE_FINAL_TYPE(StrokeTextureGL, stroke_texture_gl, STROKE, TEXTURE_GL, FlTextureGL)

struct _StrokeTextureGL {
  FlTextureGL parent_instance;
  GLStrokeRenderer *renderer;
  int width;
  int height;
};

G_DEFINE_TYPE(StrokeTextureGL, stroke_texture_gl, fl_texture_gl_get_type())

// 🔑 This runs on the RASTER THREAD with Flutter's GL context active.
// We do ALL our GL rendering here using Flutter's own context.
static gboolean stroke_texture_gl_populate(FlTextureGL *texture_gl,
                                           uint32_t *target, uint32_t *name,
                                           uint32_t *width, uint32_t *height,
                                           GError **error) {
  StrokeTextureGL *self = STROKE_TEXTURE_GL(texture_gl);
  if (!self->renderer || !self->renderer->isInitialized()) return FALSE;

  // Render using Flutter's GL context and get the output texture
  GLuint texName = self->renderer->renderAndGetTexture();
  if (texName == 0) return FALSE;

  *target = GL_TEXTURE_2D;
  *name = texName;
  *width = static_cast<uint32_t>(self->renderer->getWidth());
  *height = static_cast<uint32_t>(self->renderer->getHeight());
  return TRUE;
}

static void stroke_texture_gl_class_init(StrokeTextureGLClass *klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = stroke_texture_gl_populate;
}

static void stroke_texture_gl_init(StrokeTextureGL *self) {
  self->renderer = nullptr;
  self->width = 0;
  self->height = 0;
}

static StrokeTextureGL *stroke_texture_gl_new(GLStrokeRenderer *renderer, int w, int h) {
  auto *self = STROKE_TEXTURE_GL(g_object_new(STROKE_TEXTURE_GL_TYPE, nullptr));
  self->renderer = renderer;
  self->width = w;
  self->height = h;
  return self;
}

// ═══════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════

static double get_double(FlValue *map, const char *key, double def) {
  FlValue *v = fl_value_lookup_string(map, key);
  if (!v) return def;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(v);
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) return (double)fl_value_get_int(v);
  return def;
}

static int64_t get_int(FlValue *map, const char *key, int64_t def) {
  FlValue *v = fl_value_lookup_string(map, key);
  if (!v) return def;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) return fl_value_get_int(v);
  if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) return (int64_t)fl_value_get_float(v);
  return def;
}

// ═══════════════════════════════════════════════════════════════════
// METHOD CALL HANDLER (platform thread — CPU only, no GL calls)
// ═══════════════════════════════════════════════════════════════════

static void handle_method_call(FlMethodChannel *channel,
                               FlMethodCall *method_call,
                               gpointer user_data) {
  auto *self = GL_STROKE_OVERLAY_PLUGIN(user_data);
  const gchar *method = fl_method_call_get_name(method_call);
  FlValue *args = fl_method_call_get_args(method_call);

  // ── isAvailable ─────────────────────────────────────────────
  if (strcmp(method, "isAvailable") == 0) {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // ── init ────────────────────────────────────────────────────
  if (strcmp(method, "init") == 0) {
    int w = (int)get_int(args, "width", 1920);
    int h = (int)get_int(args, "height", 1080);

    self->renderer = new GLStrokeRenderer();
    self->renderer->init(w, h);  // No GL calls — just sets dimensions

    // Register GL texture with Flutter
    StrokeTextureGL *gl_texture = stroke_texture_gl_new(self->renderer, w, h);
    self->texture = FL_TEXTURE(gl_texture);
    fl_texture_registrar_register_texture(self->texture_registrar, self->texture);
    self->texture_id = fl_texture_get_id(self->texture);

    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(
            fl_value_new_int(self->texture_id)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // ── updateAndRender (CPU tessellation only — GL deferred) ───
  if (strcmp(method, "updateAndRender") == 0) {
    if (!self->renderer) {
      g_autoptr(FlMethodResponse) response =
          FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    FlValue *pt_list = fl_value_lookup_string(args, "points");
    if (!pt_list || fl_value_get_type(pt_list) != FL_VALUE_TYPE_LIST) {
      g_autoptr(FlMethodResponse) response =
          FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    size_t count = fl_value_get_length(pt_list);
    if (count < 10) {
      g_autoptr(FlMethodResponse) response =
          FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    std::vector<float> floatPoints(count);
    for (size_t i = 0; i < count; i++) {
      FlValue *v = fl_value_get_list_value(pt_list, i);
      floatPoints[i] = (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT)
                            ? (float)fl_value_get_float(v)
                            : (float)fl_value_get_int(v);
    }

    // CPU-only tessellation (mutex-protected, no GL calls)
    self->renderer->updateVertices(
        floatPoints.data(), (int)(count / 5),
        // Color extracted from 'color' param
        (float)((get_int(args, "color", 0xFF000000) >> 16) & 0xFF) / 255.0f,
        (float)((get_int(args, "color", 0xFF000000) >> 8) & 0xFF) / 255.0f,
        (float)(get_int(args, "color", 0xFF000000) & 0xFF) / 255.0f,
        (float)((get_int(args, "color", 0xFF000000) >> 24) & 0xFF) / 255.0f,
        (float)get_double(args, "width", 2.0),
        (int)get_int(args, "totalPoints", 0),
        (int)get_int(args, "brushType", 0),
        (float)get_double(args, "pencilBaseOpacity", 0.4),
        (float)get_double(args, "pencilMaxOpacity", 0.8),
        (float)get_double(args, "pencilMinPressure", 0.5),
        (float)get_double(args, "pencilMaxPressure", 1.2),
        (float)get_double(args, "fountainThinning", 0.5),
        (float)get_double(args, "fountainNibAngleDeg", 30.0),
        (float)get_double(args, "fountainNibStrength", 0.35),
        (float)get_double(args, "fountainPressureRate", 0.275),
        (int)get_int(args, "fountainTaperEntry", 6));

    // Tell Flutter a new frame is available — triggers populate on raster thread
    fl_texture_registrar_mark_texture_frame_available(
        self->texture_registrar, self->texture);

    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // ── setTransform ────────────────────────────────────────────
  if (strcmp(method, "setTransform") == 0) {
    if (self->renderer) {
      FlValue *m_list = fl_value_lookup_string(args, "matrix");
      if (m_list && fl_value_get_length(m_list) >= 16) {
        float matrix[16];
        for (int i = 0; i < 16; i++) {
          FlValue *v = fl_value_get_list_value(m_list, i);
          matrix[i] = (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT)
                          ? (float)fl_value_get_float(v) : 0.0f;
        }
        self->renderer->setTransform(matrix);
      }
    }
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // ── clear ───────────────────────────────────────────────────
  if (strcmp(method, "clear") == 0) {
    if (self->renderer) {
      self->renderer->clearFrame();  // CPU-only (sets flag)
      fl_texture_registrar_mark_texture_frame_available(
          self->texture_registrar, self->texture);
    }
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // ── resize ──────────────────────────────────────────────────
  if (strcmp(method, "resize") == 0) {
    if (self->renderer) {
      int w = (int)get_int(args, "width", 1920);
      int h = (int)get_int(args, "height", 1080);
      self->renderer->resize(w, h);  // CPU-only (sets flag)
      // Update texture dimensions
      if (self->texture) {
        STROKE_TEXTURE_GL(self->texture)->width = w;
        STROKE_TEXTURE_GL(self->texture)->height = h;
      }
    }
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // ── destroy ─────────────────────────────────────────────────
  if (strcmp(method, "destroy") == 0) {
    if (self->texture && self->texture_registrar) {
      fl_texture_registrar_unregister_texture(self->texture_registrar, self->texture);
      g_clear_object(&self->texture);
    }
    if (self->renderer) {
      delete self->renderer;
      self->renderer = nullptr;
    }
    self->texture_id = -1;
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // ── getStats ────────────────────────────────────────────────
  if (strcmp(method, "getStats") == 0) {
    if (!self->renderer) {
      g_autoptr(FlMethodResponse) response =
          FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    auto stats = self->renderer->getStats();
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "frameTimeP50Us", fl_value_new_float(stats.frameTimeP50Us));
    fl_value_set_string_take(map, "frameTimeP90Us", fl_value_new_float(stats.frameTimeP90Us));
    fl_value_set_string_take(map, "frameTimeP99Us", fl_value_new_float(stats.frameTimeP99Us));
    fl_value_set_string_take(map, "vertexCount", fl_value_new_int(stats.vertexCount));
    fl_value_set_string_take(map, "totalFrames", fl_value_new_int(stats.totalFrames));
    fl_value_set_string_take(map, "active", fl_value_new_bool(stats.active));
    fl_value_set_string_take(map, "deviceName", fl_value_new_string("OpenGL"));
    fl_value_set_string_take(map, "apiVersionMajor", fl_value_new_int(4));
    fl_value_set_string_take(map, "apiVersionMinor", fl_value_new_int(0));
    fl_value_set_string_take(map, "apiVersionPatch", fl_value_new_int(0));
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(map));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  fl_method_call_respond(method_call,
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()), nullptr);
}

// ═══════════════════════════════════════════════════════════════════
// GOBJECT LIFECYCLE
// ═══════════════════════════════════════════════════════════════════

static void gl_stroke_overlay_plugin_dispose(GObject *object) {
  auto *self = GL_STROKE_OVERLAY_PLUGIN(object);
  if (self->texture && self->texture_registrar) {
    fl_texture_registrar_unregister_texture(self->texture_registrar, self->texture);
    g_clear_object(&self->texture);
  }
  if (self->renderer) {
    delete self->renderer;
    self->renderer = nullptr;
  }
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(gl_stroke_overlay_plugin_parent_class)->dispose(object);
}

static void gl_stroke_overlay_plugin_class_init(GlStrokeOverlayPluginClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = gl_stroke_overlay_plugin_dispose;
}

static void gl_stroke_overlay_plugin_init(GlStrokeOverlayPlugin *self) {
  self->renderer = nullptr;
  self->texture = nullptr;
  self->texture_id = -1;
}

// Global plugin pointer for FFI access (set during registration)
static GlStrokeOverlayPlugin *g_ffi_plugin = nullptr;

void gl_stroke_overlay_plugin_register_with_registrar(
    FlPluginRegistrar *registrar) {
  auto *self = GL_STROKE_OVERLAY_PLUGIN(
      g_object_new(GL_STROKE_OVERLAY_PLUGIN_TYPE, nullptr));

  self->texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "fluera_engine/vulkan_stroke",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->channel, handle_method_call, self, nullptr);

  g_object_ref(self); // prevent premature dealloc
  g_ffi_plugin = self; // 🚀 FFI: expose to fluera_stroke_execute
}

// ═══════════════════════════════════════════════════════════════════
// 🚀 FFI EXPORT — Direct Dart→C++ hot path (replaces MethodChannel)
// ═══════════════════════════════════════════════════════════════════

// Buffer layout — mirrors fluera_stroke_ffi.h
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

extern "C" {

__attribute__((visibility("default")))
void fluera_stroke_execute(float* buf) {
  if (!buf || !g_ffi_plugin || !g_ffi_plugin->renderer ||
      !g_ffi_plugin->renderer->isInitialized()) return;

  auto *renderer = g_ffi_plugin->renderer;
  const float cmd = buf[FLUERA_FFI_CMD];

  if (cmd == FLUERA_CMD_CLEAR) {
    renderer->clearFrame();
    if (g_ffi_plugin->texture && g_ffi_plugin->texture_registrar) {
      fl_texture_registrar_mark_texture_frame_available(
          g_ffi_plugin->texture_registrar, g_ffi_plugin->texture);
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

    renderer->updateVertices(
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

    if (g_ffi_plugin->texture && g_ffi_plugin->texture_registrar) {
      fl_texture_registrar_mark_texture_frame_available(
          g_ffi_plugin->texture_registrar, g_ffi_plugin->texture);
    }
  }
}

} // extern "C"
