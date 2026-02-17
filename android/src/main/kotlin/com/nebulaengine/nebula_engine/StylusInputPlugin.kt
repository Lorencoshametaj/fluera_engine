package com.nebulaengine.nebula_engine

import android.os.Build
import android.view.InputDevice
import android.view.MotionEvent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 🖊️ StylusInputPlugin — Advanced Stylus Metadata for Android
 *
 * Provides enhanced stylus input data beyond basic predicted/coalesced touches:
 * - **Hover detection**: ACTION_HOVER_ENTER/MOVE/EXIT for S Pen and stylus hover
 * - **Tilt & orientation**: Axis tilt X/Y and orientation angles
 * - **Palm rejection**: Tool type filtering (TOOL_TYPE_STYLUS vs TOOL_TYPE_FINGER)
 * - **Pressure & size**: Full pressure and contact size data
 *
 * This plugin works alongside PredictedTouchPlugin, which handles
 * coalesced/predicted touch points. StylusInputPlugin adds the metadata
 * layer that iOS provides through its PredictedTouchPlugin's hover support.
 *
 * Channel: com.nebulaengine/stylus_input
 * Control: com.nebulaengine/stylus_input_control
 */
class StylusInputPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    companion object {
        private const val METHOD_CHANNEL = "com.nebulaengine/stylus_input_control"
        private const val EVENT_CHANNEL = "com.nebulaengine/stylus_input"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel?.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
    }

    // MARK: - MethodChannel Handler

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isStylusSupported" -> {
                result.success(hasStylusSupport())
            }
            "isHoverSupported" -> {
                // Hover is generally supported on devices with stylus input
                result.success(hasStylusSupport())
            }
            "isTiltSupported" -> {
                // Tilt data is available on Android 5.0+ (API 21+) with stylus
                result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && hasStylusSupport())
            }
            "getStylusCapabilities" -> {
                result.success(getStylusCapabilities())
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    // MARK: - EventChannel StreamHandler

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // MARK: - Stylus Event Processing

    /**
     * Process a hover event and send stylus metadata to Flutter.
     * Call from Activity's dispatchGenericMotionEvent.
     */
    fun processHoverEvent(event: MotionEvent) {
        if (eventSink == null) return
        if (event.getToolType(0) != MotionEvent.TOOL_TYPE_STYLUS) return

        when (event.actionMasked) {
            MotionEvent.ACTION_HOVER_ENTER,
            MotionEvent.ACTION_HOVER_MOVE,
            MotionEvent.ACTION_HOVER_EXIT -> {
                val state = when (event.actionMasked) {
                    MotionEvent.ACTION_HOVER_ENTER -> "began"
                    MotionEvent.ACTION_HOVER_MOVE -> "changed"
                    MotionEvent.ACTION_HOVER_EXIT -> "ended"
                    else -> "changed"
                }

                val hoverData = mutableMapOf<String, Any>(
                    "type" to "hover",
                    "x" to event.x.toDouble(),
                    "y" to event.y.toDouble(),
                    "state" to state,
                    "isHovering" to (state != "ended"),
                    "toolType" to "stylus",
                    "timestamp" to event.eventTime
                )

                // Add tilt data if available
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    hoverData["tiltX"] = event.getAxisValue(MotionEvent.AXIS_TILT).toDouble()
                    hoverData["orientation"] = event.getAxisValue(MotionEvent.AXIS_ORIENTATION).toDouble()
                    // Calculate altitude from tilt (0 = touching surface, PI/2 = perpendicular)
                    val tilt = event.getAxisValue(MotionEvent.AXIS_TILT).toDouble()
                    hoverData["altitude"] = (Math.PI / 2.0) - tilt
                    hoverData["distance"] = event.getAxisValue(MotionEvent.AXIS_DISTANCE).toDouble()
                }

                eventSink?.success(mapOf("hover_event" to hoverData))
            }
        }
    }

    /**
     * Extract enhanced stylus metadata from a touch MotionEvent.
     * Call from Activity's dispatchTouchEvent for stylus-type input only.
     *
     * Returns a Map with stylus metadata to merge with PredictedTouchPlugin data,
     * or null if the event is not from a stylus.
     */
    fun processStylusTouchEvent(event: MotionEvent) {
        if (eventSink == null) return
        if (event.getToolType(0) != MotionEvent.TOOL_TYPE_STYLUS) return

        val metadata = mutableMapOf<String, Any>(
            "type" to "stylus_metadata",
            "x" to event.x.toDouble(),
            "y" to event.y.toDouble(),
            "pressure" to event.pressure.toDouble(),
            "size" to event.size.toDouble(),
            "toolType" to "stylus",
            "timestamp" to event.eventTime,
            "action" to actionToString(event.actionMasked)
        )

        // Tilt and orientation (API 21+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            metadata["tiltX"] = event.getAxisValue(MotionEvent.AXIS_TILT).toDouble()
            metadata["orientation"] = event.getAxisValue(MotionEvent.AXIS_ORIENTATION).toDouble()
            metadata["altitude"] = (Math.PI / 2.0) - event.getAxisValue(MotionEvent.AXIS_TILT).toDouble()
        }

        // Button state (S Pen button)
        metadata["buttonState"] = event.buttonState
        metadata["isButtonPressed"] = (event.buttonState and MotionEvent.BUTTON_STYLUS_PRIMARY) != 0

        eventSink?.success(mapOf("stylus_event" to metadata))
    }

    // MARK: - Helper Methods

    /**
     * Check if any connected input device supports stylus input.
     */
    private fun hasStylusSupport(): Boolean {
        val deviceIds = InputDevice.getDeviceIds()
        for (id in deviceIds) {
            val device = InputDevice.getDevice(id) ?: continue
            val sources = device.sources
            if (sources and InputDevice.SOURCE_STYLUS == InputDevice.SOURCE_STYLUS) {
                return true
            }
        }
        return false
    }

    /**
     * Get detailed stylus capabilities for the current device.
     */
    private fun getStylusCapabilities(): Map<String, Any> {
        val caps = mutableMapOf<String, Any>(
            "hasStylusSupport" to hasStylusSupport(),
            "hasTilt" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP),
            "hasPressure" to true,
            "hasPalmRejection" to true,
            "hasHover" to hasStylusSupport(),
            "hasButton" to hasStylusSupport(),
            "apiLevel" to Build.VERSION.SDK_INT
        )

        // Check for specific device features
        val deviceIds = InputDevice.getDeviceIds()
        for (id in deviceIds) {
            val device = InputDevice.getDevice(id) ?: continue
            if (device.sources and InputDevice.SOURCE_STYLUS == InputDevice.SOURCE_STYLUS) {
                caps["stylusDeviceName"] = device.name
                caps["stylusProductId"] = device.productId
                caps["stylusVendorId"] = device.vendorId
                break
            }
        }

        return caps
    }

    private fun actionToString(action: Int): String {
        return when (action) {
            MotionEvent.ACTION_DOWN -> "down"
            MotionEvent.ACTION_MOVE -> "move"
            MotionEvent.ACTION_UP -> "up"
            MotionEvent.ACTION_CANCEL -> "cancel"
            else -> "unknown"
        }
    }
}
