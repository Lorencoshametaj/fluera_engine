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

/**
 * 📄 PdfRendererPlugin — Native Android PDF Rendering
 *
 * Uses android.graphics.pdf.PdfRenderer to:
 * - Load PDF documents from raw bytes
 * - Render pages as raw RGBA pixel buffers
 * - Transfer pixel data as ByteArray to Dart
 *
 * Note: Android's PdfRenderer doesn't support text extraction.
 * For full text support, the host app can provide a custom NebulaPdfProvider.
 *
 * Channel: com.nebulaengine/pdf_renderer
 */
class PdfRendererPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var renderer: PdfRenderer? = null
    private var fileDescriptor: ParcelFileDescriptor? = null
    private var tempFile: File? = null
    private var binding: FlutterPlugin.FlutterPluginBinding? = null

    companion object {
        private const val CHANNEL_NAME = "com.nebulaengine/pdf_renderer"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding

        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        disposeInternal()
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
            "dispose" -> handleDispose(result)
            else -> result.notImplemented()
        }
    }

    // =========================================================================
    // Load Document
    // =========================================================================

    private fun handleLoadDocument(call: MethodCall, result: MethodChannel.Result) {
        try {
            val bytes = call.argument<ByteArray>("bytes")
            if (bytes == null) {
                result.error("INVALID_ARGS", "Missing 'bytes'", null)
                return
            }

            // Clean up previous document
            disposeInternal()

            // Write bytes to temp file (PdfRenderer requires a file descriptor)
            val context = binding?.applicationContext
            if (context == null) {
                result.error("NO_CONTEXT", "Application context not available", null)
                return
            }

            val temp = File.createTempFile("nebula_pdf_", ".pdf", context.cacheDir)
            FileOutputStream(temp).use { it.write(bytes) }
            tempFile = temp

            val pfd = ParcelFileDescriptor.open(temp, ParcelFileDescriptor.MODE_READ_ONLY)
            fileDescriptor = pfd

            val pdfRenderer = PdfRenderer(pfd)
            renderer = pdfRenderer

            val response = HashMap<String, Any>()
            response["pageCount"] = pdfRenderer.pageCount
            response["success"] = true
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
        val pageIndex = call.argument<Int>("pageIndex")
        if (pageIndex == null) {
            result.error("INVALID_ARGS", "Missing 'pageIndex'", null)
            return
        }

        val pdfRenderer = renderer
        if (pdfRenderer == null || pageIndex < 0 || pageIndex >= pdfRenderer.pageCount) {
            val response = HashMap<String, Any>()
            response["width"] = 0.0
            response["height"] = 0.0
            result.success(response)
            return
        }

        val page = pdfRenderer.openPage(pageIndex)
        val response = HashMap<String, Any>()
        response["width"] = page.width.toDouble()
        response["height"] = page.height.toDouble()
        page.close()
        result.success(response)
    }

    // =========================================================================
    // Render Page (raw RGBA pixels)
    // =========================================================================

    private fun handleRenderPage(call: MethodCall, result: MethodChannel.Result) {
        val pageIndex = call.argument<Int>("pageIndex")
        val targetWidth = call.argument<Int>("targetWidth")
        val targetHeight = call.argument<Int>("targetHeight")

        if (pageIndex == null || targetWidth == null || targetHeight == null) {
            result.error("INVALID_ARGS", "Missing arguments", null)
            return
        }

        val pdfRenderer = renderer
        if (pdfRenderer == null || pageIndex < 0 || pageIndex >= pdfRenderer.pageCount) {
            result.success(null)
            return
        }

        // Render on background thread to avoid blocking UI
        Thread {
            try {
                val width = maxOf(1, targetWidth)
                val height = maxOf(1, targetHeight)

                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                bitmap.eraseColor(Color.WHITE)

                val page = pdfRenderer.openPage(pageIndex)
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                page.close()

                // Extract raw RGBA pixels
                val buffer = ByteBuffer.allocate(width * height * 4)
                bitmap.copyPixelsToBuffer(buffer)
                bitmap.recycle()

                val pixelBytes = buffer.array()

                val response = HashMap<String, Any>()
                response["width"] = width
                response["height"] = height
                response["pixels"] = pixelBytes

                // Return on main thread
                Handler(Looper.getMainLooper()).post {
                    result.success(response)
                }

            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post {
                    result.success(null)
                }
            }
        }.start()
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

    private fun handleDispose(result: MethodChannel.Result) {
        disposeInternal()
        result.success(null)
    }

    private fun disposeInternal() {
        renderer?.close()
        renderer = null
        fileDescriptor?.close()
        fileDescriptor = null
        tempFile?.delete()
        tempFile = null
    }
}
