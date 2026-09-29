import Foundation

/// One AlarmKit alarm in a task's chain.
struct ScheduledRing: Codable, Hashable, Sendable {
    var id: UUID
    var date: Date
}

/// A task alarm that keeps ringing until the task is stopped in the app.
///
/// The task gets a *chain* of alarms, one per snooze interval, scheduled in advance. iOS stops an alarm
/// on Stop, slide-to-stop and every physical button, and doesn't always run our stop intent, so the
/// next ring must already be scheduled. Stopping the task in the app cancels the whole chain.
struct PendingTaskAlarm: Codable, Hashable, Sendable, Identifiable {
    /// Identifies the task occurrence (e.g. "2026-10-05#1", or "test-…" for debug alarms).
    var key: String
    /// A copy of the task, so the alarm still works if the plan is edited or deleted.
    var task: PlanTask
    /// When the first alarm for this task was due.
    var firstAlarmAt: Date
    /// The scheduled alarms, earliest first.
    var rings: [ScheduledRing]
    var snoozeCount = 0
    /// Seconds before Stop Alarm unlocks, when the task sets its own; nil means the Settings value.
    var unlockSeconds: Int?

    var id: String { key }

    var alarmIDs: [UUID] { rings.map(\.id) }

    /// The next ring still to come.
    func nextRing(after date: Date = .now) -> ScheduledRing? {
        rings.first { $0.date > date }
    }

    /// True once the first alarm time has passed: the task is waiting to be stopped in the app.
    func isPendingAcknowledgement(now: Date = .now) -> Bool {
        firstAlarmAt <= now
    }
}

/// Which AlarmKit alarms belong to what. AlarmKit doesn't expose an alarm's metadata after scheduling,
/// so the app keeps this small record itself (in UserDefaults: operational state, not user data).
struct AlarmRegistry: Codable, Sendable {
    var wakeAlarmIDs: [UUID] = []
    /// One-off debug alarms, kept so the clean-up in `AlarmService.refresh()` leaves them alone.
    var testAlarmIDs: [UUID] = []
    var tasks: [PendingTaskAlarm] = []

    static let defaultsKey = "alarmRegistry.v2"

    /// Every alarm ID the app knows about.
    var knownAlarmIDs: Set<UUID> {
        Set(wakeAlarmIDs + testAlarmIDs + tasks.flatMap(\.alarmIDs))
    }

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

    /// Ring times for a chain: `count` alarms, `interval` apart, starting at `first`.
    static func chainDates(startingAt first: Date, interval: TimeInterval, count: Int) -> [Date] {
        (0..<max(1, count)).map { first.addingTimeInterval(TimeInterval($0) * interval) }
    }

    /// How many rings a chain gets: enough to cover an hour, between 3 and 12.
    static func chainLength(snoozeInterval: TimeInterval) -> Int {
        let needed = Int((3600 / max(60, snoozeInterval)).rounded(.up)) + 1
        return min(12, max(3, needed))
    }
}
