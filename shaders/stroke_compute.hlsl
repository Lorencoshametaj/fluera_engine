// ═══════════════════════════════════════════════════════════════════
// stroke_compute.hlsl — GPU Compute Tessellation for D3D11 (Windows)
//
// HLSL CS 5.0 port of stroke_compute.comp. Same algorithm.
// ═══════════════════════════════════════════════════════════════════

cbuffer Params : register(b0) {
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
  float pad0; // 16-byte alignment padding
};

StructuredBuffer<float>   points : register(t0);
RWStructuredBuffer<float> verts  : register(u0);
RWStructuredBuffer<int>   capCounter : register(u1);
RWStructuredBuffer<float> caps   : register(u2);

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

float computeHalfWidth(int bt, float sw, float pressure, int gi, int total, float minP, float maxP) {
  if (bt == 0) return sw * (minP + 0.5 * (maxP - minP)) * 0.5;
  if (bt == 1) return sw * 2.5 * 0.5;
  if (bt == 2) {
    float hw = sw * 0.5 * (minP + pressure * (maxP - minP));
    if (gi < 4) { float t = float(gi) / 4.0; hw *= 0.15 + t * (2.0 - t) * 0.85; }
    return hw;
  }
  return sw * 0.5;
}

float computeAlpha(int bt, float base, float p, float pbo, float pmo) {
  if (bt == 2) return base * (pbo + (pmo - pbo) * p);
  return base;
}

// ═══════════════════════════════════════════════════════════════════

[numthreads(64, 1, 1)]
void CSMain(uint3 dtid : SV_DispatchThreadID) {
  int gid = int(dtid.x);
  if (gid >= totalSubdivs) return;

  int seg = gid / subsPerSeg;
  int sub = gid % subsPerSeg;
  int N = pointCount;
  if (seg >= N - 1) return;

  int i0 = max(seg - 1, 0);
  int i1 = seg;
  int i2 = seg + 1;
  int i3 = min(seg + 2, N - 1);

  float2 p0 = float2(points[i0*5], points[i0*5+1]);
  float2 p1 = float2(points[i1*5], points[i1*5+1]);
  float2 p2 = float2(points[i2*5], points[i2*5+1]);
  float2 p3 = float2(points[i3*5], points[i3*5+1]);

  float t = float(sub) / float(subsPerSeg);
  float2 pos = catmullRom(p0, p1, p2, p3, t);
  float2 tan = catmullRomTangent(p0, p1, p2, p3, t);
  float tanLen = length(tan);
  if (tanLen < 0.0001) tan = float2(1, 0); else tan /= tanLen;

  float2 posNext, tanNext;
  if (sub < subsPerSeg - 1) {
    float tN = float(sub + 1) / float(subsPerSeg);
    posNext = catmullRom(p0, p1, p2, p3, tN);
    tanNext = catmullRomTangent(p0, p1, p2, p3, tN);
  } else if (seg + 1 < N - 1) {
    int j0 = max(seg, 0), j1 = seg + 1, j2 = min(seg + 2, N - 1), j3 = min(seg + 3, N - 1);
    posNext = catmullRom(float2(points[j0*5], points[j0*5+1]), float2(points[j1*5], points[j1*5+1]),
                         float2(points[j2*5], points[j2*5+1]), float2(points[j3*5], points[j3*5+1]), 0.0);
    tanNext = catmullRomTangent(float2(points[j0*5], points[j0*5+1]), float2(points[j1*5], points[j1*5+1]),
                                float2(points[j2*5], points[j2*5+1]), float2(points[j3*5], points[j3*5+1]), 0.0);
  } else {
    posNext = p2; tanNext = p2 - p1;
  }
  float tnl = length(tanNext);
  if (tnl < 0.0001) tanNext = float2(1, 0); else tanNext /= tnl;

  float2 perp     = float2(-tan.y, tan.x);
  float2 perpNext = float2(-tanNext.y, tanNext.x);

  float pr  = lerp(points[i1*5+2], points[i2*5+2], t);
  float prN = lerp(points[i1*5+2], points[i2*5+2], sub < subsPerSeg - 1 ? float(sub + 1) / float(subsPerSeg) : 1.0);

  float hw  = computeHalfWidth(brushType, strokeWidth, pr, seg, N, minPressure, maxPressure);
  float hwN = computeHalfWidth(brushType, strokeWidth, prN, seg + (sub == subsPerSeg - 1 ? 1 : 0), N, minPressure, maxPressure);
  float al  = computeAlpha(brushType, colorA, pr, pencilBaseOpacity, pencilMaxOpacity);
  float alN = computeAlpha(brushType, colorA, prN, pencilBaseOpacity, pencilMaxOpacity);

  float2 left  = pos     + perp     * hw;
  float2 right = pos     - perp     * hw;
  float2 leftN = posNext + perpNext * hwN;
  float2 rightN= posNext - perpNext * hwN;

  int ob = gid * 36; // 6 verts × 6 floats
  verts[ob]    = left.x;  verts[ob+1]  = left.y;  verts[ob+2] = colorR; verts[ob+3] = colorG; verts[ob+4] = colorB; verts[ob+5] = al;
  verts[ob+6]  = right.x; verts[ob+7]  = right.y; verts[ob+8] = colorR; verts[ob+9] = colorG; verts[ob+10]= colorB; verts[ob+11]= al;
  verts[ob+12] = leftN.x; verts[ob+13] = leftN.y; verts[ob+14]= colorR; verts[ob+15]= colorG; verts[ob+16]= colorB; verts[ob+17]= alN;
  verts[ob+18] = right.x; verts[ob+19] = right.y; verts[ob+20]= colorR; verts[ob+21]= colorG; verts[ob+22]= colorB; verts[ob+23]= al;
  verts[ob+24] = leftN.x; verts[ob+25] = leftN.y; verts[ob+26]= colorR; verts[ob+27]= colorG; verts[ob+28]= colorB; verts[ob+29]= alN;
  verts[ob+30] = rightN.x;verts[ob+31] = rightN.y;verts[ob+32]= colorR; verts[ob+33]= colorG; verts[ob+34]= colorB; verts[ob+35]= alN;
}
