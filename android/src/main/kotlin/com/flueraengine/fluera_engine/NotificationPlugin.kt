package com.flueraengine.fluera_engine

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.URL

/**
 * 🔔 NotificationPlugin — Native local notifications for Fluera Engine (Android)
 *
 * Method channel: `flueraengine.notifications/method`
 * Event channel:  `flueraengine.notifications/events`
 *
 * Supported methods:
 *  - requestPermission → "granted" | "denied" | "alreadyGranted"
 *  - show              → displays an immediate notification
 *  - schedule          → schedules a notification via AlarmManager
 *  - cancel            → removes a single notification
 *  - cancelAll         → removes all notifications
 *  - setBadge          → no-op on Android (launcher-specific)
 *  - getDelivered      → list of active notifications
 *
 * Notification channels (created once on first run):
 *  - fluera_default  : general purpose, HIGH importance
 *  - fluera_study    : study/review sessions, HIGH importance
 *  - fluera_export   : export completions, DEFAULT importance
 *  - fluera_silent   : silent informational, LOW importance
 */
class NotificationPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware {

    // ── Channels ──────────────────────────────────────────────────────────────

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    // ── Context & Activity ────────────────────────────────────────────────────

    private var context: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var permissionResultCallback: ((Boolean) -> Unit)? = null

    companion object {
        const val METHOD_CHANNEL = "flueraengine.notifications/method"
        const val EVENT_CHANNEL  = "flueraengine.notifications/events"

        const val CH_DEFAULT = "fluera_default"
        const val CH_STUDY   = "fluera_study"
        const val CH_EXPORT  = "fluera_export"
        const val CH_SILENT  = "fluera_silent"

        const val PERMISSION_REQUEST_CODE = 9210
        const val EXTRA_NOTIFICATION_ID   = "fluera_notification_id"
        const val EXTRA_NOTIFICATION_DATA = "fluera_notification_data"
        const val EXTRA_ACTION_ID         = "fluera_action_id"
    }

