import Foundation

/// A task alarm that keeps ringing until the task is acknowledged in the app.
struct PendingTaskAlarm: Codable, Hashable, Sendable, Identifiable {
    /// Identifies the task occurrence (e.g. "2026-10-05#1", or "test-…" for debug alarms).
    var key: String
    /// A copy of the task, so the alarm still works if the plan is edited or deleted.
    var task: PlanTask
    /// When the first alarm for this task was due.
    var firstAlarmAt: Date
    /// The AlarmKit alarm currently scheduled for it.
    var alarmID: UUID
    var nextAlarmAt: Date
    var snoozeCount = 0

    var id: String { key }

    /// True once the first alarm time has passed: the task is waiting to be acknowledged.
    func isPendingAcknowledgement(now: Date = .now) -> Bool {
        firstAlarmAt <= now
    }
}

/// Which AlarmKit alarms belong to what. AlarmKit doesn't expose an alarm's metadata after scheduling,
/// so the app keeps this small record itself (in UserDefaults: operational state, not user data).
struct AlarmRegistry: Codable, Sendable {
    var wakeAlarmIDs: [UUID] = []
    var tasks: [PendingTaskAlarm] = []

    static let defaultsKey = "alarmRegistry.v1"

    static func load(from defaults: UserDefaults = .standard) -> AlarmRegistry {
        guard let data = defaults.data(forKey: defaultsKey),
              let registry = try? JSONDecoder().decode(AlarmRegistry.self, from: data) else {
            return AlarmRegistry()
        }
        return registry
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    func task(forKey key: String) -> PendingTaskAlarm? {
        tasks.first { $0.key == key }
    }

    mutating func upsert(_ task: PendingTaskAlarm) {
        if let index = tasks.firstIndex(where: { $0.key == task.key }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
    }

    mutating func removeTask(forKey key: String) {
        tasks.removeAll { $0.key == key }
    }
}
