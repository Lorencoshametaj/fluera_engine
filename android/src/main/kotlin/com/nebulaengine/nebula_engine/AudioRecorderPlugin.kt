package com.nebulaengine.nebula_engine

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.log10
import kotlin.math.pow

/**
 * 🎤 AudioRecorderPlugin — Native audio recorder for Nebula Engine (Android)
 *
 * Uses MediaRecorder for audio capture. Supports:
 * - Start/stop/pause/resume recording
 * - Configurable format, sample rate, bit rate, channels
 * - Real-time amplitude and duration updates via EventChannel
 * - Permission checking (actual permission request must be handled by the host app Activity)
 *
 * Platform Channel: nebulaengine.audio/recorder
 * Event Channel: nebulaengine.audio/recorder_events
 */
class AudioRecorderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    // MARK: - Properties

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var context: Context? = null

    private var mediaRecorder: MediaRecorder? = null
    private var recordingFilePath: String? = null
    private var eventSink: EventChannel.EventSink? = null
    private var updateHandler: Handler? = null
    private var updateRunnable: Runnable? = null
    private var recordingStartTime: Long = 0
    private var pausedDuration: Long = 0
    private var pauseStartTime: Long = 0
    private var isPaused = false
    private var isRecording = false

    // MARK: - FlutterPlugin Implementation

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, "nebulaengine.audio/recorder")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "nebulaengine.audio/recorder_events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        stopUpdateTimer()
        releaseRecorder()
        context = null
    }

    // MARK: - MethodChannel Handler

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> handleInitialize(result)
            "startRecording" -> handleStartRecording(call, result)
            "stopRecording" -> handleStopRecording(result)
            "pauseRecording" -> handlePauseRecording(result)
            "resumeRecording" -> handleResumeRecording(result)
            "cancelRecording" -> handleCancelRecording(result)
            "hasPermission" -> handleHasPermission(result)
            "requestPermission" -> handleRequestPermission(result)
            else -> result.notImplemented()
        }
    }

    // MARK: - EventChannel StreamHandler

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // MARK: - Method Handlers

    private fun handleInitialize(result: MethodChannel.Result) {
        result.success(null)
    }

    private fun handleStartRecording(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: run {
            result.error("NO_CONTEXT", "Application context not available", null)
            return
        }

        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val formatStr = args["format"] as? String ?: "m4a"
        val sampleRate = (args["sampleRate"] as? Int) ?: 44100
        val bitRate = (args["bitRate"] as? Int) ?: 128000
        val numChannels = (args["numChannels"] as? Int) ?: 1

        try {
            // Create temp file
            val extension = when (formatStr) {
                "wav" -> "wav"
                "aac" -> "aac"
                else -> "m4a"
            }

            val fileName = "nebula_recording_${System.currentTimeMillis()}.$extension"
            val outputFile = File(ctx.cacheDir, fileName)
            recordingFilePath = outputFile.absolutePath

            // Configure MediaRecorder
            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(ctx)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }

            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)

            when (formatStr) {
                "wav" -> {
                    recorder.setOutputFormat(MediaRecorder.OutputFormat.DEFAULT)
                    recorder.setAudioEncoder(MediaRecorder.AudioEncoder.DEFAULT)
                }
                else -> {
                    recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                    recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                }
            }

            recorder.setAudioSamplingRate(sampleRate)
            recorder.setAudioEncodingBitRate(bitRate)
            recorder.setAudioChannels(numChannels)
            recorder.setOutputFile(outputFile.absolutePath)

            recorder.prepare()
            recorder.start()

            mediaRecorder = recorder
            isRecording = true
            isPaused = false
            recordingStartTime = System.currentTimeMillis()
            pausedDuration = 0
            pauseStartTime = 0

            sendState("recording")
            startUpdateTimer()

            result.success(null)
        } catch (e: Exception) {
            sendError("Failed to start recording: ${e.message}")
            result.error("RECORD_ERROR", "Failed to start recording", e.message)
        }
    }

    private fun handleStopRecording(result: MethodChannel.Result) {
        if (!isRecording) {
            result.error("NOT_RECORDING", "Not currently recording", null)
            return
        }

        try {
            mediaRecorder?.stop()
            mediaRecorder?.release()
            mediaRecorder = null
            stopUpdateTimer()

            isRecording = false
            isPaused = false
            val path = recordingFilePath

            sendState("stopped")

            recordingStartTime = 0
            pausedDuration = 0
            pauseStartTime = 0

            result.success(path)
        } catch (e: Exception) {
            releaseRecorder()
            result.error("STOP_ERROR", "Failed to stop recording", e.message)
        }
    }

    private fun handlePauseRecording(result: MethodChannel.Result) {
        if (!isRecording || isPaused) {
            result.error("NOT_RECORDING", "Not currently recording or already paused", null)
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                mediaRecorder?.pause()
                isPaused = true
                pauseStartTime = System.currentTimeMillis()
                sendState("paused")
                result.success(null)
            } else {
                result.error("UNSUPPORTED", "Pause not supported on this Android version (requires API 24+)", null)
            }
        } catch (e: Exception) {
            result.error("PAUSE_ERROR", "Failed to pause recording", e.message)
        }
    }

    private fun handleResumeRecording(result: MethodChannel.Result) {
        if (!isRecording || !isPaused) {
            result.error("NOT_PAUSED", "Not currently paused", null)
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                mediaRecorder?.resume()
                isPaused = false
                if (pauseStartTime > 0) {
                    pausedDuration += System.currentTimeMillis() - pauseStartTime
                    pauseStartTime = 0
                }
                sendState("recording")
                result.success(null)
            } else {
                result.error("UNSUPPORTED", "Resume not supported on this Android version (requires API 24+)", null)
            }
        } catch (e: Exception) {
            result.error("RESUME_ERROR", "Failed to resume recording", e.message)
        }
    }

    private fun handleCancelRecording(result: MethodChannel.Result) {
        releaseRecorder()

        // Delete temp file
        recordingFilePath?.let { path ->
            try {
                File(path).delete()
            } catch (_: Exception) { }
        }

        recordingFilePath = null
        isRecording = false
        isPaused = false
        recordingStartTime = 0
        pausedDuration = 0
        pauseStartTime = 0

        sendState("idle")
        result.success(null)
    }

    private fun handleHasPermission(result: MethodChannel.Result) {
        val ctx = context ?: run {
            result.success(false)
            return
        }

        val permissionStatus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ctx.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED
        } else {
            true // Below M, permissions are granted at install time
        }
        result.success(permissionStatus)
    }

    private fun handleRequestPermission(result: MethodChannel.Result) {
        // Cannot request permissions from a plugin without Activity context.
        // The host app must handle runtime permission requests.
        // Return current permission status instead.
        handleHasPermission(result)
    }

    // MARK: - Timer & Event Sending

    private fun startUpdateTimer() {
        stopUpdateTimer()
        updateHandler = Handler(Looper.getMainLooper())
        updateRunnable = object : Runnable {
            override fun run() {
                sendPeriodicUpdate()
                updateHandler?.postDelayed(this, 100)
            }
        }
        updateHandler?.postDelayed(updateRunnable!!, 100)
    }

    private fun stopUpdateTimer() {
        updateRunnable?.let { updateHandler?.removeCallbacks(it) }
        updateRunnable = null
        updateHandler = null
    }

    private fun sendPeriodicUpdate() {
        if (!isRecording || recordingStartTime == 0L) return

        // Duration (excluding paused time)
        val totalElapsed = System.currentTimeMillis() - recordingStartTime
        val currentPauseDuration = if (isPaused && pauseStartTime > 0) {
            System.currentTimeMillis() - pauseStartTime
        } else {
            0L
        }
        val effectiveDuration = totalElapsed - pausedDuration - currentPauseDuration
        sendDuration(effectiveDuration.coerceAtLeast(0).toInt())

        // Amplitude
        try {
            val maxAmplitude = mediaRecorder?.maxAmplitude ?: 0
            // Convert to 0.0 - 1.0 range (MediaRecorder.maxAmplitude range: 0 to 32767)
            val normalized = if (maxAmplitude > 0) {
                maxAmplitude.toDouble() / 32767.0
            } else {
                0.0
            }
            sendAmplitude(current = normalized, max = normalized)
        } catch (_: Exception) {
            // MediaRecorder may not be ready
        }
    }

    private fun sendState(state: String) {
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(mapOf("event" to "state", "state" to state))
        }
    }

    private fun sendDuration(durationMs: Int) {
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(mapOf("event" to "duration", "duration" to durationMs))
        }
    }

    private fun sendAmplitude(current: Double, max: Double) {
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(mapOf("event" to "amplitude", "current" to current, "max" to max))
        }
    }

    private fun sendError(message: String) {
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(mapOf("event" to "error", "error" to message))
        }
    }

    private fun releaseRecorder() {
        try {
            mediaRecorder?.stop()
        } catch (_: Exception) { }
        try {
            mediaRecorder?.release()
        } catch (_: Exception) { }
        mediaRecorder = null
        stopUpdateTimer()
    }
}
