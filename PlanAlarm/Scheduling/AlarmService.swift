import ActivityKit
@preconcurrency import AlarmKit
import Foundation
import Observation
import SwiftUI

/// Metadata attached to every PlanAlarm alarm.
struct PlanAlarmData: AlarmMetadata {
    enum Kind: String, Codable, Sendable {
        case wake
        case task
        case checkIn
        case reinstall
    }

    var kind: Kind
    var taskKey: String?
}

/// One task alarm to schedule.
struct TaskAlarmRequest: Sendable {
    var task: PlanTask
    var key: String
    var date: Date
    /// The task's own read time, if the plan sets one.
    var unlockSeconds: Int?
}

/// The only place that talks to AlarmKit.
///
/// What iOS allows (Apple's AlarmKit FAQ and docs): every physical button, slide-to-stop and the Stop
/// button *stop* an alarm; apps can't turn them into snooze, and the stop intent doesn't always run.
/// So each task gets a chain of alarms scheduled in advance, one per snooze interval. However a ring
/// is stopped, the next one follows after the snooze length. When our stop intent does run, the chain
/// is re-timed so the next ring is exactly one snooze length later. Only "Stop Alarm" in the app
/// (after the unlock countdown) cancels the chain. No countdown presentation is used, so no widget
/// extension is needed.
@MainActor
@Observable
final class AlarmService {
    static let shared = AlarmService()

    private(set) var authorization: AlarmManager.AuthorizationState
    private(set) var registry: AlarmRegistry
    /// The last scheduling problem, shown in Settings.
    var lastError: String?

    /// The alarms iOS reported at the last check, or nil if it couldn't be read.
    private(set) var liveAlarmIDs: Set<UUID>?

    private var needsWakeUpdate = false
    private var needsWakeRebuild = false
    private var isUpdatingWake = false
    private var needsNotificationUpdate = false
    private var isUpdatingNotifications = false
    /// Alarms being scheduled right now; the orphan clean-up must not touch them.
    private var inFlightIDs: Set<UUID> = []

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

    /// Task alarms whose time has passed and which haven't been stopped in the app yet.
    var tasksPendingAcknowledgement: [PendingTaskAlarm] {
        registry.tasks.filter { $0.isPendingAcknowledgement() }.sorted { $0.firstAlarmAt < $1.firstAlarmAt }
    }

    private var settings: AppSettings { AppSettings.current() }

    private var snoozeInterval: TimeInterval {
        TimeInterval(max(1, settings.snoozeMinutes) * 60)
    }

    // MARK: - Authorization and upkeep

    func requestAuthorization() async {
        do {
            authorization = try await manager.requestAuthorization()
        } catch {
            lastError = "Couldn't ask for alarm permission: \(error.localizedDescription)"
        }
        if authorization == .authorized {
            rebuildWakeAlarms()
        }
    }

    /// Call when the app becomes active (after `TaskActions.reconcile()`): refreshes permission, removes
    /// alarms the app no longer knows, restarts the chain of any waiting task that ran out of rings, tops up
    /// the wake-up rings, and updates the reinstall reminder and the backup notifications.
    func refresh() async {
        authorization = manager.authorizationState
        guard authorization == .authorized else { return }
        if let live = try? manager.alarms {
            let liveIDs = Set(live.map(\.id))
            liveAlarmIDs = liveIDs

            let known = registry.knownAlarmIDs.union(inFlightIDs)
            for id in liveIDs where !known.contains(id) {
                try? manager.cancel(id: id)
            }

            for entry in registry.tasks where entry.isPendingAcknowledgement() {
                let hasLiveFutureRing = entry.rings.contains { $0.date > .now && liveIDs.contains($0.id) }
                if !hasLiveFutureRing {
                    await rechain(key: entry.key, startingAt: .now.addingTimeInterval(snoozeInterval))
                }
            }
        } else {
            liveAlarmIDs = nil
            lastError = "iOS didn't say which alarms are set. Reopen the app; if this stays, restart the iPhone."
        }
        if settings.wakeEnabled, await FollowUpService.permission() == .notAsked {
            await FollowUpService.ensurePermission()
        }
        updateWakeAlarms()
        await updateExpiryReminder()
    }

    // MARK: - Reinstall reminder

