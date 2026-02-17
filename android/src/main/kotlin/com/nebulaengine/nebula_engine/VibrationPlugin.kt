package com.nebulaengine.nebula_engine

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 📳 Plugin nativo per la gestione della vibrazione su Android
 *
 * Supporta:
 * - Vibrazione semplice con durata e ampiezza
 * - Pattern di vibrazione complessi con intensità variabile
 * - Controllo della disponibilità dell'hardware
 * - Cancellazione della vibrazione attiva
 * - Supporto per Android 12+ (VibratorManager) e versioni precedenti
 */
class VibrationPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    // MARK: - Properties

    private lateinit var channel: MethodChannel
    private var vibrator: Vibrator? = null
    private var context: Context? = null

    // MARK: - FlutterPlugin Implementation

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "nebulaengine.vibration/method")
        channel.setMethodCallHandler(this)

        // Inizializza il Vibrator
        setupVibrator()

        Unit
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        vibrator?.cancel()
        vibrator = null
        context = null
    }

    // MARK: - Setup

    private fun setupVibrator() {
        context?.let { ctx ->
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                ctx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        }
    }

    // MARK: - Method Channel Handler

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasVibrator" -> handleHasVibrator(result)
            "vibrate" -> handleVibrate(call, result)
            "cancel" -> handleCancel(result)
            else -> result.notImplemented()
        }
    }

    private fun handleHasVibrator(result: MethodChannel.Result) {
        val hasVibrator = vibrator?.hasVibrator() ?: false
        result.success(hasVibrator)
    }

    private fun handleVibrate(call: MethodCall, result: MethodChannel.Result) {
        val vibrator = this.vibrator
        if (vibrator == null || !vibrator.hasVibrator()) {
            result.error("NO_VIBRATOR", "Device does not have a vibrator", null)
            return
        }

        try {
            vibrator.cancel()

            val duration = call.argument<Int>("duration")
            val amplitude = call.argument<Int>("amplitude")
            val pattern = call.argument<List<Int>>("pattern")
            val intensities = call.argument<List<Int>>("intensities")

            when {
                pattern != null -> {
                    vibrateWithPattern(vibrator, pattern, intensities)
                }
                duration != null -> {
                    vibrateWithDuration(vibrator, duration, amplitude)
                }
                else -> {
                    vibrateWithDuration(vibrator, 400, amplitude)
                }
            }

            result.success(null)
        } catch (e: Exception) {
            result.error("VIBRATION_ERROR", "Error during vibration: ${e.message}", null)
        }
    }

    private fun handleCancel(result: MethodChannel.Result) {
        try {
            vibrator?.cancel()
            result.success(null)
        } catch (e: Exception) {
            result.error("CANCEL_ERROR", "Error during cancellation: ${e.message}", null)
        }
    }

    private fun vibrateWithDuration(vibrator: Vibrator, duration: Int, amplitude: Int?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val effectiveAmplitude = when {
                amplitude != null -> amplitude.coerceIn(1, 255)
                else -> VibrationEffect.DEFAULT_AMPLITUDE
            }

            val effect = VibrationEffect.createOneShot(
                duration.toLong(),
                effectiveAmplitude
            )
            vibrator.vibrate(effect)
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(duration.toLong())
        }
    }

    private fun vibrateWithPattern(vibrator: Vibrator, pattern: List<Int>, intensities: List<Int>?) {
        val timings = pattern.map { it.toLong() }.toLongArray()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (intensities != null && intensities.isNotEmpty()) {
                val amplitudes = IntArray(pattern.size) { index ->
                    if (index % 2 == 0) {
                        0
                    } else {
                        val intensityIndex = index / 2
                        if (intensityIndex < intensities.size) {
                            intensities[intensityIndex].coerceIn(1, 255)
                        } else {
                            VibrationEffect.DEFAULT_AMPLITUDE
                        }
                    }
                }

                val effect = VibrationEffect.createWaveform(timings, amplitudes, -1)
                vibrator.vibrate(effect)
            } else {
                val effect = VibrationEffect.createWaveform(timings, -1)
                vibrator.vibrate(effect)
            }
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(timings, -1)
        }
    }
}
