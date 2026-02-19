package com.nebulaengine.nebula_engine

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * 📄 PdfRendererPlugin — Native Android PDF Rendering
 *
 * Uses android.graphics.pdf.PdfRenderer to:
 * - Load multiple PDF documents from raw bytes (keyed by documentId)
 * - Render pages as raw RGBA pixel buffers
 * - Transfer pixel data as ByteArray to Dart
 *
 * Thread safety: all PdfRenderer access is serialized via a single-thread
 * executor. Bitmap objects are pooled per size key to reduce GC pressure.
 *
 * Channel: com.nebulaengine/pdf_renderer
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

    companion object {
        private const val CHANNEL_NAME = "com.nebulaengine/pdf_renderer"
        private const val MAX_POOL_SIZE = 4
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding

        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        disposeAllInternal()
        renderExecutor.shutdownNow()
        channel?.setMethodCallHandler(null)
        channel = null
        this.binding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadDocument" -> handleLoadDocument(call, result)
            "getPageSize" -> handleGetPageSize(call, result)
            "renderPage" -> handleRenderPage(call, result)
            "extractText" -> handleExtractText(call, result)
            "getPageText" -> handleGetPageText(call, result)
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

            val temp = File.createTempFile("nebula_pdf_", ".pdf", context.cacheDir)
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
    // Render Page (raw RGBA pixels) — thread-safe + bitmap pool
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