    /// Keeps one "Reinstall PlanAlarm" alarm at 20:00 the evening before this install expires.
    /// Re-evaluated on every activation, since each reinstall moves the expiry date.
    func updateExpiryReminder() async {
        guard authorization == .authorized, let expiry = AppExpiry.current() else { return }
        let wanted = AppExpiry.reminderDate(for: expiry.date, now: .now)
        if let current = registry.expiryReminder, current.date == wanted {
            return
        }
        if let old = registry.expiryReminder {
            try? manager.cancel(id: old.id)
        }
        registry.expiryReminder = nil
        registry.save()
        guard let wanted else { return }

        let ring = ScheduledRing(id: UUID(), date: wanted)
        registry.expiryReminder = ring
        registry.save()
        let result = await scheduleAlarm(id: ring.id, configuration: expiryConfiguration(id: ring.id, at: wanted),
                                         what: "the reinstall reminder")
        if result != .scheduled {
            registry.expiryReminder = nil
            registry.save()
        }
    }

    private func expiryConfiguration(id: UUID, at date: Date) -> AlarmManager.AlarmConfiguration<PlanAlarmData> {
        let alert = makeAlert(
            title: "Reinstall PlanAlarm: it stops working tomorrow",
            stopLabel: "Stop",
            secondaryButton: AlarmButton(text: "Open", textColor: .white, systemImageName: "arrow.clockwise")
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: PlanAlarmData(kind: .reinstall),
            tintColor: .red
        )
        return .alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: OpenAppFromAlarmIntent(alarmID: id.uuidString),
            sound: sound(for: settings.wakeTone)
        )
    }

    // MARK: - Wake-up alarm

    /// Days whose wake-up walk is done.
    var awakeDays: Set<String> { Set(registry.awakeDates) }

    /// True while the wake-up rings are being set.
    var isUpdatingWakeAlarms: Bool { isUpdatingWake }

    /// The day whose wake-up walk is due right now, if any.
    func pendingWakeUp(now: Date = .now) -> LocalDate? {
        settings.wakeSchedule.pendingWakeUp(now: now, awake: awakeDays)
    }

    /// The next wake-up still to ring, and whether its first ring is really set in iOS
    /// (nil when iOS couldn't be asked).
    func nextWakeUp(now: Date = .now) -> (date: Date, isSet: Bool?)? {
        guard let next = settings.wakeSchedule.nextWakeUp(after: now, awake: awakeDays) else { return nil }
        let ring = registry.wakeChains[next.day.description]?.first { Self.sameTime($0.date, next.date) }
        guard let liveAlarmIDs else { return (next.date, nil) }
        return (next.date, ring.map { liveAlarmIDs.contains($0.id) } ?? false)
    }

    /// The wake-up walk is done: that day's rings and their notifications stop.
    func confirmAwake(on day: LocalDate) {
        let key = day.description
        registry.markAwake(key)
        for ring in registry.wakeChains[key] ?? [] {
            try? manager.cancel(id: ring.id)
        }
        registry.wakeChains[key] = nil
        registry.save()
        updateWakeAlarms()
        Task { await BackupNotifications.clearDelivered(thread: BackupNotifications.wakeThread) }
    }

    /// Replaces every wake-up ring (after the wake-up times, tone or step count change).
    func rebuildWakeAlarms() {
        needsWakeRebuild = true
        updateWakeAlarms()
    }

    /// Keeps the wake-up rings in step with the settings and the days already confirmed: the next wake-up
    /// gets its whole chain of rings (see `WakeSchedule.ringOffsetMinutes`), later ones fewer, topped up
    /// on every refresh. Rings iOS lost are scheduled again. Calls made while an update runs are merged.
    func updateWakeAlarms() {
        needsWakeUpdate = true
        guard !isUpdatingWake else { return }
        isUpdatingWake = true
        Task {
            while needsWakeUpdate {
                needsWakeUpdate = false
                let rebuild = needsWakeRebuild
                needsWakeRebuild = false
                await syncWakeRings(rebuild: rebuild)
            }
            isUpdatingWake = false
            updateBackupNotifications()
        }
    }

    private func syncWakeRings(rebuild: Bool) async {
        guard authorization != .denied else { return }
        cancelOldWakeAlarms()
        let now = Date.now
        let wanted = settings.wakeSchedule.plannedRings(now: now, awake: awakeDays)
        let live = (try? manager.alarms).map { Set($0.map(\.id)) }

        for (key, rings) in registry.wakeChains where rebuild || wanted[key] == nil {
            rings.forEach { try? manager.cancel(id: $0.id) }
            registry.wakeChains[key] = nil
        }
        registry.save()

        for key in wanted.keys.sorted() {
            let dates = wanted[key] ?? []
            // Keep rings still wanted and still set in iOS; replace the rest.
            var kept: [ScheduledRing] = []
            for ring in registry.wakeChains[key] ?? [] {
                let isWanted = ring.date > now && dates.contains { Self.sameTime($0, ring.date) }
                if isWanted && (live?.contains(ring.id) ?? true) {
                    kept.append(ring)
                } else {
                    try? manager.cancel(id: ring.id)
                }
            }
            let missing = dates.filter { date in !kept.contains { Self.sameTime($0.date, date) } }
                .map { ScheduledRing(id: UUID(), date: $0) }
            registry.wakeChains[key] = (kept + missing).sorted { $0.date < $1.date }
            registry.save()

            var failed: Set<UUID> = []
            for (index, ring) in missing.enumerated() {
                let result = await scheduleAlarm(id: ring.id, configuration: wakeConfiguration(id: ring.id, at: ring.date),
                                                 what: "the wake-up alarm")
                if result == .scheduled {
                    // The walk was done (or the settings changed) while this was being scheduled.
                    if !(registry.wakeChains[key]?.contains(ring) ?? false) {
                        try? manager.cancel(id: ring.id)
                    }
                } else {
                    failed.insert(ring.id)
                    if result == .limitReached {
                        failed.formUnion(missing[index...].map(\.id))
                        break
                    }
                }
            }
            if let current = registry.wakeChains[key] {
                registry.wakeChains[key] = current.filter { !failed.contains($0.id) }
                registry.save()
            }
        }
        liveAlarmIDs = (try? manager.alarms).map { Set($0.map(\.id)) }
    }

    /// v1.0 used one repeating alarm per wake-up time and separate check-in reminder rings; both are
    /// replaced by the wake-up chains.
    private func cancelOldWakeAlarms() {
        guard !registry.wakeAlarmIDs.isEmpty || !registry.checkInChains.isEmpty else { return }
        registry.wakeAlarmIDs.forEach { try? manager.cancel(id: $0) }
        registry.checkInChains.values.joined().forEach { try? manager.cancel(id: $0.id) }
        registry.wakeAlarmIDs = []
        registry.checkInChains = [:]
        registry.save()
    }

    /// Ring times are recomputed on every update; saved ones are compared with a little tolerance.
    private static func sameTime(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 1
    }

    private func wakeConfiguration(id: UUID, at date: Date) -> AlarmManager.AlarmConfiguration<PlanAlarmData> {
        let alert = makeAlert(
            title: LocalizedStringResource(stringLiteral: "Good morning! Walk \(settings.wakeSteps) steps in PlanAlarm to stop this"),
            stopLabel: "Stop",
            secondaryButton: AlarmButton(text: "Open", textColor: .white, systemImageName: "figure.walk")
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: PlanAlarmData(kind: .wake),
            tintColor: .orange
        )
        return .alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: OpenAppFromAlarmIntent(alarmID: id.uuidString),
            sound: sound(for: settings.wakeTone)
        )
    }

    // MARK: - Backup notifications

    /// Plain notifications with the alarm rings: every wake-up ring, and each waiting task's next 3 rings
    /// (iOS keeps only the 64 soonest notifications). Calls made while an update runs are merged.
    func updateBackupNotifications() {
        needsNotificationUpdate = true
        guard !isUpdatingNotifications else { return }
        isUpdatingNotifications = true
        Task {
            while needsNotificationUpdate {
                needsNotificationUpdate = false
                await BackupNotifications.sync(backupNotificationItems())
            }
            isUpdatingNotifications = false
        }
    }

    private func backupNotificationItems() -> [BackupNotifications.Item] {
        let now = Date.now
        let steps = settings.wakeSteps
        var items: [BackupNotifications.Item] = []
        for ring in registry.wakeChains.values.joined() where ring.date > now {
            items.append(BackupNotifications.Item(
                id: ring.id.uuidString, date: ring.date, title: "Wake up!",
                body: "Walk \(steps) steps in PlanAlarm to stop the wake-up alarm.", thread: BackupNotifications.wakeThread
            ))
        }
        for entry in registry.tasks {
            for ring in entry.rings.filter({ $0.date > now }).prefix(3) {
                items.append(BackupNotifications.Item(
                    id: ring.id.uuidString, date: ring.date, title: entry.task.title,
                    body: "Open PlanAlarm to read the task.", thread: entry.key
                ))
            }
        }
        return items
    }

    // MARK: - Task alarms

    /// Schedules a task's alarm chain. It keeps ringing every snooze interval until `acknowledge(taskKey:)`.
    /// `unlockSeconds` is the task's own read time, if the plan sets one.
    func scheduleTaskAlarm(for task: PlanTask, key: String, at date: Date, unlockSeconds: Int? = nil) async {
        await scheduleTaskAlarms([TaskAlarmRequest(task: task, key: key, date: date, unlockSeconds: unlockSeconds)])
    }

    /// Schedules several tasks' chains (e.g. at lock-in), replacing any existing chain for the same key.
    func scheduleTaskAlarms(_ requests: [TaskAlarmRequest]) async {
        guard !requests.isEmpty else { return }
        for request in requests {
            if let existing = registry.task(forKey: request.key) {
                cancelRings(of: existing)
            }
            let first = earliestRingDate(request.date)
            registry.upsert(PendingTaskAlarm(key: request.key, task: request.task, firstAlarmAt: first,
                                             rings: plannedRings(startingAt: first), unlockSeconds: request.unlockSeconds))
        }
        registry.save()
        await scheduleRings(forKeys: requests.map(\.key))
    }

    /// The stop intent ran (Stop, slide or a physical button): re-time the chain so the next ring is
    /// exactly one snooze length from now.
    func snooze(taskKey: String) async {
        guard registry.task(forKey: taskKey) != nil else { return }
        await rechain(key: taskKey, startingAt: .now.addingTimeInterval(snoozeInterval))
    }

    /// The "Open task" button: silence the ring, show the task, and keep the chain going until it's stopped.
    func openTask(taskKey: String, alarmID: String) async {
        if let id = UUID(uuidString: alarmID) {
            try? manager.stop(id: id)
        }
        guard registry.task(forKey: taskKey) != nil else { return }
        await rechain(key: taskKey, startingAt: .now.addingTimeInterval(snoozeInterval))
        AppRouter.shared.presentedTaskKey = taskKey
    }

    /// "Stop Alarm" in the app: cancel the task's whole chain.
    func acknowledge(taskKey: String) {
        guard let entry = registry.task(forKey: taskKey) else { return }
        cancelRings(of: entry)
        registry.removeTask(forKey: taskKey)
        registry.save()
        updateBackupNotifications()
        Task { await BackupNotifications.clearDelivered(thread: taskKey) }
    }

    /// Removes every task alarm (debug tool).
    func cancelAllTaskAlarms() {
        for entry in registry.tasks {
            cancelRings(of: entry)
        }
        registry.tasks = []
        registry.save()
        updateBackupNotifications()
    }

    /// Seconds before Stop Alarm unlocks for this task.
    func unlockSeconds(for entry: PendingTaskAlarm) -> Int {
        entry.unlockSeconds ?? settings.stopUnlockSeconds
    }

    /// How many times this task has rung again after its first alarm.
    func snoozeCount(for entry: PendingTaskAlarm) -> Int {
        max(0, entry.snoozeCount + entry.rings.filter { $0.date <= .now }.count - 1)
    }

    /// Replaces a task's future rings with a fresh chain starting at `first`.
    private func rechain(key: String, startingAt first: Date) async {
        guard var entry = registry.task(forKey: key) else { return }
        // Rings already heard count as snoozes; the rest are replaced.
        entry.snoozeCount += entry.rings.filter { $0.date <= .now }.count
        cancelRings(of: entry)
        entry.rings = plannedRings(startingAt: earliestRingDate(first))
        registry.upsert(entry)
        registry.save()
        await scheduleRings(forKeys: [key])
    }

    /// AlarmKit needs a future date; a time that has only just passed rings in a few seconds.
    private func earliestRingDate(_ date: Date) -> Date {
        max(date, Date.now.addingTimeInterval(5))
    }

    /// A full chain of rings, one per snooze interval.
    private func plannedRings(startingAt first: Date) -> [ScheduledRing] {
        AlarmRegistry.chainDates(startingAt: first, interval: snoozeInterval,
                                 count: AlarmRegistry.chainLength(snoozeInterval: snoozeInterval))
            .map { ScheduledRing(id: UUID(), date: $0) }
    }

    /// Schedules the planned rings of these tasks, **ring by ring across tasks**: every task's first ring,
    /// then every task's second ring, and so on. If iOS runs out of alarm slots, tasks lose backup rings
    /// rather than being left with no alarm at all. Rings that couldn't be scheduled are dropped.
    private func scheduleRings(forKeys keys: [String]) async {
        var planned: [String: [ScheduledRing]] = [:]
        for key in keys {
            planned[key] = registry.task(forKey: key)?.rings
        }
        var scheduled: [String: [ScheduledRing]] = [:]
        var failedKeys: Set<String> = []
        let depth = planned.values.map(\.count).max() ?? 0

        rings: for index in 0..<depth {
            for key in keys where !failedKeys.contains(key) {
                guard let rings = planned[key], index < rings.count,
                      let entry = registry.task(forKey: key), entry.rings == rings else { continue } // stopped meanwhile
                let ring = rings[index]
                let configuration = taskConfiguration(title: entry.task.title, key: key, alarmID: ring.id, at: ring.date)
                let result = await scheduleAlarm(id: ring.id, configuration: configuration, what: "“\(entry.task.title)”")
                switch result {
                case .scheduled: scheduled[key, default: []].append(ring)
                case .limitReached: break rings
                case .failed: failedKeys.insert(key)
                }
            }
        }

        for key in keys {
            guard let rings = planned[key] else { continue }
            let done = scheduled[key] ?? []
            if var current = registry.task(forKey: key), current.rings == rings {
                current.rings = done
                registry.upsert(current)
            } else {
                // Stopped or re-planned while scheduling: cancel what this pass added.
                let kept = registry.task(forKey: key)?.rings ?? []
                for ring in done where !kept.contains(ring) {
                    try? manager.cancel(id: ring.id)
                }
            }
        }
        registry.save()
        updateBackupNotifications()
    }

    private func cancelRings(of entry: PendingTaskAlarm) {
        for id in entry.alarmIDs {
            try? manager.cancel(id: id)
        }
    }

    private func taskConfiguration(title: String, key: String, alarmID: UUID, at date: Date) -> AlarmManager.AlarmConfiguration<PlanAlarmData> {
        let alert = makeAlert(
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
            secondaryIntent: OpenTaskIntent(taskKey: key, alarmID: alarmID.uuidString),
            sound: sound(for: settings.taskTone)
        )
    }

    // MARK: - Shared helpers

    private enum ScheduleResult {
        case scheduled
        /// iOS's alarm limit: stop scheduling more.
        case limitReached
        case failed
    }

    /// Schedules one alarm; records the problem if AlarmKit refuses.
    private func scheduleAlarm(id: UUID, configuration: AlarmManager.AlarmConfiguration<PlanAlarmData>,
                               what: String) async -> ScheduleResult {
        inFlightIDs.insert(id)
        defer { inFlightIDs.remove(id) }
        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
            authorization = manager.authorizationState
            return .scheduled
        } catch AlarmManager.AlarmError.maximumLimitReached {
            lastError = "iOS won't allow more alarms right now, so \(what) has fewer backup rings."
            return .limitReached
        } catch {
            lastError = "Couldn't set \(what): \(error.localizedDescription)"
            return .failed
        }
    }

    /// An alert with a custom secondary button. iOS 26.1+ always draws its own Stop button;
    /// on iOS 26.0 the stop button still shows `stopLabel`.
    private func makeAlert(title: LocalizedStringResource, stopLabel: LocalizedStringResource,
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

    private func sound(for tone: AlarmTone) -> AlertConfiguration.AlertSound {
        tone.fileName.map { .named($0) } ?? .default
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
        await scheduleTaskAlarm(for: task, key: "test-\(UUID().uuidString)", at: .now.addingTimeInterval(60))
    }

    /// A one-off wake-up style alarm one minute from now.
    func scheduleTestWakeAlarm() async {
        let id = UUID()
        registry.testAlarmIDs = Array((registry.testAlarmIDs + [id]).suffix(5))
        registry.save()
        _ = await scheduleAlarm(id: id, configuration: wakeConfiguration(id: id, at: .now.addingTimeInterval(60)),
                                what: "the test wake-up alarm")
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

    static func handleOpen(taskKey: String, alarmID: String) async {
        await shared.openTask(taskKey: taskKey, alarmID: alarmID)
    }

    static func handleOpenApp(alarmID: String) {
        guard let id = UUID(uuidString: alarmID) else { return }
        try? AlarmManager.shared.stop(id: id)
    }
}
