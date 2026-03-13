package com.flueraengine.fluera_engine

import android.graphics.Bitmap
import android.graphics.Canvas as AndroidCanvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect as AndroidRect
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * 📄 PdfRendererPlugin — Native Android PDF Rendering
 *
 * Uses android.graphics.pdf.PdfRenderer to:
 * - Load multiple PDF documents from raw bytes (keyed by documentId)
 * - Render pages as raw RGBA pixel buffers (legacy path)
 * - Render pages via TextureRegistry for zero-copy GPU sharing (fast path)
 * - Transfer pixel data as ByteArray to Dart
 *
 * Thread safety: all PdfRenderer access is serialized via a single-thread
 * executor. Bitmap objects are pooled per size key to reduce GC pressure.
 *
 * Channel: com.flueraengine/pdf_renderer
 */
class PdfRendererPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var binding: FlutterPlugin.FlutterPluginBinding? = null

    /// Multi-document storage keyed by documentId.
    private data class DocumentHandle(
        val renderer: PdfRenderer,
        val fileDescriptor: ParcelFileDescriptor,
        val tempFile: File
    )

    private val documents = mutableMapOf<String, DocumentHandle>()

    /// Single-thread executor for all PdfRenderer access (thread safety).
    private val renderExecutor = Executors.newSingleThreadExecutor()

    /// Bitmap pool keyed by "WxH" to reuse allocations.
    private val bitmapPool = mutableMapOf<String, Bitmap>()
    private val mainHandler = Handler(Looper.getMainLooper())

    // =========================================================================
    // TextureRegistry — Zero-copy GPU texture sharing
    // =========================================================================

    private var textureRegistry: TextureRegistry? = null

    /// Pool of SurfaceProducer entries, keyed by "WxH".
    /// Each entry holds the producer, its Flutter texture ID, and a reuse bitmap.
    private data class TextureEntry(
        val producer: TextureRegistry.SurfaceProducer,
        val textureId: Long,
        val width: Int,
        val height: Int
    )

    private val texturePool = mutableMapOf<String, TextureEntry>()

    /// Maximum texture pool size to avoid exhausting GPU memory.
    private val MAX_TEXTURE_POOL = 8

    /// Paint for drawing bitmaps onto Surfaces — reused to avoid alloc.
    private val surfacePaint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)

    companion object {
        private const val CHANNEL_NAME = "com.flueraengine/pdf_renderer"
        private const val MAX_POOL_SIZE = 4
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        textureRegistry = binding.textureRegistry

        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        disposeAllInternal()
        releaseAllTextures()
        renderExecutor.shutdownNow()
        channel?.setMethodCallHandler(null)
        channel = null
        textureRegistry = null
        this.binding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadDocument" -> handleLoadDocument(call, result)
            "getPageSize" -> handleGetPageSize(call, result)
            "renderPage" -> handleRenderPage(call, result)
            "renderPageTexture" -> handleRenderPageTexture(call, result)
            "renderThumbnail" -> handleRenderThumbnail(call, result)
            "releaseTexture" -> handleReleaseTexture(call, result)
            "extractText" -> handleExtractText(call, result)
            "getPageText" -> handleGetPageText(call, result)
            "ocrPage" -> handleOcrPage(call, result)
            "dispose" -> handleDispose(call, result)
            "disposeAll" -> handleDisposeAll(result)
            else -> result.notImplemented()
        }
    }

    // =========================================================================
    // Load Document
    // =========================================================================

    private fun handleLoadDocument(call: MethodCall, result: MethodChannel.Result) {
        try {
            val bytes = call.argument<ByteArray>("bytes")
            val documentId = call.argument<String>("documentId")
            if (bytes == null || documentId == null) {
                result.error("INVALID_ARGS", "Missing 'bytes' or 'documentId'", null)
                return
            }

            // Clean up previous document with same ID
            disposeDocument(documentId)

            val context = binding?.applicationContext
            if (context == null) {
                result.error("NO_CONTEXT", "Application context not available", null)
                return
            }

            val temp = File.createTempFile("fluera_pdf_", ".pdf", context.cacheDir)
            FileOutputStream(temp).use { it.write(bytes) }

            val pfd = ParcelFileDescriptor.open(temp, ParcelFileDescriptor.MODE_READ_ONLY)
            val pdfRenderer = PdfRenderer(pfd)

            documents[documentId] = DocumentHandle(pdfRenderer, pfd, temp)

            // Pre-compute all page sizes for Dart-side cache
            // Serialized via synchronized — loadDocument is called on main thread
            val pageSizes = ArrayList<HashMap<String, Double>>()
            synchronized(pdfRenderer) {
                for (i in 0 until pdfRenderer.pageCount) {
                    val page = pdfRenderer.openPage(i)
                    val sizeMap = HashMap<String, Double>()
                    sizeMap["width"] = page.width.toDouble()
                    sizeMap["height"] = page.height.toDouble()
                    pageSizes.add(sizeMap)
                    page.close()
                }
            }

            val response = HashMap<String, Any>()
            response["pageCount"] = pdfRenderer.pageCount
            response["success"] = true
            response["pageSizes"] = pageSizes
            result.success(response)

        } catch (e: Exception) {
            val response = HashMap<String, Any>()
            response["pageCount"] = 0
            response["success"] = false
            result.success(response)
        }
    }

    // =========================================================================
    // Page Size
    // =========================================================================

    private fun handleGetPageSize(call: MethodCall, result: MethodChannel.Result) {
        val documentId = call.argument<String>("documentId")
        val pageIndex = call.argument<Int>("pageIndex")
        if (documentId == null || pageIndex == null) {
            result.error("INVALID_ARGS", "Missing arguments", null)
            return
        }

        val handle = documents[documentId]
        if (handle == null || pageIndex < 0 || pageIndex >= handle.renderer.pageCount) {
            val response = HashMap<String, Any>()
            response["width"] = 0.0
            response["height"] = 0.0
            result.success(response)
            return
        }

        // Serialize access to PdfRenderer
        synchronized(handle.renderer) {
            val page = handle.renderer.openPage(pageIndex)
            val response = HashMap<String, Any>()
            response["width"] = page.width.toDouble()
            response["height"] = page.height.toDouble()
            page.close()
            result.success(response)
        }
    }

    // =========================================================================
    // Render Page (raw RGBA pixels) — legacy path, thread-safe + bitmap pool
    // =========================================================================

    private fun handleRenderPage(call: MethodCall, result: MethodChannel.Result) {
        val documentId = call.argument<String>("documentId")
        val pageIndex = call.argument<Int>("pageIndex")
        val targetWidth = call.argument<Int>("targetWidth")
        val targetHeight = call.argument<Int>("targetHeight")

        if (documentId == null || pageIndex == null || targetWidth == null || targetHeight == null) {
            result.error("INVALID_ARGS", "Missing arguments", null)
            return
        }

        val handle = documents[documentId]
        if (handle == null || pageIndex < 0 || pageIndex >= handle.renderer.pageCount) {
            result.success(null)
            return
        }

        // Submit to single-thread executor for thread safety
        renderExecutor.execute {
            try {
                val width = maxOf(1, targetWidth)
                val height = maxOf(1, targetHeight)

                // Bitmap pool: reuse or create
                val poolKey = "${width}x${height}"
                val bitmap = acquireBitmap(poolKey, width, height)
                bitmap.eraseColor(Color.WHITE)

                // Synchronized access to PdfRenderer.openPage
                synchronized(handle.renderer) {
                    val page = handle.renderer.openPage(pageIndex)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    page.close()
                }

                // Extract pixels and convert ARGB → RGBA
                val buffer = ByteBuffer.allocate(width * height * 4)
                bitmap.copyPixelsToBuffer(buffer)

                // Return bitmap to pool
                releaseBitmap(poolKey, bitmap)

                val pixelBytes = buffer.array()

                // Swizzle BGRA → RGBA (little-endian ARM stores ARGB_8888 as [B,G,R,A])
                // Only byte 0 (B) and byte 2 (R) need swapping.
                val totalBytes = width * height * 4
                var i = 0
                while (i < totalBytes) {
                    val b = pixelBytes[i]            // B at position 0
                    pixelBytes[i] = pixelBytes[i + 2] // R → position 0
                    pixelBytes[i + 2] = b             // B → position 2
                    i += 4
                }

                val response = HashMap<String, Any>()
                response["width"] = width
                response["height"] = height
                response["pixels"] = pixelBytes

                mainHandler.post {
                    result.success(response)
                }

            } catch (e: Exception) {
                mainHandler.post {
                    result.success(null)
                }
            }
        }
    }

    // =========================================================================
    // Render Page via TextureRegistry — ZERO-COPY fast path
    // =========================================================================

    /**
     * 🚀 Zero-copy PDF page rendering via Flutter TextureRegistry.
     *
     * Flow:
     * 1. Render PDF page → Bitmap (PdfRenderer requires Bitmap target)
     * 2. Draw Bitmap onto SurfaceProducer's Surface canvas
     * 3. Return only the textureId (8 bytes) — no pixel array transfer
     *
     * Flutter composites the SurfaceProducer texture directly via Impeller,
     * eliminating the multi-MB MethodChannel transfer overhead.
     */
    private fun handleRenderPageTexture(call: MethodCall, result: MethodChannel.Result) {
        val documentId = call.argument<String>("documentId")
        val pageIndex = call.argument<Int>("pageIndex")
        val targetWidth = call.argument<Int>("targetWidth")
        val targetHeight = call.argument<Int>("targetHeight")

        if (documentId == null || pageIndex == null || targetWidth == null || targetHeight == null) {
            result.error("INVALID_ARGS", "Missing arguments", null)
            return
        }

        val handle = documents[documentId]
        if (handle == null || pageIndex < 0 || pageIndex >= handle.renderer.pageCount) {
            result.success(null)
            return
        }

        val registry = textureRegistry
        if (registry == null) {
            // Fallback: TextureRegistry not available
            result.success(null)
            return
        }

        val width = maxOf(1, targetWidth)
        val height = maxOf(1, targetHeight)

        // Submit to single-thread executor for thread safety
        renderExecutor.execute {
            try {
                // Step 1: Render PDF page into Bitmap
                val poolKey = "${width}x${height}"
                val bitmap = acquireBitmap(poolKey, width, height)
                bitmap.eraseColor(Color.WHITE)

                synchronized(handle.renderer) {
                    val page = handle.renderer.openPage(pageIndex)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    page.close()
                }

                // Step 2: Get or create SurfaceProducer and draw bitmap onto it
                mainHandler.post {
                    try {
                        val texEntry = acquireTexture(registry, width, height)
                        if (texEntry == null) {
                            releaseBitmap(poolKey, bitmap)
                            result.success(null)
                            return@post
                        }

                        // Draw bitmap onto the Surface
                        val surface = texEntry.producer.surface
                        val canvas = surface.lockCanvas(null)
                        if (canvas != null) {
                            // Draw the bitmap scaled to fill the surface
                            canvas.drawColor(Color.WHITE)
                            canvas.drawBitmap(
                                bitmap,
                                null,
                                AndroidRect(0, 0, width, height),
                                surfacePaint
                            )
                            surface.unlockCanvasAndPost(canvas)
                        }

                        // Return bitmap to pool
                        releaseBitmap(poolKey, bitmap)

                        // Return texture info — only 3 small values, no pixel array!
                        val response = HashMap<String, Any>()
                        response["textureId"] = texEntry.textureId
                        response["width"] = width
                        response["height"] = height
                        result.success(response)

                    } catch (e: Exception) {
                        releaseBitmap(poolKey, bitmap)
                        result.success(null)
                    }
                }

            } catch (e: Exception) {
                mainHandler.post {
                    result.success(null)
                }
            }
        }
    }

    // =========================================================================
    // Render Thumbnail — fast low-res preview
    // =========================================================================

    /**
     * 🖼️ Render a low-resolution thumbnail for instant page preview.
     *
     * Returns raw RGBA pixels at a fixed small size (~200px wide).
     * At this resolution the MethodChannel overhead is negligible (~160KB).
     */
    private fun handleRenderThumbnail(call: MethodCall, result: MethodChannel.Result) {
        val documentId = call.argument<String>("documentId")
        val pageIndex = call.argument<Int>("pageIndex")

        if (documentId == null || pageIndex == null) {
            result.error("INVALID_ARGS", "Missing arguments", null)
            return
        }

        val handle = documents[documentId]
        if (handle == null || pageIndex < 0 || pageIndex >= handle.renderer.pageCount) {
            result.success(null)
            return
        }

        renderExecutor.execute {
            try {
                // Get page dimensions to compute aspect ratio
                val pageWidth: Int
                val pageHeight: Int
                synchronized(handle.renderer) {
                    val page = handle.renderer.openPage(pageIndex)
                    pageWidth = page.width
                    pageHeight = page.height
                    page.close()
                }

                // Fixed thumbnail width, preserve aspect ratio
                val thumbWidth = 200
                val thumbHeight = (thumbWidth.toDouble() * pageHeight / maxOf(1, pageWidth)).toInt().coerceIn(1, 400)

                val poolKey = "thumb_${thumbWidth}x${thumbHeight}"
                val bitmap = acquireBitmap(poolKey, thumbWidth, thumbHeight)
                bitmap.eraseColor(Color.WHITE)

                synchronized(handle.renderer) {
                    val page = handle.renderer.openPage(pageIndex)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    page.close()
                }

                // Extract pixels — small enough for MethodChannel (~160KB)
                val buffer = ByteBuffer.allocate(thumbWidth * thumbHeight * 4)
                bitmap.copyPixelsToBuffer(buffer)
                releaseBitmap(poolKey, bitmap)

                val pixelBytes = buffer.array()

                // Swizzle BGRA → RGBA
                val totalBytes = thumbWidth * thumbHeight * 4
                var i = 0
                while (i < totalBytes) {
                    val b = pixelBytes[i]
                    pixelBytes[i] = pixelBytes[i + 2]
                    pixelBytes[i + 2] = b
                    i += 4
                }

                val response = HashMap<String, Any>()
                response["width"] = thumbWidth
                response["height"] = thumbHeight
                response["pixels"] = pixelBytes

                mainHandler.post {
                    result.success(response)
                }

            } catch (e: Exception) {
                mainHandler.post {
                    result.success(null)
                }
            }
        }
    }

    // =========================================================================
    // Texture Pool Management
    // =========================================================================

    /**
     * Acquire a SurfaceProducer texture entry of the given size.
     * Reuses existing entries or creates new ones. Must be called on main thread.
     */
    @Synchronized
    private fun acquireTexture(registry: TextureRegistry, width: Int, height: Int): TextureEntry? {
        val key = "${width}x${height}"

        // Reuse existing texture of same size
        texturePool[key]?.let { return it }

        // Evict oldest if pool is full
        if (texturePool.size >= MAX_TEXTURE_POOL) {
            val oldestKey = texturePool.keys.first()
            texturePool.remove(oldestKey)?.producer?.release()
        }

        return try {
            val producer = registry.createSurfaceProducer()
            producer.setSize(width, height)
            val textureId = producer.id()
            val entry = TextureEntry(producer, textureId, width, height)
            texturePool[key] = entry
            entry
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Release a specific texture by its ID.
     */
    private fun handleReleaseTexture(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Number>("textureId")?.toLong()
        if (textureId != null) {
            val entry = texturePool.entries.find { it.value.textureId == textureId }
            if (entry != null) {
                entry.value.producer.release()
                texturePool.remove(entry.key)
            }
        }
        result.success(null)
    }

    /**
     * Release all texture entries.
     */
    private fun releaseAllTextures() {
        for (entry in texturePool.values) {
            try {
                entry.producer.release()
            } catch (_: Exception) {}
        }
        texturePool.clear()
    }

    // =========================================================================
    // Bitmap Pool
    // =========================================================================

    @Synchronized
    private fun acquireBitmap(key: String, width: Int, height: Int): Bitmap {
        val pooled = bitmapPool.remove(key)
        if (pooled != null && !pooled.isRecycled) {
            return pooled
        }
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    }

    @Synchronized
    private fun releaseBitmap(key: String, bitmap: Bitmap) {
        if (bitmapPool.size >= MAX_POOL_SIZE) {
            // Evict oldest entry
            val oldest = bitmapPool.keys.first()
            bitmapPool.remove(oldest)?.recycle()
        }
        bitmapPool[key] = bitmap
    }

    @Synchronized
    private fun clearBitmapPool() {
        bitmapPool.values.forEach { it.recycle() }
        bitmapPool.clear()
    }

    // =========================================================================
    // Text Extraction (not supported by Android PdfRenderer)
    // =========================================================================

    private fun handleExtractText(call: MethodCall, result: MethodChannel.Result) {
        result.success(emptyList<Map<String, Any>>())
    }

    private fun handleGetPageText(call: MethodCall, result: MethodChannel.Result) {
        result.success("")
    }

    // =========================================================================
    // OCR — ML Kit Text Recognition for scanned/image-based PDFs
    // =========================================================================

    private fun handleOcrPage(call: MethodCall, result: MethodChannel.Result) {
        val documentId = call.argument<String>("documentId")
        val pageIndex = call.argument<Int>("pageIndex")

        if (documentId == null || pageIndex == null) {
            result.error("INVALID_ARGS", "Missing arguments", null)
            return
        }

        val handle = documents[documentId]
        if (handle == null || pageIndex < 0 || pageIndex >= handle.renderer.pageCount) {
            result.success(null)
            return
        }

        // Render page to bitmap on background thread, then run ML Kit OCR
        renderExecutor.execute {
            try {
                // Render at reasonable resolution for OCR (1200px wide)
                val pageWidth: Int
                val pageHeight: Int
                synchronized(handle.renderer) {
                    val page = handle.renderer.openPage(pageIndex)
                    val scale = 1200.0 / page.width.coerceAtLeast(1)
                    pageWidth = (page.width * scale).toInt().coerceAtLeast(1)
                    pageHeight = (page.height * scale).toInt().coerceAtLeast(1)
                    page.close()
                }

                val bitmap = Bitmap.createBitmap(pageWidth, pageHeight, Bitmap.Config.ARGB_8888)
                bitmap.eraseColor(Color.WHITE)

                synchronized(handle.renderer) {
                    val page = handle.renderer.openPage(pageIndex)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    page.close()
                }

                // Run ML Kit text recognition
                val inputImage = InputImage.fromBitmap(bitmap, 0)
                val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

                recognizer.process(inputImage)
                    .addOnSuccessListener { visionText ->
                        val blocks = ArrayList<HashMap<String, Any>>()
                        val fullTextBuilder = StringBuilder()

                        for (block in visionText.textBlocks) {
                            for (line in block.lines) {
                                val boundingBox = line.boundingBox ?: continue
                                val lineText = line.text

                                if (fullTextBuilder.isNotEmpty()) {
                                    fullTextBuilder.append("\n")
                                }
                                fullTextBuilder.append(lineText)

                                // Normalize bounding box to 0.0–1.0
                                val blockMap = HashMap<String, Any>()
                                blockMap["text"] = lineText
                                blockMap["x"] = boundingBox.left.toDouble() / pageWidth
                                blockMap["y"] = boundingBox.top.toDouble() / pageHeight
                                blockMap["width"] = boundingBox.width().toDouble() / pageWidth
                                blockMap["height"] = boundingBox.height().toDouble() / pageHeight
                                blockMap["confidence"] = line.confidence.toDouble()
                                blocks.add(blockMap)
                            }
                        }

                        bitmap.recycle()

                        val response = HashMap<String, Any>()
                        response["text"] = fullTextBuilder.toString()
                        response["blocks"] = blocks

                        mainHandler.post {
                            result.success(response)
                        }
                    }
                    .addOnFailureListener { _ ->
                        bitmap.recycle()
                        mainHandler.post {
                            result.success(null)
                        }
                    }

            } catch (e: Exception) {
                mainHandler.post {
                    result.success(null)
                }
            }
        }
    }

    // =========================================================================
    // Dispose
    // =========================================================================

    private fun handleDispose(call: MethodCall, result: MethodChannel.Result) {
        val documentId = call.argument<String>("documentId")
        if (documentId != null) {
            disposeDocument(documentId)
        }
        result.success(null)
    }

    private fun handleDisposeAll(result: MethodChannel.Result) {
        disposeAllInternal()
        result.success(null)
    }

    private fun disposeDocument(documentId: String) {
        documents.remove(documentId)?.let { handle ->
            handle.renderer.close()
            handle.fileDescriptor.close()
            handle.tempFile.delete()
        }
    }

    private fun disposeAllInternal() {
        documents.values.forEach { handle ->
            handle.renderer.close()
            handle.fileDescriptor.close()
            handle.tempFile.delete()
        }
        documents.clear()
        clearBitmapPool()
    }
}
