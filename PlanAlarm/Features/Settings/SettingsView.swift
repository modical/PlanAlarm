import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Query(filter: #Predicate<StoredPlan> { $0.isActive == true }) private var activePlans: [StoredPlan]
    @Query private var settingsRecords: [AppSettings]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                AppInstallSection()

                if let settings = settingsRecords.first {
                    AlarmSettingsSection(settings: settings)
                    FollowUpSettingsSection(settings: settings)
                }

                Section("Plan") {
                    if let stored = activePlans.first {
                        LabeledContent("Current plan", value: stored.name)
                        if let plan = PlanStore.plan(for: stored) {
                            LabeledContent("Dates", value: plan.dateRangeText)
                        }
                        LabeledContent("Imported", value: stored.importedAt.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        Text("No plan loaded").foregroundStyle(.secondary)
                    }
                    ImportPlanButtons()
                }

                AboutSection()
            }
            .navigationTitle("Settings")
            .task {
                _ = AppSettings.current(in: modelContext)
            }
        }
    }
}

private struct AlarmSettingsSection: View {
    @Bindable var settings: AppSettings
    @State private var alarms = AlarmService.shared

    private var wakeSummary: String {
        guard settings.wakeEnabled else { return "Off" }
        let schedule = settings.wakeSchedule
        let customDays = Weekday.allCases.filter { schedule.rule(for: $0).customTime != nil || !schedule.rule(for: $0).isEnabled }
        return customDays.isEmpty ? schedule.defaultTime.description : "\(schedule.defaultTime.description) · varies"
    }

    var body: some View {
        Section {
            AlarmPermissionBanner()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            NavigationLink {
                WakeSettingsView(settings: settings)
            } label: {
                LabeledContent("Wake-up alarm", value: wakeSummary)
            }
            if let next = settings.wakeSchedule.nextAlarm(after: .now) {
                LabeledContent("Next wake-up", value: next.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
            }
            Toggle("Check-in reminder", isOn: $settings.checkInReminderEnabled)
            if settings.checkInReminderEnabled {
                Stepper("Every \(settings.checkInReminderMinutes) min after wake-up",
                        value: $settings.checkInReminderMinutes, in: 15...120, step: 15)
            }
            Stepper("Snooze: \(settings.snoozeMinutes) min", value: $settings.snoozeMinutes, in: 1...30)
            Stepper("Stop Alarm unlocks after \(settings.stopUnlockSeconds) s",
                    value: $settings.stopUnlockSeconds, in: 5...300, step: 5)
            NavigationLink {
                TonePickerView(title: "Task Alarm Tone", selection: $settings.taskTone)
            } label: {
                LabeledContent("Task alarm tone", value: settings.taskTone.displayName)
            }
            NavigationLink {
                TonePickerView(title: "Wake-up Tone", selection: $settings.wakeTone)
            } label: {
                LabeledContent("Wake-up tone", value: settings.wakeTone.displayName)
            }
            if let error = alarms.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
        } header: {
            Text("Alarms")
        } footer: {
            Text("If you haven't locked in your day by then, the check-in reminder rings (up to 4 times). A task alarm rings again every \(settings.snoozeMinutes) min, however it's stopped (Stop, slide, or the side and volume buttons), until you tap Stop Alarm in the app.")
        }
        .onChange(of: settings.wakeSchedule) {
            alarms.applyWakeSchedule(settings.wakeSchedule)
        }
        .onChange(of: settings.checkInReminderEnabled) {
            alarms.updateCheckInReminders()
        }
        .onChange(of: settings.checkInReminderMinutes) {
            alarms.updateCheckInReminders()
        }
        .onChange(of: settings.wakeToneID) {
            alarms.applyWakeSchedule(settings.wakeSchedule)
        }
    }
}

/// When this install expires (free Apple ID installs last 7 days), and the welcome screens.
private struct AppInstallSection: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var expiry = AppExpiry.current()

