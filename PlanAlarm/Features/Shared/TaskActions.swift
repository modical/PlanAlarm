import Foundation
import SwiftData

/// Everything that can happen to a task, in one place, so the read screen, the Today timeline and the
/// follow-up notification buttons keep the day's records, the alarm chains and the follow-ups in step.
@MainActor
enum TaskActions {
    private static var alarms: AlarmService { .shared }

    // MARK: - From the read screen (a ringing task)

    /// "Starting now": the alarm stops for good, the task is in progress, and the follow-up is set.
    static func start(_ pending: PendingTaskAlarm, in context: ModelContext = AppDatabase.context) {
        let snoozes = alarms.snoozeCount(for: pending)
        alarms.acknowledge(taskKey: pending.key)
        DayStore.markStarted(alarmKey: pending.key, snoozeCount: snoozes, in: context)
        let now = Date.now
        Task {
            await FollowUpService.schedule(taskKey: pending.key, title: pending.task.title,
                                           durationMinutes: pending.task.durationMinutes, startedAt: now)
        }
    }

    /// "Reschedule": a new time later today; the task will ring (and be read) again then.
    static func reschedule(_ pending: PendingTaskAlarm, to time: Date, in context: ModelContext = AppDatabase.context) async {
        let record = DayStore.record(forAlarmKey: pending.key, in: context)
        stopAlarm(key: pending.key, countingSnoozesOn: record)
        if let record {
            try? DayStore.reschedule(record, to: time, in: context)
        }
        FollowUpService.cancel(taskKeys: [pending.key])
        await alarms.scheduleTaskAlarm(for: pending.task, key: pending.key, at: time, unlockSeconds: pending.unlockSeconds)
    }

    /// "Skip today".
    static func skip(_ pending: PendingTaskAlarm, in context: ModelContext = AppDatabase.context) {
        let record = DayStore.record(forAlarmKey: pending.key, in: context)
        stopAlarm(key: pending.key, countingSnoozesOn: record)
        if let record, !record.status.isResolved {
            try? DayStore.log(record, as: .skipped, in: context)
        }
        FollowUpService.cancel(taskKeys: [pending.key])
    }

    // MARK: - From the Today timeline and notifications

    /// Done or skipped: stops any alarm and follow-up for the task.
    static func log(_ record: TaskRecord, as status: TaskStatus, in context: ModelContext = AppDatabase.context) {
        stopAlarm(key: record.alarmKey, countingSnoozesOn: record)
        try? DayStore.log(record, as: status, in: context)
        FollowUpService.cancel(taskKeys: [record.alarmKey])
    }

    /// Brings a finished task back; its alarm is set again if its time is still ahead.
    static func undo(_ record: TaskRecord, in context: ModelContext = AppDatabase.context) throws {
        try DayStore.undo(record, in: context)
        scheduleAlarms(for: [record])
    }

    /// A new time for a day's task (the alarm moves; any follow-up is dropped).
    static func reschedule(_ record: TaskRecord, to time: Date, in context: ModelContext = AppDatabase.context) throws {
        stopAlarm(key: record.alarmKey, countingSnoozesOn: record)
        try DayStore.reschedule(record, to: time, in: context)
        FollowUpService.cancel(taskKeys: [record.alarmKey])
        if AppRouter.shared.presentedTaskKey == record.alarmKey {
            AppRouter.shared.presentedTaskKey = nil
        }
        scheduleAlarms(for: [record])
    }

    /// Tasks removed from the day (unlock, or the plan changed): cancel their alarms and follow-ups.
    static func removed(taskKeys: [String]) {
        for key in taskKeys {
            alarms.acknowledge(taskKey: key)
        }
        FollowUpService.cancel(taskKeys: taskKeys)
    }

    // MARK: - Alarms for records

    /// The alarm for a record: scheduled, with a time still ahead.
    static func alarmRequest(for record: TaskRecord) -> TaskAlarmRequest? {
        guard record.status == .scheduled, let task = record.task,
              let time = record.scheduledFor, time > .now else { return nil }
        return TaskAlarmRequest(task: task, key: record.alarmKey, date: time, unlockSeconds: record.unlockSeconds)
    }

    /// Sets the alarms of these records (those with a time still ahead).
    static func scheduleAlarms(for records: [TaskRecord]) {
        let requests = records.compactMap(alarmRequest(for:))
        guard !requests.isEmpty else { return }
        Task {
            await alarms.scheduleTaskAlarms(requests)
        }
    }

    /// Brings the alarm chains in line with the day records (run each time the app becomes active):
    /// - chains of tasks from earlier days stop: those are asked about at the next morning check-in;
    /// - chains of tasks that are finished, in progress or deleted stop;
    /// - today's scheduled tasks whose alarm is missing (e.g. lost alarm data) get it back.
    static func reconcile(today: LocalDate = .today(), in context: ModelContext = AppDatabase.context) async {
        let startOfToday = today.date(hour: 0, minute: 0)
        for entry in alarms.registry.tasks {
            if entry.key.hasPrefix("test-") {
                if entry.firstAlarmAt < startOfToday { alarms.acknowledge(taskKey: entry.key) }
                continue
            }
            guard let record = DayStore.record(forAlarmKey: entry.key, in: context) else {
                alarms.acknowledge(taskKey: entry.key)
                continue
            }
            let stillRings = record.date == today.description && (record.status == .scheduled || record.status == .ringing)
            if !stillRings {
                stopAlarm(key: entry.key, countingSnoozesOn: record)
                try? context.save()
            }
        }
        let missing = DayStore.records(on: today, in: context)
            .filter { alarms.registry.task(forKey: $0.alarmKey) == nil }
            .compactMap(alarmRequest(for:))
        await alarms.scheduleTaskAlarms(missing)
    }

    /// Stops a task's alarm chain, adding the times it rang again to the record's snooze count.
    private static func stopAlarm(key: String, countingSnoozesOn record: TaskRecord?) {
        guard let entry = alarms.registry.task(forKey: key) else { return }
        record?.snoozeCount += alarms.snoozeCount(for: entry)
        alarms.acknowledge(taskKey: key)
    }
}
