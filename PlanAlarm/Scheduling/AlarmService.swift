@preconcurrency import AlarmKit
import Foundation
import Observation
import SwiftUI

/// Metadata attached to every PlanAlarm alarm.
struct PlanAlarmData: AlarmMetadata {
    enum Kind: String, Codable, Sendable {
        case wake
        case task
    }

    var kind: Kind
    var taskKey: String?
}

/// The only place that talks to AlarmKit.
///
/// Task alarms: iOS always shows its own Stop button (custom stop labels are ignored since iOS 26.1).
/// Stop runs `SnoozeTaskIntent`, which schedules the same task again after the snooze length; "Open task"
/// runs `OpenTaskIntent`, which opens the app and also re-arms. Only acknowledging the task in the app
/// ends the cycle. No countdown presentation is used, so no widget extension is needed.
@MainActor
@Observable
final class AlarmService {
    static let shared = AlarmService()

    private(set) var authorization: AlarmManager.AuthorizationState
    private(set) var registry: AlarmRegistry
    /// The last scheduling problem, shown in Settings.
    var lastError: String?

    private var pendingWakeSchedule: WakeSchedule?
    private var isApplyingWakeSchedule = false

    private var manager: AlarmManager { AlarmManager.shared }

    private init() {
        authorization = AlarmManager.shared.authorizationState
        registry = AlarmRegistry.load()
    }

    enum Permission: String {
        case allowed, denied, notAsked
    }

    /// AlarmKit authorization in the app's own terms (keeps AlarmKit types out of the UI).
    var permission: Permission {
        switch authorization {
        case .authorized: .allowed
        case .denied: .denied
        default: .notAsked
        }
    }

    /// Task alarms whose time has passed and which haven't been acknowledged yet.
    var tasksPendingAcknowledgement: [PendingTaskAlarm] {
        registry.tasks.filter { $0.isPendingAcknowledgement() }.sorted { $0.firstAlarmAt < $1.firstAlarmAt }
    }

