import Foundation
@preconcurrency import UserNotifications

/// The "Did you finish …?" follow-up: a normal notification (not an alarm) with Done / Skipped buttons,
/// sent at the task's start time plus its duration (or plus 60 minutes if it has none).
@MainActor
enum FollowUpService {
    nonisolated static let categoryID = "TASK_FOLLOW_UP"
    nonisolated static let doneActionID = "FOLLOW_UP_DONE"
    nonisolated static let skippedActionID = "FOLLOW_UP_SKIPPED"
    nonisolated static let taskKeyInfo = "taskKey"
    nonisolated static let defaultMinutes = 60

    /// Registers the Done / Skipped buttons. Call at launch.
    static func registerCategory() {
        let done = UNNotificationAction(identifier: doneActionID, title: "Done", options: [])
        let skipped = UNNotificationAction(identifier: skippedActionID, title: "Skipped", options: [])
        let category = UNNotificationCategory(identifier: categoryID, actions: [done, skipped],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// When the follow-up is sent.
    nonisolated static func followUpDate(startedAt: Date, durationMinutes: Int?) -> Date {
        startedAt.addingTimeInterval(TimeInterval((durationMinutes ?? defaultMinutes) * 60))
    }

    enum Permission {
        case allowed, denied, notAsked
    }

    static func permission() async -> Permission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notAsked
        case .denied: .denied
        default: .allowed
        }
    }

    /// Asks for permission the first time; returns whether notifications are allowed.
    @discardableResult
    static func ensurePermission() async -> Bool {
        switch await permission() {
        case .allowed: return true
        case .denied: return false
        case .notAsked:
            let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return granted ?? false
        }
    }

    /// Schedules the follow-up for a task that just started (if enabled in Settings).
    static func schedule(taskKey: String, title: String, durationMinutes: Int?, startedAt: Date = .now) async {
        guard AppSettings.current().followUpEnabled, await ensurePermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Did you finish \(title)?"
        content.body = "Mark it Done or Skipped."
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = [taskKeyInfo: taskKey]
        let delay = max(5, followUpDate(startedAt: startedAt, durationMinutes: durationMinutes).timeIntervalSinceNow)
        let request = UNNotificationRequest(identifier: identifier(for: taskKey), content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancel(taskKeys: [String]) {
        let ids = taskKeys.map(identifier(for:))
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Done / Skipped tapped on the notification.
    static func handle(actionID: String, taskKey: String) {
        let status: TaskStatus
        switch actionID {
        case doneActionID: status = .done
        case skippedActionID: status = .skipped
        default: return // tapping the notification itself just opens the app
        }
        guard let record = DayStore.record(forAlarmKey: taskKey), !record.status.isResolved else { return }
        TaskActions.log(record, as: status)
    }

    private static func identifier(for taskKey: String) -> String {
        "followup-\(taskKey)"
    }
}

/// Receives notification taps and button presses, including when the app was launched in the background.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelegate()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let actionID = response.actionIdentifier
        guard let taskKey = response.notification.request.content.userInfo[FollowUpService.taskKeyInfo] as? String else { return }
        await FollowUpService.handle(actionID: actionID, taskKey: taskKey)
    }

    /// Show follow-ups even while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
