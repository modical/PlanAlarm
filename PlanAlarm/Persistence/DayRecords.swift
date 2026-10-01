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
    /// The plan the day was locked in with: `StoredPlan.id` as a string, "none" for no plan,
    /// or "" for days recorded before this was tracked.
    var planKey: String = ""
    /// False for a day that passed without a check-in and was recorded afterwards from the plan.
    var checkedIn: Bool = true

    init(date: LocalDate, dayNote: String?, planName: String?, planKey: String, checkedIn: Bool = true,
         lockedInAt: Date = .now) {
        self.date = date.description
        self.dayNote = dayNote
        self.planName = planName
        self.planKey = planKey
        self.checkedIn = checkedIn
        self.lockedInAt = lockedInAt
    }

    static func planKey(for stored: StoredPlan?) -> String {
        stored?.id.uuidString ?? "none"
    }

    /// Whether the day still follows `active`: a locked-in day follows edits to the plan it was locked in
    /// with, but not a different plan being loaded, or the plan being deleted.
    func follows(_ active: StoredPlan?) -> Bool {
        planKey.isEmpty || planKey == Self.planKey(for: active)
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
    static func lockIn(date: LocalDate, dayNote: String?, planName: String?, planKey: String = "none", items: [CheckInItem],
                       now: Date = .now, in context: ModelContext = AppDatabase.context) throws -> [TaskRecord] {
        context.insert(DayRecord(date: date, dayNote: dayNote, planName: planName, planKey: planKey, lockedInAt: now))
        // After an unlock, records kept from earlier in the day come first.
        let firstOrder = (DayStore.records(on: date, in: context).map(\.order).max() ?? -1) + 1
        let records = items.enumerated().map { offset, item in
            TaskRecord(date: date, order: firstOrder + offset, task: item.task, isExtra: item.isExtra,
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

    /// Whether a record was resolved by the user during the day (done, or skipped after the check-in),
    /// as opposed to skipped at the check-in itself.
    static func wasResolvedDuringDay(_ record: TaskRecord) -> Bool {
        switch record.status {
        case .done: true
        case .skipped: record.skippedAt != record.lockedInAt
        default: false
        }
    }

    /// Unlocks a day so the check-in can be done again. Tasks already done or skipped during the day are
    /// kept; every other record is removed. Returns the alarm keys whose chains must be cancelled.
    @discardableResult
    static func unlock(_ date: LocalDate, in context: ModelContext = AppDatabase.context) throws -> [String] {
        let key = date.description
        for day in try context.fetch(FetchDescriptor<DayRecord>(predicate: #Predicate { $0.date == key })) {
            context.delete(day)
        }
        var cancelled: [String] = []
        for record in records(on: date, in: context) where !wasResolvedDuringDay(record) {
            cancelled.append(record.alarmKey)
            context.delete(record)
        }
        try context.save()
        return cancelled
    }

    /// Records the days since the last recorded day that passed without a check-in, from the plan as it is
    /// now. That is the plan that was in effect on those days: a plan can only be loaded, edited or deleted
    /// with the app open, and this runs whenever the app opens. Yesterday's tasks stay open, so the morning
    /// check-in asks "Did you do these?"; older days' tasks are recorded as not logged. Once recorded, a past
    /// day never changes with the plan. Days before the first recorded day aren't touched.
    @discardableResult
    static func recordDaysWithoutCheckIn(before today: LocalDate,
                                         in context: ModelContext = AppDatabase.context) -> [LocalDate] {
        var latestDayDescriptor = FetchDescriptor<DayRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        latestDayDescriptor.fetchLimit = 1
        var latestTaskDescriptor = FetchDescriptor<TaskRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        latestTaskDescriptor.fetchLimit = 1
        let latestKeys = [(try? context.fetch(latestDayDescriptor))?.first?.date,
                          (try? context.fetch(latestTaskDescriptor))?.first?.date].compactMap { $0 }
        guard let latest = latestKeys.max().flatMap(LocalDate.init(isoString:)) else { return [] }

        let yesterday = today.adding(days: -1)
        let activePlans = (try? context.fetch(FetchDescriptor<StoredPlan>(predicate: #Predicate { $0.isActive == true }))) ?? []
        let stored = activePlans.first
        let planName = stored.flatMap { PlanStore.plan(for: $0) }?.name
        var recorded: [LocalDate] = []
        var date = latest.adding(days: 1)
        // A safety cap: at most a year of days at once.
        while date < today && recorded.count < 366 {
            let agenda = DayAgenda.current(on: date, in: context)
            let start = date.date(hour: 0, minute: 0)
            context.insert(DayRecord(date: date, dayNote: agenda.day.dayNote, planName: planName,
                                     planKey: DayRecord.planKey(for: stored), checkedIn: false, lockedInAt: start))
            for (order, task) in agenda.day.tasks.enumerated() {
                let time = task.suggestedTime.map { date.date(hour: $0.hour, minute: $0.minute) }
                context.insert(TaskRecord(date: date, order: order, task: task, isExtra: order >= agenda.planTaskCount,
                                          scheduledFor: time, status: date == yesterday ? .scheduled : .unlogged,
                                          unlockSeconds: nil, lockedInAt: start))
            }
            recorded.append(date)
            date = date.adding(days: 1)
        }
        if !recorded.isEmpty { try? context.save() }
        return recorded
    }

    /// Deletes one task from a past day. Past days are otherwise never changed (not by loading, editing
    /// or deleting plans), so this manual delete is the only way one changes.
    static func deleteRecord(_ record: TaskRecord, in context: ModelContext = AppDatabase.context) throws {
        context.delete(record)
        try context.save()
    }

    /// Brings a done, skipped or not-logged task back. It keeps its time; if that time has passed,
    /// it needs a new one before it can ring.
    static func undo(_ record: TaskRecord, in context: ModelContext = AppDatabase.context) throws {
        record.status = .scheduled
        record.doneAt = nil
        record.skippedAt = nil
        record.ringingAt = nil
        record.acknowledgedAt = nil
        try context.save()
    }

    /// Gives a task a new time today. Its alarm must then be scheduled for that time.
    static func reschedule(_ record: TaskRecord, to time: Date, in context: ModelContext = AppDatabase.context) throws {
        record.status = .scheduled
        record.scheduledFor = time
        record.ringingAt = nil
        record.acknowledgedAt = nil
        try context.save()
    }

    /// Brings a locked-in day in line with the plan after the plan (or the day's extra tasks) changed:
    /// tasks new to the day are added (at their plan time if it's still ahead, otherwise without a time),
    /// and tasks no longer in the day are removed unless they were done or skipped during the day.
    /// Tasks are matched by title. Returns the added records and the alarm keys of removed ones.
    /// With `extrasOnly` (the day was locked in with a different plan, or the plan was deleted) only tasks
    /// added in the app are synced: the day keeps the plan tasks it was locked in with.
    static func sync(_ date: LocalDate, with agenda: DayAgenda, planDefaultReadSeconds: Int?, extrasOnly: Bool = false,
                     now: Date = .now,
                     in context: ModelContext = AppDatabase.context) throws -> (added: [TaskRecord], removedKeys: [String]) {
        var unmatched = records(on: date, in: context).filter { !extrasOnly || $0.isExtra }
        var newItems: [CheckInItem] = []
        for item in CheckInPlanner.items(for: agenda, planDefaultReadSeconds: planDefaultReadSeconds, now: now)
            where !extrasOnly || item.isExtra {
            if let index = unmatched.firstIndex(where: { $0.title == item.task.title && $0.isExtra == item.isExtra }) {
                let record = unmatched.remove(at: index)
                // Keep open tasks' details (exercise lists etc.) up to date with the plan.
                if !record.status.isResolved, let data = try? JSONEncoder().encode(item.task), data != record.taskJSON {
                    record.taskJSON = data
                    record.category = item.task.category
                }
            } else {
                newItems.append(item)
            }
        }

        var removedKeys: [String] = []
        for record in unmatched where !wasResolvedDuringDay(record) {
            removedKeys.append(record.alarmKey)
            context.delete(record)
        }

        var nextOrder = (records(on: date, in: context).map(\.order).max() ?? -1) + 1
        var added: [TaskRecord] = []
        for item in newItems {
            let record = TaskRecord(date: date, order: nextOrder, task: item.task, isExtra: item.isExtra,
                                    scheduledFor: item.timeWasMoved ? nil : item.time, status: .scheduled,
                                    unlockSeconds: item.unlockSeconds, lockedInAt: now)
            context.insert(record)
            added.append(record)
            nextOrder += 1
        }
        if !added.isEmpty || !removedKeys.isEmpty {
            try context.save()
        }
        return (added, removedKeys)
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

    /// "Starting now" on the read screen: the task is in progress. `snoozeCount` rings are added to its total.
    static func markStarted(alarmKey: String, snoozeCount: Int, now: Date = .now,
                                 in context: ModelContext = AppDatabase.context) {
        guard let record = record(forAlarmKey: alarmKey, in: context), !record.status.isResolved else { return }
        record.status = .inProgress
        record.acknowledgedAt = now
        record.startedAt = now
        record.ringingAt = record.ringingAt ?? record.scheduledFor
        record.snoozeCount += snoozeCount
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
