// ═══════════════════════════════════════════════════════════════════
// 🚀 NativeStrokeFfi — dart:ffi shared memory bridge
//
// Replaces MethodChannel for hot-path stroke commands:
//   updateAndRender, setTransform, clear
//
// Allocates a shared Float32 buffer that both Dart and native code
// read/write directly — zero serialization, zero copies.
//
// Cold-path calls (init, destroy, resize, getStats) remain on
// MethodChannel because they need async responses and lifecycle mgmt.
// ═══════════════════════════════════════════════════════════════════

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../drawing/models/pro_drawing_point.dart';
import '../../canvas/infinite_canvas_controller.dart';

// ─── Buffer layout constants (must match fluera_stroke_ffi.h) ─────
const int _kCmd = 0;
const int _kPointCount = 1;
const int _kColorR = 2;
const int _kColorG = 3;
const int _kColorB = 4;
const int _kColorA = 5;
const int _kStrokeWidth = 6;
const int _kTotalPoints = 7;
const int _kBrushType = 8;
const int _kPencilBase = 9;
const int _kPencilMax = 10;
const int _kPencilMinP = 11;
const int _kPencilMaxP = 12;
const int _kFountainThin = 13;
const int _kFountainAngle = 14;
const int _kFountainStr = 15;
const int _kFountainRate = 16;
const int _kFountainTaper = 17;
const int _kHeaderSize = 20;
const int _kTransform = 20; // 16 floats [20..35]
const int _kPoints = 36; // stride 5 starting at [36]

// Commands
const double _cmdUpdateAndRender = 1.0;
const double _cmdSetTransform = 2.0;
const double _cmdClear = 3.0;

// Max points per batch (1000 points × 5 = 5000 floats)
const int _kMaxPoints = 1000;
const int _kBufferSize = _kPoints + (_kMaxPoints * 5); // 5036 floats

// ─── Native function signature ────────────────────────────────────
typedef _FlueraStrokeExecuteNative = Void Function(Pointer<Float>);
typedef _FlueraStrokeExecuteDart = void Function(Pointer<Float>);

/// 🚀 FFI bridge for hot-path stroke rendering.
///
/// Lifecycle:
///   1. Call [init] once after the MethodChannel `init` succeeds
///   2. Use [updateAndRender], [setTransform], [clear] for zero-copy hot path
///   3. Call [dispose] when done
class NativeStrokeFfi {
  Pointer<Float>? _buffer;
  _FlueraStrokeExecuteDart? _execute;
  bool _initialized = false;

  /// Whether FFI is initialized and ready.
  bool get isInitialized => _initialized;

  /// Initialize the FFI bridge.
  /// Must be called AFTER the MethodChannel `init` succeeds
  /// (native renderer must exist before we can call into it).
  bool init() {
    if (_initialized) return true;
    if (kIsWeb) return false; // Web uses js_interop, not dart:ffi

    try {
      // ── Load native library ──────────────────────────────────
      final DynamicLibrary nativeLib;
      if (Platform.isAndroid) {
        nativeLib = DynamicLibrary.open('libfluera_vk_stroke.so');
      } else if (Platform.isIOS || Platform.isMacOS) {
        nativeLib = DynamicLibrary.process(); // Statically linked
      } else if (Platform.isLinux) {
        nativeLib = DynamicLibrary.open('libfluera_gl_stroke.so');
      } else if (Platform.isWindows) {
        nativeLib = DynamicLibrary.open('fluera_d3d11_stroke.dll');
      } else {
        return false;
      }

      // ── Lookup FFI function ──────────────────────────────────
      _execute = nativeLib
          .lookup<NativeFunction<_FlueraStrokeExecuteNative>>(
              'fluera_stroke_execute')
          .asFunction<_FlueraStrokeExecuteDart>();

      // ── Allocate shared buffer ───────────────────────────────
      _buffer = calloc<Float>(_kBufferSize);
      if (_buffer == nullptr) return false;

      // Write identity transform as default
      _writeIdentityTransform();

      _initialized = true;
      debugPrint('[FlueraFFI] Initialized (buffer=${_kBufferSize * 4} bytes)');
      return true;
    } catch (e) {
      debugPrint('[FlueraFFI] Init failed: $e');
      _initialized = false;
      return false;
    }
  }

