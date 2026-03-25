package com.flueraengine.fluera_engine

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.EventChannel

/**
 * 🔔 FlueraNotificationReceiver
 *
 * Single routing hub for ALL notification interactions:
 *
 *  1. ACTION_NOTIFICATION_TAP    – user tapped the notification body
 *  2. ACTION_NOTIFICATION_ACTION – user tapped an action button
 *  3. ACTION_DELIVER_SCHEDULED   – AlarmManager fires a scheduled notification
 *  4. BOOT_COMPLETED             – reschedules persisted alarms after reboot
 *
 * Every tap/action event is:
 *   a) pushed to Flutter via [EventChannel.EventSink] while the engine is alive, OR
 *   b) buffered in [pendingEvent] and flushed when the stream first subscribes
 *      (covers cold-start and deep-sleep wakeup scenarios).
 *
 * The receiver is the **only** code path that opens the host Activity for
 * notification interactions. This guarantees that [onNotificationTapped] always
 * fires before the app navigates, regardless of app state.
 */
class FlueraNotificationReceiver : BroadcastReceiver() {

    companion object {
        /** User tapped the notification body itself. */
        const val ACTION_NOTIFICATION_TAP    = "com.flueraengine.NOTIFICATION_TAP"

        /** User tapped one of the action buttons. */
        const val ACTION_NOTIFICATION_ACTION = "com.flueraengine.NOTIFICATION_ACTION"

        /** AlarmManager delivery for scheduled notifications. */
        const val ACTION_DELIVER_SCHEDULED   = "com.flueraengine.DELIVER_SCHEDULED"

        /** Extra: whether the action should bring the app to foreground. */
        const val EXTRA_OPEN_APP             = "fluera_open_app"

        /** Key for the RemoteInput text result. */
        const val EXTRA_INLINE_REPLY         = "fluera_inline_reply"

        /** Provider lambda set by [NotificationPlugin] to push events live. */
        var eventSinkProvider: (() -> EventChannel.EventSink?)? = null

        /**
         * Buffered event for when the Flutter EventChannel is not yet ready.
         * Flushed by [NotificationPlugin] when the stream subscribes.
         */
        var pendingEvent: Map<String, Any?>? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_NOTIFICATION_TAP    -> handleBodyTap(context, intent)
            ACTION_NOTIFICATION_ACTION -> handleActionTap(context, intent)
            ACTION_DELIVER_SCHEDULED   -> handleScheduledDelivery(context, intent)
            Intent.ACTION_BOOT_COMPLETED -> handleBootCompleted(context)
        }
    }

    // ── Body tap ──────────────────────────────────────────────────────────────
    //
    // The notification content-intent is a broadcast to this receiver.
    // We push the tap event to Flutter, then launch the Activity so the app
    // opens as the user expects.

    private fun handleBodyTap(context: Context, intent: Intent) {
        val notificationId = intent.getStringExtra(NotificationPlugin.EXTRA_NOTIFICATION_ID) ?: ""
        val data           = extractData(intent)

        val event: Map<String, Any?> = mapOf(
            "notificationId" to notificationId,
            "actionId"       to null,          // null = body tap
            "inputText"      to null,
            "data"           to data,
        )

        pushEvent(context, event)

        // Always bring the app to foreground for a body tap
        launchApp(context, notificationId, actionId = null, data = data)
    }

    // ── Action button tap ─────────────────────────────────────────────────────
    //
    // Both background-only and "openApp" actions come here first so the event
    // is always pushed to the EventChannel before (optionally) opening the app.

    private fun handleActionTap(context: Context, intent: Intent) {
        val notificationId = intent.getStringExtra(NotificationPlugin.EXTRA_NOTIFICATION_ID) ?: ""
        val actionId       = intent.getStringExtra(NotificationPlugin.EXTRA_ACTION_ID)
        val openApp        = intent.getBooleanExtra(EXTRA_OPEN_APP, false)
        val data           = extractData(intent)

        // Extract inline reply text if this action used RemoteInput
        val remoteInput = androidx.core.app.RemoteInput.getResultsFromIntent(intent)
        val inputText   = remoteInput?.getCharSequence(EXTRA_INLINE_REPLY)?.toString()

        val event: Map<String, Any?> = mapOf(
            "notificationId" to notificationId,
            "actionId"       to actionId,
            "inputText"      to inputText,
            "data"           to data,
        )

        pushEvent(context, event)

        if (openApp) {
            launchApp(context, notificationId, actionId = actionId, data = data)
        }
    }

    // ── Scheduled delivery ────────────────────────────────────────────────────

    private fun handleScheduledDelivery(context: Context, intent: Intent) {
        val notificationId = intent.getStringExtra(NotificationPlugin.EXTRA_NOTIFICATION_ID) ?: ""
        val intId          = notificationId.hashCode()

        // Only clean up persistence for one-shot (non-repeating) schedules.
        // Repeating alarms keep their SharedPrefs entry so they survive reboot.
        val prefs = context.getSharedPreferences("fluera_notifications", Context.MODE_PRIVATE)
        val stored = prefs.getString("scheduled_$intId", null)
        val isRepeating = stored?.contains("|repeat=") == true
        if (!isRepeating) {
            prefs.edit().remove("scheduled_$intId").apply()
        }

        // Recover display fields from intent extras (set by NotificationPlugin.handleSchedule)
        val title     = intent.getStringExtra("title") ?: "Fluera"
        val body      = intent.getStringExtra("body") ?: ""
        val channelId = intent.getStringExtra("channelId") ?: NotificationPlugin.CH_DEFAULT
        val sound     = intent.getStringExtra("sound")

        val soundUri = if (sound != null)
            android.net.Uri.parse("android.resource://${context.packageName}/raw/$sound")
        else null

        // Build content-intent that routes through this receiver (so the tap event fires)
        val tapIntent = Intent(context, FlueraNotificationReceiver::class.java).apply {
            action = ACTION_NOTIFICATION_TAP
            putExtra(NotificationPlugin.EXTRA_NOTIFICATION_ID, notificationId)
        }
        val tapPi = android.app.PendingIntent.getBroadcast(
            context, intId, tapIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val nm = androidx.core.app.NotificationManagerCompat.from(context)

        // Resolve app icon (same logic as NotificationPlugin.getSmallIconRes)
        val appIcon = try {
            val appInfo = context.packageManager.getApplicationInfo(context.packageName, android.content.pm.PackageManager.GET_META_DATA)
            val metaIcon = appInfo.metaData?.getInt("com.flueraengine.notification_icon", 0) ?: 0
            if (metaIcon != 0) metaIcon else if (appInfo.icon != 0) appInfo.icon else android.R.drawable.ic_dialog_info
        } catch (_: Exception) { android.R.drawable.ic_dialog_info }

        @Suppress("MissingPermission")
        nm.notify(
            intId,
            androidx.core.app.NotificationCompat.Builder(context, channelId)
                .setSmallIcon(appIcon)
                .setContentTitle(title)
                .setContentText(body)
                .setAutoCancel(true)
                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
                .setStyle(androidx.core.app.NotificationCompat.BigTextStyle().bigText(body))
                .setContentIntent(tapPi)
                .setSound(soundUri)
                .build()
        )
    }

    // ── Boot completed ────────────────────────────────────────────────────────

    private fun handleBootCompleted(context: Context) {
        val prefs = context.getSharedPreferences("fluera_notifications", Context.MODE_PRIVATE)
        val now   = System.currentTimeMillis()
        val am    = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager

        prefs.all.keys
            .filter { it.startsWith("scheduled_") }
            .forEach { key ->
                val value       = prefs.getString(key, null) ?: return@forEach
                // Format: "$deliverAtMs|$notifId" or "$deliverAtMs|$notifId|repeat=$interval|group=$gk"
                val parts       = value.split("|")
                val deliverAtMs = parts.getOrNull(0)?.toLongOrNull() ?: return@forEach
                val notifId     = parts.getOrNull(1) ?: return@forEach

                // Parse optional repeat interval
                val repeatPart  = parts.firstOrNull { it.startsWith("repeat=") }
                val repeatInterval = repeatPart?.removePrefix("repeat=")

                // For one-shot: skip if already past
                if (repeatInterval == null && deliverAtMs <= now) {
                    prefs.edit().remove(key).apply()
                    return@forEach
                }

                val intId = key.removePrefix("scheduled_").toIntOrNull() ?: return@forEach
                val rescheduleIntent = Intent(context, FlueraNotificationReceiver::class.java).apply {
                    action = ACTION_DELIVER_SCHEDULED
                    putExtra(NotificationPlugin.EXTRA_NOTIFICATION_ID, notifId)
                    // Also carry display extras for the scheduled delivery
                }
                val pi = android.app.PendingIntent.getBroadcast(
                    context, intId, rescheduleIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                )

                if (repeatInterval != null) {
                    // Repeating: calculate next fire time and use setRepeating
                    val intervalMs = when (repeatInterval) {
                        "hourly" -> android.app.AlarmManager.INTERVAL_HOUR
                        "weekly" -> android.app.AlarmManager.INTERVAL_DAY * 7
                        else     -> android.app.AlarmManager.INTERVAL_DAY
                    }
                    // If the original time has passed, advance to next valid trigger
                    var nextFire = deliverAtMs
                    while (nextFire <= now) nextFire += intervalMs
                    am.setRepeating(android.app.AlarmManager.RTC_WAKEUP, nextFire, intervalMs, pi)
                } else {
                    // One-shot: exact alarm
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        am.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, deliverAtMs, pi)
                    } else {
                        am.setExact(android.app.AlarmManager.RTC_WAKEUP, deliverAtMs, pi)
                    }
                }
            }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /** Extracts custom payload keys (prefixed with "data_") from the intent. */
    private fun extractData(intent: Intent): Map<String, String> {
        val data = mutableMapOf<String, String>()
        intent.extras?.keySet()
            ?.filter { it.startsWith("data_") }
            ?.forEach { key -> data[key.removePrefix("data_")] = intent.getStringExtra(key) ?: "" }
        return data
    }

    /**
     * Launches (or resumes) the host application's main Activity.
     *
     * Works across all app states:
     * - **Foreground**: onNewIntent fires, extras delivered
     * - **Background**: Activity resumes, onNewIntent fires, extras delivered
     * - **Cold start**: Activity created, extras available via getIntent()
     */
    private fun launchApp(
        context: Context,
        notificationId: String,
        actionId: String?,
        data: Map<String, String>,
    ) {
        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra(NotificationPlugin.EXTRA_NOTIFICATION_ID, notificationId)
                if (actionId != null) putExtra(NotificationPlugin.EXTRA_ACTION_ID, actionId)
                data.forEach { (k, v) -> putExtra("data_$k", v) }
            } ?: return

        context.startActivity(launchIntent)
    }

    /** Pushes an event to Flutter's EventChannel, or queues it if not yet ready. */
    private fun pushEvent(context: Context, event: Map<String, Any?>) {
        val sink = eventSinkProvider?.invoke()
        if (sink != null) {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                sink.success(event)
            }
        } else {
            // Buffer in SharedPreferences for cold start or background-action survival.
            // When NotificationPlugin is registered, it will flush the queue.
            val prefs = context.getSharedPreferences("fluera_notifications_queue", Context.MODE_PRIVATE)
            val json = org.json.JSONObject(event).toString()
            prefs.edit().putString("pending_${System.currentTimeMillis()}", json).apply()
        }
    }
}
