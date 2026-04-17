import Flutter
import UIKit
import UserNotifications

// MARK: - Models

/// Mirrors Dart's FNotificationAction
private struct FAction {
    let id: String
    let label: String
    let isDestructive: Bool
    let isAuthRequired: Bool
}

// MARK: - Plugin

/**
 * 🔔 NotificationPlugin — Native local notifications for Fluera Engine (iOS)
 *
 * Method channel:  `flueraengine.notifications/method`
 * Event channel:   `flueraengine.notifications/events`
 *
 * Supported methods:
 *  - requestPermission  → "granted" | "denied" | "alreadyGranted"
 *  - show               → immediate UNNotificationRequest
 *  - schedule           → UNCalendarNotificationTrigger
 *  - cancel             → removes pending + delivered notifications
 *  - cancelAll          → removes all pending + delivered notifications
 *  - setBadge           → set app icon badge number
 *  - getDelivered       → list of delivered notifications
 */
class NotificationPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, UNUserNotificationCenterDelegate {

    // MARK: - Channels

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    /// Cache of already-registered UNNotificationCategory identifiers.
    /// Avoids redundant getNotificationCategories/setNotificationCategories calls.
    private var registeredCategories: Set<String> = []

    // MARK: - Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = NotificationPlugin()

        let method = FlutterMethodChannel(
            name: "flueraengine.notifications/method",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: method)
        instance.methodChannel = method

        let event = FlutterEventChannel(
            name: "flueraengine.notifications/events",
            binaryMessenger: registrar.messenger()
        )
        event.setStreamHandler(instance)
        instance.eventChannel = event

