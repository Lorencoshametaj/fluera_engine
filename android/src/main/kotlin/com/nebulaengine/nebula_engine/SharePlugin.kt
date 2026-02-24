package com.nebulaengine.nebula_engine

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 📤 SharePlugin — Native file share via Android Intent.
 *
 * Zero-dependency alternative to share_plus.
 * Uses FileProvider for secure file sharing with other apps.
 */
class SharePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var binding: FlutterPlugin.FlutterPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        channel = MethodChannel(binding.binaryMessenger, "com.nebulaengine.nebula_engine/share")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        this.binding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareFile" -> {
                val filePath = call.argument<String>("filePath")
                val mimeType = call.argument<String>("mimeType") ?: "*/*"
                val subject = call.argument<String>("subject") ?: ""

                if (filePath == null) {
                    result.error("INVALID_ARGS", "filePath is required", null)
                    return
                }

                try {
                    val context = binding?.applicationContext
                        ?: throw IllegalStateException("No application context")
                    val file = File(filePath)

                    // Use FileProvider for secure sharing
                    val uri: Uri = FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileprovider",
                        file
                    )

                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = mimeType
                        putExtra(Intent.EXTRA_STREAM, uri)
                        putExtra(Intent.EXTRA_SUBJECT, subject)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }

                    val chooser = Intent.createChooser(shareIntent, "Share PDF")
                    chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(chooser)

                    result.success(null)
                } catch (e: Exception) {
                    result.error("SHARE_FAILED", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
