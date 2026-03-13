// TransformShaders.metal — Compute shaders for Liquify, Smudge, and Warp
// These operate on rasterized textures, not geometry.

#include <metal_stdlib>
using namespace metal;

// =============================================================================
// LIQUIFY COMPUTE SHADER
//
// Reads a source texture + displacement field buffer.
// For each output pixel (x, y), looks up source at (x + dx, y + dy)
// with bilinear interpolation.
// =============================================================================

struct LiquifyParams {
    uint width;
    uint height;
    uint fieldWidth;
    uint fieldHeight;
};

/// Bilinear texture sample at fractional coordinates.
static float4 bilinearSample(texture2d<float, access::read> tex,
                              float fx, float fy,
                              uint w, uint h) {
    // Clamp to valid range
    fx = clamp(fx, 0.0f, float(w - 1));
    fy = clamp(fy, 0.0f, float(h - 1));

    uint x0 = uint(floor(fx));
    uint y0 = uint(floor(fy));
    uint x1 = min(x0 + 1, w - 1);
    uint y1 = min(y0 + 1, h - 1);

    float fracX = fx - float(x0);
    float fracY = fy - float(y0);

    float4 tl = tex.read(uint2(x0, y0));
    float4 tr = tex.read(uint2(x1, y0));
    float4 bl = tex.read(uint2(x0, y1));
    float4 br = tex.read(uint2(x1, y1));

    float4 top = mix(tl, tr, fracX);
    float4 bot = mix(bl, br, fracX);
    return mix(top, bot, fracY);
}

kernel void liquify_kernel(
    texture2d<float, access::read>  srcTexture  [[texture(0)]],
    texture2d<float, access::write> dstTexture  [[texture(1)]],
    device const float*             fieldData   [[buffer(0)]],
    constant LiquifyParams&         params      [[buffer(1)]],
    uint2                           gid         [[thread_position_in_grid]])
{
    if (gid.x >= params.width || gid.y >= params.height) return;

    // Map output pixel to displacement field coordinates
    float fieldX = float(gid.x) / float(params.width) * float(params.fieldWidth);
    float fieldY = float(gid.y) / float(params.height) * float(params.fieldHeight);

    // Bilinear sample the displacement field
    uint fx0 = uint(clamp(floor(fieldX), 0.0f, float(params.fieldWidth - 1)));
    uint fy0 = uint(clamp(floor(fieldY), 0.0f, float(params.fieldHeight - 1)));
    uint fx1 = min(fx0 + 1, params.fieldWidth - 1);
    uint fy1 = min(fy0 + 1, params.fieldHeight - 1);

    float fracX = fieldX - float(fx0);
    float fracY = fieldY - float(fy0);

    // Read displacement at 4 corners (interleaved dx, dy)
    uint i00 = (fy0 * params.fieldWidth + fx0) * 2;
    uint i10 = (fy0 * params.fieldWidth + fx1) * 2;
    uint i01 = (fy1 * params.fieldWidth + fx0) * 2;
    uint i11 = (fy1 * params.fieldWidth + fx1) * 2;

    float dx = mix(mix(fieldData[i00], fieldData[i10], fracX),
                   mix(fieldData[i01], fieldData[i11], fracX), fracY);
    float dy = mix(mix(fieldData[i00 + 1], fieldData[i10 + 1], fracX),
                   mix(fieldData[i01 + 1], fieldData[i11 + 1], fracX), fracY);

    // Scale displacement from field coords back to texture coords
    float srcX = float(gid.x) + dx * float(params.width) / float(params.fieldWidth);
    float srcY = float(gid.y) + dy * float(params.height) / float(params.fieldHeight);

    float4 color = bilinearSample(srcTexture, srcX, srcY,
                                   params.width, params.height);
    dstTexture.write(color, gid);
}

// =============================================================================
// SMUDGE COMPUTE SHADER
//
// Sequentially applies smudge samples along a path.
// Each sample blends the carried color with the texture color at that position,
// then deposits the blended result.
// =============================================================================

struct SmudgeSample {
    float x;       // Pixel position X
    float y;       // Pixel position Y
    float radius;  // Brush radius in pixels
    float strength; // Blend strength [0..1]
    float r, g, b, a; // Carried color
};

struct SmudgeParams {
    uint width;
    uint height;
    uint sampleCount;
};

kernel void smudge_kernel(
    texture2d<float, access::read_write> texture   [[texture(0)]],
    device const SmudgeSample*           samples   [[buffer(0)]],
    constant SmudgeParams&               params    [[buffer(1)]],
    uint2                                gid       [[thread_position_in_grid]])
{
    if (gid.x >= params.width || gid.y >= params.height) return;

    float4 texColor = texture.read(gid);
    float px = float(gid.x);
    float py = float(gid.y);

    // Apply each smudge sample
    for (uint i = 0; i < params.sampleCount; i++) {
        SmudgeSample s = samples[i];
        float dx = px - s.x;
        float dy = py - s.y;
        float dist2 = dx * dx + dy * dy;
        float r2 = s.radius * s.radius;

        if (dist2 > r2) continue;

        // Gaussian falloff
        float dist = sqrt(dist2);
        float falloff = 1.0 - (dist / s.radius);
        falloff = falloff * falloff; // Quadratic falloff for soft edges

        float blendAmount = s.strength * falloff;

        float4 smudgeColor = float4(s.r, s.g, s.b, s.a);
        texColor = mix(texColor, smudgeColor, blendAmount);
    }

    texture.write(texColor, gid);
}

