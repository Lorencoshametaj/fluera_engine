import 'dart:async';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

/// Visual style of the notification.
enum FNotificationStyle {
  /// Standard single-line notification.
  plain,

  /// Expandable multi-line text body.
  bigText,

  /// Expandable notification with a large image.
  bigPicture,

  /// Multiple short lines displayed as a list (inbox style).
  inbox,

  /// Notification with a progress bar.
  progress,
}

/// Platform-agnostic importance/priority level.
///
/// Maps to Android `NotificationCompat.PRIORITY_*` and
/// iOS `UNNotificationInterruptionLevel`.
enum FNotificationPriority {
  min,
  low,
  defaultPriority,
  high,
  max,
}

/// Semantic category used to style the notification and register
/// UNNotificationCategory actions on iOS.
enum FNotificationCategory {
  general,
  reminder,
  studySession,
  reviewSession,
  exportDone,
}

/// Repetition interval for [NativeNotifications.scheduleRepeating].
enum FRepeatInterval {
  /// Repeats every day at the specified time.
  daily,

  /// Repeats every week on the same day and time.
  weekly,

  /// Repeats every hour (useful for testing; avoid in production).
  hourly,
}

// ─────────────────────────────────────────────────────────────────────────────
// Action
// ─────────────────────────────────────────────────────────────────────────────

/// A tappable action attached to a notification.
class FNotificationAction {
  const FNotificationAction({
    required this.id,
    required this.label,
    this.isDestructive = false,
    this.isAuthRequired = false,
    this.openApp = true,
    this.requireInput = false,
    this.inputPlaceholder,
  });

  /// Unique identifier used in [FNotificationTapEvent.actionId].
  final String id;

  /// Localised label shown in the notification button.
  final String label;

  /// iOS: renders the action in red.
  final bool isDestructive;

  /// iOS: requires biometric/passcode authentication before firing.
  final bool isAuthRequired;

  /// Android: whether tapping this action should bring the app to foreground.
  final bool openApp;

  /// Whether this action should prompt the user for inline text input.
  /// If true, [FNotificationTapEvent.inputText] will contain the typed text.
  final bool requireInput;

  /// Optional placeholder for the text input field (e.g., "Scrivi...").
  final String? inputPlaceholder;