    var body: some View {
        Section {
            if let expiry {
                LabeledContent("App expires") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(expiry.date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(expiry.isWarningDue() ? .red : .primary)
                        Text(expiry.date.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if expiry.source == .estimatedFromInstall {
                    Text("Estimated from the install date (7 days); the signing profile couldn't be read.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("App expires", value: "Unknown")
            }
            Button("Show Welcome Screens Again", systemImage: "hand.wave") {
                hasCompletedOnboarding = false
            }
        } header: {
            Text("App")
        } footer: {
            Text("Apps installed with a free Apple ID stop opening after 7 days, and their alarms stop too. A “Reinstall PlanAlarm” alarm rings at 20:00 the evening before. Reinstall with Sideloadly (see the README); your plan and history are kept.")
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { expiry = AppExpiry.current() }
        }
    }
}

private struct FollowUpSettingsSection: View {
    @Bindable var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var permission: FollowUpService.Permission?

    var body: some View {
        Section {
            Toggle("“Did you finish?” reminder", isOn: $settings.followUpEnabled)
            if settings.followUpEnabled && permission == .denied {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Notifications are off for PlanAlarm, so this reminder can't appear.",
                          systemImage: "bell.slash")
                        .font(.subheadline)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Follow-up")
        } footer: {
            Text("After you tap Starting Now, a notification asks whether you finished, once the task's duration has passed (or after 60 minutes). Answer Done or Skipped right from the notification.")
        }
        .task(id: scenePhase) {
            permission = await FollowUpService.permission()
        }
        .onChange(of: settings.followUpEnabled) {
            guard settings.followUpEnabled else { return }
            Task {
                await FollowUpService.ensurePermission()
                permission = await FollowUpService.permission()
            }
        }
    }
}

private struct AboutSection: View {
    @AppStorage("showDebugTools") private var showDebugTools = false
    @State private var buildTaps = 0

    var body: some View {
        Section {
            ShareLink(item: HistoryExportFile(), preview: SharePreview("PlanAlarm history")) {
                Label("Export History (JSON)", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("History")
        } footer: {
            Text("A backup of every checked-in day and task, with statuses and times.")
        }
        Section("About") {
            LabeledContent("Version", value: AppInfo.version)
            LabeledContent("Build", value: AppInfo.build)
                .contentShape(Rectangle())
                .onTapGesture {
                    buildTaps += 1
                    if buildTaps >= 7 {
                        showDebugTools.toggle()
                        buildTaps = 0
                    }
                }
        }
        if showDebugTools {
            DebugSection()
        }
    }
}

/// Hidden tools for testing alarms on the phone (tap "Build" 7 times to show or hide).
private struct DebugSection: View {
    @Query(filter: #Predicate<StoredPlan> { $0.isActive == true }) private var activePlans: [StoredPlan]
    @State private var alarms = AlarmService.shared
    @State private var message: String?

    var body: some View {
        Section {
            Button("Fire Test Task Alarm in 1 Minute", systemImage: "alarm") {
                Task {
                    let plan = activePlans.first.flatMap { PlanStore.plan(for: $0) }
                    await alarms.scheduleTestTaskAlarm(using: plan)
                    message = alarms.lastError ?? "Test task alarm set for \(Date.now.addingTimeInterval(60).formatted(date: .omitted, time: .shortened)). Lock the phone and wait."
                }
            }
            Button("Fire Test Wake-up Alarm in 1 Minute", systemImage: "sun.max") {
                Task {
                    await alarms.scheduleTestWakeAlarm()
                    message = alarms.lastError ?? "Test wake-up alarm set for \(Date.now.addingTimeInterval(60).formatted(date: .omitted, time: .shortened))."
                }
            }
            Button("Cancel All Task Alarms", systemImage: "xmark.circle", role: .destructive) {
                alarms.cancelAllTaskAlarms()
                message = "All task alarms cancelled."
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            LabeledContent("Permission", value: alarms.permission.rawValue)
            LabeledContent("Wake-up alarms", value: "\(alarms.registry.wakeAlarmIDs.count)")
            ForEach(alarms.registry.tasks) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.task.title)
                    Text("Next ring: \(entry.nextRing()?.date.formatted(date: .omitted, time: .standard) ?? "none") · \(entry.rings.count) rings scheduled · rang again \(alarms.snoozeCount(for: entry))×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink("AlarmKit alarms (\(alarms.scheduledAlarms.count))") {
                List(alarms.scheduledAlarms) { alarm in
                    VStack(alignment: .leading) {
                        Text(alarm.state)
                        Text(alarm.id.uuidString).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("AlarmKit Alarms")
            }
        } header: {
            Text("Debug")
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}

#Preview {
    SettingsView()
        .environment(ImportController())
        .modelContainer(for: [StoredPlan.self, AppSettings.self, ExtraTask.self, DayRecord.self, TaskRecord.self], inMemory: true)
}
