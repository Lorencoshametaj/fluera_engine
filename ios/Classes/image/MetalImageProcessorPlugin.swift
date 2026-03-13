import Flutter
import UIKit
import Metal
import MetalKit
import CoreVideo

/// 🎨 MetalImageProcessorPlugin — GPU Image Filter Pipeline (iOS)
///
/// Real-time GPU color grading, blur, sharpen, vignette, and mipmapping.
/// Uses CVPixelBuffer → MTLTexture zero-copy for FlutterTexture integration.
///
/// Channel: com.flueraengine/native_image_processor
public class MetalImageProcessorPlugin: NSObject, FlutterPlugin {
    
    // MARK: - Metal State
    
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var cvMetalTextureCache: CVMetalTextureCache?
    
    // Shader pipelines
    private var colorGradingPipeline: MTLRenderPipelineState?
    private var blurHPipeline: MTLRenderPipelineState?
    private var blurVPipeline: MTLRenderPipelineState?
    private var sharpenPipeline: MTLRenderPipelineState?
    private var edgeDetectPipeline: MTLRenderPipelineState?
    private var histogramPipeline: MTLComputePipelineState?
    private var hslPerChannelPipeline: MTLRenderPipelineState?
    private var bilateralDenoisePipeline: MTLRenderPipelineState?
    private var toneCurvePipeline: MTLRenderPipelineState?
    private var clarityPipeline: MTLRenderPipelineState?
    private var splitToningPipeline: MTLRenderPipelineState?
    private var filmGrainPipeline: MTLRenderPipelineState?
    
    // Sampler states
    private var linearSampler: MTLSamplerState?
    private var mipmapSampler: MTLSamplerState?
    
    // MARK: - Flutter Integration
    
    private var textureRegistry: FlutterTextureRegistry?
    
    /// Per-image GPU state
    private var imageStates: [String: GPUImageState] = [:]
    