  /// Send stroke points to the native renderer via shared memory.
  /// Zero-copy: writes directly into the shared buffer.
  void updateAndRender(
    List<ProDrawingPoint> points,
    int startIndex,
    ui.Color color,
    double strokeWidth,
    int totalPoints, {
    int brushType = 0,
    double pencilBaseOpacity = 0.4,
    double pencilMaxOpacity = 0.8,
    double pencilMinPressure = 0.5,
    double pencilMaxPressure = 1.2,
    double fountainThinning = 0.5,
    double fountainNibAngleDeg = 30.0,
    double fountainNibStrength = 0.35,
    double fountainPressureRate = 0.275,
    int fountainTaperEntry = 6,
  }) {
    if (!_initialized || _buffer == null || _execute == null) return;

    final newCount = points.length - startIndex;
    if (newCount < 2) return;

    // Clamp to max buffer capacity
    final count = newCount > _kMaxPoints ? _kMaxPoints : newCount;
    final buf = _buffer!;

    // ── Write header ─────────────────────────────────────────
    buf[_kCmd] = _cmdUpdateAndRender;
    buf[_kPointCount] = count.toDouble();
    buf[_kColorR] = color.r;
    buf[_kColorG] = color.g;
    buf[_kColorB] = color.b;
    buf[_kColorA] = color.a;
    buf[_kStrokeWidth] = strokeWidth;
    buf[_kTotalPoints] = totalPoints.toDouble();
    buf[_kBrushType] = brushType.toDouble();
    buf[_kPencilBase] = pencilBaseOpacity;
    buf[_kPencilMax] = pencilMaxOpacity;
    buf[_kPencilMinP] = pencilMinPressure;
    buf[_kPencilMaxP] = pencilMaxPressure;
    buf[_kFountainThin] = fountainThinning;
    buf[_kFountainAngle] = fountainNibAngleDeg;
    buf[_kFountainStr] = fountainNibStrength;
    buf[_kFountainRate] = fountainPressureRate;
    buf[_kFountainTaper] = fountainTaperEntry.toDouble();

    // ── Write points (stride 5) ──────────────────────────────
    for (int i = 0; i < count; i++) {
      final pt = points[startIndex + i];
      final off = _kPoints + i * 5;
      buf[off] = pt.position.dx;
      buf[off + 1] = pt.position.dy;
      buf[off + 2] = pt.pressure;
      buf[off + 3] = pt.tiltX;
      buf[off + 4] = pt.tiltY;
    }

    // ── Execute ──────────────────────────────────────────────
    _execute!(buf);
  }

  /// Set the canvas transform matrix via shared memory.
  void setTransform(
    InfiniteCanvasController controller,
    int width,
    int height, [
    double dpr = 1.0,
  ]) {
    if (!_initialized || _buffer == null || _execute == null) return;

    final buf = _buffer!;
    buf[_kCmd] = _cmdSetTransform;

    final scale = controller.scale;
    final ox = controller.offset.dx;
    final oy = controller.offset.dy;
    final rotation = controller.rotation;

    final double w = width.toDouble();
    final double h = height.toDouble();
    final effectiveScale = scale * dpr;
    final effectiveOx = ox * dpr;
    final effectiveOy = oy * dpr;

    final cosR = rotation == 0.0 ? 1.0 : math.cos(rotation);
    final sinR = rotation == 0.0 ? 0.0 : math.sin(rotation);

    final sx = 2.0 * effectiveScale / w;
    final sy = 2.0 * effectiveScale / h;
    final tx = (2.0 * effectiveOx / w) - 1.0;
    final ty = (2.0 * effectiveOy / h) - 1.0;

    // Column-major 4×4
    buf[_kTransform]      = sx * cosR;
    buf[_kTransform + 1]  = sy * sinR;
    buf[_kTransform + 2]  = 0.0;
    buf[_kTransform + 3]  = 0.0;
    buf[_kTransform + 4]  = sx * -sinR;
    buf[_kTransform + 5]  = sy * cosR;
    buf[_kTransform + 6]  = 0.0;
    buf[_kTransform + 7]  = 0.0;
    buf[_kTransform + 8]  = 0.0;
    buf[_kTransform + 9]  = 0.0;
    buf[_kTransform + 10] = 1.0;
    buf[_kTransform + 11] = 0.0;
    buf[_kTransform + 12] = tx;
    buf[_kTransform + 13] = ty;
    buf[_kTransform + 14] = 0.0;
    buf[_kTransform + 15] = 1.0;

    _execute!(buf);
  }

  /// Clear the render target via shared memory.
  void clear() {
    if (!_initialized || _buffer == null || _execute == null) return;
    _buffer![_kCmd] = _cmdClear;
    _execute!(_buffer!);
  }

  /// Dispose the shared buffer.
  void dispose() {
    if (_buffer != null) {
      calloc.free(_buffer!);
      _buffer = null;
    }
    _execute = null;
    _initialized = false;
  }

  void _writeIdentityTransform() {
    if (_buffer == null) return;
    for (int i = 0; i < 16; i++) {
      _buffer![_kTransform + i] = 0.0;
    }
    _buffer![_kTransform] = 1.0;      // m[0][0]
    _buffer![_kTransform + 5] = 1.0;  // m[1][1]
    _buffer![_kTransform + 10] = 1.0; // m[2][2]
    _buffer![_kTransform + 15] = 1.0; // m[3][3]
  }
}