        // Claim the UNUserNotificationCenter delegate so we receive foreground
        // notification callbacks and user interaction callbacks.
        UNUserNotificationCenter.current().delegate = instance
    }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        
        // Flush any buffered tap events from cold starts
        let defaults = UserDefaults.standard
        if let queued = defaults.array(forKey: "fluera_pending_tap_events") as? [[String: Any]] {
            for event in queued {
                eventSink?(event)
            }
            defaults.removeObject(forKey: "fluera_pending_tap_events")
        }
        
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notification even when the app is in foreground.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    /// Handles tap on notification body or action button.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo     = response.notification.request.content.userInfo
        let notifId      = userInfo["notificationId"] as? String ?? response.notification.request.identifier
        let actionId: String? = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            ? nil
            : response.actionIdentifier

        // Extract inline reply text if user typed something
        var inputText: String? = nil
        if let textResponse = response as? UNTextInputNotificationResponse {
            inputText = textResponse.userText
        }

        var data: [String: String] = [:]
        if let rawData = userInfo["data"] as? [String: String] {
            data = rawData
        }

        let event: [String: Any?] = [
            "notificationId": notifId,
            "actionId":       actionId,
            "inputText":      inputText,
            "data":           data,
        ]

        if let sink = eventSink {
            DispatchQueue.main.async {
                sink(event)
            }
        } else {
            // Buffer for cold start — flush when stream subscribes
            var queued = UserDefaults.standard.array(forKey: "fluera_pending_tap_events") as? [[String: Any]] ?? []
            // Convert event to [String: Any] since UserDefaults doesn't store Any?
            var storable: [String: Any] = [
                "notificationId": notifId as Any,
                "data": data as Any,
            ]
            if let aid = actionId { storable["actionId"] = aid }
            if let txt = inputText { storable["inputText"] = txt }
            queued.append(storable)
            UserDefaults.standard.set(queued, forKey: "fluera_pending_tap_events")
        }

        completionHandler()
    }

    // MARK: - MethodChannel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "requestPermission":      handleRequestPermission(result: result)
        case "show":                   handleShow(call: call, result: result)
        case "schedule":               handleSchedule(call: call, result: result)
        case "scheduleRepeating":      handleScheduleRepeating(call: call, result: result)
        case "cancel":                 handleCancel(call: call, result: result)
        case "cancelAll":              handleCancelAll(result: result)
        case "cancelGroup":            handleCancelGroup(call: call, result: result)
        case "setBadge":               handleSetBadge(call: call, result: result)
        case "getDelivered":           handleGetDelivered(result: result)
        case "getPending":             handleGetPending(result: result)
        case "getInitialNotification": handleGetInitial(result: result)
        case "createChannel":          result(nil) // no-op on iOS
        default:                       result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Permission

    private func handleRequestPermission(result: @escaping FlutterResult) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { result("alreadyGranted") }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        result(granted ? "granted" : "denied")
                    }
                }
            default:
                DispatchQueue.main.async { result("denied") }
            }
        }
    }

    // MARK: - Show

    private func handleShow(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Arguments missing", details: nil))
            return
        }

        let id = args["id"] as? String ?? UUID().uuidString
        let imageUrl = args["imageUrl"] as? String

        // Build on background thread so image download (if any) completes
        // BEFORE the request is submitted. This fixes the attachment race.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let content = self.buildContent(from: args)

            // Attach image synchronously (we're already off main thread)
            if let url = imageUrl {
                if let attachment = self.downloadAttachment(url: url) {
                    content.attachments = [attachment]
                }
            }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        result(FlutterError(code: "SHOW_ERROR", message: error.localizedDescription, details: nil))
                    } else {
                        result(nil)
                    }
                }
            }
        }
    }

    // MARK: - Schedule

    private func handleSchedule(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deliverAtMs = args["deliverAtMs"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "deliverAtMs missing", details: nil))
            return
        }

        let deliverAt = Date(timeIntervalSince1970: Double(deliverAtMs) / 1000.0)
        guard deliverAt > Date() else {
            result(FlutterError(code: "PAST_TIME", message: "deliverAtMs must be in the future", details: nil))
            return
        }

        let id = args["id"] as? String ?? UUID().uuidString
        let imageUrl = args["imageUrl"] as? String

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let content = self.buildContent(from: args)

            if let url = imageUrl {
                if let attachment = self.downloadAttachment(url: url) {
                    content.attachments = [attachment]
                }
            }

            let comps   = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: deliverAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        result(FlutterError(code: "SCHEDULE_ERROR", message: error.localizedDescription, details: nil))
                    } else {
                        result(nil)
                    }
                }
            }
        }
    }

    // MARK: - Cancel

    private func handleCancel(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String else {
            result(FlutterError(code: "MISSING_ID", message: "id is required", details: nil))
            return
        }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
        result(nil)
    }

    private func handleCancelAll(result: @escaping FlutterResult) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        result(nil)
    }

    // MARK: - Schedule Repeating

    private func handleScheduleRepeating(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deliverAtMs = args["deliverAtMs"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "deliverAtMs missing", details: nil))
            return
        }

        let repeatInterval = args["repeatInterval"] as? String ?? "daily"
        let id = args["id"] as? String ?? UUID().uuidString
        let imageUrl = args["imageUrl"] as? String

        let deliverAt = Date(timeIntervalSince1970: Double(deliverAtMs) / 1000.0)

        // Build matching date components based on repeat interval
        var comps: DateComponents
        switch repeatInterval {
        case "hourly":
            comps = Calendar.current.dateComponents([.minute, .second], from: deliverAt)
        case "weekly":
            comps = Calendar.current.dateComponents([.weekday, .hour, .minute, .second], from: deliverAt)
        default: // daily
            comps = Calendar.current.dateComponents([.hour, .minute, .second], from: deliverAt)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let content = self.buildContent(from: args)

            if let url = imageUrl {
                if let attachment = self.downloadAttachment(url: url) {
                    content.attachments = [attachment]
                }
            }

            // repeats: true makes UNCalendarNotificationTrigger fire repeatedly
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        result(FlutterError(code: "SCHEDULE_ERROR", message: error.localizedDescription, details: nil))
                    } else {
                        result(nil)
                    }
                }
            }
        }
    }

    // MARK: - Cancel Group

    private func handleCancelGroup(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let groupKey = args["groupKey"] as? String else {
            result(FlutterError(code: "MISSING_GROUP", message: "groupKey is required", details: nil))
            return
        }

        let center = UNUserNotificationCenter.current()
        let group = DispatchGroup()

        // Remove delivered notifications with matching threadIdentifier
        group.enter()
        center.getDeliveredNotifications { notifications in
            let ids = notifications
                .filter { $0.request.content.threadIdentifier == groupKey }
                .map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: ids)
            group.leave()
        }

        // Remove pending notifications with matching threadIdentifier
        group.enter()
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.content.threadIdentifier == groupKey }
                .map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            group.leave()
        }

        // Return result only after both operations complete
        group.notify(queue: .main) {
            result(nil)
        }
    }

    // MARK: - Get Pending

    private func handleGetPending(result: @escaping FlutterResult) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let list = requests.map { r -> [String: Any] in
                var entry: [String: Any] = [
                    "id":    r.identifier,
                    "title": r.content.title,
                    "body":  r.content.body,
                ]
                // Include next trigger date if available
                if let calTrigger = r.trigger as? UNCalendarNotificationTrigger,
                   let nextDate = calTrigger.nextTriggerDate() {
                    entry["deliverAtMs"] = Int(nextDate.timeIntervalSince1970 * 1000)
                }
                return entry
            }
            DispatchQueue.main.async { result(list) }
        }
    }

    // MARK: - Badge

    private func handleSetBadge(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let count = args["count"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "count missing", details: nil))
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = count
            result(nil)
        }
    }

    // MARK: - Get Delivered

    private func handleGetDelivered(result: @escaping FlutterResult) {
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let list = notifications.map { n -> [String: Any] in
                return [
                    "id":    n.request.identifier,
                    "title": n.request.content.title,
                    "body":  n.request.content.body,
                ]
            }
            DispatchQueue.main.async { result(list) }
        }
    }

    // MARK: - Get Initial Notification (cold start)

    private func handleGetInitial(result: @escaping FlutterResult) {
        let defaults = UserDefaults.standard
        if var queued = defaults.array(forKey: "fluera_pending_tap_events") as? [[String: Any]],
           let first = queued.first {
            // Consume the event so it's not returned again or re-flushed by onListen
            queued.removeFirst()
            if queued.isEmpty {
                defaults.removeObject(forKey: "fluera_pending_tap_events")
            } else {
                defaults.set(queued, forKey: "fluera_pending_tap_events")
            }
            result(first)
        } else {
            result(nil)
        }
    }

    // MARK: - Content Builder

    private func buildContent(from args: [String: Any]) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        content.title    = args["title"] as? String ?? ""
        content.body     = args["body"] as? String ?? ""
        content.subtitle = args["subtitle"] as? String ?? ""

        // Badge
        if let badge = args["badge"] as? Int {
            content.badge = NSNumber(value: badge)
        }

        // Sound
        if let soundName = args["sound"] as? String {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundName))
        } else {
            content.sound = .default
        }

        // User info — carry notification ID and custom data
        var userInfo: [String: Any] = [
            "notificationId": args["id"] as? String ?? "",
        ]
        if let data = args["data"] as? [String: String] {
            userInfo["data"] = data
        }
        content.userInfo = userInfo

        // Notification grouping (iOS equivalent of Android's groupKey)
        if let groupKey = args["groupKey"] as? String {
            content.threadIdentifier = groupKey
        }

        // Category for action buttons
        let categoryId   = args["category"] as? String ?? "general"
        let rawActions   = args["actions"] as? [[String: Any]] ?? []

        if !rawActions.isEmpty {
            let catIdentifier = "fluera_\(categoryId)_\(content.title.hashValue)"
            registerCategory(
                identifier: catIdentifier,
                rawActions: rawActions
            )
            content.categoryIdentifier = catIdentifier
        }

        // Image attachments are handled by the caller (handleShow/handleSchedule)
        // on a background thread to avoid the race condition.

        return content
    }

    // MARK: - Category Registration

    private func registerCategory(identifier: String, rawActions: [[String: Any]]) {
        // Skip if this exact category was already registered this session
        if registeredCategories.contains(identifier) { return }
        registeredCategories.insert(identifier)

        var actions: [UNNotificationAction] = []

        for raw in rawActions {
            guard let id = raw["id"] as? String, let label = raw["label"] as? String else { continue }
            let isDestructive  = raw["isDestructive"] as? Bool ?? false
            let isAuthRequired = raw["isAuthRequired"] as? Bool ?? false
            let openApp        = raw["openApp"] as? Bool ?? true
            let requireInput   = raw["requireInput"] as? Bool ?? false
            let placeholder    = raw["inputPlaceholder"] as? String ?? "Scrivi..."

            var options: UNNotificationActionOptions = []
            if isDestructive  { options.insert(.destructive) }
            if isAuthRequired { options.insert(.authenticationRequired) }
            if openApp        { options.insert(.foreground) }

            if requireInput {
                actions.append(UNTextInputNotificationAction(
                    identifier: id,
                    title: label,
                    options: options,
                    textInputButtonTitle: label,
                    textInputPlaceholder: placeholder
                ))
            } else {
                actions.append(UNNotificationAction(identifier: id, title: label, options: options))
            }
        }

        let category = UNNotificationCategory(
            identifier: identifier,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var updated = existing
            updated.insert(category)
            UNUserNotificationCenter.current().setNotificationCategories(updated)
        }
    }

    // MARK: - Rich Attachment (synchronous — call from background thread)

    /// Downloads or resolves an image and returns a `UNNotificationAttachment`.
    /// This method blocks the calling thread, so it MUST be called from a
    /// background queue (which `handleShow` and `handleSchedule` already do).
    private func downloadAttachment(url: String) -> UNNotificationAttachment? {
        // Try loading from assets bundle first
        let filename = url.components(separatedBy: "/").last ?? url
        let nameWithoutExt = filename.components(separatedBy: ".").first
        let ext = filename.components(separatedBy: ".").count > 1 ? filename.components(separatedBy: ".").last : nil

        if let name = nameWithoutExt,
           let bundleUrl = Bundle.main.url(forResource: name, withExtension: ext) {
            return try? UNNotificationAttachment(identifier: "img", url: bundleUrl, options: nil)
        }

        // Download from remote URL with timeout (synchronous — we're on a background thread)
        guard url.hasPrefix("http"), let remoteUrl = URL(string: url) else { return nil }

        let semaphore = DispatchSemaphore(value: 0)
        var downloadedData: Data?

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10   // 10s per request
        config.timeoutIntervalForResource = 15  // 15s total
        let session = URLSession(configuration: config)

        session.dataTask(with: remoteUrl) { data, _, _ in
            downloadedData = data
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 15)
        session.invalidateAndCancel()

        guard let data = downloadedData else { return nil }

        let tempUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext ?? "jpg")
        try? data.write(to: tempUrl)

        return try? UNNotificationAttachment(identifier: "img", url: tempUrl, options: nil)
    }
}
