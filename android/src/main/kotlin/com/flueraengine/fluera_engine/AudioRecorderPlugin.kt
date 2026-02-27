package com.flueraengine.fluera_engine

import android.app.Activity
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.NoiseSuppressor
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.pow
import java.io.RandomAccessFile

/**
 * 🎤 AudioRecorderPlugin — Native audio recorder for Fluera Engine (Android)
 *
 * Uses MediaRecorder for audio capture. Supports:
 * - Start/stop/pause/resume recording
 * - Configurable format, sample rate, bit rate, channels
 * - Real-time amplitude and duration updates via EventChannel
 * - Permission checking (actual permission request must be handled by the host app Activity)
 *
 * Platform Channel: flueraengine.audio/recorder
 * Event Channel: flueraengine.audio/recorder_events
 */
class AudioRecorderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {

    companion object {
        private const val PERMISSION_REQUEST_CODE = 29741
    }

    // MARK: - Properties

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    private var audioRecord: AudioRecord? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var autoGainControl: AutomaticGainControl? = null
    private var captureThread: Thread? = null
    private var pcmTempFile: RandomAccessFile? = null
    private var pcmTempPath: String? = null
    private var pcmSampleCount: Long = 0
    private var captureAmplitude: Double = 0.0
    private var recordingSampleRate: Int = 48000
    private var recordingBitRate: Int = 256000
    private var recordingFilePath: String? = null
    private var eventSink: EventChannel.EventSink? = null
    private var updateHandler: Handler? = null
    private var updateRunnable: Runnable? = null
    private var recordingStartTime: Long = 0
    private var pausedDuration: Long = 0
    private var pauseStartTime: Long = 0
    private var isPaused = false
    private var isRecording = false
    @Volatile private var isCapturing = false
    // Cached raw PCM from last recording for single-pass DSP + encoding
    private var cachedPcmSamples: ShortArray? = null
    private var cachedPcmSampleRate: Int = 48000