    // ── FlutterPlugin ─────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                
                // Flush any buffered tap events from cold starts or deep sleep
                context?.let { ctx ->
                    val prefs = ctx.getSharedPreferences("fluera_notifications_queue", Context.MODE_PRIVATE)
                    val editor = prefs.edit()
                    var modified = false
                    prefs.all.forEach { (key, value) ->
                        if (key.startsWith("pending_")) {
                            try {
                                val json = org.json.JSONObject(value as String)
                                val event = mutableMapOf<String, Any?>()
                                event["notificationId"] = json.optString("notificationId").takeIf { it.isNotEmpty() }
                                event["actionId"] = json.optString("actionId").takeIf { it.isNotEmpty() }
                                event["inputText"] = json.optString("inputText").takeIf { it.isNotEmpty() }
                                
                                val dataJson = json.optJSONObject("data")
                                val dataMap = mutableMapOf<String, String>()
                                dataJson?.keys()?.forEach { k ->
                                    dataMap[k] = dataJson.getString(k)
                                }
                                event["data"] = dataMap
                                
                                eventSink?.success(event)
                            } catch (e: Exception) {}
                            editor.remove(key)
                            modified = true
                        }
                    }
                    if (modified) editor.apply()  // single batch commit
                }
            }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })

        // Make sink accessible to BroadcastReceiver
        FlueraNotificationReceiver.eventSinkProvider = { eventSink }

        createNotificationChannels()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        FlueraNotificationReceiver.eventSinkProvider = null
        context = null
    }

    // ── ActivityAware ─────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener { code, _, grantResults ->
            if (code == PERMISSION_REQUEST_CODE) {
                val granted = grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED
                permissionResultCallback?.invoke(granted)
                permissionResultCallback = null
                true
            } else false
        }
    }

    override fun onDetachedFromActivityForConfigChanges() { activityBinding = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activityBinding = binding }
    override fun onDetachedFromActivity() { activityBinding = null }

    // ── MethodChannel ─────────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission"      -> handleRequestPermission(result)
            "show"                   -> handleShow(call, result)
            "schedule"               -> handleSchedule(call, result)
            "scheduleRepeating"      -> handleScheduleRepeating(call, result)
            "cancel"                 -> handleCancel(call, result)
            "cancelAll"              -> handleCancelAll(result)
            "cancelGroup"            -> handleCancelGroup(call, result)
            "setBadge"               -> result.success(null) // no-op on Android
            "getDelivered"           -> handleGetDelivered(result)
            "getPending"             -> handleGetPending(result)
            "getInitialNotification" -> handleGetInitial(result)
            "createChannel"          -> handleCreateChannel(call, result)
            else                     -> result.notImplemented()
        }
    }

    // ── Get Initial Notification (cold start) ─────────────────────────────────

    private fun handleGetInitial(result: MethodChannel.Result) {
        val ctx = context ?: return result.success(null)
        val prefs = ctx.getSharedPreferences("fluera_notifications_queue", Context.MODE_PRIVATE)
        val firstEntry = prefs.all.entries
            .filter { it.key.startsWith("pending_") }
            .minByOrNull { it.key }
        
        if (firstEntry != null) {
            try {
                val json = org.json.JSONObject(firstEntry.value as String)
                val event = mutableMapOf<String, Any?>()
                event["notificationId"] = json.optString("notificationId").takeIf { it.isNotEmpty() }
                event["actionId"] = json.optString("actionId").takeIf { it.isNotEmpty() }
                event["inputText"] = json.optString("inputText").takeIf { it.isNotEmpty() }
                val dataJson = json.optJSONObject("data")
                val dataMap = mutableMapOf<String, String>()
                dataJson?.keys()?.forEach { k -> dataMap[k] = dataJson.getString(k) }
                event["data"] = dataMap
                result.success(event)
            } catch (e: Exception) {
                result.success(null)
            }
        } else {
            result.success(null)
        }
    }

    // ── Permission ────────────────────────────────────────────────────────────

    private fun handleRequestPermission(result: MethodChannel.Result) {
        val ctx = context ?: return result.error("NO_CONTEXT", "Context unavailable", null)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // Pre-Android 13: POST_NOTIFICATIONS not required
            result.success("alreadyGranted")
            return
        }

        val permission = android.Manifest.permission.POST_NOTIFICATIONS
        val alreadyGranted = ActivityCompat.checkSelfPermission(ctx, permission) ==
                PackageManager.PERMISSION_GRANTED
        if (alreadyGranted) {
            result.success("alreadyGranted")
            return
        }

        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity unavailable for permission request", null)
            return
        }

        permissionResultCallback = { granted ->
            result.success(if (granted) "granted" else "denied")
        }
        ActivityCompat.requestPermissions(activity, arrayOf(permission), PERMISSION_REQUEST_CODE)
    }

    // ── Show ──────────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun handleShow(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("NO_CONTEXT", "Context unavailable", null)
        try {
            val nm = NotificationManagerCompat.from(ctx)
            val notification = buildNotification(ctx, call)
            val id = (call.argument<String>("id") ?: "0").hashCode()
            nm.notify(id, notification)
            result.success(null)
        } catch (e: Exception) {
            result.error("SHOW_ERROR", e.message, null)
        }
    }

    // ── Schedule ──────────────────────────────────────────────────────────────

    private fun handleSchedule(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("NO_CONTEXT", "Context unavailable", null)
        try {
            val deliverAtMs = call.argument<Long>("deliverAtMs")
                ?: return result.error("MISSING_TIME", "deliverAtMs is required", null)

            if (deliverAtMs <= System.currentTimeMillis()) {
                result.error("PAST_TIME", "deliverAtMs must be in the future", null)
                return
            }

            val notifId   = call.argument<String>("id") ?: "0"
            val id        = notifId.hashCode()
            val title     = call.argument<String>("title") ?: ""
            val body      = call.argument<String>("body") ?: ""
            val sound     = call.argument<String>("sound")
            val channelId = call.argument<String>("channelId") ?: CH_DEFAULT
            val priority  = call.argument<String>("priority") ?: "defaultPriority"

            @Suppress("UNCHECKED_CAST")
            val dataMap = call.argument<Map<String, String>>("data")

            // Embed all display fields as intent extras so the receiver can
            // reconstruct the notification even if the engine is not running.
            val intent = Intent(ctx, FlueraNotificationReceiver::class.java).apply {
                action = FlueraNotificationReceiver.ACTION_DELIVER_SCHEDULED
                putExtra(EXTRA_NOTIFICATION_ID, notifId)
                putExtra("title", title)
                putExtra("body", body)
                putExtra("channelId", channelId)
                putExtra("priority", priority)
                if (sound != null) putExtra("sound", sound)
                dataMap?.forEach { (k, v) -> putExtra("data_$k", v) }
            }

            val pendingIntent = PendingIntent.getBroadcast(
                ctx, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deliverAtMs, pendingIntent)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, deliverAtMs, pendingIntent)
            }

            // Persist for reboot recovery (minimal: just the alarm time + id)
            val prefs = ctx.getSharedPreferences("fluera_notifications", Context.MODE_PRIVATE)
            prefs.edit().putString("scheduled_$id", "$deliverAtMs|$notifId").apply()

            result.success(null)
        } catch (e: Exception) {
            result.error("SCHEDULE_ERROR", e.message, null)
        }
    }

    // ── Cancel ────────────────────────────────────────────────────────────────

    private fun handleCancel(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("NO_CONTEXT", "Context unavailable", null)
        val rawId = call.argument<String>("id") ?: return result.error("MISSING_ID", "id is required", null)
        val id = rawId.hashCode()
        NotificationManagerCompat.from(ctx).cancel(id)
        // Also cancel any pending alarm
        val intent = Intent(ctx, FlueraNotificationReceiver::class.java).apply {
            action = FlueraNotificationReceiver.ACTION_DELIVER_SCHEDULED
        }
        val pi = PendingIntent.getBroadcast(
            ctx, id, intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        pi?.let {
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(it)
        }
        val prefs = ctx.getSharedPreferences("fluera_notifications", Context.MODE_PRIVATE)
        prefs.edit().remove("scheduled_$id").apply()
        result.success(null)
    }

    private fun handleCancelAll(result: MethodChannel.Result) {
        val ctx = context ?: return result.error("NO_CONTEXT", "Context unavailable", null)
        NotificationManagerCompat.from(ctx).cancelAll()
        val prefs = ctx.getSharedPreferences("fluera_notifications", Context.MODE_PRIVATE)
        prefs.edit().clear().apply()
        result.success(null)
    }

    // ── Schedule Repeating ────────────────────────────────────────────────────

    private fun handleScheduleRepeating(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("NO_CONTEXT", "Context unavailable", null)
        try {
            val deliverAtMs = call.argument<Long>("deliverAtMs")
                ?: return result.error("MISSING_TIME", "deliverAtMs is required", null)
            val repeatInterval = call.argument<String>("repeatInterval") ?: "daily"

            val notifId   = call.argument<String>("id") ?: "0"
            val id        = notifId.hashCode()
            val title     = call.argument<String>("title") ?: ""
            val body      = call.argument<String>("body") ?: ""
            val sound     = call.argument<String>("sound")
            val channelId = call.argument<String>("channelId") ?: CH_DEFAULT
            val groupKey  = call.argument<String>("groupKey")

            val intent = Intent(ctx, FlueraNotificationReceiver::class.java).apply {
                action = FlueraNotificationReceiver.ACTION_DELIVER_SCHEDULED
                putExtra(EXTRA_NOTIFICATION_ID, notifId)
                putExtra("title", title)
                putExtra("body", body)
                putExtra("channelId", channelId)
                if (sound != null) putExtra("sound", sound)
            }

            val pendingIntent = PendingIntent.getBroadcast(
                ctx, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val intervalMs = when (repeatInterval) {
                "hourly" -> AlarmManager.INTERVAL_HOUR
                "weekly" -> AlarmManager.INTERVAL_DAY * 7
                else     -> AlarmManager.INTERVAL_DAY  // daily
            }

            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.setRepeating(AlarmManager.RTC_WAKEUP, deliverAtMs, intervalMs, pendingIntent)

            // Persist for reboot recovery
            val prefs = ctx.getSharedPreferences("fluera_notifications", Context.MODE_PRIVATE)
            val groupSuffix = if (groupKey != null) "|group=$groupKey" else ""
            prefs.edit().putString("scheduled_$id", "$deliverAtMs|$notifId|repeat=$repeatInterval$groupSuffix").apply()

            result.success(null)
        } catch (e: Exception) {
            result.error("SCHEDULE_ERROR", e.message, null)
        }
    }

    // ── Cancel Group ──────────────────────────────────────────────────────────

    private fun handleCancelGroup(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("NO_CONTEXT", "Context unavailable", null)
        val groupKey = call.argument<String>("groupKey")
            ?: return result.error("MISSING_GROUP", "groupKey is required", null)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            nm?.activeNotifications
                ?.filter { it.notification.group == groupKey }
                ?.forEach { nm.cancel(it.id) }
        }

        // Also cancel scheduled alarms that belong to this group
        val prefs = ctx.getSharedPreferences("fluera_notifications", Context.MODE_PRIVATE)
        prefs.all.entries
            .filter { it.key.startsWith("scheduled_") }
            .filter { (it.value as? String)?.contains("|group=$groupKey") == true }
            .forEach { entry ->
                val id = entry.key.removePrefix("scheduled_").toIntOrNull() ?: return@forEach
                val intent = Intent(ctx, FlueraNotificationReceiver::class.java).apply {
                    action = FlueraNotificationReceiver.ACTION_DELIVER_SCHEDULED
                }
                PendingIntent.getBroadcast(
                    ctx, id, intent,
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                )?.let {
                    (ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(it)
                }
                prefs.edit().remove(entry.key).apply()
            }

        result.success(null)
    }

    // ── Pending (scheduled) ───────────────────────────────────────────────────

    private fun handleGetPending(result: MethodChannel.Result) {
        val ctx = context ?: return result.error("NO_CONTEXT", "Context unavailable", null)
        val prefs = ctx.getSharedPreferences("fluera_notifications", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val list = prefs.all.entries
            .filter { it.key.startsWith("scheduled_") }
            .mapNotNull { entry ->
                val value = entry.value as? String ?: return@mapNotNull null
                val deliverAtMs = value.substringBefore("|").toLongOrNull() ?: return@mapNotNull null
                if (deliverAtMs <= now) return@mapNotNull null
                val notifId = value.substringAfter("|").substringBefore("|")
                mapOf<String, Any>(
                    "id" to notifId,
                    "deliverAtMs" to deliverAtMs,
                )
            }
        result.success(list)
    }

    // ── Create Channel ────────────────────────────────────────────────────────

    private fun handleCreateChannel(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(null)
            return
        }
        val ctx = context ?: return result.error("NO_CONTEXT", "Context unavailable", null)

        val id          = call.argument<String>("id") ?: return result.error("MISSING_ID", "id is required", null)
        val name        = call.argument<String>("name") ?: return result.error("MISSING_NAME", "name is required", null)
        val description = call.argument<String>("description")
        val vibrate     = call.argument<Boolean>("vibrate") ?: true
        val importStr   = call.argument<String>("importance") ?: "defaultPriority"

        val importance = when (importStr) {
            "min"  -> NotificationManager.IMPORTANCE_MIN
            "low"  -> NotificationManager.IMPORTANCE_LOW
            "high" -> NotificationManager.IMPORTANCE_HIGH
            "max"  -> NotificationManager.IMPORTANCE_MAX
            else   -> NotificationManager.IMPORTANCE_DEFAULT
        }

        val channel = NotificationChannel(id, name, importance).apply {
            if (description != null) this.description = description
            enableVibration(vibrate)
        }

        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm?.createNotificationChannel(channel)
        result.success(null)
    }

    // ── Delivered ─────────────────────────────────────────────────────────────

    private fun handleGetDelivered(result: MethodChannel.Result) {
        val ctx = context ?: return result.error("NO_CONTEXT", "Context unavailable", null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            val list = nm?.activeNotifications?.map { sbn ->
                mapOf(
                    "id" to sbn.id.toString(),
                    "title" to (sbn.notification.extras.getString("android.title") ?: ""),
                    "body" to (sbn.notification.extras.getString("android.text") ?: ""),
                )
            } ?: emptyList()
            result.success(list)
        } else {
            result.success(emptyList<Map<String, String>>())
        }
    }

    // ── Build Notification ────────────────────────────────────────────────────

    internal fun buildNotification(
        ctx: Context,
        call: MethodCall,
    ): android.app.Notification {
        val id          = call.argument<String>("id") ?: "0"
        val title       = call.argument<String>("title") ?: ""
        val body        = call.argument<String>("body") ?: ""
        val style       = call.argument<String>("style") ?: "plain"
        val priorityStr = call.argument<String>("priority") ?: "defaultPriority"
        val channelId   = call.argument<String>("channelId") ?: CH_DEFAULT
        val imageUrl    = call.argument<String>("imageUrl")
        val sound       = call.argument<String>("sound")
        val vibrate     = call.argument<Boolean>("vibrate") ?: true
        val groupKey    = call.argument<String>("groupKey")
        val isGroupSum  = call.argument<Boolean>("isGroupSummary") ?: false

        @Suppress("UNCHECKED_CAST")
        val dataMap     = call.argument<Map<String, String>>("data")
        @Suppress("UNCHECKED_CAST")
        val actions     = call.argument<List<Map<String, Any>>>("actions")
        @Suppress("UNCHECKED_CAST")
        val inboxLines  = call.argument<List<String>>("inboxLines")
        val progressMax = call.argument<Int>("progressMax") ?: 100
        val progressCur = call.argument<Int>("progressCurrent") ?: 0
        val progressInd = call.argument<Boolean>("progressIndeterminate") ?: false

        val priority = when (priorityStr) {
            "min"  -> NotificationCompat.PRIORITY_MIN
            "low"  -> NotificationCompat.PRIORITY_LOW
            "high" -> NotificationCompat.PRIORITY_HIGH
            "max"  -> NotificationCompat.PRIORITY_MAX
            else   -> NotificationCompat.PRIORITY_DEFAULT
        }

        // Body tap — routes through BroadcastReceiver so EventChannel always fires
        // before the app is opened, regardless of app state.
        val tapBroadcastIntent = Intent(ctx, FlueraNotificationReceiver::class.java).apply {
            action = FlueraNotificationReceiver.ACTION_NOTIFICATION_TAP
            putExtra(EXTRA_NOTIFICATION_ID, id)
            dataMap?.forEach { (k, v) -> putExtra("data_$k", v) }
        }
        val tapPi = PendingIntent.getBroadcast(
            ctx, id.hashCode(), tapBroadcastIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(ctx, channelId)
            .setSmallIcon(getSmallIconRes(ctx)) // host app should override via meta-data
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(priority)
            .setContentIntent(tapPi)
            .setAutoCancel(true)
            .setVibrate(if (vibrate) longArrayOf(0, 250, 100, 250) else longArrayOf())
            .setSound(
                // Custom sound from raw resources; null falls back to channel default
                if (sound != null) {
                    android.net.Uri.parse(
                        "android.resource://${ctx.packageName}/raw/$sound"
                    )
                } else null
            )

        // Style
        when (style) {
            "bigText" -> builder.setStyle(
                NotificationCompat.BigTextStyle().bigText(body)
            )
            "bigPicture" -> {
                if (imageUrl != null) {
                    // Show plain notification immediately, then update with image
                    // loaded on a background thread to avoid blocking the main thread.
                    Thread {
                        val bitmap = runCatching {
                            if (imageUrl.startsWith("http")) {
                                val conn = java.net.URL(imageUrl).openConnection() as java.net.HttpURLConnection
                                conn.connectTimeout = 10_000  // 10s connect timeout
                                conn.readTimeout = 10_000     // 10s read timeout
                                conn.connect()
                                BitmapFactory.decodeStream(conn.inputStream).also { conn.disconnect() }
                            } else {
                                val assetKey = ctx.assets.list("")
                                    ?.firstOrNull { it.contains(imageUrl.substringAfterLast("/")) }
                                assetKey?.let { BitmapFactory.decodeStream(ctx.assets.open(it)) }
                            }
                        }.getOrNull()

                        if (bitmap != null) {
                            val updatedBuilder = NotificationCompat.Builder(ctx, channelId)
                                .setSmallIcon(getSmallIconRes(ctx))
                                .setContentTitle(title)
                                .setContentText(body)
                                .setPriority(priority)
                                .setContentIntent(tapPi)
                                .setAutoCancel(true)
                                .setLargeIcon(bitmap)
                                .setStyle(
                                    NotificationCompat.BigPictureStyle()
                                        .bigPicture(bitmap)
                                        .setSummaryText(body)
                                )
                            notifySafe(ctx, id.hashCode(), updatedBuilder.build())
                        }
                    }.start()
                    // Fall through: the base plain notification is posted below
                } else {
                    builder.setStyle(NotificationCompat.BigTextStyle().bigText(body))
                }
            }
            "inbox" -> {
                val inboxStyle = NotificationCompat.InboxStyle()
                inboxLines?.forEach { inboxStyle.addLine(it) }
                inboxStyle.setSummaryText(body)
                builder.setStyle(inboxStyle)
            }
            "progress" -> {
                builder.setProgress(progressMax, progressCur, progressInd)
                    .setOngoing(true)
                    .setOnlyAlertOnce(true)
            }
        }

        // Group
        groupKey?.let {
            builder.setGroup(it)
            if (isGroupSum) builder.setGroupSummary(true)
        }

        // Action buttons — ALL route through the BroadcastReceiver.
        // The receiver pushes the event to EventChannel, then decides whether
        // to also launch the Activity based on EXTRA_OPEN_APP.
        actions?.forEach { action ->
            val actionId     = action["id"] as? String ?: ""
            val label        = action["label"] as? String ?: ""
            val openApp      = action["openApp"] as? Boolean ?: true
            val requireInput = action["requireInput"] as? Boolean ?: false
            val placeholder  = action["inputPlaceholder"] as? String ?: "Scrivi..."

            val actionIntent = Intent(ctx, FlueraNotificationReceiver::class.java).apply {
                this.action = FlueraNotificationReceiver.ACTION_NOTIFICATION_ACTION
                putExtra(EXTRA_NOTIFICATION_ID, id)
                putExtra(EXTRA_ACTION_ID, actionId)
                putExtra(FlueraNotificationReceiver.EXTRA_OPEN_APP, openApp)
                dataMap?.forEach { (k, v) -> putExtra("data_$k", v) }
            }
            
            // To allow inline reply from the lockscreen/shade without unlocking,
            // we use FLAG_MUTABLE so the system can fill in the RemoteInput text.
            val flags = if (requireInput && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            }
            
            val actionPi = PendingIntent.getBroadcast(
                ctx,
                (id + actionId).hashCode(),
                actionIntent,
                flags
            )
            
            if (requireInput) {
                val remoteInput = androidx.core.app.RemoteInput.Builder(FlueraNotificationReceiver.EXTRA_INLINE_REPLY)
                    .setLabel(placeholder)
                    .build()
                val actionBuilder = NotificationCompat.Action.Builder(
                    0, label, actionPi
                ).addRemoteInput(remoteInput)
                builder.addAction(actionBuilder.build())
            } else {
                builder.addAction(0, label, actionPi)
            }
        }

        return builder.build()
    }

    // ── Safe Notify Helper ────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun notifySafe(ctx: Context, id: Int, notification: android.app.Notification) {
        NotificationManagerCompat.from(ctx).notify(id, notification)
    }

    // ── SmallIcon Resolution ──────────────────────────────────────────────────

    /** Cached small icon resource ID — resolved once, reused for all notifications. */
    private var cachedSmallIconRes: Int = 0

    /**
     * Resolves the best small icon for notifications (cached after first call):
     *  1. Checks for `com.flueraengine.notification_icon` meta-data in AndroidManifest
     *  2. Falls back to the host app's launcher icon
     *  3. Last resort: Android default info icon
     */
    private fun getSmallIconRes(ctx: Context): Int {
        if (cachedSmallIconRes != 0) return cachedSmallIconRes

        cachedSmallIconRes = try {
            val appInfo = ctx.packageManager.getApplicationInfo(
                ctx.packageName,
                PackageManager.GET_META_DATA
            )
            val metaIcon = appInfo.metaData?.getInt("com.flueraengine.notification_icon", 0) ?: 0
            if (metaIcon != 0) metaIcon
            else if (appInfo.icon != 0) appInfo.icon
            else android.R.drawable.ic_dialog_info
        } catch (_: Exception) {
            android.R.drawable.ic_dialog_info
        }

        return cachedSmallIconRes
    }

    // ── Channels ──────────────────────────────────────────────────────────────

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val ctx = context ?: return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        data class Ch(val id: String, val name: String, val importance: Int, val description: String)

        listOf(
            Ch(CH_DEFAULT, "Fluera",            NotificationManager.IMPORTANCE_HIGH,    "General Fluera notifications"),
            Ch(CH_STUDY,   "Studio & Ripasso",  NotificationManager.IMPORTANCE_HIGH,    "Study session and review reminders"),
            Ch(CH_EXPORT,  "Esportazioni",      NotificationManager.IMPORTANCE_DEFAULT, "Export completion and progress"),
            Ch(CH_SILENT,  "Silenziose",        NotificationManager.IMPORTANCE_LOW,     "Silent informational updates"),
        ).forEach { ch ->
            if (nm.getNotificationChannel(ch.id) == null) {
                val channel = NotificationChannel(ch.id, ch.name, ch.importance).apply {
                    description = ch.description
                    enableVibration(ch.id != CH_SILENT)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }
}
