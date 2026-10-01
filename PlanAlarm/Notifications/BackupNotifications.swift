import Foundation
@preconcurrency import UserNotifications

/// Plain notifications sent with the alarm rings, as a second net: they stay on the Lock Screen even if a
/// ring was stopped by accident. They make no sound in silent mode and Focus can hold them back, so the
/// alarms are what really ring. Only added once notifications are allowed (this never asks by itself).
@MainActor
enum BackupNotifications {
    struct Item: Sendable {
        /// Unique per ring (the ring's alarm ID).
        var id: String
        var date: Date
        var title: String
        var body: String
        /// "wake", or the task's key: used to clear delivered ones.
        var thread: String
    }

    nonisolated static let prefix = "backup-"
    nonisolated static let wakeThread = "wake"

    /// Makes the pending backup notifications match `items`: removes the ones no longer wanted and adds the
    /// missing ones.
    static func sync(_ items: [Item]) async {
        guard await FollowUpService.permission() == .allowed else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        var wanted: [String: Item] = [:]
        for item in items {
            wanted[prefix + item.id] = item
        }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { wanted[$0] == nil })

        let existing = Set(pending)
        for (identifier, item) in wanted where !existing.contains(identifier) {
            let delay = item.date.timeIntervalSinceNow
            guard delay > 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = item.thread
            let request = UNNotificationRequest(identifier: identifier, content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))
            try? await center.add(request)
        }
    }

    /// Removes delivered backup notifications of one thread (the wake-up, or one task).
    static func clearDelivered(thread: String) async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.deliveredNotifications()
            .filter { $0.request.identifier.hasPrefix(prefix) && $0.request.content.threadIdentifier == thread }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