    // MARK: - FlutterPlugin Implementation

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, "flueraengine.audio/recorder")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "flueraengine.audio/recorder_events")
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
            "applyAudioProcessing" -> handleApplyAudioProcessing(call, result)
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
        val sampleRate = (args["sampleRate"] as? Int) ?: 48000
        val bitRate = (args["bitRate"] as? Int) ?: 256000
        val numChannels = (args["numChannels"] as? Int) ?: 1

        try {
            // Create output file path
            val fileName = "fluera_recording_${System.currentTimeMillis()}.m4a"
            val recordingsDir = File(ctx.filesDir, "recordings")
            if (!recordingsDir.exists()) recordingsDir.mkdirs()
            val outputFile = File(recordingsDir, fileName)
            recordingFilePath = outputFile.absolutePath
            recordingSampleRate = sampleRate
            recordingBitRate = bitRate

            // Configure AudioRecord (raw PCM capture)
            val channelConfig = if (numChannels == 2)
                AudioFormat.CHANNEL_IN_STEREO else AudioFormat.CHANNEL_IN_MONO
            val bufferSize = AudioRecord.getMinBufferSize(
                sampleRate, channelConfig, AudioFormat.ENCODING_PCM_16BIT
            ) * 2  // Double for safety

            @Suppress("MissingPermission")
            val recorder = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                sampleRate,
                channelConfig,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )

            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                recorder.release()
                result.error("RECORD_ERROR", "Failed to initialize AudioRecord", null)
                return
            }

            // Attach hardware audio effects
            val sessionId = recorder.audioSessionId
            Log.d("AudioRecorder", "🎤 AudioRecord sessionId=$sessionId")

            if (NoiseSuppressor.isAvailable()) {
                try {
                    noiseSuppressor = NoiseSuppressor.create(sessionId)
                    noiseSuppressor?.enabled = true
                    Log.d("AudioRecorder", "🔇 NoiseSuppressor attached (sessionId=$sessionId)")
                } catch (e: Exception) {
                    Log.w("AudioRecorder", "⚠️ NoiseSuppressor failed: ${e.message}")
                }
            } else {
                Log.d("AudioRecorder", "ℹ️ NoiseSuppressor not available on this device")
            }

            if (AcousticEchoCanceler.isAvailable()) {
                try {
                    echoCanceler = AcousticEchoCanceler.create(sessionId)
                    echoCanceler?.enabled = true
                    Log.d("AudioRecorder", "🔇 AcousticEchoCanceler attached")
                } catch (e: Exception) {
                    Log.w("AudioRecorder", "⚠️ AcousticEchoCanceler failed: ${e.message}")
                }
            }

            if (AutomaticGainControl.isAvailable()) {
                try {
                    autoGainControl = AutomaticGainControl.create(sessionId)
                    autoGainControl?.enabled = true
                    Log.d("AudioRecorder", "🔇 AutomaticGainControl attached")
                } catch (e: Exception) {
                    Log.w("AudioRecorder", "⚠️ AutomaticGainControl failed: ${e.message}")
                }
            }

            // Start recording
            recorder.startRecording()
            audioRecord = recorder
            isRecording = true
            isPaused = false
            isCapturing = true
            pcmSampleCount = 0

            // Create temp PCM file (streaming to disk, not RAM)
            val tempFile = File(ctx.cacheDir, "pcm_capture_${System.currentTimeMillis()}.raw")
            pcmTempPath = tempFile.absolutePath
            val raf = RandomAccessFile(tempFile, "rw")
            pcmTempFile = raf

            recordingStartTime = System.currentTimeMillis()
            pausedDuration = 0
            pauseStartTime = 0

            // Start capture thread
            captureThread = Thread({
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
                val buffer = ShortArray(bufferSize / 2)
                val byteBuffer = java.nio.ByteBuffer.allocate(bufferSize)
                    .order(java.nio.ByteOrder.LITTLE_ENDIAN)
                val shortView = byteBuffer.asShortBuffer()
                while (isCapturing) {
                    val readCount = recorder.read(buffer, 0, buffer.size)
                    if (readCount > 0 && !isPaused) {
                        // Bulk copy ShortArray → ByteBuffer (much faster than per-sample putShort)
                        byteBuffer.clear()
                        shortView.clear()
                        shortView.put(buffer, 0, readCount)
                        raf.write(byteBuffer.array(), 0, readCount * 2)
                        pcmSampleCount += readCount

                        // Fast amplitude: sample every 16th value instead of scanning all
                        var maxSample = 0
                        var i = 0
                        while (i < readCount) {
                            val v = abs(buffer[i].toInt())
                            if (v > maxSample) maxSample = v
                            i += 16
                        }
                        captureAmplitude = maxSample.toDouble() / 32767.0
                    }
                }
            }, "AudioCaptureThread")
            captureThread?.start()

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
            // Stop capture thread
            isCapturing = false
            captureThread?.join(2000)
            captureThread = null

            // Stop and release AudioRecord + effects
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
            releaseAudioEffects()
            stopUpdateTimer()

            isRecording = false
            isPaused = false

            // Read PCM from temp file → cache for single-pass DSP + encoding
            val path = recordingFilePath
            if (path != null && pcmTempPath != null && pcmSampleCount > 0) {
                val tempFile = File(pcmTempPath!!)
                val totalSamples = pcmSampleCount.toInt()
                val samples = ShortArray(totalSamples)

                // Close capture file handle first
                try { pcmTempFile?.close() } catch (_: Exception) { }
                pcmTempFile = null

                // Read all PCM data back
                val raf = RandomAccessFile(tempFile, "r")
                val readBuf = java.nio.ByteBuffer.allocate(totalSamples * 2)
                    .order(java.nio.ByteOrder.LITTLE_ENDIAN)
                raf.readFully(readBuf.array())
                readBuf.asShortBuffer().get(samples)
                raf.close()
                tempFile.delete()
                pcmTempPath = null

                Log.d("AudioRecorder", "📦 Read $totalSamples PCM samples from temp file")
                cachedPcmSamples = samples
                cachedPcmSampleRate = recordingSampleRate

                // Encode initial M4A (in case no processing is requested)
                encodeFromShortArray(samples, path, recordingSampleRate, 1, recordingBitRate)
            } else {
                // Cleanup if no data
                try { pcmTempFile?.close() } catch (_: Exception) { }
                pcmTempFile = null
                pcmTempPath?.let { File(it).delete() }
                pcmTempPath = null
            }

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
            isPaused = true
            pauseStartTime = System.currentTimeMillis()
            sendState("paused")
            result.success(null)
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
            isPaused = false
            if (pauseStartTime > 0) {
                pausedDuration += System.currentTimeMillis() - pauseStartTime
                pauseStartTime = 0
            }
            sendState("recording")
            result.success(null)
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
        val act = activity
        if (act == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            // No Activity or pre-M: just return current status
            handleHasPermission(result)
            return
        }

        // Already granted?
        val alreadyGranted = act.checkSelfPermission(
            android.Manifest.permission.RECORD_AUDIO
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (alreadyGranted) {
            result.success(true)
            return
        }

        // Store pending result and request permission via Activity
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            act,
            arrayOf(android.Manifest.permission.RECORD_AUDIO),
            PERMISSION_REQUEST_CODE
        )
    }

    // MARK: - ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    // MARK: - RequestPermissionsResultListener

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED

        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
        return true
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
        val durationMs = effectiveDuration.coerceAtLeast(0).toInt()
        val amplitude = captureAmplitude

        // Single Handler.post for both duration + amplitude (less UI thread overhead)
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(mapOf("event" to "duration", "duration" to durationMs))
            eventSink?.success(mapOf("event" to "amplitude", "current" to amplitude, "max" to amplitude))
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
        isCapturing = false
        try {
            captureThread?.join(1000)
        } catch (_: Exception) { }
        captureThread = null
        try {
            audioRecord?.stop()
        } catch (_: Exception) { }
        try {
            audioRecord?.release()
        } catch (_: Exception) { }
        audioRecord = null
        try { pcmTempFile?.close() } catch (_: Exception) { }
        pcmTempFile = null
        pcmTempPath?.let { try { File(it).delete() } catch (_: Exception) { } }
        pcmTempPath = null
        releaseAudioEffects()
        stopUpdateTimer()
    }

    private fun releaseAudioEffects() {
        try { noiseSuppressor?.release() } catch (_: Exception) { }
        try { echoCanceler?.release() } catch (_: Exception) { }
        try { autoGainControl?.release() } catch (_: Exception) { }
        noiseSuppressor = null
        echoCanceler = null
        autoGainControl = null
    }

    // =========================================================================
    // 🎛️ Audio Processing Pipeline (Post-Processing)
    // =========================================================================

    private fun handleApplyAudioProcessing(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        val sampleRate = call.argument<Int>("sampleRate") ?: 48000
        val highPassFilterHz = call.argument<Int>("highPassFilterHz") ?: 0
        val compressor = call.argument<Boolean>("compressor") ?: false
        val normalization = call.argument<Boolean>("normalization") ?: false

        if (filePath == null) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }

        Thread {
            try {
                val cached = cachedPcmSamples
                if (cached != null) {
                    // 🚀 Fast path: use cached PCM directly (no decode needed!)
                    Log.d("AudioRecorder", "🚀 Single-pass DSP on ${cached.size} cached PCM samples")
                    val doubleSamples = DoubleArray(cached.size) { cached[it].toDouble() }

                    // Apply DSP pipeline: HPF → RNNoise → Presence EQ → Compressor → Normalization
                    if (highPassFilterHz > 0) {
                        butterworth2ndOrderHPF(doubleSamples, highPassFilterHz.toDouble(), sampleRate.toDouble())
                    }
                    if (sampleRate == 48000) {
                        applyRNNoise(doubleSamples)
                    }
                    applyPresenceEQ(doubleSamples, sampleRate)
                    if (compressor) applyCompressor(doubleSamples, sampleRate)
                    if (normalization) applyNormalization(doubleSamples)

                    // Convert back and encode once
                    val processed = ShortArray(doubleSamples.size)
                    for (i in doubleSamples.indices) {
                        processed[i] = doubleSamples[i].coerceIn(-32768.0, 32767.0).toInt().toShort()
                    }
                    encodeFromShortArray(processed, filePath, sampleRate, 1, recordingBitRate)
                    cachedPcmSamples = null  // Free memory
                    Log.d("AudioRecorder", "✅ Single-pass processing complete")
                } else {
                    // Fallback: decode from file (for re-processing or external files)
                    processAudioFile(filePath, sampleRate, highPassFilterHz, compressor, normalization)
                }
                Handler(Looper.getMainLooper()).post {
                    result.success(filePath)
                }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post {
                    result.error("PROCESSING_ERROR", "Audio processing failed: ${e.message}", null)
                }
            }
        }.start()
    }

    /**
     * Full audio processing pipeline:
     * 1. Decode M4A → PCM
     * 2. High-pass filter (Butterworth 4th order)
     * 3. RNNoise neural denoising
     * 4. Compressor (evens dynamics)
     * 5. Normalization (peak → -3dB)
     * 6. Re-encode PCM → M4A
     */
    private fun processAudioFile(
        filePath: String,
        sampleRate: Int,
        highPassFilterHz: Int,
        compressor: Boolean,
        normalization: Boolean
    ) {
        val inputFile = File(filePath)
        if (!inputFile.exists()) throw Exception("Input file not found: $filePath")

        // --- Step 1: Decode to PCM ---
        val pcmSamples = decodeToShortArray(filePath)
        if (pcmSamples.isEmpty()) throw Exception("Failed to decode audio file")

        // Convert to double for higher precision processing
        val doubleSamples = DoubleArray(pcmSamples.size) { pcmSamples[it].toDouble() }

        // --- Step 2: High-pass filter ---
        if (highPassFilterHz > 0) {
            butterworth2ndOrderHPF(doubleSamples, highPassFilterHz.toDouble(), sampleRate.toDouble())
        }

        // --- Step 3: RNNoise neural denoising ---
        if (sampleRate == 48000) {
            applyRNNoise(doubleSamples)
        }

        // --- Step 4: Presence EQ (voice clarity boost) ---
        applyPresenceEQ(doubleSamples, sampleRate)

        // --- Step 5: Compressor ---
        if (compressor) {
            applyCompressor(doubleSamples, sampleRate)
        }

        // --- Step 5: Normalization ---
        if (normalization) {
            applyNormalization(doubleSamples)
        }

        // Convert back to short
        for (i in doubleSamples.indices) {
            pcmSamples[i] = doubleSamples[i].coerceIn(-32768.0, 32767.0).toInt().toShort()
        }

        // --- Step 6: Re-encode to M4A ---
        val tempFile = File(inputFile.parent, "processed_${inputFile.name}")
        encodeFromShortArray(pcmSamples, tempFile.absolutePath, sampleRate, 1, 256000)

        tempFile.copyTo(inputFile, overwrite = true)
        tempFile.delete()
    }

    // =========================================================================
    // DSP Functions
    // =========================================================================

    /**
     * 🧠 RNNoise neural denoising — processes audio through ML model.
     *
     * Operates on 480-sample frames at 48kHz (10ms windows).
     * Expects double samples in [-32768, 32767] range.
     */
    private fun applyRNNoise(samples: DoubleArray) {
        val rnnoise = try {
            RNNoise()
        } catch (e: Exception) {
            Log.w("AudioRecorder", "⚠️ RNNoise not available: ${e.message}")
            return
        }

        try {
            val frameSize = RNNoise.FRAME_SIZE  // 480
            val frame = FloatArray(frameSize)
            var framesProcessed = 0

            var i = 0
            while (i + frameSize <= samples.size) {
                // Convert Double → Float (RNNoise expects [-32768, 32767] floats)
                for (j in 0 until frameSize) {
                    frame[j] = samples[i + j].toFloat()
                }

                rnnoise.processFrame(frame)  // In-place denoising

                // Convert Float → Double back
                for (j in 0 until frameSize) {
                    samples[i + j] = frame[j].toDouble()
                }

                framesProcessed++
                i += frameSize
            }

            // Handle remaining samples (pad with zeros, process, copy back)
            if (i < samples.size) {
                frame.fill(0f)
                val remaining = samples.size - i
                for (j in 0 until remaining) {
                    frame[j] = samples[i + j].toFloat()
                }
                rnnoise.processFrame(frame)
                for (j in 0 until remaining) {
                    samples[i + j] = frame[j].toDouble()
                }
                framesProcessed++
            }

            Log.d("AudioRecorder", "🧠 RNNoise: processed $framesProcessed frames (${samples.size} samples)")
        } finally {
            rnnoise.destroy()
        }
    }

    /**
     * 4th-order Butterworth high-pass filter (in-place on doubles).
     * Cascades two 2nd-order stages for -24dB/octave roll-off.
     */
    private fun butterworth2ndOrderHPF(samples: DoubleArray, cutoffHz: Double, sampleRate: Double) {
        // Run two passes of 2nd-order Butterworth for 4th-order (-24dB/oct)
        butterworthHPFPass(samples, cutoffHz, sampleRate)
        butterworthHPFPass(samples, cutoffHz, sampleRate)
    }

    private fun butterworthHPFPass(samples: DoubleArray, cutoffHz: Double, sampleRate: Double) {
        val omega = 2.0 * Math.PI * cutoffHz / sampleRate
        val sinOmega = Math.sin(omega)
        val cosOmega = Math.cos(omega)
        val alpha = sinOmega / (2.0 * Math.sqrt(2.0))

        val a0 = 1.0 + alpha
        val b0 = ((1.0 + cosOmega) / 2.0) / a0
        val b1 = (-(1.0 + cosOmega)) / a0
        val b2 = ((1.0 + cosOmega) / 2.0) / a0
        val a1 = (-2.0 * cosOmega) / a0
        val a2 = (1.0 - alpha) / a0

        var x1 = 0.0; var x2 = 0.0
        var y1 = 0.0; var y2 = 0.0

        for (i in samples.indices) {
            val x0 = samples[i]
            val y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0
            samples[i] = y0
        }
    }

    /**
     * Presence EQ — subtle voice clarity boost.
     *
     * Parametric peaking filter centered at 3kHz with +3dB gain, Q=1.5.
     * Enhances voice intelligibility and "presence" without sounding harsh.
     * The 2-4kHz range is where human hearing is most sensitive (Fletcher-Munson).
     */
    private fun applyPresenceEQ(samples: DoubleArray, sampleRate: Int) {
        val centerHz = 3000.0
        val gainDb = 3.0
        val q = 1.5

        val A = Math.pow(10.0, gainDb / 40.0)
        val omega = 2.0 * Math.PI * centerHz / sampleRate
        val sinOmega = Math.sin(omega)
        val cosOmega = Math.cos(omega)
        val alpha = sinOmega / (2.0 * q)

        val a0 = 1.0 + alpha / A
        val b0 = (1.0 + alpha * A) / a0
        val b1 = (-2.0 * cosOmega) / a0
        val b2 = (1.0 - alpha * A) / a0
        val a1 = (-2.0 * cosOmega) / a0
        val a2 = (1.0 - alpha / A) / a0

        var x1 = 0.0; var x2 = 0.0
        var y1 = 0.0; var y2 = 0.0

        for (i in samples.indices) {
            val x0 = samples[i]
            val y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0
            samples[i] = y0
        }
    }



    /**
     * Compressor — reduces dynamic range for even, natural-sounding voice.
     *
     * Threshold: -18 dB  (only compresses louder parts)
     * Ratio:     2.5:1   (gentle — preserves natural dynamics)
     * Attack:    10ms    (lets transients through for natural feel)
     * Release:   100ms   (smooth release, no pumping)
     * Make-up:   auto    (compensates for volume reduction)
     */
    private fun applyCompressor(samples: DoubleArray, sampleRate: Int) {
        val thresholdDb = -18.0
        val ratio = 2.5
        val thresholdLinear = 32768.0 * Math.pow(10.0, thresholdDb / 20.0)
        val attackCoeff = 1.0 / (sampleRate * 0.010).coerceAtLeast(1.0)  // 10ms
        val releaseCoeff = 1.0 / (sampleRate * 0.100).coerceAtLeast(1.0) // 100ms

        var envelope = 0.0

        // Pass 1: Apply compression
        for (i in samples.indices) {
            val absVal = Math.abs(samples[i])

            // Track envelope
            val coeff = if (absVal > envelope) attackCoeff else releaseCoeff
            envelope += (absVal - envelope) * coeff

            if (envelope > thresholdLinear) {
                // Calculate gain reduction
                val overDb = 20.0 * Math.log10(envelope / thresholdLinear)
                val reducedDb = overDb * (1.0 - 1.0 / ratio)
                val gain = Math.pow(10.0, -reducedDb / 20.0)
                samples[i] *= gain
            }
        }

        // Pass 2: Auto make-up gain (bring peak back up)
        var peak = 0.0
        for (s in samples) {
            val absVal = Math.abs(s)
            if (absVal > peak) peak = absVal
        }
        if (peak > 0.0) {
            val makeupGain = (32768.0 * 0.707) / peak // target -3dB
            if (makeupGain > 1.0) {
                for (i in samples.indices) {
                    samples[i] *= makeupGain
                }
            }
        }
    }

    /**
     * Peak normalization to -3 dB.
     *
     * Finds the peak sample and scales everything so the peak hits -3dB (0.707).
     */
    private fun applyNormalization(samples: DoubleArray) {
        var peak = 0.0
        for (s in samples) {
            val absVal = Math.abs(s)
            if (absVal > peak) peak = absVal
        }

        if (peak < 1.0) return // Silence — nothing to normalize

        val targetPeak = 32768.0 * 0.707 // -3 dB
        val gain = targetPeak / peak

        for (i in samples.indices) {
            samples[i] *= gain
        }
    }

    // =========================================================================
    // Codec Utilities
    // =========================================================================

    /**
     * Decode an M4A/AAC file to a ShortArray of PCM samples.
     */
    private fun decodeToShortArray(filePath: String): ShortArray {
        val extractor = android.media.MediaExtractor()
        extractor.setDataSource(filePath)

        var audioTrackIdx = -1
        var audioFormat: android.media.MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(android.media.MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                audioTrackIdx = i
                audioFormat = format
                break
            }
        }
        if (audioTrackIdx < 0 || audioFormat == null) {
            extractor.release()
            throw Exception("No audio track found")
        }

        extractor.selectTrack(audioTrackIdx)
        val mime = audioFormat.getString(android.media.MediaFormat.KEY_MIME)!!
        val codec = android.media.MediaCodec.createDecoderByType(mime)
        codec.configure(audioFormat, null, null, 0)
        codec.start()

        val pcmChunks = mutableListOf<ShortArray>()
        val bufferInfo = android.media.MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false

        while (!outputDone) {
            if (!inputDone) {
                val inputIdx = codec.dequeueInputBuffer(10000)
                if (inputIdx >= 0) {
                    val inputBuf = codec.getInputBuffer(inputIdx)!!
                    val sampleSize = extractor.readSampleData(inputBuf, 0)
                    if (sampleSize < 0) {
                        codec.queueInputBuffer(inputIdx, 0, 0, 0,
                            android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(inputIdx, 0, sampleSize,
                            extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }

            val outputIdx = codec.dequeueOutputBuffer(bufferInfo, 10000)
            if (outputIdx >= 0) {
                if (bufferInfo.size > 0) {
                    val outputBuf = codec.getOutputBuffer(outputIdx)!!
                    val shortBuf = outputBuf.order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                    val samples = ShortArray(shortBuf.remaining())
                    shortBuf.get(samples)
                    pcmChunks.add(samples)
                }
                codec.releaseOutputBuffer(outputIdx, false)
                if (bufferInfo.flags and android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    outputDone = true
                }
            }
        }

        codec.stop()
        codec.release()
        extractor.release()

        val totalSize = pcmChunks.sumOf { it.size }
        val result = ShortArray(totalSize)
        var offset = 0
        for (chunk in pcmChunks) {
            chunk.copyInto(result, offset)
            offset += chunk.size
        }
        return result
    }

    /**
     * Encode a ShortArray of PCM samples to an M4A/AAC file.
     */
    private fun encodeFromShortArray(
        samples: ShortArray,
        outputPath: String,
        sampleRate: Int,
        channels: Int,
        bitRate: Int
    ) {
        val mime = android.media.MediaFormat.MIMETYPE_AUDIO_AAC
        val format = android.media.MediaFormat.createAudioFormat(mime, sampleRate, channels)
        format.setInteger(android.media.MediaFormat.KEY_AAC_PROFILE,
            android.media.MediaCodecInfo.CodecProfileLevel.AACObjectLC)
        format.setInteger(android.media.MediaFormat.KEY_BIT_RATE, bitRate)

        val codec = android.media.MediaCodec.createEncoderByType(mime)
        codec.configure(format, null, null, android.media.MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()

        val muxer = android.media.MediaMuxer(outputPath, android.media.MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var muxerTrackIdx = -1
        var muxerStarted = false

        val bufferInfo = android.media.MediaCodec.BufferInfo()
        var inputOffset = 0
        var inputDone = false
        var outputDone = false
        val bytesPerSample = 2

        while (!outputDone) {
            if (!inputDone) {
                val inputIdx = codec.dequeueInputBuffer(10000)
                if (inputIdx >= 0) {
                    val inputBuf = codec.getInputBuffer(inputIdx)!!
                    val capacity = inputBuf.capacity() / bytesPerSample
                    val remaining = samples.size - inputOffset
                    val count = minOf(capacity, remaining)

                    if (count <= 0) {
                        codec.queueInputBuffer(inputIdx, 0, 0, 0,
                            android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        val shortBuf = inputBuf.order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                        shortBuf.put(samples, inputOffset, count)
                        val presentationTimeUs = (inputOffset.toLong() * 1000000L) / sampleRate
                        codec.queueInputBuffer(inputIdx, 0, count * bytesPerSample,
                            presentationTimeUs, 0)
                        inputOffset += count
                    }
                }
            }

            val outputIdx = codec.dequeueOutputBuffer(bufferInfo, 10000)
            when {
                outputIdx == android.media.MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (!muxerStarted) {
                        muxerTrackIdx = muxer.addTrack(codec.outputFormat)
                        muxer.start()
                        muxerStarted = true
                    }
                }
                outputIdx >= 0 -> {
                    if (!muxerStarted) {
                        muxerTrackIdx = muxer.addTrack(codec.outputFormat)
                        muxer.start()
                        muxerStarted = true
                    }
                    if (bufferInfo.size > 0) {
                        val outputBuf = codec.getOutputBuffer(outputIdx)!!
                        outputBuf.position(bufferInfo.offset)
                        outputBuf.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(muxerTrackIdx, outputBuf, bufferInfo)
                    }
                    codec.releaseOutputBuffer(outputIdx, false)
                    if (bufferInfo.flags and android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                }
            }
        }

        codec.stop()
        codec.release()
        if (muxerStarted) {
            muxer.stop()
            muxer.release()
        }
    }
}