// =============================================================================
// WARP COMPUTE SHADER
//
// Reads a source texture + mesh control points buffer.
// For each output pixel, determines which mesh cell it falls in,
// computes UV via inverse bilinear interpolation, and samples the source.
// =============================================================================

struct WarpMeshPoint {
    float origX, origY;     // Original position
    float dispX, dispY;     // Displaced position
};

struct WarpParams {
    uint width;
    uint height;
    uint meshCols;
    uint meshRows;
    float boundsLeft;
    float boundsTop;
    float boundsWidth;
    float boundsHeight;
};

/// Inverse bilinear interpolation: find (u, v) such that
/// P = lerp(lerp(TL, TR, u), lerp(BL, BR, u), v)
static float2 inverseBilinear(float2 p, float2 tl, float2 tr,
                                float2 bl, float2 br) {
    float u = 0.5, v = 0.5;

    for (int iter = 0; iter < 8; iter++) {
        float2 top = mix(tl, tr, u);
        float2 bot = mix(bl, br, u);
        float2 f = mix(top, bot, v) - p;

        if (length(f) < 0.001) break;

        // Jacobian
        float2 dFdu = (1.0 - v) * (tr - tl) + v * (br - bl);
        float2 dFdv = (1.0 - u) * (bl - tl) + u * (br - tr);

        float det = dFdu.x * dFdv.y - dFdu.y * dFdv.x;
        if (abs(det) < 1e-10) break;

        float invDet = 1.0 / det;
        u -= (dFdv.y * f.x - dFdv.x * f.y) * invDet;
        v -= (dFdu.x * f.y - dFdu.y * f.x) * invDet;
    }

    return float2(clamp(u, 0.0f, 1.0f), clamp(v, 0.0f, 1.0f));
}

kernel void warp_kernel(
    texture2d<float, access::read>  srcTexture  [[texture(0)]],
    texture2d<float, access::write> dstTexture  [[texture(1)]],
    device const WarpMeshPoint*     meshPoints  [[buffer(0)]],
    constant WarpParams&            params      [[buffer(1)]],
    uint2                           gid         [[thread_position_in_grid]])
{
    if (gid.x >= params.width || gid.y >= params.height) return;

    // Convert pixel to canvas coordinates
    float canvasX = params.boundsLeft + float(gid.x) / float(params.width) * params.boundsWidth;
    float canvasY = params.boundsTop + float(gid.y) / float(params.height) * params.boundsHeight;
    float2 p = float2(canvasX, canvasY);

    // Find which mesh cell this pixel falls in
    float4 resultColor = float4(0.0);
    bool found = false;

    for (uint row = 0; row < params.meshRows - 1 && !found; row++) {
        for (uint col = 0; col < params.meshCols - 1 && !found; col++) {
            uint i_tl = row * params.meshCols + col;
            uint i_tr = row * params.meshCols + col + 1;
            uint i_bl = (row + 1) * params.meshCols + col;
            uint i_br = (row + 1) * params.meshCols + col + 1;

            float2 tl = float2(meshPoints[i_tl].dispX, meshPoints[i_tl].dispY);
            float2 tr = float2(meshPoints[i_tr].dispX, meshPoints[i_tr].dispY);
            float2 bl = float2(meshPoints[i_bl].dispX, meshPoints[i_bl].dispY);
            float2 br = float2(meshPoints[i_br].dispX, meshPoints[i_br].dispY);

            // Quick AABB check
            float minX = min(min(tl.x, tr.x), min(bl.x, br.x));
            float maxX = max(max(tl.x, tr.x), max(bl.x, br.x));
            float minY = min(min(tl.y, tr.y), min(bl.y, br.y));
            float maxY = max(max(tl.y, tr.y), max(bl.y, br.y));

            if (p.x < minX || p.x > maxX || p.y < minY || p.y > maxY) continue;

            // Inverse bilinear interpolation
            float2 uv = inverseBilinear(p, tl, tr, bl, br);

            // Check if uv is valid (inside the cell)
            if (uv.x >= -0.01 && uv.x <= 1.01 && uv.y >= -0.01 && uv.y <= 1.01) {
                // Map cell-local UV to global texture UV
                float globalU = (float(col) + uv.x) / float(params.meshCols - 1);
                float globalV = (float(row) + uv.y) / float(params.meshRows - 1);

                // Sample source texture
                float srcX = globalU * float(params.width);
                float srcY = globalV * float(params.height);

                resultColor = bilinearSample(srcTexture, srcX, srcY,
                                              params.width, params.height);
                found = true;
            }
        }
    }

    dstTexture.write(found ? resultColor : float4(0.0), gid);
}
