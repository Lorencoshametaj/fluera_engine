package com.flueraengine.fluera_engine

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * 🎤 AudioRecordingService — foreground service that keeps the mic alive when
 * Fluera is minimized or the screen is locked.
 *
 * Without this service Android 12+ kills the recorder process within ~30s of
 * the app entering the background. With it, the OS shows a persistent
 * notification ("Fluera is recording") and lets the mic capture continue.
 *
 * IMPORTANT: foregroundServiceType in AndroidManifest.xml MUST be "microphone"
 * to match FOREGROUND_SERVICE_TYPE_MICROPHONE; otherwise Android 14+ throws
 * SecurityException at startForeground() time.
 *
 * Lifecycle:
 *  - [AudioRecorderPlugin.handleStartRecording] starts this service via
 *    [startServiceCompat] right before the AudioRecord.startRecording() call.
 *  - [AudioRecorderPlugin.handleStopRecording] / cancel stop it.
 *  - We expose no Binder (mic ownership stays in the plugin) and intentionally
 *    don't restart on death (START_NOT_STICKY).
 */
class AudioRecordingService : Service() {

    companion object {
        const val ACTION_START = "com.flueraengine.fluera_engine.START_AUDIO_RECORDING"
        const val ACTION_STOP = "com.flueraengine.fluera_engine.STOP_AUDIO_RECORDING"
        private const val NOTIFICATION_ID = 0x46FE  // "FluEra"
        private const val CHANNEL_ID = "fluera_audio_recording"
        private const val CHANNEL_NAME = "Voice recording"

        /**
         * Start the foreground service in a way that's compatible with the
         * caller's API level. Use this from the plugin instead of
         * `context.startForegroundService` so the call site stays simple.
         */
        fun startServiceCompat(context: Context) {
            val intent = Intent(context, AudioRecordingService::class.java).apply {
                action = ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopServiceCompat(context: Context) {
            val intent = Intent(context, AudioRecordingService::class.java).apply {
                action = ACTION_STOP
            }
            context.stopService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                ensureNotificationChannel()
                val notification = buildNotification()
                startForegroundCompat(notification)
            }
        }
        // Don't auto-restart — if the system kills us, the recorder is gone
        // anyway. The plugin will restart fresh on the next recording session.
        return START_NOT_STICKY
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Indicates Fluera is recording audio in the background"
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        // Tap the notification → bring the host activity back to foreground.
        // We look up the launcher activity dynamically so this service has
        // no hard dependency on Fluera's MainActivity class.
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launchIntent?.let {
            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            PendingIntent.getActivity(this, 0, it, pendingFlags)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Fluera")
            .setContentText("Recording in progress")
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .apply { contentIntent?.let { setContentIntent(it) } }
            .build()
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Q+ requires explicit foregroundServiceType; on 14+ this MUST
            // equal FOREGROUND_SERVICE_TYPE_MICROPHONE to match the manifest.
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }
}
