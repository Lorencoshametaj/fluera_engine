// ═══════════════════════════════════════════════════════════════════
// stroke_compute.wgsl — GPU Compute Tessellation for WebGPU (Web)
//
// WGSL port of stroke_compute.comp. Same algorithm:
// Catmull-Rom spline → tangent → perpendicular → triangle output.
// ═══════════════════════════════════════════════════════════════════

struct Params {
  colorR: f32,
  colorG: f32,
  colorB: f32,
  colorA: f32,
  strokeWidth: f32,
  pointCount: i32,
  brushType: i32,
  minPressure: f32,
  maxPressure: f32,
  pencilBaseOpacity: f32,
  pencilMaxOpacity: f32,
  subsPerSeg: i32,
  totalSubdivs: i32,
};

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> points: array<f32>;
@group(0) @binding(2) var<storage, read_write> verts: array<f32>;

// ─── Helpers ──────────────────────────────────────────────────────

fn getPoint(i: i32) -> vec2<f32> {
  return vec2<f32>(points[i * 5], points[i * 5 + 1]);
}

fn getPressure(i: i32) -> f32 {
  return points[i * 5 + 2];
}

fn catmullRom(p0: vec2<f32>, p1: vec2<f32>, p2: vec2<f32>, p3: vec2<f32>, t: f32) -> vec2<f32> {
  let t2 = t * t;
  let t3 = t2 * t;
  return 0.5 * ((2.0 * p1) +
                (-p0 + p2) * t +
                (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
                (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
}

fn catmullRomTangent(p0: vec2<f32>, p1: vec2<f32>, p2: vec2<f32>, p3: vec2<f32>, t: f32) -> vec2<f32> {
  let t2 = t * t;
  return 0.5 * ((-p0 + p2) +
                (4.0 * p0 - 10.0 * p1 + 8.0 * p2 - 2.0 * p3) * t +
                (-3.0 * p0 + 9.0 * p1 - 9.0 * p2 + 3.0 * p3) * t2);
}

fn computeHalfWidth(bt: i32, sw: f32, pressure: f32, gi: i32, minP: f32, maxP: f32) -> f32 {
  if (bt == 0) {
    return sw * (minP + 0.5 * (maxP - minP)) * 0.5;
  } else if (bt == 1) {
    return sw * 2.5 * 0.5;
  } else if (bt == 2) {
    var hw = sw * 0.5 * (minP + pressure * (maxP - minP));
    if (gi < 4) {
      let t = f32(gi) / 4.0;
      let ease = t * (2.0 - t);
      hw *= 0.15 + ease * 0.85;
    }
    return hw;
  }
  return sw * 0.5;
}

fn computeAlpha(bt: i32, base: f32, p: f32, pbo: f32, pmo: f32) -> f32 {
  if (bt == 2) {
    return base * (pbo + (pmo - pbo) * p);
  }
  return base;
}

fn writeVert(idx: i32, x: f32, y: f32, r: f32, g: f32, b: f32, a: f32) {
  let base = idx * 6;
  verts[base]     = x;
  verts[base + 1] = y;
  verts[base + 2] = r;
  verts[base + 3] = g;
  verts[base + 4] = b;
  verts[base + 5] = a;
}

// ═══════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════

@compute @workgroup_size(64)
fn computeMain(@builtin(global_invocation_id) gid: vec3<u32>) {
  let id = i32(gid.x);
  if (id >= params.totalSubdivs) { return; }

  let seg = id / params.subsPerSeg;
  let sub = id % params.subsPerSeg;
  let N = params.pointCount;
  if (seg >= N - 1) { return; }

  // Control points (clamped)
  let i0 = max(seg - 1, 0);
  let i1 = seg;
  let i2 = seg + 1;
  let i3 = min(seg + 2, N - 1);

  let p0 = getPoint(i0);
  let p1 = getPoint(i1);
  let p2 = getPoint(i2);
  let p3 = getPoint(i3);

  let t = f32(sub) / f32(params.subsPerSeg);
  let pos = catmullRom(p0, p1, p2, p3, t);
  var tan_v = catmullRomTangent(p0, p1, p2, p3, t);
  let tanLen = length(tan_v);
  if (tanLen < 0.0001) { tan_v = vec2<f32>(1.0, 0.0); }
  else { tan_v = tan_v / tanLen; }

  // Next sample
  var posNext: vec2<f32>;
  var tanNext: vec2<f32>;
  if (sub < params.subsPerSeg - 1) {
    let tN = f32(sub + 1) / f32(params.subsPerSeg);
    posNext = catmullRom(p0, p1, p2, p3, tN);
    tanNext = catmullRomTangent(p0, p1, p2, p3, tN);
  } else if (seg + 1 < N - 1) {
    let j0 = max(seg, 0);
    let j1 = seg + 1;
    let j2 = min(seg + 2, N - 1);
    let j3 = min(seg + 3, N - 1);
    posNext = catmullRom(getPoint(j0), getPoint(j1), getPoint(j2), getPoint(j3), 0.0);
    tanNext = catmullRomTangent(getPoint(j0), getPoint(j1), getPoint(j2), getPoint(j3), 0.0);
  } else {
    posNext = p2;
    tanNext = p2 - p1;
  }
  let tnl = length(tanNext);
  if (tnl < 0.0001) { tanNext = vec2<f32>(1.0, 0.0); }
  else { tanNext = tanNext / tnl; }

  let perp     = vec2<f32>(-tan_v.y, tan_v.x);
  let perpNext = vec2<f32>(-tanNext.y, tanNext.x);

  let pr1 = getPressure(i1);
  let pr2 = getPressure(i2);
  let pressure     = mix(pr1, pr2, t);
  let tNextVal = select(f32(sub + 1) / f32(params.subsPerSeg), 1.0, sub >= params.subsPerSeg - 1);
  let pressureNext = mix(pr1, pr2, tNextVal);

  let hw     = computeHalfWidth(params.brushType, params.strokeWidth, pressure, seg, params.minPressure, params.maxPressure);
  let segNext = select(seg, seg + 1, sub == params.subsPerSeg - 1);
  let hwNext = computeHalfWidth(params.brushType, params.strokeWidth, pressureNext, segNext, params.minPressure, params.maxPressure);

  let alpha     = computeAlpha(params.brushType, params.colorA, pressure, params.pencilBaseOpacity, params.pencilMaxOpacity);
  let alphaNext = computeAlpha(params.brushType, params.colorA, pressureNext, params.pencilBaseOpacity, params.pencilMaxOpacity);

  let left   = pos     + perp     * hw;
  let right  = pos     - perp     * hw;
  let leftN  = posNext + perpNext * hwNext;
  let rightN = posNext - perpNext * hwNext;

  let outBase = id * 6;
  // Triangle 1
  writeVert(outBase,     left.x,   left.y,   params.colorR, params.colorG, params.colorB, alpha);
  writeVert(outBase + 1, right.x,  right.y,  params.colorR, params.colorG, params.colorB, alpha);
  writeVert(outBase + 2, leftN.x,  leftN.y,  params.colorR, params.colorG, params.colorB, alphaNext);
  // Triangle 2
  writeVert(outBase + 3, right.x,  right.y,  params.colorR, params.colorG, params.colorB, alpha);
  writeVert(outBase + 4, leftN.x,  leftN.y,  params.colorR, params.colorG, params.colorB, alphaNext);
  writeVert(outBase + 5, rightN.x, rightN.y, params.colorR, params.colorG, params.colorB, alphaNext);
}