    // MARK: - Plugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.flueraengine/native_image_processor",
            binaryMessenger: registrar.messenger()
        )
        let instance = MetalImageProcessorPlugin()
        instance.textureRegistry = registrar.textures()
        channel.setMethodCallHandler(instance.handle)
    }
    
    // MARK: - Metal Initialization
    
    private func initMetal() -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return false
        }
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.cvMetalTextureCache = cache
        
        // Build sampler states
        buildSamplers()
        
        // Build all shader pipelines
        return buildPipelines()
    }
    
    // MARK: - Sampler States
    
    private func buildSamplers() {
        guard let device = device else { return }
        
        // Linear sampler for standard texture reads
        let linearDesc = MTLSamplerDescriptor()
        linearDesc.minFilter = .linear
        linearDesc.magFilter = .linear
        linearDesc.mipFilter = .notMipmapped
        linearDesc.sAddressMode = .clampToEdge
        linearDesc.tAddressMode = .clampToEdge
        linearSampler = device.makeSamplerState(descriptor: linearDesc)
        
        // Trilinear + anisotropic sampler for mipmapped textures
        let mipDesc = MTLSamplerDescriptor()
        mipDesc.minFilter = .linear
        mipDesc.magFilter = .linear
        mipDesc.mipFilter = .linear
        mipDesc.maxAnisotropy = 8
        mipDesc.sAddressMode = .clampToEdge
        mipDesc.tAddressMode = .clampToEdge
        mipmapSampler = device.makeSamplerState(descriptor: mipDesc)
    }
    
    // MARK: - Shader Pipeline Construction
    
    private func buildPipelines() -> Bool {
        guard let device = device else { return false }
        
        // Unified Metal shader source
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        // ─── Common vertex shader (fullscreen quad) ───────────────────
        
        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };
        
        vertex VertexOut fullscreenVertex(uint vertexId [[vertex_id]]) {
            // 6 vertices for fullscreen quad
            constant float2 positions[6] = {
                float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
                float2(-1.0,  1.0), float2(1.0, -1.0), float2(1.0,  1.0)
            };
            constant float2 uvs[6] = {
                float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0),
                float2(0.0, 0.0), float2(1.0, 1.0), float2(1.0, 0.0)
            };
            
            VertexOut out;
            out.position = float4(positions[vertexId], 0.0, 1.0);
            out.uv = uvs[vertexId];
            return out;
        }
        
        // ─── Color Grading Fragment Shader ────────────────────────────
        //
        // Combined: brightness, contrast, saturation, hue, temperature,
        //           vignette, opacity — all in one pass.
        
        struct ColorGradingParams {
            float brightness;   // -1..+1
            float contrast;     // -1..+1
            float saturation;   // -1..+1
            float hueShift;     // -1..+1 (maps to -π..+π)
            float temperature;  // -1..+1
            float opacity;      // 0..1
            float vignette;     // 0..1
            float _pad;         // alignment
        };
        
        fragment float4 colorGradingFragment(
            VertexOut in [[stage_in]],
            texture2d<float> srcTexture [[texture(0)]],
            sampler srcSampler [[sampler(0)]],
            constant ColorGradingParams &params [[buffer(0)]]
        ) {
            float4 color = srcTexture.sample(srcSampler, in.uv);
            
            // Brightness
            color.rgb += params.brightness;
            
            // Contrast
            float c = params.contrast + 1.0;
            color.rgb = (color.rgb - 0.5) * c + 0.5;
            
            // Saturation
            float s = params.saturation + 1.0;
            float luminance = dot(color.rgb, float3(0.3086, 0.6094, 0.0820));
            color.rgb = mix(float3(luminance), color.rgb, s);
            
            // Hue rotation (Rodrigues' formula in RGB space)
            if (abs(params.hueShift) > 0.001) {
                float angle = params.hueShift * 3.14159265;
                float cosA = cos(angle);
                float sinA = sin(angle);
                float k = 1.0 / 3.0;
                float sq = 0.57735; // 1/sqrt(3)
                
                float3x3 hueMatrix = float3x3(
                    float3(cosA + (1.0 - cosA) * k,
                           k * (1.0 - cosA) - sq * sinA,
                           k * (1.0 - cosA) + sq * sinA),
                    float3(k * (1.0 - cosA) + sq * sinA,
                           cosA + (1.0 - cosA) * k,
                           k * (1.0 - cosA) - sq * sinA),
                    float3(k * (1.0 - cosA) - sq * sinA,
                           k * (1.0 - cosA) + sq * sinA,
                           cosA + (1.0 - cosA) * k)
                );
                color.rgb = hueMatrix * color.rgb;
            }
            
            // Temperature (warm = +red +green*0.4 -blue, cool = inverse)
            if (abs(params.temperature) > 0.001) {
                float temp = params.temperature * 0.12; // subtle effect
                color.r += temp;
                color.g += temp * 0.4;
                color.b -= temp;
            }
            
            // Vignette (radial darkening)
            if (params.vignette > 0.001) {
                float2 center = in.uv - 0.5;
                float dist = length(center) * 1.414; // normalize to 0..1 at corners
                float vig = smoothstep(0.3, 1.0, dist);
                color.rgb *= 1.0 - vig * params.vignette * 0.7;
            }
            
            // Opacity
            color.a *= params.opacity;
            
            // Clamp
            color = clamp(color, 0.0, 1.0);
            
            return color;
        }
        
        // ─── Gaussian Blur (Horizontal) ───────────────────────────────
        
        struct BlurParams {
            float texelSize;  // 1.0 / texture_width or height
            float radius;     // blur radius in pixels
            float sigma;      // gaussian sigma
            float _pad;
        };
        
        // 9-tap Gaussian kernel with dynamic sigma
        float gaussianWeight(float x, float sigma) {
            return exp(-(x * x) / (2.0 * sigma * sigma));
        }
        
        fragment float4 blurHFragment(
            VertexOut in [[stage_in]],
            texture2d<float> srcTexture [[texture(0)]],
            sampler srcSampler [[sampler(0)]],
            constant BlurParams &params [[buffer(0)]]
        ) {
            float4 result = float4(0.0);
            float totalWeight = 0.0;
            
            int taps = min(int(params.radius), 32);
            float sigma = max(params.sigma, 0.5);
            
            for (int i = -taps; i <= taps; i++) {
                float weight = gaussianWeight(float(i), sigma);
                float2 offset = float2(float(i) * params.texelSize, 0.0);
                result += srcTexture.sample(srcSampler, in.uv + offset) * weight;
                totalWeight += weight;
            }
            
            return result / totalWeight;
        }
        
        // ─── Gaussian Blur (Vertical) ─────────────────────────────────
        
        fragment float4 blurVFragment(
            VertexOut in [[stage_in]],
            texture2d<float> srcTexture [[texture(0)]],
            sampler srcSampler [[sampler(0)]],
            constant BlurParams &params [[buffer(0)]]
        ) {
            float4 result = float4(0.0);
            float totalWeight = 0.0;
            
            int taps = min(int(params.radius), 32);
            float sigma = max(params.sigma, 0.5);
            
            for (int i = -taps; i <= taps; i++) {
                float weight = gaussianWeight(float(i), sigma);
                float2 offset = float2(0.0, float(i) * params.texelSize);
                result += srcTexture.sample(srcSampler, in.uv + offset) * weight;
                totalWeight += weight;
            }
            
            return result / totalWeight;
        }
        
        // ─── Unsharp Mask (Sharpen) ───────────────────────────────────
        
        struct SharpenParams {
            float texelSizeX;
            float texelSizeY;
            float amount;      // 0..2
            float _pad;
        };
        
        fragment float4 sharpenFragment(
            VertexOut in [[stage_in]],
            texture2d<float> srcTexture [[texture(0)]],
            texture2d<float> blurTexture [[texture(1)]],
            sampler srcSampler [[sampler(0)]],
            constant SharpenParams &params [[buffer(0)]]
        ) {
            float4 original = srcTexture.sample(srcSampler, in.uv);
            float4 blurred = blurTexture.sample(srcSampler, in.uv);
            
            // Unsharp mask: original + amount * (original - blurred)
            float4 result = original + params.amount * (original - blurred);
            return clamp(result, 0.0, 1.0);
        }
        
        // ─── Sobel Edge Detection ─────────────────────────────────────
        
        struct EdgeDetectParams {
            float texelSizeX;
            float texelSizeY;
            float strength;    // 0..1
            float invert;      // 0 or 1
        };
        
        fragment float4 edgeDetectFragment(
            VertexOut in [[stage_in]],
            texture2d<float> srcTexture [[texture(0)]],
            sampler srcSampler [[sampler(0)]],
            constant EdgeDetectParams &params [[buffer(0)]]
        ) {
            float2 ts = float2(params.texelSizeX, params.texelSizeY);
            
            // Sample 3×3 neighborhood luminance
            float tl = dot(srcTexture.sample(srcSampler, in.uv + float2(-ts.x,  ts.y)).rgb, float3(0.299, 0.587, 0.114));
            float tm = dot(srcTexture.sample(srcSampler, in.uv + float2( 0.0,   ts.y)).rgb, float3(0.299, 0.587, 0.114));
            float tr = dot(srcTexture.sample(srcSampler, in.uv + float2( ts.x,  ts.y)).rgb, float3(0.299, 0.587, 0.114));
            float ml = dot(srcTexture.sample(srcSampler, in.uv + float2(-ts.x,  0.0 )).rgb, float3(0.299, 0.587, 0.114));
            float mr = dot(srcTexture.sample(srcSampler, in.uv + float2( ts.x,  0.0 )).rgb, float3(0.299, 0.587, 0.114));
            float bl = dot(srcTexture.sample(srcSampler, in.uv + float2(-ts.x, -ts.y)).rgb, float3(0.299, 0.587, 0.114));
            float bm = dot(srcTexture.sample(srcSampler, in.uv + float2( 0.0,  -ts.y)).rgb, float3(0.299, 0.587, 0.114));
            float br = dot(srcTexture.sample(srcSampler, in.uv + float2( ts.x, -ts.y)).rgb, float3(0.299, 0.587, 0.114));
            
            float gx = -tl - 2.0*ml - bl + tr + 2.0*mr + br;
            float gy = -tl - 2.0*tm - tr + bl + 2.0*bm + br;
            float edge = clamp(sqrt(gx * gx + gy * gy) * 2.0, 0.0, 1.0);
            
            if (params.invert > 0.5) { edge = 1.0 - edge; }
            
            float4 original = srcTexture.sample(srcSampler, in.uv);
            return float4(mix(original.rgb, float3(edge), params.strength), original.a);
        }
        
        // ─── Histogram Compute Kernel ─────────────────────────────────
        
        kernel void histogramKernel(
            texture2d<float, access::read> srcTexture [[texture(0)]],
            device atomic_uint* histogram [[buffer(0)]],
            uint2 gid [[thread_position_in_grid]]
        ) {
            if (gid.x >= srcTexture.get_width() || gid.y >= srcTexture.get_height()) return;
            
            float4 color = srcTexture.read(gid);
            uint r = uint(clamp(color.r, 0.0f, 1.0f) * 255.0);
            uint g = uint(clamp(color.g, 0.0f, 1.0f) * 255.0);
            uint b = uint(clamp(color.b, 0.0f, 1.0f) * 255.0);
            
            atomic_fetch_add_explicit(&histogram[r],       1, memory_order_relaxed);
            atomic_fetch_add_explicit(&histogram[256 + g], 1, memory_order_relaxed);
            atomic_fetch_add_explicit(&histogram[512 + b], 1, memory_order_relaxed);
        }
        
        // ─── HSL Per-Channel Fragment Shader ──────────────────────────
        //
        // True per-pixel RGB→HSL→adjust→HSL→RGB with 7 color bands.
        // Cannot be approximated by a 5×4 color matrix.
        
        struct HslParams {
            float adj[24]; // 7 bands × 3 (hue,sat,light) + padding
        };
        
        float3 rgb2hsl_metal(float3 c) {
            float maxC = max(c.r, max(c.g, c.b));
            float minC = min(c.r, min(c.g, c.b));
            float l = (maxC + minC) * 0.5;
            float d = maxC - minC;
            if (d < 0.00001) return float3(0.0, 0.0, l);
            float s = (l > 0.5) ? d / (2.0 - maxC - minC) : d / (maxC + minC);
            float h;
            if (maxC == c.r)      h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
            else if (maxC == c.g) h = (c.b - c.r) / d + 2.0;
            else                  h = (c.r - c.g) / d + 4.0;
            return float3(h / 6.0, s, l);
        }
        
        float hue2rgb_metal(float p, float q, float t) {
            if (t < 0.0) t += 1.0;
            if (t > 1.0) t -= 1.0;
            if (t < 1.0/6.0) return p + (q - p) * 6.0 * t;
            if (t < 0.5)     return q;
            if (t < 2.0/3.0) return p + (q - p) * (2.0/3.0 - t) * 6.0;
            return p;
        }
        
        float3 hsl2rgb_metal(float3 hsl) {
            if (hsl.y < 0.00001) return float3(hsl.z);
            float q = (hsl.z < 0.5) ? hsl.z * (1.0 + hsl.y) : hsl.z + hsl.y - hsl.z * hsl.y;
            float p = 2.0 * hsl.z - q;
            return float3(
                hue2rgb_metal(p, q, hsl.x + 1.0/3.0),
                hue2rgb_metal(p, q, hsl.x),
                hue2rgb_metal(p, q, hsl.x - 1.0/3.0)
            );
        }
        
        float bandWeight_metal(float hue, int band) {
            float center = float(band) / 7.0;
            float dist = abs(hue - center);
            dist = min(dist, 1.0 - dist);
            return clamp(1.0 - dist / (1.0/7.0), 0.0, 1.0);
        }
        
        fragment float4 hslPerChannelFragment(
            VertexOut in [[stage_in]],
            texture2d<float> srcTexture [[texture(0)]],
            sampler srcSampler [[sampler(0)]],
            constant HslParams &params [[buffer(0)]]
        ) {
            float4 pixel = srcTexture.sample(srcSampler, in.uv);
            float3 hsl = rgb2hsl_metal(pixel.rgb);
            float dH = 0.0, dS = 0.0, dL = 0.0, totalW = 0.0;
            for (int i = 0; i < 7; i++) {
                float w = bandWeight_metal(hsl.x, i);
                if (w > 0.0) {
                    dH += w * params.adj[i*3+0];
                    dS += w * params.adj[i*3+1];
                    dL += w * params.adj[i*3+2];
                    totalW += w;
                }
            }
            if (totalW > 0.0) {
                float inv = 1.0 / totalW;
                hsl.x = fract(hsl.x + dH * inv);
                hsl.y = clamp(hsl.y + dS * inv, 0.0, 1.0);
                hsl.z = clamp(hsl.z + dL * inv, 0.0, 1.0);
            }
            return float4(hsl2rgb_metal(hsl), pixel.a);
        }
        
        // ─── Bilateral Denoise Fragment Shader ────────────────────────
        
        struct BilateralParams {
            float texelSizeX;
            float texelSizeY;
            float strength;
            float rangeSigma;
        };
        
        fragment float4 bilateralDenoiseFragment(
            VertexOut in [[stage_in]],
            texture2d<float> srcTexture [[texture(0)]],
            sampler srcSampler [[sampler(0)]],
            constant BilateralParams &params [[buffer(0)]]
        ) {
            float4 center = srcTexture.sample(srcSampler, in.uv);
            float3 result = float3(0.0);
            float totalWeight = 0.0;
            float sigmaSpatial = max(1.0f, params.strength * 4.0f);
            float sigmaRange = max(0.01f, params.rangeSigma);
            float invSpatial2 = -0.5 / (sigmaSpatial * sigmaSpatial);
            float invRange2 = -0.5 / (sigmaRange * sigmaRange);
            for (int dy = -4; dy <= 4; dy++) {
                for (int dx = -4; dx <= 4; dx++) {
                    float2 offset = float2(float(dx) * params.texelSizeX,
                                           float(dy) * params.texelSizeY);
                    float4 s = srcTexture.sample(srcSampler, in.uv + offset);
                    float dist2 = float(dx*dx + dy*dy);
                    float wSpatial = exp(dist2 * invSpatial2);
                    float3 diff = s.rgb - center.rgb;
                    float wRange = exp(dot(diff, diff) * invRange2);
                    float w = wSpatial * wRange;
                    result += s.rgb * w;
                    totalWeight += w;
                }
            }
            return float4(result / totalWeight, center.a);
        }
        
        // ─── Tone Curve Fragment Shader ────────────────────────────
        
        struct ToneCurveParams {
            float4 masterPts[2];
            float4 redPts[2];
            float4 greenPts[2];
            float4 bluePts[2];
        };
        
        float evalCurve_metal(float4 pts0, float4 pts1, float t) {
            float x0 = pts0.x, y0 = pts0.y;
            float x1 = pts0.z, y1 = pts0.w;
            float x2 = pts1.x, y2 = pts1.y;
            float x3 = pts1.z, y3 = pts1.w;
            if (t <= x1) {
                float f = (x1 > x0) ? (t - x0) / (x1 - x0) : 0.0;
                return mix(y0, y1, smoothstep(0.0f, 1.0f, f));
            } else if (t <= x2) {
                float f = (x2 > x1) ? (t - x1) / (x2 - x1) : 0.0;
                return mix(y1, y2, smoothstep(0.0f, 1.0f, f));
            } else {
                float f = (x3 > x2) ? (t - x2) / (x3 - x2) : 0.0;
                return mix(y2, y3, smoothstep(0.0f, 1.0f, f));
            }
        }
        
        fragment float4 toneCurveFragment(
            VertexOut in [[stage_in]],
            texture2d<float> srcTexture [[texture(0)]],
            sampler srcSampler [[sampler(0)]],
            constant ToneCurveParams &params [[buffer(0)]]
        ) {
            float4 pixel = srcTexture.sample(srcSampler, in.uv);
            float mr = evalCurve_metal(params.masterPts[0], params.masterPts[1], pixel.r);
            float mg = evalCurve_metal(params.masterPts[0], params.masterPts[1], pixel.g);
            float mb = evalCurve_metal(params.masterPts[0], params.masterPts[1], pixel.b);
            float r = evalCurve_metal(params.redPts[0],   params.redPts[1],   mr);
            float g = evalCurve_metal(params.greenPts[0], params.greenPts[1], mg);
            float b = evalCurve_metal(params.bluePts[0],  params.bluePts[1],  mb);
            return float4(r, g, b, pixel.a);
        }
        
        // ─── Clarity Fragment Shader ───────────────────────────────
        
        struct ClarityParams {
            float texelSizeX;
            float texelSizeY;
            float clarity;
            float texturePower;
        };
        
        float3 localMean_metal(texture2d<float> tex, sampler s, float2 uv, float2 ts, float radius) {
            float3 sum = float3(0.0);
            float total = 0.0;
            for (int y = -2; y <= 2; y++) {
                for (int x = -2; x <= 2; x++) {
                    float w = exp(-0.5 * float(x*x + y*y) / 4.0);
                    sum += tex.sample(s, uv + float2(float(x), float(y)) * ts * radius).rgb * w;
                    total += w;
                }
            }
            return sum / total;
        }
        
        fragment float4 clarityFragment(
            VertexOut in [[stage_in]],
            texture2d<float> srcTexture [[texture(0)]],
            sampler srcSampler [[sampler(0)]],
            constant ClarityParams &params [[buffer(0)]]
        ) {
            float4 pixel = srcTexture.sample(srcSampler, in.uv);
            float3 color = pixel.rgb;
            float2 ts = float2(params.texelSizeX, params.texelSizeY);
            if (abs(params.clarity) > 0.001) {
                float3 blurLarge = localMean_metal(srcTexture, srcSampler, in.uv, ts, 3.0);
                color += (color - blurLarge) * params.clarity * 2.0;
            }
            if (abs(params.texturePower) > 0.001) {
                float3 blurSmall = localMean_metal(srcTexture, srcSampler, in.uv, ts, 1.0);
                color += (color - blurSmall) * params.texturePower * 1.5;
            }
            return float4(clamp(color, 0.0, 1.0), pixel.a);
        }
        
        // ─── Split Toning Fragment Shader ──────────────────────────
        
        struct SplitToningParams {
            float4 highlightColor;
            float4 shadowColor;
            float balance;
            float pad0;
            float pad1;
            float pad2;
        };
        
        fragment float4 splitToningFragment(
            VertexOut in [[stage_in]],
            texture2d<float> srcTexture [[texture(0)]],
            sampler srcSampler [[sampler(0)]],
            constant SplitToningParams &params [[buffer(0)]]
        ) {
            float4 pixel = srcTexture.sample(srcSampler, in.uv);
            float lum = dot(pixel.rgb, float3(0.2126, 0.7152, 0.0722));
            float midpoint = 0.5 + params.balance * 0.25;
            float shadowW = 1.0 - smoothstep(0.0f, midpoint, lum);
            float highlightW = smoothstep(midpoint, 1.0f, lum);
            float3 shadowTint = mix(pixel.rgb, params.shadowColor.rgb * lum, params.shadowColor.a * shadowW);
            float3 highlightTint = mix(pixel.rgb, params.highlightColor.rgb * lum + pixel.rgb * (1.0 - lum), params.highlightColor.a * highlightW);
            float3 result = mix(shadowTint, highlightTint, lum);
            float midtonePreserve = 1.0 - shadowW - highlightW;
            result = mix(result, pixel.rgb, clamp(midtonePreserve, 0.0f, 1.0f));
            return float4(result, pixel.a);
        }
        
        // ─── Film Grain Fragment Shader ────────────────────────────
        
        struct FilmGrainParams {
            float intensity;
            float size;
            float seed;
            float luminanceResponse;
        };
        
        float hash12_metal(float2 p) {
            float3 p3 = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973));
            p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
            return fract((p3.x + p3.y) * p3.z);
        }
        
        fragment float4 filmGrainFragment(
            VertexOut in [[stage_in]],
            texture2d<float> srcTexture [[texture(0)]],
            sampler srcSampler [[sampler(0)]],
            constant FilmGrainParams &params [[buffer(0)]]
        ) {
            float4 pixel = srcTexture.sample(srcSampler, in.uv);
            float2 p = floor(in.uv / max(params.size * 0.002, 0.001f));
            float noise = hash12_metal(p + float2(params.seed * 127.1, params.seed * 311.7)) * 2.0 - 1.0;
            float lum = dot(pixel.rgb, float3(0.2126, 0.7152, 0.0722));
            float lumFactor = mix(1.0f, 4.0 * lum * (1.0 - lum), params.luminanceResponse);
            float3 grained = pixel.rgb + noise * params.intensity * 0.15 * lumFactor;
            return float4(clamp(grained, 0.0, 1.0), pixel.a);
        }
        """
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            
            // ─── Color Grading Pipeline ───────────────────────────────
            let cgDesc = MTLRenderPipelineDescriptor()
            cgDesc.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            cgDesc.fragmentFunction = library.makeFunction(name: "colorGradingFragment")
            cgDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            colorGradingPipeline = try device.makeRenderPipelineState(descriptor: cgDesc)
            
            // ─── Blur H Pipeline ──────────────────────────────────────
            let bhDesc = MTLRenderPipelineDescriptor()
            bhDesc.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            bhDesc.fragmentFunction = library.makeFunction(name: "blurHFragment")
            bhDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            blurHPipeline = try device.makeRenderPipelineState(descriptor: bhDesc)
            
            // ─── Blur V Pipeline ──────────────────────────────────────
            let bvDesc = MTLRenderPipelineDescriptor()
            bvDesc.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            bvDesc.fragmentFunction = library.makeFunction(name: "blurVFragment")
            bvDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            blurVPipeline = try device.makeRenderPipelineState(descriptor: bvDesc)
            
            // ─── Sharpen Pipeline ─────────────────────────────────────
            let shDesc = MTLRenderPipelineDescriptor()
            shDesc.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            shDesc.fragmentFunction = library.makeFunction(name: "sharpenFragment")
            shDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            sharpenPipeline = try device.makeRenderPipelineState(descriptor: shDesc)
            
            // ─── Edge Detect Pipeline ─────────────────────────────────
            let edDesc = MTLRenderPipelineDescriptor()
            edDesc.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            edDesc.fragmentFunction = library.makeFunction(name: "edgeDetectFragment")
            edDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            edgeDetectPipeline = try device.makeRenderPipelineState(descriptor: edDesc)
            
            // ─── Histogram Compute Pipeline ───────────────────────────
            if let histFunc = library.makeFunction(name: "histogramKernel") {
                histogramPipeline = try device.makeComputePipelineState(function: histFunc)
            }
            
            // ─── HSL Per-Channel Pipeline ─────────────────────────────
            let hslDesc = MTLRenderPipelineDescriptor()
            hslDesc.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            hslDesc.fragmentFunction = library.makeFunction(name: "hslPerChannelFragment")
            hslDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            hslPerChannelPipeline = try device.makeRenderPipelineState(descriptor: hslDesc)
            
            // ─── Bilateral Denoise Pipeline ───────────────────────────
            let bdDesc = MTLRenderPipelineDescriptor()
            bdDesc.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            bdDesc.fragmentFunction = library.makeFunction(name: "bilateralDenoiseFragment")
            bdDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            bilateralDenoisePipeline = try device.makeRenderPipelineState(descriptor: bdDesc)
            
            // ─── Tone Curve Pipeline ──────────────────────────────────
            let tcDesc = MTLRenderPipelineDescriptor()
            tcDesc.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            tcDesc.fragmentFunction = library.makeFunction(name: "toneCurveFragment")
            tcDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            toneCurvePipeline = try device.makeRenderPipelineState(descriptor: tcDesc)
            
            // ─── Clarity Pipeline ─────────────────────────────────────
            let clDesc = MTLRenderPipelineDescriptor()
            clDesc.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            clDesc.fragmentFunction = library.makeFunction(name: "clarityFragment")
            clDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            clarityPipeline = try device.makeRenderPipelineState(descriptor: clDesc)
            
            // ─── Split Toning Pipeline ────────────────────────────────
            let stDesc = MTLRenderPipelineDescriptor()
            stDesc.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            stDesc.fragmentFunction = library.makeFunction(name: "splitToningFragment")
            stDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            splitToningPipeline = try device.makeRenderPipelineState(descriptor: stDesc)
            
            // ─── Film Grain Pipeline ──────────────────────────────────
            let fgDesc = MTLRenderPipelineDescriptor()
            fgDesc.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            fgDesc.fragmentFunction = library.makeFunction(name: "filmGrainFragment")
            fgDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            filmGrainPipeline = try device.makeRenderPipelineState(descriptor: fgDesc)
            
            return true
            
        } catch {
            print("⚠️ MetalImageProcessor: shader compilation failed: \(error)")
            return false
        }
    }
    
    // MARK: - Per-Image GPU State
    
    private class GPUImageState: FlutterTexture {
        let device: MTLDevice
        let width: Int
        let height: Int
        
        // Source image (immutable — the original uploaded image)
        var sourceTexture: MTLTexture?
        
        // Output texture (result of filter chain)
        var outputTexture: MTLTexture?
        var outputPixelBuffer: CVPixelBuffer?
        var outputCVMetalTexture: CVMetalTexture?
        
        // Ping-pong textures for multi-pass effects (blur H→V)
        var pingTexture: MTLTexture?
        var pingPixelBuffer: CVPixelBuffer?
        var pingCVMetalTexture: CVMetalTexture?
        
        // Flutter texture ID
        var textureId: Int64 = -1
        
        init(device: MTLDevice, width: Int, height: Int) {
            self.device = device
            self.width = width
            self.height = height
        }
        
        func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
            guard let pb = outputPixelBuffer else { return nil }
            return Unmanaged.passRetained(pb)
        }
    }
    
    private func createGPUImageState(
        width: Int,
        height: Int,
        cache: CVMetalTextureCache
    ) -> GPUImageState? {
        guard let device = device else { return nil }
        
        let state = GPUImageState(device: device, width: width, height: height)
        
        // Create output render target (CVPixelBuffer-backed for FlutterTexture)
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        
        // Output texture
        var outputPB: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &outputPB)
        state.outputPixelBuffer = outputPB
        
        if let pb = outputPB {
            var cvTex: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(
                nil, cache, pb, nil, .bgra8Unorm, width, height, 0, &cvTex
            )
            state.outputCVMetalTexture = cvTex
            if let cv = cvTex {
                state.outputTexture = CVMetalTextureGetTexture(cv)
            }
        }
        
        // Ping texture (for blur ping-pong)
        var pingPB: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pingPB)
        state.pingPixelBuffer = pingPB
        
        if let pb = pingPB {
            var cvTex: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(
                nil, cache, pb, nil, .bgra8Unorm, width, height, 0, &cvTex
            )
            state.pingCVMetalTexture = cvTex
            if let cv = cvTex {
                state.pingTexture = CVMetalTextureGetTexture(cv)
            }
        }
        
        // Source texture (DEVICE_LOCAL — immutable original)
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: true  // Enable mipmap storage
        )
        texDesc.usage = [.shaderRead, .renderTarget]
        texDesc.storageMode = .shared  // iOS uses unified memory
        state.sourceTexture = device.makeTexture(descriptor: texDesc)
        
        return state
    }
    
    // MARK: - Rendering
    
    private func renderColorGrading(
        state: GPUImageState,
        params: ColorGradingParams,
        sourceTexture: MTLTexture,
        destTexture: MTLTexture
    ) -> Bool {
        guard let commandQueue = commandQueue,
              let pipeline = colorGradingPipeline,
              let sampler = linearSampler else { return false }
        
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = destTexture
        passDesc.colorAttachments[0].loadAction = .dontCare
        passDesc.colorAttachments[0].storeAction = .store
        
        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            return false
        }
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        
        var uniforms = params
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ColorGradingParams>.stride, index: 0)
        
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        return true
    }
    
    private func renderBlur(
        state: GPUImageState,
        radius: Float,
        sourceTexture: MTLTexture,
        destTexture: MTLTexture,
        pingTexture: MTLTexture
    ) -> Bool {
        guard let commandQueue = commandQueue,
              let blurH = blurHPipeline,
              let blurV = blurVPipeline,
              let sampler = linearSampler else { return false }
        
        let sigma = radius / 3.0
        let w = Float(state.width)
        let h = Float(state.height)
        
        // Pass 1: Horizontal blur (source → ping)
        do {
            let passDesc = MTLRenderPassDescriptor()
            passDesc.colorAttachments[0].texture = pingTexture
            passDesc.colorAttachments[0].loadAction = .dontCare
            passDesc.colorAttachments[0].storeAction = .store
            
            guard let cmdBuf = commandQueue.makeCommandBuffer(),
                  let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
                return false
            }
            
            encoder.setRenderPipelineState(blurH)
            encoder.setFragmentTexture(sourceTexture, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            
            var params = BlurParams(texelSize: 1.0 / w, radius: radius, sigma: sigma, _pad: 0)
            encoder.setFragmentBytes(&params, length: MemoryLayout<BlurParams>.stride, index: 0)
            
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
        }
        
        // Pass 2: Vertical blur (ping → dest)
        do {
            let passDesc = MTLRenderPassDescriptor()
            passDesc.colorAttachments[0].texture = destTexture
            passDesc.colorAttachments[0].loadAction = .dontCare
            passDesc.colorAttachments[0].storeAction = .store
            
            guard let cmdBuf = commandQueue.makeCommandBuffer(),
                  let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
                return false
            }
            
            encoder.setRenderPipelineState(blurV)
            encoder.setFragmentTexture(pingTexture, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            
            var params = BlurParams(texelSize: 1.0 / h, radius: radius, sigma: sigma, _pad: 0)
            encoder.setFragmentBytes(&params, length: MemoryLayout<BlurParams>.stride, index: 0)
            
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
        }
        
        return true
    }
    
    private func renderSharpen(
        state: GPUImageState,
        amount: Float,
        originalTexture: MTLTexture,
        blurredTexture: MTLTexture,
        destTexture: MTLTexture
    ) -> Bool {
        guard let commandQueue = commandQueue,
              let pipeline = sharpenPipeline,
              let sampler = linearSampler else { return false }
        
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = destTexture
        passDesc.colorAttachments[0].loadAction = .dontCare
        passDesc.colorAttachments[0].storeAction = .store
        
        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            return false
        }
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(originalTexture, index: 0)
        encoder.setFragmentTexture(blurredTexture, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        
        let w = Float(state.width)
        let h = Float(state.height)
        var params = SharpenParams(texelSizeX: 1.0 / w, texelSizeY: 1.0 / h, amount: amount, _pad: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<SharpenParams>.stride, index: 0)
        
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        return true
    }
    
    private func generateMipmaps(texture: MTLTexture) -> Bool {
        guard let commandQueue = commandQueue else { return false }
        
        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let blitEncoder = cmdBuf.makeBlitCommandEncoder() else {
            return false
        }
        
        blitEncoder.generateMipmaps(for: texture)
        blitEncoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        return true
    }
    
    private func renderEdgeDetect(
        state: GPUImageState,
        strength: Float,
        invert: Bool,
        sourceTexture: MTLTexture,
        destTexture: MTLTexture
    ) -> Bool {
        guard let commandQueue = commandQueue,
              let pipeline = edgeDetectPipeline,
              let sampler = linearSampler else { return false }
        
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = destTexture
        passDesc.colorAttachments[0].loadAction = .dontCare
        passDesc.colorAttachments[0].storeAction = .store
        
        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            return false
        }
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        
        let w = Float(state.width)
        let h = Float(state.height)
        var params = EdgeDetectParams(
            texelSizeX: 1.0 / w,
            texelSizeY: 1.0 / h,
            strength: strength,
            invert: invert ? 1.0 : 0.0
        )
        encoder.setFragmentBytes(&params, length: MemoryLayout<EdgeDetectParams>.stride, index: 0)
        
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        return true
    }
    
    private func computeHistogramData(state: GPUImageState) -> [Int]? {
        guard let commandQueue = commandQueue,
              let pipeline = histogramPipeline,
              let device = device,
              let src = state.sourceTexture else { return nil }
        
        // Create buffer for 768 uint32 (R[256] + G[256] + B[256])
        let bufferSize = 768 * MemoryLayout<UInt32>.stride
        guard let histBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            return nil
        }
        
        // Zero-fill
        memset(histBuffer.contents(), 0, bufferSize)
        
        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else {
            return nil
        }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(src, index: 0)
        encoder.setBuffer(histBuffer, offset: 0, index: 0)
        
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (state.width + 15) / 16,
            height: (state.height + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        // Read back results
        let ptr = histBuffer.contents().bindMemory(to: UInt32.self, capacity: 768)
        var result = [Int](repeating: 0, count: 768)
        for i in 0..<768 {
            result[i] = Int(ptr[i])
        }
        return result
    }
    
    // MARK: - Uniform Structs (must match shader layout)
    
    private struct ColorGradingParams {
        var brightness: Float
        var contrast: Float
        var saturation: Float
        var hueShift: Float
        var temperature: Float
        var opacity: Float
        var vignette: Float
        var _pad: Float
    }
    
    private struct BlurParams {
        var texelSize: Float
        var radius: Float
        var sigma: Float
        var _pad: Float
    }
    
    private struct SharpenParams {
        var texelSizeX: Float
        var texelSizeY: Float
        var amount: Float
        var _pad: Float
    }
    
    private struct EdgeDetectParams {
        var texelSizeX: Float
        var texelSizeY: Float
        var strength: Float
        var invert: Float
    }
    
    // MARK: - MethodChannel Handler
    
    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
            
        case "initialize":
            let success = initMetal()
            result(success)
            
        case "uploadImage":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String,
                  let imageBytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let width = args["width"] as? Int,
                  let height = args["height"] as? Int,
                  let cache = cvMetalTextureCache else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing required args", details: nil))
                return
            }
            
            // Create GPU state for this image
            guard let state = createGPUImageState(width: width, height: height, cache: cache),
                  let sourceTexture = state.sourceTexture else {
                result(-1)
                return
            }
            
            // Upload RGBA bytes to source texture
            let bytesPerRow = width * 4
            let data = imageBytes.data
            data.withUnsafeBytes { ptr in
                sourceTexture.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: ptr.baseAddress!,
                    bytesPerRow: bytesPerRow
                )
            }
            
            // Register as Flutter texture
            if let registry = textureRegistry {
                state.textureId = registry.register(state)
            }
            
            // Initial render: copy source → output (identity filter)
            if let src = state.sourceTexture, let dst = state.outputTexture {
                let identityParams = ColorGradingParams(
                    brightness: 0, contrast: 0, saturation: 0,
                    hueShift: 0, temperature: 0, opacity: 1, vignette: 0, _pad: 0
                )
                _ = renderColorGrading(state: state, params: identityParams, sourceTexture: src, destTexture: dst)
            }
            
            imageStates[imageId] = state
            
            if state.textureId >= 0, let registry = textureRegistry {
                registry.textureFrameAvailable(state.textureId)
            }
            
            result(state.textureId)
            
        case "applyFilters":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String,
                  let state = imageStates[imageId],
                  let src = state.sourceTexture,
                  let dst = state.outputTexture else {
                result(false)
                return
            }
            
            let params = ColorGradingParams(
                brightness: Float(args["brightness"] as? Double ?? 0),
                contrast: Float(args["contrast"] as? Double ?? 0),
                saturation: Float(args["saturation"] as? Double ?? 0),
                hueShift: Float(args["hueShift"] as? Double ?? 0),
                temperature: Float(args["temperature"] as? Double ?? 0),
                opacity: Float(args["opacity"] as? Double ?? 1),
                vignette: Float(args["vignette"] as? Double ?? 0),
                _pad: 0
            )
            
            // Determine render chain based on active effects
            let blurRadius = Float(args["blurRadius"] as? Double ?? 0)
            let sharpenAmount = Float(args["sharpenAmount"] as? Double ?? 0)
            
            // Step 1: Color grading (source → output or ping depending on chain)
            let colorDest = (blurRadius > 0 || sharpenAmount > 0) ? state.pingTexture ?? dst : dst
            let success = renderColorGrading(state: state, params: params, sourceTexture: src, destTexture: colorDest)
            
            // Step 2: Blur (if active)
            if success && blurRadius > 0, let ping = state.pingTexture {
                if sharpenAmount > 0 {
                    // Blur for sharpen source: colorDest(ping) → dst via blur, keep ping for sharpen
                    _ = renderBlur(state: state, radius: blurRadius, sourceTexture: ping, destTexture: dst, pingTexture: ping)
                } else {
                    // Pure blur: ping → dst
                    _ = renderBlur(state: state, radius: blurRadius, sourceTexture: ping, destTexture: dst, pingTexture: dst)
                }
            }
            
            // Step 3: Sharpen (if active) — unsharp mask
            if success && sharpenAmount > 0, let ping = state.pingTexture {
                // First generate a mild blur for unsharp mask (3px)
                _ = renderBlur(state: state, radius: 3.0, sourceTexture: colorDest, destTexture: ping, pingTexture: ping)
                _ = renderSharpen(state: state, amount: sharpenAmount, originalTexture: colorDest, blurredTexture: ping, destTexture: dst)
            }
            
            if state.textureId >= 0, let registry = textureRegistry {
                registry.textureFrameAvailable(state.textureId)
            }
            
            result(success)
            
        case "applyBlur":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String,
                  let state = imageStates[imageId],
                  let src = state.sourceTexture,
                  let dst = state.outputTexture,
                  let ping = state.pingTexture else {
                result(false)
                return
            }
            
            let radius = Float(args["radius"] as? Double ?? 5.0)
            let success = renderBlur(state: state, radius: radius, sourceTexture: src, destTexture: dst, pingTexture: ping)
            
            if state.textureId >= 0, let registry = textureRegistry {
                registry.textureFrameAvailable(state.textureId)
            }
            
            result(success)
            
        case "applySharpen":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String,
                  let state = imageStates[imageId],
                  let src = state.sourceTexture,
                  let dst = state.outputTexture,
                  let ping = state.pingTexture else {
                result(false)
                return
            }
            
            let amount = Float(args["amount"] as? Double ?? 0.5)
            
            // Generate blur for unsharp mask
            _ = renderBlur(state: state, radius: 3.0, sourceTexture: src, destTexture: ping, pingTexture: ping)
            let success = renderSharpen(state: state, amount: amount, originalTexture: src, blurredTexture: ping, destTexture: dst)
            
            if state.textureId >= 0, let registry = textureRegistry {
                registry.textureFrameAvailable(state.textureId)
            }
            
            result(success)
            
        case "generateMipmaps":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String,
                  let state = imageStates[imageId],
                  let src = state.sourceTexture else {
                result(false)
                return
            }
            
            let success = generateMipmaps(texture: src)
            result(success)
            
        case "applyEdgeDetect":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String,
                  let state = imageStates[imageId],
                  let src = state.sourceTexture,
                  let dst = state.outputTexture else {
                result(false)
                return
            }
            
            let strength = Float(args["strength"] as? Double ?? 0.5)
            let invert = args["invert"] as? Bool ?? false
            let success = renderEdgeDetect(
                state: state,
                strength: strength,
                invert: invert,
                sourceTexture: src,
                destTexture: dst
            )
            
            if state.textureId >= 0, let registry = textureRegistry {
                registry.textureFrameAvailable(state.textureId)
            }
            
            result(success)
            
        case "computeHistogram":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String,
                  let state = imageStates[imageId] else {
                result([])
                return
            }
            
            if let histData = computeHistogramData(state: state) {
                result(histData)
            } else {
                result([])
            }
            
        case "releaseImage":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String else {
                result(nil)
                return
            }
            
            if let state = imageStates.removeValue(forKey: imageId) {
                if state.textureId >= 0, let registry = textureRegistry {
                    registry.unregisterTexture(state.textureId)
                }
            }
            result(nil)
            
        case "dispose":
            for (_, state) in imageStates {
                if state.textureId >= 0, let registry = textureRegistry {
                    registry.unregisterTexture(state.textureId)
                }
            }
            imageStates.removeAll()
            result(nil)
            
        case "applyHslPerChannel":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String,
                  let adjustments = args["adjustments"] as? [Double],
                  let state = imageStates[imageId],
                  let pipeline = hslPerChannelPipeline else {
                result(false)
                return
            }
            
            // Pack adjustments into float array (pad to 24)
            var hslParams = [Float](repeating: 0, count: 24)
            for i in 0..<min(adjustments.count, 21) {
                hslParams[i] = Float(adjustments[i])
            }
            
            applyRenderPass(state: state, pipeline: pipeline, params: hslParams,
                           paramsSize: MemoryLayout<Float>.stride * 24)
            result(true)
            
        case "applyBilateralDenoise":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String,
                  let strength = args["strength"] as? Double,
                  let state = imageStates[imageId],
                  let pipeline = bilateralDenoisePipeline else {
                result(false)
                return
            }
            
            var bilateralParams: [Float] = [
                1.0 / Float(state.width),   // texelSizeX
                1.0 / Float(state.height),  // texelSizeY
                Float(strength),             // strength
                0.1                          // rangeSigma
            ]
            
            applyRenderPass(state: state, pipeline: pipeline, params: &bilateralParams,
                           paramsSize: MemoryLayout<Float>.stride * 4)
            result(true)
            
        case "applyToneCurve":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String,
                  let curveData = args["curveData"] as? [Double],
                  let state = imageStates[imageId],
                  let pipeline = toneCurvePipeline else {
                result(false)
                return
            }
            var tcParams = [Float](repeating: 0, count: 32)
            for i in 0..<min(curveData.count, 32) {
                tcParams[i] = Float(curveData[i])
            }
            applyRenderPass(state: state, pipeline: pipeline, params: tcParams,
                           paramsSize: MemoryLayout<Float>.stride * 32)
            result(true)
            
        case "applyClarity":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String,
                  let clarity = args["clarity"] as? Double,
                  let texturePower = args["texturePower"] as? Double,
                  let state = imageStates[imageId],
                  let pipeline = clarityPipeline else {
                result(false)
                return
            }
            var clParams: [Float] = [
                1.0 / Float(state.width),
                1.0 / Float(state.height),
                Float(clarity),
                Float(texturePower)
            ]
            applyRenderPass(state: state, pipeline: pipeline, params: &clParams,
                           paramsSize: MemoryLayout<Float>.stride * 4)
            result(true)
            
        case "applySplitToning":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String,
                  let highlightColor = args["highlightColor"] as? [Double],
                  let shadowColor = args["shadowColor"] as? [Double],
                  let balance = args["balance"] as? Double,
                  let state = imageStates[imageId],
                  let pipeline = splitToningPipeline else {
                result(false)
                return
            }
            var stParams: [Float] = [
                Float(highlightColor[0]), Float(highlightColor[1]),
                Float(highlightColor[2]), Float(highlightColor[3]),
                Float(shadowColor[0]), Float(shadowColor[1]),
                Float(shadowColor[2]), Float(shadowColor[3]),
                Float(balance), 0, 0, 0
            ]
            applyRenderPass(state: state, pipeline: pipeline, params: &stParams,
                           paramsSize: MemoryLayout<Float>.stride * 12)
            result(true)
            
        case "applyFilmGrain":
            guard let args = call.arguments as? [String: Any],
                  let imageId = args["imageId"] as? String,
                  let intensity = args["intensity"] as? Double,
                  let size = args["size"] as? Double,
                  let seed = args["seed"] as? Double,
                  let lumResponse = args["luminanceResponse"] as? Double,
                  let state = imageStates[imageId],
                  let pipeline = filmGrainPipeline else {
                result(false)
                return
            }
            var fgParams: [Float] = [
                Float(intensity), Float(size), Float(seed), Float(lumResponse)
            ]
            applyRenderPass(state: state, pipeline: pipeline, params: &fgParams,
                           paramsSize: MemoryLayout<Float>.stride * 4)
            result(true)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