    private var snoozeInterval: TimeInterval {
        TimeInterval(max(1, AppSettings.current().snoozeMinutes) * 60)
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            authorization = try await manager.requestAuthorization()
        } catch {
            lastError = "Couldn't ask for alarm permission: \(error.localizedDescription)"
        }
        if authorization == .authorized {
            applyWakeSchedule(AppSettings.current().wakeSchedule)
        }
    }

    /// Call when the app becomes active: refreshes permission, restores missing wake alarms,
    /// and re-arms any unacknowledged task whose alarm is gone.
    func refresh() async {
        authorization = manager.authorizationState
        guard authorization == .authorized else { return }
        let liveIDs = Set(((try? manager.alarms) ?? []).map(\.id))

        if !registry.wakeAlarmIDs.allSatisfy(liveIDs.contains) || registry.wakeAlarmIDs.isEmpty {
            applyWakeSchedule(AppSettings.current().wakeSchedule)
        }
        for entry in registry.tasks where entry.nextAlarmAt <= .now && !liveIDs.contains(entry.alarmID) {
            var rearmed = entry
            await rearm(&rearmed, after: snoozeInterval)
        }
    }

    // MARK: - Wake-up alarm

    /// Replaces the wake-up alarms with ones matching `schedule`. Calls made while an update is
    /// running are merged, so rapid settings changes never leave duplicate alarms.
    func applyWakeSchedule(_ schedule: WakeSchedule) {
        pendingWakeSchedule = schedule
        guard !isApplyingWakeSchedule else { return }
        isApplyingWakeSchedule = true
        Task {
            while let next = pendingWakeSchedule {
                pendingWakeSchedule = nil
                await replaceWakeAlarms(with: next)
            }
            isApplyingWakeSchedule = false
        }
    }

    private func replaceWakeAlarms(with schedule: WakeSchedule) async {
        guard authorization != .denied else { return }
        for id in registry.wakeAlarmIDs {
            try? manager.cancel(id: id)
        }
        registry.wakeAlarmIDs = []
        registry.save()

        for group in schedule.alarmGroups {
            let id = UUID()
            let relative = Alarm.Schedule.Relative(
                time: .init(hour: group.time.hour, minute: group.time.minute),
                repeats: .weekly(group.weekdays.map(\.localeWeekday))
            )
            do {
                _ = try await manager.schedule(id: id, configuration: wakeConfiguration(id: id, schedule: .relative(relative)))
                registry.wakeAlarmIDs.append(id)
                registry.save()
            } catch {
                lastError = "Couldn't set the wake-up alarm: \(error.localizedDescription)"
            }
        }
        authorization = manager.authorizationState
    }

    /// An alert with a custom secondary button. iOS 26.1+ always draws its own Stop button;
    /// on iOS 26.0 the stop button still shows `stopLabel`.
    private func alert(title: LocalizedStringResource, stopLabel: LocalizedStringResource,
                       secondaryButton: AlarmButton) -> AlarmPresentation.Alert {
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: title, secondaryButton: secondaryButton, secondaryButtonBehavior: .custom)
        }
        return AlarmPresentation.Alert(
            title: title,
            stopButton: AlarmButton(text: stopLabel, textColor: .white, systemImageName: "stop.circle"),
            secondaryButton: secondaryButton,
            secondaryButtonBehavior: .custom
        )
    }

    private func wakeConfiguration(id: UUID, schedule: Alarm.Schedule) -> AlarmManager.AlarmConfiguration<PlanAlarmData> {
        let alert = alert(
            title: "Good morning! Time to plan your day",
            stopLabel: "Stop",
            secondaryButton: AlarmButton(text: "Open", textColor: .white, systemImageName: "sun.max")
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: PlanAlarmData(kind: .wake),
            tintColor: .orange
        )
        return .alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: OpenAppFromAlarmIntent(alarmID: id.uuidString)
        )
    }

    // MARK: - Task alarms

    /// Schedules a task's alarm. It keeps coming back until `acknowledge(taskKey:)`.
    func scheduleTaskAlarm(for task: PlanTask, key: String, at date: Date) async throws {
        if let existing = registry.task(forKey: key) {
            try? manager.cancel(id: existing.alarmID)
        }
        let id = UUID()
        _ = try await manager.schedule(id: id, configuration: taskConfiguration(title: task.title, key: key, alarmID: id, at: date))
        registry.upsert(PendingTaskAlarm(key: key, task: task, firstAlarmAt: date, alarmID: id, nextAlarmAt: date))
        registry.save()
        authorization = manager.authorizationState
    }

    /// The Stop button: ring again after the snooze length.
    func snooze(taskKey: String) async {
        guard var entry = registry.task(forKey: taskKey) else { return }
        entry.snoozeCount += 1
        await rearm(&entry, after: snoozeInterval)
    }

    /// The "Open task" button: silence the alarm, show the task, and keep a re-arm as a safety net.
    func openTask(taskKey: String) async {
        guard var entry = registry.task(forKey: taskKey) else { return }
        try? manager.stop(id: entry.alarmID)
        await rearm(&entry, after: snoozeInterval)
        AppRouter.shared.presentedTaskKey = taskKey
    }

    /// The task was read in the app: cancel its alarm for good.
    func acknowledge(taskKey: String) {
        guard let entry = registry.task(forKey: taskKey) else { return }
        try? manager.cancel(id: entry.alarmID)
        registry.removeTask(forKey: taskKey)
        registry.save()
    }

    /// Removes every task alarm (debug tool).
    func cancelAllTaskAlarms() {
        for entry in registry.tasks {
            try? manager.cancel(id: entry.alarmID)
        }
        registry.tasks = []
        registry.save()
    }

    private func rearm(_ entry: inout PendingTaskAlarm, after interval: TimeInterval) async {
        try? manager.cancel(id: entry.alarmID)
        let id = UUID()
        let date = Date.now.addingTimeInterval(interval)
        do {
            _ = try await manager.schedule(id: id, configuration: taskConfiguration(title: entry.task.title, key: entry.key, alarmID: id, at: date))
            entry.alarmID = id
            entry.nextAlarmAt = date
        } catch {
            lastError = "Couldn't re-arm “\(entry.task.title)”: \(error.localizedDescription)"
        }
        registry.upsert(entry)
        registry.save()
    }

    private func taskConfiguration(title: String, key: String, alarmID: UUID, at date: Date) -> AlarmManager.AlarmConfiguration<PlanAlarmData> {
        let alert = alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopLabel: LocalizedStringResource(stringLiteral: "Snooze \(Int(snoozeInterval / 60)) min"),
            secondaryButton: AlarmButton(text: "Open task", textColor: .white, systemImageName: "doc.text")
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: PlanAlarmData(kind: .task, taskKey: key),
            tintColor: .orange
        )
        return .alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: SnoozeTaskIntent(taskKey: key),
            secondaryIntent: OpenTaskIntent(taskKey: key, alarmID: alarmID.uuidString)
        )
    }

    // MARK: - Debug tools

    /// A task alarm one minute from now, using today's first task (or a sample task).
    func scheduleTestTaskAlarm(using plan: Plan?) async {
        let task = plan?.day(on: .today()).tasks.first ?? PlanTask(
            taskRef: nil,
            title: "Test task — stretch for 2 minutes",
            category: "other",
            summary: "This is a test alarm from Settings → Debug.",
            sections: [TaskSection(title: "Steps", items: ["Stand up", "Reach for the ceiling", "Touch your toes"])],
            durationMinutes: 2,
            readSeconds: 10,
            suggestedTime: nil
        )
        do {
            try await scheduleTaskAlarm(for: task, key: "test-\(UUID().uuidString)", at: .now.addingTimeInterval(60))
        } catch {
            lastError = "Couldn't schedule the test alarm: \(error.localizedDescription)"
        }
    }

    /// A one-off wake-up style alarm one minute from now.
    func scheduleTestWakeAlarm() async {
        let id = UUID()
        do {
            _ = try await manager.schedule(id: id, configuration: wakeConfiguration(id: id, schedule: .fixed(.now.addingTimeInterval(60))))
        } catch {
            lastError = "Couldn't schedule the test wake-up alarm: \(error.localizedDescription)"
        }
        authorization = manager.authorizationState
    }

    struct ScheduledAlarmInfo: Identifiable {
        let id: UUID
        let state: String
    }

    /// Every alarm AlarmKit currently holds for this app (debug view).
    var scheduledAlarms: [ScheduledAlarmInfo] {
        ((try? manager.alarms) ?? []).map { ScheduledAlarmInfo(id: $0.id, state: String(describing: $0.state)) }
    }

    // MARK: - Entry points for App Intents

    static func handleStop(taskKey: String) async {
        await shared.snooze(taskKey: taskKey)
    }

    static func handleOpen(taskKey: String) async {
        await shared.openTask(taskKey: taskKey)
    }

    static func handleOpenApp(alarmID: String) {
        guard let id = UUID(uuidString: alarmID) else { return }
        try? AlarmManager.shared.stop(id: id)
    }
}
