import SwiftUI
import UniformTypeIdentifiers

enum AppTab: String, CaseIterable, Hashable {
    case today, plan, history, settings
}

struct RootView: View {
    @State private var selection: AppTab = .today
    @State private var importer = ImportController()
    @State private var alarms = AlarmService.shared
    @State private var router = AppRouter.shared
    /// The calendar day shown on the Today tab; updated whenever the app becomes active.
    @State private var today = LocalDate.today()
    @Environment(\.scenePhase) private var scenePhase

    /// The task shown full screen until it's acknowledged.
    private var presentedTask: Binding<PendingTaskAlarm?> {
        Binding(
            get: { router.presentedTaskKey.flatMap { alarms.registry.task(forKey: $0) } },
            set: { if $0 == nil { router.presentedTaskKey = nil } }
        )
    }

    var body: some View {
        @Bindable var importer = importer

        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                TodayView(date: today)
                    .id(today)
            }
            Tab("Plan", systemImage: "list.bullet.rectangle", value: AppTab.plan) {
                PlanView()
            }
            Tab("History", systemImage: "calendar", value: AppTab.history) {
                HistoryView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        // "Open in PlanAlarm" from Files, AirDrop, WhatsApp, Mail…
        .onOpenURL { url in
            importer.importFile(at: url)
        }
        .fileImporter(
            isPresented: $importer.isShowingFileImporter,
            allowedContentTypes: [.dayplan, .json, .plainText]
        ) { result in
            switch result {
            case .success(let url): importer.importFile(at: url)
            case .failure(let error): importer.readError = error.localizedDescription
            }
        }
        .sheet(item: $importer.sheet) { sheet in
            switch sheet {
            case .paste: PastePlanView()
            case .newPlan: NewPlanView()
            case .preview(let pending): PlanImportPreviewView(pending: pending)
            }
        }
        .alert("Couldn't open the plan", isPresented: .init(
            get: { importer.readError != nil },
            set: { if !$0 { importer.readError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(importer.readError ?? "")
        }
        .onChange(of: importer.importCount) {
            selection = .plan
        }
        // A task alarm that hasn't been acknowledged takes over the screen, whatever route opened the app.
        .fullScreenCover(item: presentedTask) { pending in
            TaskAlarmView(
                pending: pending,
                unlockSeconds: alarms.unlockSeconds(for: pending),
                snoozeCount: alarms.snoozeCount(for: pending)
            ) {
                DayStore.markAcknowledged(alarmKey: pending.key, snoozeCount: alarms.snoozeCount(for: pending))
                alarms.acknowledge(taskKey: pending.key)
                router.presentedTaskKey = nil
                router.showPendingTaskIfNeeded()
            }
        }
        .onChange(of: scenePhase, initial: true) {
            guard scenePhase == .active else { return }
            today = .today()
            // Until the day is locked in, opening the app goes to the morning check-in.
            if !DayStore.isLockedIn(today) && importer.sheet == nil {
                selection = .today
            }
            Task {
                await alarms.refresh()
                syncTaskStatuses()
                router.showPendingTaskIfNeeded()
            }
        }
        .task {
            // Catch alarms that go off while the app is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                syncTaskStatuses()
                router.showPendingTaskIfNeeded()
            }
        }
        .environment(importer)
    }

    /// Marks tasks whose alarm has started ringing.
    private func syncTaskStatuses() {
        DayStore.markRinging(alarms.tasksPendingAcknowledgement.map { (key: $0.key, firstAlarmAt: $0.firstAlarmAt) })
    }
}

#Preview {
    RootView()
        .modelContainer(for: [StoredPlan.self, AppSettings.self, ExtraTask.self, DayRecord.self, TaskRecord.self], inMemory: true)
}
