package com.nebulaengine.nebula_engine

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 📊 PerformanceMonitorPlugin — Native Android Performance Metrics
 *
 * Provides real-time access to Android-specific performance data:
 * - **Memory**: Java heap, native heap, PSS, total RAM
 * - **Thermal**: Thermal throttle status (API 29+)
 * - **Battery**: Level, charging state, low power mode
 *
 * Channel: com.nebulaengine/performance_monitor
 * Control: com.nebulaengine/performance_monitor_control
 */
class PerformanceMonitorPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var context: Context? = null

    private var monitorHandler: Handler? = null
    private var monitorRunnable: Runnable? = null
    private var isMonitoring = false
    private var samplingIntervalMs: Long = 1000L

    companion object {
        private const val METHOD_CHANNEL = "com.nebulaengine/performance_monitor_control"
        private const val EVENT_CHANNEL = "com.nebulaengine/performance_monitor"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel?.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopMonitoring()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        context = null
    }

    // MARK: - Method Channel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startMonitoring" -> {
                val intervalMs = call.argument<Int>("intervalMs") ?: 1000
                samplingIntervalMs = maxOf(100L, intervalMs.toLong())
                startMonitoring()
                result.success(null)
            }
            "stopMonitoring" -> {
                stopMonitoring()
                result.success(null)
            }
            "getSnapshot" -> {
                result.success(collectMetrics())
            }
            "getCapabilities" -> {
                result.success(getCapabilities())
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    // MARK: - Event Channel

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        stopMonitoring()
    }

    // MARK: - Monitoring

    private fun startMonitoring() {
        if (isMonitoring) return
        isMonitoring = true

        monitorHandler = Handler(Looper.getMainLooper())
        monitorRunnable = object : Runnable {
            override fun run() {
                if (!isMonitoring) return
                val metrics = collectMetrics()
                eventSink?.success(metrics)
                monitorHandler?.postDelayed(this, samplingIntervalMs)
            }
        }
        monitorHandler?.postDelayed(monitorRunnable!!, samplingIntervalMs)
    }

    private fun stopMonitoring() {
        isMonitoring = false
        monitorRunnable?.let { monitorHandler?.removeCallbacks(it) }
        monitorHandler = null
        monitorRunnable = null
    }

    // MARK: - Metric Collection

    private fun collectMetrics(): Map<String, Any> {
        val metrics = mutableMapOf<String, Any>(
            "timestamp" to System.currentTimeMillis(),
            "platform" to "Android"
        )

        metrics.putAll(collectMemoryMetrics())
        metrics.putAll(collectThermalMetrics())
        metrics.putAll(collectBatteryMetrics())

        return metrics
    }

    private fun collectMemoryMetrics(): Map<String, Any> {
        val ctx = context ?: return emptyMap()
        val activityManager = ctx.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return emptyMap()

        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)

        val runtime = Runtime.getRuntime()
        val javaHeapUsedMB = (runtime.totalMemory() - runtime.freeMemory()) / (1024.0 * 1024.0)
        val javaHeapMaxMB = runtime.maxMemory() / (1024.0 * 1024.0)

        val nativeHeapMB = android.os.Debug.getNativeHeapAllocatedSize() / (1024.0 * 1024.0)

        val totalRamMB = memoryInfo.totalMem / (1024.0 * 1024.0)
        val availRamMB = memoryInfo.availMem / (1024.0 * 1024.0)
        val usedRamMB = totalRamMB - availRamMB
        val memoryUsagePercent = (usedRamMB / totalRamMB) * 100.0

        return mapOf(
            "memoryUsedMB" to usedRamMB,
            "memoryTotalMB" to totalRamMB,
            "memoryAvailableMB" to availRamMB,
            "memoryUsagePercent" to memoryUsagePercent,
            "javaHeapUsedMB" to javaHeapUsedMB,
            "javaHeapMaxMB" to javaHeapMaxMB,
            "nativeHeapMB" to nativeHeapMB,
            "isLowMemory" to memoryInfo.lowMemory,
            "memoryPressureLevel" to getMemoryPressureLevel(memoryUsagePercent)
        )
    }

    private fun getMemoryPressureLevel(usagePercent: Double): String {
        return when {
            usagePercent > 80 -> "critical"
            usagePercent > 60 -> "warning"
            else -> "normal"
        }
    }

    private fun collectThermalMetrics(): Map<String, Any> {
        val metrics = mutableMapOf<String, Any>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // API 29+ provides PowerManager thermal status
            try {
                val powerManager = context?.getSystemService(Context.POWER_SERVICE)
                        as? android.os.PowerManager
                if (powerManager != null) {
                    val thermalStatus = powerManager.currentThermalStatus
                    metrics["thermalState"] = when (thermalStatus) {
                        android.os.PowerManager.THERMAL_STATUS_NONE -> "nominal"
                        android.os.PowerManager.THERMAL_STATUS_LIGHT -> "fair"
                        android.os.PowerManager.THERMAL_STATUS_MODERATE -> "fair"
                        android.os.PowerManager.THERMAL_STATUS_SEVERE -> "serious"
                        android.os.PowerManager.THERMAL_STATUS_CRITICAL -> "critical"
                        android.os.PowerManager.THERMAL_STATUS_EMERGENCY -> "critical"
                        android.os.PowerManager.THERMAL_STATUS_SHUTDOWN -> "critical"
                        else -> "unknown"
                    }
                    metrics["thermalThrottled"] = thermalStatus >=
                            android.os.PowerManager.THERMAL_STATUS_SEVERE
                }
            } catch (e: Exception) {
                metrics["thermalState"] = "unknown"
                metrics["thermalThrottled"] = false
            }
        } else {
            metrics["thermalState"] = "unknown"
            metrics["thermalThrottled"] = false
        }

        return metrics
    }

    private fun collectBatteryMetrics(): Map<String, Any> {
        val ctx = context ?: return emptyMap()

        val batteryIntent = ctx.registerReceiver(null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED))

        if (batteryIntent != null) {
            val level = batteryIntent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = batteryIntent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            val batteryPercent = if (level >= 0 && scale > 0) {
                (level.toDouble() / scale.toDouble()) * 100.0
            } else {
                -1.0
            }

            val status = batteryIntent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            val batteryState = when (status) {
                BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
                BatteryManager.BATTERY_STATUS_FULL -> "full"
                BatteryManager.BATTERY_STATUS_NOT_CHARGING,
                BatteryManager.BATTERY_STATUS_DISCHARGING -> "unplugged"
                else -> "unknown"
            }

            val powerManager = ctx.getSystemService(Context.POWER_SERVICE)
                    as? android.os.PowerManager
            val isLowPowerMode = powerManager?.isPowerSaveMode ?: false

            return mapOf(
                "batteryLevel" to batteryPercent,
                "batteryState" to batteryState,
                "isLowPowerMode" to isLowPowerMode
            )
        }

        return mapOf(
            "batteryLevel" to -1.0,
            "batteryState" to "unknown",
            "isLowPowerMode" to false
        )
    }

    // MARK: - Capabilities

    private fun getCapabilities(): Map<String, Any> {
        return mapOf(
            "hasMemoryMonitoring" to true,
            "hasThermalMonitoring" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q),
            "hasBatteryMonitoring" to true,
            "hasGPUMonitoring" to false,
            "platform" to "Android",
            "osVersion" to Build.VERSION.RELEASE,
            "apiLevel" to Build.VERSION.SDK_INT,
            "deviceModel" to Build.MODEL
        )
    }
}
