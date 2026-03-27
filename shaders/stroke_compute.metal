// ═══════════════════════════════════════════════════════════════════
// stroke_compute.metal — GPU Compute Tessellation for Metal (iOS/macOS)
//
// MSL port of stroke_compute.comp. Same algorithm:
// Catmull-Rom spline → tangent → perpendicular → triangle output.
// ═══════════════════════════════════════════════════════════════════

#include <metal_stdlib>
using namespace metal;

struct Params {
  float colorR;
  float colorG;
  float colorB;
  float colorA;
  float strokeWidth;
  int   pointCount;
  int   brushType;
  float minPressure;
  float maxPressure;
  float pencilBaseOpacity;
  float pencilMaxOpacity;
  int   subsPerSeg;
  int   totalSubdivs;
  // Fountain pen fields
  float fountainThinning;
  float fountainNibAngleRad;
  float fountainNibStrength;
  // Incremental compute
  int   startSeg;       // First segment to tessellate
  int   vertexOffset;   // Output vertex offset (startSeg * subsPerSeg * 6)
};

// ─── Helpers ──────────────────────────────────────────────────────

float2 catmullRom(float2 p0, float2 p1, float2 p2, float2 p3, float t) {
  float t2 = t * t;
  float t3 = t2 * t;
  return 0.5 * ((2.0 * p1) +
                (-p0 + p2) * t +
                (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
                (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
}

float2 catmullRomTangent(float2 p0, float2 p1, float2 p2, float2 p3, float t) {
  float t2 = t * t;
  return 0.5 * ((-p0 + p2) +
                (4.0 * p0 - 10.0 * p1 + 8.0 * p2 - 2.0 * p3) * t +
                (-3.0 * p0 + 9.0 * p1 - 9.0 * p2 + 3.0 * p3) * t2);
}

float computeHalfWidth(int brushType, float strokeWidth, float pressure,
                       int globalIdx, int totalPts,
                       float minP, float maxP,
                       float2 dir, float nibAngleRad, float nibStrength, float thinning) {
  if (brushType == 0) {
    return strokeWidth * (minP + 0.5 * (maxP - minP)) * 0.5;
  } else if (brushType == 1) {
    return strokeWidth * 2.5 * 0.5;
  } else if (brushType == 2) {
    float hw = strokeWidth * 0.5 * (minP + pressure * (maxP - minP));
    if (globalIdx < 4) {
      float t = float(globalIdx) / 4.0;
      float ease = t * (2.0 - t);
      hw *= 0.15 + ease * 0.85;
    }
    return hw;
  } else if (brushType == 4) {
    // Fountain pen: nib angle modulates width based on stroke direction
    float baseHW = strokeWidth * 0.5 * (0.4 + pressure * 0.6 * (1.0 - thinning));
    // Compute angle between direction and nib angle
    float dirAngle = atan2(dir.y, dir.x);
    float angleDiff = abs(dirAngle - nibAngleRad);
    // Cross-nib factor: perpendicular to nib = thick, parallel = thin
    float crossNib = abs(sin(angleDiff));
    float nibFactor = mix(1.0, crossNib, nibStrength);
    baseHW *= (0.4 + nibFactor * 0.6);
    // Taper entry
    if (globalIdx < 6) {
      float t = float(globalIdx) / 6.0;
      baseHW *= 0.2 + t * 0.8;
    }
    return baseHW;
  } else {
    return strokeWidth * 0.5;
  }
}

float computeAlpha(int brushType, float baseAlpha, float pressure,
                   float pencilBaseOp, float pencilMaxOp) {
  if (brushType == 2) {
    return baseAlpha * (pencilBaseOp + (pencilMaxOp - pencilBaseOp) * pressure);
  }
  return baseAlpha;
}

// ═══════════════════════════════════════════════════════════════════
// MAIN KERNEL
// ═══════════════════════════════════════════════════════════════════

kernel void strokeComputeKernel(
    device const float* points         [[buffer(0)]],
    constant Params& params            [[buffer(1)]],
    device float* verts                [[buffer(2)]],
    device atomic_int& capVertexCount  [[buffer(3)]],
    device float* caps                 [[buffer(4)]],
    uint gid                           [[thread_position_in_grid]],
    uint lid                           [[thread_position_in_threadgroup]],
    uint wgid                          [[threadgroup_position_in_grid]])
{
  // 🚀 LDS: Threadgroup memory for Catmull-Rom control points
  threadgroup float3 s_points[20]; // float3(x, y, pressure)

  if (int(gid) >= params.totalSubdivs) return;

  // 🚀 Incremental: offset segment index and output position
  int localSeg = int(gid) / params.subsPerSeg;
  int sub = int(gid) % params.subsPerSeg;
  int seg = localSeg + params.startSeg;
  int N = params.pointCount;
  if (seg >= N - 1) return;

  // 🚀 LDS: Cooperatively load control points into threadgroup memory
  int wgFirstSeg = (int(wgid) * 64) / params.subsPerSeg + params.startSeg;
  int wgLastSeg = min(wgFirstSeg + (63 / params.subsPerSeg), N - 2);
  int firstPt = max(wgFirstSeg - 1, 0);
  int lastPt = min(wgLastSeg + 2, N - 1);
  int numPts = lastPt - firstPt + 1;

  if (int(lid) < numPts && int(lid) < 20) {
    int pi = firstPt + int(lid);
    s_points[int(lid)] = float3(points[pi*5], points[pi*5+1], points[pi*5+2]);
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // Control points from threadgroup memory
  int i0 = max(seg - 1, 0) - firstPt;
  int i1 = seg - firstPt;
  int i2 = seg + 1 - firstPt;
  int i3 = min(seg + 2, N - 1) - firstPt;

  float2 p0 = s_points[i0].xy;
  float2 p1 = s_points[i1].xy;
  float2 p2 = s_points[i2].xy;
  float2 p3 = s_points[i3].xy;

  float t = float(sub) / float(params.subsPerSeg);
  float2 pos = catmullRom(p0, p1, p2, p3, t);
  float2 tan = catmullRomTangent(p0, p1, p2, p3, t);
  float tanLen = length(tan);
  if (tanLen < 0.0001) tan = float2(1, 0);
  else tan /= tanLen;

  // Next sample
  float2 posNext, tanNext;
  if (sub < params.subsPerSeg - 1) {
    float tN = float(sub + 1) / float(params.subsPerSeg);
    posNext = catmullRom(p0, p1, p2, p3, tN);
    tanNext = catmullRomTangent(p0, p1, p2, p3, tN);
  } else if (seg + 1 < N - 1) {
    int j0 = max(seg, 0), j1 = seg + 1, j2 = min(seg + 2, N - 1), j3 = min(seg + 3, N - 1);
    float2 q0 = float2(points[j0*5], points[j0*5+1]);
    float2 q1 = float2(points[j1*5], points[j1*5+1]);
    float2 q2 = float2(points[j2*5], points[j2*5+1]);
    float2 q3 = float2(points[j3*5], points[j3*5+1]);
    posNext = catmullRom(q0, q1, q2, q3, 0.0);
    tanNext = catmullRomTangent(q0, q1, q2, q3, 0.0);
  } else {
    posNext = p2;
    tanNext = p2 - p1;
  }
  float tnl = length(tanNext);
  if (tnl < 0.0001) tanNext = float2(1, 0);
  else tanNext /= tnl;

  float2 perp     = float2(-tan.y, tan.x);
  float2 perpNext = float2(-tanNext.y, tanNext.x);

  float pressure     = mix(s_points[i1].z, s_points[i2].z, t);
  float pressureNext = mix(s_points[i1].z, s_points[i2].z, sub < params.subsPerSeg - 1 ? float(sub + 1) / float(params.subsPerSeg) : 1.0);

  float hw     = computeHalfWidth(params.brushType, params.strokeWidth, pressure, seg, N, params.minPressure, params.maxPressure, tan, params.fountainNibAngleRad, params.fountainNibStrength, params.fountainThinning);
  float hwNext = computeHalfWidth(params.brushType, params.strokeWidth, pressureNext, seg + (sub == params.subsPerSeg - 1 ? 1 : 0), N, params.minPressure, params.maxPressure, tanNext, params.fountainNibAngleRad, params.fountainNibStrength, params.fountainThinning);

  float alpha     = computeAlpha(params.brushType, params.colorA, pressure, params.pencilBaseOpacity, params.pencilMaxOpacity);
  float alphaNext = computeAlpha(params.brushType, params.colorA, pressureNext, params.pencilBaseOpacity, params.pencilMaxOpacity);

  // 🚀 #9: Miter limit — prevent spike artifacts at sharp turns (>60°)
  float turnDot = dot(tan, tanNext);
  if (turnDot < 0.5) {
    float miterScale = smoothstep(0.0, 0.5, turnDot);
    hwNext *= max(miterScale, 0.3f);
  }

  float2 left  = pos     + perp     * hw;
  float2 right = pos     - perp     * hw;
  float2 leftN = posNext + perpNext * hwNext;
  float2 rightN= posNext - perpNext * hwNext;

  int outBase = (int(gid) + params.vertexOffset) * 6 * 6; // 6 verts × 6 floats each, with offset
  // Triangle 1
  verts[outBase]    = left.x;  verts[outBase+1]  = left.y;
  verts[outBase+2]  = params.colorR; verts[outBase+3] = params.colorG;
  verts[outBase+4]  = params.colorB; verts[outBase+5] = alpha;
  // Triangle 1 vert 2
  verts[outBase+6]  = right.x; verts[outBase+7]  = right.y;
  verts[outBase+8]  = params.colorR; verts[outBase+9] = params.colorG;
  verts[outBase+10] = params.colorB; verts[outBase+11] = alpha;
  // Triangle 1 vert 3
  verts[outBase+12] = leftN.x; verts[outBase+13] = leftN.y;
  verts[outBase+14] = params.colorR; verts[outBase+15] = params.colorG;
  verts[outBase+16] = params.colorB; verts[outBase+17] = alphaNext;
  // Triangle 2
  verts[outBase+18] = right.x; verts[outBase+19] = right.y;
  verts[outBase+20] = params.colorR; verts[outBase+21] = params.colorG;
  verts[outBase+22] = params.colorB; verts[outBase+23] = alpha;
  verts[outBase+24] = leftN.x; verts[outBase+25] = leftN.y;
  verts[outBase+26] = params.colorR; verts[outBase+27] = params.colorG;
  verts[outBase+28] = params.colorB; verts[outBase+29] = alphaNext;
  verts[outBase+30] = rightN.x; verts[outBase+31] = rightN.y;
  verts[outBase+32] = params.colorR; verts[outBase+33] = params.colorG;
  verts[outBase+34] = params.colorB; verts[outBase+35] = alphaNext;

  // Endpoint caps (ballpoint + technical only) — 🚀 Adaptive LOD
  if (int(gid) == 0 && (params.brushType == 0 || params.brushType == 3)) {
    int segments = clamp(params.subsPerSeg, 4, 16);
    int baseIdx = atomic_fetch_add_explicit(&capVertexCount, segments * 3, memory_order_relaxed);
    for (int s = 0; s < segments; s++) {
      float a0 = 6.28318530718 * float(s) / float(segments);
      float a1 = 6.28318530718 * float(s + 1) / float(segments);
      int ci = (baseIdx + s * 3) * 6;
      caps[ci] = pos.x; caps[ci+1] = pos.y; caps[ci+2] = params.colorR; caps[ci+3] = params.colorG; caps[ci+4] = params.colorB; caps[ci+5] = alpha;
      caps[ci+6] = pos.x + hw * cos(a0); caps[ci+7] = pos.y + hw * sin(a0); caps[ci+8] = params.colorR; caps[ci+9] = params.colorG; caps[ci+10] = params.colorB; caps[ci+11] = alpha;
      caps[ci+12] = pos.x + hw * cos(a1); caps[ci+13] = pos.y + hw * sin(a1); caps[ci+14] = params.colorR; caps[ci+15] = params.colorG; caps[ci+16] = params.colorB; caps[ci+17] = alpha;
    }
  }
}
