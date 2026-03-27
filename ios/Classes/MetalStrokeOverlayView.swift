// MetalStrokeOverlayView.swift — Native CAMetalLayer overlay for direct GPU rendering
//
// Bypasses Flutter's TextureRegistry + Impeller compositing by rendering
// strokes directly to a CAMetalLayer positioned above the Flutter view.
// This eliminates the CVPixelBuffer → TextureRegistry → Impeller compositor
// overhead, shaving ~1-2ms off the rendering path.
//
// Lifecycle:
//   1. Plugin creates MetalStrokeOverlayView and adds as subview of FlutterView
//   2. MetalStrokeRenderer renders directly to CAMetalLayer.nextDrawable()
//   3. On pen-up, overlay is hidden; Flutter crosses back to Texture widget path

import UIKit
import Metal
import QuartzCore

/// 🚀 MetalStrokeOverlayView — Direct CAMetalLayer rendering overlay.
///
/// This UIView uses CAMetalLayer as its backing layer, enabling the Metal
/// stroke renderer to present frames directly to the display without
/// passing through Flutter's compositor.
class MetalStrokeOverlayView: UIView {

    // ─── CAMetalLayer ──────────────────────────────────────────
    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    // ─── State ─────────────────────────────────────────────────
    private(set) var isOverlayActive: Bool = false

    // ═══════════════════════════════════════════════════════════════
    // INIT
    // ═══════════════════════════════════════════════════════════════

    init(device: MTLDevice, frame: CGRect) {
        super.init(frame: frame)

        // Transparent — show Flutter content underneath
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false  // Don't intercept touches

        // Auto-resize with parent
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Configure CAMetalLayer
        let ml = metalLayer
        ml.device = device
        ml.pixelFormat = .bgra8Unorm
        ml.framebufferOnly = true          // 🚀 GPU-only, no CPU readback
        ml.presentsWithTransaction = false // 🚀 Minimum latency (async present)
        ml.isOpaque = false                // Transparent background
        ml.contentsScale = UIScreen.main.scale

        // Match screen size in pixels
        ml.drawableSize = CGSize(
            width: frame.width * UIScreen.main.scale,
            height: frame.height * UIScreen.main.scale
        )

        // Start hidden
        isHidden = true

        NSLog("[FlueraMtl] 🚀 CAMetalLayer overlay view created")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // ═══════════════════════════════════════════════════════════════
    // SHOW / HIDE
    // ═══════════════════════════════════════════════════════════════

    /// Activate the overlay for direct rendering (call on pen-down)
    func show(opacity: Float = 1.0) {
        isHidden = false
        isOverlayActive = true
        metalLayer.opacity = opacity
        NSLog("[FlueraMtl] 🚀 Direct overlay ACTIVE (opacity=%.2f)", opacity)
    }

    /// Deactivate the overlay (call on pen-up)
    func hide() {
        isHidden = true
        isOverlayActive = false
        NSLog("[FlueraMtl] 🚀 Direct overlay HIDDEN")
    }

    /// Update opacity (e.g., for highlighter: opacity < 1.0)
    func setOverlayOpacity(_ opacity: Float) {
        metalLayer.opacity = opacity
    }

    // ═══════════════════════════════════════════════════════════════
    // RESIZE
    // ═══════════════════════════════════════════════════════════════

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update drawable size when view resizes (rotation, etc.)
        metalLayer.drawableSize = CGSize(
            width: bounds.width * contentScaleFactor,
            height: bounds.height * contentScaleFactor
        )
    }

    /// Explicit resize (called from plugin on surface change)
    func updateDrawableSize(width: Int, height: Int) {
        metalLayer.drawableSize = CGSize(width: width, height: height)
    }
}
