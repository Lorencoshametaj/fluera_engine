package com.nebulaengine.nebula_engine

import android.app.Activity
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

/**
 * 🖨️ PrintPlugin — Native PDF printing via Android PrintManager.
 *
 * Requires Activity context (not Application context) because
 * PrintManager.print() can only be called from an Activity.
 */
class PrintPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.nebulaengine.nebula_engine/print")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    // ActivityAware — capture the Activity reference
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "printPdf" -> {
                val filePath = call.argument<String>("filePath")
                val jobName = call.argument<String>("jobName") ?: "PDF Document"

                if (filePath == null) {
                    result.error("INVALID_ARGS", "filePath is required", null)
                    return
                }

                val act = activity
                if (act == null) {
                    result.error("NO_ACTIVITY", "No activity available for printing", null)
                    return
                }

                try {
                    val printManager = act.getSystemService(PrintManager::class.java)

                    val file = File(filePath)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "File not found: $filePath", null)
                        return
                    }

                    val adapter = object : PrintDocumentAdapter() {
                        override fun onLayout(
                            oldAttributes: PrintAttributes?,
                            newAttributes: PrintAttributes?,
                            cancellationSignal: CancellationSignal?,
                            callback: LayoutResultCallback?,
                            extras: Bundle?
                        ) {
                            if (cancellationSignal?.isCanceled == true) {
                                callback?.onLayoutCancelled()
                                return
                            }
                            val info = PrintDocumentInfo.Builder(jobName)
                                .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                                .build()
                            callback?.onLayoutFinished(info, true)
                        }

                        override fun onWrite(
                            pages: Array<out PageRange>?,
                            destination: ParcelFileDescriptor?,
                            cancellationSignal: CancellationSignal?,
                            callback: WriteResultCallback?
                        ) {
                            try {
                                FileInputStream(file).use { input ->
                                    val output = ParcelFileDescriptor.AutoCloseOutputStream(destination)
                                    input.copyTo(output)
                                    output.close()
                                }
                                callback?.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                            } catch (e: Exception) {
                                callback?.onWriteFailed(e.message)
                            }
                        }
                    }

                    printManager.print(jobName, adapter, null)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("PRINT_FAILED", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
