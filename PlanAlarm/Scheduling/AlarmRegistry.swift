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
    /// Check-in reminder rings per date ("YYYY-MM-DD"), for days not yet locked in.
    var checkInChains: [String: [ScheduledRing]] = [:]
    /// The "Reinstall PlanAlarm" alarm before this install expires.
    var expiryReminder: ScheduledRing?

    static let defaultsKey = "alarmRegistry.v2"

    /// Every alarm ID the app knows about.
    var knownAlarmIDs: Set<UUID> {
        Set(wakeAlarmIDs + testAlarmIDs + tasks.flatMap(\.alarmIDs) + checkInChains.values.flatMap { $0.map(\.id) }
            + [expiryReminder?.id].compactMap { $0 })
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

extension AlarmRegistry {
    private enum CodingKeys: String, CodingKey {
        case wakeAlarmIDs, testAlarmIDs, tasks, checkInChains, expiryReminder
    }

    /// Fields added in later versions may be missing from saved data; they default to empty
    /// instead of making the whole registry unreadable.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wakeAlarmIDs = try container.decodeIfPresent([UUID].self, forKey: .wakeAlarmIDs) ?? []
        testAlarmIDs = try container.decodeIfPresent([UUID].self, forKey: .testAlarmIDs) ?? []
        tasks = try container.decodeIfPresent([PendingTaskAlarm].self, forKey: .tasks) ?? []
        checkInChains = try container.decodeIfPresent([String: [ScheduledRing]].self, forKey: .checkInChains) ?? [:]
        expiryReminder = try container.decodeIfPresent(ScheduledRing.self, forKey: .expiryReminder)
    }
}
