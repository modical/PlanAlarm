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
        DayStore.markAcknowledged(alarmKey: pending.key, snoozeCount: snoozes, in: context)
        let now = Date.now
        Task {
            await FollowUpService.schedule(taskKey: pending.key, title: pending.task.title,
                                           durationMinutes: pending.task.durationMinutes, startedAt: now)
        }
    }

    /// "Reschedule": a new time later today; the task will ring (and be read) again then.
    static func reschedule(_ pending: PendingTaskAlarm, to time: Date, in context: ModelContext = AppDatabase.context) async {
        let snoozes = alarms.snoozeCount(for: pending)
        if let record = DayStore.record(forAlarmKey: pending.key, in: context) {
            record.snoozeCount += snoozes
            try? DayStore.reschedule(record, to: time, in: context)
        }
        FollowUpService.cancel(taskKeys: [pending.key])
        await alarms.scheduleTaskAlarm(for: pending.task, key: pending.key, at: time, unlockSeconds: pending.unlockSeconds)
    }

    /// "Skip today".
    static func skip(_ pending: PendingTaskAlarm, in context: ModelContext = AppDatabase.context) {
        let snoozes = alarms.snoozeCount(for: pending)
        alarms.acknowledge(taskKey: pending.key)
        if let record = DayStore.record(forAlarmKey: pending.key, in: context), !record.status.isResolved {
            record.snoozeCount += snoozes
            try? DayStore.log(record, as: .skipped, in: context)
        }
        FollowUpService.cancel(taskKeys: [pending.key])
    }

    // MARK: - From the Today timeline and notifications

    /// Done or skipped: stops any alarm and follow-up for the task.
    static func log(_ record: TaskRecord, as status: TaskStatus, in context: ModelContext = AppDatabase.context) {
        try? DayStore.log(record, as: status, in: context)
        alarms.acknowledge(taskKey: record.alarmKey)
        FollowUpService.cancel(taskKeys: [record.alarmKey])
    }

    /// Brings a finished task back; its alarm is set again if its time is still ahead.
    static func undo(_ record: TaskRecord, in context: ModelContext = AppDatabase.context) throws {
        try DayStore.undo(record, in: context)
        scheduleAlarm(for: record)
    }

    /// A new time for a day's task (the alarm moves; any follow-up is dropped).
    static func reschedule(_ record: TaskRecord, to time: Date, in context: ModelContext = AppDatabase.context) throws {
        try DayStore.reschedule(record, to: time, in: context)
        FollowUpService.cancel(taskKeys: [record.alarmKey])
        if AppRouter.shared.presentedTaskKey == record.alarmKey {
            AppRouter.shared.presentedTaskKey = nil
        }
        scheduleAlarm(for: record)
    }

    /// Tasks removed from the day (unlock, or the plan changed): cancel their alarms and follow-ups.
    static func removed(taskKeys: [String]) {
        for key in taskKeys {
            alarms.acknowledge(taskKey: key)
        }
        FollowUpService.cancel(taskKeys: taskKeys)
    }

    /// Sets a record's alarm, if it has a time still ahead.
    static func scheduleAlarm(for record: TaskRecord) {
        guard let task = record.task, let time = record.scheduledFor, time > .now else { return }
        let key = record.alarmKey
        let unlock = record.unlockSeconds
        Task {
            await alarms.scheduleTaskAlarm(for: task, key: key, at: time, unlockSeconds: unlock)
        }
    }
}
