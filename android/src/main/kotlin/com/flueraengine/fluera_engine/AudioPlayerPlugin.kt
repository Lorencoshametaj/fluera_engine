package com.flueraengine.fluera_engine

import android.content.Context
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 🎵 AudioPlayerPlugin — Native audio playback for Fluera Engine.
 *
 * Handles playback of recorded audio files using Android MediaPlayer.
 *
 * Platform Channel: flueraengine.audio/player
 * Event Channel: flueraengine.audio/player_events
 */
class AudioPlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var context: Context? = null

    private var mediaPlayer: MediaPlayer? = null
    private var eventSink: EventChannel.EventSink? = null
    private var updateHandler: Handler? = null
    private var updateRunnable: Runnable? = null
    private var isPrepared = false

    // MARK: - FlutterPlugin

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "flueraengine.audio/player")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "flueraengine.audio/player_events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        releasePlayer()
        context = null
    }

    // MARK: - MethodCallHandler

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> handleInitialize(result)
            "setFilePath" -> {
                val path = call.argument<String>("path")
                if (path != null) handleSetFilePath(path, result)
                else result.error("INVALID_ARGS", "path is required", null)
            }
            "play" -> handlePlay(result)
            "pause" -> handlePause(result)
            "stop" -> handleStop(result)
            "seek" -> {
                val position = call.argument<Int>("position") ?: 0
                handleSeek(position, result)
            }
            "setVolume" -> {
                val volume = call.argument<Double>("volume") ?: 1.0
                handleSetVolume(volume.toFloat(), result)
            }
            "setSpeed" -> {
                val speed = call.argument<Double>("speed") ?: 1.0
                handleSetSpeed(speed.toFloat(), result)
            }
            "getPosition" -> handleGetPosition(result)
            "getDuration" -> handleGetDuration(result)
            "getState" -> handleGetState(result)
            "release" -> {
                releasePlayer()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // MARK: - EventChannel.StreamHandler

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // MARK: - Player Methods

    private fun handleInitialize(result: MethodChannel.Result) {
        result.success(null)
    }

    private fun handleSetFilePath(path: String, result: MethodChannel.Result) {
        try {
            releasePlayer()

            val file = File(path)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "File not found: $path", null)
                return
            }

            mediaPlayer = MediaPlayer().apply {
                setDataSource(path)

                setOnCompletionListener {
                    stopPositionUpdates()
                    sendStateEvent("completed")
                }

                setOnErrorListener { _, what, extra ->
                    isPrepared = false
                    sendEvent("error", mapOf("error" to "MediaPlayer error: what=$what extra=$extra"))
                    true
                }

                // Use synchronous prepare for local files — fast and avoids race conditions
                prepare()
            }

            isPrepared = true
            sendStateEvent("ready")
            sendEvent("duration", mapOf("duration" to mediaPlayer!!.duration))
            result.success(null)
        } catch (e: Exception) {
            result.error("SET_FILE_FAILED", e.message, null)
        }
    }

    private fun handlePlay(result: MethodChannel.Result) {
        val player = mediaPlayer
        if (player == null || !isPrepared) {
            result.error("NOT_READY", "Player not ready", null)
            return
        }
        try {
            player.start()
            startPositionUpdates()
            sendStateEvent("playing")
            result.success(null)
        } catch (e: Exception) {
            result.error("PLAY_FAILED", e.message, null)
        }
    }

    private fun handlePause(result: MethodChannel.Result) {
        val player = mediaPlayer
        if (player == null || !isPrepared) {
            result.error("NOT_READY", "Player not ready", null)
            return
        }
        try {
            player.pause()
            stopPositionUpdates()
            sendStateEvent("paused")
            result.success(null)
        } catch (e: Exception) {
            result.error("PAUSE_FAILED", e.message, null)
        }
    }

    private fun handleStop(result: MethodChannel.Result) {
        val player = mediaPlayer
        if (player == null || !isPrepared) {
            result.success(null)
            return
        }
        try {
            player.stop()
            stopPositionUpdates()
            player.prepareAsync()
            sendStateEvent("stopped")
            result.success(null)
        } catch (e: Exception) {
            result.error("STOP_FAILED", e.message, null)
        }
    }

    private fun handleSeek(positionMs: Int, result: MethodChannel.Result) {
        val player = mediaPlayer
        if (player == null || !isPrepared) {
            result.error("NOT_READY", "Player not ready", null)
            return
        }
        try {
            player.seekTo(positionMs)
            result.success(null)
        } catch (e: Exception) {
            result.error("SEEK_FAILED", e.message, null)
        }
    }

    private fun handleSetVolume(volume: Float, result: MethodChannel.Result) {
        try {
            mediaPlayer?.setVolume(volume, volume)
            result.success(null)
        } catch (e: Exception) {
            result.error("VOLUME_FAILED", e.message, null)
        }
    }

    private fun handleSetSpeed(speed: Float, result: MethodChannel.Result) {
        val player = mediaPlayer
        if (player == null || !isPrepared) {
            result.error("NOT_READY", "Player not ready", null)
            return
        }
        try {
            val params = player.playbackParams.setSpeed(speed)
            player.playbackParams = params
            result.success(null)
        } catch (e: Exception) {
            result.error("SPEED_FAILED", e.message, null)
        }
    }

    private fun handleGetPosition(result: MethodChannel.Result) {
        val player = mediaPlayer
        if (player == null || !isPrepared) {
            result.success(0)
            return
        }
        result.success(player.currentPosition)
    }

    private fun handleGetDuration(result: MethodChannel.Result) {
        val player = mediaPlayer
        if (player == null || !isPrepared) {
            result.success(null)
            return
        }
        result.success(player.duration)
    }

    private fun handleGetState(result: MethodChannel.Result) {
        val player = mediaPlayer
        val state = when {
            player == null -> "idle"
            !isPrepared -> "loading"
            player.isPlaying -> "playing"
            else -> "paused"
        }
        result.success(mapOf("state" to state))
    }

    // MARK: - Position Updates

    private fun startPositionUpdates() {
        stopPositionUpdates()
        updateHandler = Handler(Looper.getMainLooper())
        updateRunnable = object : Runnable {
            override fun run() {
                val player = mediaPlayer ?: return
                if (isPrepared && player.isPlaying) {
                    sendEvent("position", mapOf("position" to player.currentPosition))
                    updateHandler?.postDelayed(this, 200)
                }
            }
        }
        updateHandler?.post(updateRunnable!!)
    }

    private fun stopPositionUpdates() {
        updateRunnable?.let { updateHandler?.removeCallbacks(it) }
        updateRunnable = null
        updateHandler = null
    }

    // MARK: - Event Sending

    private fun sendStateEvent(state: String) {
        sendEvent("state", mapOf("state" to state))
    }

    private fun sendEvent(type: String, data: Map<String, Any?>) {
        val event = mutableMapOf<String, Any?>("event" to type)
        event.putAll(data)
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(event)
        }
    }

    // MARK: - Release

    private fun releasePlayer() {
        stopPositionUpdates()
        try {
            mediaPlayer?.release()
        } catch (_: Exception) {}
        mediaPlayer = null
        isPrepared = false
    }
}
