import Foundation
import SwiftData

/// Where a task stands on its day: scheduled → ringing (waiting to be stopped) → in progress → done | skipped.
/// `unlogged` means it was never resolved.
enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case scheduled, ringing, inProgress, done, skipped, unlogged

    var isResolved: Bool {
        switch self {
        case .done, .skipped, .unlogged: true
        case .scheduled, .ringing, .inProgress: false
        }
    }

    var label: String {
        switch self {
        case .scheduled: "Scheduled"
        case .ringing: "Ringing"
        case .inProgress: "In progress"
        case .done: "Done"
        case .skipped: "Skipped"
        case .unlogged: "Not logged"
        }
    }
}

/// A day the user locked in at the morning check-in.
@Model
final class DayRecord {
    /// "YYYY-MM-DD"
    var date: String = ""
    var dayNote: String?
    var planName: String?
    var lockedInAt: Date = Date.now

    init(date: LocalDate, dayNote: String?, planName: String?, lockedInAt: Date = .now) {
        self.date = date.description
        self.dayNote = dayNote
        self.planName = planName
        self.lockedInAt = lockedInAt
    }
}

/// One task on one day, with its chosen time, status and timestamps. Holds a copy of the task,
/// so history never depends on the plan still existing.
@Model
final class TaskRecord {
    var id: UUID = UUID()
    /// "YYYY-MM-DD"
    var date: String = ""
    var order: Int = 0
    var title: String = ""
    var category: String = ""
    /// JSON-encoded `PlanTask`.
    var taskJSON: Data = Data()
    /// True for tasks added in the app (`ExtraTask`) rather than from the plan.
    var isExtra: Bool = false
    var statusRaw: String = TaskStatus.scheduled.rawValue
    /// The alarm time chosen at check-in (nil for tasks skipped at check-in).
    var scheduledFor: Date?
    /// Seconds before Stop Alarm unlocks, when the task sets its own.
    var unlockSeconds: Int?
    var snoozeCount: Int = 0
    var lockedInAt: Date?
    var ringingAt: Date?
    var acknowledgedAt: Date?
    var startedAt: Date?
    var doneAt: Date?
    var skippedAt: Date?

    init(date: LocalDate, order: Int, task: PlanTask, isExtra: Bool, scheduledFor: Date?, status: TaskStatus,
         unlockSeconds: Int?, lockedInAt: Date) {
        self.id = UUID()
        self.date = date.description
        self.order = order
        self.title = task.title
        self.category = task.category
        self.taskJSON = (try? JSONEncoder().encode(task)) ?? Data()
        self.isExtra = isExtra
        self.statusRaw = status.rawValue
        self.scheduledFor = scheduledFor
        self.unlockSeconds = unlockSeconds
        self.lockedInAt = lockedInAt
        if status == .skipped { self.skippedAt = lockedInAt }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .unlogged }
        set { statusRaw = newValue.rawValue }
    }

    var task: PlanTask? {
        try? JSONDecoder().decode(PlanTask.self, from: taskJSON)
    }

    /// The key of this task's alarm chain in `AlarmService`.
    var alarmKey: String { id.uuidString }
}

/// Reads and writes day and task records.
@MainActor
enum DayStore {
    private static let unresolvedStatuses = [TaskStatus.scheduled.rawValue, TaskStatus.ringing.rawValue, TaskStatus.inProgress.rawValue]

    static func isLockedIn(_ date: LocalDate, in context: ModelContext = AppDatabase.context) -> Bool {
        let key = date.description
        let count = (try? context.fetchCount(FetchDescriptor<DayRecord>(predicate: #Predicate { $0.date == key }))) ?? 0
        return count > 0
    }

    static func records(on date: LocalDate, in context: ModelContext = AppDatabase.context) -> [TaskRecord] {
        let key = date.description
        let descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.date == key }, sortBy: [SortDescriptor(\.order)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func record(forAlarmKey key: String, in context: ModelContext = AppDatabase.context) -> TaskRecord? {
        guard let id = UUID(uuidString: key) else { return nil }
        return try? context.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })).first
    }

    /// Tasks on `date` that were never resolved (asked about at the next check-in).
    static func unresolvedRecords(on date: LocalDate, in context: ModelContext = AppDatabase.context) -> [TaskRecord] {
        records(on: date, in: context).filter { !$0.status.isResolved }
    }

    /// Creates the day's records from the check-in. Skipped tasks are recorded as skipped (no alarm).
    @discardableResult
    static func lockIn(date: LocalDate, dayNote: String?, planName: String?, items: [CheckInItem],
                       now: Date = .now, in context: ModelContext = AppDatabase.context) throws -> [TaskRecord] {
        context.insert(DayRecord(date: date, dayNote: dayNote, planName: planName, lockedInAt: now))
        let records = items.enumerated().map { order, item in
            TaskRecord(date: date, order: order, task: item.task, isExtra: item.isExtra,
                       scheduledFor: item.isSkipped ? nil : item.time,
                       status: item.isSkipped ? .skipped : .scheduled,
                       unlockSeconds: item.unlockSeconds, lockedInAt: now)
        }
        for record in records {
            context.insert(record)
        }
        try context.save()
        return records
    }

    /// Logs a task as done or skipped.
    static func log(_ record: TaskRecord, as status: TaskStatus, now: Date = .now,
                    in context: ModelContext = AppDatabase.context) throws {
        record.status = status
        switch status {
        case .done: record.doneAt = now
        case .skipped: record.skippedAt = now
        default: break
        }
        try context.save()
    }

    /// The task's alarm was stopped in the app.
    static func markAcknowledged(alarmKey: String, snoozeCount: Int, now: Date = .now,
                                 in context: ModelContext = AppDatabase.context) {
        guard let record = record(forAlarmKey: alarmKey, in: context), !record.status.isResolved else { return }
        record.status = .inProgress
        record.acknowledgedAt = now
        record.ringingAt = record.ringingAt ?? record.scheduledFor
        record.snoozeCount = snoozeCount
        try? context.save()
    }

    /// Marks scheduled tasks whose alarm has started ringing.
    static func markRinging(_ pending: [(key: String, firstAlarmAt: Date)], in context: ModelContext = AppDatabase.context) {
        var changed = false
        for item in pending {
            guard let record = record(forAlarmKey: item.key, in: context), record.status == .scheduled else { continue }
            record.status = .ringing
            record.ringingAt = item.firstAlarmAt
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Marks unresolved tasks from before `date` as not logged. Returns their alarm keys.
    @discardableResult
    static func markUnlogged(before date: LocalDate, in context: ModelContext = AppDatabase.context) -> [String] {
        let statuses = unresolvedStatuses
        let descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { statuses.contains($0.statusRaw) })
        let key = date.description
        let old = ((try? context.fetch(descriptor)) ?? []).filter { $0.date < key }
        for record in old {
            record.status = .unlogged
        }
        if !old.isEmpty { try? context.save() }
        return old.map(\.alarmKey)
    }
}
