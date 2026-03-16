// ═══════════════════════════════════════════════════════════════════
// fluera_stroke_ffi.h — Unified C FFI export for hot-path stroke commands
//
// Single entry point for all hot-path operations (updateAndRender,
// setTransform, clear). Replaces MethodChannel for these calls.
//
// Shared buffer layout (all float32):
//   [0]      command:  1.0=updateAndRender, 2.0=setTransform, 3.0=clear
//   [1]      pointCount
//   [2..5]   colorR, colorG, colorB, colorA
//   [6]      strokeWidth
//   [7]      totalPoints
//   [8]      brushType
//   [9]      pencilBaseOpacity
//   [10]     pencilMaxOpacity
//   [11]     pencilMinPressure
//   [12]     pencilMaxPressure
//   [13]     fountainThinning
//   [14]     fountainNibAngleDeg
//   [15]     fountainNibStrength
//   [16]     fountainPressureRate
//   [17]     fountainTaperEntry
//   [18..19] reserved
//   [20..35] transform matrix (4x4, column-major)
//   [36..]   points (stride 5: x, y, pressure, tiltX, tiltY)
//
// Total header: 20 floats = 80 bytes
// Transform:    16 floats = 64 bytes
// Points:       5 * maxPoints floats
// ═══════════════════════════════════════════════════════════════════

#ifndef FLUERA_STROKE_FFI_H
#define FLUERA_STROKE_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

// Buffer layout offsets
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
#define FLUERA_FFI_HEADER_SIZE   20
#define FLUERA_FFI_TRANSFORM     20  // 16 floats at [20..35]
#define FLUERA_FFI_POINTS        36  // stride 5 starting at [36]

// Commands
#define FLUERA_CMD_UPDATE_AND_RENDER  1.0f
#define FLUERA_CMD_SET_TRANSFORM     2.0f
#define FLUERA_CMD_CLEAR             3.0f

/// Execute a hot-path stroke command from the shared buffer.
/// Called from Dart via dart:ffi. The buffer is owned by the Dart side.
///
/// Thread safety: called on the Dart UI isolate thread.
/// The native renderer must handle any thread synchronization internally.
#if defined(_WIN32)
  __declspec(dllexport)
#else
  __attribute__((visibility("default")))
#endif
void fluera_stroke_execute(float* shared_buffer);

#ifdef __cplusplus
}
#endif

#endif // FLUERA_STROKE_FFI_H