  Map<String, dynamic> _toMap() => {
        'id': id,
        'label': label,
        'isDestructive': isDestructive,
        'isAuthRequired': isAuthRequired,
        'openApp': openApp,
        'requireInput': requireInput,
        if (inputPlaceholder != null) 'inputPlaceholder': inputPlaceholder,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification payload
// ─────────────────────────────────────────────────────────────────────────────

/// Complete notification descriptor passed to [NativeNotifications.show] or
/// [NativeNotifications.schedule].
class FNotification {
  const FNotification({
    required this.id,
    required this.title,
    this.body,
    this.subtitle,
    this.style = FNotificationStyle.plain,
    this.priority = FNotificationPriority.defaultPriority,
    this.category = FNotificationCategory.general,
    this.channelId,
    this.imageUrl,
    this.sound,
    this.vibrate = true,
    this.data,
    this.actions,
    this.progressMax,
    this.progressCurrent,
    this.progressIndeterminate,
    this.groupKey,
    this.isGroupSummary = false,
    this.inboxLines,
  });

  /// Stable identifier — used for cancellation and deduplication.
  final String id;

  /// Primary line of the notification.
  final String title;

  /// Body text (optional).
  final String? body;

  /// iOS-only secondary line below the title.
  final String? subtitle;

  final FNotificationStyle style;
  final FNotificationPriority priority;
  final FNotificationCategory category;

  /// Android notification channel ID. Defaults to `fluera_default`.
  final String? channelId;

  /// URL or asset path of the image used in [FNotificationStyle.bigPicture]
  /// (Android) or as a rich attachment (iOS).
  final String? imageUrl;

  /// Sound file name (without extension) from the app's assets.
  /// `null` → system default sound.
  final String? sound;

  /// Whether to trigger device vibration with this notification.
  final bool vibrate;

  /// Arbitrary key/value pairs delivered to [FNotificationTapEvent.data].
  final Map<String, String>? data;

  /// Optional action buttons (max 3 on Android, max 4 on iOS).
  final List<FNotificationAction>? actions;

  // Progress style fields — only used when [style] is [FNotificationStyle.progress].
  final int? progressMax;
  final int? progressCurrent;
  final bool? progressIndeterminate;

  /// Android notification group key for bundling multiple notifications.
  final String? groupKey;

  /// When `true`, this notification acts as the summary for its [groupKey].
  final bool isGroupSummary;

  /// Lines to display in [FNotificationStyle.inbox] style.
  final List<String>? inboxLines;

  Map<String, dynamic> _toMap() {
    return {
      'id': id,
      'title': title,
      if (body != null) 'body': body,
      if (subtitle != null) 'subtitle': subtitle,
      'style': style.name,
      'priority': priority.name,
      'category': category.name,
      if (channelId != null) 'channelId': channelId,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (sound != null) 'sound': sound,
      'vibrate': vibrate,
      if (data != null) 'data': data,
      if (actions != null) 'actions': actions!.map((a) => a._toMap()).toList(),
      if (progressMax != null) 'progressMax': progressMax,
      if (progressCurrent != null) 'progressCurrent': progressCurrent,
      if (progressIndeterminate != null)
        'progressIndeterminate': progressIndeterminate,
      if (groupKey != null) 'groupKey': groupKey,
      'isGroupSummary': isGroupSummary,
      if (inboxLines != null) 'inboxLines': inboxLines,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tap event
// ─────────────────────────────────────────────────────────────────────────────

/// Emitted on [NativeNotifications.onNotificationTapped] when the user
/// interacts with a notification or one of its action buttons.
class FNotificationTapEvent {
  const FNotificationTapEvent({
    required this.notificationId,
    this.actionId,
    this.inputText,
    this.data,
  });

  /// ID of the notification that was tapped.
  final String notificationId;

  /// ID of the action button tapped, or `null` when the notification body
  /// itself was tapped.
  final String? actionId;

  /// Text entered by the user if the action had [requireInput] set to true.
  final String? inputText;

  /// Payload that was attached to the notification at creation time.
  final Map<String, String>? data;

  factory FNotificationTapEvent._fromMap(Map<Object?, Object?> map) {
    final rawData = map['data'] as Map<Object?, Object?>?;
    return FNotificationTapEvent(
      notificationId: map['notificationId'] as String,
      actionId: map['actionId'] as String?,
      inputText: map['inputText'] as String?,
      data: rawData?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
    );
  }

  @override
  String toString() =>
      'FNotificationTapEvent(id: $notificationId, action: $actionId, input: $inputText)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Permission result
// ─────────────────────────────────────────────────────────────────────────────

/// Result of [NativeNotifications.requestPermission].
enum FNotificationPermission {
  /// The user granted permission.
  granted,

  /// The user denied permission.
  denied,

  /// Permission was already granted; no dialog was shown.
  alreadyGranted,
}

// ─────────────────────────────────────────────────────────────────────────────
// Main service
// ─────────────────────────────────────────────────────────────────────────────

/// 🔔 Native notification service for Android and iOS.
///
/// Uses platform channels to issue local notifications without any external
/// pub.dev dependency:
/// - **Android**: `NotificationCompat` with multiple channels, `BigPicture`,
///   `BigText`, `Inbox`, and `Progress` styles, action buttons, and
///   `AlarmManager` scheduling.
/// - **iOS**: `UserNotifications` framework with rich attachments,
///   `UNNotificationCategory` actions, badge management, and
///   `UNUserNotificationCenterDelegate` tap routing.
///
/// ## Quick start
///
/// ```dart
/// // 1. Request permission (required on iOS, required on Android 13+)
/// await NativeNotifications.requestPermission();
///
/// // 2. Show a notification
/// await NativeNotifications.show(const FNotification(
///   id: 'ripasso_24h',
///   title: '⏰ Ripasso 24h',
///   body: 'Hai del materiale da ripassare. Aprilo adesso!',
///   category: FNotificationCategory.studySession,
///   priority: FNotificationPriority.high,
///   actions: [
///     FNotificationAction(id: 'open_now', label: 'Apri'),
///     FNotificationAction(id: 'later', label: 'Dopo'),
///   ],
/// ));
///
/// // 3. Listen for taps
/// NativeNotifications.onNotificationTapped.listen((event) {
///   if (event.actionId == 'open_now') {
///     // navigate to canvas
///   }
/// });
///
/// // 4. Cancel
/// await NativeNotifications.cancel('ripasso_24h');
/// ```
class NativeNotifications {
  static const MethodChannel _method = MethodChannel(
    'flueraengine.notifications/method',
  );
  static const EventChannel _events = EventChannel(
    'flueraengine.notifications/events',
  );

  NativeNotifications._();

  // ── Tap stream ─────────────────────────────────────────────────────────────

  static Stream<FNotificationTapEvent>? _tapStream;

  /// Broadcast stream that emits whenever the user taps a notification or one
  /// of its action buttons.
  ///
  /// Subscribe before showing notifications to avoid missing early taps.
  static Stream<FNotificationTapEvent> get onNotificationTapped {
    _tapStream ??= _events
        .receiveBroadcastStream()
        .where((raw) => raw is Map)
        .map((raw) => FNotificationTapEvent._fromMap(raw as Map<Object?, Object?>))
        .asBroadcastStream();
    return _tapStream!;
  }

  // ── Permission ─────────────────────────────────────────────────────────────

  /// Requests the OS notification permission.
  ///
  /// On **Android < 13** always returns [FNotificationPermission.alreadyGranted]
  /// because no runtime permission is required.
  /// On **iOS**, presents the system alert the first time it is called.
  static Future<FNotificationPermission> requestPermission() async {
    try {
      final String? raw =
          await _method.invokeMethod<String>('requestPermission');
      return switch (raw) {
        'granted' => FNotificationPermission.granted,
        'denied' => FNotificationPermission.denied,
        'alreadyGranted' => FNotificationPermission.alreadyGranted,
        _ => FNotificationPermission.granted,
      };
    } on PlatformException {
      return FNotificationPermission.denied;
    }
  }

  // ── Show ───────────────────────────────────────────────────────────────────

  /// Displays a notification immediately.
  ///
  /// If a notification with the same [FNotification.id] is already visible,
  /// it is updated in place rather than duplicated.
  static Future<void> show(FNotification notification) async {
    await _method.invokeMethod<void>('show', notification._toMap());
  }

  // ── Schedule ───────────────────────────────────────────────────────────────

  /// Schedules a notification to be delivered at [deliverAt].
  ///
  /// The [deliverAt] must be in the future, otherwise the call is a no-op.
  /// On Android, uses `AlarmManager.setExactAndAllowWhileIdle` to wake the
  /// device even in Doze mode.  On iOS, uses
  /// `UNCalendarNotificationTrigger`.
  static Future<void> schedule(
    FNotification notification,
    DateTime deliverAt,
  ) async {
    await _method.invokeMethod<void>('schedule', {
      ...notification._toMap(),
      'deliverAtMs': deliverAt.millisecondsSinceEpoch,
    });
  }

  /// Schedules a **repeating** notification.
  ///
  /// The first delivery happens at [firstDeliveryAt], then repeats every
  /// [interval] (daily, weekly, or hourly).
  ///
  /// ```dart
  /// // Daily study reminder at 18:00
  /// await NativeNotifications.scheduleRepeating(
  ///   FNotification(id: 'daily_study', title: 'Tempo di studiare!'),
  ///   firstDeliveryAt: DateTime(2024, 1, 1, 18, 0),
  ///   interval: FRepeatInterval.daily,
  /// );
  /// ```
  ///
  /// Cancel with [cancel] using the same notification [FNotification.id].
  static Future<void> scheduleRepeating(
    FNotification notification, {
    required DateTime firstDeliveryAt,
    required FRepeatInterval interval,
  }) async {
    await _method.invokeMethod<void>('scheduleRepeating', {
      ...notification._toMap(),
      'deliverAtMs': firstDeliveryAt.millisecondsSinceEpoch,
      'repeatInterval': interval.name,
    });
  }

  // ── Cancel ─────────────────────────────────────────────────────────────────

  /// Cancels a single pending or delivered notification by [id].
  static Future<void> cancel(String id) async {
    await _method.invokeMethod<void>('cancel', {'id': id});
  }

  /// Cancels all pending and delivered notifications issued by this app.
  static Future<void> cancelAll() async {
    await _method.invokeMethod<void>('cancelAll');
  }

  /// Cancels all notifications (pending + delivered) that share the given
  /// [groupKey].
  ///
  /// Useful for clearing all study reminders at once, for example:
  /// ```dart
  /// await NativeNotifications.cancelGroup('study_reminders');
  /// ```
  static Future<void> cancelGroup(String groupKey) async {
    await _method.invokeMethod<void>('cancelGroup', {'groupKey': groupKey});
  }

  // ── Badge ──────────────────────────────────────────────────────────────────

  /// Sets the app icon badge count.
  ///
  /// On **iOS**: updates `UIApplication.applicationIconBadgeNumber`.
  /// On **Android**: this is a no-op — badge management is launcher-specific
  /// and not guaranteed.
  static Future<void> setBadgeCount(int count) async {
    assert(count >= 0, 'Badge count must be >= 0');
    await _method.invokeMethod<void>('setBadge', {'count': count});
  }

  /// Clears the app icon badge.
  static Future<void> clearBadge() => setBadgeCount(0);

  // ── Query ──────────────────────────────────────────────────────────────────

  /// Returns the list of notifications currently visible in the
  /// Notification Center / lock screen.
  ///
  /// Each entry is a map with at least `id`, `title`, and optionally `body`.
  static Future<List<Map<String, dynamic>>> getDeliveredNotifications() async {
    final List<Object?>? raw =
        await _method.invokeMethod<List<Object?>>('getDelivered');
    if (raw == null) return [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  /// Returns the notification tap event that launched the app (cold start),
  /// or `null` if the app was not opened via a notification.
  ///
  /// Call this early in your app lifecycle (e.g., in `main()` or the first
  /// screen's `initState`) **before** subscribing to [onNotificationTapped]
  /// to handle deep-link navigation:
  ///
  /// ```dart
  /// final initial = await NativeNotifications.getInitialNotification();
  /// if (initial != null) {
  ///   // Navigate based on initial.data or initial.actionId
  /// }
  /// ```
  static Future<FNotificationTapEvent?> getInitialNotification() async {
    final Map<Object?, Object?>? raw =
        await _method.invokeMethod<Map<Object?, Object?>>('getInitialNotification');
    if (raw == null) return null;
    return FNotificationTapEvent._fromMap(raw);
  }

  /// Returns the list of scheduled (pending) notifications that have not
  /// yet been delivered.
  ///
  /// Each entry contains at least `id`, `title`, and optionally `body`.
  static Future<List<Map<String, dynamic>>> getPendingNotifications() async {
    final List<Object?>? raw =
        await _method.invokeMethod<List<Object?>>('getPending');
    if (raw == null) return [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  // ── Channel creation ────────────────────────────────────────────────────

  /// Creates a custom notification channel (Android only).
  ///
  /// On **iOS** this is a no-op — iOS manages notification grouping via
  /// categories, not channels.
  ///
  /// ```dart
  /// await NativeNotifications.createChannel(
  ///   id: 'ai_insights',
  ///   name: 'Atlas AI Insights',
  ///   description: 'Smart suggestions from Atlas',
  ///   importance: FNotificationPriority.high,
  /// );
  /// ```
  static Future<void> createChannel({
    required String id,
    required String name,
    String? description,
    FNotificationPriority importance = FNotificationPriority.defaultPriority,
    bool enableVibration = true,
  }) async {
    await _method.invokeMethod<void>('createChannel', {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      'importance': importance.name,
      'vibrate': enableVibration,
    });
  }

  // ── Preset helpers ─────────────────────────────────────────────────────────

  /// Shows a study-session reminder notification with pre-built actions.
  ///
  /// Convenience wrapper for the "Ripasso 24h" learning science feature.
  static Future<void> showStudyReminder({
    required String id,
    required String title,
    String body = 'Hai del materiale da ripassare. Aprilo adesso!',
    Map<String, String>? data,
  }) {
    return show(FNotification(
      id: id,
      title: title,
      body: body,
      style: FNotificationStyle.bigText,
      priority: FNotificationPriority.high,
      category: FNotificationCategory.studySession,
      vibrate: true,
      data: data,
      actions: const [
        FNotificationAction(id: 'open_now', label: 'Apri ora', openApp: true),
        FNotificationAction(id: 'later_1h', label: 'Tra 1h', openApp: false),
        FNotificationAction(
          id: 'dismiss',
          label: 'Ignora',
          isDestructive: true,
          openApp: false,
        ),
      ],
    ));
  }

  /// Shows an export-complete notification.
  static Future<void> showExportDone({
    required String id,
    required String title,
    String body = 'Il tuo file è pronto.',
    String? imageUrl,
    Map<String, String>? data,
  }) {
    return show(FNotification(
      id: id,
      title: title,
      body: body,
      style:
          imageUrl != null ? FNotificationStyle.bigPicture : FNotificationStyle.plain,
      imageUrl: imageUrl,
      priority: FNotificationPriority.defaultPriority,
      category: FNotificationCategory.exportDone,
      channelId: 'fluera_export',
      data: data,
      actions: const [
        FNotificationAction(id: 'open_file', label: 'Apri', openApp: true),
        FNotificationAction(id: 'share', label: 'Condividi', openApp: true),
      ],
    ));
  }

  /// Shows a progress notification and updates it as work proceeds.
  ///
  /// Call repeatedly with increasing [current] values.
  /// Call with [current] == [max] to mark completion.
  static Future<void> showProgress({
    required String id,
    required String title,
    required int max,
    required int current,
    String? body,
    bool indeterminate = false,
  }) {
    return show(FNotification(
      id: id,
      title: title,
      body: body,
      style: FNotificationStyle.progress,
      priority: FNotificationPriority.low,
      channelId: 'fluera_export',
      progressMax: max,
      progressCurrent: current,
      progressIndeterminate: indeterminate,
      vibrate: false,
    ));
  }
}
